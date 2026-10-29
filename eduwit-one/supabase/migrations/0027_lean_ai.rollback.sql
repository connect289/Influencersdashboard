-- Rollback of 0027 lean AI: restores 0026's one.ai_schedule() and 0003's one.route_incident() verbatim; puts the ai
-- setting back to the version before 0027's seed when that seed is still the latest version (a later edit by a person
-- stays); reopens the D-099 proposal if 0027 closed it. Tasks 0027 cancelled stay cancelled (history; the schedule
-- queues new ones).

do $$
declare
  v_row one.settings;
  v_prev one.settings_versions;
begin
  select * into v_row from one.settings where key = 'ai';
  if found and v_row.actor = 'seed'
     and exists (select 1 from one.settings_versions where key = 'ai' and version = v_row.version and reason like 'D-101 (0027)%') then
    select * into v_prev from one.settings_versions where key = 'ai' and version = v_row.version - 1;
    if found then
      perform one.settings_put('ai', v_prev.value, 'seed', 'rollback of 0027: the version before D-101');
    end if;
  end if;
  update one.proposals
     set status = 'open', decided_by = null, decided_at = null, applied_at = null, decision_note = null, check_result = null
   where source_key = 'builder:d099-ai-explain-tier-and-timings' and status = 'applied' and decision_note like 'applied by migration 0027%';
end $$;

create or replace function one.ai_schedule() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_s jsonb := coalesce(one.setting('ai') -> 'schedule', '{}');
  v_local timestamp := now() at time zone 'Asia/Kolkata';
  v_week text := to_char(now() at time zone 'Asia/Kolkata', 'IYYY-"W"IW');
  v_out jsonb := '{}';
  v_n integer;
  v_i one.incidents;
  -- The cost switches (0026, D-099): each defaults to what the schedule did before, so adding them changed nothing; the
  -- owner turns a use down or off in Settings → AI → schedule (a versioned setting).
  v_classify boolean := coalesce((v_s ->> 'classify_new_incidents')::boolean, true);
  v_explain_sev text[] := case when jsonb_typeof(v_s -> 'explain_severities') = 'array'
                               then array(select x from jsonb_array_elements_text(v_s -> 'explain_severities') x where x in ('P1', 'P2'))
                               else array['P1', 'P2'] end;
  v_explain_unacked boolean := coalesce((v_s ->> 'explain_unacknowledged')::boolean, true);
  v_fix_only_catalogue boolean := coalesce((v_s ->> 'propose_fix_only_with_catalogue_fix')::boolean, false);
begin
  -- Every new incident is classified once (synthetic test incidents never are), while schedule.classify_new_incidents is on.
  v_n := 0;
  if v_classify then
    for v_i in select * from one.incidents i
                where i.opened_at > now() - interval '1 day' and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                  and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'classify:' || i.id)
                order by i.id limit 20 loop
      v_n := v_n + (one.enqueue_ai('classify', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'classify:' || v_i.id, v_i.id) is not null)::int;
    end loop;
  end if;
  v_out := v_out || jsonb_build_object('classify', v_n);
  -- An explanation for an incident of a severity in schedule.explain_severities (P1 and P2 by default) still open after
  -- explain_after_min, and for every storm; with schedule.explain_unacknowledged off, only once a person acknowledged it.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and (i.check_id = 'ONE-STORM'
                     or (i.severity::text = any (v_explain_sev) and (v_explain_unacked or i.acknowledged_at is not null)
                         and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'explain_after_min')::int, 15))))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'explain:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('explain', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'explain:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('explain', v_n);
  -- A fix proposal for a P1 or P2 still open after propose_fix_after_min (the deep tier when it is high-risk); with
  -- schedule.propose_fix_only_with_catalogue_fix on, only for a check some fix in the catalogue is tried on.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.severity in ('P1', 'P2') and i.check_id not in ('ONE-SYNTH', 'ONE-STORM')
                and not ('synthetic' = any (i.tags))
                and (not v_fix_only_catalogue or exists (select 1 from one.fixes f where i.check_id = any (f.checks)))
                and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'propose_fix_after_min')::int, 60))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'propose_fix:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('propose_fix', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id),
                                 case when one.ai_high_risk(v_i) then v_ai #>> '{routing,propose_fix_high_risk}' end,
                                 'propose_fix:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('propose_fix', v_n);
  -- A test idea for each incident resolved as fixed in the last day.
  v_n := 0;
  if coalesce((v_s ->> 'test_author_on_fixed')::boolean, true) then
    for v_i in select * from one.incidents i
                where i.resolution = 'fixed' and i.resolved_at > now() - interval '1 day' and i.check_id <> 'ONE-SYNTH'
                  and not ('synthetic' = any (i.tags))
                  and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'test_author:' || i.id)
                order by i.id limit 5 loop
      v_n := v_n + (one.enqueue_ai('test_author', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'test_author:' || v_i.id, v_i.id) is not null)::int;
    end loop;
  end if;
  v_out := v_out || jsonb_build_object('test_author', v_n);
  -- The weekly feature review, on propose_feature_weekday (ISO, 1 = Monday) after 03:00 IST.
  if extract(isodow from v_local) = coalesce((v_s ->> 'propose_feature_weekday')::int, 1) and v_local::time >= time '03:00' then
    v_out := v_out || jsonb_build_object('propose_feature',
               (one.enqueue_ai('propose_feature', jsonb_build_object('week', v_week), null, 'propose_feature:' || v_week, null) is not null)::int);
  end if;
  return v_out;
