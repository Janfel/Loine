-- Signatures and return types that changed compared to earlier versions.
-- The build puts these statements at the beginning of loine_functions.sql; the function files themselves
-- contain only CREATE OR REPLACE.

DROP FUNCTION IF EXISTS pgr._buffer_isolines(buffer_value NUMERIC, calculation_type TEXT, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr._candidate_edges(p_edges_table TEXT[], p_start_cluster TEXT[], p_center_x INTEGER,
                                             p_center_y INTEGER, p_sc_inner_low SMALLINT, p_sc_inner_high SMALLINT);
DROP FUNCTION IF EXISTS pgr._candidate_edges_array(p_edges_table TEXT, p_start_cluster TEXT, p_center_x INTEGER,
                                                   p_center_y INTEGER, p_street_cat INTEGER[], p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_edges_cluster(p_start_lon INTEGER, p_start_lat INTEGER, p_end_lon INTEGER,
                                                     p_end_lat INTEGER, p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._candidate_edges_hull_costmatrix(p_x1 INTEGER[], p_y1 INTEGER[], p_street_cat INTEGER[],
                                                             p_buffer_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_edges_isolines(p_lon INTEGER, p_lat INTEGER, p_radius_m INTEGER,
                                                      p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._candidate_edges_radius_costmatrix(p_edges_table TEXT[], p_cluster_ids TEXT[],
                                                               p_center_x INTEGER, p_center_y INTEGER,
                                                               p_street_cat INTEGER[], p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._candidate_grids_isolines(p_lon INTEGER, p_lat INTEGER, p_radius_m INTEGER);
DROP FUNCTION IF EXISTS pgr._catchment_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                p_calculation_type TEXT, p_mode_of_transport TEXT, p_direction TEXT,
                                                p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._catchment_isolines_static(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                       p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                       p_direction TEXT, p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._check_input(lon DOUBLE PRECISION, lat DOUBLE PRECISION, mode_of_transport TEXT,
                                         calculation_type TEXT, direction TEXT);
DROP FUNCTION IF EXISTS pgr._check_input_costmatrix(p_input_table TEXT, p_mode_of_transport TEXT, p_calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr._check_input_routes(start_lon DOUBLE PRECISION, start_lat DOUBLE PRECISION,
                                                end_lon DOUBLE PRECISION, end_lat DOUBLE PRECISION,
                                                mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr._costmatrix_points(p_input_table TEXT);
DROP FUNCTION IF EXISTS pgr._costmatrix_segment(p_point_id BIGINT, p_lot_id BIGINT, p_id_offset BIGINT, lon INTEGER,
                                                lat INTEGER, p_street_cat INTEGER[]);
DROP FUNCTION IF EXISTS pgr._create_dynamical_grids(p_id BIGINT, p_cost INTEGER, p_x1 BIGINT, p_y1 BIGINT, p_x2 BIGINT,
                                                    p_y2 BIGINT, p_geom geometry, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr._driving_distance_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                       p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                       p_direction TEXT, p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._ending_segment(lon INTEGER, lat INTEGER, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr._grids_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                            p_calculation_type TEXT, p_mode_of_transport TEXT, p_direction TEXT,
                                            p_inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._mode_category(TEXT, TEXT);
DROP PROCEDURE IF EXISTS pgr.loine_build_net_level(BIGINT);
DROP PROCEDURE IF EXISTS pgr.loine_build_net_level(BIGINT, BIGINT);
DROP FUNCTION IF EXISTS pgr._net_level_edges(INTEGER, INTEGER, INTEGER, INTEGER, INTEGER[]);
DROP FUNCTION IF EXISTS pgr._preselection_costmatrix(p_input_table TEXT, p_mode_of_transport TEXT,
                                                     p_inner_limit INTEGER, p_outer_buffer_m INTEGER);
DROP FUNCTION IF EXISTS pgr._preselection_isolines(p_lon INTEGER, p_lat INTEGER, p_buffer_value NUMERIC,
                                                   p_calculation_type TEXT, p_mode_of_transport TEXT,
                                                   p_inner_limit INTEGER, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr._preselection_routes(start_lon INTEGER, start_lat INTEGER, end_lon INTEGER, end_lat INTEGER,
                                                 mode_of_transport TEXT, inner_limit INTEGER);
DROP FUNCTION IF EXISTS pgr._starting_segment(lon INTEGER, lat INTEGER, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_costmatrix(input_table TEXT, mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_costmatrix_snap_report(input_table TEXT, mode_of_transport TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_isoline(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                        p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_isoline_static(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                               p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_multiisolines(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_values TEXT,
                                              p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_path(start_lon DOUBLE PRECISION, start_lat DOUBLE PRECISION, end_lon DOUBLE PRECISION,
                                     end_lat DOUBLE PRECISION, mode_of_transport TEXT, calculation_type TEXT);
DROP FUNCTION IF EXISTS pgr.cgo_segments(p_lon DOUBLE PRECISION, p_lat DOUBLE PRECISION, p_buffer_value NUMERIC,
                                         p_mode_of_transport TEXT, p_calculation_type TEXT, p_direction TEXT);
