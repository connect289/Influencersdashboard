-- m31e_a3_consent: Addendum 3 R8 and PART 7 (partner-sharing consent) and the routing go-live gate (PART 7 prerequisite).
-- Rulebook: docs/B2B_CRM_ADDENDUM_3.md PART 3 R8, PART 7, PART 8.2. Design: plan A3_DESIGN.md D6-D10, section m31e; the
-- interface contract (plan/a3/CONTRACT.md section 3) fixes every signature and shape below.
--
--   (1) b2b.consent_programme_pick(l)          the programme a request names: the first interest with an eligible offer (an
--                                              active partner's published programme), else the first offered one, else the primary
--   (2) b2b.consent_request_text(programme)    the PART 7.2 sentence with {{programme}} filled in
--   (3) b2b.consent_request_publish(id)        publishes one B2C-number request inside engine.consent_requests_per_hour
--                                              (status queued when the hour's budget is spent; requested when an active b2c_crm
--                                              endpoint subscribes to b2c.consent_requested, else unsendable + an alert)
--   (4) b2b.consent_request_create(lead, context, actor)   the R8 ask: Witty W2 (public.w2_consent_request) when it exists and
--                                              the lead chats with Witty, otherwise the B2C CRM; one open request per lead
--   (5) b2b.consent_answer(lead, request, answer, source, evidence)   YES / NO: ledger row, column stamp through
--                                              public.lead_intake, b2c.consent_closed, then the routing effect (route_decide
--                                              'auto' on an unrouted lead, requalify_lead on a qualification-nurture hold)
--   (6) b2b.consent_from_witty(touchpoint)     Witty's consent.partner_requested / granted / declined / request_failed
--                                              touchpoints (dispatched by m31k reenquiry_tick)
--   (7) b2b.consent_tick()                     the fixed 48 h expiry, cancellations, FIFO publishing of queued requests and
--                                              republishing of unsendable ones; cron 'b2b-consent-tick' every minute
--   (8) b2b.consent_request_admin / b2b.consent_record_admin   Admin RPCs (a refusal is always allowed; an Admin YES needs
--                                              engine.consent_admin_yes and a written evidence reference)
--   (9) b2b.b2ccrm_event_ingest  REPLACED (20261006194127_m14b_b2c_contract_admin.sql): adds b2ccrm.partner_consent (a YES needs
--                                              the student's message_id) and b2ccrm.consent_request_sent (48 h from the send)
--  (10) b2b.routing_golive_check / b2b.routing_golive_ack   the go-live checklist (consent texts approved, Witty W1 line,
--                                              B2C endpoint, Witty W2, a live partner) and its acknowledgements (setting golive_acks)
--  (11) b2b.set_live_switch  REPLACED (20261006103941_m2d_api_keys_outbox_switches.sql): 'routing' cannot go live while a
--                                              blocking checklist item fails (22023 lists them); every other scope unchanged
--
-- Nothing is added to public.student_leads. Witty tables are read only (public.w2_conversations). Every function: schema b2b,
-- SECURITY DEFINER, search_path ''. Grants: Admin RPCs to authenticated + service_role; internal functions to service_role.
-- Idempotent: every statement is create or replace / on conflict / guarded.

-- ---------- settings the gate writes (m31a seeds it; kept here so this file stands alone) ----------
insert into b2b.settings (key, value) values ('golive_acks', '{}'::jsonb) on conflict (key) do nothing;

-- ---------- (1) the programme a request names ----------
/* {programme (label), course_key, interest_rank, programme_id, basis 'eligible'|'offered'|'primary'}. Order (D7, critic B19):
   the first interest (b2b.lead_interest_list order) with an offer of an active partner (b2b.interest_offers: live, published,
   in season; no caps), else the first interest any partner offers, else the primary interest. The label comes from the
   catalogue (course, plus the student's specialization in brackets), falling back to the student's own words. */
create or replace function b2b.consent_programme_pick(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_list jsonb := b2b.lead_interest_list(l);
  v_int jsonb;
  v_pick jsonb;
  v_basis text;
  v_prog bigint;
  v_rank int := 0;
  v_label text;
  v_spec text;
begin
  for v_int in select x from jsonb_array_elements(coalesce(v_list, '[]'::jsonb)) x loop
    v_rank := v_rank + 1;
    select o.programme_id into v_prog
      from b2b.interest_offers(v_int, false) o
      join b2b.partners p on p.id = o.partner_id and p.status = 'active'
     order by o.partner_id, o.programme_id limit 1;
    if v_prog is not null then v_pick := v_int; v_basis := 'eligible'; exit; end if;
  end loop;
  if v_pick is null then
    v_rank := 0;
    for v_int in select x from jsonb_array_elements(coalesce(v_list, '[]'::jsonb)) x loop
      v_rank := v_rank + 1;
      select o.programme_id into v_prog from b2b.interest_offers(v_int, false) o order by o.partner_id, o.programme_id limit 1;
      if v_prog is not null then v_pick := v_int; v_basis := 'offered'; exit; end if;
    end loop;
  end if;
  if v_pick is null then
    v_pick := coalesce(v_list -> 0, '{}'::jsonb); v_basis := 'primary'; v_rank := 1; v_prog := null;
  end if;
  if v_prog is not null then
    select c.course into v_label from public.catalog_programs c where c.id = v_prog;
  end if;
  if nullif(trim(coalesce(v_label, '')), '') is null and nullif(trim(coalesce(v_pick ->> 'course_key', '')), '') is not null then
    select c.course into v_label from public.catalog_programs c
     where c.course_key = v_pick ->> 'course_key' and c.active and nullif(trim(coalesce(c.course, '')), '') is not null
     order by c.id limit 1;
  end if;
  v_label := coalesce(nullif(trim(coalesce(v_label, '')), ''), nullif(trim(coalesce(v_pick ->> 'course_text', '')), ''), 'your programme');
  v_spec := nullif(trim(coalesce(v_pick ->> 'specialization', '')), '');
  if v_spec is not null and lower(v_spec) not in ('general', 'any') then v_label := v_label || ' (' || v_spec || ')'; end if;
  return jsonb_build_object('programme', v_label, 'course_key', v_pick ->> 'course_key', 'interest_rank', v_rank,
                            'programme_id', v_prog, 'basis', v_basis);
end $fn$;

-- ---------- (2) the PART 7.2 sentence ----------
create or replace function b2b.consent_request_text(p_programme text)
returns text language sql stable security definer set search_path = '' as $fn$
  select replace(coalesce((select t.body from b2b.consent_texts t where t.version = 'wa_partner_consent:v1'),
                          'To connect you with the best admission counsellor for {{programme}}, may we share your details with our admission partner? Reply YES or NO.'),
                 '{{programme}}', coalesce(nullif(trim(p_programme), ''), 'your programme'));
$fn$;

-- ---------- (3) publishing one B2C-number request ----------
/* Returns {request_id, status, published boolean, expires_at, why}. Only channel b2c_crm in status queued / requested /
   unsendable. Over the hourly budget (requests published in the last hour >= engine.consent_requests_per_hour) the request
   waits as 'queued' (why 'budget'; published_at and expires_at null, so its 48 hours start when it is published). Otherwise
   status 'requested' when an active b2c_crm endpoint subscribes to b2c.consent_requested, else 'unsendable';
   published_at = now(); expires_at = now() + a3_fixed.consent_wait_hours. Events: lead.consent_requested always;
   b2c.consent_requested when requested (the B2C CRM sends the template); alert.consent_unsendable when unsendable. */
create or replace function b2b.consent_request_publish(p_request_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r b2b.consent_requests;
  l public.student_leads;
  e jsonb;
  v_wait int;
  v_budget int;
  v_used int;
  v_sub boolean;
  v_status text;
  v_exp timestamptz;
  v_republish boolean;
begin
  select * into r from b2b.consent_requests x where x.id = p_request_id for update;
  if r.id is null then
    return jsonb_build_object('request_id', p_request_id, 'status', null, 'published', false, 'expires_at', null, 'why', 'request not found');
  end if;
  if r.status not in ('queued', 'requested', 'unsendable') then
    return jsonb_build_object('request_id', r.id, 'status', r.status, 'published', false, 'expires_at', r.expires_at, 'why', 'request is ' || r.status);
  end if;
  if r.channel <> 'b2c_crm' then
    return jsonb_build_object('request_id', r.id, 'status', r.status, 'published', false, 'expires_at', r.expires_at, 'why', 'channel ' || r.channel || ' is sent by Witty');
  end if;
  e := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  v_wait := greatest(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'consent_wait_hours'), 48), 1)::int;
  v_budget := greatest(coalesce(b2b.stats_num(e -> 'consent_requests_per_hour'), 100), 1)::int;
  select count(*) into v_used from b2b.consent_requests x
   where x.channel = 'b2c_crm' and x.published_at > now() - interval '1 hour' and x.id <> r.id;
  if v_used >= v_budget then
    if r.status <> 'queued' or r.published_at is not null or r.expires_at is not null then
      update b2b.consent_requests set status = 'queued', published_at = null, expires_at = null where id = r.id;
    end if;
    return jsonb_build_object('request_id', r.id, 'status', 'queued', 'published', false, 'expires_at', null, 'why', 'budget');
  end if;
  select * into l from public.student_leads x where x.id = r.lead_id;
  v_sub := exists (select 1 from b2b.webhook_endpoints w
                    where w.active and w.consumer = 'b2c_crm' and b2b.event_subscribed(w.events, 'b2c.consent_requested'));
  v_republish := r.published_at is not null;
  v_status := case when v_sub then 'requested' else 'unsendable' end;
  v_exp := now() + make_interval(hours => v_wait);
  update b2b.consent_requests set status = v_status, published_at = now(), expires_at = v_exp where id = r.id returning * into r;
  perform b2b.log_event('lead.consent_requested', r.lead_id, null, null, jsonb_build_object(
    'request_id', r.id, 'context', r.context, 'channel', r.channel, 'programme', r.programme, 'status', r.status,
    'expires_at', r.expires_at, 'republished', v_republish));
  if v_status = 'requested' then
    perform b2b.log_event('b2c.consent_requested', r.lead_id, null, null, jsonb_build_object(
      'request_id', r.id, 'lead_id', r.lead_id, 'context', r.context, 'programme', r.programme,
      'text', b2b.consent_request_text(r.programme), 'text_version', 'wa_partner_consent:v1', 'channel', r.channel,
      'expires_at', r.expires_at,
      'student', jsonb_build_object('name', l.student_name, 'phone', b2b.phone_digits(l.whatsapp_number), 'preferred_language', l.preferred_language)));
  else
    perform b2b.log_event('alert.consent_unsendable', r.lead_id, null, null, jsonb_build_object(
      'request_id', r.id, 'lead_id', r.lead_id, 'why', 'no active B2C CRM endpoint subscribes to b2c.consent_requested'));
  end if;
  return jsonb_build_object('request_id', r.id, 'status', r.status, 'published', true, 'expires_at', r.expires_at, 'why', null);
end $fn$;

-- ---------- (4) the R8 ask ----------
/* p_context: decision (route_decide R8) | nurture (requalify_lead) | admin. Locks the lead. A test lead gets nothing (R1).
   An open request of an older enquiry cycle is cancelled first (the one-open index is per lead); an open request of the
   current cycle is returned with existing = true. Channel 'witty' (PART 7.2: Witty's number for Witty leads) when the lead
   chats with Witty, a public.w2_conversations row exists for its digits and public.w2_consent_request(jsonb) exists with a
   search_path; Witty answering anything but queued = true falls back to the B2C CRM (D6). Context 'decision' also stores
   the lead's wait (b2b.lead_wait_set) until the request expires (now() + 15 min while queued), so the sweep leaves it alone.
   Returns {created, request_id, status, channel, context, programme, programme_course_key, expires_at, published, existing, why}. */
create or replace function b2b.consent_request_create(p_lead_id bigint, p_context text, p_actor jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  r b2b.consent_requests;
  e jsonb;
  v_cycle int;
  v_wait int;
  v_digits text;
  v_pick jsonb;
  v_witty boolean := false;
  v_res jsonb;
  v_pub jsonb;
  v_why text;
begin
  if p_context not in ('decision', 'nurture', 'admin') then
    raise exception 'unknown consent context: %', coalesce(p_context, '(null)') using errcode = '22023';
  end if;
  select * into l from public.student_leads x where x.id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then
    return jsonb_build_object('created', false, 'request_id', null, 'status', null, 'channel', null, 'context', p_context,
                              'programme', null, 'programme_course_key', null, 'expires_at', null, 'published', false,
                              'existing', false, 'why', 'test lead');
  end if;
  e := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  v_cycle := coalesce(l.cycle_no, 1);
  v_wait := greatest(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'consent_wait_hours'), 48), 1)::int;

  -- the lead's open request: an older cycle's is cancelled, the current cycle's is returned as it is
  select * into r from b2b.consent_requests x
   where x.lead_id = l.id and x.status in ('queued', 'requested', 'sent', 'unsendable')
   order by x.created_at desc, x.id desc limit 1 for update;
  if r.id is not null and r.cycle_no <> v_cycle then
    update b2b.consent_requests set status = 'cancelled', closed_at = now() where id = r.id;
    perform b2b.log_event('b2c.consent_closed', l.id, null, null, jsonb_build_object(
      'request_id', r.id, 'lead_id', l.id, 'context', r.context, 'status', 'cancelled', 'answer', null, 'answered_at', null,
      'source', null, 'closed_at', now(), 'why', 'new enquiry cycle'));
    r := null;
  end if;
  if r.id is not null then
    if p_context = 'decision' then
      perform b2b.lead_wait_set(l.id, coalesce(r.expires_at, now() + interval '15 minutes'), 'awaiting partner-sharing consent', l.updated_at);
    end if;
    return jsonb_build_object('created', false, 'request_id', r.id, 'status', r.status, 'channel', r.channel, 'context', r.context,
                              'programme', r.programme, 'programme_course_key', r.evidence -> 'pick' ->> 'course_key',
                              'expires_at', r.expires_at, 'published', r.published_at is not null, 'existing', true,
                              'why', 'an open request exists');
  end if;

  v_pick := b2b.consent_programme_pick(l);
  v_digits := b2b.phone_digits(l.whatsapp_number);
  v_witty := b2b.is_witty_lead(l)
         and v_digits <> ''
         and exists (select 1 from public.w2_conversations c where c.phone = v_digits)
         and to_regprocedure('public.w2_consent_request(jsonb)') is not null
         and exists (select 1 from pg_catalog.pg_proc p cross join lateral unnest(p.proconfig) cfg
                      where p.oid = to_regprocedure('public.w2_consent_request(jsonb)') and cfg like 'search_path=%');
  insert into b2b.consent_requests (lead_id, cycle_no, channel, context, status, text_version, programme, evidence, is_test)
  values (l.id, v_cycle, case when v_witty then 'witty' else 'b2c_crm' end, p_context, 'queued',
          case when v_witty then 'witty_partner_consent_v1' else 'wa_partner_consent:v1' end, v_pick ->> 'programme',
          jsonb_build_object('pick', v_pick) || case when p_actor is not null then jsonb_build_object('requested_by', p_actor) else '{}'::jsonb end,
          false)
  returning * into r;

  if v_witty then
    begin
      execute 'select public.w2_consent_request($1)' into v_res
        using jsonb_build_object('phone', v_digits, 'lead_id', l.id, 'request_id', r.id, 'programme', r.programme,
                                 'not_before', b2b.notify_slot(now()), 'text_version', 'witty_partner_consent_v1');
    exception when others then
      v_res := jsonb_build_object('queued', false, 'error', left(sqlerrm, 300), 'code', sqlstate);
    end;
    if lower(coalesce(v_res ->> 'queued', '')) in ('true', 't') then
      update b2b.consent_requests
         set status = 'requested', published_at = now(), expires_at = now() + make_interval(hours => v_wait),
             evidence = evidence || jsonb_build_object('witty', v_res)
       where id = r.id returning * into r;
      perform b2b.log_event('lead.consent_requested', l.id, null, null, jsonb_build_object(
        'request_id', r.id, 'context', r.context, 'channel', r.channel, 'programme', r.programme, 'status', r.status, 'expires_at', r.expires_at));
    else
      v_witty := false;
      v_why := 'Witty did not queue the request: sent from the B2C number';
      update b2b.consent_requests
         set channel = 'b2c_crm', text_version = 'wa_partner_consent:v1', evidence = evidence || jsonb_build_object('witty_fallback', coalesce(v_res, '{}'::jsonb))
       where id = r.id returning * into r;
    end if;
  end if;
  if not v_witty then
    v_pub := b2b.consent_request_publish(r.id);
    select * into r from b2b.consent_requests x where x.id = r.id;
    if v_pub ->> 'why' = 'budget' then v_why := concat_ws('; ', v_why, 'over the hourly request budget: queued'); end if;
  end if;
  if p_context = 'decision' then
    perform b2b.lead_wait_set(l.id, coalesce(r.expires_at, now() + interval '15 minutes'), 'awaiting partner-sharing consent', l.updated_at);
  end if;
  return jsonb_build_object('created', true, 'request_id', r.id, 'status', r.status, 'channel', r.channel, 'context', r.context,
                            'programme', r.programme, 'programme_course_key', v_pick ->> 'course_key', 'expires_at', r.expires_at,
                            'published', r.published_at is not null, 'existing', false, 'why', v_why);
end $fn$;

-- ---------- (5) the answer ----------
/* p_answer yes | no; p_source b2c_crm | witty | admin. The request: p_request_id (must belong to the lead), else the lead's
   open request, else the latest expired request of the current cycle, else the latest answered request of the cycle (a change
   of mind, e.g. a withdrawal after a YES, must always be recordable), else 22023 'no consent request to answer'.
   Idempotent on (request, answer), on evidence.message_id and on evidence.touchpoint_id (duplicate = true, nothing written).
   Writes one b2b.lead_consents row (given; refused; or withdrawn when partner-sharing consent was given before), marks the
   request answered, logs lead.consent_answered and b2c.consent_closed. A YES on a lead that is not lost, not enrolled, not
   deleted or merged also stamps consent_partner_share_at / consent_text_version through public.lead_intake (source_system
   'b2b', event_type 'consent.partner_share', idempotency_key 'consent:<request>:yes'; both columns are write-once there, so
   the ledger stays the primary record). A withdrawal while a partner holds the lead (pushed / accepted) logs
   alert.consent_withdrawn and alert.partner_optout_notice with the partner id.
   Effects, only while routing is live: an unrouted lead gets lead_waits(now()) and route_decide(lead, true, 'consent <answer>',
   'auto') (errors -> routing.error + wait 'error', effect route_error); a lead in an open qualification-nurture hold gets
   b2b.requalify_lead(lead, 'consent <answer>') (m31k; resolved at run time); any other lead is recorded only.
   Returns {recorded, duplicate, request_id, answer, ledger_id, state, effect, route, why}. */
create or replace function b2b.consent_answer(p_lead_id bigint, p_request_id bigint, p_answer text, p_source text, p_evidence jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  r b2b.consent_requests;
  a b2b.allocations;
  v_ev jsonb := case when jsonb_typeof(p_evidence) = 'object' then p_evidence else '{}'::jsonb end;
  v_msg text;
  v_tp text;
  v_cycle int;
  v_cons jsonb;
  v_state text;
  v_at timestamptz;
  v_ledger bigint;
  v_effect text := 'none';
  v_route jsonb;
  v_why text;
  v_hold jsonb;
  v_live boolean;
begin
  if p_answer not in ('yes', 'no') then raise exception 'the answer must be yes or no' using errcode = '22023'; end if;
  if p_source not in ('b2c_crm', 'witty', 'admin') then
    raise exception 'unknown consent source: %', coalesce(p_source, '(null)') using errcode = '22023';
  end if;
  v_msg := nullif(trim(coalesce(v_ev ->> 'message_id', '')), '');
  v_tp := nullif(trim(coalesce(v_ev ->> 'touchpoint_id', '')), '');
  select * into l from public.student_leads x where x.id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  v_cycle := coalesce(l.cycle_no, 1);

  if p_request_id is not null then
    select * into r from b2b.consent_requests x where x.id = p_request_id for update;
    if r.id is null or r.lead_id <> l.id then raise exception 'no consent request to answer' using errcode = '22023'; end if;
  else
    select * into r from b2b.consent_requests x
     where x.lead_id = l.id and x.status in ('queued', 'requested', 'sent', 'unsendable')
     order by x.created_at desc, x.id desc limit 1 for update;
    if r.id is null then
      select * into r from b2b.consent_requests x
       where x.lead_id = l.id and x.cycle_no = v_cycle and x.status = 'expired'
       order by coalesce(x.expires_at, x.created_at) desc, x.id desc limit 1 for update;
    end if;
    if r.id is null then
      select * into r from b2b.consent_requests x
       where x.lead_id = l.id and x.cycle_no = v_cycle and x.status = 'answered'
       order by x.answered_at desc nulls last, x.id desc limit 1 for update;
    end if;
    if r.id is null then raise exception 'no consent request to answer' using errcode = '22023'; end if;
  end if;

  -- idempotency: the same message or touchpoint, or the same answer on the same request
  if (v_msg is not null and exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'partner_share' and c.evidence ->> 'message_id' = v_msg))
     or (v_tp is not null and exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'partner_share' and c.evidence ->> 'touchpoint_id' = v_tp))
     or (r.answer is not null and r.answer = p_answer) then
    return jsonb_build_object('recorded', false, 'duplicate', true, 'request_id', r.id, 'answer', p_answer, 'ledger_id', null,
      'state', coalesce((select c.state from b2b.lead_consents c where c.request_id = r.id order by c.id desc limit 1),
                        case when coalesce(r.answer, p_answer) = 'yes' then 'given' else 'refused' end),
      'effect', 'none', 'route', null, 'why', 'already recorded');
  end if;

  v_cons := b2b.partner_consent(l);
  v_at := coalesce(b2b.try_timestamptz(v_ev ->> 'answered_at'), now());
  v_at := greatest(least(v_at, now()), r.created_at);
  v_state := case when p_answer = 'yes' then 'given'
                  when coalesce((v_cons ->> 'given')::boolean, false) then 'withdrawn'
                  else 'refused' end;
  insert into b2b.lead_consents (lead_id, purpose, state, at, text_version, source, request_id, evidence, actor)
  values (l.id, 'partner_share', v_state, v_at, r.text_version, p_source, r.id,
          v_ev || jsonb_build_object('answer', p_answer, 'channel', r.channel, 'context', r.context), b2b.actor())
  returning id into v_ledger;
  update b2b.consent_requests
     set status = 'answered', answer = p_answer, answered_at = v_at, answer_source = p_source,
         evidence = evidence || jsonb_build_object('answer_evidence', v_ev), closed_at = coalesce(closed_at, now())
   where id = r.id returning * into r;
  perform b2b.log_event('lead.consent_answered', l.id, null, null, jsonb_build_object(
    'request_id', r.id, 'answer', p_answer, 'source', p_source, 'state', v_state));
  perform b2b.log_event('b2c.consent_closed', l.id, null, null, jsonb_build_object(
    'request_id', r.id, 'lead_id', l.id, 'context', r.context, 'status', 'answered', 'answer', p_answer, 'answered_at', v_at,
    'source', p_source, 'closed_at', r.closed_at));

  -- the column stamp (write-once in lead_intake; skipped when the stamp would reopen a lost or enrolled lead)
  if p_answer = 'yes' and coalesce(l.stage, '') <> 'lost' and l.enrollment_status is null
     and l.deleted_at is null and l.merged_into_id is null then
    begin
      perform public.lead_intake(jsonb_build_object('phone', l.whatsapp_number, 'source_system', 'b2b', 'event_type', 'consent.partner_share',
        'idempotency_key', 'consent:' || r.id || ':yes',
        'lead', jsonb_build_object('consent_partner_share_at', v_at, 'consent_text_version', r.text_version)));
    exception when others then
      v_why := 'column stamp not written: ' || left(sqlerrm, 200);
    end;
  end if;

  if v_state = 'withdrawn' then
    select * into a from b2b.allocations x
     where x.lead_id = l.id and x.destination_type = 'partner' and x.status in ('pushed', 'accepted')
     order by x.created_at desc, x.id desc limit 1;
    if a.id is not null then
      perform b2b.log_event('alert.consent_withdrawn', l.id, a.id, a.partner_id, jsonb_build_object(
        'request_id', r.id, 'allocation_id', a.id, 'partner_id', a.partner_id));
      perform b2b.log_event('alert.partner_optout_notice', l.id, a.id, a.partner_id, jsonb_build_object(
        'allocation_id', a.id, 'partner_id', a.partner_id, 'reference', a.reference, 'source', 'consent_withdrawn'));
    end if;
  end if;

  -- effects
  v_live := b2b.is_live('routing');
  if l.deleted_at is not null or l.merged_into_id is not null or coalesce(l.is_opted_out, false) then
    v_effect := 'none';
    v_why := coalesce(v_why, 'the lead is deleted, merged or opted out');
  elsif l.destination_type is null then
    perform b2b.lead_wait_set(l.id, now(), 'consent ' || p_answer, null);
    if not v_live then
      v_why := coalesce(v_why, 'routing is off: the sweep decides the lead once it is on');
    else
      begin
        v_route := b2b.route_decide(l.id, true, 'consent ' || p_answer, 'auto');
        -- 'routed' only when a decision was committed; a lead that is not ready yet stays with the sweep (wait = now())
        v_effect := case when coalesce((v_route ->> 'committed')::boolean, false) then 'routed' else 'recorded' end;
        if v_effect = 'recorded' then v_why := coalesce(v_why, v_route ->> 'why', v_route ->> 'reason'); end if;
      exception when others then
        v_effect := 'route_error';
        v_why := left(sqlerrm, 300);
        perform b2b.log_event('routing.error', l.id, null, null, jsonb_build_object(
          'where', 'consent_answer', 'error', left(sqlerrm, 300), 'code', sqlstate, 'request_id', r.id));
        perform b2b.lead_wait_set(l.id, now(), 'error', null);
      end;
    end if;
  else
    v_hold := b2b.b2c_hold(l);
    if v_hold is not null and v_hold ->> 'kind' = 'qualification_nurture' and coalesce((v_hold ->> 'open')::boolean, false) then
      if not v_live then
        v_why := coalesce(v_why, 'routing is off');
      elsif to_regprocedure('b2b.requalify_lead(bigint,text)') is null then
        v_effect := 'recorded';
        v_why := coalesce(v_why, 'requalify_lead is not installed yet (m31k)');
      else
        begin
          execute 'select b2b.requalify_lead($1, $2)' into v_route using l.id, 'consent ' || p_answer;
          v_effect := case when coalesce((v_route ->> 'requalified')::boolean, false) then 'requalified' else 'recorded' end;
          v_why := coalesce(v_why, v_route ->> 'why');
        exception when others then
          v_effect := 'route_error';
          v_why := left(sqlerrm, 300);
          perform b2b.log_event('routing.error', l.id, null, null, jsonb_build_object(
            'where', 'consent_answer.requalify', 'error', left(sqlerrm, 300), 'code', sqlstate, 'request_id', r.id));
        end;
      end if;
    else
      v_effect := 'recorded';   -- held by B2C for selling (R4), or with a partner (R3): nothing moves
    end if;
  end if;

  return jsonb_build_object('recorded', true, 'duplicate', false, 'request_id', r.id, 'answer', p_answer, 'ledger_id', v_ledger,
                            'state', v_state, 'effect', v_effect, 'route', v_route, 'why', v_why);
