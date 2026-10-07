-- M31 B2C contract version 3 (Addendum 3) in PGlite or on STAGING, rolled back. The version-3 b2c.lead_handed_off payload
-- for each reason (handling, hold, bar, "Already with other providers", missing, the explore-programmes welcome request,
-- consent, lost and nurture timing), the fan-out of b2c.lead_requalified / lead_reengaged / lead_reenquired /
-- consent_requested / consent_closed with contract_version 3 and the test flag, b2b.lead_routed_to_partner for a
-- requalified lead, the version-3 b2c_record, api_b2c_schema, the route-to-partners 422 error codes, the bulk counts,
-- the Admin reads (skipped until m31l is applied), the /v1/handoffs cursor and the sync scope 'all' (critic B16).
-- Fixtures use the staging partners 20-22 (MBA offered by all three). Every row must say ok = true.
begin;
select pg_advisory_xact_lock(hashtext('b2b.b2c_sync_tick'));
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e3","role":"authenticated","aal":"aal2","email":"m31j-admin@test.local"}', true)
$f$;
-- the function exists and is not a contract stub (plan/a3/stubs_contract.sql marks every stub body)
create function pg_temp.real(sig text) returns boolean language sql as $f$
  select coalesce((select prosrc !~ 'contract-stub' from pg_proc where oid = to_regprocedure(sig)), false) $f$;
create function pg_temp.has(sig text, marker text) returns boolean language sql as $f$
  select coalesce((select prosrc ~ marker from pg_proc where oid = to_regprocedure(sig)), false) $f$;
/* the API is called as anon, like the /v1 routes */
create function pg_temp.api(fn text, args jsonb) returns jsonb language plpgsql as $f$
declare res jsonb;
begin
  execute 'set local role anon';
  execute format('select b2b.%I(%s)', fn, (select string_agg(format('%s => %L::%s', key, value #>> '{}',
      case when key in ('p_lead_id', 'p_after') then 'bigint' when key = 'p_limit' then 'int' when key = 'p_since' then 'timestamptz'
           when key = 'p' then 'jsonb' else 'text' end), ', ')
    from jsonb_each(args))) into res;
  execute 'reset role';
  return res;
end $f$;
grant execute on function pg_temp.api(text, jsonb) to anon;
create function pg_temp.lead(p_phone text, p_course text, p_extra jsonb default '{}', p_sys text default 'crm') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', p_sys, 'event_type', 'lead.created',
    'lead', jsonb_strip_nulls(jsonb_build_object('full_name', 'M31j ' || p_phone, 'email', 'm31j-' || p_phone || '@test.local', 'interested_course', p_course,
                                                 'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi', 'source', 'website',
                                                 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1') || p_extra)));
  select l.id into v_id from public.student_leads l where l.whatsapp_number = p_phone;
  return v_id;
end $f$;
create function pg_temp.decide(p_lead bigint, p_how text default 'auto', p_note text default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  return b2b.route_decide(p_lead, true, p_note, p_how);
end $f$;
-- a B2C hand-off written directly (status handed_off, the lead pointing at it), returning the allocation id
create function pg_temp.hold(p_lead bigint, p_reason text, p_lane text, p_extra jsonb default '{}') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, attempt_no, reason, cause, is_test, origin)
  values (p_lead, 1, 'in_house', p_lane, 'handed_off', coalesce(p_extra ->> 'mode', 'fallback'), coalesce((p_extra ->> 'attempt_no')::int, 1), p_reason,
          p_extra ->> 'cause', coalesce((p_extra ->> 'is_test')::boolean, false), coalesce(p_extra ->> 'origin', 'auto'))
  returning id into v_id;
  update b2b.allocations set reference = 'EDW-' || v_id where id = v_id;
  update public.student_leads set destination_type = 'in_house', partner_id = null, allocation_id = v_id, allocated_at = now(), allocation_reason = p_reason,
         updated_by = 'b2b' where id = p_lead;
  return v_id;
end $f$;
create function pg_temp.payload(p_lead bigint) returns jsonb language sql as $f$
  select e.payload from b2b.events e where e.type = 'b2c.lead_handed_off' and e.lead_id = p_lead order by e.id desc limit 1 $f$;
create function pg_temp.rec(p_lead bigint) returns jsonb language sql as $f$
  select b2b.b2c_record(l) from public.student_leads l where l.id = p_lead $f$;
create function pg_temp.outbox(p_type text, p_lead bigint) returns jsonb language sql as $f$
  select o.payload from b2b.integration_outbox o join b2b.webhook_endpoints w on w.id = o.endpoint_id and w.consumer = 'b2c_crm'
   where o.event_type = p_type and (o.payload ->> 'lead_id')::bigint = p_lead order by o.id desc limit 1 $f$;
create function pg_temp.pname(p bigint) returns text language sql as $f$ select coalesce(display_name, name) from b2b.partners where id = p $f$;

-- ---------- settings, the admin, keys, the B2C endpoint ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e3', 'm31j-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e3', 'm31j-admin@test.local');
insert into b2b.api_keys (name, scopes, key_prefix, key_hash)
values ('m31j b2c', '{b2c}', 'eb2b_m31jb2c', encode(extensions.digest('eb2b_m31jtest_key_0001', 'sha256'), 'hex')),
       ('m31j events', '{events}', 'eb2b_m31jevt', encode(extensions.digest('eb2b_m31jtest_key_0002', 'sha256'), 'hex'));
do $x$
declare v_secret uuid := vault.create_secret('whsec_m31j_test_secret_00000000000000000000000000000', 'b2b_m31j_test_' || gen_random_uuid(), 'm31j test');
begin
  update b2b.webhook_endpoints set url = 'https://b2c.example.test/hooks/b2b', events = '{b2c.*,b2b.*}', active = true, secret_id = v_secret where consumer = 'b2c_crm';
  if not found then
    insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id) values ('B2C CRM (m31j test)', 'b2c_crm', 'https://b2c.example.test/hooks/b2b', '{b2c.*,b2b.*}', true, v_secret);
  end if;
end $x$;
update b2b.settings set value = '{"enabled":true,"scope":"held"}' where key = 'b2c_link';
insert into b2b.live_switches (scope, live, reason) values ('routing', true, 'm31j contract test') on conflict (scope) do update set live = true;
update b2b.settings set value = value || '{"enabled":true,"consent_policy":"ask","kill_switch":false,"welcome_for_all_nurture":false}' where key = 'engine';
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at)
values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now());
select pg_temp.set('ev0', (select coalesce(max(id), 0)::text from b2b.events));

-- ========================================================================================================
-- A. R6: created in the B2C CRM -> b2c_created, sales (the real route and the real event)
-- ========================================================================================================
select pg_temp.set('A', pg_temp.lead('919876560001', 'MBA', '{"source":"b2c_created"}')::text);
select pg_temp.set('XA', pg_temp.decide(pg_temp.v('A')::bigint)::text);
insert into r select 'a_routed_b2c_created', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_created' and x ->> 'b2c_lane' = 'sales' and (x ->> 'committed')::boolean, left(x::text, 200)
  from (select pg_temp.v('XA')::jsonb x) y;
