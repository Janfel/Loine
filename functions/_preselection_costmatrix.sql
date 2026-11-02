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
