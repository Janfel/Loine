-- Loine 3.0.0 (2026-11-02) – routing functions
--
-- SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-casaGeo-Commercial
-- Copyright © 2026 casaGeo Data + Services GmbH – https://www.casageo.de/loine.html – info@casageo.de
--
-- Run after install/loine_install.sql:  psql -d <database> -f loine_functions.sql
-- Generated from upgrade_drops.sql and the files in functions/; do not edit.

BEGIN;

-- Signatures and return types that changed compared to earlier versions.
-- The build puts these statements at the beginning of loine_functions.sql; the function files themselves
-- contain only CREATE OR REPLACE.

DROP FUNCTION IF EXISTS pgr._buffer_isolines(buffer_value NUMERIC, calculation_type TEXT, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr._candidate_edges(p_edges_table TEXT[], p_start_cluster TEXT[], p_center_x INTEGER,
                                             p_center_y INTEGER, p_sc_inner_low SMALLINT, p_sc_inner_high SMALLINT);
DROP FUNCTION IF EXISTS pgr._candidate_edges_array(p_edges_table TEXT, p_start_cluster TEXT, p_center_x INTEGER,
                                                   p_center_y INTEGER, p_street_cat INTEGER[], p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_edges_cluster(p_start_lon INTEGER, p_start_lat INTEGER, p_end_lon INTEGER,
                                                     p_end_lat INTEGER, p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._candidate_edges_hull_costmatrix(p_x1 INTEGER[], p_y1 INTEGER[], p_street_cat INTEGER[],
                                                             p_buffer_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_edges_isolines(p_lon INTEGER, p_lat INTEGER, p_radius_m INTEGER,
                                                      p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._candidate_edges_radius_costmatrix(p_edges_table TEXT[], p_cluster_ids TEXT[],
                                                               p_center_x INTEGER, p_center_y INTEGER,
                                                               p_street_cat INTEGER[], p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_grids_isolines(p_lon INTEGER, p_lat INTEGER, p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._catchment_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                p_calculation_type TEXT, p_mode_of_transport TEXT, p_direction TEXT,
                                                p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._catchment_isolines_static(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                       p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                       p_direction TEXT, p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._check_input(lon DOUBLE PRECISION, lat DOUBLE PRECISION, mode_of_transport TEXT,
                                         calculation_type TEXT, direction TEXT);
DROP FUNCTION IF EXISTS pgr._check_input_costmatrix(p_input_table TEXT, p_mode_of_transport TEXT, p_calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr._check_input_routes(start_lon DOUBLE PRECISION, start_lat DOUBLE PRECISION,
                                                end_lon DOUBLE PRECISION, end_lat DOUBLE PRECISION,
                                                mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr._costmatrix_points(p_input_table TEXT);
DROP FUNCTION IF EXISTS pgr._costmatrix_segment(p_point_id BIGINT, p_lot_id BIGINT, p_id_offset BIGINT, lon INTEGER,
                                                lat INTEGER, p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._create_dynamical_grids(p_id BIGINT, p_cost INTEGER, p_x1 BIGINT, p_y1 BIGINT, p_x2 BIGINT,
                                                    p_y2 BIGINT, p_geom geometry, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr._driving_distance_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                       p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                       p_direction TEXT, p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._ending_segment(lon INTEGER, lat INTEGER, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr._grids_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                            p_calculation_type TEXT, p_mode_of_transport TEXT, p_direction TEXT,
                                            p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._mode_category(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pgr.loine_build_net_level(BIGINT);
DROP PROCEDURE IF EXISTS pgr.loine_build_net_level(BIGINT, BIGINT);
DROP FUNCTION IF EXISTS pgr._net_level_edges(INTEGER, INTEGER, INTEGER, INTEGER, INTEGER[]);
DROP FUNCTION IF EXISTS pgr._preselection_costmatrix(p_input_table TEXT, p_mode_of_transport TEXT,
                                                     p_inner_limit INTEGER, p_outer_buffer_m INTEGER);
DROP FUNCTION IF EXISTS pgr._preselection_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                   p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                   p_inner_limit INTEGER, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr._preselection_routes(start_lon INTEGER, start_lat INTEGER, end_lon INTEGER, end_lat INTEGER,
                                                 mode_of_transport TEXT, inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._starting_segment(lon INTEGER, lat INTEGER, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_costmatrix(input_table TEXT, mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_costmatrix_snap_report(input_table TEXT, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_isoline(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                        p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_isoline_static(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                               p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_multiisolines(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_values TEXT,
                                              p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_path(start_lon DOUBLE PRECISION, start_lat DOUBLE PRECISION, end_lon DOUBLE PRECISION,
                                     end_lat DOUBLE PRECISION, mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_segments(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                         p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);


-- ==== functions/_buffer_isolines.sql ================================================================================

CREATE OR REPLACE FUNCTION pgr._buffer_isolines(
    buffer_value NUMERIC,
    calculation_type TEXT,
    mode_of_transport TEXT
)
    RETURNS NUMERIC
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$

    -- DESCRIPTION : Creates a buffer to preselect the data based on buffer value and speed category of mode of transport.
DECLARE
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();
    RETURN
        CASE
            WHEN calculation_type IN ('time', 'traffic') AND
                 mode_of_transport IN ('card', 'care', 'caro', 'car', 'carl')
                THEN (130 * buffer_value / 3600) * 1000
            WHEN calculation_type = 'time' AND mode_of_transport = 'pedestrian'
                THEN (5 * buffer_value / 3600) * 1000 + 1000
            ELSE buffer_value
            END;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE INFO 'Execution time for Buffer is % ', elapsed_time;
END
    ;
$function$;


-- ==== functions/_candidate_edges.sql ================================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges(
    p_edges_table TEXT[],
    p_start_cluster TEXT[],
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_sc_inner_low SMALLINT,
    p_sc_inner_high SMALLINT
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                partition_id  TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Part of preselecting grids

DECLARE
BEGIN
    -- Spatial search on the geometry: all edges that run within 1 km of the point. A search on the start point
    -- (x1/y1) and the 10 km cluster of the point would miss long segments that pass right by the point (e.g. in
    -- Namibia 80 % of the network length lies in segments longer than 1 km); there would then be no start or end
    -- segment and no route.
    -- p_edges_table and p_start_cluster remain in the signature for the existing calls but are no longer used
    -- (the search uses the geometry index of all partitions).
    RETURN QUERY
        SELECT e.id,
               e.source,
               e.target,
               e.speed_cat::INTEGER,
               e.street_cat::INTEGER,
               e.cost_time::INTEGER,
               e.cost_distance::INTEGER,
               e.cost_traffic::INTEGER,
               e.cluster_id,
               e.partition_id,
               e.x1,
               e.y1,
               e.x2,
               e.y2,
               e.geom
        FROM pgr.edges e
        WHERE ST_DWithin(e.geom, ST_SetSRID(ST_MakePoint(p_center_x * 100, p_center_y * 100), pgr._srid()), 1000)
          AND e.street_cat > p_sc_inner_low
          AND e.street_cat <= p_sc_inner_high
          AND e.source_id IS NOT NULL; -- only street segments, no turn edges (length 0)
END;
$function$;


-- ==== functions/_candidate_edges_array.sql ==========================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges_array(
    p_edges_table TEXT,
    p_start_cluster TEXT,
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_street_cat INTEGER[],
    p_radius_m INTEGER DEFAULT 500
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                partition_id  TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                source_id     DOUBLE PRECISION,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects edges using x1/y1 range filter (100m grid)
    --              within a given radius around a center point.
    --              cluster_id filter retained for local precision.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_x1_min       INTEGER;
    v_x1_max       INTEGER;
    v_y1_min       INTEGER;
    v_y1_max       INTEGER;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;
BEGIN
    --------------------------------------------------------------------------------------
    -- range limits on the 100 m grid --------------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time = CLOCK_TIMESTAMP();
    v_x1_min := FLOOR((p_center_x * 100 - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_x1_max := CEIL((p_center_x * 100 + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_min := FLOOR((p_center_y * 100 - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_max := CEIL((p_center_y * 100 + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;

    --------------------------------------------------------------------------------------
    -- query with x1/y1 range filter + cluster_id -------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY
        EXECUTE FORMAT(
            'SELECT DISTINCT ON (e.id)
                e.id,
                e.source,
                e.target,
                e.speed_cat::INTEGER,
                e.street_cat::INTEGER,
                e.cost_time::INTEGER,
                e.cost_distance::INTEGER,
                e.cost_traffic::INTEGER,
                e.cluster_id,
                e.partition_id,
                e.x1,
                e.y1,
                e.x2,
                e.y2,
                e.source_id,
                e.geom
            FROM pgr.%I AS e
            WHERE e.x1 BETWEEN %s AND %s
              AND e.y1 BETWEEN %s AND %s
              AND e.street_cat = ANY(%L::INTEGER[])
              AND e.cluster_id = %L
            ORDER BY e.id',
            p_edges_table,
            v_x1_min,
            v_x1_max,
            v_y1_min,
            v_y1_max,
            p_street_cat,
            p_start_cluster
                );
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _candidate_edges_array: %', v_elapsed_time;
END;
$function$;


-- ==== functions/_candidate_edges_cluster.sql ========================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges_cluster(
    p_start_lon INTEGER,
    p_start_lat INTEGER,
    p_end_lon INTEGER,
    p_end_lat INTEGER,
    p_street_cat INTEGER[]
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                partition_id  TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects edges using both partition_id (100km) and cluster_id (10km)
    --              to minimize index scans and enable partition pruning.

DECLARE
    v_cluster_ids   TEXT[];
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
BEGIN
    --------------------------------------------------------------------------------------
    -- 1. derive cluster ids (10 km grid) ----------------------------------------------
    --------------------------------------------------------------------------------------
    -- generate_series builds the set efficiently without loop overhead
    SELECT ARRAY(
                   SELECT 'N' || LPAD(y::TEXT, 3, '0') || 'E' || LPAD(x::TEXT, 3, '0')
                   FROM GENERATE_SERIES(
                                (FLOOR(LEAST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 10000)::INTEGER - 1),
                                (FLOOR(GREATEST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 10000)::INTEGER + 1)
                        ) AS x,
                        GENERATE_SERIES(
                                (FLOOR(LEAST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 10000)::INTEGER - 1),
                                (FLOOR(GREATEST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 10000)::INTEGER + 1)
                        ) AS y
           )
    INTO v_cluster_ids;

    --------------------------------------------------------------------------------------
    -- 2. derive partition ids (100 km grid) -------------------------------------------
    --------------------------------------------------------------------------------------
    -- IMPORTANT: allows PostgreSQL to skip 99 % of the table partitions immediately.
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(
                                      (FLOOR(LEAST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR(GREATEST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS x,
                              GENERATE_SERIES(
                                      (FLOOR(LEAST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR(GREATEST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS y) generated
                            INNER JOIN pgr.partition p ON p.partition_id = generated.partition_id
           )
    INTO v_partition_ids;


    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            -- direct access to the physical partition table (e.g. pgr.edges_n04e01)
            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, speed_cat::INTEGER, street_cat::INTEGER,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            cluster_id, partition_id, x1, y1, x2, y2, geom
                     FROM pgr.edges_%s
                     WHERE cluster_id = ANY($1)
                       AND street_cat = ANY($2)',
                    LOWER(v_part)
                              );
        END LOOP;

    --------------------------------------------------------------------------------------
    -- 3. final query with two-stage filter --------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql USING v_cluster_ids, p_street_cat;

END;
$function$;


-- ==== functions/_candidate_edges_hull_costmatrix.sql ================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges_hull_costmatrix(
    p_x1 INTEGER[],
    p_y1 INTEGER[],
    p_street_cat INTEGER[],
    p_buffer_m INTEGER
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects the "outer" / main-network candidate edges for N points
    --              using a hull-shaped corridor instead of one large bounding box,
    --              built entirely from x1/y1 BTREE range predicates (no ST_Intersects/
    --              GiST on pgr.edges). The convex hull is computed only over the
    --              (few) input points, never over the edges table. For every
    --              relevant 100km partition, the hull edges are linearly clipped
    --              to that partition's x1-band to derive a tight, partition-specific
    --              y1 range instead of applying one global y1 range everywhere.
    --              Benchmarked against ST_Intersects-based bounding box and convex
    --              hull selection: ~25-50x faster at a comparable or better result
    --              size.

DECLARE
    v_hull_pts      GEOMETRY[];
    v_n             INTEGER;
    i               INTEGER;
    v_x1a           NUMERIC;
    v_y1a           NUMERIC;
    v_x1b           NUMERIC;
    v_y1b           NUMERIC;
    v_buffer_xy     INTEGER;
    v_global_x1_min INTEGER;
    v_global_x1_max INTEGER;
    v_global_y1_min INTEGER;
    v_global_y1_max INTEGER;
    v_partition_ids TEXT[];
    v_part          TEXT;
    v_part_x        INTEGER;
    v_part_y        INTEGER;
    v_band_x_min    NUMERIC;
    v_band_x_max    NUMERIC;
    v_band_y_min    NUMERIC;
    v_band_y_max    NUMERIC;
    v_clip_x_min    NUMERIC;
    v_clip_x_max    NUMERIC;
    v_ya            NUMERIC;
    v_yb            NUMERIC;
    v_t             NUMERIC;
    v_found         BOOLEAN;
    v_sql           TEXT := '';
BEGIN
    v_buffer_xy := ROUND(p_buffer_m::DOUBLE PRECISION / 100)::INTEGER;

    -- 1. convex hull ONLY over the input points (cheap, no access to pgr.edges)
    SELECT ARRAY_AGG(g.geom ORDER BY g.path)
    INTO v_hull_pts
    FROM (SELECT (dp).path, (dp).geom
          FROM (SELECT ST_DumpPoints(ST_ExteriorRing(ST_ConvexHull(
                  ST_Collect(ST_MakePoint(pt.x1, pt.y1))
                                                     ))) AS dp
                FROM UNNEST(p_x1, p_y1) AS pt(x1, y1)) s) g;
    v_n := COALESCE(ARRAY_LENGTH(v_hull_pts, 1), 0);

    -- 2. global bounding box (to determine partitions and as fallback with < 2 hull points)
    SELECT MIN(pt.x1) - v_buffer_xy,
           MAX(pt.x1) + v_buffer_xy,
           MIN(pt.y1) - v_buffer_xy,
           MAX(pt.y1) + v_buffer_xy
    INTO v_global_x1_min, v_global_x1_max, v_global_y1_min, v_global_y1_max
    FROM UNNEST(p_x1, p_y1) AS pt(x1, y1);

    -- 3. relevant partitions (100 km grid), as in _candidate_edges_isolines
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(FLOOR(v_global_x1_min::NUMERIC / 1000)::INTEGER,
                                              FLOOR(v_global_x1_max::NUMERIC / 1000)::INTEGER) AS x,
                              GENERATE_SERIES(FLOOR(v_global_y1_min::NUMERIC / 1000)::INTEGER,
                                              FLOOR(v_global_y1_max::NUMERIC / 1000)::INTEGER) AS y) gen
                            INNER JOIN pgr.partition p ON p.partition_id = gen.partition_id
           )
    INTO v_partition_ids;

    -- 4. per partition: clip the hull edges to the x1 band of the partition and
    --    derive a tight y1 range from it (pure arithmetic, no PostGIS on
    --    pgr.edges). Without a hit (e.g. with < 2 hull points): global range.
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            v_part_x := SUBSTRING(v_part FROM 5 FOR 2)::INTEGER;
            v_part_y := SUBSTRING(v_part FROM 2 FOR 2)::INTEGER;

            v_band_x_min := GREATEST(v_global_x1_min, v_part_x * 1000);
            v_band_x_max := LEAST(v_global_x1_max, (v_part_x + 1) * 1000);
            v_band_y_min := NULL;
            v_band_y_max := NULL;
            v_found := FALSE;

            IF v_n >= 2 THEN
                FOR i IN 1..(v_n - 1)
                    LOOP
                        v_x1a := ST_X(v_hull_pts[i]);
                        v_y1a := ST_Y(v_hull_pts[i]);
                        v_x1b := ST_X(v_hull_pts[i + 1]);
                        v_y1b := ST_Y(v_hull_pts[i + 1]);

                        IF v_x1a IS DISTINCT FROM v_x1b THEN
                            v_clip_x_min := GREATEST(v_band_x_min, LEAST(v_x1a, v_x1b));
                            v_clip_x_max := LEAST(v_band_x_max, GREATEST(v_x1a, v_x1b));
                            IF v_clip_x_min <= v_clip_x_max THEN
                                v_t := (v_clip_x_min - v_x1a) / (v_x1b - v_x1a);
                                v_ya := v_y1a + v_t * (v_y1b - v_y1a);
                                v_t := (v_clip_x_max - v_x1a) / (v_x1b - v_x1a);
                                v_yb := v_y1a + v_t * (v_y1b - v_y1a);
                                v_band_y_min := LEAST(COALESCE(v_band_y_min, v_ya), v_ya, v_yb);
                                v_band_y_max := GREATEST(COALESCE(v_band_y_max, v_ya), v_ya, v_yb);
                                v_found := TRUE;
                            END IF;
                        ELSIF v_x1a BETWEEN v_band_x_min AND v_band_x_max THEN
                            v_band_y_min := LEAST(COALESCE(v_band_y_min, v_y1a), v_y1a, v_y1b);
                            v_band_y_max := GREATEST(COALESCE(v_band_y_max, v_y1a), v_y1a, v_y1b);
                            v_found := TRUE;
                        END IF;
                    END LOOP;
            END IF;

            IF NOT v_found THEN
                v_band_y_min := v_global_y1_min;
                v_band_y_max := v_global_y1_max;
            ELSE
                v_band_y_min := v_band_y_min - v_buffer_xy;
                v_band_y_max := v_band_y_max + v_buffer_xy;
            END IF;

            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;
            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            street_cat::INTEGER, x1, y1, x2, y2
                     FROM pgr.edges_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s
                       AND street_cat = ANY(%L::INTEGER[])',
                    LOWER(v_part), ROUND(v_band_x_min), ROUND(v_band_x_max),
                    ROUND(v_band_y_min), ROUND(v_band_y_max), p_street_cat
                              );
        END LOOP;

    IF v_sql = '' THEN
        RETURN;
    END IF;

    RETURN QUERY EXECUTE
        'SELECT id, source, target, cost_time, cost_distance, cost_traffic,
                street_cat, x1, y1, x2, y2
         FROM (' || v_sql || ') s';
END;
$function$;


-- ==== functions/_candidate_edges_isolines.sql =======================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_radius_m INTEGER,
    p_street_cat INTEGER[]
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                partition_id  TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                source_id     DOUBLE PRECISION,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects edges using partition_id (100km) for partition pruning
    --              and x1/y1 range filter for spatial selection.
    --              No cluster array, no subcluster array.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;
BEGIN
    v_start_time = CLOCK_TIMESTAMP();
    --------------------------------------------------------------------------------------
    -- 1. derive partition ids (100 km grid) --------------------------------------------
    --------------------------------------------------------------------------------------
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(
                                      (FLOOR((p_lon - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lon + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS x,
                              GENERATE_SERIES(
                                      (FLOOR((p_lat - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lat + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS y) generated
                            INNER JOIN pgr.partition p ON p.partition_id = generated.partition_id
           )
    INTO v_partition_ids;
    --------------------------------------------------------------------------------------
    -- 2. dynamic SQL: one query per partition (partition pruning) ----------------------
    --------------------------------------------------------------------------------------
    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, speed_cat::INTEGER, street_cat::INTEGER,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            cluster_id, partition_id, x1, y1, x2, y2,
                            source_id,
                            geom
                     FROM pgr.edges_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s
                       AND street_cat = ANY($1)',
                    LOWER(v_part),
                    ROUND((p_lon - p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lon + p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lat - p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lat + p_radius_m) / 100.0)::INTEGER
                              );
        END LOOP;
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _candidate_edges_isolines: %', v_elapsed_time;
    --------------------------------------------------------------------------------------
    -- 3. final query -------------------------------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql USING p_street_cat;

END;
$function$;


-- ==== functions/_candidate_edges_radius_costmatrix.sql ==============================================================

CREATE OR REPLACE FUNCTION pgr._candidate_edges_radius_costmatrix(
    p_edges_table TEXT[],
    p_cluster_ids TEXT[],
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_street_cat INTEGER[],
    p_radius_m INTEGER
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Like pgr._candidate_edges, but with a CONFIGURABLE radius instead of a
    --              fixed 1000 m, and with a single street_cat list (= ANY(...)) instead of
    --              an inner/outer range (low/high) - suitable for the cost matrix, where all
    --              remaining modes (card, caro, care, no_mode, pedestrian) use the same
    --              street_cat list inside and outside. Called by _costmatrix_segment in a
    --              loop with growing radius until the network permitted for the selected
    --              mode ("selected network") actually returns an edge - the nearest street
    --              is thus always searched in the selected (mode-filtered) network, not
    --              the geometrically nearest street regardless of mode. Prevents a point
    --              (e.g. on a footway) from remaining unreachable for restrictive modes
    --              such as caro although a matching street lies further away.

DECLARE
    v_union_block TEXT;
BEGIN
    SELECT STRING_AGG(
                   FORMAT('SELECT * FROM pgr.%I', tbl),
                   ' UNION ALL '
           )
    INTO v_union_block
    FROM UNNEST(p_edges_table) AS tbl;

    RETURN QUERY
        EXECUTE FORMAT(
            $sql$
            WITH p AS (
                SELECT
                    %s AS p_center_x,
                    %s AS p_center_y,
                    %s::INTEGER AS p_radius_m,
                    100::INTEGER AS p_grid_size
            ),
            radius_in_cells AS (
                SELECT
                    p.p_center_x,
                    p.p_center_y,
                    p.p_radius_m,
                    p.p_grid_size,
                    (p.p_radius_m / p.p_grid_size)::INTEGER AS p_r_cells
                FROM p
            ),
            y_offsets AS (
                SELECT
                    r.p_center_x,
                    r.p_center_y,
                    r.p_r_cells,
                    dy.dy
                FROM radius_in_cells r
                CROSS JOIN GENERATE_SERIES(-r.p_r_cells, r.p_r_cells) AS dy(dy)
            ),
            x_ranges AS (
                SELECT
                    yo.p_center_x,
                    yo.p_center_y,
                    yo.dy,
                    FLOOR(SQRT(
                        (yo.p_r_cells::DOUBLE PRECISION * yo.p_r_cells) -
                        (yo.dy::DOUBLE PRECISION   * yo.dy)
                    ))::INTEGER AS dx_max
                FROM y_offsets yo
            ),
            selected_grids AS (
                SELECT
                    xr.p_center_x + dx.dx AS sg_grid_x,
                    xr.p_center_y + xr.dy AS sg_grid_y
                FROM x_ranges xr
                CROSS JOIN LATERAL GENERATE_SERIES(-xr.dx_max, xr.dx_max) AS dx(dx)
            ),
            all_edges AS (
            %s
            )
            SELECT DISTINCT ON (e.id)
                e.id,
                e.source,
                e.target,
                e.speed_cat::INTEGER,
                e.street_cat::INTEGER,
                e.cost_time::INTEGER,
                e.cost_distance::INTEGER,
                e.cost_traffic::INTEGER,
                e.cluster_id,
                e.x1,
                e.y1,
                e.x2,
                e.y2,
                e.geom
            FROM selected_grids sg
            INNER JOIN all_edges e
                ON sg.sg_grid_x = e.x1 AND sg.sg_grid_y = e.y1
            WHERE e.street_cat = ANY(%L::INTEGER[])
              AND e.cluster_id = ANY(%L::TEXT[])
            ORDER BY e.id, sg.sg_grid_y, sg.sg_grid_x
            $sql$,
            p_center_x,
            p_center_y,
            p_radius_m,
            v_union_block,
            p_street_cat,
            p_cluster_ids
                );
END;
$function$;


-- ==== functions/_candidate_grids_isolines.sql =======================================================================

CREATE OR REPLACE FUNCTION pgr._candidate_grids_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_radius_m INTEGER
)
    RETURNS TABLE
            (
                id                      BIGINT,
                source                  BIGINT,
                target                  BIGINT,
                source_id               DOUBLE PRECISION,
                gitter_id_              TEXT,
                grid_1km                TEXT,
                grid_time               INTEGER,
                grid_distance           INTEGER,
                grid_traffic            INTEGER,
                grid_factor             DOUBLE PRECISION,
                distance_to_grid_factor DOUBLE PRECISION,
                cost_time               INTEGER,
                cost_distance           INTEGER,
                cost_traffic            INTEGER,
                street_cat              INTEGER,
                x1                      INTEGER,
                y1                      INTEGER,
                grid_geom               geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects grid cells using partition_id (100km) for partition pruning
    --              and x1/y1 range filter (100m grid) for spatial selection.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
    v_x1_min        INTEGER;
    v_x1_max        INTEGER;
    v_y1_min        INTEGER;
    v_y1_max        INTEGER;
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;
BEGIN
    --------------------------------------------------------------------------------------
    -- 1. range limits on the 100 m grid -----------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time = CLOCK_TIMESTAMP();
    v_x1_min := FLOOR((p_lon - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_x1_max := CEIL((p_lon + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_min := FLOOR((p_lat - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_max := CEIL((p_lat + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;

    --------------------------------------------------------------------------------------
    -- 2. derive partition ids (100 km grid) ------------------------------------------
    --------------------------------------------------------------------------------------
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(
                                      (FLOOR((p_lon - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lon + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS x,
                              GENERATE_SERIES(
                                      (FLOOR((p_lat - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lat + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS y) generated
                            INNER JOIN pgr.partition p ON p.partition_id = generated.partition_id
           )
    INTO v_partition_ids;

    --------------------------------------------------------------------------------------
    -- 3. dynamic SQL: one query per partition (partition pruning) ----------------------
    --------------------------------------------------------------------------------------
    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, source_id, gitter_id_, grid_1km,
                            grid_time, grid_distance, grid_traffic,
                            grid_factor, distance_to_grid_factor,
                            cost_time, cost_distance, cost_traffic,
                            street_cat::INTEGER,
                            x1, y1,
                            grid_geom
                     FROM pgr.grids_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s',
                    LOWER(v_part),
                    v_x1_min,
                    v_x1_max,
                    v_y1_min,
                    v_y1_max
                              );
        END LOOP;
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for candidate_grids_isolines: %', v_elapsed_time;
    --------------------------------------------------------------------------------------
    -- 4. final query -------------------------------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql;

END;
$function$;


-- ==== functions/_catchment_isolines.sql =============================================================================

CREATE OR REPLACE FUNCTION pgr._catchment_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_direction TEXT,
    p_inner_limit INTEGER DEFAULT 1500
)
    RETURNS geometry
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns catchment area polygon based on grid cells.
    --              Builds on _grids_isolines, applies triple buffer smoothing.
    --              Dynamic factor_buffer calculated from area of union.

DECLARE
    v_catchment    GEOMETRY;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    SELECT st_makepolygon(st_exteriorring(geom)) AS geom
    INTO v_catchment
    FROM (SELECT (st_dump(
            st_buffer(
                    st_buffer(
                            st_buffer(geom::GEOGRAPHY, factor_buffer / 2),
                            factor_buffer * -1
                    ),
                    factor_buffer / 2
            )::GEOMETRY
                  )).geom AS geom
          FROM (SELECT st_union(grid_geom)                                        AS geom,
                       ROUND(SQRT(st_area(st_union(grid_geom)::GEOGRAPHY))) / 7.5 AS factor_buffer
                FROM pgr._grids_isolines(
                        p_lon,
                        p_lat,
                        p_buffer_value,
                        p_calculation_type,
                        p_mode_of_transport,
                        p_direction,
                        p_inner_limit
                     )) tes) collect
    ORDER BY st_area(geom) DESC
    LIMIT 1;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _catchment_isolines: %', v_elapsed_time;

    RETURN v_catchment;

END;
$function$;


-- ==== functions/_catchment_isolines_static.sql ======================================================================

CREATE OR REPLACE FUNCTION pgr._catchment_isolines_static(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_direction TEXT,
    p_inner_limit INTEGER DEFAULT 1500
)
    RETURNS geometry
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns catchment area polygon based on grid cells.
    --              Builds on _grids_isolines, applies triple buffer smoothing.
    --              Dynamic factor_buffer calculated from area of union.

DECLARE
    v_catchment     GEOMETRY;
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;
    v_factor_buffer DOUBLE PRECISION DEFAULT 100;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    SELECT st_makepolygon(st_exteriorring(geom)) AS geom
    INTO v_catchment
    FROM (SELECT (st_dump(
            st_buffer(
                    st_buffer(
                            st_buffer(geom::GEOGRAPHY, v_factor_buffer / 2),
                            v_factor_buffer * -1
                    ),
                    v_factor_buffer / 2
            )::GEOMETRY
                  )).geom AS geom
          FROM (SELECT st_union(grid_geom) AS geom
                FROM pgr._grids_isolines(
                        p_lon,
                        p_lat,
                        p_buffer_value,
                        p_calculation_type,
                        p_mode_of_transport,
                        p_direction,
                        p_inner_limit
                     )) tes) collect
    ORDER BY st_area(geom) DESC
    LIMIT 1;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _catchment_isolines: %', v_elapsed_time;

    RETURN v_catchment;

END;
$function$;


-- ==== functions/_check_input.sql ====================================================================================

CREATE OR REPLACE FUNCTION pgr._check_input(
    lon DOUBLE PRECISION,
    lat DOUBLE PRECISION,
    mode_of_transport TEXT,
    calculation_type TEXT,
    direction TEXT
)
    RETURNS TEXT
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
DECLARE
    ctrycode     TEXT;
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();
    ----------------------------------------------------------------------------------------------------------
    -- DESCRIPTION : checks the input, if it's correct.
    -----------------------------------------------------------------------------------------------------------
/*
 The function will check the input for the main function. If the input is not correct the function will be stopped and
 the user gets an error message.
 */
    IF mode_of_transport NOT IN ('card', 'car', 'caro', 'care', 'pedestrian', 'no_mode')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''car'', ''card'',''care'', ''caro'', ''pedestrian'' or ''no_mode''.';
    ELSEIF calculation_type NOT IN ('distance', 'time', 'traffic')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'', ''time'' or ''traffic''.';
    ELSEIF direction NOT IN ('from', 'to')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Direction should be ''from'' or ''to''.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(lon, lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The startpoint is outside the network.';
    END IF;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;


-- ==== functions/_check_input_costmatrix.sql =========================================================================

CREATE OR REPLACE FUNCTION pgr._check_input_costmatrix(
    p_input_table TEXT,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT
)
    RETURNS TEXT
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION : checks the input for cgo_costmatrix, if it's correct.
/*
 The function will check the input for cgo_costmatrix. If the input is not correct the function will be
 stopped and the user gets an error message.
 */
DECLARE
    ctrycode           TEXT;
    v_x_type           TEXT;
    v_y_type           TEXT;
    v_outside_list     TEXT;
    v_street_cat       INTEGER[];
    v_unreachable_list TEXT;
    start_time         TIMESTAMP;
    end_time           TIMESTAMP;
    elapsed_time       INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();

    -- 1. parameter domains (as _check_input / _check_input_routes)
    IF p_mode_of_transport NOT IN ('card', 'care', 'caro', 'no_mode', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''card'', ''care'', ''caro'', ''no_mode'' or ''pedestrian''.';
    ELSEIF p_calculation_type NOT IN ('distance', 'time')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'' or ''time''.';
    END IF;

    -- 2. input_table: required columns with the EXACT names node_id, x, y.
    --    (Positional column aliases FROM ... AS t(node_id,x,y) rename only the
    --    first 3 columns - a 4th or later column with the same name (e.g. a
    --    column "y") led to "column reference is not unique". Fixed required
    --    names are more robust and simpler.)
    IF TO_REGCLASS(p_input_table) IS NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s does not exist.', p_input_table);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = p_input_table::regclass
                     AND attname = 'node_id'
                     AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = p_input_table::regclass
                         AND attname = 'x'
                         AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = p_input_table::regclass
                         AND attname = 'y'
                         AND NOT attisdropped)
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s must contain columns named node_id, x and y.', p_input_table);
    END IF;

    SELECT a.atttypid::regtype::TEXT
    INTO v_x_type
    FROM pg_attribute a
    WHERE a.attrelid = p_input_table::regclass
      AND a.attname = 'x'
      AND NOT a.attisdropped;

    SELECT a.atttypid::regtype::TEXT
    INTO v_y_type
    FROM pg_attribute a
    WHERE a.attrelid = p_input_table::regclass
      AND a.attname = 'y'
      AND NOT a.attisdropped;

    IF v_x_type NOT IN ('double precision', 'real', 'numeric')
        OR v_y_type NOT IN ('double precision', 'real', 'numeric')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'Columns x and y of %s must be of type double precision, real or numeric.',
                    p_input_table);
    END IF;

    -- 3. All points must lie within the network. Affected node_id(s) are named
    --    in the error message (consistent with section 4).
    EXECUTE FORMAT(
            'SELECT STRING_AGG(t.node_id::text, '', '' ORDER BY t.node_id) FROM %s AS t
             WHERE NOT EXISTS (
                 SELECT 1 FROM pgr.cluster c
                 WHERE st_within(st_setsrid(st_makepoint(t.x, t.y), 4326), c.geom)
             )', p_input_table::regclass
            ) INTO v_outside_list;

    IF v_outside_list IS NOT NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'The following node_id(s) in %I are outside the network: %s.',
                    p_input_table, v_outside_list);
    END IF;

    -- 4. Reachability: every point must find at least one edge of the selected
    --    (mode-filtered) network within the standard search radius (1000 m, as
    --    _starting_segment/_ending_segment/_costmatrix_segment). Otherwise the
    --    point would remain isolated and unreachable in the result -
    --    _costmatrix_segment deliberately returns NO rows for it (no artificial
    --    zero-cost connector of arbitrary length), so this must be caught here
    --    BEFOREHAND with a clear error message.
    SELECT CASE p_mode_of_transport
               WHEN 'card' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'caro' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,13]
               WHEN 'care' THEN ARRAY [-1,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'no_mode' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14]
               WHEN 'pedestrian' THEN ARRAY [-1,5,4,6,7,8,9,10,11,12,13,14]
               END
    INTO v_street_cat;

    EXECUTE FORMAT(
            'WITH pts AS (
                 SELECT
                     t.node_id,
                     ROUND(ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lon,
                     ROUND(ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lat
                 FROM %s AS t
             ),
             checked AS (
                 SELECT p.node_id,
                        EXISTS (
                            SELECT 1
                            FROM pgr._candidate_edges_radius_costmatrix(
                                     ARRAY[''edges_n'' || SUBSTR(p.lat::TEXT, 1, 2) || ''e'' || SUBSTR(p.lon::TEXT, 1, 2)],
                                     ARRAY[UPPER(''N'' || SUBSTR(p.lat::TEXT, 1, 3) || ''E'' || SUBSTR(p.lon::TEXT, 1, 3))],
                                     ROUND(p.lon::DOUBLE PRECISION / 100)::INTEGER,
                                     ROUND(p.lat::DOUBLE PRECISION / 100)::INTEGER,
                                     %L::INTEGER[], 1000
                                 ) c
                        ) AS reachable
                 FROM pts p
             )
             SELECT STRING_AGG(node_id::text, '', '' ORDER BY node_id) FROM checked WHERE NOT reachable',
            p_input_table::regclass, v_street_cat
            ) INTO v_unreachable_list;

    IF v_unreachable_list IS NOT NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'The following node_id(s) have no street matching mode_of_transport %s within 1000 m: %s.',
                    p_mode_of_transport, v_unreachable_list);
    END IF;

    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input_costmatrix: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;


-- ==== functions/_check_input_routes.sql =============================================================================

CREATE OR REPLACE FUNCTION pgr._check_input_routes(
    start_lon DOUBLE PRECISION,
    start_lat DOUBLE PRECISION,
    end_lon DOUBLE PRECISION,
    end_lat DOUBLE PRECISION,
    mode_of_transport TEXT,
    calculation_type TEXT
)
    RETURNS TEXT
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
DECLARE
    ctrycode     TEXT;
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();
    ----------------------------------------------------------------------------------------------------------
    -- DESCRIPTION : checks the input, if it's correct.
    -----------------------------------------------------------------------------------------------------------
/*
 The function will check the input for the main function. If the input is not correct the function will be stopped and
 the user gets an error message.
 */
    IF mode_of_transport NOT IN ('card', 'car', 'caro', 'care', 'carl', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''car'', ''card'',''care'', ''carl'', ''caro'' or ''pedestrian''.';
    ELSEIF calculation_type NOT IN ('distance', 'time', 'traffic')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'', ''time''or ''traffic''.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(start_lon, start_lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The startpoint is outside the network.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(end_lon, end_lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The endpoint is outside the network.';
    END IF;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input_routes: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;


-- ==== functions/_costmatrix_points.sql ==============================================================================

CREATE OR REPLACE FUNCTION pgr._costmatrix_points(
    p_input_table TEXT
)
    RETURNS TABLE
            (
                node_id     TEXT,
                lon         INTEGER,
                lat         INTEGER,
                x1          INTEGER,
                y1          INTEGER,
                point_id    BIGINT,
                lot_id      BIGINT,
                id_offset   BIGINT,
                edges_table TEXT,
                cluster_id  TEXT
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Central, DETERMINISTIC point_id/lot_id assignment for the N points of
    --              input_table (columns node_id, x, y - EXACT names required, ensured by
    --              pgr._check_input_costmatrix, which is called beforehand). Called both by
    --              _preselection_costmatrix (to build vids/edges_sql) and by cgo_costmatrix
    --              (to translate pgr_astarcostmatrix's start_vid/end_vid back to the
    --              original node_id) - both calls MUST return exactly the same assignment,
    --              otherwise result rows are assigned to the wrong node_id.
    --              Therefore ROW_NUMBER() explicitly uses ORDER BY node_id - a CTE or
    --              ROW_NUMBER() without ORDER BY does NOT guarantee a repeatable order
    --              between two separate executions of the same query (e.g. the physical
    --              scan order of a table can change after autovacuum).
    --              Materialises the result in a TEMPORARY TABLE (created anew with every
    --              call, no caching across calls - avoids reusing a stale state from an
    --              earlier cgo_costmatrix call in the same transaction). Needed only once
    --              per cgo_costmatrix call (not per point), so unproblematic here.
    --              point_id := rn (1..N), lot_id := rn + 10000 - collision-free, since real
    --              graph node ids in pgr.edges are in the billions. node_id is returned as
    --              TEXT (the original type in input_table can be anything).

BEGIN
    DROP TABLE IF EXISTS tmp_costmatrix_points;
    EXECUTE FORMAT(
            'CREATE TEMP TABLE tmp_costmatrix_points AS
             SELECT
                 node_id::TEXT AS node_id, lon, lat, x1, y1,
                 rn::BIGINT                            AS point_id,
                 (rn + 10000)::BIGINT                  AS lot_id,
                 (rn * 1000)::BIGINT                   AS id_offset,
                 ''edges_n'' || SUBSTR(lat::TEXT,1,2) || ''e'' || SUBSTR(lon::TEXT,1,2)          AS edges_table,
                 UPPER(''N'' || SUBSTR(lat::TEXT,1,3) || ''E'' || SUBSTR(lon::TEXT,1,3))         AS cluster_id
             FROM (
                 SELECT
                     t.node_id,
                     p3035.lon, p3035.lat,
                     ROUND(p3035.lon::DOUBLE PRECISION / 100)::INTEGER AS x1,
                     ROUND(p3035.lat::DOUBLE PRECISION / 100)::INTEGER AS y1,
                     ROW_NUMBER() OVER (ORDER BY t.node_id) AS rn
                 FROM %s AS t
                 CROSS JOIN LATERAL (
                     SELECT ROUND(ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lon,
                            ROUND(ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lat
                 ) p3035
             ) raw_pts',
            p_input_table::regclass
            );

    RETURN QUERY SELECT * FROM tmp_costmatrix_points;
END;
$function$;


-- ==== functions/_costmatrix_segment.sql =============================================================================

CREATE OR REPLACE FUNCTION pgr._costmatrix_segment(
    p_point_id BIGINT,
    p_lot_id BIGINT,
    p_id_offset BIGINT,
    lon INTEGER,
    lat INTEGER,
    p_street_cat INTEGER[]
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                split_edge_id BIGINT
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Unified, bidirectional version of _starting_segment and
    --              _ending_segment. Snaps ONE input point to the nearest street segment
    --              of the SELECTED (mode-filtered) network and returns synthetic edges
    --              that connect the point to the network in BOTH directions, so that the
    --              same virtual node (p_point_id) can be used both as start_vid and as
    --              end_vid in pgr_astarcostmatrix.
    --              p_street_cat is passed directly by the caller (already resolved; no
    --              mode_of_transport -> street_cat derivation here, since all remaining
    --              modes (card/caro/care/no_mode/pedestrian) use the same list inside and
    --              outside).
    --              Search radius FIXED at 1000 m, as in _starting_segment/_ending_segment
    --              (_candidate_edges) - deliberately NOT extended: point_connector has
    --              cost_time/cost_distance/cost_traffic = 0, so a larger radius would fake
    --              a connection of several km at cost 0 and distort the cost matrix. If no
    --              edge matching the mode is found within 1000 m, the function returns NO
    --              rows (as _starting_segment/_ending_segment) - reachability is checked
    --              BEFOREHAND in pgr._check_input_costmatrix (clear error message with the
    --              affected node_id instead of silently skipping or wrongly connecting
    --              the point).
    --              Returns NO geometry (geom), since pgr_astarcostmatrix (only_cost=true)
    --              only needs id, source, target, cost, reverse_cost, x1, y1, x2, y2 and
    --              cgo_costmatrix returns no geometries.
    --              p_point_id/p_lot_id: virtual node ids, unique per input point, assigned
    --              by the caller.
    --              p_id_offset: avoids collisions of the 'id' column (synthetic edge ids)
    --              between several points when the caller combines several calls with
    --              UNION ALL.
    --              Point and snap point coordinates use the 100 m grid of the network
    --              (ROUND(x / 100)), so that the A* heuristic is correct.

DECLARE
    v_point3035       GEOMETRY;
    v_center_x        INTEGER;
    v_center_y        INTEGER;
    v_edges_table     TEXT[];
    v_cluster_ids     TEXT[];
    v_radius CONSTANT INTEGER := 1000;
BEGIN
    SELECT st_setsrid(st_makepoint(lon, lat), pgr._srid()) INTO v_point3035;

    SELECT ROUND(lon::DOUBLE PRECISION / 100)::INTEGER INTO v_center_x;
    SELECT ROUND(lat::DOUBLE PRECISION / 100)::INTEGER INTO v_center_y;

    -- derive partition/cluster names from the 4 corners of the search radius
    -- (as in _starting_segment/_ending_segment)
    SELECT ARRAY_AGG(DISTINCT 'edges_n' || SUBSTR(y::TEXT, 1, 2) || 'e' || SUBSTR(x::TEXT, 1, 2))
    INTO v_edges_table
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    SELECT ARRAY_AGG(DISTINCT UPPER('N' || SUBSTR(y::TEXT, 1, 3) || 'E' || SUBSTR(x::TEXT, 1, 3)))
    INTO v_cluster_ids
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    RETURN QUERY
        WITH pointgeom AS (SELECT v_point3035 AS geom),

             -- x1/y1/x2/y2 use the 100 m grid as in pgr.edges (ROUND(x / 100)), also for the point and the
             -- snap point; otherwise pgr_astarCostMatrix misestimates start and end by a factor of 100.
             candidate_edges AS (SELECT ce.id,
                                        ce.source,
                                        ce.target,
                                        ce.speed_cat,
                                        ce.street_cat,
                                        ce.cost_time,
                                        ce.cost_distance,
                                        ce.cost_traffic,
                                        ce.cluster_id,
                                        ce.x1,
                                        ce.y1,
                                        ce.x2,
                                        ce.y2,
                                        ce.geom
                                 FROM pgr._candidate_edges_radius_costmatrix(
                                              v_edges_table, v_cluster_ids, v_center_x, v_center_y,
                                              p_street_cat, v_radius) ce),

             closest_points AS (SELECT e.id                                                        AS cp_id,
                                       e.source                                                    AS cp_source,
                                       e.target                                                    AS cp_target,
                                       e.street_cat                                                AS cp_street_cat,
                                       e.cost_time                                                 AS cp_cost_time,
                                       e.cost_distance                                             AS cp_cost_distance,
                                       e.cost_traffic                                              AS cp_cost_traffic,
                                       e.speed_cat                                                 AS cp_speed_cat,
                                       e.x1                                                        AS cp_x1,
                                       e.y1                                                        AS cp_y1,
                                       e.x2                                                        AS cp_x2,
                                       e.y2                                                        AS cp_y2,
                                       e.geom                                                      AS cp_edge_geom,
                                       st_closestpoint(e.geom, p.geom)                             AS cp_snap_geom,
                                       st_distance(e.geom, p.geom)                                 AS cp_distance,
                                       st_linelocatepoint(e.geom, st_closestpoint(e.geom, p.geom)) AS cp_fraction
                                FROM candidate_edges e,
                                     pointgeom p),

             min_distance AS (SELECT MIN(cp.cp_distance) AS md_dist FROM closest_points cp),

             nearest AS (SELECT cp.*
                         FROM closest_points cp,
                              min_distance md
                         WHERE cp.cp_distance = md.md_dist
                         LIMIT 1),

             reverse_nearest AS (SELECT cp.*
                                 FROM closest_points cp,
                                      nearest n
                                 WHERE cp.cp_id != n.cp_id
                                   AND st_equals(st_startpoint(cp.cp_edge_geom), st_endpoint(n.cp_edge_geom))
                                   AND st_equals(st_endpoint(cp.cp_edge_geom), st_startpoint(n.cp_edge_geom))
                                 LIMIT 1),

             snap_decision AS (SELECT CASE
                                          WHEN n.cp_fraction <= 0.001 THEN 'source'
                                          WHEN n.cp_fraction >= 0.999 THEN 'target'
                                          ELSE 'split'
                                          END AS sd_snap_case,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_source
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_target
                                          ELSE NULL
                                          END AS sd_snap_node_id,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_x1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_x2
                                          ELSE NULL
                                          END AS sd_snap_x,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_y1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_y2
                                          ELSE NULL
                                          END AS sd_snap_y
                               FROM nearest n),

             point_connector AS (SELECT 1                                                              AS sort_order,
                                        p_point_id                                                     AS source,
                                        p_lot_id                                                       AS target,
                                        NULL::INTEGER                                                  AS street_cat,
                                        0::INTEGER                                                     AS cost_time,
                                        0::INTEGER                                                     AS cost_distance,
                                        0::INTEGER                                                     AS cost_traffic,
                                        ROUND(st_x((SELECT pg.geom FROM pointgeom pg)) / 100)::INTEGER AS x1,
                                        ROUND(st_y((SELECT pg.geom FROM pointgeom pg)) / 100)::INTEGER AS y1,
                                        CASE
                                            WHEN sd.sd_snap_case = 'split' THEN ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER
                                            ELSE sd.sd_snap_x END                                      AS x2,
                                        CASE
                                            WHEN sd.sd_snap_case = 'split' THEN ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER
                                            ELSE sd.sd_snap_y END                                      AS y2,
                                        NULL::BIGINT                                                   AS split_edge_id
                                 FROM nearest n,
                                      snap_decision sd

                                 UNION ALL

                                 SELECT 1                                                              AS sort_order,
                                        p_lot_id                                                       AS source,
                                        p_point_id                                                     AS target,
                                        NULL::INTEGER                                                  AS street_cat,
                                        0::INTEGER                                                     AS cost_time,
                                        0::INTEGER                                                     AS cost_distance,
                                        0::INTEGER                                                     AS cost_traffic,
                                        CASE
                                            WHEN sd.sd_snap_case = 'split' THEN ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER
                                            ELSE sd.sd_snap_x END                                      AS x1,
                                        CASE
                                            WHEN sd.sd_snap_case = 'split' THEN ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER
                                            ELSE sd.sd_snap_y END                                      AS y1,
                                        ROUND(st_x((SELECT pg.geom FROM pointgeom pg)) / 100)::INTEGER AS x2,
                                        ROUND(st_y((SELECT pg.geom FROM pointgeom pg)) / 100)::INTEGER AS y2,
                                        NULL::BIGINT                                                   AS split_edge_id
                                 FROM nearest n,
                                      snap_decision sd),

             split_segments AS (SELECT 2                                          AS sort_order,
                                       n.cp_source                                AS source,
                                       p_lot_id                                   AS target,
                                       n.cp_street_cat::INTEGER                   AS street_cat,
                                       CASE
                                           WHEN n.cp_cost_time < 100000 THEN ROUND(n.cp_cost_time *
                                                                                   st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                                                                   NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER              AS cost_time,
                                       CASE
                                           WHEN n.cp_cost_distance < 100000 THEN ROUND(n.cp_cost_distance *
                                                                                       st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE n.cp_cost_distance
                                           END::INTEGER                           AS cost_distance,
                                       CASE
                                           WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                                      st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                                                                      NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER              AS cost_traffic,
                                       n.cp_x1                                    AS x1,
                                       n.cp_y1                                    AS y1,
                                       ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER AS x2,
                                       ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER AS y2,
                                       n.cp_id                                    AS split_edge_id
                                FROM nearest n,
                                     snap_decision sd
                                WHERE sd.sd_snap_case = 'split'

                                UNION ALL

                                SELECT 2                                          AS sort_order,
                                       p_lot_id                                   AS source,
                                       n.cp_target                                AS target,
                                       n.cp_street_cat::INTEGER                   AS street_cat,
                                       CASE
                                           WHEN n.cp_cost_time < 100000 THEN ROUND(n.cp_cost_time *
                                                                                   st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                                                                   NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER              AS cost_time,
                                       CASE
                                           WHEN n.cp_cost_distance < 100000 THEN ROUND(n.cp_cost_distance *
                                                                                       st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE n.cp_cost_distance
                                           END::INTEGER                           AS cost_distance,
                                       CASE
                                           WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                                      st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                                                                      NULLIF(st_length(n.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER              AS cost_traffic,
                                       ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER AS x1,
                                       ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER AS y1,
                                       n.cp_x2                                    AS x2,
                                       n.cp_y2                                    AS y2,
                                       n.cp_id                                    AS split_edge_id
                                FROM nearest n,
                                     snap_decision sd
                                WHERE sd.sd_snap_case = 'split'

                                UNION ALL

                                SELECT 2                                           AS sort_order,
                                       p_lot_id                                    AS source,
                                       rn.cp_source                                AS target,
                                       rn.cp_street_cat::INTEGER                   AS street_cat,
                                       CASE
                                           WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                                    st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                                    NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER               AS cost_time,
                                       CASE
                                           WHEN rn.cp_cost_distance < 100000 THEN ROUND(rn.cp_cost_distance *
                                                                                        st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE rn.cp_cost_distance
                                           END::INTEGER                            AS cost_distance,
                                       CASE
                                           WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                                       st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                                       NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER               AS cost_traffic,
                                       ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER AS x1,
                                       ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER AS y1,
                                       rn.cp_x1                                    AS x2,
                                       rn.cp_y1                                    AS y2,
                                       rn.cp_id                                    AS split_edge_id
                                FROM reverse_nearest rn,
                                     snap_decision sd
                                WHERE sd.sd_snap_case = 'split'

                                UNION ALL

                                SELECT 2                                           AS sort_order,
                                       rn.cp_target                                AS source,
                                       p_lot_id                                    AS target,
                                       rn.cp_street_cat::INTEGER                   AS street_cat,
                                       CASE
                                           WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                                    st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                                    NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER               AS cost_time,
                                       CASE
                                           WHEN rn.cp_cost_distance < 100000 THEN ROUND(rn.cp_cost_distance *
                                                                                        st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE rn.cp_cost_distance
                                           END::INTEGER                            AS cost_distance,
                                       CASE
                                           WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                                       st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                                       NULLIF(st_length(rn.cp_edge_geom), 0))
                                           ELSE 1000000 END::INTEGER               AS cost_traffic,
                                       rn.cp_x2                                    AS x1,
                                       rn.cp_y2                                    AS y1,
                                       ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER AS x2,
                                       ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER AS y2,
                                       rn.cp_id                                    AS split_edge_id
                                FROM reverse_nearest rn,
                                     snap_decision sd
                                WHERE sd.sd_snap_case = 'split'),

             snap_segments AS (SELECT 2                        AS sort_order,
                                      p_lot_id                 AS source,
                                      e.target                 AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.source = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target')

                               UNION ALL

                               SELECT 2                        AS sort_order,
                                      e.source                 AS source,
                                      p_lot_id                 AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.target = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target'))

        SELECT ROW_NUMBER() OVER (ORDER BY u.sort_order, u.source, u.target) + p_id_offset,
               u.source,
               u.target,
               u.cost_time,
               u.cost_distance,
               u.cost_traffic,
               u.street_cat,
               u.x1,
               u.y1,
               u.x2,
               u.y2,
               u.split_edge_id
        FROM (SELECT *
              FROM point_connector
              UNION ALL
              SELECT *
              FROM split_segments
              UNION ALL
              SELECT *
              FROM snap_segments) u
        ORDER BY u.sort_order, u.source, u.target;
END;
$function$;


-- ==== functions/_create_dynamical_grids.sql =========================================================================

CREATE OR REPLACE FUNCTION pgr._create_dynamical_grids(
    p_id BIGINT,
    p_cost INTEGER,
    p_x1 BIGINT,
    p_y1 BIGINT,
    p_x2 BIGINT,
    p_y2 BIGINT,
    p_geom geometry,
    p_direction TEXT
)
    RETURNS TABLE
            (
                edge_id    BIGINT,
                seq        INTEGER,
                gitter_id_ TEXT,
                agg_cost   INTEGER,
                geom       geometry
            )
    LANGUAGE plpgsql
AS
$function$
DECLARE
    v_res       INT := 100;
    v_x1        BIGINT;
    v_y1        BIGINT;
    v_x2        BIGINT;
    v_y2        BIGINT;
    v_total_len DOUBLE PRECISION;
    v_cf_cost   DOUBLE PRECISION;
    v_geom      GEOMETRY; -- geometry, reversed if necessary
BEGIN
    v_x1 := CASE WHEN p_x1 < 1000000 THEN p_x1 * 100 ELSE p_x1 END;
    v_y1 := CASE WHEN p_y1 < 1000000 THEN p_y1 * 100 ELSE p_y1 END;
    v_x2 := CASE WHEN p_x2 < 1000000 THEN p_x2 * 100 ELSE p_x2 END;
    v_y2 := CASE WHEN p_y2 < 1000000 THEN p_y2 * 100 ELSE p_y2 END;

    /*
     * For 'to': reverse the geometry so that ST_LineLocatePoint
     * calculates the position along the opposite direction
     * and sorting and cost calculation are correct.
     */
    v_geom := CASE
                  WHEN p_direction = 'to' THEN st_reverse(p_geom)
                  ELSE p_geom
        END;

    v_total_len := st_length(v_geom);

    v_cf_cost := CASE
                     WHEN p_cost > 0 AND v_total_len > 0
                         THEN p_cost::DOUBLE PRECISION / v_total_len
                     ELSE NULL
        END;

    RETURN QUERY
        WITH bbox AS (SELECT FLOOR(st_xmin(v_geom) / v_res)::BIGINT * v_res AS xmin,
                             FLOOR(st_ymin(v_geom) / v_res)::BIGINT * v_res AS ymin,
                             FLOOR(st_xmax(v_geom) / v_res)::BIGINT * v_res AS xmax,
                             FLOOR(st_ymax(v_geom) / v_res)::BIGINT * v_res AS ymax),
             candidates AS (SELECT x.val AS cx, y.val AS cy
                            FROM bbox,
                                 GENERATE_SERIES(bbox.xmin, bbox.xmax, v_res) AS x(val),
                                 GENERATE_SERIES(bbox.ymin, bbox.ymax, v_res) AS y(val)),
             cells AS (SELECT c.cx,
                              c.cy,
                              SUBSTR(c.cx::TEXT, 1, 5)                                 AS cx_5,
                              SUBSTR(c.cy::TEXT, 1, 5)                                 AS cy_5,
                              st_makeenvelope(c.cx, c.cy,
                                              c.cx + v_res, c.cy + v_res, pgr._srid()) AS cell_geom,
                              st_linelocatepoint(
                                      v_geom,
                                      st_closestpoint(
                                              v_geom,
                                              st_setsrid(
                                                      st_makepoint(c.cx + v_res / 2.0,
                                                                   c.cy + v_res / 2.0), pgr._srid())
                                      )
                              )                                                        AS frac
                       FROM candidates c
                       WHERE st_intersects(
                                     v_geom,
                                     st_makeenvelope(c.cx, c.cy,
                                                     c.cx + v_res, c.cy + v_res, pgr._srid())
                             )),
             ordered AS (SELECT ROW_NUMBER() OVER (ORDER BY frac)::INT AS seq,
                                cx,
                                cy,
                                cx_5,
                                cy_5,
                                cell_geom,
                                frac * v_total_len                     AS dist_to_center
                         FROM cells)
        SELECT p_id,
               o.seq,
               '100mN' || o.cy_5 || 'E' || o.cx_5           AS gitter_id_,
               ROUND(o.dist_to_center * v_cf_cost)::INTEGER AS agg_cost,
               o.cell_geom
        FROM ordered o;

END;
$function$;


-- ==== functions/_driving_distance_isolines.sql ======================================================================

CREATE OR REPLACE FUNCTION pgr._driving_distance_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_direction TEXT,
    p_inner_limit INTEGER DEFAULT 1500
)
    RETURNS TABLE
            (
                edge_node SMALLINT,
                seq       BIGINT,
                id        BIGINT,
                source    BIGINT,
                target    BIGINT,
                cost      INTEGER,
                agg_cost  INTEGER,
                geom      geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Central helper function for isoline calculation.
    --              Calls pgr_drivingdistance once via CTE within EXECUTE.
    --              _preselection_isolines called twice: once for pgr_drivingdistance,
    --              once for edge join. No temporary tables.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_new_source           TEXT;
    v_new_target           TEXT;
    v_new_cost             TEXT;
    v_reverse_cost         TEXT;
    v_cost_expression      TEXT;
    v_cost_expression_edge TEXT;
    v_start_time           TIMESTAMP;
    v_end_time             TIMESTAMP;
    v_elapsed_time         INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Parameter: plain text values only for the pgr_drivingdistance SQL string --------
    --------------------------------------------------------------------------------------

    IF p_direction = 'from' THEN
        v_new_source := 'source';
        v_new_target := 'target';
    ELSE
        v_new_source := 'target AS source';
        v_new_target := 'source AS target';
    END IF;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_cost_expression := '(cost_distance * 0.72)::DOUBLE PRECISION';
                 v_cost_expression_edge := '(e.cost_distance * 0.72)';
                 v_new_cost := 'cost_distance';
        WHEN p_calculation_type = 'time'
            THEN v_cost_expression := 'cost_time::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_time';
                 v_new_cost := 'cost_time';
        WHEN p_calculation_type = 'distance'
            THEN v_cost_expression := 'cost_distance::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_distance';
                 v_new_cost := 'cost_distance';
        WHEN p_calculation_type = 'traffic'
            THEN v_cost_expression := 'cost_traffic::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_traffic';
                 v_new_cost := 'cost_traffic';
        END CASE;
    IF p_mode_of_transport IN ('pedestrian', 'no_mode') THEN
        v_reverse_cost := v_new_cost;
    ELSE
        v_reverse_cost := '-1';
    END IF;
    --------------------------------------------------------------------------------------
    -- pgr_drivingdistance (once via CTE) + edge join (preselection twice) -------------
    --------------------------------------------------------------------------------------

    RETURN QUERY EXECUTE
        'WITH isoline AS (
            SELECT * FROM pgr_drivingdistance(
                ''SELECT DISTINCT ON (id)
                    id,
                    ' || v_new_source || ',
                    ' || v_new_target || ',
                    ' || v_cost_expression || ' AS cost,
                    ' || v_reverse_cost || ' AS reverse_cost
                 FROM pgr._preselection_isolines(
                     ' || p_lon || ',
                     ' || p_lat || ',
                     ' || p_buffer_value || ',
                     ''''' || p_calculation_type || ''''',
                     ''''' || p_mode_of_transport || ''''',
                     ' || p_inner_limit || ',
                    ''''' || p_direction || '''''
                 )'',
                CASE WHEN ''' || p_direction || ''' = ''from'' THEN 1 ELSE 10001 END,
                ' || p_buffer_value || '::DOUBLE PRECISION,
                TRUE
            )
        ),
        preselection AS (
            SELECT DISTINCT ON (id) *
            FROM pgr._preselection_isolines(
                ' || p_lon || ',
                ' || p_lat || ',
                ' || p_buffer_value || ',
                ''' || p_calculation_type || ''',
                ''' || p_mode_of_transport || ''',
                ' || p_inner_limit + 1000 || ',
                ''' || p_direction || '''
            )
        ),
        -- Start nodes for the ends: reached nodes and, one turn edge (connector, source_id NULL) further, their
        -- target nodes. In the edge-based network there is always a connector between two segments; branching
        -- segments only begin behind it.
        ends AS (
            SELECT i.seq, i.node, i.agg_cost
            FROM isoline i
            UNION ALL
            SELECT i.seq,
                   CASE WHEN ''' || p_direction || ''' = ''from'' THEN c.target ELSE c.source END,
                   i.agg_cost + ' || REPLACE(v_cost_expression_edge, 'e.', 'c.') || '
            FROM isoline i
            INNER JOIN preselection AS c ON CASE WHEN ''' || p_direction || ''' = ''from''
                 THEN c.source = i.node
             ELSE c.target = i.node
            END
            WHERE c.source_id IS NULL
              AND i.agg_cost + ' || REPLACE(v_cost_expression_edge, 'e.', 'c.') || ' < ' || p_buffer_value || '
        )
        SELECT DISTINCT ON (source_id, seg_k1, seg_k2)
            edge_node,
            seq,
            id,
            source,
            target,
            cost,
            agg_cost,
            geom
        FROM (
            -- edge_node = 1: directly routed edges
            SELECT
                *
            FROM
            (SELECT
                DISTINCT ON (e.source_id, seg_k1, seg_k2)
                1::SMALLINT                AS edge_node,
                i.seq::BIGINT              AS seq,
                e.id,
                e.source_id,
                e.source,
                e.target,
                ROUND(i.cost)::INTEGER     AS cost,

                ROUND(
                    CASE
                        WHEN i.agg_cost > ' || p_buffer_value || '::DOUBLE PRECISION
                            THEN ' || p_buffer_value || '::DOUBLE PRECISION
                        ELSE i.agg_cost
                    END
                )::INTEGER                 AS agg_cost ,
                CASE
                    WHEN i.agg_cost > ' || p_buffer_value || '
                        THEN
                            CASE WHEN ''' || p_direction || ''' = ''from'' AND i.cost > 0
                                THEN st_linesubstring(e.geom, 0.0, 1.0 - ((i.agg_cost - ' || p_buffer_value || ') / i.cost))
                                ELSE st_linesubstring(e.geom, ((i.agg_cost - ' || p_buffer_value || ') / i.cost), 1.0)
                            END
                        ELSE e.geom
                    END                        AS geom,
                LEAST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k1,
                GREATEST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k2
            FROM isoline i
            INNER JOIN preselection AS e ON e.id = i.edge
            WHERE e.source_id IS NOT NULL
            ORDER BY e.source_id, seg_k1, seg_k2, CASE WHEN ''' || p_direction || ''' = ''from'' THEN agg_cost ELSE -agg_cost END) en1

            UNION ALL

            -- edge_node = 2: neighbouring edges at the last reachable node
            SELECT
                2::SMALLINT                                         AS edge_node,
                i.seq::BIGINT                                       AS seq,
                e.id,
                e.source_id,
                e.source,
                e.target,
                ROUND(' || v_cost_expression_edge || ')::INTEGER              AS cost,
                ROUND(
                    CASE
                        WHEN i.agg_cost+ ' || v_cost_expression_edge || ' > ' || p_buffer_value || '::DOUBLE PRECISION
                            THEN ' || p_buffer_value || '::DOUBLE PRECISION
                        ELSE i.agg_cost
                    END
                )::INTEGER                 AS agg_cost ,
                CASE
                    WHEN i.agg_cost + ' || v_cost_expression_edge || ' > ' || p_buffer_value || '
                        THEN
                            CASE WHEN ''' || p_direction || ''' = ''from''
                                THEN st_linesubstring(e.geom, 0.0, 1.0 - ((i.agg_cost + ' || v_cost_expression_edge ||
        ' - ' ||
        p_buffer_value || ') /' || v_cost_expression_edge || '))
                                ELSE st_linesubstring(e.geom, ((i.agg_cost+' || v_cost_expression_edge || ' - ' ||
        p_buffer_value || ') / ' || v_cost_expression_edge || '), 1.0)
                            END
                        ELSE e.geom
                     END                        AS geom,
                LEAST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k1,
                GREATEST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k2
            FROM ends i
            INNER JOIN preselection AS e ON    CASE WHEN ''' || p_direction || ''' = ''from''
                 THEN e.source = i.node
             ELSE e.target = i.node
            END
            WHERE e.source_id IS NOT NULL

        ) created_conn
        ORDER BY source_id, seg_k1, seg_k2, edge_node';
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _driving_distance_isolines: %', v_elapsed_time;

END;
$function$;


-- ==== functions/_ending_segment.sql =================================================================================

CREATE OR REPLACE FUNCTION pgr._ending_segment(
    lon INTEGER,
    lat INTEGER,
    mode_of_transport TEXT
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                split_edge_id BIGINT,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Finds the end segment and adds the necessary edges to the network

DECLARE
    v_end3035       GEOMETRY;
    v_sc_inner_low  SMALLINT;
    v_sc_inner_high SMALLINT;
    v_center_x      INTEGER;
    v_center_y      INTEGER;
    v_edges_table   TEXT[];
    v_cluster_ids   TEXT[];
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();
    --------------------------------------------------------------------------------------
    -- Parameter assignment -------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT (SELECT MIN(c) FROM UNNEST(pgr._mode_category(mode_of_transport, 'snap')) c) - 1 INTO v_sc_inner_low;

    SELECT (SELECT MAX(c) FROM UNNEST(pgr._mode_category(mode_of_transport, 'snap')) c) INTO v_sc_inner_high;

    SELECT st_setsrid(st_makepoint(lon, lat), pgr._srid())
    INTO v_end3035;

    -- grid coordinates rounded to the 100 m grid (for the grid join)
    SELECT ROUND(lon::DOUBLE PRECISION / 100)::INTEGER INTO v_center_x;
    SELECT ROUND(lat::DOUBLE PRECISION / 100)::INTEGER INTO v_center_y;

    -- derive partition and cluster names from the 4 corners of the search radius
    SELECT ARRAY_AGG(DISTINCT 'edges_n' || SUBSTR(y::TEXT, 1, 2) || 'e' || SUBSTR(x::TEXT, 1, 2))
    INTO v_edges_table
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    SELECT ARRAY_AGG(DISTINCT UPPER('N' || SUBSTR(y::TEXT, 1, 3) || 'E' || SUBSTR(x::TEXT, 1, 3)))
    INTO v_cluster_ids
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    ---------------------------------------------------------------------------------------
    -- End segment for routes ------------------------------------------------------------
    ---------------------------------------------------------------------------------------

    RETURN QUERY
        WITH endpoint AS (SELECT v_end3035 AS geom),

             -- ------------------------------------------------------------------
             -- candidate edges via helper function (grid + partition + cluster)
             -- ------------------------------------------------------------------
             candidate_edges AS (SELECT ce.*
                                 FROM pgr._candidate_edges(
                                              v_edges_table,
                                              v_cluster_ids,
                                              v_center_x,
                                              v_center_y,
                                              v_sc_inner_low,
                                              v_sc_inner_high
                                      ) ce
                                 WHERE ce.street_cat = ANY (pgr._mode_category(mode_of_transport, 'snap')) -- categories per data source
                                   AND EXISTS (SELECT 1 FROM pgr.edges n WHERE n.target = ce.source)), -- only edges with a predecessor, otherwise no path leads to the end

             closest_points AS (SELECT e.id                                                                         AS cp_id,
                                       e.source                                                                     AS cp_source,
                                       e.target                                                                     AS cp_target,
                                       e.street_cat                                                                 AS cp_street_cat,
                                       e.cost_time                                                                  AS cp_cost_time,
                                       e.cost_distance                                                              AS cp_cost_distance,
                                       e.cost_traffic                                                               AS cp_cost_traffic,
                                       e.speed_cat                                                                  AS cp_speed_cat,
                                       e.x1                                                                         AS cp_x1,
                                       e.y1                                                                         AS cp_y1,
                                       e.x2                                                                         AS cp_x2,
                                       e.y2                                                                         AS cp_y2,
                                       e.geom                                                                       AS cp_edge_geom,
                                       st_setsrid(st_closestpoint(e.geom, s.geom), pgr._srid())                     AS cp_snap_geom,
                                       st_distance(e.geom, s.geom)                                                  AS cp_distance,
                                       st_linelocatepoint(e.geom,
                                                          st_setsrid(st_closestpoint(e.geom, s.geom), pgr._srid())) AS cp_fraction
                                FROM candidate_edges e,
                                     endpoint s),

             min_distance AS (SELECT MIN(cp.cp_distance) AS md_dist
                              FROM closest_points cp),

             nearest AS (SELECT cp.*
                         FROM closest_points cp,
                              min_distance md
                         WHERE cp.cp_distance = md.md_dist
                         LIMIT 1),

             reverse_nearest AS (SELECT cp.*
                                 FROM closest_points cp,
                                      nearest n
                                 WHERE cp.cp_id != n.cp_id
                                   AND st_equals(st_startpoint(cp.cp_edge_geom), st_endpoint(n.cp_edge_geom))
                                   AND st_equals(st_endpoint(cp.cp_edge_geom), st_startpoint(n.cp_edge_geom))
                                 LIMIT 1),

             snap_decision AS (SELECT CASE
                                          WHEN n.cp_fraction <= 0.001 THEN 'source'
                                          WHEN n.cp_fraction >= 0.999 THEN 'target'
                                          ELSE 'split'
                                          END AS sd_snap_case,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_source
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_target
                                          ELSE NULL
                                          END AS sd_snap_node_id,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_x1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_x2
                                          ELSE NULL
                                          END AS sd_snap_x,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_y1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_y2
                                          ELSE NULL
                                          END AS sd_snap_y,
                                      n.cp_id AS sd_edge_id
                               FROM nearest n),

             -- ------------------------------------------------------------------
             -- regular case: connecting edge projected point (10002) → end point (10001)
             -- ------------------------------------------------------------------
             split_connector AS (SELECT 1                                                              AS sort_order,
                                        10002::BIGINT                                                  AS source,
                                        10001::BIGINT                                                  AS target,
                                        NULL::INTEGER                                                  AS street_cat,
                                        0::INTEGER                                                     AS cost_time,
                                        0::INTEGER                                                     AS cost_distance,
                                        0::INTEGER                                                     AS cost_traffic,
                                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER                     AS x1,
                                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER                     AS y1,
                                        ROUND(st_x((SELECT ep.geom FROM endpoint ep)) / 100)::INTEGER  AS x2,
                                        ROUND(st_y((SELECT ep.geom FROM endpoint ep)) / 100)::INTEGER  AS y2,
                                        NULL::BIGINT                                                   AS split_edge_id,
                                        st_makeline(n.cp_snap_geom, (SELECT ep.geom FROM endpoint ep)) AS geom
                                 FROM nearest n,
                                      snap_decision sd
                                 WHERE sd.sd_snap_case = 'split'
                                 LIMIT 1),

             -- ------------------------------------------------------------------
             -- regular case: split segments
             -- part 1: source → projected point (10002)
             -- part 2: projected point (10002) → target
             -- part 3: projected point (10002) → source (reverse direction)
             -- part 4: target → projected point (10002) (reverse direction)
             -- ------------------------------------------------------------------
             split_segments AS (
                 -- part 1: source → projected point
                 SELECT 2                                                    AS sort_order,
                        n.cp_source                                          AS source,
                        10002::BIGINT                                        AS target,
                        n.cp_street_cat::INTEGER                             AS street_cat,
                        CASE
                            WHEN n.cp_cost_time < 100000 THEN ROUND(
                                    n.cp_cost_time * st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                    NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_time,
                        CASE
                            WHEN n.cp_cost_distance < 100000
                                THEN ROUND(n.cp_cost_distance *
                                           st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                           NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE n.cp_cost_distance
                            END::INTEGER                                     AS cost_distance,
                        CASE
                            WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                       st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_traffic,
                        n.cp_x1                                              AS x1,
                        n.cp_y1                                              AS y1,
                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER           AS x2,
                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER           AS y2,
                        n.cp_id                                              AS split_edge_id,
                        st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction) AS geom
                 FROM nearest n,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 2: projected point → target
                 SELECT 2                                                    AS sort_order,
                        10002::BIGINT                                        AS source,
                        n.cp_target                                          AS target,
                        n.cp_street_cat::INTEGER                             AS street_cat,
                        CASE
                            WHEN n.cp_cost_time < 100000 THEN ROUND(
                                    n.cp_cost_time * st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                    NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_time,
                        CASE
                            WHEN n.cp_cost_distance < 100000
                                THEN ROUND(n.cp_cost_distance *
                                           st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                           NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE n.cp_cost_distance
                            END::INTEGER                                     AS cost_distance,
                        CASE
                            WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                       st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_traffic,
                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER           AS x1,
                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER           AS y1,
                        n.cp_x2                                              AS x2,
                        n.cp_y2                                              AS y2,
                        n.cp_id                                              AS split_edge_id,
                        st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0) AS geom
                 FROM nearest n,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 3: projected point → source (reverse direction)
                 SELECT 2                                                      AS sort_order,
                        rn.cp_source                                           AS source,
                        10002::BIGINT                                          AS target,
                        rn.cp_street_cat::INTEGER                              AS street_cat,
                        CASE
                            WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                     st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                     NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_time,
                        CASE
                            WHEN rn.cp_cost_distance < 100000
                                THEN ROUND(rn.cp_cost_distance *
                                           st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                           NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE rn.cp_cost_distance
                            END::INTEGER                                       AS cost_distance,
                        CASE
                            WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                        st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_traffic,
                        ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER            AS x1,
                        ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER            AS y1,
                        rn.cp_x1                                               AS x2,
                        rn.cp_y1                                               AS y2,
                        rn.cp_id                                               AS split_edge_id,
                        st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction) AS geom
                 FROM reverse_nearest rn,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 4: target → projected point (reverse direction)
                 SELECT 2                                                      AS sort_order,
                        10002::BIGINT                                          AS source,
                        rn.cp_target                                           AS target,
                        rn.cp_street_cat::INTEGER                              AS street_cat,
                        CASE
                            WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                     st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                     NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_time,
                        CASE
                            WHEN rn.cp_cost_distance < 100000
                                THEN ROUND(rn.cp_cost_distance *
                                           st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                           NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE rn.cp_cost_distance
                            END::INTEGER                                       AS cost_distance,
                        CASE
                            WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                        st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_traffic,
                        rn.cp_x2                                               AS x1,
                        rn.cp_y2                                               AS y1,
                        ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER            AS x2,
                        ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER            AS y2,
                        rn.cp_id                                               AS split_edge_id,
                        st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0) AS geom
                 FROM reverse_nearest rn,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'),

             -- ------------------------------------------------------------------
             -- snap case: connecting edge snap node (10002) → end point (10001)
             -- ------------------------------------------------------------------
             snap_connector AS (SELECT 1                                                             AS sort_order,
                                       10002::BIGINT                                                 AS source,
                                       10001::BIGINT                                                 AS target,
                                       NULL::INTEGER                                                 AS street_cat,
                                       0::INTEGER                                                    AS cost_time,
                                       0::INTEGER                                                    AS cost_distance,
                                       0::INTEGER                                                    AS cost_traffic,
                                       sd.sd_snap_x                                                  AS x1,
                                       sd.sd_snap_y                                                  AS y1,
                                       ROUND(st_x((SELECT ep.geom FROM endpoint ep)) / 100)::INTEGER AS x2,
                                       ROUND(st_y((SELECT ep.geom FROM endpoint ep)) / 100)::INTEGER AS y2,
                                       NULL::BIGINT                                                  AS split_edge_id,
                                       st_makeline(
                                               CASE
                                                   WHEN sd.sd_snap_case = 'source' THEN st_startpoint(n.cp_edge_geom)
                                                   WHEN sd.sd_snap_case = 'target' THEN st_endpoint(n.cp_edge_geom)
                                                   END,
                                               (SELECT ep.geom FROM endpoint ep)
                                       )                                                             AS geom
                                FROM snap_decision sd,
                                     nearest n
                                WHERE sd.sd_snap_case IN ('source', 'target')),

             -- ------------------------------------------------------------------
             -- snap case: all segments at the snap node – only from candidate_edges
             -- ------------------------------------------------------------------
             snap_segments AS (SELECT 2                        AS sort_order,
                                      10002::BIGINT            AS source,
                                      e.target                 AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id,
                                      e.geom
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.source = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target')

                               UNION ALL

                               SELECT 2                        AS sort_order,
                                      e.source                 AS source,
                                      10002::BIGINT            AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id,
                                      e.geom
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.target = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target'))

        SELECT ROW_NUMBER() OVER (ORDER BY ns.sort_order, ns.source, ns.target) + 10000,
               ns.source,
               ns.target,
               ns.cost_time,
               ns.cost_distance,
               ns.cost_traffic,
               ns.street_cat,
               ns.x1,
               ns.y1,
               ns.x2,
               ns.y2,
               ns.split_edge_id,
               ns.geom
        FROM (SELECT sc.sort_order,
                     sc.source,
                     sc.target,
                     sc.cost_time,
                     sc.cost_distance,
                     sc.cost_traffic,
                     sc.street_cat,
                     sc.x1,
                     sc.y1,
                     sc.x2,
                     sc.y2,
                     sc.split_edge_id,
                     sc.geom
              FROM split_connector sc
              UNION ALL
              SELECT sps.sort_order,
                     sps.source,
                     sps.target,
                     sps.cost_time,
                     sps.cost_distance,
                     sps.cost_traffic,
                     sps.street_cat,
                     sps.x1,
                     sps.y1,
                     sps.x2,
                     sps.y2,
                     sps.split_edge_id,
                     sps.geom
              FROM split_segments sps
              UNION ALL
              SELECT snc.sort_order,
                     snc.source,
                     snc.target,
                     snc.cost_time,
                     snc.cost_distance,
                     snc.cost_traffic,
                     snc.street_cat,
                     snc.x1,
                     snc.y1,
                     snc.x2,
                     snc.y2,
                     snc.split_edge_id,
                     snc.geom
              FROM snap_connector snc
              UNION ALL
              SELECT sns.sort_order,
                     sns.source,
                     sns.target,
                     sns.cost_time,
                     sns.cost_distance,
                     sns.cost_traffic,
                     sns.street_cat,
                     sns.x1,
                     sns.y1,
                     sns.x2,
                     sns.y2,
                     sns.split_edge_id,
                     sns.geom
              FROM snap_segments sns) AS ns
        ORDER BY ns.sort_order, ns.source, ns.target;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _ending_segment: %', v_elapsed_time;
END;
$function$;


-- ==== functions/_grids_isolines.sql =================================================================================

CREATE OR REPLACE FUNCTION pgr._grids_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_direction TEXT,
    p_inner_limit INTEGER DEFAULT 1500
)
    RETURNS TABLE
            (
                gitter_id_              TEXT,
                seq                     BIGINT,
                node                    BIGINT,
                edge                    BIGINT,
                cost                    INTEGER,
                agg_cost                INTEGER,
                grid_time               INTEGER,
                grid_distance           INTEGER,
                grid_traffic            INTEGER,
                distance_to_grid_factor DOUBLE PRECISION,
                street_cat              INTEGER,
                grid_geom               geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns grid cells reachable within buffer_value.
--              pgr_drivingdistance on _preselection_isolines (once),
--              then joined directly to pgr.grids via node.
--              No temporary tables. All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_new_source      TEXT;
    v_new_target      TEXT;
    v_new_cost        TEXT;
    v_cost            TEXT;
    v_cost_expression TEXT;
    v_new_agg_cost    TEXT;
    v_agg_cost        TEXT;
    v_agg_cost1       TEXT;
    v_reverse_cost    TEXT;
    v_start_time      TIMESTAMP;
    v_end_time        TIMESTAMP;
    v_elapsed_time    INTERVAL;
    v_start_cluster   TEXT;
    v_segment_func    TEXT;
    v_segment_filter  TEXT;

BEGIN
    v_start_time
        = CLOCK_TIMESTAMP();


    --------------------------------------------------------------------------------------
    -- Parameter: plain text values only -----------------------------------------------
    --------------------------------------------------------------------------------------

    IF
        p_direction = 'from' THEN
        v_new_source := 'source';
        v_new_target
            := 'target';
    ELSE
        v_new_source := 'target AS source';
        v_new_target
            := 'source AS target';
    END IF;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_cost_expression := 'cost_distance * 0.72::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_distance';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 :=
                             'i.agg_cost + g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     --'i.agg_cost -  + g.cost_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_distance * 0.72 - g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_distance * 0.72 - g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     --'i.agg_cost';
                 END IF;
        WHEN p_calculation_type = 'time'
            THEN v_cost_expression := 'cost_time::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_time';
                 IF
                     p_direction = 'from' THEN
                     v_cost := 'g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost1
                         := 'i.agg_cost - i.cost + g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost
                         := 'i.agg_cost - i.cost + g.grid_time + g.distance_to_grid_factor * g.cost_time';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_time - g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_time - g.grid_time + g.distance_to_grid_factor * g.cost_time';
                 END IF;
        WHEN p_calculation_type = 'distance'
            THEN v_cost_expression := 'cost_distance::DOUBLE PRECISION';
                 v_cost
                     := 'g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                 v_new_cost
                     := 'cost_distance';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 := 'i.agg_cost + g.grid_distance + g.distance_to_grid_factor * g.cost_distance ';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                     --   'i.agg_cost - i.cost * grid_factor + g.distance_to_grid_factor * g.cost_distance';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_distance - g.grid_distance + g.distance_to_grid_factor * g.cost_distance ';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_distance - g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                     --'i.agg_cost - i.cost * grid_factor + g.distance_to_grid_factor * g.cost_distance';
                 END IF;
        WHEN p_calculation_type = 'traffic'
            THEN v_cost_expression := 'cost_traffic::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_traffic';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 := 'i.agg_cost  + g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                     v_agg_cost
                         := 'i.agg_cost - i.cost + g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_traffic - g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_traffic - g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                 END IF;
        END CASE;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_new_agg_cost := 'g.cost_distance * 0.72';
        WHEN p_calculation_type = 'time'
            THEN v_new_agg_cost := 'g.cost_time';
        WHEN p_calculation_type = 'distance'
            THEN v_new_agg_cost := 'g.cost_distance';
        WHEN p_calculation_type = 'traffic'
            THEN v_new_agg_cost := 'g.cost_traffic';
        END CASE;

    v_reverse_cost
        := CASE
               WHEN p_mode_of_transport = 'pedestrian' AND p_calculation_type = 'time'
                   THEN 'cost_distance * 0.72::DOUBLE PRECISION'
               WHEN p_mode_of_transport IN ('pedestrian', 'no_mode')
                   THEN 'cost_distance::DOUBLE PRECISION'
               ELSE '-1'
        END;

    v_start_cluster
        := '100mN' || SUBSTR(p_lat::TEXT, 1, 5) || 'E' || SUBSTR(p_lon::TEXT, 1, 5);

    v_end_time
        = CLOCK_TIMESTAMP();
    v_elapsed_time
        = v_end_time - v_start_time;

    v_segment_func
        := CASE
               WHEN p_direction = 'from'
                   THEN 'pgr._starting_segment'
               ELSE 'pgr._ending_segment'
        END;
    v_segment_filter
        := CASE
               WHEN p_direction = 'from'
                   THEN 'source < 100000'
               ELSE 'target < 100000'
        END;

    RAISE
        NOTICE 'Execution Time for _grids_isolines /Defining Selection parameters: %', v_elapsed_time;

    --------------------------------------------------------------------------------------
    -- pgr_drivingdistance + grid join -------------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time
        = CLOCK_TIMESTAMP();

    RETURN QUERY EXECUTE
        'WITH isoline AS (
            SELECT * FROM pgr_drivingdistance(
                ''SELECT DISTINCT ON (id)
                    id,
                    ' || v_new_source || ',
                    ' || v_new_target || ',
                    ' || v_cost_expression || ' AS cost,
                    ' || v_reverse_cost || ' AS reverse_cost
                 FROM pgr._preselection_isolines(
                     ' || p_lon || ',
                     ' || p_lat || ',
                     ' || p_buffer_value || ',
                     ''''' || p_calculation_type || ''''',
                     ''''' || p_mode_of_transport || ''''',
                     ' || p_inner_limit || ',
                     ''''' || p_direction || '''''
                 )'',
                CASE WHEN ''' || p_direction || ''' = ''from'' THEN 1 ELSE 10001 END,
                ' || p_buffer_value || '::DOUBLE PRECISION,
                TRUE
            )
        ),
        grid_result AS (
            -- 1. static grid cells
            SELECT --DISTINCT ON (g.gitter_id_)
                g.gitter_id_,
                i.seq::BIGINT                               AS seq,
                i.node,
                i.edge,
                CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0::INTEGER ELSE ROUND(i.cost)::INTEGER END AS cost,
                CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0::INTEGER
                ELSE
                    ROUND(CASE WHEN i.cost = i.agg_cost THEN ' || v_agg_cost || ' ELSE ' || v_agg_cost || ' END)::INTEGER END AS agg_cost,

                --ROUND(CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0 ELSE i.cost END)::INTEGER AS cost,
                --ROUND(i.cost)::INTEGER                      AS cost,
                --ROUND(CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0 ELSE ' || v_agg_cost || ' END)::INTEGER AS agg_cost,
                --ROUND(CASE WHEN ' || v_agg_cost || ' IS NULL THEN ' || v_new_agg_cost || ' ELSE ' || v_agg_cost || ' END)::INTEGER AS agg_cost,
                --
                --ROUND(' || v_agg_cost || ')::INTEGER        AS agg_cost,
                ROUND(g.grid_time)::INTEGER                 AS grid_time,
                ROUND(g.grid_distance)::INTEGER             AS grid_distance,
                ROUND(g.grid_traffic)::INTEGER              AS grid_traffic,
                g.distance_to_grid_factor,
                g.street_cat::INTEGER,
                g.grid_geom
            FROM isoline i
            LEFT JOIN pgr._candidate_grids_isolines(' || p_lon || ',' || p_lat || ', ' ||
        ROUND(pgr._buffer_isolines(p_buffer_value, p_calculation_type, p_mode_of_transport))::INTEGER || ') g ON
                CASE WHEN ''' || p_direction || ''' = ''from''
                    THEN g.source = i.node
                    ELSE g.target = i.node
                END
            WHERE  i.cost >= 0
            AND  g.gitter_id_ IS NOT NULL
            AND  g.street_cat = ANY(' || QUOTE_LITERAL(pgr._mode_category(p_mode_of_transport, 'buffer')) || '::INTEGER[])  -- only categories of the mode
            AND  i.edge > 100000



        -- 2. dynamic grid cells
        UNION
        SELECT
            dg.gitter_id_,
            dg.seq::BIGINT                  AS seq,
            dg.node,
            dg.edge,
            ROUND(dg.agg_cost)::INTEGER     AS cost,
            ROUND(dg.agg_cost)::INTEGER     AS agg_cost,
            NULL::INTEGER                   AS grid_time,
            NULL::INTEGER                   AS grid_distance,
            NULL::INTEGER                   AS grid_traffic,
            NULL::DOUBLE PRECISION          AS distance_to_grid_factor,
            NULL::INTEGER                   AS street_cat,
            st_transform(dg.geom,4326)                         AS grid_geom
        FROM (
            SELECT DISTINCT ON (gitter_id_)
                gitter_id_,
                seq,
                node,
                edge,
                agg_cost,
                geom
            FROM (
                SELECT i.node, i.edge,
                    (pgr._create_dynamical_grids(s.id, i.cost::integer, s.x1, s.y1, s.x2, s.y2, s.geom, ''' ||
        p_direction || ''')).*
                FROM (
                    SELECT (' || v_segment_func || '(' || p_lon || ',' || p_lat || ', ''' || p_mode_of_transport || ''')).*
                ) s
                INNER JOIN isoline i ON s.id = i.edge
                WHERE ' || v_segment_filter || '
            ) dg
            ORDER BY gitter_id_, agg_cost
        )   dg

        -- end of dynamic grid cells
        )
        SELECT
            DISTINCT ON (gitter_id_)
            gitter_id_,
            seq,
            node,
            edge,
            cost::INTEGER,
            agg_cost::INTEGER,
            grid_time,
            grid_distance,
            grid_traffic,
            distance_to_grid_factor,
            street_cat,
            grid_geom
        FROM grid_result
        WHERE agg_cost <= ' || p_buffer_value || '::INTEGER
        ORDER BY gitter_id_, agg_cost';

    v_end_time
        = CLOCK_TIMESTAMP();
    v_elapsed_time
        = v_end_time - v_start_time;
    RAISE
        NOTICE 'Execution Time for _grids_isolines: %', v_elapsed_time;

END;
$function$;


-- ==== functions/_mode_category.sql ==================================================================================

CREATE OR REPLACE FUNCTION pgr._mode_category(
    p_mode TEXT,
    p_kind TEXT
)
    RETURNS INTEGER[]
    LANGUAGE plpgsql
    STABLE
    PARALLEL SAFE
AS
$function$
    -- The categories come from the respective network (HERE or OSM) and mean different things per source. They are stored
    -- in pgr.loine_mode_category (created by loine_install.sql). The source is taken from pgr.loine_installed (default: here).
    -- p_kind: buffer (buffer around start and end) | main (main network between start and end) |
    --         snap (categories to which start and end are snapped) | matrix (network of the cost matrix)
DECLARE
    v_source TEXT := 'here';
    v_cats   INTEGER[];
BEGIN
    IF TO_REGCLASS('pgr.loine_installed') IS NOT NULL THEN
        SELECT COALESCE(MIN(source), 'here') INTO v_source FROM pgr.loine_installed;
    END IF;

    SELECT CASE p_kind
               WHEN 'buffer' THEN buffer_cats
               WHEN 'main' THEN main_cats
               WHEN 'snap' THEN snap_cats
               WHEN 'matrix' THEN matrix_cats
               END
    INTO v_cats
    FROM pgr.loine_mode_category
    WHERE source = v_source
      AND mode = p_mode;

    RETURN v_cats;
END;
$function$;


-- ==== functions/_net_level_cats.sql =================================================================================

CREATE OR REPLACE FUNCTION pgr._net_level_cats()
    RETURNS INTEGER[]
    LANGUAGE sql
    STABLE
AS
$function$
    -- Categories of all car modes of the installed data source (from pgr._mode_category, without -1).
    -- Used by pgr.loine_build_net_level.
SELECT ARRAY(SELECT DISTINCT c
             FROM UNNEST(ARRAY ['car', 'card', 'caro', 'care', 'carl']) m,
                  UNNEST(pgr._mode_category(m, 'buffer')) c
             WHERE c > 0
             ORDER BY c);
$function$;


-- ==== functions/_net_level_edges.sql ================================================================================

CREATE OR REPLACE FUNCTION pgr._net_level_edges(
    start_lon INTEGER,
    start_lat INTEGER,
    end_lon INTEGER,
    end_lat INTEGER,
    p_buffer_cats INTEGER[],
    p_main_cats INTEGER[]
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                geom          GEOMETRY
            )
    LANGUAGE plpgsql
    STABLE PARALLEL SAFE
AS
$function$
    -- Coordinates as in pgr._preselection_routes. Estimated size of the local preselection from pgr.net_density_cluster
    -- (main network in the rectangle ± 1 cluster, buffer network in the start and end cluster). From the base network
    -- (pgr.edges_global, built by pgr.loine_build_net_level), the edges with prio <= budget − local size are returned,
    -- at least min_global. Default min_global = budget: the whole base network is always loaded. With min_global = 0
    -- nothing is added where the local preselection already uses up the budget; faster, but routes in sparse networks
    -- may be missing. Without base network (pgr.net_level empty) no edges are returned.

DECLARE
    v_budget     BIGINT;
    v_min_global BIGINT;
    v_local      BIGINT;
    v_limit      BIGINT;
BEGIN
    SELECT l.budget, l.min_global INTO v_budget, v_min_global FROM pgr.net_level l;
    IF v_budget IS NULL THEN
        RETURN;
    END IF;

    -- estimated size of the local preselection: main network in the rectangle ± 1 cluster (as _candidate_edges_cluster)
    -- and buffer network in the start and end cluster
    SELECT COALESCE(SUM(d.n), 0)
    INTO v_local
    FROM pgr.net_density_cluster d
    WHERE d.street_cat = ANY (p_main_cats)
      AND d.cluster_id IN (SELECT 'N' || LPAD(y::TEXT, 3, '0') || 'E' || LPAD(x::TEXT, 3, '0')
                           FROM GENERATE_SERIES(LEAST(start_lon, end_lon) / 10000 - 1,
                                                GREATEST(start_lon, end_lon) / 10000 + 1) x
                                    CROSS JOIN GENERATE_SERIES(LEAST(start_lat, end_lat) / 10000 - 1,
                                                               GREATEST(start_lat, end_lat) / 10000 + 1) y);
    v_local := v_local + (SELECT COALESCE(SUM(d.n), 0)
                          FROM pgr.net_density_cluster d
                          WHERE d.street_cat = ANY (p_buffer_cats)
                            AND d.street_cat <> ALL (p_main_cats)
                            AND d.cluster_id IN ('N' || LPAD((start_lat / 10000)::TEXT, 3, '0') || 'E' ||
                                                 LPAD((start_lon / 10000)::TEXT, 3, '0'),
                                                 'N' || LPAD((end_lat / 10000)::TEXT, 3, '0') || 'E' ||
                                                 LPAD((end_lon / 10000)::TEXT, 3, '0')));

    v_limit := GREATEST(v_budget - v_local, v_min_global);
    IF v_limit <= 0 THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT g.id,
               g.source,
               g.target,
               g.cost_time,
               g.cost_distance,
               g.cost_traffic,
               g.street_cat,
               g.x1,
               g.y1,
               g.x2,
               g.y2,
               g.geom
        FROM pgr.edges_global g
        WHERE g.prio <= v_limit
          AND g.street_cat = ANY (p_buffer_cats);
END;
$function$;


-- ==== functions/_preselection_costmatrix.sql ========================================================================

CREATE OR REPLACE FUNCTION pgr._preselection_costmatrix(
    p_input_table TEXT,
    p_mode_of_transport TEXT,
    p_inner_limit INTEGER DEFAULT 1500,
    p_outer_buffer_m INTEGER DEFAULT 20000
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Preselects the network for the N points in input_table (node_id, x, y
    --              in WGS84). Combines three sources:
    --              (A) bidirectional snapping of each point to the network (pgr._costmatrix_segment),
    --              (B) a local fine-selection buffer per point (pgr._candidate_edges_array,
    --                  radius p_inner_limit, as in _preselection_routes),
    --              (C) the outer/main network via an inexpensive hull corridor
    --                  (pgr._candidate_edges_hull_costmatrix) instead of one large bounding box.
    --              Consistently uses x1/y1 BTREE range queries instead of ST_Intersects/GiST
    --              on pgr.edges.
    --              The point_id/lot_id assignment comes from pgr._costmatrix_points
    --              (deterministic, ORDER BY node_id) - called EXACTLY ONCE here via a
    --              MATERIALIZED CTE (pgr._costmatrix_points creates a temporary table;
    --              calling it several times within the same query would be problematic,
    --              since each call drops and recreates it).
    --              cgo_costmatrix calls the same function again later to translate
    --              pgr_astarcostmatrix's start_vid/end_vid back to node_id - thanks to
    --              ORDER BY node_id both calls return the same assignment.
    --              The result may contain duplicates (same id from several sources) - the
    --              caller applies DISTINCT ON (id) when building edges_sql for
    --              pgr_astarcostmatrix (as in _driving_distance_isolines).

DECLARE
    v_street_cat INTEGER[];
BEGIN
    SELECT pgr._mode_category(p_mode_of_transport, 'matrix')
    INTO v_street_cat; -- categories per data source (pgr.loine_mode_category)

    RETURN QUERY
        WITH pts AS MATERIALIZED (SELECT * FROM pgr._costmatrix_points(p_input_table))

        -- A: bidirectional snapping of each point to the network
        SELECT cs.id,
               cs.source,
               cs.target,
               cs.cost_time,
               cs.cost_distance,
               cs.cost_traffic,
               NULL::INTEGER AS street_cat,
               cs.x1,
               cs.y1,
               cs.x2,
               cs.y2
        FROM pts p,
             LATERAL pgr._costmatrix_segment(p.point_id, p.lot_id, p.id_offset, p.lon, p.lat, v_street_cat) cs

        UNION ALL

        -- B: local fine-selection buffer per point (as in _preselection_routes)
        SELECT ca.id,
               ca.source,
               ca.target,
               ca.cost_time,
               ca.cost_distance,
               ca.cost_traffic,
               ca.street_cat,
               ca.x1,
               ca.y1,
               ca.x2,
               ca.y2
        FROM pts p,
             LATERAL pgr._candidate_edges_array(p.edges_table, p.cluster_id, p.x1, p.y1, v_street_cat, p_inner_limit) ca

        UNION ALL

        -- C: outer main network via the hull corridor
        SELECT h.id,
               h.source,
               h.target,
               h.cost_time,
               h.cost_distance,
               h.cost_traffic,
               h.street_cat,
               h.x1,
               h.y1,
               h.x2,
               h.y2
        FROM pgr._candidate_edges_hull_costmatrix(
                     (SELECT ARRAY_AGG(pts.x1) FROM pts), (SELECT ARRAY_AGG(pts.y1) FROM pts),
                     v_street_cat, p_outer_buffer_m
             ) h;
END;
$function$;


-- ==== functions/_preselection_isolines.sql ==========================================================================

CREATE OR REPLACE FUNCTION pgr._preselection_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_inner_limit INTEGER,
    p_direction TEXT DEFAULT 'from'::TEXT
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                source_id     DOUBLE PRECISION,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Preselects the network for isoline calculation around a single point.
    --              Calls _starting_segment (from) or _ending_segment (to).
    --              No dynamic SQL, no geography buffer, no WGS84.

DECLARE
    v_street_cat_inner INTEGER[];
    v_street_cat_outer INTEGER[];
    v_edges_table      TEXT;
    v_start_cluster    TEXT;
    v_center_x         INTEGER;
    v_center_y         INTEGER;
    v_buffer_m         INTEGER;
    v_start_time       TIMESTAMP;
    v_end_time         TIMESTAMP;
    v_elapsed_time     INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Parameter: street categories -----------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._mode_category(p_mode_of_transport, 'buffer')
    INTO v_street_cat_inner; -- categories per data source (pgr.loine_mode_category)

    SELECT pgr._mode_category(p_mode_of_transport, 'main') INTO v_street_cat_outer;
    -- categories per data source (pgr.loine_mode_category)

    --------------------------------------------------------------------------------------
    -- Parameter: grid coordinates ------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT ROUND(p_lon::DOUBLE PRECISION / 100)::INTEGER INTO v_center_x;
    SELECT ROUND(p_lat::DOUBLE PRECISION / 100)::INTEGER INTO v_center_y;

    SELECT 'edges_n' || SUBSTR(p_lat::TEXT, 1, 2) || 'e' || SUBSTR(p_lon::TEXT, 1, 2)
    INTO v_edges_table;

    SELECT UPPER('N' || SUBSTR(p_lat::TEXT, 1, 3) || 'E' || SUBSTR(p_lon::TEXT, 1, 3))
    INTO v_start_cluster;

    --------------------------------------------------------------------------------------
    -- Parameter: outer buffer (metres, from _buffer_isolines) --------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._buffer_isolines(p_buffer_value, p_calculation_type, p_mode_of_transport)::INTEGER
    INTO v_buffer_m;

    --------------------------------------------------------------------------------------
    -- Preselection ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    IF p_direction = 'from' THEN
        RETURN QUERY
            WITH start_seg AS (SELECT ss.id,
                                      ss.source,
                                      ss.target,
                                      ss.cost_time,
                                      ss.cost_distance,
                                      ss.cost_traffic,
                                      ss.street_cat,
                                      ss.x1,
                                      ss.y1,
                                      ss.x2,
                                      ss.y2,
                                      ss.split_edge_id,
                                      ss.geom
                               FROM pgr._starting_segment(p_lon, p_lat, p_mode_of_transport) ss),
                 split_id AS (SELECT split_edge_id
                              FROM start_seg
                              WHERE split_edge_id IS NOT NULL)
            SELECT ss.id,
                   ss.source,
                   ss.target,
                   ss.cost_time,
                   ss.cost_distance,
                   ss.cost_traffic,
                   ss.street_cat,
                   ss.x1,
                   ss.y1,
                   ss.x2,
                   ss.y2,
                   ss.id::DOUBLE PRECISION AS source_id,
                   ss.geom
            FROM start_seg ss

            UNION ALL

            SELECT nb.id,
                   nb.source,
                   nb.target,
                   nb.cost_time,
                   nb.cost_distance,
                   nb.cost_traffic,
                   nb.street_cat,
                   nb.x1,
                   nb.y1,
                   nb.x2,
                   nb.y2,
                   nb.source_id,
                   nb.geom
            FROM pgr._candidate_edges_array(
                         v_edges_table, v_start_cluster, v_center_x, v_center_y,
                         v_street_cat_inner, p_inner_limit
                 ) nb
            WHERE nb.id NOT IN (SELECT split_edge_id FROM split_id)

            UNION ALL

            SELECT fb.id,
                   fb.source,
                   fb.target,
                   fb.cost_time,
                   fb.cost_distance,
                   fb.cost_traffic,
                   fb.street_cat,
                   fb.x1,
                   fb.y1,
                   fb.x2,
                   fb.y2,
                   fb.source_id,
                   fb.geom
            FROM pgr._candidate_edges_isolines(
                         p_lon, p_lat, v_buffer_m, v_street_cat_outer
                 ) fb
            WHERE fb.id NOT IN (SELECT split_edge_id FROM split_id);
    ELSE
        RETURN QUERY
            WITH start_seg AS (SELECT ss.id,
                                      ss.source,
                                      ss.target,
                                      ss.cost_time,
                                      ss.cost_distance,
                                      ss.cost_traffic,
                                      ss.street_cat,
                                      ss.x1,
                                      ss.y1,
                                      ss.x2,
                                      ss.y2,
                                      ss.split_edge_id,
                                      ss.geom
                               FROM pgr._ending_segment(p_lon, p_lat, p_mode_of_transport) ss),
                 split_id AS (SELECT split_edge_id
                              FROM start_seg
                              WHERE split_edge_id IS NOT NULL)
            SELECT ss.id,
                   ss.source,
                   ss.target,
                   ss.cost_time,
                   ss.cost_distance,
                   ss.cost_traffic,
                   ss.street_cat,
                   ss.x1,
                   ss.y1,
                   ss.x2,
                   ss.y2,
                   ss.id::DOUBLE PRECISION AS source_id,
                   ss.geom
            FROM start_seg ss

            UNION ALL

            SELECT nb.id,
                   nb.source,
                   nb.target,
                   nb.cost_time,
                   nb.cost_distance,
                   nb.cost_traffic,
                   nb.street_cat,
                   nb.x1,
                   nb.y1,
                   nb.x2,
                   nb.y2,
                   nb.source_id,
                   nb.geom
            FROM pgr._candidate_edges_array(
                         v_edges_table, v_start_cluster, v_center_x, v_center_y,
                         v_street_cat_inner, p_inner_limit
                 ) nb
            WHERE nb.id NOT IN (SELECT split_edge_id FROM split_id)

            UNION ALL

            SELECT fb.id,
                   fb.source,
                   fb.target,
                   fb.cost_time,
                   fb.cost_distance,
                   fb.cost_traffic,
                   fb.street_cat,
                   fb.x1,
                   fb.y1,
                   fb.x2,
                   fb.y2,
                   fb.source_id,
                   fb.geom
            FROM pgr._candidate_edges_isolines(
                         p_lon, p_lat, v_buffer_m, v_street_cat_outer
                 ) fb
            WHERE fb.id NOT IN (SELECT split_edge_id FROM split_id);
    END IF;


    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _preselection_isolines: %', v_elapsed_time;
END;
$function$;


-- ==== functions/_preselection_routes.sql ============================================================================

CREATE OR REPLACE FUNCTION pgr._preselection_routes(
    start_lon INTEGER,
    start_lat INTEGER,
    end_lon INTEGER,
    end_lat INTEGER,
    mode_of_transport TEXT,
    inner_limit INTEGER
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Preselects the network for the routing

DECLARE
    v_street_cat_inner  INTEGER[];
    v_street_cat_outer  INTEGER[];
    v_start_edges_table TEXT;
    v_end_edges_table   TEXT;
    v_mid_edges_table   TEXT;
    v_start_cluster     TEXT;
    v_end_cluster       TEXT;
    v_mid_cluster       TEXT;
    v_start_center_x    INTEGER;
    v_start_center_y    INTEGER;
    v_end_center_x      INTEGER;
    v_end_center_y      INTEGER;
    v_mid_center_x      INTEGER;
    v_mid_center_y      INTEGER;
    v_mid_lon           INTEGER;
    v_mid_lat           INTEGER;
    v_main_radius       INTEGER;
    v_start_time        TIMESTAMP;
    v_end_time          TIMESTAMP;
    v_elapsed_time      INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Parameter: street categories -----------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._mode_category(mode_of_transport, 'buffer')
    INTO v_street_cat_inner; -- categories per data source (pgr.loine_mode_category)

    SELECT pgr._mode_category(mode_of_transport, 'main') INTO v_street_cat_outer;
    -- categories per data source (pgr.loine_mode_category)

    --------------------------------------------------------------------------------------
    -- Parameter: grid coordinates ------------------------------------------------------
    --------------------------------------------------------------------------------------

    -- Start
    SELECT ROUND(start_lon::DOUBLE PRECISION / 100)::INTEGER INTO v_start_center_x;
    SELECT ROUND(start_lat::DOUBLE PRECISION / 100)::INTEGER INTO v_start_center_y;
    SELECT 'edges_n' || SUBSTR(start_lat::TEXT, 1, 2) || 'e' || SUBSTR(start_lon::TEXT, 1, 2)
    INTO v_start_edges_table;
    SELECT UPPER('N' || SUBSTR(start_lat::TEXT, 1, 3) || 'E' || SUBSTR(start_lon::TEXT, 1, 3))
    INTO v_start_cluster;

    -- End
    SELECT ROUND(end_lon::DOUBLE PRECISION / 100)::INTEGER INTO v_end_center_x;
    SELECT ROUND(end_lat::DOUBLE PRECISION / 100)::INTEGER INTO v_end_center_y;
    SELECT 'edges_n' || SUBSTR(end_lat::TEXT, 1, 2) || 'e' || SUBSTR(end_lon::TEXT, 1, 2)
    INTO v_end_edges_table;
    SELECT UPPER('N' || SUBSTR(end_lat::TEXT, 1, 3) || 'E' || SUBSTR(end_lon::TEXT, 1, 3))
    INTO v_end_cluster;

    -- centre point for the main network
    SELECT ((start_lon + end_lon) / 2)::INTEGER INTO v_mid_lon;
    SELECT ((start_lat + end_lat) / 2)::INTEGER INTO v_mid_lat;
    SELECT ROUND(v_mid_lon::DOUBLE PRECISION / 100)::INTEGER INTO v_mid_center_x;
    SELECT ROUND(v_mid_lat::DOUBLE PRECISION / 100)::INTEGER INTO v_mid_center_y;
    SELECT 'edges_n' || SUBSTR(v_mid_lat::TEXT, 1, 2) || 'e' || SUBSTR(v_mid_lon::TEXT, 1, 2)
    INTO v_mid_edges_table;
    SELECT UPPER('N' || SUBSTR(v_mid_lat::TEXT, 1, 3) || 'E' || SUBSTR(v_mid_lon::TEXT, 1, 3))
    INTO v_mid_cluster;

    -- dynamic radius: half the distance start–end + buffer
    SELECT (SQRT(
                    POWER((end_lon - start_lon)::DOUBLE PRECISION, 2) +
                    POWER((end_lat - start_lat)::DOUBLE PRECISION, 2)
            ) / 1 * 1.2)::INTEGER
    INTO v_main_radius;

    --------------------------------------------------------------------------------------
    -- Preselection ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    RETURN QUERY

        -- start segment
        SELECT ss.id,
               ss.source,
               ss.target,
               ss.cost_time,
               ss.cost_distance,
               ss.cost_traffic,
               ss.street_cat,
               ss.x1,
               ss.y1,
               ss.x2,
               ss.y2,
               ss.geom
        FROM pgr._starting_segment(start_lon, start_lat, mode_of_transport) ss

        UNION ALL

        -- end segment
        SELECT es.id,
               es.source,
               es.target,
               es.cost_time,
               es.cost_distance,
               es.cost_traffic,
               es.street_cat,
               es.x1,
               es.y1,
               es.x2,
               es.y2,
               es.geom
        FROM pgr._ending_segment(end_lon, end_lat, mode_of_transport) es

        UNION ALL

        -- start buffer area (street_cat_inner, fixed radius inner_limit)
        SELECT sb.id,
               sb.source,
               sb.target,
               sb.cost_time,
               sb.cost_distance,
               sb.cost_traffic,
               sb.street_cat,
               sb.x1,
               sb.y1,
               sb.x2,
               sb.y2,
               sb.geom
        FROM pgr._candidate_edges_array(
                     v_start_edges_table,
                     v_start_cluster,
                     v_start_center_x,
                     v_start_center_y,
                     v_street_cat_inner,
                     inner_limit
             ) sb

        UNION ALL

        -- end buffer area (street_cat_inner, fixed radius inner_limit)
        SELECT eb.id,
               eb.source,
               eb.target,
               eb.cost_time,
               eb.cost_distance,
               eb.cost_traffic,
               eb.street_cat,
               eb.x1,
               eb.y1,
               eb.x2,
               eb.y2,
               eb.geom
        FROM pgr._candidate_edges_array(
                     v_end_edges_table,
                     v_end_cluster,
                     v_end_center_x,
                     v_end_center_y,
                     v_street_cat_inner,
                     inner_limit
             ) eb

        UNION ALL

        -- main network (street_cat_outer, dynamic radius from the centre point)
        SELECT mn.id,
               mn.source,
               mn.target,
               mn.cost_time,
               mn.cost_distance,
               mn.cost_traffic,
               mn.street_cat,
               mn.x1,
               mn.y1,
               mn.x2,
               mn.y2,
               mn.geom
        FROM pgr._candidate_edges_cluster(
                     start_lon,
                     start_lat,
                     end_lon,
                     end_lat,
                     v_street_cat_outer
             ) mn;

    -- Base network (pgr.net_level, built in pgr.loine_finalize): country-wide network by density, as far as the
    -- edge budget allows next to the local preselection. This provides a connection even if the road runs outside
    -- the rectangle start–end (e.g. Windhoek ↔ Swakopmund). Without base network only the local preselection is used.
    IF TO_REGCLASS('pgr.net_level') IS NOT NULL AND EXISTS (SELECT 1 FROM pgr.net_level) THEN
        RETURN QUERY
            SELECT nl.id,
                   nl.source,
                   nl.target,
                   nl.cost_time,
                   nl.cost_distance,
                   nl.cost_traffic,
                   nl.street_cat,
                   nl.x1,
                   nl.y1,
                   nl.x2,
                   nl.y2,
                   nl.geom
            FROM pgr._net_level_edges(start_lon, start_lat, end_lon, end_lat, v_street_cat_inner,
                                      v_street_cat_outer) nl;
    END IF;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _preselection_routes: %', v_elapsed_time;
END;
$function$;


-- ==== functions/_srid.sql ===========================================================================================

CREATE OR REPLACE FUNCTION pgr._srid()
    RETURNS INTEGER
    LANGUAGE plpgsql
    STABLE
    PARALLEL SAFE
AS
$function$
    -- A database contains only countries of one region (checked by pgr.loine_install_country). The projection is stored in
    -- pgr.loine_installed.srid: Europe 3035, Africa 990001, North America 990002. Without entry (older installation): 3035.
    -- The functions transform input points (EPSG:4326) into metre coordinates of this projection and derive tile,
    -- cluster, grid cell and search radii from them.
DECLARE
    v_srid INTEGER;
BEGIN
    IF TO_REGCLASS('pgr.loine_installed') IS NOT NULL
        AND EXISTS (SELECT 1
                    FROM information_schema.columns
                    WHERE table_schema = 'pgr'
                      AND table_name = 'loine_installed'
                      AND column_name = 'srid') THEN
        EXECUTE 'SELECT MIN(srid) FROM pgr.loine_installed' INTO v_srid;
    END IF;
    RETURN COALESCE(v_srid, 3035);
END;
$function$;


-- ==== functions/_starting_segment.sql ===============================================================================

CREATE OR REPLACE FUNCTION pgr._starting_segment(
    lon INTEGER,
    lat INTEGER,
    mode_of_transport TEXT
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                split_edge_id BIGINT,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Finds the start segment and adds the necessary edges to the network

DECLARE
    v_start3035     GEOMETRY;
    v_sc_inner_low  SMALLINT;
    v_sc_inner_high SMALLINT;
    v_center_x      INTEGER;
    v_center_y      INTEGER;
    v_edges_table   TEXT[];
    v_cluster_ids   TEXT[];
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();
    --------------------------------------------------------------------------------------
    -- Parameter assignment -------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT (SELECT MIN(c) FROM UNNEST(pgr._mode_category(mode_of_transport, 'snap')) c) - 1 INTO v_sc_inner_low;

    SELECT (SELECT MAX(c) FROM UNNEST(pgr._mode_category(mode_of_transport, 'snap')) c) INTO v_sc_inner_high;

    SELECT st_setsrid(st_makepoint(lon, lat), pgr._srid())
    INTO v_start3035;

    -- grid coordinates rounded to the 100 m grid (for the grid join)
    SELECT ROUND(lon::DOUBLE PRECISION / 100)::INTEGER INTO v_center_x;
    SELECT ROUND(lat::DOUBLE PRECISION / 100)::INTEGER INTO v_center_y;

    -- derive partition and cluster names from the 4 corners of the search radius
    SELECT ARRAY_AGG(DISTINCT 'edges_n' || SUBSTR(y::TEXT, 1, 2) || 'e' || SUBSTR(x::TEXT, 1, 2))
    INTO v_edges_table
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    SELECT ARRAY_AGG(DISTINCT UPPER('N' || SUBSTR(y::TEXT, 1, 3) || 'E' || SUBSTR(x::TEXT, 1, 3)))
    INTO v_cluster_ids
    FROM (VALUES (lat - 500, lon - 500),
                 (lat - 500, lon + 500),
                 (lat + 500, lon - 500),
                 (lat + 500, lon + 500)) AS corners(y, x);

    ---------------------------------------------------------------------------------------
    -- Start segment for routes ----------------------------------------------------------
    ---------------------------------------------------------------------------------------

    RETURN QUERY
        WITH startpoint AS (SELECT v_start3035 AS geom),

             -- ------------------------------------------------------------------
             -- candidate edges via helper function (grid + partition + cluster)
             -- ------------------------------------------------------------------
             candidate_edges AS (SELECT ce.*
                                 FROM pgr._candidate_edges(
                                              v_edges_table,
                                              v_cluster_ids,
                                              v_center_x,
                                              v_center_y,
                                              v_sc_inner_low,
                                              v_sc_inner_high
                                      ) ce
                                 WHERE ce.street_cat = ANY (pgr._mode_category(mode_of_transport, 'snap')) -- categories per data source
                                   AND EXISTS (SELECT 1 FROM pgr.edges n WHERE n.source = ce.target)), -- only edges with a successor, otherwise no path leads away from the start

             closest_points AS (SELECT e.id                                                        AS cp_id,
                                       e.source                                                    AS cp_source,
                                       e.target                                                    AS cp_target,
                                       e.street_cat                                                AS cp_street_cat,
                                       e.cost_time                                                 AS cp_cost_time,
                                       e.cost_distance                                             AS cp_cost_distance,
                                       e.cost_traffic                                              AS cp_cost_traffic,
                                       e.speed_cat                                                 AS cp_speed_cat,
                                       e.x1                                                        AS cp_x1,
                                       e.y1                                                        AS cp_y1,
                                       e.x2                                                        AS cp_x2,
                                       e.y2                                                        AS cp_y2,
                                       e.geom                                                      AS cp_edge_geom,
                                       st_closestpoint(e.geom, s.geom)                             AS cp_snap_geom,
                                       st_distance(e.geom, s.geom)                                 AS cp_distance,
                                       st_linelocatepoint(e.geom, st_closestpoint(e.geom, s.geom)) AS cp_fraction
                                FROM candidate_edges e,
                                     startpoint s),

             min_distance AS (SELECT MIN(cp.cp_distance) AS md_dist
                              FROM closest_points cp),

             -- forward direction: first nearest edge
             nearest AS (SELECT cp.*
                         FROM closest_points cp,
                              min_distance md
                         WHERE cp.cp_distance = md.md_dist
                         LIMIT 1),

             -- backward direction: second nearest edge (same distance, other id)
             reverse_nearest AS (SELECT cp.*
                                 FROM closest_points cp,
                                      nearest n
                                 WHERE cp.cp_id != n.cp_id
                                   AND st_equals(st_startpoint(cp.cp_edge_geom), st_endpoint(n.cp_edge_geom))
                                   AND st_equals(st_endpoint(cp.cp_edge_geom), st_startpoint(n.cp_edge_geom))
                                 LIMIT 1),

             snap_decision AS (SELECT CASE
                                          WHEN n.cp_fraction <= 0.001 THEN 'source'
                                          WHEN n.cp_fraction >= 0.999 THEN 'target'
                                          ELSE 'split'
                                          END AS sd_snap_case,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_source
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_target
                                          ELSE NULL
                                          END AS sd_snap_node_id,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_x1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_x2
                                          ELSE NULL
                                          END AS sd_snap_x,
                                      CASE
                                          WHEN n.cp_fraction <= 0.001 THEN n.cp_y1
                                          WHEN n.cp_fraction >= 0.999 THEN n.cp_y2
                                          ELSE NULL
                                          END AS sd_snap_y,
                                      n.cp_id AS sd_edge_id
                               FROM nearest n),

             -- ------------------------------------------------------------------
             -- regular case: connecting edge start point (1) → projected point (2)
             -- ------------------------------------------------------------------
             split_connector AS (SELECT 1                                                                AS sort_order,
                                        1::BIGINT                                                        AS source,
                                        2::BIGINT                                                        AS target,
                                        NULL::INTEGER                                                    AS street_cat,
                                        0::INTEGER                                                       AS cost_time,
                                        0::INTEGER                                                       AS cost_distance,
                                        0::INTEGER                                                       AS cost_traffic,
                                        ROUND(st_x((SELECT sp.geom FROM startpoint sp)) / 100)::INTEGER  AS x1,
                                        ROUND(st_y((SELECT sp.geom FROM startpoint sp)) / 100)::INTEGER  AS y1,
                                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER                       AS x2,
                                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER                       AS y2,
                                        NULL::BIGINT                                                     AS split_edge_id,
                                        st_makeline((SELECT sp.geom FROM startpoint sp), n.cp_snap_geom) AS geom
                                 FROM nearest n,
                                      snap_decision sd
                                 WHERE sd.sd_snap_case = 'split'
                                 LIMIT 1),

             -- ------------------------------------------------------------------
             -- regular case: split segments
             -- part 1: source → projected point
             -- part 2: projected point → target
             -- part 3: projected point → source (reverse direction)
             -- part 4: target → projected point (reverse direction)
             -- ------------------------------------------------------------------
             split_segments AS (
                 -- part 1: source → projected point
                 SELECT 2                                                    AS sort_order,
                        n.cp_source                                          AS source,
                        2::BIGINT                                            AS target,
                        n.cp_street_cat::INTEGER                             AS street_cat,
                        CASE
                            WHEN n.cp_cost_time < 100000 THEN ROUND(
                                    n.cp_cost_time * st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                    NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_time,
                        CASE
                            WHEN n.cp_cost_distance < 100000
                                THEN ROUND(n.cp_cost_distance *
                                           st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                           NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE n.cp_cost_distance
                            END::INTEGER                                     AS cost_distance,
                        CASE
                            WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                       st_length(st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction)) /
                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_traffic,
                        n.cp_x1                                              AS x1,
                        n.cp_y1                                              AS y1,
                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER           AS x2,
                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER           AS y2,
                        n.cp_id                                              AS split_edge_id,
                        st_linesubstring(n.cp_edge_geom, 0.0, n.cp_fraction) AS geom
                 FROM nearest n,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 2: projected point → target
                 SELECT 2                                                    AS sort_order,
                        2::BIGINT                                            AS source,
                        n.cp_target                                          AS target,
                        n.cp_street_cat::INTEGER                             AS street_cat,
                        CASE
                            WHEN n.cp_cost_time < 100000 THEN ROUND(
                                    n.cp_cost_time * st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                    NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_time,
                        CASE
                            WHEN n.cp_cost_distance < 100000
                                THEN ROUND(n.cp_cost_distance *
                                           st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                           NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE n.cp_cost_distance
                            END::INTEGER                                     AS cost_distance,
                        CASE
                            WHEN n.cp_cost_traffic < 100000 THEN ROUND(n.cp_cost_traffic *
                                                                       st_length(st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0)) /
                                                                       NULLIF(st_length(n.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                        AS cost_traffic,
                        ROUND(st_x(n.cp_snap_geom) / 100)::INTEGER           AS x1,
                        ROUND(st_y(n.cp_snap_geom) / 100)::INTEGER           AS y1,
                        n.cp_x2                                              AS x2,
                        n.cp_y2                                              AS y2,
                        n.cp_id                                              AS split_edge_id,
                        st_linesubstring(n.cp_edge_geom, n.cp_fraction, 1.0) AS geom
                 FROM nearest n,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 3: projected point → source (reverse direction)
                 SELECT 2                                                      AS sort_order,
                        rn.cp_source                                           AS source,
                        2::BIGINT                                              AS target,
                        rn.cp_street_cat::INTEGER                              AS street_cat,
                        CASE
                            WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                     st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                     NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_time,
                        CASE
                            WHEN rn.cp_cost_distance < 100000
                                THEN ROUND(rn.cp_cost_distance *
                                           st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                           NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE rn.cp_cost_distance
                            END::INTEGER                                       AS cost_distance,
                        CASE
                            WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                        st_length(st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction)) /
                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_traffic,
                        ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER            AS x1,
                        ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER            AS y1,
                        rn.cp_x1                                               AS x2,
                        rn.cp_y1                                               AS y2,
                        rn.cp_id                                               AS split_edge_id,
                        st_linesubstring(rn.cp_edge_geom, 0.0, rn.cp_fraction) AS geom
                 FROM reverse_nearest rn,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'

                 UNION ALL

                 -- part 4: target → projected point (reverse direction)
                 SELECT 2                                                      AS sort_order,
                        2::BIGINT                                              AS source,
                        rn.cp_target                                           AS target,
                        rn.cp_street_cat::INTEGER                              AS street_cat,
                        CASE
                            WHEN rn.cp_cost_time < 100000 THEN ROUND(rn.cp_cost_time *
                                                                     st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                     NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_time,
                        CASE
                            WHEN rn.cp_cost_distance < 100000
                                THEN ROUND(rn.cp_cost_distance *
                                           st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                           NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE rn.cp_cost_distance
                            END::INTEGER                                       AS cost_distance,
                        CASE
                            WHEN rn.cp_cost_traffic < 100000 THEN ROUND(rn.cp_cost_traffic *
                                                                        st_length(st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0)) /
                                                                        NULLIF(st_length(rn.cp_edge_geom), 0))
                            ELSE 1000000 END::INTEGER                          AS cost_traffic,
                        rn.cp_x2                                               AS x1,
                        rn.cp_y2                                               AS y1,
                        ROUND(st_x(rn.cp_snap_geom) / 100)::INTEGER            AS x2,
                        ROUND(st_y(rn.cp_snap_geom) / 100)::INTEGER            AS y2,
                        rn.cp_id                                               AS split_edge_id,
                        st_linesubstring(rn.cp_edge_geom, rn.cp_fraction, 1.0) AS geom
                 FROM reverse_nearest rn,
                      snap_decision sd
                 WHERE sd.sd_snap_case = 'split'),

             -- ------------------------------------------------------------------
             -- snap case: connecting edge start point (1) → snap node (2)
             -- ------------------------------------------------------------------
             snap_connector AS (SELECT 1                                                               AS sort_order,
                                       1::BIGINT                                                       AS source,
                                       2::BIGINT                                                       AS target,
                                       NULL::INTEGER                                                   AS street_cat,
                                       0::INTEGER                                                      AS cost_time,
                                       0::INTEGER                                                      AS cost_distance,
                                       0::INTEGER                                                      AS cost_traffic,
                                       ROUND(st_x((SELECT sp.geom FROM startpoint sp)) / 100)::INTEGER AS x1,
                                       ROUND(st_y((SELECT sp.geom FROM startpoint sp)) / 100)::INTEGER AS y1,
                                       sd.sd_snap_x                                                    AS x2,
                                       sd.sd_snap_y                                                    AS y2,
                                       NULL::BIGINT                                                    AS split_edge_id,
                                       st_makeline(
                                               (SELECT sp.geom FROM startpoint sp),
                                               CASE
                                                   WHEN sd.sd_snap_case = 'source'
                                                       THEN st_startpoint(n.cp_edge_geom)
                                                   WHEN sd.sd_snap_case = 'target'
                                                       THEN st_endpoint(n.cp_edge_geom)
                                                   END
                                       )                                                               AS geom
                                FROM snap_decision sd,
                                     nearest n
                                WHERE sd.sd_snap_case IN ('source', 'target')),

             -- ------------------------------------------------------------------
             -- snap case: all segments at the snap node – only from candidate_edges
             -- ------------------------------------------------------------------
             snap_segments AS (SELECT 2                        AS sort_order,
                                      2::BIGINT                AS source,
                                      e.target                 AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id,
                                      e.geom
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.source = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target')


                               UNION ALL

                               SELECT 2                        AS sort_order,
                                      e.source                 AS source,
                                      2::BIGINT                AS target,
                                      e.street_cat::INTEGER    AS street_cat,
                                      e.cost_time::INTEGER     AS cost_time,
                                      e.cost_distance::INTEGER AS cost_distance,
                                      e.cost_traffic::INTEGER  AS cost_traffic,
                                      e.x1,
                                      e.y1,
                                      e.x2,
                                      e.y2,
                                      NULL::BIGINT             AS split_edge_id,
                                      e.geom
                               FROM candidate_edges e
                                        INNER JOIN snap_decision sd ON e.target = sd.sd_snap_node_id
                               WHERE sd.sd_snap_case IN ('source', 'target'))


        SELECT ROW_NUMBER() OVER (ORDER BY ns.sort_order, ns.source, ns.target),
               ns.source,
               ns.target,
               ns.cost_time,
               ns.cost_distance,
               ns.cost_traffic,
               ns.street_cat,
               ns.x1,
               ns.y1,
               ns.x2,
               ns.y2,
               ns.split_edge_id,
               ns.geom
        FROM (SELECT sc.sort_order,
                     sc.source,
                     sc.target,
                     sc.cost_time,
                     sc.cost_distance,
                     sc.cost_traffic,
                     sc.street_cat,
                     sc.x1,
                     sc.y1,
                     sc.x2,
                     sc.y2,
                     sc.split_edge_id,
                     sc.geom
              FROM split_connector sc
              UNION ALL
              SELECT sps.sort_order,
                     sps.source,
                     sps.target,
                     sps.cost_time,
                     sps.cost_distance,
                     sps.cost_traffic,
                     sps.street_cat,
                     sps.x1,
                     sps.y1,
                     sps.x2,
                     sps.y2,
                     sps.split_edge_id,
                     sps.geom
              FROM split_segments sps
              UNION ALL
              SELECT sc.sort_order,
                     sc.source,
                     sc.target,
                     sc.cost_time,
                     sc.cost_distance,
                     sc.cost_traffic,
                     sc.street_cat,
                     sc.x1,
                     sc.y1,
                     sc.x2,
                     sc.y2,
                     sc.split_edge_id,
                     sc.geom
              FROM snap_connector sc
              UNION ALL
              SELECT sns.sort_order,
                     sns.source,
                     sns.target,
                     sns.cost_time,
                     sns.cost_distance,
                     sns.cost_traffic,
                     sns.street_cat,
                     sns.x1,
                     sns.y1,
                     sns.x2,
                     sns.y2,
                     sns.split_edge_id,
                     sns.geom
              FROM snap_segments sns) AS ns
        ORDER BY ns.sort_order, ns.source, ns.target;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _starting_segment: %', v_elapsed_time;
END;
$function$;


-- ==== functions/cgo_costmatrix.sql ==================================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_costmatrix(
    input_table TEXT,
    mode_of_transport TEXT,
    calculation_type TEXT)
    RETURNS TABLE
            (
                start_id TEXT,
                end_id   TEXT,
                agg_cost NUMERIC
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Cost matrix between N input points (input_table: node_id, x, y in
    --              WGS84). Based on the pgRouting function pgr_astarcostmatrix
    --              (many-to-many A*, only_cost=true - no geometries). Respects restrictions
    --              (one-way streets) via reverse_cost + directed=true, as cgo_path.
    --              No geometries; the cost from a point to itself (start_id = end_id) is
    --              set to 0 directly instead of being calculated by pgr_astarcostmatrix.
    --              agg_cost for calculation_type 'time' in MINUTES (stored internally in
    --              seconds and converted, as in cgo_grids/cgo_segments), for 'distance'
    --              in METRES.

DECLARE
    ctrycode       TEXT;
    v_vids         BIGINT[];
    v_cost_col     TEXT;
    v_reverse_cost TEXT;
    v_edges_sql    TEXT;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;
BEGIN
    RAISE INFO 'cgo_costmatrix – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- input check (incl. reachability of every point) ---------------------------------
    --------------------------------------------------------------------------------------
    SELECT pgr._check_input_costmatrix(input_table, mode_of_transport, calculation_type)
    INTO ctrycode;

    --------------------------------------------------------------------------------------
    -- vids: all point_id of the input points -------------------------------------------
    --------------------------------------------------------------------------------------
    SELECT ARRAY_AGG(point_id)
    INTO v_vids
    FROM pgr._costmatrix_points(input_table);

    --------------------------------------------------------------------------------------
    -- cost/reverse_cost depending on calculation_type/mode_of_transport ----------------
    --------------------------------------------------------------------------------------
    v_cost_col := CASE WHEN calculation_type = 'time' THEN 'cost_time' ELSE 'cost_distance' END;
    v_reverse_cost := CASE
                          WHEN mode_of_transport IN ('pedestrian', 'no_mode') THEN v_cost_col
                          ELSE '-1'
        END;

    v_edges_sql := FORMAT(
            'SELECT DISTINCT ON (id) id, source, target, %I::DOUBLE PRECISION AS cost, %s::DOUBLE PRECISION AS reverse_cost, x1, y1, x2, y2
             FROM pgr._preselection_costmatrix(%L, %L)
             ORDER BY id',
            v_cost_col, v_reverse_cost, input_table, mode_of_transport
                   );

    --------------------------------------------------------------------------------------
    -- pgr_astarcostmatrix + translation start_vid/end_vid -> node_id -------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY
        WITH pts AS MATERIALIZED (SELECT * FROM pgr._costmatrix_points(input_table))

        -- pgr_astarcostmatrix returns NO start_vid = end_vid rows (tested) -
        -- the cost to itself is therefore added separately below and filtered
        -- out here defensively in case the behaviour of pgRouting changes.
        SELECT m1.node_id AS start_id,
               m2.node_id AS end_id,
               CASE
                   WHEN calculation_type = 'time' THEN ROUND((r.agg_cost / 60.0)::NUMERIC, 2)
                   ELSE ROUND(r.agg_cost::NUMERIC, 2)
                   END    AS agg_cost
        FROM pgr_astarcostmatrix(v_edges_sql, v_vids, TRUE) r
                 JOIN pts m1 ON m1.point_id = r.start_vid
                 JOIN pts m2 ON m2.point_id = r.end_vid
        WHERE r.start_vid != r.end_vid

        UNION ALL

        -- cost to itself: a point to itself is always 0, without routing
        SELECT node_id, node_id, 0::NUMERIC
        FROM pts;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_costmatrix: %', v_elapsed_time;
END;
$function$;


-- ==== functions/cgo_costmatrix_snap_report.sql ======================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_costmatrix_snap_report(
    input_table TEXT,
    mode_of_transport TEXT
)
    RETURNS TABLE
            (
                node_id  TEXT,
                x_input  DOUBLE PRECISION,
                y_input  DOUBLE PRECISION,
                x_used   DOUBLE PRECISION,
                y_used   DOUBLE PRECISION,
                offset_m NUMERIC
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Diagnostic function, one row per input point of input_table: the
    --              coordinates entered by the user (x_input/y_input) next to the snapped
    --              coordinates ACTUALLY USED for routing (x_used/y_used) and the offset
    --              between them in metres (offset_m). Uses the same point_connector row
    --              that _costmatrix_segment computes for snapping anyway - no new geometry
    --              calculation, only exposes existing intermediate results.
    --              UNLIKE pgr._check_input_costmatrix it does NOT abort if a point finds no
    --              matching street within 1000 m, but shows x_used/y_used/offset_m = NULL
    --              for this point - intended as a diagnostic tool BEFORE a cgo_costmatrix
    --              call, to identify exactly such points without the whole call aborting.
    --              Kept separate from cgo_costmatrix (not as additional columns of the
    --              N x N matrix), since the snap data of start and end points would
    --              otherwise be repeated in every row.

DECLARE
    v_street_cat INTEGER[];
BEGIN
    RAISE INFO 'cgo_costmatrix_snap_report – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    -- Parameter/structure check (as _check_input_costmatrix sections 1+2,
    -- WITHOUT calculation_type - irrelevant for a snap report - and WITHOUT
    -- the hard network/reachability aborts of sections 3+4, since exactly
    -- these cases are to be made visible here instead of prevented).
    IF mode_of_transport NOT IN ('card', 'care', 'caro', 'no_mode', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''card'', ''care'', ''caro'', ''no_mode'' or ''pedestrian''.';
    END IF;

    IF TO_REGCLASS(input_table) IS NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s does not exist.', input_table);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = input_table::regclass
                     AND attname = 'node_id'
                     AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = input_table::regclass
                         AND attname = 'x'
                         AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = input_table::regclass
                         AND attname = 'y'
                         AND NOT attisdropped)
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s must contain columns named node_id, x and y.', input_table);
    END IF;

    SELECT CASE mode_of_transport
               WHEN 'card' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'caro' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,13]
               WHEN 'care' THEN ARRAY [-1,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'no_mode' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14]
               WHEN 'pedestrian' THEN ARRAY [-1,5,4,6,7,8,9,10,11,12,13,14]
               END
    INTO v_street_cat;

    RETURN QUERY
        WITH pts AS MATERIALIZED (SELECT * FROM pgr._costmatrix_points(input_table))
        SELECT p.node_id,
               ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(p.lon, p.lat), pgr._srid()), 4326))          AS x_input,
               ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(p.lon, p.lat), pgr._srid()), 4326))          AS y_input,
               ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(cs.x2, cs.y2), pgr._srid()), 4326))          AS x_used,
               ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(cs.x2, cs.y2), pgr._srid()), 4326))          AS y_used,
               ROUND(ST_Distance(ST_MakePoint(p.lon, p.lat), ST_MakePoint(cs.x2, cs.y2))::NUMERIC, 1) AS offset_m
        FROM pts p
                 LEFT JOIN LATERAL pgr._costmatrix_segment(
                p.point_id, p.lot_id, p.id_offset, p.lon, p.lat, v_street_cat
                                   ) cs ON cs.source = p.point_id AND cs.target = p.lot_id;
END;
$function$;


-- ==== functions/cgo_grids.sql =======================================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_grids(
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_buffer_value NUMERIC,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT,
    p_direction TEXT)
    RETURNS TABLE
            (
                gitter_id_ TEXT,
                agg_cost   NUMERIC,
                geom       geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns grid cells reachable within buffer_value.
    --              Input in WGS84 (4326), internal calculation in the projection of the region (pgr._srid),
    --              output geometry transformed back to WGS84 (4326).
    --              Time/traffic costs input in minutes, internal in seconds,
    --              output back in minutes.


DECLARE
    v_lon3035         INTEGER;
    v_lat3035         INTEGER;
    v_point3035       GEOMETRY;
    v_ctrycode        TEXT;
    v_buffer_internal NUMERIC;
    v_inner_limit     INTEGER DEFAULT 1500;
    v_start_time      TIMESTAMP;
    v_end_time        TIMESTAMP;
    v_elapsed_time    INTERVAL;

BEGIN
    RAISE INFO 'cgo_grids – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Input-Check ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._check_input(p_lon, p_lat, p_mode_of_transport, p_calculation_type, p_direction)
    INTO v_ctrycode;

    --------------------------------------------------------------------------------------
    -- transformation 4326 → projection of the region (INTEGER) ------------------------
    --------------------------------------------------------------------------------------

    SELECT st_transform(st_setsrid(st_makepoint(p_lon, p_lat), 4326), pgr._srid())
    INTO v_point3035;

    SELECT ROUND(st_x(v_point3035))::INTEGER INTO v_lon3035;
    SELECT ROUND(st_y(v_point3035))::INTEGER INTO v_lat3035;
    --------------------------------------------------------------------------------------
    -- conversion minutes → seconds for the internal calculation ----------------------
    --------------------------------------------------------------------------------------

    SELECT CASE
               WHEN p_calculation_type IN ('time', 'traffic')
                   THEN p_buffer_value * 60
               ELSE p_buffer_value
               END
    INTO v_buffer_internal;

    --------------------------------------------------------------------------------------
    -- calculate grid cells + return --------------------------------------------------
    --------------------------------------------------------------------------------------

    RETURN QUERY
        SELECT g.gitter_id_,
               CASE
                   WHEN p_calculation_type IN ('time', 'traffic')
                       THEN (g.agg_cost / 60.0)::NUMERIC(10, 2)
                   ELSE g.agg_cost::NUMERIC(10, 2)
                   END                         AS agg_cost,
               st_transform(g.grid_geom, 4326) AS geom
        FROM pgr._grids_isolines(
                     v_lon3035,
                     v_lat3035,
                     v_buffer_internal,
                     p_calculation_type,
                     p_mode_of_transport,
                     p_direction,
                     v_inner_limit
             ) g;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_grids: %', v_elapsed_time;

END;
$function$;


-- ==== functions/cgo_isoline.sql =====================================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_isoline(
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_buffer_value NUMERIC,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT,
    p_direction TEXT
)
    RETURNS geometry
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns catchment area polygon based on grid cells.
    --              Input in WGS84 (4326), internal calculation in the projection of the region (pgr._srid),
    --              output transformed back to WGS84 (4326).

DECLARE
    v_lon3035      INTEGER;
    v_lat3035      INTEGER;
    v_point3035    GEOMETRY;
    v_buffer_value INTEGER;
    v_ctrycode     TEXT;
    v_catchment    GEOMETRY;
    v_inner_limit  INTEGER DEFAULT 1500;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;

BEGIN
    RAISE INFO 'cgo_isoline – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Input-Check ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._check_input(p_lon, p_lat, p_mode_of_transport, p_calculation_type, p_direction)
    INTO v_ctrycode;

    --------------------------------------------------------------------------------------
    -- transformation 4326 → projection of the region (INTEGER) ------------------------
    --------------------------------------------------------------------------------------

    SELECT st_transform(st_setsrid(st_makepoint(p_lon, p_lat), 4326), pgr._srid())
    INTO v_point3035;

    SELECT ROUND(st_x(v_point3035))::INTEGER INTO v_lon3035;
    SELECT ROUND(st_y(v_point3035))::INTEGER INTO v_lat3035;

    --------------------------------------------------------------------------------------
    -- convert minutes to seconds ------------------------------------------------------
    --------------------------------------------------------------------------------------

    v_buffer_value :=
            CASE WHEN p_calculation_type IN ('time', 'traffic') THEN p_buffer_value * 60 ELSE p_buffer_value END;

    --------------------------------------------------------------------------------------
    -- calculate catchment area -------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._catchment_isolines(
                   v_lon3035,
                   v_lat3035,
                   v_buffer_value,
                   p_calculation_type,
                   p_mode_of_transport,
                   p_direction,
                   v_inner_limit
           )
    INTO v_catchment;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_isoline: %', v_elapsed_time;

    --------------------------------------------------------------------------------------
    -- transformation back to 4326 ------------------------------------------------------
    --------------------------------------------------------------------------------------

    RETURN st_transform(v_catchment, 4326);

END;
$function$;


-- ==== functions/cgo_isoline_static.sql ==============================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_isoline_static(
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_buffer_value NUMERIC,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT,
    p_direction TEXT
)
    RETURNS geometry
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns catchment area polygon based on grid cells.
    --              Input in WGS84 (4326), internal calculation in the projection of the region (pgr._srid),
    --              output transformed back to WGS84 (4326).

DECLARE
    v_lon3035      INTEGER;
    v_lat3035      INTEGER;
    v_point3035    GEOMETRY;
    v_buffer_value INTEGER;
    v_ctrycode     TEXT;
    v_catchment    GEOMETRY;
    v_inner_limit  INTEGER DEFAULT 1500;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;

BEGIN
    RAISE INFO 'cgo_isoline_static – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Input-Check ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._check_input(p_lon, p_lat, p_mode_of_transport, p_calculation_type, p_direction)
    INTO v_ctrycode;

    --------------------------------------------------------------------------------------
    -- transformation 4326 → projection of the region (INTEGER) ------------------------
    --------------------------------------------------------------------------------------

    SELECT st_transform(st_setsrid(st_makepoint(p_lon, p_lat), 4326), pgr._srid())
    INTO v_point3035;

    SELECT ROUND(st_x(v_point3035))::INTEGER INTO v_lon3035;
    SELECT ROUND(st_y(v_point3035))::INTEGER INTO v_lat3035;

    --------------------------------------------------------------------------------------
    -- convert minutes to seconds ------------------------------------------------------
    --------------------------------------------------------------------------------------

    v_buffer_value :=
            CASE WHEN p_calculation_type IN ('time', 'traffic') THEN p_buffer_value * 60 ELSE p_buffer_value END;

    --------------------------------------------------------------------------------------
    -- calculate catchment area -------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._catchment_isolines_static(
                   v_lon3035,
                   v_lat3035,
                   v_buffer_value,
                   p_calculation_type,
                   p_mode_of_transport,
                   p_direction,
                   v_inner_limit
           )
    INTO v_catchment;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_isoline: %', v_elapsed_time;

    --------------------------------------------------------------------------------------
    -- transformation back to 4326 ------------------------------------------------------
    --------------------------------------------------------------------------------------

    RETURN st_transform(v_catchment, 4326);

END;
$function$;


-- ==== functions/cgo_multiisolines.sql ===============================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_multiisolines(
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_buffer_values TEXT,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT,
    p_direction TEXT
)
    RETURNS TABLE
            (
                id           INTEGER,
                buffer_value NUMERIC,
                isolines     geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Creates 1 to 5 isolines for one location.
    --              _grids_isolines called once with MAX(buffer_value).
    --              factor_buffer calculated dynamically per buffer_value.
    --              Input in WGS84 (4326), internal calculation in the projection of the region (pgr._srid),
    --              output geometry transformed back to WGS84 (4326).
    --              Time/traffic costs input in minutes, internal in seconds.

DECLARE
    v_lon3035          INTEGER;
    v_lat3035          INTEGER;
    v_point3035        GEOMETRY;
    v_ctrycode         TEXT;
    v_inner_limit      INTEGER DEFAULT 1500;
    v_max_buffer       NUMERIC;
    v_factor_buffer    DOUBLE PRECISION;
    v_maxi             INTEGER;
    v_zaehler          INTEGER;
    v_loop_bv          NUMERIC;
    v_loop_bv_internal NUMERIC;
    v_isochrone        GEOMETRY;
    v_start_time       TIMESTAMP;
    v_end_time         TIMESTAMP;
    v_elapsed_time     INTERVAL;

BEGIN
    RAISE INFO 'cgo_multiisolines – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Input-Check ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._check_input(p_lon, p_lat, p_mode_of_transport, p_calculation_type, p_direction)
    INTO v_ctrycode;

    --------------------------------------------------------------------------------------
    -- split and sort buffer values ----------------------------------------------------
    --------------------------------------------------------------------------------------

    DROP TABLE IF EXISTS tmp_input_buffer;
    CREATE TEMPORARY TABLE tmp_input_buffer AS
    SELECT ROW_NUMBER() OVER (ORDER BY bv) AS idn,
           bv
    FROM UNNEST(STRING_TO_ARRAY(p_buffer_values, ',')::NUMERIC[]) AS bv
    ORDER BY bv;

    SELECT COUNT(*) FROM tmp_input_buffer INTO v_maxi;

    IF v_maxi > 5 THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'You can calculate a maximum of five isochrones in one run using this function.';
    END IF;

    SELECT MAX(bv) FROM tmp_input_buffer INTO v_max_buffer;

    --------------------------------------------------------------------------------------
    -- transformation 4326 → projection of the region (INTEGER) ------------------------
    --------------------------------------------------------------------------------------

    SELECT st_transform(st_setsrid(st_makepoint(p_lon, p_lat), 4326), pgr._srid())
    INTO v_point3035;

    SELECT ROUND(st_x(v_point3035))::INTEGER INTO v_lon3035;
    SELECT ROUND(st_y(v_point3035))::INTEGER INTO v_lat3035;

    --------------------------------------------------------------------------------------
    -- run _grids_isolines once with MAX(buffer_value) ---------------------------------
    --------------------------------------------------------------------------------------

    DROP TABLE IF EXISTS tmp_grids;
    CREATE TEMPORARY TABLE tmp_grids AS
    SELECT *
    FROM pgr._grids_isolines(
            v_lon3035,
            v_lat3035,
            CASE
                WHEN p_calculation_type IN ('time', 'traffic')
                    THEN v_max_buffer * 60
                ELSE v_max_buffer
                END,
            p_calculation_type,
            p_mode_of_transport,
            p_direction,
            v_inner_limit
         );

    CREATE INDEX tmp_grids_agg_cost_idx ON tmp_grids USING btree (agg_cost);

    --------------------------------------------------------------------------------------
    -- WHILE loop: calculate a dynamic factor_buffer for each buffer_value -------------
    -- and build the polygon -----------------------------------------------------------
    --------------------------------------------------------------------------------------

    v_zaehler = 1;
    WHILE v_zaehler <= v_maxi
        LOOP

            SELECT bv FROM tmp_input_buffer WHERE idn = v_zaehler INTO v_loop_bv;

            SELECT CASE
                       WHEN p_calculation_type IN ('time', 'traffic')
                           THEN v_loop_bv * 60
                       ELSE v_loop_bv
                       END
            INTO v_loop_bv_internal;

            -- calculate factor_buffer dynamically per buffer_value
            SELECT ROUND(SQRT(st_area(st_union(grid_geom)::GEOGRAPHY))) / 7.5
            INTO v_factor_buffer
            FROM tmp_grids
            WHERE agg_cost <= v_loop_bv_internal;

            -- build polygon
            SELECT st_makepolygon(st_exteriorring(geom))
            INTO v_isochrone
            FROM (SELECT (st_dump(
                    st_buffer(
                            st_buffer(
                                    st_buffer(
                                            st_union(grid_geom)::GEOGRAPHY,
                                            v_factor_buffer / 2
                                    ),
                                    v_factor_buffer * -1
                            ),
                            v_factor_buffer / 2
                    )::GEOMETRY
                          )).geom AS geom
                  FROM tmp_grids
                  WHERE agg_cost <= v_loop_bv_internal) collect
            ORDER BY st_area(geom) DESC
            LIMIT 1;

            RETURN QUERY
                SELECT v_zaehler::INTEGER              AS id,
                       v_loop_bv                       AS buffer_value,
                       st_transform(v_isochrone, 4326) AS isolines;

            v_zaehler = v_zaehler + 1;

        END LOOP;

    DROP TABLE IF EXISTS tmp_grids;
    DROP TABLE IF EXISTS tmp_input_buffer;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_multiisolines: %', v_elapsed_time;

END;
$function$;


-- ==== functions/cgo_path.sql ========================================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_path(
    start_lon DOUBLE PRECISION,
    start_lat DOUBLE PRECISION,
    end_lon DOUBLE PRECISION,
    end_lat DOUBLE PRECISION,
    mode_of_transport TEXT,
    calculation_type TEXT
)
    RETURNS TABLE
            (
                route_time     NUMERIC,
                route_distance BIGINT,
                route_traffic  NUMERIC,
                geom           geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION : Create path based on to segments
DECLARE
    choose_cost  VARCHAR;
    ctrycode     VARCHAR(2);
    inner_limit  INTEGER DEFAULT 10000;
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
    start_point  GEOMETRY;
    end_point    GEOMETRY;
    v_start_lon  INTEGER;
    v_start_lat  INTEGER;
    v_end_lon    INTEGER;
    v_end_lat    INTEGER;
BEGIN
    RAISE INFO 'cgo_path – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    start_time = CLOCK_TIMESTAMP();
    -----------------------------------------------------------------------------------------------------------------------------------
    -- Start --checking INPUT / identification of the network ------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------------------------------------

    SELECT pgr._check_input_routes(start_lon, start_lat, end_lon, end_lat, mode_of_transport, calculation_type)
    INTO ctrycode;

    -----------------------------------------------------------------------------------------------------------------------------------
-- Start Selecting the streets
-----------------------------------------------------------------------------------------------------------------------------------

    SELECT CASE
               WHEN calculation_type = 'time' THEN 'cost_time'
               WHEN calculation_type = 'distance' THEN 'cost_distance'
               WHEN calculation_type = 'traffic' THEN 'cost_traffic'
               END AS choose_cost
    INTO choose_cost;

    start_point := st_transform(st_setsrid(st_makepoint(start_lon, start_lat), 4326), pgr._srid());
    end_point := st_transform(st_setsrid(st_makepoint(end_lon, end_lat), 4326), pgr._srid());

    v_start_lon := ROUND(st_x(start_point))::INTEGER;
    v_start_lat := ROUND(st_y(start_point))::INTEGER;
    v_end_lon := ROUND(st_x(end_point))::INTEGER;
    v_end_lat := ROUND(st_y(end_point))::INTEGER;
    -- End data preparation
------------------------------------------------------------------------------------------------------------------------------------
    IF
        ABS(start_lon - end_lon) < 0.001 AND ABS(start_lat - end_lat) < 0.001
    THEN
        RETURN QUERY
            SELECT 0::NUMERIC     AS route_time,
                   0::BIGINT      AS route_distance,
                   0::NUMERIC     AS route_traffic,
                   NULL::GEOMETRY AS geom;
    ELSIF mode_of_transport IN ('car', 'care', 'card', 'caro', 'carl')
    THEN
        -- Preselection only once: pgr_astar returns the nodes and edges of the route; costs and geometry then come
        -- from pgr.edges via the index on source, the start and end pieces again from _starting_segment /
        -- _ending_segment (virtual edges 1–5 and 10001–10005). No temporary table.
        -- DISTINCT ON (id): the preselection contains edges several times (buffer, rectangle and base network
        -- overlap); with duplicate edge ids pgr_astar returns wrong routes.
        RETURN QUERY
            EXECUTE
            '
            WITH route AS (SELECT r.node, r.edge
                           FROM pgr_astar(
                                    ''SELECT DISTINCT ON (id) id, source::bigint, target::bigint, ' || choose_cost || '::double precision AS cost,
                                             -1 AS reverse_cost, x1, y1, x2, y2
                                      FROM pgr._preselection_routes(' || v_start_lon || ',' || v_start_lat || ',' ||
            v_end_lon || ','
                || v_end_lat || ',''''' || mode_of_transport || ''''',' || inner_limit || ')'',
                                    1, 10001, true, 2) r
                           WHERE r.edge > 0),
                 net AS (SELECT e.id, e.cost_time, e.cost_distance, e.cost_traffic, e.geom
                         FROM route r
                                  CROSS JOIN LATERAL (SELECT e.id, e.cost_time, e.cost_distance, e.cost_traffic, e.geom
                                                      FROM pgr.edges e
                                                      WHERE e.source = r.node AND e.id = r.edge
                                                      LIMIT 1) e
                         UNION ALL
                         SELECT ss.id, ss.cost_time, ss.cost_distance, ss.cost_traffic, ss.geom
                         FROM pgr._starting_segment(' || v_start_lon || ',' || v_start_lat || ',''' ||
            mode_of_transport || ''') ss
                         WHERE ss.id IN (SELECT edge FROM route)
                         UNION ALL
                         SELECT es.id, es.cost_time, es.cost_distance, es.cost_traffic, es.geom
                         FROM pgr._ending_segment(' || v_end_lon || ',' || v_end_lat || ',''' || mode_of_transport || ''') es
                         WHERE es.id IN (SELECT edge FROM route))
            SELECT SUM(route_time)::NUMERIC(10,2)       AS route_time,
                   SUM(route_distance)::BIGINT          AS route_distance,
                   SUM(route_traffic)::NUMERIC(10,2)    AS route_traffic,
                   ST_Union(ST_Transform(geom, 4326))   AS geom
            FROM (SELECT DISTINCT ON (net.id)
                         net.cost_time / 60.0    AS route_time,
                         net.cost_distance       AS route_distance,
                         net.cost_traffic / 60.0 AS route_traffic,
                         net.geom
                  FROM net
                  WHERE geometrytype(net.geom) = ''LINESTRING'') AS route_segments;';

    END IF;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for cgo_path: %', elapsed_time;
END
    ;
$function$;


-- ==== functions/cgo_segments.sql ====================================================================================

CREATE OR REPLACE FUNCTION pgr.cgo_segments(
    p_lon DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_buffer_value NUMERIC,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT,
    p_direction TEXT
)
    RETURNS TABLE
            (
                id       BIGINT,
                agg_cost NUMERIC,
                geom     geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns network segments reachable within buffer_value.
    --              Input in WGS84 (4326), internal calculation in the projection of the region (pgr._srid),
    --              output geometry transformed back to WGS84 (4326).
    --              Time/traffic costs input in minutes, internal in seconds,
    --              output back in minutes.

DECLARE
    v_lon3035         INTEGER;
    v_lat3035         INTEGER;
    v_point3035       GEOMETRY;
    v_ctrycode        TEXT;
    v_buffer_internal NUMERIC;
    v_inner_limit     INTEGER DEFAULT 1500;
    v_start_time      TIMESTAMP;
    v_end_time        TIMESTAMP;
    v_elapsed_time    INTERVAL;

BEGIN
    RAISE INFO 'cgo_segments – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Input-Check ----------------------------------------------------------------------
    --------------------------------------------------------------------------------------

    SELECT pgr._check_input(p_lon, p_lat, p_mode_of_transport, p_calculation_type, p_direction)
    INTO v_ctrycode;

    --------------------------------------------------------------------------------------
    -- transformation 4326 → projection of the region (INTEGER) ------------------------
    --------------------------------------------------------------------------------------

    SELECT st_transform(st_setsrid(st_makepoint(p_lon, p_lat), 4326), pgr._srid())
    INTO v_point3035;

    SELECT ROUND(st_x(v_point3035))::INTEGER INTO v_lon3035;
    SELECT ROUND(st_y(v_point3035))::INTEGER INTO v_lat3035;

    --------------------------------------------------------------------------------------
    -- conversion minutes → seconds for the internal calculation ----------------------
    --------------------------------------------------------------------------------------

    SELECT CASE
               WHEN p_calculation_type IN ('time', 'traffic')
                   THEN p_buffer_value * 60
               ELSE p_buffer_value
               END
    INTO v_buffer_internal;

    --------------------------------------------------------------------------------------
    -- calculate segments + return ----------------------------------------------------
    --------------------------------------------------------------------------------------

    RETURN QUERY
        SELECT s.id,
               CASE
                   WHEN p_calculation_type IN ('time', 'traffic')
                       THEN (s.agg_cost / 60.0)::NUMERIC(10, 2)
                   ELSE s.agg_cost::NUMERIC(10, 2)
                   END                    AS agg_cost,
               st_transform(s.geom, 4326) AS geom
        FROM pgr._driving_distance_isolines(
                     v_lon3035,
                     v_lat3035,
                     v_buffer_internal,
                     p_calculation_type,
                     p_mode_of_transport,
                     p_direction,
                     v_inner_limit
             ) s
        WHERE geometrytype(s.geom) IN ('LINESTRING');

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_segments: %', v_elapsed_time;

END;
$function$;


-- ==== functions/loine_build_net_level.sql ===========================================================================

CREATE OR REPLACE PROCEDURE pgr.loine_build_net_level(
    p_budget BIGINT DEFAULT 1000000,
    p_min_global BIGINT DEFAULT NULL
)
    LANGUAGE plpgsql
AS
$procedure$
    -- Problem: The preselection of cgo_path takes the main network only from the rectangle between start and end (± 10 km).
-- In sparse networks the best path often runs outside it, resulting in no route or a detour. In dense networks the
-- rectangle is sufficient; a larger area only costs run time there.
--
-- Solution: The local preselection is complemented by a country-wide base network whose size depends on the density.
-- Budget (parameter p_budget, default 1 million edges ≈ 1.5 s load time for pgr_astar) for base network and local
-- preselection. The base network is stored in pgr.edges_global:
--   1. Backbone: all categories up to base_cat country-wide whose edges together make up at most half of the budget.
--   2. Fill per 100 km tile by density: for each tile and category above base_cat, the number of edges of the tile
--      up to this category is counted (cumulated from category 1). Filling starts with the sparsest level and goes up
--      until the budget is reached. Sparse tiles thus get the whole network, dense tiles only the backbone.
--   Each edge carries its rank prio (cumulated number of edges up to and including its level): backbone first
--   (by category), then the fill (sparsest level first).
-- p_min_global: edges of the base network that are always loaded per query (default = p_budget, the whole base network;
-- see pgr._net_level_edges).
--
-- The tables pgr.net_level, pgr.net_density and pgr.net_density_cluster are created by loine_install.sql.
-- pgr.loine_finalize calls CALL pgr.loine_build_net_level() (after the last country, again with every new delivery).
-- Custom values: CALL pgr.loine_build_net_level(p_budget => …, p_min_global => …);
DECLARE
    v_cats   INTEGER[] := pgr._net_level_cats();
    v_base   INTEGER;
    v_base_n BIGINT;
    v_n      BIGINT;
BEGIN
    TRUNCATE pgr.net_density;
    INSERT INTO pgr.net_density (partition_id, street_cat, n)
    SELECT e.partition_id, e.street_cat, COUNT(*)
    FROM pgr.edges e
    WHERE e.street_cat = ANY (v_cats)
    GROUP BY 1, 2;
    TRUNCATE pgr.net_density_cluster;
    INSERT INTO pgr.net_density_cluster (cluster_id, street_cat, n)
    SELECT e.cluster_id, e.street_cat, COUNT(*)
    FROM pgr.edges e
    WHERE e.street_cat > 0
    GROUP BY 1, 2;
    COMMIT;

    -- 1. Backbone: highest category whose edges make up at most half of the budget in the whole country
    SELECT MAX(c.street_cat), MAX(c.cum)
    INTO v_base, v_base_n
    FROM (SELECT d.street_cat, SUM(SUM(d.n)) OVER (ORDER BY d.street_cat) AS cum
          FROM pgr.net_density d
          GROUP BY d.street_cat) c
    WHERE c.cum <= p_budget / 2;
    v_base := COALESCE(v_base, 0);
    v_base_n := COALESCE(v_base_n, 0);

    -- Levels: backbone per category, then fill per tile and category (sparsest level first)
    DROP TABLE IF EXISTS pgr.net_level_step;
    CREATE TABLE pgr.net_level_step AS
    WITH base AS (SELECT NULL::TEXT AS partition_id, d.street_cat, SUM(d.n) AS n, 0 AS grp, d.street_cat::BIGINT AS ord
                  FROM pgr.net_density d
                  WHERE d.street_cat <= v_base
                  GROUP BY d.street_cat),
         fill AS (SELECT t.partition_id, t.street_cat, t.n, 1 AS grp, t.tile_cum AS ord
                  FROM (SELECT d.partition_id,
                               d.street_cat,
                               d.n,
                               SUM(d.n) OVER (PARTITION BY d.partition_id ORDER BY d.street_cat) AS tile_cum
                        FROM pgr.net_density d) t
                  WHERE t.street_cat > v_base),
         steps AS (SELECT * FROM base UNION ALL SELECT * FROM fill)
    SELECT s.partition_id,
           s.street_cat,
           s.n,
           SUM(s.n) OVER (ORDER BY s.grp, s.ord, s.street_cat, s.partition_id) AS prio
    FROM steps s;
    DELETE FROM pgr.net_level_step WHERE prio > GREATEST(p_budget, v_base_n);

    DROP TABLE IF EXISTS pgr.edges_global;
    CREATE TABLE pgr.edges_global AS
    SELECT e.id,
           e.source,
           e.target,
           e.speed_cat::INTEGER     AS speed_cat,
           e.street_cat::INTEGER    AS street_cat,
           e.cost_time::INTEGER     AS cost_time,
           e.cost_distance::INTEGER AS cost_distance,
           e.cost_traffic::INTEGER  AS cost_traffic,
           e.cluster_id,
           e.partition_id,
           e.x1,
           e.y1,
           e.x2,
           e.y2,
           e.geom,
           s.prio
    FROM pgr.edges e
             JOIN pgr.net_level_step s
                  ON s.street_cat = e.street_cat AND (s.partition_id IS NULL OR s.partition_id = e.partition_id)
    ORDER BY s.prio;
    SELECT COUNT(*) INTO v_n FROM pgr.edges_global;
    CREATE INDEX idx_pgr_edges_global_prio ON pgr.edges_global USING btree (prio);
    ANALYZE pgr.edges_global;

    TRUNCATE pgr.net_level;
    INSERT INTO pgr.net_level (budget, min_global, base_cat, global_n)
    VALUES (p_budget, COALESCE(p_min_global, p_budget), v_base, v_n); -- default: whole base network
    RAISE NOTICE 'net_level: budget %, backbone up to category % (% edges), base network % edges', p_budget, v_base, v_base_n, v_n;
END;
$procedure$;


-- ==== functions/loine_info.sql ======================================================================================

CREATE OR REPLACE FUNCTION pgr.loine_info(OUT version TEXT,
                                          OUT released DATE,
                                          OUT website TEXT,
                                          OUT contact TEXT,
                                          OUT license TEXT)
    LANGUAGE sql
    IMMUTABLE
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Version of the installed Loine software, website, contact and license.
    --              Version and release date are set with every release (same version as in the file VERSION).
SELECT '3.0.0',
       DATE '2026-11-02',
       'https://www.casageo.de/loine.html',
       'info@casageo.de',
       'AGPL-3.0-only or commercial license (casaGeo Data + Services GmbH)';
$function$;


COMMIT;

DO
$$
    BEGIN
        RAISE INFO 'Loine % (%) installed – %', (pgr.loine_info()).version, (pgr.loine_info()).released,
            (pgr.loine_info()).website;
    END
$$;