insert into r select 'a_payload_v3_keys', p ?& array['lead_id', 'allocation_id', 'reference', 'decision_id', 'b2c_lane', 'reason', 'cause', 'contract_version', 'hold', 'handling',
                                               'partner_bar', 'already_with_providers', 'partners_tried', 'missing', 'b2c_actions', 'welcome', 'consent', 'lost',
                                               'nurture_first_message_after_days', 'nurture_first_message_at', 'interests_tried', 'attribution', 'paid', 'test']
                       and (p ->> 'contract_version')::int = 3 and p ->> 'reason' = 'b2c_created' and p ->> 'b2c_lane' = 'sales', left(p::text, 300)
  from (select pg_temp.payload(pg_temp.v('A')::bigint) p) y;
insert into r select 'a_handling_sell_counsellor_choice', p -> 'handling' ->> 'job' = 'sell' and p -> 'handling' ->> 'assignment' = 'counsellor_choice'
                       and p -> 'handling' ->> 'first_contact_script' = 'standard' and (p -> 'handling' ->> 'previous_owner') is null
                       and p -> 'hold' ->> 'kind' = 'selling' and (p -> 'hold' ->> 'open')::boolean and (p ->> 'partner_bar') is null
                       and p -> 'already_with_providers' = '[]' and p -> 'missing' = '[]' and p -> 'b2c_actions' = '[]' and (p ->> 'welcome') is null
                       and (p ->> 'consent') is null and (p ->> 'lost') is null and (p ->> 'nurture_first_message_after_days') is null
                       and jsonb_typeof(p -> 'attribution') = 'object' and (p -> 'attribution') ? 'paid' and (p ->> 'paid') is null and not (p ->> 'test')::boolean, left(p::text, 300)
  from (select pg_temp.payload(pg_temp.v('A')::bigint) p) y;
insert into r select 'a_envelope_contract_3', o ->> 'type' = 'b2c.lead_handed_off' and (o ->> 'contract_version')::int = 3 and not (o ->> 'test')::boolean
                       and o -> 'data' ->> 'reason' = 'b2c_created' and (o -> 'data' ->> 'contract_version')::int = 3 and o -> 'data' ->> 'reference' like 'EDW-%', left(o::text, 200)
  from (select pg_temp.outbox('b2c.lead_handed_off', pg_temp.v('A')::bigint) o) y;
-- the record of the held lead
select b2b.lead_interest_add(pg_temp.v('A')::bigint, '"BBA"', 'b2c');
insert into r select 'a_record_v3', (x ->> 'contract_version')::int = 3 and (x ->> 'held_by_b2c')::boolean
                       and x -> 'allocation' ->> 'reason' = 'b2c_created' and x -> 'allocation' ->> 'b2c_lane' = 'sales'
                       and x -> 'allocation' ->> 'job' = 'sell' and x -> 'allocation' ->> 'assignment' = 'counsellor_choice' and x -> 'allocation' ->> 'first_contact_script' = 'standard'
                       and x -> 'allocation' -> 'hold' ->> 'kind' = 'selling' and (x -> 'allocation' ->> 'partner_bar_reason') is null and (x -> 'allocation' ->> 'partner_barred_at') is null
                       and x -> 'allocation' -> 'already_with_providers' = '[]' and x -> 'allocation' -> 'b2c_actions' = '[]' and (x -> 'allocation' ->> 'nurture_first_message_at') is null
                       and (x -> 'allocation') ? 'cause' and x -> 'allocation' ->> 'reference' like 'EDW-%'
                       and x -> 'qualification' ->> 'class' = 'qualified' and x -> 'qualification' -> 'missing' = '[]' and x -> 'qualification' ? 'lead_status'
                       and (x -> 'consent' ->> 'partner_share_given')::boolean and x -> 'consent' ->> 'state' = 'given' and (x -> 'consent' ->> 'partner_share_request') is null
                       and x -> 'consent' ? 'partner_share_consent_at'
                       and x -> 'interest' -> 'other_courses' = '["BBA"]' and x -> 'interest' ->> 'course' = 'MBA'
                       and x -> 'student' ->> 'phone' = '919876560001' and x::text !~ 'cpe_net|commission|ncpl|candidates', left(x::text, 300)
  from (select pg_temp.rec(pg_temp.v('A')::bigint) x) y;

-- ========================================================================================================
-- B. R7: an unqualified Witty lead -> not_qualified, nurture, with the explore-programmes welcome request (Amendment 1.2)
-- ========================================================================================================
select pg_temp.set('B', pg_temp.lead('919876560002', 'MBA', '{"email":null,"classification":null,"consent_partner_share_at":null,"consent_text_version":null,"source":"whatsapp_direct","first_agent_channel":"whatsapp"}', 'witty')::text);
insert into r select 'b_is_witty_unqualified', b2b.is_witty_lead(l) and b2b.lead_class(l) ->> 'class' = 'unqualified' and b2b.lead_class(l) -> 'missing' = '["no_email"]', b2b.lead_class(l)::text
  from public.student_leads l where l.id = pg_temp.v('B')::bigint;
select pg_temp.set('XB', pg_temp.decide(pg_temp.v('B')::bigint)::text);
insert into r select 'b_routed_not_qualified', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'not_qualified' and x ->> 'b2c_lane' = 'nurture' and (x ->> 'committed')::boolean, left(x::text, 200)
  from (select pg_temp.v('XB')::jsonb x) y;
insert into r select 'b_payload_welcome_request', p ->> 'reason' = 'not_qualified' and p ->> 'b2c_lane' = 'nurture'
                       and p -> 'handling' ->> 'job' = 'qualify' and p -> 'handling' ->> 'assignment' = 'unassigned' and p -> 'handling' ->> 'first_contact_script' = 'standard'
                       and p -> 'missing' = '["no_email"]' and p -> 'b2c_actions' = '["welcome_explore_programmes"]'
                       and p -> 'welcome' ->> 'template_hint' = 'explore_programmes' and (p -> 'welcome') ? 'last_inbound_at'
                       and p -> 'hold' ->> 'kind' = 'qualification_nurture' and (p ->> 'partner_bar') is null, left(p::text, 300)
  from (select pg_temp.payload(pg_temp.v('B')::bigint) p) y;
insert into r select 'b_record_nurture_welcome', x -> 'allocation' ->> 'job' = 'qualify' and x -> 'allocation' ->> 'assignment' = 'unassigned'
                       and x -> 'allocation' -> 'b2c_actions' = '["welcome_explore_programmes"]' and x -> 'allocation' -> 'hold' ->> 'kind' = 'qualification_nurture'
                       and x -> 'qualification' ->> 'class' = 'unqualified' and x -> 'qualification' -> 'missing' = '["no_email"]'
                       and not (x -> 'consent' ->> 'partner_share_given')::boolean and x -> 'consent' ->> 'state' = 'none', left(x::text, 300)
  from (select pg_temp.rec(pg_temp.v('B')::bigint) x) y;
