CREATE OR REPLACE FUNCTION pgr._grids_isolines(
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
                gitter_id_              TEXT,
                seq                     BIGINT,
                node                    BIGINT,
                edge                    BIGINT,
                cost                    INTEGER,
                agg_cost                INTEGER,
                grid_time               INTEGER,
                grid_distance           INTEGER,
                grid_traffic            INTEGER,
                distance_to_grid_factor DOUBLE PRECISION,
                street_cat              INTEGER,
                grid_geom               geometry
            )
    LANGUAGE plpgsql
    PARALLEL SAFE
AS
$function$
    -- DESCRIPTION: Returns grid cells reachable within buffer_value.
--              pgr_drivingdistance on _preselection_isolines (once),
--              then joined directly to pgr.grids via node.
--              No temporary tables. All calculations in metres in the projection of the region (pgr._srid), INTEGER.

DECLARE
    v_new_source      TEXT;
    v_new_target      TEXT;
    v_new_cost        TEXT;
    v_cost            TEXT;
    v_cost_expression TEXT;
    v_new_agg_cost    TEXT;
    v_agg_cost        TEXT;
    v_agg_cost1       TEXT;
    v_reverse_cost    TEXT;
    v_start_time      TIMESTAMP;
    v_end_time        TIMESTAMP;
    v_elapsed_time    INTERVAL;
    v_start_cluster   TEXT;
    v_segment_func    TEXT;
    v_segment_filter  TEXT;

