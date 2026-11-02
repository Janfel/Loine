/*
 Loine – installation of the street network and the target tables

 SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-casaGeo-Commercial
 Copyright © 2026 casaGeo Data + Services GmbH – https://www.casageo.de/loine.html – info@casageo.de

 Run once (creates schema pgr, the target tables and the installation procedures):
     psql -d <database> -f loine_install.sql

 Per country:
     pg_restore -d <database> --no-owner loine_<country>_….dump    -- creates the schema loine_<country>
     CALL pgr.loine_install_country('<country>');                   -- moves the country into pgr

 After the last country (indexes, sorting, statistics, base network for routes over the whole delivery):
     CALL pgr.loine_finalize();

 Requirements: PostgreSQL 18, PostGIS, pgRouting.
 A database contains only countries of one data source (HERE or OSM) and one region (Europe EPSG:3035, Africa 990001,
 North America 990002); the routing functions read the projection from pgr.loine_installed.
 A country can be installed again at any time; its previous data is replaced.
 */

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE SCHEMA IF NOT EXISTS pgr;

-- Projections of the regions outside Europe (Lambert azimuthal equal area per continent)
INSERT INTO spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
VALUES (990001, 'LOINE', 990001,
        '+proj=laea +lat_0=4.2 +lon_0=19.1 +x_0=5500000 +y_0=5500000 +datum=WGS84 +units=m +no_defs',
        'PROJCS["LOINE Afrika LAEA",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]]],PROJECTION["Lambert_Azimuthal_Equal_Area"],PARAMETER["latitude_of_center",4.2],PARAMETER["longitude_of_center",19.1],PARAMETER["false_easting",5500000],PARAMETER["false_northing",5500000],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH]]'),
       (990002, 'LOINE', 990002,
        '+proj=laea +lat_0=43.3 +lon_0=-94 +x_0=5500000 +y_0=5500000 +datum=WGS84 +units=m +no_defs',
        'PROJCS["LOINE Nordamerika LAEA",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]]],PROJECTION["Lambert_Azimuthal_Equal_Area"],PARAMETER["latitude_of_center",43.3],PARAMETER["longitude_of_center",-94],PARAMETER["false_easting",5500000],PARAMETER["false_northing",5500000],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH]]')
ON CONFLICT (srid) DO UPDATE SET auth_name = EXCLUDED.auth_name,
                                 auth_srid = EXCLUDED.auth_srid,
                                 proj4text = EXCLUDED.proj4text,
                                 srtext    = EXCLUDED.srtext;

--======================================================================================================================
-- Target tables
--======================================================================================================================