end $$;

-- Routes an incident each time it needs a person's attention again: opened, reopened, made more severe, or joined by
-- a new subject. P1 alerts now, P2 waits for the digest, P3 is dashboard only; a muted check or app records but does
-- not deliver. While an alert storm is open (ONE-STORM, routed in the last storm.suppress_min minutes), other P1s are
-- suppressed and filed under it; the storm itself alerts once and suppresses the P1s that opened with it (spec §9).
-- Each routing bumps alert_seq and gets one AI triage task, on the deep model for a storm.
create or replace function one.route_incident(p_incident_id bigint) returns void
language plpgsql set search_path = '' as $$
declare
  v_inc one.incidents;
  v_storm jsonb := coalesce(one.setting('alerts') -> 'storm', '{}');
  v_storm_id bigint;
  v_state text;
begin
  update one.incidents set alert_seq = alert_seq + 1, routed_at = now() where id = p_incident_id returning * into v_inc;
  select id into v_storm_id from one.incidents
   where check_id = 'ONE-STORM' and resolved_at is null and id <> v_inc.id
     and routed_at > now() - make_interval(mins => coalesce((v_storm ->> 'suppress_min')::int, 15));
  v_state := case
    when one.is_muted(v_inc.check_id, v_inc.app) then 'muted'
    when v_inc.severity = 'P1' and v_storm_id is not null then 'suppressed'
    when v_inc.severity = 'P1' then 'pending'
    when v_inc.severity = 'P2' then 'digest'
    else 'none' end;
  update one.incidents set alert_state = v_state, parent_id = coalesce(case when v_state = 'suppressed' then v_storm_id end, parent_id)
   where id = v_inc.id;
  if v_inc.check_id = 'ONE-STORM' then
    update one.incidents set alert_state = 'suppressed', parent_id = v_inc.id
     where severity = 'P1' and resolved_at is null and id <> v_inc.id and alert_state = 'pending'
       and routed_at > now() - make_interval(mins => coalesce((v_storm ->> 'window_min')::int, 5));
  end if;
  if v_state = 'pending' then
    perform one.enqueue_alert(v_inc.id, 0);
  end if;
  if v_state not in ('muted', 'suppressed') and 'code' = any (v_inc.tags) then
    perform one.enqueue_developer(v_inc.id);
  end if;
  perform one.enqueue_ai('triage', jsonb_build_object('incident_id', v_inc.id, 'check_id', v_inc.check_id, 'subjects', to_jsonb(v_inc.subjects)),
                         case when v_inc.check_id = 'ONE-STORM' then 'deep' end, format('triage:%s:%s', v_inc.id, v_inc.alert_seq), v_inc.id);
end $$;

call one.apply_grants();
