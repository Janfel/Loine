CREATE OR REPLACE FUNCTION pgr._candidate_edges_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_radius_m INTEGER,
    p_street_cat INTEGER[]
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                speed_cat     INTEGER,
                street_cat    INTEGER,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                cluster_id    TEXT,
                partition_id  TEXT,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER,
                source_id     DOUBLE PRECISION,
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects edges using partition_id (100km) for partition pruning
    --              and x1/y1 range filter for spatial selection.
    --              No cluster array, no subcluster array.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_elapsed_time  INTERVAL;
BEGIN
    v_start_time = CLOCK_TIMESTAMP();
    --------------------------------------------------------------------------------------
    -- 1. derive partition ids (100 km grid) --------------------------------------------
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
    -- 2. dynamic SQL: one query per partition (partition pruning) ----------------------
    --------------------------------------------------------------------------------------
    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, speed_cat::INTEGER, street_cat::INTEGER,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            cluster_id, partition_id, x1, y1, x2, y2,
                            source_id,
                            geom
                     FROM pgr.edges_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s
                       AND street_cat = ANY($1)',
                    LOWER(v_part),
                    ROUND((p_lon - p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lon + p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lat - p_radius_m) / 100.0)::INTEGER,
                    ROUND((p_lat + p_radius_m) / 100.0)::INTEGER
                              );
        END LOOP;
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _candidate_edges_isolines: %', v_elapsed_time;
    --------------------------------------------------------------------------------------
    -- 3. final query -------------------------------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql USING p_street_cat;

END;
$function$;