end $fn$;

-- ---------- (6) Witty's consent touchpoints ----------
/* public.touchpoints rows with source_system 'witty' and event_type consent.partner_requested | consent.partner_granted |
   consent.partner_declined | consent.partner_request_failed (dispatched by m31k reenquiry_tick). The request is
   payload.request_id, else the lead's latest Witty-channel request (open first). Returns {handled, action
   'sent'|'answered'|'republished'|'ignored', request_id, why}. */
create or replace function b2b.consent_from_witty(p_touchpoint_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  t public.touchpoints;
  l public.student_leads;
  r b2b.consent_requests;
  v_rid bigint;
  v_res jsonb;
  v_wait int;
  v_sent timestamptz;
begin
  select * into t from public.touchpoints x where x.id = p_touchpoint_id;
  if t.id is null then
    return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', null, 'why', 'touchpoint not found');
  end if;
  if t.source_system <> 'witty' or t.event_type not like 'consent.partner\_%' then
    return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', null, 'why', 'not a Witty consent touchpoint');
  end if;
  select * into l from public.student_leads x where x.id = t.lead_id for update;
  if l.id is null then
    return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', null, 'why', 'lead not found');
  end if;
  begin v_rid := nullif(trim(coalesce(t.payload ->> 'request_id', '')), '')::bigint; exception when others then v_rid := null; end;
  if v_rid is not null then
    select * into r from b2b.consent_requests x where x.id = v_rid and x.lead_id = l.id for update;
  end if;
  if r.id is null then
    select * into r from b2b.consent_requests x where x.lead_id = l.id and x.channel = 'witty'
     order by (x.status in ('queued', 'requested', 'sent', 'unsendable')) desc, x.created_at desc, x.id desc limit 1 for update;
  end if;

  if t.event_type = 'consent.partner_requested' then
    if r.id is null then return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', null, 'why', 'no Witty consent request for this lead'); end if;
    if r.status not in ('queued', 'requested', 'sent') then
      return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', r.id, 'why', 'request is ' || r.status);
    end if;
    v_wait := greatest(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'consent_wait_hours' from b2b.settings s where s.key = 'engine')), 48), 1)::int;
    v_sent := least(t.created_at, now());
    update b2b.consent_requests
       set status = 'sent', sent_at = v_sent, published_at = coalesce(published_at, v_sent), expires_at = v_sent + make_interval(hours => v_wait),
           evidence = evidence || jsonb_build_object('sent_touchpoint_id', t.id, 'sent_message_id', t.payload ->> 'message_id')
     where id = r.id returning * into r;
    if r.context = 'decision' and l.destination_type is null then
      perform b2b.lead_wait_set(l.id, r.expires_at, 'awaiting partner-sharing consent', l.updated_at);
    end if;
    return jsonb_build_object('handled', true, 'action', 'sent', 'request_id', r.id, 'why', null);

  elsif t.event_type in ('consent.partner_granted', 'consent.partner_declined') then
    if exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'partner_share' and c.evidence ->> 'touchpoint_id' = t.id::text) then
      return jsonb_build_object('handled', true, 'action', 'answered', 'request_id', r.id, 'why', 'already recorded');
    end if;
    begin
      v_res := b2b.consent_answer(l.id, r.id, case when t.event_type = 'consent.partner_granted' then 'yes' else 'no' end, 'witty',
                 jsonb_build_object('touchpoint_id', t.id, 'text_version', 'witty_partner_consent_v1',
                                    'message_id', nullif(trim(coalesce(t.payload ->> 'message_id', '')), ''),
                                    'answered_at', t.occurred_at));
    exception when sqlstate '22023' then
      return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', r.id, 'why', sqlerrm);
    end;
    return jsonb_build_object('handled', true, 'action', 'answered', 'request_id', (v_res ->> 'request_id')::bigint, 'why', v_res ->> 'why');

  elsif t.event_type = 'consent.partner_request_failed' then
    if r.id is null then return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', null, 'why', 'no Witty consent request for this lead'); end if;
    if r.status not in ('queued', 'requested', 'sent') then
      return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', r.id, 'why', 'request is ' || r.status);
    end if;
    update b2b.consent_requests
       set channel = 'b2c_crm', text_version = 'wa_partner_consent:v1', status = 'queued', published_at = null, sent_at = null, expires_at = null,
           evidence = evidence || jsonb_build_object('witty_failed', coalesce(t.payload, '{}'::jsonb) || jsonb_build_object('touchpoint_id', t.id))
     where id = r.id;
    v_res := b2b.consent_request_publish(r.id);
    if r.context = 'decision' and l.destination_type is null then
      perform b2b.lead_wait_set(l.id, coalesce((v_res ->> 'expires_at')::timestamptz, now() + interval '15 minutes'), 'awaiting partner-sharing consent', l.updated_at);
    end if;
    return jsonb_build_object('handled', true, 'action', 'republished', 'request_id', r.id,
                              'why', case when v_res ->> 'why' = 'budget' then 'queued: over the hourly budget' else v_res ->> 'status' end);
  end if;
  return jsonb_build_object('handled', false, 'action', 'ignored', 'request_id', r.id, 'why', 'unknown consent event ' || t.event_type);
