use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema dw_core;

create or replace table dw_core.dim_date (
    date_sk number(8) primary key,
    full_date date not null,
    day number(2),
    day_name varchar(15),
    day_of_week number(1),
    is_weekend boolean,
    week_of_year number(2),
    month number(2),
    month_name varchar(15),
    quarter number(1),
    quarter_name varchar(2),
    year number(4)
);

create or replace table dw_core.dim_region (
    region_sk number autoincrement primary key,
    region_id number not null,
    region_name varchar(100),
    region_code varchar(10)
);

create or replace table dw_core.dim_customer (
    customer_sk number autoincrement primary key,
    customer_id number not null,
    first_name varchar(100),
    last_name varchar(100),
    full_name varchar(200),
    email varchar(200),
    phone varchar(50),
    birth_date date,
    age number,
    gender varchar(1),
    city varchar(150),
    state varchar(2),
    region_id number,
    region_name varchar(100),
    customer_segment varchar(50),
    registration_date date,
    effective_date date,
    end_date date,
    is_current boolean
);

create or replace table dw_core.dim_product (
    product_sk number autoincrement primary key,
    product_id number not null,
    product_name varchar(200),
    category_id number,
    category_name varchar(100),
    category_description varchar(1000),
    supplier_id number,
    supplier_name varchar(200),
    supplier_email varchar(200),
    supplier_phone varchar(50),
    list_price number(12,2),
    cost number(12,2),
    created_date date,
    effective_date date,
    end_date date,
    is_current boolean
);

create or replace table dw_core.dim_channel (
    channel_sk number autoincrement primary key,
    channel_code varchar(50) not null,
    channel_name varchar(100),
    channel_type varchar(50),
    is_online boolean
);

create or replace table dw_core.fact_sales (
    sales_sk number autoincrement primary key,
    date_sk number(8) references dw_core.dim_date(date_sk),
    customer_sk number references dw_core.dim_customer(customer_sk),
    product_sk number references dw_core.dim_product(product_sk),
    region_sk number references dw_core.dim_region(region_sk),
    channel_sk number references dw_core.dim_channel(channel_sk),
    order_id number,
    item_id number,
    order_status varchar(50),
    quantity number,
    unit_price number(12,2),
    total_price number(14,2),
    list_price_at_sale number(12,2),
    unit_cost number(12,2),
    total_cost number(14,2),
    gross_margin number(14,2),
    discount_amount number(14,2)
);

-- desafio: view calculada em cima da fact_sales
--   quantidade vendida | valor de vendas | custo dos produtos | lucro bruto | margem de lucro
--   fórmulas:
--     lucro bruto (R$)    = valor de vendas - custo dos produtos
--     margem de lucro (%) = lucro bruto / valor de vendas * 100

create or replace view dw_marts.vw_lucratividade_vendas as
select
    fs.sales_sk,
    fs.order_id,
    fs.item_id,
    dd.full_date as data_venda,
    dd.year,
    dd.quarter_name,
    dc.customer_id,
    dc.full_name as cliente,
    dp.product_id,
    dp.product_name,
    dp.category_name,
    dr.region_name,
    dch.channel_name,
    fs.quantity as quantidade_vendida,
    fs.total_price as valor_de_vendas,
    fs.total_cost as custo_dos_produtos,
    fs.total_price - fs.total_cost as lucro_bruto,
    round(
        (fs.total_price - fs.total_cost) / nullif(fs.total_price, 0) * 100,
        2
    ) as margem_de_lucro_pct
from dw_core.fact_sales fs
join dw_core.dim_date dd
    on dd.date_sk = fs.date_sk
join dw_core.dim_customer dc
    on dc.customer_sk = fs.customer_sk
join dw_core.dim_product dp
    on dp.product_sk = fs.product_sk
left join dw_core.dim_region dr
    on dr.region_sk = fs.region_sk
left join dw_core.dim_channel dch
    on dch.channel_sk = fs.channel_sk;
