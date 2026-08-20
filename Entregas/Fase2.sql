/*
============================================================================
 techstore - pipeline de dados (snowflake)
 fase 1: preparação do ambiente
 fase 2: análise da fonte de dados / staging
============================================================================
 execute este script no worksheet do snowflake (snowsight) usando um
 usuário com privilégios accountadmin ou sysadmin + securityadmin.
============================================================================
*/


-- ###########################################################################
-- fase 1 - preparação do ambiente
-- ###########################################################################

use role securityadmin;

-- ---------------------------------------------------------------------------
-- 1. criar a role de acesso do time de análise
-- ---------------------------------------------------------------------------
create role if not exists techmart_analyst
    comment = 'role de acesso para analistas do projeto techstore dw';

-- conceder a role ao usuário atual (troque seu_usuario pelo seu usuário snowflake)
-- grant role techmart_analyst to user seu_usuario;
grant role techmart_analyst to role sysadmin;

use role sysadmin;

-- ---------------------------------------------------------------------------
-- 2. warehouse dedicado ao projeto
-- ---------------------------------------------------------------------------
create warehouse if not exists techmart_wh
    warehouse_size = 'xsmall'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'warehouse do projeto techstore data warehouse';

-- ---------------------------------------------------------------------------
-- 3. database e schemas
-- ---------------------------------------------------------------------------
create database if not exists techmart_dw
    comment = 'data warehouse da techstore';

use database techmart_dw;

create schema if not exists staging
    comment = 'área de staging - dados brutos, réplica exata da fonte';

create schema if not exists dw_core
    comment = 'core do data warehouse - dimensões e fatos (modelo estrela)';

create schema if not exists dw_marts
    comment = 'data marts especializados por área de negócio';

-- ---------------------------------------------------------------------------
-- 4. stage interno para upload dos arquivos csv
-- ---------------------------------------------------------------------------
use schema staging;

-- file format específico para os csvs do projeto (separador vírgula, header, aspas)
create or replace file format techmart_dw.staging.ff_csv_techstore
    type = 'csv'
    field_delimiter = ','
    skip_header = 1
    field_optionally_enclosed_by = '"'
    null_if = ('', 'null', 'NULL')
    empty_field_as_null = true
    date_format = 'yyyy-mm-dd'
    encoding = 'utf8'
    comment = 'formato padrão dos arquivos csv gerados pelo gerar_dados.py';

-- stage interno (armazenamento gerenciado pelo próprio snowflake)
create or replace stage techmart_dw.staging.techmart_stage
    file_format = techmart_dw.staging.ff_csv_techstore
    comment = 'stage para upload dos arquivos csv (regions, categories, suppliers, products, customers, orders, order_items)';

-- ---------------------------------------------------------------------------
-- 5. grants para a role techmart_analyst
-- ---------------------------------------------------------------------------
grant usage on warehouse techmart_wh to role techmart_analyst;

grant usage on database techmart_dw to role techmart_analyst;

grant usage on schema techmart_dw.staging   to role techmart_analyst;
grant usage on schema techmart_dw.dw_core   to role techmart_analyst;
grant usage on schema techmart_dw.dw_marts  to role techmart_analyst;

-- direito de criar objetos em cada schema
grant create table, create view, create procedure, create task, create file format, create stage, create stream
    on schema techmart_dw.staging  to role techmart_analyst;
grant create table, create view, create procedure, create task
    on schema techmart_dw.dw_core  to role techmart_analyst;
grant create table, create view, create procedure, create task
    on schema techmart_dw.dw_marts to role techmart_analyst;

-- acesso a tabelas/views futuras e existentes (facilita o dia a dia do analista)
grant select on future tables in schema techmart_dw.staging  to role techmart_analyst;
grant select on future tables in schema techmart_dw.dw_core  to role techmart_analyst;
grant select on future tables in schema techmart_dw.dw_marts to role techmart_analyst;
grant select on future views  in schema techmart_dw.staging  to role techmart_analyst;
grant select on future views  in schema techmart_dw.dw_core  to role techmart_analyst;
grant select on future views  in schema techmart_dw.dw_marts to role techmart_analyst;

-- executar tasks criadas com essa role
grant execute task on account to role techmart_analyst;

-- a partir daqui, use a role do projeto
use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema staging;


-- ###########################################################################
-- fase 2 - análise da fonte de dados / staging
-- ###########################################################################

