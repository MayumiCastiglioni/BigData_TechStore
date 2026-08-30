/*
============================================================================
 TECHSTORE DATA WAREHOUSE
 FASE 4 - STAGING -> DATA WAREHOUSE
============================================================================

 OBJETIVOS
 1. Manter DIM_DATE com quatro anos-calendário:
      - dois anos anteriores
      - ano corrente
      - próximo ano
 2. Criar TASK mensal para garantir a janela da DIM_DATE.
 3. Carregar DIM_REGION e DIM_CHANNEL.
 4. Implementar SCD Tipo 2 em DIM_CUSTOMER e DIM_PRODUCT.
 5. Criar procedures de manutenção das dimensões.
 6. Criar TASK diária para STAGING -> DW_CORE.

 IMPORTANTE
 - A estrutura SCD de DIM_CUSTOMER e DIM_PRODUCT foi definida na Fase 3.
 - Este script NÃO altera o DDL das dimensões.
 - FACT_SALES não é carregada nesta fase.
 - O hash usado na detecção de alterações é calculado temporariamente
   dentro das procedures e não é armazenado no modelo dimensional.
 - A fonte oficial da Fase 4 é a STAGING criada na Fase 2.
============================================================================
*/

use role techmart_analyst;
use warehouse techmart_wh;
use database techmart_dw;
use schema dw_core;


-- ============================================================================
-- 1. DIM_DATE
-- ============================================================================

create or replace procedure dw_core.sp_load_dim_date()
returns string
language sql
execute as caller
as
$$
declare
    v_start_date date;
    v_end_date date;
    v_rows number;
begin

    /*
       Janela adotada: quatro anos-calendário.
       Exemplo em 2026: 2024, 2025, 2026 e 2027.
    */
    v_start_date := date_from_parts(year(current_date()) - 2, 1, 1);
    v_end_date   := date_from_parts(year(current_date()) + 1, 12, 31);

    merge into dw_core.dim_date target
    using (
        select
            to_number(to_char(date_value, 'YYYYMMDD')) as date_sk,
            date_value as full_date,
            day(date_value) as day,
            dayname(date_value) as day_name,
            dayofweekiso(date_value) as day_of_week,
            iff(dayofweekiso(date_value) in (6, 7), true, false) as is_weekend,
            weekofyear(date_value) as week_of_year,
            month(date_value) as month,
            monthname(date_value) as month_name,
            quarter(date_value) as quarter,
            'Q' || quarter(date_value) as quarter_name,
            year(date_value) as year
        from (
            select dateadd(day, seq4(), :v_start_date) as date_value
            from table(generator(rowcount => 2000))
        )
        where date_value <= :v_end_date
    ) source
        on target.date_sk = source.date_sk

    when not matched then
        insert (
            date_sk,
            full_date,
            day,
            day_name,
            day_of_week,
            is_weekend,
            week_of_year,
            month,
            month_name,
            quarter,
            quarter_name,
            year
        )
        values (
            source.date_sk,
            source.full_date,
            source.day,
            source.day_name,
            source.day_of_week,
            source.is_weekend,
            source.week_of_year,
            source.month,
            source.month_name,
            source.quarter,
            source.quarter_name,
            source.year
        );

    select count(*)
      into :v_rows
      from dw_core.dim_date
     where full_date between :v_start_date and :v_end_date;

    return 'DIM_DATE atualizada. Periodo: '
        || :v_start_date::string
        || ' ate '
        || :v_end_date::string
        || '. Registros no periodo: '
        || :v_rows::string;
end;
$$;

call dw_core.sp_load_dim_date();


-- ============================================================================
-- 2. TASK MENSAL - DIM_DATE
-- ============================================================================

create or replace task dw_core.task_load_dim_date_monthly
    warehouse = techmart_wh
    schedule = 'USING CRON 0 3 1 * * America/Sao_Paulo'
    comment = 'Atualiza mensalmente a DIM_DATE e garante a janela do proximo ano'
as
    call dw_core.sp_load_dim_date();

alter task dw_core.task_load_dim_date_monthly resume;


-- ============================================================================
-- 3. DIM_REGION - DIMENSAO BASICA
-- ============================================================================

create or replace procedure dw_core.sp_load_dim_region()
returns string
language sql
execute as caller
as
$$
declare
    v_rows number;
