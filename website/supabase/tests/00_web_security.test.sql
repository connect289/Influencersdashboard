-- Security invariants for every website-owned object (spec 2.6, 15). Runs on the local DB and on prod-replica.
begin;
create temp table r (ok boolean, name text) on commit drop;

-- Every web_ table/view/materialised view in public has RLS (tables) and grants nothing to anon/authenticated.
insert into r
select c.relrowsecurity, 'RLS enabled on ' || c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname like 'web\_%' and c.relkind in ('r', 'p');

insert into r
select not has_table_privilege(role, c.oid, priv), format('%s has no %s on %s', role, priv, c.relname)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('anon'), ('authenticated')) roles(role)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) privs(priv)
 where n.nspname = 'public' and c.relname like 'web\_%' and c.relkind in ('r', 'p', 'v', 'm');

-- Every web_ function: SECURITY DEFINER with a pinned search_path, and not executable by public/anon/authenticated.
insert into r
select p.prosecdef and coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false),
       'definer + search_path on ' || p.oid::regprocedure
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname like 'web\_%' and p.prokind = 'f'
   and p.prorettype <> 'trigger'::regtype;

insert into r
select not has_function_privilege(role, p.oid, 'EXECUTE'), format('%s cannot execute %s', role, p.oid::regprocedure)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join (values ('anon'), ('authenticated')) roles(role)
 where n.nspname = 'public' and p.proname like 'web\_%' and p.prokind = 'f';

-- Shared lead writer stays service-role only (we must never widen it).
insert into r values (not has_function_privilege('anon', 'public.lead_intake(jsonb)', 'EXECUTE'), 'lead_intake not executable by anon');
insert into r values (has_function_privilege('service_role', 'public.lead_intake(jsonb)', 'EXECUTE'), 'lead_intake executable by service_role');

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
