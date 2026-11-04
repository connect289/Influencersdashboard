-- Rollback of 0026 AI cost controls: restores 0018's one.ai_schedule() and 0019's one.proposal_execute() and
-- one.ui_proposal_decide() verbatim, drops the merge helper, and removes the seeded proposal while it is still open (a
-- decided one is history and stays). Settings already applied by an approval stay as versions the owner can restore.

delete from one.proposals where source_key = 'builder:d099-ai-explain-tier-and-timings' and status = 'open';

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
begin
  -- Every new incident is classified once (synthetic test incidents never are).
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.opened_at > now() - interval '1 day' and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'classify:' || i.id)
              order by i.id limit 20 loop
    v_n := v_n + (one.enqueue_ai('classify', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'classify:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('classify', v_n);
  -- An explanation for a P1 or P2 still open after explain_after_min, and for every storm.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and (i.check_id = 'ONE-STORM'
                     or (i.severity in ('P1', 'P2') and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'explain_after_min')::int, 15))))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'explain:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('explain', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'explain:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('explain', v_n);
  -- A fix proposal for a P1 or P2 still open after propose_fix_after_min (the deep tier when it is high-risk).
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.severity in ('P1', 'P2') and i.check_id not in ('ONE-SYNTH', 'ONE-STORM')
                and not ('synthetic' = any (i.tags))
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

drop function if exists one.jsonb_deep_merge(jsonb, jsonb);

call one.apply_grants();
