-- w5_revoke_api_grants (proposed 30 Oct 2026, Witty audit; not applied)
--
-- What: removes the privileges that Supabase's default privileges gave anon, authenticated and PUBLIC on the
-- public.w2_* tables, views and functions. service_role keeps everything. Eduwit One's reader and fixer roles keep
-- w2_health_alerts() and w2_health_digest(integer) and the two helpers those call. public.w2_crm_owned(text) keeps its
-- authenticated grant (the B2B CRM's database tests call it).
-- Why: least privilege next to RLS. Witty's callers are the owner (n8n and pg_cron run as postgres) and postgres-owned
-- SECURITY DEFINER functions of the other apps; no client role needs these privileges.
-- Re-run after any new w2 migration: the default privileges grant new objects to anon and authenticated again.
-- Idempotent: the loops act on the w2 objects present when the file runs.

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as f, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'w2\_%' and p.prokind = 'f'
  loop
    execute format('revoke execute on function %s from public, anon', r.f);
    if r.proname <> 'w2_crm_owned' then
      execute format('revoke execute on function %s from authenticated', r.f);
    end if;
    execute format('grant execute on function %s to service_role', r.f);
  end loop;

  for r in
    select c.oid::regclass as t
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname like 'w2\_%' and c.relkind in ('r', 'p', 'v', 'm', 'f')
  loop
    execute format('revoke all on table %s from anon, authenticated', r.t);
  end loop;

  if exists (select 1 from pg_roles where rolname = 'eduwit_one_reader') then
    grant execute on function public.w2_health_alerts(), public.w2_health_digest(integer),
                              public.w2_stale_inbox(integer), public.w2_is_test(text) to eduwit_one_reader;
  end if;
  if exists (select 1 from pg_roles where rolname = 'eduwit_one_fixer') then
    grant execute on function public.w2_health_alerts(), public.w2_health_digest(integer),
                              public.w2_stale_inbox(integer), public.w2_is_test(text) to eduwit_one_fixer;
  end if;
end $$;

-- rollback (restores the grants as they were on 30 Oct 2026; w2_crm_owned and w2_fee_review are untouched by both):
-- do $$
-- declare
--   r record;
-- begin
--   for r in
--     select p.oid::regprocedure as f
--       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname like 'w2\_%' and p.prokind = 'f' and p.proname <> 'w2_crm_owned'
--   loop
--     execute format('grant execute on function %s to public, anon, authenticated', r.f);
--   end loop;
--   for r in
--     select c.oid::regclass as t
--       from pg_class c join pg_namespace n on n.oid = c.relnamespace
--      where n.nspname = 'public' and c.relname like 'w2\_%' and c.relkind in ('r', 'p', 'v', 'm', 'f')
--        and c.relname <> 'w2_fee_review'
--   loop
--     execute format('grant all on table %s to anon, authenticated', r.t);
--   end loop;
--   if exists (select 1 from pg_roles where rolname = 'eduwit_one_reader') then
--     revoke execute on function public.w2_stale_inbox(integer), public.w2_is_test(text) from eduwit_one_reader;
--   end if;
--   if exists (select 1 from pg_roles where rolname = 'eduwit_one_fixer') then
--     revoke execute on function public.w2_health_alerts(), public.w2_health_digest(integer),
--                                public.w2_stale_inbox(integer), public.w2_is_test(text) from eduwit_one_fixer;
--   end if;
-- end $$;
