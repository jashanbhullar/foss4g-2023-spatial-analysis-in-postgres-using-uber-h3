CREATE TABLE
    tracking_data_raw (
        pos_id INT,
        ivu_id VARCHAR,
        record_dto VARCHAR,
        position_latitude VARCHAR,
        position_longitude VARCHAR,
        record_number VARCHAR,
        record_cluster VARCHAR
    );
 COPY tracking_data_raw FROM '/home/sample-data.csv' DELIMITER ','CSV HEADER;


drop table tracking_data;

CREATE TABLE
    tracking_data (
        pos_id INT,
        ivu_id VARCHAR,
        record_dto TIMESTAMP,
        position_latitude FLOAT,
        position_longitude FLOAT,
        record_number VARCHAR,
        record_cluster DATE
    );

INSERT INTO tracking_data  (pos_id, ivu_id, record_dto, position_latitude, position_longitude, record_number, record_cluster)
SELECT
    pos_id::INT,
    ivu_id,
    TO_TIMESTAMP(record_dto , 'DD/MM/YYYY HH24:MI:SS'),
    position_latitude::FLOAT * -1,
    position_longitude::FLOAT,
    record_number,
    TO_DATE(record_cluster , 'DD/MM/YYYY')
FROM
    tracking_data_raw;    

   select count(*) from tracking_data;   
  
alter table tracking_data drop column point; 
alter table tracking_data  add column point geometry(Point, 4326) generated always as (ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326)) stored;

alter table tracking_data drop column h3_index_7; 
ALTER TABLE tracking_data ADD COLUMN h3_index_7 h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 7)) STORED;

alter table tracking_data drop column h3_index_7_shape; 
alter table tracking_data ADD COLUMN h3_index_7_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 7))) STORED;


alter table tracking_data drop column h3_index_14; 
ALTER TABLE tracking_data ADD COLUMN h3_index_14 h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 14)) STORED;

alter table tracking_data drop column h3_index_14_shape; 
alter table tracking_data ADD COLUMN h3_index_14_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 14))) STORED;

alter table tracking_data drop column h3_index_13_shape; 
alter table tracking_data ADD COLUMN h3_index_13_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 13))) STORED;

alter table tracking_data drop column h3_index_12; 
ALTER TABLE tracking_data ADD COLUMN h3_index_12 h3index GENERATED ALWAYS AS (h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 12)) STORED;


alter table tracking_data drop column h3_index_12_shape; 
alter table tracking_data ADD COLUMN h3_index_12_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 12))) STORED;

alter table tracking_data drop column h3_index_11_shape; 
alter table tracking_data ADD COLUMN h3_index_11_shape geometry GENERATED ALWAYS AS (h3_cell_to_boundary_geometry(h3_lat_lng_to_cell(ST_SetSRID(st_makepoint(position_longitude, position_latitude), 4326), 11))) STORED;



