-- Rehearsal smoke test: safe on staging and on production after an apply. It runs the minute job once, as pg_cron
-- does (one.tick_job(), which writes only to schema one and commits after each step, so the first event backfill never
-- holds the app tables for its whole length; m9 of the second review), and otherwise reads the catalogue; it changes
-- no app data. Run by scripts/db/rehearse.sh, scripts/db/apply.sh and scripts/db/local-test.sh, as postgres, never
-- inside a transaction block. Any failed assertion raises; on success it returns one summary row.
set lock_timeout = '2s';
set statement_timeout = '5min';
call one.tick_job();
reset statement_timeout;

do $$
declare
  v_run one.runs;
  v_bad text;
begin
  -- The minute job and the two cron jobs (spec §14, phase 1): the latest tick finished, and its report has no
  -- "_error" key. (If pg_cron took this minute first, its run is the one read.)
  select * into v_run from one.runs where kind = 'tick' and finished_at is not null and started_at > now() - interval '3 minutes'
   order by id desc limit 1;
  if v_run.id is null then
    raise exception 'ASSERT FAILED: no tick finished in the last 3 minutes';
  end if;
  if v_run.report::text ~ '_error"' then
    raise exception 'ASSERT FAILED: tick report has an error key: %', v_run.report;
  end if;
  -- one.tick() buckets by now(), this block's start, so the guard can be tested only while the block started in the
  -- minute of the run above. A real tick takes tens of seconds (38 s on staging, 24 Oct), so this block often starts in
  -- the next minute; a second tick there is a real one, and the guard is left to the local tests (10_core.sql).
  if date_trunc('minute', now()) = v_run.bucket and not (one.tick() ? 'skipped') then
    raise exception 'ASSERT FAILED: a second tick in the same minute ran again';
  end if;
  if (select count(*) from cron.job where (jobname, schedule, command) in
        (('one-tick', '* * * * *', 'call one.tick_job()'), ('one-nightly', '0 21 * * *', 'select one.nightly()'))) <> 2 then
    raise exception 'ASSERT FAILED: cron.job does not show both jobs';
  end if;
  if not exists (select 1 from one.heartbeats where component = 'one:tick' and last_ok_at > now() - interval '2 minutes') then
    raise exception 'ASSERT FAILED: no recent one:tick heartbeat';
  end if;

  -- Every enabled check ran and none is broken against this database's real schema. source_missing is allowed:
  -- staging lacks some sources (D-009).
  select string_agg(c.id || '=' || coalesce(s.last_status, 'never'), ', ') into v_bad
    from one.checks c left join one.check_state s on s.check_id = c.id
   where c.enabled and c.sql is not null and coalesce(s.last_status, 'never') not in ('ok', 'fail', 'source_missing', 'skipped');
  if v_bad is not null then raise exception 'ASSERT FAILED: checks errored or never ran: %', v_bad; end if;

  -- Least privilege (spec §13), by catalogue: the reader writes nothing and bypasses no RLS (D-030); the fixer holds no
  -- table privilege, executes only the catalogue's app functions and owns only its one.fixer_* functions (0019, D-079);
  -- the API roles cannot reach schema one; the service role cannot write a check's SQL.
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
  if v_bad is not null then raise exception 'ASSERT FAILED: the fixer holds a table privilege: %', v_bad; end if;
  select string_agg(a.attrelid::regclass::text || '.' || a.attname, ', ') into v_bad
    from pg_attribute a join pg_class c on c.oid = a.attrelid
   where a.attacl::text ~ '"?eduwit_one_(fixer|reader)"?=' and c.relnamespace <> 'one'::regnamespace;
  if v_bad is not null then raise exception 'ASSERT FAILED: an Eduwit One role holds a column privilege: %', v_bad; end if;
  -- The fixer is a member of no role, and only the migrating user is a member of it (0019 hands it its functions).
  select string_agg(m.roleid::regrole::text || '>' || m.member::regrole::text, ', ') into v_bad
    from pg_auth_members m
   where m.member = 'eduwit_one_fixer'::regrole
      or (m.roleid = 'eduwit_one_fixer'::regrole and m.member <> (select oid from pg_roles where rolname = current_user));
  if v_bad is not null then raise exception 'ASSERT FAILED: a membership of or in the fixer: %', v_bad; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname <> 'one' and p.proacl::text like '%eduwit_one_fixer=%'
     and p.oid::regprocedure::text not in ('b2b.b2c_sync_tick(integer)', 'b2b.outbox_kick()', 'b2b.outbox_retry(bigint)', 'b2c.inbox_retry(integer)',
                                           'b2c.outbox_unstick()', 'b2c.job_call(text)', 'b2c.programme_cache_refresh(boolean)',
                                           'web_outbox_retry(bigint,uuid)', 'web_job_call(text,integer)', 'web_catalog_poll()',
                                           'public.web_outbox_retry(bigint,uuid)', 'public.web_job_call(text,integer)', 'public.web_catalog_poll()');
  if v_bad is not null then raise exception 'ASSERT FAILED: the fixer may execute an app function outside the catalogue: %', v_bad; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p where p.proowner = 'eduwit_one_fixer'::regrole and (p.pronamespace <> 'one'::regnamespace or p.proname !~ '^fixer_');
  if v_bad is not null then raise exception 'ASSERT FAILED: the fixer owns a function that is not one of its one.fixer_*: %', v_bad; end if;
  if has_schema_privilege('eduwit_one_fixer', 'one', 'CREATE') or has_schema_privilege('eduwit_one_fixer', 'one', 'USAGE') then
    raise exception 'ASSERT FAILED: the fixer can use or create in schema one';
  end if;
  -- The API roles reach schema one only through the functions one.api_grants lists, each SECURITY DEFINER; they hold
  -- no privilege on any table or sequence of it, and anon cannot even use the schema (D-055).
  if has_schema_privilege('anon', 'one', 'USAGE') then
    raise exception 'ASSERT FAILED: anon can use schema one';
  end if;
  select string_agg(r || ' on ' || c.oid::regclass::text, ', ') into v_bad
    from pg_class c, unnest(array['service_role', 'authenticated', 'anon']) r
   where c.relnamespace = 'one'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'S')
     and (has_table_privilege(r, c.oid, 'SELECT') or has_table_privilege(r, c.oid, 'INSERT') or has_table_privilege(r, c.oid, 'UPDATE')
          or has_table_privilege(r, c.oid, 'DELETE') or has_table_privilege(r, c.oid, 'TRUNCATE'));
  if v_bad is not null then raise exception 'ASSERT FAILED: an API role holds a table privilege in schema one: %', v_bad; end if;
  select string_agg(r || ' → ' || p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p, unnest(array['service_role', 'authenticated', 'anon']) r
   where p.pronamespace = 'one'::regnamespace and has_function_privilege(r, p.oid, 'EXECUTE')
     and (r = 'anon' or not p.prosecdef
          or not exists (select 1 from one.api_grants a where to_regprocedure(a.fn) = p.oid and a.role = r));
  if v_bad is not null then raise exception 'ASSERT FAILED: an API role can execute a one.* function outside one.api_grants: %', v_bad; end if;
  -- Every function a signed-in person can call starts with the gate, except the four of the sign-in flow (D-058).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'one'::regnamespace and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosrc !~ 'one\.ui_require\(' and p.proname not in ('me', 'auth_verify_code', 'auth_device_check', 'auth_sign_out');
  if v_bad is not null then raise exception 'ASSERT FAILED: signed-in functions without the gate: %', v_bad; end if;
  select string_agg(r, ', ') into v_bad from unnest(array['eduwit_one_reader', 'service_role', 'anon', 'authenticated']) r
   where has_function_privilege(r, 'one.secret(text)', 'EXECUTE');
  if v_bad is not null then raise exception 'ASSERT FAILED: one.secret is executable by %', v_bad; end if;

  -- WITTY-01 runs with search_path public, safe only while no API or Eduwit One role can create objects there (D-042).
  select string_agg(r, ', ') into v_bad from one.public_schema_writers() r;
  if v_bad is not null then raise exception 'ASSERT FAILED: these roles can create in schema public: %', v_bad; end if;
  if not exists (select 1 from cron.job where jobname = 'one-tick' and command = 'call one.tick_job()') then
    raise exception 'ASSERT FAILED: one-tick does not run the committing procedure';
  end if;

  -- Conventions: RLS on every table of schema one; every function pins search_path.
  select string_agg(c.relname, ', ') into v_bad from pg_class c
   where c.relnamespace = 'one'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if v_bad is not null then raise exception 'ASSERT FAILED: RLS off on one.%', v_bad; end if;
  -- one.tick_job() and one.fixes_job() are the exceptions: a procedure that commits cannot carry SET clauses; each sets
  -- search_path itself (D-044, 0019).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'one'::regnamespace and p.prokind in ('f', 'p') and not (p.prokind = 'p' and p.proname in ('tick_job', 'fixes_job'))
     and not coalesce(p.proconfig::text like '%search_path=%', false);
  if v_bad is not null then raise exception 'ASSERT FAILED: functions without a pinned search_path: %', v_bad; end if;
end $$;

select 'SMOKE PASSED' as result,
       (select count(*) from one.checks where enabled) as enabled_checks,
       (select jsonb_object_agg(last_status, n) from (select last_status, count(*) as n from one.check_state group by 1) s) as check_status,
       (select count(*) from one.incidents where resolved_at is null) as open_incidents,
       (select count(*) from one.events) as events;
