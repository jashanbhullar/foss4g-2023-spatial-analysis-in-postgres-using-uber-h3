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
Choose whichever ones you want

```bash
apt install osm2pgsql
# Just to make our life easy
export PGPASSWORD=postgres
export PGPORT=6432
export PGHOST=localhost

# our database and extension
psql -c "Create database osm_data;"
psql -d osm_data -c "create extension postgis;"

# This will take some time
osm2pgsql -c -d osm_data -x -E 4326 <osm_file>
osm2pgsql -a -d osm_data -x -E 4326 <osm_file_2>
```

### Let's run some queries

Let's get a subset of data

```SQL
create extension h3;
create extension h3_postgis CASCADE;
create table planet_osm_polygon_admin_2 as Select distinct on (osm_id) * from planet_osm_polygon where admin_level = '2';
create table planet_osm_trees as Select * from planet_osm_point where "natural" = 'tree';

select count(*) from planet_osm_polygon_admin_2 ;
-- 165

select count(*) from planet_osm_trees ;
-- 1043665

-- Not let's try to find all the trees in these countries
select b.osm_id , b."name",  count(a.osm_id) from planet_osm_trees a join planet_osm_polygon_admin_2 b on ST_Within(a.way , b.way) group by b.osm_id, b.name ;
-- takes forever

-- Let's try the h3 grid. Calculate all the h3 index for all trees
ALTER TABLE planet_osm_trees ADD COLUMN h3_index h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(way::POINT, 7)) STORED;

-- For polygons we need to do a bit of extra work
-- This function takes a pplygon and gives all the h3 index inside that polygon
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
ALTER TABLE planet_osm_polygon_admin_2  ADD COLUMN h3_indexes h3index[] GENERATED ALWAYS AS (get_h3_indexes(way,7)) STORED;

-- Create a flat table for faster joins
create table planet_osm_polygon_admin_2_flat as
select h3_index, osm_id, h3_cell_to_boundary_geometry(h3_index) from (
select unnest (h3_indexes) as h3_index, osm_id from planet_osm_polygon_admin_2) as a;

-- We compare the h3 index and find all the shape ids
select b.osm_id,count(a.osm_id) from planet_osm_trees a join planet_osm_polygon_admin_2_flat b on a.h3_index = b.h3_index group by b.osm_id;
-- takes 1 sec

```
