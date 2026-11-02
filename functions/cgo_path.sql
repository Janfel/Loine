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
