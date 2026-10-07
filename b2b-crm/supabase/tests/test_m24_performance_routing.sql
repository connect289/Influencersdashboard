-- M24 performance routing on STAGING, rolled back. Two fixture partners (A, B) in segment zzm24|PG|Online with hand-made
-- outcomes: A has 10 matured leads (6 at 60 days, 3 enrolled; 4 at 90 days, 1 enrolled) and 1 young lead (30 days,
-- accepted); B has 10 matured leads at 60 days, 1 enrolled. With maturity 60, half-life 30, prior strength 20 and default
-- 0.05 the numbers are computed by hand below. Then: the seeded sampler, the mode switch (performance once 2 partners have
-- 5 matured leads), reproducible Thompson sampling and its logged probability, pins, the seeded exploration lane, the
-- holdout ignoring AI changes, the kill switch, the share cap, partner weights, validation, the Admin reads, replay,
-- auto-pause, the drop alert, and a real route_decide logging seed, mode and candidate numbers.
-- Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d1","role":"authenticated","aal":"aal2","email":"m24-admin@test.local"}', true)
$f$;
create function pg_temp.alloc(p_partner bigint, p_cycle int, p_age interval, p_enrolled boolean, p_status text default 'closed') returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, accepted_at, created_at, is_test)
  values (pg_temp.v('L')::bigint, p_cycle, 'zzm24|PG|Online', 'partner', p_partner, p_status, 'commission_first',
          case when p_status = 'closed' then now() - p_age + interval '1 hour' end, now() - p_age, false)
  returning id into v_id;
  if p_enrolled then
    insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on, verified_at)
    values (pg_temp.v('L')::bigint, p_cycle, p_partner, v_id, 'verified', 'b2b', (now() - p_age + interval '20 days')::date, now() - p_age + interval '25 days');
  end if;
  return v_id;
end $f$;
create function pg_temp.kept() returns jsonb language sql as $f$
  select jsonb_build_array(
    jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'name', 'M24 Alpha', 'cpe', 10000, 'has_rate', true, 'segment_leads', 11, 'leads_week', 0, 'leads_today', 0, 'leads_month', 0),
    jsonb_build_object('partner_id', pg_temp.v('B')::bigint, 'name', 'M24 Beta', 'cpe', 12000, 'has_rate', true, 'segment_leads', 10, 'leads_week', 0, 'leads_today', 0, 'leads_month', 0));
$f$;
create function pg_temp.score(p_seed numeric) returns jsonb language sql as $f$
  select b2b.route_score(pg_temp.v('L')::bigint, 'zzm24|PG|Online', pg_temp.kept(), p_seed, false);
$f$;
create function pg_temp.policy(p jsonb) returns void language sql as $f$
  update b2b.settings set value = value || p where key = 'engine_policy';
$f$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d1', 'm24-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000d1', 'm24-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d2', 'nobody24@test.local', 'authenticated', 'authenticated');

update b2b.settings set value = value || '{"maturity_days":60,"half_life_days":30,"prior_weight":20,"default_p_enroll":0.05,"min_matured_leads":5,
                                         "exploration_share":0,"kill_switch":false,"fixed_split":{}}'::jsonb
                                   || jsonb_build_object('speed_factor', '{"enabled":false,"bounds":[0.85,1.15]}'::jsonb,
                                                         'reliability_factor', '{"enabled":false,"bounds":[0.7,1.0]}'::jsonb)
 where key = 'engine';
select pg_temp.policy('{"holdout_share":0,"mc_draws":200,"leading_weight":0.5,"leading_min_days":3,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}');

with x as (insert into b2b.partners (slug, name, status) values ('m24-alpha', 'M24 Alpha', 'active') returning id) insert into t select 'A', id::text from x;
with x as (insert into b2b.partners (slug, name, status) values ('m24-beta', 'M24 Beta', 'active') returning id) insert into t select 'B', id::text from x;
insert into b2b.live_switches (scope, live, reason) select 'partner:' || v, true, 'm24 test' from t where k in ('A', 'B')
on conflict (scope) do update set live = true;
do $x$ begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876504901', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Perf Test', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'consent_partner_share_at', now())));
end $x$;
insert into t select 'L', id::text from public.student_leads where whatsapp_number = '919876504901';

