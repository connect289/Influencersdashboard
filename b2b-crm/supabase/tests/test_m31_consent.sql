-- M31 partner-sharing consent (Addendum 3 R8 and PART 7) and the routing go-live gate, in PGlite (FIXTURES=1) or on
-- STAGING, rolled back. Uses the staging fixture: catalogue 33 MBA (course_key mba), partner 20 offering MBA (25 %);
-- partners 21 and 22 are paused in the transaction so partner 20 is the only candidate, and the exploration lane is 0.
-- Covers rulebook test 2 in full (YES -> partner, NO -> B2C sales no_partner_consent, no answer in 48 h -> B2C nurture
-- consent_no_answer, a later YES -> partner), the design's 'Consent versions and asking', 'Channels and timing', 'Paths
-- and policies' and 'Go-live gate' rows (critics A5, A6, B2, B19, B20), the consent texts (consent_text_covers,
-- consent_text_save) and the b2ccrm.* inbound events. Every row must say ok = true. Phones: 91987… (non-test) and one
-- 910000… test lead; everything rolled back.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.put(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.lead(key text) returns public.student_leads language sql as $f$
  select l from public.student_leads l where l.id = (select v from t where k = key)::bigint $f$;
-- a lead through public.lead_intake (the only writer of student_leads); p_extra overrides the lead fields
create function pg_temp.mk(key text, p_phone text, p_course text, p_extra jsonb default '{}', p_system text default 'api') returns bigint language plpgsql as $f$
declare v bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  v := (public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', p_system, 'event_type', 'lead.created',
         'lead', jsonb_strip_nulls(jsonb_build_object('full_name', 'M31e ' || key, 'email', 'm31e-' || key || '@example.com', 'interested_course', p_course,
                                                      'programme_level', 'PG', 'study_mode_preference', 'online', 'source', 'website_form') || p_extra))) ->> 'lead_id')::bigint;
  perform pg_temp.put(key, v::text);
  return v;
end $f$;
create function pg_temp.decide(key text, p_commit boolean, p_how text default 'auto', p_note text default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  return b2b.route_decide(pg_temp.v(key)::bigint, p_commit, p_note, p_how);
end $f$;
create function pg_temp.alloc(key text) returns b2b.allocations language sql as $f$
  select a.* from b2b.allocations a join public.student_leads l on l.allocation_id = a.id where l.id = (select v from t where k = key)::bigint $f$;
create function pg_temp.req(key text) returns b2b.consent_requests language sql as $f$
  select q.* from b2b.consent_requests q where q.lead_id = (select v from t where k = key)::bigint order by q.id desc limit 1 $f$;
create function pg_temp.handoff(key text) returns jsonb language sql as $f$
  select e.payload from b2b.events e where e.type = 'b2c.lead_handed_off' and e.lead_id = (select v from t where k = key)::bigint order by e.id desc limit 1 $f$;
-- a signed B2C CRM event
create function pg_temp.b2c(p_body jsonb) returns jsonb language plpgsql as $f$
declare ts text := extract(epoch from now())::bigint::text; sec text := pg_temp.v('secret');
begin
  return b2b.b2ccrm_event_ingest(p_body::text, ts, 'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || p_body::text, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
end $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e8","role":"authenticated","aal":"aal2","email":"m31e-admin@test.local"}', true) $f$;

-- ---------- fixtures ----------
insert into b2b.live_switches (scope, live, reason) values ('routing', true, 'm31 consent test') on conflict (scope) do update set live = true;
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"enabled":true,"consent_policy":"ask","consent_admin_yes":false,"consent_requests_per_hour":100,"kill_switch":false}' where key = 'engine';
update b2b.settings set value = jsonb_set(value, '{a3_fixed,exploration_share}', '0') where key = 'engine';
update b2b.ml_models set status = 'retired' where status in ('shadow', 'challenger', 'champion', 'training');
update b2b.partners set status = 'paused' where id in (21, 22);
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at)
values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now());
-- a registered version that does NOT cover admission partners (critic A5)
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active)
values ('web-v3', 'web_form', '{sales}', 'universities only', false, true);
-- the B2C endpoint, active and subscribed to every b2c.* event, with a signing secret
do $x$
declare sid uuid;
begin
  sid := vault.create_secret('whsec_m31e_test', 'b2b_webhook_m31e', 'm31 consent test');
  insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id)
  values ('B2C CRM (m31e test)', 'b2c_crm', 'https://b2c.example/v1/events', array['b2c.*'], true, sid);
  perform pg_temp.put('secret', 'whsec_m31e_test');
end $x$;
-- a catalogue course no partner offers (literal R8: the lead is still asked)
insert into public.catalog_programs (program_key, university_id, level, course, course_key, specialization, program_name, mode, fee_yearly, fee_total, active)
values ('zz-consent-nobody', 18, 'PG', 'ZZConsentNobody', 'zzconsentnobody', 'General', 'ZZConsentNobody (nobody offers it)', 'Online', 100000, 200000, true);
-- the admin
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e8', 'm31e-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e8', 'm31e-admin@test.local');

insert into r select 'fixture_partner_20_only', (select count(*) from b2b.partners where status = 'active' and id in (20, 21, 22)) = 1
                     and exists (select 1 from b2b.partner_programmes pp where pp.partner_id = 20 and pp.programme_id = 33), null;
insert into r select 'fixture_routing_live', b2b.is_live('routing') and (select (value ->> 'consent_policy') = 'ask' and (value -> 'a3_fixed' ->> 'exploration_share')::numeric = 0 from b2b.settings where key = 'engine'), null;

