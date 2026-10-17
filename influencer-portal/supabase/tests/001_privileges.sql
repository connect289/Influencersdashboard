-- Client privileges on schema inf equal exactly the declared list in inf.client_grants; anon reaches nothing else.
begin;
\ir _helpers.psql
select plan(8);

select is(
  (select count(*)::int from pg_class c where c.relnamespace = 'inf'::regnamespace and c.relkind in ('r', 'v', 'm')
      and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT')
           or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))),
  0, 'anon has no privilege on any inf table');

select is(
  (select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text), '{}') from pg_proc p
    where p.pronamespace = 'inf'::regnamespace and has_function_privilege('anon', p.oid, 'execute')),
  array['inf.health()', 'inf.media_kit_public(text)'],
  'anon can execute only health() and media_kit_public() (rate_check is server-only)');

select is(
  (select count(*)::int from pg_class c cross join unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) pr
    where c.relnamespace = 'inf'::regnamespace and c.relkind = 'r' and has_table_privilege('authenticated', c.oid, pr)),
  0, 'authenticated cannot write any inf table directly (all writes go through functions)');

select set_eq(
  $$ select c.oid::regclass::text from pg_class c where c.relnamespace = 'inf'::regnamespace and c.relkind = 'r'
       and has_table_privilege('authenticated', c.oid, 'SELECT') $$,
  $$ select to_regclass(object_name)::text from inf.client_grants where object_type = 'table' and grantee = 'authenticated' and privilege = 'select' $$,
  'authenticated SELECT grants equal the declared list');

select set_eq(
  $$ select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'inf'::regnamespace
       and has_function_privilege('authenticated', p.oid, 'execute') $$,
  $$ select to_regprocedure(object_name)::text from inf.client_grants where object_type = 'function' and grantee = 'authenticated' $$,
  'authenticated EXECUTE grants equal the declared list');

select is(
  (select count(*)::int from pg_class c where c.relnamespace = 'inf'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every inf table');

select ok(not has_function_privilege('authenticated', 'inf.mfa_issue(uuid,uuid)', 'execute'), 'clients cannot issue 2FA codes');
select ok(not has_function_privilege('authenticated', 'inf.notify(uuid,text,text,text,text,jsonb,boolean,text,text[])', 'execute'),
          'clients cannot create notifications for others');

select * from finish();
rollback;
