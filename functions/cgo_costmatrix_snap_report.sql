CREATE OR REPLACE FUNCTION pgr.cgo_costmatrix_snap_report(
    input_table TEXT,
    mode_of_transport TEXT
)
    RETURNS TABLE
            (
                node_id  TEXT,
                x_input  DOUBLE PRECISION,
                y_input  DOUBLE PRECISION,
                x_used   DOUBLE PRECISION,
                y_used   DOUBLE PRECISION,
                offset_m NUMERIC
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Diagnostic function, one row per input point of input_table: the
    --              coordinates entered by the user (x_input/y_input) next to the snapped
    --              coordinates ACTUALLY USED for routing (x_used/y_used) and the offset
    --              between them in metres (offset_m). Uses the same point_connector row
    --              that _costmatrix_segment computes for snapping anyway - no new geometry
    --              calculation, only exposes existing intermediate results.
    --              UNLIKE pgr._check_input_costmatrix it does NOT abort if a point finds no
    --              matching street within 1000 m, but shows x_used/y_used/offset_m = NULL
    --              for this point - intended as a diagnostic tool BEFORE a cgo_costmatrix
    --              call, to identify exactly such points without the whole call aborting.
    --              Kept separate from cgo_costmatrix (not as additional columns of the
    --              N x N matrix), since the snap data of start and end points would
    --              otherwise be repeated in every row.

DECLARE
    v_street_cat INTEGER[];
BEGIN
    RAISE INFO 'cgo_costmatrix_snap_report – Loine % – %', (pgr.loine_info()).version, (pgr.loine_info()).website;
    -- Parameter/structure check (as _check_input_costmatrix sections 1+2,
    -- WITHOUT calculation_type - irrelevant for a snap report - and WITHOUT
    -- the hard network/reachability aborts of sections 3+4, since exactly
    -- these cases are to be made visible here instead of prevented).
    IF mode_of_transport NOT IN ('card', 'care', 'caro', 'no_mode', 'pedestrian')
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT =
                    'Input for Mode_of_transport should be ''card'', ''care'', ''caro'', ''no_mode'' or ''pedestrian''.';
    END IF;

    IF TO_REGCLASS(input_table) IS NULL THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s does not exist.', input_table);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = input_table::regclass
                     AND attname = 'node_id'
                     AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = input_table::regclass
                         AND attname = 'x'
                         AND NOT attisdropped)
        OR NOT EXISTS (SELECT 1
                       FROM pg_attribute
                       WHERE attrelid = input_table::regclass
                         AND attname = 'y'
                         AND NOT attisdropped)
    THEN
        RAISE EXCEPTION 'Please check your input!'
            USING HINT = FORMAT('Table %s must contain columns named node_id, x and y.', input_table);
    END IF;

    SELECT CASE mode_of_transport
               WHEN 'card' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'caro' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,13]
               WHEN 'care' THEN ARRAY [-1,3,4,5,6,7,8,9,10,11,12,13]
               WHEN 'no_mode' THEN ARRAY [-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14]
               WHEN 'pedestrian' THEN ARRAY [-1,5,4,6,7,8,9,10,11,12,13,14]
               END
    INTO v_street_cat;

    RETURN QUERY
        WITH pts AS MATERIALIZED (SELECT * FROM pgr._costmatrix_points(input_table))
        SELECT p.node_id,
               ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(p.lon, p.lat), pgr._srid()), 4326))          AS x_input,
               ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(p.lon, p.lat), pgr._srid()), 4326))          AS y_input,
               ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(cs.x2, cs.y2), pgr._srid()), 4326))          AS x_used,
               ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(cs.x2, cs.y2), pgr._srid()), 4326))          AS y_used,
               ROUND(ST_Distance(ST_MakePoint(p.lon, p.lat), ST_MakePoint(cs.x2, cs.y2))::NUMERIC, 1) AS offset_m
        FROM pts p
                 LEFT JOIN LATERAL pgr._costmatrix_segment(
                p.point_id, p.lot_id, p.id_offset, p.lon, p.lat, v_street_cat
                                   ) cs ON cs.source = p.point_id AND cs.target = p.lot_id;
END;
$function$;
