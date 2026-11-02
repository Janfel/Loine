CREATE OR REPLACE FUNCTION pgr._driving_distance_isolines(
    p_lon INTEGER,
    p_lat INTEGER,
    p_buffer_value NUMERIC,
    p_calculation_type TEXT,
    p_mode_of_transport TEXT,
    p_direction TEXT,
    p_inner_limit INTEGER DEFAULT 1500
)
    RETURNS TABLE
            (
                edge_node SMALLINT,
                seq       BIGINT,
                id        BIGINT,
                source    BIGINT,
                target    BIGINT,
                cost      INTEGER,
                agg_cost  INTEGER,
                geom      geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Central helper function for isoline calculation.
    --              Calls pgr_drivingdistance once via CTE within EXECUTE.
    --              _preselection_isolines called twice: once for pgr_drivingdistance,
    --              once for edge join. No temporary tables.
    --              All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_new_source           TEXT;
    v_new_target           TEXT;
    v_new_cost             TEXT;
    v_reverse_cost         TEXT;
    v_cost_expression      TEXT;
    v_cost_expression_edge TEXT;
    v_start_time           TIMESTAMP;
    v_end_time             TIMESTAMP;
    v_elapsed_time         INTERVAL;

BEGIN
    v_start_time = CLOCK_TIMESTAMP();

    --------------------------------------------------------------------------------------
    -- Parameter: plain text values only for the pgr_drivingdistance SQL string --------
    --------------------------------------------------------------------------------------

    IF p_direction = 'from' THEN
        v_new_source := 'source';
        v_new_target := 'target';
    ELSE
        v_new_source := 'target AS source';
        v_new_target := 'source AS target';
    END IF;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_cost_expression := '(cost_distance * 0.72)::DOUBLE PRECISION';
                 v_cost_expression_edge := '(e.cost_distance * 0.72)';
                 v_new_cost := 'cost_distance';
        WHEN p_calculation_type = 'time'
            THEN v_cost_expression := 'cost_time::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_time';
                 v_new_cost := 'cost_time';
        WHEN p_calculation_type = 'distance'
            THEN v_cost_expression := 'cost_distance::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_distance';
                 v_new_cost := 'cost_distance';
        WHEN p_calculation_type = 'traffic'
            THEN v_cost_expression := 'cost_traffic::DOUBLE PRECISION';
                 v_cost_expression_edge := 'e.cost_traffic';
                 v_new_cost := 'cost_traffic';
        END CASE;
    IF p_mode_of_transport IN ('pedestrian', 'no_mode') THEN
        v_reverse_cost := v_new_cost;
    ELSE
        v_reverse_cost := '-1';
    END IF;
    --------------------------------------------------------------------------------------
    -- pgr_drivingdistance (once via CTE) + edge join (preselection twice) -------------
    --------------------------------------------------------------------------------------

    RETURN QUERY EXECUTE
        'WITH isoline AS (
            SELECT * FROM pgr_drivingdistance(
                ''SELECT DISTINCT ON (id)
                    id,
                    ' || v_new_source || ',
                    ' || v_new_target || ',
                    ' || v_cost_expression || ' AS cost,
                    ' || v_reverse_cost || ' AS reverse_cost
                 FROM pgr._preselection_isolines(
                     ' || p_lon || ',
                     ' || p_lat || ',
                     ' || p_buffer_value || ',
                     ''''' || p_calculation_type || ''''',
                     ''''' || p_mode_of_transport || ''''',
                     ' || p_inner_limit || ',
                    ''''' || p_direction || '''''
                 )'',
                CASE WHEN ''' || p_direction || ''' = ''from'' THEN 1 ELSE 10001 END,
                ' || p_buffer_value || '::DOUBLE PRECISION,
                TRUE
            )
        ),
        preselection AS (
            SELECT DISTINCT ON (id) *
            FROM pgr._preselection_isolines(
                ' || p_lon || ',
                ' || p_lat || ',
                ' || p_buffer_value || ',
                ''' || p_calculation_type || ''',
                ''' || p_mode_of_transport || ''',
                ' || p_inner_limit + 1000 || ',
                ''' || p_direction || '''
            )
        ),
        -- Start nodes for the ends: reached nodes and, one turn edge (connector, source_id NULL) further, their
        -- target nodes. In the edge-based network there is always a connector between two segments; branching
        -- segments only begin behind it.
        ends AS (
            SELECT i.seq, i.node, i.agg_cost
            FROM isoline i
            UNION ALL
            SELECT i.seq,
                   CASE WHEN ''' || p_direction || ''' = ''from'' THEN c.target ELSE c.source END,
                   i.agg_cost + ' || REPLACE(v_cost_expression_edge, 'e.', 'c.') || '
            FROM isoline i
            INNER JOIN preselection AS c ON CASE WHEN ''' || p_direction || ''' = ''from''
                 THEN c.source = i.node
             ELSE c.target = i.node
            END
            WHERE c.source_id IS NULL
              AND i.agg_cost + ' || REPLACE(v_cost_expression_edge, 'e.', 'c.') || ' < ' || p_buffer_value || '
        )
        SELECT DISTINCT ON (source_id, seg_k1, seg_k2)
            edge_node,
            seq,
            id,
            source,
            target,
            cost,
            agg_cost,
            geom
        FROM (
            -- edge_node = 1: directly routed edges
            SELECT
                *
            FROM
            (SELECT
                DISTINCT ON (e.source_id, seg_k1, seg_k2)
                1::SMALLINT                AS edge_node,
                i.seq::BIGINT              AS seq,
                e.id,
                e.source_id,
                e.source,
                e.target,
                ROUND(i.cost)::INTEGER     AS cost,

                ROUND(
                    CASE
                        WHEN i.agg_cost > ' || p_buffer_value || '::DOUBLE PRECISION
                            THEN ' || p_buffer_value || '::DOUBLE PRECISION
                        ELSE i.agg_cost
                    END
                )::INTEGER                 AS agg_cost ,
                CASE
                    WHEN i.agg_cost > ' || p_buffer_value || '
                        THEN
                            CASE WHEN ''' || p_direction || ''' = ''from'' AND i.cost > 0
                                THEN st_linesubstring(e.geom, 0.0, 1.0 - ((i.agg_cost - ' || p_buffer_value || ') / i.cost))
                                ELSE st_linesubstring(e.geom, ((i.agg_cost - ' || p_buffer_value || ') / i.cost), 1.0)
                            END
                        ELSE e.geom
                    END                        AS geom,
                LEAST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k1,
                GREATEST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k2
            FROM isoline i
            INNER JOIN preselection AS e ON e.id = i.edge
            WHERE e.source_id IS NOT NULL
            ORDER BY e.source_id, seg_k1, seg_k2, CASE WHEN ''' || p_direction || ''' = ''from'' THEN agg_cost ELSE -agg_cost END) en1

            UNION ALL

            -- edge_node = 2: neighbouring edges at the last reachable node
            SELECT
                2::SMALLINT                                         AS edge_node,
                i.seq::BIGINT                                       AS seq,
                e.id,
                e.source_id,
                e.source,
                e.target,
                ROUND(' || v_cost_expression_edge || ')::INTEGER              AS cost,
                ROUND(
                    CASE
                        WHEN i.agg_cost+ ' || v_cost_expression_edge || ' > ' || p_buffer_value || '::DOUBLE PRECISION
                            THEN ' || p_buffer_value || '::DOUBLE PRECISION
                        ELSE i.agg_cost
                    END
                )::INTEGER                 AS agg_cost ,
                CASE
                    WHEN i.agg_cost + ' || v_cost_expression_edge || ' > ' || p_buffer_value || '
                        THEN
                            CASE WHEN ''' || p_direction || ''' = ''from''
                                THEN st_linesubstring(e.geom, 0.0, 1.0 - ((i.agg_cost + ' || v_cost_expression_edge ||
        ' - ' ||
        p_buffer_value || ') /' || v_cost_expression_edge || '))
                                ELSE st_linesubstring(e.geom, ((i.agg_cost+' || v_cost_expression_edge || ' - ' ||
        p_buffer_value || ') / ' || v_cost_expression_edge || '), 1.0)
                            END
                        ELSE e.geom
                     END                        AS geom,
                LEAST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k1,
                GREATEST(st_asbinary(st_startpoint(e.geom)), st_asbinary(st_endpoint(e.geom))) AS seg_k2
            FROM ends i
            INNER JOIN preselection AS e ON    CASE WHEN ''' || p_direction || ''' = ''from''
                 THEN e.source = i.node
             ELSE e.target = i.node
            END
            WHERE e.source_id IS NOT NULL

        ) created_conn
        ORDER BY source_id, seg_k1, seg_k2, edge_node';
    v_end_time = CLOCK_TIMESTAMP();
    v_elapsed_time = v_end_time - v_start_time;
    RAISE NOTICE 'Execution Time for _driving_distance_isolines: %', v_elapsed_time;

END;
$function$;