-- ======================================================================================================== rulebook test 2
-- four qualified MBA leads without consent: A says YES, B says NO, C never answers, D is asked twice
select pg_temp.mk('a', '919876551001', 'MBA');
select pg_temp.mk('b', '919876551002', 'MBA');
select pg_temp.mk('c', '919876551003', 'MBA');
select pg_temp.mk('d', '919876551004', 'MBA');
do $x$
declare v jsonb; k text; q b2b.consent_requests; w b2b.lead_waits; ev b2b.events; l public.student_leads;
begin
  insert into r values ('t2_leads_qualified', (select bool_and(b2b.lead_class(s) ->> 'class' = 'qualified' and not coalesce((b2b.partner_consent(s) ->> 'given')::boolean, false))
                                                 from public.student_leads s where s.id in (pg_temp.v('a')::bigint, pg_temp.v('b')::bigint, pg_temp.v('c')::bigint, pg_temp.v('d')::bigint)), null);
  -- a preview asks nothing: outcome consent_request
  v := pg_temp.decide('d', false);
  insert into r values ('t2_preview_consent_request', v ->> 'destination' = 'consent_request' and v ->> 'outcome' = 'consent_request' and not (v ->> 'committed')::boolean
                        and not exists (select 1 from b2b.consent_requests where lead_id = pg_temp.v('d')::bigint), v::text);
  -- each decision creates a request: destination consent_requested, no decision row, no allocation
  foreach k in array array['a', 'b', 'c', 'd'] loop
    v := pg_temp.decide(k, true);
    perform pg_temp.put('dec_' || k, v::text);
    perform pg_temp.put('req_' || k, v -> 'consent_request' ->> 'request_id');
  end loop;
  insert into r values ('t2_each_decision_asks', (select bool_and(d ->> 'destination' = 'consent_requested' and d ->> 'outcome' = 'consent_requested' and (d ->> 'committed')::boolean
                                                                 and (d -> 'consent_request' ->> 'created')::boolean and d -> 'consent_request' ->> 'status' = 'requested'
                                                                 and d -> 'consent_request' ->> 'channel' = 'b2c_crm' and d -> 'consent_request' ->> 'context' = 'decision'
                                                                 and d -> 'consent_request' ->> 'programme' = 'MBA' and d -> 'consent_request' ->> 'programme_course_key' = 'mba'
                                                                 and (d ->> 'allocation_id') is null and (d ->> 'decision_id') is null and d ->> 'reason' is null)
                                                  from (select t.v::jsonb d from t where t.k in ('dec_a', 'dec_b', 'dec_c', 'dec_d')) x), pg_temp.v('dec_a'));
  insert into r values ('t2_nothing_written', not exists (select 1 from b2b.allocations where lead_id in (pg_temp.v('a')::bigint, pg_temp.v('b')::bigint, pg_temp.v('c')::bigint, pg_temp.v('d')::bigint))
                        and not exists (select 1 from b2b.engine_decisions where lead_id in (pg_temp.v('a')::bigint, pg_temp.v('b')::bigint, pg_temp.v('c')::bigint, pg_temp.v('d')::bigint))
                        and (select bool_and(s.destination_type is null and s.allocation_id is null) from public.student_leads s where s.id in (pg_temp.v('a')::bigint, pg_temp.v('b')::bigint, pg_temp.v('c')::bigint, pg_temp.v('d')::bigint)), null);
  select * into q from b2b.consent_requests where id = pg_temp.v('req_a')::bigint;
  insert into r values ('t2_request_row', q.lead_id = pg_temp.v('a')::bigint and q.status = 'requested' and q.channel = 'b2c_crm' and q.context = 'decision' and q.programme = 'MBA'
                        and q.text_version = 'wa_partner_consent:v1' and q.published_at is not null and q.expires_at = q.published_at + interval '48 hours' and not q.is_test, q::text);
  -- the B2C CRM is told what to send: the PART 7.2 sentence with the programme filled in
  select * into ev from b2b.events where type = 'b2c.consent_requested' and lead_id = pg_temp.v('a')::bigint order by id desc limit 1;
  insert into r values ('t2_b2c_consent_requested', ev.payload ->> 'text' = 'To connect you with the best admission counsellor for MBA, may we share your details with our admission partner? Reply YES or NO.'
                        and ev.payload ->> 'text_version' = 'wa_partner_consent:v1' and ev.payload ->> 'channel' = 'b2c_crm' and ev.payload ->> 'context' = 'decision'
                        and (ev.payload ->> 'request_id')::bigint = q.id and ev.payload -> 'student' ->> 'phone' = '919876551001'
                        and (ev.payload ->> 'expires_at')::timestamptz = q.expires_at, ev.payload::text);
  insert into r values ('t2_b2c_event_fanned_out', exists (select 1 from b2b.integration_outbox o where o.event_type = 'b2c.consent_requested' and o.source_event_id = ev.id), null);
  insert into r values ('t2_no_handoff_yet', not exists (select 1 from b2b.events where type in ('b2c.lead_handed_off', 'lead.routed') and lead_id = pg_temp.v('a')::bigint), null);
  -- the lead waits for the answer (48 h), the pool shows it as awaiting consent, the sweep leaves it alone
  select * into w from b2b.lead_waits where lead_id = pg_temp.v('a')::bigint;
  l := pg_temp.lead('a');
  insert into r values ('t2_wait_48h', w.why = 'awaiting partner-sharing consent' and w.decide_after = q.expires_at and w.lead_updated_at = l.updated_at, w::text);
  insert into r values ('t2_readiness_wait_consent', not (b2b.lead_readiness(l) ->> 'ready')::boolean and b2b.lead_readiness(l) -> 'wait' ->> 'kind' = 'consent'
                        and (b2b.lead_readiness(l) -> 'wait' ->> 'request_id')::bigint = q.id, (b2b.lead_readiness(l) -> 'wait')::text);
  insert into r values ('t2_pool_awaiting_consent', b2b.pool_lead(l, true) ->> 'group' = 'awaiting_consent' and b2b.pool_lead(l, true) ->> 'outlook' = 'consent_pending', b2b.pool_lead(l, true)::text);
  insert into r values ('t2_outlook_pending', b2b.route_outlook(l) ->> 'outlook' = 'consent_pending', b2b.route_outlook(l)::text);
  insert into r values ('t2_consent_state_requested', b2b.consent_state_of(b2b.partner_consent(l)) = 'requested', b2b.partner_consent(l)::text);
  -- asked again while the request is open: consent_pending, nothing new
  v := pg_temp.decide('d', true);
  insert into r values ('t2_second_ask_pending', v ->> 'destination' = 'consent_pending' and v ->> 'outcome' = 'consent_pending' and not (v ->> 'committed')::boolean
                        and (select count(*) from b2b.consent_requests where lead_id = pg_temp.v('d')::bigint) = 1, v::text);
  insert into r values ('t2_sweep_skips_waiting', b2b.route_ready_leads(50) = 0
                        and (select count(*) from b2b.consent_requests where lead_id in (pg_temp.v('a')::bigint, pg_temp.v('b')::bigint, pg_temp.v('c')::bigint, pg_temp.v('d')::bigint)) = 4, null);
end $x$;

-- A: YES from the B2C CRM (b2ccrm.partner_consent with the student's message id) -> ledger, column stamp, partner 20
do $x$
declare v jsonb; l public.student_leads; c b2b.lead_consents; q b2b.consent_requests; a b2b.allocations;
begin
  -- a YES without message_id is refused and records nothing
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-yes-nomsg', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('a')::bigint, 'request_id', pg_temp.v('req_a')::bigint, 'answer', 'yes')));
  insert into r values ('a_yes_without_message_id_422', not (v ->> 'ok')::boolean and (v ->> 'status')::int = 422 and v ->> 'error' = 'message_id is required for a YES'
                        and not exists (select 1 from b2b.lead_consents where lead_id = pg_temp.v('a')::bigint), v::text);
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-yes-a', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('a')::bigint, 'request_id', pg_temp.v('req_a')::bigint, 'answer', 'yes', 'message_id', 'wamid.A1',
                                    'channel', 'whatsapp', 'answered_at', now()::text, 'text_version', 'wa_partner_consent:v1')));
  insert into r values ('a_yes_routed', (v ->> 'ok')::boolean and (v ->> 'status')::int = 200 and v ->> 'result' = 'consent yes: routed', v::text);
  select * into c from b2b.lead_consents where lead_id = pg_temp.v('a')::bigint order by id desc limit 1;
  insert into r values ('a_ledger_row', c.purpose = 'partner_share' and c.state = 'given' and c.source = 'b2c_crm' and c.text_version = 'wa_partner_consent:v1'
                        and c.request_id = pg_temp.v('req_a')::bigint and c.evidence ->> 'message_id' = 'wamid.A1' and c.evidence ->> 'answer' = 'yes', c::text);
  select * into q from b2b.consent_requests where id = pg_temp.v('req_a')::bigint;
  insert into r values ('a_request_answered', q.status = 'answered' and q.answer = 'yes' and q.answer_source = 'b2c_crm' and q.answered_at is not null and q.closed_at is not null, q::text);
  l := pg_temp.lead('a');
  insert into r values ('a_column_stamp', l.consent_partner_share_at is not null and l.consent_text_version = 'wa_partner_consent:v1'
                        and (b2b.partner_consent(l) ->> 'given')::boolean and b2b.consent_state_of(b2b.partner_consent(l)) = 'given', l.consent_text_version);
  a := pg_temp.alloc('a');
  insert into r values ('a_partner_allocation', a.destination_type = 'partner' and a.partner_id = 20 and a.status in ('queued', 'pushing', 'pushed') and a.origin = 'auto'
                        and a.b2c_lane is null and a.cycle_no = coalesce(l.cycle_no, 1) and l.destination_type = 'partner' and l.partner_id = 20, a::text);
  insert into r values ('a_events', exists (select 1 from b2b.events where type = 'lead.routed' and lead_id = l.id and allocation_id = a.id and (payload ->> 'partner_id')::bigint = 20)
                        and exists (select 1 from b2b.events where type = 'b2c.consent_closed' and lead_id = l.id and payload ->> 'status' = 'answered' and payload ->> 'answer' = 'yes' and payload ->> 'source' = 'b2c_crm')
                        and exists (select 1 from b2b.events where type = 'lead.consent_answered' and lead_id = l.id and payload ->> 'state' = 'given'), null);
  insert into r values ('a_decision_logged', exists (select 1 from b2b.engine_decisions d where d.lead_id = l.id and d.destination_type = 'partner' and d.winner_partner_id = 20 and d.how = 'auto' and d.class = 'qualified'), null);
  -- idempotent: the same event, and a new event carrying the same message id
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-yes-a', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('a')::bigint, 'request_id', pg_temp.v('req_a')::bigint, 'answer', 'yes', 'message_id', 'wamid.A1')));
  insert into r values ('a_same_event_once', v ->> 'result' = 'already received', v::text);
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-yes-a2', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('a')::bigint, 'request_id', pg_temp.v('req_a')::bigint, 'answer', 'yes', 'message_id', 'wamid.A1')));
  insert into r values ('a_same_message_once', (v ->> 'ok')::boolean and v ->> 'result' = 'consent yes: already recorded'
                        and (select count(*) from b2b.lead_consents where lead_id = pg_temp.v('a')::bigint) = 1
                        and (select count(*) from b2b.allocations where lead_id = pg_temp.v('a')::bigint) = 1, v::text);