-- fixtures: A 6 x 60d (3 enrolled), 4 x 90d (1 enrolled), 1 x 30d young; B 10 x 60d (1 enrolled)
select pg_temp.alloc(pg_temp.v('A')::bigint, n, interval '60 days', n <= 3) from generate_series(1, 6) n;
select pg_temp.alloc(pg_temp.v('A')::bigint, n, interval '90 days', n = 7) from generate_series(7, 10) n;
select pg_temp.alloc(pg_temp.v('A')::bigint, 11, interval '30 days', false);
select pg_temp.alloc(pg_temp.v('B')::bigint, n, interval '60 days', n = 12) from generate_series(12, 21) n;

-- ---------- sampler ----------
insert into r select 'u01_range_and_repeatable', b2b.u01('0.123', 'x') > 0 and b2b.u01('0.123', 'x') < 1 and b2b.u01('0.123', 'x') = b2b.u01('0.123', 'x')
                       and b2b.u01('0.123', 'x') <> b2b.u01('0.123', 'y'), b2b.u01('0.123', 'x')::text;
insert into r select 'beta_sample_mean', abs(avg(b2b.beta_sample(2, 8, 's', n::text)) - 0.2) < 0.02, round(avg(b2b.beta_sample(2, 8, 's', n::text))::numeric, 4)::text
  from generate_series(1, 2000) n;
insert into r select 'beta_sample_small_shape', min(x) >= 0 and max(x) <= 1 and abs(avg(x) - 0.3 / (0.3 + 5)) < 0.02, round(avg(x)::numeric, 4)::text
  from (select b2b.beta_sample(0.3, 5, 'q', n::text) x from generate_series(1, 2000) n) z;

-- ---------- statistics (hand-computed) ----------
select b2b.stats_refresh();
insert into t select 'r_acc', rate::text from b2b.stage_rates where stage = 'accepted';
insert into t select 'g_ref', coalesce(sum(case when e.status in ('refunded', 'cancelled') then 1 else 0 end)::numeric / nullif(count(*), 0), 0)::text
  from public.enrollments e where e.source_product = 'b2b' and e.status in ('verified', 'refunded', 'cancelled');
insert into r select 'segment_prior', s.prior = 0.14474 and s.n_matured = 20 and s.partners_matured = 2 and s.auto_mode = 'performance',
                     s.prior || ' ' || s.n_matured || ' ' || s.partners_matured || ' ' || s.auto_mode
  from b2b.segment_stats s where s.variant = 'base' and s.segment = 'zzm24|PG|Online';
insert into r select 'partner_a_weighted', s.n_leads = 11 and s.n_matured = 10 and s.w_matured = 8 and s.w_enrolled = 3.5 and s.n_young = 1 and s.w_young = 0.25,
                     s.n_leads || ' ' || s.n_matured || ' ' || s.w_matured || ' ' || s.w_enrolled || ' ' || s.w_young
  from b2b.partner_segment_stats s where s.variant = 'base' and s.segment = 'zzm24|PG|Online' and s.partner_id = pg_temp.v('A')::bigint;
insert into r select 'partner_a_posterior',
                     abs(s.alpha - (6.3948 + 0.25 * pg_temp.v('r_acc')::numeric)) < 0.0002 and abs(s.beta - (21.8552 - 0.25 * pg_temp.v('r_acc')::numeric)) < 0.0002
                     and abs(s.p_hat - (6.3948 + 0.25 * pg_temp.v('r_acc')::numeric) / 28.25) < 0.00001,
                     s.alpha || ' ' || s.beta || ' ' || s.p_hat
  from b2b.partner_segment_stats s where s.variant = 'base' and s.segment = 'zzm24|PG|Online' and s.partner_id = pg_temp.v('A')::bigint;
insert into r select 'partner_b_posterior', s.alpha = 3.8948 and s.beta = 26.1052 and s.p_hat = round(3.8948 / 30, 5), s.alpha || ' ' || s.beta || ' ' || s.p_hat
  from b2b.partner_segment_stats s where s.variant = 'base' and s.segment = 'zzm24|PG|Online' and s.partner_id = pg_temp.v('B')::bigint;
insert into r select 'refund_rate_shrunk', s.refund_rate = round((0 + pg_temp.v('g_ref')::numeric * 20) / (4 + 20), 5), s.refund_rate::text
  from b2b.partner_segment_stats s where s.variant = 'base' and s.segment = 'zzm24|PG|Online' and s.partner_id = pg_temp.v('A')::bigint;