-- a non-Witty nurture hand-off asks for the welcome only when engine.welcome_for_all_nurture is on
select pg_temp.set('B2', pg_temp.lead('919876560003', null, '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
select pg_temp.set('HB2', pg_temp.hold(pg_temp.v('B2')::bigint, 'not_qualified', 'nurture')::text);
insert into r select 'b2_no_welcome_by_default', p -> 'b2c_actions' = '[]' and (p ->> 'welcome') is null and p -> 'missing' = '["no_course"]'
                       and x -> 'allocation' -> 'b2c_actions' = '[]', left(p::text, 200)
  from (select b2b.handoff_payload(pg_temp.v('HB2')::bigint) p, pg_temp.rec(pg_temp.v('B2')::bigint) x) y;
update b2b.settings set value = value || '{"welcome_for_all_nurture":true}' where key = 'engine';
insert into r select 'b2_welcome_for_all_nurture', p -> 'b2c_actions' = '["welcome_explore_programmes"]' and p -> 'welcome' ->> 'template_hint' = 'explore_programmes'
                       and x -> 'allocation' -> 'b2c_actions' = '["welcome_explore_programmes"]', left(p::text, 200)
  from (select b2b.handoff_payload(pg_temp.v('HB2')::bigint) p, pg_temp.rec(pg_temp.v('B2')::bigint) x) y;
update b2b.settings set value = value || '{"welcome_for_all_nurture":false}' where key = 'engine';

-- ========================================================================================================
-- C. R8: a qualified lead without consent -> b2c.consent_requested; NO -> b2c.consent_closed + no_partner_consent
-- ========================================================================================================
select pg_temp.set('C', pg_temp.lead('919876560004', 'MBA', '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
select pg_temp.set('XC', pg_temp.decide(pg_temp.v('C')::bigint)::text);
insert into r select 'c_consent_requested', x ->> 'destination' = 'consent_requested' and x ->> 'outcome' = 'consent_requested' and (x ->> 'committed')::boolean
                       and (x -> 'consent_request' ->> 'created')::boolean and x -> 'consent_request' ->> 'channel' = 'b2c_crm' and x -> 'consent_request' ->> 'status' = 'requested', left(x::text, 300)
  from (select pg_temp.v('XC')::jsonb x) y;
select pg_temp.set('CR', (pg_temp.v('XC')::jsonb -> 'consent_request' ->> 'request_id'));
insert into r select 'c_consent_requested_envelope', o ->> 'type' = 'b2c.consent_requested' and (o ->> 'contract_version')::int = 3 and not (o ->> 'test')::boolean
                       and o -> 'data' ->> 'request_id' = pg_temp.v('CR') and o -> 'data' ->> 'text_version' = 'wa_partner_consent:v1' and length(o -> 'data' ->> 'text') > 20
                       and o -> 'data' -> 'student' ->> 'phone' = '919876560004', left(o::text, 300)
  from (select pg_temp.outbox('b2c.consent_requested', pg_temp.v('C')::bigint) o) y;
insert into r select 'c_record_request_pending', not (x ->> 'held_by_b2c')::boolean and (x -> 'allocation' ->> 'hold') is null and (x -> 'allocation' ->> 'job') is null
                       and x -> 'consent' ->> 'state' = 'requested' and not (x -> 'consent' ->> 'partner_share_given')::boolean
                       and x -> 'consent' -> 'partner_share_request' ->> 'id' = pg_temp.v('CR') and x -> 'consent' -> 'partner_share_request' ->> 'status' = 'requested'
                       and x -> 'consent' -> 'partner_share_request' ->> 'channel' = 'b2c_crm' and x -> 'consent' -> 'partner_share_request' ->> 'context' = 'decision'
                       and (x -> 'consent' -> 'partner_share_request' ->> 'expires_at') is not null and (x -> 'consent' -> 'partner_share_request' ->> 'answer') is null, left(x::text, 300)
  from (select pg_temp.rec(pg_temp.v('C')::bigint) x) y;
select pg_temp.set('XCN', b2b.consent_answer(pg_temp.v('C')::bigint, pg_temp.v('CR')::bigint, 'no', 'b2c_crm', '{"message_id":"wamid.m31j.no"}')::text);
insert into r select 'c_no_recorded_and_routed', (x ->> 'recorded')::boolean and x ->> 'state' = 'refused' and x ->> 'effect' = 'routed'
                       and x -> 'route' ->> 'reason' = 'no_partner_consent' and x -> 'route' ->> 'b2c_lane' = 'sales', left(x::text, 300)
  from (select pg_temp.v('XCN')::jsonb x) y;
insert into r select 'c_consent_closed_envelope', o ->> 'type' = 'b2c.consent_closed' and (o ->> 'contract_version')::int = 3 and not (o ->> 'test')::boolean
                       and o -> 'data' ->> 'request_id' = pg_temp.v('CR') and o -> 'data' ->> 'status' = 'answered' and o -> 'data' ->> 'answer' = 'no', left(o::text, 300)
  from (select pg_temp.outbox('b2c.consent_closed', pg_temp.v('C')::bigint) o) y;
insert into r select 'c_payload_no_partner_consent', p ->> 'reason' = 'no_partner_consent' and p ->> 'b2c_lane' = 'sales'
                       and p -> 'handling' ->> 'job' = 'sell' and p -> 'handling' ->> 'assignment' = 'counsellor_choice'
                       and p -> 'consent' ->> 'request_id' = pg_temp.v('CR') and p -> 'consent' ->> 'status' = 'answered'
                       and (p -> 'consent' ->> 'requested_at') is not null and (p -> 'consent' ->> 'refused_at') is not null and p -> 'hold' ->> 'kind' = 'selling', left(p::text, 300)
  from (select pg_temp.payload(pg_temp.v('C')::bigint) p) y;
insert into r select 'c_record_refused', (x ->> 'held_by_b2c')::boolean and x -> 'consent' ->> 'state' = 'refused' and not (x -> 'consent' ->> 'partner_share_given')::boolean
                       and x -> 'consent' -> 'partner_share_request' ->> 'answer' = 'no' and x -> 'consent' -> 'partner_share_request' ->> 'status' = 'answered'
                       and x -> 'allocation' ->> 'reason' = 'no_partner_consent' and x -> 'allocation' -> 'hold' ->> 'kind' = 'selling', left(x::text, 300)
  from (select pg_temp.rec(pg_temp.v('C')::bigint) x) y;

-- ========================================================================================================
-- D. PART 5.4: the duplicate cascade -> barred, round robin, neutral adviser, "Already with other providers" with dates
-- ========================================================================================================
select pg_temp.set('D', pg_temp.lead('919876560005', 'MBA')::text);
do $x$
declare v_lead bigint := pg_temp.v('D')::bigint; v_a bigint;
begin
  insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, attempt_no, pushed_at, outcome, outcome_at, origin,
                               claim_proof_ok, claim_existing_record_id, claim_existing_created_at, claim_proof, created_at)
  values (v_lead, 1, 'partner', 20, 'duplicate', 'commission_first', 1, now() - interval '2 hours', 'duplicate', now() - interval '110 minutes', 'auto',
          true, 'LS-77001', now() - interval '40 days', '{"existing_record_id":"LS-77001"}', now() - interval '2 hours');
  insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, attempt_no, pushed_at, outcome, outcome_at, origin,
                               claim_proof_ok, claim_existing_record_id, claim_existing_created_at, claim_proof, created_at)
  values (v_lead, 1, 'partner', 21, 'duplicate', 'commission_first', 2, now() - interval '100 minutes', 'duplicate', now() - interval '90 minutes', 'auto',
          true, null, null, '{"crm_message":"Duplicate lead"}', now() - interval '100 minutes');
  v_a := pg_temp.hold(v_lead, 'duplicate_cascade', 'sales', '{"attempt_no":3}');
  perform pg_temp.set('HD', v_a::text);
  perform b2b.partner_bar_set(v_lead, 'duplicate', v_a, 'engine');
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.log_event('b2c.lead_handed_off', v_lead, v_a, null, b2b.handoff_payload(v_a));
end $x$;
insert into r select 'd_payload_duplicate_cascade', p ->> 'reason' = 'duplicate_cascade' and p ->> 'b2c_lane' = 'sales'
                       and p -> 'handling' ->> 'job' = 'sell' and p -> 'handling' ->> 'assignment' = 'round_robin_now' and p -> 'handling' ->> 'first_contact_script' = 'neutral_adviser'
                       and p -> 'partner_bar' ->> 'reason' = 'duplicate' and (p -> 'partner_bar' ->> 'barred_at') is not null
                       and p -> 'hold' ->> 'kind' = 'barred' and jsonb_array_length(p -> 'partners_tried') = 2, left(p::text, 300)
  from (select pg_temp.payload(pg_temp.v('D')::bigint) p) y;
insert into r select 'd_already_with_providers_badge', jsonb_array_length(a) = 2
                       and a -> 0 ->> 'partner_id' = '20' and a -> 0 ->> 'partner_name' = pg_temp.pname(20) and (a -> 0 ->> 'first_had_at')::timestamptz < now() - interval '39 days'
                       and a -> 0 ->> 'existing_record_id' = 'LS-77001' and (a -> 0 ->> 'claimed_at') is not null
                       and a -> 1 ->> 'partner_id' = '21' and (a -> 1 ->> 'first_had_at') is null and (a -> 1 ->> 'existing_record_id') is null, a::text
  from (select pg_temp.payload(pg_temp.v('D')::bigint) -> 'already_with_providers' a) y;
insert into r select 'd_record_bar_and_badge', x -> 'allocation' ->> 'partner_bar_reason' = 'duplicate' and (x -> 'allocation' ->> 'partner_barred_at') is not null
                       and jsonb_array_length(x -> 'allocation' -> 'already_with_providers') = 2 and x -> 'allocation' -> 'already_with_providers' -> 0 ->> 'existing_record_id' = 'LS-77001'
                       and x -> 'allocation' -> 'hold' ->> 'kind' = 'barred' and x -> 'allocation' ->> 'job' = 'sell'
                       and x -> 'allocation' ->> 'assignment' = 'round_robin_now' and x -> 'allocation' ->> 'first_contact_script' = 'neutral_adviser'
                       and x -> 'allocation' ->> 'reason' = 'duplicate_cascade', left(x::text, 300)
  from (select pg_temp.rec(pg_temp.v('D')::bigint) x) y;
-- the barred lead enquires again: b2c.lead_reenquired fans out with the bar and lane (payload as m31k writes it)
do $x$ begin
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.log_event('b2c.lead_reenquired', pg_temp.v('D')::bigint, pg_temp.v('HD')::bigint, null, jsonb_build_object(
    'lead_id', pg_temp.v('D')::bigint, 'b2c_lane', 'sales', 'reason', 'duplicate_cascade', 'hold', (select b2b.b2c_hold(l) from public.student_leads l where l.id = pg_temp.v('D')::bigint),
    'partner_bar', (select b2b.partner_bar(l) from public.student_leads l where l.id = pg_temp.v('D')::bigint), 'cycle_no', 1,
    'what', jsonb_build_object('source_system', 'meta', 'source', 'meta_lead_ad', 'event_type', 'lead.created', 'campaign', 'Oct MBA', 'attribution', '{}'::jsonb, 'at', now(), 'ref', 1),
    'interest', true, 'reactivation', false, 'contract_version', 3));
end $x$;
insert into r select 'd_reenquired_envelope', o ->> 'type' = 'b2c.lead_reenquired' and (o ->> 'contract_version')::int = 3 and not (o ->> 'test')::boolean
                       and o -> 'data' -> 'partner_bar' ->> 'reason' = 'duplicate' and o -> 'data' -> 'hold' ->> 'kind' = 'barred' and o -> 'data' ->> 'b2c_lane' = 'sales'
                       and o -> 'data' ->> 'reference' = 'EDW-' || pg_temp.v('HD'), left(o::text, 300)
  from (select pg_temp.outbox('b2c.lead_reenquired', pg_temp.v('D')::bigint) o) y;

-- ========================================================================================================
-- E. PART 6.1: lost, after the 7-day grace -> B2C nurture partner_lost, unassigned, barred, first message delayed
-- ========================================================================================================
select pg_temp.set('E', pg_temp.lead('919876560006', 'MBA')::text);
do $x$
declare v_lead bigint := pg_temp.v('E')::bigint; v_a bigint; v_x jsonb;
begin
  insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, attempt_no, pushed_at, accepted_at, origin, partner_record_id,
                               lost_at, lost_grace_until, lost_detail, lost_count, created_at)
  values (v_lead, 1, 'partner', 21, 'accepted', 'commission_first', 1, now() - interval '20 days', now() - interval '20 days' + interval '1 hour', 'auto', 'SYNC-9001',
          now() - interval '8 days', now() - interval '1 day', '{"lost_reason":"Not interested","status":"Lost","sub_status":"Budget","last_activity_at":"2026-09-29T10:00:00+05:30"}', 1,
          now() - interval '20 days')
  returning id into v_a;
  update b2b.allocations set reference = 'EDW-' || v_a where id = v_a;
  update public.student_leads set destination_type = 'partner', partner_id = 21, allocation_id = v_a, allocated_at = now() - interval '20 days', allocation_reason = 'commission_first',
         owner_user_id = 'aaaaaaaa-0000-0000-0000-0000000000e3', stage = 'lost', lost_reason = 'Not interested', updated_by = 'b2b' where id = v_lead;
  perform pg_temp.set('EA', v_a::text);
  if pg_temp.real('b2b.lost_handoff(bigint)') then
    perform set_config('b2b.actor', 'system', true);
    v_x := b2b.lost_handoff(v_a);
    perform pg_temp.set('XE', v_x::text);
    insert into r values ('e_lost_handoff', (v_x ->> 'handed_off')::boolean and (v_x ->> 'barred')::boolean and v_x ->> 'previous_owner' = 'aaaaaaaa-0000-0000-0000-0000000000e3'
                            and (v_x ->> 'closed_allocation_id')::bigint = v_a, left(v_x::text, 300));
    insert into r select 'e_payload_partner_lost', p ->> 'reason' = 'partner_lost' and p ->> 'b2c_lane' = 'nurture'
                           and p -> 'handling' ->> 'job' = 'nurture' and p -> 'handling' ->> 'assignment' = 'unassigned_until_interest' and p -> 'handling' ->> 'first_contact_script' = 'standard'
                           and p -> 'handling' ->> 'previous_owner' = 'aaaaaaaa-0000-0000-0000-0000000000e3'
                           and (p ->> 'nurture_first_message_after_days')::int = 14
                           and (p ->> 'nurture_first_message_at')::timestamptz between now() + interval '13 days 23 hours' and now() + interval '14 days 1 hour'
                           and p -> 'partner_bar' ->> 'reason' = 'lost' and p -> 'hold' ->> 'kind' = 'barred'
                           and p -> 'lost' ->> 'partner_id' = '21' and p -> 'lost' ->> 'partner_name' = pg_temp.pname(21) and p -> 'lost' ->> 'partner_record_id' = 'SYNC-9001'
                           and p -> 'lost' ->> 'lost_reason' = 'Not interested' and (p -> 'lost' ->> 'grace_ended_at') is not null and p -> 'lost' ->> 'partner_status' = 'Lost'
                           and p -> 'lost' ->> 'partner_sub_status' = 'Budget' and (p -> 'lost' ->> 'partner_last_activity') is not null
                           and p -> 'missing' = '[]' and p -> 'b2c_actions' = '[]', left(p::text, 400)
      from (select pg_temp.payload(v_lead) p) y;
    insert into r select 'e_record_partner_lost', x -> 'allocation' ->> 'reason' = 'partner_lost' and x -> 'allocation' ->> 'b2c_lane' = 'nurture'
                           and x -> 'allocation' ->> 'job' = 'nurture' and x -> 'allocation' ->> 'assignment' = 'unassigned_until_interest'
                           and x -> 'allocation' ->> 'partner_bar_reason' = 'lost' and x -> 'allocation' -> 'hold' ->> 'kind' = 'barred'
                           and (x -> 'allocation' ->> 'nurture_first_message_at')::timestamptz > now() + interval '13 days'
                           and x -> 'allocation' -> 'already_with_providers' = '[]' and (x -> 'pipeline' ->> 'owner_user_id') is null and (x ->> 'held_by_b2c')::boolean, left(x::text, 300)
      from (select pg_temp.rec(v_lead) x) y;
  else
    insert into r values ('e_lost_handoff', true, 'skipped: lost_handoff is a stub (m31i not applied)'),
                         ('e_payload_partner_lost', true, 'skipped'), ('e_record_partner_lost', true, 'skipped');
  end if;
end $x$;

-- ========================================================================================================
-- F. Every other reason: the version-3 keys and the handling table (hand-offs written directly)
-- ========================================================================================================
do $x$
declare
  x record; v_lead bigint; v_a bigint; p jsonb; i int := 10;
begin
  for x in
    select * from (values
      ('manual_route_failed', 'sales', 'no_capacity', 'sell', 'previous_counsellor', 'standard'),
      ('consent_no_answer', 'nurture', null, 'qualify', 'unassigned', 'standard'),
      ('no_partner_offers_programme', 'sales', null, 'sell', 'counsellor_choice', 'standard'),
      ('no_capacity', 'sales', 'caps', 'sell', 'counsellor_choice', 'standard'),
      ('partners_unreachable', 'sales', null, 'sell', 'counsellor_choice', 'standard'),
      ('partner_attempts_exhausted', 'sales', null, 'sell', 'counsellor_choice', 'standard'),
      ('import_choice', 'nurture', null, 'nurture', 'counsellor_choice', 'standard'),
      ('rule', 'sales', null, 'sell', 'counsellor_choice', 'standard'),
      ('manual', 'sales', null, 'sell', 'counsellor_choice', 'standard'),
      ('b2c_held', 'sales', null, 'sell', 'counsellor_choice', 'standard')) v(reason, lane, cause, job, assignment, script)
  loop
    i := i + 1;
    v_lead := pg_temp.lead('9198765600' || i, 'MBA');
    v_a := pg_temp.hold(v_lead, x.reason, x.lane, jsonb_strip_nulls(jsonb_build_object('cause', x.cause)));
    p := b2b.handoff_payload(v_a);
    insert into r values ('f_' || x.reason,
      p ?& array['lead_id', 'allocation_id', 'reference', 'decision_id', 'b2c_lane', 'reason', 'cause', 'contract_version', 'hold', 'handling', 'partner_bar',
                 'already_with_providers', 'partners_tried', 'missing', 'b2c_actions', 'welcome', 'consent', 'lost', 'nurture_first_message_after_days',
                 'nurture_first_message_at', 'interests_tried', 'attribution', 'paid', 'test']
      and (p ->> 'contract_version')::int = 3 and p ->> 'reason' = x.reason and p ->> 'b2c_lane' = x.lane and (p ->> 'cause') is not distinct from x.cause
      and p -> 'handling' ->> 'job' = x.job and p -> 'handling' ->> 'assignment' = x.assignment and p -> 'handling' ->> 'first_contact_script' = x.script
      and p -> 'hold' ->> 'kind' = case when x.reason = 'consent_no_answer' then 'qualification_nurture' else 'selling' end
      and (p ->> 'partner_bar') is null and p -> 'already_with_providers' = '[]'
      and p -> 'missing' = case when x.reason = 'consent_no_answer' then '["partner_consent"]'::jsonb else '[]'::jsonb end
      and (p ->> 'nurture_first_message_after_days') is null and (p ->> 'lost') is null and not (p ->> 'test')::boolean
      and (select b2b.b2c_record(l) from public.student_leads l where l.id = v_lead) -> 'allocation' ->> 'job' = x.job
      and (select b2b.b2c_record(l) from public.student_leads l where l.id = v_lead) -> 'allocation' ->> 'cause' is not distinct from x.cause,
      left(p::text, 300));
  end loop;
end $x$;
-- manual_route_failed names the previous counsellor
update public.student_leads set owner_user_id = 'aaaaaaaa-0000-0000-0000-0000000000e3' where whatsapp_number = '919876560011';
insert into r select 'f_manual_route_failed_previous_owner', p -> 'handling' ->> 'previous_owner' = 'aaaaaaaa-0000-0000-0000-0000000000e3', p -> 'handling' ->> 'previous_owner'
  from (select b2b.handoff_payload(l.allocation_id) p from public.student_leads l where l.whatsapp_number = '919876560011') y;

-- ========================================================================================================
-- G. b2c.lead_requalified / lead_reengaged fan out with contract_version 3 and the test flag (payloads as m31k writes them)
-- ========================================================================================================
select pg_temp.set('T', pg_temp.lead('919000000071', 'MBA', '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
do $x$ begin
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.log_event('b2c.lead_requalified', pg_temp.v('T')::bigint, null, null, jsonb_build_object(
    'lead_id', pg_temp.v('T')::bigint, 'closed_allocation_id', null, 'reference', null, 'decision_id', null, 'destination', 'partner', 'reason', null, 'b2c_lane', null, 'contract_version', 3));
  perform b2b.log_event('b2c.lead_reengaged', pg_temp.v('T')::bigint, null, null, jsonb_build_object(
    'lead_id', pg_temp.v('T')::bigint, 'allocation_id', null, 'engaged_at', now(), 'source', 'witty', 'missing', '["no_email"]'::jsonb, 'contract_version', 3));
end $x$;
insert into r select 'g_requalified_envelope', o ->> 'type' = 'b2c.lead_requalified' and (o ->> 'contract_version')::int = 3 and (o ->> 'test')::boolean
                       and o -> 'data' ->> 'destination' = 'partner' and (o ->> 'lead_id')::bigint = pg_temp.v('T')::bigint and o ->> 'id' like 'evt_%', left(o::text, 300)
  from (select pg_temp.outbox('b2c.lead_requalified', pg_temp.v('T')::bigint) o) y;
insert into r select 'g_reengaged_envelope', o ->> 'type' = 'b2c.lead_reengaged' and (o ->> 'contract_version')::int = 3 and (o ->> 'test')::boolean
                       and o -> 'data' -> 'missing' = '["no_email"]' and o -> 'data' ->> 'source' = 'witty', left(o::text, 300)
  from (select pg_temp.outbox('b2c.lead_reengaged', pg_temp.v('T')::bigint) o) y;

-- ========================================================================================================
-- H. b2b.lead_routed_to_partner follows the acceptance of a requalified lead
-- ========================================================================================================
select pg_temp.set('H', pg_temp.lead('919876560007', 'MBA')::text);
do $x$
declare v_a bigint;
begin
  insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, attempt_no, pushed_at, accepted_at, origin)
  values (pg_temp.v('H')::bigint, 1, 'partner', 21, 'accepted', 'commission_first', 1, now(), now(), 'requalify') returning id into v_a;
  update b2b.allocations set reference = 'EDW-' || v_a where id = v_a;
  update public.student_leads set destination_type = 'partner', partner_id = 21, allocation_id = v_a, allocated_at = now(), allocation_reason = 'commission_first' where id = pg_temp.v('H')::bigint;
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.log_event('lead.accepted', pg_temp.v('H')::bigint, v_a, 21, '{}');
  perform pg_temp.set('HA', v_a::text);
end $x$;
insert into r select 'h_routed_to_partner_envelope', o ->> 'type' = 'b2b.lead_routed_to_partner' and (o ->> 'contract_version')::int = 3 and not (o ->> 'test')::boolean
                       and o -> 'data' ->> 'origin' = 'requalify' and o -> 'data' ->> 'partner_id' = '21' and o -> 'data' ->> 'reference' = 'EDW-' || pg_temp.v('HA'), left(o::text, 300)
  from (select pg_temp.outbox('b2b.lead_routed_to_partner', pg_temp.v('H')::bigint) o) y;
insert into r select 'h_lead_accepted_not_for_b2c', count(*) = 0, count(*)::text
  from b2b.integration_outbox o join b2b.webhook_endpoints w on w.id = o.endpoint_id and w.consumer = 'b2c_crm'
 where o.event_type = 'lead.accepted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('H')::bigint;

-- ========================================================================================================
-- I. GET /v1/b2c/schema, contract version 3
-- ========================================================================================================
insert into r select 'i_schema_bad_key', (pg_temp.api('api_b2c_schema', '{"p_key":"nope"}') ->> 'status')::int = 401, null;
insert into r select 'i_schema_v3', (x ->> 'ok')::boolean and (x -> 'result' ->> 'contract_version')::int = 3
                       and x -> 'result' -> 'reasons' -> 'sales' @> '["b2c_created","import_choice","rule","manual","manual_route_failed","no_partner_offers_programme","no_capacity","partners_unreachable","partner_attempts_exhausted","duplicate_cascade","no_partner_consent","partner_barred","b2c_held"]'
                       and not x -> 'result' -> 'reasons' -> 'sales' @> '["paid_campaign"]' and x -> 'result' -> 'reasons' -> 'retired' @> '["paid_campaign"]'
                       and x -> 'result' -> 'reasons' -> 'nurture' = '["not_qualified","consent_no_answer","partner_lost"]'
                       and x -> 'result' -> 'reasons' -> 'test' = '["test_handoff"]'
                       and x -> 'result' -> 'events' @> '["b2c.lead_requalified","b2c.lead_reengaged","b2c.consent_requested","b2c.consent_closed","b2c.lead_handed_off","b2c.lead_reenquired","b2b.lead_routed_to_partner"]'
                       and x -> 'result' -> 'inbound' @> '["b2ccrm.partner_consent","b2ccrm.consent_request_sent","b2ccrm.opted_out"]'
                       and x -> 'result' -> 'handling' -> 'assignment' @> '["round_robin_now","unassigned_until_interest","previous_counsellor","counsellor_choice","unassigned"]'
                       and x -> 'result' -> 'hold_kinds' = '["barred","qualification_nurture","selling"]'
                       and x -> 'result' -> 'consent_states' @> '["given","refused","withdrawn","requested","queued","expired","stamp_uncovered","none"]'
                       and x -> 'result' -> 'b2c_actions' = '["welcome_explore_programmes"]'
                       and x -> 'result' -> 'route_to_partners_error_codes' = '["partner_barred","no_consent","not_held","invalid"]'
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'other_courses' and f ->> 'group' = 'interest' and (f ->> 'writable')::boolean)
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'stage' and (f ->> 'writable')::boolean)
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'phone' and not (f ->> 'writable')::boolean)
                       and x -> 'result' -> 'stages' @> '[{"key":"assigned"}]' and x -> 'result' ->> 'delivery' = 'realtime', left(x::text, 300)
  from (select pg_temp.api('api_b2c_schema', '{"p_key":"eb2b_m31jtest_key_0001"}') x) y;

