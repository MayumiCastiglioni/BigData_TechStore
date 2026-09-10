/*
 - Criar a estrutura das 5 tabelas de Data Mart em DW_MARTS.
 - Criar procedures "esqueleto" (sp_load_mart_*) já conectadas às tabelas
   corretas, com TRUNCATE + INSERT prontos.
 - Criar a procedure orquestradora e a TASK diária.
*/

use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema dw_marts;

create or replace table dw_marts.mart_sazonalidade (
    ano                     number(4),
    trimestre               varchar(2),
    mes                     number(2),
    mes_nome                varchar(15),
    category_name           varchar(100),
    quantidade_vendida      number,
    valor_de_vendas         number(14,2),
    dt_atualizacao          timestamp_ntz default current_timestamp()
);

create or replace table dw_marts.mart_cohort_clientes (
    cohort_mes              date,  
    mes_atividade            date,   
    numero_periodo           number, 
    clientes_ativos          number,
    clientes_do_cohort       number,
    taxa_retencao_pct        number(6,2),
    dt_atualizacao           timestamp_ntz default current_timestamp()
);

create or replace table dw_marts.mart_rfm (
    customer_id              number,
    cliente                  varchar(200),
    recencia_dias            number,   
    frequencia_pedidos       number,   
    valor_monetario          number(14,2), 
    score_recencia           number(1),
    score_frequencia         number(1),
    score_monetario          number(1),
    score_rfm                varchar(3),
    segmento_cliente         varchar(50),
    dt_atualizacao           timestamp_ntz default current_timestamp()
);

create or replace table dw_marts.mart_market_basket (
    product_id_a              number,
    product_name_a             varchar(200),
    product_id_b              number,
    product_name_b             varchar(200),
    qtd_pedidos_juntos         number,  -- em quantos pedidos apareceram juntos
    suporte_pct                number(6,2),
    confianca_pct              number(6,2),
    lift                       number(8,4),
    dt_atualizacao             timestamp_ntz default current_timestamp()
);

create or replace table dw_marts.mart_performance_canal_regiao (
    ano                       number(4),
    mes                       number(2),
    channel_name              varchar(100),
    region_name               varchar(100),
    quantidade_pedidos        number,
    quantidade_vendida        number,
    valor_de_vendas           number(14,2),
    custo_dos_produtos        number(14,2),
    lucro_bruto               number(14,2),
    margem_de_lucro_pct       number(6,2),
    dt_atualizacao            timestamp_ntz default current_timestamp()
);

create or replace procedure dw_marts.sp_load_mart_sazonalidade()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_sazonalidade;

    insert into dw_marts.mart_sazonalidade (
        ano, trimestre, mes, mes_nome, category_name,
        quantidade_vendida, valor_de_vendas
    )
    select null, null, null, null, null, null, null
    where 1 = 0;

    return 'mart_sazonalidade: estrutura pronta, lógica pendente';
end;
$$;


create or replace procedure dw_marts.sp_load_mart_cohort_clientes()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_cohort_clientes;

    insert into dw_marts.mart_cohort_clientes (
        cohort_mes, mes_atividade, numero_periodo,
        clientes_ativos, clientes_do_cohort, taxa_retencao_pct
    )
    select null, null, null, null, null, null
    where 1 = 0;

    return 'mart_cohort_clientes: estrutura pronta, lógica pendente';
end;
$$;


create or replace procedure dw_marts.sp_load_mart_rfm()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_rfm;

    insert into dw_marts.mart_rfm (
        customer_id, cliente, recencia_dias, frequencia_pedidos,
        valor_monetario, score_recencia, score_frequencia,
        score_monetario, score_rfm, segmento_cliente
    )
    select null, null, null, null, null, null, null, null, null, null
    where 1 = 0;

    return 'mart_rfm: estrutura pronta, lógica pendente';
end;
$$;


create or replace procedure dw_marts.sp_load_mart_market_basket()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_market_basket;

    insert into dw_marts.mart_market_basket (
        product_id_a, product_name_a, product_id_b, product_name_b,
        qtd_pedidos_juntos, suporte_pct, confianca_pct, lift
    )
    select null, null, null, null, null, null, null, null
    where 1 = 0;

    return 'mart_market_basket: estrutura pronta, lógica pendente';
end;
$$;


create or replace procedure dw_marts.sp_load_mart_performance_canal_regiao()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_performance_canal_regiao;

    insert into dw_marts.mart_performance_canal_regiao (
        ano, mes, channel_name, region_name,
        quantidade_pedidos, quantidade_vendida, valor_de_vendas,
        custo_dos_produtos, lucro_bruto, margem_de_lucro_pct
    )
    select null, null, null, null, null, null, null, null, null, null
    where 1 = 0;

    return 'mart_performance_canal_regiao: estrutura pronta, lógica pendente';
end;
$$;

create or replace procedure dw_marts.sp_load_all_marts()
returns string
language sql
execute as caller
as
$$
begin
    call dw_marts.sp_load_mart_sazonalidade();
    call dw_marts.sp_load_mart_cohort_clientes();
    call dw_marts.sp_load_mart_rfm();
    call dw_marts.sp_load_mart_market_basket();
    call dw_marts.sp_load_mart_performance_canal_regiao();

    return 'Carga diária dos data marts concluída em ' || current_timestamp()::string;
end;
$$;

call dw_marts.sp_load_all_marts();

create or replace task dw_marts.task_load_marts_daily
    warehouse = techmart_wh
    schedule = 'USING CRON 0 5 * * * America/Sao_Paulo'
    comment = 'Atualizacao diaria dos data marts a partir do DW_CORE'
as
    call dw_marts.sp_load_all_marts();

show tasks like 'task_load_marts_daily' in schema dw_marts;

use role securityadmin;

create role if not exists techmart_bi_reader
    comment = 'role somente leitura para conexao do Power BI (DW_MARTS)';

grant role techmart_bi_reader to role sysadmin;

use role sysadmin;

grant usage on warehouse techmart_wh to role techmart_bi_reader;
grant usage on database techmart_dw to role techmart_bi_reader;
grant usage on schema techmart_dw.dw_marts to role techmart_bi_reader;

grant select on all tables in schema techmart_dw.dw_marts to role techmart_bi_reader;
grant select on future tables in schema techmart_dw.dw_marts to role techmart_bi_reader;

use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema dw_marts;