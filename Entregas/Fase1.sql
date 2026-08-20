-- Criação de Roles
create role if not exists techmart_analyst;
grant role techmart_analyst to role sysadmin;
use role sysadmin;

-- Criar database
create database if not exists techmart_dw;
use database techmart_dw;

-- Criar schema
grant create schema on database techmart_dw to role sysadmin;
create schema if not exists staging;
create schema if not exists dw_core;
create schema if not exists dw_marts;

-- Criação de stage para carregar os csv
use schema staging;
create or replace file format ff_csv_techstore
    type = csv
    field_delimiter = ','
    skip_header = 1
    field_optionally_enclosed_by = '"';
create or replace stage techmart_dw.staging.techmart_stage
    file_format = techmart_dw.staging.ff_csv_techstore;

-- Criação do warehouse
use role sysadmin;

create warehouse if not exists techmart_wh
    warehouse_size = 'xsmall'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'warehouse do projeto techstore data warehouse';

-- Grants para a techmart_analyst
grant usage on warehouse techmart_wh to role techmart_analyst;
grant usage on database techmart_dw to role techmart_analyst;

-- Grants para as tabelas
grant usage on schema techmart_dw.STAGING to role techmart_analyst;
grant usage on schema techmart_dw.DW_CORE to role techmart_analyst;
grant usage on schema techmart_dw.DW_MARTS to role techmart_analyst;

-- Dire to de criar obj tos em cada schema
grant create table, create view, create procedure, create task, create file format, create stage, create stream
 on schema techmart_dw.STAGING  to role techmart_analyst;
grant create table, create view, create procedure, create task
 on schema techmart_dw.DW_CORE  to role techmart_analyst;
grant create table, create view, create procedure, create task
 on schema techmart_dw.DW_MARTS to role techmart_analyst;

-- Acesso a tabelas/views
grant select on future tables in schema techmart_dw.staging  to role techmart_analyst;
grant select on future tables in schema techmart_dw.dw_core  to role techmart_analyst;
grant select on future tables in schema techmart_dw.dw_marts to role techmart_analyst;
grant select on future views  in schema techmart_dw.staging  to role techmart_analyst;
grant select on future views  in schema techmart_dw.dw_core  to role techmart_analyst;
grant select on future views  in schema techmart_dw.dw_marts to role techmart_analyst;

-- Executar tasks criadas com essa role
grant execute task on account to role techmart_analyst;

-- use a role do proj to
use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema staging;
