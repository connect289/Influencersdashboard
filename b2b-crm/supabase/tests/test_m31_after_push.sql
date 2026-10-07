-- M31 after the push (Addendum 3 PART 5, PART 6.1 and 6.4) in PGlite or on STAGING, rolled back. Fixtures are built in the
-- transaction: a ZZ catalogue (one course per test group, so the staging partners never compete), partners with rates and
-- offers, qualified leads with covering consent. Partner answers are applied as the push engine applies them (apply_created,
-- apply_duplicate, apply_rejection, apply_push_error) and partner events are stored rows applied with partner_event_apply.
-- Covers rulebook tests 3, 4 and the bar part of 9, the design's after-push rows (duplicates, rejections and limits; lost grace
-- and revival; disputes and notifications; auto-pause; partner settings; the push note) and critics B6-B11. Checks of functions
-- that m31j / m31l replace (b2c_record, reroute_lead, reroute_check) are recorded as ok with detail 'skipped' until those
-- migrations are applied. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
create temp sequence fxcycle;
create temp sequence evseq;
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.has(sig text, marker text) returns boolean language sql as $f$
  select coalesce((select prosrc ~ marker from pg_proc where oid = to_regprocedure(sig)), false) $f$;
create function pg_temp.stub(sig text) returns boolean language sql as $f$
  select to_regprocedure(sig) is null or pg_temp.has(sig, 'contract-stub') $f$;
create function pg_temp.decide(p_lead bigint, p_commit boolean, p_how text default 'auto', p_note text default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
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
  insert into b2b.partners (slug, name, display_name, status, daily_cap, monthly_cap, contract_min_monthly, lead_criteria, api_base_url, notify_enabled)
  values (p_slug, p_name, p_name, coalesce(p_extra ->> 'status', 'active'), (p_extra ->> 'daily_cap')::int, (p_extra ->> 'monthly_cap')::int,
          (p_extra ->> 'contract_min_monthly')::int, coalesce(p_extra -> 'criteria', '{}'::jsonb), 'https://' || p_slug || '.zz-ap.example.invalid/leads',
          coalesce((p_extra ->> 'notify')::boolean, false))
  returning id into v_id;
  insert into b2b.live_switches (scope, live, reason) values ('partner:' || v_id, true, 'm31 after-push test') on conflict (scope) do update set live = true;
  insert into b2b.partner_programme_versions (partner_id, version_no, status, published_at) values (v_id, 1, 'published', now());
  return v_id;
end $f$;
create function pg_temp.offer(p bigint, p_prog bigint, p_fees jsonb default '{}') returns void language sql as $f$
  insert into b2b.partner_programmes (partner_id, programme_id, program_key, source_version_id, fees)
  select p, p_prog, c.program_key, pv.id, p_fees from public.catalog_programs c, b2b.partner_programme_versions pv where c.id = p_prog and pv.partner_id = p $f$;
create function pg_temp.rate(p bigint, p_type text, p_value numeric) returns void language sql as $f$
  insert into b2b.rates (scope, partner_id, rate_type, value, tiers, gst_inclusive) values ('partner', p, p_type, p_value, null, false) $f$;
create function pg_temp.lead(p_phone text, p_course text, p_extra jsonb default '{}') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_strip_nulls(jsonb_build_object('full_name', 'M31i ' || p_phone, 'email', 'm31i-' || p_phone || '@test.local', 'interested_course', p_course,
                                                 'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi', 'source', 'website',
                                                 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1') || p_extra)));
  select l.id into v_id from public.student_leads l where l.whatsapp_number = p_phone;
  return v_id;
end $f$;
-- the lead's current allocation, and its latest partner allocation
create function pg_temp.alloc(p_lead bigint) returns b2b.allocations language sql as $f$
  select a.* from b2b.allocations a join public.student_leads l on l.allocation_id = a.id where l.id = p_lead $f$;
create function pg_temp.palloc(p_lead bigint) returns b2b.allocations language sql as $f$
  select a.* from b2b.allocations a where a.lead_id = p_lead and a.destination_type = 'partner' order by a.id desc limit 1 $f$;
-- the partner's answers, as the push engine applies them
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
-- a lead routed, pushed and accepted by the winning partner: returns the allocation id
create function pg_temp.accepted_lead(p_phone text, p_course text) returns bigint language plpgsql as $f$
declare v_lead bigint; a b2b.allocations;
begin
  v_lead := pg_temp.lead(p_phone, p_course);
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  perform pg_temp.pushed(a.id);
  perform pg_temp.accept(a.id);
  return a.id;
end $f$;
-- a partner event stored raw and applied (partner_event_ingest does the same after its signature check)
create function pg_temp.event(p_alloc bigint, p_type text, p_data jsonb, p_extra jsonb default '{}') returns jsonb language plpgsql as $f$
declare a b2b.allocations; v_id bigint; v_eid text := 'zzap-' || nextval('evseq');
begin
  perform set_config('b2b.actor', 'partner', true);
  select * into a from b2b.allocations where id = p_alloc;
  insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
  values (a.partner_id, v_eid, p_type, a.reference, a.partner_record_id, a.id, a.lead_id,
          jsonb_build_object('event_id', v_eid, 'type', p_type, 'reference', a.reference, 'data', p_data) || p_extra)
  returning id into v_id;
  return b2b.partner_event_apply(v_id) || jsonb_build_object('event_id', v_id);
end $f$;
create function pg_temp.handoff(p_lead bigint) returns jsonb language sql as $f$
  select e.payload from b2b.events e where e.type = 'b2c.lead_handed_off' and e.lead_id = p_lead order by e.id desc limit 1 $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $f$;

-- ---------- settings, the admin, consent ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f9', 'm31i-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f9', 'm31i-admin@test.local');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f9","role":"authenticated","aal":"aal2","email":"m31i-admin@test.local"}', true);
insert into b2b.live_switches (scope, live, reason) values ('routing', true, 'm31 after-push test') on conflict (scope) do update set live = true;
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"enabled":true,"consent_policy":"ask","kill_switch":false}' where key = 'engine';
update b2b.settings set value = jsonb_set(value, '{a3_fixed,exploration_share}', '0') where key = 'engine';
update b2b.ml_models set status = 'retired' where status in ('shadow', 'challenger', 'champion', 'training');
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at)
values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now());
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m31i b2c', '{events}', 'eb2b_m31itest', encode(extensions.digest('eb2b_m31itest_key_0001', 'sha256'), 'hex'));
update b2b.message_templates set status = 'active' where kind = 'accepted' and channel = 'whatsapp' and language = 'en';

