-- | Migrations for the Hasura catalog.
--
-- To add a new migration:
--
--   1. Bump the catalog version number in @src-rsr/catalog_version.txt@.
--   2. Add a migration script in the @src-rsr/migrations/@ directory with the name
--      @<old version>_to_<new version>.sql@.
--   3. Create a downgrade script in the @src-rsr/migrations/@ directory with the name
--      @<new version>_to_<old version>.sql@.
--   4. If making a new release, add the mapping from application version to catalog
--      schema version in @src-rsr/catalog_versions.txt@.
--   5. If appropriate, add the change to @server/src-rsr/initialise.sql@ for fresh installations
--      of hasura.
--
-- The Template Haskell code in this module will automatically compile the new migration script into
-- the @graphql-engine@ executable.
module Hasura.Server.Migrate
  ( MigrationResult (..),
    getMigratedFrom,
    migrateCatalog,
    latestCatalogVersion,
    downgradeCatalog,
  )
where

import Control.Monad.Trans.Control (MonadBaseControl)
import Data.Aeson qualified as A
import Data.FileEmbed (makeRelativeToProject)
import Data.HashMap.Strict.InsOrd qualified as OMap
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (UTCTime)
import Database.PG.Query qualified as Q
import Hasura.Backends.Postgres.SQL.Types
import Hasura.Base.Error
import Hasura.Logging (Hasura, LogLevel (..), ToEngineLog (..))
import Hasura.Prelude
import Hasura.RQL.DDL.Schema
import Hasura.RQL.DDL.Schema.LegacyCatalog
import Hasura.RQL.Types
import Hasura.SQL.AnyBackend qualified as AB
import Hasura.Server.Init (DowngradeOptions (..), databaseUrlEnv)
import Hasura.Server.Logging (StartupLog (..))
import Hasura.Server.Migrate.Internal
import Hasura.Server.Migrate.Version
  ( latestCatalogVersion,
    latestCatalogVersionString,
  )
import Hasura.Server.Types (MaintenanceMode (..))
import Language.Haskell.TH.Lib qualified as TH
import Language.Haskell.TH.Syntax qualified as TH
import System.Directory (doesFileExist)

data MigrationResult
  = MRNothingToDo
  | MRInitialized
  | -- | old catalog version
    MRMigrated Text
  | MRMaintanenceMode
  deriving (Show, Eq)

instance ToEngineLog MigrationResult Hasura where
  toEngineLog result =
    toEngineLog $
      StartupLog
        { slLogLevel = LevelInfo,
          slKind = "catalog_migrate",
          slInfo = A.toJSON $ case result of
            MRNothingToDo ->
              "Already at the latest catalog version (" <> latestCatalogVersionString
                <> "); nothing to do."
            MRInitialized ->
              "Successfully initialized the catalog (at version " <> latestCatalogVersionString <> ")."
            MRMigrated oldVersion ->
              "Successfully migrated from catalog version " <> oldVersion <> " to version "
                <> latestCatalogVersionString
                <> "."
            MRMaintanenceMode ->
              "Catalog migrations are skipped because the graphql-engine is in maintenance mode"
        }

getMigratedFrom ::
  MigrationResult ->
  -- | We have version 0.8 as non integral catalog version
  Maybe Float
getMigratedFrom = \case
  MRNothingToDo -> Nothing
  MRInitialized -> Nothing
  MRMigrated t -> readMaybe (T.unpack t)
  MRMaintanenceMode -> Nothing

-- A migration and (hopefully) also its inverse if we have it.
-- Polymorphic because `m` can be any `MonadTx`, `MonadIO` when
-- used in the `migrations` function below.
data MigrationPair m = MigrationPair
  { mpMigrate :: m (),
    mpDown :: Maybe (m ())
  }

migrateCatalog ::
  forall m.
  ( MonadTx m,
    MonadIO m,
    MonadBaseControl IO m
  ) =>
  Maybe (SourceConnConfiguration ('Postgres 'Vanilla)) ->
  MaintenanceMode ->
  UTCTime ->
  m (MigrationResult, Metadata)
