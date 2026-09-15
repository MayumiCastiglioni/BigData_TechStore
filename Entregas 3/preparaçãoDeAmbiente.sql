/*
 FASE 5 - DATA MART

 - Criar as 5 tabelas de Data Mart em DW_MARTS.
 - Implementar a lógica das análises nas procedures sp_load_mart_*.
 - Manter a carga com TRUNCATE + INSERT a partir do DW_CORE.
 - Executar as cargas por meio da procedure orquestradora e da TASK diária.

 Observação:
 As análises abaixo dependem de dados na DW_CORE.FACT_SALES.
 A Fase 4 criou a estrutura da FACT_SALES, mas deixou sua carga para uma etapa
 específica de fatos. Este script não altera a Fase 4 nem carrega a FACT_SALES.
*/

use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema dw_marts;

-- ============================================================================
-- 1. TABELAS DOS DATA MARTS
-- ============================================================================

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
    product_name_a            varchar(200),
    product_id_b              number,
    product_name_b            varchar(200),
    qtd_pedidos_juntos        number,
    suporte_pct               number(6,2),
    confianca_pct             number(6,2),
    lift                      number(8,4),
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

-- ============================================================================
-- 2. ANÁLISE DE SAZONALIDADE
-- ============================================================================

create or replace procedure dw_marts.sp_load_mart_sazonalidade()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_sazonalidade;

    insert into dw_marts.mart_sazonalidade (
        ano,
        trimestre,
        mes,
        mes_nome,
        category_name,
        quantidade_vendida,
        valor_de_vendas
    )
    select
        dd.year as ano,
        dd.quarter_name as trimestre,
        dd.month as mes,
        dd.month_name as mes_nome,
        dp.category_name,
        sum(fs.quantity) as quantidade_vendida,
        sum(fs.total_price) as valor_de_vendas
    from dw_core.fact_sales fs
    join dw_core.dim_date dd
        on dd.date_sk = fs.date_sk
    join dw_core.dim_product dp
        on dp.product_sk = fs.product_sk
    group by
        dd.year,
        dd.quarter_name,
        dd.month,
        dd.month_name,
        dp.category_name;

    return 'mart_sazonalidade: carga concluída em ' || current_timestamp()::string;
end;
$$;

-- ============================================================================
-- 3. ANÁLISE DE COHORT - COMPORTAMENTO DE CLIENTES
-- ============================================================================

create or replace procedure dw_marts.sp_load_mart_cohort_clientes()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_cohort_clientes;

    insert into dw_marts.mart_cohort_clientes (
        cohort_mes,
        mes_atividade,
        numero_periodo,
        clientes_ativos,
        clientes_do_cohort,
        taxa_retencao_pct
    )
    with compras_cliente as (
        select distinct
            fs.customer_sk,
            dd.full_date
        from dw_core.fact_sales fs
        join dw_core.dim_date dd
            on dd.date_sk = fs.date_sk
        where fs.customer_sk is not null
    ),
    primeira_compra as (
        select
            customer_sk,
            date_trunc('month', min(full_date))::date as cohort_mes
        from compras_cliente
        group by customer_sk
    ),
    atividade as (
        select distinct
            cc.customer_sk,
            pc.cohort_mes,
            date_trunc('month', cc.full_date)::date as mes_atividade
        from compras_cliente cc
        join primeira_compra pc
            on pc.customer_sk = cc.customer_sk
    ),
    cohort_tamanho as (
        select
            cohort_mes,
            count(distinct customer_sk) as clientes_do_cohort
        from primeira_compra
        group by cohort_mes
    )
    select
        a.cohort_mes,
        a.mes_atividade,
        datediff(month, a.cohort_mes, a.mes_atividade) as numero_periodo,
        count(distinct a.customer_sk) as clientes_ativos,
        ct.clientes_do_cohort,
        round(
            count(distinct a.customer_sk)
            / nullif(ct.clientes_do_cohort, 0) * 100,
            2
        ) as taxa_retencao_pct
    from atividade a
    join cohort_tamanho ct
        on ct.cohort_mes = a.cohort_mes
    group by
        a.cohort_mes,
        a.mes_atividade,
        ct.clientes_do_cohort;

    return 'mart_cohort_clientes: carga concluída em ' || current_timestamp()::string;
end;
$$;

-- ============================================================================
-- 4. ANÁLISE RFM
-- ============================================================================