begin

    merge into dw_core.dim_region target
    using (
        select
            region_id,
            region_name,
            region_code
        from staging.stg_regions
        where region_id is not null
        qualify row_number() over (
            partition by region_id
            order by stg_load_ts desc, stg_row_number desc
        ) = 1
    ) source
        on target.region_id = source.region_id

    when matched then
        update set
            region_name = source.region_name,
            region_code = source.region_code

    when not matched then
        insert (
            region_id,
            region_name,
            region_code
        )
        values (
            source.region_id,
            source.region_name,
            source.region_code
        );

    select count(*)
      into :v_rows
      from dw_core.dim_region;

    return 'DIM_REGION atualizada. Total: ' || :v_rows::string;
end;
$$;


-- ============================================================================
-- 4. DIM_CHANNEL - DIMENSAO BASICA
-- ============================================================================

create or replace procedure dw_core.sp_load_dim_channel()
returns string
language sql
execute as caller
as
$$
declare
    v_rows number;
begin

    /*
       channel_code preserva o valor normalizado da STAGING.
       channel_type consolida os canais conhecidos em categorias de negócio.
       Os valores reais encontrados em STAGING devem ser validados com:

       select distinct channel
       from staging.stg_orders
       order by channel;
    */
    merge into dw_core.dim_channel target
    using (
        select
            upper(trim(channel)) as channel_code,
            initcap(trim(channel)) as channel_name,
            case
                when lower(trim(channel)) in
                    ('website', 'site', 'e-commerce', 'ecommerce')
                    then 'E-commerce'
                when lower(trim(channel)) = 'marketplace'
                    then 'Marketplace'
                when lower(trim(channel)) in
                    ('store', 'loja', 'loja fisica', 'loja física')
                    then 'Loja Física'
                else 'Outros'
            end as channel_type,
            case
                when lower(trim(channel)) in
                    ('website', 'site', 'e-commerce', 'ecommerce', 'marketplace')
                    then true
                else false
            end as is_online
        from staging.stg_orders
        where channel is not null
          and trim(channel) <> ''
        qualify row_number() over (
            partition by upper(trim(channel))
            order by stg_load_ts desc, stg_row_number desc
        ) = 1
    ) source
        on target.channel_code = source.channel_code

    when matched then
        update set
            channel_name = source.channel_name,
            channel_type = source.channel_type,
            is_online = source.is_online

    when not matched then
        insert (
            channel_code,
            channel_name,
            channel_type,
            is_online
        )
        values (
            source.channel_code,
            source.channel_name,
            source.channel_type,
            source.is_online
        );

    select count(*)
      into :v_rows
      from dw_core.dim_channel;

    return 'DIM_CHANNEL atualizada. Total: ' || :v_rows::string;
end;
$$;


-- ============================================================================
-- 5. DIM_CUSTOMER - SCD TIPO 2
-- ============================================================================

create or replace procedure dw_core.sp_load_dim_customer()
returns string
language sql
execute as caller
as
$$
declare
    v_versions_inserted number;