insert into r select 'course_rollup_row', count(*) = 2 and bool_and(s.is_rollup), count(*)::text
  from b2b.partner_segment_stats s where s.variant = 'base' and s.segment = 'zzm24|*|*';
insert into r select 'stage_rates_bounded', count(*) = 5 and bool_and(rate > 0 and rate < 1), count(*)::text from b2b.stage_rates;
insert into r select 'refresh_idempotent', (b2b.stats_refresh() ->> 'variants') = '["base"]'
                     and (select p_hat from b2b.partner_segment_stats where variant = 'base' and segment = 'zzm24|PG|Online' and partner_id = pg_temp.v('B')::bigint) = round(3.8948 / 30, 5), null;

-- ---------- performance mode: Thompson sampling ----------
insert into t select 's1', pg_temp.score(0.4242)::text;
insert into r select 'performance_mode', x ->> 'scoring_mode' = 'performance' and x ->> 'mode' = 'performance' and not (x ->> 'holdout')::boolean,
                     x ->> 'scoring_mode' from (select pg_temp.v('s1')::jsonb x) z;
insert into r select 'reproducible', pg_temp.score(0.4242) -> 'winner' ->> 'partner_id' = x -> 'winner' ->> 'partner_id'
                     and pg_temp.score(0.4242) ->> 'selection_probability' = x ->> 'selection_probability', x ->> 'selection_probability'
  from (select pg_temp.v('s1')::jsonb x) z;
