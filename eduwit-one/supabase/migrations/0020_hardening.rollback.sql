-- Rollback of 0020 hardening: restores 0018's one.ai_tool_data and 0019's one.fix_run and one.fix_verify_one verbatim; drops the
-- proof-before-power objects (D-084). Fix state (pauses) is dropped with its table: a paused fix is paused only by 0020's rules.

create or replace function one.ai_tool_data(p_name text, p_args jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}' end;
  v_hours integer := least(greatest(coalesce((a ->> 'since_hours')::int, 168), 1), 720);
  v_limit integer := least(greatest(coalesce((a ->> 'limit')::int, 20), 1), 50);
  v_days integer := least(greatest(coalesce((a ->> 'days')::int, 7), 1), 90);
  v jsonb;
begin
  case p_name
    when 'incidents' then
      select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'severity', i.severity, 'title', i.title,
                                                   'opened_at', i.opened_at, 'resolved_at', i.resolved_at, 'resolution', i.resolution,
                                                   'occurrences', i.occurrences, 'acknowledged', i.acknowledged_at is not null, 'summary', i.summary,
                                                   'value', i.evidence -> 'value') order by i.opened_at desc), '[]')
        into v
        from (select * from one.incidents i
               where i.check_id <> 'ONE-SYNTH'
                 and (a ->> 'app' is null or i.app = a ->> 'app')
                 and (a ->> 'check_id' is null or i.check_id = a ->> 'check_id')
                 and (a ->> 'severity' is null or i.severity::text = a ->> 'severity')
                 and case coalesce(a ->> 'status', 'open')
                       when 'open' then i.resolved_at is null
                       when 'resolved' then i.resolved_at is not null and i.opened_at > now() - make_interval(hours => v_hours)
                       else i.resolved_at is null or i.opened_at > now() - make_interval(hours => v_hours) end
               order by i.opened_at desc limit v_limit) i;
    when 'incident' then
      v := one.ai_incident_context((a ->> 'id')::bigint, 'triage');
    when 'check' then
      select jsonb_build_object('check', jsonb_build_object('id', c.id, 'app', c.app, 'title', c.title, 'description', c.description, 'kind', c.kind,
                                                            'severity', c.severity, 'cadence_s', c.cadence_s, 'enabled', c.enabled,
                                                            'disabled_reason', c.disabled_reason, 'tags', to_jsonb(c.tags)),
                                'last_results', (select coalesce(jsonb_agg(jsonb_build_object('at', r.ran_at, 'status', r.status, 'value', r.value,
                                                                                              'error', left(r.error, 200)) order by r.ran_at desc), '[]')
                                                   from (select * from one.results where check_id = c.id order by ran_at desc limit 20) r))
        into v from one.checks c where c.id = a ->> 'check_id';
      if v is null then
        raise exception 'no check %', a ->> 'check_id' using errcode = 'P0002';
      end if;
    when 'checks_failing' then
      select coalesce(jsonb_agg(jsonb_build_object('check_id', x.check_id, 'app', x.app, 'severity', x.severity, 'title', x.title, 'status', x.status,
                                                   'at', x.ran_at, 'value', x.value) order by x.severity, x.check_id), '[]')
        into v
        from (select distinct on (r.check_id) r.check_id, r.status, r.ran_at, r.value, c.app, c.severity, c.title
                from one.results r join one.checks c on c.id = r.check_id
               where c.enabled and r.ran_at > now() - interval '1 day' and (a ->> 'app' is null or c.app = a ->> 'app')
               order by r.check_id, r.ran_at desc) x
       where x.status <> 'ok';
    when 'tests' then
      select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'app', t.app, 'title', t.title, 'enabled', t.enabled, 'needs', to_jsonb(t.needs),
                                                   'last_runs', (select coalesce(jsonb_agg(jsonb_build_object('at', r.started_at, 'ok', r.ok, 'error', r.error,
                                                                                                              'failed_steps', (select coalesce(jsonb_agg(s ->> 'key'), '[]')
                                                                                                                                 from jsonb_array_elements(r.step_results) s
                                                                                                                                where (s ->> 'ok')::boolean is false))
                                                                                          order by r.started_at desc), '[]')
                                                                   from (select * from one.test_runs r where r.test_id = t.id order by started_at desc limit 5) r))
                                order by t.id), '[]')
        into v from one.tests t where a ->> 'test_id' is null or t.id = a ->> 'test_id';
    when 'events' then
      select coalesce(jsonb_agg(jsonb_build_object('bucket', b, 'app', app, 'type', type, 'n', n) order by b desc, n desc), '[]')
        into v
        from (select date_trunc(case when a ->> 'bucket' = 'hour' then 'hour' else 'day' end, occurred_at at time zone 'Asia/Kolkata') as b,
                     app, type, count(*) as n
                from one.events
               where occurred_at > now() - make_interval(hours => least(v_hours, 24 * 14))
                 and (a ->> 'app' is null or app = a ->> 'app')
                 and (a ->> 'type' is null or type = a ->> 'type')
               group by 1, 2, 3 order by 1 desc, 4 desc limit 200) s;
    when 'analytics' then
      v := one.analytics_data(v_days);
    when 'marketing' then
      v := one.marketing_data(v_days);
    when 'witty' then
      if coalesce(a ->> 'panel', '') not in ('replies', 'outbox', 'digest', 'health_alerts', 'learnings', 'n8n') then
        raise exception 'panel is one of replies, outbox, digest, health_alerts, learnings, n8n' using errcode = '22023';
      end if;
      v := one.embed_data('witty.' || (a ->> 'panel'));
      perform set_config('search_path', '', true);
    when 'health' then
      v := jsonb_build_object('one', one.health(),
                              'heartbeats', (select coalesce(jsonb_agg(jsonb_build_object('component', h.component) || one.heartbeat_state(h.component)
                                                                       order by h.component), '[]') from one.heartbeats h));
      begin v := v || jsonb_build_object('b2b', b2b.health_check()); exception when others then v := v || jsonb_build_object('b2b_error', left(sqlerrm, 160)); end;
      begin v := v || jsonb_build_object('website', public.web_health()); exception when others then v := v || jsonb_build_object('website_error', left(sqlerrm, 160)); end;
      begin v := v || jsonb_build_object('influencer', one.inf_health()); exception when others then v := v || jsonb_build_object('influencer_error', left(sqlerrm, 160)); end;
    when 'cron' then
      select coalesce(jsonb_agg(to_jsonb(s) order by s.failed desc, s.job), '[]')
        into v
        from (select j.jobname as job, count(*) as runs, count(*) filter (where d.status = 'failed') as failed,
                     max(d.start_time) filter (where d.status = 'failed') as last_failed_at,
                     left((array_agg(d.return_message order by d.start_time desc) filter (where d.status = 'failed'))[1], 200) as last_failure
                from cron.job_run_details d join cron.job j on j.jobid = d.jobid
               where d.start_time > now() - make_interval(hours => least(v_hours, 48))
               group by j.jobname) s;
    when 'ai_spend' then
      select coalesce(jsonb_agg(to_jsonb(s) order by s.day desc, s.model), '[]')
        into v
        from (select (created_at at time zone 'Asia/Kolkata')::date as day, provider, model, count(*) as calls, count(*) filter (where not ok) as failed,
                     sum(cost_inr) as inr, sum(input_tokens) as input_tokens, sum(output_tokens) as output_tokens
                from one.ai_calls where created_at > now() - make_interval(days => least(v_days, 30)) group by 1, 2, 3) s;
    when 'proposals' then
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'app', p.app, 'title', p.title, 'status', p.status, 'risk', p.risk,
                                                   'source', p.source, 'created_at', p.created_at) order by p.id desc), '[]')
        into v
        from (select * from one.proposals where status = coalesce(a ->> 'status', 'open') order by id desc limit v_limit) p;
    when 'deliveries' then
      select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
        into v
        from (select kind, status, count(*) as n from one.deliveries where created_at > now() - make_interval(hours => v_hours) group by 1, 2) s;
    else
      raise exception 'unknown tool %', p_name using errcode = '22023';
  end case;
  return one.redact(v, one.pii_keys());
end $$;


create or replace function one.fix_run(p_fix text, p_incident bigint, p_dry_run boolean default true, p_by text default 'one',
                                       p_approval bigint default null, p_rows jsonb default null, p_actor uuid default null) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_f one.fixes;
  v_cfg jsonb;
  v_inc one.incidents;
  v_plan jsonb;
  v_dry boolean;
  v_limit integer;
  v_cool integer;
  v_key text;
  v_target jsonb;
  v_res jsonb;
  v_status text;
  v_prop bigint;
  v_id bigint;
