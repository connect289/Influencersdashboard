-- M31i (Addendum 3, PART 5 and PART 6.1 / 6.4): after the push.
--   hold window        derived from the partner's duplicate handling: 0 minutes for a confirmed duplicate-blocking CRM, 30 for the
--                      others (partner_save, partner_adapter_save); the duplicate window is fixed at 24 hours
--   duplicates         a claim counts only with proof (record id, created date or the CRM's native duplicate error): the partner is
--                      excluded and the next partner gets the lead; a claim without proof is a rejection plus a contract alert (D4)
--   cascade            reroute_after (m31f) runs route_decide with p_how 'cascade', so the episode's origin decides the context
--   rejections         contract alert (contract_breach) and the next partner; they count as attempts
--   technical failure  retries on a3_fixed.push_retry_seconds (about one hour), then the next partner; not an attempt
--   paused partners    a queued push for a partner that is not active fails at once without an attempt and fails over
--   limits             2 duplicate-or-rejection attempts, 3 partners pushed (route_decide, m31f); the bar for duplicate cascades
--   disputes           a duplicate claimed within 24 hours of acceptance, and activity after a lost lead moved to B2C, with a kind
--   lost grace         a partner's 'lost' starts a 7-day grace on the allocation; it keeps its status (accepted or pushed) and the
--                      lead keeps its pointers, so the live public.w2_crm_owned rule is unchanged; partner activity revives it;
--                      after the grace lost_handoff moves the lead to B2C nurture (partner_lost), unassigned and partner-barred
--   notifications      no acceptance message while lost in grace or disputed; a second partner in the same cycle gets a
--                      'reroute_update' message instead of a second welcome; cancelled messages when the lead leaves the partner
--   money              an upheld duplicate dispute leaves no commission; an enrolment after the grace is a dispute first
--   push note          lists every interest (PART 4 'several interests'); interests[] only with partners.push_options.interests_array
-- Depends on m31a0 (claim_*, lost_*, origin, interest_rank), m31a (commission_disputes.kind / partner_event_id / existing_created_on /
-- also, partners.dedupe_confirmed_at / push_options, engine.a3_fixed), m31b (partner_bar_set, handoff_payload, lead_interest_list,
-- phone_digits), m31c (stats_num, partner_paused_failover's failover shape), m31f (reroute_after with p_how 'cascade').
-- Replaces: apply_duplicate, apply_rejection, apply_push_error (m8b), push_dispatch (m19b), push_collect (m21c), apply_partner_duplicate,
-- apply_partner_lost, allocation_partner_lost, dispute_resolve, push_overview (m8c), partner_event_apply, sla_tick (m16b),
-- apply_partner_mapped_stage, push_payload_base, partner_checklist (m15c), notify_accepted (m9a), notify_tick (m9b), enrollment_record
-- (m20b), partner_save (m4b), partner_adapter_save (m21d). New: claim_proof_normalize, late_activity_dispute, partner_lost_revive,
-- lost_handoff, lost_grace_tick. Every function is replaced whole with its signature kept; new signatures have new names.
-- Nothing here touches public.student_leads' shape; B2B writes only the columns it already wrote (stage, lost_reason, lost_at,
-- pointers, owner_user_id / team_id / assigned_at at the lost hand-off).

-- ---------- (1) duplicate proof ----------
/* PART 5.3 'with proof' (D4): an existing record id, the partner's created date, or a CRM adapter's native duplicate error
   (push_response with crm_message). Normalised into the allocation's claim_* columns. p_partner is kept for partner-specific
   proof conventions; the rule is the same for every partner today. */
create or replace function b2b.claim_proof_normalize(p_proof jsonb, p_partner bigint)
returns jsonb language sql stable set search_path = '' as $fn$
  with p as (select coalesce(p_proof, '{}'::jsonb) j),
       x as (select nullif(trim(coalesce(p.j ->> 'existing_record_id', p.j ->> 'existing_id', p.j ->> 'record_id')), '') rid,
                    coalesce(b2b.try_timestamptz(p.j ->> 'existing_created_at'), b2b.try_timestamptz(p.j ->> 'created_at'),
                             b2b.try_timestamptz(p.j ->> 'first_seen_at')) cat,
                    p.j ? 'crm_message' native
               from p)
  select jsonb_build_object('existing_record_id', left(x.rid, 200), 'existing_created_at', x.cat,
                            'proof_ok', x.rid is not null or x.cat is not null or x.native)
    from x;
$fn$;

-- ---------- (2) duplicate during the push or the hold window ----------
/* A partner says the student is already its lead (during the push or the hold window). A returning Eduwit lead (the existing
   record is Eduwit's own earlier push) is accepted instead. With proof: duplicate, the proof kept on the claim columns, and the
   next-best partner (reroute_after, p_how 'cascade'). Without proof: a rejection with a contract alert, the partner excluded,
   the claim an attempt, never a bar (D4). */
create or replace function b2b.apply_duplicate(p_allocation_id bigint, p_proof jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_existing text := coalesce(p_proof ->> 'existing_record_id', p_proof ->> 'existing_id');
  v_ref text := p_proof ->> 'existing_reference';
  pf jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then return 'ignored: allocation not found'; end if;
  if a.status not in ('pushing', 'pushed') then return 'ignored: allocation is ' || a.status; end if;
  if exists (select 1 from b2b.allocations p where p.lead_id = a.lead_id and p.partner_id = a.partner_id and p.id <> a.id
               and ((v_existing is not null and p.partner_record_id = v_existing) or (v_ref is not null and p.reference = v_ref))) then
    update b2b.allocations set status = 'pushed', returning_lead = true, partner_record_id = coalesce(partner_record_id, v_existing),
           claim_proof = p_proof, pushed_at = coalesce(pushed_at, now()), push_request_id = null, hold_until = now() where id = a.id;
    update public.student_leads set stage = 'sent_to_partner', partner_record_id = coalesce(v_existing, partner_record_id), updated_by = 'b2b'
     where id = a.lead_id and allocation_id = a.id;
    perform b2b.accept_allocation(a.id);
    return 'accepted: returning Eduwit lead';
  end if;

  pf := b2b.claim_proof_normalize(coalesce(p_proof, '{}'), a.partner_id);
  if coalesce((pf ->> 'proof_ok')::boolean, false) then
    update b2b.allocations set status = 'duplicate', outcome = 'duplicate', outcome_at = now(), claim_proof = p_proof,
           claim_existing_record_id = pf ->> 'existing_record_id', claim_existing_created_at = (pf ->> 'existing_created_at')::timestamptz,
           claim_proof_ok = true, spot_check = random() < coalesce((e ->> 'duplicate_spot_check')::numeric, 0.05)
     where id = a.id;
    update public.student_leads set duplicate_claim_count = coalesce(duplicate_claim_count, 0) + 1 where id = a.lead_id;
    perform b2b.log_event('lead.duplicate', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', p_proof, 'reference', a.reference, 'proof_ok', true,
                          'existing_record_id', pf ->> 'existing_record_id', 'existing_created_at', pf -> 'existing_created_at'));
    perform b2b.reroute_after(a.id, 'duplicate at partner');
    return 'duplicate: re-routed';
  end if;

  -- PART 5.3 requires proof: an unproven claim is handled as a rejection (contract alert, excluded, an attempt, no bar)
  update b2b.allocations set status = 'rejected', outcome = 'rejected', outcome_at = now(), claim_proof = p_proof, claim_proof_ok = false,
         last_error = 'duplicate claim without proof' where id = a.id;
  perform b2b.log_event('alert.partner_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('reason', 'duplicate claim without proof',
                        'contract_breach', true, 'why', 'duplicate claim without proof', 'reference', a.reference, 'claim', p_proof));
  perform b2b.reroute_after(a.id, 'duplicate claim without proof');
  return 'rejected: duplicate claim without proof';
end $fn$;

-- ---------- (3) rejection ----------
/* PART 5.5: a partner refuses the lead for a reason other than a duplicate: contract alert, excluded, the next partner. An attempt. */
create or replace function b2b.apply_rejection(p_allocation_id bigint, p_reason text)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare a b2b.allocations;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then return 'ignored: allocation not found'; end if;
  if a.status not in ('pushing', 'pushed') then return 'ignored: allocation is ' || a.status; end if;
  update b2b.allocations set status = 'rejected', outcome = 'rejected', outcome_at = now(), last_error = left(p_reason, 500) where id = a.id;
  perform b2b.log_event('alert.partner_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('reason', left(p_reason, 500), 'contract_breach', true,
                        'why', 'the partner rejected the lead', 'reference', a.reference));
  perform b2b.reroute_after(a.id, 'rejected by partner');
  return 'rejected: re-routed';
end $fn$;

-- ---------- (4) technical failure ----------
/* PART 5.6: retries on the fixed schedule (a3_fixed.push_retry_seconds: 10 s, 1 min, 5 min, 15 min, 40 min, about an hour), then
   failed and the next partner. Not an attempt. */
create or replace function b2b.apply_push_error(p_allocation_id bigint, p_error text)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_sched jsonb := coalesce(case when jsonb_typeof(e -> 'a3_fixed' -> 'push_retry_seconds') = 'array' then e -> 'a3_fixed' -> 'push_retry_seconds' end,
                            case when jsonb_typeof(e -> 'push_retry_seconds') = 'array' then e -> 'push_retry_seconds' end,
                            '[10, 60, 300, 900, 2400]'::jsonb);
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null or a.status <> 'pushing' then return 'ignored'; end if;
  if a.push_attempts = 1 then
    perform b2b.log_event('alert.push_failed', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(p_error, 300), 'reference', a.reference));
  end if;
  if a.push_attempts <= jsonb_array_length(v_sched) then
    update b2b.allocations set push_request_id = null, last_error = left(p_error, 500),
           next_push_at = now() + make_interval(secs => coalesce(b2b.stats_num(v_sched -> greatest(a.push_attempts - 1, 0)), 60)) where id = a.id;
    return 'retry';
  end if;
  update b2b.allocations set status = 'failed', outcome = 'failed', outcome_at = now(), push_request_id = null, next_push_at = null, last_error = left(p_error, 500) where id = a.id;
  perform b2b.log_event('lead.push_failed', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(p_error, 300), 'attempts', a.push_attempts));
  perform b2b.reroute_after(a.id, 'partner unreachable');
  return 'failed: re-routed';
end $fn$;

-- ---------- (5) dispatch ----------
/* Sends queued pushes and due retries (m19b). PART 6.4: a non-test allocation whose partner is not active fails at once, with no
   attempt counted, and fails over to the next partner (the same shape as b2b.partner_paused_failover). A partner switched off or
   without a URL still fails the attempt and re-routes, as before. */
create or replace function b2b.push_dispatch(p_limit int default 20)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  a b2b.allocations;
  p b2b.partners;
  req jsonb;
  v_net bigint;
  n int := 0;
begin
  for a in
    select * from b2b.allocations
     where destination_type = 'partner' and push_request_id is null
       and ((status = 'queued' and (next_push_at is null or next_push_at <= now())) or (status = 'pushing' and next_push_at <= now()))
     order by coalesce(next_push_at, created_at)
     limit least(greatest(p_limit, 1), 100)
     for update skip locked
  loop
    begin
      if not a.is_test then
        select * into p from b2b.partners where id = a.partner_id;
        if p.status is distinct from 'active' then
          update b2b.allocations set status = 'failed', outcome = 'failed', outcome_at = now(), next_push_at = null,
                 last_error = left('partner paused: ' || coalesce(p.status, 'unknown'), 500) where id = a.id;
          perform b2b.log_event('lead.push_failed', a.lead_id, a.id, a.partner_id,
                                jsonb_build_object('error', 'partner paused', 'why', coalesce(p.status, 'unknown'), 'partner_paused', true, 'attempts', a.push_attempts));
          perform b2b.reroute_after(a.id, 'partner paused');
          continue;
        end if;
      end if;
      if not a.is_test and not b2b.is_live('partner:' || a.partner_id) then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, 'partner is switched off');
        continue;
      end if;
      if a.programme_id is null then
        select (c -> 'programmes' ->> 0)::bigint into a.programme_id
          from b2b.engine_decisions d, jsonb_array_elements(d.candidates) c
         where d.id = a.engine_decision_id and (c ->> 'partner_id')::bigint = a.partner_id;
        update b2b.allocations set programme_id = a.programme_id where id = a.id;
      end if;
      req := b2b.push_request(a);
      if coalesce((req ->> 'needs_token')::boolean, false) then
        select * into p from b2b.partners where id = a.partner_id;
        perform b2b.adapter_token_request(p, req ->> 'env');
        update b2b.allocations set status = 'pushing', next_push_at = now() + interval '20 seconds' where id = a.id;
        continue;
      end if;
      if req ->> 'token_error' is not null then
        -- the CRM sign-in failed: a failed attempt on the normal retry schedule
        update b2b.allocations set status = 'pushing', push_attempts = push_attempts + 1 where id = a.id;
        perform b2b.apply_push_error(a.id, req ->> 'token_error');
        continue;
      end if;
      if req ->> 'url' is null then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, coalesce(req ->> 'error', case when a.is_test then 'partner has no test endpoint' else 'partner has no API URL' end));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers',
                             timeout_milliseconds := coalesce((e ->> 'push_timeout_ms')::int, 10000));
      update b2b.allocations set status = 'pushing', push_attempts = push_attempts + 1, push_request_id = v_net, next_push_at = null where id = a.id;
      insert into b2b.push_requests (allocation_id, attempt, net_request_id, url, sandbox)
      values (a.id, a.push_attempts + 1, v_net, req ->> 'url', a.is_test);
      n := n + 1;
    exception when others then
      update b2b.allocations set next_push_at = now() + interval '5 minutes', last_error = left(sqlerrm, 500) where id = a.id;
      perform b2b.log_event('alert.push_error', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(sqlerrm, 300)));
    end;
  end loop;
  return n;
