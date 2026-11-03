# Table structure of `pgr.edges` and `pgr.grids`

The Loine routing functions work on two tables: `pgr.edges` (road network) and `pgr.grids` (100 m grid cells linked to the road network). The tables can also be used without the Loine functions, for example directly with pgRouting or in QGIS.

Preparing the road networks is not part of the Loine software. casaGeo provides prepared networks for Loine per country. If you want to prepare your own network, see the requirements in [Preparing your own networks](#preparing-your-own-networks).

## Table `pgr.edges`

### Structure

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | Edge ID, unique across all countries |
| `source` | bigint | Start node |
| `target` | bigint | End node |
| `source_id` | double precision | ID of the object in the data source (HERE: link ID, OSM: way ID); empty for connectors |
| `speed_cat` | integer | Speed category, rank (1 = fastest) |
| `street_cat` | integer | Street category, rank (1 = highest class) |
| `cost_distance` | integer | Length in metres |
| `cost_time` | integer | Travel time in seconds |
| `cost_traffic` | integer | Travel time in seconds with traffic speeds |
| `partition_id` | text | 100 km tile of the start point |
| `cluster_id` | text | 10 km cluster of the start point |
| `grid_1km` | text | 1 km cell of the start point |
| `geom` | geometry(LineString) | Geometry in the regional projection |
| `x1`, `y1` | integer | Start point in the regional projection, in 100 m units |
| `x2`, `y2` | integer | End point in the regional projection, in 100 m units |

### Properties

- **Directed, edge-based graph.** The table contains segments and connectors.
  - **Segments** are road sections. Each drivable direction is a separate row, digitised in the direction of travel, so a two-way street appears twice. Each segment has its own nodes, which it shares with no other segment.
  - **Connectors** lead from the end of one segment to the start of another and represent turning. They have length 0 and no `source_id`.
- **Turn costs and turn restrictions** are stored in the connectors. The `cost_time` of a connector is the turn time. A turn restriction is a connector with `cost_distance` = 1,000,000 m and `cost_time` = 1,800,000 s plus the turn time; it stays in the graph but is practically never chosen.
- **Traffic times.** `cost_traffic` is based on measured traffic speeds where the data source provides them. These already include the time for turning, so connectors have `cost_traffic` = 0.
- **IDs.** Each country has a fixed range of one billion IDs for edges and nodes (e.g. Austria 1,000,000,001 to 1,999,999,999). This keeps them unique when several countries are in one database. Border crossings connect the networks of neighbouring countries and have their own range.
- **`source_id`.** Several segments can share the same `source_id` if an object of the source was split, e.g. at intersections.
- **Street category of connectors.** A connector gets the higher class of the two segments it connects.
- **Projection.** `geom`, `x1`/`y1` and `x2`/`y2` are in the regional projection (`pgr.loine_installed.srid`): Europe EPSG:3035, Africa 990001, North America including Central America 990002 (each Lambert azimuthal equal-area).
- **Tiles, clusters and cells.** The IDs consist of `N` + northing and `E` + easting of the south-west corner at the respective size, e.g. tile `N19E52` (100 km), cluster `N197E527` (10 km), cell `1kmN1973E5272` (1 km). In Europe they match the INSPIRE grid.
- **Partitioning.** The table is partitioned by `partition_id`; each tile is a separate partition, e.g. `pgr.edges_n19e52`.
- **Use with pgRouting.** Exclude turn restrictions with `cost_distance < 1000000`:

  ```sql
  SELECT *
  FROM pgr_dijkstra(
      'SELECT id, source, target, cost_time AS cost FROM pgr.edges WHERE cost_distance < 1000000',
      <start_node>, <end_node>);
  ```

  Because each segment has its own nodes, a route starts and ends at the nodes of a segment, not at an intersection.

## Table `pgr.grids`

### Structure

| Column | Type | Meaning |
|---|---|---|
| `id` | bigint | Segment ID (`pgr.edges.id`) |
| `partition_id` | text | 100 km tile of the cell |
| `cluster_id` | text | 10 km cluster of the cell |
| `source`, `target` | bigint | Nodes of the segment |
| `source_id` | double precision | ID of the object in the data source, as in `pgr.edges` |
| `gitter_id_` | text | ID of the 100 m cell |
| `grid_1km` | text | 1 km cell containing the 100 m cell |
| `grid_distance` | integer | Length from the start of the segment to the cell in metres |
| `grid_time` | integer | Travel time from the start of the segment to the cell in seconds |
| `grid_traffic` | integer | As `grid_time`, with traffic speeds |
| `grid_factor` | double precision | Position of the cell along the segment (0 = start, 1 = end) |
| `distance_to_grid_factor` | double precision | Distance from the segment to the cell as a share of the segment length |
| `cost_distance`, `cost_time`, `cost_traffic` | integer | Costs of the whole segment, as in `pgr.edges` |
| `street_cat` | integer | Street category of the segment |
| `x1`, `y1` | integer | South-west corner of the cell in the regional projection, in 100 m units |
| `grid_geom` | geometry(Polygon, 4326) | Outline of the cell in WGS84 |

### Properties

- **One row per pair of segment and cell.** The table assigns to each segment the 100 m cells it crosses or borders. A cell appears as often as segments reach it.
- **Crossed and neighbouring cells.** For crossed cells `distance_to_grid_factor` = 0. For neighbouring cells it gives the additional way from the segment to the cell as a share of the segment length.
- **Costs up to the cell.** `grid_distance`, `grid_time` and `grid_traffic` are `grid_factor` × the costs of the segment.
- **Computing the cost of a cell.** If a segment is reached at its start with the cost `agg_cost` (e.g. from `pgr_drivingDistance`), one of its cells is reached with

  ```
  agg_cost + grid_time + distance_to_grid_factor × cost_time
  ```

  The lowest cost over all rows of a `gitter_id_` is the cost of the cell. This gives the accessibility of every cell without intersecting geometries.
- **Cell ID.** `gitter_id_` is built like the IDs in `pgr.edges`, e.g. `100mN18868E54079`; in Europe it is the ID of the INSPIRE grid.
- **Projection.** `grid_geom` is in WGS84 (EPSG:4326), `x1`/`y1` in the regional projection.
- **Partitioning.** Like `pgr.edges`, by `partition_id`, here the tile of the cell.

## Preparing your own networks

A network can be prepared from any data source. For the Loine functions to run on it, it must meet the following requirements:

- **Tables and columns** as described above. `install/loine_install.sql` creates all tables; the data is loaded directly into these tables.
- **Partitions** per 100 km tile named `edges_<tile>` and `grids_<tile>` in lowercase, e.g. `pgr.edges_n19e52`. The functions access these partitions directly.
- **Tiles and clusters** in `pgr.partition` (one row per tile) and `pgr.cluster` (one row per 10 km cluster with its outline in WGS84). A start or end point must lie within a cluster.
- **Graph:** directed segments with their own nodes per segment; connectors without `source_id`, with length 0 and the turn costs in `cost_time`; turn restrictions as connectors with `cost_distance` = 1,000,000.
- **Units:** lengths in metres, times in seconds, `x1`/`y1`/`x2`/`y2` in 100 m units in the regional projection.
- **IDs:** edges and nodes unique across all countries in the database. IDs up to 10,005 are reserved for connecting the start and end points.
- **Street categories** matching `pgr.loine_mode_category`, so that each mode of transport uses the right roads.
- **Installed countries** in `pgr.loine_installed` with source (`source`) and projection (`srid`).
- **Finalisation** with `CALL pgr.loine_finalize()`: indexes, sorting, statistics and the base network for routes.

How speeds, turn times and the assignment of grid cells are determined is up to whoever prepares the network.

If you prepare a network from OpenStreetMap, you must comply with the terms of the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).

## Note: street categories depend on the data source

The values of `street_cat` and `speed_cat` are currently not the same for all data sources:

- **OpenStreetMap:** Loine maps the OSM road classes to its own ranking: 1 `motorway`, 2 `trunk`, 3 `primary`, 4 `secondary`, 5 `tertiary`, 6 `unclassified`, 7 `residential` and `living_street`, 8 `service`, 9 `track`, 10 `pedestrian`, 11 `footway`, `path`, `cycleway` and `steps`. Link roads (`*_link`) get the class of their road. `speed_cat` is the ranking of the classes by their average speed.
- **HERE:** `street_cat` and `speed_cat` take over the HERE categories.

The same number can therefore mean a different kind of road depending on the source. Which categories a mode of transport uses is therefore stored per source in `pgr.loine_mode_category`. A database always contains countries of one source only; the source is stored in `pgr.loine_installed.source`.

The goal is a unified Loine scheme of street categories to which every data source is mapped during preparation. Then the networks of all sources have the same structure, and `pgr.loine_mode_category` no longer needs to distinguish by source.
