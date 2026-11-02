CREATE OR REPLACE FUNCTION pgr._costmatrix_points(
    p_input_table TEXT
)
    RETURNS TABLE
            (
                node_id     TEXT,
                lon         INTEGER,
                lat         INTEGER,
                x1          INTEGER,
                y1          INTEGER,
                point_id    BIGINT,
                lot_id      BIGINT,
                id_offset   BIGINT,
                edges_table TEXT,
                cluster_id  TEXT
            )
    LANGUAGE plpgsql
AS
$function$
    -- DESCRIPTION: Central, DETERMINISTIC point_id/lot_id assignment for the N points of
    --              input_table (columns node_id, x, y - EXACT names required, ensured by
    --              pgr._check_input_costmatrix, which is called beforehand). Called both by
    --              _preselection_costmatrix (to build vids/edges_sql) and by cgo_costmatrix
    --              (to translate pgr_astarcostmatrix's start_vid/end_vid back to the
    --              original node_id) - both calls MUST return exactly the same assignment,
    --              otherwise result rows are assigned to the wrong node_id.
    --              Therefore ROW_NUMBER() explicitly uses ORDER BY node_id - a CTE or
    --              ROW_NUMBER() without ORDER BY does NOT guarantee a repeatable order
    --              between two separate executions of the same query (e.g. the physical
    --              scan order of a table can change after autovacuum).
    --              Materialises the result in a TEMPORARY TABLE (created anew with every
    --              call, no caching across calls - avoids reusing a stale state from an
    --              earlier cgo_costmatrix call in the same transaction). Needed only once
    --              per cgo_costmatrix call (not per point), so unproblematic here.
    --              point_id := rn (1..N), lot_id := rn + 10000 - collision-free, since real
    --              graph node ids in pgr.edges are in the billions. node_id is returned as
    --              TEXT (the original type in input_table can be anything).

BEGIN
    DROP TABLE IF EXISTS tmp_costmatrix_points;
    EXECUTE FORMAT(
            'CREATE TEMP TABLE tmp_costmatrix_points AS
             SELECT
                 node_id::TEXT AS node_id, lon, lat, x1, y1,
                 rn::BIGINT                            AS point_id,
                 (rn + 10000)::BIGINT                  AS lot_id,
                 (rn * 1000)::BIGINT                   AS id_offset,
                 ''edges_n'' || SUBSTR(lat::TEXT,1,2) || ''e'' || SUBSTR(lon::TEXT,1,2)          AS edges_table,
                 UPPER(''N'' || SUBSTR(lat::TEXT,1,3) || ''E'' || SUBSTR(lon::TEXT,1,3))         AS cluster_id
             FROM (
                 SELECT
                     t.node_id,
                     p3035.lon, p3035.lat,
                     ROUND(p3035.lon::DOUBLE PRECISION / 100)::INTEGER AS x1,
                     ROUND(p3035.lat::DOUBLE PRECISION / 100)::INTEGER AS y1,
                     ROW_NUMBER() OVER (ORDER BY t.node_id) AS rn
                 FROM %s AS t
                 CROSS JOIN LATERAL (
                     SELECT ROUND(ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lon,
                            ROUND(ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(t.x, t.y), 4326), pgr._srid())))::INTEGER AS lat
                 ) p3035
             ) raw_pts',
            p_input_table::regclass
            );

    RETURN QUERY SELECT * FROM tmp_costmatrix_points;
END;
$function$;