end $fn$;

-- ---------- (6) collect ----------
/* Reads finished pg_net responses for allocations waiting on one and applies them (m21c). Each answer is applied in its own
   block: a failure to apply is alerted (alert.push_collect_error) and then handled as a push error, so one bad answer never
   stops the tick. */
create or replace function b2b.push_collect()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  j jsonb;
  res jsonb;
  v_outcome text;
  v_rid text;
  v_reason text;
  n int := 0;
begin
  for r in
    select a.id, a.lead_id, a.partner_id, a.is_test, p.adapter_type, q.id as req_id, q.sent_at, x.status_code, x.content, x.timed_out, x.error_msg, x.id is not null as done
      from b2b.allocations a
      join b2b.partners p on p.id = a.partner_id
      join b2b.push_requests q on q.net_request_id = a.push_request_id and q.allocation_id = a.id
      left join net._http_response x on x.id = a.push_request_id
     where a.status = 'pushing' and a.push_request_id is not null
     order by a.id
     limit 200
  loop
    if not r.done then
      if r.sent_at < now() - interval '2 minutes' then
        update b2b.push_requests set outcome = 'timeout', error = 'no response within 2 minutes', completed_at = now() where id = r.req_id;
        begin
          perform b2b.apply_push_error(r.id, 'no response within 2 minutes');
        exception when others then
          perform b2b.log_event('alert.push_collect_error', r.lead_id, r.id, r.partner_id, jsonb_build_object('allocation_id', r.id, 'error', left(sqlerrm, 300), 'code', sqlstate));
        end;
        n := n + 1;
      end if;
      continue;
    end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    res := null; v_rid := null; v_reason := null;
    if r.timed_out or r.error_msg is not null then
      v_outcome := 'error';
    elsif b2b.adapter_spec(r.adapter_type) is not null then
      res := b2b.adapter_push_result_p(r.partner_id, r.is_test, r.adapter_type, r.status_code, r.content);
      v_outcome := res ->> 'outcome';
      v_rid := res ->> 'record_id';
      v_reason := res ->> 'reason';
      if v_outcome = 'auth' then
        update b2b.partner_adapter_state set token_expires_at = null, updated_at = now()
         where partner_id = r.partner_id and env = case when r.is_test then 'sandbox' else 'live' end;
        perform b2b.log_event('alert.push_error', null, r.id, r.partner_id, jsonb_build_object('error', 'the CRM refused the credentials: ' || left(coalesce(v_reason, ''), 200)));
        v_outcome := 'error';
      end if;
    else
      v_rid := coalesce(j ->> 'record_id', j ->> 'id', j ->> 'lead_id', j -> 'data' ->> 'id');
      v_outcome := case
        when r.status_code = 409 or coalesce((j ->> 'duplicate')::boolean, false) then 'duplicate'
        when r.status_code in (422, 403) and (coalesce((j ->> 'rejected')::boolean, false) or j ? 'reason') then 'rejected'
        when r.status_code between 200 and 299 then 'created'
        else 'error' end;
      v_reason := j ->> 'reason';
    end if;
    update b2b.push_requests set status_code = r.status_code, response = left(r.content, 2000), outcome = case when r.timed_out then 'timeout' else v_outcome end,
           error = coalesce(r.error_msg, case when v_outcome = 'error' then 'HTTP ' || coalesce(r.status_code::text, '?') || coalesce(': ' || left(v_reason, 200), '') end),
           completed_at = now()
     where id = r.req_id;
    begin
      case v_outcome
        when 'created' then perform b2b.apply_created(r.id, v_rid);
        when 'duplicate' then perform b2b.apply_duplicate(r.id, coalesce(res, j, '{}') || jsonb_build_object('status_code', r.status_code, 'source', 'push_response'));
        when 'rejected' then perform b2b.apply_rejection(r.id, coalesce(v_reason, 'rejected'));
        else perform b2b.apply_push_error(r.id, coalesce(r.error_msg, case when r.timed_out then 'timeout' end,
                                                         'HTTP ' || coalesce(r.status_code::text, '?') || ': ' || left(coalesce(v_reason, r.content, ''), 200)));
      end case;
    exception when others then
      perform b2b.log_event('alert.push_collect_error', r.lead_id, r.id, r.partner_id,
                            jsonb_build_object('allocation_id', r.id, 'error', left(sqlerrm, 300), 'code', sqlstate, 'outcome', v_outcome));
      begin
        perform b2b.apply_push_error(r.id, 'could not apply the partner''s answer (' || coalesce(v_outcome, '?') || '): ' || left(sqlerrm, 200));
      exception when others then
        perform b2b.log_event('routing.error', r.lead_id, r.id, r.partner_id, jsonb_build_object('where', 'push_collect', 'error', left(sqlerrm, 300), 'code', sqlstate));
      end;
    end;
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- ---------- (7) duplicate reported by a partner event ----------
/* PART 5.3 and 5.8. During the push or the hold window: apply_duplicate. Within 24 hours of acceptance (the lead may be lost in
   grace): a commission dispute of kind duplicate_after_acceptance for the Admin, the student's pending messages cancelled, the lead
   stays with the partner. A second claim joins the open dispute ('also'). Later: logged, never re-routed. */
create or replace function b2b.apply_partner_duplicate(p_allocation_id bigint, p_data jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_window numeric := coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'duplicate_window_hours'), 24);
  d jsonb := coalesce(p_data, '{}');
  pf jsonb;
  v_id bigint;
  v_new boolean := false;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then return 'ignored: allocation not found'; end if;
  if a.status in ('pushing', 'pushed') then
    return b2b.apply_duplicate(a.id, d || jsonb_build_object('source', 'partner_event'));
  end if;
  if a.status = 'accepted' and a.accepted_at > now() - make_interval(mins => round(v_window * 60)::int) then
    pf := b2b.claim_proof_normalize(d, a.partner_id);
    select x.id into v_id from b2b.commission_disputes x where x.allocation_id = a.id and x.status = 'open' and x.kind = 'duplicate_after_acceptance';
    if v_id is null then
      begin
        insert into b2b.commission_disputes (allocation_id, lead_id, partner_id, kind, existing_record_id, existing_created_at, existing_created_on, proof)
        values (a.id, a.lead_id, a.partner_id, 'duplicate_after_acceptance', pf ->> 'existing_record_id',
                coalesce(d ->> 'existing_created_at', d ->> 'created_at', d ->> 'first_seen_at'), (pf ->> 'existing_created_at')::timestamptz, d)
        returning id into v_id;
        v_new := true;
      exception when unique_violation then
        -- one open dispute per allocation (without pending/m31i_dispute_index): the claim joins the open one, whatever its kind
        select x.id into v_id from b2b.commission_disputes x where x.allocation_id = a.id and x.status = 'open' order by x.id desc limit 1;
      end;
    end if;
    if not v_new and v_id is not null then
      update b2b.commission_disputes
         set also = also || jsonb_build_object('kind', 'duplicate_after_acceptance', 'at', now(), 'claim', d,
                                               'existing_record_id', pf ->> 'existing_record_id', 'existing_created_on', pf -> 'existing_created_at')
       where id = v_id;
    end if;
    update b2b.student_notifications set status = 'cancelled', error = 'duplicate claimed after acceptance', updated_at = now()
     where allocation_id = a.id and status = 'scheduled';
    perform b2b.log_event('alert.commission_dispute', a.lead_id, a.id, a.partner_id,
                          jsonb_build_object('dispute_id', v_id, 'kind', 'duplicate_after_acceptance', 'existing_created_on', pf -> 'existing_created_at',
                                             'existing_record_id', pf ->> 'existing_record_id', 'proof_ok', pf -> 'proof_ok', 'proof', d, 'reference', a.reference,
                                             'appended', not v_new));
    return case when v_new then 'dispute: opened, the lead stays with the partner' else 'dispute: claim added to the open dispute' end;
  end if;
  perform b2b.log_event('partner.late_duplicate_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', d, 'status', a.status, 'accepted_at', a.accepted_at));
  return 'late duplicate: claim outside the ' || round(v_window)::text || '-hour window, ignored';
end $fn$;

-- ---------- (8) lost: the 7-day grace ----------
/* PART 6.1. The allocation keeps its status (accepted, or pushed inside the hold window) and the lead keeps allocation_id and
   destination_type 'partner', so Witty stays quiet (live public.w2_crm_owned). Grace fields live on the allocation; the lead's
   stage 'lost', lost_reason and lost_at are display only, written while the lead points at the allocation. Pending student
   messages are cancelled. A report while already in grace merges the detail and leaves the clock. */
create or replace function b2b.apply_partner_lost(p_allocation_id bigint, p_detail jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_days numeric := coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'lost_grace_days'), 7);
  d jsonb := case when jsonb_typeof(p_detail) = 'object' then p_detail else '{}'::jsonb end;
  v_until timestamptz;
  v_prev text;
  v_status text;
  v_sub text;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then
    return jsonb_build_object('status', 'ignored', 'allocation_id', p_allocation_id, 'reference', null, 'grace_until', null, 'lost_count', 0, 'why', 'allocation not found');
  end if;
  if a.destination_type <> 'partner' or a.status not in ('pushed', 'accepted') then
    return jsonb_build_object('status', 'ignored', 'allocation_id', a.id, 'reference', a.reference, 'grace_until', null, 'lost_count', a.lost_count,
                              'why', 'only a lead the partner holds (pushed or accepted) can be marked lost; this allocation is ' || a.status);
  end if;
  select * into l from public.student_leads where id = a.lead_id for update;
  v_status := coalesce(d ->> 'status', l.partner_stage_raw);
  v_sub := coalesce(d ->> 'sub_status', l.partner_sub_stage_raw);
  if a.lost_at is not null and a.lost_revived_at is null then
    update b2b.allocations set lost_detail = coalesce(lost_detail, '{}') || jsonb_strip_nulls(d - 'history'), updated_at = now() where id = a.id;
    return jsonb_build_object('status', 'grace', 'allocation_id', a.id, 'reference', a.reference, 'grace_until', a.lost_grace_until,
                              'lost_count', a.lost_count, 'why', 'already in grace');
  end if;
  v_until := now() + v_days * interval '1 day';
  v_prev := case when l.allocation_id = a.id and l.stage is distinct from 'lost' then l.stage end;
  update b2b.allocations
     set lost_at = now(), lost_grace_until = v_until,
         lost_detail = jsonb_strip_nulls((d - 'history') || jsonb_build_object('status', v_status, 'sub_status', v_sub))
                       || jsonb_build_object('history', coalesce(lost_detail -> 'history', '[]'::jsonb)),
         lost_prev_stage = coalesce(v_prev, lost_prev_stage), lost_revived_at = null, lost_count = lost_count + 1, updated_at = now()
   where id = a.id;
  update public.student_leads
     set stage = 'lost', lost_reason = left(d ->> 'lost_reason', 200), lost_at = now(),
         stage_changed_at = case when stage is distinct from 'lost' then now() else stage_changed_at end,
         partner_synced_at = now(), updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  update b2b.student_notifications set status = 'cancelled', error = 'lost, in grace', updated_at = now()
   where allocation_id = a.id and status = 'scheduled';
  perform b2b.log_event('lead.partner_lost', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('lost_reason', d ->> 'lost_reason', 'grace_until', v_until, 'lost_count', a.lost_count + 1,
                                           'partner_status', v_status, 'partner_sub_status', v_sub, 'partner_last_activity', d ->> 'last_activity_at',
                                           'reference', a.reference));
  return jsonb_build_object('status', 'grace', 'allocation_id', a.id, 'reference', a.reference, 'grace_until', v_until, 'lost_count', a.lost_count + 1, 'why', null);
end $fn$;