CREATE TABLE IF NOT EXISTS pgr.kacheln
(
    partition_id VARCHAR PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS pgr.partition
(
    partition_id VARCHAR PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS pgr.cluster
(
    country_code CHAR(2),
    partition_id VARCHAR,
    cluster_id   VARCHAR,
    geom         GEOMETRY,
    PRIMARY KEY (partition_id, cluster_id, country_code)
);

CREATE TABLE IF NOT EXISTS pgr.edges
(
    id            BIGINT,
    source        BIGINT,
    target        BIGINT,
    source_id     DOUBLE PRECISION,
    speed_cat     INTEGER,
    street_cat    INTEGER,
    cost_distance INTEGER,
    cost_time     INTEGER,
    cost_traffic  INTEGER,
    partition_id  TEXT,
    cluster_id    TEXT,
    grid_1km      TEXT,
    geom          GEOMETRY,
    x1            INTEGER,
    y1            INTEGER,
    x2            INTEGER,
    y2            INTEGER
) PARTITION BY LIST (partition_id);

CREATE TABLE IF NOT EXISTS pgr.grids
(
    id                      BIGINT,
    partition_id            TEXT,
    cluster_id              TEXT,
    source                  BIGINT,
    target                  BIGINT,
    source_id               DOUBLE PRECISION,
    gitter_id_              TEXT,
    grid_1km                TEXT,
    grid_distance           INTEGER,
    grid_time               INTEGER,
    grid_traffic            INTEGER,
    grid_factor             DOUBLE PRECISION,
    distance_to_grid_factor DOUBLE PRECISION,
    cost_distance           INTEGER,
    cost_time               INTEGER,
    cost_traffic            INTEGER,
    street_cat              INTEGER,
    x1                      INTEGER,
    y1                      INTEGER,
    grid_geom               GEOMETRY
) PARTITION BY LIST (partition_id);

-- Older installations: column link_id is now called source_id
DO
$$
    DECLARE
        t TEXT;
    BEGIN
        FOREACH t IN ARRAY ARRAY ['edges', 'grids']
            LOOP
                IF EXISTS (SELECT 1
                           FROM information_schema.columns
                           WHERE table_schema = 'pgr'
                             AND table_name = t
                             AND column_name = 'link_id') THEN
                    EXECUTE FORMAT('ALTER TABLE pgr.%I RENAME COLUMN link_id TO source_id', t);
                    RAISE NOTICE 'Loine: pgr.%.link_id renamed to source_id', t;
                END IF;
            END LOOP;
    END
$$;

-- Installed countries
CREATE TABLE IF NOT EXISTS pgr.loine_installed
(
    country        CHAR(2) PRIMARY KEY,
    source         TEXT,
    source_version TEXT,
    run_id         BIGINT,
    edges          BIGINT,
    grids          BIGINT,
    installed_at   TIMESTAMPTZ NOT NULL DEFAULT CLOCK_TIMESTAMP()
);
-- Region and projection (older installations without these columns are Europe, EPSG:3035)
ALTER TABLE pgr.loine_installed
    ADD COLUMN IF NOT EXISTS region TEXT NOT NULL DEFAULT 'europa';
ALTER TABLE pgr.loine_installed
    ADD COLUMN IF NOT EXISTS srid INTEGER NOT NULL DEFAULT 3035;

-- Street categories per data source and mode of transport (read by pgr._mode_category)
--   buffer_cats  buffer around start and end
--   main_cats    main network between start and end
--   snap_cats    categories to which start and end are snapped
--   matrix_cats  network of the cost matrix
-- Running this script again resets the values to the delivered ones.
CREATE TABLE IF NOT EXISTS pgr.loine_mode_category
(
    source      TEXT NOT NULL,
    mode        TEXT NOT NULL,
    buffer_cats INTEGER[],
    main_cats   INTEGER[],
    snap_cats   INTEGER[],
    matrix_cats INTEGER[],
    PRIMARY KEY (source, mode)
);

INSERT INTO pgr.loine_mode_category (source, mode, buffer_cats, main_cats, snap_cats, matrix_cats)
VALUES
    -- HERE
    ('here', 'car', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13}', '{-1,1,2,3,4,5,6,7,8,9,13}', '{4,5,6,7,8,9,10,11,12}', NULL),
    ('here', 'card', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13}', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13}',
     '{4,5,6,7,8,9,10,11,12}', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13}'),
    ('here', 'caro', '{-1,1,2,3,4,5,6,7,8,9,13}', '{-1,1,2,3,4,5,6,7,8,9,13}', '{4,5,6,7,8,9,10}',
     '{-1,1,2,3,4,5,6,7,8,9,13}'),
    ('here', 'care', '{-1,3,4,5,6,7,8,9,10,11,12,13}', '{-1,3,4,5,6,7,8,9,10,11,12,13}', '{4,5,6,7,8,9,10,11,12}',
     '{-1,3,4,5,6,7,8,9,10,11,12,13}'),
    ('here', 'carl', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14}', '{-1,1,2,3,4,5,6,7,8,9,13}',
     '{4,5,6,7,8,9,10,11,12,13,14}', NULL),
    ('here', 'pedestrian', '{-1,4,5,6,7,8,9,10,11,12,13,14}', '{-1,4,5,6,7,8,9,10,11,12,13,14}',
     '{6,7,8,9,10,11,12,13,14}', '{-1,4,5,6,7,8,9,10,11,12,13,14}'),
    ('here', 'no_mode', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14}', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14}',
     '{4,5,6,7,8,9,10,11,12,13,14}', '{-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14}'),
    -- OSM (rank: 1 motorway … 7 residential/living_street, 8 service, 9 track, 10 pedestrian, 11 footway/path/cycleway/steps)
    ('osm', 'car', '{-1,1,2,3,4,5,6,7,8}', '{-1,1,2,3,4,5,6,7}', '{3,4,5,6,7,8}', '{-1,1,2,3,4,5,6,7,8}'),
    ('osm', 'card', '{-1,1,2,3,4,5,6,7,8}', '{-1,1,2,3,4,5,6,7,8}', '{3,4,5,6,7,8}', '{-1,1,2,3,4,5,6,7,8}'),
    ('osm', 'caro', '{-1,1,2,3,4,5,6,7}', '{-1,1,2,3,4,5,6}', '{3,4,5,6,7}',
     '{-1,1,2,3,4,5,6}'), -- residential streets only for snapping
    ('osm', 'care', '{-1,2,3,4,5,6,7,8}', '{-1,2,3,4,5,6,7}', '{3,4,5,6,7,8}', '{-1,2,3,4,5,6,7,8}'),
    ('osm', 'carl', '{-1,1,2,3,4,5,6,7,8,10}', '{-1,1,2,3,4,5,6,7}', '{3,4,5,6,7,8,10}', '{-1,1,2,3,4,5,6,7,8,10}'),
    ('osm', 'pedestrian', '{-1,3,4,5,6,7,8,9,10,11}', '{-1,3,4,5,6,7,8,9,10,11}', '{3,4,5,6,7,8,9,10,11}',
     '{-1,3,4,5,6,7,8,9,10,11}'),
    ('osm', 'no_mode', '{-1,1,2,3,4,5,6,7,8,9,10,11}', '{-1,1,2,3,4,5,6,7,8,9,10,11}', '{1,2,3,4,5,6,7,8,9,10,11}',
     '{-1,1,2,3,4,5,6,7,8,9,10,11}')