end $fn$;

-- ---------- (7) the minute tick ----------
/* {expired, cancelled, published, republished}. (a) requested / sent / unsendable requests past expires_at become expired
   (b2c.consent_closed; a 'decision' request of a still unrouted lead gets lead_waits(now()), so the sweep re-decides it:
   R8 -> B2C nurture consent_no_answer); (b) open requests of deleted, merged, opted-out or partner-held leads, and of leads
   whose partner-sharing consent is recorded elsewhere meanwhile, become cancelled; (c) queued B2C requests are published
   oldest first inside the hourly budget; (d) unsendable ones are republished once an endpoint subscribes. One tick at a time. */
create or replace function b2b.consent_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  x b2b.consent_requests;
  c record;
  v_res jsonb;
  v_upd timestamptz;
  v_expired int := 0;
  v_cancelled int := 0;
  v_published int := 0;
  v_republished int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);
  if not pg_try_advisory_xact_lock(hashtext('b2b.consent_tick')) then
    return jsonb_build_object('expired', 0, 'cancelled', 0, 'published', 0, 'republished', 0, 'skipped', 'another tick is running');
  end if;

  -- (a) expiry
  for x in select q.* from b2b.consent_requests q
            where q.status in ('requested', 'sent', 'unsendable') and q.expires_at is not null and q.expires_at <= now()
            order by q.expires_at, q.id limit 500 for update skip locked loop
    update b2b.consent_requests set status = 'expired', closed_at = now() where id = x.id;
    perform b2b.log_event('b2c.consent_closed', x.lead_id, null, null, jsonb_build_object(
      'request_id', x.id, 'lead_id', x.lead_id, 'context', x.context, 'status', 'expired', 'answer', null, 'answered_at', null,
      'source', null, 'closed_at', now()));
    if x.context = 'decision' and exists (select 1 from public.student_leads l where l.id = x.lead_id and l.destination_type is null
                                              and l.deleted_at is null and l.merged_into_id is null) then
      perform b2b.lead_wait_set(x.lead_id, now(), 'consent request expired', null);
    end if;
    v_expired := v_expired + 1;
  end loop;

  -- (b) cancellations
  for c in
    select * from (
      select q.*, case when l.id is null then 'lead not found'
                       when l.deleted_at is not null then 'lead deleted'
                       when l.merged_into_id is not null then 'lead merged'
                       when coalesce(l.is_opted_out, false) then 'student opted out'
                       when l.destination_type = 'partner' then 'lead is with a partner'
                       when coalesce((b2b.partner_consent(l) ->> 'given')::boolean, false) then 'consent recorded elsewhere' end as why,
             l.destination_type as lead_destination
        from b2b.consent_requests q left join public.student_leads l on l.id = q.lead_id
       where q.status in ('queued', 'requested', 'sent', 'unsendable')) s
     where s.why is not null order by s.id limit 500 loop
    update b2b.consent_requests set status = 'cancelled', closed_at = now()
     where id = c.id and status in ('queued', 'requested', 'sent', 'unsendable');
    if found then
      perform b2b.log_event('b2c.consent_closed', c.lead_id, null, null, jsonb_build_object(
        'request_id', c.id, 'lead_id', c.lead_id, 'context', c.context, 'status', 'cancelled', 'answer', null, 'answered_at', null,
        'source', null, 'closed_at', now(), 'why', c.why));
      if c.why = 'consent recorded elsewhere' and c.context = 'decision' and c.lead_destination is null then
        perform b2b.lead_wait_set(c.lead_id, now(), 'consent recorded', null);
      end if;
      v_cancelled := v_cancelled + 1;
    end if;
  end loop;

  -- (c) queued requests, oldest first, inside the hourly budget
  for x in select q.* from b2b.consent_requests q where q.status = 'queued' and q.channel = 'b2c_crm'
            order by q.created_at, q.id limit 200 for update skip locked loop
    v_res := b2b.consent_request_publish(x.id);
    exit when v_res ->> 'why' = 'budget';
    if coalesce((v_res ->> 'published')::boolean, false) then
      v_published := v_published + 1;
      if x.context = 'decision' then
        select l.updated_at into v_upd from public.student_leads l where l.id = x.lead_id and l.destination_type is null;
        if found then perform b2b.lead_wait_set(x.lead_id, (v_res ->> 'expires_at')::timestamptz, 'awaiting partner-sharing consent', v_upd); end if;
      end if;
    end if;
  end loop;

  -- (d) unsendable requests once an endpoint subscribes
  if exists (select 1 from b2b.webhook_endpoints w where w.active and w.consumer = 'b2c_crm' and b2b.event_subscribed(w.events, 'b2c.consent_requested')) then
    for x in select q.* from b2b.consent_requests q where q.status = 'unsendable' and q.channel = 'b2c_crm'
              order by q.published_at, q.id limit 200 for update skip locked loop
      v_res := b2b.consent_request_publish(x.id);
      exit when v_res ->> 'why' = 'budget';
      if coalesce((v_res ->> 'published')::boolean, false) then
        v_republished := v_republished + 1;
        if x.context = 'decision' then
          select l.updated_at into v_upd from public.student_leads l where l.id = x.lead_id and l.destination_type is null;
          if found then perform b2b.lead_wait_set(x.lead_id, (v_res ->> 'expires_at')::timestamptz, 'awaiting partner-sharing consent', v_upd); end if;
        end if;
      end if;
    end loop;
  end if;

  return jsonb_build_object('expired', v_expired, 'cancelled', v_cancelled, 'published', v_published, 'republished', v_republished);