-- ---------- catalogue: one course per test group ----------
select pg_temp.set('U1', pg_temp.uni('ZZ After Push University', 'ZZAP')::text);
select pg_temp.set('PA', pg_temp.prog('zz-ap-dup', 'ZZApDup', 'zzapdup', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PONLY', pg_temp.prog('zz-ap-only', 'ZZApOnly', 'zzaponly', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PCAP', pg_temp.prog('zz-ap-cap', 'ZZApCap', 'zzapcap', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PPAUSE', pg_temp.prog('zz-ap-pause', 'ZZApPause', 'zzappause', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PGUARD', pg_temp.prog('zz-ap-guard', 'ZZApGuard', 'zzapguard', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);

-- ---------- partners: Alpha 25 %, Beta 20 %, Gamma 15 % on the duplicate course; Full is always at its cap ----------
select pg_temp.set('A1', pg_temp.partner('zz-ap-alpha', 'ZZ Alpha', '{"notify": true}')::text);
select pg_temp.set('A2', pg_temp.partner('zz-ap-beta', 'ZZ Beta')::text);
select pg_temp.set('A3', pg_temp.partner('zz-ap-gamma', 'ZZ Gamma')::text);
select pg_temp.set('CAP', pg_temp.partner('zz-ap-full', 'ZZ Full', '{"daily_cap": 0}')::text);
select pg_temp.set('PP', pg_temp.partner('zz-ap-pause', 'ZZ Pause')::text);
select pg_temp.set('GP', pg_temp.partner('zz-ap-guard', 'ZZ Guard')::text);
select pg_temp.rate(pg_temp.v('A1')::bigint, 'percent', 25);
select pg_temp.rate(pg_temp.v('A2')::bigint, 'percent', 20);
select pg_temp.rate(pg_temp.v('A3')::bigint, 'percent', 15);
select pg_temp.rate(pg_temp.v('CAP')::bigint, 'percent', 10);
select pg_temp.rate(pg_temp.v('PP')::bigint, 'percent', 30);
select pg_temp.rate(pg_temp.v('GP')::bigint, 'percent', 30);
select pg_temp.offer(pg_temp.v('A1')::bigint, pg_temp.v('PA')::bigint);
select pg_temp.offer(pg_temp.v('A2')::bigint, pg_temp.v('PA')::bigint);
select pg_temp.offer(pg_temp.v('A3')::bigint, pg_temp.v('PA')::bigint);
select pg_temp.offer(pg_temp.v('A1')::bigint, pg_temp.v('PONLY')::bigint);
select pg_temp.offer(pg_temp.v('A1')::bigint, pg_temp.v('PCAP')::bigint);
select pg_temp.offer(pg_temp.v('CAP')::bigint, pg_temp.v('PCAP')::bigint);
select pg_temp.offer(pg_temp.v('A1')::bigint, pg_temp.v('PPAUSE')::bigint);
select pg_temp.offer(pg_temp.v('PP')::bigint, pg_temp.v('PPAUSE')::bigint);
select pg_temp.offer(pg_temp.v('A1')::bigint, pg_temp.v('PGUARD')::bigint);
select pg_temp.offer(pg_temp.v('GP')::bigint, pg_temp.v('PGUARD')::bigint);

insert into r select 'setup_schema', exists (select 1 from cron.job where jobname = 'b2b-lost-grace-tick')
    and (select count(*) from b2b.message_templates where kind = 'reroute_update' and status = 'draft') = 4
    and to_regprocedure('b2b.lost_handoff(bigint)') is not null and not pg_temp.has('b2b.lost_handoff(bigint)', 'contract-stub'),
  (select string_agg(kind || '/' || channel || '/' || language, ' ') from b2b.message_templates where kind = 'reroute_update');

-- ======================================================================================================================
-- PART 6.4: a queued push for a paused partner fails over at once, with no attempt (push_dispatch; critic B27)
-- ======================================================================================================================
do $x$
declare v_lead bigint; a b2b.allocations; n int; b b2b.allocations;
begin
  v_lead := pg_temp.lead('919876519001', 'ZZApPause');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  insert into r values ('pause_winner_is_pause', a.partner_id = pg_temp.v('PP')::bigint and a.status = 'queued', a.partner_id::text || ' ' || a.status);
  update b2b.partners set status = 'paused', paused_reason = 'm31i test' where id = pg_temp.v('PP')::bigint;
  perform set_config('b2b.actor', 'engine', true);
  n := b2b.push_dispatch(100);
  select * into a from b2b.allocations where id = a.id;
  b := pg_temp.alloc(v_lead);
  insert into r values ('pause_failover_no_attempt', a.status = 'failed' and a.push_attempts = 0 and a.last_error like 'partner paused%'
      and exists (select 1 from b2b.events e where e.type = 'lead.push_failed' and e.allocation_id = a.id and (e.payload ->> 'partner_paused')::boolean),
    a.status || ' attempts=' || a.push_attempts || ' ' || coalesce(a.last_error, ''));
  insert into r values ('pause_failover_next_partner', b.destination_type = 'partner' and b.partner_id = pg_temp.v('A1')::bigint and b.id <> a.id,
    coalesce(b.destination_type, 'none') || ' ' || coalesce(b.partner_id::text, '-'));
end $x$;

-- ======================================================================================================================
-- PART 6.4 auto-pause: 5 first-contact breaches in a row (met late counts) pause the partner; its queued lead fails over
-- ======================================================================================================================
do $x$
declare v_fx bigint; v_lead bigint; a b2b.allocations; b b2b.allocations; g jsonb; i int; v_al bigint; d b2b.engine_decisions;
begin
  v_fx := pg_temp.lead('919876519002', 'ZZApGuard');
  for i in 1..5 loop
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, accepted_at, pushed_at, created_at, is_test, origin)
    values (v_fx, nextval('fxcycle'), 'zzapguard|PG|Online', 'partner', pg_temp.v('GP')::bigint, 'accepted', 'commission_first', 1,
            now() - make_interval(days => i) + interval '1 hour', now() - make_interval(days => i), now() - make_interval(days => i), false, 'auto')
    returning id into v_al;
    insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, met_at, status, is_test)
    values (v_al, v_fx, pg_temp.v('GP')::bigint, 'first_attempt', now() - make_interval(days => i), now() - make_interval(days => i) + interval '2 hours',
            now() - make_interval(days => i) + interval '5 hours', 'met_late', false);
  end loop;
  v_lead := pg_temp.lead('919876519003', 'ZZApGuard');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  insert into r values ('guard_winner_is_guard', a.partner_id = pg_temp.v('GP')::bigint and a.status = 'queued', a.partner_id::text);
  perform set_config('b2b.actor', 'system', true);
  g := b2b.guard_tick();
  select * into a from b2b.allocations where id = a.id;
  b := pg_temp.alloc(v_lead);
  select * into d from b2b.engine_decisions where lead_id = v_lead order by id desc limit 1;
  insert into r values ('guard_pauses_partner', (select status from b2b.partners where id = pg_temp.v('GP')::bigint) = 'paused'
      and exists (select 1 from b2b.events e where e.type = 'alert.partner_auto_paused' and e.partner_id = pg_temp.v('GP')::bigint),
    (select status || ' ' || coalesce(paused_reason, '') from b2b.partners where id = pg_temp.v('GP')::bigint));
  insert into r values ('guard_failover_not_an_attempt', a.status = 'failed' and a.push_attempts = 0
      and b.destination_type = 'partner' and b.partner_id = pg_temp.v('A1')::bigint and d.destination_type = 'partner' and d.reason is distinct from 'partners_unreachable',
    a.status || ' attempts=' || a.push_attempts || ' next=' || coalesce(b.partner_id::text, 'none') || ' reason=' || coalesce(d.reason, 'partner'));
  insert into r values ('duplicate_rate_pause_off_by_default',
    not coalesce(((select value from b2b.settings where key = 'engine') -> 'guard' ->> 'duplicate_rate_pause')::boolean, false), null);
end $x$;

-- ======================================================================================================================
-- Rulebook test 3: two proof-backed duplicate claims → B2C sales, duplicate_cascade, barred, "Already with other providers"
-- ======================================================================================================================
do $x$
declare v_lead bigint; a1 b2b.allocations; a2 b2b.allocations; h b2b.allocations; s1 text; s2 text; p jsonb; bar b2b.partner_bars; x jsonb;
begin
  v_lead := pg_temp.lead('919876519010', 'ZZApDup');
  perform pg_temp.set('L3', v_lead::text);
  perform pg_temp.decide(v_lead, true);
  a1 := pg_temp.alloc(v_lead);
  insert into r values ('t3_highest_cpe_first', a1.partner_id = pg_temp.v('A1')::bigint and a1.stage = 'A', a1.partner_id::text || ' ' || coalesce(a1.stage, '-'));
  perform pg_temp.pushing(a1.id);
  s1 := b2b.apply_duplicate(a1.id, '{"existing_record_id": "A1-77", "created_at": "2026-09-01T10:00:00+05:30"}');
  select * into a1 from b2b.allocations where id = a1.id;
  a2 := pg_temp.alloc(v_lead);
  insert into r values ('t3_first_duplicate_proof_kept', s1 = 'duplicate: re-routed' and a1.status = 'duplicate' and a1.claim_proof_ok
      and a1.claim_existing_record_id = 'A1-77' and a1.claim_existing_created_at = '2026-09-01T10:00:00+05:30'::timestamptz,
    s1 || ' ' || coalesce(a1.claim_existing_record_id, '-'));
  insert into r values ('t3_next_best_partner', a2.destination_type = 'partner' and a2.partner_id = pg_temp.v('A2')::bigint and a2.origin = 'auto' and a2.attempt_no = 2,
    coalesce(a2.destination_type, 'none') || ' ' || coalesce(a2.partner_id::text, '-') || ' attempt ' || a2.attempt_no);
  perform pg_temp.pushing(a2.id);
  s2 := b2b.apply_duplicate(a2.id, '{"existing_id": "A2-88", "existing_created_at": "2026-08-01"}');
  h := pg_temp.alloc(v_lead);
  select * into bar from b2b.partner_bars where lead_id = v_lead;
  p := pg_temp.handoff(v_lead);
  insert into r values ('t3_second_duplicate_to_b2c_sales', s2 = 'duplicate: re-routed' and h.destination_type = 'in_house' and h.reason = 'duplicate_cascade'
      and h.b2c_lane = 'sales' and h.status = 'handed_off'
      and (select destination_type from public.student_leads where id = v_lead) = 'in_house',
    coalesce(h.destination_type, 'none') || ' ' || coalesce(h.reason, '-') || ' ' || coalesce(h.b2c_lane, '-'));
  insert into r values ('t3_partner_bar_duplicate_engine', bar.reason = 'duplicate' and bar.set_by = 'engine' and bar.allocation_id = h.id
      and jsonb_array_length(bar.providers) = 2 and bar.phone_digits = '919876519010',
    coalesce(bar.reason, 'no bar') || ' ' || coalesce(bar.set_by, '-') || ' providers=' || coalesce(jsonb_array_length(bar.providers)::text, '-'));
  insert into r values ('t3_already_with_providers_badge', jsonb_array_length(p -> 'already_with_providers') = 2
      and (select bool_and(e ->> 'partner_name' in ('ZZ Alpha', 'ZZ Beta') and (e ->> 'first_had_at') is not null and (e ->> 'existing_record_id') is not null)
             from jsonb_array_elements(p -> 'already_with_providers') e)
      and (p -> 'partner_bar' ->> 'reason') = 'duplicate' and (p ->> 'contract_version') = '3',
    left(p -> 'already_with_providers' #>> '{}', 300));
  insert into r values ('t3_round_robin_neutral_adviser', p -> 'handling' ->> 'assignment' = 'round_robin_now' and p -> 'handling' ->> 'first_contact_script' = 'neutral_adviser'
      and p -> 'handling' ->> 'job' = 'sell', p -> 'handling' #>> '{}');
  insert into r values ('t3_partners_tried_two', jsonb_array_length(p -> 'partners_tried') = 2, p -> 'partners_tried' #>> '{}');
  -- no third partner was tried: Gamma never saw the lead
  insert into r values ('t3_gamma_never_tried', not exists (select 1 from b2b.allocations where lead_id = v_lead and partner_id = pg_temp.v('A3')::bigint), null);
  -- the B2C record shows the same (m31j)
  if pg_temp.has('b2b.b2c_record(public.student_leads)', 'already_with_providers') then
    select b2b.b2c_record(l) into x from public.student_leads l where l.id = v_lead;
    insert into r values ('t3_b2c_record_shows_bar', x -> 'allocation' ->> 'partner_bar_reason' = 'duplicate'
        and jsonb_array_length(x -> 'allocation' -> 'already_with_providers') = 2, left(x -> 'allocation' #>> '{}', 200));
  else
    insert into r values ('t3_b2c_record_shows_bar', true, 'skipped: b2c_record is pre-m31j');
  end if;
end $x$;

-- rulebook test 9, the bar: the duplicate-cascade lead can never go to a partner again, not even by hand
do $x$
declare v_lead bigint := pg_temp.v('L3')::bigint; e text; x jsonb;
begin
  e := pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_lead, 'manual try after the cascade'));
  insert into r values ('t9_dup_route_to_partners_refused', e like '22023 partner_barred:%', e);
  x := b2b.api_route_to_partners('eb2b_m31itest_key_0001', v_lead, 'manual try after the cascade');
  insert into r values ('t9_dup_api_422_partner_barred', (x ->> 'status') = '422' and x ->> 'error_code' = 'partner_barred' and not (x ->> 'ok')::boolean, x::text);
  -- a new enquiry months later is 're-enquired', never a partner (R2 preview)
  x := pg_temp.decide(v_lead, false);
  insert into r values ('t9_dup_reenquiry_stays_with_b2c', x ->> 'outcome' = 're-enquired' and coalesce(x ->> 'destination', '') <> 'partner'
      and (x -> 'bar' ->> 'reason') = 'duplicate', (x ->> 'outcome') || ' ' || coalesce(x ->> 'destination', '-'));
end $x$;

-- ======================================================================================================================
-- Duplicates, rejections and limits (PART 5.3-5.7, D2-D4, critic B6)
-- ======================================================================================================================
do $x$
declare v_lead bigint; a b2b.allocations; b b2b.allocations; s text;
begin
  -- a duplicate without proof is a rejection with a contract alert; the lead moves on; no bar
  v_lead := pg_temp.lead('919876519020', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  perform pg_temp.pushing(a.id);
  s := b2b.apply_duplicate(a.id, '{"source": "partner_event"}');
  select * into a from b2b.allocations where id = a.id;
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_unproven_duplicate_is_rejection', s = 'rejected: duplicate claim without proof' and a.status = 'rejected' and a.claim_proof_ok is false
      and a.last_error = 'duplicate claim without proof'
      and exists (select 1 from b2b.events e where e.type = 'alert.partner_rejected' and e.allocation_id = a.id and (e.payload ->> 'contract_breach')::boolean)
      and b.destination_type = 'partner' and b.partner_id = pg_temp.v('A2')::bigint
      and not exists (select 1 from b2b.partner_bars where lead_id = v_lead),
    s || ' -> ' || coalesce(b.destination_type, 'none') || ' ' || coalesce(b.partner_id::text, '-'));

  -- two rejections → partner_attempts_exhausted, no bar
  v_lead := pg_temp.lead('919876519021', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_rejection(a.id, 'outside our criteria');
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_rejection(a.id, 'outside our criteria too');
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_two_rejections_exhausted_no_bar', b.destination_type = 'in_house' and b.reason = 'partner_attempts_exhausted' and b.b2c_lane = 'sales'
      and not exists (select 1 from b2b.partner_bars where lead_id = v_lead)
      and (select count(*) from b2b.events e where e.type = 'alert.partner_rejected' and e.lead_id = v_lead and (e.payload ->> 'contract_breach')::boolean) = 2,
    coalesce(b.destination_type, 'none') || ' ' || coalesce(b.reason, '-'));

  -- one proven duplicate then a rejection → partner_attempts_exhausted, no bar
  v_lead := pg_temp.lead('919876519022', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_duplicate(a.id, '{"existing_record_id": "X-1"}');
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_rejection(a.id, 'no');
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_dup_then_reject_exhausted_no_bar', b.destination_type = 'in_house' and b.reason = 'partner_attempts_exhausted'
      and not exists (select 1 from b2b.partner_bars where lead_id = v_lead), coalesce(b.destination_type, 'none') || ' ' || coalesce(b.reason, '-'));

  -- one proven duplicate and no other eligible partner → duplicate_cascade and a bar (D2)
  v_lead := pg_temp.lead('919876519023', 'ZZApOnly');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_duplicate(a.id, '{"existing_record_id": "X-2", "created_at": "2026-07-01"}');
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_one_dup_no_eligible_cascade_bar', b.destination_type = 'in_house' and b.reason = 'duplicate_cascade'
      and exists (select 1 from b2b.partner_bars where lead_id = v_lead and reason = 'duplicate' and set_by = 'engine')
      and jsonb_array_length(pg_temp.handoff(v_lead) -> 'already_with_providers') = 1,
    coalesce(b.destination_type, 'none') || ' ' || coalesce(b.reason, '-'));

  -- one proven duplicate plus two technical failures → partners_unreachable (3 partners pushed), no bar
  v_lead := pg_temp.lead('919876519024', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  s := b2b.apply_duplicate(a.id, '{"existing_record_id": "X-3"}');
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  update b2b.allocations set push_attempts = 99 where id = a.id;
  s := b2b.apply_push_error(a.id, 'HTTP 503');
  insert into r values ('b6_failure_result', s = 'failed: re-routed', s);
  a := pg_temp.alloc(v_lead);
  insert into r values ('b6_third_partner_after_failure', a.destination_type = 'partner' and a.partner_id = pg_temp.v('A3')::bigint, coalesce(a.partner_id::text, 'none'));
  perform pg_temp.pushing(a.id);
  update b2b.allocations set push_attempts = 99 where id = a.id;
  s := b2b.apply_push_error(a.id, 'HTTP 503');
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_dup_two_failures_unreachable_no_bar', b.destination_type = 'in_house' and b.reason = 'partners_unreachable'
      and not exists (select 1 from b2b.partner_bars where lead_id = v_lead), coalesce(b.destination_type, 'none') || ' ' || coalesce(b.reason, '-'));

  -- one rejection, then the only other partner is at its cap → no_capacity (cause caps), no bar
  v_lead := pg_temp.lead('919876519025', 'ZZApCap');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  insert into r values ('b6_cap_partner_not_first', a.partner_id = pg_temp.v('A1')::bigint, coalesce(a.partner_id::text, 'none'));
  perform pg_temp.pushing(a.id);
  s := b2b.apply_rejection(a.id, 'not for us');
  b := pg_temp.alloc(v_lead);
  insert into r values ('b6_reject_then_cap_no_capacity', b.destination_type = 'in_house' and b.reason = 'no_capacity' and b.cause = 'caps'
      and not exists (select 1 from b2b.partner_bars where lead_id = v_lead), coalesce(b.destination_type, 'none') || ' ' || coalesce(b.reason, '-') || ' ' || coalesce(b.cause, '-'));
end $x$;

-- a failed push is not an attempt; the retry schedule totals about 62 minutes (a3_fixed.push_retry_seconds)
do $x$
declare v_lead bigint; a b2b.allocations; s text; i int; v_total numeric := 0; v_steps text := ''; v_gap numeric; b b2b.allocations;
begin
  v_lead := pg_temp.lead('919876519026', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead); perform pg_temp.pushing(a.id);
  for i in 1..5 loop
    update b2b.allocations set push_attempts = i where id = a.id;
    s := b2b.apply_push_error(a.id, 'timeout ' || i);
    select round(extract(epoch from (next_push_at - now()))) into v_gap from b2b.allocations where id = a.id;
    v_total := v_total + v_gap;
    v_steps := v_steps || s || ':' || v_gap::text || ' ';
  end loop;
  insert into r values ('retry_schedule_about_an_hour', v_total between 3600 and 3700 and v_steps like 'retry:10 retry:60 retry:300 retry:900 retry:2400%', v_steps || 'total ' || v_total);
  update b2b.allocations set push_attempts = 6 where id = a.id;
  s := b2b.apply_push_error(a.id, 'timeout 6');
  b := pg_temp.alloc(v_lead);
  insert into r values ('failed_push_not_an_attempt', s = 'failed: re-routed' and b.destination_type = 'partner' and b.partner_id = pg_temp.v('A2')::bigint
      and (select e.payload ->> 'attempts' from b2b.events e where e.type = 'lead.push_failed' and e.allocation_id = a.id) = '6',
    s || ' -> ' || coalesce(b.destination_type, 'none') || ' ' || coalesce(b.partner_id::text, '-'));
end $x$;

-- ======================================================================================================================
-- A mapping for Alpha (stage, field and activity rules), so stage / update / activity events can be tested
-- ======================================================================================================================
do $x$
declare d bigint;
begin
  d := b2b.mapping_draft_start(pg_temp.v('A1')::bigint);
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Dead', 'stage', 'lost', 'lost_reason', 'not interested'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Follow-up', 'stage', 'contacted'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Admission', 'stage', 'enrolled'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Counsellor', 'canonical_key', 'counsellor_name', 'direction', 'in'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Next Call', 'canonical_key', 'next_follow_up_at', 'direction', 'in',
    'transforms', '[{"op":"datetime"}]'::jsonb));
  perform b2b.mapping_rule_save('activity', jsonb_build_object('profile_id', d, 'partner_type', 'Call Log', 'partner_outcome', 'Connected', 'kind', 'call', 'outcome', 'connected'));
  perform b2b.mapping_publish(d, 'm31i after-push test mapping');
  insert into r values ('mapping_published', exists (select 1 from b2b.mapping_profiles where partner_id = pg_temp.v('A1')::bigint and status = 'active'), null);
end $x$;

-- ======================================================================================================================
-- Rulebook test 4: lost on day 0, revived on day 3 → stays with the partner; still lost on day 8 → B2C nurture, barred
-- ======================================================================================================================
do $x$
declare v_lead bigint; a b2b.allocations; x jsonb; s jsonb; v_grace interval;
begin
  -- lead A
  v_lead := pg_temp.lead('919876519030', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  perform pg_temp.pushed(a.id);
  perform pg_temp.accept(a.id);
  perform pg_temp.set('LA', v_lead::text); perform pg_temp.set('LA_alloc', a.id::text);
  insert into r values ('t4_a_accepted_and_witty_quiet', (select status from b2b.allocations where id = a.id) = 'accepted' and public.w2_crm_owned('919876519030'),
    (select status from b2b.allocations where id = a.id));
  x := pg_temp.event(a.id, 'lost', '{"reason": "not interested", "status": "Dead", "sub_status": "No budget"}');
  select * into a from b2b.allocations where id = a.id;
  v_grace := a.lost_grace_until - a.lost_at;
  insert into r values ('t4_a_lost_starts_grace', x ->> 'status' = 'applied' and x ->> 'result' like 'lost: in grace until %'
      and a.status = 'accepted' and a.lost_at is not null and a.lost_revived_at is null and a.lost_count = 1
      and v_grace between interval '6 days 23 hours' and interval '7 days 1 hour' and a.lost_detail ->> 'lost_reason' = 'not interested',
    (x ->> 'result') || ' | ' || a.status || ' grace=' || v_grace::text);
  insert into r select 't4_a_lead_display_lost_pointers_kept', l.stage = 'lost' and l.lost_reason = 'not interested' and l.lost_at is not null
      and l.destination_type = 'partner' and l.allocation_id = a.id and public.w2_crm_owned('919876519030'),
    l.stage || ' ' || coalesce(l.destination_type, '-')
    from public.student_leads l where l.id = v_lead;
  insert into r values ('t4_a_lost_activity_and_event', exists (select 1 from b2b.partner_activities where allocation_id = a.id and kind = 'stage_change' and outcome = 'lost')
      and exists (select 1 from b2b.events e where e.type = 'lead.partner_lost' and e.allocation_id = a.id and (e.payload ->> 'grace_until') is not null)
      and not exists (select 1 from b2b.events e where e.type = 'b2c.lead_handed_off' and e.lead_id = v_lead), null);
  -- B2C sends nothing: no hand-off, and the status-update clock is not owed while in grace (critic: m16 void during grace)
  s := b2b.sla_tick();
  insert into r values ('t4_a_status_update_voided_in_grace', (s ->> 'voided_in_grace')::int >= 1
      and exists (select 1 from b2b.sla_checks where allocation_id = a.id and sla = 'status_update' and status = 'void'), s::text);
  -- a second lost report in the grace merges the detail and keeps the clock
  x := pg_temp.event(a.id, 'lost', '{"reason": "not interested", "sub_status": "Moved"}');
  insert into r values ('t4_a_second_lost_keeps_clock', x ->> 'result' like 'lost: in grace until %'
      and (select lost_count from b2b.allocations where id = a.id) = 1 and (select lost_grace_until from b2b.allocations where id = a.id) = a.lost_grace_until
      and (select lost_detail ->> 'sub_status' from b2b.allocations where id = a.id) = 'Moved', x ->> 'result');
  -- the hand-off refuses before the grace ends
  x := b2b.lost_handoff(a.id);
  insert into r values ('t4_a_handoff_refused_in_grace', not (x ->> 'handed_off')::boolean and x ->> 'why' like 'in grace until%', x ->> 'why');
  -- day 3: the partner reports a contact → back with the partner, no dispute
  update b2b.allocations set lost_at = now() - interval '3 days', lost_grace_until = now() + interval '4 days' where id = a.id;
  update public.student_leads set lost_at = now() - interval '3 days' where id = v_lead;
  x := pg_temp.event(a.id, 'contacted', '{"connected": true, "duration_sec": 120, "direction": "outbound"}', jsonb_build_object('occurred_at', now()));
  select * into a from b2b.allocations where id = a.id;
  insert into r values ('t4_a_revived_on_day_3', x ->> 'status' = 'applied' and x ->> 'result' like 'contact recorded%back with the partner%'
      and a.status = 'accepted' and a.lost_revived_at is not null and a.lost_at is not null
      and jsonb_array_length(a.lost_detail -> 'history') = 1 and (a.lost_detail -> 'history' -> 0 ->> 'why') like 'partner contacted event%',
    (x ->> 'result') || ' | ' || a.status);
  insert into r select 't4_a_stage_restored_no_dispute', l.stage in ('sent_to_partner', 'contacted') and l.lost_reason is null and l.lost_at is null
      and l.destination_type = 'partner' and l.allocation_id = a.id and public.w2_crm_owned('919876519030')
      and not exists (select 1 from b2b.commission_disputes where allocation_id = a.id)
      and exists (select 1 from b2b.events e where e.type = 'lead.partner_revived' and e.allocation_id = a.id and (e.payload ->> 'lost_for_hours')::numeric between 71 and 73)
      and exists (select 1 from b2b.sla_checks where allocation_id = a.id and sla = 'status_update' and status = 'pending'),
    l.stage || ' lost_reason=' || coalesce(l.lost_reason, 'null') || ' lost_at=' || coalesce(l.lost_at::text, 'null') || ' dest=' || coalesce(l.destination_type, 'null')
      || ' owned=' || public.w2_crm_owned('919876519030')::text
      || ' hours=' || coalesce((select e.payload ->> 'lost_for_hours' from b2b.events e where e.type = 'lead.partner_revived' and e.allocation_id = a.id order by e.id desc limit 1), 'no event')
      || ' sla=' || coalesce((select string_agg(sla || ':' || status, ',') from b2b.sla_checks where allocation_id = a.id), 'none')
    from public.student_leads l where l.id = v_lead;
  insert into r values ('t4_a_grace_tick_leaves_it', b2b.lost_grace_tick() = 0 and (select status from b2b.allocations where id = a.id) = 'accepted', null);
end $x$;

do $x$
declare v_lead bigint; a b2b.allocations; h b2b.allocations; x jsonb; p jsonb; n int; bar b2b.partner_bars; d b2b.engine_decisions; l public.student_leads; e jsonb; v_disp bigint;
begin
  -- lead B: accepted, a counsellor owned it (a manual route kept the owner), lost 8 days ago
  v_lead := pg_temp.lead('919876519031', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  perform pg_temp.pushed(a.id);
  perform pg_temp.accept(a.id);
  perform pg_temp.set('LB', v_lead::text); perform pg_temp.set('LB_alloc', a.id::text);
  update public.student_leads set owner_user_id = 'aaaaaaaa-0000-0000-0000-0000000000f9', team_id = 7, assigned_at = now() where id = v_lead;
  x := pg_temp.event(a.id, 'lost', '{"reason": "joined elsewhere", "status": "Closed Lost"}');
  update b2b.allocations set lost_at = now() - interval '8 days', lost_grace_until = now() - interval '1 day' where id = a.id;
  update public.student_leads set lost_at = now() - interval '8 days' where id = v_lead;
  insert into r values ('t4_b_lost_owned_and_quiet', x ->> 'result' like 'lost: in grace until %' and public.w2_crm_owned('919876519031'), x ->> 'result');
  perform set_config('b2b.actor', 'system', true);
  n := b2b.lost_grace_tick();
  select * into a from b2b.allocations where id = a.id;
  h := pg_temp.alloc(v_lead);
  select * into l from public.student_leads where id = v_lead;
  select * into bar from b2b.partner_bars where lead_id = v_lead;
  select * into d from b2b.engine_decisions where id = h.engine_decision_id;
  p := pg_temp.handoff(v_lead);
  insert into r values ('t4_b_grace_tick_hands_off', n = 1 and a.status = 'closed' and a.outcome = 'lost' and a.outcome_at is not null,
    n::text || ' ' || a.status || '/' || coalesce(a.outcome, '-'));
  insert into r values ('t4_b_nurture_partner_lost', h.destination_type = 'in_house' and h.status = 'handed_off' and h.reason = 'partner_lost' and h.b2c_lane = 'nurture'
      and h.mode = 'fallback' and h.origin = 'auto' and h.attempt_no = a.attempt_no + 1 and h.reference = 'EDW-' || h.id
      and l.destination_type = 'in_house' and l.partner_id is null and l.allocation_reason = 'partner_lost' and l.stage = 'lost',
    coalesce(h.destination_type, 'none') || ' ' || coalesce(h.reason, '-') || ' ' || coalesce(h.b2c_lane, '-') || ' origin=' || coalesce(h.origin, '-'));
  insert into r values ('t4_b_decision_grace', d.reason = 'partner_lost' and d.how = 'grace' and d.mode = 'fallback' and d.b2c_lane = 'nurture' and d.destination_type = 'in_house',
    coalesce(d.reason, '-') || ' how=' || coalesce(d.how, '-'));
  insert into r values ('t4_b_unassigned_owner_cleared', l.owner_user_id is null and l.team_id is null and l.assigned_at is null and not public.w2_crm_owned('919876519031'),
    coalesce(l.owner_user_id::text, 'null') || ' owned=' || public.w2_crm_owned('919876519031')::text);
  insert into r values ('t4_b_lost_bar_grace', bar.reason = 'lost' and bar.set_by = 'grace' and bar.allocation_id = h.id
      and (bar.providers -> 0 ->> 'partner_id')::bigint = pg_temp.v('A1')::bigint and bar.providers -> 0 ->> 'lost_reason' = 'joined elsewhere',
    coalesce(bar.reason, 'no bar') || ' ' || coalesce(bar.set_by, '-'));
  insert into r values ('t4_b_handoff_payload', p -> 'handling' ->> 'assignment' = 'unassigned_until_interest' and p -> 'handling' ->> 'job' = 'nurture'
      and p -> 'handling' ->> 'previous_owner' = 'aaaaaaaa-0000-0000-0000-0000000000f9'
      and (p ->> 'nurture_first_message_after_days')::int = 14
      and (p ->> 'nurture_first_message_at')::timestamptz = h.created_at + interval '14 days'
      and (p -> 'lost' ->> 'partner_id')::bigint = pg_temp.v('A1')::bigint and p -> 'lost' ->> 'lost_reason' = 'joined elsewhere'
      and (p -> 'lost' ->> 'grace_ended_at') is not null and (p -> 'partner_bar' ->> 'reason') = 'lost' and (p -> 'hold' ->> 'kind') = 'barred'
      and p ->> 'reason' = 'partner_lost' and (p ->> 'contract_version') = '3',
    left(p::text, 400));
  -- day 9: the partner reports activity on the lead that moved to B2C → a late-activity dispute, nothing moves
  x := pg_temp.event(a.id, 'activity', '{"type": "Call Log", "outcome": "Connected"}', jsonb_build_object('occurred_at', now()));
  select id into v_disp from b2b.commission_disputes where allocation_id = a.id and kind = 'late_activity_after_lost' and status = 'open';
  insert into r values ('t4_b_late_activity_dispute', x ->> 'status' = 'applied' and x ->> 'result' = 'dispute opened: activity after the lead moved to B2C'
      and v_disp is not null and (select partner_event_id from b2b.commission_disputes where id = v_disp) = (x ->> 'event_id')::bigint
      and exists (select 1 from b2b.partner_activities where allocation_id = a.id and partner_event_id = (x ->> 'event_id')::bigint and kind = 'call')
      and exists (select 1 from b2b.events e where e.type = 'alert.commission_dispute' and e.allocation_id = a.id and e.payload ->> 'kind' = 'late_activity_after_lost')
      and (select destination_type from public.student_leads where id = v_lead) = 'in_house'
      and (select status from b2b.allocations where id = a.id) = 'closed',
    (x ->> 'result') || ' dispute=' || coalesce(v_disp::text, 'none'));
  -- an enrolment after the grace books no earnings: it joins the dispute
  e := b2b.enrollment_record(a.id, jsonb_build_object('enrolled_on', current_date, 'fee_amount_inr', 100000), 'admin');
  insert into r values ('t4_b_enrolment_after_grace_disputed', e ->> 'status' = 'disputed' and (e ->> 'dispute_id')::bigint = v_disp
      and not exists (select 1 from public.enrollments where allocation_id = a.id)
      and (select jsonb_array_length(also) from b2b.commission_disputes where id = v_disp) = 1,
    e::text);
  -- the lost lead is barred: no manual route, 422 for the API, re-enquiries stay with B2C (test 9)
  insert into r values ('t9_lost_route_to_partners_refused', pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_lead, 'manual try after the grace')) like '22023 partner_barred:%',
    pg_temp.err(format('select b2b.route_to_partners_core(%s, %L)', v_lead, 'manual try after the grace')));
  x := b2b.api_route_to_partners('eb2b_m31itest_key_0001', v_lead, 'manual try after the grace');
  insert into r values ('t9_lost_api_422_partner_barred', (x ->> 'status') = '422' and x ->> 'error_code' = 'partner_barred', x::text);
  x := pg_temp.decide(v_lead, false);
  insert into r values ('t9_lost_reenquiry_stays_with_b2c', x ->> 'outcome' = 're-enquired' and (x -> 'bar' ->> 'reason') = 'lost', (x ->> 'outcome') || ' ' || coalesce(x ->> 'destination', '-'));
  -- a 'lost' reported again after the hand-off is just ignored, not a dispute
  x := pg_temp.event(a.id, 'lost', '{"reason": "still lost"}');
  insert into r values ('t4_b_lost_again_ignored', x ->> 'status' = 'ignored' and x ->> 'result' like 'ignored:%', x ->> 'result');
end $x$;

-- grace edge cases (critics B7, B8, B11, D35)
do $x$
declare v_lead bigint; a b2b.allocations; x jsonb; e jsonb; s text; v_alloc bigint;
begin
  -- an enrolment reported for a lost-in-grace allocation revives it and books expected earnings; no bar later
  v_alloc := pg_temp.accepted_lead('919876519032', 'ZZApDup');
  -- (sent two days ago: m20b compares the enrolment date with the allocation's India-time date)
  update b2b.allocations set created_at = now() - interval '2 days', pushed_at = now() - interval '2 days', accepted_at = now() - interval '2 days' where id = v_alloc;
  select * into a from b2b.allocations where id = v_alloc;
  x := pg_temp.event(a.id, 'lost', '{"reason": "not reachable"}');
  e := b2b.enrollment_record(a.id, jsonb_build_object('enrolled_on', current_date, 'fee_amount_inr', 100000), 'admin');
  select * into a from b2b.allocations where id = a.id;
  insert into r values ('grace_enrolment_revives_and_earns', (e ->> 'existing')::boolean is false and (e ->> 'id') is not null
      and a.lost_revived_at is not null and a.status = 'accepted'
      and exists (select 1 from b2b.earnings x where x.enrollment_id = (e ->> 'id')::bigint and x.kind = 'commission' and x.status = 'expected' and x.net_inr = 25000)
      and (select stage from public.student_leads where id = a.lead_id) = 'enrolled'
      and b2b.lost_grace_tick() = 0 and not exists (select 1 from b2b.partner_bars where lead_id = a.lead_id),
    e::text);

  -- an 'update' that only sets fields does not revive; one that schedules a future follow-up does
  v_alloc := pg_temp.accepted_lead('919876519033', 'ZZApDup');
  x := pg_temp.event(v_alloc, 'lost', '{"reason": "no answer"}');
  x := pg_temp.event(v_alloc, 'update', '{"fields": {"Counsellor": "Riya"}}');
  insert into r values ('grace_field_only_update_no_revive', x ->> 'status' = 'applied' and x ->> 'result' = 'fields updated'
      and (select lost_revived_at from b2b.allocations where id = v_alloc) is null
      and (select partner_fields ->> 'counsellor_name' from b2b.allocations where id = v_alloc) = 'Riya', x ->> 'result');
  x := pg_temp.event(v_alloc, 'update', jsonb_build_object('fields', jsonb_build_object('Next Call', to_char((now() + interval '2 days') at time zone 'Asia/Kolkata', 'DD/MM/YYYY HH24:MI'))));
  insert into r values ('grace_future_followup_revives', x ->> 'status' = 'applied' and x ->> 'result' like 'fields updated%back with the partner%'
      and (select lost_revived_at from b2b.allocations where id = v_alloc) is not null
      and (select next_task_due_at > now() from public.student_leads where id = (select lead_id from b2b.allocations where id = v_alloc)), x ->> 'result');

  -- a mapped stage: 'Dead' starts the grace (critic B11), 'Follow-up' revives and is applied without the forward-only check
  v_alloc := pg_temp.accepted_lead('919876519034', 'ZZApDup');
  x := pg_temp.event(v_alloc, 'stage', '{"stage": "Dead", "sub_stage": "Budget"}');
  select * into a from b2b.allocations where id = v_alloc;
  insert into r values ('grace_mapped_lost_result', x ->> 'status' = 'applied' and x ->> 'result' like 'lost: in grace until %' and a.lost_at is not null
      and a.lost_detail ->> 'lost_reason' = 'not interested' and a.lost_detail ->> 'status' = 'Dead'
      and exists (select 1 from b2b.partner_activities where allocation_id = a.id and kind = 'stage_change' and outcome = 'lost'
                    and partner_event_id = (x ->> 'event_id')::bigint)
      and (select stage from public.student_leads where id = a.lead_id) = 'lost', x ->> 'result');
  x := pg_temp.event(v_alloc, 'stage', '{"stage": "Follow-up"}');
  select * into a from b2b.allocations where id = v_alloc;
  insert into r values ('grace_other_stage_revives', x ->> 'status' = 'applied' and x ->> 'result' like 'stage contacted%back with the partner%'
      and a.lost_revived_at is not null and (select stage from public.student_leads where id = a.lead_id) = 'contacted'
      and not exists (select 1 from b2b.commission_disputes where allocation_id = a.id), x ->> 'result');
  -- a lost report after a revival starts a fresh 7 days
  x := pg_temp.event(v_alloc, 'lost', '{"reason": "again"}');
  select * into a from b2b.allocations where id = v_alloc;
  insert into r values ('grace_second_loss_fresh_clock', a.lost_count = 2 and a.lost_revived_at is null and a.lost_grace_until > now() + interval '6 days'
      and jsonb_array_length(a.lost_detail -> 'history') = 1, 'count=' || a.lost_count);

  -- only a lead the partner holds can be marked lost
  v_lead := pg_temp.lead('919876519035', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  x := b2b.apply_partner_lost(a.id, '{"lost_reason": "x"}');
  s := pg_temp.err(format('select b2b.allocation_partner_lost(%s, %L::jsonb)', a.id, '{}'));
  insert into r values ('lost_needs_pushed_or_accepted', x ->> 'status' = 'ignored' and x ->> 'why' like '%queued%' and s like '22023 %queued%', (x ->> 'why') || ' | ' || s);
  insert into r values ('lost_unknown_allocation_ignored', (b2b.apply_partner_lost(-1, '{}') ->> 'status') = 'ignored', null);

  -- the Admin's re-route is refused while lost in grace (critic B7; m31l)
  if pg_temp.stub('b2b.reroute_check(bigint)') or pg_temp.stub('b2b.reroute_lead(bigint,text,text,text)') then
    insert into r values ('grace_admin_reroute_refused', true, 'skipped: reroute_check / reroute_lead are pre-m31l');
  else
    v_alloc := pg_temp.accepted_lead('919876519036', 'ZZApDup');
    x := pg_temp.event(v_alloc, 'lost', '{"reason": "ghosted"}');
    x := b2b.reroute_check(v_alloc);
    s := pg_temp.err(format('select b2b.reroute_lead(%s, %L, %L)', (select lead_id from b2b.allocations where id = v_alloc), 'b2c', 'trying during the grace'));
    insert into r values ('grace_admin_reroute_refused', not (x ->> 'allowed')::boolean and (x ->> 'lost_in_grace')::boolean and s like '22023 %', (x ->> 'why') || ' | ' || s);
  end if;
end $x$;

-- ======================================================================================================================
-- Disputes and notifications (PART 5.2, 5.8, D20; critics B10, m9)
-- ======================================================================================================================
do $x$
declare v_alloc bigint; a b2b.allocations; s text; v_disp bigint; e jsonb; v_lead bigint; n int;
begin
  -- a duplicate 2 h after acceptance opens a dispute with a kind and cancels the scheduled message
  v_alloc := pg_temp.accepted_lead('919876519040', 'ZZApDup');
  insert into r values ('notif_scheduled_on_acceptance', exists (select 1 from b2b.student_notifications where allocation_id = v_alloc and channel = 'whatsapp' and kind = 'accepted' and status = 'scheduled'),
    (select string_agg(channel || ':' || status || ':' || coalesce(error, ''), ' ') from b2b.student_notifications where allocation_id = v_alloc));
  update b2b.allocations set accepted_at = now() - interval '2 hours' where id = v_alloc;
  s := b2b.apply_partner_duplicate(v_alloc, '{"existing_record_id": "A1-999", "existing_created_at": "2026-09-15T10:00:00+05:30"}');
  select id into v_disp from b2b.commission_disputes where allocation_id = v_alloc and status = 'open';
  select * into a from b2b.allocations where id = v_alloc;
  insert into r values ('dispute_after_acceptance_opened', s like 'dispute: opened%' and v_disp is not null and a.status = 'accepted'
      and (select kind from b2b.commission_disputes where id = v_disp) = 'duplicate_after_acceptance'
      and (select existing_created_on from b2b.commission_disputes where id = v_disp) = '2026-09-15T10:00:00+05:30'::timestamptz
      and (select existing_record_id from b2b.commission_disputes where id = v_disp) = 'A1-999'
      and exists (select 1 from b2b.events x where x.type = 'alert.commission_dispute' and x.allocation_id = v_alloc and x.payload ->> 'kind' = 'duplicate_after_acceptance'
                    and (x.payload ->> 'dispute_id')::bigint = v_disp),
    s);
  insert into r values ('dispute_cancels_student_message', (select status || ':' || coalesce(error, '') from b2b.student_notifications where allocation_id = v_alloc and channel = 'whatsapp')
      = 'cancelled:duplicate claimed after acceptance', null);
  s := b2b.apply_partner_duplicate(v_alloc, '{"existing_record_id": "A1-1000"}');
  insert into r values ('dispute_second_claim_appended', s = 'dispute: claim added to the open dispute'
      and (select jsonb_array_length(also) from b2b.commission_disputes where id = v_disp) = 1
      and (select count(*) from b2b.commission_disputes where allocation_id = v_alloc) = 1, s);
  -- the push overview carries the kind
  insert into r values ('push_overview_dispute_kind', exists (select 1 from jsonb_array_elements(b2b.push_overview(pg_temp.v('A1')::bigint) -> 'disputes') d
                                                            where (d ->> 'id')::bigint = v_disp and d ->> 'kind' = 'duplicate_after_acceptance'), null);
  -- upheld: no commission, excluded from the outcomes
  perform b2b.dispute_resolve(v_disp, true, 'the partner had this student first');
  e := b2b.enrollment_record(v_alloc, jsonb_build_object('enrolled_on', current_date, 'fee_amount_inr', 100000), 'admin');
  insert into r values ('dispute_upheld_no_earnings', (select outcome from b2b.allocations where id = v_alloc) = 'duplicate_upheld'
      and e ->> 'status' = 'no_earnings' and e ->> 'why' = 'duplicate_upheld'
      and not exists (select 1 from public.enrollments where allocation_id = v_alloc)
      and not exists (select 1 from b2b.allocation_outcomes() o where o.allocation_id = v_alloc)
      and (select status from b2b.allocations where id = v_alloc) = 'accepted',
    e::text);
  -- notify_accepted on a disputed allocation queues nothing new
  insert into r values ('disputed_no_new_message', b2b.notify_accepted(v_alloc) = 0, null);

  -- at 25 h the claim is logged late, no dispute
  v_alloc := pg_temp.accepted_lead('919876519041', 'ZZApDup');
  update b2b.allocations set accepted_at = now() - interval '25 hours' where id = v_alloc;
  s := b2b.apply_partner_duplicate(v_alloc, '{"existing_record_id": "A1-2000"}');
  insert into r values ('late_duplicate_logged', s like 'late duplicate:%' and not exists (select 1 from b2b.commission_disputes where allocation_id = v_alloc)
      and exists (select 1 from b2b.events x where x.type = 'partner.late_duplicate_rejected' and x.allocation_id = v_alloc)
      and (select status from b2b.allocations where id = v_alloc) = 'accepted', s);

  -- no acceptance message while lost in grace: lost inside the hold window, accepted later by the hold tick
  v_lead := pg_temp.lead('919876519042', 'ZZApDup');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  perform pg_temp.pushed(a.id);
  e := b2b.apply_partner_lost(a.id, '{"lost_reason": "changed mind"}');
  perform pg_temp.accept(a.id);
  insert into r values ('no_message_while_lost_in_grace', e ->> 'status' = 'grace' and (select status from b2b.allocations where id = a.id) = 'accepted'
      and (select count(*) from b2b.student_notifications where allocation_id = a.id and status = 'scheduled') = 0
      and (select bool_and(status = 'skipped' and error = 'lost, in grace') from b2b.student_notifications where allocation_id = a.id),
    (select string_agg(channel || ':' || status || ':' || coalesce(error, ''), ' ') from b2b.student_notifications where allocation_id = a.id));

  -- an upheld duplicate dispute cancels a reported enrolment and voids its expected line
  v_alloc := pg_temp.accepted_lead('919876519043', 'ZZApDup');
  update b2b.allocations set created_at = now() - interval '2 days', pushed_at = now() - interval '2 days' where id = v_alloc;
  e := b2b.enrollment_record(v_alloc, jsonb_build_object('enrolled_on', current_date, 'fee_amount_inr', 100000), 'admin');
  update b2b.allocations set accepted_at = now() - interval '3 hours' where id = v_alloc;
  s := b2b.apply_partner_duplicate(v_alloc, '{"existing_id": "A1-3000", "created_at": "2026-09-20"}');
  select id into v_disp from b2b.commission_disputes where allocation_id = v_alloc and status = 'open';
  perform b2b.dispute_resolve(v_disp, true, 'upheld: the partner had the student');
  insert into r values ('dispute_upheld_cancels_enrolment', (select status from public.enrollments where id = (e ->> 'id')::bigint) = 'cancelled'
      and (select bool_and(status = 'void') from b2b.earnings where enrollment_id = (e ->> 'id')::bigint)
      and exists (select 1 from b2b.events x where x.type = 'dispute.resolved' and x.allocation_id = v_alloc and (x.payload ->> 'enrolments_cancelled')::int = 1
                    and x.payload ->> 'kind' = 'duplicate_after_acceptance'),
    (select status from public.enrollments where id = (e ->> 'id')::bigint));
end $x$;

-- a second partner in the same cycle: 'reroute_update' instead of a second welcome (D20, critic B10)
do $x$
declare v_lead bigint; a b2b.allocations; b b2b.allocations; x jsonb; i int; v_phone text;
begin
  for i in 1..2 loop
    v_phone := '91987651905' || i;
    v_lead := pg_temp.lead(v_phone, 'ZZApDup');
    perform pg_temp.decide(v_lead, true);
    a := pg_temp.alloc(v_lead);
    perform pg_temp.pushed(a.id);
    perform pg_temp.accept(a.id);
    update b2b.student_notifications set status = 'sent', sent_at = now() where allocation_id = a.id and channel = 'whatsapp' and status = 'scheduled';
    -- the Admin recalls Alpha and sends the lead to the next partner (as reroute_lead does)
    perform set_config('b2b.actor', 'engine', true);
    update b2b.allocations set status = 'recalled', outcome = 'recalled', outcome_at = now(), recall_reason = 'm31i reroute test' where id = a.id;
    update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null, allocation_reason = null, updated_by = 'b2b' where id = v_lead;
    x := pg_temp.decide(v_lead, true, 'reroute', 'm31i reroute test');
    b := pg_temp.alloc(v_lead);
    insert into r values ('reroute_excludes_recalled_partner_' || i, b.destination_type = 'partner' and b.partner_id = pg_temp.v('A2')::bigint and b.origin = 'reroute' and b.mode = 'manual',
      coalesce(b.destination_type, 'none') || ' ' || coalesce(b.partner_id::text, '-') || ' ' || coalesce(b.origin, '-'));
    update b2b.partners set notify_enabled = true where id = pg_temp.v('A2')::bigint;
    perform pg_temp.pushed(b.id);
    perform pg_temp.accept(b.id);
    if i = 1 then
      insert into r values ('reroute_update_skipped_without_template',
        (select kind || ':' || status || ':' || coalesce(error, '') from b2b.student_notifications where allocation_id = b.id and channel = 'whatsapp')
          = 'reroute_update:skipped:no active template',
        (select string_agg(kind || ':' || status || ':' || coalesce(error, ''), ' ') from b2b.student_notifications where allocation_id = b.id));
      update b2b.message_templates set status = 'active' where kind = 'reroute_update' and channel = 'whatsapp' and language = 'en';
    else
      insert into r values ('reroute_update_queued_with_template',
        (select kind || ':' || status from b2b.student_notifications where allocation_id = b.id and channel = 'whatsapp') = 'reroute_update:scheduled'
          and (select variables ->> 'partner_display_name' from b2b.student_notifications where allocation_id = b.id and channel = 'whatsapp') = 'ZZ Beta',
        (select string_agg(kind || ':' || status || ':' || coalesce(error, ''), ' ') from b2b.student_notifications where allocation_id = b.id));
    end if;
  end loop;
end $x$;

-- notify_tick cancels a due message once the lead is lost in grace
do $x$
declare v_alloc bigint; x jsonb;
begin
  v_alloc := pg_temp.accepted_lead('919876519053', 'ZZApDup');
  update b2b.student_notifications set scheduled_for = now() - interval '1 minute' where allocation_id = v_alloc and status = 'scheduled';
  update b2b.allocations set lost_at = now(), lost_grace_until = now() + interval '7 days', lost_count = 1 where id = v_alloc;
  x := b2b.notify_tick();
  insert into r values ('notify_tick_cancels_in_grace', (select status || ':' || coalesce(error, '') from b2b.student_notifications where allocation_id = v_alloc and channel = 'whatsapp')
      = 'cancelled:lost, in grace', x::text);
end $x$;

-- ======================================================================================================================
-- Partner settings: derived hold, fixed duplicate window, SLA floors, criteria validation, push options, the checklist
-- ======================================================================================================================
do $x$
declare x jsonb; p b2b.partners; e text; v_id bigint; st jsonb;
begin
  x := b2b.partner_save('{"slug": "zz-ap-sync", "name": "ZZ Sync CRM", "dedupe_mode": "sync", "dedupe_confirmed": true, "hold_minutes": 15, "duplicate_window_hours": 48,
                         "push_options": {"interests_array": true}, "lead_criteria": {"states_include": ["Delhi"], "unknown": "pass", "min_work_experience_years": 2}}');
  select * into p from b2b.partners where id = (x ->> 'id')::bigint;
  insert into r values ('partner_save_sync_confirmed_zero_hold', p.dedupe_mode = 'sync' and p.hold_minutes = 0 and p.duplicate_window_hours = 24 and p.dedupe_confirmed_at is not null
      and (p.push_options ->> 'interests_array')::boolean and p.lead_criteria ->> 'unknown' = 'pass',
    p.dedupe_mode || ' hold=' || p.hold_minutes || ' win=' || p.duplicate_window_hours);
  insert into r values ('checklist_dedupe_done', exists (select 1 from jsonb_array_elements(b2b.partner_checklist(p)) c where c ->> 'key' = 'dedupe' and (c ->> 'done')::boolean), null);
  x := b2b.partner_save('{"slug": "zz-ap-async", "name": "ZZ Async", "dedupe_mode": "async", "hold_minutes": 5, "duplicate_window_hours": 1}');
  select * into p from b2b.partners where id = (x ->> 'id')::bigint;
  insert into r values ('partner_save_async_thirty_minutes', p.dedupe_mode = 'async' and p.hold_minutes = 30 and p.duplicate_window_hours = 24 and p.dedupe_confirmed_at is null
      and p.push_options = '{}'::jsonb, p.dedupe_mode || ' hold=' || p.hold_minutes);
  x := b2b.partner_save('{"slug": "zz-ap-sync2", "name": "ZZ Sync Generic", "dedupe_mode": "sync"}');
  select * into p from b2b.partners where id = (x ->> 'id')::bigint;
  insert into r values ('checklist_dedupe_pending_unconfirmed_sync', p.hold_minutes = 0 and p.dedupe_confirmed_at is null
      and exists (select 1 from jsonb_array_elements(b2b.partner_checklist(p)) c where c ->> 'key' = 'dedupe' and not (c ->> 'done')::boolean), null);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-sla", "name": "ZZ Slow", "sla": {"first_contact_hours": 3}}') $q$);
  insert into r values ('partner_save_refuses_looser_first_contact', e like '22023 %first-contact SLA%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-sla", "name": "ZZ Slow", "sla": {"status_update_days": 10}}') $q$);
  insert into r values ('partner_save_refuses_looser_status_update', e like '22023 %status-update SLA%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-sla", "name": "ZZ Slow", "sla": {"proof_days": 14}}') $q$);
  insert into r values ('partner_save_refuses_looser_proof', e like '22023 %proof%', e);
  x := b2b.partner_save('{"slug": "zz-ap-sla", "name": "ZZ Fast", "sla": {"first_contact_hours": 1, "status_update_days": 3, "proof_days": 5}}');
  insert into r values ('partner_save_accepts_stricter_sla', (select (sla ->> 'first_contact_hours')::int from b2b.partners where id = (x ->> 'id')::bigint) = 1, null);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crit", "name": "ZZ Crit", "lead_criteria": {"unknown": "maybe"}}') $q$);
  insert into r values ('criteria_unknown_pass_or_fail', e like '22023 %pass%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crit", "name": "ZZ Crit", "lead_criteria": {"min_academic_pct": 150}}') $q$);
  insert into r values ('criteria_pct_range', e like '22023 %0 to 100%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crit", "name": "ZZ Crit", "lead_criteria": {"cities_include": "Delhi"}}') $q$);
  insert into r values ('criteria_lists', e like '22023 %list%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crit", "name": "ZZ Crit", "lead_criteria": {"colour": "blue"}}') $q$);
  insert into r values ('criteria_unknown_key', e like '22023 unknown lead criterion%', e);
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crit", "name": "ZZ Crit", "push_options": {"interests_array": "yes"}}') $q$);
  insert into r values ('push_options_boolean', e like '22023 %interests_array%', e);
  -- a CRM adapter is 'sync' only with the confirmation (D37)
  e := pg_temp.err($q$ select b2b.partner_save('{"slug": "zz-ap-crm", "name": "ZZ CRM", "adapter_type": "inhouse", "dedupe_mode": "sync"}') $q$);
  insert into r values ('crm_adapter_sync_needs_confirmation', e like '22023 confirm that the CRM rejects duplicates%', e);
  x := b2b.partner_save('{"slug": "zz-ap-crm", "name": "ZZ CRM", "adapter_type": "inhouse", "dedupe_mode": "sync", "dedupe_confirmed": true}');
  v_id := (x ->> 'id')::bigint;
  insert into r values ('crm_adapter_sync_confirmed', (select hold_minutes from b2b.partners where id = v_id) = 0, null);
  -- the adapter settings follow the confirmation: unconfirmed → async with the 30-minute hold; confirmed → sync, 0 minutes
  st := b2b.partner_adapter_save(v_id, '{"env": "live", "settings": {"create_url": "https://crm.zz-ap.example.invalid/leads", "auth_type": "none"}, "dedupe_confirmed": false}');
  select * into p from b2b.partners where id = v_id;
  insert into r values ('adapter_save_unconfirmed_async', p.dedupe_mode = 'async' and p.hold_minutes = 30 and p.dedupe_confirmed_at is null and p.duplicate_window_hours = 24,
    p.dedupe_mode || ' hold=' || p.hold_minutes);
  st := b2b.partner_adapter_save(v_id, '{"env": "live", "dedupe_confirmed": true}');
  select * into p from b2b.partners where id = v_id;
  insert into r values ('adapter_save_confirmed_sync', p.dedupe_mode = 'sync' and p.hold_minutes = 0 and p.dedupe_confirmed_at is not null, p.dedupe_mode || ' hold=' || p.hold_minutes);