begin
  select * into v_f from one.fixes where id = p_fix;
  if not found then
    raise exception 'no fix %', p_fix using errcode = 'P0002';
  end if;
  v_cfg := coalesce(one.setting('fixes') -> p_fix, '{}');
  v_limit := coalesce((v_cfg ->> 'per_tick')::int, 1);
  v_cool := coalesce((v_cfg ->> 'cooldown_min')::int, 60);
  select * into v_inc from one.incidents where id = p_incident;
  if not found then
    raise exception 'no incident %', p_incident using errcode = 'P0002';
  end if;
  if v_inc.resolved_at is not null and p_approval is null then
    return jsonb_build_object('fix', p_fix, 'skipped', 'the incident is resolved');
  end if;
  v_dry := p_approval is null
           and (p_dry_run or not coalesce((v_cfg ->> 'enabled')::boolean, false) or (one.fix_window() ->> 'running')::boolean);
  -- A run on this incident did not hold: the incident went up a level instead of a retry (spec §8), and the fix stays
  -- off it; only an approval runs it again, and a person may still ask for a dry run (phase 7 review M10).
  if p_approval is null and not (v_dry and p_by <> 'one')
     and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.step = 'verify' and a.status = 'failed') then
    return jsonb_build_object('fix', p_fix, 'skipped', 'stopped: a run on this incident did not hold');
  end if;
  if p_approval is null then
    if v_dry then
      if p_by = 'one' and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.dry_run and a.ran_by = 'one'
                                     and a.ran_at > now() - make_interval(mins => v_cool)) then
        return jsonb_build_object('fix', p_fix, 'skipped', 'cooldown');
      end if;
    elsif exists (select 1 from one.actions a where a.fix_id = p_fix and not a.dry_run and a.step in ('before', 'after', 'skip')
                     and a.ran_at > now() - make_interval(mins => v_cool)) then
      return jsonb_build_object('fix', p_fix, 'skipped', 'cooldown');
    end if;
  end if;
  v_plan := one.fix_plan(p_fix, v_inc);
  if p_approval is not null then
    v_plan := one.fix_plan_within(v_plan, p_rows);
  end if;
  if not coalesce((v_plan ->> 'applies')::boolean, false) then
    return jsonb_build_object('fix', p_fix, 'applies', false, 'why_not', v_plan ->> 'why_not');
  end if;
  v_key := format('%s:%s:%s', p_fix, p_incident, to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
  v_target := coalesce(v_plan -> 'target', '{}') || jsonb_build_object('rows', coalesce(v_plan -> 'rows', '[]'), 'count', v_plan -> 'count',
                                                                         'test_rows_left_out', coalesce(v_plan -> 'test_rows', '0'));
  -- More rows than the rate limit: nothing is done, a proposal is opened instead (spec §8). A proposing fix's act is the
  -- proposal itself, so it has no row limit (phase 7 review M3).
  if p_approval is null and v_f.mode <> 'propose' and coalesce((v_plan ->> 'count')::int, 0) > v_limit then
    if v_dry then
      v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                             jsonb_build_object('would', format('open a proposal: %s rows is over the limit of %s', v_plan ->> 'count', v_limit),
                                                'over_limit', true, 'mode', v_f.mode), p_by, v_key);
      return jsonb_build_object('fix', p_fix, 'dry_run', true, 'action', v_id, 'over_limit', true);
    end if;
    v_prop := one.fix_propose(v_f, v_inc, v_plan, 'over_limit');
    v_id := one.fix_record(p_fix, p_incident, 'skip', 'skipped', false, v_target,
                           jsonb_build_object('reason', 'over_limit', 'limit', v_limit, 'proposal', v_prop), p_by, v_key, null, v_prop);
    return jsonb_build_object('fix', p_fix, 'skipped', 'over_limit', 'proposal', v_prop, 'action', v_id);
  end if;
  if v_dry then
    v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                           jsonb_build_object('would', v_plan ->> 'would', 'mode', v_f.mode,
                                              'why_dry', case when p_dry_run then 'asked for a dry run'
                                                              when not coalesce((v_cfg ->> 'enabled')::boolean, false) then 'switched off'
                                                              else 'observation window' end), p_by, v_key);
    return jsonb_build_object('fix', p_fix, 'dry_run', true, 'action', v_id);
  end if;
  if v_f.mode = 'propose' or (v_f.mode = 'approve' and p_approval is null) then
    v_prop := one.fix_propose(v_f, v_inc, v_plan, v_f.mode);
    v_id := one.fix_record(p_fix, p_incident, 'after', 'done', false, v_target,
                           jsonb_build_object('proposal', v_prop, 'waiting', case when v_f.mode = 'approve' then 'the owner''s approval' end),
                           p_by, v_key, null, v_prop);
    return jsonb_build_object('fix', p_fix, 'proposal', v_prop, 'action', v_id);
  end if;
  if v_f.mode = 'approve' then
    -- An approved FIX-OUTBOX-B2B: B2B's admin action for each row, under the approver's session, with the fixer's rights.
    perform one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target, jsonb_build_object('approval', p_approval), p_by, v_key, null, p_approval);
    v_res := jsonb_build_object('done', '[]'::jsonb, 'refused', '[]'::jsonb);
    for v_id in select x::bigint from jsonb_array_elements_text(coalesce(v_plan -> 'rows', '[]')) x loop
      begin
        perform one.fixer_b2b_outbox_retry(v_id);
        v_res := jsonb_set(v_res, '{done}', (v_res -> 'done') || to_jsonb(v_id));
      exception when others then
        v_res := jsonb_set(v_res, '{refused}', (v_res -> 'refused') || jsonb_build_object('id', v_id, 'error', left(sqlerrm, 200)));
      end;
    end loop;
    v_status := case when jsonb_array_length(v_res -> 'done') > 0 then 'done' else 'failed' end;
    v_res := one.redact(v_res || jsonb_build_object('partial', jsonb_array_length(v_res -> 'done') > 0 and jsonb_array_length(v_res -> 'refused') > 0),
                        one.pii_keys());
    v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, v_res, p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id, 'result', v_res);
  end if;
  if v_f.mode = 'app' then
    v_id := one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target,
                           jsonb_build_object('waiting', 'the app', 'approval', p_approval), p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'queued_for_app', v_id);
  end if;
  perform one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target, jsonb_build_object('approval', p_approval), p_by, v_key, null, p_approval);
  -- An app row held by another session makes the act give up after the checks' lock timeout instead of waiting
  -- (phase 7 review M8).
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  begin
    v_res := one.fix_act(p_fix, v_plan, p_actor);
    v_status := 'done';
  exception when others then
    v_res := jsonb_build_object('error', left(sqlerrm, 300), 'sqlstate', sqlstate);
    v_status := 'failed';
  end;
  v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, one.redact(coalesce(v_res, '{}'), one.pii_keys()), p_by, v_key,
                         case when v_status = 'done' then now() + make_interval(mins => least(2, v_cool)) end, p_approval);
  return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id);
end $$;

create or replace function one.fix_verify_one(p_run one.actions) returns text
language plpgsql set search_path = '' as $$
declare
  v_inc one.incidents;
  v_seen one.incidents;
  v_next one.results;
  v_cool integer := coalesce((one.setting('fixes') -> p_run.fix_id ->> 'cooldown_min')::int, 60);
  v_cadence integer;
  v_applies boolean;
  v_esc jsonb;
begin
  select * into v_inc from one.incidents where id = p_run.incident_id;
  if v_inc.resolved_at is not null then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'why', 'the incident resolved (' || v_inc.resolution || ')'), 'one', p_run.run_key);
    return 'held';
  end if;
  select cadence_s into v_cadence from one.checks where id = v_inc.check_id;
  select * into v_next from one.results x where x.check_id = v_inc.check_id and x.ran_at >= p_run.verify_at order by x.ran_at, x.id limit 1;
  if not found then
    if now() > p_run.ran_at + make_interval(mins => v_cool) + make_interval(secs => 2 * coalesce(v_cadence, 60)) then
      perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'skipped', false, p_run.target,
                             jsonb_build_object('held', null, 'why', format('no run of %s to judge it by', v_inc.check_id)), 'one', p_run.run_key);
      return 'unverified';
    end if;
    return null;
  end if;
  if v_next.status = 'ok' then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'judged_by', v_next.id, 'why', format('%s passed at %s', v_inc.check_id, v_next.ran_at)),
                           'one', p_run.run_key);
    return 'held';
  end if;
  if v_next.status <> 'fail' then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'skipped', false, p_run.target,
                           jsonb_build_object('held', null, 'judged_by', v_next.id, 'why', format('%s could not run (%s)', v_inc.check_id, v_next.status)),
                           'one', p_run.run_key);
    return 'unverified';
  end if;
  -- What that failing run saw, as the plan reads it. A retried execution that failed again shows as a retry.
  v_seen := v_inc;
  v_seen.evidence := jsonb_build_object('status', 'fail', 'value', v_next.value);
  v_seen.subjects := coalesce(case when jsonb_typeof(v_next.value -> 'subjects') = 'array'
                                   then array(select jsonb_array_elements_text(v_next.value -> 'subjects')) end, v_inc.subjects);
  v_applies := coalesce((one.fix_plan(p_run.fix_id, v_seen) ->> 'applies')::boolean, false)
               or (p_run.fix_id = 'FIX-N8N-RETRY' and jsonb_array_length(coalesce(v_next.value -> 'retries_15m', '[]')) > 0);
  if not v_applies then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'judged_by', v_next.id, 'why', format('%s still fails, for another reason', v_inc.check_id)),
                           'one', p_run.run_key);
    return 'held';
  end if;
  if exists (select 1 from one.actions a where a.step = 'verify' and a.incident_id = p_run.incident_id
                and a.result ->> 'judged_by' = v_next.id::text and coalesce((a.result ->> 'escalated')::boolean, false)) then
    v_esc := jsonb_build_object('escalated', false, 'why', 'already escalated on this failing run');
  else
    v_esc := one.incident_escalate(v_inc.id, format('%s ran at %s and %s failed again', p_run.fix_id, p_run.ran_at, v_inc.check_id));
  end if;
  perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'failed', false, p_run.target,
                         jsonb_build_object('held', false, 'judged_by', v_next.id, 'failed_again_at', v_next.ran_at) || v_esc, 'one', p_run.run_key);
  return 'did not hold';
