CREATE OR REPLACE FUNCTION pgr._candidate_edges(
    p_edges_table TEXT[],
    p_start_cluster TEXT[],
    p_center_x INTEGER,
    p_center_y INTEGER,
    p_sc_inner_low SMALLINT,
    p_sc_inner_high SMALLINT
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
    -- DESCRIPTION: Part of preselecting grids

DECLARE
BEGIN
    -- Spatial search on the geometry: all edges that run within 1 km of the point. A search on the start point
    -- (x1/y1) and the 10 km cluster of the point would miss long segments that pass right by the point (e.g. in
    -- Namibia 80 % of the network length lies in segments longer than 1 km); there would then be no start or end
    -- segment and no route.
    -- p_edges_table and p_start_cluster remain in the signature for the existing calls but are no longer used
    -- (the search uses the geometry index of all partitions).
    RETURN QUERY
        SELECT e.id,
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
               e.geom
        FROM pgr.edges e
        WHERE ST_DWithin(e.geom, ST_SetSRID(ST_MakePoint(p_center_x * 100, p_center_y * 100), pgr._srid()), 1000)
          AND e.street_cat > p_sc_inner_low
          AND e.street_cat <= p_sc_inner_high
          AND e.source_id IS NOT NULL; -- only street segments, no turn edges (length 0)
END;
$function$;