-- ---------- (9) the Admin's / a service's entry point ----------
create or replace function b2b.allocation_partner_lost(p_allocation_id bigint, p_detail jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  v := b2b.apply_partner_lost(p_allocation_id, p_detail);
  if v ->> 'status' = 'ignored' then raise exception '%', coalesce(v ->> 'why', 'not applied') using errcode = '22023'; end if;
  return v;
end $fn$;

-- ---------- (10) revival inside the grace ----------
/* PART 6.1: 'If the partner reports new activity in that time, the lead is simply back with the partner, with no dispute.'
   True when the allocation was in grace (lost_at set, not revived, before lost_grace_until, status pushed or accepted). The lost
   period is appended to lost_detail.history, the lead's stage is restored (guarded by allocation_id), the status-update SLA
   clock restarts, lead.partner_revived is logged. */
create or replace function b2b.partner_lost_revive(p_allocation_id bigint, p_event_id bigint, p_why text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_hours numeric;
  v_stage text;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null or a.lost_at is null or a.lost_revived_at is not null or a.lost_grace_until is null or now() >= a.lost_grace_until
     or a.status not in ('pushed', 'accepted') then
    return false;
  end if;
  v_hours := round((extract(epoch from (now() - a.lost_at)) / 3600)::numeric, 2);
  v_stage := case when a.lost_prev_stage is null or a.lost_prev_stage = 'lost' then 'sent_to_partner' else a.lost_prev_stage end;
  update b2b.allocations
     set lost_revived_at = now(),
         lost_detail = coalesce(lost_detail, '{}') || jsonb_build_object('history', coalesce(lost_detail -> 'history', '[]'::jsonb)
                       || jsonb_build_object('lost_at', a.lost_at, 'revived_at', now(), 'lost_reason', lost_detail ->> 'lost_reason',
                                             'why', left(p_why, 200), 'event_id', p_event_id)),
         updated_at = now()
   where id = a.id;
  update public.student_leads
     set stage = v_stage, lost_reason = null, lost_at = null, stage_changed_at = now(), partner_synced_at = now(), updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id and stage = 'lost';
  -- the partner holds the lead again: the status-update clock restarts (a check voided at this very instant is re-armed)
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
  values (a.id, a.lead_id, a.partner_id, 'status_update', now(), now() + make_interval(days => b2b.partner_sla(a.partner_id, 'status_update_days')), a.is_test)
  on conflict (allocation_id, sla, started_at) do update
    set status = 'pending', met_at = null, breached_at = null, due_at = excluded.due_at, updated_at = now()
    where b2b.sla_checks.status = 'void';
  perform b2b.log_event('lead.partner_revived', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('why', left(p_why, 200), 'event_id', p_event_id, 'lost_for_hours', v_hours, 'stage_restored', v_stage,
                                           'lost_count', a.lost_count, 'reference', a.reference));
  return true;
end $fn$;

-- ---------- (11) the hand-off after the grace ----------
/* PART 6.1 after 7 days, in one transaction: the partner allocation closes (outcome lost), an engine decision (partner_lost,
   nurture, fallback, how 'grace'), an in_house hand-off with the closed allocation's origin, the lead's pointers moved and
   owner_user_id / team_id / assigned_at cleared ('unassigned'; the previous owner travels in the payload, critic B9), the
   permanent lost bar (set_by 'grace'), and b2c.lead_handed_off with handoff_payload (nurture, unassigned_until_interest, the
   lost block and the first-nurture-message timing). */
create or replace function b2b.lost_handoff(p_allocation_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  v_dec bigint;
  v_new bigint;
  v_owner uuid;
  v_attr jsonb;
  v_hold jsonb;
  v_bar jsonb;
  v_interests jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then
    return jsonb_build_object('handed_off', false, 'allocation_id', null, 'reference', null, 'decision_id', null, 'closed_allocation_id', p_allocation_id,
                              'barred', false, 'previous_owner', null, 'why', 'allocation not found');
  end if;
  if a.destination_type <> 'partner' or a.lost_at is null or a.lost_revived_at is not null or a.status not in ('pushed', 'accepted') then
    return jsonb_build_object('handed_off', false, 'allocation_id', null, 'reference', null, 'decision_id', null, 'closed_allocation_id', a.id,
                              'barred', false, 'previous_owner', null, 'why', 'the allocation is not lost in grace (status ' || a.status || ')');
  end if;
  if a.lost_grace_until is null or now() < a.lost_grace_until then
    return jsonb_build_object('handed_off', false, 'allocation_id', null, 'reference', null, 'decision_id', null, 'closed_allocation_id', a.id,
                              'barred', false, 'previous_owner', null, 'why', 'in grace until ' || coalesce(a.lost_grace_until::text, '?'));
  end if;
  select * into l from public.student_leads where id = a.lead_id for update;
  if l.id is null then
    return jsonb_build_object('handed_off', false, 'allocation_id', null, 'reference', null, 'decision_id', null, 'closed_allocation_id', a.id,
                              'barred', false, 'previous_owner', null, 'why', 'lead not found');
  end if;
  if l.allocation_id is distinct from a.id then
    return jsonb_build_object('handed_off', false, 'allocation_id', null, 'reference', null, 'decision_id', null, 'closed_allocation_id', a.id,
                              'barred', false, 'previous_owner', null, 'why', 'the lead no longer points at the allocation');
  end if;
  v_owner := l.owner_user_id;
  v_attr := b2b.lead_attribution(l);
  v_hold := b2b.b2c_hold(l);
  v_bar := b2b.partner_bar(l);
  if a.engine_decision_id is not null then select d.interests into v_interests from b2b.engine_decisions d where d.id = a.engine_decision_id; end if;

  -- 1. the partner allocation closes: its grace ended
  update b2b.allocations set status = 'closed', outcome = 'lost', outcome_at = now(), updated_at = now() where id = a.id;
  -- 2. the decision (reason exactly 'partner_lost': no free text, C124)
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, segment_exact, interest, interest_rank, interests, mode, destination_type, reason,
                                    settings_version, is_test, actor_type, actor_id, b2c_lane, how, hold, bar, class, attribution)
  values (a.lead_id, a.cycle_no, a.segment, a.segment_exact, b2b.lead_interest(l), a.interest_rank, v_interests, 'fallback', 'in_house', 'partner_lost',
          (select version from b2b.settings where key = 'engine'), a.is_test, b2b.actor() ->> 'type', b2b.actor() ->> 'id', 'nurture', 'grace',
          v_hold, v_bar, b2b.lead_class(l) ->> 'class', v_attr)
  returning id into v_dec;
  -- 3. the B2C nurture hand-off, with the closed allocation's origin
  insert into b2b.allocations (lead_id, cycle_no, segment, segment_exact, destination_type, status, mode, attempt_no, reason, engine_decision_id, is_test,
                               b2c_lane, origin, interest_rank, paid, paid_platform, campaign_id)
  values (a.lead_id, a.cycle_no, a.segment, a.segment_exact, 'in_house', 'handed_off', 'fallback', a.attempt_no + 1, 'partner_lost', v_dec, a.is_test,
          'nurture', coalesce(a.origin, 'auto'), a.interest_rank, (v_attr ->> 'paid')::boolean, v_attr ->> 'platform', v_attr ->> 'campaign_id')
  returning id into v_new;
  update b2b.allocations set reference = 'EDW-' || v_new where id = v_new;
  -- 4. the lead: with B2C, unassigned (the partner-sync columns stay as history; stage 'lost' is kept for display)
  update public.student_leads
     set destination_type = 'in_house', partner_id = null, allocation_id = v_new, allocated_at = now(), allocation_reason = 'partner_lost',
         owner_user_id = null, team_id = null, assigned_at = null, updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  -- 5. the permanent bar (Guiding principle, PART 6.1, PART 6.3)
  v_bar := b2b.partner_bar_set(a.lead_id, 'lost', v_new, 'grace');
  -- 6. the B2C CRM hears about it (the payload reads the hold, the bar and the lost block live)
  perform b2b.log_event('b2c.lead_handed_off', a.lead_id, v_new, a.partner_id,
                        b2b.handoff_payload(v_new, jsonb_build_object('previous_owner', to_jsonb(v_owner))));
  return jsonb_build_object('handed_off', true, 'allocation_id', v_new, 'reference', 'EDW-' || v_new, 'decision_id', v_dec, 'closed_allocation_id', a.id,
                            'barred', v_bar is not null, 'previous_owner', v_owner, 'why', null);
end $fn$;

-- ---------- (12) the grace timer ----------
/* Every 5 minutes: allocations whose grace ended are handed off, 50 at a time inside a 2-second box, each in its own block.
   An allocation whose lead no longer points at it (nothing left to hand off) is closed as lost so it leaves the queue. */
create or replace function b2b.lost_grace_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  x jsonb;
  n int := 0;
  t0 timestamptz := clock_timestamp();
  v_prev text;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.lost_grace_tick')) then return 0; end if;
  perform set_config('b2b.actor', 'system', true);
  v_prev := current_setting('lock_timeout', true);
  perform set_config('lock_timeout', '2000', true);
  for r in
    select a.id, a.lead_id, a.partner_id from b2b.allocations a
     where a.destination_type = 'partner' and a.lost_at is not null and a.lost_revived_at is null and a.lost_grace_until <= now()
       and a.status in ('pushed', 'accepted')
     order by a.lost_grace_until, a.id
     limit 50
  loop
    exit when clock_timestamp() - t0 > interval '2 seconds';
    begin
      x := b2b.lost_handoff(r.id);
      if coalesce((x ->> 'handed_off')::boolean, false) then
        n := n + 1;
      elsif x ->> 'why' = 'the lead no longer points at the allocation' then
        update b2b.allocations set status = 'closed', outcome = 'lost', outcome_at = now(), updated_at = now()
         where id = r.id and status in ('pushed', 'accepted');
        perform b2b.log_event('routing.error', r.lead_id, r.id, r.partner_id,
                              jsonb_build_object('where', 'lost_grace_tick', 'error', 'lost grace ended but the lead had moved on; allocation closed', 'allocation_id', r.id));
      end if;
    exception when others then
      perform b2b.log_event('routing.error', r.lead_id, r.id, r.partner_id,
                            jsonb_build_object('where', 'lost_grace_tick', 'error', left(sqlerrm, 300), 'code', sqlstate, 'allocation_id', r.id));
    end;
  end loop;
  perform set_config('lock_timeout', coalesce(nullif(v_prev, ''), '0'), true);
  return n;
end $fn$;

-- ---------- late activity after the lead moved to B2C ----------
/* PART 6.1 'Late partner activity: activity reported after the grace period is logged as a commission dispute.' One dispute of
   kind late_activity_after_lost per allocation takes every later claim in 'also' (an open one, or an upheld one; a rejected one
   is not reopened). Without pending/m31i_dispute_index a different open kind also takes the claim. */
create or replace function b2b.late_activity_dispute(p_allocation_id bigint, p_event_id bigint, p_proof jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  d b2b.commission_disputes;
  v_new boolean := false;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  select x.* into d from b2b.commission_disputes x
   where x.allocation_id = a.id and x.kind = 'late_activity_after_lost' and x.status in ('open', 'upheld')
   order by (x.status = 'open') desc, x.id desc limit 1;
  if d.id is null then
    begin
      insert into b2b.commission_disputes (allocation_id, lead_id, partner_id, kind, partner_event_id, proof)
      values (a.id, a.lead_id, a.partner_id, 'late_activity_after_lost', p_event_id, coalesce(p_proof, '{}'))
      returning * into d;
      v_new := true;
    exception when unique_violation then
      select x.* into d from b2b.commission_disputes x where x.allocation_id = a.id and x.status = 'open' order by x.id desc limit 1;
    end;
  end if;
  if not v_new and d.id is not null then
    update b2b.commission_disputes
       set also = also || jsonb_build_object('kind', 'late_activity_after_lost', 'at', now(), 'partner_event_id', p_event_id, 'proof', coalesce(p_proof, '{}'))
     where id = d.id;
  end if;
  perform b2b.log_event('alert.commission_dispute', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('dispute_id', d.id, 'kind', 'late_activity_after_lost', 'existing_created_on', null, 'partner_event_id', p_event_id,
                                           'reference', a.reference, 'appended', not v_new));
  return jsonb_build_object('dispute_id', d.id, 'appended', not v_new, 'status', d.status);
end $fn$;

-- ---------- (13) partner events ----------
/* Applies one stored partner event (m16b), with PART 6.1:
   (a) a closed allocation with outcome lost: contacted, activity, update and stage events open (or join) a late_activity_after_lost
       dispute; contact and activity rows are written for audit only; nothing else is applied. A 'lost' reported again is ignored.
   (b) in the grace: a contacted event, any mapped activity, and an update whose mapping sets a future next_follow_up_at revive the
       lead first (a stage other than lost revives inside apply_partner_mapped_stage), then the event is applied as usual.
   (c) 'lost': apply_partner_lost; the result reads 'lost: in grace until <date>' or 'ignored: <why>'.
   (d) the rest as m16b. */
create or replace function b2b.partner_event_apply(p_event_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e b2b.partner_events;
  a b2b.allocations;
  pr b2b.mapping_profiles;
  j jsonb;
  d jsonb;
  m jsonb;
  x jsonb;
  v_kind text;
  v_status text := 'applied';
  v_result text;
  v_unmapped jsonb;
  v_at timestamptz;
  v_connected boolean;
  v_grace boolean;
  v_after_lost boolean;
  v_revive boolean := false;
  v_act_keys text[] := array['direction', 'duration', 'duration_sec', 'counsellor', 'counsellor_name', 'counsellor_id'];
begin
  select * into e from b2b.partner_events where id = p_event_id for update;
  if e.id is null then raise exception 'event not found' using errcode = 'P0002'; end if;
  select * into a from b2b.allocations where id = e.allocation_id;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = e.id;
    return jsonb_build_object('status', 'error', 'result', 'no allocation matches reference or record_id');
  end if;
  j := e.raw;
  d := coalesce(j -> 'data', '{}');
  select * into pr from b2b.mapping_profiles where partner_id = e.partner_id and status = 'active';
  v_grace := a.destination_type = 'partner' and a.lost_at is not null and a.lost_revived_at is null and a.status in ('pushed', 'accepted');
  v_after_lost := a.destination_type = 'partner' and a.status = 'closed' and a.outcome = 'lost';

  begin
    if v_after_lost and e.event_type in ('contacted', 'activity', 'update', 'stage') then
      -- (a) the lead moved to B2C after the grace: a commission dispute, nothing moves the lead
      if e.event_type = 'stage' and pr.id is not null then m := b2b.mapping_in(pr.id, 'stage', d); end if;
      if e.event_type = 'stage' and (lower(coalesce(d ->> 'stage', '')) = 'lost' or coalesce(m -> 'status' ->> 'stage', '') = 'lost') then
        v_status := 'ignored';
        v_result := 'ignored: lost reported again after the lead moved to B2C';
      else
        if e.event_type = 'activity' and pr.id is not null then m := b2b.mapping_in(pr.id, 'activity', d - v_act_keys); end if;
        x := b2b.late_activity_dispute(a.id, e.id, j);
        if e.event_type = 'contacted' then
          v_connected := coalesce((d ->> 'connected')::boolean, false);
          perform b2b.activity_record(e, a, 'call', case when v_connected then 'connected' else coalesce(nullif(lower(trim(d ->> 'outcome')), ''), 'not_connected') end, null);
        elsif e.event_type = 'activity' then
          perform b2b.activity_record(e, a, coalesce(m -> 'activity' ->> 'kind', 'note'), coalesce(m -> 'activity' ->> 'outcome', d ->> 'outcome', d ->> 'type'), m);
        end if;
        v_result := 'dispute opened: activity after the lead moved to B2C';
      end if;
    else
      -- (b) in the grace, sales activity brings the lead back to the partner before the event is applied
      if v_grace then
        v_revive := coalesce(case e.event_type
          when 'contacted' then true
          when 'activity' then pr.id is not null and (b2b.mapping_in(pr.id, 'activity', d - v_act_keys) -> 'activity') is not null
          when 'update' then pr.id is not null and b2b.try_timestamptz(b2b.mapping_in(pr.id, 'update', d) -> 'fields' ->> 'next_follow_up_at') > now()
          else false end, false);
        if v_revive then
          perform b2b.partner_lost_revive(a.id, e.id, 'partner ' || e.event_type || ' event');
          select * into a from b2b.allocations where id = a.id;
        end if;
      end if;
      case e.event_type
        when 'duplicate' then v_result := b2b.apply_partner_duplicate(a.id, d);
        when 'rejected' then v_result := case when a.status in ('pushing', 'pushed') then b2b.apply_rejection(a.id, coalesce(d ->> 'reason', 'rejected'))
                                              else 'ignored: rejection after acceptance' end;
        when 'lost' then
          -- (c) PART 6.1: the grace starts (or continues); the lead stays with the partner
          x := b2b.apply_partner_lost(a.id, d || jsonb_build_object('lost_reason', coalesce(d ->> 'lost_reason', d ->> 'reason')));
          if x ->> 'status' = 'grace' then
            v_result := 'lost: in grace until ' || to_char((x ->> 'grace_until')::timestamptz at time zone 'Asia/Kolkata', 'DD Mon YYYY HH24:MI') || ' IST';
            perform b2b.activity_record(e, a, 'stage_change', 'lost', null);
          else
            v_result := 'ignored: ' || coalesce(x ->> 'why', 'not applied');
          end if;
        when 'contacted' then
          v_result := b2b.apply_contacted(a.id, j);
          if v_result not like 'ignored%' then
            v_connected := coalesce((d ->> 'connected')::boolean, false);
            perform b2b.activity_record(e, a, 'call', case when v_connected then 'connected' else coalesce(nullif(lower(trim(d ->> 'outcome')), ''), 'not_connected') end, null);
          end if;
        when 'stage', 'update', 'activity' then
          -- the partner's own wording is always kept on the lead
          if e.event_type = 'stage' and a.status in ('pushed', 'accepted') then
            update public.student_leads set partner_stage_raw = left(d ->> 'stage', 200), partner_sub_stage_raw = left(d ->> 'sub_stage', 200),
                   partner_synced_at = now(), updated_by = 'b2b'
             where id = a.lead_id and allocation_id = a.id;
          end if;
          if pr.id is null then
            v_status := 'held_unmapped';
            v_result := 'stored: no mapping published for this partner yet';
          else
            v_kind := e.event_type;
            -- an activity's standard keys (direction, duration, counsellor) are read by activity_record, not mapped as fields
            m := b2b.mapping_in(pr.id, v_kind, case when v_kind = 'activity' then d - v_act_keys else d end);
            v_unmapped := coalesce(m -> 'unmapped', '[]');
            perform b2b.mapping_queue_add(e.partner_id, v_unmapped, a.lead_id);
            if a.status in ('pushed', 'accepted', 'closed', 'duplicate') then perform b2b.apply_partner_fields(a.id, pr.id, m); end if;
            if v_kind = 'stage' then
              if not coalesce((m -> 'status' ->> 'matched')::boolean, false) then
                v_status := 'held_unmapped';
                v_result := 'stored: unmapped stage ' || (d ->> 'stage') || coalesce(' / ' || (d ->> 'sub_stage'), '');
              elsif (m -> 'status' ->> 'ignored')::boolean then
                v_status := 'ignored';
                v_result := 'ignored stage: ' || (m -> 'status' ->> 'ignore_reason');
              else
                v_result := b2b.apply_partner_mapped_stage(a.id, m -> 'status', d);
                if v_result like 'stage %' and v_result not like 'stage unchanged%' or v_result like 'lost:%' then
                  perform b2b.activity_record(e, a, 'stage_change', m -> 'status' ->> 'stage', m);
                end if;
              end if;
            elsif v_kind = 'activity' then
              if m -> 'activity' is null then
                v_status := 'held_unmapped';
                v_result := 'stored: unmapped activity ' || coalesce(d ->> 'type', '?') || coalesce(' / ' || (d ->> 'outcome'), '');
              else
                begin v_at := least(coalesce((j ->> 'occurred_at')::timestamptz, now()), now()); exception when others then v_at := now(); end;
                perform b2b.log_event('partner.activity', a.lead_id, a.id, a.partner_id,
                                      (m -> 'activity') || jsonb_build_object('occurred_at', v_at, 'partner_type', d ->> 'type', 'partner_outcome', d ->> 'outcome'));
                if m -> 'activity' ->> 'kind' = 'call' then
                  perform b2b.apply_contacted(a.id, jsonb_build_object('occurred_at', v_at, 'data', jsonb_build_object('connected', m -> 'activity' ->> 'outcome' = 'connected')));
                end if;
                perform b2b.activity_record(e, a, m -> 'activity' ->> 'kind', m -> 'activity' ->> 'outcome', m);
                v_result := 'activity ' || (m -> 'activity' ->> 'kind') || coalesce(' / ' || (m -> 'activity' ->> 'outcome'), '');
              end if;
            else
              v_result := 'fields updated';
            end if;
            if jsonb_array_length(v_unmapped) > 0 and v_status = 'applied' then
              v_result := v_result || '; ' || jsonb_array_length(v_unmapped) || ' unmapped item(s) queued';
            end if;
          end if;
        else
          v_status := 'held_unmapped';
          v_result := 'stored: unknown event type';
      end case;
      if v_revive then v_result := v_result || '; back with the partner (lost grace ended early)'; end if;
    end if;
    if v_status = 'applied' and v_result like 'ignored%' then v_status := 'ignored'; end if;
    -- any report from the partner ends a "no status update" stale flag
    update public.student_leads set partner_stale_at = null, updated_by = 'b2b'
     where id = a.lead_id and allocation_id = a.id and partner_stale_at is not null;
    update b2b.partner_events set status = v_status, result = left(v_result, 500), mapped = m, mapping_version = pr.version,
           applied_at = case when v_status in ('applied', 'ignored') then now() end
     where id = e.id;
  exception when others then
    update b2b.partner_events set status = 'error', result = left(sqlerrm, 300) where id = e.id;
    return jsonb_build_object('status', 'error', 'result', left(sqlerrm, 300));
  end;
  return jsonb_build_object('status', v_status, 'result', v_result);
end $fn$;

-- ---------- (14) a mapped stage ----------
/* A mapped stage on the lead: forward only (unless the rule is a reopen); lost starts the grace; a stage other than lost while the
   lead is lost in grace revives it first and is then applied without the forward-only check (the lead's current stage 'lost' has
   rank 999). Duplicate goes through its own path. */
create or replace function b2b.apply_partner_mapped_stage(p_allocation_id bigint, st jsonb, p_raw jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  x jsonb;
  v_stages jsonb := (select value from b2b.settings where key = 'stages');
  v_new text := st ->> 'stage';
  v_rank_new int;
  v_rank_old int;
  v_revived boolean := false;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then return 'ignored: allocation not found'; end if;
  if a.status not in ('pushed', 'accepted') then return 'ignored: allocation is ' || a.status; end if;
  if v_new = 'lost' then
    x := b2b.apply_partner_lost(a.id, jsonb_build_object('lost_reason', st ->> 'lost_reason', 'status', p_raw ->> 'stage', 'sub_status', p_raw ->> 'sub_stage',
                                                          'last_activity_at', p_raw ->> 'occurred_at'));
    return case when x ->> 'status' = 'grace'
                then 'lost: in grace until ' || to_char((x ->> 'grace_until')::timestamptz at time zone 'Asia/Kolkata', 'DD Mon YYYY HH24:MI') || ' IST'
                else 'ignored: ' || coalesce(x ->> 'why', 'not applied') end;
  end if;
  if v_new = 'duplicate_at_partner' then
    return b2b.apply_partner_duplicate(a.id, coalesce(p_raw -> 'fields', '{}') || jsonb_build_object('source', 'mapped_stage'));
  end if;
  -- PART 6.1: a stage other than lost while lost in grace means the partner is working the lead again
  if a.lost_at is not null and a.lost_revived_at is null then
    v_revived := b2b.partner_lost_revive(a.id, null, 'partner stage ' || coalesce(p_raw ->> 'stage', v_new));
  end if;

  select * into l from public.student_leads where id = a.lead_id for update;
  if l.allocation_id is distinct from a.id then return 'stored: the partner no longer holds the lead'; end if;
  select (e ->> 'rank')::int into v_rank_new from jsonb_array_elements(v_stages) e where e ->> 'key' = v_new;
  select (e ->> 'rank')::int into v_rank_old from jsonb_array_elements(v_stages) e where e ->> 'key' = l.stage;
  if not v_revived and v_rank_new < coalesce(v_rank_old, 0) and not coalesce((st ->> 'is_reopen')::boolean, false) then
    perform b2b.log_event('partner.stage_backwards', a.lead_id, a.id, a.partner_id,
                          jsonb_build_object('from', l.stage, 'to', v_new, 'partner_stage', p_raw ->> 'stage', 'partner_sub_stage', p_raw ->> 'sub_stage'));
    return 'stored: not moved back from ' || l.stage || ' to ' || v_new;
  end if;
  if l.stage is not distinct from v_new and l.sub_stage is not distinct from (st ->> 'sub_stage') then
    return 'stage unchanged (' || v_new || ')' || case when v_revived then '; back with the partner' else '' end;
  end if;

  update public.student_leads
     set stage = v_new, sub_stage = st ->> 'sub_stage', stage_changed_at = case when stage is distinct from v_new then now() else stage_changed_at end,
         reopened_at = case when coalesce((st ->> 'is_reopen')::boolean, false) and v_rank_new < coalesce(v_rank_old, 0) then now() else reopened_at end,
         partner_synced_at = now(), updated_by = 'b2b'
   where id = l.id;
  perform b2b.log_event('partner.stage_applied', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('stage', v_new, 'sub_stage', st ->> 'sub_stage', 'from', l.stage, 'partner_stage', p_raw ->> 'stage',
                                           'partner_sub_stage', p_raw ->> 'sub_stage', 'reopen', coalesce((st ->> 'is_reopen')::boolean, false), 'revived', v_revived));
  if v_new = 'enrolled' and l.stage is distinct from 'enrolled' then
    perform b2b.log_event('lead.enrolled', a.lead_id, a.id, a.partner_id, jsonb_build_object('source', 'partner_stage', 'partner_stage', p_raw ->> 'stage'));
  end if;
  return 'stage ' || v_new || coalesce(' / ' || (st ->> 'sub_stage'), '') || case when v_revived then '; back with the partner' else '' end;
end $fn$;

-- ---------- (15) SLA clocks ----------
/* Opens, meets and breaches the SLA clocks (m16b). PART 6.1: no status update is owed while the lead is lost in grace, so pending
   status_update checks of an allocation in grace are voided (keyed on the allocation, counted as voided_in_grace); the clock
   restarts on revival (partner_lost_revive). */
create or replace function b2b.sla_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  al b2b.allocations;
  v_met timestamptz;
  n_open int := 0;
  n_met int := 0;
  n_breach int := 0;
  n_void int := 0;
  n_void_grace int := 0;
  v_n int;
begin
  perform set_config('b2b.actor', 'system', true);
  -- 1. clocks open when a lead reaches the partner (pushed in the last 60 days)
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
  select a.id, a.lead_id, a.partner_id, s.sla, a.pushed_at, s.due, a.is_test
    from (select * from b2b.allocations y
           where y.destination_type = 'partner' and y.pushed_at is not null and y.pushed_at > now() - interval '60 days'
             and y.status in ('pushed', 'accepted', 'closed')
             and not exists (select 1 from b2b.sla_checks c where c.allocation_id = y.id)) a
   cross join lateral (values
     ('first_attempt', b2b.working_deadline(a.partner_id, a.pushed_at, 60 * b2b.partner_sla(a.partner_id, 'first_contact_hours'))),
     ('first_connect', b2b.working_days_deadline(a.partner_id, a.pushed_at, b2b.partner_sla(a.partner_id, 'first_connect_days'))),
     ('counselling_outcome', b2b.working_days_deadline(a.partner_id, a.pushed_at, b2b.partner_sla(a.partner_id, 'outcome_days'))),
     ('status_update', a.pushed_at + make_interval(days => b2b.partner_sla(a.partner_id, 'status_update_days')))) s(sla, due)
  on conflict do nothing;
  get diagnostics v_n = row_count; n_open := n_open + v_n;

  -- enrollment proof: from the partner's "enrolled", proof due within proof_days calendar days
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
  select a.id, a.lead_id, a.partner_id, 'enrollment_proof', s.t0, s.t0 + make_interval(days => b2b.partner_sla(a.partner_id, 'proof_days')), a.is_test
    from b2b.allocations a
    cross join lateral (select coalesce(
             (select min(x.occurred_at) from b2b.partner_activities x where x.allocation_id = a.id and x.kind = 'stage_change' and x.outcome = 'enrolled'),
             (select l.stage_changed_at from public.student_leads l where l.id = a.lead_id and l.allocation_id = a.id and l.stage = 'enrolled')) as t0) s
   where a.destination_type = 'partner' and a.pushed_at > now() - interval '180 days' and s.t0 is not null
     and exists (select 1 from b2b.sla_checks c where c.allocation_id = a.id)
     and not exists (select 1 from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'enrollment_proof')
  on conflict do nothing;
  get diagnostics v_n = row_count; n_open := n_open + v_n;

  -- 2a. PART 6.1: no status update is owed while the lead is lost in grace (keyed on the allocation, not the lead's stage)
  update b2b.sla_checks c set status = 'void', updated_at = now()
    from b2b.allocations y
   where y.id = c.allocation_id and c.status = 'pending' and c.sla = 'status_update'
     and y.lost_at is not null and y.lost_revived_at is null and y.status in ('pushed', 'accepted');
  get diagnostics n_void_grace = row_count;

  -- 2b. a partner that never held the lead owes nothing; status updates stop once the lead leaves the partner or is enrolled
  update b2b.sla_checks c set status = 'void', updated_at = now()
    from b2b.allocations y
   where y.id = c.allocation_id and c.status = 'pending'
     and (y.status in ('duplicate', 'rejected', 'recalled', 'failed')
          or (c.sla = 'status_update' and (y.status not in ('pushed', 'accepted')
              or exists (select 1 from public.student_leads l where l.id = y.lead_id and l.allocation_id = y.id
                           and l.stage in ('enrolled', 'verified', 'commission_booked', 'paid', 'lost')))));
  get diagnostics n_void = row_count;
  update public.student_leads l set partner_stale_at = null, updated_by = 'b2b'
   where l.partner_stale_at is not null
     and not exists (select 1 from b2b.allocations y where y.id = l.allocation_id and y.status in ('pushed', 'accepted'));

  -- 3. met, or breached
  for r in select c.* from b2b.sla_checks c
            where c.status = 'pending' or (c.status = 'breached' and c.due_at > now() - interval '30 days')
            order by c.due_at limit 5000 loop
    select * into al from b2b.allocations where id = r.allocation_id;
    v_met := b2b.sla_met_at(r.sla, al, r.started_at);
    if v_met is not null then
      update b2b.sla_checks set met_at = v_met, status = case when v_met <= r.due_at then 'met' else 'met_late' end, updated_at = now() where id = r.id;
      n_met := n_met + 1;
      if r.sla = 'status_update' and al.status in ('pushed', 'accepted') and not (al.lost_at is not null and al.lost_revived_at is null) then
        insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
        values (al.id, al.lead_id, al.partner_id, 'status_update', v_met, v_met + make_interval(days => b2b.partner_sla(al.partner_id, 'status_update_days')), al.is_test)
        on conflict do nothing;
      end if;
    elsif r.status = 'pending' and r.due_at < now() then
      update b2b.sla_checks set status = 'breached', breached_at = now(), updated_at = now() where id = r.id;
      n_breach := n_breach + 1;
      if r.sla = 'first_attempt' then
        perform b2b.log_event('alert.sla_breach', r.lead_id, r.allocation_id, r.partner_id,
                              jsonb_build_object('sla', r.sla, 'due_at', r.due_at, 'is_test', r.is_test));
      elsif r.sla = 'status_update' then
        update public.student_leads set partner_stale_at = now(), updated_by = 'b2b'
         where id = r.lead_id and allocation_id = r.allocation_id and partner_stale_at is null;
        perform b2b.log_event('lead.stale', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('last_update_at', r.started_at, 'due_at', r.due_at));
      else
        perform b2b.log_event('partner.sla_breached', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('sla', r.sla, 'due_at', r.due_at));
      end if;
    end if;
  end loop;
  return jsonb_build_object('opened', n_open, 'met', n_met, 'breached', n_breach, 'voided', n_void, 'voided_in_grace', n_void_grace);
end $fn$;

-- ---------- (16) enrolments ----------
/* A partner enrollment (m20b). p: enrolled_on, fee_amount_inr, fee_paid_inr, programme_id, proof_ref. Idempotent per allocation.
   Addendum 3 (critic B8): an upheld duplicate dispute earns nothing ({status 'no_earnings'}); an enrolment reported after the lost
   grace, with no upheld late-activity dispute, opens or joins a late_activity_after_lost dispute and books nothing ({status
   'disputed', dispute_id}); an enrolment reported while lost in grace revives the lead first and is then booked as before. */
create or replace function b2b.enrollment_record(p_allocation_id bigint, p jsonb, p_source text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  c public.catalog_programs;
  v_uni text;
  v_id bigint;
  v_on date;
  v_prog bigint;
  m jsonb;
  x jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.partner_id is null then raise exception 'only partner allocations earn partner commission' using errcode = '22023'; end if;
  if a.is_test then raise exception 'test leads never earn commission' using errcode = '22023'; end if;
  if a.status not in ('pushed', 'accepted', 'closed') then raise exception 'the partner never held this lead (allocation is %)', a.status using errcode = '22023'; end if;
  select id into v_id from public.enrollments where allocation_id = a.id and status <> 'cancelled';
  if v_id is not null then return jsonb_build_object('id', v_id, 'existing', true); end if;

  -- PART 5.8: an upheld duplicate claim after acceptance leaves no commission on this lead
  if a.outcome = 'duplicate_upheld'
     or exists (select 1 from b2b.commission_disputes d where d.allocation_id = a.id and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance') then
    perform b2b.log_event('money.enrollment_not_booked', a.lead_id, a.id, a.partner_id, jsonb_build_object('source', p_source, 'why', 'duplicate_upheld', 'enrollment', p));
    return jsonb_build_object('status', 'no_earnings', 'why', 'duplicate_upheld');
  end if;
  -- PART 6.1: an enrolment after the lead moved to B2C is a commission dispute first; it earns once the Admin upholds it
  if a.status = 'closed' and a.outcome = 'lost'
     and not exists (select 1 from b2b.commission_disputes d where d.allocation_id = a.id and d.status = 'upheld' and d.kind = 'late_activity_after_lost') then
    x := b2b.late_activity_dispute(a.id, null, jsonb_build_object('source', p_source, 'enrollment', coalesce(p, '{}'), 'at', now()));
    return jsonb_build_object('status', 'disputed', 'dispute_id', (x ->> 'dispute_id')::bigint, 'why', 'enrolment reported after the lead moved to B2C');
  end if;
  -- PART 6.1: an enrolment inside the grace brings the lead back to the partner (never followed by a bar)
  if a.lost_at is not null and a.lost_revived_at is null and a.status in ('pushed', 'accepted') then
    perform b2b.partner_lost_revive(a.id, null, 'enrolment reported (' || coalesce(p_source, '?') || ')');
    select * into a from b2b.allocations where id = a.id;
  end if;

  select * into l from public.student_leads where id = a.lead_id;
  v_on := coalesce(nullif(p ->> 'enrolled_on', '')::date, l.enrollment_date, (l.stage_changed_at at time zone 'Asia/Kolkata')::date, current_date);
  if v_on > current_date then raise exception 'the enrolment date is in the future' using errcode = '22023'; end if;
  if v_on < (a.created_at at time zone 'Asia/Kolkata')::date then raise exception 'the enrolment date is before the lead was sent to the partner' using errcode = '22023'; end if;
  v_prog := coalesce(nullif(p ->> 'programme_id', '')::bigint, a.programme_id);
  select * into c from public.catalog_programs where id = v_prog;
  select name into v_uni from public.catalog_universities where id = c.university_id;

  insert into public.enrollments (lead_id, cycle_no, university_id, university_name, programme_id, programme_name, fee_amount_inr, fee_paid_inr,
                                  enrolled_on, destination_type, partner_id, status, proof_ref, reported_by, allocation_id, source_product)
  values (a.lead_id, a.cycle_no, c.university_id, v_uni, c.id, coalesce(c.program_name, nullif(trim(concat_ws(' ', c.course, c.specialization)), '')),
          coalesce(nullif(p ->> 'fee_amount_inr', '')::numeric, l.fee_amount_inr), coalesce(nullif(p ->> 'fee_paid_inr', '')::numeric, l.fee_paid_inr),
          v_on, 'partner', a.partner_id, 'reported', nullif(left(trim(p ->> 'proof_ref'), 300), ''), auth.uid(), a.id, 'b2b')
  returning id into v_id;
  m := b2b.enrollment_expect(v_id);

  if l.allocation_id is not distinct from a.id then
    update public.student_leads
       set expected_net_revenue_inr = case when m ? 'error' then expected_net_revenue_inr else (m ->> 'net')::numeric end,
           enrollment_date = coalesce(enrollment_date, v_on), enrolled_program = coalesce(enrolled_program, c.program_name),
           enrolled_university = coalesce(enrolled_university, v_uni), enrollment_status = 'reported', updated_by = 'b2b'
     where id = l.id;
    perform b2b.lead_stage_up(l.id, 'enrolled');
  end if;
  perform b2b.log_event('money.enrollment_reported', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('enrollment_id', v_id, 'source', p_source, 'enrolled_on', v_on, 'expected_net_inr', m -> 'net', 'problem', m -> 'error'));
  return jsonb_build_object('id', v_id, 'existing', false, 'amounts', m);
end $fn$;

-- ---------- (17) the student's message ----------
/* Queues the student's notifications for one accepted allocation (m9a), idempotent per allocation, channel and kind. PART 5.2 /
   5.8 / 6.1: skipped (with the reason) while the lead is lost in grace or a duplicate was claimed after acceptance. D20: when an
   'accepted' message for the same lead and cycle already went out for another allocation, the kind is 'reroute_update' (the student
   is told the counsellor changed, not welcomed twice). A kind without an active template is skipped with 'no active template'. */
create or replace function b2b.notify_accepted(p_allocation_id bigint)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  p b2b.partners;
  l public.student_leads;
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_lang text;
  v_vars jsonb;
  v_test boolean;
  v_slot timestamptz := b2b.notify_slot(now());
  v_hold text;
  v_kind text := 'accepted';
  ch text;
  v_to text;
  v_skip text;
  t b2b.message_templates;
  n int := 0;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null or a.destination_type <> 'partner' or a.status <> 'accepted' then return 0; end if;
  select * into p from b2b.partners where id = a.partner_id;
  select * into l from public.student_leads where id = a.lead_id;
  v_test := a.is_test or coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_lang := case when lower(coalesce(l.preferred_language, '')) ~ '(hindi|hinglish|^hi)' then 'hi' else 'en' end;
  v_hold := case
    when a.lost_at is not null and a.lost_revived_at is null then 'lost, in grace'
    when exists (select 1 from b2b.commission_disputes d where d.allocation_id = a.id and d.kind = 'duplicate_after_acceptance' and d.status in ('open', 'upheld'))
      then 'duplicate claimed after acceptance' end;
  if exists (select 1 from b2b.student_notifications x join b2b.allocations y on y.id = x.allocation_id
              where x.lead_id = a.lead_id and x.allocation_id <> a.id and x.kind = 'accepted' and y.cycle_no = a.cycle_no
                and x.status in ('sending', 'sent', 'delivered', 'read')) then
    v_kind := 'reroute_update';
  end if;
  v_vars := jsonb_build_object(
    'student_first_name', coalesce(nullif(split_part(trim(coalesce(l.student_name, '')), ' ', 1), ''), 'there'),
    'programme_label', b2b.allocation_programme_label(a),
    'partner_display_name', coalesce(p.display_name, p.name),
    'expected_contact_window', b2b.contact_window(p, v_slot),
    'eduwit_support_contact', coalesce(s ->> 'support_contact', 'support@eduwit.in'),
    'partner_logo_url', p.logo_url);

  foreach ch in array array['whatsapp', 'email'] loop
    select * into t from b2b.message_templates where kind = v_kind and channel = ch and language = v_lang;
    if t.id is null then select * into t from b2b.message_templates where kind = v_kind and channel = ch and language = 'en'; end if;
    v_to := case ch when 'whatsapp' then nullif(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), '') else nullif(trim(l.email_id), '') end;
    v_skip := case
      when v_test then 'test lead: never sent on a live channel'
      when v_hold is not null then v_hold
      when not coalesce(p.notify_enabled, true) then 'notifications are off for this partner'
      when coalesce(l.is_opted_out, false) or ch = any (coalesce(l.opted_out_channels, '{}')) then 'student opted out'
      when ch = 'email' and l.email_bounced_at is not null then 'email bounced before'
      when v_to is null then case ch when 'whatsapp' then 'no phone number' else 'no email address' end
      when t.id is null or t.status <> 'active' then 'no active template'
    end;
    insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, template_id, language, variables, recipient,
                                           status, scheduled_for, error)
    values (a.lead_id, a.id, a.partner_id, v_kind, ch, t.id, coalesce(t.language, v_lang), v_vars, v_to,
            case when v_skip is null then 'scheduled' else 'skipped' end, case when v_skip is null then v_slot end, v_skip)
    on conflict (allocation_id, channel, kind) do nothing;
    if found and v_skip is null then n := n + 1; end if;
  end loop;
  return n;
end $fn$;

-- ---------- (18) the sender ----------
/* Sends due student notifications (m9b). Due messages are also cancelled when the allocation is lost in grace or disputed. */
create or replace function b2b.notify_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_retry int := coalesce((s ->> 'retry_after_minutes')::int, 5);
  r record;
  n b2b.student_notifications;
  j jsonb;
  req jsonb;
  v_net bigint;
  v_sent int := 0;
  v_done int := 0;
  v_why text;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    select x.id, x.attempts, x.lead_id, x.allocation_id, x.partner_id, x.channel, x.updated_at, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null as done
      from b2b.student_notifications x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 200
  loop
    if not r.done and r.updated_at > now() - interval '2 minutes' then continue; end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.student_notifications set status = 'sent', sent_at = now(), updated_at = now(), net_request_id = null, error = null,
             provider_message_id = left(coalesce(j -> 'messages' -> 0 ->> 'id', j ->> 'id', j ->> 'messageId'), 200)
       where id = r.id;
      perform b2b.log_event('notification.sent', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'notification_id', r.id));
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer from the provider' end,
                             'HTTP ' || r.status_code || ': ' || coalesce(j -> 'error' ->> 'message', j ->> 'message', left(r.content, 200))), 300);
      if r.attempts < 2 then
        update b2b.student_notifications set status = 'scheduled', scheduled_for = now() + make_interval(mins => v_retry), net_request_id = null,
               error = v_why, updated_at = now() where id = r.id;
      else
        update b2b.student_notifications set status = 'failed', net_request_id = null, error = v_why, updated_at = now() where id = r.id;
        perform b2b.log_event('alert.notification_failed', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'error', v_why));
      end if;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due messages
  for n in
    select * from b2b.student_notifications where status = 'scheduled' and scheduled_for <= now()
     order by scheduled_for limit 50 for update skip locked
  loop
    begin
      v_why := case
        when not exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.status = 'accepted') then 'the allocation is no longer accepted'
        when exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.lost_at is not null and a.lost_revived_at is null) then 'lost, in grace'
        when exists (select 1 from b2b.commission_disputes d where d.allocation_id = n.allocation_id and d.kind = 'duplicate_after_acceptance'
                        and d.status in ('open', 'upheld')) then 'duplicate claimed after acceptance'
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and (coalesce(l.is_opted_out, false) or coalesce(l.is_test, false)
                                                                                       or b2b.is_test_phone(l.whatsapp_number))) then 'student opted out or is a test lead'
        when not b2b.is_live(n.channel) then n.channel || ' is switched off'
      end;
      if v_why is not null then
        update b2b.student_notifications set status = 'cancelled', error = v_why, updated_at = now() where id = n.id;
        continue;
      end if;
      req := b2b.notify_request(n);
      if req ? 'error' then
        update b2b.student_notifications set status = 'failed', error = req ->> 'error', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', req ->> 'error'));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 15000);
      update b2b.student_notifications set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider',
             updated_at = now() where id = n.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.student_notifications set status = 'failed', error = left(sqlerrm, 300), updated_at = now() where id = n.id;
      perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $fn$;

