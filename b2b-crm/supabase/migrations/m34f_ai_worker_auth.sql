-- M34f (31 Oct 2026, audit B2B-W1): the AI worker route (/v1/ai/tick) answers only a caller holding the worker key, and the
-- database sends that key when it wakes the worker.
--   b2b.ai_wake()        NEW, internal: POST <worker_url>/v1/ai/tick with "Authorization: Bearer <worker key>", only when the
--                        worker address is public (b2b.url_allowed, m34e) and the key is saved; otherwise nothing is sent and
--                        the answer says why. ai_run_now and ai_schedule_tick call it instead of their own pg_net call.
--   ai_settings_save     also takes worker_key: an active API key with the ai_worker scope (the value set as AI_WORKER_KEY on
--                        the server), kept in Vault as b2b_ai_worker_key; the settings record only worker_key_set. The worker
--                        address must be public (m34e).
-- Until the Admin saves the worker key in AI settings the database does not wake the worker (the route would refuse it).
-- Each replaced function is its production definition with only those lines changed.
-- Re-appliable. Checked by supabase/tests/test_m34f_ai_worker_auth.sql.

create or replace function b2b.ai_wake()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  v_url text := nullif(rtrim(coalesce(cfg ->> 'worker_url', ''), '/'), '');
  v_key text;
begin
  if v_url is null then return jsonb_build_object('woken', false, 'why', 'no worker address'); end if;
  if not b2b.url_allowed(v_url || '/v1/ai/tick') then return jsonb_build_object('woken', false, 'why', 'the worker address is not allowed'); end if;
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'b2b_ai_worker_key';
  if v_key is null then return jsonb_build_object('woken', false, 'why', 'no worker key saved in AI settings'); end if;
  perform net.http_post(url := v_url || '/v1/ai/tick', body := '{}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
                        timeout_milliseconds := 5000);
  return jsonb_build_object('woken', true);
end $fn$;
revoke execute on function b2b.ai_wake() from public, anon, authenticated;
grant execute on function b2b.ai_wake() to service_role;