end $fn$;

-- ---------- (8) Admin ----------
/* Asks the student now (context 'admin'). A lead whose partner-sharing consent is already recorded is refused (22023). */
create or replace function b2b.consent_request_admin(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare l public.student_leads;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads x where x.id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if coalesce((b2b.partner_consent(l) ->> 'given')::boolean, false) then
    raise exception 'partner-sharing consent is already recorded for this lead' using errcode = '22023';
  end if;
  return b2b.consent_request_create(p_lead_id, 'admin', b2b.actor() || jsonb_build_object('reason', left(trim(p_reason), 300)));
end $fn$;

/* Records an answer the Admin received (D9). 'no' is always allowed; 'yes' needs engine.consent_admin_yes (default false)
   and a written evidence reference. Source 'admin', evidence {note, evidence_ref, by}. */
create or replace function b2b.consent_record_admin(p_lead_id bigint, p_answer text, p_note text, p_evidence_ref text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_answer not in ('yes', 'no') then raise exception 'the answer must be yes or no' using errcode = '22023'; end if;
  if length(trim(coalesce(p_note, ''))) < 10 then raise exception 'a note of at least 10 characters is required' using errcode = '22023'; end if;
  if p_answer = 'yes' then
    if not coalesce((select (s.value ->> 'consent_admin_yes')::boolean from b2b.settings s where s.key = 'engine'), false) then
      raise exception 'recording a YES given on a call is not enabled (engine.consent_admin_yes)' using errcode = '22023';
    end if;
    if length(trim(coalesce(p_evidence_ref, ''))) = 0 then
      raise exception 'a written evidence reference is required for a YES' using errcode = '22023';
    end if;
  end if;
  return b2b.consent_answer(p_lead_id, null, p_answer, 'admin',
           jsonb_build_object('note', left(trim(p_note), 300), 'evidence_ref', nullif(left(trim(coalesce(p_evidence_ref, '')), 300), ''),
                              'by', b2b.actor() ->> 'id'));
end $fn$;

-- ---------- (9) inbound B2C CRM events (m14b, replaced) ----------
/* POST /v1/events/b2ccrm: signed with the B2C endpoint's secret, idempotent by event_id. Unchanged for lead_assigned,
   stage_changed, enrolled, opted_out and erasure_requested. New:
     b2ccrm.partner_consent      {lead_id, request_id?, answer yes|no, answered_at, channel, message_id, text_version};
                                 a YES without message_id -> 422 'message_id is required for a YES'
     b2ccrm.consent_request_sent {request_id, sent_at, message_id} -> status sent, sent_at, expires_at = sent_at + 48 h
   Both may name the request instead of the lead; both may concern leads the B2C CRM does not hold. Result {ok, status,
   result|error}; Admin-facing refusals (22023) answer 422. */
create or replace function b2b.b2ccrm_event_ingest(p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  w b2b.webhook_endpoints;
  j jsonb;
  v_ts bigint;
  v_type text;
  v_event_id text;
  v_lead bigint;
  v_req bigint;
  v_id bigint;
  l public.student_leads;
  cr b2b.consent_requests;
  v_result text;
  v_answer text;
  v_res jsonb;
  v_sent timestamptz;
  v_wait int;
  a record;
begin
  perform set_config('b2b.actor', 'b2c_crm', true);
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  if w.id is null or w.secret_id is null then return jsonb_build_object('ok', false, 'status', 503, 'error', 'the B2C connection is not set up'); end if;
  if length(coalesce(p_body, '')) > 100000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  if p_signature is distinct from 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                                     convert_to(b2b.partner_secret(w.secret_id), 'UTF8'), 'sha256'), 'hex') then
    perform b2b.log_event('alert.b2c_bad_signature', null, null, null, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  begin v_lead := (j -> 'data' ->> 'lead_id')::bigint; exception when others then v_lead := null; end;
  begin v_req := nullif(trim(coalesce(j -> 'data' ->> 'request_id', '')), '')::bigint; exception when others then v_req := null; end;
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  insert into b2b.product_events (source, event_id, event_type, lead_id, raw) values ('b2c_crm', v_event_id, v_type, v_lead, j)
  on conflict (source, event_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;

  if v_type not in ('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested',
                    'b2ccrm.partner_consent', 'b2ccrm.consent_request_sent') then
    update b2b.product_events set status = 'ignored', result = 'unknown event type' where id = v_id;
    return jsonb_build_object('ok', true, 'status', 200, 'result', 'ignored: unknown type');
  end if;
  -- the consent events may name the request instead of the lead
  if v_lead is null and v_req is not null then
    select q.lead_id into v_lead from b2b.consent_requests q where q.id = v_req;
    if v_lead is not null then update b2b.product_events set lead_id = v_lead where id = v_id; end if;
  end if;
  select * into l from public.student_leads where id = v_lead;
  if l.id is null then
    update b2b.product_events set status = 'error',
           result = case when v_type = 'b2ccrm.consent_request_sent' then 'unknown request_id' else 'unknown lead_id' end where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404,
                              'error', case when v_type = 'b2ccrm.consent_request_sent' then 'unknown request_id' else 'unknown lead_id' end);
  end if;

  begin
    case v_type
      when 'b2ccrm.lead_assigned' then
        perform b2b.log_event('b2c.counsellor_assigned', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.stage_changed' then
        perform b2b.log_event('b2c.stage_changed', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.enrolled' then
        perform b2b.log_event('b2c.enrolled', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.opted_out' then
        perform public.lead_intake(jsonb_build_object('phone', l.whatsapp_number, 'source_system', 'b2c_crm', 'event_type', 'lead.opted_out',
                                                      'lead', jsonb_build_object('is_opted_out', true)));
        update b2b.student_notifications set status = 'cancelled', error = 'student opted out (B2C CRM)', updated_at = now()
         where lead_id = l.id and status = 'scheduled';
        -- every partner that ever received the lead must be told (adapters later; an alert for the Admin until then)
        for a in select distinct x.partner_id from b2b.allocations x where x.lead_id = l.id and x.destination_type = 'partner'
                   and x.status in ('pushed', 'accepted', 'duplicate', 'rejected', 'closed') loop
          perform b2b.log_event('alert.partner_optout_notice', l.id, null, a.partner_id, jsonb_build_object('source', 'b2c_crm'));
        end loop;
        v_result := 'opted out';
      when 'b2ccrm.erasure_requested' then
        insert into b2b.erasure_requests (lead_id, source, note) values (l.id, 'b2c_crm', left(j -> 'data' ->> 'note', 300))
        on conflict (lead_id) where status = 'open' do nothing;
        perform b2b.log_event('alert.erasure_requested', l.id, null, null, jsonb_build_object('source', 'b2c_crm'));
        v_result := 'erasure request recorded for the Admin';
      when 'b2ccrm.partner_consent' then
        v_answer := lower(trim(coalesce(j -> 'data' ->> 'answer', '')));
        if v_answer not in ('yes', 'no') then raise exception 'answer must be yes or no' using errcode = '22023'; end if;
        if v_answer = 'yes' and nullif(trim(coalesce(j -> 'data' ->> 'message_id', '')), '') is null then
          raise exception 'message_id is required for a YES' using errcode = '22023';
        end if;
        v_res := b2b.consent_answer(l.id, v_req, v_answer, 'b2c_crm', jsonb_build_object(
                   'message_id', nullif(trim(coalesce(j -> 'data' ->> 'message_id', '')), ''), 'channel', j -> 'data' ->> 'channel',
                   'answered_at', j -> 'data' ->> 'answered_at', 'text_version', j -> 'data' ->> 'text_version', 'event_id', v_event_id));
        v_result := 'consent ' || v_answer || case when coalesce((v_res ->> 'duplicate')::boolean, false) then ': already recorded'
                                                   else ': ' || coalesce(v_res ->> 'effect', 'recorded') end;
      when 'b2ccrm.consent_request_sent' then
        if v_req is null then raise exception 'request_id is required' using errcode = '22023'; end if;
        select * into cr from b2b.consent_requests q where q.id = v_req for update;
        if cr.id is null then raise exception 'unknown request_id' using errcode = '22023'; end if;
        if cr.status in ('queued', 'requested', 'unsendable', 'sent') then
          v_wait := greatest(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'consent_wait_hours' from b2b.settings s where s.key = 'engine')), 48), 1)::int;
          v_sent := least(coalesce(b2b.try_timestamptz(j -> 'data' ->> 'sent_at'), now()), now());
          update b2b.consent_requests
             set status = 'sent', sent_at = v_sent, published_at = coalesce(published_at, v_sent), expires_at = v_sent + make_interval(hours => v_wait),
                 evidence = evidence || jsonb_build_object('sent_message_id', j -> 'data' ->> 'message_id', 'sent_event_id', v_event_id)
           where id = cr.id returning * into cr;
          if cr.context = 'decision' and l.destination_type is null then
            perform b2b.lead_wait_set(l.id, cr.expires_at, 'awaiting partner-sharing consent', l.updated_at);
          end if;
          v_result := 'sent at ' || v_sent::text || '; expires at ' || cr.expires_at::text;
        else
          v_result := 'ignored: request is ' || cr.status;
        end if;
    end case;
    update b2b.product_events set status = 'applied', result = v_result where id = v_id;
  exception
    when sqlstate '22023' then
      update b2b.product_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
      return jsonb_build_object('ok', false, 'status', 422, 'error', sqlerrm);
    when others then
      update b2b.product_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
      return jsonb_build_object('ok', false, 'status', 500, 'error', 'stored; it will be reviewed');
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', v_result);
end $fn$;

-- ---------- (10) the go-live checklist ----------
/* A JSON array, in this order: consent_texts_approved (blocking), witty_w1_consent_line (blocking unless acknowledged),
   b2c_endpoint_subscribed (blocking), witty_w2_consent_request (blocking unless acknowledged), live_partner (warning).
   Each item: {key, ok, blocking, acknowledgeable, acked, ack {reason, by, at}|null, why, detail}. An item passes when ok, or
   when acknowledgeable and acked (setting golive_acks, written by routing_golive_ack). Admin-only; also read inside
   set_live_switch, command_center, pool_overview and lead_routing. */
create or replace function b2b.routing_golive_check()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  acks jsonb;
  items jsonb := '[]'::jsonb;
  v_unapproved text[];
  v_approved int;
  v_ok boolean;
  v_why text;
  v_n int;
  v_last timestamptz;
  w b2b.webhook_endpoints;
  v_missing text[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  acks := coalesce((select s.value from b2b.settings s where s.key = 'golive_acks'), '{}'::jsonb);
  if jsonb_typeof(acks) <> 'object' then acks := '{}'::jsonb; end if;

  -- (a) every active consent text that covers admission partners carries the lawyer's approval (PART 7.1)
  select coalesce(array_agg(t.version order by t.version) filter (where t.lawyer_approved_at is null), '{}'::text[]),
         count(*) filter (where t.lawyer_approved_at is not null)
    into v_unapproved, v_approved
    from b2b.consent_texts t where t.active and t.covers_admission_partners;
  v_ok := cardinality(v_unapproved) = 0 and v_approved > 0;
  v_why := case when cardinality(v_unapproved) > 0 then 'awaiting the lawyer''s approval: ' || array_to_string(v_unapproved, ', ')
                when v_approved = 0 then 'no active consent text covers admission partners (edtech companies)'
                else v_approved || ' covering consent text(s) approved' end;
  items := items || jsonb_build_array(jsonb_build_object('key', 'consent_texts_approved', 'ok', v_ok, 'blocking', true,
    'acknowledgeable', false, 'acked', false, 'ack', null, 'why', v_why,
    'detail', jsonb_build_object('unapproved', to_jsonb(v_unapproved), 'approved', v_approved)));

  -- (b) Witty's W1 consent line is live: a non-test Witty lead of the last 14 days carries witty-notice-2026-10-v2
  select count(*), max(l.created_at) into v_n, v_last
    from public.student_leads l
   where l.created_at > now() - interval '14 days' and l.consent_text_version = 'witty-notice-2026-10-v2'
     and l.deleted_at is null and not coalesce(l.is_test, false) and not b2b.is_test_phone(l.whatsapp_number)
     and b2b.is_witty_lead(l);
  v_ok := v_n > 0;
  v_why := case when v_ok then v_n || ' Witty lead(s) of the last 14 days carry the consent line (witty-notice-2026-10-v2)'
                else 'no Witty lead of the last 14 days carries consent_text_version witty-notice-2026-10-v2: Witty''s W1 workflow half is not live' end;
  items := items || jsonb_build_array(jsonb_build_object('key', 'witty_w1_consent_line', 'ok', v_ok, 'blocking', true,
    'acknowledgeable', true, 'acked', acks ? 'witty_w1_consent_line' and jsonb_typeof(acks -> 'witty_w1_consent_line') = 'object',
    'ack', case when jsonb_typeof(acks -> 'witty_w1_consent_line') = 'object' then acks -> 'witty_w1_consent_line' end,
    'why', v_why, 'detail', jsonb_build_object('leads_14d', v_n, 'last_at', v_last)));

  -- (c) an active B2C CRM endpoint subscribes to the hand-off and the consent request
  select * into w from b2b.webhook_endpoints x where x.active and x.consumer = 'b2c_crm' order by x.id limit 1;
  v_missing := array(select t from unnest(array['b2c.lead_handed_off', 'b2c.consent_requested']) t
                      where w.id is null or not b2b.event_subscribed(w.events, t));
  v_ok := w.id is not null and cardinality(v_missing) = 0;
  v_why := case when w.id is null then 'no active B2C CRM endpoint (System > Endpoints)'
                when cardinality(v_missing) > 0 then 'the B2C CRM endpoint does not subscribe to ' || array_to_string(v_missing, ', ')
                else 'endpoint "' || w.name || '" subscribes to hand-offs and consent requests' end;
  items := items || jsonb_build_array(jsonb_build_object('key', 'b2c_endpoint_subscribed', 'ok', v_ok, 'blocking', true,
    'acknowledgeable', false, 'acked', false, 'ack', null, 'why', v_why,
    'detail', jsonb_build_object('endpoint_id', w.id, 'events', to_jsonb(w.events), 'missing', to_jsonb(v_missing))));

  -- (d) Witty W2 (public.w2_consent_request with a search_path) is present, or the B2C number asks Witty leads too
  v_ok := to_regprocedure('public.w2_consent_request(jsonb)') is not null
      and exists (select 1 from pg_catalog.pg_proc p cross join lateral unnest(p.proconfig) cfg
                   where p.oid = to_regprocedure('public.w2_consent_request(jsonb)') and cfg like 'search_path=%');
  v_why := case when v_ok then 'Witty W2 is present: Witty leads are asked from Witty''s number'
                else 'public.w2_consent_request(jsonb) with a search_path is missing: Witty leads would be asked from the B2C number' end;
  items := items || jsonb_build_array(jsonb_build_object('key', 'witty_w2_consent_request', 'ok', v_ok, 'blocking', true,
    'acknowledgeable', true, 'acked', acks ? 'witty_w2_consent_request' and jsonb_typeof(acks -> 'witty_w2_consent_request') = 'object',
    'ack', case when jsonb_typeof(acks -> 'witty_w2_consent_request') = 'object' then acks -> 'witty_w2_consent_request' end,
    'why', v_why, 'detail', jsonb_build_object('present', to_regprocedure('public.w2_consent_request(jsonb)') is not null)));

  -- (e) warning: a live, active partner with a published programme
  select count(*) into v_n from b2b.partners p
   where p.status = 'active' and b2b.is_live('partner:' || p.id)
     and exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active);
  v_ok := v_n > 0;
  v_why := case when v_ok then v_n || ' live partner(s) with a published programme'
                else 'no live, active partner has a published programme: every qualified lead would fall back to B2C' end;
  items := items || jsonb_build_array(jsonb_build_object('key', 'live_partner', 'ok', v_ok, 'blocking', false,
    'acknowledgeable', false, 'acked', false, 'ack', null, 'why', v_why, 'detail', jsonb_build_object('partners', v_n)));
  return items;
end $fn$;

/* Acknowledges one of the two Witty items with a reason (>= 10 characters): golive_acks[key] = {reason, by, at}, written
   under a row lock (C126) through set_setting. Returns the checklist. */
create or replace function b2b.routing_golive_ack(p_key text, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_key not in ('witty_w1_consent_line', 'witty_w2_consent_request') then
    raise exception 'this item cannot be acknowledged: %', coalesce(p_key, '(null)') using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'a reason of at least 10 characters is required' using errcode = '22023'; end if;
  v := b2b.setting_for_update('golive_acks');
  if jsonb_typeof(v) <> 'object' then v := '{}'::jsonb; end if;
  perform b2b.set_setting('golive_acks',
            v || jsonb_build_object(p_key, jsonb_build_object('reason', left(trim(p_reason), 300), 'by', b2b.actor() ->> 'id', 'at', now())),
            'go-live acknowledgement: ' || p_key);
  perform b2b.log_event('routing.golive_acked', null, null, null, jsonb_build_object('key', p_key, 'reason', left(trim(p_reason), 300)));
  return b2b.routing_golive_check();
end $fn$;

-- ---------- (11) the switch (m2d, replaced) ----------
/* Unchanged, except that 'routing' cannot go live while a blocking checklist item fails and is not acknowledged:
   22023 'routing cannot go live: <key>: <why>; ...'. */
create or replace function b2b.set_live_switch(p_scope text, p_live boolean, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_bad text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if p_scope = 'routing' and p_live then
    select string_agg((x ->> 'key') || ': ' || coalesce(x ->> 'why', 'not ready'), '; ' order by ord)
      into v_bad
      from jsonb_array_elements(b2b.routing_golive_check()) with ordinality u(x, ord)
     where coalesce((x ->> 'blocking')::boolean, false)
       and not (coalesce((x ->> 'ok')::boolean, false)
                or (coalesce((x ->> 'acknowledgeable')::boolean, false) and coalesce((x ->> 'acked')::boolean, false)));
    if v_bad is not null then raise exception 'routing cannot go live: %', v_bad using errcode = '22023'; end if;
  end if;
  insert into b2b.live_switches (scope, live, reason, switched_by, switched_at)
  values (p_scope, p_live, p_reason, auth.uid(), now())
  on conflict (scope) do update set live = excluded.live, reason = excluded.reason,
                                    switched_by = excluded.switched_by, switched_at = excluded.switched_at;
  perform b2b.log_event('live_switch.changed', null, null, null, jsonb_build_object('scope', p_scope, 'live', p_live, 'reason', p_reason));
  return jsonb_build_object('scope', p_scope, 'live', p_live);
end $fn$;

-- ---------- cron ----------
do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-consent-tick';
  perform cron.schedule('b2b-consent-tick', '* * * * *', 'select b2b.consent_tick()');
end $cron$;

-- ---------- grants ----------
revoke execute on function b2b.consent_programme_pick(public.student_leads), b2b.consent_request_text(text), b2b.consent_request_publish(bigint),
                           b2b.consent_request_create(bigint, text, jsonb), b2b.consent_answer(bigint, bigint, text, text, jsonb),
                           b2b.consent_from_witty(bigint), b2b.consent_tick()
  from public, anon, authenticated;
grant execute on function b2b.consent_programme_pick(public.student_leads), b2b.consent_request_text(text), b2b.consent_request_publish(bigint),
                          b2b.consent_request_create(bigint, text, jsonb), b2b.consent_answer(bigint, bigint, text, text, jsonb),
                          b2b.consent_from_witty(bigint), b2b.consent_tick()
  to service_role;
revoke execute on function b2b.consent_request_admin(bigint, text), b2b.consent_record_admin(bigint, text, text, text),
                           b2b.routing_golive_check(), b2b.routing_golive_ack(text, text)
  from public, anon;
grant execute on function b2b.consent_request_admin(bigint, text), b2b.consent_record_admin(bigint, text, text, text),
                          b2b.routing_golive_check(), b2b.routing_golive_ack(text, text)
  to authenticated, service_role;
-- b2ccrm_event_ingest (anon, authenticated, service_role: m14b) and set_live_switch (authenticated: m2e) keep their grants.
