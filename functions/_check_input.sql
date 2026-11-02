CREATE OR REPLACE FUNCTION pgr._check_input(
    lon DOUBLE PRECISION,
    lat DOUBLE PRECISION,
    mode_of_transport TEXT,
    calculation_type TEXT,
    direction TEXT
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
    IF mode_of_transport NOT IN ('card', 'car', 'caro', 'care', 'pedestrian', 'no_mode')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''car'', ''card'',''care'', ''caro'', ''pedestrian'' or ''no_mode''.';
    ELSEIF calculation_type NOT IN ('distance', 'time', 'traffic')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'', ''time'' or ''traffic''.';
    ELSEIF direction NOT IN ('from', 'to')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Direction should be ''from'' or ''to''.';
    END IF;
    IF (SELECT cluster_id
        FROM pgr.cluster cluster
        WHERE st_within(st_setsrid(st_makepoint(lon, lat), 4326), cluster.geom)
        LIMIT 1) IS NULL
    THEN
        RAISE EXCEPTION 'The startpoint is outside the network.';
    END IF;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;
