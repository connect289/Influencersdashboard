-- B2C CRM b9: every hand-off to the internal sales team is recorded in the B2B CRM, like a hand-off to a partner.
--   (Vikas, 14 Oct: "every lead passed to the partner or the internal sales team in the B2C CRM is recorded in the B2B CRM,
--   the same as leads passed to partners by the B2B CRM".)
--   Partners: the B2C CRM never sends a lead to a partner itself. route_to_partners() asks the B2B engine
--     (POST /v1/leads/{id}/route-to-partners), which records the allocation as it does for its own; nothing changes there.
--   Internal sales team: each counsellor assignment (b2c.assignments) now goes to the B2B CRM at once (urgent outbox, sent
--     within a minute) as b2ccrm.lead_assigned, and its end as b2ccrm.assignment_ended. The B2B CRM records them in its
--     allocation ledger (Addendum 4 §4a). A trigger on b2c.assignments does it, so no path can skip it.
--   Also closes the assignment when a lead leaves B2C (close_lead) or when nobody can take it after reassignment (allocate).

create or replace function b2c.assignment_payload(a b2c.assignments) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_strip_nulls(jsonb_build_object(
    'assignment_id', a.id,
    'assigned_at', a.at,
    'trigger', a.trigger,
    'reason', a.reason,
    'counsellor', jsonb_build_object('id', u.user_id, 'email', u.email, 'name', u.full_name, 'role', u.role, 'is_test_user', u.is_test_user),
    'assigned_by', case when a.by_user is not null then (select jsonb_build_object('id', b.user_id, 'email', b.email, 'name', b.full_name) from b2c.users b where b.user_id = a.by_user) end,
    'decision', case when d.id is not null then jsonb_build_object('id', d.id, 'rule', d.rule_name, 'logic', d.logic, 'pool', d.pool, 'outcome', d.outcome,
                                                                  'why', d.why, 'hot', d.hot, 'skipped', d.skipped) end,
    'replaces_assignment_id', (select p.id from b2c.assignments p where p.lead_id = a.lead_id and p.id < a.id order by p.id desc limit 1),
    'b2b_allocation_id', r.record -> 'allocation' -> 'allocation_id',
    'reference', r.record -> 'allocation' ->> 'reference',
    'lane', s.lane,
    'handoff_reason', s.handoff_reason,
    'is_test', coalesce(s.is_test, false) or coalesce(r.is_test, false)))
  from b2c.users u
  left join b2c.allocation_decisions d on d.id = a.decision_id
  left join b2c.leads_state s on s.lead_id = a.lead_id
  left join b2c.lead_records r on r.lead_id = a.lead_id
  where u.user_id = a.user_id
$f$;

create or replace function b2c.assignment_to_b2b() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if tg_op = 'INSERT' then
    perform b2c.queue_event('b2ccrm.lead_assigned', new.lead_id, b2c.assignment_payload(new), true);
  elsif old.ended_at is null and new.ended_at is not null then
    perform b2c.queue_event('b2ccrm.assignment_ended', new.lead_id,
      jsonb_build_object('assignment_id', new.id, 'ended_at', new.ended_at, 'end_reason', new.end_reason,
                         'counsellor', (select jsonb_build_object('id', u.user_id, 'email', u.email, 'name', u.full_name) from b2c.users u where u.user_id = new.user_id)),
      true);
  end if;
  return null;
end $f$;

do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'assignments_to_b2b') then
    create trigger assignments_to_b2b after insert or update of ended_at on b2c.assignments for each row execute function b2c.assignment_to_b2b();
  end if;
end $d$;

