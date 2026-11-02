CREATE OR REPLACE FUNCTION pgr.cgo_costmatrix(
    input_table TEXT,
    mode_of_transport TEXT,
    calculation_type TEXT)
    RETURNS TABLE
            (
                start_id TEXT,
                end_id   TEXT,
                agg_cost NUMERIC
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Cost matrix between N input points (input_table: node_id, x, y in
    --              WGS84). Based on the pgRouting function pgr_astarcostmatrix
    --              (many-to-many A*, only_cost=true - no geometries). Respects restrictions
    --              (one-way streets) via reverse_cost + directed=true, as cgo_path.
    --              No geometries; the cost from a point to itself (start_id = end_id) is
    --              set to 0 directly instead of being calculated by pgr_astarcostmatrix.
    --              agg_cost for calculation_type 'time' in MINUTES (stored internally in
    --              seconds and converted, as in cgo_grids/cgo_segments), for 'distance'
    --              in METRES.

DECLARE
    ctrycode       TEXT;
    v_vids         BIGINT[];
    v_cost_col     TEXT;
    v_reverse_cost TEXT;
    v_edges_sql    TEXT;
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_elapsed_time INTERVAL;
BEGIN
    RAISE INFO 'cgo_costmatrix – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- input check (incl. reachability of every point) ---------------------------------
    --------------------------------------------------------------------------------------
    SELECT pgr._check_input_costmatrix(input_table, mode_of_transport, calculation_type)
    INTO ctrycode;

    --------------------------------------------------------------------------------------
    -- vids: all point_id of the input points -------------------------------------------
    --------------------------------------------------------------------------------------
    SELECT ARRAY_AGG(point_id)
    INTO v_vids
    FROM pgr._costmatrix_points(input_table);

    --------------------------------------------------------------------------------------
    -- cost/reverse_cost depending on calculation_type/mode_of_transport ----------------
    --------------------------------------------------------------------------------------
    v_cost_col := CASE WHEN calculation_type = 'time' THEN 'cost_time' ELSE 'cost_distance' END;
    v_reverse_cost := CASE
                          WHEN mode_of_transport IN ('pedestrian', 'no_mode') THEN v_cost_col
                          ELSE '-1'
        END;

    v_edges_sql := FORMAT(
            'SELECT DISTINCT ON (id) id, source, target, %I::DOUBLE PRECISION AS cost, %s::DOUBLE PRECISION AS reverse_cost, x1, y1, x2, y2
             FROM pgr._preselection_costmatrix(%L, %L)
             ORDER BY id',
            v_cost_col, v_reverse_cost, input_table, mode_of_transport
                   );

    --------------------------------------------------------------------------------------
    -- pgr_astarcostmatrix + translation start_vid/end_vid -> node_id -------------------
    --------------------------------------------------------------------------------------
    RETURN QUERY
        WITH pts AS MATERIALIZED (SELECT * FROM pgr._costmatrix_points(input_table))

        -- pgr_astarcostmatrix returns NO start_vid = end_vid rows (tested) -
        -- the cost to itself is therefore added separately below and filtered
        -- out here defensively in case the behaviour of pgRouting changes.
        SELECT m1.node_id AS start_id,
               m2.node_id AS end_id,
               CASE
                   WHEN calculation_type = 'time' THEN ROUND((r.agg_cost / 60.0)::NUMERIC, 2)
                   ELSE ROUND(r.agg_cost::NUMERIC, 2)
                   END    AS agg_cost
        FROM pgr_astarcostmatrix(v_edges_sql, v_vids, TRUE) r
                 JOIN pts m1 ON m1.point_id = r.start_vid
                 JOIN pts m2 ON m2.point_id = r.end_vid
        WHERE r.start_vid != r.end_vid

        UNION ALL

        -- cost to itself: a point to itself is always 0, without routing
        SELECT node_id, node_id, 0::NUMERIC
        FROM pts;

    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for cgo_costmatrix: %', v_elapsed_time;
END;
$function$;
