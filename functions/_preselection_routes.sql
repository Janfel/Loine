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
