-- 0001 schema one and its two roles (spec §5).
-- Applied with: psql -X -1 -v ON_ERROR_STOP=1 (scripts/db/apply.sh sets lock_timeout 5s and statement_timeout 5min).
-- Additive only: creates schema one, two NOLOGIN roles, and read grants for the reader. Nothing in the five apps is
-- altered. Both roles stay NOLOGIN here; a login password is set outside migrations when the app needs one, never
-- committed. Neither role bypasses RLS (D-030): on the app tables, which nearly all have RLS on, the reader's SELECT
-- returns only what a policy grants it, and the checks read as the owner through one.run_check() instead.

create schema if not exists one;
revoke all on schema one from public;
comment on schema one is 'Eduwit One: monitoring, tests, alerts, fixes and proposals over the five apps. See eduwit-one/docs.';

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'eduwit_one_reader') then
    create role eduwit_one_reader nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'eduwit_one_fixer') then
    create role eduwit_one_fixer nologin noinherit;
  end if;
end $$;

comment on role eduwit_one_reader is 'Eduwit One reads: SELECT on the app schemas, EXECUTE on public health RPCs, no writes outside schema one.';
comment on role eduwit_one_fixer is 'Eduwit One auto-fixes: no grants until a fix migration (0009_fixer_grants_<fix>) adds exactly what that fix needs.';

grant usage on schema one to eduwit_one_reader, service_role;

-- The reader sees every app schema that exists on this database. Staging lacks some (D-009), so each is conditional.
-- Not net: postgres cannot grant on it, and PUBLIC already holds USAGE there and every privilege on its two tables
-- (Supabase default, measured 23 Oct; D-028).
do $$
declare
  s text;
begin
  foreach s in array array['public', 'b2b', 'b2c', 'catalog', 'cron'] loop
    continue when not exists (select 1 from pg_namespace where nspname = s);
    execute format('grant usage on schema %I to eduwit_one_reader', s);
    if s in ('public', 'b2b', 'b2c', 'catalog') then
      execute format('grant select on all tables in schema %I to eduwit_one_reader', s);
      execute format('alter default privileges for role postgres in schema %I grant select on tables to eduwit_one_reader', s);
    end if;
  end loop;
end $$;

-- pg_cron's tables belong to supabase_admin; postgres holds SELECT with grant option on both. Their RLS policy shows a
-- role only its own jobs, so the reader sees none; the cron checks run as the owner.
do $$
begin
  if to_regclass('cron.job') is not null then
    grant select on cron.job, cron.job_run_details to eduwit_one_reader;
  end if;
end $$;

-- Health RPCs the app may call as the reader (D-020). Admin-session RPCs (b2b.alert_feed, b2b.command_center,
-- b2c.system_health) are not granted: they need a signed-in admin and are only rendered under the owner's session.
do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where (n.nspname, p.proname) in (('public', 'w2_health_alerts'), ('public', 'w2_health_digest'),
                                      ('public', 'web_health'), ('b2b', 'health_check'))
  loop
    execute format('grant execute on function %s to eduwit_one_reader', f);
  end loop;
end $$;