end $$;

drop function if exists one.ui_fix_unpause(text, text, text);
drop function if exists one.ui_fix_states();
drop function if exists one.fix_breaker(text);
drop function if exists one.fix_pause(text, text, text);
drop function if exists one.fix_proven(text);
drop function if exists one.fix_paused_reason(text);
drop table if exists one.fix_state;
delete from one.api_grants where fn in ('one.ui_fix_states()', 'one.ui_fix_unpause(text,text,text)');

-- >>> hardening batch (self-healing, security, efficiency)
create or replace function one.evaluate(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_state one.check_state;
  v_open bigint;
  v_severity one.severity;
  v_failing boolean;
  v_subjects text[];
begin
  select * into strict v_check from one.checks where id = p_check_id;
  v_failing := p_status in ('fail', 'error')
               or (p_status = 'source_missing' and coalesce((one.setting('checks') ->> 'source_missing_opens_incident')::boolean, true));
  insert into one.results (check_id, status, value, error, duration_ms) values (p_check_id, p_status, p_value, left(p_error, 1000), p_duration_ms);
  insert into one.check_state (check_id) values (p_check_id) on conflict do nothing;
  update one.check_state set
    last_ran_at = now(), last_status = p_status, killed_count = 0,
    consecutive_fail = case when v_failing then consecutive_fail + 1 when p_status = 'ok' then 0 else consecutive_fail end,
    consecutive_ok = case when p_status = 'ok' then consecutive_ok + 1 when v_failing then 0 else consecutive_ok end
   where check_id = p_check_id
   returning * into v_state;
  select id into v_open from one.incidents where check_id = p_check_id and resolved_at is null;
  if v_failing and v_state.consecutive_fail >= v_check.open_after then
    v_severity := case when p_status = 'fail' then coalesce(nullif(p_value ->> 'severity', '')::one.severity, v_check.severity) else v_check.severity end;
    v_subjects := case when p_status = 'fail' and jsonb_typeof(p_value -> 'subjects') = 'array'
                       then array(select jsonb_array_elements_text(p_value -> 'subjects')) else '{}' end;
    perform one.open_or_touch_incident(p_check_id, v_severity,
      jsonb_build_object('status', p_status, 'value', p_value, 'error', left(p_error, 300), 'at', now()), v_subjects);
    return case when v_open is null then 'opened' else 'touched' end;
  end if;
  if p_status = 'ok' and v_open is not null and v_state.consecutive_ok >= v_check.resolve_after then
    perform one.resolve_incident(v_open, 'one', 'recovered');
    return 'resolved';
  end if;
  return 'none';
end $$;

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
    returning d.id, d.incident_id, d.brief_id, d.recipient, d.kind, d.escalation_level, d.attempts, d.idempotency_key
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
         where i.severity = 'P2' and (i.opened_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
           and i.check_id <> 'ONE-SYNTH') end,
      -- With the saved views people asked to have emailed: daily ones every day, weekly ones on Mondays (links only;
      -- their numbers stay on the page).
      'brief', case when v_row.kind = 'brief' then (
        select jsonb_build_object('id', b.id, 'for_date', b.for_date, 'body_md', b.body_md, 'model', b.model,
                                  'views', (select coalesce(jsonb_agg(jsonb_build_object('name', v.name, 'page', v.page, 'days', v.params -> 'days')
                                                                      order by v.page, v.name), '[]')
                                              from one.saved_views v
                                             where v.schedule = 'daily' or (v.schedule = 'weekly' and extract(isodow from b.for_date) = 1)))
          from one.briefs b where b.id = v_row.brief_id) end));
  end loop;
  return v_out;
end $$;

create or replace function one.ui_incident(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_inc one.incidents;
begin
  select * into v_inc from one.incidents where id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'incident', to_jsonb(v_inc),
    'check', (select jsonb_build_object('id', c.id, 'title', c.title, 'description', c.description, 'kind', c.kind, 'severity', c.severity,
                                        'cadence_s', c.cadence_s, 'sql', c.sql, 'tags', c.tags, 'auto_fix_id', c.auto_fix_id, 'enabled', c.enabled,
                                        'disabled_reason', c.disabled_reason, 'open_after', c.open_after, 'resolve_after', c.resolve_after,
                                        'muted', one.is_muted(c.id, c.app),
                                        'fix_enabled', coalesce((one.setting('fixes') -> c.auto_fix_id ->> 'enabled')::boolean, false))
                from one.checks c where c.id = v_inc.check_id),
    'results', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'ran_at', r.ran_at, 'status', r.status, 'value', r.value,
                                                            'error', r.error, 'duration_ms', r.duration_ms) order by r.id desc), '[]')
                  from (select * from one.results where check_id = v_inc.check_id order by id desc limit 30) r),
    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.occurred_at, 'app', e.app, 'source', e.source_table,
                                                             'type', e.type, 'lead_id', e.lead_id, 'actor_type', e.actor_type, 'payload', e.payload)
                                           order by e.occurred_at), '[]')
                   from (select * from one.events e
                          where e.app = v_inc.app and e.occurred_at between v_inc.opened_at - interval '30 minutes' and v_inc.opened_at + interval '30 minutes'
                          order by e.occurred_at limit 200) e),
    'deliveries', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'recipient', d.recipient, 'kind', d.kind, 'level', d.escalation_level,
                                                               'status', d.status, 'attempts', d.attempts, 'sent_at', d.sent_at, 'error', d.error,
                                                               'created_at', d.created_at) order by d.id), '[]')
                     from one.deliveries d where d.incident_id = p_id),
    'actions', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]') from one.actions a where a.incident_id = p_id),
    'ai_tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'model_hint', t.model_hint, 'status', t.status,
                                                             'result', t.result, 'error', t.error, 'created_at', t.created_at) order by t.id desc), '[]')
                   from one.ai_tasks t where t.incident_id = p_id),
    'proposals', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'title', p.title, 'status', p.status, 'risk', p.risk)
                                            order by p.id desc), '[]')
                    from one.proposals p where p.incident_id = p_id),
    'tests', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'enabled', t.enabled,
                                                          'last_ok', (select r.ok from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 1))
                                        order by t.id), '[]')
                from one.tests t where t.app = v_inc.app),
    'children', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'check_id', c.check_id, 'title', c.title, 'severity', c.severity,
                                                             'resolved_at', c.resolved_at) order by c.id), '[]')
                   from one.incidents c where c.parent_id = p_id),
    'mutes', (select coalesce(jsonb_agg(to_jsonb(m) order by m.ends_at desc), '[]') from one.mutes m
               where m.ends_at > now() and ((m.target_type = 'check' and m.target = v_inc.check_id) or (m.target_type = 'app' and m.target = v_inc.app))));
end $$;

create or replace function one.ui_check_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_c one.checks;
  v_enabled boolean;
begin
  select * into v_c from one.checks where id = p_id for update;
  if not found then
    raise exception 'no check %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_c.enabled);
  -- Switching off, or lowering the severity of, a check that guards the platform is the owner's (security review S7):
  -- every P1, the integrity checks, and those tagged security, integrity, money or consent.
  if (v_c.severity = 'P1' or v_c.app = 'integrity' or v_c.tags && array['security', 'integrity', 'money', 'consent'])
     and ((v_c.enabled and not v_enabled)
          or coalesce((p_patch ->> 'severity')::one.severity, v_c.severity) > v_c.severity) then
    perform one.ui_require('owner');
  end if;
  if v_enabled and not v_c.enabled and v_c.disabled_reason like 'blocked:%' then
    raise exception 'check % cannot run: %', p_id, v_c.disabled_reason using errcode = '22023';
  end if;
  update one.checks set
    enabled = v_enabled,
    disabled_reason = case when v_enabled then null
                           when v_c.enabled then 'owner:' || coalesce(nullif(trim(both '-' from regexp_replace(lower(left(v_reason, 40)), '[^a-z0-9_.:-]+', '-', 'g')), ''),
                                                                     'switched-off')
                           else disabled_reason end,
    severity = coalesce((p_patch ->> 'severity')::one.severity, severity),
    cadence_s = coalesce((p_patch ->> 'cadence_s')::int, cadence_s),
    threshold = case when jsonb_typeof(p_patch -> 'threshold') = 'object' then p_patch -> 'threshold' else threshold end,
    open_after = coalesce((p_patch ->> 'open_after')::int, open_after),
    resolve_after = coalesce((p_patch ->> 'resolve_after')::int, resolve_after),
    updated_by = v_actor, updated_at = now(), version = version + 1
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'check.update', 'check:' || p_id,
    jsonb_build_object('enabled', v_c.enabled, 'severity', v_c.severity, 'cadence_s', v_c.cadence_s, 'threshold', v_c.threshold,
                       'open_after', v_c.open_after, 'resolve_after', v_c.resolve_after),
    p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.ui_test_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_t one.tests;
  v_enabled boolean;
  v_item text;