migrateCatalog maybeDefaultSourceConfig maintenanceMode migrationTime = do
  catalogSchemaExists <- doesSchemaExist (SchemaName "hdb_catalog")
  versionTableExists <- doesTableExist (SchemaName "hdb_catalog") (TableName "hdb_version")
  metadataTableExists <- doesTableExist (SchemaName "hdb_catalog") (TableName "hdb_metadata")
  migrationResult <-
    if
        | maintenanceMode == MaintenanceModeEnabled -> do
          if
              | not catalogSchemaExists ->
                throw500 "unexpected: hdb_catalog schema not found in maintenance mode"
              | not versionTableExists ->
                throw500 "unexpected: hdb_catalog.hdb_version table not found in maintenance mode"
              | not metadataTableExists ->
                throw500 $
                  "the \"hdb_catalog.hdb_metadata\" table is expected to exist and contain"
                    <> " the metadata of the graphql-engine"
              | otherwise -> pure MRMaintanenceMode
        | otherwise -> case catalogSchemaExists of
          False -> initialize True
          True -> case versionTableExists of
            False -> initialize False
            True -> migrateFrom =<< liftTx getCatalogVersion
  metadata <- liftTx fetchMetadataFromCatalog
  pure (migrationResult, metadata)
  where
    -- initializes the catalog, creating the schema if necessary
    initialize :: Bool -> m MigrationResult
    initialize createSchema = do
      liftTx $
        Q.catchE defaultTxErrorHandler $
          when createSchema $ Q.unitQ "CREATE SCHEMA hdb_catalog" () False
      enablePgcryptoExtension
      multiQ $(makeRelativeToProject "src-rsr/initialise.sql" >>= Q.sqlFromFile)
      updateCatalogVersion

      let emptyMetadata' = case maybeDefaultSourceConfig of
            Nothing -> emptyMetadata
            Just defaultSourceConfig ->
              -- insert metadata with default source
              let defaultSourceMetadata =
                    AB.mkAnyBackend $
                      SourceMetadata @('Postgres 'Vanilla) defaultSource mempty mempty defaultSourceConfig Nothing
                  sources = OMap.singleton defaultSource defaultSourceMetadata
               in emptyMetadata {_metaSources = sources}

      liftTx $ insertMetadataInCatalog emptyMetadata'
      pure MRInitialized

    -- migrates an existing catalog to the latest version from an existing verion
    migrateFrom :: Text -> m MigrationResult
    migrateFrom previousVersion
      | previousVersion == latestCatalogVersionString = pure MRNothingToDo
      | [] <- neededMigrations =
        throw400 NotSupported $
          "Cannot use database previously used with a newer version of graphql-engine (expected"
            <> " a catalog version <="
            <> latestCatalogVersionString
            <> ", but the current version"
            <> " is "
            <> previousVersion
            <> ")."
      | otherwise = do
        traverse_ (mpMigrate . snd) neededMigrations
        updateCatalogVersion
        pure $ MRMigrated previousVersion
      where
        neededMigrations =
          dropWhile ((/= previousVersion) . fst) (migrations maybeDefaultSourceConfig False maintenanceMode)

    updateCatalogVersion = setCatalogVersion latestCatalogVersionString migrationTime

downgradeCatalog ::
  forall m.
  (MonadIO m, MonadTx m) =>
  Maybe (SourceConnConfiguration ('Postgres 'Vanilla)) ->
  DowngradeOptions ->
  UTCTime ->
  m MigrationResult
downgradeCatalog defaultSourceConfig opts time = do
  downgradeFrom =<< liftTx getCatalogVersion
  where
    -- downgrades an existing catalog to the specified version
    downgradeFrom :: Text -> m MigrationResult
    downgradeFrom previousVersion
      | previousVersion == dgoTargetVersion opts = do
        pure MRNothingToDo
      | otherwise =
        case neededDownMigrations (dgoTargetVersion opts) of
          Left reason ->
            throw400 NotSupported $
              "This downgrade path (from "
                <> previousVersion
                <> " to "
                <> dgoTargetVersion opts
                <> ") is not supported, because "
                <> reason
          Right path -> do
            sequence_ path
            unless (dgoDryRun opts) do
              setCatalogVersion (dgoTargetVersion opts) time
            pure (MRMigrated previousVersion)
      where
        neededDownMigrations newVersion =
          downgrade
            previousVersion
            newVersion
            (reverse (migrations defaultSourceConfig (dgoDryRun opts) MaintenanceModeDisabled))

        downgrade ::
          Text ->
          Text ->
          [(Text, MigrationPair m)] ->
          Either Text [m ()]
        downgrade lower upper = skipFutureDowngrades
          where
            -- We find the list of downgrade scripts to run by first
            -- dropping any downgrades which correspond to newer versions
            -- of the schema than the one we're running currently.
            -- Then we take migrations as needed until we reach the target
            -- version, dropping any remaining migrations from the end of the
            -- (reversed) list.
            skipFutureDowngrades, dropOlderDowngrades :: [(Text, MigrationPair m)] -> Either Text [m ()]
            skipFutureDowngrades xs | previousVersion == lower = dropOlderDowngrades xs
            skipFutureDowngrades [] = Left "the starting version is unrecognized."
            skipFutureDowngrades ((x, _) : xs)
              | x == lower = dropOlderDowngrades xs
              | otherwise = skipFutureDowngrades xs

            dropOlderDowngrades [] = Left "the target version is unrecognized."
            dropOlderDowngrades ((x, MigrationPair {mpDown = Nothing}) : _) =
              Left $ "there is no available migration back to version " <> x <> "."
            dropOlderDowngrades ((x, MigrationPair {mpDown = Just y}) : xs)
              | x == upper = Right [y]
              | otherwise = (y :) <$> dropOlderDowngrades xs

migrations ::
  forall m.
  (MonadIO m, MonadTx m) =>
  Maybe (SourceConnConfiguration ('Postgres 'Vanilla)) ->
  Bool ->
  MaintenanceMode ->
  [(Text, MigrationPair m)]
