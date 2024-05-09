## Geospatial analysis inside postgres using h3-pg

### Settting up

You can skip the steps below to pull the built image from the docker hub:

```bash
# Pull any postgis docker image
docker pull postgis/postgis:15-master
# Let's run a demo container where we can install h3 extension
docker run -it --name postgis-h3 -e POSTGRES_PASSWORD=postgres postgis/postgis:15-master

# shell access into the docker
docker exec -it -u root postgis-h3 bash

# Install the dependencies
apt update
apt install -y pip libpq-dev postgresql-server-dev-15
pip install pgxnclient cmake
# Install the extension
pgxn install h3

# Remove the dev dependencies
pip uninstall pgxnclient cmake
apt purge -y libpq-dev postgresql-server-dev-15 pip
exit

docker commit postgis-h3 postgis-h3
docker stop postgis-h3
docker rm postgis-h3
docker run -it --name postgis-h3 -d  -p 6432:5432 -e POSTGRES_PASSWORD=postgres postgis-h3
```

Create docker container from the pre-built image

```bash
docker run -it --name postgis-h3 -d -p 6432:5432 -e POSTGRES_PASSWORD=postgres  jsonsingh/postgis-h3
```

### Test the extension

```bash
PGPASSWORD=postgres psql -p 6432 -h localhost
```

```SQL
-- Create a temporary database
Create database temp;
\c temp;
create extension h3;
create extension h3_postgis CASCADE;
SELECT h3_lat_lng_to_cell(POINT('37.3615593,-122.0553238'), 5);

-- Clean up
\c postgres
Drop database temp
```

### Let's add a bunch of data

Get the data from https://download.geofabrik.de/
Choose whichever ones you want. e.g. Asia

Tip: You can see all the shapes in QGIS

```bash
apt install osm2pgsql
# Just to make our life easy
export PGPASSWORD=postgres
export PGPORT=6432
export PGHOST=localhost

# our database and extension
psql -c "Create database uber_h3_demo;"
psql -d uber_h3_demo -c "create extension postgis;"

# This will take some time
osm2pgsql -c -d uber_h3_demo -x -E 4326 <osm_file>
osm2pgsql -a -d uber_h3_demo -x -E 4326 <osm_file_2>
```

### Let's run some queries

Let's get a subset of data

```SQL
create extension h3;
create extension h3_postgis CASCADE;
create table planet_osm_polygon_admin_6 as Select distinct on (osm_id) * from planet_osm_polygon where admin_level = '6';
create table planet_osm_trees as Select * from planet_osm_point where "natural" = 'tree';

select count(*) from planet_osm_polygon_admin_6;
-- 5518

select count(*) from planet_osm_trees ;
-- 799130
```

### Point in Polygon

```SQL
-- Not let's try to find all the trees in these countries
select b.osm_id, count(a.osm_id) from planet_osm_trees a right join planet_osm_polygon_admin_2 b on ST_Within(a.way , b.way) group by b.osm_id order by count;
-- Cancelled after 1000 seconds

-- Let's try the h3 grid. Calculate all the h3 index for all trees
ALTER TABLE planet_osm_trees ADD COLUMN h3_index h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(way::POINT, 7)) STORED;
-- 4 seconds

-- For polygons we need to do a bit of extra work
-- This function takes a polygon and gives all the h3 index inside that polygon
CREATE OR REPLACE FUNCTION get_h3_indexes(shape geometry, index integer)
  RETURNS h3index[] AS $$
DECLARE
  h3_indexes h3index[];
BEGIN
  SELECT ARRAY(
    SELECT h3_polygon_to_cells(shape, index)
  ) INTO h3_indexes;

  RETURN h3_indexes;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- We calculate all the h3 index for all the shapes. This will take a lot of time but it's a one time process
ALTER TABLE planet_osm_polygon_admin_6  ADD COLUMN h3_indexes h3index[] GENERATED ALWAYS AS (get_h3_indexes(way,7)) STORED;
-- 63 seconds

-- Create a flat table for faster joins and visulize this table in QGIS
create table planet_osm_polygon_admin_6_flat as
select h3_index, osm_id, h3_cell_to_boundary_geometry(h3_index) from (
select unnest (h3_indexes) as h3_index, osm_id from planet_osm_polygon_admin_6) as a;
-- 8 seconds

-- We compare the h3 index and find all the shape ids
select b.osm_id,count(a.osm_id) from planet_osm_trees a join planet_osm_polygon_admin_6_flat b on a.h3_index = b.h3_index group by b.osm_id order by count;
-- takes 3 sec
```