BEGIN
    v_start_time
        = CLOCK_TIMESTAMP();


    --------------------------------------------------------------------------------------
    -- Parameter: plain text values only -----------------------------------------------
    --------------------------------------------------------------------------------------

    IF
        p_direction = 'from' THEN
        v_new_source := 'source';
        v_new_target
            := 'target';
    ELSE
        v_new_source := 'target AS source';
        v_new_target
            := 'source AS target';
    END IF;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_cost_expression := 'cost_distance * 0.72::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_distance';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 :=
                             'i.agg_cost + g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     --'i.agg_cost -  + g.cost_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_distance * 0.72 - g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_distance * 0.72 - g.grid_distance * 0.72 + g.distance_to_grid_factor * g.cost_distance * 0.72';
                     --'i.agg_cost';
                 END IF;
        WHEN p_calculation_type = 'time'
            THEN v_cost_expression := 'cost_time::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_time';
                 IF
                     p_direction = 'from' THEN
                     v_cost := 'g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost1
                         := 'i.agg_cost - i.cost + g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost
                         := 'i.agg_cost - i.cost + g.grid_time + g.distance_to_grid_factor * g.cost_time';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_time - g.grid_time + g.distance_to_grid_factor * g.cost_time';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_time - g.grid_time + g.distance_to_grid_factor * g.cost_time';
                 END IF;
        WHEN p_calculation_type = 'distance'
            THEN v_cost_expression := 'cost_distance::DOUBLE PRECISION';
                 v_cost
                     := 'g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                 v_new_cost
                     := 'cost_distance';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 := 'i.agg_cost + g.grid_distance + g.distance_to_grid_factor * g.cost_distance ';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                     --   'i.agg_cost - i.cost * grid_factor + g.distance_to_grid_factor * g.cost_distance';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_distance - g.grid_distance + g.distance_to_grid_factor * g.cost_distance ';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_distance - g.grid_distance + g.distance_to_grid_factor * g.cost_distance';
                     --'i.agg_cost - i.cost * grid_factor + g.distance_to_grid_factor * g.cost_distance';
                 END IF;
        WHEN p_calculation_type = 'traffic'
            THEN v_cost_expression := 'cost_traffic::DOUBLE PRECISION';
                 v_new_cost
                     := 'cost_traffic';
                 IF
                     p_direction = 'from' THEN
                     v_agg_cost1 := 'i.agg_cost  + g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                     v_agg_cost
                         := 'i.agg_cost - i.cost + g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                 ELSE
                     v_agg_cost1 :=
                             'i.agg_cost + g.cost_traffic - g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                     v_agg_cost
                         :=
                             'i.agg_cost - i.cost + g.cost_traffic - g.grid_traffic + g.distance_to_grid_factor * g.cost_traffic';
                 END IF;
        END CASE;

    CASE
        WHEN p_calculation_type = 'time' AND p_mode_of_transport = 'pedestrian'
            THEN v_new_agg_cost := 'g.cost_distance * 0.72';
        WHEN p_calculation_type = 'time'
            THEN v_new_agg_cost := 'g.cost_time';
        WHEN p_calculation_type = 'distance'
            THEN v_new_agg_cost := 'g.cost_distance';
        WHEN p_calculation_type = 'traffic'
            THEN v_new_agg_cost := 'g.cost_traffic';
        END CASE;

    v_reverse_cost
        := CASE
               WHEN p_mode_of_transport = 'pedestrian' AND p_calculation_type = 'time'
                   THEN 'cost_distance * 0.72::DOUBLE PRECISION'
               WHEN p_mode_of_transport IN ('pedestrian', 'no_mode')
                   THEN 'cost_distance::DOUBLE PRECISION'
               ELSE '-1'
        END;

    v_start_cluster
        := '100mN' || SUBSTR(p_lat::TEXT, 1, 5) || 'E' || SUBSTR(p_lon::TEXT, 1, 5);

    v_end_time
        = CLOCK_TIMESTAMP();
    v_elapsed_time
        = v_end_time - v_start_time;

    v_segment_func
        := CASE
               WHEN p_direction = 'from'
                   THEN 'pgr._starting_segment'
               ELSE 'pgr._ending_segment'
        END;
    v_segment_filter
        := CASE
               WHEN p_direction = 'from'
                   THEN 'source < 100000'
               ELSE 'target < 100000'
        END;

    RAISE
        NOTICE 'Execution Time for _grids_isolines /Defining Selection parameters: %', v_elapsed_time;

    --------------------------------------------------------------------------------------
    -- pgr_drivingdistance + grid join -------------------------------------------------
    --------------------------------------------------------------------------------------
    v_start_time
        = CLOCK_TIMESTAMP();

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
        grid_result AS (
            -- 1. static grid cells
            SELECT --DISTINCT ON (g.gitter_id_)
                g.gitter_id_,
                i.seq::BIGINT                               AS seq,
                i.node,
                i.edge,
                CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0::INTEGER ELSE ROUND(i.cost)::INTEGER END AS cost,
                CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0::INTEGER
                ELSE
                    ROUND(CASE WHEN i.cost = i.agg_cost THEN ' || v_agg_cost || ' ELSE ' || v_agg_cost || ' END)::INTEGER END AS agg_cost,

                --ROUND(CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0 ELSE i.cost END)::INTEGER AS cost,
                --ROUND(i.cost)::INTEGER                      AS cost,
                --ROUND(CASE WHEN gitter_id_ = ''' || v_start_cluster || ''' THEN 0 ELSE ' || v_agg_cost || ' END)::INTEGER AS agg_cost,
                --ROUND(CASE WHEN ' || v_agg_cost || ' IS NULL THEN ' || v_new_agg_cost || ' ELSE ' || v_agg_cost || ' END)::INTEGER AS agg_cost,
                --
                --ROUND(' || v_agg_cost || ')::INTEGER        AS agg_cost,
                ROUND(g.grid_time)::INTEGER                 AS grid_time,
                ROUND(g.grid_distance)::INTEGER             AS grid_distance,
                ROUND(g.grid_traffic)::INTEGER              AS grid_traffic,
                g.distance_to_grid_factor,
                g.street_cat::INTEGER,
                g.grid_geom
            FROM isoline i
            LEFT JOIN pgr._candidate_grids_isolines(' || p_lon || ',' || p_lat || ', ' ||
        ROUND(pgr._buffer_isolines(p_buffer_value, p_calculation_type, p_mode_of_transport))::INTEGER || ') g ON
                CASE WHEN ''' || p_direction || ''' = ''from''
                    THEN g.source = i.node
                    ELSE g.target = i.node
                END
            WHERE  i.cost >= 0
            AND  g.gitter_id_ IS NOT NULL
            AND  g.street_cat = ANY(' || QUOTE_LITERAL(pgr._mode_category(p_mode_of_transport, 'buffer')) || '::INTEGER[])  -- only categories of the mode
            AND  i.edge > 100000



        -- 2. dynamic grid cells
        UNION
        SELECT
            dg.gitter_id_,
            dg.seq::BIGINT                  AS seq,
            dg.node,
            dg.edge,
            ROUND(dg.agg_cost)::INTEGER     AS cost,
            ROUND(dg.agg_cost)::INTEGER     AS agg_cost,
            NULL::INTEGER                   AS grid_time,
            NULL::INTEGER                   AS grid_distance,
            NULL::INTEGER                   AS grid_traffic,
            NULL::DOUBLE PRECISION          AS distance_to_grid_factor,
            NULL::INTEGER                   AS street_cat,
            st_transform(dg.geom,4326)                         AS grid_geom
        FROM (
            SELECT DISTINCT ON (gitter_id_)
                gitter_id_,
                seq,
                node,
                edge,
                agg_cost,
                geom
            FROM (
                SELECT i.node, i.edge,
                    (pgr._create_dynamical_grids(s.id, i.cost::integer, s.x1, s.y1, s.x2, s.y2, s.geom, ''' ||
        p_direction || ''')).*
                FROM (
                    SELECT (' || v_segment_func || '(' || p_lon || ',' || p_lat || ', ''' || p_mode_of_transport || ''')).*
                ) s
                INNER JOIN isoline i ON s.id = i.edge
                WHERE ' || v_segment_filter || '
            ) dg
            ORDER BY gitter_id_, agg_cost
        )   dg

        -- end of dynamic grid cells
        )
        SELECT
            DISTINCT ON (gitter_id_)
            gitter_id_,
            seq,
            node,
            edge,
            cost::INTEGER,
            agg_cost::INTEGER,
            grid_time,
            grid_distance,
            grid_traffic,
            distance_to_grid_factor,
            street_cat,
            grid_geom
        FROM grid_result
        WHERE agg_cost <= ' || p_buffer_value || '::INTEGER
        ORDER BY gitter_id_, agg_cost';

    v_end_time
        = CLOCK_TIMESTAMP();
    v_elapsed_time
        = v_end_time - v_start_time;
    RAISE
        NOTICE 'Execution Time for _grids_isolines: %', v_elapsed_time;

END;
$function$;
