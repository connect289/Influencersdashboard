-- 0008 the functions the app calls (spec §5 app layer, phase 2). The app's service role reaches the database only
-- through these, each SECURITY DEFINER and listed in one.api_grants; it holds no privilege on any table (D-055). It
-- reads app data only through functions that return no contact fields (D-030). One call reads what a tick needs, one
-- call writes what it found.

-- Everything the app's probe runner needs for one tick: the runtime settings it reads, the app-run checks with their
-- last run, and the heartbeat rows. Setup items are reduced to their status, without the evidence text.
create or replace function one.app_tick_state() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'now', now(),
    'settings', (select coalesce(jsonb_object_agg(s.key, s.value), '{}') from one.settings s
                  where s.key in ('app', 'hosts', 'health_paths', 'vendors', 'vercel', 'chatwoot', 'n8n', 'whatsapp', 'witty', 'thresholds', 'checks', 'alerts',
                                  'access')),
    'setup', (select coalesce(jsonb_object_agg(i.key, jsonb_build_object('status', i.value ->> 'status', 'validated', coalesce((i.value ->> 'validated')::boolean, false))), '{}')
                from one.settings s, jsonb_each(coalesce(s.value -> 'items', '{}')) i where s.key = 'setup'),
    'checks', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'enabled', c.enabled, 'disabled_reason', c.disabled_reason,
                                                            'cadence_s', c.cadence_s, 'last_ran_at', st.last_ran_at) order by c.id), '[]')
                 from one.checks c left join one.check_state st on st.check_id = c.id where c.kind in ('http', 'test')),
    'heartbeats', (select coalesce(jsonb_agg(jsonb_build_object('component', h.component, 'last_ok_at', h.last_ok_at,
                                                                'last_error_at', h.last_error_at, 'expected_interval_s', h.expected_interval_s)), '[]')
                     from one.heartbeats h))
$$;

-- What one tick found: heartbeats and app-run check results, each applied on its own so one bad item cannot drop the
-- rest. Values are bounded and pass through one.redact(), so a probe cannot store contact data by mistake. One audit
-- row per call (spec §13: every write through the app is audited).
create or replace function one.app_report(p_report jsonb, p_actor text default 'app:tick', p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(one.setting('events') -> 'pii_columns')), '{}');
  v_item jsonb;
  v_out jsonb := jsonb_build_object('heartbeats', '{}'::jsonb, 'results', '{}'::jsonb);
  v_value jsonb;
begin
  for v_item in select jsonb_array_elements(coalesce(p_report -> 'heartbeats', '[]')) loop
    begin
      -- The database's own heartbeats (one:tick, one:nightly) are written only by the database: the watchdog and the
      -- HB checks must not be fed by the app (m4 of the second review).
      if coalesce(v_item ->> 'component', '') !~ '^[a-z0-9:._-]{1,80}$'
         or (v_item ->> 'component' like 'one:%' and v_item ->> 'component' <> 'one:app') then
        raise exception 'bad component' using errcode = '22023';
      end if;
      v_value := one.redact(coalesce(v_item -> 'detail', '{}'), v_pii);
      if length(v_value::text) > 8000 then v_value := jsonb_build_object('truncated', true); end if;
      perform one.heartbeat(v_item ->> 'component', coalesce((v_item ->> 'ok')::boolean, false), v_value,
                            left(v_item ->> 'error', 500), (v_item ->> 'expected_interval_s')::int);
      v_out := jsonb_set(v_out, array['heartbeats', v_item ->> 'component'], '"ok"');
    exception when others then
      v_out := jsonb_set(v_out, array['heartbeats', coalesce(v_item ->> 'component', '?')], to_jsonb(left(sqlerrm, 120)));
    end;
  end loop;
  for v_item in select jsonb_array_elements(coalesce(p_report -> 'results', '[]')) loop
    begin
      if coalesce(v_item ->> 'status', '') not in ('ok', 'fail', 'error', 'skipped') then
        raise exception 'bad status' using errcode = '22023';
      end if;
      v_value := one.redact(coalesce(v_item -> 'value', '{}'), v_pii);
      if length(v_value::text) > 8000 then v_value := jsonb_build_object('truncated', true); end if;
      v_out := jsonb_set(v_out, array['results', v_item ->> 'check_id'],
        to_jsonb(one.report_result(v_item ->> 'check_id', v_item ->> 'status', v_value, left(v_item ->> 'error', 500), (v_item ->> 'duration_ms')::int)));
    exception when others then
      v_out := jsonb_set(v_out, array['results', coalesce(v_item ->> 'check_id', '?')], to_jsonb('refused: ' || left(sqlerrm, 120)));
    end;
  end loop;
  insert into one.audit (actor, action, target, after, request_id)
  values (left(p_actor, 80), 'app_report', 'one.heartbeats, one.results',
          jsonb_build_object('heartbeats', jsonb_array_length(coalesce(p_report -> 'heartbeats', '[]')),
                             'results', jsonb_array_length(coalesce(p_report -> 'results', '[]'))), left(p_request_id, 80));
  return v_out;
