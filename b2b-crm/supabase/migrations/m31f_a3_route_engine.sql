-- M31f: Addendum 3, the routing engine (docs/B2B_CRM_ADDENDUM_3.md PART 3-5, PART 7 R8, Amendment 1; design D2-D3, D7,
-- D14, D21-D33). Swapped in whole, in one file:
--   model_score       the per-lead ML hook (m25b), with the challenger drawn on its share (C4) and a feature hash (C61);
--   offer_candidates  one interest's offers grouped by partner, as route_decide hands them to the scorer (C59);
--   stage_score       Stages A / B / C, the sales-effort and SLA factors, deterministic selection, the literal 20%
--                     exploration lane and exact propensities; stable, every draw from the seed (C16, C45, C46, C47, C128);
--   route_score       the m24b entry point, now a wrapper over stage_score;
--   cpe_net           the m6a entry point, now the middle-tier cpe_detail;
--   rule_matches      Step 2 conditions (+ specializations, paid);
--   route_decide      R1-R9 in order with the cascade and manual contexts, the bar, the holds, consent, the interest
--                     loop, Step 1 causes, the Step 2 rule loop, contractual minimums, the cap at commit, the
--                     version-3 hand-off (C112, C123, C124, C125);
--   route_outlook     the same order without scoring, for lists and the pool;
--   pool_lead         the pool groups (awaiting_consent, waiting_inactivity, chatting, ...);
--   route_to_partners_core / api_route_to_partners   the manual route (partner_barred, no_consent, not_held);
--   reroute_after     the cascade entry (p_how 'cascade', lead_waits 'reroute_error' on failure).
-- Every rulebook number is read from engine.a3_fixed (m31a). No kill switch, no pins, no share caps, no partner weights,
-- no Monte-Carlo draws: 'Highest score wins'. Every function keeps its signature; new ones are service_role only.

-- ======================================================================================================== model_score
/* The per-lead model (M25): given the scored candidates, the deciding model's calibrated P(enrol) per partner.
   Holdout leads get no deciding model. The challenger decides only when u01(seed, 'challenger') < challenger_share
   (C4); otherwise the champion decides when one exists; with neither, the segment P-hat decides (deciding null).
   Returns {deciding, p, p_champion, p_challenger, challenger_share (0 without a challenger), challenger_drawn, shadow
   {version: {partner_id: p}}, feature_hash (C61: md5 of the lead features and every candidate's feature vector)}.
   The empty shape when no model exists or the lead is unknown. */
