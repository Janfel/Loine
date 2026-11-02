CREATE OR REPLACE FUNCTION pgr._candidate_edges_array(
    p_edges_table TEXT,
    p_start_cluster TEXT,
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_street_cat INTEGER[],
    p_radius_m INTEGER DEFAULT 500
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
    -- DESCRIPTION: Selects edges using x1/y1 range filter (100m grid)
    --              within a given radius around a center point.
    --              cluster_id filter retained for local precision.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_x1_min       INTEGER;
    v_x1_max       INTEGER;
    v_y1_min       INTEGER;
    v_y1_max       INTEGER;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;
BEGIN
    --------------------------------------------------------------------------------------
    -- range limits on the 100 m grid --------------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time = CLOCK_TIMESTAMP();
    v_x1_min := FLOOR((p_center_x * 100 - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_x1_max := CEIL((p_center_x * 100 + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_min := FLOOR((p_center_y * 100 - p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;
    v_y1_max := CEIL((p_center_y * 100 + p_radius_m)::DOUBLE PRECISION / 100)::INTEGER;

    --------------------------------------------------------------------------------------
    -- query with x1/y1 range filter + cluster_id -------------------------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY
        EXECUTE FORMAT(
            'SELECT DISTINCT ON (e.id)
                e.id,
                e.source,
                e.target,
                e.speed_cat::INTEGER,
                e.street_cat::INTEGER,
                e.cost_time::INTEGER,
                e.cost_distance::INTEGER,
                e.cost_traffic::INTEGER,
                e.cluster_id,
                e.partition_id,
                e.x1,
                e.y1,
                e.x2,
                e.y2,
                e.source_id,
                e.geom
            FROM pgr.%I AS e
            WHERE e.x1 BETWEEN %s AND %s
              AND e.y1 BETWEEN %s AND %s
              AND e.street_cat = ANY(%L::INTEGER[])
              AND e.cluster_id = %L
            ORDER BY e.id',
            p_edges_table,
            v_x1_min,
            v_x1_max,
            v_y1_min,
            v_y1_max,
            p_street_cat,
            p_start_cluster
                );
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _candidate_edges_array: %', v_elapsed_time;
END;
$function$;
