CREATE OR REPLACE FUNCTION pgr._candidate_grids_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_radius_m INTEGER
)
    RETURNS TABLE
            (
                id                      BIGINT,
                source                  BIGINT,
                target                  BIGINT,
                source_id               DOUBLE PRECISION,
                gitter_id_              TEXT,
                grid_1km                TEXT,
                grid_time               INTEGER,
                grid_distance           INTEGER,
                grid_traffic            INTEGER,
                grid_factor             DOUBLE PRECISION,
                distance_to_grid_factor DOUBLE PRECISION,
                cost_time               INTEGER,
                cost_distance           INTEGER,
                cost_traffic            INTEGER,
                street_cat              INTEGER,
                x1                      INTEGER,
                y1                      INTEGER,
                grid_geom               geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects grid cells using partition_id (100km) for partition pruning
    --              and x1/y1 range filter (100m grid) for spatial selection.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
    v_x1_min        INTEGER;
    v_x1_max        INTEGER;
    v_y1_min        INTEGER;
    v_y1_max        INTEGER;
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;
BEGIN
    --------------------------------------------------------------------------------------
    -- 1. range limits on the 100 m grid -----------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time = CLOCK_TIMESTAMP();
    v_x1_min := FLOOR((p_lon - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_x1_max := CEIL((p_lon + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_min := FLOOR((p_lat - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_max := CEIL((p_lat + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;

    --------------------------------------------------------------------------------------
    -- 2. derive partition ids (100 km grid) ------------------------------------------
    --------------------------------------------------------------------------------------
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(
                                      (FLOOR((p_lon - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lon + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS x,
                              GENERATE_SERIES(
                                      (FLOOR((p_lat - p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR((p_lat + p_radius_m)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS y) generated
                            INNER JOIN pgr.partition p ON p.partition_id = generated.partition_id
           )
    INTO v_partition_ids;

    --------------------------------------------------------------------------------------
    -- 3. dynamic SQL: one query per partition (partition pruning) ----------------------
    --------------------------------------------------------------------------------------
    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, source_id, gitter_id_, grid_1km,
                            grid_time, grid_distance, grid_traffic,
                            grid_factor, distance_to_grid_factor,
                            cost_time, cost_distance, cost_traffic,
                            street_cat::INTEGER,
                            x1, y1,
                            grid_geom
                     FROM pgr.grids_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s',
                    LOWER(v_part),
                    v_x1_min,
                    v_x1_max,
                    v_y1_min,
                    v_y1_max
                              );
        END LOOP;
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for candidate_grids_isolines: %', v_elapsed_time;
    --------------------------------------------------------------------------------------
    -- 4. final query -------------------------------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql;

END;
$function$;
