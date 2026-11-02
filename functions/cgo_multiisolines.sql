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
