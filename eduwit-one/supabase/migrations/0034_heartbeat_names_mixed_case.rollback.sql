-- Rollback of 0034: one.app_report as 0008 defined it (heartbeat names lowercase only).

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