end $x$;

-- ======================================================================================================================
-- The push note lists every interest; interests[] only with push_options.interests_array (PART 4, D44)
-- ======================================================================================================================
do $x$
declare v_lead bigint; a b2b.allocations; j jsonb;
begin
  v_lead := pg_temp.lead('919876519060', 'ZZApDup');
  insert into b2b.lead_interests (lead_id, position, course_text, course_key, source) values (v_lead, 2, 'ZZApOnly', 'zzaponly', 'admin');
  perform pg_temp.decide(v_lead, true);
  a := pg_temp.alloc(v_lead);
  j := b2b.push_payload_base(a);
  insert into r values ('push_note_lists_all_interests', a.partner_id = pg_temp.v('A1')::bigint and a.interest_rank = 1
      and j ->> 'note' like 'Interested in ZZApDup%Also asked about: ZZApOnly%' and length(j ->> 'note') <= 500 and not (j ? 'interests'),
    j ->> 'note');
  update b2b.partners set push_options = '{"interests_array": true}' where id = pg_temp.v('A1')::bigint;
  j := b2b.push_payload_base(a);
  insert into r values ('push_interests_array_opt_in', jsonb_array_length(j -> 'interests') = 2 and (j -> 'interests' -> 0 ->> 'routed')::boolean
      and j -> 'interests' -> 1 ->> 'course' = 'ZZApOnly' and (j -> 'interests' -> 1 ->> 'rank') = '2', j -> 'interests' #>> '{}');
  update b2b.partners set push_options = '{}' where id = pg_temp.v('A1')::bigint;
end $x$;

-- engine functions are not callable by signed-in users or anon
insert into r select 'engine_locked', not has_function_privilege('authenticated', 'b2b.lost_handoff(bigint)', 'execute')
    and not has_function_privilege('anon', 'b2b.lost_grace_tick()', 'execute')
    and not has_function_privilege('authenticated', 'b2b.partner_lost_revive(bigint, bigint, text)', 'execute')
    and not has_function_privilege('authenticated', 'b2b.apply_partner_lost(bigint, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'b2b.allocation_partner_lost(bigint, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'b2b.dispute_resolve(bigint, boolean, text)', 'execute'), null;

select * from r order by name;
rollback;
