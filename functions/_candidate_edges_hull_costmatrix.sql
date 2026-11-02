CREATE OR REPLACE FUNCTION pgr._candidate_edges_hull_costmatrix(
    p_x1 INTEGER[],
    p_y1 INTEGER[],
    p_street_cat INTEGER[],
    p_buffer_m INTEGER
)
    RETURNS TABLE
            (
                id            BIGINT,
                source        BIGINT,
                target        BIGINT,
                cost_time     INTEGER,
                cost_distance INTEGER,
                cost_traffic  INTEGER,
                street_cat    INTEGER,
                x1            INTEGER,
                y1            INTEGER,
                x2            INTEGER,
                y2            INTEGER
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Selects the "outer" / main-network candidate edges for N points
    --              using a hull-shaped corridor instead of one large bounding box,
    --              built entirely from x1/y1 BTREE range predicates (no ST_Intersects/
    --              GiST on pgr.edges). The convex hull is computed only over the
    --              (few) input points, never over the edges table. For every
    --              relevant 100km partition, the hull edges are linearly clipped
    --              to that partition's x1-band to derive a tight, partition-specific
    --              y1 range instead of applying one global y1 range everywhere.
    --              Benchmarked against ST_Intersects-based bounding box and convex
    --              hull selection: ~25-50x faster at a comparable or better result
    --              size.

DECLARE
    v_hull_pts      GEOMETRY[];
    v_n             INTEGER;
    i               INTEGER;
    v_x1a           NUMERIC;
    v_y1a           NUMERIC;
    v_x1b           NUMERIC;
    v_y1b           NUMERIC;
    v_buffer_xy     INTEGER;
    v_global_x1_min INTEGER;
    v_global_x1_max INTEGER;
    v_global_y1_min INTEGER;
    v_global_y1_max INTEGER;
    v_partition_ids TEXT[];
    v_part          TEXT;
    v_part_x        INTEGER;
    v_part_y        INTEGER;
    v_band_x_min    NUMERIC;
    v_band_x_max    NUMERIC;
    v_band_y_min    NUMERIC;
    v_band_y_max    NUMERIC;
    v_clip_x_min    NUMERIC;
    v_clip_x_max    NUMERIC;
    v_ya            NUMERIC;
    v_yb            NUMERIC;
    v_t             NUMERIC;
    v_found         BOOLEAN;
    v_sql           TEXT := '';
BEGIN
    v_buffer_xy := ROUND(p_buffer_m::DOUBLE PRECISION / 100)::INTEGER;

    -- 1. convex hull ONLY over the input points (cheap, no access to pgr.edges)
    SELECT ARRAY_AGG(g.geom ORDER BY g.path)
    INTO v_hull_pts
    FROM (SELECT (dp).path, (dp).geom
          FROM (SELECT ST_DumpPoints(ST_ExteriorRing(ST_ConvexHull(
                  ST_Collect(ST_MakePoint(pt.x1, pt.y1))
                                                     ))) AS dp
                FROM UNNEST(p_x1, p_y1) AS pt(x1, y1)) s) g;
    v_n := COALESCE(ARRAY_LENGTH(v_hull_pts, 1), 0);

    -- 2. global bounding box (to determine partitions and as fallback with < 2 hull points)
    SELECT MIN(pt.x1) - v_buffer_xy,
           MAX(pt.x1) + v_buffer_xy,
           MIN(pt.y1) - v_buffer_xy,
           MAX(pt.y1) + v_buffer_xy
    INTO v_global_x1_min, v_global_x1_max, v_global_y1_min, v_global_y1_max
    FROM UNNEST(p_x1, p_y1) AS pt(x1, y1);

    -- 3. relevant partitions (100 km grid), as in _candidate_edges_isolines
    SELECT ARRAY(
                   SELECT p.partition_id
                   FROM (SELECT 'N' || LPAD(y::TEXT, 2, '0') || 'E' || LPAD(x::TEXT, 2, '0') AS partition_id
                         FROM GENERATE_SERIES(FLOOR(v_global_x1_min::NUMERIC / 1000)::INTEGER,
                                              FLOOR(v_global_x1_max::NUMERIC / 1000)::INTEGER) AS x,
                              GENERATE_SERIES(FLOOR(v_global_y1_min::NUMERIC / 1000)::INTEGER,
                                              FLOOR(v_global_y1_max::NUMERIC / 1000)::INTEGER) AS y) gen
                            INNER JOIN pgr.partition p ON p.partition_id = gen.partition_id
           )
    INTO v_partition_ids;

    -- 4. per partition: clip the hull edges to the x1 band of the partition and
    --    derive a tight y1 range from it (pure arithmetic, no PostGIS on
    --    pgr.edges). Without a hit (e.g. with < 2 hull points): global range.
    FOREACH v_part IN ARRAY v_partition_ids
        LOOP
            v_part_x := SUBSTRING(v_part FROM 5 FOR 2)::INTEGER;
            v_part_y := SUBSTRING(v_part FROM 2 FOR 2)::INTEGER;

            v_band_x_min := GREATEST(v_global_x1_min, v_part_x * 1000);
            v_band_x_max := LEAST(v_global_x1_max, (v_part_x + 1) * 1000);
            v_band_y_min := NULL;
            v_band_y_max := NULL;
            v_found := FALSE;

            IF v_n >= 2 THEN
                FOR i IN 1..(v_n - 1)
                    LOOP
                        v_x1a := ST_X(v_hull_pts[i]);
                        v_y1a := ST_Y(v_hull_pts[i]);
                        v_x1b := ST_X(v_hull_pts[i + 1]);
                        v_y1b := ST_Y(v_hull_pts[i + 1]);

                        IF v_x1a IS DISTINCT FROM v_x1b THEN
                            v_clip_x_min := GREATEST(v_band_x_min, LEAST(v_x1a, v_x1b));
                            v_clip_x_max := LEAST(v_band_x_max, GREATEST(v_x1a, v_x1b));
                            IF v_clip_x_min <= v_clip_x_max THEN
                                v_t := (v_clip_x_min - v_x1a) / (v_x1b - v_x1a);
                                v_ya := v_y1a + v_t * (v_y1b - v_y1a);
                                v_t := (v_clip_x_max - v_x1a) / (v_x1b - v_x1a);
                                v_yb := v_y1a + v_t * (v_y1b - v_y1a);
                                v_band_y_min := LEAST(COALESCE(v_band_y_min, v_ya), v_ya, v_yb);
                                v_band_y_max := GREATEST(COALESCE(v_band_y_max, v_ya), v_ya, v_yb);
                                v_found := TRUE;
                            END IF;
                        ELSIF v_x1a BETWEEN v_band_x_min AND v_band_x_max THEN
                            v_band_y_min := LEAST(COALESCE(v_band_y_min, v_y1a), v_y1a, v_y1b);
                            v_band_y_max := GREATEST(COALESCE(v_band_y_max, v_y1a), v_y1a, v_y1b);
                            v_found := TRUE;
                        END IF;
                    END LOOP;
            END IF;

            IF NOT v_found THEN
                v_band_y_min := v_global_y1_min;
                v_band_y_max := v_global_y1_max;
            ELSE
                v_band_y_min := v_band_y_min - v_buffer_xy;
                v_band_y_max := v_band_y_max + v_buffer_xy;
            END IF;

            IF v_sql <> '' THEN
                v_sql := v_sql || ' UNION ALL ';
            END IF;
            v_sql := v_sql || FORMAT(
                    'SELECT id, source, target,
                            cost_time::INTEGER, cost_distance::INTEGER, cost_traffic::INTEGER,
                            street_cat::INTEGER, x1, y1, x2, y2
                     FROM pgr.edges_%s
                     WHERE x1 BETWEEN %s AND %s
                       AND y1 BETWEEN %s AND %s
                       AND street_cat = ANY(%L::INTEGER[])',
                    LOWER(v_part), ROUND(v_band_x_min), ROUND(v_band_x_max),
                    ROUND(v_band_y_min), ROUND(v_band_y_max), p_street_cat
                              );
        END LOOP;

    IF v_sql = '' THEN
        RETURN;
    END IF;

    RETURN QUERY EXECUTE
        'SELECT id, source, target, cost_time, cost_distance, cost_traffic,
                street_cat, x1, y1, x2, y2
         FROM (' || v_sql || ') s';
END;
$function$;
