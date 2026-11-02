CREATE OR REPLACE PROCEDURE pgr.loine_build_net_level(
    p_budget BIGINT DEFAULT 1000000,
    p_min_global BIGINT DEFAULT NULL
)
    LANGUAGE plpgsql
AS
$procedure$
    -- Problem: The preselection of cgo_path takes the main network only from the rectangle between start and end (± 10 km).
-- In sparse networks the best path often runs outside it, resulting in no route or a detour. In dense networks the
-- rectangle is sufficient; a larger area only costs run time there.
--
-- Solution: The local preselection is complemented by a country-wide base network whose size depends on the density.
-- Budget (parameter p_budget, default 1 million edges ≈ 1.5 s load time for pgr_astar) for base network and local
-- preselection. The base network is stored in pgr.edges_global:
--   1. Backbone: all categories up to base_cat country-wide whose edges together make up at most half of the budget.
--   2. Fill per 100 km tile by density: for each tile and category above base_cat, the number of edges of the tile
--      up to this category is counted (cumulated from category 1). Filling starts with the sparsest level and goes up
--      until the budget is reached. Sparse tiles thus get the whole network, dense tiles only the backbone.
--   Each edge carries its rank prio (cumulated number of edges up to and including its level): backbone first
--   (by category), then the fill (sparsest level first).
-- p_min_global: edges of the base network that are always loaded per query (default = p_budget, the whole base network;
-- see pgr._net_level_edges).
--
-- The tables pgr.net_level, pgr.net_density and pgr.net_density_cluster are created by loine_install.sql.
-- pgr.loine_finalize calls CALL pgr.loine_build_net_level() (after the last country, again with every new delivery).
-- Custom values: CALL pgr.loine_build_net_level(p_budget => …, p_min_global => …);
DECLARE
    v_cats   INTEGER[] := pgr._net_level_cats();
    v_base   INTEGER;
    v_base_n BIGINT;
    v_n      BIGINT;
BEGIN
    TRUNCATE pgr.net_density;
    INSERT INTO pgr.net_density (partition_id, street_cat, n)
    SELECT e.partition_id, e.street_cat, COUNT(*)
    FROM pgr.edges e
    WHERE e.street_cat = ANY (v_cats)
    GROUP BY 1, 2;
    TRUNCATE pgr.net_density_cluster;
    INSERT INTO pgr.net_density_cluster (cluster_id, street_cat, n)
    SELECT e.cluster_id, e.street_cat, COUNT(*)
    FROM pgr.edges e
    WHERE e.street_cat > 0
    GROUP BY 1, 2;
    COMMIT;

    -- 1. Backbone: highest category whose edges make up at most half of the budget in the whole country
    SELECT MAX(c.street_cat), MAX(c.cum)
    INTO v_base, v_base_n
    FROM (SELECT d.street_cat, SUM(SUM(d.n)) OVER (ORDER BY d.street_cat) AS cum
          FROM pgr.net_density d
          GROUP BY d.street_cat) c
    WHERE c.cum <= p_budget / 2;
    v_base := COALESCE(v_base, 0);
    v_base_n := COALESCE(v_base_n, 0);

    -- Levels: backbone per category, then fill per tile and category (sparsest level first)
    DROP TABLE IF EXISTS pgr.net_level_step;
    CREATE TABLE pgr.net_level_step AS
    WITH base AS (SELECT NULL::TEXT AS partition_id, d.street_cat, SUM(d.n) AS n, 0 AS grp, d.street_cat::BIGINT AS ord
                  FROM pgr.net_density d
                  WHERE d.street_cat <= v_base
                  GROUP BY d.street_cat),
         fill AS (SELECT t.partition_id, t.street_cat, t.n, 1 AS grp, t.tile_cum AS ord
                  FROM (SELECT d.partition_id,
                               d.street_cat,
                               d.n,
                               SUM(d.n) OVER (PARTITION BY d.partition_id ORDER BY d.street_cat) AS tile_cum
                        FROM pgr.net_density d) t
                  WHERE t.street_cat > v_base),
         steps AS (SELECT * FROM base UNION ALL SELECT * FROM fill)
    SELECT s.partition_id,
           s.street_cat,
           s.n,
           SUM(s.n) OVER (ORDER BY s.grp, s.ord, s.street_cat, s.partition_id) AS prio
    FROM steps s;
    DELETE FROM pgr.net_level_step WHERE prio > GREATEST(p_budget, v_base_n);

    DROP TABLE IF EXISTS pgr.edges_global;
    CREATE TABLE pgr.edges_global AS
    SELECT e.id,
           e.source,
           e.target,
           e.speed_cat::INTEGER     AS speed_cat,
           e.street_cat::INTEGER    AS street_cat,
           e.cost_time::INTEGER     AS cost_time,
           e.cost_distance::INTEGER AS cost_distance,
           e.cost_traffic::INTEGER  AS cost_traffic,
           e.cluster_id,
           e.partition_id,
           e.x1,
           e.y1,
           e.x2,
           e.y2,
           e.geom,
           s.prio
    FROM pgr.edges e
             JOIN pgr.net_level_step s
                  ON s.street_cat = e.street_cat AND (s.partition_id IS NULL OR s.partition_id = e.partition_id)
    ORDER BY s.prio;
    SELECT COUNT(*) INTO v_n FROM pgr.edges_global;
    CREATE INDEX idx_pgr_edges_global_prio ON pgr.edges_global USING btree (prio);
    ANALYZE pgr.edges_global;

    TRUNCATE pgr.net_level;
    INSERT INTO pgr.net_level (budget, min_global, base_cat, global_n)
    VALUES (p_budget, COALESCE(p_min_global, p_budget), v_base, v_n); -- default: whole base network
    RAISE NOTICE 'net_level: budget %, backbone up to category % (% edges), base network % edges', p_budget, v_base, v_base_n, v_n;
END;
$procedure$;
