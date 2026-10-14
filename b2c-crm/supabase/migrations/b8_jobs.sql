-- B2C CRM b8: timers (pg_cron). Staging first.
--   b2c-minute       allocation retries, SLA breaches, reminders and escalations, envelope retries, stuck outbox items (SQL only)
--   b2c-sync-urgent  every minute: the app sends urgent outbox items (consent, opt-out, erasure, routing, intake) and messages
--   b2c-sync-batch   every 15 minutes: the app sends the batch of B2C activity to the B2B CRM (decision K2)
--   b2c-reconcile    every 5 minutes: the app catches up on hand-offs and record changes from the B2B feeds
-- The app's address and key come from settings 'app' and Vault secret 'b2c_internal_key'. Until both exist the HTTP jobs
-- do nothing, so this is safe to apply before the app is deployed.

insert into b2c.settings (key, value) values ('app', '{"base_url": null}') on conflict (key) do nothing;

create or replace function b2c.job_call(p_path text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_base text := b2c.setting('app') ->> 'base_url'; v_key text;
begin
  if v_base is null then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'b2c_internal_key';
  if v_key is null then return null; end if;
  return net.http_post(url := rtrim(v_base, '/') || p_path, body := '{}'::jsonb,
                       headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key), timeout_milliseconds := 55000);
end $f$;
revoke execute on function b2c.job_call(text) from public, authenticated;

create or replace function b2c.minute_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('inbox', b2c.inbox_retry(50)); exception when others then v := v || jsonb_build_object('inbox_error', sqlerrm); end;
  begin v := v || jsonb_build_object('allocation', b2c.allocation_tick()); exception when others then v := v || jsonb_build_object('allocation_error', sqlerrm); end;
  begin v := v || jsonb_build_object('sla', b2c.sla_tick()); exception when others then v := v || jsonb_build_object('sla_error', sqlerrm); end;
  begin v := v || jsonb_build_object('reminders', b2c.reminder_tick()); exception when others then v := v || jsonb_build_object('reminders_error', sqlerrm); end;
  begin v := v || jsonb_build_object('unstuck', b2c.outbox_unstick()); exception when others then v := v || jsonb_build_object('unstick_error', sqlerrm); end;
  return v;
end $f$;
revoke execute on function b2c.minute_tick() from public, authenticated;

do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-minute') then
    perform cron.schedule('b2c-minute', '* * * * *', 'select b2c.minute_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-sync-urgent') then
    perform cron.schedule('b2c-sync-urgent', '* * * * *', $$select b2c.job_call('/api/internal/sync?mode=urgent')$$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-sync-batch') then
    perform cron.schedule('b2c-sync-batch', '*/15 * * * *', $$select b2c.job_call('/api/internal/sync?mode=batch')$$);
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-reconcile') then
    perform cron.schedule('b2c-reconcile', '*/5 * * * *', $$select b2c.job_call('/api/internal/reconcile')$$);
  end if;
end $d$;

-- last: nothing in b2c is executable by PUBLIC or anon; every grant to authenticated and service_role above stays
revoke execute on all functions in schema b2c from public, anon;