### Compact Polygon

```SQL
-- create a function which returns compacted h3
CREATE OR REPLACE FUNCTION get_h3_indexes_compact(shape geometry, index integer)
  RETURNS h3index[] AS $$
DECLARE
  h3_indexes h3index[];
BEGIN
WITH cells AS (
  SELECT h3_polygon_to_cells(shape, index) AS cell_array
)
select Array(
SELECT h3_compact_cells(array_agg(cell_array))
FROM cells
) into h3_indexes;

  RETURN h3_indexes;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Let's create the compacted array indice
ALTER TABLE planet_osm_polygon_admin_6  ADD COLUMN h3_indexes_compacted h3index[] GENERATED ALWAYS AS (get_h3_indexes_compact(way,7)) STORED;
-- 67 seconds

-- Visualize the below table in QGIS
create table planet_osm_polygon_admin_6_flat_compact as
select h3_index, osm_id, h3_cell_to_boundary_geometry(h3_index) from (
select unnest (h3_indexes_compacted) as h3_index, osm_id from planet_osm_polygon_admin_6) as a;
-- 60 seconds
```

### Aggregating Data

```SQL
-- Aggregate the data at resolution 4 by simply
ALTER TABLE planet_osm_trees ADD COLUMN h3_index_res_4 h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(way::POINT, 4)) STORED;
select h3_index_res_4, count(h3_index) from planet_osm_trees group by h3_index_res_4;

-- Create the table for visual purposes
create table planet_osm_trees_agg as select distinct on (h3_index_res_4) * from planet_osm_trees;
-- Visualize the shapefile in QGIS
alter table planet_osm_trees_agg ADD COLUMN h3_index_res_4_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_index_res_4)) STORED;

```

### Raster

Once you have the raster data (I used sentinel for demo) you can load the rasters using

```bash
# Copy the raster inside docker
docker container cp ndvi.tiff postgis-h3:/home/
# Go inside the docker container (raster2psql is available inside the container)
docker exec -it postgis-h3 bash
# Load the raster
raster2pgsql -s 4326 -F *.tiff public.ndvi_raster > tiff.sql
```

Create hex indexes from the raster table

```SQL
CREATE TABLE ndvi_hex AS
SELECT *
FROM
  (SELECT (SUMMARY).h3 AS h3, (h3_raster_summary_stats_agg((SUMMARY).stats)).*,
                                                                             filename
   FROM
     (SELECT h3_raster_summary_clip(rast, 7) AS SUMMARY,
             filename
      FROM ndvi_raster) AS A
   GROUP BY h3,
            filename) AS B
WHERE SUM != 'NaN';

```

Create hex shapes from the indice (useful for visualization)

```SQL
ALTER TABLE ndvi_hex ADD COLUMN h3_shape geometry GENERATED always AS (h3_cell_to_boundary_geometry(h3)) stored;
```

Average of mean on shapes

```SQL
select b.osm_id, avg(a.mean) from ndvi_hex a join planet_osm_polygon_admin_6_flat b on a.h3 = b.h3_index group by b.osm_id;
```

## More things to try

- Nearest neighbours (kRing), helpful especially in ML analysis
- Edge function, moving from one cell to the next creating a path with h3index
- Optimizing queries using postgres techniques such as indexing and partitioning

Sources:

- https://www.youtube.com/watch?v=ay2uwtRO3QE&t=1044s&ab_channel=UberEngineering
- https://www.uber.com/en-IN/blog/h3/
- https://h3geo.org/docs/
- https://github.com/zachasme/h3-pg
- https://hub.docker.com/r/postgis/postgis
- https://h3geo.org/docs/community/tutorials
- https://github.com/jashanbhullar/foss4g-2023-spatial-analysis-in-postgres-using-uber-h3
