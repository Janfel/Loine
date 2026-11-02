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
