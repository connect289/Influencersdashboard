-- 0027 lean AI (D-101). The owner, 29 Oct 2026: "Remove all unnecessary use of AI or AI api from Eduwit One." The AI
-- usage audit (docs/reviews/ai-usage-audit.md, §6) had named them, and 0026 had given each a switch defaulting to the
-- old behaviour; this migration turns the defaults lean and keeps every switch, so the owner turns a use back on in
-- Settings → AI → schedule. What changes:
--   1. one.ai_schedule(): no classification unless classify_new_incidents is true; an explanation only for a P1 (or any
--      P1/P2 a person acknowledged, or a storm), after explain_after_min as before (15, on the deep tier as before: what
--      remains keeps its quality and timing, the owner's "nothing important changes"); a fix proposal only when some fix
--      in the catalogue is tried on the check (1440 minutes after it opened) or a person acknowledged the incident
--      (after explain_after_min, so a person who engages is helped at once).
--   2. one.route_incident(): one triage per incident per triage_min_gap_h (24) hours, unless its severity rose; a
--      routing for a new subject or a passed storm re-uses the triage it has.
--   3. The ai setting: propose_fix_after_min 1440 and the switches written out, as a seed version, only while the row is
--      still the seed's (a person's edit wins, settings_put's rule). The D-099 proposal (the cheaper explanation tier
--      after 60 minutes) stays open for the owner, narrowed to that: its fix-proposal timing is now the default.
--   4. The tasks waiting for a key that these defaults would never queue are cancelled, so the first day with a key
--      does not spend on them.
-- Nothing of the five apps is touched; only schema one. Rollback: 0027_lean_ai.rollback.sql.

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
  -- The cost switches (0026, D-099), lean by default since 0027 (D-101, the owner's instruction of 29 Oct 2026): a use
  -- comes back when the owner sets its switch in Settings → AI → schedule (a versioned setting).
  v_classify boolean := coalesce((v_s ->> 'classify_new_incidents')::boolean, false);
  v_explain_sev text[] := case when jsonb_typeof(v_s -> 'explain_severities') = 'array'
                               then array(select x from jsonb_array_elements_text(v_s -> 'explain_severities') x where x in ('P1', 'P2'))
                               else array['P1'] end;
  v_explain_unacked boolean := coalesce((v_s ->> 'explain_unacknowledged')::boolean, true);
  v_fix_only_catalogue boolean := coalesce((v_s ->> 'propose_fix_only_with_catalogue_fix')::boolean, true);
begin
  -- A classification for every new incident (synthetic test incidents never), only while schedule.classify_new_incidents is on.
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
  -- An explanation for a P1 or P2 still open after explain_after_min (15) when its severity is in
  -- schedule.explain_severities (P1 by default; with explain_unacknowledged off, only once a person acknowledged it) or a
  -- person acknowledged it whatever its severity; and for every storm.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and (i.check_id = 'ONE-STORM'
                     or (i.severity in ('P1', 'P2')
                         and ((i.severity::text = any (v_explain_sev) and (v_explain_unacked or i.acknowledged_at is not null))
                              or i.acknowledged_at is not null)
                         and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'explain_after_min')::int, 15))))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'explain:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('explain', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'explain:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('explain', v_n);
  -- A fix proposal for a P1 or P2 (the deep tier when it is high-risk): once a person acknowledged it, after
  -- explain_after_min; otherwise after propose_fix_after_min (1440) and only when some fix in the catalogue is tried on
  -- its check, unless propose_fix_only_with_catalogue_fix is off.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.severity in ('P1', 'P2') and i.check_id not in ('ONE-SYNTH', 'ONE-STORM')
                and not ('synthetic' = any (i.tags))
                and (case when i.acknowledged_at is not null
                          then i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'explain_after_min')::int, 15))
                          when not v_fix_only_catalogue or exists (select 1 from one.fixes f where i.check_id = any (f.checks))
                          then i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'propose_fix_after_min')::int, 1440))
                          else false end)
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
-- Each routing bumps alert_seq. It gets an AI triage task (on the deep model for a storm) unless the incident was
-- triaged in the last schedule.triage_min_gap_h hours (24; 0 means every routing) at a severity no lower than now:
-- a routing for a new subject, or after a storm passed, keeps the summary it has; a rise in severity gets a new one
-- (0027, D-101; audit finding 4).
create or replace function one.route_incident(p_incident_id bigint) returns void
language plpgsql set search_path = '' as $$
declare
  v_inc one.incidents;
  v_storm jsonb := coalesce(one.setting('alerts') -> 'storm', '{}');
  v_storm_id bigint;
  v_state text;
  v_gap_raw text := one.setting('ai') #>> '{schedule,triage_min_gap_h}';
  v_gap numeric := case when v_gap_raw ~ '^[0-9]{1,3}(\.[0-9]+)?$' then least(v_gap_raw::numeric, 168) else 24 end;
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
  if v_gap <= 0 or not exists (
       select 1 from one.ai_tasks t
        where t.incident_id = v_inc.id and t.kind = 'triage' and t.status <> 'failed'
          and t.created_at > now() - v_gap * interval '1 hour'
          -- A triage without a severity in its input (before 0027, or asked for by a person) counts as one at today's.
          and coalesce((t.input ->> 'severity')::one.severity, v_inc.severity) <= v_inc.severity) then
    perform one.enqueue_ai('triage', jsonb_build_object('incident_id', v_inc.id, 'check_id', v_inc.check_id, 'subjects', to_jsonb(v_inc.subjects),
                                                        'severity', v_inc.severity),
                           case when v_inc.check_id = 'ONE-STORM' then 'deep' end, format('triage:%s:%s', v_inc.id, v_inc.alert_seq), v_inc.id);
  end if;