-- ---------- (19) templates for a changed partner (critic B10) ----------
-- Drafts until the Admin activates them (the WhatsApp copy needs Meta's approval as 'eduwit_partner_changed').
insert into b2b.message_templates (kind, channel, language, subject, body, wa_template, wa_language) values
  ('reroute_update', 'whatsapp', 'en', null,
   'Hi {{student_first_name}}, an update about {{programme_label}}: an academic counsellor from {{partner_display_name}} will now contact you {{expected_contact_window}} to guide you on admission and next steps. If you need help in the meantime, contact Eduwit at {{eduwit_support_contact}}. — Team Eduwit',
   'eduwit_partner_changed', 'en'),
  ('reroute_update', 'whatsapp', 'hi', null,
   'Hi {{student_first_name}}, {{programme_label}} ke baare mein ek update: ab {{partner_display_name}} ke academic counsellor aapko {{expected_contact_window}} contact karenge aur admission aur next steps mein help karenge. Tab tak koi help chahiye to Eduwit se {{eduwit_support_contact}} par contact karein. — Team Eduwit',
   'eduwit_partner_changed', 'hi'),
  ('reroute_update', 'email', 'en', 'An update: your counsellor will now be from {{partner_display_name}}',
   E'Hi {{student_first_name}},\n\nAn update about {{programme_label}}: an academic counsellor from {{partner_display_name}} will now contact you {{expected_contact_window}} to guide you on admission and next steps.\n\nIf you need help in the meantime, contact Eduwit at {{eduwit_support_contact}}.\n\nTeam Eduwit',
   null, null),
  ('reroute_update', 'email', 'hi', 'Update: aapke counsellor ab {{partner_display_name}} se honge',
   E'Hi {{student_first_name}},\n\n{{programme_label}} ke baare mein ek update: ab {{partner_display_name}} ke academic counsellor aapko {{expected_contact_window}} contact karenge aur admission aur next steps mein help karenge.\n\nTab tak koi help chahiye to Eduwit se {{eduwit_support_contact}} par contact karein.\n\nTeam Eduwit',
   null, null)
on conflict (kind, channel, language) do nothing;

-- ---------- (20) disputes: the Admin decides ----------
/* Kind-aware (m8c). An upheld duplicate_after_acceptance: no commission on the lead (outcome duplicate_upheld; reported enrolments
   cancelled through the money engine's cancel path) and the allocation leaves the conversion statistics (m31c, by the dispute row).
   An upheld late_activity_after_lost lets the later enrolment earn (enrollment_record books it once the dispute is upheld). */
create or replace function b2b.dispute_resolve(p_id bigint, p_uphold boolean, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  d b2b.commission_disputes;
  r record;
  n_cancelled int := 0;
  n_verified int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required' using errcode = '22023'; end if;
  update b2b.commission_disputes set status = case when p_uphold then 'upheld' else 'rejected' end, note = left(trim(p_note), 300),
         resolved_at = now(), resolved_by = auth.uid()::text
   where id = p_id and status = 'open' returning * into d;
  if d.id is null then raise exception 'dispute not found or already resolved' using errcode = 'P0002'; end if;
  if p_uphold and d.kind = 'duplicate_after_acceptance' then
    -- PART 5.8: no commission on this lead; it is left out of conversion statistics
    update b2b.allocations set outcome = 'duplicate_upheld', outcome_at = now(), updated_at = now() where id = d.allocation_id;
    for r in select e.id from public.enrollments e where e.allocation_id = d.allocation_id and e.status = 'reported' and e.source_product = 'b2b' order by e.id loop
      perform b2b.enrollment_cancel(r.id, 'duplicate claim upheld (dispute ' || d.id || ')');
      n_cancelled := n_cancelled + 1;
    end loop;
    select count(*) into n_verified from public.enrollments e where e.allocation_id = d.allocation_id and e.status = 'verified';
  end if;
  perform b2b.log_event('dispute.resolved', d.lead_id, d.allocation_id, d.partner_id,
                        jsonb_build_object('upheld', p_uphold, 'kind', d.kind, 'note', left(trim(p_note), 300), 'enrolments_cancelled', n_cancelled,
                                           'verified_enrolments_to_refund', n_verified));
end $fn$;

-- ---------- (21) push health ----------
/* Push health for the Routing overview and the partner page (m8c). Disputes carry their kind. */
create or replace function b2b.push_overview(p_partner_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from b2b.allocations
                            where destination_type = 'partner' and (p_partner_id is null or partner_id = p_partner_id)
                              and created_at > now() - interval '30 days' group by 1) x), '{}'),
    'retrying', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'reference', a.reference, 'lead_id', a.lead_id, 'partner_id', a.partner_id,
                            'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id),
                            'attempts', a.push_attempts, 'next_push_at', a.next_push_at, 'last_error', a.last_error) order by a.next_push_at)
                          from b2b.allocations a where a.status = 'pushing' and a.push_attempts > 0 and a.last_error is not null
                            and (p_partner_id is null or a.partner_id = p_partner_id)), '[]'),
    'requests', coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object('reference', a.reference) order by q.sent_at desc)
                          from (select * from b2b.push_requests q where p_partner_id is null or q.allocation_id in (select id from b2b.allocations where partner_id = p_partner_id)
                                 order by sent_at desc limit 20) q join b2b.allocations a on a.id = q.allocation_id), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'partner_id', e.partner_id, 'event_type', e.event_type, 'reference', e.reference,
                            'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.received_at desc)
                        from (select * from b2b.partner_events where p_partner_id is null or partner_id = p_partner_id order by received_at desc limit 20) e), '[]'),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'lead_id', d.lead_id, 'lead_name', l.student_name, 'reference', a.reference,
                            'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.partner_id),
                            'existing_record_id', d.existing_record_id, 'existing_created_at', d.existing_created_at, 'existing_created_on', d.existing_created_on,
                            'partner_event_id', d.partner_event_id, 'also', jsonb_array_length(d.also), 'created_at', d.created_at) order by d.created_at desc)
                          from b2b.commission_disputes d join b2b.allocations a on a.id = d.allocation_id left join public.student_leads l on l.id = d.lead_id
                         where d.status = 'open' and (p_partner_id is null or d.partner_id = p_partner_id)), '[]'),
    'lost_in_grace', (select count(*) from b2b.allocations a where a.destination_type = 'partner' and a.lost_at is not null and a.lost_revived_at is null
                        and a.status in ('pushed', 'accepted') and (p_partner_id is null or a.partner_id = p_partner_id)),
    'duplicate_rate_7d', (select round(count(*) filter (where status = 'duplicate')::numeric / nullif(count(*) filter (where status in ('duplicate', 'pushed', 'accepted', 'rejected', 'closed')), 0), 3)
                            from b2b.allocations where destination_type = 'partner' and not is_test and created_at > now() - interval '7 days'
                              and (p_partner_id is null or partner_id = p_partner_id)));
