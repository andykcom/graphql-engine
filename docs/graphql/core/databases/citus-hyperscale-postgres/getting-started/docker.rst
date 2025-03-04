.. meta::
  :description: Hasura with Docker for Citus - Hyperscale
  :keywords: hasura, docs, databases, citus, docker

.. _database_citus_hyperscale_docker:

Get Started with Docker (Hasura & Citus - Hyperscale)
=====================================================

.. contents:: Table of contents
  :backlinks: none
  :depth: 2
  :local:

Try it out
----------

Pre-requisites
^^^^^^^^^^^^^^

- `Docker <https://docs.docker.com/install/>`_
- `Docker Compose <https://docs.docker.com/compose/install/>`_
- An existing Citus database

Step 1: Get the docker-compose file
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Get the Hasura docker-compose file:

.. code-block:: bash

   # in a new directory run
   wget https://raw.githubusercontent.com/hasura/graphql-engine/stable/install-manifests/docker-compose/docker-compose.yaml
   # or run
   curl https://raw.githubusercontent.com/hasura/graphql-engine/stable/install-manifests/docker-compose/docker-compose.yaml -o docker-compose.yaml

Step 2: Run Hasura GraphQL engine
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The following command will run Hasura along with a Postgres database required
for its functioning.

.. code-block::  bash

   $ docker-compose up -d

Check if the containers are running:

.. code-block:: bash

  $ docker ps

  CONTAINER ID IMAGE                 ... CREATED STATUS PORTS          ...
  097f58433a2b hasura/graphql-engine ... 1m ago  Up 1m  8080->8080/tcp ...
  b0b1aac0508d postgres              ... 1m ago  Up 1m  5432/tcp       ...

  Please do note that you will see a Postgres database running, which is used by Hasura to store its configuration (Hasura metadata).

Step 3: Open the Hasura console
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Head to ``http://localhost:8080/console`` to open the Hasura console.

Step 4: Add your Citus database as a source to Hasura
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

In the ``Data > Data Manager > Connect Existing Database`` section on the console, 
select ``Citus`` from the ``Data Source Driver`` dropdown and add the connection string
directly or through an environment variable. As Citus speaks the same protocol as 
Postgres, the connection string will start with ``postgres://``, i.e, there is no
difference between Citus’s connection strings and Postgres’s connection strings.

.. thumbnail:: /img/graphql/core/databases/citus-hyperscale-postgres/1-add-source.png
   :alt: Add source
   :width: 600px

If you're testing Hasura with Citus running locally, :ref:`read this guide<docker_networking>` on Docker networking in case you're not sure
how to make sure that your Citus database is reachable from the Hasura docker container on Linux, Mac or Windows.


Once you add the database, you'll see your database pop up on the sidebar.

Step 5: Track existing tables or create new tables
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you have existing tables, head to the database page by clicking on the database name on the sidebar. You should see a list of tables.

..
   .. thumbnail:: /img/graphql/core/databases/ms-sql-server/3-manage-mydb.png
      :alt: Manage my-db
      :width: 1000px

Track tables selectively or all of them so that Hasura can introspect the tables and create the corresponding GraphQL schema.

..
   .. thumbnail:: /img/graphql/core/databases/ms-sql-server/4-track-tables.png
      :alt: Track tables
      :width: 1000px

If you have foreign keys, you'll also see suggested relationships. Again, you can choose to track them selectively or all at once.

..
   .. thumbnail:: /img/graphql/core/databases/ms-sql-server/5-track-rels.png
      :alt: Track relationships
      :width: 1000px

If you don't have existing tables, go ahead and add new tables and data and try out some queries, just like with a regular Postgres database.


..
   Step 3: Option 2: Create new tables
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

   If you don't have existing tables, head to the Run SQL window
   to run SQL against your SQL Server database and create tables or hit the Create Table button
   to create a table.

   If you're running raw SQL queries to create your tables, Don't forget to check "track metadata"
   at the bottom of the Run SQL window to make sure Hasura tracks your new database objects 
   in its GraphQL schema.


   .. thumbnail:: /img/graphql/core/databases/ms-sql-server/7-run-sql.png
      :alt: Run SQL to create table
      :width: 1000px


Step 6: Try out a GraphQL query
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Head to the ``GraphiQL`` tab in the console and try running a GraphQL query! Use the explorer sidebar on GraphQL to get help in creating a GraphQL query.

.. thumbnail:: /img/graphql/core/databases/ms-sql-server/6-make-graphql-query.png
   :alt: Make GraphQL query
   :width: 1000px


Keep up to date
---------------

Hasura supports queries, subscriptions, relationships and permissions on Citus - Hyperscale.

Please watch this space to get the latest docs on how you can try these features out via the console or by manipulating metadata in JSON/YAML directly.

If you'd like to stay informed about the status of Citus support, subscribe to our newsletter and join our discord!

- https://hasura.io/newsletter/
- https://discord.com/invite/hasura