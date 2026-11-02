CREATE OR REPLACE FUNCTION pgr._buffer_isolines(
    buffer_value NUMERIC,
    calculation_type TEXT,
    mode_of_transport TEXT
)
    RETURNS NUMERIC
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$

    -- DESCRIPTION : Creates a buffer to preselect the data based on buffer value and speed category of mode of transport.
DECLARE
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    elapsed_time INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();
    RETURN
        CASE
            WHEN calculation_type IN ('time', 'traffic') AND
                 mode_of_transport IN ('card', 'care', 'caro', 'car', 'carl')
                THEN (130 * buffer_value / 3600) * 1000
            WHEN calculation_type = 'time' AND mode_of_transport = 'pedestrian'
                THEN (5 * buffer_value / 3600) * 1000 + 1000
            ELSE buffer_value
            END;
    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE INFO 'Execution time for Buffer is % ', elapsed_time;
END
    ;
$function$;
