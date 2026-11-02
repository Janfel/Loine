CREATE OR REPLACE FUNCTION pgr._create_dynamical_grids(
    p_id BIGINT,
    p_cost INTEGER,
    p_x1 BIGINT,
    p_y1 BIGINT,
    p_x2 BIGINT,
    p_y2 BIGINT,
    p_geom geometry,
    p_direction TEXT
)
    RETURNS TABLE
            (
                edge_id    BIGINT,
                seq        INTEGER,
                gitter_id_ TEXT,
                agg_cost   INTEGER,
                geom       geometry
            )
    LANGUAGE plpgsql
AS
$function$
DECLARE
    v_res       INT := 100;
    v_x1        BIGINT;
    v_y1        BIGINT;
    v_x2        BIGINT;
    v_y2        BIGINT;
    v_total_len DOUBLE PRECISION;
    v_cf_cost   DOUBLE PRECISION;
    v_geom      GEOMETRY; -- geometry, reversed if necessary
BEGIN
    v_x1 := CASE WHEN p_x1 < 1000000 THEN p_x1 * 100 ELSE p_x1 END;
    v_y1 := CASE WHEN p_y1 < 1000000 THEN p_y1 * 100 ELSE p_y1 END;
    v_x2 := CASE WHEN p_x2 < 1000000 THEN p_x2 * 100 ELSE p_x2 END;
    v_y2 := CASE WHEN p_y2 < 1000000 THEN p_y2 * 100 ELSE p_y2 END;

    /*
     * For 'to': reverse the geometry so that ST_LineLocatePoint
     * calculates the position along the opposite direction
     * and sorting and cost calculation are correct.
     */
    v_geom := CASE
                  WHEN p_direction = 'to' THEN st_reverse(p_geom)
                  ELSE p_geom
        END;

    v_total_len := st_length(v_geom);

    v_cf_cost := CASE
                     WHEN p_cost > 0 AND v_total_len > 0
                         THEN p_cost::DOUBLE PRECISION / v_total_len
                     ELSE NULL
        END;

    RETURN QUERY
        WITH bbox AS (SELECT FLOOR(st_xmin(v_geom) / v_res)::BIGINT * v_res AS xmin,
                             FLOOR(st_ymin(v_geom) / v_res)::BIGINT * v_res AS ymin,
                             FLOOR(st_xmax(v_geom) / v_res)::BIGINT * v_res AS xmax,
                             FLOOR(st_ymax(v_geom) / v_res)::BIGINT * v_res AS ymax),
             candidates AS (SELECT x.val AS cx, y.val AS cy
                            FROM bbox,
                                 GENERATE_SERIES(bbox.xmin, bbox.xmax, v_res) AS x(val),
                                 GENERATE_SERIES(bbox.ymin, bbox.ymax, v_res) AS y(val)),
             cells AS (SELECT c.cx,
                              c.cy,
                              SUBSTR(c.cx::TEXT, 1, 5)                                 AS cx_5,
                              SUBSTR(c.cy::TEXT, 1, 5)                                 AS cy_5,
                              st_makeenvelope(c.cx, c.cy,
                                              c.cx + v_res, c.cy + v_res, pgr._srid()) AS cell_geom,
                              st_linelocatepoint(
                                      v_geom,
                                      st_closestpoint(
                                              v_geom,
                                              st_setsrid(
                                                      st_makepoint(c.cx + v_res / 2.0,
                                                                   c.cy + v_res / 2.0), pgr._srid())
                                      )
                              )                                                        AS frac
                       FROM candidates c
                       WHERE st_intersects(
                                     v_geom,
                                     st_makeenvelope(c.cx, c.cy,
                                                     c.cx + v_res, c.cy + v_res, pgr._srid())
                             )),
             ordered AS (SELECT ROW_NUMBER() OVER (ORDER BY frac)::INT AS seq,
                                cx,
                                cy,
                                cx_5,
                                cy_5,
                                cell_geom,
                                frac * v_total_len                     AS dist_to_center
                         FROM cells)
        SELECT p_id,
               o.seq,
               '100mN' || o.cy_5 || 'E' || o.cx_5           AS gitter_id_,
               ROUND(o.dist_to_center * v_cf_cost)::INTEGER AS agg_cost,
               o.cell_geom
        FROM ordered o;

END;
$function$;