end $fn$;

-- ---------- (22) the push payload ----------
/* The standard payload (m15c). PART 4 'Several interests': the note lists every stated interest ('Interested in … Also asked
   about: …', up to 500 characters); the structured interests[] array only when partners.push_options.interests_array is true
   (D44: strict partner APIs may reject unknown keys). */
create or replace function b2b.push_payload_base(a b2b.allocations)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  l public.student_leads;
  c record;
  v_prev text;
  v_list jsonb;
  v_rank int;
  v_main text;
  v_others text;
  v_course text;
  v_spec text;
  v_arr boolean;
  v_out jsonb;
begin
  select * into l from public.student_leads where id = a.lead_id;
  select u.name as university, cp.course, cp.specialization, cp.level, cp.mode, o.partner_course_code
    into c from public.catalog_programs cp
    left join public.catalog_universities u on u.id = cp.university_id
    left join b2b.partner_programmes o on o.partner_id = a.partner_id and o.programme_id = cp.id and o.valid_to is null
   where cp.id = a.programme_id;
  select p.reference into v_prev from b2b.allocations p
   where p.lead_id = a.lead_id and p.partner_id = a.partner_id and p.id <> a.id and p.status in ('accepted', 'closed') order by p.created_at desc limit 1;
  v_list := coalesce(b2b.lead_interest_list(l), '[]'::jsonb);
  v_rank := greatest(coalesce(a.interest_rank, 1)::int, 1);
  v_course := coalesce(c.course, v_list -> (v_rank - 1) ->> 'course_text', nullif(l.interested_course, ''));
  v_spec := coalesce(c.specialization, v_list -> (v_rank - 1) ->> 'specialization', nullif(l.interested_specialization, ''));
  v_main := case when v_course is not null then 'Interested in ' || v_course || coalesce(' (' || v_spec || ')', '') end;
  select string_agg((x ->> 'course_text') || coalesce(' (' || (x ->> 'specialization') || ')', ''), ', ' order by (x ->> 'rank')::int)
    into v_others
    from jsonb_array_elements(v_list) x where (x ->> 'rank')::int <> v_rank and nullif(trim(x ->> 'course_text'), '') is not null;
  v_arr := coalesce((select (p.push_options ->> 'interests_array')::boolean from b2b.partners p where p.id = a.partner_id), false);
  v_out := jsonb_strip_nulls(jsonb_build_object(
    'reference', a.reference,
    'test', a.is_test,
    'student', jsonb_build_object(
      'name', nullif(trim(l.student_name), ''), 'phone', '+' || regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'),
      'email', nullif(trim(l.email_id), ''), 'city', coalesce(nullif(l.city, ''), nullif(l.current_city_country, '')), 'state', nullif(l.state, ''),
      'preferred_language', nullif(l.preferred_language, '')),
    'programme', jsonb_build_object(
      'university', c.university, 'course', coalesce(c.course, nullif(l.interested_course, '')),
      'specialization', coalesce(c.specialization, nullif(l.interested_specialization, '')),
      'level', coalesce(c.level, nullif(l.program_level, '')), 'mode', coalesce(c.mode, nullif(l.study_mode_preference, '')),
      'partner_course_code', c.partner_course_code),
    'profile', jsonb_build_object(
      'highest_qualification', nullif(l.highest_qualification, ''), 'academic_score_pct', l.academic_score_pct,
      'work_experience_years', l.work_experience_years_num, 'enrollment_timeline', nullif(l.enrollment_timeline, '')),
    'note', left(concat_ws('. ',
              v_main,
              case when v_others is not null then 'Also asked about: ' || v_others end,
              case when coalesce(c.mode, l.study_mode_preference) is not null then 'Mode: ' || coalesce(c.mode, l.study_mode_preference) end,
              case when nullif(l.enrollment_timeline, '') is not null then 'Wants to start: ' || l.enrollment_timeline end), 500),
    'returning_lead', v_prev is not null,
    'previous_reference', v_prev,
    'sent_at', now()));
  if v_arr then
    v_out := v_out || jsonb_build_object('interests', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'rank', (x ->> 'rank')::int, 'course', x ->> 'course_text', 'course_key', x ->> 'course_key', 'specialization', x ->> 'specialization',
               'level', x ->> 'level', 'mode', x ->> 'mode', 'university', x ->> 'university_text', 'routed', (x ->> 'rank')::int = v_rank)) order by (x ->> 'rank')::int)
        from jsonb_array_elements(v_list) x), '[]'::jsonb));
  end if;
  return v_out;
