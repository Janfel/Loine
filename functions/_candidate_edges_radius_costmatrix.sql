CREATE OR REPLACE FUNCTION pgr._candidate_edges_radius_costmatrix(
    p_edges_table TEXT[],
    p_cluster_ids TEXT[],
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_street_cat INTEGER[],
    p_radius_m INTEGER
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
    -- DESCRIPTION: Like pgr._candidate_edges, but with a CONFIGURABLE radius instead of a
    --              fixed 1000 m, and with a single street_cat list (= ANY(...)) instead of
    --              an inner/outer range (low/high) - suitable for the cost matrix, where all
    --              remaining modes (card, caro, care, no_mode, pedestrian) use the same
    --              street_cat list inside and outside. Called by _costmatrix_segment in a
    --              loop with growing radius until the network permitted for the selected
    --              mode ("selected network") actually returns an edge - the nearest street
    --              is thus always searched in the selected (mode-filtered) network, not
    --              the geometrically nearest street regardless of mode. Prevents a point
    --              (e.g. on a footway) from remaining unreachable for restrictive modes
    --              such as caro although a matching street lies further away.

DECLARE
    v_union_block TEXT;
BEGIN
    SELECT STRING_AGG(
                   FORMAT('SELECT * FROM pgr.%I', tbl),
                   ' UNION ALL '
           )
    INTO v_union_block
    FROM UNNEST(p_edges_table) AS tbl;

    RETURN QUERY
        EXECUTE FORMAT(
            $sql$
            WITH p AS (
                SELECT
                    %s AS p_center_x,
                    %s AS p_center_y,
                    %s::INTEGER AS p_radius_m,
                    100::INTEGER AS p_grid_size
            ),
            radius_in_cells AS (
                SELECT
                    p.p_center_x,
                    p.p_center_y,
                    p.p_radius_m,
                    p.p_grid_size,
                    (p.p_radius_m / p.p_grid_size)::INTEGER AS p_r_cells
                FROM p
            ),
            y_offsets AS (
                SELECT
                    r.p_center_x,
                    r.p_center_y,
                    r.p_r_cells,
                    dy.dy
                FROM radius_in_cells r
                CROSS JOIN GENERATE_SERIES(-r.p_r_cells, r.p_r_cells) AS dy(dy)
            ),
            x_ranges AS (
                SELECT
                    yo.p_center_x,
                    yo.p_center_y,
                    yo.dy,
                    FLOOR(SQRT(
                        (yo.p_r_cells::DOUBLE PRECISION * yo.p_r_cells) -
                        (yo.dy::DOUBLE PRECISION   * yo.dy)
                    ))::INTEGER AS dx_max
                FROM y_offsets yo
            ),
            selected_grids AS (
                SELECT
                    xr.p_center_x + dx.dx AS sg_grid_x,
                    xr.p_center_y + xr.dy AS sg_grid_y
                FROM x_ranges xr
                CROSS JOIN LATERAL GENERATE_SERIES(-xr.dx_max, xr.dx_max) AS dx(dx)
            ),
            all_edges AS (
            %s
            )
            SELECT DISTINCT ON (e.id)
                e.id,
                e.source,
                e.target,
                e.speed_cat::INTEGER,
                e.street_cat::INTEGER,
                e.cost_time::INTEGER,
                e.cost_distance::INTEGER,
                e.cost_traffic::INTEGER,
                e.cluster_id,
                e.x1,
                e.y1,
                e.x2,
                e.y2,
                e.geom
            FROM selected_grids sg
            INNER JOIN all_edges e
                ON sg.sg_grid_x = e.x1 AND sg.sg_grid_y = e.y1
            WHERE e.street_cat = ANY(%L::INTEGER[])
              AND e.cluster_id = ANY(%L::TEXT[])
            ORDER BY e.id, sg.sg_grid_y, sg.sg_grid_x
            $sql$,
            p_center_x,
            p_center_y,
            p_radius_m,
            v_union_block,
            p_street_cat,
            p_cluster_ids
                );
END;
$function$;
