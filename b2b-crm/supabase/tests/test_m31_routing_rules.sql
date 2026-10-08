-- M31 routing rules (Addendum 3 PART 3 R1-R9, PART 2 + Amendment 1, PART 6.3, PART 7 R8) in PGlite or on STAGING, rolled
-- back. Fixtures are built in the transaction: a ZZ catalogue (one course per test group, so the staging partners never
-- compete), partners with rates and offers, leads through public.lead_intake (Witty, forms, Meta Lead Ads, Google lead
-- forms, B2C-created). Covers R1-R9 in order, rulebook tests 1, 2 (routing parts), 6, 8, 9, 10 and 15, Amendment 1 (18 h),
-- the design's Sweep / Rule order / Caps rows that name this file and the review findings C6 and C124. Seeds are forced
-- through the GUC b2b.route_seed where the lane could matter (exploration_share is set to 0 as well). Test phones are
-- 910000xxxxxx only; every other fixture phone is 91987…; everything is rolled back. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.lead_row(p_lead bigint) returns public.student_leads language sql as $f$ select l from public.student_leads l where l.id = p_lead $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $f$;
create function pg_temp.decide(p_lead bigint, p_commit boolean, p_how text default 'auto', p_note text default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  perform set_config('b2b.route_seed', '0.5', true);
  return b2b.route_decide(p_lead, p_commit, p_note, p_how);
end $f$;
create function pg_temp.uni(p_name text, p_short text) returns bigint language sql as $f$
  insert into public.catalog_universities (name, short_name) values (p_name, p_short) returning id $f$;
create function pg_temp.prog(p_key text, p_course text, p_ck text, p_level text, p_mode text, p_uni bigint, p_fee_y numeric, p_fee_t numeric) returns bigint language sql as $f$
  insert into public.catalog_programs (program_key, university_id, level, course, course_key, specialization, program_name, mode, fee_yearly, fee_total, active)
  values (p_key, p_uni, p_level, p_course, p_ck, 'General', p_course || ' (' || p_key || ')', p_mode, p_fee_y, p_fee_t, true) returning id $f$;
create function pg_temp.partner(p_slug text, p_name text, p_extra jsonb default '{}') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  insert into b2b.partners (slug, name, display_name, status, daily_cap, monthly_cap, contract_min_monthly, lead_criteria, api_base_url, test_endpoint, notify_enabled)
  values (p_slug, p_name, p_name, coalesce(p_extra ->> 'status', 'active'), (p_extra ->> 'daily_cap')::int, (p_extra ->> 'monthly_cap')::int,
          (p_extra ->> 'contract_min_monthly')::int, coalesce(p_extra -> 'criteria', '{}'::jsonb), 'https://' || p_slug || '.zz-rr.example.invalid/leads',
          case when coalesce((p_extra ->> 'sandbox')::boolean, false) then 'https://' || p_slug || '.zz-rr.example.invalid/test' end, false)
  returning id into v_id;
  insert into b2b.live_switches (scope, live, reason) values ('partner:' || v_id, true, 'm31 routing rules test') on conflict (scope) do update set live = true;
  insert into b2b.partner_programme_versions (partner_id, version_no, status, published_at) values (v_id, 1, 'published', now());
  return v_id;
end $f$;
create function pg_temp.offer(p bigint, p_prog bigint, p_fees jsonb default '{}') returns void language sql as $f$
  insert into b2b.partner_programmes (partner_id, programme_id, program_key, source_version_id, fees)
  select p, p_prog, c.program_key, pv.id, p_fees from public.catalog_programs c, b2b.partner_programme_versions pv where c.id = p_prog and pv.partner_id = p $f$;
create function pg_temp.rate(p bigint, p_type text, p_value numeric) returns void language sql as $f$
  insert into b2b.rates (scope, partner_id, rate_type, value, tiers, gst_inclusive) values ('partner', p, p_type, p_value, null, false) $f$;
-- a lead through public.lead_intake: p_sys = source_system (crm writes no touchpoint), p_extra overrides the lead fields
-- (a JSON null removes a default, e.g. '{"consent_partner_share_at": null}')
create function pg_temp.lead(p_phone text, p_course text, p_extra jsonb default '{}', p_sys text default 'crm') returns bigint language plpgsql as $f$
declare v_id bigint; v_lead jsonb;
begin
  perform set_config('b2b.actor', 'engine', true);
  v_lead := jsonb_build_object('full_name', 'M31r ' || p_phone, 'email', 'm31r-' || p_phone || '@test.local', 'interested_course', p_course,
                               'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi', 'source', 'website',
                               'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1') || p_extra;
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', p_sys, 'event_type', 'lead.created', 'lead', jsonb_strip_nulls(v_lead)));
  select l.id into v_id from public.student_leads l where l.whatsapp_number = p_phone and l.deleted_at is null order by l.id desc limit 1;
  return v_id;
end $f$;
create function pg_temp.alloc(p_lead bigint) returns b2b.allocations language sql as $f$
  select a.* from b2b.allocations a join public.student_leads l on l.allocation_id = a.id where l.id = p_lead $f$;
create function pg_temp.pushed(p_alloc bigint) returns text language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  update b2b.allocations set status = 'pushing' where id = p_alloc and status = 'queued';
  return b2b.apply_created(p_alloc, 'REC-' || p_alloc);
end $f$;
create function pg_temp.accept(p_alloc bigint) returns void language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.accept_allocation(p_alloc);
end $f$;
create function pg_temp.pushing(p_alloc bigint) returns void language sql as $f$
  update b2b.allocations set status = 'pushing' where id = p_alloc and status = 'queued' $f$;
create function pg_temp.handoff(p_lead bigint) returns jsonb language sql as $f$
  select e.payload from b2b.events e where e.type = 'b2c.lead_handed_off' and e.lead_id = p_lead order by e.id desc limit 1 $f$;
create function pg_temp.decision(p_alloc bigint) returns b2b.engine_decisions language sql as $f$
  select d.* from b2b.engine_decisions d join b2b.allocations a on a.engine_decision_id = d.id where a.id = p_alloc $f$;
-- the lead's intake touchpoints are moved before its allocation, so only the touchpoints a test adds count as re-enquiries
create function pg_temp.age_touchpoints(p_lead bigint, p_allocated_at timestamptz) returns void language sql as $f$
  update public.student_leads set allocated_at = p_allocated_at where id = p_lead;
  update public.touchpoints set created_at = p_allocated_at - interval '1 day', occurred_at = p_allocated_at - interval '1 day' where lead_id = p_lead $f$;

-- ---------- settings, the admin, consent, the B2C endpoint, the API key ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000fa', 'm31r-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000fa', 'm31r-admin@test.local');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000fa","role":"authenticated","aal":"aal2","email":"m31r-admin@test.local"}', true);
insert into b2b.live_switches (scope, live, reason) values ('routing', true, 'm31 routing rules test') on conflict (scope) do update set live = true;
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"enabled":true,"consent_policy":"ask","kill_switch":false}' where key = 'engine';
update b2b.settings set value = jsonb_set(value, '{a3_fixed,exploration_share}', '0') where key = 'engine';
update b2b.ml_models set status = 'retired' where status in ('shadow', 'challenger', 'champion', 'training');
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at)
values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now());
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m31r b2c', '{events}', 'eb2b_m31rtest', encode(extensions.digest('eb2b_m31rtest_key_0001', 'sha256'), 'hex'));
do $x$
declare sid uuid;
begin
  sid := vault.create_secret('whsec_m31r_test', 'b2b_webhook_m31r', 'm31 routing rules test');
  insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id)
  values ('B2C CRM (m31r)', 'b2c_crm', 'https://b2c.zz-rr.example.invalid/v1/events', array['b2c.*'], true, sid);
end $x$;
select b2b.intake_settings_save('{"google":{"key":"gkey-zz-12345678"}}');

-- the real functions are installed (no contract stub left)
insert into r select 'functions_installed',
  to_regprocedure('b2b.route_decide(bigint,boolean,text,text)') is not null and to_regprocedure('b2b.requalify_tick(integer)') is not null
  and to_regprocedure('b2b.reenquiry_tick(integer)') is not null and to_regprocedure('b2b.route_test_lead(bigint,text,text)') is not null
  and to_regprocedure('b2b.route_to_partners_many(bigint[],text)') is not null and to_regprocedure('b2b.lost_grace_tick()') is not null
  and not exists (select 1 from pg_proc where prosrc ~ 'contract-stub' and pronamespace = 'b2b'::regnamespace), null;

