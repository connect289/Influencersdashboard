-- Deployment settings set by the deploy script (web/scripts/deploy-staging.mjs) with the service role, so the timers'
-- key goes into Vault without ever being typed into an SQL editor or a chat.
--   app_deploy_set(p_base_url, p_internal_key)   service role only: settings 'app'.base_url and Vault 'b2c_internal_key'

create or replace function b2c.app_deploy_set(p_base_url text, p_internal_key text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_id uuid;
begin
  if p_base_url !~ '^https://[a-z0-9.-]+$' then raise exception 'base url must be https://host'; end if;
  if length(coalesce(p_internal_key, '')) < 32 then raise exception 'the internal key must be at least 32 characters'; end if;
  select id into v_id from vault.secrets where name = 'b2c_internal_key';
  if v_id is null then perform vault.create_secret(p_internal_key, 'b2c_internal_key', 'B2C CRM timers: x-internal-key for the app');
  else perform vault.update_secret(v_id, p_internal_key); end if;
  insert into b2c.settings (key, value) values ('app', jsonb_build_object('base_url', p_base_url))
  on conflict (key) do update set value = b2c.settings.value || jsonb_build_object('base_url', p_base_url), updated_at = now(), version = b2c.settings.version + 1;
  return jsonb_build_object('base_url', p_base_url, 'key_saved', true);
end $f$;

revoke execute on function b2c.app_deploy_set(text, text) from public, anon, authenticated;
grant execute on function b2c.app_deploy_set(text, text) to service_role;
