-- M31 scoring (Addendum 3 PART 4 Step 3) in PGlite or on STAGING, rolled back. Fixtures are built in the transaction: a ZZ
-- catalogue (one course per test group, so the staging partners never compete), partners with their rates and offers,
-- received allocations, activities, SLA checks and enrolments, then b2b.stats_refresh(). Covers rulebook tests 5, 7, 11,
-- 12, 13 and 14, the design's 'Lane and ties', 'Stages and segments' and 'Other' rows, and the review findings C1, C4,
-- C16, C45, C46, C47, C54, C56, C60, C61, C112, C123, C124, C125 and C128 that name this file. Checks of functions that
-- m31l / m31m replace (decision_replay, the Admin saves, routing_segment) are recorded as ok with detail 'skipped' until
-- those migrations are applied. Seeds are forced through the GUC b2b.route_seed. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
create temp sequence fxcycle;   -- one open allocation per lead and cycle: every fixture allocation gets its own cycle
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f8","role":"authenticated","aal":"aal2","email":"m31-admin@test.local"}', true)
$f$;
create function pg_temp.cand(x jsonb, pid text) returns jsonb language sql as $f$
  select c from jsonb_array_elements(x -> 'candidates') c where c ->> 'partner_id' = pid limit 1 $f$;
create function pg_temp.has(sig text, marker text) returns boolean language sql as $f$
  select coalesce((select prosrc ~ marker from pg_proc where oid = to_regprocedure(sig)), false) $f$;
create function pg_temp.seed_pick(tag text, lo numeric, hi numeric) returns text language sql as $f$
  select '0.' || lpad(i::text, 3, '0') from generate_series(1, 999) i
   where b2b.u01('0.' || lpad(i::text, 3, '0'), tag) >= lo and b2b.u01('0.' || lpad(i::text, 3, '0'), tag) < hi order by i limit 1 $f$;
create function pg_temp.decide(p_lead bigint, p_seed text, p_commit boolean, p_how text default 'auto', p_note text default null) returns jsonb language plpgsql as $f$
begin
  perform set_config('b2b.actor', 'engine', true);
  perform set_config('b2b.route_seed', coalesce(p_seed, ''), true);
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
  insert into b2b.partners (slug, name, display_name, status, daily_cap, monthly_cap, contract_min_monthly, lead_criteria)
  values (p_slug, p_name, p_name, coalesce(p_extra ->> 'status', 'active'), (p_extra ->> 'daily_cap')::int, (p_extra ->> 'monthly_cap')::int,
          (p_extra ->> 'contract_min_monthly')::int, coalesce(p_extra -> 'criteria', '{}'::jsonb))
  returning id into v_id;
  insert into b2b.live_switches (scope, live, reason) values ('partner:' || v_id, true, 'm31 scoring test') on conflict (scope) do update set live = true;
  insert into b2b.partner_programme_versions (partner_id, version_no, status, published_at) values (v_id, 1, 'published', now());
  return v_id;
end $f$;
create function pg_temp.offer(p bigint, p_prog bigint, p_fees jsonb default '{}') returns void language sql as $f$
  insert into b2b.partner_programmes (partner_id, programme_id, program_key, source_version_id, fees)
  select p, p_prog, c.program_key, pv.id, p_fees from public.catalog_programs c, b2b.partner_programme_versions pv where c.id = p_prog and pv.partner_id = p $f$;
create function pg_temp.rate(p bigint, p_type text, p_value numeric, p_tiers jsonb default null, p_gst boolean default false) returns void language sql as $f$
  insert into b2b.rates (scope, partner_id, rate_type, value, tiers, gst_inclusive) values ('partner', p, p_type, p_value, p_tiers, p_gst) $f$;
create function pg_temp.lead(p_phone text, p_course text, p_extra jsonb default '{}') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_strip_nulls(jsonb_build_object('full_name', 'M31 ' || p_phone, 'email', 'm31-' || p_phone || '@test.local', 'interested_course', p_course,
                                                 'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi', 'source', 'website',
                                                 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1') || p_extra)));
  select l.id into v_id from public.student_leads l where l.whatsapp_number = p_phone;
  return v_id;
end $f$;
-- received allocations of a fixture lead (status accepted, pushed/accepted at creation)
create function pg_temp.recv(p bigint, p_seg text, p_n int, p_age interval, p_segx text default null, p_test boolean default false, p_status text default 'accepted') returns void language sql as $f$
  insert into b2b.allocations (lead_id, cycle_no, segment, segment_exact, destination_type, partner_id, status, mode, attempt_no, accepted_at, pushed_at, created_at, is_test, origin)
  select pg_temp.v('FX')::bigint, nextval('fxcycle'), p_seg, p_segx, 'partner', p, p_status, 'commission_first', 1, now() - p_age + interval '1 hour', now() - p_age, now() - p_age, p_test, 'auto'
    from generate_series(1, p_n) $f$;
-- one received allocation pushed at a given moment, returning its id (for activities and SLA checks)
create function pg_temp.alloc_at(p bigint, p_seg text, p_at timestamptz) returns bigint language sql as $f$
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, accepted_at, pushed_at, created_at, is_test, origin)
  values (pg_temp.v('FX')::bigint, nextval('fxcycle'), p_seg, 'partner', p, 'accepted', 'commission_first', 1, p_at + interval '30 minutes', p_at, p_at, false, 'auto') returning id $f$;
create function pg_temp.act(p_alloc bigint, p_kind text, p_outcome text, p_at timestamptz) returns void language sql as $f$
  insert into b2b.partner_activities (allocation_id, lead_id, partner_id, kind, direction, outcome, occurred_at)
  select a.id, a.lead_id, a.partner_id, p_kind, case when p_kind = 'stage_change' then null else 'outbound' end, p_outcome, p_at from b2b.allocations a where a.id = p_alloc $f$;
create function pg_temp.sla(p_alloc bigint, p_sla text, p_due interval, p_met boolean) returns void language sql as $f$
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, met_at, status, breached_at, is_test)
  select a.id, a.lead_id, a.partner_id, p_sla, a.pushed_at, a.pushed_at + p_due, case when p_met then a.pushed_at + p_due / 2 end,
         case when p_met then 'met' else 'breached' end, case when not p_met then a.pushed_at + p_due end, false
    from b2b.allocations a where a.id = p_alloc $f$;
create function pg_temp.ist(p_day date, p_time time) returns timestamptz language sql as $f$ select (p_day + p_time) at time zone 'Asia/Kolkata' $f$;

-- ---------- settings and the admin ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f8', 'm31-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f8', 'm31-admin@test.local');
insert into b2b.live_switches (scope, live, reason) values ('routing', true, 'm31 scoring test') on conflict (scope) do update set live = true;
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"enabled":true,"half_life_days":30,"prior_weight":20,"default_p_enroll":0.05,"consent_policy":"ask","kill_switch":false}'
                                   || jsonb_build_object('effort_factor', (value -> 'effort_factor') || '{"enabled":true}', 'sla_factor', (value -> 'sla_factor') || '{"enabled":true}')
 where key = 'engine';
update b2b.settings set value = value || '{"challenger_share":0.1}' where key = 'ml';
update b2b.ml_models set status = 'retired' where status in ('shadow', 'challenger', 'champion', 'training');
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at)
values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now());
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m31 b2c', '{events}', 'eb2b_m31test', encode(extensions.digest('eb2b_m31test_key_0001', 'sha256'), 'hex'));
select pg_temp.set('seed_hi', pg_temp.seed_pick('explore', 0.2, 1));
select pg_temp.set('seed_lo', pg_temp.seed_pick('explore', 0, 0.2));
select pg_temp.set('seed_hold', pg_temp.seed_pick('holdout', 0, 0.5));
select pg_temp.set('seed_champ', (select '0.' || lpad(i::text, 3, '0') from generate_series(1, 999) i
                                   where b2b.u01('0.' || lpad(i::text, 3, '0'), 'challenger') >= 0.1 and b2b.u01('0.' || lpad(i::text, 3, '0'), 'holdout') >= 0.5
                                     and b2b.u01('0.' || lpad(i::text, 3, '0'), 'explore') >= 0.2 order by i limit 1));
select pg_temp.set('seed_chall', pg_temp.seed_pick('challenger', 0, 0.1));