insert into r select 'win_shares_sum_to_one', abs(sum((c ->> 'win_share')::numeric) - 1) < 0.001
                     and (select (c2 ->> 'win_share')::numeric from jsonb_array_elements(x -> 'candidates') c2 where c2 ->> 'partner_id' = x -> 'winner' ->> 'partner_id')
                         = (x ->> 'selection_probability')::numeric, sum((c ->> 'win_share')::numeric)::text
  from (select pg_temp.v('s1')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c group by x;
-- A: NCPL about 10000 x 0.23 = 2300; B: 12000 x 0.13 = 1560: A should win most draws though B pays more
insert into r select 'higher_ncpl_wins_most', (select (c ->> 'win_share')::numeric from jsonb_array_elements(x -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('A')) > 0.6,
                     x -> 'candidates' ->> 0 from (select pg_temp.v('s1')::jsonb x) z;
insert into r select 'candidate_numbers', (c ->> 'p_hat')::numeric > 0 and (c ->> 'alpha')::numeric > 0 and c ? 'ncpl' and c ? 'refund_rate' and (c ->> 'weight')::numeric = 1
                     and (c ->> 'matured_in_segment')::int = 10 and c ->> 'stats_segment' = 'zzm24|*|*', c::text
  from (select pg_temp.v('s1')::jsonb x) z, jsonb_array_elements(x -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('A');
insert into r select 'thompson_pick_matches', b2b.thompson_pick(x -> 'candidates', '0.4242', 200) ->> 'winner' = x -> 'winner' ->> 'partner_id', null
  from (select pg_temp.v('s1')::jsonb x) z;
insert into r select 'seeds_vary', count(distinct pg_temp.score(s / 100.0) -> 'winner' ->> 'partner_id') = 2, null from generate_series(1, 40) s;
insert into r select 'logged_probability_calibrated',
                     abs(avg(case when pg_temp.score(s / 1000.0) -> 'winner' ->> 'partner_id' = pg_temp.v('A') then 1 else 0 end)
                         - (select (c ->> 'win_share')::numeric from jsonb_array_elements(pg_temp.v('s1')::jsonb -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('A'))) < 0.15,
                     null from generate_series(1, 60) s;

-- ---------- commission first while immature, and pins ----------
update b2b.settings set value = value || '{"min_matured_leads":11}' where key = 'engine';
insert into r select 'immature_commission_first', x ->> 'scoring_mode' = 'commission_first' and x -> 'winner' ->> 'partner_id' = pg_temp.v('B')
                     and (x ->> 'selection_probability')::numeric = 1, x ->> 'scoring_mode' from (select pg_temp.score(0.4242) x) z;
update b2b.settings set value = value || '{"min_matured_leads":5}' where key = 'engine';
set local role authenticated;
select pg_temp.admin();
select b2b.segment_policy_save('zzm24|PG|Online', '{"pin":{"mode":"commission_first"}}', 'm24 test: keep the commission rule');
reset role;
insert into r select 'pin_commission_first', x ->> 'scoring_mode' = 'commission_first' and (x ->> 'pinned')::boolean and x -> 'winner' ->> 'partner_id' = pg_temp.v('B'),
                     x ->> 'scoring_mode' from (select pg_temp.score(0.4242) x) z;
-- seeded exploration lane in commission-first: the draw decides, and it is reproducible
set local role authenticated;
select pg_temp.admin();
select b2b.segment_policy_save('zzm24|PG|Online', '{"exploration_share":0.5}', 'm24 test: explore');
reset role;
insert into r select 'exploration_seeded', bool_and(case when b2b.u01((s / 100.0)::text, 'explore') < 0.5
                                                    then x ->> 'mode' = 'exploration' and x -> 'winner' ->> 'partner_id' = pg_temp.v('A') and (x ->> 'selection_probability')::numeric = 0.5
                                                    else x ->> 'mode' = 'commission_first' and x -> 'winner' ->> 'partner_id' = pg_temp.v('B') end)
                     and count(*) filter (where x ->> 'mode' = 'exploration') between 1 and 19, count(*) filter (where x ->> 'mode' = 'exploration')::text
  from (select s, pg_temp.score(s / 100.0) x from generate_series(1, 20) s) z;
set local role authenticated;
select pg_temp.admin();
select b2b.segment_policy_save('zzm24|PG|Online', '{"pin":null,"exploration_share":null}', 'm24 test: back to automatic');
reset role;
insert into r select 'pin_removed', pg_temp.score(0.4242) ->> 'scoring_mode' = 'performance'
                     and not (select value -> 'segments' from b2b.settings where key = 'engine_policy') ? 'zzm24|PG|Online', null;

-- ---------- holdout ignores the AI's changes ----------
select pg_temp.policy(jsonb_build_object('holdout_share', 0.5, 'segments',
  jsonb_build_object('zzm24|PG|Online', jsonb_build_object('pin', jsonb_build_object('mode', 'commission_first', 'source', 'ai', 'until', now() + interval '10 days')))));
insert into t select 'hold_seed', min(s / 1000.0)::text from generate_series(1, 200) s where b2b.u01((s / 1000.0)::text, 'holdout') < 0.5;
insert into t select 'ai_seed', min(s / 1000.0)::text from generate_series(1, 200) s where b2b.u01((s / 1000.0)::text, 'holdout') >= 0.5;
insert into r select 'holdout_ignores_ai_pin', (x ->> 'holdout')::boolean and x ->> 'scoring_mode' = 'performance', x::text
  from (select pg_temp.score(pg_temp.v('hold_seed')::numeric) x) z;
insert into r select 'ai_steered_follows_pin', not (x ->> 'holdout')::boolean and x ->> 'scoring_mode' = 'commission_first', x ->> 'scoring_mode'
  from (select pg_temp.score(pg_temp.v('ai_seed')::numeric) x) z;
insert into r select 'holdout_share_about_half', count(*) filter (where (pg_temp.score(s / 1000.0) ->> 'holdout')::boolean) between 10 and 30, null
  from generate_series(1, 40) s;
select pg_temp.policy('{"holdout_share":0,"segments":{}}');

-- ---------- partner weight ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.partner_weight_save(pg_temp.v('B')::bigint, 1.2, now() + interval '3 days', 'too much'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('weight_bounds', e = 'a partner weight is between 0.90 and 1.10', e);
  begin perform b2b.partner_weight_save(pg_temp.v('B')::bigint, 1.1, now() + interval '20 days', 'too long'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('weight_max_14_days', e = 'a partner weight ends within 14 days', e);
end $x$;
select b2b.partner_weight_save(pg_temp.v('B')::bigint, 1.1, now() + interval '7 days', 'm24 test: new counsellors');
reset role;
insert into r select 'weight_applied', (c ->> 'weight')::numeric = 1.1
                     and abs((c ->> 'ncpl')::numeric - round(12000 * (c ->> 'p_hat')::numeric * (1 - (c ->> 'refund_rate')::numeric) * 1.1, 2)) <= 0.01, c::text
  from jsonb_array_elements(pg_temp.score(0.4242) -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B');
select pg_temp.policy('{"holdout_share":1}');
update b2b.settings set value = jsonb_set(value, array['partner_weights', pg_temp.v('B')], (value -> 'partner_weights' -> pg_temp.v('B')) || '{"source":"ai"}') where key = 'engine_policy';
insert into r select 'holdout_ignores_ai_weight', (c ->> 'weight')::numeric = 1, c ->> 'weight'
  from jsonb_array_elements(pg_temp.score(0.4242) -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B');
select pg_temp.policy('{"holdout_share":0,"partner_weights":{}}');

-- ---------- kill switch ----------
update b2b.settings set value = value || jsonb_build_object('fixed_split', jsonb_build_object(pg_temp.v('A'), 1, pg_temp.v('B'), 3)) where key = 'engine';
select pg_temp.policy('{"kill_segments":["zzm24|PG|Online"]}');
insert into r select 'kill_switch_split', bool_and(x ->> 'scoring_mode' = 'kill_switch' and x ->> 'mode' = 'rule'
                                                  and (x ->> 'selection_probability')::numeric = case when x -> 'winner' ->> 'partner_id' = pg_temp.v('A') then 0.25 else 0.75 end)
                     and count(distinct x -> 'winner' ->> 'partner_id') = 2, null
  from (select pg_temp.score(s / 100.0) x from generate_series(1, 30) s) z;
update b2b.settings set value = value || jsonb_build_object('fixed_split', jsonb_build_object('999999', 1)) where key = 'engine';
insert into r select 'kill_switch_no_split_partner', x ->> 'scoring_mode' = 'kill_switch' and x -> 'winner' ->> 'partner_id' = pg_temp.v('B'), x ->> 'why'
  from (select pg_temp.score(0.4242) x) z;
select pg_temp.policy('{"kill_segments":[]}');
update b2b.settings set value = value || '{"fixed_split":{}}' where key = 'engine';

-- ---------- validation and settings ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; v jsonb := (select value from b2b.settings where key = 'engine'); begin
  begin perform b2b.engine_settings_save(v || '{"maturity_days":5}', 'bad'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('maturity_bounds', e = 'maturity is 14 to 180 days', e);
  begin perform b2b.engine_settings_save(v || '{"kill_switch":true}', 'no split'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('kill_needs_split', e = 'set the fixed split between partners before turning the kill switch on', e);
  begin perform b2b.engine_settings_save(v || '{"fixed_split":{"999999":1}}', 'unknown'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('split_unknown_partner', e like 'the fixed split names an unknown%', e);
  begin perform b2b.segment_policy_save('zzm24|PG|Online', '{"share_cap":0.3}', 'low'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('share_cap_bounds', e = 'a share cap is between 50% and 100%', e);
  begin perform b2b.segment_policy_save('zzm24|PG|Online', '{"pin":{"mode":"fastest"}}', 'bad'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('pin_mode_checked', e = 'pin the segment to commission first or performance', e);
  begin perform b2b.engine_policy_save('{"holdout_share":0.8}', 'bad'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('holdout_bounds', e = 'the holdout is 0 to 50% of leads', e);
  perform b2b.engine_settings_save(v || '{"maturity_days":45,"speed_factor":true}', 'm24 test: shorter maturity');
end $x$;
reset role;
insert into r select 'settings_versioned', (value ->> 'maturity_days')::int = 45 and (value -> 'speed_factor' ->> 'enabled')::boolean
                     and exists (select 1 from b2b.settings_versions v where v.key = 'engine' and v.reason = 'm24 test: shorter maturity'), null
  from b2b.settings where key = 'engine';
update b2b.settings set value = value || '{"maturity_days":60}' || jsonb_build_object('speed_factor', '{"enabled":false,"bounds":[0.85,1.15]}'::jsonb) where key = 'engine';

-- ---------- AI parameters make an 'ai' stats variant; the holdout keeps 'base' ----------
select pg_temp.policy('{"ai":{"prior_weight":5}}');
insert into r select 'ai_variant_refreshed', (b2b.stats_refresh() ->> 'variants') = '["base", "ai"]'
                     and (select s.prior from b2b.segment_stats s where s.variant = 'ai' and s.segment = 'zzm24|PG|Online') = round((4.5 + 0.05 * 5) / (18 + 5), 5), null;
select pg_temp.policy('{"holdout_share":1}');
insert into r select 'holdout_uses_base_stats', abs((c ->> 'alpha')::numeric - (select alpha from b2b.partner_segment_stats where variant = 'base' and segment = 'zzm24|*|*'
                                                                                     and partner_id = pg_temp.v('B')::bigint)) < 0.0001, c ->> 'alpha'
  from jsonb_array_elements(pg_temp.score(0.4242) -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B');
select pg_temp.policy('{"holdout_share":0}');
insert into r select 'steered_uses_ai_stats', abs((c ->> 'alpha')::numeric - (select alpha from b2b.partner_segment_stats where variant = 'ai' and segment = 'zzm24|*|*'
                                                                                   and partner_id = pg_temp.v('B')::bigint)) < 0.0001, c ->> 'alpha'
  from jsonb_array_elements(pg_temp.score(0.4242) -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B');
select pg_temp.policy('{"ai":{}}');

-- ---------- Admin reads and replay ----------
insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed,
                                  selection_probability, scoring_mode, holdout, policy_version, is_test, actor_type)
select pg_temp.v('L')::bigint, 30, 'zzm24|PG|Online', '{}', x ->> 'mode', 'partner', (x -> 'winner' ->> 'partner_id')::bigint,
       (select jsonb_agg(c || '{"eligible":true}') from jsonb_array_elements(x -> 'candidates') c), 0.4242,
       (x ->> 'selection_probability')::numeric, x ->> 'scoring_mode', false, (x ->> 'policy_version')::int, false, 'system'
  from (select pg_temp.score(0.4242) x) z;
insert into t select 'D', max(id)::text from b2b.engine_decisions where lead_id = pg_temp.v('L')::bigint and cycle_no = 30;
set local role authenticated;
select pg_temp.admin();
insert into r select 'segments_list', s ->> 'segment' = 'zzm24|PG|Online' and s -> 'mode' ->> 'mode' = 'performance' and (s ->> 'matured')::int = 20,
                     s::text from jsonb_array_elements(b2b.routing_segments() -> 'segments') s where s ->> 'segment' = 'zzm24|PG|Online';
insert into r select 'segment_detail', jsonb_array_length(x -> 'partners') = 2
                     and (select (p -> 'exact' -> 'interval' ->> 'low')::numeric < (p -> 'exact' ->> 'p_hat')::numeric
                                 and (p -> 'exact' -> 'interval' ->> 'high')::numeric > (p -> 'exact' ->> 'p_hat')::numeric
                            from jsonb_array_elements(x -> 'partners') p where p ->> 'partner_id' = pg_temp.v('A'))
                     and jsonb_array_length(x -> 'decisions') >= 1, null
  from (select b2b.routing_segment('zzm24|PG|Online') x) z;
insert into r select 'replay_reproduces', (x ->> 'replayable')::boolean and (x ->> 'reproduced')::boolean
                     and (x ->> 'selection_probability')::numeric = (x ->> 'logged_probability')::numeric, x::text
  from (select b2b.decision_replay(pg_temp.v('D')::bigint) x) z;
reset role;
select pg_temp.admin();
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d2","role":"authenticated","aal":"aal2","email":"nobody24@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.routing_segments(); e := 'read'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_refused', e = '42501', e);
  begin perform b2b.route_score(1, 'x|*|*', '[]', 0.1, false); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('scorer_not_callable', e = '42501', e);
end $x$;
reset role;

-- ---------- share cap ----------
select pg_temp.alloc(pg_temp.v('B')::bigint, n, interval '1 day', false) from generate_series(40, 42) n;
select pg_temp.policy(jsonb_build_object('segments', jsonb_build_object('zzm24|PG|Online', '{"share_cap":{"value":0.5,"source":"admin"}}'::jsonb)));
insert into r select 'share_cap_passes_over', x -> 'winner' ->> 'partner_id' = pg_temp.v('A') and jsonb_array_length(x -> 'capped') = 1
                     and x -> 'capped' -> 0 ->> 'partner_id' = pg_temp.v('B'), x -> 'capped' ->> 0
  from (select pg_temp.score(0.4242) x) z;
select pg_temp.policy('{"segments":{}}');

-- ---------- guardrails ----------
insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, status, breached_at)
select a.id, a.lead_id, a.partner_id, 'first_attempt', now() - interval '3 hours' - n * interval '1 minute', now() - interval '1 hour' - n * interval '1 minute',
       'breached', now() - interval '1 hour'
  from b2b.allocations a, generate_series(1, 5) n
 where a.partner_id = pg_temp.v('A')::bigint and a.cycle_no = 11;
select pg_temp.alloc(pg_temp.v('B')::bigint, n, interval '2 hours', false, case when n < 49 then 'duplicate' else 'closed' end) from generate_series(43, 62) n;
insert into r select 'guard_pauses', (b2b.guard_tick() ->> 'paused')::int >= 2, null;
-- other staging partners the tick paused (old test evidence) are put back, so the rest of the test is unaffected
update b2b.partners set status = 'active', paused_reason = null, auto_paused_at = null
 where auto_paused_at = now() and id not in (pg_temp.v('A')::bigint, pg_temp.v('B')::bigint);
insert into r select 'auto_paused_sla', p.status = 'paused' and p.auto_paused_at is not null and p.paused_reason like 'auto-paused: missed the first-contact SLA%', p.paused_reason
  from b2b.partners p where p.id = pg_temp.v('A')::bigint;
insert into r select 'auto_paused_duplicates', p.status = 'paused' and p.paused_reason like 'auto-paused: duplicate rate is 30%%', p.paused_reason
  from b2b.partners p where p.id = pg_temp.v('B')::bigint;
insert into r select 'pause_alerts', count(*) = 2, count(*)::text from b2b.events e
 where e.type = 'alert.partner_auto_paused' and e.partner_id in (pg_temp.v('A')::bigint, pg_temp.v('B')::bigint);
-- resuming gives a clean slate
update b2b.partners set status = 'active' where id = pg_temp.v('A')::bigint;
select b2b.log_event('partner.status_changed', null, null, pg_temp.v('A')::bigint, '{"from":"paused","to":"active"}');
select b2b.guard_tick();
insert into r select 'resume_clean_slate', p.status = 'active', p.status from b2b.partners p where p.id = pg_temp.v('A')::bigint;
update b2b.partners set status = 'active', paused_reason = null, auto_paused_at = null
 where auto_paused_at = now() and id not in (pg_temp.v('A')::bigint, pg_temp.v('B')::bigint);

-- drop alert: A's P̂ was 0.5 thirty-one days ago
insert into b2b.stats_snapshots (day, partner_id, segment, p_hat, ncpl_inr, n_matured)
values ((now() at time zone 'Asia/Kolkata')::date - 31, pg_temp.v('A')::bigint, 'zzm24|PG|Online', 0.5, null, 10);
select b2b.stats_refresh();
insert into r select 'drop_alert', count(*) = 1, count(*)::text from b2b.events e
 where e.type = 'alert.ncpl_drop' and e.partner_id = pg_temp.v('A')::bigint and e.payload ->> 'segment' = 'zzm24|PG|Online';

-- ---------- a real decision logs the scoring ----------
update b2b.partners set status = 'active' where id = pg_temp.v('B')::bigint;
insert into b2b.live_switches (scope, live, reason) values ('partner:20', true, 'm24 test') on conflict (scope) do update set live = true;
do $x$ declare v_id bigint; d jsonb; begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876504902', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Perf Route', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now())));
  select id into v_id from public.student_leads where whatsapp_number = '919876504902';
  d := b2b.route_decide(v_id, true, 'm24', 'auto');
  insert into t values ('RD', d::text);
end $x$;
insert into r select 'route_decide_logs_scoring', d.seed is not null and d.scoring_mode is not null and d.policy_version is not null
                     and (d.candidates -> 0 ? 'p_hat') and d.seed = (x ->> 'seed')::numeric, coalesce(d.scoring_mode, x ->> 'reason')
  from (select pg_temp.v('RD')::jsonb x) z join b2b.engine_decisions d on d.id = (x ->> 'decision_id')::bigint
 where x ->> 'destination' = 'partner';
insert into r select 'route_decide_partner', x ->> 'destination' = 'partner' and x ? 'scoring_mode' and x ? 'holdout', x ->> 'destination' || ' ' || coalesce(x ->> 'reason', '')
  from (select pg_temp.v('RD')::jsonb x) z;

select name, ok, detail from r order by ok, name;
rollback;