end $fn$;

-- ---------- (23) partner settings ----------
/* Creates (no id) or updates a partner (m4b). Addendum 3: the hold window is derived from the duplicate handling (PART 5.1:
   a3_fixed.hold_minutes_sync 0 for 'sync', hold_minutes_async 30 otherwise), the duplicate window is fixed at 24 hours, a CRM
   adapter is 'sync' only with the Admin's confirmation that the CRM blocks duplicates on create (dedupe_confirmed, D37), SLA
   overrides may only be stricter than the rulebook (2 working hours, 7 days, 7 days), lead_criteria is validated (D32:
   unknown 'pass' | 'fail') and push_options {interests_array} is kept. */
create or replace function b2b.partner_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id    bigint := nullif(p ->> 'id', '')::bigint;
  v_old   b2b.partners;
  v_new   b2b.partners;
  v_slug  text := lower(trim(p ->> 'slug'));
  v_dedupe text := coalesce(nullif(p ->> 'dedupe_mode', ''), 'async');
  v_wh    jsonb := coalesce(p -> 'working_hours', 'null'::jsonb);
  v_changed text[];
  v_who   text := coalesce(auth.uid()::text, 'system');
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_hold_sync int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_sync'), 0))::int;
  v_hold_async int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_async'), 30))::int;
  v_crit jsonb;
  v_push jsonb;
  v_conf boolean;
  v_adapter text;
  k text;
  v_num numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_slug is null or v_slug !~ '^[a-z0-9][a-z0-9-]{1,39}$' then
    raise exception 'slug: 2 to 40 lowercase letters, digits or hyphens' using errcode = '22023';
  end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if jsonb_typeof(v_wh) = 'object' and not b2b.valid_working_hours(v_wh) then
    raise exception 'working hours: each day closed or open < close (HH:MM)' using errcode = '22023';
  end if;
  if v_dedupe not in ('sync', 'async', 'none') then raise exception 'duplicate handling is sync, async or none' using errcode = '22023'; end if;
  if p ? 'sla' and jsonb_typeof(p -> 'sla') <> 'object' then raise exception 'sla must be an object' using errcode = '22023'; end if;
  if p ? 'sla' then
    -- PART 4 and PART 6.4: the SLAs the engine measures are the rulebook's; a partner may promise more, never less
    for k in select key from jsonb_object_keys(p -> 'sla') key loop
      if jsonb_typeof(p -> 'sla' -> k) = 'null' then continue; end if;
      begin v_num := (p -> 'sla' ->> k)::numeric; exception when others then raise exception 'sla %: a number of hours or days', k using errcode = '22023'; end;
      if v_num is null or v_num < 0 then raise exception 'sla %: a number of hours or days', k using errcode = '22023'; end if;
      if k = 'first_contact_hours' and v_num > 2 then raise exception 'the first-contact SLA is 2 working hours at most (Addendum 3)' using errcode = '22023'; end if;
      if k = 'status_update_days' and v_num > 7 then raise exception 'the status-update SLA is every 7 days at most (Addendum 3)' using errcode = '22023'; end if;
      if k = 'proof_days' and v_num > 7 then raise exception 'enrolment proof is due within 7 days at most (Addendum 3)' using errcode = '22023'; end if;
    end loop;
  end if;
  if p ? 'lead_criteria' then
    v_crit := p -> 'lead_criteria';
    if jsonb_typeof(v_crit) <> 'object' then raise exception 'lead criteria must be an object' using errcode = '22023'; end if;
    for k in select key from jsonb_object_keys(v_crit) key loop
      if k not in ('states_include', 'states_exclude', 'cities_include', 'cities_exclude', 'sources_exclude', 'qualifications_include',
                   'min_academic_pct', 'min_work_experience_years', 'unknown', 'other') then
        raise exception 'unknown lead criterion: %', k using errcode = '22023';
      end if;
      if k in ('states_include', 'states_exclude', 'cities_include', 'cities_exclude', 'sources_exclude', 'qualifications_include') then
        if jsonb_typeof(v_crit -> k) <> 'array'
           or exists (select 1 from jsonb_array_elements(v_crit -> k) x where jsonb_typeof(x) <> 'string' or length(trim(x #>> '{}')) not between 1 and 80)
           or jsonb_array_length(v_crit -> k) > 100 then
          raise exception 'lead criteria %: a list of up to 100 names', replace(k, '_', ' ') using errcode = '22023';
        end if;
      elsif k = 'min_academic_pct' and jsonb_typeof(v_crit -> k) <> 'null' then
        if b2b.stats_num(v_crit -> k) is null or b2b.stats_num(v_crit -> k) not between 0 and 100 then
          raise exception 'minimum academic score: 0 to 100 percent' using errcode = '22023';
        end if;
      elsif k = 'min_work_experience_years' and jsonb_typeof(v_crit -> k) <> 'null' then
        if b2b.stats_num(v_crit -> k) is null or b2b.stats_num(v_crit -> k) not between 0 and 40 then
          raise exception 'minimum work experience: 0 to 40 years' using errcode = '22023';
        end if;
      elsif k = 'unknown' and jsonb_typeof(v_crit -> k) <> 'null' then
        if (v_crit ->> k) not in ('pass', 'fail') then raise exception 'unknown lead data: ''pass'' or ''fail''' using errcode = '22023'; end if;
      elsif k = 'other' and jsonb_typeof(v_crit -> k) not in ('null', 'string') then
        raise exception 'lead criteria other: a short text' using errcode = '22023';
      end if;
    end loop;
  end if;
  if p ? 'push_options' then
    if jsonb_typeof(p -> 'push_options') <> 'object' then raise exception 'push options must be an object' using errcode = '22023'; end if;
    if p -> 'push_options' ? 'interests_array' and jsonb_typeof(p -> 'push_options' -> 'interests_array') not in ('boolean', 'null') then
      raise exception 'push options interests_array: true or false' using errcode = '22023';
    end if;
    v_push := jsonb_build_object('interests_array', coalesce((p -> 'push_options' ->> 'interests_array')::boolean, false));
  end if;

  if v_id is not null then
    select * into v_old from b2b.partners where id = v_id for update;
    if v_old.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
    if v_slug <> v_old.slug and (v_old.status <> 'onboarding' or b2b.is_live('partner:' || v_id)) then
      raise exception 'the slug is fixed once a partner leaves onboarding' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from b2b.partners where slug = v_slug and id is distinct from v_id) then
    raise exception 'slug already used by another partner' using errcode = '23505';
  end if;

  if v_id is null then
    insert into b2b.partners (slug, name, created_by, updated_by) values (v_slug, trim(p ->> 'name'), auth.uid(), v_who)
    returning * into v_old;
    v_id := v_old.id;
  end if;

  -- D37: a CRM adapter blocks duplicates on create only when the Admin confirmed it; 'sync' without that confirmation is refused
  v_conf := case when p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') = 'boolean' then (p ->> 'dedupe_confirmed')::boolean
                 else v_old.dedupe_confirmed_at is not null end;
  v_adapter := coalesce(nullif(p ->> 'adapter_type', ''), v_old.adapter_type);
  if v_dedupe = 'sync' and not v_conf and b2b.adapter_spec(v_adapter) is not null then
    raise exception 'confirm that the CRM rejects duplicates on create (dedupe_confirmed) before choosing a 0-minute hold' using errcode = '22023';
  end if;

  update b2b.partners t set
    slug                   = v_slug,
    name                   = trim(p ->> 'name'),
    display_name           = nullif(trim(p ->> 'display_name'), ''),
    logo_url               = nullif(trim(p ->> 'logo_url'), ''),
    brand_color            = nullif(trim(p ->> 'brand_color'), ''),
    adapter_type           = coalesce(nullif(p ->> 'adapter_type', ''), t.adapter_type),
    api_base_url           = nullif(trim(p ->> 'api_base_url'), ''),
    test_endpoint          = nullif(trim(p ->> 'test_endpoint'), ''),
    dedupe_mode            = v_dedupe,
    hold_minutes           = case when v_dedupe = 'sync' then v_hold_sync else v_hold_async end,
    duplicate_window_hours = 24,
    dedupe_confirmed_at    = case when v_conf then coalesce(t.dedupe_confirmed_at, now()) end,
    push_options           = coalesce(v_push, t.push_options, '{}'::jsonb),
    notify_enabled         = coalesce((p ->> 'notify_enabled')::boolean, false),
    daily_cap              = (p ->> 'daily_cap')::int,
    monthly_cap            = (p ->> 'monthly_cap')::int,
    contract_min_monthly   = (p ->> 'contract_min_monthly')::int,
    working_hours          = case when jsonb_typeof(v_wh) = 'object' then v_wh else t.working_hours end,
    holidays               = coalesce((select array_agg(distinct d::date order by d::date) from jsonb_array_elements_text(p -> 'holidays') d), '{}'),
    sla                    = case when p ? 'sla' then t.sla || (p -> 'sla') else t.sla end,
    lead_criteria          = case when p ? 'lead_criteria' then p -> 'lead_criteria' else t.lead_criteria end,
    notes                  = nullif(trim(p ->> 'notes'), ''),
    updated_at             = now(),
    updated_by             = v_who
  where t.id = v_id
  returning * into v_new;

  select coalesce(array_agg(n.key order by n.key), '{}') into v_changed
    from jsonb_each(to_jsonb(v_new)) n
   where n.key not in ('updated_at', 'updated_by', 'created_at', 'created_by')
     and n.value is distinct from (to_jsonb(v_old) -> n.key);

  if p ->> 'id' is null or p ->> 'id' = '' then
    perform b2b.log_event('partner.created', null, null, v_id, jsonb_build_object('slug', v_slug));
  elsif cardinality(v_changed) > 0 then
    perform b2b.log_event('partner.updated', null, null, v_id, jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;
  return jsonb_build_object('id', v_id, 'changed', to_jsonb(v_changed));
end $fn$;

-- ---------- (24) CRM adapter settings ----------
/* In-house and vendor CRM adapter settings (m21d). D37: the adapter is 'sync' (0-minute hold) only when the Admin confirms that
   the CRM blocks duplicates on create (p.dedupe_confirmed true stamps dedupe_confirmed_at); otherwise 'async' with the 30-minute
   hold ('none' is kept for a CRM that never reports duplicates). */
create or replace function b2b.partner_adapter_save(p_partner_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pt b2b.partners;
  spec jsonb;
  v_env text := coalesce(p ->> 'env', 'live');
  cfg jsonb;
  v_old jsonb := '{}';
  v_new jsonb;
  v_secret_id uuid;
  v_url text;
  k text;
  t text;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_hold_sync int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_sync'), 0))::int;
  v_hold_async int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_async'), 30))::int;
  v_conf boolean;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pt from b2b.partners where id = p_partner_id for update;
  if pt.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  spec := b2b.adapter_spec(pt.adapter_type);
  if spec is null then raise exception 'this partner uses the generic contract; set its API credential instead' using errcode = '22023'; end if;
  if v_env not in ('live', 'sandbox') then raise exception 'environment must be live or sandbox' using errcode = '22023'; end if;
  if p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') not in ('boolean', 'null') then
    raise exception 'dedupe_confirmed: true or false' using errcode = '22023';
  end if;
  cfg := coalesce(pt.outbound_auth -> v_env, '{}');
  if jsonb_typeof(pt.outbound_auth -> 'live') is null and jsonb_typeof(pt.outbound_auth -> 'sandbox') is null then
    -- first adapter save replaces a generic credential shape
    pt.outbound_auth := '{}';
  end if;

  for k in select jsonb_array_elements_text(spec -> 'settings') loop
    t := nullif(trim(coalesce(p -> 'settings' ->> k, cfg ->> k, '')), '');
    if k = 'host' and t is not null and t !~ '^[a-z0-9.-]+\.leadsquared\.com$' then raise exception 'the LeadSquared API host looks like api-in21.leadsquared.com' using errcode = '22023'; end if;
    if k in ('login_url', 'base_url') and t is not null and t !~ '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._/-]*)?$' then raise exception '% must be an https address', k using errcode = '22023'; end if;
    if k in ('api_domain', 'accounts_domain') and t is not null and t !~ '^[a-z0-9.-]+\.zoho(apis)?\.(in|com|eu|com\.au|jp|com\.cn|ca|sa)$' then
      raise exception '% looks like www.zohoapis.in or accounts.zoho.in', k using errcode = '22023';
    end if;
    if k = 'api_version' and t is not null and t !~ '^v\d{2}\.\d$' then raise exception 'the Salesforce API version looks like v60.0' using errcode = '22023'; end if;
    if k = 'client_id' and t is not null and length(t) > 300 then raise exception 'the client ID is too long' using errcode = '22023'; end if;
    if k in ('create_url', 'poll_url') and t is not null and (t !~ '^https://[A-Za-z0-9.-]+(:\d+)?(/\S*)?$' or length(t) > 500) then
      raise exception '% must be an https address', replace(k, '_', ' ') using errcode = '22023';
    end if;
    if k = 'auth_type' and coalesce(t, '') not in ('bearer', 'header', 'basic', 'query', 'none') then raise exception 'choose how the CRM checks Eduwit''s key' using errcode = '22023'; end if;
    if k in ('auth_name', 'since_param') and t is not null and t !~ '^[A-Za-z][A-Za-z0-9_-]{0,59}$' then raise exception '% uses letters, digits, - and _', replace(k, '_', ' ') using errcode = '22023'; end if;
    if k in ('wrap_key', 'record_id_path') and t is not null and t !~ '^[A-Za-z_][A-Za-z0-9_]{0,59}(\.[A-Za-z0-9_]{1,60}){0,4}$' then
      raise exception '% looks like data or data.lead.id', replace(k, '_', ' ') using errcode = '22023';
    end if;
    if k = 'duplicate_status' and t is not null and (t !~ '^\d{3}$' or t::int not between 200 and 599) then raise exception 'the duplicate status is an HTTP code such as 409' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object(k, t);
  end loop;
  foreach k in array array['reference_field', 'status_field'] loop
    if p ? k then
      t := nullif(trim(p ->> k), '');
      if t is not null and t !~ '^[A-Za-z_][A-Za-z0-9_]{0,79}(\.[A-Za-z0-9_]{1,60}){0,4}$' then
        raise exception 'a CRM field name uses letters, digits and underscores (an in-house CRM may use a path such as stage.name)' using errcode = '22023';
      end if;
      cfg := cfg || jsonb_build_object(k, t);
    end if;
  end loop;
  if p ? 'fixed' then
    if jsonb_typeof(p -> 'fixed') <> 'object' or (select count(*) from jsonb_object_keys(p -> 'fixed')) > 20 then raise exception 'fixed values must be at most 20 field: value pairs' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object('fixed', p -> 'fixed');
  end if;
  if p ? 'poll' then cfg := cfg || jsonb_build_object('poll', coalesce((p ->> 'poll')::boolean, true)); end if;
  if p ? 'poll_minutes' then
    if coalesce((p ->> 'poll_minutes')::int, 0) not between 2 and 1440 then raise exception 'poll every 2 to 1,440 minutes' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object('poll_minutes', (p ->> 'poll_minutes')::int);
  end if;

  -- secrets: merged with the stored JSON; every listed secret is required once
  v_secret_id := nullif(cfg ->> 'secret_id', '')::uuid;
  if v_secret_id is not null then begin v_old := b2b.partner_secret(v_secret_id)::jsonb; exception when others then v_old := '{}'; end; end if;
  v_new := v_old;
  for k in select jsonb_array_elements_text(spec -> 'secrets') loop
    t := nullif(p -> 'secrets' ->> k, '');
    if t is not null then
      if length(t) < 8 or length(t) > 4000 then raise exception '% looks wrong (8 to 4,000 characters)', replace(k, '_', ' ') using errcode = '22023'; end if;
      v_new := v_new || jsonb_build_object(k, t);
    end if;
    if nullif(v_new ->> k, '') is null and not (pt.adapter_type = 'inhouse' and cfg ->> 'auth_type' = 'none') then
      raise exception 'the % is required', replace(k, '_', ' ') using errcode = '22023';
    end if;
  end loop;
  for k in select jsonb_array_elements_text(spec -> 'settings') loop
    if k not in ('api_version', 'source', 'base_url', 'accounts_domain', 'api_domain', 'login_url', 'auth_name', 'wrap_key', 'record_id_path',
                 'duplicate_status', 'poll_url', 'since_param') and nullif(cfg ->> k, '') is null then
      raise exception 'the % is required', replace(k, '_', ' ') using errcode = '22023';
    end if;
  end loop;
  if v_new is distinct from v_old or v_secret_id is null then
    if v_secret_id is null then v_secret_id := vault.create_secret(v_new::text, 'b2b_partner_' || pt.id || '_' || v_env || '_crm', 'CRM credentials for partner ' || pt.slug || ' (' || v_env || ')');
    else perform vault.update_secret(v_secret_id, v_new::text); end if;
    -- new credentials: the cached access token is dropped
    update b2b.partner_adapter_state set token_expires_at = null, token_failed_at = null, token_error = null where partner_id = pt.id and env = v_env;
  end if;
  cfg := cfg || jsonb_build_object('secret_id', v_secret_id);
  -- the address shown as the partner's endpoint (pushes are built by the adapter)
  v_url := case pt.adapter_type
    when 'leadsquared' then 'https://' || (cfg ->> 'host')
    when 'zoho' then 'https://' || coalesce(cfg ->> 'api_domain', 'www.zohoapis.in')
    when 'salesforce' then coalesce(cfg ->> 'login_url', case when v_env = 'sandbox' then 'https://test.salesforce.com' else 'https://login.salesforce.com' end)
    when 'hubspot' then 'https://api.hubapi.com'
    when 'meritto' then coalesce(cfg ->> 'base_url', 'https://api.nopaperforms.io')
    when 'inhouse' then cfg ->> 'create_url' end;
  -- an in-house CRM without a changes address reports by webhook only
  if pt.adapter_type = 'inhouse' and nullif(cfg ->> 'poll_url', '') is null then cfg := cfg || jsonb_build_object('poll', false); end if;
  -- D37: the hold window follows the Admin's confirmation that this CRM blocks duplicates on create
  v_conf := case when p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') = 'boolean' then (p ->> 'dedupe_confirmed')::boolean
                 else pt.dedupe_confirmed_at is not null end;
  update b2b.partners
     set outbound_auth = coalesce(pt.outbound_auth, '{}') - 'type' - 'header' || jsonb_build_object(v_env, cfg),
         api_base_url = case when v_env = 'live' then v_url else api_base_url end,
         test_endpoint = case when v_env = 'sandbox' then v_url else test_endpoint end,
         outbound_secret_id = coalesce(outbound_secret_id, case when v_env = 'live' then v_secret_id end),
         dedupe_mode = case when v_conf then 'sync' when pt.dedupe_mode = 'none' then 'none' else 'async' end,
         hold_minutes = case when v_conf then v_hold_sync else v_hold_async end,
         duplicate_window_hours = 24,
         dedupe_confirmed_at = case when v_conf then coalesce(pt.dedupe_confirmed_at, now()) end,
         updated_at = now(), updated_by = auth.uid()::text
   where id = pt.id;
  perform b2b.log_event('partner.adapter_saved', null, null, pt.id, jsonb_build_object('env', v_env, 'adapter', pt.adapter_type,
                        'secrets_changed', v_new is distinct from v_old, 'dedupe_confirmed', v_conf));
  return b2b.partner_adapter_status(pt.id);
end $fn$;

-- ---------- (25) the go-live checklist ----------
/* As m15c, plus 'dedupe': the partner's duplicate handling is settled (a 30-minute hold, or a 0-minute hold the Admin confirmed).
   test_leads stays (sandbox allocations). */
create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', false, 'available', false),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    jsonb_build_object('key', 'credentials', 'done', p.api_base_url is not null and (p.outbound_secret_id is not null or p.outbound_auth ->> 'type' = 'none')
                                                     and p.inbound_secret_id is not null, 'available', true),
    jsonb_build_object('key', 'dedupe',      'done', p.dedupe_mode <> 'sync' or p.dedupe_confirmed_at is not null, 'available', true),
    jsonb_build_object('key', 'mapping',     'done', b2b.mapping_ready(p.id), 'available', true),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')), 'available', true)
  );
$fn$;

-- ---------- cron: the grace timer every 5 minutes ----------
-- An existing job is changed in place (a job paused for the promotion window stays paused); a new one follows the push tick's state.
do $cron$
declare
  v_id bigint;
  v_active boolean;
begin
  select j.jobid into v_id from cron.job j where j.jobname = 'b2b-lost-grace-tick' order by j.jobid limit 1;
  if v_id is null then
    perform cron.schedule('b2b-lost-grace-tick', '*/5 * * * *', 'select b2b.lost_grace_tick()');
    select j.active into v_active from cron.job j where j.jobname = 'b2b-push-tick' order by j.jobid limit 1;
    if v_active is false then
      perform cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname = 'b2b-lost-grace-tick';
    end if;
  else
    perform cron.alter_job(v_id, schedule := '*/5 * * * *', command := 'select b2b.lost_grace_tick()');
  end if;
end $cron$;

-- ---------- grants ----------
-- Replaced functions keep their grants (create or replace). The new internal functions are for the engine only.
revoke execute on function b2b.claim_proof_normalize(jsonb, bigint), b2b.late_activity_dispute(bigint, bigint, jsonb),
                           b2b.partner_lost_revive(bigint, bigint, text), b2b.lost_handoff(bigint), b2b.lost_grace_tick()
  from public, anon, authenticated;
grant execute on function b2b.claim_proof_normalize(jsonb, bigint), b2b.late_activity_dispute(bigint, bigint, jsonb),
                          b2b.partner_lost_revive(bigint, bigint, text), b2b.lost_handoff(bigint), b2b.lost_grace_tick()
  to service_role;
-- the replaced ones, restated
revoke execute on function b2b.apply_duplicate(bigint, jsonb), b2b.apply_rejection(bigint, text), b2b.apply_push_error(bigint, text), b2b.push_dispatch(int),
                           b2b.push_collect(), b2b.apply_partner_duplicate(bigint, jsonb), b2b.apply_partner_lost(bigint, jsonb), b2b.partner_event_apply(bigint),
                           b2b.sla_tick(), b2b.apply_partner_mapped_stage(bigint, jsonb, jsonb), b2b.push_payload_base(b2b.allocations), b2b.notify_accepted(bigint),
                           b2b.notify_tick(), b2b.enrollment_record(bigint, jsonb, text)
  from public, anon, authenticated;
grant execute on function b2b.apply_duplicate(bigint, jsonb), b2b.apply_rejection(bigint, text), b2b.apply_push_error(bigint, text), b2b.push_dispatch(int),
                          b2b.push_collect(), b2b.apply_partner_duplicate(bigint, jsonb), b2b.apply_partner_lost(bigint, jsonb), b2b.partner_event_apply(bigint),
                          b2b.sla_tick(), b2b.apply_partner_mapped_stage(bigint, jsonb, jsonb), b2b.push_payload_base(b2b.allocations), b2b.notify_accepted(bigint),
                          b2b.notify_tick(), b2b.enrollment_record(bigint, jsonb, text)
  to service_role;
revoke execute on function b2b.allocation_partner_lost(bigint, jsonb), b2b.dispute_resolve(bigint, boolean, text), b2b.push_overview(bigint),
                           b2b.partner_save(jsonb), b2b.partner_adapter_save(bigint, jsonb)
  from public, anon;
grant execute on function b2b.allocation_partner_lost(bigint, jsonb), b2b.dispute_resolve(bigint, boolean, text), b2b.push_overview(bigint),
                          b2b.partner_save(jsonb), b2b.partner_adapter_save(bigint, jsonb)
  to authenticated, service_role;
revoke execute on function b2b.partner_checklist(b2b.partners) from public, anon, authenticated;
grant execute on function b2b.partner_checklist(b2b.partners) to service_role;