-- ---------- catalogue: one course per test group ----------
select pg_temp.set('U1', pg_temp.uni('ZZ Scoring University', 'ZZSU')::text);
select pg_temp.set('U2', pg_temp.uni('ZZ Other University', 'ZZOU')::text);
select pg_temp.set('P7', pg_temp.prog('zz-t7', 'ZZSeven', 'zzseven', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P11', pg_temp.prog('zz-t11', 'ZZEleven', 'zzeleven', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P12', pg_temp.prog('zz-t12', 'ZZTwelve', 'zztwelve', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P13', pg_temp.prog('zz-t13', 'ZZThirteen', 'zzthirteen', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P14', pg_temp.prog('zz-t14', 'ZZFourteen', 'zzfourteen', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P5A', pg_temp.prog('zz-t5a', 'ZZNobody', 'zznobody', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('P5B', pg_temp.prog('zz-t5b', 'ZZSecond', 'zzsecond', 'UG', 'Online', pg_temp.v('U1')::bigint, 50000, 150000)::text);
select pg_temp.set('P5C', pg_temp.prog('zz-t5c', 'ZZFive', 'zzfive', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PTIE', pg_temp.prog('zz-tie', 'ZZTie', 'zztie', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PTIE2', pg_temp.prog('zz-tie2', 'ZZTietwo', 'zztietwo', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PEX1', pg_temp.prog('zz-ex-u1', 'ZZExact', 'zzexact', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PEX2', pg_temp.prog('zz-ex-u2', 'ZZExact', 'zzexact', 'PG', 'Online', pg_temp.v('U2')::bigint, 100000, 200000)::text);
select pg_temp.set('PMIN', pg_temp.prog('zz-min', 'ZZMinimum', 'zzminimum', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PRULE', pg_temp.prog('zz-rule', 'ZZRule', 'zzrule', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PNR', pg_temp.prog('zz-norate', 'ZZNorate', 'zznorate', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PMAN', pg_temp.prog('zz-man', 'ZZManual', 'zzmanual', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
select pg_temp.set('PTEN', pg_temp.prog('zz-ten', 'ZZTen', 'zzten', 'PG', 'Online', pg_temp.v('U1')::bigint, 100000, 200000)::text);
-- the fixture lead that owns the received allocations (never routed)
select pg_temp.set('FX', pg_temp.lead('919876531000', 'ZZSeven')::text);

-- ========================================================================================================
-- Test 7: tiered partners at cold start are compared on the middle tier (D28)
-- ========================================================================================================
select pg_temp.set('T1', pg_temp.partner('zz-t7-one', 'ZZ T7 One')::text);
select pg_temp.set('T2', pg_temp.partner('zz-t7-two', 'ZZ T7 Two')::text);
select pg_temp.offer(pg_temp.v('T1')::bigint, pg_temp.v('P7')::bigint);
select pg_temp.offer(pg_temp.v('T2')::bigint, pg_temp.v('P7')::bigint);
select pg_temp.rate(pg_temp.v('T1')::bigint, 'tiered', null, '[{"from_pct":0,"pct":22.42},{"from_pct":7,"pct":20.42},{"from_pct":12,"pct":18.42}]', true);
select pg_temp.rate(pg_temp.v('T2')::bigint, 'tiered', null, '[{"from_pct":0,"pct":25},{"from_pct":7,"pct":19},{"from_pct":12,"pct":15}]', true);
select pg_temp.set('L7', pg_temp.lead('919876531007', 'ZZSeven')::text);
insert into t select 'X7', pg_temp.decide(pg_temp.v('L7')::bigint, '0.5', false)::text;
insert into r select 'test7_middle_tier_wins',
       x ->> 'destination' = 'partner' and x ->> 'partner_id' = pg_temp.v('T1') and x ->> 'stage' = 'A' and x ->> 'scoring_mode' = 'commission_first'
       and (x ->> 'cpe')::numeric = round(20.42 / 100 * 100000 / 1.18, 2)
       and pg_temp.cand(x, pg_temp.v('T1')) -> 'cpe_basis' ->> 'tier_basis' = 'middle'
       and pg_temp.cand(x, pg_temp.v('T2')) -> 'cpe_basis' ->> 'tier_basis' = 'middle'
       and (pg_temp.cand(x, pg_temp.v('T2')) ->> 'cpe')::numeric = round(19.0 / 100 * 100000 / 1.18, 2)
       and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'score')::numeric = (x ->> 'cpe')::numeric,
       coalesce(x ->> 'partner_id', '-') || ' cpe ' || coalesce(x ->> 'cpe', '-') || ' ' || coalesce((pg_temp.cand(x, pg_temp.v('T1')) -> 'cpe_basis')::text, x ->> 'reason')
  from (select pg_temp.v('X7')::jsonb x) z;
-- the literal lane: both partners are under-tested, the highest-CPE one is the score winner, so the lane changes nothing
insert into r select 'lane_x_is_winner_changes_nothing',
       not (x -> 'lane' ->> 'applied')::boolean and (x ->> 'selection_probability')::numeric = 1 and (x ->> 'exploration_share')::numeric = 0
       and (x ->> 'draw') is null and x ->> 'mode' = 'commission_first' and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'under_tested')::boolean
       and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'propensity')::numeric = 1 and (pg_temp.cand(x, pg_temp.v('T2')) ->> 'propensity')::numeric = 0,
       (x -> 'lane')::text || ' ' || (x ->> 'selection_probability')
  from (select pg_temp.v('X7')::jsonb x) z;
insert into r select 'no_pinned_mc_draws_keys', not (x ? 'pinned') and not (x ? 'mc_draws') and not (x ? 'sampled_score') and x ? 'seed_source' and x ->> 'seed_source' = 'forced',
       x ->> 'seed_source' from (select pg_temp.v('X7')::jsonb x) z;
-- variant: 30 matured leads and a conversion in Money -> the projected tier (18.42 at 50% conversion), so T2's middle 19 wins
select pg_temp.recv(pg_temp.v('T1')::bigint, 'zzseven|PG|Online', 30, interval '70 days');
select pg_temp.recv(pg_temp.v('T1')::bigint, 'zzseven|PG|Online', 2, interval '1 hour');
insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
select a.lead_id, a.cycle_no, a.partner_id, a.id, 'verified', 'b2b', (now() at time zone 'Asia/Kolkata')::date
  from b2b.allocations a where a.partner_id = pg_temp.v('T1')::bigint order by a.id desc limit 1;
insert into t select 'X7b', pg_temp.decide(pg_temp.v('L7')::bigint, '0.5', false)::text;
insert into r select 'test7_projected_tier_after_30_matured',
       pg_temp.cand(x, pg_temp.v('T1')) -> 'cpe_basis' ->> 'tier_basis' = 'projected'
       and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'cpe')::numeric = round(18.42 / 100 * 100000 / 1.18, 2)
       and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'n_matured_c')::int = 30 and (pg_temp.cand(x, pg_temp.v('T1')) ->> 'n_received')::int = 32
       and x ->> 'partner_id' = pg_temp.v('T2') and x ->> 'stage' = 'A',
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce((pg_temp.cand(x, pg_temp.v('T1')) -> 'cpe_basis')::text, '-') || ' ' || coalesce(pg_temp.cand(x, pg_temp.v('T1')) ->> 'cpe', '-')
  from (select pg_temp.v('X7b')::jsonb x) z;

-- ========================================================================================================
-- Test 11: Stage A, two partners, the higher CPE wins outside the exploration lane
-- ========================================================================================================
select pg_temp.set('A', pg_temp.partner('zz-t11-a', 'ZZ T11 Alpha')::text);
select pg_temp.set('B', pg_temp.partner('zz-t11-b', 'ZZ T11 Beta')::text);
select pg_temp.offer(pg_temp.v('A')::bigint, pg_temp.v('P11')::bigint);
select pg_temp.offer(pg_temp.v('B')::bigint, pg_temp.v('P11')::bigint);
select pg_temp.rate(pg_temp.v('A')::bigint, 'fixed', 12000);
select pg_temp.rate(pg_temp.v('B')::bigint, 'fixed', 10000);
select pg_temp.recv(pg_temp.v('A')::bigint, 'zzeleven|PG|Online', 35, interval '20 days');
select pg_temp.set('L11', pg_temp.lead('919876531011', 'ZZEleven')::text);
update public.student_leads set lead_score = 72 where id = pg_temp.v('L11')::bigint;
insert into t select 'X11a', pg_temp.decide(pg_temp.v('L11')::bigint, pg_temp.v('seed_hi'), false)::text;
insert into r select 'test11_higher_cpe_wins_outside_lane',
       x ->> 'partner_id' = pg_temp.v('A') and x ->> 'stage' = 'A' and x ->> 'mode' = 'commission_first'
       and (x ->> 'selection_probability')::numeric = 0.8 and (x ->> 'exploration_share')::numeric = 0.2
       and (x -> 'lane' ->> 'applied')::boolean and x -> 'lane' ->> 'x_partner_id' = pg_temp.v('B')
       and (x ->> 'draw')::numeric = round(b2b.u01(pg_temp.v('seed_hi'), 'explore')::numeric, 12) and (x ->> 'draw')::numeric >= 0.2
       and (pg_temp.cand(x, pg_temp.v('B')) ->> 'propensity')::numeric = 0.2 and (pg_temp.cand(x, pg_temp.v('A')) ->> 'tie_rank')::int = 1
       and (pg_temp.cand(x, pg_temp.v('B')) ->> 'under_tested')::boolean and not (pg_temp.cand(x, pg_temp.v('A')) ->> 'under_tested')::boolean,
       coalesce(x ->> 'partner_id', '-') || ' p=' || coalesce(x ->> 'selection_probability', '-') || ' draw=' || coalesce(x ->> 'draw', '-') || ' ' || coalesce(x ->> 'reason', '')
  from (select pg_temp.v('X11a')::jsonb x) z;
-- the lane draws below 0.2: the under-tested partner gets the lead, mode exploration, probability 0.2; committed (C112)
insert into t select 'X11b', pg_temp.decide(pg_temp.v('L11')::bigint, pg_temp.v('seed_lo'), true)::text;
insert into r select 'test11_lane_sends_to_under_tested',
       x ->> 'partner_id' = pg_temp.v('B') and x ->> 'mode' = 'exploration' and (x ->> 'selection_probability')::numeric = 0.2
       and (pg_temp.cand(x, pg_temp.v('A')) ->> 'propensity')::numeric = 0.8 and (x ->> 'committed')::boolean and (x ->> 'decision_id') is not null
       and (x ->> 'draw')::numeric < 0.2 and x ->> 'origin' = 'auto',
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'mode', '-') || ' p=' || coalesce(x ->> 'selection_probability', '-')
  from (select pg_temp.v('X11b')::jsonb x) z;
insert into r select 'c112_stored_decision_matches_result',
       d.stage = x ->> 'stage' and d.score = (x ->> 'score')::numeric and d.eval_segment = x ->> 'eval_segment' and d.holdout_share = (x ->> 'holdout_share')::numeric
       and d.draw = (x ->> 'draw')::numeric and d.mode = 'exploration' and d.selection_probability = 0.2 and d.seed = (x ->> 'seed')::numeric
       and d.how = 'auto' and d.interest_rank = 1 and jsonb_array_length(d.interests) = 1 and d.interests -> 0 ->> 'outcome' = 'routed'
       and d.class = 'qualified' and d.hold is null and d.bar is null and (d.attribution ->> 'paid')::boolean = false
       and not (b2b.decision_json(d) ? 'pinned') and not (b2b.decision_json(d) ? 'mc_draws')
       and (b2b.decision_json(d) ->> 'draw')::numeric = (x ->> 'draw')::numeric and b2b.decision_json(d) ->> 'stage' = 'A'
       and jsonb_array_length(d.candidates) = 2 and (d.candidates -> 0 ->> 'tie_rank')::int = 1 and (d.candidates -> 0 ? 'propensity'),
       d.mode || ' ' || d.stage || ' ' || d.score || ' ' || coalesce(d.draw::text, '-')
  from (select pg_temp.v('X11b')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint;
insert into r select 'c46_decision_feature_snapshot',
       d.features is not null and d.features_hash = md5(d.features::text) and (d.features ->> 'score')::numeric = 0.72 and d.feature_hash is null and d.model_version is null,
       coalesce(d.features_hash, '-') || ' score=' || coalesce(d.features ->> 'score', '-')
  from (select pg_temp.v('X11b')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint;
insert into r select 'test11_allocation_written',
       a.status = 'queued' and a.partner_id = pg_temp.v('B')::bigint and a.stage = 'A' and a.score_inr = 10000 and a.mode = 'exploration' and a.origin = 'auto'
       and not a.override and a.interest_rank = 1 and a.effort_factor = 1 and a.sla_factor = 1 and a.p_enroll is null and a.ncpl_inr is null
       and a.programme_id = pg_temp.v('P11')::bigint and a.paid = false and a.segment = 'zzeleven|PG|Online' and a.reference = 'EDW-' || a.id
       and l.destination_type = 'partner' and l.partner_id = a.partner_id and l.allocation_id = a.id and l.allocation_reason = 'exploration' and l.stage = 'allocated'
       and exists (select 1 from b2b.events ev where ev.type = 'lead.routed' and ev.allocation_id = a.id and ev.payload ->> 'stage' = 'A' and ev.payload ->> 'origin' = 'auto'),
       a.status || ' ' || a.mode || ' ' || coalesce(a.stage, '-')
  from (select pg_temp.v('X11b')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join public.student_leads l on l.id = a.lead_id;
-- both partners at 30 or more: no lane, probability 1; with 20+ leads each, 7+ days old and no activity data the stage is B with neutral factors
select pg_temp.recv(pg_temp.v('B')::bigint, 'zzeleven|PG|Online', 35, interval '20 days');
select pg_temp.set('L11b', pg_temp.lead('919876531012', 'ZZEleven')::text);
insert into t select 'X11c', pg_temp.decide(pg_temp.v('L11b')::bigint, pg_temp.v('seed_lo'), false)::text;
insert into r select 'test11_no_lane_when_both_tested',
       x ->> 'partner_id' = pg_temp.v('A') and (x ->> 'selection_probability')::numeric = 1 and (x ->> 'exploration_share')::numeric = 0 and (x ->> 'draw') is null
       and not (x -> 'lane' ->> 'applied')::boolean and x ->> 'stage' = 'B' and x ->> 'scoring_mode' = 'performance' and x ->> 'mode' = 'performance'
       and (pg_temp.cand(x, pg_temp.v('A')) ->> 'effort_factor')::numeric = 1 and (pg_temp.cand(x, pg_temp.v('A')) ->> 'sla_factor')::numeric = 1
       and (pg_temp.cand(x, pg_temp.v('A')) ->> 'score')::numeric = 12000 and pg_temp.cand(x, pg_temp.v('A')) ->> 'p_source' = 'prior',
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'stage', '-') || ' p=' || coalesce(x ->> 'selection_probability', '-')
  from (select pg_temp.v('X11c')::jsonb x) z;
-- C46: a shadow model is scored for every candidate in Stage A/B; it never decides
insert into b2b.ml_models (version, status, weights, calibration) values ('m31-shadow', 'shadow', '{"(bias)":-2}', '[]');
insert into t select 'X11d', pg_temp.decide(pg_temp.v('L11b')::bigint, pg_temp.v('seed_lo'), false)::text;
insert into r select 'c46_every_candidate_prediction',
       (x ->> 'model_version') is null and x -> 'shadow' ? 'm31-shadow' and (x -> 'shadow' -> 'm31-shadow') ? pg_temp.v('A') and (x -> 'shadow' -> 'm31-shadow') ? pg_temp.v('B')
       and x ->> 'feature_hash' ~ '^[0-9a-f]{32}$' and x ->> 'partner_id' = pg_temp.v('A') and (pg_temp.cand(x, pg_temp.v('A')) ->> 'p_used') is null,
       coalesce((x -> 'shadow')::text, '-') from (select pg_temp.v('X11d')::jsonb x) z;
update b2b.ml_models set status = 'retired' where version = 'm31-shadow';
-- C124: the Admin's note is kept on a partner decision; a reason code is stored alone
insert into t select 'X11e', pg_temp.decide(pg_temp.v('L11b')::bigint, pg_temp.v('seed_hi'), true, 'pass', 'm31 pass note')::text;
insert into r select 'c124_pass_note_stored', d.reason = 'm31 pass note' and d.how = 'pass' and a.origin = 'pass' and a.override and a.reason is null and x ->> 'destination' = 'partner',
       coalesce(d.reason, '-') || ' ' || coalesce(a.origin, '-')
  from (select pg_temp.v('X11e')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint;

-- ========================================================================================================
-- Fixtures for Tests 12, 13, 14 and the ties (one stats_refresh for all of them)
-- ========================================================================================================
-- Test 12: X and Y with 20 received leads each, pushed on the Mondays two and three weeks ago at 11:00 IST.
-- X: first call after 1 working hour, 3 calls in 72 h (2 connected), every SLA met.
-- Y: first call after 30 working hours (Thursday 14:00), 1 call, no connect, every first-attempt SLA breached.
select pg_temp.set('X', pg_temp.partner('zz-t12-x', 'ZZ T12 Fast')::text);
select pg_temp.set('Y', pg_temp.partner('zz-t12-y', 'ZZ T12 Slow')::text);
select pg_temp.offer(pg_temp.v('X')::bigint, pg_temp.v('P12')::bigint);
select pg_temp.offer(pg_temp.v('Y')::bigint, pg_temp.v('P12')::bigint);
select pg_temp.rate(pg_temp.v('X')::bigint, 'fixed', 10000);
select pg_temp.rate(pg_temp.v('Y')::bigint, 'fixed', 11111);
do $x$
declare v_mon date; w int; i int; v_a bigint; v_at timestamptz;
begin
  for w in 2 .. 3 loop
    v_mon := (date_trunc('week', current_date::timestamp))::date - 7 * w;
    for i in 1 .. 10 loop
      v_at := pg_temp.ist(v_mon, time '11:00');
      v_a := pg_temp.alloc_at(pg_temp.v('X')::bigint, 'zztwelve|PG|Online', v_at);
      perform pg_temp.act(v_a, 'call', 'connected', v_at + interval '1 hour');
      perform pg_temp.act(v_a, 'call', 'connected', v_at + interval '2 hours');
      perform pg_temp.act(v_a, 'call', 'not_connected', v_at + interval '3 hours');
      perform pg_temp.sla(v_a, 'first_attempt', interval '2 hours', true);
      perform pg_temp.sla(v_a, 'status_update', interval '7 days', true);
      v_a := pg_temp.alloc_at(pg_temp.v('Y')::bigint, 'zztwelve|PG|Online', v_at);
      perform pg_temp.act(v_a, 'call', 'not_connected', pg_temp.ist(v_mon + 3, time '14:00'));
      perform pg_temp.sla(v_a, 'first_attempt', interval '2 hours', false);
      perform pg_temp.sla(v_a, 'status_update', interval '7 days', true);
    end loop;
  end loop;
end $x$;
-- Test 14: P syncs stage events only, Q has slow calls (12 leads each, below the Stage B gate), R has 4 leads
select pg_temp.set('P', pg_temp.partner('zz-t14-p', 'ZZ T14 NoActivity')::text);
select pg_temp.set('Q', pg_temp.partner('zz-t14-q', 'ZZ T14 Calls')::text);
select pg_temp.set('RR', pg_temp.partner('zz-t14-r', 'ZZ T14 Thin')::text);
select pg_temp.offer(pg_temp.v('P')::bigint, pg_temp.v('P14')::bigint);
select pg_temp.offer(pg_temp.v('Q')::bigint, pg_temp.v('P14')::bigint);
select pg_temp.offer(pg_temp.v('RR')::bigint, pg_temp.v('P14')::bigint);
select pg_temp.rate(pg_temp.v('P')::bigint, 'fixed', 9000);
select pg_temp.rate(pg_temp.v('Q')::bigint, 'fixed', 9000);
select pg_temp.rate(pg_temp.v('RR')::bigint, 'fixed', 9000);
do $x$
declare v_mon date := (date_trunc('week', current_date::timestamp))::date - 14; i int; v_a bigint; v_at timestamptz;
begin
  for i in 1 .. 12 loop
    v_at := pg_temp.ist(v_mon, time '11:00') + (i % 5) * interval '1 day';
    v_a := pg_temp.alloc_at(pg_temp.v('P')::bigint, 'zzfourteen|PG|Online', v_at);
    perform pg_temp.act(v_a, 'stage_change', 'contacted', v_at + interval '2 hours');
    v_a := pg_temp.alloc_at(pg_temp.v('Q')::bigint, 'zzfourteen|PG|Online', v_at);
    perform pg_temp.act(v_a, 'call', 'connected', v_at + interval '4 hours');
    if i <= 4 then
      v_a := pg_temp.alloc_at(pg_temp.v('RR')::bigint, 'zzfourteen|PG|Online', v_at);
      perform pg_temp.act(v_a, 'call', 'connected', v_at + interval '2 hours');
    end if;
  end loop;
end $x$;
-- Test 13: C1 and C2 with 32 matured leads each (70 days), enrolments and refunds
select pg_temp.set('C1', pg_temp.partner('zz-t13-c1', 'ZZ T13 One')::text);
select pg_temp.set('C2', pg_temp.partner('zz-t13-c2', 'ZZ T13 Two')::text);
select pg_temp.offer(pg_temp.v('C1')::bigint, pg_temp.v('P13')::bigint);
select pg_temp.offer(pg_temp.v('C2')::bigint, pg_temp.v('P13')::bigint);
select pg_temp.rate(pg_temp.v('C1')::bigint, 'fixed', 8000);
select pg_temp.rate(pg_temp.v('C2')::bigint, 'fixed', 12000);
select pg_temp.recv(pg_temp.v('C1')::bigint, 'zzthirteen|PG|Online', 32, interval '70 days', null, false, 'closed');
select pg_temp.recv(pg_temp.v('C2')::bigint, 'zzthirteen|PG|Online', 32, interval '70 days', null, false, 'closed');
insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
select a.lead_id, a.cycle_no, a.partner_id, a.id, case when rn <= 10 then 'verified' else 'refunded' end, 'b2b', (now() - interval '50 days')::date
  from (select a.*, row_number() over (order by a.id) rn from b2b.allocations a where a.partner_id = pg_temp.v('C1')::bigint) a where rn <= 12;
insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
select a.lead_id, a.cycle_no, a.partner_id, a.id, 'verified', 'b2b', (now() - interval '50 days')::date
  from (select a.*, row_number() over (order by a.id) rn from b2b.allocations a where a.partner_id = pg_temp.v('C2')::bigint) a where rn <= 6;
-- a test partner's test allocations never count (C5 is paused again after the check)
select pg_temp.set('C5', pg_temp.partner('zz-t13-c5', 'ZZ T13 Test')::text);
select pg_temp.offer(pg_temp.v('C5')::bigint, pg_temp.v('P13')::bigint);
select pg_temp.rate(pg_temp.v('C5')::bigint, 'fixed', 20000);
select pg_temp.recv(pg_temp.v('C5')::bigint, 'zzthirteen|PG|Online', 40, interval '70 days', null, true, 'closed');
-- ties: TA and TB share the rate, TA keeps every SLA, TB half; TC and TD share the rate, TC had 3 leads this week, TD 1
select pg_temp.set('TA', pg_temp.partner('zz-tie-a', 'ZZ Tie A')::text);
select pg_temp.set('TB', pg_temp.partner('zz-tie-b', 'ZZ Tie B')::text);
select pg_temp.offer(pg_temp.v('TA')::bigint, pg_temp.v('PTIE')::bigint);
select pg_temp.offer(pg_temp.v('TB')::bigint, pg_temp.v('PTIE')::bigint);
select pg_temp.rate(pg_temp.v('TA')::bigint, 'fixed', 9000);
select pg_temp.rate(pg_temp.v('TB')::bigint, 'fixed', 9000);
do $x$
declare v_a bigint; i int;
begin
  for i in 1 .. 4 loop
    v_a := pg_temp.alloc_at(pg_temp.v('TA')::bigint, 'zztie|PG|Online', now() - interval '10 days');
    perform pg_temp.sla(v_a, 'first_attempt', interval '2 hours', true);
    v_a := pg_temp.alloc_at(pg_temp.v('TB')::bigint, 'zztie|PG|Online', now() - interval '10 days');
    perform pg_temp.sla(v_a, 'first_attempt', interval '2 hours', i <= 2);
  end loop;
end $x$;
select pg_temp.set('TC', pg_temp.partner('zz-tie-c', 'ZZ Tie C')::text);
select pg_temp.set('TD', pg_temp.partner('zz-tie-d', 'ZZ Tie D')::text);
select pg_temp.offer(pg_temp.v('TC')::bigint, pg_temp.v('PTIE2')::bigint);
select pg_temp.offer(pg_temp.v('TD')::bigint, pg_temp.v('PTIE2')::bigint);
select pg_temp.rate(pg_temp.v('TC')::bigint, 'fixed', 9000);
select pg_temp.rate(pg_temp.v('TD')::bigint, 'fixed', 9000);
select pg_temp.recv(pg_temp.v('TC')::bigint, 'zztietwo|PG|Online', 3, interval '2 days');
select pg_temp.recv(pg_temp.v('TD')::bigint, 'zztietwo|PG|Online', 1, interval '2 days');
insert into t select 'SR', b2b.stats_refresh()::text;
insert into r select 'stats_refreshed', (x ->> 'rows')::int > 0 and (x ->> 'effort_rows')::int > 0 and (x ->> 'sla_rows')::int > 0, x::text from (select pg_temp.v('SR')::jsonb x) z;

-- ========================================================================================================
-- Test 12: Stage B, a lower CPE with much better effort and SLA adherence wins (D27)
-- ========================================================================================================
select pg_temp.set('L12', pg_temp.lead('919876531112', 'ZZTwelve')::text);
insert into t select 'X12', pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false)::text;
insert into r select 'test12_stage_b_factors_computed',
       x ->> 'stage' = 'B' and x ->> 'scoring_mode' = 'performance'
       and (cx ->> 'effort_factor')::numeric > 1 and (cy ->> 'effort_factor')::numeric < 1
       and (cx ->> 'sla_factor')::numeric = 1 and (cy ->> 'sla_factor')::numeric = 0.80
       and (cx ->> 'sla_adherence')::numeric = 1 and (cy ->> 'sla_adherence')::numeric = 0.5
       and (cx ->> 'has_activity')::boolean and (cy ->> 'has_activity')::boolean
       and (cx -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'r')::numeric > 0 and (cy -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'r')::numeric < 0
       and (cx -> 'effort_detail' -> 'metrics' -> 'attempts_72h' ->> 'r')::numeric > 0 and (cy -> 'effort_detail' -> 'metrics' -> 'connect_rate' ->> 'r')::numeric < 0
       and (cx ->> 'n_received')::int = 20 and (cy ->> 'n_received')::int = 20,
       'X effort ' || coalesce(cx ->> 'effort_factor', '-') || ' sla ' || coalesce(cx ->> 'sla_factor', '-') || ' | Y effort ' || coalesce(cy ->> 'effort_factor', '-') || ' sla ' || coalesce(cy ->> 'sla_factor', '-') || ' stage ' || coalesce(x ->> 'stage', '-')
  from (select pg_temp.v('X12')::jsonb x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx, pg_temp.cand(x, pg_temp.v('Y')) cy) c;
insert into r select 'test12_score_is_cpe_x_effort_x_sla',
       (cx ->> 'score')::numeric = round(10000 * (cx ->> 'effort_factor')::numeric * (cx ->> 'sla_factor')::numeric, 2)
       and (cy ->> 'score')::numeric = round(11111 * (cy ->> 'effort_factor')::numeric * (cy ->> 'sla_factor')::numeric, 2)
       and (cx ->> 'score')::numeric > (cy ->> 'score')::numeric and (cx ->> 'tie_rank')::int = 1 and (cy ->> 'tie_rank')::int = 2
       and x ->> 'partner_id' = pg_temp.v('X') and (x ->> 'score')::numeric = (cx ->> 'score')::numeric,
       'X ' || coalesce(cx ->> 'score', '-') || ' Y ' || coalesce(cy ->> 'score', '-')
  from (select pg_temp.v('X12')::jsonb x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx, pg_temp.cand(x, pg_temp.v('Y')) cy) c;
-- the lane is active in Stage B while a partner has fewer than 30 leads (the draw here is >= 0.2, so X keeps the lead at 0.8)
insert into r select 'lane_active_in_stage_b',
       (x -> 'lane' ->> 'applied')::boolean and x -> 'lane' ->> 'x_partner_id' = pg_temp.v('Y') and (x ->> 'exploration_share')::numeric = 0.2
       and (x ->> 'selection_probability')::numeric = 0.8 and (pg_temp.cand(x, pg_temp.v('Y')) ->> 'propensity')::numeric = 0.2 and x ->> 'mode' = 'performance',
       (x -> 'lane')::text from (select pg_temp.v('X12')::jsonb x) z;
-- raw factor inputs are logged whatever the stage or the switches (C16)
insert into r select 'c16_raw_factors_logged',
       (cx ->> 'effort_raw')::numeric = (cx ->> 'effort_factor')::numeric and (cy ->> 'sla_raw')::numeric = 0.80 and (cy ->> 'sla_total')::int = 40
       and cx -> 'effort_detail' ? 'metrics' and (cx ->> 'w_n') is not null and (cx ->> 'prior_weight')::numeric = 20 and (cx ->> 'half_life_days')::int = 30
       and (cx ->> 'p_hat') is not null and cx ->> 'p_source' in ('p_hat', 'prior') and (cx ->> 'refund_rate') is not null,
       coalesce(cx ->> 'effort_raw', '-') || ' ' || coalesce(cy ->> 'sla_raw', '-')
  from (select pg_temp.v('X12')::jsonb x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx, pg_temp.cand(x, pg_temp.v('Y')) cy) c;
-- counter-case: a CPE gap too large keeps the slow partner
update b2b.rates set value = 20000 where partner_id = pg_temp.v('Y')::bigint;
insert into r select 'test12_large_cpe_gap_keeps_slow_partner', x ->> 'partner_id' = pg_temp.v('Y') and x ->> 'stage' = 'B'
       and (pg_temp.cand(x, pg_temp.v('Y')) ->> 'score')::numeric > (pg_temp.cand(x, pg_temp.v('X')) ->> 'score')::numeric,
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'score', '-')
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.rates set value = 11111 where partner_id = pg_temp.v('Y')::bigint;
-- factors off make Stage B ordered like Stage A; the raw inputs are still logged
update b2b.settings set value = jsonb_set(jsonb_set(value, '{effort_factor,enabled}', 'false'), '{sla_factor,enabled}', 'false') where key = 'engine';
insert into r select 'factors_off_orders_like_stage_a', x ->> 'partner_id' = pg_temp.v('Y') and x ->> 'stage' = 'B'
       and (cx ->> 'effort_factor')::numeric = 1 and (cy ->> 'sla_factor')::numeric = 1 and (cy ->> 'score')::numeric = 11111
       and (cy ->> 'sla_raw')::numeric = 0.80 and (cx ->> 'effort_raw')::numeric > 1,
       coalesce(x ->> 'partner_id', '-') || ' Yscore ' || coalesce(cy ->> 'score', '-') || ' Xraw ' || coalesce(cx ->> 'effort_raw', '-')
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx, pg_temp.cand(x, pg_temp.v('Y')) cy) c;
update b2b.settings set value = jsonb_set(jsonb_set(value, '{effort_factor,enabled}', 'true'), '{sla_factor,enabled}', 'true') where key = 'engine';
-- a new partner with fewer than 20 leads keeps the segment at Stage A; paused, it is excluded and the stage is B again
select pg_temp.set('Z', pg_temp.partner('zz-t12-z', 'ZZ T12 New')::text);
select pg_temp.offer(pg_temp.v('Z')::bigint, pg_temp.v('P12')::bigint);
select pg_temp.rate(pg_temp.v('Z')::bigint, 'fixed', 9000);
insert into r select 'new_partner_keeps_stage_a', x ->> 'stage' = 'A' and x ->> 'scoring_mode' = 'commission_first' and x ->> 'partner_id' = pg_temp.v('Y')
       and (pg_temp.cand(x, pg_temp.v('Z')) ->> 'n_received')::int = 0 and (pg_temp.cand(x, pg_temp.v('Y')) ->> 'effort_factor')::numeric = 1,
       coalesce(x ->> 'stage', '-') || ' ' || coalesce(x ->> 'partner_id', '-')
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.partners set status = 'paused' where id = pg_temp.v('Z')::bigint;
insert into r select 'paused_partner_excluded_with_cause', x ->> 'stage' = 'B' and x ->> 'partner_id' = pg_temp.v('X')
       and exists (select 1 from jsonb_array_elements(x -> 'excluded') e where e ->> 'partner_id' = pg_temp.v('Z') and e ->> 'cause' = 'paused')
       and exists (select 1 from jsonb_array_elements(x -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('Z') and not (c ->> 'eligible')::boolean and c ->> 'cause' = 'paused'),
       (x -> 'excluded')::text
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z;
-- C60: a leftover kill switch or kill segment changes nothing; C56: a leftover share cap changes nothing
update b2b.settings set value = value || '{"kill_segments":["zztwelve|PG|Online"]}' where key = 'engine_policy';
update b2b.settings set value = value || '{"kill_switch":true}' where key = 'engine';
insert into r select 'c60_kill_segments_ignored', x ->> 'stage' = 'B' and x ->> 'scoring_mode' = 'performance' and x ->> 'mode' in ('performance', 'exploration') and x ->> 'partner_id' = pg_temp.v('X'),
       coalesce(x ->> 'mode', '-') from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.settings set value = value || '{"kill_segments":[]}' where key = 'engine_policy';
update b2b.settings set value = value || '{"kill_switch":false}' where key = 'engine';
update b2b.settings set value = jsonb_set(value, '{segments}', '{"zztwelve|PG|Online":{"share_cap":{"value":1.0}}}') where key = 'engine_policy';
insert into r select 'c56_leftover_share_cap_ignored', x ->> 'partner_id' = pg_temp.v('X')
       and not exists (select 1 from jsonb_array_elements(x -> 'excluded') e where e ->> 'why' ilike '%share cap%'),
       (x -> 'excluded')::text from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.settings set value = value || '{"segments":{}}' where key = 'engine_policy';
-- C1 (e) / C5: an AI effort-weight change acts at decision time for steered leads; a holdout lead keeps the Admin's weights
update b2b.settings set value = value || '{"ai":{"effort_weights":{"first_call":5}}}' where key = 'engine_policy';
insert into r select 'c1_ai_effort_weights_apply_without_refresh',
       (cx ->> 'effort_factor')::numeric = b2b.effort_from_detail(cx -> 'effort_detail', b2b.engine_params(false) -> 'effort')
       and (cx ->> 'effort_factor')::numeric <> b2b.effort_from_detail(cx -> 'effort_detail', b2b.engine_params(true) -> 'effort')
       and (b2b.engine_params(false) -> 'effort' ->> 'source') = 'ai' and not (x ->> 'holdout')::boolean,
       coalesce(cx ->> 'effort_factor', '-') || ' vs admin ' || b2b.effort_from_detail(cx -> 'effort_detail', b2b.engine_params(true) -> 'effort')::text
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hi'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx) c;
update b2b.settings set value = value || '{"holdout_share":0.5}' where key = 'engine_policy';
insert into r select 'c5_holdout_keeps_admin_weights',
       (x ->> 'holdout')::boolean and (x ->> 'holdout_share')::numeric = 0.5
       and (cx ->> 'effort_factor')::numeric = b2b.effort_from_detail(cx -> 'effort_detail', b2b.engine_params(true) -> 'effort'),
       coalesce(cx ->> 'effort_factor', '-') || ' holdout ' || coalesce(x ->> 'holdout', '-')
  from (select pg_temp.decide(pg_temp.v('L12')::bigint, pg_temp.v('seed_hold'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('X')) cx) c;
update b2b.settings set value = value || '{"holdout_share":0,"ai":{}}' where key = 'engine_policy';

-- ========================================================================================================
-- Test 14: a partner that syncs no activity data never gets an effort factor above 1.0
-- ========================================================================================================
select pg_temp.set('L14', pg_temp.lead('919876531114', 'ZZFourteen')::text);
insert into t select 'X14', pg_temp.decide(pg_temp.v('L14')::bigint, pg_temp.v('seed_hi'), false)::text;
insert into r select 'test14_no_activity_capped',
       not (cp ->> 'has_activity')::boolean and (cp -> 'effort_detail' ->> 'capped_no_activity')::boolean and (cp ->> 'effort_raw')::numeric <= 1
       and cp -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'basis' = 'no_activity' and (cp -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'r') is null
       and (cq ->> 'has_activity')::boolean and x ->> 'stage' = 'A',
       'P ' || coalesce(cp ->> 'effort_raw', '-') || ' ' || coalesce((cp -> 'effort_detail' -> 'metrics' -> 'first_call')::text, '-')
  from (select pg_temp.v('X14')::jsonb x) z, lateral (select pg_temp.cand(x, pg_temp.v('P')) cp, pg_temp.cand(x, pg_temp.v('Q')) cq) c;
-- the no-activity partner is excluded from the medians of metrics 1-5, so Q falls back to the partner-wide basis; R (4 leads) is thin
insert into r select 'test14_medians_exclude_no_activity_partner',
       cq -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'basis' in ('partner', 'thin')
       and cq -> 'effort_detail' -> 'metrics' -> 'connect_rate' ->> 'basis' in ('partner', 'thin')
       and cr -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'basis' = 'thin' and (cr -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'r') is null
       and (cr ->> 'effort_raw')::numeric = 1,
       'Q ' || coalesce(cq -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'basis', '-') || ' R ' || coalesce(cr -> 'effort_detail' -> 'metrics' -> 'first_call' ->> 'basis', '-')
  from (select pg_temp.v('X14')::jsonb x) z, lateral (select pg_temp.cand(x, pg_temp.v('Q')) cq, pg_temp.cand(x, pg_temp.v('RR')) cr) c;

-- ========================================================================================================
-- Ties: higher CPE, then better SLA adherence, then fewer leads this week
-- ========================================================================================================
select pg_temp.set('LTIE', pg_temp.lead('919876531201', 'ZZTie')::text);
insert into r select 'tie_breaks_on_sla_adherence', x ->> 'partner_id' = pg_temp.v('TA') and x ->> 'stage' = 'A'
       and (ca ->> 'score')::numeric = (cb ->> 'score')::numeric and (ca ->> 'sla_adherence')::numeric = 1 and (cb ->> 'sla_adherence')::numeric = 0.5
       and (ca ->> 'tie_rank')::int = 1 and (cb ->> 'tie_rank')::int = 2 and not (x -> 'lane' ->> 'applied')::boolean,
       coalesce(x ->> 'partner_id', '-') || ' sla ' || coalesce(ca ->> 'sla_adherence', '-') || '/' || coalesce(cb ->> 'sla_adherence', '-')
  from (select pg_temp.decide(pg_temp.v('LTIE')::bigint, pg_temp.v('seed_hi'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('TA')) ca, pg_temp.cand(x, pg_temp.v('TB')) cb) c;
select pg_temp.set('LTIE2', pg_temp.lead('919876531202', 'ZZTietwo')::text);
insert into r select 'tie_breaks_on_fewer_leads_this_week', x ->> 'partner_id' = pg_temp.v('TD')
       and (cc ->> 'leads_week')::int = 3 and (cd ->> 'leads_week')::int = 1 and (cc ->> 'score')::numeric = (cd ->> 'score')::numeric
       and (cc ->> 'sla_adherence') is null and (cd ->> 'sla_adherence') is null and (cd ->> 'tie_rank')::int = 1,
       coalesce(x ->> 'partner_id', '-') || ' weeks ' || coalesce(cc ->> 'leads_week', '-') || '/' || coalesce(cd ->> 'leads_week', '-')
  from (select pg_temp.decide(pg_temp.v('LTIE2')::bigint, pg_temp.v('seed_hi'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('TC')) cc, pg_temp.cand(x, pg_temp.v('TD')) cd) c;

-- ========================================================================================================
-- Test 13: Stage C, the partner with the highest CPE x P(enrol) x (1 - refund) x effort x SLA wins (D29)
-- ========================================================================================================
update b2b.partners set status = 'paused' where id = pg_temp.v('C5')::bigint;   -- back in for the test-allocation check below
select pg_temp.set('L13', pg_temp.lead('919876531113', 'ZZThirteen')::text);
insert into t select 'X13', pg_temp.decide(pg_temp.v('L13')::bigint, pg_temp.v('seed_hi'), false)::text;
insert into r select 'test13_stage_c_score_is_ncpl_x_factors',
       x ->> 'stage' = 'C' and x ->> 'scoring_mode' = 'performance' and x ->> 'mode' = 'performance' and not (x -> 'lane' ->> 'applied')::boolean
       and bool_and((c ->> 'score')::numeric = round((c ->> 'cpe')::numeric * (c ->> 'p_used')::numeric * (1 - (c ->> 'refund_rate')::numeric) * (c ->> 'effort_factor')::numeric * (c ->> 'sla_factor')::numeric, 2)
                    and (c ->> 'ncpl')::numeric = round((c ->> 'cpe')::numeric * (c ->> 'p_used')::numeric * (1 - (c ->> 'refund_rate')::numeric), 2)
                    and c ->> 'p_source' = 'p_hat' and (c ->> 'p_used')::numeric = (c ->> 'p_hat')::numeric and (c ->> 'n_matured_c')::int = 32)
       and (x ->> 'score')::numeric = (select max((c2 ->> 'score')::numeric) from jsonb_array_elements(x -> 'candidates') c2)
       and (x ->> 'ncpl')::numeric = (pg_temp.cand(x, x ->> 'partner_id') ->> 'ncpl')::numeric,
       coalesce(x ->> 'partner_id', '-') || ' score ' || coalesce(x ->> 'score', '-') || ' | ' || string_agg(c ->> 'partner_id' || ':' || (c ->> 'p_used') || 'x' || (c ->> 'refund_rate'), ' ')
  from (select pg_temp.v('X13')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c where (c ->> 'eligible')::boolean group by x;
insert into r select 'c45_candidate_live_features', bool_and(c ? 'open_backlog' and c ? 'in_hours' and c ? 'fch_7d' and c ? 'fch_30d' and c ? 'connect_30d' and c ? 'fee_inr'
                                                              and (c ->> 'open_backlog')::int >= 0 and jsonb_typeof(c -> 'in_hours') = 'boolean'),
       (select (c2 - 'effort_detail' - 'offers' - 'programmes')::text from jsonb_array_elements(x -> 'candidates') c2 limit 1)
  from (select pg_temp.v('X13')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c where (c ->> 'eligible')::boolean group by x;
insert into t select 'X13c', pg_temp.decide(pg_temp.v('L13')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'test13_allocation_carries_stage_c_numbers',
       a.stage = 'C' and a.p_enroll = (w ->> 'p_used')::numeric and a.ncpl_inr = (w ->> 'ncpl')::numeric and a.score_inr = (w ->> 'score')::numeric
       and a.effort_factor = (w ->> 'effort_factor')::numeric and a.sla_factor = (w ->> 'sla_factor')::numeric and a.cpe_net_inr = (w ->> 'cpe')::numeric
       and d.stage = 'C' and d.scoring_mode = 'performance' and d.score = a.score_inr and a.model_version is null and d.model_version is null,
       coalesce(a.stage, '-') || ' p ' || coalesce(a.p_enroll::text, '-') || ' ncpl ' || coalesce(a.ncpl_inr::text, '-')
  from (select pg_temp.v('X13c')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id,
       lateral (select pg_temp.cand(x, x ->> 'partner_id') w) ww;
-- test allocations never count toward the gates (C5 has 40 test leads)
insert into r select 'test_allocations_never_count',
       (c ->> 'n_received')::int = 0 and (c ->> 'n_matured_c')::int = 0 and (c ->> 'under_tested')::boolean and sc ->> 'stage' = 'C',
       coalesce(c ->> 'n_received', '-') || ' ' || coalesce(sc ->> 'stage', '-')
  from (select b2b.stage_score(jsonb_build_object('segment', 'zzthirteen|PG|Online', 'seed', 0.5, 'lane_allowed', false),
                               b2b.offer_candidates(b2b.lead_interest(l), false)) sc from public.student_leads l where l.id = pg_temp.v('L13')::bigint) z,
       lateral (select pg_temp.cand(sc, pg_temp.v('C5')) c) cc;
-- the lane is active in Stage C while a partner has fewer than 30 leads
select pg_temp.set('C4', pg_temp.partner('zz-t13-c4', 'ZZ T13 Young')::text);
select pg_temp.offer(pg_temp.v('C4')::bigint, pg_temp.v('P13')::bigint);
select pg_temp.rate(pg_temp.v('C4')::bigint, 'fixed', 5000);
select pg_temp.recv(pg_temp.v('C4')::bigint, 'zzthirteen|PG|Online', 22, interval '10 days');
select pg_temp.set('L13b', pg_temp.lead('919876531213', 'ZZThirteen')::text);
insert into r select 'lane_active_in_stage_c', x ->> 'stage' = 'C' and (x -> 'lane' ->> 'applied')::boolean and x -> 'lane' ->> 'x_partner_id' = pg_temp.v('C4')
       and (x ->> 'selection_probability')::numeric = 0.8 and (x ->> 'exploration_share')::numeric = 0.2 and x ->> 'partner_id' <> pg_temp.v('C4'),
       coalesce(x ->> 'stage', '-') || ' ' || (x -> 'lane')::text
  from (select pg_temp.decide(pg_temp.v('L13b')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.partners set status = 'paused' where id = pg_temp.v('C4')::bigint;
-- C1 (a)-(d): an AI prior change is picked up through the 'ai' stats variant, never through missing rows
update b2b.settings set value = value || '{"ai":{"prior_weight":10}}' where key = 'engine_policy';
insert into r select 'c1a_ai_wanted_but_base_until_refresh',
       (b2b.engine_params(false) ->> 'ai_stats_wanted')::boolean and b2b.engine_params(false) ->> 'variant' = 'base'
       and x ->> 'params_variant' = 'base' and x ->> 'stage' = 'C' and x ->> 'partner_id' = (pg_temp.v('X13')::jsonb ->> 'partner_id'),
       coalesce(x ->> 'params_variant', '-') from (select pg_temp.decide(pg_temp.v('L13b')::bigint, pg_temp.v('seed_hi'), false) x) z;
select b2b.stats_refresh();
insert into r select 'c1b_ai_variant_after_refresh',
       exists (select 1 from b2b.segment_stats s where s.variant = 'ai' and s.segment = 'zzthirteen|PG|Online' and s.params ->> 'prior_weight' = '10')
       and b2b.engine_params(false) ->> 'variant' = 'ai' and b2b.engine_params(true) ->> 'variant' = 'base'
       and x ->> 'params_variant' = 'ai'
       and (pg_temp.cand(x, pg_temp.v('C1')) ->> 'p_hat')::numeric = (select p.p_hat from b2b.partner_segment_stats p where p.variant = 'ai' and p.segment = 'zzthirteen|PG|Online' and p.partner_id = pg_temp.v('C1')::bigint)
       and (pg_temp.cand(x, pg_temp.v('C1')) ->> 'prior_weight')::numeric = 10,
       coalesce(x ->> 'params_variant', '-') || ' p_hat ' || coalesce(pg_temp.cand(x, pg_temp.v('C1')) ->> 'p_hat', '-')
  from (select pg_temp.decide(pg_temp.v('L13b')::bigint, pg_temp.v('seed_hi'), false) x) z;
update b2b.settings set value = value || '{"ai":{"prior_weight":12}}' where key = 'engine_policy';
insert into t select 'V1', b2b.engine_params(false) ->> 'variant';
insert into t select 'RS', b2b.stats_refresh_if_stale()::text;
insert into r select 'c1c_changed_prior_rebuilt_by_catchup', pg_temp.v('V1') = 'base' and (pg_temp.v('RS')::jsonb ->> 'refreshed') = 'ai' and b2b.engine_params(false) ->> 'variant' = 'ai',
       pg_temp.v('V1') || ' -> ' || coalesce(pg_temp.v('RS')::jsonb ->> 'refreshed', '-');
update b2b.settings set value = value || '{"ai":{}}' where key = 'engine_policy';
insert into r select 'c1d_no_ai_keys_base_and_fresh', b2b.engine_params(false) ->> 'variant' = 'base' and (b2b.stats_refresh_if_stale() ->> 'fresh')::boolean, null;
-- C61: a champion decides Stage C for steered leads; the decision and the allocation carry the version and the hash
insert into b2b.ml_models (version, status, weights, calibration) values ('m31-champ', 'champion', jsonb_build_object('(bias)', -3, 'p:' || pg_temp.v('C1'), 4), '[]');
select pg_temp.set('L13m', pg_temp.lead('919876531313', 'ZZThirteen')::text);
insert into t select 'X13m', pg_temp.decide(pg_temp.v('L13m')::bigint, pg_temp.v('seed_champ'), true)::text;
insert into r select 'c61_champion_decides_stage_c',
       x ->> 'model_version' = 'm31-champ' and x ->> 'feature_hash' ~ '^[0-9a-f]{32}$' and x ->> 'partner_id' = pg_temp.v('C1') and x ->> 'stage' = 'C'
       and w ->> 'p_source' = 'model' and (w ->> 'p_used')::numeric = (w ->> 'p_model')::numeric and (w ->> 'p_used')::numeric between 0.7 and 0.76
       and (pg_temp.cand(x, pg_temp.v('C2')) ->> 'p_used')::numeric < 0.1 and pg_temp.cand(x, pg_temp.v('C2')) ->> 'p_source' = 'model'
       and d.model_version = 'm31-champ' and d.feature_hash = x ->> 'feature_hash' and a.model_version = 'm31-champ' and a.p_enroll = round((w ->> 'p_used')::numeric, 5)
       and (x ->> 'selection_probability')::numeric = 1,
       coalesce(x ->> 'model_version', '-') || ' p ' || coalesce(w ->> 'p_used', '-') || ' ' || coalesce(x ->> 'partner_id', '-')
  from (select pg_temp.v('X13m')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint,
       lateral (select pg_temp.cand(x, pg_temp.v('C1')) w) ww;
update b2b.settings set value = value || '{"holdout_share":0.5}' where key = 'engine_policy';
select pg_temp.set('L13h', pg_temp.lead('919876531413', 'ZZThirteen')::text);
insert into t select 'X13h', pg_temp.decide(pg_temp.v('L13h')::bigint, pg_temp.v('seed_hold'), true)::text;
insert into r select 'c61_holdout_has_no_deciding_model',
       (x ->> 'holdout')::boolean and (x ->> 'model_version') is null and w ->> 'p_source' = 'p_hat' and (w ->> 'p_model') is not null
       and a.model_version is null and d.model_version is null and d.holdout and d.holdout_share = 0.5 and x ->> 'params_variant' = 'base',
       coalesce(x ->> 'partner_id', '-') || ' holdout ' || coalesce(x ->> 'holdout', '-')
  from (select pg_temp.v('X13h')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint,
       lateral (select pg_temp.cand(x, x ->> 'partner_id') w) ww;
update b2b.settings set value = value || '{"holdout_share":0}' where key = 'engine_policy';
-- C4: the challenger decides only on its 10%; the logged propensity mixes both orderings 90/10
insert into b2b.ml_models (version, status, weights, calibration) values ('m31-chall', 'challenger', jsonb_build_object('(bias)', -3, 'p:' || pg_temp.v('C2'), 4), '[]');
select pg_temp.set('L13q', pg_temp.lead('919876531513', 'ZZThirteen')::text);
insert into r select 'c4_challenger_not_drawn_mixture_0_9',
       x ->> 'model_version' = 'm31-champ' and x ->> 'partner_id' = pg_temp.v('C1') and (x ->> 'selection_probability')::numeric = 0.9
       and (pg_temp.cand(x, pg_temp.v('C2')) ->> 'propensity')::numeric = 0.1 and x -> 'shadow' ? 'm31-chall' and not (x -> 'shadow' ? 'm31-champ'),
       coalesce(x ->> 'model_version', '-') || ' p=' || coalesce(x ->> 'selection_probability', '-')
  from (select pg_temp.decide(pg_temp.v('L13q')::bigint, pg_temp.v('seed_champ'), false) x) z;
insert into r select 'c4_challenger_drawn_decides',
       x ->> 'model_version' = 'm31-chall' and x ->> 'partner_id' = pg_temp.v('C2') and (x ->> 'selection_probability')::numeric = 0.1
       and (pg_temp.cand(x, pg_temp.v('C1')) ->> 'propensity')::numeric = 0.9 and pg_temp.cand(x, pg_temp.v('C2')) ->> 'p_source' = 'model',
       coalesce(x ->> 'model_version', '-') || ' p=' || coalesce(x ->> 'selection_probability', '-')
  from (select pg_temp.decide(pg_temp.v('L13q')::bigint, pg_temp.v('seed_chall'), false) x) z;
update b2b.ml_models set status = 'retired' where version in ('m31-champ', 'm31-chall');

-- ========================================================================================================
-- Test 5: primary interest offered by nobody, secondary offered by one partner
-- ========================================================================================================
select pg_temp.set('S', pg_temp.partner('zz-t5-s', 'ZZ T5 Second')::text);
select pg_temp.offer(pg_temp.v('S')::bigint, pg_temp.v('P5B')::bigint);
select pg_temp.rate(pg_temp.v('S')::bigint, 'fixed', 7000);
select pg_temp.set('L5', pg_temp.lead('919876531005', 'ZZNobody')::text);
insert into b2b.lead_interests (lead_id, position, course_text, course_key, level, mode, source) values (pg_temp.v('L5')::bigint, 2, 'ZZSecond', 'zzsecond', 'UG', 'Online', 'api');
insert into t select 'X5', pg_temp.decide(pg_temp.v('L5')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'test5_secondary_interest_routed',
       x ->> 'partner_id' = pg_temp.v('S') and (x ->> 'interest_rank')::int = 2 and x -> 'interest' ->> 'course_key' = 'zzsecond'
       and x ->> 'eval_segment' = 'zzsecond|UG|Online' and jsonb_array_length(x -> 'interests') = 2
       and x -> 'interests' -> 0 ->> 'outcome' = 'no_offer' and x -> 'interests' -> 0 ->> 'course_key' = 'zznobody'
       and x -> 'interests' -> 1 ->> 'outcome' = 'routed'
       and a.interest_rank = 2 and a.segment = 'zzsecond|UG|Online' and d.interest_rank = 2 and jsonb_array_length(d.interests) = 2 and d.segment = 'zzsecond|UG|Online',
       coalesce(x ->> 'partner_id', '-') || ' rank ' || coalesce(x ->> 'interest_rank', '-') || ' ' || (x -> 'interests')::text
  from (select pg_temp.v('X5')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id;
-- critic B4: an offered primary whose partner is full gives no_capacity (cause caps), never the secondary
select pg_temp.set('F', pg_temp.partner('zz-t5-f', 'ZZ T5 Full', '{"daily_cap":0}')::text);
select pg_temp.offer(pg_temp.v('F')::bigint, pg_temp.v('P5C')::bigint);
select pg_temp.rate(pg_temp.v('F')::bigint, 'fixed', 7000);
select pg_temp.set('L5b', pg_temp.lead('919876531015', 'ZZFive')::text);
insert into b2b.lead_interests (lead_id, position, course_text, course_key, level, mode, source) values (pg_temp.v('L5b')::bigint, 2, 'ZZSecond', 'zzsecond', 'UG', 'Online', 'api');
insert into t select 'X5b', pg_temp.decide(pg_temp.v('L5b')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'test5_full_primary_is_no_capacity_not_secondary',
       x ->> 'destination' = 'in_house' and x ->> 'reason' = 'no_capacity' and x ->> 'cause' = 'caps' and x ->> 'b2c_lane' = 'sales' and x ->> 'mode' = 'fallback'
       and jsonb_array_length(x -> 'interests') = 1 and x -> 'interests' -> 0 ->> 'outcome' = 'offered'
       and exists (select 1 from jsonb_array_elements(x -> 'excluded') e where e ->> 'partner_id' = pg_temp.v('F') and e ->> 'cause' = 'caps')
       and a.reason = 'no_capacity' and a.cause = 'caps' and a.b2c_lane = 'sales' and a.status = 'handed_off' and a.destination_type = 'in_house'
       and exists (select 1 from b2b.events ev where ev.type = 'b2c.lead_handed_off' and ev.allocation_id = a.id and ev.payload ->> 'cause' = 'caps' and (ev.payload ->> 'contract_version')::int = 3
                     and ev.payload -> 'handling' ->> 'job' = 'sell' and ev.payload -> 'handling' ->> 'assignment' = 'counsellor_choice'),
       coalesce(x ->> 'reason', '-') || ' ' || coalesce(x ->> 'cause', '-') || ' ' || (x -> 'interests')::text
  from (select pg_temp.v('X5b')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint;

-- ========================================================================================================
-- Stages and segments: exact segment versus roll-up (D25); contractual minimums; fix_partner; no rate
-- ========================================================================================================
select pg_temp.set('E1', pg_temp.partner('zz-ex-one', 'ZZ Exact One')::text);
select pg_temp.set('E2', pg_temp.partner('zz-ex-two', 'ZZ Exact Two')::text);
select pg_temp.offer(pg_temp.v('E1')::bigint, pg_temp.v('PEX1')::bigint); select pg_temp.offer(pg_temp.v('E1')::bigint, pg_temp.v('PEX2')::bigint);
select pg_temp.offer(pg_temp.v('E2')::bigint, pg_temp.v('PEX1')::bigint); select pg_temp.offer(pg_temp.v('E2')::bigint, pg_temp.v('PEX2')::bigint);
select pg_temp.rate(pg_temp.v('E1')::bigint, 'fixed', 8000);
select pg_temp.rate(pg_temp.v('E2')::bigint, 'fixed', 8500);
select pg_temp.recv(pg_temp.v('E1')::bigint, 'zzexact|PG|Online', 30, interval '20 days', 'zzexact|PG|Online|u' || pg_temp.v('U1'));
select pg_temp.recv(pg_temp.v('E2')::bigint, 'zzexact|PG|Online', 30, interval '20 days', 'zzexact|PG|Online|u' || pg_temp.v('U1'));
select pg_temp.set('LEX1', pg_temp.lead('919876531301', 'ZZExact', '{"interested_university":"ZZ Scoring University"}')::text);
select pg_temp.set('LEX2', pg_temp.lead('919876531302', 'ZZExact', '{"interested_university":"ZZ Other University"}')::text);
insert into r select 'exact_segment_when_every_partner_has_30', x ->> 'eval_segment' = 'zzexact|PG|Online|u' || pg_temp.v('U1') and x ->> 'segment_exact' = x ->> 'eval_segment'
       and x ->> 'stage' = 'B' and (pg_temp.cand(x, pg_temp.v('E1')) ->> 'n_received')::int = 30 and x ->> 'partner_id' = pg_temp.v('E2'),
       coalesce(x ->> 'eval_segment', '-') from (select pg_temp.decide(pg_temp.v('LEX1')::bigint, pg_temp.v('seed_hi'), false) x) z;
insert into r select 'rollup_segment_when_exact_is_thin', x ->> 'eval_segment' = 'zzexact|PG|Online' and x ->> 'segment_exact' = 'zzexact|PG|Online|u' || pg_temp.v('U2')
       and (pg_temp.cand(x, pg_temp.v('E1')) ->> 'n_received')::int = 30 and x ->> 'stage' = 'B',
       coalesce(x ->> 'eval_segment', '-') from (select pg_temp.decide(pg_temp.v('LEX2')::bigint, pg_temp.v('seed_hi'), false) x) z;
-- a contractual minimum behind schedule is served first, scored without the lane (C30, C47)
select pg_temp.set('M1', pg_temp.partner('zz-min-one', 'ZZ Min One', '{"contract_min_monthly":100}')::text);
select pg_temp.set('M2', pg_temp.partner('zz-min-two', 'ZZ Min Two')::text);
select pg_temp.offer(pg_temp.v('M1')::bigint, pg_temp.v('PMIN')::bigint); select pg_temp.offer(pg_temp.v('M2')::bigint, pg_temp.v('PMIN')::bigint);
select pg_temp.rate(pg_temp.v('M1')::bigint, 'fixed', 5000); select pg_temp.rate(pg_temp.v('M2')::bigint, 'fixed', 9000);
select pg_temp.set('LMIN', pg_temp.lead('919876531401', 'ZZMinimum')::text);
insert into t select 'XMIN', pg_temp.decide(pg_temp.v('LMIN')::bigint, pg_temp.v('seed_lo'), true)::text;
insert into r select 'minimum_served_first_without_lane',
       x ->> 'partner_id' = pg_temp.v('M1') and x ->> 'mode' = 'minimum' and (x ->> 'exploration_share')::numeric = 0 and (x ->> 'draw') is null
       and not (x -> 'lane' ->> 'applied')::boolean and (x ->> 'selection_probability')::numeric = 1
       and exists (select 1 from jsonb_array_elements(x -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('M2') and not (c ->> 'eligible')::boolean and c ->> 'why' ilike '%minimum%')
       and a.mode = 'minimum' and d.mode = 'minimum' and d.draw is null,
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'mode', '-')
  from (select pg_temp.v('XMIN')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id;
insert into r select 'c47_minimum_logs_stats', bool_and((c ->> 'p_hat') is not null and c ->> 'p_source' in ('p_hat', 'prior') and c ? 'effort_factor' and c ? 'sla_adherence'),
       count(*)::text from (select pg_temp.v('XMIN')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c where (c ->> 'eligible')::boolean;
-- a fix_partner rule keeps its partner, mode 'rule', no lane (C30); every candidate still logs its stats (C47)
select pg_temp.set('R1', pg_temp.partner('zz-rule-one', 'ZZ Rule One')::text);
select pg_temp.set('R2', pg_temp.partner('zz-rule-two', 'ZZ Rule Two')::text);
select pg_temp.offer(pg_temp.v('R1')::bigint, pg_temp.v('PRULE')::bigint); select pg_temp.offer(pg_temp.v('R2')::bigint, pg_temp.v('PRULE')::bigint);
select pg_temp.rate(pg_temp.v('R1')::bigint, 'fixed', 9000); select pg_temp.rate(pg_temp.v('R2')::bigint, 'fixed', 7000);
insert into b2b.routing_rules (name, priority, conditions, action, partner_ids) values ('M31 fix R2', 10, '{"course_keys":["zzrule"]}', 'fix_partner', array[pg_temp.v('R2')::bigint]);
select pg_temp.set('LRULE', pg_temp.lead('919876531402', 'ZZRule')::text);
insert into t select 'XRULE', pg_temp.decide(pg_temp.v('LRULE')::bigint, pg_temp.v('seed_lo'), false)::text;
insert into r select 'fix_partner_rule_no_lane',
       x ->> 'partner_id' = pg_temp.v('R2') and x ->> 'mode' = 'rule' and (x ->> 'exploration_share')::numeric = 0 and (x ->> 'draw') is null
       and jsonb_array_length(x -> 'rules') = 1 and x -> 'rules' -> 0 ->> 'effect' = '1 kept' and x -> 'rules' -> 0 ->> 'action' = 'fix_partner'
       and exists (select 1 from jsonb_array_elements(x -> 'excluded') e where e ->> 'partner_id' = pg_temp.v('R1') and e ->> 'cause' = 'rule'),
       coalesce(x ->> 'partner_id', '-') || ' ' || (x -> 'rules')::text from (select pg_temp.v('XRULE')::jsonb x) z;
insert into r select 'c47_fix_partner_logs_stats', bool_and((c ->> 'p_hat') is not null and c ->> 'p_source' in ('p_hat', 'prior')), count(*)::text
  from (select pg_temp.v('XRULE')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c where (c ->> 'eligible')::boolean;
insert into r select 'rule_matches_new_keys',
       b2b.rule_matches('{"states":["delhi"]}', l, i) and not b2b.rule_matches('{"states":["Goa"]}', l, i)
       and b2b.rule_matches('{"paid":false}', l, i) and not b2b.rule_matches('{"paid":true}', l, i)
       and not b2b.rule_matches('{"specializations":["Finance"]}', l, i) and b2b.rule_matches('{"course_keys":["zzrule"],"levels":["PG"],"modes":["Online"]}', l, i)
       and not b2b.rule_matches(jsonb_build_object('university_ids', jsonb_build_array(pg_temp.v('U1'))), l, i) and b2b.rule_matches('{}', l, i),
       null
  from public.student_leads l, lateral (select b2b.lead_interest(l) i) ii where l.id = pg_temp.v('LRULE')::bigint;
-- no rate scores 0 and sorts last
select pg_temp.set('N1', pg_temp.partner('zz-nr-one', 'ZZ NoRate')::text);
select pg_temp.set('N2', pg_temp.partner('zz-nr-two', 'ZZ Rated')::text);
select pg_temp.offer(pg_temp.v('N1')::bigint, pg_temp.v('PNR')::bigint); select pg_temp.offer(pg_temp.v('N2')::bigint, pg_temp.v('PNR')::bigint);
select pg_temp.rate(pg_temp.v('N2')::bigint, 'fixed', 6000);
select pg_temp.set('LNR', pg_temp.lead('919876531403', 'ZZNorate')::text);
insert into r select 'no_rate_scores_zero', x ->> 'partner_id' = pg_temp.v('N2') and (c1 ->> 'score')::numeric = 0 and not (c1 ->> 'has_rate')::boolean and (c1 ->> 'cpe') is null
       and (c1 ->> 'tie_rank')::int = 2 and (c1 ->> 'eligible')::boolean, coalesce(c1 ->> 'score', '-')
  from (select pg_temp.decide(pg_temp.v('LNR')::bigint, pg_temp.v('seed_hi'), false) x) z, lateral (select pg_temp.cand(x, pg_temp.v('N1')) c1) c;

-- ========================================================================================================
-- The manual route (PART 6.3): a B2C-held lead goes to partners by hand, without the lane; the API's refusals
-- ========================================================================================================
select pg_temp.set('LM', pg_temp.lead('919876531501', 'ZZManual')::text);
insert into t select 'XMa', pg_temp.decide(pg_temp.v('LM')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'no_partner_offers_programme_to_b2c_sales',
       x ->> 'destination' = 'in_house' and x ->> 'reason' = 'no_partner_offers_programme' and x ->> 'b2c_lane' = 'sales' and x ->> 'mode' = 'fallback' and (x ->> 'interest_rank') is null
       and x -> 'interests' -> 0 ->> 'outcome' = 'no_offer' and a.status = 'handed_off' and a.reason = 'no_partner_offers_programme' and a.origin = 'auto'
       and exists (select 1 from b2b.events ev where ev.type = 'b2c.lead_handed_off' and ev.allocation_id = a.id and ev.payload -> 'handling' ->> 'job' = 'sell'
                     and ev.payload ->> 'reason' = 'no_partner_offers_programme' and ev.payload -> 'hold' ->> 'kind' = 'selling')
       and b2b.route_outlook(l) ->> 'outlook' = 'b2c_held' and b2b.route_outlook(l) ->> 'reason' = 'no_partner_offers_programme',
       coalesce(x ->> 'reason', '-')
  from (select pg_temp.v('XMa')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join public.student_leads l on l.id = a.lead_id;
select pg_temp.set('MA', pg_temp.partner('zz-man-a', 'ZZ Manual A')::text);
select pg_temp.set('MB', pg_temp.partner('zz-man-b', 'ZZ Manual B')::text);
select pg_temp.offer(pg_temp.v('MA')::bigint, pg_temp.v('PMAN')::bigint); select pg_temp.offer(pg_temp.v('MB')::bigint, pg_temp.v('PMAN')::bigint);
select pg_temp.rate(pg_temp.v('MA')::bigint, 'fixed', 9000); select pg_temp.rate(pg_temp.v('MB')::bigint, 'fixed', 6000);
select pg_temp.recv(pg_temp.v('MA')::bigint, 'zzmanual|PG|Online', 35, interval '20 days');
select set_config('b2b.route_seed', pg_temp.v('seed_lo'), true);
insert into t select 'XMb', b2b.route_to_partners_core(pg_temp.v('LM')::bigint, 'm31 manual route test')::text;
insert into r select 'manual_route_no_lane_origin_to_partners',
       x ->> 'destination' = 'partner' and x ->> 'partner_id' = pg_temp.v('MA') and x ->> 'mode' = 'manual' and x ->> 'how' = 'to_partners' and x ->> 'origin' = 'to_partners'
       and (x ->> 'exploration_share')::numeric = 0 and (x ->> 'draw') is null and not (x -> 'lane' ->> 'applied')::boolean and (x ->> 'selection_probability')::numeric = 1
       and (pg_temp.cand(x, pg_temp.v('MB')) ->> 'under_tested')::boolean and x ->> 'outcome' = 'decided'
       and a.origin = 'to_partners' and a.mode = 'manual' and not a.override and a.status = 'queued' and d.how = 'to_partners' and d.mode = 'manual' and d.draw is null and d.reason = 'm31 manual route test'
       and old.status = 'closed' and old.outcome = 'routed_to_partners' and l.destination_type = 'partner' and l.allocation_id = a.id
       and exists (select 1 from b2b.events ev where ev.type = 'lead.route_to_partners' and ev.lead_id = l.id)
       and exists (select 1 from b2b.events ev where ev.type = 'lead.routed' and ev.allocation_id = a.id and ev.payload ->> 'origin' = 'to_partners' and (ev.payload ->> 'manual_from_b2c')::boolean),
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'mode', '-') || ' share ' || coalesce(x ->> 'exploration_share', '-')
  from (select pg_temp.v('XMb')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id
       join public.student_leads l on l.id = a.lead_id join b2b.allocations old on old.id = (pg_temp.v('XMa')::jsonb ->> 'allocation_id')::bigint;
-- the API: 422 with an error code for a lead that is not held, has no consent, or is partner-barred; 'invalid' otherwise
select pg_temp.set('LNH', pg_temp.lead('919876531502', 'ZZManual')::text);
insert into r select 'api_not_held_422', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 422 and x ->> 'error_code' = 'not_held', x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_m31test_key_0001', pg_temp.v('LNH')::bigint, 'm31 api test') x) z;
select pg_temp.set('LNC', pg_temp.lead('919876531503', 'ZZManual', '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
insert into r select 'api_no_consent_422', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 422 and x ->> 'error_code' = 'no_consent', x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_m31test_key_0001', pg_temp.v('LNC')::bigint, 'm31 api test') x) z;
insert into r select 'api_short_reason_invalid', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 422 and x ->> 'error_code' = 'invalid', x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_m31test_key_0001', pg_temp.v('LNH')::bigint, 'x') x) z;
insert into r select 'api_bad_key_401', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 401, x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_wrong_key', pg_temp.v('LNH')::bigint, 'm31 api test') x) z;
insert into r select 'api_unknown_lead_404', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 404, x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_m31test_key_0001', 999999999, 'm31 api test') x) z;
-- R2: a partner-barred lead never reaches a partner, not even by hand; it goes to B2C sales with the bar's handling
select pg_temp.set('LB', pg_temp.lead('919876531504', 'ZZManual')::text);
select b2b.partner_bar_set(pg_temp.v('LB')::bigint, 'duplicate', null, 'engine');
insert into r select 'api_partner_barred_422', not (x ->> 'ok')::boolean and (x ->> 'status')::int = 422 and x ->> 'error_code' = 'partner_barred' and x ->> 'error' like 'partner_barred: partner-barred (duplicate) since %', x ->> 'error'
  from (select b2b.api_route_to_partners('eb2b_m31test_key_0001', pg_temp.v('LB')::bigint, 'm31 api test') x) z;
insert into t select 'XB', pg_temp.decide(pg_temp.v('LB')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'r2_barred_lead_to_b2c_sales',
       x ->> 'destination' = 'in_house' and x ->> 'reason' = 'partner_barred' and x ->> 'mode' = 'rule' and x ->> 'b2c_lane' = 'sales' and (x -> 'bar' ->> 'reason') = 'duplicate'
       and a.reason = 'partner_barred' and a.mode = 'rule'
       and exists (select 1 from b2b.events ev where ev.type = 'b2c.lead_handed_off' and ev.allocation_id = a.id and ev.payload -> 'handling' ->> 'assignment' = 'round_robin_now'
                     and ev.payload -> 'handling' ->> 'first_contact_script' = 'neutral_adviser' and ev.payload -> 'partner_bar' ->> 'reason' = 'duplicate')
       and b2b.route_outlook(l) ->> 'outlook' = 'b2c_sales' and b2b.route_outlook(l) ->> 'reason' = 'partner_barred',
       coalesce(x ->> 'reason', '-') || ' ' || coalesce(x ->> 'mode', '-')
  from (select pg_temp.v('XB')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join public.student_leads l on l.id = a.lead_id;
select pg_temp.set('LB2', pg_temp.lead('919876531505', 'ZZManual')::text);
select b2b.partner_bar_set(pg_temp.v('LB2')::bigint, 'lost', null, 'backfill');
do $x$ declare e text; x jsonb; begin
  begin perform pg_temp.decide(pg_temp.v('LB2')::bigint, pg_temp.v('seed_hi'), true, 'reroute'); e := 'routed'; exception when others then e := sqlerrm; end;
  insert into r values ('r2_manual_context_raises_on_bar', e like 'partner_barred: partner-barred (lost) since %', e);
  x := pg_temp.decide(pg_temp.v('LB2')::bigint, pg_temp.v('seed_hi'), false, 'to_partners');
  insert into r values ('r2_manual_preview_shows_b2c', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'partner_barred' and not (x ->> 'committed')::boolean, x ->> 'reason');
end $x$;

-- ========================================================================================================
-- R8: consent is asked on the automatic path; NO or the b2c_sales policy sends the lead to B2C sales
-- ========================================================================================================
select pg_temp.set('LC', pg_temp.lead('919876531601', 'ZZEleven', '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
insert into r select 'r8_preview_consent_request', x ->> 'outcome' = 'consent_request' and x ->> 'destination' = 'consent_request' and not (x ->> 'committed')::boolean
       and not (x -> 'consent' ->> 'given')::boolean and (x ->> 'partner_id') is null, coalesce(x ->> 'outcome', '-')
  from (select pg_temp.decide(pg_temp.v('LC')::bigint, pg_temp.v('seed_hi'), false) x) z;
insert into t select 'XC', pg_temp.decide(pg_temp.v('LC')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'r8_commit_creates_request_without_decision',
       x ->> 'outcome' = 'consent_requested' and x ->> 'destination' = 'consent_requested' and (x ->> 'committed')::boolean and (x -> 'consent_request' ->> 'request_id') is not null
       and (x ->> 'decision_id') is null and (x ->> 'allocation_id') is null
       and exists (select 1 from b2b.consent_requests q where q.lead_id = pg_temp.v('LC')::bigint and q.status in ('queued', 'requested', 'sent', 'unsendable') and q.context = 'decision')
       and not exists (select 1 from b2b.engine_decisions d where d.lead_id = pg_temp.v('LC')::bigint)
       and (select l.destination_type from public.student_leads l where l.id = pg_temp.v('LC')::bigint) is null
       and exists (select 1 from b2b.lead_waits w where w.lead_id = pg_temp.v('LC')::bigint and w.why = 'awaiting partner-sharing consent'),
       coalesce((x -> 'consent_request')::text, '-')
  from (select pg_temp.v('XC')::jsonb x) z;
insert into r select 'r8_second_preview_is_pending', x ->> 'outcome' = 'consent_pending' and not (x ->> 'committed')::boolean
       and b2b.route_outlook(l) ->> 'outlook' = 'consent_pending' and b2b.pool_lead(l, true) ->> 'group' = 'awaiting_consent',
       coalesce(x ->> 'outcome', '-') from public.student_leads l, lateral (select pg_temp.decide(l.id, pg_temp.v('seed_hi'), true) x) z where l.id = pg_temp.v('LC')::bigint;
update b2b.settings set value = value || '{"consent_policy":"b2c_sales"}' where key = 'engine';
select pg_temp.set('LC2', pg_temp.lead('919876531602', 'ZZEleven', '{"consent_partner_share_at":null,"consent_text_version":null}')::text);
insert into r select 'r8_policy_b2c_sales', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'no_partner_consent' and x ->> 'mode' = 'fallback' and x ->> 'b2c_lane' = 'sales'
       and b2b.route_outlook(l) ->> 'outlook' = 'b2c_sales' and b2b.route_outlook(l) ->> 'reason' = 'no_partner_consent', coalesce(x ->> 'reason', '-')
  from public.student_leads l, lateral (select pg_temp.decide(l.id, pg_temp.v('seed_hi'), false) x) z where l.id = pg_temp.v('LC2')::bigint;
update b2b.settings set value = value || '{"consent_policy":"ask"}' where key = 'engine';

-- ========================================================================================================
-- R1, R5, R6, R7 and the sandbox (the rules test file covers them in depth)
-- ========================================================================================================
select pg_temp.set('LT', pg_temp.lead('910000000311', 'ZZEleven')::text);
insert into r select 'r1_test_lead_writes_nothing', x ->> 'destination' = 'none' and x ->> 'reason' = 'test_lead' and x ->> 'outcome' = 'test_lead' and not (x ->> 'committed')::boolean
       and (x ->> 'is_test')::boolean and not exists (select 1 from b2b.engine_decisions d where d.lead_id = pg_temp.v('LT')::bigint)
       and b2b.route_outlook(l) ->> 'outlook' = 'none' and b2b.pool_lead(l, true) ->> 'group' = 'test',
       coalesce(x ->> 'reason', '-') from public.student_leads l, lateral (select pg_temp.decide(l.id, pg_temp.v('seed_hi'), true) x) z where l.id = pg_temp.v('LT')::bigint;
insert into r select 'r1_sandbox_without_test_endpoint', x ->> 'destination' = 'none' and x ->> 'reason' = 'no_sandbox_partner' and not (x ->> 'committed')::boolean, coalesce(x ->> 'reason', '-')
  from (select pg_temp.decide(pg_temp.v('LT')::bigint, pg_temp.v('seed_hi'), true, 'sandbox') x) z;
update b2b.partners set test_endpoint = 'https://sandbox.example.test/leads' where id = pg_temp.v('A')::bigint;
insert into t select 'XSB', pg_temp.decide(pg_temp.v('LT')::bigint, pg_temp.v('seed_hi'), true, 'sandbox')::text;
insert into r select 'r1_sandbox_routes_test_allocation', x ->> 'destination' = 'partner' and x ->> 'partner_id' = pg_temp.v('A') and x ->> 'mode' = 'rule' and x ->> 'origin' = 'sandbox'
       and a.is_test and a.origin = 'sandbox' and a.status = 'queued' and (x ->> 'exploration_share')::numeric = 0 and d.is_test and d.how = 'sandbox'
       and exists (select 1 from b2b.events ev where ev.type = 'lead.routed' and ev.allocation_id = a.id and (ev.payload ->> 'test')::boolean),
       coalesce(x ->> 'partner_id', '-') || ' ' || coalesce(x ->> 'origin', '-')
  from (select pg_temp.v('XSB')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id;
do $x$ declare e text; begin
  begin perform pg_temp.decide(pg_temp.v('L11')::bigint, pg_temp.v('seed_hi'), true, 'sandbox'); e := 'routed'; exception when others then e := sqlerrm; end;
  insert into r values ('sandbox_refused_for_real_lead', e in ('the sandbox is for test leads', 'this lead is already routed'), e);
  begin perform pg_temp.decide(pg_temp.v('L11')::bigint, pg_temp.v('seed_hi'), true, 'auto'); e := 'routed'; exception when others then e := sqlerrm; end;
  insert into r values ('already_routed_raises', e = 'this lead is already routed', e);
  begin perform pg_temp.decide(pg_temp.v('L11')::bigint, pg_temp.v('seed_hi'), false, 'nonsense'); e := 'routed'; exception when others then e := sqlerrm; end;
  insert into r values ('unknown_how_raises', e = 'unknown routing request', e);
end $x$;
select pg_temp.set('LR6', pg_temp.lead('919876531701', 'ZZEleven', '{"source":"b2c_created"}')::text);
insert into t select 'XR6', pg_temp.decide(pg_temp.v('LR6')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'r6_b2c_created', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'b2c_created' and x ->> 'mode' = 'rule' and x ->> 'b2c_lane' = 'sales' and a.status = 'handed_off' and a.mode = 'rule'
       and exists (select 1 from b2b.events ev where ev.type = 'b2c.lead_handed_off' and ev.allocation_id = a.id and ev.payload ->> 'reason' = 'b2c_created'),
       coalesce(x ->> 'reason', '-') from (select pg_temp.v('XR6')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint;
select pg_temp.set('LR5', pg_temp.lead('919876531702', 'ZZEleven', '{"classification":"JUNK"}')::text);
insert into t select 'XR5', pg_temp.decide(pg_temp.v('LR5')::bigint, pg_temp.v('seed_hi'), true)::text;
insert into r select 'r5_junk_not_passed', x ->> 'destination' = 'not_passed' and x ->> 'reason' = 'junk' and (x ->> 'committed')::boolean and (x ->> 'decision_id') is null
       and exists (select 1 from b2b.not_passed np where np.lead_id = pg_temp.v('LR5')::bigint and np.reason = 'junk' and np.passed_at is null and not np.override and np.detail is null)
       and exists (select 1 from b2b.events ev where ev.type = 'lead.not_passed' and ev.lead_id = pg_temp.v('LR5')::bigint)
       and not exists (select 1 from b2b.engine_decisions d where d.lead_id = pg_temp.v('LR5')::bigint)
       and (select l.destination_type from public.student_leads l where l.id = pg_temp.v('LR5')::bigint) is null,
       coalesce(x ->> 'reason', '-') from (select pg_temp.v('XR5')::jsonb x) z;
select pg_temp.set('LR7', pg_temp.lead('919876531703', null)::text);
insert into t select 'XR7', pg_temp.decide(pg_temp.v('LR7')::bigint, pg_temp.v('seed_hi'), true, 'auto', 'a note that must not join the reason')::text;
insert into r select 'r7_not_qualified_nurture', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'not_qualified' and x ->> 'b2c_lane' = 'nurture' and x ->> 'mode' = 'fallback'
       and d.reason = 'not_qualified' and d.class = 'unqualified' and a.b2c_lane = 'nurture'
       and exists (select 1 from b2b.events ev where ev.type = 'b2c.lead_handed_off' and ev.allocation_id = a.id and ev.payload -> 'missing' ? 'no_course' and ev.payload -> 'handling' ->> 'job' = 'qualify'),
       coalesce(d.reason, '-') from (select pg_temp.v('XR7')::jsonb x) z join b2b.allocations a on a.id = (x ->> 'allocation_id')::bigint join b2b.engine_decisions d on d.id = a.engine_decision_id;

-- ========================================================================================================
-- C54: a partner is credited with the lead's progress only while it holds the lead (m31c allocation_outcomes)
-- ========================================================================================================
select pg_temp.set('LO', pg_temp.lead('919876531801', 'ZZManual')::text);
with x as (insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, accepted_at, pushed_at, created_at, is_test, origin, outcome, outcome_at)
           values (pg_temp.v('LO')::bigint, 1, 'zzmanual|PG|Online', 'partner', pg_temp.v('MA')::bigint, 'closed', 'commission_first', 1, now() - interval '10 days', now() - interval '10 days',
                   now() - interval '10 days', false, 'auto', 'lost', now() - interval '2 days') returning id)
insert into t select 'A1', id::text from x;
with x as (insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, status, mode, attempt_no, reason, b2c_lane, created_at, is_test, origin)
           values (pg_temp.v('LO')::bigint, 1, 'zzmanual|PG|Online', 'in_house', 'handed_off', 'fallback', 2, 'partner_lost', 'nurture', now() - interval '2 days', false, 'auto') returning id)
insert into t select 'A2', id::text from x;
update public.student_leads set allocation_id = pg_temp.v('A2')::bigint, destination_type = 'in_house', applied_at = now(), first_contacted_at = now(), stage = 'applied' where id = pg_temp.v('LO')::bigint;
insert into r select 'c54_young_stage_not_credited_after_handoff', o.stage = 'accepted', o.stage from b2b.allocation_outcomes() o where o.allocation_id = pg_temp.v('A1')::bigint;
update public.student_leads set allocation_id = pg_temp.v('A1')::bigint where id = pg_temp.v('LO')::bigint;
insert into r select 'c54_young_stage_credited_while_held', o.stage = 'applied', o.stage from b2b.allocation_outcomes() o where o.allocation_id = pg_temp.v('A1')::bigint;
update public.student_leads set applied_at = null, first_contacted_at = null, stage = 'applied' where id = pg_temp.v('LO')::bigint;
insert into r select 'c54_stage_rank_alone_credits', o.stage = 'applied', o.stage from b2b.allocation_outcomes() o where o.allocation_id = pg_temp.v('A1')::bigint;
update public.student_leads set stage = 'lost' where id = pg_temp.v('LO')::bigint;
insert into r select 'c54_lost_display_stage_not_applied', o.stage = 'accepted', o.stage from b2b.allocation_outcomes() o where o.allocation_id = pg_temp.v('A1')::bigint;

-- ========================================================================================================
-- C125: no sampling in the engine; ten candidates decide in under a second. The stepped SLA factor.
-- ========================================================================================================
insert into r select 'c125_no_thompson_in_engine', bool_and(prosrc !~ 'thompson_pick'), count(*)::text from pg_proc
 where oid in (to_regprocedure('b2b.route_decide(bigint,boolean,text,text)'), to_regprocedure('b2b.stage_score(jsonb,jsonb)'), to_regprocedure('b2b.route_score(bigint,text,jsonb,numeric,boolean)'));
do $x$ declare i int; v_p bigint; begin
  for i in 1 .. 10 loop
    v_p := pg_temp.partner('zz-ten-' || i, 'ZZ Ten ' || i);
    perform pg_temp.offer(v_p, pg_temp.v('PTEN')::bigint);
    perform pg_temp.rate(v_p, 'fixed', 1000 * i);
    if i = 10 then perform pg_temp.set('TEN10', v_p::text); end if;
  end loop;
end $x$;
select pg_temp.set('LTEN', pg_temp.lead('919876531901', 'ZZTen')::text);
do $x$ declare t0 timestamptz; x jsonb; ms numeric; begin
  t0 := clock_timestamp();
  x := pg_temp.decide(pg_temp.v('LTEN')::bigint, pg_temp.v('seed_hi'), false);
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  insert into r values ('c125_ten_candidates_under_1s', ms < 1000 and x ->> 'destination' = 'partner' and x ->> 'partner_id' = pg_temp.v('TEN10') and jsonb_array_length(x -> 'candidates') = 10, ms::text || ' ms');
end $x$;
insert into r select 'sla_factor_stepped', b2b.sla_factor_of(0.95, 10, s) = 1.0 and b2b.sla_factor_of(0.90, 10, s) = 0.95 and b2b.sla_factor_of(0.85, 10, s) = 0.95
       and b2b.sla_factor_of(0.55, 10, s) = 0.80 and b2b.sla_factor_of(null, 0, s) = 1.0 and b2b.sla_factor_of(0.5, 10, s || '{"enabled":false}') = 1.0,
       b2b.sla_factor_of(0.90, 10, s)::text from (select b2b.engine_params(true) -> 'sla' s) z;

-- ========================================================================================================
-- Checks of functions replaced by m31l (skipped with ok until that migration is applied)
-- ========================================================================================================
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; x jsonb; y jsonb; begin
  if pg_temp.has('b2b.decision_replay(bigint)', 'lane_applied') then
    x := b2b.decision_replay((pg_temp.v('X11b')::jsonb ->> 'decision_id')::bigint);
    insert into r values ('c128_replay_exploration_decision', (x ->> 'replayable')::boolean and (x ->> 'reproduced')::boolean and (x ->> 'lane_applied')::boolean and x ->> 'stage' = 'A', x::text);
    x := b2b.decision_replay((pg_temp.v('XMb')::jsonb ->> 'decision_id')::bigint);
    insert into r values ('c128_replay_manual_route_no_lane', (x ->> 'replayable')::boolean and (x ->> 'reproduced')::boolean and not (x ->> 'lane_applied')::boolean, x::text);
    x := b2b.decision_replay((pg_temp.v('XMIN')::jsonb ->> 'decision_id')::bigint);
    insert into r values ('c128_replay_minimum_no_lane', (x ->> 'replayable')::boolean and (x ->> 'reproduced')::boolean and not (x ->> 'lane_applied')::boolean, x::text);
  else
    insert into r values ('c128_replay_exploration_decision', true, 'skipped: m31l decision_replay not applied');
  end if;
  if pg_temp.has('b2b.engine_settings_save(jsonb,text)', 'Addendum 3') then
    begin perform b2b.engine_settings_save('{"exploration_share":0.3}', 'm31 test'); e := 'saved'; exception when others then e := sqlerrm; end;
    insert into r values ('engine_settings_save_refuses_exploration_share', e like '%Addendum 3%', e);
    begin perform b2b.engine_settings_save('{"kill_switch":true}', 'm31 test'); e := 'saved'; exception when others then e := sqlerrm; end;
    insert into r values ('c60_kill_switch_save_refused', e like '%Addendum 3%', e);
    begin perform b2b.segment_policy_save('zztwelve|PG|Online', '{"pin":{"mode":"performance"}}', 'm31 test'); e := 'saved'; exception when others then e := sqlerrm; end;
    insert into r values ('segment_policy_save_refuses_pins', e like '%Addendum 3%', e);
    begin perform b2b.partner_weight_save(pg_temp.v('X')::bigint, 1.1, now() + interval '7 days', 'm31 test'); e := 'saved'; exception when others then e := sqlerrm; end;
    insert into r values ('partner_weight_save_refuses', e like '%Addendum 3%', e);
    begin perform b2b.engine_policy_save('{"mc_draws":1000}', 'm31 test'); e := 'saved'; exception when others then e := sqlerrm; end;
    insert into r values ('c125_engine_policy_save_refuses_mc_draws', e <> 'saved', e);
  else
    insert into r values ('engine_settings_save_refuses_exploration_share', true, 'skipped: m31l admin saves not applied');
  end if;
  if pg_temp.has('b2b.routing_segment(text)', 'stage_score') then
    x := b2b.routing_segment('zzten|PG|Online');
    insert into r values ('c59_segment_page_cold_start',
      (select bool_and((p ->> 'score')::numeric = (p ->> 'cpe')::numeric) from jsonb_array_elements(x -> 'partners') p where (p ->> 'competing')::boolean)
      and (select p ->> 'partner_id' from jsonb_array_elements(x -> 'partners') p where (p ->> 'tie_rank')::int = 1) = pg_temp.v('TEN10')
      and coalesce(x -> 'mode' ->> 'stage', x ->> 'stage') = 'A', (x -> 'mode')::text);
    x := b2b.routing_segment('zztwelve|PG|Online');
    y := pg_temp.v('X12')::jsonb;
    insert into r values ('c58_segment_page_matches_decision',
      (select (p ->> 'score')::numeric from jsonb_array_elements(x -> 'partners') p where p ->> 'partner_id' = pg_temp.v('X')) = (pg_temp.cand(y, pg_temp.v('X')) ->> 'score')::numeric
      and (select (p ->> 'effort_factor')::numeric from jsonb_array_elements(x -> 'partners') p where p ->> 'partner_id' = pg_temp.v('Y')) = (pg_temp.cand(y, pg_temp.v('Y')) ->> 'effort_factor')::numeric,
      (select (p - 'effort_detail')::text from jsonb_array_elements(x -> 'partners') p where p ->> 'partner_id' = pg_temp.v('X')));
  else
    insert into r values ('c59_segment_page_cold_start', true, 'skipped: m31l routing_segment not applied');
  end if;
end $x$;
reset role;

select * from r order by name;
rollback;
