module Hasura.Server.API.Metadata where

import Hasura.RQL.DDL.Action
import Hasura.RQL.DDL.ComputedField
import Hasura.RQL.DDL.EventTrigger
import Hasura.RQL.DDL.Metadata
import Hasura.RQL.DDL.Permission
import Hasura.RQL.DDL.QueryCollection
import Hasura.RQL.DDL.QueryTags
import Hasura.RQL.DDL.Relationship
import Hasura.RQL.DDL.Relationship.Rename
import Hasura.RQL.DDL.RemoteRelationship
import Hasura.RQL.DDL.Schema
import Hasura.RQL.DDL.Schema.Source
import Hasura.RQL.Types
import Hasura.SQL.AnyBackend

data RQLMetadataV1
  = -- Sources
    RMAddSource !(AnyBackend AddSource)
  | RMDropSource DropSource
  | RMRenameSource !RenameSource
  | -- Tables
    RMTrackTable !(AnyBackend TrackTableV2)
  | RMUntrackTable !(AnyBackend UntrackTable)
  | RMSetTableCustomization !(AnyBackend SetTableCustomization)
  | -- Tables (PG-specific)
    RMPgSetTableIsEnum !SetTableIsEnum
  | -- Tables permissions
    RMCreateInsertPermission !(AnyBackend (CreatePerm InsPerm))
  | RMCreateSelectPermission !(AnyBackend (CreatePerm SelPerm))
  | RMCreateUpdatePermission !(AnyBackend (CreatePerm UpdPerm))
  | RMCreateDeletePermission !(AnyBackend (CreatePerm DelPerm))
  | RMDropInsertPermission !(AnyBackend (DropPerm InsPerm))
  | RMDropSelectPermission !(AnyBackend (DropPerm SelPerm))
  | RMDropUpdatePermission !(AnyBackend (DropPerm UpdPerm))
  | RMDropDeletePermission !(AnyBackend (DropPerm DelPerm))
  | RMSetPermissionComment !(AnyBackend SetPermComment)
  | -- Tables relationships
    RMCreateObjectRelationship !(AnyBackend CreateObjRel)
  | RMCreateArrayRelationship !(AnyBackend CreateArrRel)
  | RMDropRelationship !(AnyBackend DropRel)
  | RMSetRelationshipComment !(AnyBackend SetRelComment)
  | RMRenameRelationship !(AnyBackend RenameRel)
  | -- Tables remote relationships
    RMCreateRemoteRelationship !(AnyBackend RemoteRelationship)
  | RMUpdateRemoteRelationship !(AnyBackend RemoteRelationship)
  | RMDeleteRemoteRelationship !(DeleteRemoteRelationship ('Postgres 'Vanilla))
  | -- Functions
    RMTrackFunction !(AnyBackend TrackFunctionV2)
  | RMUntrackFunction !(AnyBackend UnTrackFunction)
  | RMSetFunctionCustomization (AnyBackend SetFunctionCustomization)
  | -- Functions permissions
    RMCreateFunctionPermission !(AnyBackend FunctionPermissionArgument)
  | RMDropFunctionPermission !(AnyBackend FunctionPermissionArgument)
  | -- Computed fields (PG-specific)
    RMAddComputedField !(AddComputedField ('Postgres 'Vanilla))
  | RMDropComputedField !(DropComputedField ('Postgres 'Vanilla))
  | -- Tables event triggers
    RMCreateEventTrigger !(AnyBackend CreateEventTriggerQuery)
  | RMDeleteEventTrigger !(AnyBackend DeleteEventTriggerQuery)
  | RMRedeliverEvent !(AnyBackend RedeliverEventQuery)
  | RMInvokeEventTrigger !(AnyBackend InvokeEventTriggerQuery)
  | -- Remote schemas
    RMAddRemoteSchema !AddRemoteSchemaQuery
  | RMUpdateRemoteSchema !AddRemoteSchemaQuery
  | RMRemoveRemoteSchema !RemoteSchemaNameQuery
  | RMReloadRemoteSchema !RemoteSchemaNameQuery
  | RMIntrospectRemoteSchema !RemoteSchemaNameQuery
  | -- Remote schemas permissions
    RMAddRemoteSchemaPermissions !AddRemoteSchemaPermission
  | RMDropRemoteSchemaPermissions !DropRemoteSchemaPermissions
  | -- Scheduled triggers
    RMCreateCronTrigger !CreateCronTrigger
  | RMDeleteCronTrigger !ScheduledTriggerName
  | RMCreateScheduledEvent !CreateScheduledEvent
  | RMDeleteScheduledEvent !DeleteScheduledEvent
  | RMGetScheduledEvents !GetScheduledEvents
  | RMGetEventInvocations !GetEventInvocations
  | -- Actions
    RMCreateAction !CreateAction
  | RMDropAction !DropAction
  | RMUpdateAction !UpdateAction
  | RMCreateActionPermission !CreateActionPermission
  | RMDropActionPermission !DropActionPermission
  | -- Query collections, allow list related
    RMCreateQueryCollection !CreateCollection
  | RMDropQueryCollection !DropCollection
  | RMAddQueryToCollection !AddQueryToCollection
  | RMDropQueryFromCollection !DropQueryFromCollection
  | RMAddCollectionToAllowlist !CollectionReq
  | RMDropCollectionFromAllowlist !CollectionReq
  | -- Rest endpoints
    RMCreateRestEndpoint !CreateEndpoint
  | RMDropRestEndpoint !DropEndpoint
  | -- Custom types
    RMSetCustomTypes !CustomTypes
  | -- Api limits
    RMSetApiLimits !ApiLimit
  | RMRemoveApiLimits
  | -- Metrics config
    RMSetMetricsConfig !MetricsConfig
  | RMRemoveMetricsConfig
  | -- Inherited roles
    RMAddInheritedRole !InheritedRole
  | RMDropInheritedRole !DropInheritedRole
  | -- Metadata management
    RMReplaceMetadata !ReplaceMetadata
  | RMExportMetadata !ExportMetadata
  | RMClearMetadata !ClearMetadata
  | RMReloadMetadata !ReloadMetadata
  | RMGetInconsistentMetadata !GetInconsistentMetadata
  | RMDropInconsistentMetadata !DropInconsistentMetadata
  | -- Introspection options
    RMSetGraphqlSchemaIntrospectionOptions !SetGraphqlIntrospectionOptions
  | -- Network
    RMAddHostToTLSAllowlist !AddHostToTLSAllowlist
  | RMDropHostFromTLSAllowlist !DropHostFromTLSAllowlist
  | -- QueryTags
    RMSetQueryTagsConfig !SetQueryTagsConfig
  | -- Debug
    RMDumpInternalState !DumpInternalState
  | RMGetCatalogState !GetCatalogState
  | RMSetCatalogState !SetCatalogState
  | RMTestWebhookTransform !TestWebhookTransform
  | -- Bulk metadata queries
    RMBulk [RQLMetadataRequest]

data RQLMetadataV2
  = RMV2ReplaceMetadata !ReplaceMetadataV2
  | RMV2ExportMetadata !ExportMetadata

data RQLMetadataRequest
  = RMV1 !RQLMetadataV1
  | RMV2 !RQLMetadataV2
