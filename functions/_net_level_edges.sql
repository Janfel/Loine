CREATE OR REPLACE FUNCTION pgr._net_level_edges(
    start_lon INTEGER,
    start_lat INTEGER,
    end_lon INTEGER,
    end_lat INTEGER,
    p_buffer_cats INTEGER[],
    p_main_cats INTEGER[]
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
                y2            INTEGER,
                geom          GEOMETRY
            )
    LANGUAGE plpgsql
    STABLE PARALLEL SAFE
AS
$function$
    -- Coordinates as in pgr._preselection_routes. Estimated size of the local preselection from pgr.net_density_cluster
    -- (main network in the rectangle ± 1 cluster, buffer network in the start and end cluster). From the base network
    -- (pgr.edges_global, built by pgr.loine_build_net_level), the edges with prio <= budget − local size are returned,
    -- at least min_global. Default min_global = budget: the whole base network is always loaded. With min_global = 0
    -- nothing is added where the local preselection already uses up the budget; faster, but routes in sparse networks
    -- may be missing. Without base network (pgr.net_level empty) no edges are returned.

DECLARE
    v_budget     BIGINT;
    v_min_global BIGINT;
    v_local      BIGINT;
    v_limit      BIGINT;
BEGIN
    SELECT l.budget, l.min_global INTO v_budget, v_min_global FROM pgr.net_level l;
    IF v_budget IS NULL THEN
        RETURN;
    END IF;

    -- estimated size of the local preselection: main network in the rectangle ± 1 cluster (as _candidate_edges_cluster)
    -- and buffer network in the start and end cluster
    SELECT COALESCE(SUM(d.n), 0)
    INTO v_local
    FROM pgr.net_density_cluster d
    WHERE d.street_cat = ANY (p_main_cats)
      AND d.cluster_id IN (SELECT 'N' || LPAD(y::TEXT, 3, '0') || 'E' || LPAD(x::TEXT, 3, '0')
                           FROM GENERATE_SERIES(LEAST(start_lon, end_lon) / 10000 - 1,
                                                GREATEST(start_lon, end_lon) / 10000 + 1) x
                                    CROSS JOIN GENERATE_SERIES(LEAST(start_lat, end_lat) / 10000 - 1,
                                                               GREATEST(start_lat, end_lat) / 10000 + 1) y);
    v_local := v_local + (SELECT COALESCE(SUM(d.n), 0)
                          FROM pgr.net_density_cluster d
                          WHERE d.street_cat = ANY (p_buffer_cats)
                            AND d.street_cat <> ALL (p_main_cats)
                            AND d.cluster_id IN ('N' || LPAD((start_lat / 10000)::TEXT, 3, '0') || 'E' ||
                                                 LPAD((start_lon / 10000)::TEXT, 3, '0'),
                                                 'N' || LPAD((end_lat / 10000)::TEXT, 3, '0') || 'E' ||
                                                 LPAD((end_lon / 10000)::TEXT, 3, '0')));

    v_limit := GREATEST(v_budget - v_local, v_min_global);
    IF v_limit <= 0 THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT g.id,
               g.source,
               g.target,
               g.cost_time,
               g.cost_distance,
               g.cost_traffic,
               g.street_cat,
               g.x1,
               g.y1,
               g.x2,
               g.y2,
               g.geom
        FROM pgr.edges_global g
        WHERE g.prio <= v_limit
          AND g.street_cat = ANY (p_buffer_cats);
END;
$function$;
