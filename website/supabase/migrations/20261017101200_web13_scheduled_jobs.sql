-- =====================================================================================================================
-- web13 · The website's scheduled jobs run from Supabase pg_cron, not Vercel Cron (owner decision, D-082). Vercel Hobby
-- only allows daily cron jobs, so the site stays on Hobby and every website job lives in one place:
--   web_catalog_poll   * * * * *     select public.web_catalog_poll()                         (web4; inside the database)
--   web_outbox_worker  * * * * *     POST {internal_base_url}/api/internal/outbox             (this file)
--   web_seo_daily      30 21 * * *   POST {internal_base_url}/api/internal/seo-daily (03:00 IST) (this file)
-- Same pattern as the B2C CRM's b2c.job_call: the site's address comes from web_settings 'internal_base_url' and the key
-- from Vault secret 'web_internal_key' (= the app's WEB_INTERNAL_KEY). Until BOTH exist the HTTP jobs do nothing, so this
-- is safe to apply before the site is deployed. Jobs are scheduled only where pg_cron and pg_net exist (production);
-- the local stack has neither. Rollback: scripts/db/rollback-web.sql removes every web_* job; delete the Vault secret by
-- hand. Shared-project impact: two more pg_cron entries (A-CRON-1).
-- =====================================================================================================================

insert into public.web_settings (key, value, description) values
  ('internal_base_url', 'null'::jsonb,
   'Address the database jobs call (web_outbox_worker, web_seo_daily), e.g. "https://eduwit.in". Null = jobs do nothing (D-082).')
on conflict (key) do nothing;

-- Calls one of the website's internal endpoints from the database (pg_net, asynchronous). Returns the pg_net request id,
-- or null when the address or the key is not configured yet (nothing is sent).
create or replace function public.web_job_call(p_path text, p_timeout_ms integer default 55000)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_base text; v_key text;
begin
  if p_path is null or p_path !~ '^/api/internal/[a-z0-9-]+$' then raise exception 'web_job_call: unexpected path %', p_path; end if;
  select nullif(btrim(value #>> '{}'), '') into v_base from public.web_settings where key = 'internal_base_url';
  if v_base is null or v_base !~ '^https?://[^/\s]+$' then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'web_internal_key';
  if v_key is null or v_key = '' then return null; end if;
  return net.http_post(
    url := v_base || p_path,
    body := '{}'::jsonb,
    headers := jsonb_build_object('content-type', 'application/json', 'authorization', 'Bearer ' || v_key),
    timeout_milliseconds := greatest(1000, least(coalesce(p_timeout_ms, 55000), 300000)));
end $$;
revoke all on function public.web_job_call(text, integer) from public, anon, authenticated;
grant execute on function public.web_job_call(text, integer) to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('web_outbox_worker', '* * * * *', $j$select public.web_job_call('/api/internal/outbox')$j$);
    perform cron.schedule('web_seo_daily', '30 21 * * *', $j$select public.web_job_call('/api/internal/seo-daily', 300000)$j$);
  end if;
end $$;