-- ---------- catalogue: one course per test group ----------
select pg_temp.set('U1', pg_temp.uni('ZZ Rules University', 'ZZRU')::text);
select pg_temp.set('P_R1', pg_temp.prog('zz-r1', 'ZZRone', 'zzrone', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R2', pg_temp.prog('zz-r2', 'ZZRtwo', 'zzrtwo', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R4', pg_temp.prog('zz-r4', 'ZZRfour', 'zzrfour', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R5', pg_temp.prog('zz-r5', 'ZZRfive', 'zzrfive', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R6', pg_temp.prog('zz-r6', 'ZZRsix', 'zzrsix', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R7', pg_temp.prog('zz-r7', 'ZZRseven', 'zzrseven', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_R8', pg_temp.prog('zz-r8', 'ZZReight', 'zzreight', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_T9', pg_temp.prog('zz-t9', 'ZZNine', 'zznine', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_T10A', pg_temp.prog('zz-t10a', 'ZZTenA', 'zztena', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_T10B', pg_temp.prog('zz-t10b', 'ZZTenB', 'zztenb', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_T6', pg_temp.prog('zz-t6', 'ZZPaid', 'zzpaid', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_AM', pg_temp.prog('zz-am', 'ZZAmend', 'zzamend', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_CAP', pg_temp.prog('zz-cap', 'ZZCap', 'zzcap', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P_ORD', pg_temp.prog('zz-ord', 'ZZOrder', 'zzorder', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);

-- ---------- partners: Alpha 25 % (most courses), Beta 20 % (R2, 9, order), Sandbox (test endpoint, R1), Gamma (no offers yet), Cap (daily cap 1) ----------
select pg_temp.set('ALPHA', pg_temp.partner('zz-rr-alpha', 'ZZ RR Alpha')::text);
select pg_temp.set('BETA', pg_temp.partner('zz-rr-beta', 'ZZ RR Beta')::text);
select pg_temp.set('SBX', pg_temp.partner('zz-rr-sandbox', 'ZZ RR Sandbox', '{"sandbox": true}')::text);
select pg_temp.set('GAMMA', pg_temp.partner('zz-rr-gamma', 'ZZ RR Gamma')::text);
select pg_temp.set('CAP', pg_temp.partner('zz-rr-cap', 'ZZ RR Cap', '{"daily_cap": 1, "sandbox": true}')::text);
select pg_temp.rate(pg_temp.v('ALPHA')::bigint, 'percent', 25);
select pg_temp.rate(pg_temp.v('BETA')::bigint, 'percent', 20);
select pg_temp.rate(pg_temp.v('SBX')::bigint, 'percent', 15);
select pg_temp.rate(pg_temp.v('GAMMA')::bigint, 'percent', 22);
select pg_temp.rate(pg_temp.v('CAP')::bigint, 'percent', 18);
select pg_temp.offer(pg_temp.v('ALPHA')::bigint, pg_temp.v(k)::bigint) from unnest(array['P_R2', 'P_R4', 'P_R5', 'P_R6', 'P_R7', 'P_R8', 'P_T9', 'P_T6', 'P_AM']) k;
select pg_temp.offer(pg_temp.v('BETA')::bigint, pg_temp.v(k)::bigint) from unnest(array['P_R2', 'P_T9', 'P_ORD']) k;
select pg_temp.offer(pg_temp.v('SBX')::bigint, pg_temp.v('P_R1')::bigint);
select pg_temp.offer(pg_temp.v('CAP')::bigint, pg_temp.v('P_CAP')::bigint);

-- ======================================================================================================================
-- R1: test leads are never routed; the sandbox and the B2C test hand-off are the Admin's test tools
-- ======================================================================================================================
do $x$
declare v_t1 bigint; v_t2 bigint; v_real bigint; x jsonb; a b2b.allocations; e text;
begin
  v_t1 := pg_temp.lead('910000770001', 'ZZRone');
  v_t2 := pg_temp.lead('910000770002', 'ZZRtwo');
  perform pg_temp.set('T1', v_t1::text); perform pg_temp.set('T2', v_t2::text);
  x := pg_temp.decide(v_t1, true);
  insert into r values ('r1_test_lead_nothing_written', x ->> 'destination' = 'none' and x ->> 'reason' = 'test_lead' and x ->> 'outcome' = 'test_lead'
      and not (x ->> 'committed')::boolean and (x ->> 'is_test')::boolean
      and not exists (select 1 from b2b.engine_decisions where lead_id = v_t1) and not exists (select 1 from b2b.allocations where lead_id = v_t1)
      and (select destination_type from public.student_leads where id = v_t1) is null, x ->> 'destination' || ' ' || coalesce(x ->> 'reason', '-'));
  x := pg_temp.decide(v_t1, false, 'pass');
  insert into r values ('r1_test_lead_pass_preview_none', x ->> 'destination' = 'none' and x ->> 'reason' = 'test_lead', x ->> 'reason');
  -- the sandbox: the partner with a test endpoint, an is_test allocation with origin sandbox
  x := b2b.route_test_lead(v_t1, 'partner_sandbox', 'sandbox check of the test lead');
  a := pg_temp.alloc(v_t1);
  insert into r values ('r1_sandbox_routes_to_test_endpoint', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('SBX')::bigint and (x ->> 'committed')::boolean
      and a.is_test and a.origin = 'sandbox' and a.destination_type = 'partner' and a.partner_id = pg_temp.v('SBX')::bigint
      and (select is_test from b2b.engine_decisions where id = a.engine_decision_id) and (select how from b2b.engine_decisions where id = a.engine_decision_id) = 'sandbox',
    coalesce(x ->> 'destination', '-') || ' ' || coalesce(x ->> 'partner_id', '-') || ' origin=' || coalesce(a.origin, '-'));
  -- no partner with a test endpoint offers the course: nothing written, the result says why
  x := b2b.route_test_lead(v_t2, 'partner_sandbox', 'sandbox check without a sandbox partner');
  insert into r values ('r1_no_sandbox_partner', x ->> 'destination' = 'none' and x ->> 'reason' = 'no_sandbox_partner' and not (x ->> 'committed')::boolean
      and not exists (select 1 from b2b.allocations where lead_id = v_t2), coalesce(x ->> 'destination', '-') || ' ' || coalesce(x ->> 'reason', '-'));
  -- the B2C test hand-off
  x := b2b.route_test_lead(v_t2, 'b2c_test', 'b2c test hand-off');
  a := pg_temp.alloc(v_t2);
  insert into r values ('r1_b2c_test_handoff', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'test_handoff' and x ->> 'b2c_lane' = 'sales' and (x ->> 'committed')::boolean
      and x ->> 'outcome' = 'decided' and a.is_test and a.reason = 'test_handoff' and a.origin = 'sandbox' and a.status = 'handed_off'
      and (pg_temp.handoff(v_t2) ->> 'test')::boolean, x::text);
  -- a real lead is refused by the test tools, and the sandbox context is refused by route_decide
  v_real := pg_temp.lead('919876570101', 'ZZRtwo');
  e := pg_temp.err(format('select b2b.route_test_lead(%s, %L, %L)', v_real, 'partner_sandbox', 'not a test lead'));
  insert into r values ('r1_real_lead_refused_by_test_tools', e like '22023%only a test lead%', e);
  e := pg_temp.err(format('select b2b.route_decide(%s, false, null, %L)', v_real, 'sandbox'));
  insert into r values ('r1_sandbox_context_refused_for_real_lead', e like '22023%sandbox is for test leads%', e);
  e := pg_temp.err(format('select b2b.route_decide(%s, false, null, %L)', v_real, 'elsewhere'));
  insert into r values ('r1_unknown_context_refused', e like '22023 unknown routing request%', e);
end $x$;

-- ======================================================================================================================
-- Caps: a test allocation does not consume a cap; with a daily cap of 1 and two decisions only one partner win
-- ======================================================================================================================
do $x$
declare v_t bigint; v_1 bigint; v_2 bigint; x jsonb; y jsonb;
begin
  v_t := pg_temp.lead('910000770003', 'ZZCap');
  x := b2b.route_test_lead(v_t, 'partner_sandbox', 'sandbox check of the cap partner');
  insert into r values ('caps_test_allocation_to_cap_partner', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('CAP')::bigint, x ->> 'destination');
  v_1 := pg_temp.lead('919876570111', 'ZZCap');
  v_2 := pg_temp.lead('919876570112', 'ZZCap');
  x := pg_temp.decide(v_1, true);
  y := pg_temp.decide(v_2, true);
  insert into r values ('caps_test_allocation_not_counted', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('CAP')::bigint, x ->> 'destination' || ' ' || coalesce(x ->> 'reason', '-'));
  insert into r values ('caps_second_lead_no_capacity', y ->> 'destination' = 'in_house' and y ->> 'reason' = 'no_capacity' and y ->> 'cause' = 'caps' and y ->> 'b2c_lane' = 'sales'
      and exists (select 1 from jsonb_array_elements(y -> 'excluded') z where (z ->> 'partner_id')::bigint = pg_temp.v('CAP')::bigint and z ->> 'cause' = 'caps'),
    coalesce(y ->> 'destination', '-') || ' ' || coalesce(y ->> 'reason', '-') || ' cause=' || coalesce(y ->> 'cause', '-'));
end $x$;

-- ======================================================================================================================
-- R2: the permanent partner bar (B2C only, forever; not even by hand; merged and same-phone leads inherit it)
-- ======================================================================================================================
do $x$
declare v_b bigint; v_c bigint; v_d bigint; v_e bigint; a b2b.allocations; h bigint; x jsonb; p jsonb; bar jsonb; e text; v_rule bigint;
begin
  -- a lead that reached B2C through a duplicate cascade (built as the cascade leaves it)
  v_b := pg_temp.lead('919876570201', 'ZZRtwo');
  perform pg_temp.set('RB', v_b::text);
  x := pg_temp.decide(v_b, true);
  a := pg_temp.alloc(v_b);
  insert into r values ('r2_fixture_alpha_first', x ->> 'destination' = 'partner' and a.partner_id = pg_temp.v('ALPHA')::bigint, coalesce(x ->> 'destination', '-'));
  update b2b.allocations set status = 'pushing' where id = a.id;
  update b2b.allocations set status = 'duplicate', outcome = 'duplicate', outcome_at = now(), claim_proof_ok = true, claim_existing_record_id = 'ALPHA-1' where id = a.id;
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, status, mode, attempt_no, reason, b2c_lane, is_test, origin)
  values (v_b, 1, 'zzrtwo|PG|Online', 'in_house', 'handed_off', 'fallback', 2, 'duplicate_cascade', 'sales', false, 'auto') returning id into h;
  update b2b.allocations set reference = 'EDW-' || h where id = h;
  update public.student_leads set destination_type = 'in_house', partner_id = null, allocation_id = h, allocated_at = now(), allocation_reason = 'duplicate_cascade' where id = v_b;
  perform b2b.partner_bar_set(v_b, 'duplicate', h, 'engine');
  bar := b2b.partner_bar(pg_temp.lead_row(v_b));
  insert into r values ('r2_bar_set', bar ->> 'reason' = 'duplicate' and bar ->> 'via' = 'lead' and (b2b.b2c_hold(pg_temp.lead_row(v_b)) ->> 'kind') = 'barred', bar::text);
  -- a new enquiry while B2C holds it: re-enquired, never a partner
  x := pg_temp.decide(v_b, false);
  insert into r values ('r2_held_reenquiry_preview', x ->> 'outcome' = 're-enquired' and x ->> 'destination' = 'in_house' and (x -> 'bar' ->> 'reason') = 'duplicate'
      and not (x ->> 'committed')::boolean, (x ->> 'outcome') || ' ' || coalesce(x ->> 'destination', '-'));
  -- the manual route is refused (direct), the API answers 422 partner_barred
  e := pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_b, 'try the partners again'));
  insert into r values ('r2_manual_route_refused', e like '22023 partner_barred: partner-barred (duplicate) since %', e);
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_b, 'try the partners again');
  insert into r values ('r2_api_422_partner_barred', (x ->> 'status') = '422' and x ->> 'error_code' = 'partner_barred' and not (x ->> 'ok')::boolean, x::text);
  e := pg_temp.err(format('select b2b.route_decide(%s, true, %L, %L)', v_b, 'reroute by hand', 'reroute'));
  insert into r values ('r2_reroute_context_refused', e like '22023%already routed%' or e like '22023 partner_barred:%', e);
  -- destination cleared by hand: the next decision is a partner_barred hand-off (sales, mode rule, neutral adviser)
  update public.student_leads set destination_type = null, allocation_id = null, allocation_reason = null, allocated_at = null where id = v_b;
  update b2b.allocations set status = 'closed', outcome = 'cleared', outcome_at = now() where id = h;
  x := pg_temp.decide(v_b, true);
  a := pg_temp.alloc(v_b);
  p := pg_temp.handoff(v_b);
  insert into r values ('r2_cleared_gives_partner_barred_handoff', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'partner_barred' and x ->> 'b2c_lane' = 'sales' and x ->> 'mode' = 'rule'
      and a.reason = 'partner_barred' and a.b2c_lane = 'sales' and a.status = 'handed_off'
      and p -> 'partner_bar' ->> 'reason' = 'duplicate' and p -> 'handling' ->> 'assignment' = 'round_robin_now' and p -> 'handling' ->> 'first_contact_script' = 'neutral_adviser'
      and (p -> 'hold' ->> 'kind') = 'barred', coalesce(x ->> 'reason', '-') || ' ' || coalesce(p -> 'handling' #>> '{}', '-'));
  -- a fix_partner rule and Pass to CRM cannot move a barred lead to a partner
  v_rule := (b2b.routing_rule_save(jsonb_build_object('name', 'ZZ R2 fix Beta', 'action', 'fix_partner', 'priority', 10,
                                                        'partner_ids', jsonb_build_array(pg_temp.v('BETA')::bigint), 'conditions', '{"course_keys": ["zzrtwo"]}'::jsonb)) ->> 'id')::bigint;
  perform pg_temp.set('RULE_R2', v_rule::text);
  update b2b.allocations set status = 'closed', outcome = 'cleared', outcome_at = now() where id = a.id;
  update public.student_leads set destination_type = null, allocation_id = null, allocation_reason = null, allocated_at = null where id = v_b;
  insert into b2b.not_passed (lead_id, reason, fingerprint) select l.id, 'junk', b2b.np_fingerprint(l) from public.student_leads l where l.id = v_b
  on conflict (lead_id) do update set passed_at = null, override = false, fingerprint = excluded.fingerprint;
  x := b2b.pass_to_crm(array[v_b], 'pass the barred lead');
  a := pg_temp.alloc(v_b);
  insert into r values ('r2_fix_partner_and_pass_still_b2c', (x ->> 'passed')::int = 1 and x -> 'results' -> 0 ->> 'destination' = 'in_house'
      and a.reason = 'partner_barred' and a.destination_type = 'in_house' and a.partner_id is null and a.origin = 'pass'
      and (select count(*) from b2b.allocations where lead_id = v_b and destination_type = 'partner' and status not in ('duplicate')) = 0, x::text);
  update b2b.routing_rules set active = false where id = v_rule;
  -- merging the barred lead into a clean one bars the kept lead
  v_c := pg_temp.lead('919876570202', 'ZZRtwo');
  update public.student_leads set merged_into_id = v_c where id = v_b;
  bar := b2b.partner_bar(pg_temp.lead_row(v_c));
  x := pg_temp.decide(v_c, false);
  insert into r values ('r2_merge_bars_kept_lead', bar ->> 'reason' = 'duplicate' and bar ->> 'via' = 'merged' and (bar ->> 'lead_id')::bigint = v_b
      and x ->> 'destination' = 'in_house' and x ->> 'reason' = 'partner_barred', coalesce(bar::text, 'no bar'));
  update public.student_leads set merged_into_id = null where id = v_b;
  -- a new lead with the same phone digits after a soft delete is barred too
  v_d := pg_temp.lead('919876570203', 'ZZRtwo');
  perform b2b.partner_bar_set(v_d, 'lost', null, 'backfill');
  update public.student_leads set deleted_at = now() where id = v_d;
  v_e := pg_temp.lead('919876570203', 'ZZRtwo');
  bar := b2b.partner_bar(pg_temp.lead_row(v_e));
  x := pg_temp.decide(v_e, false);
  insert into r values ('r2_same_phone_after_soft_delete_barred', v_e <> v_d and bar ->> 'reason' = 'lost' and bar ->> 'via' = 'phone'
      and x ->> 'destination' = 'in_house' and x ->> 'reason' = 'partner_barred', coalesce(bar::text, 'no bar') || ' new=' || v_e || ' old=' || v_d);
end $x$;

-- ======================================================================================================================
-- R4 and R6: a B2C-created lead is decided at intake and stays with B2C; a Google form is "re-enquired"; a new cycle stays held
-- ======================================================================================================================
do $x$
declare v_s bigint; v_o bigint; x jsonb; rd jsonb; a b2b.allocations; tk jsonb; q b2b.lead_reenquiries; ev b2b.events; v_tp bigint; v_reason text;
begin
  v_s := pg_temp.lead('919876570401', 'ZZRfour', '{"source": "b2c_whatsapp", "channel": "whatsapp"}', 'api');
  rd := b2b.lead_readiness(pg_temp.lead_row(v_s));
  insert into r values ('r6_b2c_whatsapp_decided_at_intake', (rd ->> 'ready')::boolean and rd ->> 'gate' = 'intake' and not b2b.is_chat_lead(pg_temp.lead_row(v_s)), rd::text);
  x := pg_temp.decide(v_s, true);
  a := pg_temp.alloc(v_s);
  insert into r values ('r6_b2c_created_sales', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_created' and x ->> 'b2c_lane' = 'sales' and x ->> 'mode' = 'rule'
      and a.reason = 'b2c_created' and a.b2c_lane = 'sales' and (b2b.b2c_hold(pg_temp.lead_row(v_s)) ->> 'kind') = 'selling', x ->> 'reason');
  -- an off-catalogue B2C-created lead is still b2c_created (R6 before R5)
  v_o := pg_temp.lead('919876570402', 'Commercial Pilot Licence', '{"source": "b2c_created"}', 'api');
  x := pg_temp.decide(v_o, true);
  insert into r values ('r6_off_catalogue_b2c_created', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_created' and (x -> 'class' ->> 'class') = 'mismatch', coalesce(x ->> 'reason', '-'));
  -- R4: a Google form for the selling-held lead is one b2c.lead_reenquired, the hold is unchanged
  v_reason := (select allocation_reason from public.student_leads where id = v_s);
  perform pg_temp.age_touchpoints(v_s, now() - interval '10 minutes');
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, created_at)
  values (v_s, '919876570401', 'google', 'lead.updated', 'google_lead_form', now() - interval '3 minutes') returning id into v_tp;
  tk := b2b.reenquiry_tick(1000);
  select * into q from b2b.lead_reenquiries where touchpoint_id = v_tp;
  select * into ev from b2b.events where id = q.event_id;
  insert into r values ('r4_selling_hold_reenquired_once', (tk ->> 'errors')::int = 0 and q.holder = 'b2c_selling' and ev.type = 'b2c.lead_reenquired'
      and ev.payload ->> 'reason' = 'b2c_created' and ev.payload -> 'hold' ->> 'kind' = 'selling' and (ev.payload ->> 'contract_version')::int = 3
      and (select count(*) from b2b.events e where e.type = 'b2c.lead_reenquired' and e.lead_id = v_s) = 1
      and (select allocation_reason from public.student_leads where id = v_s) = v_reason
      and (select allocation_id from public.student_leads where id = v_s) = a.id, tk::text || ' ' || coalesce(ev.payload::text, 'no event'));
  x := pg_temp.decide(v_s, false);
  insert into r values ('r4_held_preview_reenquired', x ->> 'outcome' = 're-enquired' and x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_created', x ->> 'outcome');
  -- a new enquiry cycle: the lead stays held by B2C (b2c_held), it reaches a partner only by hand
  update b2b.allocations set status = 'closed', outcome = 'cycle_ended', outcome_at = now() where id = a.id;
  update public.student_leads set destination_type = null, allocation_id = null, allocation_reason = null, allocated_at = null,
         cycle_no = coalesce(cycle_no, 1) + 1, reopened_at = now(), lead_source = 'website' where id = v_s;
  x := pg_temp.decide(v_s, true);
  a := pg_temp.alloc(v_s);
  insert into r values ('r4_new_cycle_stays_held', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_held' and x ->> 'b2c_lane' = 'sales' and x ->> 'mode' = 'rule'
      and a.reason = 'b2c_held' and a.cycle_no = 2 and (x -> 'hold' ->> 'kind') = 'selling', coalesce(x ->> 'reason', '-'));
  -- held by B2C: the manual route is the only way to a partner, and it works for a lead that is not barred
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_s, 'the counsellor asked for a partner');
  insert into r values ('r4_manual_route_allowed', (x ->> 'status') = '200' and x -> 'result' ->> 'destination' = 'partner'
      and (select origin from b2b.allocations a2 join public.student_leads l on l.allocation_id = a2.id where l.id = v_s) = 'to_partners'
      and b2b.partner_bar(pg_temp.lead_row(v_s)) is null, x::text);
end $x$;

-- ======================================================================================================================
-- R5: junk, spam and programme mismatch are recorded as Not passed; Pass to CRM overrides the label
-- ======================================================================================================================
do $x$
declare v_sp bigint; v_bl bigint; v_hot bigint; v_off bigint; v_mm bigint; x jsonb; np b2b.not_passed; i int; v_id bigint; a b2b.allocations; d b2b.engine_decisions;
begin
  -- disposable email
  v_sp := pg_temp.lead('919876570501', 'ZZRfive', '{"email": "someone@mailinator.com"}');
  x := pg_temp.decide(v_sp, true);
  select * into np from b2b.not_passed where lead_id = v_sp;
  insert into r values ('r5_disposable_email_spam', x ->> 'destination' = 'not_passed' and x ->> 'reason' = 'junk' and (x -> 'class' ->> 'detail') = 'spam:disposable_email'
      and np.reason = 'junk' and np.detail = 'spam:disposable_email' and np.passed_at is null and not np.override
      and not exists (select 1 from b2b.engine_decisions where lead_id = v_sp) and (select destination_type from public.student_leads where id = v_sp) is null
      and exists (select 1 from b2b.events e where e.type = 'lead.not_passed' and e.lead_id = v_sp and e.payload ->> 'detail' = 'spam:disposable_email'),
    coalesce(x ->> 'destination', '-') || ' ' || coalesce(np.detail, '-'));
  -- six leads from one IP inside an hour: the sixth is spam, and the verdict does not change 18 hours later
  for i in 1..6 loop
    v_id := pg_temp.lead('91987657051' || i, 'ZZRfive', '{"ip_address": "10.31.5.9"}');
    update public.student_leads set created_at = now() - make_interval(mins => 60 - i * 5) where id = v_id;
    perform pg_temp.set('IP' || i, v_id::text);
  end loop;
  x := pg_temp.decide(pg_temp.v('IP6')::bigint, true);
  insert into r values ('r5_ip_burst_sixth_not_passed', x ->> 'destination' = 'not_passed' and x ->> 'reason' = 'junk'
      and (select detail from b2b.not_passed where lead_id = pg_temp.v('IP6')::bigint) = 'spam:ip_burst'
      and b2b.spam_check(pg_temp.lead_row(pg_temp.v('IP5')::bigint)) is null, coalesce(x ->> 'reason', '-'));
  update public.student_leads set created_at = created_at - interval '18 hours' where id in (select v::bigint from t where k like 'IP_');
  insert into r values ('r5_ip_burst_same_18h_later', b2b.lead_class(pg_temp.lead_row(pg_temp.v('IP6')::bigint)) ->> 'detail' = 'spam:ip_burst'
      and b2b.lead_class(pg_temp.lead_row(pg_temp.v('IP5')::bigint)) ->> 'class' = 'qualified', b2b.lead_class(pg_temp.lead_row(pg_temp.v('IP6')::bigint))::text);
  -- a phone Witty blocked
  v_bl := pg_temp.lead('919876570521', 'ZZRfive');
  insert into public.w2_blocks (phone, reason) values ('919876570521', 'abuse');
  x := pg_temp.decide(v_bl, true);
  insert into r values ('r5_witty_block_spam', x ->> 'destination' = 'not_passed' and (x -> 'class' ->> 'detail') = 'spam:witty_block'
      and (select detail from b2b.not_passed where lead_id = v_bl) = 'spam:witty_block'
      and pg_temp.err(format('select b2b.lead_class(l) from public.student_leads l where l.id = %s', v_bl)) = 'no error', coalesce(x -> 'class' ->> 'detail', '-'));
  -- a HOT chat lead with an off-catalogue primary and an in-catalogue secondary interest is not a mismatch (critic B5)
  v_hot := pg_temp.lead('919876570531', 'Commercial Pilot Licence', '{"classification": "HOT", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  insert into b2b.lead_interests (lead_id, position, course_text, source) values (v_hot, 2, 'ZZRfive', 'witty');
  update public.student_leads set lead_stage = 'ESCALATION', is_bot_paused = true where id = v_hot;
  x := pg_temp.decide(v_hot, true);
  insert into r values ('r5_secondary_in_catalogue_not_mismatch', (x -> 'class' ->> 'class') = 'qualified' and x ->> 'destination' = 'partner' and (x ->> 'interest_rank')::int = 2
      and (x ->> 'partner_id')::bigint = pg_temp.v('ALPHA')::bigint, coalesce(x ->> 'destination', '-') || ' rank=' || coalesce(x ->> 'interest_rank', '-'));
  -- off-catalogue only
  v_off := pg_temp.lead('919876570541', 'Commercial Pilot Licence');
  x := pg_temp.decide(v_off, true);
  insert into r values ('r5_off_catalogue_mismatch', x ->> 'destination' = 'not_passed' and x ->> 'reason' = 'program_mismatch'
      and (select detail from b2b.not_passed where lead_id = v_off) = 'course_not_in_catalogue', coalesce(x ->> 'reason', '-'));
  -- a PROGRAM_MISMATCH label on a catalogue course: Not passed, then Pass to CRM sends it to a partner (origin pass, the note kept: C124)
  v_mm := pg_temp.lead('919876570551', 'ZZRfive', '{"classification": "PROGRAM_MISMATCH"}');
  x := pg_temp.decide(v_mm, true);
  insert into r values ('r5_label_mismatch_not_passed', x ->> 'destination' = 'not_passed' and x ->> 'reason' = 'program_mismatch' and (x -> 'class' ->> 'basis') = 'label', coalesce(x ->> 'reason', '-'));
  x := b2b.pass_to_crm(array[v_mm], 'm31 pass note');
  a := pg_temp.alloc(v_mm);
  d := pg_temp.decision(a.id);
  insert into r values ('r5_pass_to_crm_reaches_partner', (x ->> 'passed')::int = 1 and x -> 'results' -> 0 ->> 'destination' = 'partner'
      and a.destination_type = 'partner' and a.partner_id = pg_temp.v('ALPHA')::bigint and a.origin = 'pass' and a.override
      and (select override and passed_at is not null from b2b.not_passed where lead_id = v_mm), x::text);
  insert into r values ('c124_pass_note_stored', d.reason = 'm31 pass note' and d.how = 'pass', coalesce(d.reason, 'null'));
end $x$;

-- ======================================================================================================================
-- R7: not qualified → B2C qualification nurture; the missing codes per source; a B2C edit completes the lead
-- ======================================================================================================================
do $x$
declare v_w bigint; v_f bigint; v_wa bigint; v_u bigint; x jsonb; p jsonb; a b2b.allocations; d b2b.engine_decisions; res jsonb; c jsonb;
begin
  v_w := pg_temp.lead('919876570701', 'ZZRseven', '{"email": null, "classification": "UNQUALIFIED", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  v_f := pg_temp.lead('919876570702', null, '{"classification": null, "source": "website_form"}', 'api');
  v_wa := pg_temp.lead('919876570703', 'ZZRseven', '{"classification": null, "source": "website"}', 'web_agent');
  v_u := pg_temp.lead('919876570704', 'ZZRseven', '{"classification": "UNQUALIFIED", "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  insert into r values ('r7_missing_codes_per_source',
      b2b.lead_class(pg_temp.lead_row(v_w)) -> 'missing' = '["no_email"]' and b2b.lead_class(pg_temp.lead_row(v_f)) -> 'missing' = '["no_course"]'
      and b2b.lead_class(pg_temp.lead_row(v_wa)) -> 'missing' = '["phone_not_verified"]' and b2b.lead_class(pg_temp.lead_row(v_u)) -> 'missing' = '["witty_unconfirmed"]',
    (b2b.lead_class(pg_temp.lead_row(v_w)) -> 'missing')::text || ' ' || (b2b.lead_class(pg_temp.lead_row(v_f)) -> 'missing')::text || ' '
      || (b2b.lead_class(pg_temp.lead_row(v_wa)) -> 'missing')::text || ' ' || (b2b.lead_class(pg_temp.lead_row(v_u)) -> 'missing')::text);
  -- the form lead without a course: nurture, with the welcome only for Witty leads
  x := pg_temp.decide(v_f, true);
  a := pg_temp.alloc(v_f);
  d := pg_temp.decision(a.id);
  p := pg_temp.handoff(v_f);
  insert into r values ('r7_form_no_course_nurture', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'not_qualified' and x ->> 'b2c_lane' = 'nurture' and x ->> 'mode' = 'fallback'
      and a.reason = 'not_qualified' and a.b2c_lane = 'nurture' and p -> 'missing' = '["no_course"]' and p -> 'b2c_actions' = '[]'
      and p -> 'handling' ->> 'job' = 'qualify' and (b2b.b2c_hold(pg_temp.lead_row(v_f)) ->> 'kind') = 'qualification_nurture', coalesce(x ->> 'reason', '-') || ' ' || coalesce(p -> 'missing' #>> '{}', '-'));
  insert into r values ('c124_not_qualified_reason_exact', d.reason = 'not_qualified' and d.b2c_lane = 'nurture', coalesce(d.reason, 'null'));
  -- the Witty UNQUALIFIED lead with name, email and course: nurture with the welcome; a B2C edit of the programme level qualifies it
  update public.student_leads set program_level = null where id = v_u;
  x := pg_temp.decide(v_u, true);
  a := pg_temp.alloc(v_u);
  p := pg_temp.handoff(v_u);
  insert into r values ('r7_witty_unconfirmed_nurture_with_welcome', x ->> 'reason' = 'not_qualified' and p -> 'missing' = '["witty_unconfirmed"]'
      and p -> 'b2c_actions' = '["welcome_explore_programmes"]' and p -> 'welcome' ->> 'template_hint' = 'explore_programmes', coalesce(p -> 'b2c_actions' #>> '{}', '-'));
  res := b2b.requalify_lead(v_u, 'still unconfirmed');
  insert into r values ('r7_unconfirmed_not_requalified', not (res ->> 'requalified')::boolean and res ->> 'why' like 'not qualified:%witty_unconfirmed%', res ->> 'why');
  update public.student_leads set program_level = 'PG' where id = v_u;
  insert into b2b.events (type, lead_id, allocation_id, actor_type, payload, occurred_at)
  values ('b2c.lead_updated', v_u, a.id, 'api', '{"changes":{"programme_level":{"from":null,"to":"PG"}}}', now() + interval '1 second');
  c := b2b.lead_class(pg_temp.lead_row(v_u));
  res := b2b.requalify_lead(v_u, 'completed by the B2C counsellor');
  insert into r values ('r7_b2c_edit_qualifies_on_requalify', c ->> 'class' = 'qualified' and c ->> 'basis' = 'completed_by_b2c' and (res ->> 'requalified')::boolean
      and res ->> 'destination' = 'partner' and (res ->> 'closed_allocation_id')::bigint = a.id
      and (select outcome from b2b.allocations where id = a.id) = 'requalified'
      and (select origin from b2b.allocations where id = (res ->> 'allocation_id')::bigint) = 'requalify', coalesce(c ->> 'basis', '-') || ' ' || coalesce(res ->> 'destination', '-'));
end $x$;

-- ======================================================================================================================
-- R8 and rulebook test 2 (routing parts): no consent → ask; YES → partner; NO → B2C sales; no answer → nurture; later YES → partner
-- ======================================================================================================================
do $x$
declare v_a bigint; v_b bigint; v_c bigint; v_d bigint; x jsonb; ans jsonb; q b2b.consent_requests; a b2b.allocations; tk jsonb; w b2b.lead_waits;
begin
  v_a := pg_temp.lead('919876570801', 'ZZReight', '{"consent_partner_share_at": null, "consent_text_version": null}');
  v_b := pg_temp.lead('919876570802', 'ZZReight', '{"consent_partner_share_at": null, "consent_text_version": null}');
  v_c := pg_temp.lead('919876570803', 'ZZReight', '{"consent_partner_share_at": null, "consent_text_version": null}');
  v_d := pg_temp.lead('919876570804', 'ZZReight', '{"consent_partner_share_at": null, "consent_text_version": null}');
  -- a preview only says that a request would be sent
  x := pg_temp.decide(v_d, false);
  insert into r values ('r8_preview_consent_request', x ->> 'destination' = 'consent_request' and x ->> 'outcome' = 'consent_request' and not (x ->> 'committed')::boolean
      and not exists (select 1 from b2b.consent_requests where lead_id = v_d), x ->> 'destination');
  -- the decision asks for consent: no decision row, no allocation, a 48-hour wait
  x := pg_temp.decide(v_a, true);
  select * into q from b2b.consent_requests where lead_id = v_a;
  select * into w from b2b.lead_waits where lead_id = v_a;
  insert into r values ('r8_commit_asks_for_consent', x ->> 'destination' = 'consent_requested' and x ->> 'outcome' = 'consent_requested' and (x ->> 'committed')::boolean
      and (x -> 'consent_request' ->> 'created')::boolean and (x -> 'consent_request' ->> 'request_id')::bigint = q.id and (x ->> 'allocation_id') is null and (x ->> 'decision_id') is null
      and q.context = 'decision' and q.status = 'requested' and q.channel = 'b2c_crm' and q.programme like 'ZZReight%' and q.expires_at between now() + interval '47 hours' and now() + interval '49 hours'
      and not exists (select 1 from b2b.engine_decisions where lead_id = v_a) and not exists (select 1 from b2b.allocations where lead_id = v_a)
      and (select destination_type from public.student_leads where id = v_a) is null
      and w.why = 'awaiting partner-sharing consent' and w.decide_after = q.expires_at
      and exists (select 1 from b2b.events e where e.type = 'b2c.consent_requested' and e.lead_id = v_a and e.payload ->> 'text' like '%ZZReight%'), x::text);
  x := pg_temp.decide(v_a, true);
  insert into r values ('r8_open_request_pending', x ->> 'destination' = 'consent_pending' and x ->> 'outcome' = 'consent_pending' and not (x ->> 'committed')::boolean
      and (select count(*) from b2b.consent_requests where lead_id = v_a) = 1, x ->> 'destination');
  -- YES → R9 → partner
  perform set_config('b2b.actor', 'b2c_crm', true);
  ans := b2b.consent_answer(v_a, null, 'yes', 'b2c_crm', jsonb_build_object('message_id', 'm31r-yes-a'));
  a := pg_temp.alloc(v_a);
  insert into r values ('t2_yes_to_partner', (ans ->> 'recorded')::boolean and ans ->> 'effect' = 'routed' and ans -> 'route' ->> 'destination' = 'partner' and ans ->> 'state' = 'given'
      and a.destination_type = 'partner' and a.partner_id = pg_temp.v('ALPHA')::bigint and a.origin = 'auto'
      and (select consent_partner_share_at is not null and consent_text_version = 'wa_partner_consent:v1' from public.student_leads where id = v_a)
      and (b2b.partner_consent(pg_temp.lead_row(v_a)) ->> 'given')::boolean, ans::text);
  -- NO → B2C sales, reason no_partner_consent
  x := pg_temp.decide(v_b, true);
  ans := b2b.consent_answer(v_b, null, 'no', 'b2c_crm', jsonb_build_object('message_id', 'm31r-no-b'));
  a := pg_temp.alloc(v_b);
  insert into r values ('t2_no_to_b2c_sales', ans ->> 'effect' = 'routed' and ans -> 'route' ->> 'destination' = 'in_house' and ans -> 'route' ->> 'reason' = 'no_partner_consent'
      and ans -> 'route' ->> 'b2c_lane' = 'sales' and ans ->> 'state' = 'refused' and a.reason = 'no_partner_consent' and a.b2c_lane = 'sales' and a.mode = 'fallback'
      and (b2b.b2c_hold(pg_temp.lead_row(v_b)) ->> 'kind') = 'selling', ans::text);
  -- a refused lead cannot be routed by hand either
  insert into r values ('r8_refused_manual_route_no_consent', pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_b, 'try partners anyway')) like '22023 no_consent:%',
    pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_b, 'try partners anyway')));
  -- no answer in 48 hours → nurture consent_no_answer; a later YES requalifies to a partner
  perform set_config('b2b.actor', 'engine', true);
  x := pg_temp.decide(v_c, true);
  update b2b.consent_requests set expires_at = now() - interval '1 hour' where lead_id = v_c;
  tk := b2b.consent_tick();
  select * into q from b2b.consent_requests where lead_id = v_c;
  insert into r values ('t2_request_expired', (tk ->> 'expired')::int >= 1 and q.status = 'expired' and q.closed_at is not null
      and (select decide_after <= now() from b2b.lead_waits where lead_id = v_c), tk::text || ' ' || q.status);
  x := pg_temp.decide(v_c, true);
  a := pg_temp.alloc(v_c);
  insert into r values ('t2_no_answer_to_nurture', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'consent_no_answer' and x ->> 'b2c_lane' = 'nurture' and x ->> 'mode' = 'fallback'
      and a.reason = 'consent_no_answer' and a.b2c_lane = 'nurture' and (b2b.b2c_hold(pg_temp.lead_row(v_c)) ->> 'kind') = 'qualification_nurture'
      and pg_temp.handoff(v_c) -> 'missing' = '["partner_consent"]', coalesce(x ->> 'reason', '-'));
  perform set_config('b2b.actor', 'b2c_crm', true);
  ans := b2b.consent_answer(v_c, null, 'yes', 'b2c_crm', jsonb_build_object('message_id', 'm31r-yes-c'));
  insert into r values ('t2_later_yes_to_partner', ans ->> 'effect' = 'requalified' and ans -> 'route' ->> 'destination' = 'partner' and (ans -> 'route' ->> 'requalified')::boolean
      and (select destination_type from public.student_leads where id = v_c) = 'partner'
      and (select outcome from b2b.allocations where id = a.id) = 'requalified'
      and (select origin from b2b.allocations a2 join public.student_leads l on l.allocation_id = a2.id where l.id = v_c) = 'requalify', ans::text);
  perform set_config('b2b.actor', 'engine', true);
end $x$;

-- ======================================================================================================================
-- Rule order: fix_partner at 10 beats to_b2c at 50; to_b2c never fires before the consent request (R8 precedes R9)
-- ======================================================================================================================
do $x$
declare v_nc bigint; v_ok bigint; x jsonb; r_fix bigint; r_b2c bigint; r_b2c_hi bigint;
begin
  r_b2c := (b2b.routing_rule_save(jsonb_build_object('name', 'ZZ order to B2C', 'action', 'to_b2c', 'priority', 50, 'b2c_lane', 'sales', 'conditions', '{"course_keys": ["zzorder"]}'::jsonb)) ->> 'id')::bigint;
  v_nc := pg_temp.lead('919876570901', 'ZZOrder', '{"consent_partner_share_at": null, "consent_text_version": null}');
  x := pg_temp.decide(v_nc, true);
  insert into r values ('order_to_b2c_waits_for_consent', x ->> 'destination' = 'consent_requested' and (x ->> 'committed')::boolean and jsonb_array_length(coalesce(x -> 'rules', '[]')) = 0, x ->> 'destination');
  v_ok := pg_temp.lead('919876570902', 'ZZOrder');
  x := pg_temp.decide(v_ok, false);
  insert into r values ('order_to_b2c_alone_fires', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'rule' and x ->> 'mode' = 'rule' and x ->> 'b2c_lane' = 'sales'
      and exists (select 1 from jsonb_array_elements(x -> 'rules') z where (z ->> 'id')::bigint = r_b2c and z ->> 'effect' like 'sent to B2C%'), coalesce(x ->> 'reason', '-'));
  r_fix := (b2b.routing_rule_save(jsonb_build_object('name', 'ZZ order fix Beta', 'action', 'fix_partner', 'priority', 10,
                                                      'partner_ids', jsonb_build_array(pg_temp.v('BETA')::bigint), 'conditions', '{"course_keys": ["zzorder"]}'::jsonb)) ->> 'id')::bigint;
  x := pg_temp.decide(v_ok, true);
  insert into r values ('order_fix_partner_beats_to_b2c', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('BETA')::bigint and x ->> 'mode' = 'rule'
      and exists (select 1 from jsonb_array_elements(x -> 'rules') z where (z ->> 'id')::bigint = r_fix and z ->> 'effect' like '% kept')
      and not exists (select 1 from jsonb_array_elements(x -> 'rules') z where (z ->> 'id')::bigint = r_b2c), coalesce(x ->> 'destination', '-') || ' ' || coalesce(x -> 'rules' #>> '{}', '-'));
  update b2b.routing_rules set active = false where id in (r_fix, r_b2c);
end $x$;

-- ======================================================================================================================
-- R9 and rulebook test 6: a Meta Lead Ads lead and a Google lead-form lead with covering consent are routed to partners
-- ======================================================================================================================
insert into b2b.lead_forms (platform, form_ref, name, field_map, defaults, consent_version, consent_purposes)
values ('meta', 'ZZF1', 'ZZ Meta form', '{"preferred_course": "course"}', '{"programme_level": "PG", "study_mode": "online"}', 'test-partner-share:v1', '{sales,partner_share}'),
       ('google', 'ZZG1', 'ZZ Google form', '{"which_course": "course"}', '{"programme_level": "PG", "study_mode": "online"}', 'test-partner-share:v1', '{sales,partner_share}');
do $x$
declare v_req bigint; x jsonb; v_m bigint; v_g bigint; a b2b.allocations; d b2b.engine_decisions;
begin
  -- Meta: the stored webhook request, then the fetched lead
  insert into b2b.intake_requests (source, idempotency_key, form_ref, raw, status)
  values ('meta', 'ZZ-L-1', 'ZZF1', '{"leadgen_id": "ZZ-L-1", "form_id": "ZZF1", "page_id": "ZZP1", "ad_id": "ZZAD1", "adgroup_id": "ZZAS1"}', 'received') returning id into v_req;
  perform set_config('b2b.actor', 'engine', true);
  x := b2b.meta_lead_apply(v_req, '{"id":"ZZ-L-1","created_time":"2026-10-07T09:00:00+0000","form_id":"ZZF1","campaign_name":"ZZ Oct Paid","platform":"fb",
                                    "field_data":[{"name":"full_name","values":["Meta Student"]},{"name":"phone_number","values":["+919876570601"]},
                                                  {"name":"email","values":["meta-student@test.local"]},{"name":"preferred_course","values":["ZZPaid"]}]}');
  v_m := (x ->> 'lead_id')::bigint;
  perform pg_temp.set('META', v_m::text);
  insert into r values ('t6_meta_lead_written', x ->> 'action' = 'created' and (select status from b2b.intake_requests where id = v_req) = 'done'
      and (select lead_source = 'meta_lead_ad' and interested_course = 'ZZPaid' and consent_partner_share_at is not null and consent_text_version = 'test-partner-share:v1'
             from public.student_leads where id = v_m)
      and (b2b.lead_attribution(pg_temp.lead_row(v_m)) ->> 'paid')::boolean and b2b.lead_attribution(pg_temp.lead_row(v_m)) ->> 'platform' = 'meta'
      and b2b.lead_class(pg_temp.lead_row(v_m)) ->> 'class' = 'qualified', x::text || ' ' || b2b.lead_attribution(pg_temp.lead_row(v_m))::text);
  x := pg_temp.decide(v_m, true);
  a := pg_temp.alloc(v_m);
  insert into r values ('t6_meta_lead_to_partner', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('ALPHA')::bigint and x ->> 'paid' = 'Meta Lead Ads'
      and (x -> 'attribution' ->> 'paid')::boolean and x -> 'attribution' ->> 'platform' = 'meta'
      and a.destination_type = 'partner' and a.paid and a.paid_platform = 'meta' and a.origin = 'auto' and a.stage = 'A', coalesce(x ->> 'destination', '-') || ' paid=' || coalesce(x ->> 'paid', '-'));
  -- Google
  x := b2b.google_leadform_ingest('{"google_key":"gkey-zz-12345678","lead_id":"zz-g-1","form_id":"ZZG1","gcl_id":"ZZGCL1","campaign_id":"771",
    "user_column_data":[{"column_id":"FULL_NAME","string_value":"Google Student"},{"column_id":"PHONE_NUMBER","string_value":"+91 98765 70602"},
                        {"column_id":"EMAIL","string_value":"google-student@test.local"},{"column_id":"which_course","column_name":"Which course?","string_value":"ZZPaid"}]}');
  select l.id into v_g from public.student_leads l where l.whatsapp_number = '919876570602';
  perform pg_temp.set('GOOGLE', v_g::text);
  insert into r values ('t6_google_lead_written', (x ->> 'ok')::boolean and v_g is not null
      and (select lead_source = 'google_lead_form' and interested_course = 'ZZPaid' and consent_partner_share_at is not null and click_ids ->> 'gclid' = 'ZZGCL1'
             from public.student_leads where id = v_g)
      and (b2b.lead_attribution(pg_temp.lead_row(v_g)) ->> 'paid')::boolean and b2b.lead_attribution(pg_temp.lead_row(v_g)) ->> 'platform' = 'google', x::text);
  x := pg_temp.decide(v_g, true);
  a := pg_temp.alloc(v_g);
  insert into r values ('t6_google_lead_to_partner', x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = pg_temp.v('ALPHA')::bigint and x ->> 'paid' = 'Google lead form'
      and x -> 'attribution' ->> 'platform' = 'google' and a.paid and a.paid_platform = 'google' and a.destination_type = 'partner', coalesce(x ->> 'destination', '-') || ' paid=' || coalesce(x ->> 'paid', '-'));
  d := pg_temp.decision(a.id);
  insert into r values ('t6_decision_stores_attribution', (d.attribution ->> 'paid')::boolean and d.attribution ->> 'platform' = 'google' and d.class = 'qualified' and d.stage = 'A' and d.how = 'auto', d.attribution::text);
end $x$;

-- ======================================================================================================================
-- R3 and rulebook test 8: a paid lead with an open partner allocation stays with the partner; new forms are recorded only
-- ======================================================================================================================
do $x$
declare v_m bigint := pg_temp.v('META')::bigint; a b2b.allocations; x jsonb; tk jsonb; q b2b.lead_reenquiries; ev b2b.events; v_tp bigint; v_tp2 bigint; v_tp3 bigint; lost jsonb;
begin
  a := pg_temp.alloc(v_m);
  perform pg_temp.pushed(a.id);
  perform pg_temp.accept(a.id);
  insert into r values ('t8_fixture_accepted', (select status from b2b.allocations where id = a.id) = 'accepted' and public.w2_crm_owned('919876570601'), (select status from b2b.allocations where id = a.id));
  x := pg_temp.decide(v_m, false);
  insert into r values ('r3_with_partner_preview', x ->> 'outcome' = 'with_partner' and x ->> 'destination' = 'partner' and (x ->> 'partner_id')::bigint = a.partner_id
      and (x ->> 'already_routed')::boolean and not (x ->> 'committed')::boolean, x ->> 'outcome');
  insert into r values ('r3_commit_refused_already_routed', pg_temp.err(format('select b2b.route_decide(%s, true, null, %L)', v_m, 'auto')) like '22023%already routed%',
    pg_temp.err(format('select b2b.route_decide(%s, true, null, %L)', v_m, 'auto')));
  -- a new Meta form for the same phone, and a Witty lead.qualified during the hold window (critic B28)
  perform pg_temp.age_touchpoints(v_m, now() - interval '10 minutes');
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, campaign, created_at)
  values (v_m, '919876570601', 'meta', 'lead.updated', 'meta_lead_ads', 'ZZ Oct Paid', now() - interval '3 minutes') returning id into v_tp;
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, created_at)
  values (v_m, '919876570601', 'witty', 'lead.qualified', 'whatsapp_direct', now() - interval '3 minutes') returning id into v_tp2;
  tk := b2b.reenquiry_tick(1000);
  select * into q from b2b.lead_reenquiries where touchpoint_id = v_tp;
  select * into ev from b2b.events where id = q.event_id;
  insert into r values ('t8_paid_form_recorded_stays_with_partner', (tk ->> 'errors')::int = 0 and q.holder = 'partner' and q.partner_id = a.partner_id and q.paid_label = 'Meta Lead Ads'
      and q.campaign = 'ZZ Oct Paid' and ev.type = 'lead.reenquired' and ev.payload ->> 'holder' = 'partner' and not (ev.payload ->> 'lost_in_grace')::boolean
      and (select count(*) from b2b.lead_reenquiries where lead_id = v_m) = 1
      and not exists (select 1 from b2b.events e where e.type like 'b2c.lead_reen%' and e.lead_id = v_m)
      and (select status from b2b.allocations where id = a.id) = 'accepted'
      and (select allocation_id = a.id and destination_type = 'partner' from public.student_leads where id = v_m), tk::text || ' ' || coalesce(ev.payload::text, 'no event'));
  insert into r values ('t8_witty_qualified_not_a_reenquiry', not exists (select 1 from b2b.lead_reenquiries where touchpoint_id = v_tp2), null);
  -- the same while lost in grace
  perform set_config('b2b.actor', 'partner', true);
  lost := b2b.apply_partner_lost(a.id, '{"lost_reason": "not reachable"}');
  insert into r values ('t8_lost_in_grace', lost ->> 'status' = 'grace' and (lost ->> 'grace_until')::timestamptz > now() + interval '6 days'
      and (select status from b2b.allocations where id = a.id) = 'accepted' and public.w2_crm_owned('919876570601'), lost::text);
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, created_at)
  values (v_m, '919876570601', 'meta', 'lead.updated', 'meta_lead_ads', now() - interval '150 seconds') returning id into v_tp3;
  perform set_config('b2b.actor', 'engine', true);
  tk := b2b.reenquiry_tick(1000);
  select * into q from b2b.lead_reenquiries where touchpoint_id = v_tp3;
  select * into ev from b2b.events where id = q.event_id;
  x := pg_temp.decide(v_m, false);
  insert into r values ('t8_lost_in_grace_stays_with_partner', q.holder = 'partner' and ev.type = 'lead.reenquired' and (ev.payload ->> 'lost_in_grace')::boolean
      and (select status from b2b.allocations where id = a.id) = 'accepted' and x ->> 'outcome' = 'with_partner'
      and not exists (select 1 from b2b.events e where e.type like 'b2c.%' and e.lead_id = v_m and e.type <> 'b2c.lead_handed_off'), coalesce(ev.payload::text, 'no event'));
end $x$;

-- ======================================================================================================================
-- Rulebook test 9: a duplicate-cascade lead and a lost-after-grace lead are barred; a Meta form months later is "re-enquired"
-- ======================================================================================================================
do $x$
declare v_dup bigint; v_lost bigint; a1 b2b.allocations; a2 b2b.allocations; h b2b.allocations; s text; x jsonb; lost jsonb; n int; tk jsonb; tp1 bigint; tp2 bigint; ev1 b2b.events; ev2 b2b.events; e text;
begin
  -- the duplicate cascade: Alpha then Beta claim proven duplicates
  v_dup := pg_temp.lead('919876570911', 'ZZNine');
  perform pg_temp.decide(v_dup, true);
  a1 := pg_temp.alloc(v_dup);
  perform pg_temp.pushing(a1.id);
  s := b2b.apply_duplicate(a1.id, '{"existing_record_id": "ALPHA-9", "created_at": "2026-09-01T10:00:00+05:30"}');
  a2 := pg_temp.alloc(v_dup);
  insert into r values ('t9_first_duplicate_next_partner', s = 'duplicate: re-routed' and a1.partner_id = pg_temp.v('ALPHA')::bigint and a2.destination_type = 'partner'
      and a2.partner_id = pg_temp.v('BETA')::bigint and a2.attempt_no = 2, s || ' ' || coalesce(a2.partner_id::text, '-'));
  perform pg_temp.pushing(a2.id);
  s := b2b.apply_duplicate(a2.id, '{"existing_record_id": "BETA-9", "created_at": "2026-08-01T10:00:00+05:30"}');
  h := pg_temp.alloc(v_dup);
  insert into r values ('t9_second_duplicate_cascade_barred', s = 'duplicate: re-routed' and h.destination_type = 'in_house' and h.reason = 'duplicate_cascade' and h.b2c_lane = 'sales'
      and (select reason = 'duplicate' and set_by = 'engine' from b2b.partner_bars where lead_id = v_dup)
      and jsonb_array_length(pg_temp.handoff(v_dup) -> 'already_with_providers') = 2, coalesce(h.reason, '-'));
  -- lost after the grace
  v_lost := pg_temp.lead('919876570912', 'ZZNine');
  perform pg_temp.decide(v_lost, true);
  a1 := pg_temp.alloc(v_lost);
  perform pg_temp.pushed(a1.id);
  perform pg_temp.accept(a1.id);
  perform set_config('b2b.actor', 'partner', true);
  lost := b2b.apply_partner_lost(a1.id, '{"lost_reason": "joined elsewhere"}');
  update b2b.allocations set lost_at = now() - interval '8 days', lost_grace_until = now() - interval '1 day' where id = a1.id;
  update public.student_leads set lost_at = now() - interval '8 days' where id = v_lost;
  perform set_config('b2b.actor', 'system', true);
  n := b2b.lost_grace_tick();
  h := pg_temp.alloc(v_lost);
  insert into r values ('t9_lost_after_grace_barred', lost ->> 'status' = 'grace' and n >= 1 and h.destination_type = 'in_house' and h.reason = 'partner_lost' and h.b2c_lane = 'nurture'
      and (select status = 'closed' and outcome = 'lost' from b2b.allocations where id = a1.id)
      and (select reason = 'lost' and set_by = 'grace' from b2b.partner_bars where lead_id = v_lost)
      and (b2b.b2c_hold(pg_temp.lead_row(v_lost)) ->> 'kind') = 'barred' and not public.w2_crm_owned('919876570912'), coalesce(h.reason, '-') || ' n=' || n);
  -- months later: a new Meta form for each student
  perform pg_temp.age_touchpoints(v_dup, now() - interval '90 days');
  perform pg_temp.age_touchpoints(v_lost, now() - interval '90 days');
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, campaign, created_at)
  values (v_dup, '919876570911', 'meta', 'lead.updated', 'meta_lead_ads', 'ZZ Spring', now() - interval '3 minutes') returning id into tp1;
  insert into public.touchpoints (lead_id, phone, source_system, event_type, source, campaign, created_at)
  values (v_lost, '919876570912', 'meta', 'lead.updated', 'meta_lead_ads', 'ZZ Spring', now() - interval '3 minutes') returning id into tp2;
  perform set_config('b2b.actor', 'engine', true);
  tk := b2b.reenquiry_tick(1000);
  select e.* into ev1 from b2b.lead_reenquiries q join b2b.events e on e.id = q.event_id where q.touchpoint_id = tp1;
  select e.* into ev2 from b2b.lead_reenquiries q join b2b.events e on e.id = q.event_id where q.touchpoint_id = tp2;
  insert into r values ('t9_reenquiry_goes_to_b2c_barred', (tk ->> 'errors')::int = 0
      and ev1.type = 'b2c.lead_reenquired' and ev1.payload -> 'hold' ->> 'kind' = 'barred' and ev1.payload -> 'partner_bar' ->> 'reason' = 'duplicate' and ev1.payload ->> 'reason' = 'duplicate_cascade'
      and ev2.type = 'b2c.lead_reenquired' and ev2.payload -> 'hold' ->> 'kind' = 'barred' and ev2.payload -> 'partner_bar' ->> 'reason' = 'lost' and ev2.payload ->> 'reason' = 'partner_lost'
      and (select holder from b2b.lead_reenquiries where touchpoint_id = tp1) = 'barred' and (select holder from b2b.lead_reenquiries where touchpoint_id = tp2) = 'barred'
      and (select destination_type = 'in_house' and allocation_reason = 'duplicate_cascade' from public.student_leads where id = v_dup)
      and (select destination_type = 'in_house' and allocation_reason = 'partner_lost' from public.student_leads where id = v_lost)
      and not exists (select 1 from b2b.allocations where lead_id in (v_dup, v_lost) and destination_type = 'partner' and status in ('queued', 'pushing', 'pushed', 'accepted')),
    tk::text || ' ' || coalesce(ev1.payload -> 'hold' #>> '{}', '-') || ' ' || coalesce(ev2.payload -> 'hold' #>> '{}', '-'));
  x := pg_temp.decide(v_dup, false);
  insert into r values ('t9_preview_never_a_partner', x ->> 'outcome' = 're-enquired' and x ->> 'destination' = 'in_house' and (x -> 'bar' ->> 'reason') = 'duplicate', x ->> 'outcome');
  -- the Admin's manual route is refused for both: the function, the API and the bulk action
  e := pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_dup, 'manual try after the cascade'));
  insert into r values ('t9_dup_manual_route_refused', e like '22023 partner_barred: partner-barred (duplicate) since %', e);
  e := pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_lost, 'manual try after the grace'));
  insert into r values ('t9_lost_manual_route_refused', e like '22023 partner_barred: partner-barred (lost) since %', e);
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_dup, 'manual try after the cascade');
  insert into r values ('t9_dup_api_422', (x ->> 'status') = '422' and x ->> 'error_code' = 'partner_barred' and not (x ->> 'ok')::boolean, x::text);
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_lost, 'manual try after the grace');
  insert into r values ('t9_lost_api_422', (x ->> 'status') = '422' and x ->> 'error_code' = 'partner_barred', x::text);
  x := b2b.route_to_partners_many(array[v_dup, v_lost], 'bulk try for barred leads');
  insert into r values ('t9_bulk_skips_barred', (x ->> 'skipped_barred')::int = 2 and (x ->> 'sent')::int = 0 and (x ->> 'failed')::int = 0
      and (select bool_and(not (z ->> 'ok')::boolean and z ->> 'skipped' = 'partner_barred') from jsonb_array_elements(x -> 'results') z), x::text);
end $x$;

-- ======================================================================================================================
-- Rulebook test 10: a no_partner_offers_programme lead can be routed by hand once a partner offers the course (C124 note)
-- ======================================================================================================================
do $x$
declare v_a bigint; v_b bigint; x jsonb; a b2b.allocations; h b2b.allocations; d b2b.engine_decisions; s text; bar b2b.partner_bars;
begin
  v_a := pg_temp.lead('919876571001', 'ZZTenA');
  x := pg_temp.decide(v_a, true);
  h := pg_temp.alloc(v_a);
  insert into r values ('t10_nobody_offers_to_b2c_sales', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'no_partner_offers_programme' and x ->> 'b2c_lane' = 'sales'
      and h.reason = 'no_partner_offers_programme' and (b2b.b2c_hold(pg_temp.lead_row(v_a)) ->> 'kind') = 'selling'
      and (x -> 'interests' -> 0 ->> 'outcome') = 'no_offer', coalesce(x ->> 'reason', '-'));
  -- Gamma starts offering the course: the API routes the lead by hand
  perform pg_temp.offer(pg_temp.v('GAMMA')::bigint, pg_temp.v('P_T10A')::bigint);
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_a, 'partner asked for this lead');
  a := pg_temp.alloc(v_a);
  d := pg_temp.decision(a.id);
  insert into r values ('t10_manual_route_to_new_partner', (x ->> 'status') = '200' and (x ->> 'ok')::boolean and x -> 'result' ->> 'destination' = 'partner'
      and (x -> 'result' ->> 'partner_id')::bigint = pg_temp.v('GAMMA')::bigint and x -> 'result' ->> 'outcome' = 'decided'
      and a.destination_type = 'partner' and a.partner_id = pg_temp.v('GAMMA')::bigint and a.origin = 'to_partners' and a.mode = 'manual' and a.status = 'queued'
      and (select status = 'closed' and outcome = 'routed_to_partners' from b2b.allocations where id = h.id)
      and b2b.partner_bar(pg_temp.lead_row(v_a)) is null and b2b.b2c_hold(pg_temp.lead_row(v_a)) is null
      and exists (select 1 from b2b.events e where e.type = 'lead.route_to_partners' and e.lead_id = v_a), x::text);
  insert into r values ('c124_route_to_partners_reason_stored', d.reason = 'partner asked for this lead' and d.how = 'to_partners' and d.mode = 'manual', coalesce(d.reason, 'null'));
  -- the variant: the only partner claims a proven duplicate → manual_route_failed, cause duplicate_cascade, barred by the manual route
  v_b := pg_temp.lead('919876571002', 'ZZTenB');
  x := pg_temp.decide(v_b, true);
  insert into r values ('t10_variant_fixture_b2c', x ->> 'reason' = 'no_partner_offers_programme', x ->> 'reason');
  perform pg_temp.offer(pg_temp.v('GAMMA')::bigint, pg_temp.v('P_T10B')::bigint);
  x := b2b.api_route_to_partners('eb2b_m31rtest_key_0001', v_b, 'partner asked for this lead too');
  a := pg_temp.alloc(v_b);
  perform pg_temp.pushing(a.id);
  s := b2b.apply_duplicate(a.id, '{"existing_record_id": "GAMMA-10", "created_at": "2026-06-01"}');
  h := pg_temp.alloc(v_b);
  select * into bar from b2b.partner_bars where lead_id = v_b;
  insert into r values ('t10_variant_duplicate_manual_route_failed', (x ->> 'status') = '200' and s = 'duplicate: re-routed'
      and h.destination_type = 'in_house' and h.reason = 'manual_route_failed' and h.cause = 'duplicate_cascade' and h.b2c_lane = 'sales' and h.mode = 'manual' and h.origin = 'to_partners'
      and bar.reason = 'duplicate' and bar.set_by = 'manual_route' and bar.allocation_id = h.id
      and pg_temp.handoff(v_b) -> 'handling' ->> 'assignment' = 'previous_counsellor'
      and (select destination_type = 'in_house' from public.student_leads where id = v_b), coalesce(h.reason, '-') || ' cause=' || coalesce(h.cause, '-') || ' bar=' || coalesce(bar.set_by, 'none'));
end $x$;

-- ======================================================================================================================
-- Rulebook tests 1 and 15 with Amendment 1: an unqualified Witty lead waits 18 h, goes to nurture, qualifies, reaches a partner
-- ======================================================================================================================
do $x$
declare v_w bigint; rd jsonb; po jsonb; ll jsonb; n int; a b2b.allocations; p jsonb; tk jsonb; l public.student_leads; x jsonb;
begin
  v_w := pg_temp.lead('919876571501', 'ZZAmend', '{"email": null, "classification": null, "source": "whatsapp_direct", "first_agent_channel": "whatsapp", "consent_partner_share_at": null, "consent_text_version": null}', 'witty');
  perform pg_temp.set('W15', v_w::text);
  insert into public.w2_inbox (message_id, phone, received_at) values ('m31r-w15-1', '919876571501', now() - interval '1 hour');
  update public.student_leads set created_at = now() - interval '1 hour' where id = v_w;
  -- it is in the B2B CRM: the Master Lead Table and the pool (waiting for 18 h of inactivity)
  ll := b2b.leads_list(jsonb_build_object('q', '919876571501'));
  rd := b2b.lead_readiness(pg_temp.lead_row(v_w));
  po := b2b.pool_overview('waiting_inactivity');
  insert into r values ('t15_unqualified_witty_lead_in_master_table', exists (select 1 from jsonb_array_elements(ll -> 'rows') z where (z ->> 'id')::bigint = v_w)
      and b2b.lead_class(pg_temp.lead_row(v_w)) -> 'missing' = '["no_email"]', left(coalesce(ll::text, '-'), 200));
  insert into r values ('t15_pool_waiting_inactivity', not (rd ->> 'ready')::boolean and rd -> 'wait' ->> 'kind' = 'inactivity' and rd ->> 'gate' = 'inactivity'
      and (rd ->> 'decide_after')::timestamptz = now() + interval '17 hours'
      and (po -> 'groups' -> 'waiting_inactivity' ->> 'n')::int >= 1 and exists (select 1 from jsonb_array_elements(po -> 'rows') z where (z ->> 'id')::bigint = v_w and z ->> 'group' = 'waiting_inactivity')
      and (po ->> 'routing_on')::boolean, coalesce(rd -> 'wait' #>> '{}', '-') || ' pool=' || coalesce(po -> 'groups' -> 'waiting_inactivity' #>> '{}', '-'));
  -- the sweep stores the wait and decides nothing
  n := b2b.route_ready_leads(25);
  insert into r values ('t1_sweep_waits_18h', (select destination_type from public.student_leads where id = v_w) is null
      and (select why like 'unqualified: waiting for 18 h%' and decide_after = now() + interval '17 hours' from b2b.lead_waits where lead_id = v_w), (select why from b2b.lead_waits where lead_id = v_w));
  -- 19 hours of silence: the sweep hands it to B2C qualification nurture with the welcome request and the missing codes
  update public.w2_inbox set received_at = now() - interval '19 hours' where message_id = 'm31r-w15-1';
  update public.student_leads set created_at = now() - interval '19 hours' where id = v_w;
  update b2b.lead_waits set decide_after = now() - interval '1 minute' where lead_id = v_w;
  n := b2b.route_ready_leads(25);
  a := pg_temp.alloc(v_w);
  p := pg_temp.handoff(v_w);
  insert into r values ('t1_nurture_after_18h', a.destination_type = 'in_house' and a.reason = 'not_qualified' and a.b2c_lane = 'nurture' and a.status = 'handed_off' and a.origin = 'auto'
      and exists (select 1 from b2b.engine_decisions d where d.lead_id = v_w and d.reason = 'not_qualified' and d.how = 'auto')
      and p -> 'b2c_actions' = '["welcome_explore_programmes"]' and p -> 'missing' = '["no_email"]' and p -> 'welcome' ->> 'template_hint' = 'explore_programmes'
      and p -> 'handling' ->> 'job' = 'qualify' and (p ->> 'contract_version') = '3'
      and (b2b.b2c_hold(pg_temp.lead_row(v_w)) ->> 'kind') = 'qualification_nurture', coalesce(a.reason, '-') || ' ' || coalesce(p -> 'b2c_actions' #>> '{}', '-'));
  insert into r values ('t15_pool_shows_nurture_not_waiting', not exists (select 1 from jsonb_array_elements(b2b.pool_overview('waiting_inactivity') -> 'rows') z where (z ->> 'id')::bigint = v_w), null);
  -- two days later Witty gets the email, the label WARM and the covering consent; the lead is idle; requalify_tick routes it to a partner
  perform public.lead_intake(jsonb_build_object('phone', '919876571501', 'source_system', 'witty', 'event_type', 'lead.updated',
    'lead', jsonb_build_object('email', 'w15@test.local', 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1')));
  update public.student_leads set created_at = now() - interval '2 days 19 hours' where id = v_w;
  update b2b.allocations set created_at = now() - interval '2 days' where id = a.id;
  insert into r values ('t1_witty_qualified_it', b2b.lead_class(pg_temp.lead_row(v_w)) ->> 'class' = 'qualified' and (b2b.partner_consent(pg_temp.lead_row(v_w)) ->> 'given')::boolean, b2b.lead_class(pg_temp.lead_row(v_w))::text);
  tk := b2b.requalify_tick(25);
  l := pg_temp.lead_row(v_w);
  insert into r values ('t1_requalified_to_partner', (tk ->> 'requalified')::int >= 1 and (tk ->> 'errors')::int = 0 and l.destination_type = 'partner' and l.partner_id = pg_temp.v('ALPHA')::bigint
      and (select outcome from b2b.allocations where id = a.id) = 'requalified'
      and (select origin = 'requalify' and destination_type = 'partner' and status = 'queued' from b2b.allocations where id = l.allocation_id)
      and exists (select 1 from b2b.events e where e.type = 'b2c.lead_requalified' and e.lead_id = v_w and e.payload ->> 'destination' = 'partner' and (e.payload ->> 'closed_allocation_id')::bigint = a.id)
      and exists (select 1 from b2b.events e where e.type = 'lead.requalified' and e.lead_id = v_w), tk::text || ' ' || coalesce(l.destination_type, '-'));
  x := pg_temp.decide(v_w, false);
  insert into r values ('t15_with_partner_now', x ->> 'outcome' = 'with_partner', x ->> 'outcome');
end $x$;

-- ======================================================================================================================
-- Amendment 1: the 18-hour inactivity clock (readiness + the sweep)
-- ======================================================================================================================
do $x$
declare v_a bigint; v_e bigint; v_wa bigint; v_q bigint; rd jsonb; n int; a b2b.allocations;
begin
  -- an inbound message 17 h ago: not ready, decide_after = message + 18 h
  v_a := pg_temp.lead('919876571511', 'ZZAmend', '{"email": null, "classification": null, "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  update public.student_leads set created_at = now() - interval '3 days' where id = v_a;
  insert into public.w2_inbox (message_id, phone, received_at) values ('m31r-a1-1', '919876571511', now() - interval '17 hours');
  rd := b2b.lead_readiness(pg_temp.lead_row(v_a));
  insert into r values ('a1_inbound_17h_waits', not (rd ->> 'ready')::boolean and rd -> 'wait' ->> 'kind' = 'inactivity' and (rd ->> 'decide_after')::timestamptz = now() + interval '1 hour'
      and rd -> 'missing' ? 'unqualified: waiting for 18 h without a student message', rd::text);
  -- Witty's own reply 1 h ago does not restart the clock
  update public.w2_inbox set received_at = now() - interval '19 hours' where message_id = 'm31r-a1-1';
  insert into public.w2_messages (phone, direction, content, created_at) values ('919876571511', 'out', 'reply', now() - interval '1 hour');
  rd := b2b.lead_readiness(pg_temp.lead_row(v_a));
  insert into r values ('a1_outbound_does_not_restart', (rd ->> 'ready')::boolean and rd ->> 'gate' = 'inactivity', rd::text);
  -- a new inbound message restarts it; the sweep stores the wait
  insert into public.w2_messages (phone, direction, content, created_at) values ('919876571511', 'in', 'hello', now() - interval '2 hours');
  rd := b2b.lead_readiness(pg_temp.lead_row(v_a));
  n := b2b.route_ready_leads(25);
  insert into r values ('a1_inbound_restarts', not (rd ->> 'ready')::boolean and (rd ->> 'decide_after')::timestamptz = now() + interval '16 hours'
      and (select destination_type from public.student_leads where id = v_a) is null
      and (select decide_after = now() + interval '16 hours' from b2b.lead_waits where lead_id = v_a), rd ->> 'decide_after');
  -- the admin setting is the clock
  update b2b.settings set value = jsonb_set(value, '{witty_unqualified_idle_hours}', '1') where key = 'engine';
  insert into r values ('a1_hours_are_an_admin_setting', (b2b.lead_readiness(pg_temp.lead_row(v_a)) ->> 'ready')::boolean, null);
  update b2b.settings set value = jsonb_set(value, '{witty_unqualified_idle_hours}', '18') where key = 'engine';
  -- it qualifies inside the 18 hours (WARM, email, consent) and is idle 31 minutes: the next sweep routes it to a partner (critic A3)
  perform public.lead_intake(jsonb_build_object('phone', '919876571511', 'source_system', 'witty', 'event_type', 'lead.updated',
    'lead', jsonb_build_object('email', 'a1@test.local', 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1')));
  update public.w2_messages set created_at = now() - interval '31 minutes' where phone = '919876571511' and direction = 'in';
  update b2b.lead_waits set decide_after = now() - interval '1 minute' where lead_id = v_a;
  rd := b2b.lead_readiness(pg_temp.lead_row(v_a));
  n := b2b.route_ready_leads(25);
  a := pg_temp.alloc(v_a);
  insert into r values ('a1_qualified_idle_31min_routed', (rd ->> 'ready')::boolean and rd ->> 'gate' = 'idle' and a.destination_type = 'partner' and a.partner_id = pg_temp.v('ALPHA')::bigint and a.origin = 'auto',
    coalesce(rd ->> 'gate', '-') || ' ' || coalesce(a.destination_type, 'not routed'));
  -- an unqualified escalated lead still waits the 18 hours
  v_e := pg_temp.lead('919876571512', 'ZZAmend', '{"email": null, "classification": null, "source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  insert into public.w2_inbox (message_id, phone, received_at) values ('m31r-a1-2', '919876571512', now() - interval '5 hours');
  update public.student_leads set lead_stage = 'ESCALATION', is_bot_paused = true where id = v_e;
  rd := b2b.lead_readiness(pg_temp.lead_row(v_e));
  insert into r values ('a1_unqualified_escalated_still_waits', not (rd ->> 'ready')::boolean and rd -> 'wait' ->> 'kind' = 'inactivity' and (rd ->> 'decide_after')::timestamptz = now() + interval '13 hours', rd::text);
  -- a website-agent unqualified lead waits 30 minutes, not 18 hours
  v_wa := pg_temp.lead('919876571513', null, '{"classification": null, "source": "website"}', 'web_agent');
  update public.student_leads set phone_verified_at = now() where id = v_wa;
  rd := b2b.lead_readiness(pg_temp.lead_row(v_wa));
  insert into r values ('a1_web_agent_waits_30min', not (rd ->> 'ready')::boolean and rd -> 'wait' ->> 'kind' = 'chatting' and rd -> 'missing' ? 'still chatting with the website agent'
      and (rd ->> 'decide_after')::timestamptz <= now() + interval '30 minutes' and (rd ->> 'decide_after')::timestamptz > now() + interval '28 minutes', rd::text);
  -- a qualified Witty lead still chatting: an escalation touchpoint whose occurred_at is days old but created now opens the gate (critic A2)
  v_q := pg_temp.lead('919876571514', 'ZZAmend', '{"source": "whatsapp_direct", "first_agent_channel": "whatsapp"}', 'witty');
  update public.student_leads set created_at = now() - interval '1 day', last_agent_message_at = now() - interval '5 minutes' where id = v_q;
  rd := b2b.lead_readiness(pg_temp.lead_row(v_q));
  insert into r values ('a1_qualified_chatting_waits', not (rd ->> 'ready')::boolean and rd ->> 'gate' = 'chatting' and rd -> 'missing' ? 'still chatting with Witty'
      and (rd ->> 'decide_after')::timestamptz = now() + interval '25 minutes', rd::text);
  insert into public.touchpoints (lead_id, phone, source_system, event_type, occurred_at)
  values (v_q, '919876571514', 'witty', 'lead.escalated', now() - interval '5 days');
  rd := b2b.lead_readiness(pg_temp.lead_row(v_q));
  insert into r values ('a1_escalation_touchpoint_created_now_opens_gate', (rd ->> 'ready')::boolean and rd ->> 'gate' = 'escalated', rd::text);
end $x$;

-- ======================================================================================================================
-- Sweep (C6): the legacy kill switch is ignored; the sweep decides a ready form lead; the Admin cannot set the retired key
-- ======================================================================================================================
do $x$
declare v_f bigint; n int; e text;
begin
  update b2b.settings set value = value || '{"kill_switch": true}' where key = 'engine';
  v_f := pg_temp.lead('919876571601', 'ZZRseven', '{"source": "website_form"}', 'api');
  n := b2b.route_ready_leads(25);
  insert into r values ('c6_sweep_ignores_legacy_kill_switch', exists (select 1 from b2b.engine_decisions d where d.lead_id = v_f)
      and (select destination_type from public.student_leads where id = v_f) = 'partner'
      and (b2b.pool_overview() ->> 'routing_on')::boolean, (select destination_type from public.student_leads where id = v_f));
  e := pg_temp.err('select b2b.engine_settings_save(''{"kill_switch": true}'', ''x'')');
  insert into r values ('c6_kill_switch_retired', e like '22023 retired by Addendum 3: kill_switch%', e);
  update b2b.settings set value = value || '{"kill_switch": false}' where key = 'engine';
  -- a Not passed lead with an unchanged fingerprint is not re-decided (critic B18)
  n := b2b.route_ready_leads(25);
  insert into r values ('sweep_not_passed_once', (select times from b2b.not_passed where lead_id = (select v::bigint from t where k = 'IP6')) = 1
      and not exists (select 1 from b2b.engine_decisions where lead_id = (select v::bigint from t where k = 'IP6')), null);
  -- the engine switch stops the sweep
  update b2b.settings set value = value || '{"enabled": false}' where key = 'engine';
  insert into r values ('sweep_engine_disabled_stops', b2b.route_ready_leads(25) = 0 and not (b2b.pool_overview() ->> 'routing_on')::boolean, null);
  update b2b.settings set value = value || '{"enabled": true}' where key = 'engine';
end $x$;

-- ---------- hygiene ----------
insert into r select 'no_test_phone_outside_tests', not exists (select 1 from public.student_leads l where l.whatsapp_number like '910000%' and l.id not in (select v::bigint from t where k in ('T1', 'T2'))
                                                                 and l.student_name like 'M31r %' and l.whatsapp_number <> '910000770003'), null;
insert into r select 'route_decide_has_no_thompson', position('thompson_pick' in pg_get_functiondef('b2b.route_decide(bigint,boolean,text,text)'::regprocedure)) = 0, null;

select name, ok, detail from r order by ok, name;
rollback;
