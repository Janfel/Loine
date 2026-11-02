CREATE OR REPLACE FUNCTION pgr._check_input_costmatrix(
    p_input_table TEXT,
    p_mode_of_transport TEXT,
    p_calculation_type TEXT
)
    RETURNS TEXT
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION : checks the input for cgo_costmatrix, if it's correct.
/*
 The function will check the input for cgo_costmatrix. If the input is not correct the function will be
 stopped and the user gets an error message.
 */
DECLARE
    ctrycode           TEXT;
    v_x_type           TEXT;
    v_y_type           TEXT;
    v_outside_list     TEXT;
    v_street_cat       INTEGER[];
    v_unreachable_list TEXT;
    start_time         TIMESTAMP;
    end_time           TIMESTAMP;
    elapsed_time       INTERVAL;
BEGIN
    start_time = CLOCK_TIMESTAMP();

    -- 1. parameter domains (as _check_input / _check_input_routes)
    IF p_mode_of_transport NOT IN ('card', 'care', 'caro', 'no_mode', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''card'', ''care'', ''caro'', ''no_mode'' or ''pedestrian''.';
    ELSEIF p_calculation_type NOT IN ('distance', 'time')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = 'Input for Calculation_type should be ''distance'' or ''time''.';
    END IF;

    -- 2. input_table: required columns with the EXACT names node_id, x, y.
    --    (Positional column aliases FROM ... AS t(node_id,x,y) rename only the
    --    first 3 columns - a 4th or later column with the same name (e.g. a
    --    column "y") led to "column reference is not unique". Fixed required
    --    names are more robust and simpler.)
    IF TO_REGCLASS(p_input_table) IS NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s does not exist.', p_input_table);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = p_input_table::regclass
                     AND attname = 'node_id'
                     AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = p_input_table::regclass
                         AND attname = 'x'
                         AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = p_input_table::regclass
                         AND attname = 'y'
                         AND NOT attisdropped)
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s must contain columns named node_id, x and y.', p_input_table);
    END IF;

    SELECT a.atttypid::regtype::TEXT
    INTO v_x_type
    FROM pg_attribute a
    WHERE a.attrelid = p_input_table::regclass
      AND a.attname = 'x'
      AND NOT a.attisdropped;

    SELECT a.atttypid::regtype::TEXT
    INTO v_y_type
    FROM pg_attribute a
    WHERE a.attrelid = p_input_table::regclass
      AND a.attname = 'y'
      AND NOT a.attisdropped;

    IF v_x_type NOT IN ('double precision', 'real', 'numeric')
        OR v_y_type NOT IN ('double precision', 'real', 'numeric')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'Columns x and y of %s must be of type double precision, real or numeric.',
                    p_input_table);
    END IF;

    -- 3. All points must lie within the network. Affected node_id(s) are named
    --    in the error message (consistent with section 4).
    EXECUTE FORMAT(
            'SELECT STRING_AGG(t.node_id::text, '', '' ORDER BY t.node_id) FROM %s AS t
             WHERE NOT EXISTS (
                 SELECT 1 FROM pgr.cluster c
                 WHERE st_within(st_setsrid(st_makepoint(t.x, t.y), 4326), c.geom)
             )', p_input_table::regclass
            ) INTO v_outside_list;

    IF v_outside_list IS NOT NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'The following node_id(s) in %I are outside the network: %s.',
                    p_input_table, v_outside_list);
    END IF;

    -- 4. Reachability: every point must find at least one edge of the selected
    --    (mode-filtered) network within the standard search radius (1000 m, as
    --    _starting_segment/_ending_segment/_costmatrix_segment). Otherwise the
    --    point would remain isolated and unreachable in the result -
    --    _costmatrix_segment deliberately returns NO rows for it (no artificial
    --    zero-cost connector of arbitrary length), so this must be caught here
    --    BEFOREHAND with a clear error message.
    SELECT CASE p_mode_of_transport
               WHEN 'card' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'caro' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,13]
               WHEN 'care' THEN ARRAY [-1,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'no_mode' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14]
               WHEN 'pedestrian' THEN ARRAY [-1,5,4,6,7,8,9,10,11,12,13,14]
               END
    INTO v_street_cat;

    EXECUTE FORMAT(
            'WITH pts AS (
                 SELECT
                     t.node_id,
                     ROUND(ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lon,
                     ROUND(ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lat
                 FROM %s AS t
             ),
             checked AS (
                 SELECT p.node_id,
                        EXISTS (
                            SELECT 1
                            FROM pgr._candidate_edges_radius_costmatrix(
                                     ARRAY[''edges_n'' || SUBSTR(p.lat::TEXT, 1, 2) || ''e'' || SUBSTR(p.lon::TEXT, 1, 2)],
                                     ARRAY[UPPER(''N'' || SUBSTR(p.lat::TEXT, 1, 3) || ''E'' || SUBSTR(p.lon::TEXT, 1, 3))],
                                     ROUND(p.lon::DOUBLE PRECISION / 100)::INTEGER,
                                     ROUND(p.lat::DOUBLE PRECISION / 100)::INTEGER,
                                     %L::INTEGER[], 1000
                                 ) c
                        ) AS reachable
                 FROM pts p
             )
             SELECT STRING_AGG(node_id::text, '', '' ORDER BY node_id) FROM checked WHERE NOT reachable',
            p_input_table::regclass, v_street_cat
            ) INTO v_unreachable_list;

    IF v_unreachable_list IS NOT NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT(
                    'The following node_id(s) have no street matching mode_of_transport %s within 1000 m: %s.',
                    p_mode_of_transport, v_unreachable_list);
    END IF;

    end_time = CLOCK_TIMESTAMP();
    elapsed_time = end_time - start_time;
    RAISE NOTICE 'Execution Time for _check_input_costmatrix: %', elapsed_time;
    RETURN ctrycode;
END;
$function$;