end $$;

-- Witty conversations a person took over (bot paused after an escalation), for WITTY-05's Chatwoot label check.
-- Conversation ids only: the phone never leaves the database.
create or replace function one.witty_escalations(p_limit integer default 50) returns table (conversation_id bigint, account_id bigint, escalated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select c.conversation_id, c.account_id, c.escalated_at from public.w2_conversations c
   where c.bot_paused and c.escalated_at is not null and c.conversation_id is not null
   order by c.escalated_at desc limit least(greatest(p_limit, 1), 200)
$$;

-- The two ages the external watchdog reads (spec §3): the last minute tick and the app's last answer to it.
-- What the external watchdog reads (D-018): the age of the last tick that finished its alert step and app call (not the
-- heartbeat written at its start, which stays fresh while every later step is killed; B1 of the second review), the
-- app's last answer, and how long the oldest alert email has waited (the app can be unreachable from the database while
-- the monitor still reaches it; M2).
create or replace function one.watchdog() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'tick_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'app_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:app'),
    'delivery_wait_s', (select round(extract(epoch from now() - min(created_at))) from one.deliveries
                         where status in ('pending', 'sending') and kind in ('alert', 'escalation', 'storm')))
$$;

-- Deliveries for the app's sender to send now (spec §9). Claims up to p_limit pending email deliveries (and any left
-- in "sending" for more than 5 minutes by a sender that died), with what the message needs: the incident, already
-- free of contact data, or for a digest the day's P2 list. A delivery whose reason has gone (incident resolved;
-- acknowledged, for an escalation; muted or held by a storm) is closed instead of sent.
create or replace function one.claim_deliveries(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_out jsonb := '[]';
  v_row record;
begin
  update one.deliveries d set status = case when i.alert_state = 'muted' then 'muted' else 'suppressed' end
    from one.incidents i
   where d.incident_id = i.id and d.status = 'pending' and d.channel = 'email'
     and (i.resolved_at is not null or i.alert_state in ('muted', 'suppressed')
          or (d.kind = 'escalation' and i.acknowledged_at is not null));
  for v_row in
    with c as (
      select d.id from one.deliveries d
       where d.channel = 'email'
         and ((d.status = 'pending' and d.next_attempt_at <= now()) or (d.status = 'sending' and d.claimed_at < now() - interval '5 minutes'))
       order by d.created_at limit least(greatest(p_limit, 1), 100) for update skip locked)
    update one.deliveries d set status = 'sending', claimed_at = now() from c where d.id = c.id
    returning d.id, d.incident_id, d.recipient, d.kind, d.escalation_level, d.attempts, d.idempotency_key
  loop
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row.id, 'recipient', v_row.recipient, 'kind', v_row.kind, 'escalation_level', v_row.escalation_level,
      'attempts', v_row.attempts, 'idempotency_key', v_row.idempotency_key,
      'incident', (select jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'severity', i.severity, 'title', i.title,
                                             'opened_at', i.opened_at, 'occurrences', i.occurrences, 'reopened_count', i.reopened_count,
                                             'subjects', to_jsonb(i.subjects), 'summary', i.summary, 'value', i.evidence -> 'value',
                                             'status', i.evidence ->> 'status', 'error', i.evidence ->> 'error')
                     from one.incidents i where i.id = v_row.incident_id),
      'digest', case when v_row.kind = 'digest' then (
        select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                     'resolved', i.resolved_at is not null) order by i.opened_at), '[]')
          from one.incidents i
         where i.severity = 'P2' and (i.opened_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date) end));
  end loop;
  return v_out;