begin

    /*
       Seleciona somente o registro mais recente de cada customer_id
       na STAGING.

       age é derivado de birth_date e, portanto, NÃO participa do hash.
       full_name também é derivado de first_name + last_name e não participa
       do hash separadamente.
    */
    create or replace temporary table tmp_customer_source as
    select
        c.customer_id,
        c.first_name,
        c.last_name,
        trim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')) as full_name,
        c.email,
        c.phone,
        c.birth_date,
        case
            when c.birth_date is not null
                then datediff(year, c.birth_date, current_date())
                     - iff(
                         dateadd(
                             year,
                             datediff(year, c.birth_date, current_date()),
                             c.birth_date
                         ) > current_date(),
                         1,
                         0
                     )
            else null
        end as age,
        c.gender,
        c.city,
        c.state,
        c.region_id,
        r.region_name,
        c.customer_segment,
        c.registration_date,
        sha2(
            concat_ws(
                '||',
                coalesce(c.first_name, ''),
                coalesce(c.last_name, ''),
                coalesce(c.email, ''),
                coalesce(c.phone, ''),
                coalesce(to_varchar(c.birth_date), ''),
                coalesce(c.gender, ''),
                coalesce(c.city, ''),
                coalesce(c.state, ''),
                coalesce(to_varchar(c.region_id), ''),
                coalesce(r.region_name, ''),
                coalesce(c.customer_segment, ''),
                coalesce(to_varchar(c.registration_date), '')
            ),
            256
        ) as source_hash
    from staging.stg_customers c
    left join dw_core.dim_region r
        on r.region_id = c.region_id
    where c.customer_id is not null
    qualify row_number() over (
        partition by c.customer_id
        order by c.stg_load_ts desc, c.stg_row_number desc
    ) = 1;


    /*
       Fecha a versão corrente somente quando houve alteração
       em algum atributo historizado.
    */
    update dw_core.dim_customer target
       set end_date = current_date() - 1,
           is_current = false
     from tmp_customer_source source
    where target.customer_id = source.customer_id
      and target.is_current = true
      and sha2(
            concat_ws(
                '||',
                coalesce(target.first_name, ''),
                coalesce(target.last_name, ''),
                coalesce(target.email, ''),
                coalesce(target.phone, ''),
                coalesce(to_varchar(target.birth_date), ''),
                coalesce(target.gender, ''),
                coalesce(target.city, ''),
                coalesce(target.state, ''),
                coalesce(to_varchar(target.region_id), ''),
                coalesce(target.region_name, ''),
                coalesce(target.customer_segment, ''),
                coalesce(to_varchar(target.registration_date), '')
            ),
            256
          ) <> source.source_hash;


    /*
       Insere clientes novos e novas versões de clientes alterados.
    */
    insert into dw_core.dim_customer (
        customer_id,
        first_name,
        last_name,
        full_name,
        email,
        phone,
        birth_date,
        age,
        gender,
        city,
        state,
        region_id,
        region_name,
        customer_segment,
        registration_date,
        effective_date,
        end_date,
        is_current
    )
    select
        source.customer_id,
        source.first_name,
        source.last_name,
        source.full_name,
        source.email,
        source.phone,
        source.birth_date,
        source.age,
        source.gender,
        source.city,
        source.state,
        source.region_id,
        source.region_name,
        source.customer_segment,
        source.registration_date,
        case
            when previous.customer_id is null
                then coalesce(source.registration_date, current_date())
            else current_date()
        end as effective_date,
        null as end_date,
        true as is_current
    from tmp_customer_source source
    left join dw_core.dim_customer previous
        on previous.customer_id = source.customer_id
       and previous.is_current = true
    where previous.customer_id is null
       or sha2(
            concat_ws(
                '||',
                coalesce(previous.first_name, ''),
                coalesce(previous.last_name, ''),
                coalesce(previous.email, ''),
                coalesce(previous.phone, ''),
                coalesce(to_varchar(previous.birth_date), ''),
                coalesce(previous.gender, ''),
                coalesce(previous.city, ''),
                coalesce(previous.state, ''),
                coalesce(to_varchar(previous.region_id), ''),
                coalesce(previous.region_name, ''),
                coalesce(previous.customer_segment, ''),
                coalesce(to_varchar(previous.registration_date), '')
            ),
            256
          ) <> source.source_hash;


    /*
       age é um atributo derivado. Atualiza somente as versões correntes
       para acompanhar a passagem do tempo sem criar uma nova versão SCD2.
    */
    update dw_core.dim_customer
       set age =
           case
               when birth_date is not null
                   then datediff(year, birth_date, current_date())
                        - iff(
                            dateadd(
                                year,
                                datediff(year, birth_date, current_date()),
                                birth_date
                            ) > current_date(),
                            1,
                            0
                        )
               else null
           end
     where is_current = true;


    select count(*)
      into :v_versions_inserted
      from dw_core.dim_customer
     where effective_date = current_date();

    return 'DIM_CUSTOMER SCD2 concluida. Versoes com inicio hoje: '
        || :v_versions_inserted::string;
end;
$$;


-- ============================================================================
-- 6. DIM_PRODUCT - SCD TIPO 2
-- ============================================================================

create or replace procedure dw_core.sp_load_dim_product()
returns string
language sql
execute as caller
as
$$
declare
    v_versions_inserted number;