migrations maybeDefaultSourceConfig dryRun maintenanceMode =
  -- We need to build the list of migrations at compile-time so that we can compile the SQL
  -- directly into the executable using `Q.sqlFromFile`. The GHC stage restriction makes
  -- doing this a little bit awkward (we can’t use any definitions in this module at
  -- compile-time), but putting a `let` inside the splice itself is allowed.
  $( let migrationFromFile from to =
           let path = "src-rsr/migrations/" <> from <> "_to_" <> to <> ".sql"
            in [|runTxOrPrint $(makeRelativeToProject path >>= Q.sqlFromFile)|]
         migrationFromFileMaybe from to = do
           path <- makeRelativeToProject $ "src-rsr/migrations/" <> from <> "_to_" <> to <> ".sql"
           exists <- TH.runIO (doesFileExist path)
           if exists
             then [|Just (runTxOrPrint $(Q.sqlFromFile path))|]
             else [|Nothing|]

         migrationsFromFile = map $ \(to :: Integer) ->
           let from = to - 1
            in [|
                 ( $(TH.lift $ tshow from),
                   MigrationPair
                     $(migrationFromFile (show from) (show to))
                     $(migrationFromFileMaybe (show to) (show from))
                 )
                 |]
      in TH.listE
         -- version 0.8 is the only non-integral catalog version
         $
           [|("0.8", MigrationPair $(migrationFromFile "08" "1") Nothing)|] :
           migrationsFromFile [2 .. 3]
             ++ [|("3", MigrationPair from3To4 Nothing)|] :
           migrationsFromFile [5 .. 42]
             ++ [|("42", MigrationPair from42To43 (Just from43To42))|] :
           migrationsFromFile [44 .. latestCatalogVersion]
   )
  where
    runTxOrPrint :: Q.Query -> m ()
    runTxOrPrint
      | dryRun =
        liftIO . TIO.putStrLn . Q.getQueryText
      | otherwise = multiQ

    from42To43 = do
      when (maintenanceMode == MaintenanceModeEnabled) $
        throw500 "cannot migrate to catalog version 43 in maintenance mode"
      let query = $(makeRelativeToProject "src-rsr/migrations/42_to_43.sql" >>= Q.sqlFromFile)
      if dryRun
        then (liftIO . TIO.putStrLn . Q.getQueryText) query
        else do
          metadataV2 <- fetchMetadataFromHdbTables
          multiQ query
          defaultSourceConfig <-
            onNothing maybeDefaultSourceConfig $
              throw400 NotSupported $
                "cannot migrate to catalog version 43 without --database-url or env var " <> tshow (fst databaseUrlEnv)
          let metadataV3 =
                let MetadataNoSources {..} = metadataV2
                    defaultSourceMetadata =
                      AB.mkAnyBackend $
                        SourceMetadata defaultSource _mnsTables _mnsFunctions defaultSourceConfig Nothing
                 in Metadata
                      (OMap.singleton defaultSource defaultSourceMetadata)
                      _mnsRemoteSchemas
                      _mnsQueryCollections
                      _mnsAllowlist
                      _mnsCustomTypes
                      _mnsActions
                      _mnsCronTriggers
                      mempty
                      emptyApiLimit
                      emptyMetricsConfig
                      mempty
                      mempty
                      emptyNetwork
          liftTx $ insertMetadataInCatalog metadataV3

    from43To42 = do
      let query = $(makeRelativeToProject "src-rsr/migrations/43_to_42.sql" >>= Q.sqlFromFile)
      if dryRun
        then (liftIO . TIO.putStrLn . Q.getQueryText) query
        else do
          Metadata {..} <- liftTx fetchMetadataFromCatalog
          multiQ query
          let emptyMetadataNoSources =
                MetadataNoSources mempty mempty mempty mempty mempty emptyCustomTypes mempty mempty
          metadataV2 <- case OMap.toList _metaSources of
            [] -> pure emptyMetadataNoSources
            [(_, exists)] ->
              pure $ case AB.unpackAnyBackend exists of
                Nothing -> emptyMetadataNoSources
                Just SourceMetadata {..} ->
                  MetadataNoSources
                    _smTables
                    _smFunctions
                    _metaRemoteSchemas
                    _metaQueryCollections
                    _metaAllowlist
                    _metaCustomTypes
                    _metaActions
                    _metaCronTriggers
            _ -> throw400 NotSupported "Cannot downgrade since there are more than one source"
          liftTx $ do
            runHasSystemDefinedT (SystemDefined False) $ saveMetadataToHdbTables metadataV2
            -- when the graphql-engine is migrated from v1 to v2, we drop the foreign key
            -- constraint of the `hdb_catalog.hdb_cron_event` table because the cron triggers
            -- in v2 are saved in the `hdb_catalog.hdb_metadata` table. So, when a downgrade
            -- happens, we need to delay adding the foreign key constraint until the
            -- cron triggers are added in the `hdb_catalog.hdb_cron_triggers`
            addCronTriggerForeignKeyConstraint
          recreateSystemMetadata

multiQ :: (MonadTx m) => Q.Query -> m ()
multiQ = liftTx . Q.multiQE defaultTxErrorHandler