end $x$;

-- B: NO -> B2C sales lane, reason no_partner_consent
do $x$
declare v jsonb; l public.student_leads; a b2b.allocations; h jsonb;
begin
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-no-b', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('b')::bigint, 'answer', 'no', 'message_id', 'wamid.B1', 'channel', 'whatsapp')));
  insert into r values ('b_no_recorded', (v ->> 'ok')::boolean and v ->> 'result' like 'consent no: %', v::text);
  l := pg_temp.lead('b');
  a := pg_temp.alloc('b');
  insert into r values ('b_sales_no_partner_consent', a.destination_type = 'in_house' and a.b2c_lane = 'sales' and a.reason = 'no_partner_consent' and a.mode = 'fallback'
                        and a.status = 'handed_off' and l.destination_type = 'in_house' and l.allocation_reason = 'no_partner_consent', a::text);
  insert into r values ('b_consent_refused', (b2b.partner_consent(l) ->> 'refused')::boolean and not (b2b.partner_consent(l) ->> 'given')::boolean and l.consent_partner_share_at is null
                        and b2b.consent_state_of(b2b.partner_consent(l)) = 'refused', b2b.partner_consent(l)::text);
  h := pg_temp.handoff('b');
  insert into r values ('b_handoff_payload', h ->> 'reason' = 'no_partner_consent' and h ->> 'b2c_lane' = 'sales' and (h ->> 'contract_version')::int = 3
                        and h -> 'consent' ->> 'refused_at' is not null and h -> 'handling' ->> 'job' = 'sell', h::text);
  insert into r values ('b_hold_selling', b2b.b2c_hold(l) ->> 'kind' = 'selling' and coalesce((b2b.b2c_hold(l) ->> 'open')::boolean, false), b2b.b2c_hold(l)::text);
  -- the same NO again is a duplicate; a re-decision keeps the hold
  v := b2b.consent_answer(l.id, pg_temp.v('req_b')::bigint, 'no', 'b2c_crm', '{"message_id":"wamid.B2"}');
  insert into r values ('b_no_again_duplicate', (v ->> 'duplicate')::boolean and not (v ->> 'recorded')::boolean and v ->> 'effect' = 'none', v::text);
  v := pg_temp.decide('b', false);
  insert into r values ('b_redecide_held', v ->> 'outcome' = 're-enquired' and v ->> 'destination' = 'in_house' and v ->> 'reason' = 'no_partner_consent', v::text);
end $x$;

-- C: no answer in 48 hours -> consent_tick expires the request, the sweep sends the lead to B2C qualification nurture
do $x$
declare tick jsonb; n int; q b2b.consent_requests; l public.student_leads; a b2b.allocations; h jsonb; v jsonb;
begin
  update b2b.consent_requests set published_at = published_at - interval '49 hours', expires_at = expires_at - interval '49 hours' where id = pg_temp.v('req_c')::bigint;
  tick := b2b.consent_tick();
  select * into q from b2b.consent_requests where id = pg_temp.v('req_c')::bigint;
  insert into r values ('c_tick_expires', (tick ->> 'expired')::int = 1 and q.status = 'expired' and q.answer is null and q.closed_at is not null, tick::text);
  insert into r values ('c_expired_closed_event', exists (select 1 from b2b.events where type = 'b2c.consent_closed' and lead_id = pg_temp.v('c')::bigint and payload ->> 'status' = 'expired'), null);
  l := pg_temp.lead('c');
  insert into r values ('c_ready_again', (b2b.lead_readiness(l) ->> 'ready')::boolean and (b2b.partner_consent(l) -> 'expired_request' ->> 'id')::bigint = q.id
                        and b2b.consent_state_of(b2b.partner_consent(l)) = 'expired' and b2b.route_outlook(l) ->> 'outlook' = 'b2c_nurture' and b2b.route_outlook(l) ->> 'reason' = 'consent_no_answer',
                        b2b.route_outlook(l)::text);
  perform set_config('b2b.actor', 'engine', true);
  n := b2b.route_ready_leads(50);
  l := pg_temp.lead('c');
  a := pg_temp.alloc('c');
  insert into r values ('c_sweep_nurture', n = 1 and a.destination_type = 'in_house' and a.b2c_lane = 'nurture' and a.reason = 'consent_no_answer' and a.mode = 'fallback'
                        and a.status = 'handed_off' and l.destination_type = 'in_house' and l.allocation_reason = 'consent_no_answer', coalesce(a::text, 'n=' || n));
  insert into r values ('c_sweep_left_others', (select count(*) from b2b.engine_decisions d where d.lead_id = pg_temp.v('d')::bigint) = 0
                        and (pg_temp.lead('d')).destination_type is null, null);
  h := pg_temp.handoff('c');
  insert into r values ('c_handoff_nurture', h ->> 'reason' = 'consent_no_answer' and h ->> 'b2c_lane' = 'nurture' and h -> 'handling' ->> 'job' = 'qualify'
                        and (h -> 'consent' ->> 'request_id')::bigint = q.id and h -> 'consent' ->> 'status' = 'expired', h::text);
  insert into r values ('c_hold_qualification_nurture', b2b.b2c_hold(l) ->> 'kind' = 'qualification_nurture' and coalesce((b2b.b2c_hold(l) ->> 'open')::boolean, false), b2b.b2c_hold(l)::text);
  -- a later YES (the expired request of the cycle is answered) requalifies the lead: nurture closed, partner 20
  v := b2b.consent_answer(l.id, null, 'yes', 'b2c_crm', '{"message_id":"wamid.C1"}');
  insert into r values ('c_late_yes_requalified', (v ->> 'recorded')::boolean and (v ->> 'request_id')::bigint = q.id and v ->> 'state' = 'given' and v ->> 'effect' = 'requalified'
                        and (v -> 'route' ->> 'requalified')::boolean and v -> 'route' ->> 'destination' = 'partner', v::text);
  l := pg_temp.lead('c');
  insert into r values ('c_late_yes_partner', l.destination_type = 'partner' and l.partner_id = 20 and l.consent_partner_share_at is not null
                        and (select count(*) from b2b.allocations x where x.lead_id = l.id and x.destination_type = 'partner' and x.partner_id = 20 and x.origin = 'requalify') = 1, l.allocation_reason);
  insert into r values ('c_nurture_closed', (select x.status = 'closed' and x.outcome = 'requalified' from b2b.allocations x where x.id = a.id)
                        and exists (select 1 from b2b.events where type = 'b2c.lead_requalified' and lead_id = l.id and (payload ->> 'closed_allocation_id')::bigint = a.id and payload ->> 'destination' = 'partner'), null);
end $x$;

