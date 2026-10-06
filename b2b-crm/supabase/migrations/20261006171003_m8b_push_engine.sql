-- M8b: the push engine. Every 10 seconds pg_cron runs b2b.push_tick(): collect partner responses (pg_net), accept
-- allocations whose hold window has passed, then send queued pushes. Adapters: generic_rest (the partner's API answers
-- created / duplicate / rejected in the create call) and webhook (signed POST; duplicates come back as events).
-- Contract for partners: docs/partner-api.md.

/* What a partner receives (B8.1): only what it needs to sell. Never budget, source, campaign, score or chat text. */
create or replace function b2b.push_payload(a b2b.allocations)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  l public.student_leads;
  c record;
  v_prev text;
begin
  select * into l from public.student_leads where id = a.lead_id;
  select u.name as university, cp.course, cp.specialization, cp.level, cp.mode, o.partner_course_code
    into c from public.catalog_programs cp
    left join public.catalog_universities u on u.id = cp.university_id
    left join b2b.partner_programmes o on o.partner_id = a.partner_id and o.programme_id = cp.id and o.valid_to is null
   where cp.id = a.programme_id;
  select p.reference into v_prev from b2b.allocations p
   where p.lead_id = a.lead_id and p.partner_id = a.partner_id and p.id <> a.id and p.status in ('accepted', 'closed') order by p.created_at desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
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
              'Interested in ' || coalesce(c.course, l.interested_course) || coalesce(' (' || coalesce(c.specialization, l.interested_specialization) || ')', ''),
              case when coalesce(c.mode, l.study_mode_preference) is not null then 'Mode: ' || coalesce(c.mode, l.study_mode_preference) end,
              case when nullif(l.enrollment_timeline, '') is not null then 'Wants to start: ' || l.enrollment_timeline end), 300),
    'returning_lead', v_prev is not null,
    'previous_reference', v_prev,
    'sent_at', now()));
end $$;

/* The HTTP request for one allocation: URL, headers (auth, idempotency, signature) and body. */
create or replace function b2b.push_request(a b2b.allocations)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  p b2b.partners;
  v_url text;
  v_body jsonb := b2b.push_payload(a);
  v_auth jsonb;
  v_secret text;
  v_headers jsonb := jsonb_build_object('Content-Type', 'application/json', 'Idempotency-Key', a.reference, 'X-Eduwit-Reference', a.reference,
                                        'User-Agent', 'Eduwit-B2B-CRM/1');
  v_ts text := extract(epoch from now())::bigint::text;