end $$;

-- 3. The setting, as a seed version while the row is still the seed's; the D-099 proposal narrowed and left open.
do $$
declare
  v_row one.settings;
  v_patch jsonb := '{"schedule": {"propose_fix_after_min": 1440, "classify_new_incidents": false,
                                  "explain_severities": ["P1"], "explain_unacknowledged": true,
                                  "propose_fix_only_with_catalogue_fix": true, "triage_min_gap_h": 24}}';
begin
  select * into v_row from one.settings where key = 'ai';
  if not found then
    raise exception '0027: no ai setting; 0007 must be applied first';
  end if;
  if v_row.actor <> 'seed' then
    raise notice '0027: Settings → AI was changed by % (version %), so it is left as it is (D-101); the owner sets the lean values there', v_row.actor, v_row.version;
  else
    perform one.settings_put('ai', one.jsonb_deep_merge(v_row.value, v_patch), 'seed',
                             'D-101 (0027): the AI usage audit''s lean defaults, on the owner''s instruction of 29 Oct 2026');
  end if;
  -- The D-099 proposal offered a cheaper explanation tier and later timings for both explanations and fix proposals. The
  -- fix-proposal timing is the default now, so the proposal is narrowed to the explanations (tier and 60 minutes), which
  -- stay as they were until the owner decides it on the Proposals page.
  update one.proposals
     set title = 'AI: explain incidents on the regular tier after 60 minutes',
         change = jsonb_set(change, '{settings_patch,ai,schedule}', '{"explain_after_min": 60}'),
         rationale = rationale || ' Narrowed by migration 0027 (D-101): fix proposals wait 1440 minutes by default now, so this proposal offers only the explanation tier and timing; the first explanations in Audit → AI calls will show whether the regular tier is enough.'
   where source_key = 'builder:d099-ai-explain-tier-and-timings' and status in ('open', 'snoozed')
     and change #> '{settings_patch,ai,schedule}' ? 'propose_fix_after_min';
end $$;

-- 4. Waiting tasks these defaults would never queue: cancelled, with the reason, so a key saved tomorrow does not pay
-- for them. Done or claimed tasks are history and stay.
update one.ai_tasks t
   set status = 'cancelled', error = 'cancelled by 0027 (D-101): classification is off unless schedule.classify_new_incidents is on'
 where t.kind = 'classify' and t.status in ('pending', 'deferred');
update one.ai_tasks t
   set status = 'cancelled', error = 'cancelled by 0027 (D-101): a P2 nobody acknowledged is not explained unless schedule.explain_severities names P2'
  from one.incidents i
 where i.id = t.incident_id and t.kind = 'explain' and t.status in ('pending', 'deferred')
   and i.severity <> 'P1' and i.acknowledged_at is null and i.check_id <> 'ONE-STORM';
update one.ai_tasks t
   set status = 'cancelled', error = 'cancelled by 0027 (D-101): no fix in the catalogue for this check and nobody acknowledged the incident'
  from one.incidents i
 where i.id = t.incident_id and t.kind = 'propose_fix' and t.status in ('pending', 'deferred')
   and i.acknowledged_at is null and not exists (select 1 from one.fixes f where i.check_id = any (f.checks));
update one.ai_tasks t
   set status = 'cancelled', error = 'cancelled by 0027 (D-101): a newer triage of the same incident is waiting'
 where t.kind = 'triage' and t.status in ('pending', 'deferred')
   and exists (select 1 from one.ai_tasks n where n.incident_id = t.incident_id and n.kind = 'triage' and n.status in ('pending', 'deferred') and n.id > t.id);

call one.apply_grants();