begin
  select * into v_t from one.tests where id = p_id for update;
  if not found then
    raise exception 'no test %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_t.enabled);
  -- A test runs only on validated identities: every Setup item it needs (spec §10, §15).
  select u.n into v_item from unnest(v_t.needs) with ordinality u(n, o)
   where not coalesce((one.setting('setup') #>> array['items', u.n, 'validated'])::boolean, false) order by u.o limit 1;
  if v_enabled and not v_t.enabled and v_t.disabled_reason like 'blocked:%' then
    raise exception 'test % cannot run: %', p_id, v_t.disabled_reason using errcode = '22023';
  end if;
  if v_enabled and not v_t.enabled and v_item is not null then
    raise exception 'test % waits for Setup item %', p_id, v_item using errcode = '22023';
  end if;
  -- Switching off a P1 test is the owner's, as for a P1 check (D-065).
  if v_t.enabled and not v_enabled and v_t.severity = 'P1' then
    perform one.ui_require('owner');
  end if;
  if p_patch ? 'schedule' and p_patch ->> 'schedule' !~ '^(\S+\s+){4}\S+$' then
    raise exception 'a schedule is a 5-field cron expression' using errcode = '22023';
  end if;
  update one.tests set enabled = v_enabled,
         disabled_reason = case when v_enabled then null when v_t.enabled then 'owner:' || left(v_reason, 60) else disabled_reason end,
         schedule = coalesce(p_patch ->> 'schedule', schedule), updated_by = v_actor
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'test.update', 'test:' || p_id, jsonb_build_object('enabled', v_t.enabled, 'schedule', v_t.schedule),
                             p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.settings_check(p_key text, p_value jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare
  v_email text := '^[^@\s]+@[^@\s]+\.[a-z]{2,}$';
  v_bad text;
begin
  if jsonb_typeof(p_value) is distinct from 'object' then
    raise exception 'setting %: the value must be a JSON object', p_key using errcode = '22023';
  end if;
  case p_key
    when 'events' then
      if jsonb_typeof(p_value -> 'pii_columns') is distinct from 'array' or jsonb_array_length(p_value -> 'pii_columns') = 0
         or exists (select 1 from jsonb_array_elements(p_value -> 'pii_columns') e where jsonb_typeof(e) <> 'string') then
        raise exception 'setting events: pii_columns must be a non-empty list of key patterns' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'batch')::int, 5000) not between 100 and 50000
         or coalesce((p_value ->> 'id_overlap')::int, 0) not between 0 and 10000
         or coalesce((p_value ->> 'window_hours')::int, 48) not between 1 and 720 then
        raise exception 'setting events: batch 100–50000, id_overlap 0–10000, window_hours 1–720' using errcode = '22023';
      end if;
    when 'alerts' then
      if jsonb_typeof(p_value #> '{p1,email}') is distinct from 'array' or jsonb_array_length(p_value #> '{p1,email}') = 0 then
        raise exception 'setting alerts: p1.email must be a non-empty list of addresses' using errcode = '22023';
      end if;
      select string_agg(x, ', ') into v_bad
        from (select jsonb_array_elements_text(p_value #> '{p1,email}') x
              union all select jsonb_array_elements_text(coalesce(p_value #> '{escalation,second_contact}', '[]'))
              union all select p_value ->> 'developer_email' where p_value ->> 'developer_email' is not null) a
       where lower(x) !~ v_email;
      if v_bad is not null then
        raise exception 'setting alerts: not an email address: %', left(v_bad, 200) using errcode = '22023';
      end if;
      if coalesce((p_value #>> '{escalation,resend_min}')::numeric, 30) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,second_contact_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,repeat_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value ->> 'p2_digest_hour_ist')::numeric, 18) not between 0 and 23
         or coalesce((p_value ->> 'p2_digest_min_count')::numeric, 5) not between 0 and 1000
         or coalesce((p_value #>> '{storm,p1_count}')::numeric, 10) not between 2 and 1000
         or coalesce((p_value #>> '{storm,window_min}')::numeric, 5) not between 1 and 120
         or coalesce((p_value #>> '{storm,suppress_min}')::numeric, 15) not between 1 and 240 then
        raise exception 'setting alerts: an escalation, digest or storm number is out of range' using errcode = '22023';
      end if;
    when 'thresholds' then
      select string_agg(key, ', ') into v_bad from jsonb_each(p_value) where jsonb_typeof(value) <> 'number';
      if v_bad is not null then
        raise exception 'setting thresholds: not a number: %', left(v_bad, 200) using errcode = '22023';
      end if;
    when 'checks' then
      if coalesce(p_value ->> 'lock_timeout', '2s') !~ '^[0-9]{1,5}(ms|s)$'
         or coalesce(p_value ->> 'transaction_timeout', '30s') !~ '^[0-9]{1,5}(ms|s|min)$'
         or jsonb_typeof(coalesce(p_value -> 'source_missing_opens_incident', 'true')) <> 'boolean'
         or coalesce((p_value ->> 'slow_ms')::int, 5000) not between 100 and 600000 then
        raise exception 'setting checks: lock_timeout like "2s", transaction_timeout like "30s", a boolean source_missing_opens_incident, slow_ms 100–600000'
          using errcode = '22023';
      end if;
    when 'access' then
      if jsonb_typeof(p_value -> 'owners') is distinct from 'array'
         or exists (select 1 from jsonb_array_elements_text(p_value -> 'owners') x where lower(x) !~ '^[^@\s]+@eduwit\.in$') then
        raise exception 'setting access: owners must be a list of @eduwit.in addresses' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'trusted_days')::int, 30) not between 0 and 90
         or coalesce((p_value ->> 'idle_hours')::int, 12) not between 1 and 72
         or coalesce((p_value ->> 'code_minutes')::int, 10) not between 2 and 30 then
        raise exception 'setting access: trusted_days 0–90, idle_hours 1–72, code_minutes 2–30' using errcode = '22023';
      end if;
    when 'app' then
      if p_value ->> 'base_url' is not null and p_value ->> 'base_url' !~ '^https://[a-z0-9.-]+(:[0-9]+)?$' then
        raise exception 'setting app: base_url must be https://host with no path' using errcode = '22023';
      end if;
    -- The shapes the pages cast or parse (phase review m12): a bad edit must be refused here, not break a page.
    when 'analytics' then
      if jsonb_typeof(p_value -> 'funnel') is distinct from 'array' or jsonb_array_length(p_value -> 'funnel') not between 1 and 20
         or exists (select 1 from jsonb_array_elements(p_value -> 'funnel') s
                     where jsonb_typeof(s) <> 'object' or coalesce(s ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,30}$'
                        or jsonb_typeof(s -> 'label') is distinct from 'string' or length(s ->> 'label') not between 1 and 80
                        or jsonb_typeof(s -> 'match') is distinct from 'array' or jsonb_array_length(s -> 'match') = 0
                        or exists (select 1 from jsonb_array_elements(s -> 'match') m
                                    where jsonb_typeof(m) <> 'object' or jsonb_typeof(m -> 'type') is distinct from 'string'
                                       or (m ? 'app' and jsonb_typeof(m -> 'app') is distinct from 'string')))
         or (select count(distinct s ->> 'key') from jsonb_array_elements(p_value -> 'funnel') s) <> jsonb_array_length(p_value -> 'funnel') then
        raise exception 'setting analytics: funnel is 1 to 20 steps, each {key (a-z_), label, match: [{type, app?}]}, keys unique' using errcode = '22023';
      end if;
    when 'ai' then
      if exists (select 1 from unnest(array['daily_cap_inr', 'per_task_cap_inr', 'queue_non_triage_at_pct', 'usd_inr']) k
                  where p_value ? k and (jsonb_typeof(p_value -> k) <> 'number' or (p_value ->> k)::numeric < 0)) then
        raise exception 'setting ai: daily_cap_inr, per_task_cap_inr, queue_non_triage_at_pct and usd_inr are numbers, 0 or more' using errcode = '22023';
      end if;
      -- The worker reads these on every task (phase 6, D-075): a bad edit is refused here, not found by a failing task.
      -- Claude only (owner, 24 Oct; D-004): there is no provider to choose.
      if p_value ? 'provider'
         or (p_value ? 'effort' and (jsonb_typeof(p_value -> 'effort') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'effort') e where e.key not in ('quick', 'regular', 'deep')
                                                                         or e.value not in ('null', '"low"', '"medium"', '"high"', '"xhigh"', '"max"'))))
         or (p_value ? 'prices' and (jsonb_typeof(p_value -> 'prices') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'prices') e
                        where jsonb_typeof(e.value) not in ('null', 'object')
                           or (jsonb_typeof(e.value) = 'object'
                               and (not (e.value ? 'input' and e.value ? 'output')
                                    or exists (select 1 from jsonb_each(e.value) f
                                                where f.key not in ('input', 'output', 'cache_read', 'cache_write')
                                                   or jsonb_typeof(f.value) <> 'number' or (f.value #>> '{}')::numeric < 0))))))
         or (p_value ? 'queue_non_triage_at_pct' and (p_value ->> 'queue_non_triage_at_pct')::numeric > 100)
         or (p_value ? 'allow_message_excerpts' and jsonb_typeof(p_value -> 'allow_message_excerpts') <> 'boolean')
         or coalesce((p_value ->> 'max_parallel')::numeric, 2) not between 1 and 5
         or coalesce((p_value ->> 'task_max_age_h')::numeric, 48) not between 1 and 720
         or coalesce(p_value #>> '{schedule,brief_mail_at_ist}', '08:00') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         or coalesce((p_value #>> '{schedule,propose_feature_weekday}')::numeric, 1) not between 1 and 7
         or coalesce((p_value #>> '{schedule,explain_after_min}')::numeric, 15) not between 1 and 1440
         or coalesce((p_value #>> '{schedule,propose_fix_after_min}')::numeric, 60) not between 1 and 10080
         -- Routing and models are read by the schedule and every claim (phase 6 review m1).
         or (p_value ? 'usd_inr' and (p_value ->> 'usd_inr')::numeric <= 0)
         or (p_value ? 'routing' and (jsonb_typeof(p_value -> 'routing') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'routing') e where e.value not in ('"quick"', '"regular"', '"deep"'))))
         or (p_value ? 'fallback_when_model_missing' and p_value -> 'fallback_when_model_missing' not in ('null', '"quick"', '"regular"', '"deep"'))
         or (p_value ? 'models' and (jsonb_typeof(p_value -> 'models') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'models') m
                         where m.key not in ('quick', 'regular', 'deep')
                            or (jsonb_typeof(m.value) <> 'null'
                                and (jsonb_typeof(m.value) <> 'string' or (m.value #>> '{}') !~ '^claude-[a-z0-9.-]{1,80}$')))))
         or (p_value ? 'refusal_fallback' and jsonb_typeof(p_value -> 'refusal_fallback') <> 'null'
             and (jsonb_typeof(p_value -> 'refusal_fallback') <> 'string' or (p_value ->> 'refusal_fallback') !~ '^claude-[a-z0-9.-]{1,80}$')) then
        raise exception 'setting ai: Claude only, so no provider; effort per tier null, low, medium, high, xhigh or max; prices per model null or {input, output, cache_read?, cache_write?} in USD per million tokens, 0 or more; queue_non_triage_at_pct at most 100; allow_message_excerpts a boolean; max_parallel 1–5; task_max_age_h 1–720; schedule: brief_mail_at_ist HH:MM, propose_feature_weekday 1–7, explain_after_min 1–1440, propose_fix_after_min 1–10080; usd_inr above 0; routing values quick, regular or deep; fallback_when_model_missing null or a tier; models {tier: a claude-… model or null}; refusal_fallback null or a claude-… model'
          using errcode = '22023';
      end if;
    when 'fixes' then
      if (p_value ? 'observation_days' and (jsonb_typeof(p_value -> 'observation_days') <> 'number' or (p_value ->> 'observation_days')::numeric not between 14 and 90))
         or (jsonb_typeof(p_value -> 'observation_started_at') not in ('null') and coalesce(p_value ->> 'observation_started_at', '')
             !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?)?$') then
        raise exception 'setting fixes: observation_days 14–90 (spec §8: two weeks at least), observation_started_at null or an ISO time' using errcode = '22023';
      end if;
      -- The window's start is set once, by the first tick that runs the fixes; nobody moves it afterwards (phase 7 review m8).
      if (select s.value ->> 'observation_started_at' from one.settings s where s.key = 'fixes') is not null
         and ((p_value ->> 'observation_started_at') is null
              or (p_value ->> 'observation_started_at')::timestamptz <> (select (s.value ->> 'observation_started_at')::timestamptz from one.settings s where s.key = 'fixes')) then
        raise exception 'setting fixes: the observation window started at its first tick and its start cannot change' using errcode = '22023';
      end if;
      -- Each fix: {enabled, per_tick 1–500, cooldown_min 1–1440}. A fix is switched on only on evidence (spec §8):
      -- after the observation window, and once it has at least one dry run.
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key not in ('observation_days', 'observation_started_at')
                    and (f.key !~ '^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$' or jsonb_typeof(f.value) <> 'object'
                         or exists (select 1 from jsonb_object_keys(f.value) k where k not in ('enabled', 'per_tick', 'cooldown_min'))
                         or jsonb_typeof(f.value -> 'enabled') <> 'boolean'
                         or jsonb_typeof(f.value -> 'per_tick') <> 'number' or (f.value ->> 'per_tick')::numeric not between 1 and 500
                         or (f.value ->> 'per_tick')::numeric <> trunc((f.value ->> 'per_tick')::numeric)
                         or jsonb_typeof(f.value -> 'cooldown_min') <> 'number' or (f.value ->> 'cooldown_min')::numeric not between 1 and 1440
                         or (f.value ->> 'cooldown_min')::numeric <> trunc((f.value ->> 'cooldown_min')::numeric))) then
        raise exception 'setting fixes: each FIX-… is {enabled: boolean, per_tick: 1–500, cooldown_min: 1–1440}' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean)
         and (p_value ->> 'observation_started_at' is null
              or (p_value ->> 'observation_started_at')::timestamptz + make_interval(days => coalesce((p_value ->> 'observation_days')::int, 14)) > now()) then
        raise exception 'setting fixes: a fix is switched on only after the observation window ends' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean
                    and not exists (select 1 from one.actions a where a.fix_id = f.key and a.dry_run)) then
        raise exception 'setting fixes: a fix is switched on only once it has a dry run to judge it by' using errcode = '22023';
      end if;
    else
      null;
  end case;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'setting %: a number field holds something else', p_key using errcode = '22023';
end $$;

create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_version integer;
begin
  select value into v_before from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  if p_value = v_before then
    raise exception 'nothing changed: the value is the current version' using errcode = '22023';
  end if;
  v_version := one.settings_put(p_key, p_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, p_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

create or replace function one.ui_view_save(p_page text, p_name text, p_params jsonb, p_schedule text default null,
                                            p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  insert into one.saved_views (page, name, params, schedule, created_by) values (p_page, trim(p_name), coalesce(p_params, '{}'), p_schedule, v_actor)
  on conflict (page, name) do update set params = excluded.params, schedule = excluded.schedule
  returning id into v_id;
  perform one.ui_audit_write(v_actor, 'view.save', 'view:' || v_id, null, jsonb_build_object('page', p_page, 'name', p_name, 'schedule', p_schedule), p_request_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

drop function if exists one.mute(text, text, integer, text, text, text);
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

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor);
begin
  update one.audit set request_id = left(p_request_id, 80) where id = (select max(id) from one.audit where action = 'mute' and actor = v_actor);
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

create or replace function one.redact(p_value jsonb, p_keys text[]) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_out jsonb;
  v_text text;
  v_kind text;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select coalesce(jsonb_object_agg(coalesce('[' || one.has_contact(e.key) || ']', e.key), one.redact(e.value, p_keys)), '{}'::jsonb) into v_out
        from jsonb_each(p_value) e
       where not exists (select 1 from unnest(p_keys) k
                          where lower(e.key) like replace(replace(lower(k), '_', '\_'), '*', '%'));
      return v_out;
    when 'array' then
      select coalesce(jsonb_agg(one.redact(a.value, p_keys) order by a.ord), '[]'::jsonb) into v_out
        from jsonb_array_elements(p_value) with ordinality a(value, ord);
      return v_out;
    when 'string' then
      v_text := p_value #>> '{}';
      -- A JSON document kept as text (a partner reply, a webhook body): redacted as JSON, then stored as text again.
      if v_text ~ '^\s*[\[{]' and length(v_text) <= 20000 then
        begin
          return to_jsonb(one.redact(v_text::jsonb, p_keys)::text);
        exception when invalid_text_representation then
          null;
        end;
      end if;
      v_kind := one.has_contact(v_text);
      if v_kind is not null then
        return to_jsonb('[' || v_kind || ']');
      end if;
      return p_value;
    when 'number' then
      -- A phone stored as a number (S2): 10 digits from 6 (an Indian mobile), or any whole number of 11 to 15 digits
      -- (an international number with its country code). Counts, ids, amounts and epoch seconds stay.
      if p_value::text ~ '^([6-9][0-9]{9}|[0-9]{11,15})$' then
        return '"[phone]"'::jsonb;
      end if;
      return p_value;
    else
      return p_value;
  end case;
end $$;

create or replace function one.fix_plan_within(p_plan jsonb, p_rows jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_rows is null or jsonb_typeof(p_plan -> 'rows') <> 'array' then p_plan
         else p_plan || jsonb_build_object('rows', r.rows, 'count', jsonb_array_length(r.rows),
                                           'applies', jsonb_array_length(r.rows) > 0 or coalesce((p_plan #>> '{target,oldest_pending_old}')::boolean, false))
         end
    from (select coalesce(jsonb_agg(x order by x::text), '[]') as rows from jsonb_array_elements(coalesce(p_plan -> 'rows', '[]')) x
           where coalesce(p_rows, '[]') @> jsonb_build_array(x)) r
$$;

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
    update one.briefs set sent_at = now() where id = v_d.brief_id and sent_at is null;
    return 'sent';
  end if;
  update one.deliveries
     set attempts = attempts + 1, error = left(p_error, 500),
         status = case when attempts + 1 >= 2 then 'failed' else 'pending' end,
         next_attempt_at = now() + interval '2 minutes'
   where id = p_id;
  return case when v_d.attempts + 1 >= 2 then 'failed' else 'retry' end;
end $$;

create or replace function one.watchdog() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'tick_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'app_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:app'),
    'delivery_wait_s', (select round(extract(epoch from now() - min(created_at))) from one.deliveries
                         where status in ('pending', 'sending') and kind in ('alert', 'escalation', 'storm')))
$$;

create or replace function one.due_checks(p_killed boolean default false) returns setof text
language sql stable set search_path = '' as $$
  select c.id from one.checks c left join one.check_state s on s.check_id = c.id
   where c.enabled and c.sql is not null
     and (coalesce(s.killed_count, 0) > 0) = p_killed
     and (s.last_ran_at is null
          or s.last_ran_at < date_trunc('minute', now()) - make_interval(secs => c.cadence_s - 60))
     and (not p_killed or s.last_started_at < now() - make_interval(mins => least(10 * s.killed_count, 60)))
   order by s.last_started_at nulls first, c.id
$$;

create or replace function one.reap_killed() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row record;
  v_checks text[] := '{}';
  v_sources text[] := '{}';
begin
  for v_row in
    select s.check_id, s.killed_count from one.check_state s
     where s.last_started_at > coalesce(s.last_ran_at, '-infinity'::timestamptz)
     order by s.check_id
  loop
    perform one.evaluate(v_row.check_id, 'error', null,
      'killed: the run started and did not finish (transaction_timeout, a cancel or a crash); it now runs after the alert step', null);
    update one.check_state set killed_count = v_row.killed_count + 1 where check_id = v_row.check_id;
    v_checks := v_checks || v_row.check_id;
  end loop;
  update one.event_watermarks set last_status = 'killed', last_error = 'the copy started and did not finish', updated_at = now()
   where last_started_at >= updated_at and last_status is distinct from 'killed';
  select coalesce(array_agg(source order by source), '{}') into v_sources from one.event_watermarks where last_status = 'killed' and updated_at = now();
  return case when cardinality(v_checks) + cardinality(v_sources) = 0 then '{}'::jsonb
              else jsonb_build_object('killed_error', jsonb_build_object('checks', to_jsonb(v_checks), 'sources', to_jsonb(v_sources))) end;
end $$;

create or replace function one.events_due() returns table (source text, app text, sql text)
language sql stable set search_path = '' as $$
  select s.source, s.app, s.sql from one.events_sources() s left join one.event_watermarks w on w.source = s.source
   where w.last_status is distinct from 'killed' or w.last_started_at < now() - interval '10 minutes'
   order by w.last_status = 'killed' nulls first, w.last_started_at nulls first, s.source
$$;

create or replace function one.events_copy(p_source text, p_app text, p_sql text) returns integer
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('events'), '{}');
  v_wm one.event_watermarks;
  v_batch integer := coalesce((v_cfg ->> 'batch')::int, 5000);
  v_overlap bigint := coalesce((v_cfg ->> 'id_overlap')::bigint, 1000);
  v_window interval := make_interval(hours => coalesce((v_cfg ->> 'window_hours')::int, 48));
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(v_cfg -> 'pii_columns')), '{}');
  v_inserted integer;
  v_max_id bigint;
  v_max_at timestamptz;
begin
  -- Nothing is copied without a PII list: an empty or missing one would store names and free text (M4).
  if cardinality(v_pii) = 0 then
    raise exception 'events.pii_columns is missing or empty: nothing is copied without a PII list' using errcode = '22023';
  end if;
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  insert into one.event_watermarks (source) values (p_source) on conflict do nothing;
  select * into v_wm from one.event_watermarks where source = p_source for update;
  execute format($q$
    with src (source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id, wm_at) as (%s),
    ins as (
      insert into one.events (app, source_table, source_id, occurred_at, type, lead_id, actor_type, actor_id, payload)
      select %L, %L, s.source_id, s.occurred_at, s.type, s.lead_id, s.actor_type, s.actor_id, one.redact(coalesce(s.payload, '{}'), $4)
        from src s
       where s.occurred_at is not null
         -- Rows copied before are skipped before they are redacted: the overlap and the state window re-read them (M9).
         and not exists (select 1 from one.events e where e.app = %L and e.source_table = %L and e.source_id = s.source_id)
      on conflict (app, source_table, source_id) do nothing
      returning 1)
    select (select count(*) from ins)::int, (select max(wm_id) from src), (select max(wm_at) from src)$q$, p_sql, p_app, p_source, p_app, p_source)
    into v_inserted, v_max_id, v_max_at
    using greatest(coalesce(v_wm.last_id, 0) - v_overlap, 0), now() - v_window, v_batch, v_pii;
  update one.event_watermarks
     set last_id = greatest(last_id, v_max_id), last_at = greatest(last_at, v_max_at), last_status = 'ok', last_error = null,
         rows_copied = rows_copied + v_inserted, updated_at = now()
   where source = p_source;
  return v_inserted;
exception
  when undefined_table or undefined_function or undefined_column or invalid_schema_name then
    -- The body's writes were rolled back with the error, including the watermark row, so upsert it.
    insert into one.event_watermarks (source, last_status, last_error) values (p_source, 'source_missing', left(sqlerrm, 300))
    on conflict (source) do update set last_status = 'source_missing', last_error = excluded.last_error, updated_at = now();
    return -1;
end $$;

create or replace function one.open_or_touch_incident(p_check_id text, p_severity one.severity, p_evidence jsonb,
                                                      p_subjects text[] default '{}') returns bigint
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_inc one.incidents;
  v_new text[];
  v_escalated boolean;
begin
  select * into strict v_check from one.checks where id = p_check_id;
  select * into v_inc from one.incidents where check_id = p_check_id and resolved_at is null for update;
  if found then
    v_new := array(select x from unnest(coalesce(p_subjects, '{}')) x where not x = any (v_inc.subjects));
    v_escalated := p_severity < v_inc.severity;
    update one.incidents
       set occurrences = occurrences + 1, last_seen_at = now(), evidence = p_evidence,
           severity = least(severity, p_severity)::one.severity,
           subjects = case when cardinality(coalesce(p_subjects, '{}')) > 0 then p_subjects else subjects end,
           acknowledged_at = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_at end,
           acknowledged_by = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_by end
     where id = v_inc.id;
    if v_escalated or cardinality(v_new) > 0 then
      perform one.route_incident(v_inc.id);
    end if;
    return v_inc.id;
  end if;
  -- Reopen, not duplicate, when the same check fails again within 24 h of recovering.
  select * into v_inc from one.incidents
   where check_id = p_check_id and resolved_at > now() - interval '24 hours' and resolution = 'recovered'
   order by resolved_at desc limit 1 for update;
  if found then
    update one.incidents
       set resolved_at = null, resolved_by = null, resolution = null, resolution_note = null,
           reopened_count = reopened_count + 1, occurrences = occurrences + 1, last_seen_at = now(),
           evidence = p_evidence, severity = p_severity, acknowledged_at = null, acknowledged_by = null,
           subjects = coalesce(p_subjects, '{}')
     where id = v_inc.id
     returning * into v_inc;
  else
    insert into one.incidents (check_id, app, severity, title, evidence, first_evidence, tags, subjects)
    values (p_check_id, v_check.app, p_severity, v_check.title, p_evidence, p_evidence, v_check.tags, coalesce(p_subjects, '{}'))
    returning * into v_inc;
  end if;
  perform one.route_incident(v_inc.id);
  return v_inc.id;
end $$;

create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
begin
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 90));
  get diagnostics v_results = row_count;
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 180));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  delete from one.runs where started_at < now() - interval '30 days';
  return jsonb_build_object('results', v_results, 'events', v_events, 'ai_calls', v_calls);
end $$;

create or replace function one.nightly() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:nightly', true, jsonb_build_object('at', now()), null, 90000);
  insert into one.runs (kind, bucket) values ('nightly', v_day::timestamptz) on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran today');
  end if;
  begin v_report := v_report || jsonb_build_object('privileges', one.privilege_audit());
  exception when others then v_report := v_report || jsonb_build_object('privileges_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('baselines', one.capture_baselines());
  exception when others then v_report := v_report || jsonb_build_object('baselines_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('retention', one.retention());
  exception when others then v_report := v_report || jsonb_build_object('retention_error', sqlerrm); end;
  begin
    -- A snooze ends: the proposal is back in the queue with a fresh expiry (the builder's never expire). Before the
    -- expiry step, so the snooze end it kept in expires_at does not expire it at once (phase review M2).
    update one.proposals
       set status = 'open',
           expires_at = case when source = 'builder' then null
                             else now() + make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14)) end
     where status = 'snoozed' and expires_at <= now();
    update one.proposals set status = 'expired' where status = 'open' and expires_at < now();
    v_report := v_report || jsonb_build_object('proposals_expired', true);
  exception when others then v_report := v_report || jsonb_build_object('proposals_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('test_purge', one.purge_test_rows());
  exception when others then v_report := v_report || jsonb_build_object('test_purge_error', sqlerrm); end;
  begin
    perform one.enqueue_ai('brief', jsonb_build_object('for_date', v_day), null, format('brief:%s', v_day));
    v_report := v_report || jsonb_build_object('brief', 'queued');
  exception when others then v_report := v_report || jsonb_build_object('brief_error', sqlerrm); end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
end $$;

create or replace procedure one.fixes_job(inout p_report jsonb default null)
language plpgsql as $$
declare
  v_out jsonb;
  r record;
  v text;
begin
  perform pg_catalog.set_config('search_path', '', false);
  v_out := one.fixes_start_window() || one.fixes_verify_safe();
  commit;
  for r in select * from one.fixes_pairs() loop
    v := one.fix_run_safe(r.fix, r.incident);
    if v not in ('cooldown', 'not applicable') then
      v_out := v_out || jsonb_build_object(r.fix || '#' || r.incident, v);
    end if;
    commit;
  end loop;
  p_report := one.fixes_report(v_out);
end $$;

create or replace procedure one.tick_job()
language plpgsql as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now(), 'mode', 'job');
  v_id text;
  v_src record;
  v_fixes jsonb;
begin
  perform pg_catalog.set_config('search_path', '', false);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', coalesce(one.setting('checks') ->> 'transaction_timeout', '30s'), false);
  end if;
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  commit;
  if not pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('one.tick')) then
    return;
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
    commit;
    return;
  end if;
  v_report := v_report || one.reap_killed();
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_id in select one.due_checks(false) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  v_report := v_report || one.alerts_step();
  update one.runs set report = v_report where id = v_run;
  commit;
  v_report := v_report || one.tick_app_call();
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  commit;
  call one.fixes_job(v_fixes);
  v_report := v_report || coalesce(v_fixes, '{}');
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_src in select * from one.events_due() loop
    perform one.mark_source_started(v_src.source);
    commit;
    v_report := jsonb_set(v_report, '{events}', coalesce(v_report -> 'events', '{}') || one.events_copy_safe(v_src.source, v_src.app, v_src.sql));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  for v_id in select one.due_checks(true) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
  commit;
end $$;

create or replace function one.fix_verify_due() returns jsonb
language plpgsql set search_path = '' as $$
declare
  r one.actions;
  v text;
  v_n integer := 0;
begin
  for r in
    select a.* from one.actions a
     where a.step = 'after' and a.status = 'done' and not a.dry_run and a.verify_at <= now()
       and not exists (select 1 from one.actions v where v.run_key = a.run_key and v.step = 'verify')
     order by a.id limit 50
  loop
    begin
      v := one.fix_verify_one(r);
    exception when others then
      perform one.fix_record(r.fix_id, r.incident_id, 'verify', 'skipped', false, r.target,
                             jsonb_build_object('held', null, 'error', left(sqlerrm, 200)), 'one', r.run_key);
      v := 'error';
    end;
    if v is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('verified', v_n);
end $$;

create or replace function one.app_fixes_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v jsonb;
begin
  for r in
    select a.* from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
       and (a.ran_at <= now() - interval '15 minutes'
            or (a.claimed_at is null and a.proposal_id is null and not coalesce((one.setting('fixes') -> a.fix_id ->> 'enabled')::boolean, false)))
     order by a.id limit 50 for update of a skip locked
  loop
    if r.ran_at > now() - interval '15 minutes' then
      perform one.fix_record(r.fix_id, r.incident_id, 'skip', 'skipped', false, r.target,
                             jsonb_build_object('reason', 'switched off before the app ran it'), 'one', r.run_key);
    else
      perform one.fix_record(r.fix_id, r.incident_id, 'after', 'failed', false, r.target,
                             jsonb_build_object('error', case when r.claimed_at is null then 'the app did not run it within 15 minutes'
                                                              else 'the app claimed it and did not report within 15 minutes: outcome unknown' end,
                                                'unknown', r.claimed_at is not null),
                             'one', r.run_key, null, r.proposal_id);
    end if;
  end loop;
  with c as (
    select a.id from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run and a.ran_at > now() - interval '15 minutes' and a.claimed_at is null
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
     order by a.id limit 10 for update of a skip locked),
  u as (
    update one.actions a set claimed_at = now(), claimed_by = left(p_holder, 120) from c where a.id = c.id
    returning a.id, a.fix_id, a.incident_id, a.target)
  select coalesce(jsonb_agg(jsonb_build_object('action_id', u.id, 'fix_id', u.fix_id, 'incident_id', u.incident_id, 'target', u.target) order by u.id), '[]')
    into v from u;
  return jsonb_build_object('runs', v);
end $$;

create or replace function one.ui_actions(p_fix text default null, p_app text default null, p_day date default null,
                                          p_limit integer default 100, p_before bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]') into v_rows from (
    select a.* from one.actions a
     where (p_fix is null or a.fix_id = p_fix) and (p_app is null or a.app = p_app)
       and (p_day is null or (a.ran_at at time zone 'Asia/Kolkata')::date = p_day) and (p_before is null or a.id < p_before)
     order by a.id desc limit v_limit) a;
  return jsonb_build_object('rows', v_rows, 'fixes', coalesce(one.setting('fixes'), '{}'),
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

create or replace function one.analytics_data(p_days integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_steps jsonb := coalesce(one.setting('analytics') -> 'funnel', '[]');
  v_out jsonb := jsonb_build_object('days', v_days);
  v_ms jsonb := '{}';
  v_t timestamptz := clock_timestamp();
begin
  with steps as (
    select s.ord, s.step ->> 'key' as key, s.step ->> 'label' as label, s.step -> 'match' as match
      from jsonb_array_elements(v_steps) with ordinality s(step, ord)),
  hits as (
    select st.ord, e.lead_id, min(e.occurred_at) as at, count(*) as n
      from steps st join one.events e on e.occurred_at > v_from
       and exists (select 1 from jsonb_array_elements(st.match) m
                    where (m ->> 'app' is null or e.app = m ->> 'app') and e.type like (m ->> 'type'))
     group by st.ord, e.lead_id),
  per_step as (
    select st.ord, st.key, st.label,
           coalesce((select sum(h.n) from hits h where h.ord = st.ord), 0) as events,
           (select count(distinct h.lead_id) from hits h where h.ord = st.ord and h.lead_id is not null) as leads,
           (select round(percentile_cont(0.5) within group (order by extract(epoch from h.at - p.at) / 60)::numeric, 1)
              from hits h join hits p on p.lead_id = h.lead_id and p.ord = st.ord - 1 and h.at >= p.at where h.ord = st.ord) as median_min_from_previous
      from steps st)
  select v_out || jsonb_build_object('funnel', coalesce(jsonb_agg(to_jsonb(p) order by p.ord), '[]')) into v_out from per_step p;
  v_out := v_out || jsonb_build_object('events_by_app', (select coalesce(jsonb_object_agg(app, n), '{}') from (
             select app, count(*) as n from one.events where occurred_at > v_from group by 1) s));
  v_ms := v_ms || jsonb_build_object('funnel', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('partners', (select coalesce(jsonb_agg(jsonb_build_object('partner', coalesce(p.display_name, p.name, a.partner_id::text), 'allocated', a.n,
                                                                                                  'accepted', a.acc, 'enrolled', a.enr, 'lost', a.lost) order by a.n desc), '[]')
      from (select partner_id, count(*) as n, count(accepted_at) as acc, count(*) filter (where outcome = 'enrolled' or stage = 'enrolled') as enr, count(lost_at) as lost
              from b2b.allocations where not coalesce(is_test, false) and created_at > v_from group by 1) a
      left join b2b.partners p on p.id = a.partner_id));
  exception when others then v_out := v_out || jsonb_build_object('partners_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('partners', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('counsellors', (select coalesce(jsonb_agg(jsonb_build_object('counsellor', coalesce(u.full_name, 'unassigned'), 'leads', t.n,
                                                                                                     'contacted', t.c, 'applied', t.a, 'enrolled', t.e,
                                                                                                     'median_first_contact_min', t.m) order by t.n desc), '[]')
      from (select owner_id, count(*) as n, count(contacted_at) as c, count(applied_at) as a, count(enrolled_at) as e,
                   round(percentile_cont(0.5) within group (order by first_contact_minutes)::numeric, 1) as m
              from b2c.fact_leads where not coalesce(is_test, false) and not coalesce(deleted, false) and assigned_at > v_from group by 1) t
      left join b2c.users u on u.user_id = t.owner_id));
  exception when others then v_out := v_out || jsonb_build_object('counsellors_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('counsellors', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  return v_out || jsonb_build_object('ms', v_ms);
end $$;

create or replace function one.ui_fixes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_win jsonb := one.fix_window();
begin
  return jsonb_build_object(
    'window', v_win,
    'fixes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id, 'app', f.app, 'title', f.title, 'checks', to_jsonb(f.checks), 'trigger', f.trigger, 'mode', f.mode,
        'what', f.what, 'grants', f.grants, 'rollback', f.rollback, 'app_functions', to_jsonb(f.app_functions),
        'settings', coalesce(one.setting('fixes') -> f.id, '{}'),
        'grants_state', one.fix_grants(f.id),
        'counts', (select jsonb_build_object('dry_runs', count(*) filter (where a.step = 'dry_run'),
                                             'runs', count(*) filter (where a.step = 'after' and b.id is not null),
                                             'failed', count(*) filter (where a.step = 'after' and b.id is not null and a.status = 'failed'),
                                             'proposals', count(distinct a.proposal_id) filter (where a.step in ('after', 'skip') and b.id is null),
                                             'skipped', count(*) filter (where a.step = 'skip'),
                                             'held', count(*) filter (where a.step = 'verify' and a.status = 'done'),
                                             'escalated', count(*) filter (where a.step = 'verify' and a.status = 'failed'),
                                             'last_at', max(a.ran_at))
                     from one.actions a
                     left join lateral (select x.id from one.actions x where x.run_key = a.run_key and x.step = 'before' limit 1) b on true
                    where a.fix_id = f.id),
        'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
                     from (select * from one.actions where fix_id = f.id order by id desc limit 10) a),
        'open_incidents', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'severity', i.severity, 'title', i.title,
                                                                        'stopped', exists (select 1 from one.actions a where a.fix_id = f.id and a.incident_id = i.id
                                                                                              and a.step = 'verify' and a.status = 'failed'))
                                                     order by i.id), '[]')
                             from one.incidents i where i.check_id = any (f.checks) and i.resolved_at is null),
        'can_enable', not (v_win ->> 'running')::boolean and exists (select 1 from one.actions a where a.fix_id = f.id and a.dry_run))
      order by f.id), '[]') from one.fixes f));
end $$;

create or replace function one.ui_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_day timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  return jsonb_build_object(
    'apps', (select coalesce(jsonb_agg(t order by t.ord, t.key), '[]') from (
      select a.key, a.name, a.enabled, one.app_link(a.key) as link,
             case a.key when 'witty' then 1 when 'b2b' then 2 when 'b2c' then 3 when 'web' then 4 when 'influencer' then 5
                        when 'one' then 6 else 7 end as ord,
             (select jsonb_build_object('P1', count(*) filter (where i.severity = 'P1'), 'P2', count(*) filter (where i.severity = 'P2'),
                                        'P3', count(*) filter (where i.severity = 'P3'))
                from one.incidents i where i.app = a.key and i.resolved_at is null) as open,
             (select max(h.last_ok_at) from one.app_heartbeats() h where h.app = a.key) as last_heartbeat_at,
             (select bool_and(h.ok) from one.app_heartbeats() h where h.app = a.key) as heartbeats_ok,
             (select count(*) from one.events e where e.app = a.key and e.occurred_at >= v_day) as events_today,
             (select count(*) from one.checks c where c.app = a.key and c.enabled) as checks_on,
             (select count(*) from one.checks c where c.app = a.key and not c.enabled and c.disabled_reason like 'setup:%') as checks_waiting_setup
        from one.apps a) t),
    'actions', (select coalesce(jsonb_agg(x order by x.rank, x.at desc), '[]') from (
      select * from (
        select 'incident' as kind, i.id::text as id, i.severity as level, i.title, i.app, i.opened_at as at,
               case i.severity when 'P1' then 0 when 'P2' then 3 else 6 end as rank, '/incidents/' || i.id as href
          from one.incidents i where i.resolved_at is null and i.acknowledged_at is null and i.alert_state <> 'suppressed'
        union all
        select 'proposal', p.id::text, p.risk, p.title, p.app, p.created_at, case p.risk when 'high' then 1 when 'medium' then 4 else 7 end,
               '/proposals/' || p.id
          from one.proposals p where p.status = 'open'
        union all
        select 'test', t.id, t.severity, t.title, t.app, r.started_at, case t.severity when 'P1' then 2 else 5 end, '/tests#' || t.id
          from one.tests t join lateral (select * from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 1) r on true
         where t.enabled and r.ok = false
        union all
        select 'delivery', d.id::text, 'failed', 'An alert email failed: ' || coalesce(i.title, d.kind), coalesce(i.app, 'one'), d.created_at, 2,
               coalesce('/incidents/' || d.incident_id, '/audit')
          from one.deliveries d left join one.incidents i on i.id = d.incident_id
         where d.status = 'failed' and d.created_at > now() - interval '24 hours') u
      order by rank, at desc limit 10) x),
    'brief', (select jsonb_build_object('id', b.id, 'for_date', b.for_date, 'model', b.model, 'excerpt', left(b.body_md, 800))
                from one.briefs b order by b.for_date desc, b.id desc limit 1),
    'ai_today', (select jsonb_build_object('inr', coalesce(sum(cost_inr), 0), 'usd', coalesce(sum(cost_usd), 0), 'calls', count(*),
                                           'cap_inr', (one.setting('ai') ->> 'daily_cap_inr')::numeric)
                   from one.ai_calls where created_at >= v_day));
end $$;

create or replace function one.record_action(p_fix_id text, p_incident_id bigint, p_app text, p_target jsonb,
                                             p_dry_run boolean, p_status text, p_result jsonb, p_by text,
                                             p_idempotency_key text default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into one.actions (fix_id, incident_id, app, target, dry_run, status, result, ran_by, idempotency_key)
  values (p_fix_id, p_incident_id, p_app, coalesce(p_target, '{}'), p_dry_run, p_status, coalesce(p_result, '{}'), p_by, p_idempotency_key)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  return v_id;
end $$;

delete from one.api_grants where fn = 'one.ui_settings_restore(text,integer,text,text)';
drop function if exists one.tick_lock_holder(interval);
drop function if exists one.mask_json(jsonb);
drop function if exists one.mask_text(text);
drop trigger if exists forbid_mutation on one.results;
drop trigger if exists forbid_mutation on one.sign_in_log;
drop trigger if exists forbid_mutation on one.settings_versions;
drop trigger if exists forbid_mutation on one.audit;
drop function if exists one.forbid_mutation();
alter table one.event_watermarks reset (fillfactor);
alter table one.check_state reset (fillfactor);
alter table one.runs reset (fillfactor);
drop index if exists one.events_app_type_time_idx;
drop index if exists one.events_app_time_idx;
drop index if exists one.incidents_opened_idx;
drop index if exists one.audit_target_idx;
drop index if exists one.actions_before_idx;
drop index if exists one.actions_fix_incident_idx;
drop index if exists one.runs_kind_finished_idx;
drop index if exists one.runs_kind_started_idx;
alter table one.event_watermarks drop column if exists killed_count;
alter table one.incidents drop column if exists reopened_at;
drop function if exists one.ui_settings_restore(text, integer, text, text);
-- <<< hardening batch
-- >>> hardening batch 2 (the app token)
create or replace function one.job_call(p_path text, p_timeout_ms integer default 55000) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_base text := one.setting('app') ->> 'base_url';
  v_key text;
begin
  if p_path !~ '^/api/internal/[a-z0-9/-]+$' then
    raise exception 'one.job_call: bad path %', p_path using errcode = '22023';
  end if;
  -- https only: the bearer key must never travel in clear text (m15). A bad value is "not configured", and PLAT-05
  -- reports it.
  if v_base is null or v_base !~ '^https://[^/\s]+$' then
    return null;
  end if;
  v_key := one.secret('one_internal_key');
  if v_key is null then
    return null;
  end if;
  return net.http_post(
    url := v_base || p_path,
    body := '{}'::jsonb,
    headers := jsonb_build_object('content-type', 'application/json', 'authorization', 'Bearer ' || v_key),
    timeout_milliseconds := greatest(1000, least(p_timeout_ms, 300000)));
end $$;

drop function if exists one.hmac_hex(text, text);
-- <<< hardening batch 2
call one.apply_grants();
