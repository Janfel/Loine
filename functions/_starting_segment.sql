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
