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
