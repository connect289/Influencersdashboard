-- =====================================================================================================================
-- Rollback of the website's own database objects (go-live rollback, docs/RUNBOOK.md §Rollback). Removes every object in
-- schema public whose name starts with web_ (tables and their data, views, materialized views, functions, sequences,
-- types) and the website's pg_cron jobs (web_*). Touches nothing else.
--
-- Run ONLY after rolling back any approved shared proposals that build on website objects (s03 renames web_tax_* tables
-- and adds views on them: run s03_shared_taxonomy.rollback.sql first). The script refuses to run if any non-website
-- object depends on a website object, so CASCADE below can never reach a shared object.
--
-- Data written into SHARED tables through the approved paths (leads via lead_intake, touchpoints) is business data and
-- is NOT removed. Website-only data (students, sessions, applications, chats, consents) is dropped with the tables:
-- take a backup first (RUNBOOK) — the consent ledger in particular must be kept for DPDP purposes.
-- Usage: psql "<url>" -v ON_ERROR_STOP=1 -f scripts/db/rollback-web.sql
-- =====================================================================================================================
\set ON_ERROR_STOP on
begin;
set local client_min_messages = warning;  -- the cascades below stay inside web_* (step 1); no per-object notices

-- 1. Safety: nothing outside the website may depend on a website object.
do $$
declare v_bad text;
begin
  with web_obj as (
    select 'pg_class'::regclass as classid, c.oid as objid from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relname like 'web\_%'
    union all
    select 'pg_proc'::regclass, p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'web\_%'
  ), dependents as (
    select distinct
      case d.classid
        -- indexes, sequences and toast tables belong to their table (checked through it); report the table instead
        when 'pg_class'::regclass then (select n.nspname || '.' || coalesce(t.relname, c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                         left join pg_index i on i.indexrelid = c.oid left join pg_class t on t.oid = i.indrelid
                                         where c.oid = d.objid and c.relkind not in ('S', 't'))
        when 'pg_rewrite'::regclass then (select n.nspname || '.' || c.relname from pg_rewrite r join pg_class c on c.oid = r.ev_class join pg_namespace n on n.oid = c.relnamespace where r.oid = d.objid)
        when 'pg_proc'::regclass then (select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.oid = d.objid)
        when 'pg_trigger'::regclass then (select n.nspname || '.' || c.relname || ' trigger ' || t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where t.oid = d.objid)
        when 'pg_constraint'::regclass then (select n.nspname || '.' || co.conname from pg_constraint co join pg_namespace n on n.oid = co.connamespace where co.oid = d.objid)
      end as name
    from pg_depend d join web_obj w on w.classid = d.refclassid and w.objid = d.refobjid
    where d.deptype in ('n', 'a')
  )
  select string_agg(name, ', ') into v_bad from dependents
   where name is not null and name not like 'public.web\_%' and name not like 'pg\_toast.%';
  if v_bad is not null then
    raise exception 'rollback-web: non-website objects depend on website objects: % (roll back the shared proposals first)', v_bad;
  end if;
end $$;

-- 2. pg_cron jobs created by the website.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname like 'web\_%';
  end if;
end $$;

-- 3. Views and materialized views, then functions, then tables (CASCADE stays inside web_*, proven by step 1).
do $$
declare r record;
begin
  for r in select c.relname, c.relkind from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relname like 'web\_%' and c.relkind in ('v', 'm') loop
    execute format(case r.relkind when 'v' then 'drop view if exists public.%I cascade' else 'drop materialized view if exists public.%I cascade' end, r.relname);
  end loop;
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'web\_%' loop
    execute format('drop function if exists %s cascade', r.sig);
  end loop;
  for r in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relname like 'web\_%' and c.relkind in ('r', 'p') loop
    execute format('drop table if exists public.%I cascade', r.relname);
  end loop;
  for r in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relname like 'web\_%' and c.relkind = 'S' loop
    execute format('drop sequence if exists public.%I cascade', r.relname);
  end loop;
  for r in select t.typname from pg_type t
            where t.typnamespace = 'public'::regnamespace and t.typname like 'web\_%' and t.typtype in ('e', 'd', 'c')
              and not exists (select 1 from pg_class c where c.reltype = t.oid) loop
    execute format('drop type if exists public.%I cascade', r.typname);
  end loop;
end $$;

-- 4. Nothing left.
do $$ begin
  if exists (select 1 from pg_class where relnamespace = 'public'::regnamespace and relname like 'web\_%')
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname like 'web\_%') then
    raise exception 'rollback-web: website objects remain';
  end if;
end $$;
commit;
