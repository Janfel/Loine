CREATE OR REPLACE FUNCTION pgr._check_input_routes(
    start_lon DOUBLE PRECISION,
    start_lat DOUBLE PRECISION,
    end_lon DOUBLE PRECISION,
    end_lat DOUBLE PRECISION,
    mode_of_transport TEXT,
    calculation_type TEXT
)
    RETURNS TEXT
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
DECLARE
    ctrycode     TEXT;
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();
    ----------------------------------------------------------------------------------------------------------
    -- DESCRIPTION : checks the input, if it's correct.
    -----------------------------------------------------------------------------------------------------------
/*
 The function will check the input for the main function. If the input is not correct the function will be stopped and
 the user gets an error message.
 */
    IF mode_of_transport NOT IN ('card', 'car', 'caro', 'care', 'carl', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''car'', ''card'',''care'', ''carl'', ''caro'' or ''pedestrian''.';
    ELSEIF calculation_type NOT IN ('distance', 'time', 'traffic')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'', ''time''or ''traffic''.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(start_lon, start_lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The startpoint is outside the network.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(end_lon, end_lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The endpoint is outside the network.';
    END IF;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input_routes: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;