begin

    /*
       As tabelas de categoria e fornecedor são deduplicadas antes do JOIN.
       Isso evita multiplicação de linhas caso a STAGING possua mais de um
       registro para a mesma chave natural.
    */
    create or replace temporary table tmp_product_source as
    with latest_categories as (
        select
            category_id,
            category_name,
            category_description
        from staging.stg_categories
        where category_id is not null
        qualify row_number() over (
            partition by category_id
            order by stg_load_ts desc, stg_row_number desc
        ) = 1
    ),
    latest_suppliers as (
        select
            supplier_id,
            supplier_name,
            contact_email,
            phone
        from staging.stg_suppliers
        where supplier_id is not null
        qualify row_number() over (
            partition by supplier_id
            order by stg_load_ts desc, stg_row_number desc
        ) = 1
    ),
    latest_products as (
        select
            p.product_id,
            p.product_name,
            p.category_id,
            p.supplier_id,
            p.price,
            p.cost,
            p.created_date
        from staging.stg_products p
        where p.product_id is not null
        qualify row_number() over (
            partition by p.product_id
            order by p.stg_load_ts desc, p.stg_row_number desc
        ) = 1
    )
    select
        p.product_id,
        p.product_name,
        p.category_id,
        c.category_name,
        c.category_description,
        p.supplier_id,
        s.supplier_name,
        s.contact_email as supplier_email,
        s.phone as supplier_phone,
        p.price as list_price,
        p.cost,
        p.created_date,
        sha2(
            concat_ws(
                '||',
                coalesce(p.product_name, ''),
                coalesce(to_varchar(p.category_id), ''),
                coalesce(c.category_name, ''),
                coalesce(c.category_description, ''),
                coalesce(to_varchar(p.supplier_id), ''),
                coalesce(s.supplier_name, ''),
                coalesce(s.contact_email, ''),
                coalesce(s.phone, ''),
                coalesce(to_varchar(p.price), ''),
                coalesce(to_varchar(p.cost), ''),
                coalesce(to_varchar(p.created_date), '')
            ),
            256
        ) as source_hash
    from latest_products p
    left join latest_categories c
        on c.category_id = p.category_id
    left join latest_suppliers s
        on s.supplier_id = p.supplier_id;


    /*
       Fecha a versão corrente somente quando houve alteração
       em algum atributo historizado.
    */
    update dw_core.dim_product target
       set end_date = current_date() - 1,
           is_current = false
     from tmp_product_source source
    where target.product_id = source.product_id
      and target.is_current = true
      and sha2(
            concat_ws(
                '||',
                coalesce(target.product_name, ''),
                coalesce(to_varchar(target.category_id), ''),
                coalesce(target.category_name, ''),
                coalesce(target.category_description, ''),
                coalesce(to_varchar(target.supplier_id), ''),
                coalesce(target.supplier_name, ''),
                coalesce(target.supplier_email, ''),
                coalesce(target.supplier_phone, ''),
                coalesce(to_varchar(target.list_price), ''),
                coalesce(to_varchar(target.cost), ''),
                coalesce(to_varchar(target.created_date), '')
            ),
            256
          ) <> source.source_hash;


    /*
       Insere produtos novos e novas versões de produtos alterados.
    */
    insert into dw_core.dim_product (
        product_id,
        product_name,
        category_id,
        category_name,
        category_description,
        supplier_id,
        supplier_name,
        supplier_email,
        supplier_phone,
        list_price,
        cost,
        created_date,
        effective_date,
        end_date,
        is_current
    )
    select
        source.product_id,
        source.product_name,
        source.category_id,
        source.category_name,
        source.category_description,
        source.supplier_id,
        source.supplier_name,
        source.supplier_email,
        source.supplier_phone,
        source.list_price,
        source.cost,
        source.created_date,
        case
            when previous.product_id is null
                then coalesce(source.created_date, current_date())
            else current_date()
        end as effective_date,
        null as end_date,
        true as is_current
    from tmp_product_source source
    left join dw_core.dim_product previous
        on previous.product_id = source.product_id
       and previous.is_current = true
    where previous.product_id is null
       or sha2(
            concat_ws(
                '||',
                coalesce(previous.product_name, ''),
                coalesce(to_varchar(previous.category_id), ''),
                coalesce(previous.category_name, ''),
                coalesce(previous.category_description, ''),
                coalesce(to_varchar(previous.supplier_id), ''),
                coalesce(previous.supplier_name, ''),
                coalesce(previous.supplier_email, ''),
                coalesce(previous.supplier_phone, ''),
                coalesce(to_varchar(previous.list_price), ''),
                coalesce(to_varchar(previous.cost), ''),
                coalesce(to_varchar(previous.created_date), '')
            ),
            256
          ) <> source.source_hash;


    select count(*)
      into :v_versions_inserted
      from dw_core.dim_product
     where effective_date = current_date();

    return 'DIM_PRODUCT SCD2 concluida. Versoes com inicio hoje: '
        || :v_versions_inserted::string;
