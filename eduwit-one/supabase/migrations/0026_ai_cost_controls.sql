-- 0026 AI cost controls (D-099), on the owner's rule that no use of the AI is switched off without their approval:
--   one.ai_schedule()        four switches in settings ai.schedule, each defaulting to what the schedule did before
--                            (classify_new_incidents true; explain_severities ["P1","P2"]; explain_unacknowledged true;
--                            propose_fix_only_with_catalogue_fix false), so this file changes no behaviour; the owner
--                            turns a use down or off on Settings → AI, a versioned setting.
--   settings proposals       a builder proposal for Eduwit One's own settings carries change.settings_patch; the
--                            owner's approval on the Proposals page applies it through one.settings_put (versioned,
--                            restorable, audited) instead of recording a decision someone then types in by hand.
--   one proposal seeded      "AI: explain on the regular tier, after 60 minutes; fix proposals after 180 minutes"
--                            (the audit docs/reviews/ai-usage-audit.md: the Opus explanations of unacknowledged set-up
--                            gaps were the main projected cost). Nothing applies until the owner approves it.

-- Objects merged recursively, the second winning on a key; arrays and scalars are replaced whole.
create or replace function one.jsonb_deep_merge(a jsonb, b jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
begin
  if jsonb_typeof(a) = 'object' and jsonb_typeof(b) = 'object' then
    return coalesce((select jsonb_object_agg(k, case when a ? k and b ? k then one.jsonb_deep_merge(a -> k, b -> k)
                                                     when b ? k then b -> k else a -> k end)
                       from (select jsonb_object_keys(a) as k union select jsonb_object_keys(b)) keys), '{}'::jsonb);
  end if;
  return b;
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

create or replace function one.proposal_execute(p_id bigint, p_actor text, p_rows jsonb, p_actor_id uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare
  p one.proposals;
  v_x jsonb;
  v_res jsonb;
begin
  select * into p from one.proposals where id = p_id for update;
  -- A builder proposal for Eduwit One's own settings (0026, D-099): change.settings_patch = {key: patch}, each patch
  -- merged into the current value and saved through one.settings_put under the approver's name and the proposal's
  -- number, so the Settings page shows the version and can restore the one before. Keys the owner alone may change
  -- are the owner's here too (ui_proposal_decide asked for the owner before calling, through proposal_sensitive).
  if p.source = 'builder' and p.app = 'one' and jsonb_typeof(p.change -> 'settings_patch') = 'object' then
    declare
      k record;
      v_applied jsonb := '{}';
      v_cur jsonb;
    begin
      for k in select key, value from jsonb_each(p.change -> 'settings_patch') loop
        if k.key in ('setup', 'setup_catalog') or jsonb_typeof(k.value) <> 'object' then
          raise exception 'a settings proposal cannot change %', k.key using errcode = '22023';
        end if;
        select value into v_cur from one.settings where key = k.key;
        if v_cur is null then
          raise exception 'no setting %', k.key using errcode = 'P0002';
        end if;
        v_applied := v_applied || jsonb_build_object(k.key,
                       one.settings_put(k.key, one.jsonb_deep_merge(v_cur, k.value), p_actor, format('proposal #%s approved: %s', p_id, left(p.title, 120))));
      end loop;
      update one.proposals set status = 'applied', applied_at = now(), check_due_at = null,
                               check_result = jsonb_build_object('ran', true, 'ok', true, 'checked_at', now(), 'versions', v_applied)
       where id = p_id;
      return jsonb_build_object('executed', true, 'settings', v_applied);
    end;
  end if;
  v_x := p.change -> 'execute';
  if p.source <> 'check' or p.source_key not like 'fix:%' or v_x is null
     or p.source_key not like format('fix:%s:%s:%%', v_x ->> 'fix', v_x ->> 'incident') then
    return jsonb_build_object('executed', false, 'why', 'nothing to run: this proposal records a decision');
  end if;
  v_res := one.fix_run(v_x ->> 'fix', (v_x ->> 'incident')::bigint, false, p_actor, p_id, coalesce(p_rows, '[]'), p_actor_id);
  if coalesce(v_res ->> 'status', '') = 'done' or v_res ? 'queued_for_app' then
    update one.proposals set status = 'applied', applied_at = now(), check_due_at = now() + interval '10 minutes', check_result = null where id = p_id;
  else
    update one.proposals set check_result = jsonb_build_object('ran', false, 'ok', false, 'checked_at', now(),
                                                               'why', coalesce(v_res ->> 'why_not', v_res ->> 'skipped', 'the run failed'),
                                                               'result', v_res -> 'result')
     where id = p_id;
  end if;
  return jsonb_build_object('executed', true) || v_res;
end $$;

create or replace function one.ui_proposal_decide(p_id bigint, p_decision text, p_note text default null, p_change jsonb default null,
                                                  p_snooze_days integer default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_p one.proposals;
  v_change jsonb;
  v_rows jsonb;
  v_exec jsonb;
begin
  select * into v_p from one.proposals where id = p_id for update;
  if not found or v_p.status not in ('open', 'snoozed') then
    raise exception 'proposal % is not open', p_id using errcode = 'P0002';
  end if;
  case p_decision
    when 'approve' then
      v_change := coalesce(p_change, v_p.change);
      if one.proposal_sensitive(v_p.kind, v_p.change) or one.proposal_sensitive(v_p.kind, v_change) then
        perform one.ui_require('owner');
      end if;
      if v_p.source = 'check' and v_p.change ? 'execute' then
        select coalesce(jsonb_agg(x order by x::text), '[]') into v_rows
          from jsonb_array_elements(coalesce(v_p.change #> '{execute,rows}', '[]')) x
         where jsonb_typeof(v_change #> '{execute,rows}') <> 'array' or (v_change #> '{execute,rows}') @> jsonb_build_array(x);
        update one.proposals
           set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000), check_due_at = null,
               change = v_p.change || jsonb_build_object('approved_rows', v_rows)
                        || case when v_change is distinct from v_p.change then jsonb_build_object('approved_change', v_change) else '{}' end
         where id = p_id;
        v_exec := one.proposal_execute(p_id, v_actor, v_rows, one.uid());
      elsif v_p.source = 'builder' and v_p.app = 'one' and jsonb_typeof(v_p.change -> 'settings_patch') = 'object' then
        -- The owner's approval applies Eduwit One's own settings change (0026, D-099): the proposal's patch, never an
        -- edited one, so what was approved is what the Proposals page showed.
        update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000), check_due_at = null
         where id = p_id;
        v_exec := one.proposal_execute(p_id, v_actor, null, one.uid());
      else
        update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000),
                                 change = v_change, check_due_at = null
         where id = p_id;
      end if;
    when 'reject' then
      update one.proposals set status = 'rejected', decided_by = v_actor, decided_at = now(), decision_note = one.ui_reason(p_note) where id = p_id;
    when 'snooze' then
      if coalesce(p_snooze_days, 0) not between 1 and 30 then
        raise exception 'snooze for 1 to 30 days' using errcode = '22023';
      end if;
      update one.proposals set status = 'snoozed', decision_note = left(p_note, 1000), expires_at = now() + make_interval(days => p_snooze_days)
       where id = p_id;
    else
      raise exception 'decision must be approve, reject or snooze' using errcode = '22023';
  end case;
  perform one.ui_audit_write(v_actor, 'proposal.' || p_decision, 'proposal:' || p_id,
                             jsonb_build_object('status', v_p.status, 'change', v_p.change),
                             jsonb_build_object('note', p_note, 'change', v_change, 'snooze_days', p_snooze_days, 'executed', v_exec), p_request_id);
  return jsonb_build_object('ok', true, 'executed', v_exec);
end $$;


-- The audit's one settings change that keeps every use of the AI (D-099): a different tier and later timings. Approving
-- it on the Proposals page applies it; rejecting it leaves today's values.
insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key)
values ('config', 'one', 'AI: explain incidents on the regular tier after 60 minutes; propose fixes after 180 minutes',
        'The AI usage audit of 29 Oct 2026 (docs/reviews/ai-usage-audit.md) projected about ₹150 a day once the Anthropic key is saved, at today''s rate of about 44 AI tasks a day, and about half of it on Opus ("deep") explanations of incidents that nobody has acknowledged, most of them set-up gaps the check already names. This change keeps every AI task but asks for explanations on Sonnet ("regular", 2 to 4 times cheaper) after an hour instead of 15 minutes, and for fix proposals after three hours instead of one, so incidents that resolve themselves or are acknowledged first cost nothing. Projected: about ₹70 a day instead of ₹150. Switching a task off altogether (classification, explanations of P2s or of unacknowledged incidents, proposals for checks without a catalogue fix) is a separate decision: the switches exist in Settings → AI → schedule and default to on.',
        '{"measured_at": "2026-10-29", "tasks_queued_6_days": {"classify": 58, "triage": 95, "explain": 53, "propose_fix": 50, "brief": 5, "propose_feature": 1}, "incidents_open_unacknowledged": 11, "projected_inr_per_day": {"before": 150, "after": 70}, "audit": "docs/reviews/ai-usage-audit.md", "decision": "D-099"}',
        '{"where": "Eduwit One: Settings → AI", "settings_patch": {"ai": {"routing": {"explain": "regular"}, "schedule": {"explain_after_min": 60, "propose_fix_after_min": 180}}}, "touches": ["versioned_settings"], "owner_action": "Approve to apply; reject to keep today''s values. Both are versioned on Settings → AI and can be restored."}',
        'low', 'builder', 'builder:d099-ai-explain-tier-and-timings')
on conflict (source_key) do nothing;

call one.apply_grants();