-- ======================================================================================================== consent versions and asking
select pg_temp.mk('unc', '919876551011', 'MBA', '{"consent_partner_share_at": "2026-10-01T10:00:00+05:30", "consent_text_version": "web-v3"}');
select pg_temp.mk('nobody', '919876551012', 'ZZConsentNobody');
select pg_temp.mk('multi', '919876551013', 'ZZConsentNobody');
select b2b.lead_interest_add(pg_temp.v('multi')::bigint, '"MBA"'::jsonb, 'api');
do $x$
declare v jsonb; l public.student_leads;
begin
  -- a stamp under a version that does not cover admission partners is not consent (critic A5)
  l := pg_temp.lead('unc');
  insert into r values ('uncovered_stamp_not_consent', l.consent_partner_share_at is not null and not b2b.consent_text_covers('web-v3')
                        and not coalesce((b2b.partner_consent(l) ->> 'given')::boolean, false) and (b2b.partner_consent(l) ->> 'stamp_uncovered')::boolean
                        and b2b.consent_state_of(b2b.partner_consent(l)) = 'stamp_uncovered', b2b.partner_consent(l)::text);
  v := pg_temp.decide('unc', true);
  insert into r values ('uncovered_stamp_asked', v ->> 'destination' = 'consent_requested' and (v -> 'consent_request' ->> 'created')::boolean, v::text);
  -- a lead whose only interest is offered by nobody is still asked (literal R8)
  v := pg_temp.decide('nobody', true);
  insert into r values ('nobody_offers_still_asked', v ->> 'destination' = 'consent_requested' and v -> 'consent_request' ->> 'programme' = 'ZZConsentNobody'
                        and v -> 'consent_request' ->> 'programme_course_key' = 'zzconsentnobody', v::text);
  perform pg_temp.put('req_nobody', v -> 'consent_request' ->> 'request_id');
  -- the request names the first interest with an eligible offer (critic B19): MBA, not the unoffered primary
  l := pg_temp.lead('multi');
  insert into r values ('multi_interests', jsonb_array_length(b2b.lead_interest_list(l)) = 2 and b2b.lead_interest_list(l) -> 0 ->> 'course_key' = 'zzconsentnobody'
                        and b2b.lead_interest_list(l) -> 1 ->> 'course_key' = 'mba', b2b.lead_interest_list(l)::text);
  v := pg_temp.decide('multi', true);
  insert into r values ('request_names_eligible_interest', v ->> 'destination' = 'consent_requested' and v -> 'consent_request' ->> 'programme' = 'MBA'
                        and v -> 'consent_request' ->> 'programme_course_key' = 'mba'
                        and (select q.programme from b2b.consent_requests q where q.id = (v -> 'consent_request' ->> 'request_id')::bigint) = 'MBA', v::text);
  insert into r values ('request_text_names_mba', exists (select 1 from b2b.events e where e.type = 'b2c.consent_requested' and e.lead_id = l.id and e.payload ->> 'text' like '%counsellor for MBA, may we share%'), null);
end $x$;

-- ======================================================================================================== channels and timing
-- the hourly budget (critic B20): with the budget at the number already published, the next request is queued
update b2b.settings set value = value || jsonb_build_object('consent_requests_per_hour',
  (select count(*) from b2b.consent_requests q where q.channel = 'b2c_crm' and q.published_at > now() - interval '1 hour')) where key = 'engine';
select pg_temp.mk('budget', '919876551021', 'MBA');
do $x$
declare v jsonb; q b2b.consent_requests; tick jsonb;
begin
  v := pg_temp.decide('budget', true);
  select * into q from b2b.consent_requests where lead_id = pg_temp.v('budget')::bigint;
  perform pg_temp.put('req_budget', q.id::text);
  insert into r values ('budget_queued', v ->> 'destination' = 'consent_requested' and v -> 'consent_request' ->> 'status' = 'queued' and (v -> 'consent_request' ->> 'expires_at') is null
                        and not (v -> 'consent_request' ->> 'published')::boolean and q.status = 'queued' and q.published_at is null and q.expires_at is null, v::text);
  insert into r values ('budget_queued_wait_15min', exists (select 1 from b2b.lead_waits w where w.lead_id = q.lead_id and w.decide_after between now() + interval '14 minutes' and now() + interval '16 minutes'), null);
  insert into r values ('budget_queued_state', b2b.consent_state_of(b2b.partner_consent(pg_temp.lead('budget'))) = 'queued'
                        and not exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id), null);
  tick := b2b.consent_tick();
  insert into r values ('budget_tick_still_queued', (tick ->> 'published')::int = 0 and (select status from b2b.consent_requests where id = q.id) = 'queued', tick::text);
  -- an hour later the budget is free: the tick publishes it with a fresh 48-hour expiry and moves the wait
  update b2b.consent_requests set published_at = published_at - interval '2 hours' where channel = 'b2c_crm' and published_at is not null and id <> q.id;
  tick := b2b.consent_tick();
  select * into q from b2b.consent_requests where id = q.id;
  insert into r values ('budget_tick_publishes', (tick ->> 'published')::int = 1 and q.status = 'requested' and q.published_at is not null and q.expires_at = q.published_at + interval '48 hours'
                        and exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id), tick::text);
  insert into r values ('budget_wait_moved', (select w.decide_after from b2b.lead_waits w where w.lead_id = q.lead_id) = q.expires_at, null);
end $x$;
update b2b.settings set value = value || '{"consent_requests_per_hour": 100}'::jsonb where key = 'engine';

-- no endpoint: unsendable plus an alert; the tick republishes once an endpoint subscribes
update b2b.webhook_endpoints set active = false where consumer = 'b2c_crm';
select pg_temp.mk('noep', '919876551022', 'MBA');
do $x$
declare v jsonb; q b2b.consent_requests; tick jsonb;
begin
  v := pg_temp.decide('noep', true);
  select * into q from b2b.consent_requests where lead_id = pg_temp.v('noep')::bigint;
  insert into r values ('no_endpoint_unsendable', v ->> 'destination' = 'consent_requested' and v -> 'consent_request' ->> 'status' = 'unsendable' and q.status = 'unsendable' and q.expires_at is not null
                        and exists (select 1 from b2b.events where type = 'alert.consent_unsendable' and lead_id = q.lead_id and (payload ->> 'request_id')::bigint = q.id)
                        and not exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id), v::text);
  update b2b.webhook_endpoints set active = true where consumer = 'b2c_crm';
  tick := b2b.consent_tick();
  insert into r values ('endpoint_back_republished', (tick ->> 'republished')::int = 1 and (select status from b2b.consent_requests where id = q.id) = 'requested'
                        and exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id), tick::text);
  -- the B2C CRM reports the send: expires_at follows sent_at
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-sent-noep', 'type', 'b2ccrm.consent_request_sent',
         'data', jsonb_build_object('request_id', q.id, 'sent_at', (now() - interval '20 minutes')::text, 'message_id', 'wamid.S1')));
  select * into q from b2b.consent_requests where id = q.id;
  insert into r values ('request_sent_moves_expiry', (v ->> 'ok')::boolean and q.status = 'sent' and q.sent_at between now() - interval '21 minutes' and now() - interval '19 minutes'
                        and q.expires_at = q.sent_at + interval '48 hours' and q.evidence ->> 'sent_message_id' = 'wamid.S1'
                        and (select w.decide_after from b2b.lead_waits w where w.lead_id = q.lead_id) = q.expires_at, v::text || ' ' || q::text);
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-sent-unknown', 'type', 'b2ccrm.consent_request_sent', 'data', jsonb_build_object('request_id', 999999999, 'sent_at', now()::text)));
  insert into r values ('request_sent_unknown_404', not (v ->> 'ok')::boolean and (v ->> 'status')::int = 404, v::text);
end $x$;

-- Witty channel: a W2 stub with a search_path, created in this transaction, queues the request for Witty leads
create function public.w2_consent_request(p jsonb) returns jsonb language sql set search_path = public as $w$
  select jsonb_build_object('queued', true, 'echo', p) $w$;