end $$;

-- The sender's verdict on one delivery. Sent: the provider's id is kept and a pending P1 becomes "sent". Failed: one
-- retry after 2 minutes; a second failure is final, and ONE-01 reports it (spec §9: a delivery failing twice is an
-- incident, so a dead email key does not stay silent).
create or replace function one.finish_delivery(p_id bigint, p_ok boolean, p_error text default null, p_provider_id text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_d one.deliveries;
begin
  select * into v_d from one.deliveries where id = p_id and status = 'sending' for update;
  if not found then
    return 'not_claimed';
  end if;
  if p_ok then
    update one.deliveries set status = 'sent', sent_at = now(), provider_id = left(p_provider_id, 120), error = null, attempts = attempts + 1 where id = p_id;
    update one.incidents set alert_state = 'sent' where id = v_d.incident_id and alert_state = 'pending';
    return 'sent';
  end if;
  update one.deliveries
     set attempts = attempts + 1, error = left(p_error, 500),
         status = case when attempts + 1 >= 2 then 'failed' else 'pending' end,
         next_attempt_at = now() + interval '2 minutes'
   where id = p_id;
  return case when v_d.attempts + 1 >= 2 then 'failed' else 'retry' end;
end $$;

-- Mute a check or an app, or open a maintenance window on an app (spec §9): incidents still record, deliveries are held.
-- When the mute ends, one.escalate() routes the still-open incidents again.
create or replace function one.mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_by text) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  if p_target_type = 'check' and not exists (select 1 from one.checks where id = p_target)
     or p_target_type = 'app' and not exists (select 1 from one.apps where key = p_target) then
    raise exception 'one.mute: unknown % %', p_target_type, p_target using errcode = '22023';
  end if;
  if coalesce(p_minutes, 0) not between 1 and 10080 or nullif(trim(p_reason), '') is null then
    raise exception 'one.mute: a duration of 1 minute to 7 days and a reason are required' using errcode = '22023';
  end if;
  insert into one.mutes (target_type, target, ends_at, reason, created_by)
  values (p_target_type, p_target, now() + make_interval(mins => p_minutes), left(p_reason, 300), left(p_by, 120))
  returning id into v_id;
  update one.incidents set alert_state = 'muted'
   where resolved_at is null and alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2', 'digest')
     and ((p_target_type = 'check' and check_id = p_target) or (p_target_type = 'app' and app = p_target));
  insert into one.audit (actor, action, target, after) values (left(p_by, 120), 'mute', p_target_type || ':' || p_target,
    jsonb_build_object('mute_id', v_id, 'minutes', p_minutes, 'reason', left(p_reason, 300)));
  return v_id;
end $$;

create or replace function one.unmute(p_id bigint, p_by text) returns void
language plpgsql set search_path = '' as $$
begin
  update one.mutes set ends_at = greatest(now(), starts_at + interval '1 second') where id = p_id and ends_at > now();
  insert into one.audit (actor, action, target, after) values (left(p_by, 120), 'unmute', 'mute:' || p_id, '{}');
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.app_tick_state()', 'service_role', 'the probe runner reads settings, app-run checks and heartbeats'),
  ('one.app_report(jsonb,text,text)', 'service_role', 'the probe runner writes heartbeats and app-run results'),
  ('one.witty_escalations(integer)', 'service_role', 'WITTY-05: conversation ids only'),
  ('one.watchdog()', 'service_role', 'the external watchdog endpoint'),
  ('one.claim_deliveries(integer)', 'service_role', 'the alert sender claims emails'),
  ('one.finish_delivery(bigint,boolean,text,text)', 'service_role', 'the alert sender records the verdict')
on conflict do nothing;
call one.apply_grants();
