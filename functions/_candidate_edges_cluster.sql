CREATE OR REPLACE FUNCTION pgr._candidate_edges_cluster(
    p_start_lon INTEGER,
    p_start_lat INTEGER,
    p_end_lon INTEGER,
    p_end_lat INTEGER,
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
                geom          geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects edges using both partition_id (100km) and cluster_id (10km)
    --              to minimize index scans and enable partition pruning.

DECLARE
    v_cluster_ids   TEXT[];
    v_partition_ids TEXT[];
    v_sql           TEXT;
    v_part          TEXT;
BEGIN
    --------------------------------------------------------------------------------------
    -- 1. derive cluster ids (10 km grid) ----------------------------------------------
    --------------------------------------------------------------------------------------
    -- generate_series builds the set efficiently without loop overhead
    SELECT ARRAY(
                   SELECT 'N' || LPAD(y::TEXT, 3, '0') || 'E' || LPAD(x::TEXT, 3, '0')
                   FROM GENERATE_SERIES(
                                (FLOOR(LEAST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 10000)::INTEGER - 1),
                                (FLOOR(GREATEST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 10000)::INTEGER + 1)
                        ) AS x,
                        GENERATE_SERIES(
                                (FLOOR(LEAST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 10000)::INTEGER - 1),
                                (FLOOR(GREATEST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 10000)::INTEGER + 1)
                        ) AS y
           )
    INTO v_cluster_ids;

    --------------------------------------------------------------------------------------
    -- 2. derive partition ids (100 km grid) -------------------------------------------
    --------------------------------------------------------------------------------------
    -- IMPORTANT: allows PostgreSQL to skip 99 % of the table partitions immediately.
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(
                                      (FLOOR(LEAST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR(GREATEST(p_start_lon, p_end_lon)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS x,
                              GENERATE_SERIES(
                                      (FLOOR(LEAST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 100000)::INTEGER),
                                      (FLOOR(GREATEST(p_start_lat, p_end_lat)::DOUBLE PRECISION / 100000)::INTEGER)
                              ) AS y) generated
                            INNER JOIN pgr.partition p ON p.partition_id = generated.partition_id
           )
    INTO v_partition_ids;


    v_sql := '';
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;

            -- direct access to the physical partition table (e.g. pgr.edges_n04e01)
            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target, speed_cat::INTEGER, street_cat::INTEGER,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            cluster_id, partition_id, x1, y1, x2, y2, geom
                     FROM pgr.edges_%s
                     WHERE cluster_id = ANY($1)
                       AND street_cat = ANY($2)',
                    LOWER(v_part)
                              );
        END LOOP;

    --------------------------------------------------------------------------------------
    -- 3. final query with two-stage filter --------------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY EXECUTE v_sql USING v_cluster_ids, p_street_cat;

END;
$function$;