CREATE OR REPLACE FUNCTION b2b.ai_run_now(p_kind text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id bigint; cfg jsonb := b2b.ai_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind not in ('light_check', 'optimise', 'deep_review', 'weekly_report') then raise exception 'unknown kind of run' using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not coalesce((cfg ->> 'enabled')::boolean, false) then raise exception 'turn the optimiser on first (AI settings)' using errcode = '22023'; end if;
  v_id := b2b.ai_queue('manual', p_kind, jsonb_build_object('reason', left(trim(p_reason), 300)), coalesce(auth.uid()::text, 'admin'));
  if v_id is null then raise exception 'a run of this kind is already waiting' using errcode = '22023'; end if;
  perform b2b.ai_wake();   -- M34f: with the worker key, to a public address only
  return jsonb_build_object('id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION b2b.ai_schedule_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := b2b.ai_cfg();
  sch jsonb := coalesce(cfg -> 'schedules', '{}');
  v_now_ist timestamp := now() at time zone 'Asia/Kolkata';
  v_last timestamptz;
  v_n int;
  v_queued int := 0;
  v_spent numeric;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, false) then return '{"enabled":false}'; end if;
  if not pg_try_advisory_xact_lock(hashtext('b2b.ai_schedule_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  -- the daily budget is spent: queue nothing more today (each queued run would only be skipped), skip what still waits
  -- (as api_ai_claim does; otherwise it would wait past IST midnight and run on the next day's budget with stale
  -- context), alert once a day (IST)
  v_spent := (b2b.ai_spend() ->> 'today_usd')::numeric;
  if v_spent >= coalesce((cfg ->> 'daily_budget_usd')::numeric, 5) then
    update b2b.ai_recommendations set status = 'expired' where status = 'open' and expires_at < now();
    update b2b.ai_runs set status = 'skipped', error = format('daily budget of $%s reached ($%s spent)', cfg ->> 'daily_budget_usd', v_spent), finished_at = now()
     where status = 'queued';
    get diagnostics v_n = row_count;
    if not exists (select 1 from b2b.events where type = 'alert.ai_budget'
                    and occurred_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') then
      perform b2b.log_event('alert.ai_budget', null, null, null, jsonb_build_object('spent_usd', v_spent, 'budget_usd', cfg ->> 'daily_budget_usd'));
    end if;
    return jsonb_build_object('budget_reached', true, 'spent_usd', v_spent, 'skipped', v_n);
  end if;
  -- light check: only when new alerts arrived (no call at all on a quiet quarter hour)
  if coalesce((sch ->> 'light')::boolean, true) then
    select max(created_at) into v_last from b2b.ai_runs where kind = 'light_check';
    if v_last is null or v_last < now() - interval '15 minutes' then
      select count(*) into v_n from b2b.events where (type like 'alert.%' or type = 'routing.error') and type not in ('alert.ai_budget', 'alert.ai_run_failed')
                                               and occurred_at > coalesce(v_last, now() - interval '15 minutes');
      if v_n > 0 and b2b.ai_queue('light', 'light_check', jsonb_build_object('new_alerts', v_n)) is not null then v_queued := v_queued + 1; end if;
    end if;
  end if;
  -- hourly optimisation: only when decisions or outcomes changed since the last one
  if coalesce((sch ->> 'hourly')::boolean, true) then
    select max(created_at) into v_last from b2b.ai_runs where kind = 'optimise' and status <> 'skipped';
    if (v_last is null or v_last < now() - interval '55 minutes')
       and (exists (select 1 from b2b.engine_decisions where created_at > coalesce(v_last, '-infinity') and not is_test and destination_type = 'partner')
            or exists (select 1 from public.enrollments where updated_at > coalesce(v_last, '-infinity') and source_product = 'b2b')) then
      if b2b.ai_queue('hourly', 'optimise', '{}') is not null then v_queued := v_queued + 1; end if;
    end if;
  end if;
  -- nightly deep review after 01:00 IST, weekly report Monday after 09:00 IST: once per IST day / ISO week, counting only
  -- scheduled runs, so a manual run does not move the schedule (while one of the same kind waits, ai_queue returns null
  -- and the next tick retries)
  if coalesce((sch ->> 'nightly')::boolean, true) and extract(hour from v_now_ist) >= 1
     and not exists (select 1 from b2b.ai_runs where kind = 'deep_review' and trigger = 'nightly'
                       and (created_at at time zone 'Asia/Kolkata')::date = v_now_ist::date) then
    if b2b.ai_queue('nightly', 'deep_review', '{}') is not null then v_queued := v_queued + 1; end if;
  end if;
  if coalesce((sch ->> 'weekly')::boolean, true) and extract(isodow from v_now_ist) = 1 and extract(hour from v_now_ist) >= 9
     and not exists (select 1 from b2b.ai_runs where kind = 'weekly_report' and trigger = 'weekly'
                       and date_trunc('week', created_at at time zone 'Asia/Kolkata') = date_trunc('week', v_now_ist)) then
    if b2b.ai_queue('weekly', 'weekly_report', '{}') is not null then v_queued := v_queued + 1; end if;
  end if;
  -- events: a partner auto-paused or its status changed, an NCPL alert, a model fallback or promotion, a commission rate change, a partner going live
  select count(*) into v_n from b2b.events e
   where b2b.ai_is_trigger_event(e.type, e.payload)
     and e.occurred_at > coalesce((select max(created_at) from b2b.ai_runs where trigger = 'event'), now() - interval '5 minutes');
  if v_n > 0 and not exists (select 1 from b2b.ai_runs where trigger = 'event' and created_at > now() - interval '1 hour') then
    if b2b.ai_queue('event', 'optimise', jsonb_build_object('events', v_n)) is not null then v_queued := v_queued + 1; end if;
  end if;
  -- recommendations past their expiry
  update b2b.ai_recommendations set status = 'expired' where status = 'open' and expires_at < now();
  -- wake the worker when something waits
  if exists (select 1 from b2b.ai_runs where status = 'queued') then
    perform b2b.ai_wake();   -- M34f: with the worker key, to a public address only
  end if;
  return jsonb_build_object('queued', v_queued);
end $function$;

CREATE OR REPLACE FUNCTION b2b.ai_settings_save(p jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := b2b.ai_cfg(); v_model text; v_secret uuid;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'enabled' and jsonb_typeof(p -> 'enabled') <> 'boolean' then raise exception 'the optimiser is on or off' using errcode = '22023'; end if;
  if p ? 'mode' and p ->> 'mode' not in ('advisory', 'autopilot') then raise exception 'advisory or autopilot' using errcode = '22023'; end if;
  -- only switching into Autopilot is checked, so other settings can still be saved while in Autopilot
  if p ->> 'mode' = 'autopilot' and coalesce(v ->> 'mode', 'advisory') <> 'autopilot'
     and not coalesce((b2b.ai_autopilot_gate() ->> 'open')::boolean, false) then
    raise exception 'Autopilot unlocks once AI-steered leads beat the holdout over 4 weeks of matured leads (see AI vs holdout)' using errcode = '22023';
  end if;
  if p ? 'daily_budget_usd' and not ((p ->> 'daily_budget_usd')::numeric between 0 and 200) then raise exception 'the daily budget is $0 to $200' using errcode = '22023'; end if;
  if p ? 'worker_url' and coalesce(p ->> 'worker_url', '') <> '' and p ->> 'worker_url' !~ '^https://[^\s/]+(/[^\s]*)?$' then
    raise exception 'the worker address starts with https://' using errcode = '22023';
  end if;
  -- M34f: the database calls the worker address, so it must be on the public internet (m34e)
  if p ? 'worker_url' and coalesce(p ->> 'worker_url', '') <> '' and not b2b.url_allowed(rtrim(p ->> 'worker_url', '/') || '/v1/ai/tick') then
    raise exception 'the worker address must be an https address on the public internet, not a private, loopback, link-local or metadata address' using errcode = '22023';
  end if;
  -- M34f: the worker key the database sends to /v1/ai/tick: an active API key with the ai_worker scope, kept in Vault
  if coalesce(p ->> 'worker_key', '') <> '' then
    if not exists (select 1 from b2b.api_keys k where k.key_hash = encode(extensions.digest(p ->> 'worker_key', 'sha256'), 'hex')
                      and k.revoked_at is null and (k.expires_at is null or k.expires_at > now()) and 'ai_worker' = any (k.scopes)) then
      raise exception 'the worker key must be an active API key with the AI optimiser worker scope (the server''s AI_WORKER_KEY)' using errcode = '22023';
    end if;
    select s.id into v_secret from vault.secrets s where s.name = 'b2b_ai_worker_key';
    if v_secret is null then
      perform vault.create_secret(p ->> 'worker_key', 'b2b_ai_worker_key', 'B2B CRM: the AI worker key the database sends to /v1/ai/tick (m34f)');
    else
      perform vault.update_secret(v_secret, p ->> 'worker_key');
    end if;
    v := v || '{"worker_key_set": true}'::jsonb;
  end if;
  if p ? 'models' and (jsonb_typeof(p -> 'models') <> 'object' or exists (select 1 from jsonb_each_text(p -> 'models') m(k, x)
                                                                          where k not in ('regular', 'deep', 'quick') or x !~ '^claude-[a-z0-9.-]{3,60}$')) then
    raise exception 'models are claude-… names for regular, deep and quick runs' using errcode = '22023';
  end if;
  if p ? 'schedules' and jsonb_typeof(p -> 'schedules') <> 'object' then raise exception 'schedules are on or off' using errcode = '22023'; end if;
  if p ? 'prices_per_mtok' and (jsonb_typeof(p -> 'prices_per_mtok') <> 'object'
       or exists (select 1 from jsonb_each(p -> 'prices_per_mtok') m(k, x)
                   where k !~ '^claude-[a-z0-9.-]{3,60}$'
                      or case when jsonb_typeof(x) <> 'object' or not (x ? 'in' and x ? 'out') then true
                              else exists (select 1 from jsonb_each(x) f(fk, fx)
                                            where fk not in ('in', 'out', 'cache_read', 'cache_write')
                                               or case when jsonb_typeof(fx) = 'number' then not ((fx #>> '{}')::numeric between 0 and 1000) else true end) end)) then
    raise exception 'prices are dollars per million tokens (in, out, cache_read, cache_write) for claude-… models' using errcode = '22023';
  end if;
  if p ? 'autopilot' then
    if not ((p -> 'autopilot' ->> 'min_gain_pct')::numeric between 1 and 50) then raise exception 'Autopilot needs a simulated gain of 1 to 50%%' using errcode = '22023'; end if;
    if not ((p -> 'autopilot' ->> 'max_per_day')::int between 1 and 10) then raise exception 'Autopilot applies 1 to 10 changes a day' using errcode = '22023'; end if;
  end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('enabled', (p ->> 'enabled')::boolean, 'mode', p ->> 'mode',
                                                 'daily_budget_usd', round((p ->> 'daily_budget_usd')::numeric, 2),
                                                 'worker_url', case when p ? 'worker_url' then coalesce(nullif(rtrim(p ->> 'worker_url', '/'), ''), '') end))
       || case when p ? 'models' then jsonb_build_object('models', coalesce(v -> 'models', '{}') || (p -> 'models')) else '{}' end
       || case when p ? 'schedules' then jsonb_build_object('schedules', coalesce(v -> 'schedules', '{}')
                                                            || (select coalesce(jsonb_object_agg(k, x::boolean), '{}') from jsonb_each_text(p -> 'schedules') s(k, x)
                                                                 where k in ('light', 'hourly', 'nightly', 'weekly') and x in ('true', 'false'))) else '{}' end
       || case when p ? 'autopilot' then jsonb_build_object('autopilot', coalesce(v -> 'autopilot', '{}')
                                                            || jsonb_build_object('min_gain_pct', round((p -> 'autopilot' ->> 'min_gain_pct')::numeric, 1),
                                                                                  'max_per_day', (p -> 'autopilot' ->> 'max_per_day')::int)) else '{}' end
       || case when p ? 'prices_per_mtok' then jsonb_build_object('prices_per_mtok', coalesce(v -> 'prices_per_mtok', '{}') || (p -> 'prices_per_mtok')) else '{}' end;
  -- every model in use is priced, so the cost log and the daily budget never guess
  select m.x into v_model from jsonb_each_text(coalesce(v -> 'models', '{}')) m(k, x)
   where jsonb_typeof(v -> 'prices_per_mtok' -> m.x) is distinct from 'object' order by m.k limit 1;
  if v_model is not null then raise exception 'add a price for % first', v_model using errcode = '22023'; end if;
  return b2b.set_setting('ai', v, p_reason);
end $function$;

-- the replaced functions keep their grants (create or replace); restated
revoke execute on function b2b.ai_run_now(text, text), b2b.ai_settings_save(jsonb, text) from public, anon;
grant execute on function b2b.ai_run_now(text, text), b2b.ai_settings_save(jsonb, text) to authenticated, service_role;
revoke execute on function b2b.ai_schedule_tick() from public, anon, authenticated;
grant execute on function b2b.ai_schedule_tick() to service_role;

-- rollback: re-run the previous definitions, which are production's as of 30 Oct 2026 (these without their "M34f" lines):
--   ai_run_now and ai_schedule_tick: m26b_ai_worker_inbox.sql; ai_settings_save: m30a_autopilot_ask.sql. ai_wake and the
--   Vault secret b2b_ai_worker_key can stay (unused).
