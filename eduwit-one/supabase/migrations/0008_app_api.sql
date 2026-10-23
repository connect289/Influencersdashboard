-- 0008 the functions the app calls (spec §5 app layer, phase 2). The app reaches the database only through these and
-- the one.* tables, with the service role; it reads app data only through SECURITY DEFINER functions that return no
-- contact fields (D-030). One call reads what a tick needs, one call writes what it found.

-- Everything the app's probe runner needs for one tick: the runtime settings it reads, the app-run checks with their
-- last run, and the heartbeat rows. Setup items are reduced to their status, without the evidence text.
create or replace function one.app_tick_state() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'now', now(),
    'settings', (select coalesce(jsonb_object_agg(s.key, s.value), '{}') from one.settings s
                  where s.key in ('app', 'hosts', 'health_paths', 'vendors', 'vercel', 'chatwoot', 'n8n', 'whatsapp', 'witty', 'thresholds', 'checks')),
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
language plpgsql set search_path = '' as $$
declare
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(one.setting('events') -> 'pii_columns')), '{}');
  v_item jsonb;
  v_out jsonb := jsonb_build_object('heartbeats', '{}'::jsonb, 'results', '{}'::jsonb);
  v_value jsonb;
begin
  for v_item in select jsonb_array_elements(coalesce(p_report -> 'heartbeats', '[]')) loop
    begin
      if coalesce(v_item ->> 'component', '') !~ '^[a-z0-9:._-]{1,80}$' then
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
create or replace function one.watchdog() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'tick_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:tick'),
    'app_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:app'))
$$;

call one.apply_grants();
grant execute on function one.app_tick_state(), one.app_report(jsonb, text, text), one.witty_escalations(integer), one.watchdog()
  to service_role;
-- one.app_report runs with the caller's rights and redacts every value; redact is a pure function.
grant execute on function one.redact(jsonb, text[]) to service_role;
