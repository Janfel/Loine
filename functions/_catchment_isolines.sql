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