-- ---------------------------------------------------------------------------
-- 1. tabelas de staging
--    -> réplicas exatas dos csvs de origem + colunas de auditoria
--    colunas de auditoria em todas as tabelas:
--      stg_file_name    -> nome do arquivo de origem
--      stg_load_ts      -> timestamp da carga
--      stg_row_number   -> linha do arquivo (rastreabilidade)
-- ---------------------------------------------------------------------------

create or replace table staging.stg_regions (
    region_id            number,
    region_name          varchar(100),
    region_code          varchar(10),
    stg_file_name        varchar(500),
    stg_row_number       number,
    stg_load_ts          timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_categories (
    category_id           number,
    category_name         varchar(100),
    category_description  varchar(1000),
    stg_file_name         varchar(500),
    stg_row_number        number,
    stg_load_ts           timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_suppliers (
    supplier_id           number,
    supplier_name         varchar(200),
    contact_email         varchar(200),
    phone                 varchar(50),
    stg_file_name         varchar(500),
    stg_row_number        number,
    stg_load_ts           timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_products (
    product_id            number,
    product_name          varchar(200),
    category_id           number,
    supplier_id           number,
    price                 number(12,2),
    cost                  number(12,2),
    stock_quantity        number,
    created_date          date,
    stg_file_name         varchar(500),
    stg_row_number        number,
    stg_load_ts           timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_customers (
    customer_id            number,
    first_name             varchar(100),
    last_name               varchar(100),
    email                    varchar(200),
    phone                    varchar(50),
    birth_date               date,
    gender                   varchar(1),
    city                     varchar(150),
    state                    varchar(2),
    region_id                number,
    registration_date        date,
    customer_segment         varchar(50),
    stg_file_name             varchar(500),
    stg_row_number            number,
    stg_load_ts               timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_orders (
    order_id               number,
    customer_id            number,
    order_date              date,
    status                   varchar(50),
    channel                  varchar(50),
    total_amount             number(14,2),
    shipping_cost             number(10,2),
    stg_file_name              varchar(500),
    stg_row_number             number,
    stg_load_ts                 timestamp_ntz default current_timestamp()
);

create or replace table staging.stg_order_items (
    item_id                  number,
    order_id                  number,
    product_id                 number,
    quantity                    number,
    unit_price                    number(12,2),
    total_price                    number(14,2),
    stg_file_name                    varchar(500),
    stg_row_number                    number,
    stg_load_ts                        timestamp_ntz default current_timestamp()
);

-- ---------------------------------------------------------------------------
-- 2. upload dos arquivos para o stage
-- ---------------------------------------------------------------------------
-- opção a) via snowsight (interface web):
--    data > databases > techmart_dw > staging > stages > techmart_stage
--    > botão "+ files" > selecione os 7 csvs > upload
--
-- opção b) via snowsql (linha de comando), a partir da pasta com os csvs:
--    put file://regions.csv       @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://categories.csv    @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://suppliers.csv     @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://products.csv      @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://customers.csv     @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://orders.csv        @techmart_dw.staging.techmart_stage auto_compress=true;
--    put file://order_items.csv   @techmart_dw.staging.techmart_stage auto_compress=true;
--
-- conferir o que chegou no stage:
list @techmart_dw.staging.techmart_stage;

-- 3. carga inicial (copy into) - primeira carga manual
copy into staging.stg_regions (region_id, region_name, region_code, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/regions.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_categories (category_id, category_name, category_description, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/categories.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_suppliers (supplier_id, supplier_name, contact_email, phone, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, $4, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/suppliers.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_products (product_id, product_name, category_id, supplier_id, price, cost, stock_quantity, created_date, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, $4, $5, $6, $7, $8, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/products.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_customers (customer_id, first_name, last_name, email, phone, birth_date, gender, city, state, region_id, registration_date, customer_segment, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/customers.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_orders (order_id, customer_id, order_date, status, channel, total_amount, shipping_cost, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, $4, $5, $6, $7, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/orders.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

copy into staging.stg_order_items (item_id, order_id, product_id, quantity, unit_price, total_price, stg_file_name, stg_row_number)
from (
    select $1, $2, $3, $4, $5, $6, metadata$filename, metadata$file_row_number
    from @techmart_dw.staging.techmart_stage/order_items.csv
)
file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore')
on_error = 'abort_statement';

-- conferência rápida
select 'stg_regions' as tabela, count(*) as linhas from staging.stg_regions
union all select 'stg_categories', count(*) from staging.stg_categories
union all select 'stg_suppliers', count(*) from staging.stg_suppliers
union all select 'stg_products', count(*) from staging.stg_products
union all select 'stg_customers', count(*) from staging.stg_customers
union all select 'stg_orders', count(*) from staging.stg_orders
union all select 'stg_order_items', count(*) from staging.stg_order_items;

-- 4. log de carga + task para verificar novas informações automaticamente
create or replace table staging.stg_load_log (
    log_id           number autoincrement,
    table_name       varchar(100),
    stage_path       varchar(500),
    rows_loaded      number,
    rows_parsed      number,
    status           varchar(50),
    error_message    varchar(2000),
    load_start_ts    timestamp_ntz,
    load_end_ts      timestamp_ntz default current_timestamp()
);

-- stored procedure que executa o copy into de todas as tabelas de staging
create or replace procedure staging.sp_load_all_staging()
returns string
language sql
as
$$
declare
    v_start timestamp_ltz;
    v_result string default '';
begin
    v_start := current_timestamp();

    -- regions
    copy into staging.stg_regions (region_id, region_name, region_code, stg_file_name, stg_row_number)
    from (select $1,$2,$3, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/regions.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- categories
    copy into staging.stg_categories (category_id, category_name, category_description, stg_file_name, stg_row_number)
    from (select $1,$2,$3, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/categories.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- suppliers
    copy into staging.stg_suppliers (supplier_id, supplier_name, contact_email, phone, stg_file_name, stg_row_number)
    from (select $1,$2,$3,$4, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/suppliers.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- products
    copy into staging.stg_products (product_id, product_name, category_id, supplier_id, price, cost, stock_quantity, created_date, stg_file_name, stg_row_number)
    from (select $1,$2,$3,$4,$5,$6,$7,$8, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/products.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- customers
    copy into staging.stg_customers (customer_id, first_name, last_name, email, phone, birth_date, gender, city, state, region_id, registration_date, customer_segment, stg_file_name, stg_row_number)
    from (select $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/customers.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- orders
    copy into staging.stg_orders (order_id, customer_id, order_date, status, channel, total_amount, shipping_cost, stg_file_name, stg_row_number)
    from (select $1,$2,$3,$4,$5,$6,$7, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/orders.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- order_items
    copy into staging.stg_order_items (item_id, order_id, product_id, quantity, unit_price, total_price, stg_file_name, stg_row_number)
    from (select $1,$2,$3,$4,$5,$6, metadata$filename, metadata$file_row_number from @techmart_dw.staging.techmart_stage/order_items.csv)
    file_format = (format_name = 'techmart_dw.staging.ff_csv_techstore');

    -- registra no log a partir do histórico de copy do próprio snowflake
    -- (copy_history exige table_name preenchido - não aceita null nem location;
    -- por isso chamamos uma vez por tabela e juntamos tudo com union all)
    insert into staging.stg_load_log (table_name, stage_path, rows_loaded, rows_parsed, status, error_message, load_start_ts)
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_regions', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_categories', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_suppliers', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_products', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_customers', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_orders', start_time => :v_start))
    union all
    select table_name, stage_location, row_count, row_parsed, status, first_error_message, :v_start
    from table(information_schema.copy_history(table_name => 'staging.stg_order_items', start_time => :v_start));

    v_result := 'carga concluída em ' || current_timestamp()::string;
    return v_result;
end;
$$;

-- testar a procedure manualmente
call staging.sp_load_all_staging();

-- task: verifica periodicamente se há arquivos novos no stage e recarrega
create or replace task staging.task_load_staging
    warehouse = techmart_wh
    schedule = '30 minute'
    comment = 'verifica e carrega novos arquivos do stage techmart_stage para as tabelas stg_*'
as
    call staging.sp_load_all_staging();

-- tasks nascem suspended por padrão - ativar:
alter task staging.task_load_staging resume;

-- verificar status da task
show tasks like 'task_load_staging' in schema staging;

-- 5. view de controle - última carga de dados por tabela
create or replace view staging.vw_ultima_carga as
select
    table_name,
    max(load_end_ts)                                   as ultima_carga,
    sum(rows_loaded)                                    as total_linhas_carregadas_execucao,
    max(status)                                          as ultimo_status
from staging.stg_load_log
group by table_name
order by ultima_carga desc;

-- consultar
select * from staging.vw_ultima_carga;