select pg_temp.mk('w1', '919876551031', 'MBA', '{"classification": "WARM", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
select pg_temp.mk('w2', '919876551032', 'MBA', '{"classification": "WARM", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
select pg_temp.mk('w3', '919876551033', 'MBA', '{"classification": "WARM", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
insert into public.w2_conversations (phone) values ('919876551031'), ('919876551032'), ('919876551033');
do $x$
declare v jsonb; q b2b.consent_requests; q2 b2b.consent_requests; tick jsonb; l public.student_leads; c b2b.lead_consents;
begin
  insert into r values ('witty_leads_detected', b2b.is_witty_lead(pg_temp.lead('w1')) and b2b.is_witty_lead(pg_temp.lead('w2')), null);
  v := pg_temp.decide('w1', true);
  select * into q from b2b.consent_requests where lead_id = pg_temp.v('w1')::bigint;
  insert into r values ('witty_channel_used', v ->> 'destination' = 'consent_requested' and v -> 'consent_request' ->> 'channel' = 'witty' and q.channel = 'witty' and q.status = 'requested'
                        and q.text_version = 'witty_partner_consent_v1' and (q.evidence -> 'witty' -> 'echo' ->> 'phone') = '919876551031'
                        and (q.evidence -> 'witty' -> 'echo' ->> 'request_id')::bigint = q.id and (q.evidence -> 'witty' -> 'echo' ->> 'programme') = 'MBA'
                        and (q.evidence -> 'witty' -> 'echo' ->> 'not_before') is not null, v::text);
  insert into r values ('witty_sends_itself', not exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id)
                        and exists (select 1 from b2b.events where type = 'lead.consent_requested' and lead_id = q.lead_id and payload ->> 'channel' = 'witty'), null);
  v := pg_temp.decide('w2', true);
  select * into q2 from b2b.consent_requests where lead_id = pg_temp.v('w2')::bigint;
  insert into r values ('witty_second_lead_asked', q2.channel = 'witty' and q2.status = 'requested', v::text);
  -- Witty's touchpoints (older than the 2-minute horizon) are dispatched by reenquiry_tick: sent, then YES for w1, NO for w2
  insert into public.touchpoints (lead_id, phone, source_system, event_type, payload, occurred_at, created_at) values
    (q.lead_id, '919876551031', 'witty', 'consent.partner_requested', jsonb_build_object('request_id', q.id, 'message_id', 'wamid.W1s'), now() - interval '30 minutes', now() - interval '30 minutes'),
    (q.lead_id, '919876551031', 'witty', 'consent.partner_granted', jsonb_build_object('request_id', q.id, 'message_id', 'wamid.W1y'), now() - interval '10 minutes', now() - interval '10 minutes'),
    (q2.lead_id, '919876551032', 'witty', 'consent.partner_requested', jsonb_build_object('request_id', q2.id, 'message_id', 'wamid.W2s'), now() - interval '30 minutes', now() - interval '30 minutes'),
    (q2.lead_id, '919876551032', 'witty', 'consent.partner_declined', jsonb_build_object('request_id', q2.id, 'message_id', 'wamid.W2n'), now() - interval '9 minutes', now() - interval '9 minutes');
  perform set_config('b2b.actor', 'engine', true);
  tick := b2b.reenquiry_tick(1000);
  insert into r values ('witty_touchpoints_dispatched', (tick ->> 'consent')::int = 4 and (tick ->> 'errors')::int = 0, tick::text);
  select * into q from b2b.consent_requests where id = q.id;
  insert into r values ('witty_sent_recorded', q.status = 'answered' and q.sent_at between now() - interval '31 minutes' and now() - interval '29 minutes' and q.answer = 'yes' and q.answer_source = 'witty', q::text);
  l := pg_temp.lead('w1');
  select * into c from b2b.lead_consents where lead_id = l.id order by id desc limit 1;
  insert into r values ('witty_yes_partner', c.state = 'given' and c.source = 'witty' and c.text_version = 'witty_partner_consent_v1' and l.consent_partner_share_at is not null
                        and l.destination_type = 'partner' and l.partner_id = 20, c::text);
  l := pg_temp.lead('w2');
  insert into r values ('witty_no_sales', (b2b.partner_consent(l) ->> 'refused')::boolean and l.destination_type = 'in_house' and l.allocation_reason = 'no_partner_consent'
                        and (pg_temp.alloc('w2')).b2c_lane = 'sales', b2b.partner_consent(l)::text);
  insert into r values ('witty_touchpoints_not_reenquiries', not exists (select 1 from b2b.lead_reenquiries where lead_id in (pg_temp.v('w1')::bigint, pg_temp.v('w2')::bigint)), null);
  -- a second tick sees nothing new
  tick := b2b.reenquiry_tick(1000);
  insert into r values ('witty_tick_idempotent', (tick ->> 'consent')::int = 0 and (select count(*) from b2b.lead_consents where lead_id in (pg_temp.v('w1')::bigint, pg_temp.v('w2')::bigint)) = 2, tick::text);
end $x$;
-- Witty declines to queue (queued = false): the request falls back to the B2C number
create or replace function public.w2_consent_request(p jsonb) returns jsonb language sql set search_path = public as $w$
  select jsonb_build_object('queued', false, 'reason', 'no open conversation') $w$;
do $x$
declare v jsonb; q b2b.consent_requests;
begin
  v := pg_temp.decide('w3', true);
  select * into q from b2b.consent_requests where lead_id = pg_temp.v('w3')::bigint;
  insert into r values ('witty_fallback_b2c', v -> 'consent_request' ->> 'channel' = 'b2c_crm' and q.channel = 'b2c_crm' and q.status = 'requested' and q.text_version = 'wa_partner_consent:v1'
                        and (q.evidence -> 'witty_fallback' ->> 'reason') = 'no open conversation' and v -> 'consent_request' ->> 'why' like 'Witty did not queue%'
                        and exists (select 1 from b2b.events where type = 'b2c.consent_requested' and lead_id = q.lead_id), v::text);
end $x$;
create or replace function public.w2_consent_request(p jsonb) returns jsonb language sql set search_path = public as $w$
  select jsonb_build_object('queued', true) $w$;

-- ======================================================================================================== paths and policies
-- Pass to CRM of a not-passed lead asks for consent; YES then routes (no partner offers the course: B2C sales)
select pg_temp.mk('mis', '919876551041', 'Astrology');
do $x$
declare v jsonb; l public.student_leads; a b2b.allocations;
begin
  v := pg_temp.decide('mis', true);
  insert into r values ('pass_not_passed_first', v ->> 'destination' = 'not_passed' and v ->> 'reason' = 'program_mismatch'
                        and exists (select 1 from b2b.not_passed np where np.lead_id = pg_temp.v('mis')::bigint and np.passed_at is null and np.detail = 'course_not_in_catalogue'), v::text);
end $x$;
set local role authenticated;
select pg_temp.admin();
do $x$
declare v jsonb;
begin
  v := b2b.pass_to_crm(array[pg_temp.v('mis')::bigint], 'the student confirmed the course on a call');
  insert into r values ('pass_asks_consent', (v ->> 'passed')::int = 1 and v -> 'results' -> 0 ->> 'destination' = 'consent_requested' and v -> 'results' -> 0 ->> 'outcome' = 'consent_requested', v::text);
end $x$;
reset role;
do $x$
declare v jsonb; l public.student_leads; a b2b.allocations;
begin
  insert into r values ('pass_request_context_decision', (pg_temp.req('mis')).context = 'decision' and (pg_temp.req('mis')).status = 'requested', null);
  v := b2b.consent_answer(pg_temp.v('mis')::bigint, null, 'yes', 'b2c_crm', '{"message_id":"wamid.M1"}');
  a := pg_temp.alloc('mis');
  insert into r values ('pass_yes_routed_b2c', v ->> 'effect' = 'routed' and a.destination_type = 'in_house' and a.b2c_lane = 'sales' and a.reason = 'no_partner_offers_programme', v::text);
end $x$;

-- a nurture lead that qualifies without consent stays in nurture with a request (context nurture), and moves on YES
select pg_temp.mk('nq', '919876551042', null);
do $x$
declare v jsonb; l public.student_leads; a b2b.allocations; q b2b.consent_requests;
begin
  v := pg_temp.decide('nq', true);
  a := pg_temp.alloc('nq');
  insert into r values ('nq_nurture_not_qualified', v ->> 'destination' = 'in_house' and v ->> 'reason' = 'not_qualified' and a.b2c_lane = 'nurture' and a.reason = 'not_qualified', v::text);
  -- B2C completes the course
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876551042', 'source_system', 'b2c_crm', 'event_type', 'lead.updated', 'lead', jsonb_build_object('interested_course', 'MBA')));
  l := pg_temp.lead('nq');
  insert into r values ('nq_now_qualified', l.interested_course = 'MBA' and b2b.lead_class(l) ->> 'class' = 'qualified' and l.allocation_id = a.id, b2b.lead_class(l)::text);
  v := b2b.requalify_lead(l.id, 'm31 consent test');
  select * into q from b2b.consent_requests where lead_id = l.id order by id desc limit 1;
  insert into r values ('nq_requalify_waits_consent', not (v ->> 'requalified')::boolean and v ->> 'waiting' = 'consent' and q.context = 'nurture' and q.status = 'requested'
                        and (select nw.consent_request_id from b2b.nurture_watch nw where nw.lead_id = l.id) = q.id, v::text);
  l := pg_temp.lead('nq');
  insert into r values ('nq_still_in_nurture', l.allocation_id = a.id and l.destination_type = 'in_house' and (select x.status from b2b.allocations x where x.id = a.id) = 'handed_off', null);
  insert into r values ('nq_redecide_pending', (pg_temp.decide('nq', false)) ->> 'outcome' = 're-enquired' or (pg_temp.decide('nq', false)) ->> 'outcome' = 'consent_pending', (pg_temp.decide('nq', false))::text);
  v := b2b.consent_answer(l.id, q.id, 'yes', 'b2c_crm', '{"message_id":"wamid.NQ1"}');
  l := pg_temp.lead('nq');
  insert into r values ('nq_yes_requalified_partner', v ->> 'effect' = 'requalified' and (v -> 'route' ->> 'requalified')::boolean and l.destination_type = 'partner' and l.partner_id = 20
                        and (select x.status = 'closed' and x.outcome = 'requalified' from b2b.allocations x where x.id = a.id)
                        and (pg_temp.alloc('nq')).origin = 'requalify', v::text);
end $x$;

-- NO after a push: the consent is withdrawn, the partner is told, the lead stays where it is
do $x$
declare a b2b.allocations; v jsonb; l public.student_leads;
begin
  a := pg_temp.alloc('a');
  perform set_config('b2b.actor', 'engine', true);
  update b2b.allocations set status = 'pushing' where id = a.id and status = 'queued';
  perform b2b.apply_created(a.id, 'REC-' || a.id);
  perform b2b.accept_allocation(a.id);
  insert into r values ('a_accepted', (select status from b2b.allocations where id = a.id) = 'accepted' and public.w2_crm_owned('919876551001'), null);
  v := pg_temp.b2c(jsonb_build_object('event_id', 'm31e-no-after-push', 'type', 'b2ccrm.partner_consent',
         'data', jsonb_build_object('lead_id', pg_temp.v('a')::bigint, 'answer', 'no', 'message_id', 'wamid.A9', 'channel', 'whatsapp')));
  l := pg_temp.lead('a');
  insert into r values ('withdrawn_after_push', (v ->> 'ok')::boolean and (select c.state from b2b.lead_consents c where c.lead_id = l.id order by c.id desc limit 1) = 'withdrawn'
                        and (b2b.partner_consent(l) ->> 'refused')::boolean and b2b.partner_consent(l) ->> 'last_state' = 'withdrawn'
                        and b2b.consent_state_of(b2b.partner_consent(l)) = 'withdrawn', v::text);
  insert into r values ('withdrawn_alerts', exists (select 1 from b2b.events where type = 'alert.consent_withdrawn' and lead_id = l.id and allocation_id = a.id and partner_id = 20)
                        and exists (select 1 from b2b.events where type = 'alert.partner_optout_notice' and lead_id = l.id and allocation_id = a.id and partner_id = 20 and payload ->> 'reference' = a.reference), null);
  insert into r values ('withdrawn_lead_untouched', l.destination_type = 'partner' and l.allocation_id = a.id and (select status from b2b.allocations where id = a.id) = 'accepted', null);
end $x$;

-- the Admin: a refusal is recorded; a YES is refused while consent_admin_yes is false, then needs written evidence
set local role authenticated;
select pg_temp.admin();
do $x$
declare v jsonb; lr jsonb;
begin
  -- lead_routing shows the open request and the state
  lr := b2b.lead_routing(pg_temp.v('d')::bigint);
  insert into r values ('admin_lead_routing_consent', lr -> 'consent_detail' ->> 'state' = 'requested' and jsonb_array_length(lr -> 'consent_detail' -> 'requests') = 1
                        and not (lr ->> 'consent')::boolean and lr -> 'outlook' ->> 'outlook' = 'consent_pending', (lr -> 'consent_detail')::text);
  begin perform b2b.consent_record_admin(pg_temp.v('d')::bigint, 'no', 'short'); insert into r values ('admin_note_required', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('admin_note_required', true, sqlerrm); end;
  v := b2b.consent_record_admin(pg_temp.v('d')::bigint, 'no', 'the student wants only Eduwit to call them');
  insert into r values ('admin_no_recorded', (v ->> 'recorded')::boolean and v ->> 'state' = 'refused' and (v ->> 'request_id')::bigint = pg_temp.v('req_d')::bigint
                        and v ->> 'effect' = 'routed' and v -> 'route' ->> 'destination' = 'in_house' and v -> 'route' ->> 'reason' = 'no_partner_consent' and v -> 'route' ->> 'b2c_lane' = 'sales', v::text);
  begin perform b2b.consent_record_admin(pg_temp.v('nobody')::bigint, 'yes', 'the student said yes on the call', 'call-2026-10-08-01'); insert into r values ('admin_yes_refused_off', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('admin_yes_refused_off', sqlerrm like '%consent_admin_yes%', sqlerrm); end;
  v := b2b.engine_settings_save('{"consent_admin_yes": true}'::jsonb, 'm31 consent test: allow a YES given on a call');
  begin perform b2b.consent_record_admin(pg_temp.v('nobody')::bigint, 'yes', 'the student said yes on the call', null); insert into r values ('admin_yes_needs_evidence', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('admin_yes_needs_evidence', sqlerrm like '%evidence%', sqlerrm); end;
  v := b2b.consent_record_admin(pg_temp.v('nobody')::bigint, 'yes', 'the student said yes on the call', 'call-2026-10-08-01');
  insert into r values ('admin_yes_recorded', (v ->> 'recorded')::boolean and v ->> 'state' = 'given' and v ->> 'effect' = 'routed'
                        and v -> 'route' ->> 'destination' = 'in_house' and v -> 'route' ->> 'reason' = 'no_partner_offers_programme' and v -> 'route' ->> 'b2c_lane' = 'sales', v::text);
  -- an Admin request for a lead whose consent is given is refused; the policy has no 'off'
  begin perform b2b.consent_request_admin(pg_temp.v('nobody')::bigint, 'ask again'); insert into r values ('admin_request_refused_when_given', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('admin_request_refused_when_given', true, sqlerrm); end;
  begin perform b2b.engine_settings_save('{"consent_policy": "off"}'::jsonb, 'm31 consent test'); insert into r values ('policy_off_refused', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('policy_off_refused', true, sqlerrm); end;
  v := b2b.engine_settings_save('{"consent_policy": "b2c_sales"}'::jsonb, 'm31 consent test: policy b2c_sales');
  insert into r values ('policy_b2c_sales_saved', (select value ->> 'consent_policy' from b2b.settings where key = 'engine') = 'b2c_sales', v::text);
end $x$;
reset role;
insert into r select 'admin_ledger_rows', (select c.source = 'admin' and c.evidence ->> 'evidence_ref' = 'call-2026-10-08-01' and c.evidence ->> 'by' = 'aaaaaaaa-0000-0000-0000-0000000000e8'
                                             from b2b.lead_consents c where c.lead_id = pg_temp.v('nobody')::bigint order by c.id desc limit 1)
                                    and (select c.source = 'admin' and c.evidence ->> 'note' like 'the student wants only%' from b2b.lead_consents c where c.lead_id = pg_temp.v('d')::bigint order by c.id desc limit 1), null;
insert into r select 'admin_nobody_stamped', (pg_temp.lead('nobody')).consent_partner_share_at is not null and (pg_temp.lead('nobody')).consent_text_version = 'wa_partner_consent:v1', null;

-- consent_policy b2c_sales: no request, B2C sales no_partner_consent at once
select pg_temp.mk('pol', '919876551051', 'MBA');
do $x$
declare v jsonb; a b2b.allocations;
begin
  insert into r values ('policy_outlook_b2c_sales', b2b.route_outlook(pg_temp.lead('pol')) ->> 'outlook' = 'b2c_sales' and b2b.route_outlook(pg_temp.lead('pol')) ->> 'reason' = 'no_partner_consent', null);
  v := pg_temp.decide('pol', true);
  a := pg_temp.alloc('pol');
  insert into r values ('policy_b2c_sales_routes', v ->> 'destination' = 'in_house' and v ->> 'reason' = 'no_partner_consent' and v ->> 'b2c_lane' = 'sales' and v ->> 'mode' = 'fallback'
                        and a.reason = 'no_partner_consent' and not exists (select 1 from b2b.consent_requests where lead_id = pg_temp.v('pol')::bigint), v::text);
end $x$;
update b2b.settings set value = value || '{"consent_policy": "ask"}'::jsonb where key = 'engine';

-- a test lead never gets a request
select pg_temp.mk('tst', '910000551061', 'MBA');
do $x$
declare v jsonb;
begin
  v := pg_temp.decide('tst', true);
  insert into r values ('test_lead_nothing', v ->> 'destination' = 'none' and v ->> 'reason' = 'test_lead' and v ->> 'outcome' = 'test_lead' and not (v ->> 'committed')::boolean
                        and not exists (select 1 from b2b.consent_requests where lead_id = pg_temp.v('tst')::bigint), v::text);
  v := b2b.consent_request_create(pg_temp.v('tst')::bigint, 'decision', null);
  insert into r values ('test_lead_no_request', not (v ->> 'created')::boolean and v ->> 'why' = 'test lead' and not exists (select 1 from b2b.consent_requests where lead_id = pg_temp.v('tst')::bigint), v::text);
end $x$;

-- the B2C record carries the consent block (contract version 3)
insert into r select 'b2c_record_consent', (rec -> 'consent' ->> 'partner_share_given')::boolean and rec -> 'consent' ->> 'state' = 'given' and (rec ->> 'contract_version')::int = 3
                     and rec -> 'consent' -> 'partner_share_request' ->> 'status' = 'answered' and rec -> 'consent' -> 'partner_share_request' ->> 'answer' = 'yes', (rec -> 'consent')::text
  from (select b2b.b2c_record(pg_temp.lead('c')) rec) x;

-- ======================================================================================================== consent texts
insert into r select 'covers_registered_covering', b2b.consent_text_covers('test-partner-share:v1') and b2b.consent_text_covers('wa_partner_consent:v1') and b2b.consent_text_covers('witty-notice-2026-10-v2'), null;
insert into r select 'covers_not', not b2b.consent_text_covers('web-v3') and not b2b.consent_text_covers('unknown-version') and not b2b.consent_text_covers(null), null;
insert into r select 'seeded_texts_unapproved', (select count(*) from b2b.consent_texts where version in ('wa_partner_consent:v1', 'witty-notice-2026-10-v2', 'witty_partner_consent_v1') and lawyer_approved_at is null) = 3, null;
set local role authenticated;
select pg_temp.admin();
do $x$
declare v jsonb;
begin
  begin perform b2b.consent_text_save('{"version":"wa_partner_consent:v1","lawyer_approved":true,"approval_note":"short"}'::jsonb, 'approve'); insert into r values ('text_approval_needs_note', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('text_approval_needs_note', true, sqlerrm); end;
  begin perform b2b.consent_text_save('{"version":"m31e-bad","channel":"web_form","purposes":["sales"],"body":"names partners","covers_admission_partners":true}'::jsonb, 'save'); insert into r values ('text_covering_needs_purpose', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('text_covering_needs_purpose', true, sqlerrm); end;
  v := b2b.consent_text_save('{"version":"wa_partner_consent:v1","lawyer_approved":true,"approval_note":"approved by counsel on 8 Oct 2026"}'::jsonb, 'lawyer approval');
  insert into r values ('text_approved', (v ->> 'lawyer_approved_at') is not null and v ->> 'approved_by' = 'm31e-admin@test.local' and (v ->> 'covers_admission_partners')::boolean, v::text);
  insert into r values ('text_saved_event', exists (select 1 from b2b.events where type = 'consent_text.saved' and payload ->> 'version' = 'wa_partner_consent:v1' and (payload ->> 'approved')::boolean), null);
  -- a changed wording loses its approval
  v := b2b.consent_text_save('{"version":"wa_partner_consent:v1","body":"May we share your details for {{programme}} with our admission partner (edtech company)? Reply YES or NO."}'::jsonb, 'reworded');
  insert into r values ('text_change_clears_approval', (v ->> 'lawyer_approved_at') is null and (v ->> 'approved_by') is null, v::text);
  v := b2b.consent_text_save('{"version":"wa_partner_consent:v1","lawyer_approved":true,"approval_note":"re-approved by counsel on 8 Oct 2026"}'::jsonb, 'lawyer approval');
  insert into r values ('text_reapproved', (v ->> 'lawyer_approved_at') is not null, null);
end $x$;
reset role;
-- the reworded text is what the next request sends
insert into r select 'request_text_follows_body', b2b.consent_request_text('MBA') = 'May we share your details for MBA with our admission partner (edtech company)? Reply YES or NO.', b2b.consent_request_text('MBA');

-- ======================================================================================================== the go-live gate
-- routing off; two covering texts still unapproved; no W1-stamped Witty lead; the endpoint subscribes to the wrong events
update b2b.live_switches set live = false where scope = 'routing';
update b2b.webhook_endpoints set events = array['b2c.lead_handed_off'] where consumer = 'b2c_crm';
set local role authenticated;
select pg_temp.admin();
do $x$
declare g jsonb; v jsonb;
begin
  g := b2b.routing_golive_check();
  insert into r values ('gate_items_in_order', jsonb_array_length(g) = 5
                        and (select array_agg(x ->> 'key' order by ord) from jsonb_array_elements(g) with ordinality u(x, ord))
                            = array['consent_texts_approved', 'witty_w1_consent_line', 'b2c_endpoint_subscribed', 'witty_w2_consent_request', 'live_partner'], g::text);
  insert into r values ('gate_texts_blocking', not (g -> 0 ->> 'ok')::boolean and (g -> 0 ->> 'blocking')::boolean and not (g -> 0 ->> 'acknowledgeable')::boolean
                        and g -> 0 -> 'detail' -> 'unapproved' ? 'witty-notice-2026-10-v2' and g -> 0 -> 'detail' -> 'unapproved' ? 'witty_partner_consent_v1'
                        and not (g -> 0 -> 'detail' -> 'unapproved' ? 'wa_partner_consent:v1'), (g -> 0)::text);
  insert into r values ('gate_w1_missing', not (g -> 1 ->> 'ok')::boolean and (g -> 1 ->> 'blocking')::boolean and (g -> 1 ->> 'acknowledgeable')::boolean and not (g -> 1 ->> 'acked')::boolean
                        and (g -> 1 -> 'detail' ->> 'leads_14d')::int = 0, (g -> 1)::text);
  insert into r values ('gate_endpoint_missing_event', not (g -> 2 ->> 'ok')::boolean and (g -> 2 ->> 'blocking')::boolean and g -> 2 -> 'detail' -> 'missing' ? 'b2c.consent_requested', (g -> 2)::text);
  insert into r values ('gate_w2_present', (g -> 3 ->> 'ok')::boolean and (g -> 3 ->> 'acknowledgeable')::boolean, (g -> 3)::text);
  insert into r values ('gate_live_partner_warning', (g -> 4 ->> 'ok')::boolean and not (g -> 4 ->> 'blocking')::boolean, (g -> 4)::text);
  -- refused with every failing blocking item named
  begin perform b2b.set_live_switch('routing', true, 'go live'); insert into r values ('gate_refuses_three', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('gate_refuses_three', sqlerrm like 'routing cannot go live: consent_texts_approved: %' and sqlerrm like '%; witty_w1_consent_line: %'
                                                                                  and sqlerrm like '%; b2c_endpoint_subscribed: %' and sqlerrm not like '%witty_w2%' and sqlerrm not like '%live_partner%', sqlerrm); end;
  insert into r values ('gate_still_off', not b2b.is_live('routing'), null);
  -- the lawyer approves the remaining texts: still refused (W1, endpoint)
  perform b2b.consent_text_save('{"version":"witty-notice-2026-10-v2","lawyer_approved":true,"approval_note":"approved by counsel on 8 Oct 2026"}'::jsonb, 'lawyer approval');
  perform b2b.consent_text_save('{"version":"witty_partner_consent_v1","lawyer_approved":true,"approval_note":"approved by counsel on 8 Oct 2026"}'::jsonb, 'lawyer approval');
  g := b2b.routing_golive_check();
  insert into r values ('gate_texts_ok_after_approval', (g -> 0 ->> 'ok')::boolean, (g -> 0)::text);
  begin perform b2b.set_live_switch('routing', true, 'go live'); insert into r values ('gate_refuses_two', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('gate_refuses_two', sqlerrm like 'routing cannot go live: witty_w1_consent_line: %; b2c_endpoint_subscribed: %', sqlerrm); end;
  -- the acknowledgement needs a real reason and one of the two Witty keys
  begin perform b2b.routing_golive_ack('b2c_endpoint_subscribed', 'a long enough reason'); insert into r values ('ack_wrong_key', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('ack_wrong_key', true, sqlerrm); end;
  begin perform b2b.routing_golive_ack('witty_w1_consent_line', 'short'); insert into r values ('ack_short_reason', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('ack_short_reason', true, sqlerrm); end;
  g := b2b.routing_golive_ack('witty_w1_consent_line', 'W1 consent line goes live with the Witty release on 9 Oct');
  insert into r values ('ack_recorded', not (g -> 1 ->> 'ok')::boolean and (g -> 1 ->> 'acked')::boolean and g -> 1 -> 'ack' ->> 'by' = 'aaaaaaaa-0000-0000-0000-0000000000e8'
                        and g -> 1 -> 'ack' ->> 'reason' like 'W1 consent line%' and (g -> 1 -> 'ack' ->> 'at') is not null, (g -> 1)::text);
  insert into r values ('ack_versioned', exists (select 1 from b2b.settings_versions where key = 'golive_acks' and reason = 'go-live acknowledgement: witty_w1_consent_line')
                        and exists (select 1 from b2b.events where type = 'routing.golive_acked' and payload ->> 'key' = 'witty_w1_consent_line'), null);
  begin perform b2b.set_live_switch('routing', true, 'go live'); insert into r values ('gate_refuses_endpoint_only', false, 'no error');
  exception when sqlstate '22023' then insert into r values ('gate_refuses_endpoint_only', sqlerrm = 'routing cannot go live: b2c_endpoint_subscribed: ' || (g -> 2 ->> 'why'), sqlerrm); end;
end $x$;
reset role;
-- the B2C endpoint subscribes to the consent request: the switch turns on
update b2b.webhook_endpoints set events = array['b2c.lead_handed_off', 'b2c.consent_requested'] where consumer = 'b2c_crm';
set local role authenticated;
select pg_temp.admin();
do $x$
declare g jsonb; v jsonb;
begin
  g := b2b.routing_golive_check();
  insert into r values ('gate_endpoint_ok', (g -> 2 ->> 'ok')::boolean and (g -> 0 ->> 'ok')::boolean and not (g -> 1 ->> 'ok')::boolean and (g -> 1 ->> 'acked')::boolean, (g -> 2)::text);
  v := b2b.set_live_switch('routing', true, 'go live');
  insert into r values ('gate_passes_with_ack', (v ->> 'live')::boolean and b2b.is_live('routing'), v::text);
  v := b2b.set_live_switch('routing', false, 'pause');
  insert into r values ('switch_off_always_allowed', not (v ->> 'live')::boolean and not b2b.is_live('routing'), v::text);
end $x$;
reset role;
-- a Witty lead carrying the W1 line satisfies the item without an acknowledgement
update b2b.settings set value = value - 'witty_w1_consent_line' where key = 'golive_acks';
select pg_temp.mk('w1line', '919876551071', 'MBA', '{"classification": "WARM", "source": "whatsapp_direct", "first_agent_channel": "whatsapp", "consent_partner_share_at": "2026-10-08T09:00:00+05:30", "consent_text_version": "witty-notice-2026-10-v2"}', 'witty');
set local role authenticated;
select pg_temp.admin();
do $x$
declare g jsonb; v jsonb;
begin
  g := b2b.routing_golive_check();
  insert into r values ('gate_w1_lead_counts', (g -> 1 ->> 'ok')::boolean and not (g -> 1 ->> 'acked')::boolean and (g -> 1 -> 'detail' ->> 'leads_14d')::int = 1, (g -> 1)::text);
  insert into r values ('gate_all_ok', (select bool_and((x ->> 'ok')::boolean) from jsonb_array_elements(g) x), g::text);
  v := b2b.set_live_switch('routing', true, 'go live');
  insert into r values ('gate_passes_with_w1_lead', (v ->> 'live')::boolean and b2b.is_live('routing'), v::text);
end $x$;
reset role;
insert into r select 'w1_lead_consent_given', (b2b.partner_consent(pg_temp.lead('w1line')) ->> 'given')::boolean and b2b.partner_consent(pg_temp.lead('w1line')) ->> 'source' = 'stamp'
                     and b2b.route_outlook(pg_temp.lead('w1line')) ->> 'outlook' = 'partners', b2b.partner_consent(pg_temp.lead('w1line'))::text;

-- ======================================================================================================== wiring
insert into r select 'cron_consent_tick', exists (select 1 from cron.job where jobname = 'b2b-consent-tick' and schedule = '* * * * *' and command = 'select b2b.consent_tick()'), null;
insert into r select 'grants_internal', bool_and(not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')), string_agg(p.proname, ',')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'b2b' and p.proname in ('consent_request_create', 'consent_answer', 'consent_from_witty', 'consent_tick');
insert into r select 'grants_admin', bool_and(has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')), string_agg(p.proname, ',')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'b2b' and p.proname in ('consent_request_admin', 'consent_record_admin', 'routing_golive_check', 'routing_golive_ack', 'consent_text_save');
insert into r select 'no_stub_bodies', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2b' and p.prosrc like '%contract-stub%'
   and p.proname in ('consent_request_create', 'consent_answer', 'consent_from_witty', 'consent_tick', 'consent_request_admin', 'consent_record_admin', 'routing_golive_check',
                     'routing_golive_ack', 'set_live_switch', 'b2ccrm_event_ingest', 'route_decide', 'requalify_lead', 'reenquiry_tick', 'pass_to_crm', 'consent_text_save')), null;

select * from r order by name;
rollback;
