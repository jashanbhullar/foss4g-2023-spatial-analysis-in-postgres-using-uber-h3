create table planet_osm_polygon_admin_6 as Select *
from planet_osm_polygon
where admin_level = '6';

create table planet_osm_trees as select *
from planet_osm_point
where "natural" = 'tree';

select distinct on(place) place from planet_osm_point;

select count(*) from planet_osm_polygon_admin_6;

select count(*) from planet_osm_trees;


select b.osm_id, count(a.osm_id)
from planet_osm_trees a
right join planet_osm_polygon_admin_6 b on
ST_Within(a.way , b.way)
group by b.osm_id
order by count;

alter table planet_osm_trees add column h3_index h3index generated always as (h3_lat_lng_to_cell(way::POINT, 7)) stored;

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


alter table planet_osm_polygon_admin_6 add column h3_indexes h3index[] generated always as (get_h3_indexes(way, 7)) stored;

create table planet_osm_polygon_admin_6_flat as
select h3_index, osm_id, h3_cell_to_boundary_geometry(h3_index)
from(
select unnest (h3_indexes) as h3_index, osm_id
from planet_osm_polygon_admin_6) as a;

select b.osm_id,count(a.osm_id) from planet_osm_trees a join planet_osm_polygon_admin_6_flat b on a.h3_index = b.h3_index group by b.osm_id order by count;

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

ALTER TABLE planet_osm_polygon_admin_6  ADD COLUMN h3_indexes_compacted h3index[] GENERATED ALWAYS AS (get_h3_indexes_compact(way,7)) STORED;

create table planet_osm_polygon_admin_6_flat_compact as
select h3_index, osm_id, h3_cell_to_boundary_geometry(h3_index) from (
select unnest (h3_indexes_compacted) as h3_index, osm_id from planet_osm_polygon_admin_6) as a;


-- Raster 

select h3, unnest (stats) from h3_raster_summar((select rast from sample), 7);

SELECT
    (summary).h3 AS h3,
    (h3_raster_summary_stats_agg((summary).stats)).*
FROM (
    SELECT h3_raster_summary((select rast from sample), 7) AS summary
) as A
GROUP BY h3;

select rid, filename  from sample ;

select h3, stats from sample_h3;

alter table sample_h3 add column h3_shape geometry generated always as (h3_cell_to_boundary_geometry(h3)) stored;

alter table planet_osm_trees  add column h3_shape geometry generated always as (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(way::point, 7))) stored;


create table ndvi_hex as select *
from(
select(summary).h3 as h3,(h3_raster_summary_stats_agg((summary).stats)).*, filename
from(
    select h3_raster_summary_clip(rast, 7) as summary, filename
from ndvi_raster
) as A
group by h3, filename) as B
where sum != 'NaN';

select * from ndvi_hex limit 10;

alter table ndvi_hex add column h3_shape geometry generated always as (h3_cell_to_boundary_geometry(h3)) stored;

select b.osm_id, avg(a.mean) from ndvi_hex a join planet_osm_polygon_admin_6_flat b on a.h3 = b.h3_index group by b.osm_id;

