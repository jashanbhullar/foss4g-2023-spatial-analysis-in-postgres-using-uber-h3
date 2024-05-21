select distinct highway from melbourne_roads order by highway ;

select
	ST_Length(geom),
	*
from
	melbourne_roads
where
	"highway" in ('motorway', 'motorway_link', 'primary', 'primary_link', 'secondary', 'secondary_link', 'tertiary', 'residential')
order by st_length desc
limit 10;

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

ALTER TABLE melbourne_roads  ADD COLUMN h3_indexes h3index[] GENERATED ALWAYS AS (get_h3_indexes(ST_Buffer(geom, 0.0001801802),12)) STORED;

drop table melbourne_roads_flat;
create table melbourne_roads_flat as
select
	h3_index,
	osm_id,
	highway,
	h3_cell_to_boundary_geometry(h3_index)
from
	(
	select
		unnest (h3_indexes) as h3_index,
		osm_id,
		highway
	from
		melbourne_roads) as a;

drop table line_polygon_temp;
create table line_polygon_temp as 
select h3_polygon_to_cells(ST_Buffer(geom, 0.0001801802),12) from melbourne_roads where osm_id = '265723201';

select * from line_polygon_temp ;

alter table line_polygon_temp  ADD COLUMN h3_index_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_polygon_to_cells)) STORED;

select
	p.pos_id ,
	array_agg(l.osm_id)
from
	tracking_data p
left join melbourne_roads l on
	(ST_Intersects(p.point ,
	l.geom)
		or ST_Distance(p.point,
		l.geom) < 0.000134 )
where
	l.highway in ('motorway', 'motorway_link', 'primary', 'primary_link', 'secondary', 'secondary_link', 'tertiary', 'residential')
group by p.pos_id
order by
	p.pos_id;

select
	p.pos_id,
	array_agg(l.osm_id) 
from
	tracking_data p
left join melbourne_roads_flat l on
	p.h3_index_12 = l.h3_index
where
	l.highway in ('motorway', 'motorway_link', 'primary', 'primary_link', 'secondary', 'secondary_link', 'tertiary', 'residential')
group by p.pos_id
order by
	p.pos_id;




