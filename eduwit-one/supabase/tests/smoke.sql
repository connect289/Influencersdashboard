-- Rehearsal smoke test: safe on staging and on production after an apply. It calls one.tick() (which writes only to
-- schema one) and otherwise reads the catalogue; it changes no app data. Run by scripts/db/rehearse.sh and
-- scripts/db/local-test.sh, as postgres. Any failed assertion raises; on success it returns one summary row.
do $$
declare
  v_tick jsonb := one.tick();
  v_bad text;
begin
  -- one.tick() and the two jobs (spec §14, phase 1)
  if v_tick::text ~ '_error"' or v_tick ? 'checks' and v_tick -> 'checks' ? 'check_errors' then
    raise exception 'ASSERT FAILED: tick report has an error key: %', v_tick;
  end if;
  if not (one.tick() ? 'skipped' or date_trunc('minute', clock_timestamp()) > date_trunc('minute', (v_tick ->> 'at')::timestamptz)) then
    raise exception 'ASSERT FAILED: a second tick in the same minute ran again';
  end if;
  if (select count(*) from cron.job where (jobname, schedule, command) in
        (('one-tick', '* * * * *', 'select one.tick()'), ('one-nightly', '0 21 * * *', 'select one.nightly()'))) <> 2 then
    raise exception 'ASSERT FAILED: cron.job does not show both jobs';
  end if;
  if not exists (select 1 from one.heartbeats where component = 'one:tick' and last_ok_at > now() - interval '2 minutes') then
    raise exception 'ASSERT FAILED: no recent one:tick heartbeat';
  end if;

  -- Every enabled check ran and none is broken against this database's real schema. source_missing is allowed:
  -- staging lacks some sources (D-009).
  select string_agg(c.id || '=' || coalesce(s.last_status, 'never'), ', ') into v_bad
    from one.checks c left join one.check_state s on s.check_id = c.id
   where c.enabled and c.sql is not null and coalesce(s.last_status, 'never') not in ('ok', 'fail', 'source_missing');
  if v_bad is not null then raise exception 'ASSERT FAILED: checks errored or never ran: %', v_bad; end if;

  -- Least privilege (spec §13), by catalogue: the reader writes nothing and bypasses no RLS (D-030); the fixer holds
  -- nothing until a fix migration; the API roles cannot reach schema one; the service role cannot write a check's SQL.
  if (select rolbypassrls or rolsuper or rolcreaterole or rolcreatedb from pg_roles where rolname = 'eduwit_one_reader') then
    raise exception 'ASSERT FAILED: eduwit_one_reader has a role attribute it must not have';
  end if;
  select string_agg(c.oid::regclass::text, ', ') into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind in ('r', 'p', 'v', 'm', 'f') and n.nspname not in ('pg_catalog', 'information_schema', 'net', 'cron')
     and n.nspname not like 'pg_toast%'
     and (has_table_privilege('eduwit_one_reader', c.oid, 'INSERT') or has_table_privilege('eduwit_one_reader', c.oid, 'UPDATE')
          or has_table_privilege('eduwit_one_reader', c.oid, 'DELETE') or has_table_privilege('eduwit_one_reader', c.oid, 'TRUNCATE'));
  if v_bad is not null then raise exception 'ASSERT FAILED: the reader can write %', v_bad; end if;
  if to_regclass('public.student_leads') is not null and not has_table_privilege('eduwit_one_reader', 'public.student_leads', 'SELECT') then
    raise exception 'ASSERT FAILED: the reader lacks SELECT on student_leads';
  end if;
  select string_agg(c.oid::regclass::text, ', ') into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind in ('r', 'p', 'v', 'm', 'f') and n.nspname not in ('pg_catalog', 'information_schema', 'net', 'cron')
     and n.nspname not like 'pg_toast%'
     and (c.relacl::text like '%eduwit_one_fixer=%');
  if v_bad is not null then raise exception 'ASSERT FAILED: the fixer has grants before any fix migration: %', v_bad; end if;
  if has_schema_privilege('anon', 'one', 'USAGE') or has_schema_privilege('authenticated', 'one', 'USAGE') then
    raise exception 'ASSERT FAILED: an API role can use schema one';
  end if;
  if has_table_privilege('service_role', 'one.checks', 'INSERT') or has_table_privilege('service_role', 'one.checks', 'DELETE')
     or has_column_privilege('service_role', 'one.checks', 'sql', 'UPDATE') or not has_column_privilege('service_role', 'one.checks', 'enabled', 'UPDATE') then
    raise exception 'ASSERT FAILED: service role privileges on one.checks are not the operational columns only';
  end if;
  select string_agg(r, ', ') into v_bad from unnest(array['eduwit_one_reader', 'service_role', 'anon', 'authenticated']) r
   where has_function_privilege(r, 'one.secret(text)', 'EXECUTE');
  if v_bad is not null then raise exception 'ASSERT FAILED: one.secret is executable by %', v_bad; end if;

  -- Conventions: RLS on every table of schema one; every function pins search_path.
  select string_agg(c.relname, ', ') into v_bad from pg_class c
   where c.relnamespace = 'one'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if v_bad is not null then raise exception 'ASSERT FAILED: RLS off on one.%', v_bad; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'one'::regnamespace and p.prokind in ('f', 'p')
     and not coalesce(p.proconfig::text like '%search_path=%', false);
  if v_bad is not null then raise exception 'ASSERT FAILED: functions without a pinned search_path: %', v_bad; end if;
end $$;

select 'SMOKE PASSED' as result,
       (select count(*) from one.checks where enabled) as enabled_checks,
       (select jsonb_object_agg(last_status, n) from (select last_status, count(*) as n from one.check_state group by 1) s) as check_status,
       (select count(*) from one.incidents where resolved_at is null) as open_incidents,
       (select count(*) from one.events) as events;