create or replace procedure dw_marts.sp_load_mart_rfm()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_rfm;

    insert into dw_marts.mart_rfm (
        customer_id,
        cliente,
        recencia_dias,
        frequencia_pedidos,
        valor_monetario,
        score_recencia,
        score_frequencia,
        score_monetario,
        score_rfm,
        segmento_cliente
    )
    with rfm_base as (
        select
            dc.customer_id,
            dc.full_name as cliente,
            max(dd.full_date) as ultima_compra,
            count(distinct fs.order_id) as frequencia_pedidos,
            sum(fs.total_price) as valor_monetario
        from dw_core.fact_sales fs
        join dw_core.dim_date dd
            on dd.date_sk = fs.date_sk
        join dw_core.dim_customer dc
            on dc.customer_sk = fs.customer_sk
        where fs.customer_sk is not null
        group by
            dc.customer_id,
            dc.full_name
    ),
    rfm_calculado as (
        select
            customer_id,
            cliente,
            datediff(
                day,
                ultima_compra,
                max(ultima_compra) over ()
            ) as recencia_dias,
            frequencia_pedidos,
            valor_monetario
        from rfm_base
    ),
    rfm_scores as (
        select
            *,
            6 - ntile(5) over (order by recencia_dias) as score_recencia,
            ntile(5) over (order by frequencia_pedidos) as score_frequencia,
            ntile(5) over (order by valor_monetario) as score_monetario
        from rfm_calculado
    )
    select
        customer_id,
        cliente,
        recencia_dias,
        frequencia_pedidos,
        valor_monetario,
        score_recencia,
        score_frequencia,
        score_monetario,
        to_varchar(score_recencia)
            || to_varchar(score_frequencia)
            || to_varchar(score_monetario) as score_rfm,
        case
            when score_recencia >= 4
             and score_frequencia >= 4
             and score_monetario >= 4
                then 'VIP'
            when score_recencia >= 4
             and score_frequencia >= 3
                then 'Fiel'
            when score_recencia >= 4
             and score_frequencia <= 2
                then 'Novo'
            when score_recencia <= 2
             and score_frequencia >= 3
                then 'Em Risco'
            when score_recencia <= 2
             and score_frequencia <= 2
                then 'Perdido'
            else 'Regular'
        end as segmento_cliente
    from rfm_scores;

    return 'mart_rfm: carga concluída em ' || current_timestamp()::string;
end;
$$;

-- ============================================================================
-- 5. ANÁLISE DE MARKET BASKET
-- ============================================================================

create or replace procedure dw_marts.sp_load_mart_market_basket()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_market_basket;

    insert into dw_marts.mart_market_basket (
        product_id_a,
        product_name_a,
        product_id_b,
        product_name_b,
        qtd_pedidos_juntos,
        suporte_pct,
        confianca_pct,
        lift
    )
    with produtos_pedido as (
        select distinct
            fs.order_id,
            fs.product_sk
        from dw_core.fact_sales fs
        where fs.order_id is not null
          and fs.product_sk is not null
    ),
    pares_produtos as (
        select
            a.product_sk as product_sk_a,
            b.product_sk as product_sk_b,
            a.order_id
        from produtos_pedido a
        join produtos_pedido b
            on a.order_id = b.order_id
           and a.product_sk < b.product_sk
    ),
    total_pedidos as (
        select count(distinct order_id) as total
        from produtos_pedido
    ),
    qtd_produto as (
        select
            product_sk,
            count(distinct order_id) as pedidos_produto
        from produtos_pedido
        group by product_sk
    ),
    pares as (
        select
            product_sk_a,
            product_sk_b,
            count(distinct order_id) as qtd_pedidos_juntos
        from pares_produtos
        group by
            product_sk_a,
            product_sk_b
    )
    select
        dpa.product_id as product_id_a,
        dpa.product_name as product_name_a,
        dpb.product_id as product_id_b,
        dpb.product_name as product_name_b,
        p.qtd_pedidos_juntos,
        round(
            p.qtd_pedidos_juntos
            / nullif(tp.total, 0) * 100,
            2
        ) as suporte_pct,
        round(
            p.qtd_pedidos_juntos
            / nullif(qa.pedidos_produto, 0) * 100,
            2
        ) as confianca_pct,
        round(
            (
                p.qtd_pedidos_juntos
                / nullif(qa.pedidos_produto, 0)
            )
            /
            (
                qb.pedidos_produto
                / nullif(tp.total, 0)
            ),
            4
        ) as lift
    from pares p
    join dw_core.dim_product dpa
        on dpa.product_sk = p.product_sk_a
       and dpa.is_current = true
    join dw_core.dim_product dpb
        on dpb.product_sk = p.product_sk_b
       and dpb.is_current = true
    join qtd_produto qa
        on qa.product_sk = p.product_sk_a
    join qtd_produto qb
        on qb.product_sk = p.product_sk_b
    cross join total_pedidos tp;

    return 'mart_market_basket: carga concluída em ' || current_timestamp()::string;