begin
  select * into p from b2b.partners where id = a.partner_id;
  v_url := case when a.is_test then p.test_endpoint else p.api_base_url end;
  v_auth := coalesce(p.outbound_auth, '{}');
  v_secret := case when p.outbound_secret_id is not null then b2b.partner_secret(p.outbound_secret_id) end;
  if v_secret is not null then
    v_headers := v_headers || case coalesce(v_auth ->> 'type', 'bearer')
      when 'bearer' then jsonb_build_object('Authorization', 'Bearer ' || v_secret)
      when 'header' then jsonb_build_object(v_auth ->> 'header', v_secret)
      when 'basic'  then jsonb_build_object('Authorization', 'Basic ' || translate(encode(convert_to(v_secret, 'UTF8'), 'base64'), E'\n', ''))
      else '{}'::jsonb end;
  end if;
  -- every push is signed with the partner's inbound secret too, so a webhook partner can verify it came from Eduwit
  if p.inbound_secret_id is not null then
    v_headers := v_headers || jsonb_build_object('X-Eduwit-Timestamp', v_ts, 'X-Eduwit-Signature',
      'sha256=' || encode(extensions.hmac(convert_to(v_ts || '.' || v_body::text, 'UTF8'), convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex'));
  end if;
  return jsonb_build_object('url', v_url, 'headers', v_headers, 'body', v_body, 'adapter', p.adapter_type);
end $$;

/* Clears the lead's allocation columns (when they still point at this allocation) and runs the engine again. */
create or replace function b2b.reroute_after(p_allocation_id bigint, p_why text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  v jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null,
         allocation_reason = null, stage = 'qualifying', updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  if not found then return null; end if;
  -- a lead the Admin passed by hand stays passed; everything else follows the normal rules again
  v := b2b.route_decide(a.lead_id, true, p_why, case when a.override then 'pass' else 'auto' end);
  perform b2b.log_event('lead.rerouted', a.lead_id, a.id, a.partner_id, jsonb_build_object('why', p_why, 'destination', v ->> 'destination',
                        'reason', v ->> 'reason', 'partner_id', v ->> 'partner_id', 'reference', v ->> 'reference'));
  return v;
end $$;

/*
 * A partner says the student is already its lead (during the push or the hold window). A returning Eduwit lead
 * (the existing record is Eduwit's own earlier push) is accepted instead. Otherwise: duplicate, proof kept, re-route.
 */
create or replace function b2b.apply_duplicate(p_allocation_id bigint, p_proof jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_existing text := coalesce(p_proof ->> 'existing_record_id', p_proof ->> 'existing_id');
  v_ref text := p_proof ->> 'existing_reference';
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
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
  update b2b.allocations set status = 'duplicate', outcome = 'duplicate', outcome_at = now(), claim_proof = p_proof,
         spot_check = random() < coalesce((e ->> 'duplicate_spot_check')::numeric, 0.05) where id = a.id;
  update public.student_leads set duplicate_claim_count = coalesce(duplicate_claim_count, 0) + 1 where id = a.lead_id;
  perform b2b.log_event('lead.duplicate', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', p_proof, 'reference', a.reference));
  perform b2b.reroute_after(a.id, 'duplicate at partner');
  return 'duplicate: re-routed';
end $$;

/* A partner refuses the lead for a reason other than a duplicate: contract alert, then re-route. */
create or replace function b2b.apply_rejection(p_allocation_id bigint, p_reason text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare a b2b.allocations;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.status not in ('pushing', 'pushed') then return 'ignored: allocation is ' || a.status; end if;
  update b2b.allocations set status = 'rejected', outcome = 'rejected', outcome_at = now(), last_error = left(p_reason, 500) where id = a.id;
  perform b2b.log_event('alert.partner_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('reason', left(p_reason, 500), 'reference', a.reference));
  perform b2b.reroute_after(a.id, 'rejected by partner');
  return 'rejected: re-routed';
end $$;

/* A technical failure: retry on the schedule (10 s, 1 min, 5 min, 15 min, 1 h), then fail and re-route. */
create or replace function b2b.apply_push_error(p_allocation_id bigint, p_error text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_sched jsonb := coalesce(e -> 'push_retry_seconds', '[10, 60, 300, 900, 3600]');
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.status <> 'pushing' then return 'ignored'; end if;
  if a.push_attempts = 1 then
    perform b2b.log_event('alert.push_failed', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(p_error, 300), 'reference', a.reference));
  end if;
  if a.push_attempts <= jsonb_array_length(v_sched) then
    update b2b.allocations set push_request_id = null, last_error = left(p_error, 500),
           next_push_at = now() + make_interval(secs => (v_sched ->> (a.push_attempts - 1))::int) where id = a.id;
    return 'retry';
  end if;
  update b2b.allocations set status = 'failed', outcome = 'failed', outcome_at = now(), push_request_id = null, last_error = left(p_error, 500) where id = a.id;
  perform b2b.log_event('lead.push_failed', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(p_error, 300), 'attempts', a.push_attempts));
  perform b2b.reroute_after(a.id, 'partner unreachable');
  return 'failed: re-routed';
end $$;

/* The partner created the lead: pushed, and the hold window starts (0 for sync partners: accepted at once). */
create or replace function b2b.apply_created(p_allocation_id bigint, p_record_id text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  p b2b.partners;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.status <> 'pushing' then return 'ignored'; end if;
  select * into p from b2b.partners where id = a.partner_id;
  update b2b.allocations set status = 'pushed', pushed_at = now(), push_request_id = null, last_error = null,
         partner_record_id = left(p_record_id, 200), hold_until = now() + make_interval(mins => coalesce(p.hold_minutes, 30)) where id = a.id;
  update public.student_leads set stage = 'sent_to_partner', partner_record_id = left(p_record_id, 200), updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  perform b2b.log_event('lead.pushed', a.lead_id, a.id, a.partner_id, jsonb_build_object('record_id', p_record_id, 'reference', a.reference, 'hold_minutes', p.hold_minutes));
  if coalesce(p.hold_minutes, 30) = 0 then perform b2b.accept_allocation(a.id); end if;
  return 'pushed';
end $$;

/* The hold window passed with no claim: the lead is the partner's (notifications hook in here, m9). */
create or replace function b2b.accept_allocation(p_allocation_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare a b2b.allocations;
begin
  update b2b.allocations set status = 'accepted', accepted_at = now() where id = p_allocation_id and status = 'pushed' returning * into a;
  if a.id is null then return; end if;
  perform b2b.log_event('lead.accepted', a.lead_id, a.id, a.partner_id, jsonb_build_object('reference', a.reference, 'record_id', a.partner_record_id,
                        'returning_lead', a.returning_lead));
end $$;

/* Reads finished pg_net responses for allocations waiting on one, and applies them. */
create or replace function b2b.push_collect()
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  r record;
  j jsonb;
  v_outcome text;
  v_rid text;
  n int := 0;
begin
  for r in
    select a.id, a.partner_id, p.adapter_type, q.id as req_id, q.sent_at, x.status_code, x.content, x.timed_out, x.error_msg, x.id is not null as done
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
        perform b2b.apply_push_error(r.id, 'no response within 2 minutes');
        n := n + 1;
      end if;
      continue;
    end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    v_rid := coalesce(j ->> 'record_id', j ->> 'id', j ->> 'lead_id', j -> 'data' ->> 'id');
    v_outcome := case
      when r.timed_out or r.error_msg is not null then 'error'
      when r.status_code = 409 or coalesce((j ->> 'duplicate')::boolean, false) then 'duplicate'
      when r.status_code in (422, 403) and (coalesce((j ->> 'rejected')::boolean, false) or j ? 'reason') then 'rejected'
      when r.status_code between 200 and 299 then 'created'
      else 'error' end;
    update b2b.push_requests set status_code = r.status_code, response = left(r.content, 2000), outcome = case when r.timed_out then 'timeout' else v_outcome end,
           error = coalesce(r.error_msg, case when v_outcome = 'error' then 'HTTP ' || coalesce(r.status_code::text, '?') end), completed_at = now()
     where id = r.req_id;
    case v_outcome
      when 'created' then perform b2b.apply_created(r.id, v_rid);
      when 'duplicate' then perform b2b.apply_duplicate(r.id, coalesce(j, '{}') || jsonb_build_object('status_code', r.status_code, 'source', 'push_response'));
      when 'rejected' then perform b2b.apply_rejection(r.id, coalesce(j ->> 'reason', 'rejected'));
      else perform b2b.apply_push_error(r.id, coalesce(r.error_msg, case when r.timed_out then 'timeout' end, 'HTTP ' || coalesce(r.status_code::text, '?') || ': ' || left(coalesce(r.content, ''), 200)));
    end case;
    n := n + 1;
  end loop;
  return n;
end $$;

/* Sends queued pushes and due retries. A partner switched off (or without a URL) fails the attempt and re-routes. */
create or replace function b2b.push_dispatch(p_limit int default 20)
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  a b2b.allocations;
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
      if not a.is_test and not b2b.is_live('partner:' || a.partner_id) then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, 'partner is switched off');
        continue;
      end if;
      if a.programme_id is null then
        -- the partner's best-paying matching programme, as the engine ranked it
        select (c -> 'programmes' ->> 0)::bigint into a.programme_id
          from b2b.engine_decisions d, jsonb_array_elements(d.candidates) c
         where d.id = a.engine_decision_id and (c ->> 'partner_id')::bigint = a.partner_id;
        update b2b.allocations set programme_id = a.programme_id where id = a.id;
      end if;
      req := b2b.push_request(a);
      if req ->> 'url' is null then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, case when a.is_test then 'partner has no test endpoint' else 'partner has no API URL' end);
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers',
                             timeout_milliseconds := coalesce((e ->> 'push_timeout_ms')::int, 10000));
      update b2b.allocations set status = 'pushing', push_attempts = push_attempts + 1, push_request_id = v_net, next_push_at = null where id = a.id;
      insert into b2b.push_requests (allocation_id, attempt, net_request_id, url, sandbox)
      values (a.id, a.push_attempts + 1, v_net, req ->> 'url', a.is_test);
      n := n + 1;
    exception when others then
      -- an unexpected error (not the partner's answer): try again in 5 minutes rather than every tick
      update b2b.allocations set next_push_at = now() + interval '5 minutes', last_error = left(sqlerrm, 500) where id = a.id;
      perform b2b.log_event('alert.push_error', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(sqlerrm, 300)));
    end;
  end loop;
  return n;
end $$;

/* One tick: responses first, then the hold windows, then new pushes. Runs every 10 seconds. */
create or replace function b2b.push_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_collected int;
  v_accepted int := 0;
  v_sent int;
  r record;
begin
  perform set_config('b2b.actor', 'engine', true);
  v_collected := b2b.push_collect();
  for r in select id from b2b.allocations where status = 'pushed' and hold_until <= now() order by hold_until limit 200 loop
    perform b2b.accept_allocation(r.id);
    v_accepted := v_accepted + 1;
  end loop;
  v_sent := b2b.push_dispatch(20);
  return jsonb_build_object('collected', v_collected, 'accepted', v_accepted, 'sent', v_sent);
end $$;

revoke execute on function b2b.push_payload(b2b.allocations), b2b.push_request(b2b.allocations), b2b.reroute_after(bigint, text),
                           b2b.apply_duplicate(bigint, jsonb), b2b.apply_rejection(bigint, text), b2b.apply_push_error(bigint, text),
                           b2b.apply_created(bigint, text), b2b.accept_allocation(bigint), b2b.push_collect(), b2b.push_dispatch(int), b2b.push_tick()
  from public, anon, authenticated;
grant execute on function b2b.push_payload(b2b.allocations), b2b.push_request(b2b.allocations), b2b.reroute_after(bigint, text),
                          b2b.apply_duplicate(bigint, jsonb), b2b.apply_rejection(bigint, text), b2b.apply_push_error(bigint, text),
                          b2b.apply_created(bigint, text), b2b.accept_allocation(bigint), b2b.push_collect(), b2b.push_dispatch(int), b2b.push_tick()
  to service_role;

select cron.schedule('b2b-push-tick', '10 seconds', 'select b2b.push_tick()');