create or replace function b2c.close_lead(p_lead bigint, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.leads_state set status = p_status, closed_at = case when p_status = 'closed' then now() else closed_at end,
         closed_reason = p_reason, journey = null, updated_at = now()
   where lead_id = p_lead;
  update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'cancelled: ' || p_reason
   where lead_id = p_lead and status = 'open';
  update b2c.assignments set ended_at = now(), end_reason = p_reason where lead_id = p_lead and ended_at is null;
end $f$;

create or replace function b2c.allocate(p_lead bigint, p_trigger text, p_exclude uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare s b2c.leads_state; d jsonb; v_id bigint; v_creator uuid;
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null or s.deleted_at is not null or s.status = 'closed' then return jsonb_build_object('outcome', 'skipped'); end if;
  if s.owner_id is not null and p_exclude is null and p_trigger not in ('reassign', 'hand_back')
     and exists (select 1 from b2c.users u where u.user_id = s.owner_id and u.is_active) then
    insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, s.owner_id, 'kept', 'already with an active counsellor')
    returning id into v_id;
    if p_trigger = 'returned_from_partners' then
      perform b2c.assign(p_lead, s.owner_id, v_id, p_trigger, 'no partner took it');
    else
      perform b2c.notify(s.owner_id, 'reenquiry', 'Your lead came back', p_trigger, '/s/leads/' || p_lead, p_lead, 'kept:' || v_id);
    end if;
    return jsonb_build_object('outcome', 'kept', 'chosen', s.owner_id, 'decision_id', v_id);
  end if;
  -- B4.3: a lead created in B2C goes to the person who created it (the Intake answer names the lead; wait up to 2 minutes for it)
  if s.handoff_reason = 'b2c_created' and p_exclude is null and p_trigger in ('handoff', 'retry') then
    select c.user_id into v_creator from b2c.created_leads c join b2c.users u on u.user_id = c.user_id and u.is_active
     where c.lead_id = p_lead order by c.created_at desc limit 1;
    if v_creator is not null then
      insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, v_creator, 'assigned', 'created by this counsellor')
      returning id into v_id;
      perform b2c.assign(p_lead, v_creator, v_id, 'created', 'created by them');
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_creator, 'decision_id', v_id, 'why', 'created by this counsellor');
    elsif s.handed_off_at > now() - interval '2 minutes' then
      return jsonb_build_object('outcome', 'skipped', 'why', 'waiting for the creating counsellor');
    end if;
  end if;
  d := b2c.decide(p_lead, p_trigger, now(), p_exclude, false);
  insert into b2c.allocation_decisions (lead_id, trigger, hot, facts, rule_id, rule_name, logic, pool, eligible, skipped, chosen, turn, outcome, why)
  values (p_lead, p_trigger, coalesce((d ->> 'hot')::boolean, false), coalesce(d -> 'facts', '{}'), (d ->> 'rule_id')::bigint, d ->> 'rule_name', d ->> 'logic',
          d ->> 'pool', coalesce(d -> 'eligible', '[]'), coalesce(d -> 'skipped', '[]'), (d ->> 'chosen')::uuid, (d ->> 'turn')::int, d ->> 'outcome',
          coalesce(d ->> 'why', (select string_agg(t ->> 'rule' || ': ' || coalesce(t ->> 'why', 'nobody eligible'), '; ') from jsonb_array_elements(d -> 'tried') t)))
  returning id into v_id;
  if d ->> 'outcome' = 'assigned' then
    if d ->> 'turn' is not null then update b2c.allocation_rules set turn = (d ->> 'turn')::int where id = (d ->> 'rule_id')::bigint; end if;
    perform b2c.assign(p_lead, (d ->> 'chosen')::uuid, v_id, p_trigger, d ->> 'rule_name');
  else
    -- nobody could take it: whoever had it no longer does (reassign, hand back, deactivation, leave)
    update b2c.assignments set ended_at = now(), end_reason = p_trigger where lead_id = p_lead and ended_at is null;
    update b2c.leads_state set owner_id = null, status = 'active', updated_at = now() where lead_id = p_lead and status <> 'closed';
  end if;
  return d - 'facts' || jsonb_build_object('decision_id', v_id);
end $f$;

revoke execute on function b2c.assignment_payload(b2c.assignments), b2c.assignment_to_b2b() from public, anon, authenticated;
revoke execute on function b2c.allocate(bigint, text, uuid), b2c.close_lead(bigint, text, text) from public, anon, authenticated;
