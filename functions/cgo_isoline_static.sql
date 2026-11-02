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