end;
$$;


-- ============================================================================
-- 7. PROCEDURE ORQUESTRADORA
-- ============================================================================

create or replace procedure dw_core.sp_load_all_dimensions()
returns string
language sql
execute as caller
as
$$
begin
    /*
       Região e canal são carregados antes das dimensões que utilizam
       seus atributos na construção da carga.
    */
    call dw_core.sp_load_dim_region();
    call dw_core.sp_load_dim_channel();
    call dw_core.sp_load_dim_customer();
    call dw_core.sp_load_dim_product();

    return 'Carga diaria das dimensoes concluida em '
        || current_timestamp()::string;
end;
$$;


-- ============================================================================
-- 8. CARGA INICIAL DAS DIMENSOES
-- ============================================================================

call dw_core.sp_load_dim_region();
call dw_core.sp_load_dim_channel();
call dw_core.sp_load_dim_customer();
call dw_core.sp_load_dim_product();


-- ============================================================================
-- 9. TASK DIARIA - STAGING -> DIMENSOES
-- ============================================================================

create or replace task dw_core.task_load_dimensions_daily
    warehouse = techmart_wh
    schedule = 'USING CRON 0 4 * * * America/Sao_Paulo'
    comment = 'Atualizacao diaria das dimensoes a partir da STAGING'
as
    call dw_core.sp_load_all_dimensions();

alter task dw_core.task_load_dimensions_daily resume;


-- ============================================================================
-- 10. VALIDACOES
-- ============================================================================

-- show tasks in schema dw_core;


-- -- DIM_DATE: período e quantidade de dias
-- select
--     min(full_date) as menor_data,
--     max(full_date) as maior_data,
--     count(*) as quantidade_dias
-- from dw_core.dim_date;

-- select
--     year,
--     count(*) as quantidade_dias
-- from dw_core.dim_date
-- group by year
-- order by year;


-- -- DIM_REGION
-- select count(*) as total_regioes
-- from dw_core.dim_region;


-- -- DIM_CHANNEL
-- select
--     channel_code,
--     channel_name,
--     channel_type,
--     is_online
-- from dw_core.dim_channel
-- order by channel_code;


-- -- Valores efetivamente encontrados na STAGING para validação do mapeamento
-- select distinct
--     channel
-- from staging.stg_orders
-- where channel is not null
-- order by channel;


-- -- DIM_CUSTOMER - histórico
-- select
--     customer_id,
--     customer_sk,
--     effective_date,
--     end_date,
--     is_current
-- from dw_core.dim_customer
-- order by customer_id, effective_date;


-- -- DIM_CUSTOMER - deve retornar zero linhas
-- select
--     customer_id,
--     count(*) as current_versions
-- from dw_core.dim_customer
-- where is_current = true
-- group by customer_id
-- having count(*) > 1;


-- -- DIM_CUSTOMER - não deve haver intervalos inválidos
-- select *
-- from dw_core.dim_customer
-- where end_date is not null
--   and effective_date > end_date;


-- -- DIM_CUSTOMER - cada cliente deve possuir exatamente uma versão corrente
-- select
--     customer_id
-- from dw_core.dim_customer
-- group by customer_id
-- having sum(iff(is_current, 1, 0)) <> 1;


-- -- DIM_PRODUCT - histórico
-- select
--     product_id,
--     product_sk,
--     product_name,
--     category_name,
--     supplier_name,
--     list_price,
--     cost,
--     effective_date,
--     end_date,
--     is_current
-- from dw_core.dim_product
-- order by product_id, effective_date;


-- -- DIM_PRODUCT - deve retornar zero linhas
-- select
--     product_id,
--     count(*) as current_versions
-- from dw_core.dim_product
-- where is_current = true
-- group by product_id
-- having count(*) > 1;


-- -- DIM_PRODUCT - não deve haver intervalos inválidos
-- select *
-- from dw_core.dim_product
-- where end_date is not null
--   and effective_date > end_date;


-- -- DIM_PRODUCT - cada produto deve possuir exatamente uma versão corrente
-- select
--     product_id
-- from dw_core.dim_product
-- group by product_id
-- having sum(iff(is_current, 1, 0)) <> 1;


-- -- FACT_SALES permanece sem carga nesta fase.