-- ========================================================================================================
-- J. POST /v1/leads/{id}/route-to-partners: the 422 error codes
-- ========================================================================================================
select pg_temp.set('N', pg_temp.lead('919876560008', 'MBA')::text);   -- consent given, never routed
insert into r select 'j_422_partner_barred', (x ->> 'status')::int = 422 and x ->> 'error_code' = 'partner_barred' and x ->> 'error' like 'partner_barred:%', x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_lead_id', pg_temp.v('D'), 'p_reason', 'student asked for a partner')) x) y;
insert into r select 'j_422_no_consent', (x ->> 'status')::int = 422 and x ->> 'error_code' = 'no_consent' and x ->> 'error' like 'no_consent:%', x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_lead_id', pg_temp.v('C'), 'p_reason', 'student asked for a partner')) x) y;
insert into r select 'j_422_not_held', (x ->> 'status')::int = 422 and x ->> 'error_code' = 'not_held' and x ->> 'error' like 'not_held:%', x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_lead_id', pg_temp.v('N'), 'p_reason', 'student asked for a partner')) x) y;
insert into r select 'j_422_invalid_reason', (x ->> 'status')::int = 422 and x ->> 'error_code' = 'invalid' and x ->> 'error' like 'a reason is required%', x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_lead_id', pg_temp.v('A'), 'p_reason', 'x')) x) y;
insert into r select 'j_404_unknown_lead', (x ->> 'status')::int = 404, x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_lead_id', 0, 'p_reason', 'student asked for a partner')) x) y;
insert into r select 'j_401_bad_key', (x ->> 'status')::int = 401, x::text
  from (select pg_temp.api('api_route_to_partners', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0001', 'p_lead_id', pg_temp.v('A'), 'p_reason', 'student asked for a partner')) x) y;
insert into r select 'j_refusals_change_nothing', l.allocation_id = pg_temp.v('HD')::bigint and l.destination_type = 'in_house'
                       and (select count(*) from b2b.allocations a where a.lead_id = l.id) = 3, null
  from public.student_leads l where l.id = pg_temp.v('D')::bigint;

-- ========================================================================================================
-- K. Bulk actions: exact counts (route_to_partners_many runs with the stub too; reroute_many only when m31l is applied)
-- ========================================================================================================
-- a second lost-in-grace lead for the re-route count
select pg_temp.set('E2', pg_temp.lead('919876560009', 'MBA')::text);
do $x$
declare v_a bigint;
begin
  insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, attempt_no, pushed_at, accepted_at, origin, lost_at, lost_grace_until, lost_detail, lost_count)
  values (pg_temp.v('E2')::bigint, 1, 'partner', 21, 'accepted', 'commission_first', 1, now() - interval '3 days', now() - interval '3 days', 'auto',
          now() - interval '1 hour', now() + interval '6 days 23 hours', '{"lost_reason":"No response"}', 1) returning id into v_a;
  update b2b.allocations set reference = 'EDW-' || v_a where id = v_a;
  update public.student_leads set destination_type = 'partner', partner_id = 21, allocation_id = v_a, allocated_at = now() - interval '3 days', allocation_reason = 'commission_first'
   where id = pg_temp.v('E2')::bigint;
end $x$;
set local role authenticated;
select pg_temp.admin();
do $x$
declare x jsonb;
begin
  if to_regprocedure('b2b.route_to_partners_many(bigint[],text)') is not null then
    x := b2b.route_to_partners_many(array[pg_temp.v('D')::bigint, pg_temp.v('C')::bigint, pg_temp.v('N')::bigint], 'bulk: students asked for partners');
    insert into r values ('k_route_to_partners_many_counts', (x ->> 'sent')::int = 0 and (x ->> 'skipped_barred')::int = 1 and (x ->> 'skipped_no_consent')::int = 1
                            and (x ->> 'skipped_not_held')::int = 1 and (x ->> 'failed')::int = 0 and jsonb_array_length(x -> 'results') = 3
                            and (select bool_and(not (e ->> 'ok')::boolean and e ->> 'skipped' in ('partner_barred', 'no_consent', 'not_held')) from jsonb_array_elements(x -> 'results') e),
                          left(x::text, 300) || case when pg_temp.real('b2b.route_to_partners_many(bigint[],text)') then '' else ' (stub)' end);
  else
    insert into r values ('k_route_to_partners_many_counts', true, 'skipped: route_to_partners_many not installed (m31l)');
  end if;
  if pg_temp.real('b2b.reroute_many(bigint[],text,text,text)') then
    x := b2b.reroute_many(array[pg_temp.v('E2')::bigint, pg_temp.v('A')::bigint], 'b2c', 'bulk: back to B2C');
    insert into r values ('k_reroute_many_counts', (x ->> 'done')::int = 0 and (x ->> 'skipped_lost_in_grace')::int = 1 and (x ->> 'skipped_no_partner_allocation')::int = 1
                            and (x ->> 'failed')::int = 0 and jsonb_array_length(x -> 'results') = 2, left(x::text, 300));
  else
    insert into r values ('k_reroute_many_counts', true, 'skipped: reroute_many is a stub or missing (m31l)');
  end if;
end $x$;

-- ========================================================================================================
-- L. Admin reads carry the new fields (m31l): skipped until that migration is applied
-- ========================================================================================================
do $x$
declare x jsonb; f jsonb;
begin
  if pg_temp.has('b2b.lead_routing(bigint)', 'consent_detail') then
    x := b2b.lead_routing(pg_temp.v('D')::bigint);
    insert into r values ('l_lead_routing_fields', x ?& array['bar', 'other_providers', 'hold', 'outlook', 'consent_detail', 'reenquiries', 'interests', 'attribution']
                            and x -> 'bar' ->> 'reason' = 'duplicate' and jsonb_array_length(x -> 'other_providers') = 2 and x -> 'hold' ->> 'kind' = 'barred'
                            and x -> 'consent_detail' ->> 'state' = 'given', left(x::text, 300));
  else
    insert into r values ('l_lead_routing_fields', true, 'skipped: lead_routing not yet replaced (m31l)');
  end if;
  if pg_temp.has('b2b.leads_list(jsonb)', 'partner_bar_reason') then
    x := b2b.leads_list(jsonb_build_object('q', '919876560005', 'limit', 5));
    insert into r values ('l_leads_list_fields', jsonb_array_length(x -> 'rows') = 1 and x -> 'rows' -> 0 ->> 'partner_bar_reason' = 'duplicate'
                            and (x -> 'rows' -> 0 ->> 'partner_barred_at') is not null and (x -> 'rows' -> 0 ->> 'other_providers_count')::int = 2
                            and x -> 'rows' -> 0 ->> 'hold_kind' = 'barred' and x -> 'rows' -> 0 ->> 'consent_state' = 'given' and x -> 'rows' -> 0 ->> 'b2c_lane' = 'sales'
                            and x -> 'rows' -> 0 ->> 'allocation_reason' = 'duplicate_cascade' and (x -> 'rows' -> 0) ? 'reenquired_open' and (x -> 'rows' -> 0) ? 'paid_platform'
                            and (x -> 'rows' -> 0) ? 'lost_grace_until', left(x::text, 300));
  else
    insert into r values ('l_leads_list_fields', true, 'skipped: leads_list not yet replaced (m31l)');
  end if;
  if pg_temp.has('b2b.leads_facets(jsonb)', 'barred') then
    f := b2b.leads_facets('{}');
    insert into r values ('l_leads_facets_fields', f ? 'destination' and (f -> 'destination' ? 'barred' or f ? 'paid'), left(f::text, 300));
  else
    insert into r values ('l_leads_facets_fields', true, 'skipped: leads_facets not yet replaced (m31l)');
  end if;
end $x$;
reset role;

-- ========================================================================================================
-- M. GET /v1/handoffs keeps the m14d next_after cursor (critic B24)
-- ========================================================================================================
insert into r select 'm_handoffs_feed', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'events') >= 8
                       and (x -> 'result' ->> 'next_after')::bigint >= (select max(id) from b2b.events where type = 'b2c.lead_handed_off')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.lead_handed_off' and (e ->> 'lead_id')::bigint = pg_temp.v('D')::bigint
                                     and (e ->> 'contract_version')::int = 3 and e -> 'data' -> 'partner_bar' ->> 'reason' = 'duplicate')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.consent_requested')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.consent_closed')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.lead_requalified' and (e ->> 'test')::boolean)
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.lead_reengaged')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2c.lead_reenquired')
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'b2b.lead_routed_to_partner')
                       and not exists (select 1 from jsonb_array_elements(x -> 'result' -> 'events') e where e ->> 'type' = 'lead.accepted'), left(x::text, 300)
  from (select pg_temp.api('api_b2c_handoffs', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_since', null, 'p_after', pg_temp.v('ev0')::bigint, 'p_limit', 500)) x) y;
insert into r select 'm_handoffs_cursor_echo', (x ->> 'ok')::boolean and x -> 'result' -> 'events' = '[]' and (x -> 'result' ->> 'next_after')::bigint = pg_temp.v('ev0')::bigint + 100000, x::text
  from (select pg_temp.api('api_b2c_handoffs', jsonb_build_object('p_key', 'eb2b_m31jtest_key_0002', 'p_since', null, 'p_after', pg_temp.v('ev0')::bigint + 100000, 'p_limit', 50)) x) y;

-- ========================================================================================================
-- N. Sync scope 'all': Not passed leads and test leads are out; a lead that becomes Not passed is released (critic B16)
-- ========================================================================================================
update b2b.settings set value = value || '{"scope":"all"}' where key = 'b2c_link';
-- a course Eduwit does not offer -> R5 Not passed (program_mismatch)
select pg_temp.set('NP', pg_temp.lead('919876560010', 'Astrology Studies')::text);
select pg_temp.set('XNP', pg_temp.decide(pg_temp.v('NP')::bigint)::text);
insert into r select 'n_not_passed_recorded', x ->> 'destination' = 'not_passed' and exists (select 1 from b2b.not_passed np where np.lead_id = pg_temp.v('NP')::bigint and np.passed_at is null), left(x::text, 200)
  from (select pg_temp.v('XNP')::jsonb x) y;
insert into r select 'n_not_passed_out_of_scope', not (b2b.b2c_sync_lead(pg_temp.v('NP')::bigint) ->> 'changed')::boolean
                       and not exists (select 1 from b2b.b2c_sync s where s.lead_id = pg_temp.v('NP')::bigint)
                       and not (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('NP')::bigint), null;
insert into r select 'n_test_lead_out_of_scope', not (b2b.b2c_sync_lead(pg_temp.v('T')::bigint) ->> 'changed')::boolean
                       and not exists (select 1 from b2b.b2c_sync s where s.lead_id = pg_temp.v('T')::bigint), null;
-- a test hand-off is in scope (and flagged)
select pg_temp.set('T2', pg_temp.lead('919000000072', 'MBA')::text);
select pg_temp.hold(pg_temp.v('T2')::bigint, 'test_handoff', 'sales', '{"is_test":true,"origin":"sandbox"}');
-- (the sync call and the outbox read go in separate statements: one statement cannot see its own call's writes)
select pg_temp.set('ST2', b2b.b2c_sync_lead(pg_temp.v('T2')::bigint)::text);
insert into r select 'n_test_handoff_in_scope', (x ->> 'changed')::boolean and x ->> 'type' = 'b2c.lead_upserted'
                       and (select (o.payload ->> 'test')::boolean and o.payload -> 'data' -> 'record' ->> 'held_by_b2c' = 'true' and o.payload -> 'data' -> 'record' -> 'allocation' ->> 'reason' = 'test_handoff'
                              from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('T2')::bigint order by o.id desc limit 1), x::text
  from (select pg_temp.v('ST2')::jsonb x) y;
-- an unrouted real lead is in scope under 'all' (read-only), and leaves it when it becomes Not passed
select pg_temp.set('SN1', b2b.b2c_sync_lead(pg_temp.v('N')::bigint)::text);
insert into r select 'n_unrouted_in_scope_all', (x ->> 'changed')::boolean and x ->> 'type' = 'b2c.lead_upserted' and (x ->> 'version')::int = 1
                       and (select o.payload -> 'data' -> 'record' ->> 'held_by_b2c' = 'false' and (o.payload -> 'data' -> 'record' ->> 'contract_version')::int = 3
                              from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('N')::bigint order by o.id desc limit 1), x::text
  from (select pg_temp.v('SN1')::jsonb x) y;
insert into b2b.not_passed (lead_id, reason, lead_status, requested_course, lead_source, fingerprint, detail)
select l.id, 'junk', l.lead_status, l.interested_course, l.lead_source, b2b.np_fingerprint(l), 'spam:ip_burst' from public.student_leads l where l.id = pg_temp.v('N')::bigint;
select pg_temp.set('SN2', b2b.b2c_sync_lead(pg_temp.v('N')::bigint)::text);
insert into r select 'n_becomes_not_passed_released', (x ->> 'changed')::boolean and x ->> 'type' = 'b2c.lead_released' and (x ->> 'version')::int = 2
                       and (select s.in_scope = false from b2b.b2c_sync s where s.lead_id = pg_temp.v('N')::bigint)
                       and exists (select 1 from b2b.integration_outbox o where o.event_type = 'b2c.lead_released' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('N')::bigint
                                     and o.payload -> 'data' -> 'record' ->> 'held_by_b2c' = 'false' and not (o.payload -> 'data' -> 'record') ? 'student'), x::text
  from (select pg_temp.v('SN2')::jsonb x) y;
insert into r select 'n_released_not_resent', not (b2b.b2c_sync_lead(pg_temp.v('N')::bigint) ->> 'changed')::boolean, null;
-- the held leads stay in scope whatever the setting; a partner-held lead is in scope only under 'all'
insert into r select 'n_held_and_partner_scope', (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('A')::bigint)
                       and (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('H')::bigint), null;
update b2b.settings set value = value || '{"scope":"held"}' where key = 'b2c_link';
insert into r select 'n_scope_held_again', (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('A')::bigint)
                       and not (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('H')::bigint)
                       and not (select b2b.b2c_in_scope(l) from public.student_leads l where l.id = pg_temp.v('T')::bigint), null;
-- a held lead syncs once at version 3 and is not re-sent while nothing changes
select pg_temp.set('SA1', b2b.b2c_sync_lead(pg_temp.v('A')::bigint)::text);
insert into r select 'n_held_sync_then_unchanged', (x ->> 'changed')::boolean and x ->> 'type' = 'b2c.lead_upserted' and (x ->> 'version')::int = 1
                       and not (b2b.b2c_sync_lead(pg_temp.v('A')::bigint) ->> 'changed')::boolean, x::text
  from (select pg_temp.v('SA1')::jsonb x) y;
insert into r select 'n_held_record_v3_in_outbox', (o.payload -> 'data' -> 'record' ->> 'contract_version')::int = 3 and o.payload -> 'data' -> 'record' ->> 'held_by_b2c' = 'true'
                       and o.payload -> 'data' -> 'record' -> 'allocation' ->> 'job' = 'sell' and o.payload -> 'data' -> 'record' -> 'interest' -> 'other_courses' = '["BBA"]'
                       and not (o.payload ->> 'test')::boolean, left(o.payload::text, 200)
  from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('A')::bigint order by o.id desc limit 1;

-- consent state words (CONTRACT 1.3) from partner_consent shapes
insert into r select 'consent_state_words',
       b2b.consent_state_of('{"given":true}') = 'given' and b2b.consent_state_of('{"given":false,"refused":true,"last_state":"withdrawn"}') = 'withdrawn'
       and b2b.consent_state_of('{"given":false,"refused":true,"last_state":"refused"}') = 'refused'
       and b2b.consent_state_of('{"given":false,"refused":false,"open_request":{"status":"sent"}}') = 'requested'
       and b2b.consent_state_of('{"given":false,"refused":false,"open_request":{"status":"queued"}}') = 'queued'
       and b2b.consent_state_of('{"given":false,"refused":false,"open_request":null,"expired_request":{"id":1}}') = 'expired'
       and b2b.consent_state_of('{"given":false,"refused":false,"open_request":null,"expired_request":null,"stamp_uncovered":true}') = 'stamp_uncovered'
       and b2b.consent_state_of('{"given":false,"refused":false,"open_request":null,"expired_request":null,"stamp_uncovered":false}') = 'none'
       and b2b.consent_state_of(null) = 'none', null;

select name, ok, detail from r order by ok, name;
rollback;