create or replace function b2b.model_score(p_lead_id bigint, p_cands jsonb, p_seed numeric, p_holdout boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  champ b2b.ml_models;
  chall b2b.ml_models;
  shad b2b.ml_models;
  dec b2b.ml_models;
  l public.student_leads;
  v_lead jsonb;
  v_cands jsonb := case when jsonb_typeof(p_cands) = 'array' then p_cands else '[]'::jsonb end;
  v_share numeric := 0;
  v_drawn boolean := false;
  v_p_champ jsonb;
  v_p_chall jsonb;
  v_p_shad jsonb;
  v_shadow jsonb := '{}';
  v_hash text;
  v_empty jsonb := jsonb_build_object('deciding', null, 'p', '{}'::jsonb, 'p_champion', null, 'p_challenger', null,
                                      'challenger_share', 0, 'challenger_drawn', false, 'shadow', '{}'::jsonb, 'feature_hash', null);
begin
  select * into champ from b2b.ml_models where status = 'champion' order by id desc limit 1;
  select * into chall from b2b.ml_models where status = 'challenger' order by id desc limit 1;
  select * into shad from b2b.ml_models where status = 'shadow' order by id desc limit 1;
  if champ.id is null and chall.id is null and shad.id is null then return v_empty; end if;
  if p_lead_id is null then return v_empty; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return v_empty; end if;
  v_lead := b2b.ml_lead_features(l);
  v_hash := md5(jsonb_build_object('lead', v_lead, 'cands',
              coalesce((select jsonb_object_agg(c ->> 'partner_id', b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c))
                          from jsonb_array_elements(v_cands) c where (c ->> 'partner_id') is not null), '{}'::jsonb))::text);
  if chall.id is not null then
    v_share := least(greatest(coalesce(b2b.stats_num(cfg -> 'challenger_share'), 0.1), 0), 1);
    v_drawn := b2b.u01(coalesce(p_seed::text, '0.5'), 'challenger') < v_share;
  end if;
  if not coalesce(p_holdout, false) then
    if chall.id is not null and v_drawn then dec := chall; else dec := champ; end if;
  end if;
  if champ.id is not null then
    select coalesce(jsonb_object_agg(c ->> 'partner_id', (b2b.ml_predict(champ.weights, champ.calibration, b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric), '{}'::jsonb)
      into v_p_champ from jsonb_array_elements(v_cands) c where (c ->> 'partner_id') is not null;
  end if;
  if chall.id is not null then
    select coalesce(jsonb_object_agg(c ->> 'partner_id', (b2b.ml_predict(chall.weights, chall.calibration, b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric), '{}'::jsonb)
      into v_p_chall from jsonb_array_elements(v_cands) c where (c ->> 'partner_id') is not null;
  end if;
  if shad.id is not null then
    select coalesce(jsonb_object_agg(c ->> 'partner_id', (b2b.ml_predict(shad.weights, shad.calibration, b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric), '{}'::jsonb)
      into v_p_shad from jsonb_array_elements(v_cands) c where (c ->> 'partner_id') is not null;
    v_shadow := v_shadow || jsonb_build_object(shad.version, v_p_shad);
  end if;
  -- a challenger is shadow-scored on the leads it does not decide
  if chall.id is not null and dec.id is distinct from chall.id then
    v_shadow := v_shadow || jsonb_build_object(chall.version, v_p_chall);
  end if;
  return jsonb_build_object(
    'deciding', dec.version,
    'p', coalesce(case when dec.id is null then null when dec.id = chall.id then v_p_chall else v_p_champ end, '{}'::jsonb),
    'p_champion', v_p_champ, 'p_challenger', v_p_chall,
    'challenger_share', v_share, 'challenger_drawn', v_drawn,
    'shadow', v_shadow, 'feature_hash', v_hash);
end $fn$;

-- ======================================================================================================== offer_candidates
/* One interest's published offers grouped by partner, exactly as route_decide hands them to stage_score (C59): the
   b2b.interest_offers rows (paused partners included: the caller excludes), up to 20 programmes by middle-tier CPE,
   the median CPE over the offers with a rate, the caps and this partner's live counts (non-test allocations in
   queued/pushing/pushed/accepted/closed, today and this month in India time, and the last 7 days), the lead criteria and
   whether the partner has a sandbox endpoint. Ordered by partner_id. */
create or replace function b2b.offer_candidates(p_int jsonb, p_sandbox boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v jsonb;
begin
  with o as (
    select f.partner_id, f.programme_id, f.fees, f.eligibility, f.spec_match, f.university_id, f.cat_min_qualification, f.cat_min_pct,
           (b2b.cpe_detail(f.partner_id, f.programme_id, f.fees, 'middle', null) ->> 'cpe')::numeric as cpe
      from b2b.interest_offers(p_int, coalesce(p_sandbox, false)) f),
  pp as (
    select o.partner_id, count(*)::int as n,
           (array_agg(o.programme_id order by o.cpe desc nulls last, o.programme_id))[1:20] as progs,
           jsonb_agg(jsonb_build_object('programme_id', o.programme_id, 'fees', o.fees, 'eligibility', o.eligibility, 'spec_match', o.spec_match,
                                        'university_id', o.university_id, 'cat_min_qualification', o.cat_min_qualification,
                                        'cat_min_pct', o.cat_min_pct, 'cpe', o.cpe)
                     order by o.cpe desc nulls last, o.programme_id) as offers,
           (percentile_cont(0.5) within group (order by o.cpe) filter (where o.cpe is not null))::numeric as cpe
      from o group by o.partner_id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'partner_id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
           'offers_count', pp.n, 'programmes', to_jsonb(pp.progs), 'offers', pp.offers,
           'cpe', round(pp.cpe, 2), 'has_rate', pp.cpe is not null,
           'daily_cap', p.daily_cap, 'monthly_cap', p.monthly_cap, 'contract_min_monthly', p.contract_min_monthly,
           'leads_today', k.n_today, 'leads_month', k.n_month, 'leads_week', k.n_week,
           'criteria', p.lead_criteria, 'test_endpoint', p.test_endpoint is not null) order by p.id), '[]'::jsonb)
    into v
    from pp
    join b2b.partners p on p.id = pp.partner_id
    cross join lateral (
      select (count(*) filter (where a.created_at >= v_today))::int as n_today,
             (count(*) filter (where a.created_at >= v_month))::int as n_month,
             (count(*) filter (where a.created_at > now() - interval '7 days'))::int as n_week
        from b2b.allocations a
       where a.partner_id = p.id and a.destination_type = 'partner' and not a.is_test
         and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'closed')
         and a.created_at >= least(v_month, now() - interval '7 days')) k;
  return v;
end $fn$;

-- ======================================================================================================== stage_score
/* PART 4 Step 3. p_ctx = {lead_id, seed (numeric|text), seed_source, is_test, segment, segment_exact, lane_allowed,
   mode_hint minimum|rule|manual|null, holdout (previews only: replaces the u01 draw)}; p_cands = offer_candidates(..)
   after the caller's Step 1/2 exclusions (extra keys are kept). Stable: every draw comes from the seed, nothing is
   written. Steps:
   (a) holdout = engine_policy.holdout_share > 0 and u01(seed, 'holdout') < share; prm = engine_params(holdout), so a
       holdout lead runs the Admin's bounds, weights, floor and 'base' stats (C5).
   (b) eval segment = segment_exact when set and every candidate has >= a3_fixed.exact_segment_min_leads received leads
       there, else the 3-part segment (D25).
   (c) per candidate, live from non-test allocations at eval (received = pushed/accepted/closed or accepted_at set):
       n_received, first_lead_at, n_matured_c, leads_week; the partner_segment_stats row of prm.variant at eval, else at
       the 3-part key, else the prior: p_hat, alpha, beta, w_n, w_enr, refund_rate, effort_detail, has_activity,
       sla_adherence, sla_total. Every candidate in every mode carries p_hat and p_source (C47) and the raw factor inputs
       (effort_raw, sla_raw, C16). Live partner features for the ML log (C45): open_backlog, in_hours, fch_7d, fch_30d,
       connect_30d, fee_inr.
   (d) CPE per offer with cpe_detail: basis 'projected' once the partner has >= tier_projected_min_matured matured leads
       at eval and a conversion in Money, else 'middle' (D28); cpe = the median over offers with a rate.
   (e) stage: C when >= stage_c_min_partners candidates have n_matured_c >= stage_c_min_matured; B when every candidate
       has n_received >= stage_b_min_leads and first_lead_at <= now - stage_b_min_age_days; else A (D26).
   (f) model_score runs whenever any model exists (C46); P from the model is used only in Stage C for non-holdout leads
       (p_source model | p_hat | prior).
   (g) f_e and f_s: the effort and SLA factors in Stages B and C (1 in Stage A); the helpers return 1 when disabled.
   (h) score: A = cpe; B = cpe x f_e x f_s; C = cpe x p_used x (1 - refund_rate) x f_e x f_s; no rate scores 0.
   (i) order: score desc, cpe desc nulls last, sla_adherence desc nulls last, leads_week asc, partner_id (ties: PART 4).
   (j) the lane: when lane_allowed, more than one candidate and an under-tested candidate x (n_received <
       learn_leads, the highest CPE, ties as above) differs from the score winner, draw = u01(seed, 'explore') and x
       wins when draw < exploration_share; otherwise draw null and exploration_share 0 (C128).
   (k) propensities: pi(w*) = 1 - share and pi(x) = share while the lane applies, else pi(winner) = 1; with a challenger
       share q in Stage C, pi = (1 - q) pi_champion + q pi_challenger (D23).
   Returns {winner, stage, scoring_mode, mode, eval_segment, holdout, holdout_share, draw, exploration_share, lane
   {applied, x_partner_id}, selection_probability, candidates (ordered, with score, tie_rank, propensity ...),
   policy_version, stats_at, params_variant, model_version, feature_hash, shadow, seed, seed_source}. */
create or replace function b2b.stage_score(p_ctx jsonb, p_cands jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine_policy'), '{}');
  v_pol_ver int := (select s.version from b2b.settings s where s.key = 'engine_policy');
  v_seed text := coalesce(nullif(p_ctx ->> 'seed', ''), '0.5');
  v_seed_src text := coalesce(nullif(p_ctx ->> 'seed_source', ''), 'given');
  v_seed_num numeric;
  v_lead_id bigint := nullif(p_ctx ->> 'lead_id', '')::bigint;
  v_is_test boolean := coalesce((p_ctx ->> 'is_test')::boolean, false);
  v_seg text := p_ctx ->> 'segment';
  v_segx text := nullif(p_ctx ->> 'segment_exact', '');
  v_lane_ok boolean := coalesce((p_ctx ->> 'lane_allowed')::boolean, false);
  v_hint text := nullif(p_ctx ->> 'mode_hint', '');
  v_hold_share numeric := least(greatest(coalesce(b2b.stats_num(pol -> 'holdout_share'), 0.1), 0), 0.5);
  v_hold boolean;
  prm jsonb;
  stg jsonb;
  v_variant text;
  v_md int;
  v_learn int;
  v_exact_min int;
  v_proj_min int;
  v_b_leads int;
  v_b_age int;
  v_c_mat int;
  v_c_part int;
  v_share numeric;
  v_pw numeric;
  v_hl int;
  v_dpe numeric;
  v_eff jsonb;
  v_sla jsonb;
  v_eff_raw jsonb;
  v_sla_raw jsonb;
  v_cands jsonb := case when jsonb_typeof(p_cands) = 'array' then p_cands else '[]'::jsonb end;
  v_n int;
  v_eval text;
  v_use_exact boolean := false;
  v_stage text;
  v_smode text;
  v_mode text;
  v_m jsonb := null;
  v_model_dec boolean := false;
  v_scored jsonb;
  v_stats_at timestamptz;
  v_period text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM');
  v_period_prev text := to_char((now() at time zone 'Asia/Kolkata') - interval '1 month', 'YYYY-MM');
  v_win jsonb;
  v_x jsonb;
  v_w_dec text;
  v_w_ch text;
  v_w_cl text;
  v_draw numeric;
  v_lane boolean := false;
  v_lane_ch boolean := false;
  v_lane_cl boolean := false;
  v_exp numeric := 0;
  v_q numeric := 0;
  v_mix boolean := false;
  v_prob numeric;
  v_win_pid text;
  v_x_pid text;
begin
  v_seed_num := case when v_seed ~ '^-?[0-9]+(\.[0-9]+)?$' then v_seed::numeric else 0.5 end;
  v_n := jsonb_array_length(v_cands);

  -- (a) holdout and the parameters
  if jsonb_typeof(p_ctx -> 'holdout') = 'boolean' then
    v_hold := (p_ctx ->> 'holdout')::boolean;
  else
    v_hold := v_hold_share > 0 and b2b.u01(v_seed, 'holdout') < v_hold_share;
  end if;
  prm := b2b.engine_params(v_hold);
  stg := coalesce(prm -> 'stages', '{}'::jsonb);
  v_variant := coalesce(prm ->> 'variant', 'base');
  v_md := round(coalesce(b2b.stats_num(stg -> 'matured_days'), 60))::int;
  v_learn := round(coalesce(b2b.stats_num(stg -> 'learn_leads'), 30))::int;
  v_exact_min := round(coalesce(b2b.stats_num(stg -> 'exact_segment_min_leads'), 30))::int;
  v_proj_min := round(coalesce(b2b.stats_num(stg -> 'tier_projected_min_matured'), 30))::int;
  v_b_leads := round(coalesce(b2b.stats_num(stg -> 'stage_b_min_leads'), 20))::int;
  v_b_age := round(coalesce(b2b.stats_num(stg -> 'stage_b_min_age_days'), 7))::int;
  v_c_mat := round(coalesce(b2b.stats_num(stg -> 'stage_c_min_matured'), 30))::int;
  v_c_part := round(coalesce(b2b.stats_num(stg -> 'stage_c_min_partners'), 2))::int;
  v_share := least(greatest(coalesce(b2b.stats_num(stg -> 'exploration_share'), 0.2), 0), 0.5);
  v_pw := coalesce(b2b.stats_num(prm -> 'prior_weight'), 20);
  v_hl := round(coalesce(b2b.stats_num(prm -> 'half_life_days'), 30))::int;
  v_dpe := coalesce(b2b.stats_num(prm -> 'default_p_enroll'), 0.05);
  v_eff := coalesce(prm -> 'effort', '{}'::jsonb);
  v_sla := coalesce(prm -> 'sla', '{}'::jsonb);
  v_eff_raw := v_eff || '{"enabled":true}'::jsonb;
  v_sla_raw := v_sla || '{"enabled":true}'::jsonb;

  if v_n = 0 then
    return jsonb_build_object('winner', null, 'stage', 'A', 'scoring_mode', 'commission_first', 'mode', coalesce(v_hint, 'commission_first'),
             'eval_segment', v_seg, 'holdout', v_hold, 'holdout_share', round(v_hold_share, 3), 'draw', null, 'exploration_share', 0,
             'lane', jsonb_build_object('applied', false, 'x_partner_id', null), 'selection_probability', null, 'candidates', '[]'::jsonb,
             'policy_version', v_pol_ver, 'stats_at', null, 'params_variant', v_variant, 'model_version', null, 'feature_hash', null,
             'shadow', null, 'seed', v_seed, 'seed_source', v_seed_src, 'why', null, 'challenger_share', 0);
  end if;

  -- (b) the evaluation segment
  v_eval := v_seg;
  if v_segx is not null then
    select coalesce(bool_and(k.n >= v_exact_min), false) into v_use_exact
      from jsonb_array_elements(v_cands) c
      cross join lateral (select count(*) as n from b2b.allocations a
                           where a.partner_id = (c ->> 'partner_id')::bigint and a.destination_type = 'partner' and not a.is_test
                             and (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null)
                             and a.segment_exact = v_segx) k;
    if v_use_exact then v_eval := v_segx; end if;
  end if;

  -- (c) + (d): counts, statistics, CPE and live features per candidate
  select coalesce(jsonb_agg(
           c || jsonb_build_object(
             'n_received', cnt.n, 'first_lead_at', cnt.first_at, 'n_matured_c', cnt.nm, 'leads_week', cnt.lw,
             'under_tested', cnt.n < v_learn,
             'p_hat', round(coalesce(st.p_hat, pr.prior), 5),
             'alpha', coalesce(st.alpha, round(pr.prior * v_pw, 4)),
             'beta', coalesce(st.beta, round((1 - pr.prior) * v_pw, 4)),
             'prior', round(pr.prior, 5), 'prior_weight', v_pw, 'half_life_days', v_hl,
             'w_n', coalesce(st.w_matured, 0), 'w_enr', coalesce(st.w_enrolled, 0),
             'refund_rate', coalesce(st.refund_rate, 0),
             'effort_detail', st.effort_detail, 'has_activity', coalesce(st.has_activity, false),
             'effort_raw', b2b.effort_from_detail(st.effort_detail, v_eff_raw),
             'sla_adherence', st.sla_adherence, 'sla_total', coalesce(st.sla_total, 0),
             'sla_raw', b2b.sla_factor_of(st.sla_adherence, st.sla_total, v_sla_raw),
             'p_source', case when st.p_hat is not null then 'p_hat' else 'prior' end,
             'stats_segment', st.segment)
           || jsonb_build_object(
             'cpe', round(cp.cpe, 2), 'has_rate', cp.has_rate, 'cpe_basis', cp.basis, 'fee_inr', round(cp.fee, 2),
             'open_backlog', lf.backlog, 'in_hours', lf.in_hours,
             'fch_7d', round(lf.fch7, 2), 'fch_30d', round(lf.fch30, 2),
             'connect_30d', b2b.stats_num(st.effort_detail -> 'metrics' -> 'connect_rate' -> 'v'))
           order by (c ->> 'partner_id')::bigint), '[]'::jsonb),
         max(st.refreshed_at)
    into v_scored, v_stats_at
    from jsonb_array_elements(v_cands) c
    cross join lateral (select (c ->> 'partner_id')::bigint as pid) p
    cross join lateral (
      select count(*)::int as n, min(a.created_at) as first_at,
             (count(*) filter (where a.created_at < now() - make_interval(days => v_md)))::int as nm,
             (count(*) filter (where a.created_at > now() - interval '7 days'))::int as lw
        from b2b.allocations a
       where a.partner_id = p.pid and a.destination_type = 'partner' and not a.is_test and a.segment is not null
         and (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null)
         and (a.segment_exact = v_eval or a.segment = v_eval or b2b.segment_rollup(a.segment) = v_eval)) cnt
    left join b2b.partner_segment_stats ex on ex.variant = v_variant and ex.partner_id = p.pid and ex.segment = v_eval
    left join b2b.partner_segment_stats r3 on v_eval <> v_seg and r3.variant = v_variant and r3.partner_id = p.pid and r3.segment = v_seg
    cross join lateral (select case when ex.partner_id is not null then ex else r3 end as row) pick
    cross join lateral (select (pick.row).segment, (pick.row).p_hat, (pick.row).alpha, (pick.row).beta, (pick.row).w_matured, (pick.row).w_enrolled,
                               (pick.row).refund_rate, (pick.row).effort_detail, (pick.row).has_activity, (pick.row).sla_adherence,
                               (pick.row).sla_total, (pick.row).refreshed_at) st
    cross join lateral (select coalesce(
                          (select s.prior from b2b.segment_stats s where s.variant = v_variant and s.segment = v_eval and s.n_matured > 0),
                          (select s.prior from b2b.segment_stats s where s.variant = v_variant and s.segment = v_seg and s.n_matured > 0),
                          (select s.prior from b2b.segment_stats s where s.variant = v_variant and s.segment = b2b.segment_rollup(v_seg) and s.n_matured > 0),
                          v_dpe) as prior) pr
    cross join lateral (
      select cnt.nm >= v_proj_min and conv.pct is not null as proj, conv.pct
        from (select coalesce(b2b.stats_num(b2b.partner_conversion(p.pid, v_period) -> 'conversion_pct'),
                              b2b.stats_num(b2b.partner_conversion(p.pid, v_period_prev) -> 'conversion_pct')) as pct) conv) tb
    cross join lateral (
      with o as (
        select (x ->> 'programme_id')::bigint as prog, x -> 'fees' as fees,
               b2b.cpe_detail(p.pid, (x ->> 'programme_id')::bigint, x -> 'fees',
                              case when tb.proj then 'projected' else 'middle' end, case when tb.proj then tb.pct end) as d
          from jsonb_array_elements(case when jsonb_typeof(c -> 'offers') = 'array' then c -> 'offers' else '[]'::jsonb end) x),
      w as (select o.* from o where (o.d ->> 'cpe') is not null)
      select case when (select count(*) from o) = 0 then (c ->> 'cpe')::numeric
                  else (select (percentile_cont(0.5) within group (order by (w.d ->> 'cpe')::numeric))::numeric from w) end as cpe,
             case when (select count(*) from o) = 0 then coalesce((c ->> 'has_rate')::boolean, (c ->> 'cpe') is not null)
                  else (select count(*) from w) > 0 end as has_rate,
             (select (percentile_cont(0.5) within group (order by (w.d ->> 'fee_base_inr')::numeric))::numeric from w where (w.d ->> 'fee_base_inr') is not null) as fee,
             coalesce((select jsonb_build_object('tier_basis', coalesce(w.d ->> 'tier_basis', case when tb.proj then 'projected' else 'middle' end),
                                                 'fee_source', w.d ->> 'fee_source', 'fee_basis', w.d ->> 'fee_basis',
                                                 'offers_with_rate', (select count(*) from w), 'programme_id', w.prog)
                         from w order by (w.d ->> 'cpe')::numeric, w.prog offset greatest((select count(*) from w) - 1, 0) / 2 limit 1),
                      jsonb_build_object('tier_basis', case when tb.proj then 'projected' else 'middle' end, 'fee_source', null, 'fee_basis', null,
                                         'offers_with_rate', 0, 'programme_id', null)) as basis) cp
    cross join lateral (
      select (select count(*) from b2b.allocations a where a.partner_id = p.pid and a.destination_type = 'partner' and not a.is_test
                                                      and a.status in ('queued', 'pushing', 'pushed', 'accepted'))::int as backlog,
             exists (select 1 from b2b.working_windows(p.pid, now(), 1) w where w.win_start <= now() and now() < w.win_end) as in_hours,
             (select (percentile_cont(0.5) within group (order by extract(epoch from s.met_at - s.started_at) / 3600))::numeric
                from b2b.sla_checks s where s.partner_id = p.pid and s.sla = 'first_attempt' and not s.is_test and s.met_at is not null
                                        and s.started_at > now() - interval '7 days') as fch7,
             (select (percentile_cont(0.5) within group (order by extract(epoch from s.met_at - s.started_at) / 3600))::numeric
                from b2b.sla_checks s where s.partner_id = p.pid and s.sla = 'first_attempt' and not s.is_test and s.met_at is not null
                                        and s.started_at > now() - interval '30 days') as fch30) lf;

  -- (e) the stage
  if (select count(*) from jsonb_array_elements(v_scored) c where (c ->> 'n_matured_c')::int >= v_c_mat) >= v_c_part then
    v_stage := 'C';
  elsif (select bool_and((c ->> 'n_received')::int >= v_b_leads and (c ->> 'first_lead_at')::timestamptz <= now() - make_interval(days => v_b_age))
           from jsonb_array_elements(v_scored) c) then
    v_stage := 'B';
  else
    v_stage := 'A';
  end if;
  v_smode := case when v_stage = 'A' then 'commission_first' else 'performance' end;

  -- (f) the model: called in every stage whenever a model exists; its P is used only in Stage C for non-holdout leads
  if v_lead_id is not null and exists (select 1 from b2b.ml_models m where m.status in ('champion', 'challenger', 'shadow')) then
    v_m := b2b.model_score(v_lead_id, v_scored, v_seed_num, v_hold);
  end if;
  v_model_dec := v_stage = 'C' and not v_hold and (v_m ->> 'deciding') is not null;
  if v_stage = 'C' and not v_hold and jsonb_typeof(v_m -> 'p_challenger') = 'object' and jsonb_typeof(v_m -> 'p_champion') = 'object'
     and coalesce(b2b.stats_num(v_m -> 'challenger_share'), 0) > 0 then
    v_q := b2b.stats_num(v_m -> 'challenger_share');
    v_mix := true;
  end if;

  -- (g) + (h): factors and scores (score_champ / score_chall: the Stage C score under each P source, for the mixture)
  select coalesce(jsonb_agg(c || jsonb_build_object(
           'p_model', b2b.stats_num(coalesce(v_m -> 'p' -> (c ->> 'partner_id'), v_m -> 'p_champion' -> (c ->> 'partner_id'))),
           'p_used', case when v_stage = 'C' then z.pu end,
           'p_source', case when v_model_dec and (v_m -> 'p') ? (c ->> 'partner_id') then 'model' else c ->> 'p_source' end,
           'effort_factor', z.fe, 'sla_factor', z.fs,
           'ncpl', case when v_stage = 'C' then round(z.cpe * z.pu * (1 - z.rr), 2) end,
           'score', round(case v_stage when 'A' then z.cpe when 'B' then z.cpe * z.fe * z.fs else z.cpe * z.pu * (1 - z.rr) * z.fe * z.fs end, 2),
           'score_champ', round(z.cpe * z.p_ch * (1 - z.rr) * z.fe * z.fs, 2),
           'score_chall', case when z.p_cl is not null then round(z.cpe * z.p_cl * (1 - z.rr) * z.fe * z.fs, 2) end)
           order by (c ->> 'partner_id')::bigint), '[]'::jsonb)
    into v_scored
    from jsonb_array_elements(v_scored) c
    cross join lateral (
      select coalesce((c ->> 'cpe')::numeric, 0) as cpe,
             coalesce((c ->> 'refund_rate')::numeric, 0) as rr,
             case when v_stage in ('B', 'C') then b2b.effort_from_detail(c -> 'effort_detail', v_eff) else 1 end as fe,
             case when v_stage in ('B', 'C') then b2b.sla_factor_of((c ->> 'sla_adherence')::numeric, (c ->> 'sla_total')::int, v_sla) else 1 end as fs,
             case when v_model_dec and (v_m -> 'p') ? (c ->> 'partner_id') then b2b.stats_num(v_m -> 'p' -> (c ->> 'partner_id'))
                  else (c ->> 'p_hat')::numeric end as pu,
             coalesce(b2b.stats_num(v_m -> 'p_champion' -> (c ->> 'partner_id')), (c ->> 'p_hat')::numeric) as p_ch,
             b2b.stats_num(v_m -> 'p_challenger' -> (c ->> 'partner_id')) as p_cl) z;

  -- (i) order and tie ranks
  select coalesce(jsonb_agg(c || jsonb_build_object('tie_rank', rk) order by rk), '[]'::jsonb) into v_scored
    from (select c, row_number() over (order by (c ->> 'score')::numeric desc, (c ->> 'cpe')::numeric desc nulls last,
                                               (c ->> 'sla_adherence')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint) rk
            from jsonb_array_elements(v_scored) c) s;
  v_win := v_scored -> 0;
  v_w_dec := v_win ->> 'partner_id';
  if v_mix then
    select c ->> 'partner_id' into v_w_ch from jsonb_array_elements(v_scored) c
     order by (c ->> 'score_champ')::numeric desc, (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_adherence')::numeric desc nulls last,
              (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
    select c ->> 'partner_id' into v_w_cl from jsonb_array_elements(v_scored) c
     order by (c ->> 'score_chall')::numeric desc, (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_adherence')::numeric desc nulls last,
              (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
  end if;

  -- (j) the exploration lane: the under-tested candidate with the highest CPE, when it is not the score winner
  if v_lane_ok and v_n > 1 and v_share > 0 then
    select c into v_x from jsonb_array_elements(v_scored) c where (c ->> 'under_tested')::boolean
     order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_adherence')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint
     limit 1;
    v_x_pid := v_x ->> 'partner_id';
    if v_x_pid is not null then
      v_lane := v_x_pid <> v_w_dec;
      v_lane_ch := v_mix and v_x_pid <> v_w_ch;
      v_lane_cl := v_mix and v_x_pid <> v_w_cl;
    end if;
  end if;
  if v_lane then
    v_draw := round(b2b.u01(v_seed, 'explore')::numeric, 12);
    v_exp := v_share;
    if v_draw < v_share then v_win := v_x; end if;
  end if;
  v_win_pid := v_win ->> 'partner_id';

  -- (k) propensities, exact
  select coalesce(jsonb_agg((c - 'score_champ' - 'score_chall') || jsonb_build_object('propensity', round(pp.pi, 4)) order by (c ->> 'tie_rank')::int), '[]'::jsonb)
    into v_scored
    from jsonb_array_elements(v_scored) c
    cross join lateral (select c ->> 'partner_id' as pid) q
    cross join lateral (
      select case when v_mix then
                    (1 - v_q) * (case when q.pid = v_w_ch then (case when v_lane_ch then 1 - v_share else 1 end)
                                      when v_lane_ch and q.pid = v_x_pid then v_share else 0 end)
                    + v_q * (case when q.pid = v_w_cl then (case when v_lane_cl then 1 - v_share else 1 end)
                                  when v_lane_cl and q.pid = v_x_pid then v_share else 0 end)
                  else (case when q.pid = v_w_dec then (case when v_lane then 1 - v_share else 1 end)
                             when v_lane and q.pid = v_x_pid then v_share else 0 end) end as pi) pp;
  select c into v_win from jsonb_array_elements(v_scored) c where c ->> 'partner_id' = v_win_pid;
  v_prob := (v_win ->> 'propensity')::numeric;
  v_mode := case when v_hint is not null then v_hint
                 when v_lane and v_win_pid = v_x_pid then 'exploration'
                 else v_smode end;

  return jsonb_build_object('winner', v_win, 'stage', v_stage, 'scoring_mode', v_smode, 'mode', v_mode, 'eval_segment', v_eval,
           'holdout', v_hold, 'holdout_share', round(v_hold_share, 3),
           'draw', case when v_lane then v_draw end, 'exploration_share', v_exp,
           'lane', jsonb_build_object('applied', v_lane, 'x_partner_id', case when v_lane then v_x_pid::bigint end),
           'selection_probability', v_prob, 'candidates', v_scored, 'policy_version', v_pol_ver, 'stats_at', v_stats_at,
           'params_variant', v_variant, 'model_version', case when v_model_dec then v_m ->> 'deciding' end,
           'feature_hash', v_m ->> 'feature_hash', 'shadow', v_m -> 'shadow', 'seed', v_seed, 'seed_source', v_seed_src,
           'why', null, 'challenger_share', v_q);
end $fn$;

-- the m24b entry point: a wrapper (test_m24 and older callers)
create or replace function b2b.route_score(p_lead_id bigint, p_segment text, p_kept jsonb, p_seed numeric, p_is_test boolean)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select b2b.stage_score(jsonb_build_object('lead_id', p_lead_id, 'segment', p_segment, 'seed', p_seed, 'is_test', p_is_test, 'lane_allowed', true), p_kept);
$fn$;

-- the m6a entry point: the middle-tier CPE of one offer
create or replace function b2b.cpe_net(p_partner bigint, p_programme bigint, p_fees jsonb)
returns numeric language sql stable set search_path = '' as $fn$
  select (b2b.cpe_detail(p_partner, p_programme, p_fees, 'middle', null) ->> 'cpe')::numeric;
$fn$;

-- ======================================================================================================== rule_matches
/* Step 2 conditions against the lead and the interest being tried: sources, course_keys, levels, modes, university_ids
   (the interest's university or any it named), states (b2b.lead_geo, norm_key compare), campaign_contains,
   specializations (norm_key of the interest's specialization) and paid (boolean, b2b.lead_attribution). An empty or
   absent array matches everything. */
create or replace function b2b.rule_matches(c jsonb, l public.student_leads, v_int jsonb)
returns boolean language plpgsql stable set search_path = '' as $fn$
declare
  v_geo jsonb;
begin
  if jsonb_typeof(c) <> 'object' then return true; end if;
  if jsonb_array_length(coalesce(c -> 'sources', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'sources') s where lower(s) = lower(coalesce(l.lead_source, ''))) then return false; end if;
  if jsonb_array_length(coalesce(c -> 'course_keys', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'course_keys') s where s = v_int ->> 'course_key') then return false; end if;
  if jsonb_array_length(coalesce(c -> 'levels', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'levels') s where s = v_int ->> 'level') then return false; end if;
  if jsonb_array_length(coalesce(c -> 'modes', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'modes') s where s = v_int ->> 'mode') then return false; end if;
  if jsonb_array_length(coalesce(c -> 'university_ids', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'university_ids') s
                      where s = v_int ->> 'university_id'
                         or (jsonb_typeof(v_int -> 'university_ids') = 'array' and (v_int -> 'university_ids') @> to_jsonb(array[nullif(s, '')::bigint]))) then return false; end if;
  if jsonb_array_length(coalesce(c -> 'specializations', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(c -> 'specializations') s
                      where b2b.norm_key(s) <> '' and b2b.norm_key(s) = b2b.norm_key(v_int ->> 'specialization')) then return false; end if;
  if jsonb_array_length(coalesce(c -> 'states', '[]')) > 0 then
    v_geo := b2b.lead_geo(l);
    if not exists (select 1 from jsonb_array_elements_text(c -> 'states') s
                    where b2b.norm_key(s) <> '' and b2b.norm_key(s) = b2b.norm_key(v_geo ->> 'state')) then return false; end if;
  end if;
  if coalesce(c ->> 'campaign_contains', '') <> ''
     and not (coalesce(l.campaign, '') ilike '%' || replace(replace(replace(c ->> 'campaign_contains', '\', '\\'), '%', '\%'), '_', '\_') || '%') then return false; end if;
  if jsonb_typeof(c -> 'paid') = 'boolean'
     and coalesce((b2b.lead_attribution(l) ->> 'paid')::boolean, false) <> (c ->> 'paid')::boolean then return false; end if;
  return true;
end $fn$;

-- ======================================================================================================== route_decide
/* The decision for one lead (PART 3 R1-R9, PART 4, PART 7 R8). p_how: auto (the sweep, a YES answer), pass (Pass to
   CRM), to_partners (manual route from B2C), requalify (a nurture lead that qualified), reroute (Admin re-route to
   partners), cascade (after a duplicate, rejection, failure or paused partner: the episode's origin gives the context),
   sandbox (test leads only). v_ctx = the origin for a cascade, else p_how; manual = to_partners | reroute.
   Rules by context (D14): R5 only for 'auto'; R6, the import choice and R7 only for 'auto' and 'pass'; R4 skipped in
   manual contexts; manual contexts have no exploration lane, no to_b2c rules, mode 'manual' and fail into
   manual_route_failed with a cause. R8 asks for consent on auto, pass, requalify and their cascades.
   p_commit false previews; outcomes with_partner (R3), re-enquired (R2/R4 with an open hold), consent_pending and
   test_lead are never committed. On commit: engine_decisions, the allocation (origin, override, stage, factors, paid),
   the lead's allocation columns, the directive release, Not passed, the partner bar after a duplicate cascade, and the
   events lead.routed / b2c.lead_handed_off (handoff_payload) / lead.not_passed. Every display key is stored (C112);
   the free-text note is kept next to any why (C124). The GUC b2b.route_seed forces the seed (tests). */
create or replace function b2b.route_decide(p_lead_id bigint, p_commit boolean, p_note text, p_how text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  fx jsonb;
  v_set_ver int := (select s.version from b2b.settings s where s.key = 'engine');
  v_actor jsonb := b2b.actor();
  v_attempt_limit int;
  v_partner_limit int;
  v_unknown text := coalesce(nullif(e ->> 'criteria_unknown', ''), 'fail');
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month_frac numeric := extract(day from now() at time zone 'Asia/Kolkata')
                          / extract(day from (date_trunc('month', now() at time zone 'Asia/Kolkata') + interval '1 month - 1 day'));
  v_ready jsonb;
  v_test boolean;
  v_cycle int;
  v_class jsonb;
  v_ints jsonb;
  v_int jsonb;
  v_bar jsonb;
  v_hold jsonb;
  v_hold_open boolean;
  v_consent jsonb;
  v_attr jsonb;
  v_ep jsonb;
  v_feat jsonb;
  v_geo jsonb;
  v_ctx text;
  v_manual boolean;
  v_open b2b.allocations;
  v_already boolean;
  v_d int := 0;
  v_j int := 0;
  v_tried_ep int := 0;
  v_prev bigint[] := '{}';
  v_dup bigint[] := '{}';
  v_all jsonb := '[]';
  v_kept jsonb := '[]';
  v_excluded jsonb := '[]';
  v_rules jsonb := '[]';
  v_interests jsonb := '[]';
  v_offered boolean := false;
  v_rank int;
  v_reason text;
  v_cause text;
  v_lane text;
  v_mode text;
  v_smode text;
  v_stage text;
  v_dest text;
  v_outcome text := 'decided';
  v_why text;
  v_fixed boolean := false;
  v_hint text;
  v_ids bigint[];
  r record;
  i jsonb;
  d b2b.intake_directives;
  v_sc jsonb;
  v_win jsonb;
  v_prob numeric := 1;
  v_draw numeric;
  v_share numeric := 0;
  v_hold_b boolean := false;
  v_hold_share numeric;
  v_pol_ver int;
  v_stats_at timestamptz;
  v_seed numeric;
  v_seed_src text := 'random';
  v_seed_guc text;
  v_eval text;
  v_segx text;
  v_score numeric;
  v_try int := 0;
  v_ct int;
  v_cm int;
  v_cr jsonb;
  v_dec_id bigint;
  v_alloc_id bigint;
  v_attempt_no int;
  v_origin text;
  v_x jsonb;
  v_fp text;
  v_cands jsonb;
  v_lane_ok boolean;
  v_sbx jsonb := '[]';
begin
  if p_how not in ('auto', 'pass', 'to_partners', 'requalify', 'reroute', 'cascade', 'sandbox') then
    raise exception 'unknown routing request' using errcode = '22023';
  end if;
  fx := case when jsonb_typeof(e -> 'a3_fixed') = 'object' then e -> 'a3_fixed' else '{}'::jsonb end;
  v_attempt_limit := round(coalesce(b2b.stats_num(fx -> 'attempt_limit'), 2))::int;
  v_partner_limit := round(coalesce(b2b.stats_num(fx -> 'partner_limit'), 3))::int;

  -- ---------- Step 0: load (the lock first, so every read is of the locked row) ----------
  if p_commit then
    select * into l from public.student_leads where id = p_lead_id for update;
  else
    select * into l from public.student_leads where id = p_lead_id;
  end if;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if (l.deleted_at is not null or l.merged_into_id is not null) and p_commit then
    raise exception 'deleted or merged leads are not routed' using errcode = '22023';
  end if;

  v_cycle := coalesce(l.cycle_no, 1);
  v_ready := b2b.lead_readiness(l);
  v_test := coalesce((v_ready ->> 'is_test')::boolean, false);
  v_class := b2b.lead_class(l);
  v_ints := b2b.lead_interest_list(l);
  v_int := v_ints -> 0;
  v_bar := b2b.partner_bar(l);
  v_hold := b2b.b2c_hold(l);
  v_hold_open := coalesce((v_hold ->> 'open')::boolean, false);
  v_consent := b2b.partner_consent(l);
  v_attr := b2b.lead_attribution(l);
  v_ep := b2b.episode(l);
  v_feat := b2b.ml_lead_features(l);
  v_geo := b2b.lead_geo(l);
  v_ctx := case when p_how = 'cascade' then coalesce(nullif(v_ep ->> 'origin', ''), 'auto') else p_how end;
  v_manual := v_ctx in ('to_partners', 'reroute');
  v_origin := case when p_how = 'cascade' then v_ctx when p_how in ('pass', 'to_partners', 'requalify', 'reroute', 'sandbox') then p_how else 'auto' end;
  if v_origin not in ('auto', 'pass', 'to_partners', 'requalify', 'reroute', 'sandbox') then v_origin := 'auto'; end if;

  select a.* into v_open from b2b.allocations a
   where a.lead_id = l.id and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off')
   order by a.created_at desc, a.id desc limit 1;
  v_already := v_open.id is not null or l.destination_type is not null;
  if p_commit and v_already then raise exception 'this lead is already routed' using errcode = '22023'; end if;
  if p_how = 'sandbox' and not v_test then raise exception 'the sandbox is for test leads' using errcode = '22023'; end if;

  -- the seed: the test hook b2b.route_seed, else random
  v_seed_guc := nullif(trim(coalesce(current_setting('b2b.route_seed', true), '')), '');
  if v_seed_guc is not null and v_seed_guc ~ '^-?[0-9]+(\.[0-9]+)?$' then
    v_seed := v_seed_guc::numeric; v_seed_src := 'forced';
  else
    v_seed := round(random()::numeric, 12);
  end if;

  -- ---------- R1: test leads ----------
  if v_test and p_how <> 'sandbox' then
    v_dest := 'none'; v_reason := 'test_lead'; v_outcome := 'test_lead'; v_mode := 'rule';
  elsif v_test then
    -- the sandbox: the first offered interest, partners with a test endpoint, the highest CPE
    for i in select x from jsonb_array_elements(v_ints) x loop
      v_sbx := b2b.offer_candidates(i, true);
      if jsonb_array_length(v_sbx) > 0 then
        v_int := i; v_rank := (i ->> 'rank')::int; v_offered := true;
        v_interests := v_interests || jsonb_build_object('rank', i ->> 'rank', 'course_key', i ->> 'course_key', 'course_text', i ->> 'course_text', 'segment', i ->> 'segment', 'outcome', 'offered');
        exit;
      end if;
      v_interests := v_interests || jsonb_build_object('rank', i ->> 'rank', 'course_key', i ->> 'course_key', 'course_text', i ->> 'course_text', 'segment', i ->> 'segment', 'outcome', 'no_offer');
    end loop;
    if not v_offered then
      v_dest := 'none'; v_reason := 'no_sandbox_partner'; v_mode := 'rule';
    else
      v_all := v_sbx;
      v_kept := (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(v_sbx) x where x ->> 'status' <> 'closed');
      v_hint := 'rule';
    end if;
  end if;

  -- ---------- R2: the permanent partner bar ----------
  if v_dest is null and v_bar is not null and not v_test then
    if v_manual and p_how <> 'cascade' and p_commit then
      raise exception 'partner_barred: partner-barred (%) since %: this lead can never be sent to partners',
        v_bar ->> 'reason', (v_bar ->> 'barred_at')::timestamptz::date using errcode = '22023';
    end if;
    if v_hold_open and not p_commit then
      v_outcome := 're-enquired'; v_dest := 'in_house'; v_reason := coalesce(v_hold ->> 'reason', 'partner_barred'); v_lane := coalesce(v_hold ->> 'lane', 'sales'); v_mode := 'rule';
    else
      v_dest := 'in_house'; v_reason := 'partner_barred'; v_lane := 'sales'; v_mode := 'rule';
    end if;
  end if;

  -- ---------- R3: with a partner (open allocation, lost-in-grace included) ----------
  if v_dest is null and v_open.id is not null and v_open.destination_type = 'partner' then
    v_outcome := 'with_partner'; v_dest := 'partner'; v_mode := 'rule';
    v_win := jsonb_build_object('partner_id', v_open.partner_id, 'name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = v_open.partner_id),
                                'cpe', v_open.cpe_net_inr, 'ncpl', v_open.ncpl_inr, 'has_rate', v_open.cpe_net_inr is not null);
  end if;

  -- ---------- R4: held by B2C for selling ----------
  if v_dest is null and v_hold ->> 'kind' = 'selling' and not v_manual then
    if v_hold_open and not p_commit then
      v_outcome := 're-enquired'; v_dest := 'in_house'; v_reason := coalesce(v_hold ->> 'reason', 'b2c_held'); v_lane := coalesce(v_hold ->> 'lane', 'sales'); v_mode := 'rule';
    else
      v_dest := 'in_house'; v_reason := 'b2c_held'; v_lane := coalesce(v_hold ->> 'lane', 'sales'); v_mode := 'rule';
    end if;
  end if;

  -- ---------- R6 (before R5, PART 1.8): created in the B2C CRM ----------
  if v_dest is null and p_how in ('auto', 'pass')
     and lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(case when jsonb_typeof(e -> 'b2c_sources') = 'array' then e -> 'b2c_sources'
                                                                                                    else '["b2c_created","b2c_whatsapp"]'::jsonb end) x) then
    v_dest := 'in_house'; v_reason := 'b2c_created'; v_lane := 'sales'; v_mode := 'rule';
  end if;

  -- ---------- R5: junk, spam and programme mismatch are not passed to any CRM ----------
  if v_dest is null and p_how = 'auto' and v_class ->> 'class' in ('junk', 'mismatch') then
    v_dest := 'not_passed'; v_reason := v_class ->> 'reason'; v_mode := 'rule';
  end if;

  -- ---------- the import's choice ----------
  if v_dest is null and p_how = 'auto' then
    d := b2b.lead_directive(l.id);
    if d.directive = 'b2c' then
      v_dest := 'in_house'; v_reason := 'import_choice'; v_lane := coalesce(d.b2c_lane, 'sales'); v_mode := 'rule';
    end if;
  end if;

  -- ---------- R7: not qualified: B2C qualification nurture ----------
  if v_dest is null and p_how in ('auto', 'pass') and v_class ->> 'class' = 'unqualified' then
    v_dest := 'in_house'; v_reason := 'not_qualified'; v_lane := 'nurture'; v_mode := 'fallback';
  end if;

  -- ---------- R8: partner-sharing consent ----------
  if v_dest is null and not v_test and not coalesce((v_consent ->> 'given')::boolean, false) then
    if coalesce((v_consent ->> 'refused')::boolean, false) or e ->> 'consent_policy' = 'b2c_sales' then
      if v_manual then
        if p_how <> 'cascade' and p_commit then
          raise exception 'no_consent: the student has not consented to sharing with partners' using errcode = '22023';
        end if;
        v_dest := 'in_house'; v_reason := 'manual_route_failed'; v_cause := 'no_partner_consent'; v_lane := 'sales'; v_mode := 'manual';
      else
        v_dest := 'in_house'; v_reason := 'no_partner_consent'; v_lane := 'sales'; v_mode := 'fallback';
      end if;
    elsif v_manual then
      if p_how <> 'cascade' and p_commit then
        raise exception 'no_consent: the student has not consented to sharing with partners' using errcode = '22023';
      end if;
      v_dest := 'in_house'; v_reason := 'manual_route_failed'; v_cause := 'no_partner_consent'; v_lane := 'sales'; v_mode := 'manual';
    elsif (v_consent ->> 'open_request') is not null then
      v_outcome := 'consent_pending'; v_dest := 'consent_pending'; v_mode := 'rule';
    elsif (v_consent ->> 'expired_request') is not null then
      v_dest := 'in_house'; v_reason := 'consent_no_answer'; v_lane := 'nurture'; v_mode := 'fallback';
    elsif p_commit then
      v_cr := b2b.consent_request_create(l.id, 'decision');
      v_outcome := 'consent_requested'; v_dest := 'consent_requested'; v_mode := 'rule';
    else
      v_outcome := 'consent_request'; v_dest := 'consent_request'; v_mode := 'rule';
    end if;
  end if;

  -- ---------- R9: the episode's limits (PART 5.7) ----------
  if v_dest is null then
    select coalesce(count(*) filter (where a.status = 'duplicate' and coalesce(a.claim_proof_ok, false) and not coalesce(a.returning_lead, false)), 0),
           coalesce(count(*) filter (where a.status = 'rejected' or (a.status = 'duplicate' and not coalesce(a.claim_proof_ok, false))), 0),
           coalesce(count(distinct a.partner_id) filter (where a.status in ('pushed', 'accepted', 'closed', 'duplicate', 'rejected')
                                                        or (a.status = 'failed' and coalesce(a.push_attempts, 0) > 0)), 0)
      into v_d, v_j, v_tried_ep
      from b2b.allocations a
     where a.id in (select (x #>> '{}')::bigint from jsonb_array_elements(coalesce(v_ep -> 'partner_allocation_ids', '[]'::jsonb)) x);
    select coalesce(array_agg(distinct a.partner_id), '{}') into v_prev from b2b.allocations a
     where a.lead_id = l.id and a.cycle_no = v_cycle and a.destination_type = 'partner' and a.status in ('duplicate', 'rejected', 'failed', 'recalled');
    v_dup := coalesce(b2b.dup_history(l.id), '{}');
    if v_d >= v_attempt_limit then v_reason := 'duplicate_cascade';
    elsif v_d + v_j >= v_attempt_limit then v_reason := 'partner_attempts_exhausted';
    elsif v_tried_ep >= v_partner_limit then v_reason := 'partners_unreachable';
    end if;
    if v_reason is not null then v_dest := 'in_house'; v_lane := 'sales'; end if;
  end if;

  -- ---------- R9 Step 1 + Step 2, interest by interest (PART 4 'Several interests') ----------
  if v_dest is null then
    for i in select x from jsonb_array_elements(v_ints) x loop
      if not b2b.interest_offered(i) then
        v_interests := v_interests || jsonb_build_object('rank', (i ->> 'rank')::int, 'course_key', i ->> 'course_key', 'course_text', i ->> 'course_text',
                                                         'segment', i ->> 'segment', 'outcome', 'no_offer');
        continue;
      end if;
      v_offered := true;
      v_int := i;
      v_rank := (i ->> 'rank')::int;
      v_all := b2b.offer_candidates(i, false);

      -- Step 1 exclusions, with causes, in order: duplicate history, tried this enquiry, paused, criteria, caps
      select coalesce(jsonb_agg((c - 'offers' - 'programmes' - 'offers_count')
                                || jsonb_build_object('offers', el.offers_ok, 'programmes', el.progs_ok, 'offers_count', el.n_ok)
                                order by (c ->> 'partner_id')::bigint) filter (where w.cause is null), '[]'::jsonb),
             coalesce(jsonb_agg(jsonb_build_object('partner_id', (c ->> 'partner_id')::bigint, 'name', c ->> 'name', 'why', w.why, 'cause', w.cause)
                                order by (c ->> 'partner_id')::bigint) filter (where w.cause is not null), '[]'::jsonb)
        into v_kept, v_excluded
        from jsonb_array_elements(v_all) c
        cross join lateral (select (c ->> 'partner_id')::bigint as pid) p
        cross join lateral (
          select coalesce(jsonb_agg(o order by (o ->> 'cpe')::numeric desc nulls last, (o ->> 'programme_id')::bigint) filter (where k.ok), '[]'::jsonb) as offers_ok,
                 to_jsonb(coalesce((array_agg((o ->> 'programme_id')::bigint order by (o ->> 'cpe')::numeric desc nulls last, (o ->> 'programme_id')::bigint) filter (where k.ok))[1:20], '{}'::bigint[])) as progs_ok,
                 (count(*) filter (where k.ok))::int as n_ok
            from jsonb_array_elements(case when jsonb_typeof(c -> 'offers') = 'array' then c -> 'offers' else '[]'::jsonb end) o
            cross join lateral (select b2b.offer_eligible(o -> 'eligibility', o ->> 'cat_min_qualification', (o ->> 'cat_min_pct')::numeric, l, v_unknown) as ok) k) el
        cross join lateral (select b2b.criteria_check(c -> 'criteria', l, v_geo, v_unknown) as ck) cc
        cross join lateral (select case
            when p.pid = any (v_dup) then array['duplicate_history', 'reported this student as a duplicate before']
            when p.pid = any (v_prev) then array['tried', 'already tried for this enquiry']
            when coalesce(c ->> 'status', '') <> 'active' then array['paused', 'partner is ' || coalesce(c ->> 'status', 'not active')]
            when not coalesce((cc.ck ->> 'ok')::boolean, false) then array['criteria', coalesce(cc.ck ->> 'why', 'outside the partner''s criteria')]
            when el.n_ok = 0 then array['criteria', 'the student does not meet the programme''s eligibility']
            when coalesce((c ->> 'leads_today')::int, 0) >= coalesce((c ->> 'daily_cap')::int, 2147483647) then array['caps', 'at its daily cap']
            when coalesce((c ->> 'leads_month')::int, 0) >= coalesce((c ->> 'monthly_cap')::int, 2147483647) then array['caps', 'at its monthly cap']
            end as arr) z
        cross join lateral (select z.arr[1] as cause, z.arr[2] as why) w;

      -- Step 2: the Admin's rules in priority order (to_b2c skipped in manual contexts)
      for r in select * from b2b.routing_rules where active order by priority, id loop
        if r.action = 'to_b2c' then
          if v_manual then continue; end if;
          if b2b.rule_matches(r.conditions, l, i) then
            v_reason := 'rule'; v_lane := coalesce(r.b2c_lane, 'sales'); v_dest := 'in_house'; v_mode := 'rule';
            v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', 'sent to B2C ' || coalesce(r.b2c_lane, 'sales'));
            exit;
          end if;
          continue;
        end if;
        continue when not b2b.rule_matches(r.conditions, l, i);
        select coalesce(array_agg((c ->> 'partner_id')::bigint), '{}') into v_ids
          from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (r.partner_ids);
        if r.action = 'exclude' then
          v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', (c ->> 'partner_id')::bigint, 'name', c ->> 'name', 'why', 'rule: ' || r.name, 'cause', 'rule'))
                                                  from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (v_ids)), '[]'::jsonb);
          v_kept := coalesce((select jsonb_agg(c) from jsonb_array_elements(v_kept) c where not (c ->> 'partner_id')::bigint = any (v_ids)), '[]'::jsonb);
          v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', format('%s excluded', cardinality(v_ids)));
        elsif cardinality(v_ids) = 0 then
          v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', 'skipped: none of its partners is eligible');
        else
          v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', (c ->> 'partner_id')::bigint, 'name', c ->> 'name', 'why', 'rule: ' || r.name, 'cause', 'rule'))
                                                  from jsonb_array_elements(v_kept) c where not (c ->> 'partner_id')::bigint = any (v_ids)), '[]'::jsonb);
          v_kept := coalesce((select jsonb_agg(c) from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (v_ids)), '[]'::jsonb);
          v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', format('%s kept', cardinality(v_ids)));
          v_hint := 'rule';
          if r.action = 'fix_partner' then v_fixed := true; exit; end if;
        end if;
      end loop;

      v_interests := v_interests || jsonb_build_object('rank', (i ->> 'rank')::int, 'course_key', i ->> 'course_key', 'course_text', i ->> 'course_text',
                                                       'segment', i ->> 'segment', 'outcome', 'offered');
      exit;   -- an offered interest ends the loop, even when no candidate survives (critic B4)
    end loop;

    if not v_offered then
      v_reason := 'no_partner_offers_programme'; v_dest := 'in_house'; v_lane := 'sales';
    elsif v_dest is null and jsonb_array_length(v_kept) = 0 then
      -- partners ran out (D3)
      if v_d >= 1 then
        v_reason := 'duplicate_cascade';
      elsif not exists (select 1 from jsonb_array_elements(v_excluded) x where x ->> 'cause' <> 'tried') then
        v_reason := case when v_j >= 1 then 'partner_attempts_exhausted' else 'partners_unreachable' end;
      else
        v_reason := 'no_capacity';
        select x ->> 'cause' into v_cause from jsonb_array_elements(v_excluded) x
         where x ->> 'cause' in ('caps', 'paused', 'criteria', 'rule', 'duplicate_history')
         group by x ->> 'cause' order by count(*) desc, min(x ->> 'cause') limit 1;
        v_cause := coalesce(v_cause, 'caps');
      end if;
      v_dest := 'in_house'; v_lane := 'sales';
    end if;
  end if;

  -- a manual route that no partner can take goes back to its B2C counsellor
  if v_dest = 'in_house' and v_manual and v_reason not in ('manual_route_failed', 'b2c_held', 'partner_barred') then
    v_cause := coalesce(v_cause, v_reason); v_reason := 'manual_route_failed'; v_lane := 'sales'; v_mode := 'manual';
  end if;

  -- ---------- contractual minimums behind schedule are served first (unless a rule fixed the partner) ----------
  if v_dest is null and not v_fixed and jsonb_array_length(v_kept) > 1 then
    v_x := (select jsonb_agg(c) from jsonb_array_elements(v_kept) c
             where coalesce((c ->> 'contract_min_monthly')::int, 0) > 0
               and coalesce((c ->> 'leads_month')::int, 0) < (c ->> 'contract_min_monthly')::int * v_month_frac);
    if v_x is not null and jsonb_array_length(v_x) < jsonb_array_length(v_kept) then
      v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', (c ->> 'partner_id')::bigint, 'name', c ->> 'name',
                                                                                 'why', 'a contractual minimum behind schedule is served first', 'cause', null))
                                              from jsonb_array_elements(v_kept) c where not (v_x @> jsonb_build_array(c))), '[]'::jsonb);
      v_kept := v_x; v_hint := 'minimum';
    elsif v_x is not null then
      v_hint := 'minimum';
    end if;
  end if;

  -- ---------- Step 3: the stage score, re-checking the winner's cap under a lock at commit ----------
  if v_dest is null then
    v_segx := nullif(v_int ->> 'segment_exact', '');
    v_lane_ok := not v_fixed and v_hint is null and not v_manual;
    loop
      v_sc := b2b.stage_score(jsonb_build_object('lead_id', l.id, 'seed', v_seed, 'seed_source', v_seed_src, 'is_test', v_test,
                                                 'segment', v_int ->> 'segment', 'segment_exact', v_segx, 'lane_allowed', v_lane_ok,
                                                 'mode_hint', case when v_manual then 'manual' else v_hint end), v_kept);
      v_win := v_sc -> 'winner';
      exit when v_win is null or not p_commit or v_test or v_try >= 3;
      perform pg_advisory_xact_lock(hashtext('b2b.partner_cap:' || (v_win ->> 'partner_id')));
      select (count(*) filter (where a.created_at >= v_today))::int, (count(*) filter (where a.created_at >= v_month))::int into v_ct, v_cm
        from b2b.allocations a
       where a.partner_id = (v_win ->> 'partner_id')::bigint and a.destination_type = 'partner' and not a.is_test
         and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'closed') and a.created_at >= v_month;
      exit when v_ct < coalesce((v_win ->> 'daily_cap')::int, 2147483647) and v_cm < coalesce((v_win ->> 'monthly_cap')::int, 2147483647);
      -- the winner filled up while we were deciding: leave it out and score again
      v_excluded := v_excluded || jsonb_build_object('partner_id', (v_win ->> 'partner_id')::bigint, 'name', v_win ->> 'name',
                                                     'why', case when v_ct >= coalesce((v_win ->> 'daily_cap')::int, 2147483647) then 'at its daily cap' else 'at its monthly cap' end, 'cause', 'caps');
      v_kept := coalesce((select jsonb_agg(c) from jsonb_array_elements(v_kept) c where c ->> 'partner_id' <> v_win ->> 'partner_id'), '[]'::jsonb);
      v_why := 'a partner reached its cap while deciding; scored again';
      v_try := v_try + 1;
      if jsonb_array_length(v_kept) = 0 then v_win := null; v_sc := null; exit; end if;
    end loop;
    if v_win is null then
      v_reason := 'no_capacity'; v_cause := 'caps'; v_dest := 'in_house'; v_lane := 'sales';
      if v_manual then v_cause := 'no_capacity'; v_reason := 'manual_route_failed'; v_mode := 'manual'; end if;
    else
      v_dest := 'partner';
      v_mode := case when v_manual then 'manual' else v_sc ->> 'mode' end;
      v_smode := v_sc ->> 'scoring_mode';
      v_stage := v_sc ->> 'stage';
      v_hold_b := coalesce((v_sc ->> 'holdout')::boolean, false);
      v_hold_share := (v_sc ->> 'holdout_share')::numeric;
      v_draw := (v_sc ->> 'draw')::numeric;
      v_share := coalesce((v_sc ->> 'exploration_share')::numeric, 0);
      v_prob := coalesce((v_sc ->> 'selection_probability')::numeric, 1);
      v_pol_ver := (v_sc ->> 'policy_version')::int;
      v_stats_at := (v_sc ->> 'stats_at')::timestamptz;
      v_eval := v_sc ->> 'eval_segment';
      v_score := (v_win ->> 'score')::numeric;
      v_why := coalesce(v_why, v_sc ->> 'why');
      v_interests := (select coalesce(jsonb_agg(case when (x ->> 'rank')::int = v_rank then x || '{"outcome":"routed"}'::jsonb else x end order by (x ->> 'rank')::int), '[]'::jsonb)
                        from jsonb_array_elements(v_interests) x);
    end if;
  end if;

  -- ---------- the mode of a B2C hand-off ----------
  if v_dest = 'in_house' then
    v_lane := coalesce(v_lane, 'sales');
    v_mode := coalesce(v_mode, case when v_reason in ('b2c_created', 'rule', 'b2c_held', 'import_choice', 'partner_barred') then 'rule'
                                    when v_manual then 'manual' else 'fallback' end);
    if v_manual then v_mode := 'manual'; end if;
    v_prob := 1; v_win := null;
  end if;
  if v_dest in ('none', 'not_passed', 'consent_requested', 'consent_pending', 'consent_request') then v_prob := 1; v_win := null; end if;

  -- ---------- the candidate log: the scored ones (eligible) and the excluded ones with their cause ----------
  if v_sc is not null then
    v_cands := (select coalesce(jsonb_agg((c - 'criteria' - 'offers') || '{"eligible":true}'::jsonb order by (c ->> 'tie_rank')::int), '[]'::jsonb)
                  from jsonb_array_elements(v_sc -> 'candidates') c);
  else
    v_cands := (select coalesce(jsonb_agg((c - 'criteria' - 'offers')
                                           || jsonb_build_object('eligible', exists (select 1 from jsonb_array_elements(v_kept) k where k ->> 'partner_id' = c ->> 'partner_id'))
                                           order by (c ->> 'partner_id')::bigint), '[]'::jsonb)
                  from jsonb_array_elements(v_all) c
                 where exists (select 1 from jsonb_array_elements(v_kept) k where k ->> 'partner_id' = c ->> 'partner_id'));
  end if;
  v_cands := v_cands || (select coalesce(jsonb_agg((c - 'criteria' - 'offers')
                                                   || jsonb_build_object('eligible', false, 'cause', x.y ->> 'cause', 'why', x.y ->> 'why')
                                                   order by (c ->> 'partner_id')::bigint), '[]'::jsonb)
                           from jsonb_array_elements(v_all) c
                           join lateral (select y from jsonb_array_elements(v_excluded) y where y ->> 'partner_id' = c ->> 'partner_id' order by 1 limit 1) x on true
                          where not exists (select 1 from jsonb_array_elements(v_cands) k where k ->> 'partner_id' = c ->> 'partner_id'));

  v_x := jsonb_build_object(
    'lead_id', l.id, 'cycle_no', v_cycle, 'is_test', v_test, 'readiness', v_ready, 'interest', v_int, 'interests', v_interests, 'interest_rank', v_rank,
    'class', v_class, 'attribution', v_attr, 'bar', v_bar, 'hold', v_hold, 'consent', v_consent,
    'destination', v_dest, 'outcome', v_outcome, 'reason', v_reason, 'cause', v_cause, 'mode', v_mode, 'scoring_mode', v_smode, 'stage', v_stage,
    'b2c_lane', case when v_dest = 'in_house' then v_lane end,
    'paid', case when coalesce((v_attr ->> 'paid')::boolean, false) then v_attr ->> 'label' end,
    'partner_id', (v_win ->> 'partner_id')::bigint, 'partner_name', v_win ->> 'name',
    'cpe', (v_win ->> 'cpe')::numeric, 'ncpl', (v_win ->> 'ncpl')::numeric, 'has_rate', (v_win ->> 'has_rate')::boolean, 'score', v_score,
    'eval_segment', v_eval, 'segment_exact', v_segx, 'how', p_how, 'origin', v_origin)
  || jsonb_build_object(
    'candidates', v_cands, 'excluded', v_excluded, 'rules', v_rules,
    'draw', v_draw, 'exploration_share', v_share, 'lane', coalesce(v_sc -> 'lane', jsonb_build_object('applied', false, 'x_partner_id', null)),
    'selection_probability', round(v_prob, 4), 'settings_version', v_set_ver, 'policy_version', v_pol_ver,
    'holdout', v_hold_b, 'holdout_share', v_hold_share, 'seed', v_seed, 'seed_source', v_seed_src, 'stats_at', v_stats_at,
    'model_version', v_sc ->> 'model_version', 'feature_hash', v_sc ->> 'feature_hash', 'shadow', v_sc -> 'shadow', 'params_variant', v_sc ->> 'params_variant', 'why', v_why,
    'already_routed', v_already, 'committed', false, 'decision_id', null, 'allocation_id', null, 'reference', null, 'consent_request', v_cr);

  if not p_commit then return v_x; end if;
  if v_outcome in ('test_lead', 'with_partner', 're-enquired', 'consent_pending') or v_dest = 'none' then return v_x; end if;
  if v_outcome = 'consent_requested' then return v_x || jsonb_build_object('committed', true); end if;

  -- ---------- R5 commit: Not passed ----------
  if v_dest = 'not_passed' then
    v_fp := b2b.np_fingerprint(l);
    insert into b2b.not_passed (lead_id, reason, lead_status, requested_course, lead_source, fingerprint, detail, override)
    values (l.id, v_reason, l.lead_status, coalesce(nullif(l.interested_course, ''), l.field_of_interest), l.lead_source, v_fp, v_class ->> 'detail', false)
    on conflict (lead_id) do update
      set reason = excluded.reason, lead_status = excluded.lead_status, requested_course = excluded.requested_course,
          lead_source = excluded.lead_source, fingerprint = excluded.fingerprint, detail = excluded.detail, override = false,
          decided_at = now(), times = b2b.not_passed.times + 1, passed_at = null, passed_by = null, pass_note = null;
    perform b2b.log_event('lead.not_passed', l.id, null, null, jsonb_build_object('reason', v_reason, 'lead_status', l.lead_status, 'detail', v_class ->> 'detail'));
    return v_x || jsonb_build_object('committed', true);
  end if;

  -- ---------- commit: the decision ----------
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, reason, candidates, excluded, rules,
                                    seed, selection_probability, settings_version, is_test, actor_type, actor_id, b2c_lane,
                                    scoring_mode, holdout, policy_version, stats_at, model_version, shadow,
                                    stage, score, eval_segment, segment_exact, class, attribution, interest_rank, interests, hold, bar, how,
                                    holdout_share, draw, features, features_hash, feature_hash)
  values (l.id, v_cycle, v_int ->> 'segment', v_int, v_mode, v_dest, (v_win ->> 'partner_id')::bigint,
          coalesce(v_reason, nullif(concat_ws(' · ', v_why, nullif(trim(p_note), '')), '')),
          v_cands, v_excluded, v_rules, v_seed, round(v_prob, 4), v_set_ver, v_test, coalesce(v_actor ->> 'type', 'system'), v_actor ->> 'id',
          case when v_dest = 'in_house' then v_lane end,
          v_smode, v_hold_b, v_pol_ver, v_stats_at, v_sc ->> 'model_version', v_sc -> 'shadow',
          v_stage, v_score, v_eval, v_segx, v_class ->> 'class', v_attr, v_rank, v_interests, v_hold, v_bar, p_how,
          v_hold_share, v_draw, v_feat, md5(v_feat::text), v_sc ->> 'feature_hash')
  returning id into v_dec_id;

  update b2b.not_passed set passed_at = now(), passed_by = coalesce(v_actor ->> 'type', 'system'),
         pass_note = case when p_how = 'pass' then left(p_note, 300) else 'classification changed' end
   where lead_id = l.id and passed_at is null;

  select count(*) + 1 into v_attempt_no from b2b.allocations a where a.lead_id = l.id and a.cycle_no = v_cycle and a.destination_type = 'partner';

  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, reason,
                               cpe_net_inr, ncpl_inr, selection_probability, engine_decision_id, is_test, b2c_lane, override,
                               stage, score_inr, p_enroll, effort_factor, sla_factor, segment_exact, interest_rank, origin,
                               paid, paid_platform, campaign_id, cause, programme_id, model_version)
  values (l.id, v_cycle, v_int ->> 'segment', v_dest, (v_win ->> 'partner_id')::bigint,
          case when v_dest = 'partner' then 'queued' else 'handed_off' end, v_mode, v_attempt_no, coalesce(v_reason, v_why),
          (v_win ->> 'cpe')::numeric, case when v_stage = 'C' then (v_win ->> 'ncpl')::numeric end, round(v_prob, 4), v_dec_id, v_test,
          case when v_dest = 'in_house' then v_lane end, v_origin = 'pass',
          v_stage, v_score, case when v_stage = 'C' then (v_win ->> 'p_used')::numeric end,
          case when v_dest = 'partner' then (v_win ->> 'effort_factor')::numeric end, case when v_dest = 'partner' then (v_win ->> 'sla_factor')::numeric end,
          v_segx, v_rank, v_origin,
          coalesce((v_attr ->> 'paid')::boolean, false), v_attr ->> 'platform', v_attr ->> 'campaign_id', v_cause,
          (v_win -> 'programmes' ->> 0)::bigint, case when v_dest = 'partner' then v_sc ->> 'model_version' end)
  returning id into v_alloc_id;
  update b2b.allocations set reference = 'EDW-' || v_alloc_id where id = v_alloc_id;

  -- B2B writes only the allocation columns; the B2C CRM sets the next stage of a hand-off (Addendum 1 §3)
  update public.student_leads
     set destination_type = v_dest,
         partner_id = (v_win ->> 'partner_id')::bigint,
         allocation_id = v_alloc_id,
         allocated_at = now(),
         allocation_reason = coalesce(v_reason, v_mode),
         stage = case when v_dest = 'partner' then 'allocated' else stage end,
         updated_by = 'b2b'
   where id = l.id;

  -- the source's routing choice has been carried out
  update b2b.intake_directives set released_at = now(), released_by = coalesce(v_actor ->> 'id', v_actor ->> 'type', 'system')
   where lead_id = l.id and released_at is null;

  -- PART 5.4 / 6.3: a duplicate cascade bars the lead from partners for ever
  if v_d >= 1 and (v_reason = 'duplicate_cascade' or (v_reason = 'manual_route_failed' and v_cause = 'duplicate_cascade')) then
    perform b2b.partner_bar_set(l.id, 'duplicate', v_alloc_id, case when v_manual then 'manual_route' else 'engine' end);
  end if;

  if v_dest = 'partner' then
    perform b2b.log_event('lead.routed', l.id, v_alloc_id, (v_win ->> 'partner_id')::bigint,
                          jsonb_build_object('decision_id', v_dec_id, 'mode', v_mode, 'stage', v_stage, 'origin', v_origin, 'reference', 'EDW-' || v_alloc_id,
                                             'test', v_test, 'partner_id', (v_win ->> 'partner_id')::bigint, 'manual_from_b2c', v_manual));
  else
    -- no student message from B2B: the B2C CRM messages the student from its own number (Addendum 1 §2)
    perform b2b.log_event('b2c.lead_handed_off', l.id, v_alloc_id, null, b2b.handoff_payload(v_alloc_id));
  end if;

  return v_x || jsonb_build_object('committed', true, 'decision_id', v_dec_id, 'allocation_id', v_alloc_id, 'reference', 'EDW-' || v_alloc_id);
end $fn$;

-- ======================================================================================================== route_outlook
/* What the engine would do with the lead, in the R1-R9 order and without scoring (lists, the pool, intake answers):
   {outlook none | not_passed | b2c_sales | b2c_nurture | b2c | b2c_held | with_partner | consent_pending | consent_request
   | partners, reason, lane}. No side effects. */
create or replace function b2b.route_outlook(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  v_class jsonb;
  v_hold jsonb;
  v_cons jsonb;
  d b2b.intake_directives;
  v_any_offer boolean := false;
  i jsonb;
begin
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then
    return jsonb_build_object('outlook', 'none', 'reason', 'test_lead', 'lane', null);
  end if;
  if l.deleted_at is not null or l.merged_into_id is not null then
    return jsonb_build_object('outlook', 'none', 'reason', 'deleted or merged', 'lane', null);
  end if;
  if b2b.partner_bar(l) is not null then
    return jsonb_build_object('outlook', 'b2c_sales', 'reason', 'partner_barred', 'lane', 'sales');
  end if;
  if exists (select 1 from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted')) then
    return jsonb_build_object('outlook', 'with_partner', 'reason', null, 'lane', null);
  end if;
  v_hold := b2b.b2c_hold(l);
  if v_hold ->> 'kind' = 'selling' then
    return jsonb_build_object('outlook', 'b2c_held', 'reason', coalesce(v_hold ->> 'reason', 'b2c_held'), 'lane', coalesce(v_hold ->> 'lane', 'sales'));
  end if;
  if lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(case when jsonb_typeof(e -> 'b2c_sources') = 'array' then e -> 'b2c_sources'
                                                                                                 else '["b2c_created","b2c_whatsapp"]'::jsonb end) x) then
    return jsonb_build_object('outlook', 'b2c_sales', 'reason', 'b2c_created', 'lane', 'sales');
  end if;
  v_class := b2b.lead_class(l);
  if v_class ->> 'class' in ('junk', 'mismatch') then
    return jsonb_build_object('outlook', 'not_passed', 'reason', v_class ->> 'reason', 'lane', null);
  end if;
  d := b2b.lead_directive(l.id);
  if d.directive = 'b2c' then
    return jsonb_build_object('outlook', 'b2c', 'reason', 'import_choice', 'lane', coalesce(d.b2c_lane, 'sales'));
  end if;
  if v_class ->> 'class' = 'unqualified' then
    return jsonb_build_object('outlook', 'b2c_nurture', 'reason', 'not_qualified', 'lane', 'nurture');
  end if;
  v_cons := b2b.partner_consent(l);
  if not coalesce((v_cons ->> 'given')::boolean, false) then
    if coalesce((v_cons ->> 'refused')::boolean, false) or e ->> 'consent_policy' = 'b2c_sales' then
      return jsonb_build_object('outlook', 'b2c_sales', 'reason', 'no_partner_consent', 'lane', 'sales');
    end if;
    if (v_cons ->> 'open_request') is not null then return jsonb_build_object('outlook', 'consent_pending', 'reason', null, 'lane', null); end if;
    if (v_cons ->> 'expired_request') is not null then return jsonb_build_object('outlook', 'b2c_nurture', 'reason', 'consent_no_answer', 'lane', 'nurture'); end if;
    return jsonb_build_object('outlook', 'consent_request', 'reason', null, 'lane', null);
  end if;
  for i in select x from jsonb_array_elements(b2b.lead_interest_list(l)) x loop
    if b2b.interest_offered(i) then
      v_any_offer := true;
      if exists (select 1 from b2b.interest_offers(i, false) o join b2b.partners p on p.id = o.partner_id where p.status = 'active') then
        return jsonb_build_object('outlook', 'partners', 'reason', null, 'lane', null);
      end if;
      exit;   -- the engine stays on the first offered interest
    end if;
  end loop;
  return jsonb_build_object('outlook', 'b2c_sales', 'reason', case when v_any_offer then 'no_capacity' else 'no_partner_offers_programme' end, 'lane', 'sales');
end $fn$;

-- ======================================================================================================== pool_lead
/* Why a lead without a destination is still waiting, and what will happen to it at its decision point. Groups: test,
   opted_out, held (review), awaiting_consent, waiting_inactivity (Amendment 1), chatting, too_old (no change in 90
   days), routing_off, due. */
create or replace function b2b.pool_lead(l public.student_leads, p_routing_on boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  r jsonb := b2b.lead_readiness(l);
  d b2b.intake_directives := b2b.lead_directive(l.id);
  o jsonb := b2b.route_outlook(l);
  v_group text;
begin
  v_group := case
    when coalesce((r ->> 'is_test')::boolean, false) then 'test'
    when coalesce(l.is_opted_out, false) then 'opted_out'
    when r -> 'missing' ? 'held for review' then 'held'
    when r -> 'wait' ->> 'kind' = 'consent' then 'awaiting_consent'
    when r -> 'wait' ->> 'kind' = 'inactivity' then 'waiting_inactivity'
    when r -> 'wait' ->> 'kind' = 'chatting' then 'chatting'
    when coalesce(l.updated_at, l.created_at) <= now() - interval '90 days' then 'too_old'
    when not coalesce(p_routing_on, false) then 'routing_off'
    else 'due' end;
  return jsonb_build_object('group', v_group, 'class', r ->> 'class', 'class_reason', r ->> 'class_reason',
                            'not_qualified', coalesce(r -> 'not_qualified', '[]'::jsonb), 'missing', coalesce(r -> 'missing', '[]'::jsonb),
                            'paid', (r ->> 'paid') is not null, 'paid_platform', r ->> 'paid_platform',
                            'import_id', d.import_id,
                            'outlook', o ->> 'outlook', 'outlook_reason', o ->> 'reason', 'outlook_lane', o ->> 'lane',
                            'wait', r -> 'wait', 'decide_after', r -> 'decide_after');
end $fn$;

-- ======================================================================================================== manual route to partners
/* PART 6.3: the only way a B2C-held lead reaches a partner. Refusals (22023), in this order: a reason is required, test
   leads use the sandbox, partner_barred: ..., no_consent: ..., not_held: .... Then the hand-off is closed
   (routed_to_partners), the lead's allocation columns are cleared (the owner stays), lead.route_to_partners is logged
   and route_decide runs in the 'to_partners' context. */
create or replace function b2b.route_to_partners_core(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  v_bar jsonb;
  v_hold jsonb;
  v_cons jsonb;
begin
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then raise exception 'test leads use the sandbox' using errcode = '22023'; end if;
  v_bar := b2b.partner_bar(l);
  if v_bar is not null then
    raise exception 'partner_barred: partner-barred (%) since %: this lead can never be sent to partners',
      v_bar ->> 'reason', (v_bar ->> 'barred_at')::timestamptz::date using errcode = '22023';
  end if;
  v_cons := b2b.partner_consent(l);
  if not coalesce((v_cons ->> 'given')::boolean, false) then
    raise exception 'no_consent: the student has not consented to sharing with partners' using errcode = '22023';
  end if;
  v_hold := b2b.b2c_hold(l);
  if v_hold is null or not coalesce((v_hold ->> 'open')::boolean, false) or coalesce(v_hold ->> 'kind', '') not in ('selling', 'qualification_nurture') then
    raise exception 'not_held: only a lead held by B2C can be sent to partners' using errcode = '22023';
  end if;
  select * into a from b2b.allocations where id = (v_hold ->> 'allocation_id')::bigint for update;
  if a.id is null or a.status <> 'handed_off' then raise exception 'not_held: only a lead held by B2C can be sent to partners' using errcode = '22023'; end if;

  update b2b.allocations set status = 'closed', outcome = 'routed_to_partners', outcome_at = now(), updated_at = now() where id = a.id;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null, allocation_reason = null,
         updated_by = 'b2b' where id = l.id;
  perform b2b.log_event('lead.route_to_partners', l.id, a.id, null, jsonb_build_object('reason', left(trim(p_reason), 300), 'closed_allocation', a.reference));
  return b2b.route_decide(l.id, true, trim(p_reason), 'to_partners');
end $fn$;

/* POST /v1/leads/{id}/route-to-partners for the B2C CRM. A 22023 becomes 422 with error_code partner_barred | no_consent
   | not_held | invalid (the prefix of the message); P0002 is 404; a bad key 401. */
create or replace function b2b.api_route_to_partners(p_key text, p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare k jsonb; v jsonb;
begin
  k := b2b.api_key_check(p_key, 'events');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  perform set_config('b2b.actor', 'b2c_crm', true);
  begin
    v := b2b.route_to_partners_core(p_lead_id, p_reason);
  exception when sqlstate '22023' then
      return jsonb_build_object('ok', false, 'status', 422, 'error', sqlerrm,
        'error_code', case when sqlerrm like 'partner_barred:%' then 'partner_barred' when sqlerrm like 'no_consent:%' then 'no_consent'
                           when sqlerrm like 'not_held:%' then 'not_held' else 'invalid' end);
    when sqlstate 'P0002' then return jsonb_build_object('ok', false, 'status', 404, 'error', sqlerrm);
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'destination', v ->> 'destination', 'reference', v ->> 'reference', 'partner_id', (v ->> 'partner_id')::bigint,
    'b2c_lane', v ->> 'b2c_lane', 'reason', v ->> 'reason', 'outcome', v ->> 'outcome'));
end $fn$;

-- ======================================================================================================== reroute_after
/* After a duplicate, a rejection, a technical failure or a paused partner (m8b, m31c, m31i): clears the lead's columns
   (only while it still points at the allocation) and decides again in the 'cascade' context, which keeps the episode's
   origin (a manual route moves on to the next partner or fails into manual_route_failed, never into R5-R7). An error is
   logged (routing.error) and the sweep retries the lead whatever its age (lead_waits 'reroute_error'). */
create or replace function b2b.reroute_after(p_allocation_id bigint, p_why text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then return null; end if;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null,
         allocation_reason = null, stage = 'qualifying', updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  if not found then return null; end if;
  begin
    v := b2b.route_decide(a.lead_id, true, p_why, 'cascade');
  exception when others then
    perform b2b.log_event('routing.error', a.lead_id, a.id, a.partner_id,
                          jsonb_build_object('where', 'reroute_after', 'error', left(sqlerrm, 300), 'code', sqlstate, 'allocation_id', a.id));
    perform b2b.lead_wait_set(a.lead_id, now(), 'reroute_error');
    return jsonb_build_object('error', left(sqlerrm, 300), 'code', sqlstate);
  end;
  perform b2b.log_event('lead.rerouted', a.lead_id, a.id, a.partner_id, jsonb_build_object('why', p_why, 'destination', v ->> 'destination',
                        'reason', v ->> 'reason', 'partner_id', v ->> 'partner_id', 'reference', v ->> 'reference'));
  return v;
end $fn$;

-- ======================================================================================================== grants
-- replaced functions keep their grants (create or replace); the new ones are internal (service_role only)
revoke execute on function b2b.stage_score(jsonb, jsonb), b2b.offer_candidates(jsonb, boolean), b2b.route_outlook(public.student_leads)
  from public, anon, authenticated;
grant execute on function b2b.stage_score(jsonb, jsonb), b2b.offer_candidates(jsonb, boolean), b2b.route_outlook(public.student_leads)
  to service_role;
revoke execute on function b2b.route_decide(bigint, boolean, text, text), b2b.route_score(bigint, text, jsonb, numeric, boolean),
                           b2b.model_score(bigint, jsonb, numeric, boolean), b2b.rule_matches(jsonb, public.student_leads, jsonb),
                           b2b.cpe_net(bigint, bigint, jsonb), b2b.pool_lead(public.student_leads, boolean),
                           b2b.route_to_partners_core(bigint, text), b2b.reroute_after(bigint, text)
  from public, anon, authenticated;
grant execute on function b2b.route_decide(bigint, boolean, text, text), b2b.route_score(bigint, text, jsonb, numeric, boolean),
                          b2b.model_score(bigint, jsonb, numeric, boolean), b2b.rule_matches(jsonb, public.student_leads, jsonb),
                          b2b.cpe_net(bigint, bigint, jsonb), b2b.pool_lead(public.student_leads, boolean),
                          b2b.route_to_partners_core(bigint, text), b2b.reroute_after(bigint, text)
  to service_role;
revoke execute on function b2b.api_route_to_partners(text, bigint, text) from public;
grant execute on function b2b.api_route_to_partners(text, bigint, text) to anon, authenticated, service_role;