end;
$$;

-- ============================================================================
-- 6. ANÁLISE DE PERFORMANCE POR CANAL E REGIÃO
-- ============================================================================

create or replace procedure dw_marts.sp_load_mart_performance_canal_regiao()
returns string
language sql
execute as caller
as
$$
begin
    truncate table dw_marts.mart_performance_canal_regiao;

    insert into dw_marts.mart_performance_canal_regiao (
        ano,
        mes,
        channel_name,
        region_name,
        quantidade_pedidos,
        quantidade_vendida,
        valor_de_vendas,
        custo_dos_produtos,
        lucro_bruto,
        margem_de_lucro_pct
    )
    select
        dd.year as ano,
        dd.month as mes,
        dch.channel_name,
        dr.region_name,
        count(distinct fs.order_id) as quantidade_pedidos,
        sum(fs.quantity) as quantidade_vendida,
        sum(fs.total_price) as valor_de_vendas,
        sum(fs.total_cost) as custo_dos_produtos,
        sum(fs.gross_margin) as lucro_bruto,
        round(
            sum(fs.gross_margin)
            / nullif(sum(fs.total_price), 0) * 100,
            2
        ) as margem_de_lucro_pct
    from dw_core.fact_sales fs
    join dw_core.dim_date dd
        on dd.date_sk = fs.date_sk
    left join dw_core.dim_channel dch
        on dch.channel_sk = fs.channel_sk
    left join dw_core.dim_region dr
        on dr.region_sk = fs.region_sk
    group by
        dd.year,
        dd.month,
        dch.channel_name,
        dr.region_name;

    return 'mart_performance_canal_regiao: carga concluída em ' || current_timestamp()::string;
end;
$$;

-- ============================================================================
-- 7. ORQUESTRADOR DOS DATA MARTS
-- ============================================================================

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

-- ============================================================================
-- 8. CARGA MANUAL PARA TESTE
-- ============================================================================

call dw_marts.sp_load_all_marts();

-- ============================================================================
-- 9. TASK DIÁRIA
-- ============================================================================

create or replace task dw_marts.task_load_marts_daily
    warehouse = techmart_wh
    schedule = 'USING CRON 0 5 * * * America/Sao_Paulo'
    comment = 'Atualizacao diaria dos data marts a partir do DW_CORE'
as
    call dw_marts.sp_load_all_marts();

show tasks like 'task_load_marts_daily' in schema dw_marts;

-- ============================================================================
-- 10. PERMISSÕES PARA BI
-- ============================================================================

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

-- ============================================================================
-- 11. VALIDAÇÕES
-- ============================================================================

-- quantidade de registros gerados em cada Data Mart
select 'mart_sazonalidade' as mart, count(*) as quantidade_registros
from dw_marts.mart_sazonalidade
union all
select 'mart_cohort_clientes', count(*)
from dw_marts.mart_cohort_clientes
union all
select 'mart_rfm', count(*)
from dw_marts.mart_rfm
union all
select 'mart_market_basket', count(*)
from dw_marts.mart_market_basket
union all
select 'mart_performance_canal_regiao', count(*)
from dw_marts.mart_performance_canal_regiao;

-- validação rápida da sazonalidade
select *
from dw_marts.mart_sazonalidade
order by ano, mes, category_name;

-- validação rápida do cohort
select *
from dw_marts.mart_cohort_clientes
order by cohort_mes, mes_atividade;

-- validação rápida do RFM
select *
from dw_marts.mart_rfm
order by score_recencia desc, score_frequencia desc, score_monetario desc;

-- validação rápida do market basket
select *
from dw_marts.mart_market_basket
order by lift desc, qtd_pedidos_juntos desc;

-- validação rápida da performance
select *
from dw_marts.mart_performance_canal_regiao
order by ano, mes, valor_de_vendas desc;
