-- M2 part e of 5 (see 20261006103851_m2a_extensions_and_schema.sql for the overview).

-- ---------- row-level security: the Admin reads; all writes go through functions ----------
do $rls$
declare t text;
begin
  foreach t in array array['app_users', 'sign_in_log', 'events', 'settings', 'settings_versions', 'api_keys',
                           'integration_outbox', 'live_switches'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using (b2b.is_admin())', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;
revoke select on b2b.api_keys from authenticated;   -- hashes stay server-side
grant select (id, name, scopes, key_prefix, created_at, created_by, last_used_at, revoked_at) on b2b.api_keys to authenticated;
grant usage, select on all sequences in schema b2b to service_role;

-- ---------- function privileges ----------
revoke execute on all functions in schema b2b from public, anon, authenticated;
grant execute on all functions in schema b2b to service_role;
grant execute on function b2b.is_admin()                         to authenticated;
grant execute on function b2b.me()                               to authenticated;
grant execute on function b2b.my_sessions()                      to authenticated;
grant execute on function b2b.set_setting(text, jsonb, text)     to authenticated;
grant execute on function b2b.create_api_key(text, text[])       to authenticated;
grant execute on function b2b.revoke_api_key(bigint)             to authenticated;
grant execute on function b2b.set_live_switch(text, boolean, text) to authenticated;
grant execute on function b2b.is_live(text)                      to authenticated;

-- ---------- shared table: index for lead_intake()'s phone lookup (crm_find_lead) ----------
-- Matches the expression in crm_find_lead() exactly, so the planner uses it. Index only; no behaviour change.
create index if not exists student_leads_phone_digits_idx
  on public.student_leads ((regexp_replace(coalesce(whatsapp_number, ''), '\D', '', 'g')))
  where deleted_at is null and merged_into_id is null;
