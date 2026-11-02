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