ON CONFLICT (source, mode) DO UPDATE SET buffer_cats = EXCLUDED.buffer_cats,
                                         main_cats   = EXCLUDED.main_cats,
                                         snap_cats   = EXCLUDED.snap_cats,
                                         matrix_cats = EXCLUDED.matrix_cats;

-- Base network for the preselection of routes: parameters (pgr.net_level) and number of edges per tile or cluster
-- and category. Filled by CALL pgr.loine_build_net_level() in pgr.loine_finalize.
CREATE TABLE IF NOT EXISTS pgr.net_level
(
    budget     BIGINT NOT NULL, -- edges per preselection (base network + local preselection)
    min_global BIGINT NOT NULL, -- edges of the base network that are always loaded
    base_cat   INTEGER,         -- highest category of the backbone (NULL: no backbone)
    global_n   BIGINT NOT NULL, -- edges of the base network
    built_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pgr.net_density
(
    partition_id TEXT    NOT NULL,
    street_cat   INTEGER NOT NULL,
    n            BIGINT  NOT NULL,
    PRIMARY KEY (partition_id, street_cat)
);

CREATE TABLE IF NOT EXISTS pgr.net_density_cluster
(
    cluster_id TEXT    NOT NULL,
    street_cat INTEGER NOT NULL,
    n          BIGINT  NOT NULL,
    PRIMARY KEY (cluster_id, street_cat)
);

--======================================================================================================================
-- Install a country
--======================================================================================================================
CREATE OR REPLACE PROCEDURE pgr.loine_install_country(
    p_country CHAR(2),
    p_drop_import BOOLEAN DEFAULT TRUE -- drop schema loine_<country> after the installation
)
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_country CHAR(2)     := LOWER(p_country);
    v_imp     TEXT        := 'loine_' || LOWER(p_country);
    m         RECORD;
    v_region  TEXT;
    v_srid    INTEGER;
    v_pid     TEXT;
    v_rows    BIGINT;
    v_ts      TIMESTAMPTZ := CLOCK_TIMESTAMP();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = v_imp) THEN
        RAISE EXCEPTION 'Schema % is missing', v_imp
            USING HINT = 'Restore the dump of the country with pg_restore first.';
    END IF;

    EXECUTE FORMAT('SELECT * FROM %I.meta', v_imp) INTO m;
    RAISE NOTICE 'Loine: installing % (%, %), run %', UPPER(v_country), UPPER(m.source),
        COALESCE(m.source_version, 'data version not specified'), m.run_id;

    -- Region and projection (older dumps without these values are Europe, EPSG:3035)
    v_region := COALESCE(TO_JSONB(m) ->> 'region', 'europa');
    v_srid := COALESCE((TO_JSONB(m) ->> 'srid')::INTEGER, 3035);
    IF NOT EXISTS (SELECT 1 FROM spatial_ref_sys WHERE srid = v_srid) THEN
        RAISE EXCEPTION 'Projection % is missing in spatial_ref_sys', v_srid
            USING HINT = 'Run loine_install.sql again.';
    END IF;
    IF EXISTS (SELECT 1 FROM pgr.loine_installed WHERE srid <> v_srid AND country <> v_country) THEN
        RAISE EXCEPTION 'This database already contains countries of another region (%); this country belongs to % (SRID %)',
            (SELECT STRING_AGG(DISTINCT region || ' ' || srid, ', ') FROM pgr.loine_installed), v_region, v_srid;
    END IF;

    -- do not mix with another data source
    IF EXISTS (SELECT 1 FROM pgr.loine_installed WHERE source <> m.source) THEN
        RAISE EXCEPTION 'This database already contains countries of another data source (%); this country has %',
            (SELECT STRING_AGG(DISTINCT UPPER(source), ', ') FROM pgr.loine_installed), UPPER(m.source);
    END IF;

    -- remove the previous data of the country (identified by the id range of the nodes)
    DELETE FROM pgr.edges WHERE source BETWEEN m.id_from AND m.id_to;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows > 0 THEN
        RAISE NOTICE 'Loine: % previous edges of % removed', v_rows, UPPER(v_country);
    END IF;
    DELETE FROM pgr.grids WHERE source BETWEEN m.id_from AND m.id_to;
    DELETE FROM pgr.cluster WHERE country_code = v_country;

    -- tiles and partitions
    EXECUTE FORMAT('INSERT INTO pgr.kacheln SELECT partition_id FROM %I.kacheln ON CONFLICT DO NOTHING', v_imp);
    EXECUTE FORMAT('INSERT INTO pgr.partition SELECT partition_id FROM %I.partition ON CONFLICT DO NOTHING', v_imp);

    FOR v_pid IN EXECUTE FORMAT('SELECT partition_id FROM %I.partition ORDER BY 1', v_imp)
        LOOP
            EXECUTE FORMAT('CREATE TABLE IF NOT EXISTS pgr.%I PARTITION OF pgr.edges FOR VALUES IN (%L)',
                           'edges_' || LOWER(v_pid), v_pid);
            EXECUTE FORMAT('CREATE TABLE IF NOT EXISTS pgr.%I PARTITION OF pgr.grids FOR VALUES IN (%L)',
                           'grids_' || LOWER(v_pid), v_pid);
        END LOOP;
    COMMIT;

    -- copy the data
    EXECUTE FORMAT('INSERT INTO pgr.edges
                    SELECT id, source, target, source_id, speed_cat, street_cat, cost_distance, cost_time, cost_traffic,
                           partition_id, cluster_id, grid_1km, geom, x1, y1, x2, y2
                    FROM %I.edges', v_imp);
    COMMIT;
    EXECUTE FORMAT('INSERT INTO pgr.grids
                    SELECT id, partition_id, cluster_id, source, target, source_id, gitter_id_, grid_1km,
                           grid_distance, grid_time, grid_traffic, grid_factor, distance_to_grid_factor,
                           cost_distance, cost_time, cost_traffic, street_cat, x1, y1, grid_geom
                    FROM %I.grids', v_imp);
    COMMIT;
    EXECUTE FORMAT('INSERT INTO pgr.cluster SELECT country_code, partition_id, cluster_id, geom FROM %I.cluster
                    ON CONFLICT DO NOTHING', v_imp);

    INSERT INTO pgr.loine_installed (country, source, source_version, run_id, edges, grids, region, srid)
    VALUES (v_country, m.source, m.source_version, m.run_id, m.edges, m.grids, v_region, v_srid)
    ON CONFLICT (country) DO UPDATE
        SET source         = EXCLUDED.source,
            source_version = EXCLUDED.source_version,
            run_id         = EXCLUDED.run_id,
            edges          = EXCLUDED.edges,
            grids          = EXCLUDED.grids,
            region         = EXCLUDED.region,
            srid           = EXCLUDED.srid,
            installed_at   = CLOCK_TIMESTAMP();

    IF p_drop_import THEN
        EXECUTE FORMAT('DROP SCHEMA %I CASCADE', v_imp);
    END IF;
    COMMIT;

    RAISE NOTICE 'Loine: % installed – % edges, % grid cells (duration %). After the last country: CALL pgr.loine_finalize();',
        UPPER(v_country), m.edges, m.grids, DATE_TRUNC('second', CLOCK_TIMESTAMP() - v_ts);
END;
$$;

--======================================================================================================================
-- Finalize after the last country: indexes, sorting, statistics over the whole delivery
--======================================================================================================================
CREATE OR REPLACE PROCEDURE pgr.loine_finalize()
    LANGUAGE plpgsql
AS
$$
DECLARE
    r    RECORD;
    v_ts TIMESTAMPTZ := CLOCK_TIMESTAMP();
BEGIN
    RAISE NOTICE 'Loine: creating indexes';
    CREATE INDEX IF NOT EXISTS idx_pgr_edges_grid_1km ON pgr.edges USING btree (grid_1km);
    CREATE INDEX IF NOT EXISTS idx_pgr_edges_cluster_id ON pgr.edges USING btree (cluster_id);
    CREATE INDEX IF NOT EXISTS idx_pgr_edges_x1y1 ON pgr.edges USING btree (x1, y1);
    CREATE INDEX IF NOT EXISTS gist_pgr_edges_geom ON pgr.edges USING gist (geom);
    -- predecessors/successors when snapping start and end (pgr._starting_segment, pgr._ending_segment)
    CREATE INDEX IF NOT EXISTS idx_pgr_edges_source ON pgr.edges USING btree (source);
    CREATE INDEX IF NOT EXISTS idx_pgr_edges_target ON pgr.edges USING btree (target);
    COMMIT;
    CREATE INDEX IF NOT EXISTS idx_pgr_grids_grid_1km ON pgr.grids USING btree (grid_1km);
    CREATE INDEX IF NOT EXISTS idx_pgr_grids_cluster_id ON pgr.grids USING btree (cluster_id);
    CREATE INDEX IF NOT EXISTS idx_pgr_grids_source ON pgr.grids USING btree (source);
    CREATE INDEX IF NOT EXISTS idx_pgr_grids_target ON pgr.grids USING btree (target);
    CREATE INDEX IF NOT EXISTS idx_pgr_grids_x1y1 ON pgr.grids USING btree (x1, y1);
    CREATE INDEX IF NOT EXISTS gist_pgr_grids_grid_geom ON pgr.grids USING gist (grid_geom);
    CREATE INDEX IF NOT EXISTS gist_pgr_cluster_geom ON pgr.cluster USING gist (geom);
    COMMIT;

    -- sort each tile by 1 km cell (CLUSTER on the parent table is not possible in a procedure)
    RAISE NOTICE 'Loine: sorting tables per tile';
    FOR r IN
        SELECT c.relname                                                  AS part,
               p.relname                                                  AS parent,
               (SELECT ci.relname
                FROM pg_index i
                         JOIN pg_class ci ON ci.oid = i.indexrelid
                         JOIN pg_inherits ii ON ii.inhrelid = i.indexrelid
                         JOIN pg_class pi ON pi.oid = ii.inhparent
                WHERE i.indrelid = c.oid
                  AND pi.relname = CASE p.relname
                                       WHEN 'edges' THEN 'idx_pgr_edges_grid_1km'
                                       ELSE 'idx_pgr_grids_grid_1km' END) AS idx
        FROM pg_inherits h
                 JOIN pg_class c ON c.oid = h.inhrelid
                 JOIN pg_class p ON p.oid = h.inhparent
                 JOIN pg_namespace n ON n.oid = p.relnamespace
        WHERE n.nspname = 'pgr'
          AND p.relname IN ('edges', 'grids')
        ORDER BY 1
        LOOP
            EXECUTE FORMAT('CLUSTER pgr.%I USING %I', r.part, r.idx);
            COMMIT;
        END LOOP;

    RAISE NOTICE 'Loine: statistics';
    ANALYZE pgr.edges;
    ANALYZE pgr.grids;
    ANALYZE pgr.cluster;
    COMMIT;

    -- base network for the preselection of routes (pgr.loine_build_net_level), if the functions are installed
    IF TO_REGPROCEDURE('pgr.loine_build_net_level(bigint, bigint)') IS NOT NULL THEN
        RAISE NOTICE 'Loine: base network for routes';
        CALL pgr.loine_build_net_level();
    ELSE
        RAISE WARNING 'Loine: routing functions not installed – after installing them run CALL pgr.loine_build_net_level();';
    END IF;

    RAISE NOTICE 'Loine: finalize done (duration %)', DATE_TRUNC('second', CLOCK_TIMESTAMP() - v_ts);
END;
$$;
