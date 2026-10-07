-- M24b: performance routing, part 2 (B7.1 step 6, B7.2, B7.3, B7.4, B7.8.1): the scorer.
-- route_score(lead, segment, eligible candidates, seed, is_test) runs after the rules, caps and contractual minimums, and:
--   1. draws the holdout (engine_policy.holdout_share, default 10%): holdout leads use the Admin's settings only, never an
--      AI optimiser change (pins, exploration, weights, caps or parameters whose source is 'ai');
--   2. applies the kill switch (engine.kill_switch, or the segment in engine_policy.kill_segments): a fixed split between
--      partners set by the Admin (engine.fixed_split), no scoring;
--   3. applies the segment's share cap (optional): a partner at or over the cap of the segment's leads in the last 7 days
--      is passed over while another candidate remains;
--   4. enriches every candidate with its statistics (exact segment when the partner has 30 or more leads in it, else the
--      course roll-up): P̂, alpha, beta, refund rate, SLA compliance, the optional speed and reliability factors and a
--      temporary partner weight, and NCPL = P̂ x CPE x (1 - refund) x factors;
--   5. picks the mode: a pin on the segment, else performance once 2 or more candidates each have min_matured_leads
--      matured leads in the segment, else commission first;
--   6. commission first: the highest CPE (ties: SLA compliance, then fewer leads this week), with the exploration lane
--      while a candidate is under-sampled (the draw is now seeded and reproducible);
--      performance: Thompson sampling, one Beta draw per candidate; the highest sampled NCPL wins. The selection
--      probability is estimated from mc_draws further seeded draws (default 200), so every decision can be replayed
--      and evaluated offline (inverse propensity).
-- Every random number comes from b2b.u01(seed, tag): replaying a decision from engine_decisions.seed gives the same choice.
-- route_decide (as in M17b) now calls it for commission-first decisions and logs mode, holdout, seed, policy version and
-- every candidate's numbers. Rule (fix_partner) and contractual-minimum decisions keep the highest CPE, unchanged.

/* Thompson sampling over scored candidates (each with partner_id, alpha, beta, cpe, refund_rate, speed, reliability, weight):
   draw i samples P from Beta(alpha, beta) per candidate and scores P x CPE x (1 - refund) x speed x reliability x weight;
   draw 0 decides (ties: candidate order, i.e. higher CPE, better SLA, fewer leads this week), draws 0..K count wins.
   Pure: the same candidates and seed always give the same answer (replay, offline evaluation). */
create or replace function b2b.thompson_pick(p_cands jsonb, p_seed text, p_k int)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  v_wins jsonb := '{}';
  v_best text;
  v_best_score double precision;
  v_score double precision;
  v_winner text;
  v_sampled double precision;
  i int;
  r record;
begin
  for i in 0 .. greatest(p_k, 0) loop
    v_best := null; v_best_score := null;
    for r in select c2 ->> 'partner_id' pid, coalesce((c2 ->> 'alpha')::double precision, 1) a, coalesce((c2 ->> 'beta')::double precision, 19) b,
                    coalesce((c2 ->> 'cpe')::double precision, 0) * (1 - coalesce((c2 ->> 'refund_rate')::double precision, 0))
                      * coalesce((c2 ->> 'speed')::double precision, 1) * coalesce((c2 ->> 'reliability')::double precision, 1)
                      * coalesce((c2 ->> 'weight')::double precision, 1) v
               from jsonb_array_elements(p_cands) c2
              order by (c2 ->> 'cpe')::numeric desc nulls last, (c2 ->> 'sla_compliance')::numeric desc nulls last,
                       (c2 ->> 'leads_week')::int, (c2 ->> 'partner_id')::bigint
    loop
      v_score := b2b.beta_sample(r.a, r.b, p_seed, 'ts:' || i || ':' || r.pid) * r.v;
      if v_best_score is null or v_score > v_best_score then v_best := r.pid; v_best_score := v_score; end if;
    end loop;
    if v_best is null then return jsonb_build_object('winner', null, 'wins', '{}'::jsonb, 'draws', 0); end if;
    if i = 0 then v_winner := v_best; v_sampled := v_best_score; end if;
    v_wins := jsonb_set(v_wins, array[v_best], to_jsonb(coalesce((v_wins ->> v_best)::int, 0) + 1));
  end loop;
  return jsonb_build_object('winner', v_winner, 'sampled_score', round(v_sampled::numeric, 6), 'wins', v_wins, 'draws', greatest(p_k, 0) + 1,
                            'selection_probability', round(greatest((v_wins ->> v_winner)::numeric / (greatest(p_k, 0) + 1), 0.0001), 4));
end $fn$;

/* Hook for the per-lead model (M25): given the scored candidates, returns
   {"deciding": version or null, "p": {partner_id: P(enrol)}, "shadow": {"version": v, "p": {...}} or null}.
   Until M25 there is no model: an empty object. */
create or replace function b2b.model_score(p_lead_id bigint, p_cands jsonb, p_seed numeric, p_holdout boolean)
returns jsonb language sql stable set search_path = '' as $fn$ select '{}'::jsonb $fn$;

create or replace function b2b.route_score(p_lead_id bigint, p_segment text, p_kept jsonb, p_seed numeric, p_is_test boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  v_pol_ver int := (select version from b2b.settings where key = 'engine_policy');
  v_seed text := p_seed::text;
  v_hold_share numeric := least(greatest(coalesce((pol ->> 'holdout_share')::numeric, 0.1), 0), 0.5);
  v_hold boolean;
  prm jsonb;
  seg jsonb;
  v_pin jsonb;
  v_share numeric;
  v_cap numeric;
  v_min_learn int := coalesce((e ->> 'min_learning_leads')::int, 30);
  v_k int := least(greatest(coalesce((pol ->> 'mc_draws')::int, 200), 20), 1000);
  v_kept jsonb := p_kept;
  v_capped jsonb := '[]';
  v_scored jsonb;
  v_mode text;        -- scoring mode: commission_first, performance, kill_switch
  v_alloc_mode text;  -- allocation mode: commission_first, exploration, performance, rule
  v_win jsonb;
  v_x jsonb;
  v_draw numeric;
  v_prob numeric := 1;
  v_why text;
  v_split jsonb;
  v_total numeric;
  v_acc numeric := 0;
  v_u numeric;
  v_wins jsonb := '{}';
  v_stats_at timestamptz;
  v_model jsonb := '{}';
  c jsonb;
begin
  -- 1. holdout
  v_hold := v_hold_share > 0 and b2b.u01(v_seed, 'holdout') < v_hold_share;
  prm := b2b.engine_params(v_hold);
  seg := coalesce(pol -> 'segments' -> p_segment, '{}');
  -- entries the AI set are ignored for holdout leads
  if v_hold then
    seg := (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(seg) x(k, v) where coalesce(v ->> 'source', 'admin') <> 'ai');
  end if;

  -- 2. kill switch: fixed split between partners (B2C is never part of it)
  if coalesce((e ->> 'kill_switch')::boolean, false) or coalesce(pol -> 'kill_segments', '[]') ? p_segment then
    select coalesce(jsonb_agg(c2 || jsonb_build_object('split_weight', (e -> 'fixed_split' ->> (c2 ->> 'partner_id'))::numeric) order by (c2 ->> 'partner_id')::bigint), '[]')
      into v_split from jsonb_array_elements(v_kept) c2
     where coalesce((e -> 'fixed_split' ->> (c2 ->> 'partner_id'))::numeric, 0) > 0;
    v_mode := 'kill_switch';
    if jsonb_array_length(v_split) > 0 then
      select sum((s ->> 'split_weight')::numeric) into v_total from jsonb_array_elements(v_split) s;
      v_u := b2b.u01(v_seed, 'split') * v_total;
      for c in select * from jsonb_array_elements(v_split) loop
        v_acc := v_acc + (c ->> 'split_weight')::numeric;
        if v_win is null and v_u < v_acc then v_win := c; end if;
      end loop;
      v_win := coalesce(v_win, v_split -> (jsonb_array_length(v_split) - 1));
      v_prob := (v_win ->> 'split_weight')::numeric / v_total;
      v_why := 'kill switch: fixed split';
    else
      -- no partner of the split is eligible: highest commission, no exploration
      select c2 into v_win from jsonb_array_elements(v_kept) c2
       order by (c2 ->> 'cpe')::numeric desc nulls last, (c2 ->> 'leads_week')::int, (c2 ->> 'partner_id')::bigint limit 1;
      v_why := 'kill switch: no partner of the fixed split is eligible; highest commission';
    end if;
    return jsonb_build_object('winner', v_win - 'split_weight', 'scoring_mode', v_mode, 'mode', 'rule', 'holdout', v_hold, 'draw', null,
                              'selection_probability', round(v_prob, 4), 'why', v_why, 'candidates', v_kept, 'capped', '[]'::jsonb,
                              'policy_version', v_pol_ver, 'exploration_share', 0, 'stats_at', null);
  end if;

  -- 3. share cap per segment (optional, 50 to 100%)
  v_cap := nullif(seg -> 'share_cap' ->> 'value', '')::numeric;
  if v_cap is not null and v_cap between 0.5 and 1 and jsonb_array_length(v_kept) > 1 then
    with wk as (select a.partner_id, count(*) n from b2b.allocations a
                 where a.segment = p_segment and a.destination_type = 'partner' and not a.is_test and a.status <> 'failed'
                   and a.created_at > now() - interval '7 days' group by 1),
         tot as (select sum(n) t from wk)
    select coalesce(jsonb_agg(c2) filter (where coalesce(wk.n, 0)::numeric / nullif(tot.t, 0) >= v_cap), '[]'),
           coalesce(jsonb_agg(c2) filter (where not (coalesce(wk.n, 0)::numeric / nullif(tot.t, 0) >= v_cap) or tot.t is null), '[]')
      into v_capped, v_x
      from jsonb_array_elements(v_kept) c2 cross join tot left join wk on wk.partner_id = (c2 ->> 'partner_id')::bigint;
    if jsonb_array_length(v_x) > 0 and jsonb_array_length(v_capped) > 0 then
      v_kept := v_x;
      v_capped := (select jsonb_agg(jsonb_build_object('partner_id', c2 ->> 'partner_id', 'name', c2 ->> 'name',
                                                       'why', format('at the segment''s share cap (%s%% of its leads this week)', round(v_cap * 100))))
                     from jsonb_array_elements(v_capped) c2);
    else
      v_capped := '[]';
    end if;
  end if;

  -- 4. statistics per candidate
  select coalesce(jsonb_agg(c2 || jsonb_build_object(
           'stats_segment', st.segment, 'stats_rollup', st.segment is not null and st.segment <> p_segment,
           'leads_in_segment', coalesce(ex.n_leads, 0), 'matured_in_segment', coalesce(ex.n_matured, 0),
           'p_hat', round(coalesce(st.p_hat, pr.prior), 5),
           'alpha', coalesce(st.alpha, round(pr.prior * (prm ->> 'prior_weight')::numeric, 4)),
           'beta', coalesce(st.beta, round((1 - pr.prior) * (prm ->> 'prior_weight')::numeric, 4)),
           'refund_rate', coalesce(st.refund_rate, ex.refund_rate, 0),
           'sla_compliance', coalesce(st.sla_compliance, ex.sla_compliance),
           'speed', case when (prm ->> 'speed_on')::boolean then coalesce(st.speed, 1) else 1 end,
           'reliability', case when (prm ->> 'reliability_on')::boolean then coalesce(st.reliability, 1) else 1 end,
           'weight', w.weight,
           'ncpl', round(coalesce((c2 ->> 'cpe')::numeric, 0) * coalesce(st.p_hat, pr.prior) * (1 - coalesce(st.refund_rate, ex.refund_rate, 0))
                         * case when (prm ->> 'speed_on')::boolean then coalesce(st.speed, 1) else 1 end
                         * case when (prm ->> 'reliability_on')::boolean then coalesce(st.reliability, 1) else 1 end * w.weight, 2))
           order by (c2 ->> 'partner_id')::bigint), '[]'),
         max(coalesce(st.refreshed_at, ex.refreshed_at))
    into v_scored, v_stats_at
    from jsonb_array_elements(v_kept) c2
    left join b2b.partner_segment_stats ex on ex.variant = prm ->> 'variant' and ex.partner_id = (c2 ->> 'partner_id')::bigint and ex.segment = p_segment
    left join b2b.partner_segment_stats ru on ru.variant = prm ->> 'variant' and ru.partner_id = (c2 ->> 'partner_id')::bigint
                                          and ru.segment = b2b.segment_rollup(p_segment) and b2b.segment_rollup(p_segment) <> p_segment
    cross join lateral (select case when coalesce(ex.n_leads, 0) >= 30 or ru.partner_id is null then ex else ru end st_row) pick
    cross join lateral (select (pick.st_row).segment, (pick.st_row).p_hat, (pick.st_row).alpha, (pick.st_row).beta, (pick.st_row).refund_rate,
                               (pick.st_row).sla_compliance, (pick.st_row).speed, (pick.st_row).reliability, (pick.st_row).refreshed_at) st
    cross join lateral (select coalesce((select s.prior from b2b.segment_stats s where s.variant = prm ->> 'variant' and s.segment = p_segment and s.n_matured > 0),
                                        (select s.prior from b2b.segment_stats s where s.variant = prm ->> 'variant' and s.segment = b2b.segment_rollup(p_segment) and s.n_matured > 0),
                                        (prm ->> 'default_p_enroll')::numeric) prior) pr
    cross join lateral (select coalesce(case when (pw ->> 'until') is null or (pw ->> 'until')::timestamptz > now()
                                             then least(greatest(coalesce((pw ->> 'weight')::numeric, 1), 0.9), 1.1) end, 1) weight
                          from (select case when v_hold and pol -> 'partner_weights' -> (c2 ->> 'partner_id') ->> 'source' = 'ai' then null
                                            else pol -> 'partner_weights' -> (c2 ->> 'partner_id') end pw) z) w;
  v_kept := v_scored;

  -- 4b. the per-lead model (M25): shadow scores are logged; a champion (or a challenger on its share of leads) replaces
  --     each candidate's P̂ in performance mode, keeping the candidate's uncertainty (alpha + beta). Never for holdout leads.
  v_model := coalesce(b2b.model_score(p_lead_id, v_kept, p_seed, v_hold), '{}');

  -- 5. mode
  v_pin := seg -> 'pin';
  if v_pin is not null and v_pin ->> 'mode' in ('commission_first', 'performance')
     and ((v_pin ->> 'until') is null or (v_pin ->> 'until')::timestamptz > now()) then
    v_mode := v_pin ->> 'mode';
  elsif (select count(*) from jsonb_array_elements(v_kept) c2 where (c2 ->> 'matured_in_segment')::int >= (prm ->> 'min_matured_leads')::int) >= 2 then
    v_mode := 'performance';
  else
    v_mode := 'commission_first';
  end if;

  -- 6a. commission first, with the exploration lane
  if v_mode = 'commission_first' or jsonb_array_length(v_kept) = 1 then
    v_alloc_mode := case when v_mode = 'performance' then 'performance' else 'commission_first' end;
    v_share := least(greatest(coalesce((seg -> 'exploration_share' ->> 'value')::numeric, (e ->> 'exploration_share')::numeric, 0.2), 0), 0.5);
    select c2 into v_win from jsonb_array_elements(v_kept) c2
     order by (c2 ->> 'cpe')::numeric desc nulls last, (c2 ->> 'sla_compliance')::numeric desc nulls last, (c2 ->> 'leads_week')::int, (c2 ->> 'partner_id')::bigint limit 1;
    if v_mode = 'commission_first' and v_share > 0 and jsonb_array_length(v_kept) > 1
       and exists (select 1 from jsonb_array_elements(v_kept) c2 where (c2 ->> 'segment_leads')::int < v_min_learn and c2 <> v_win) then
      select c2 into v_x from jsonb_array_elements(v_kept) c2 where (c2 ->> 'segment_leads')::int < v_min_learn and c2 <> v_win
       order by (c2 ->> 'cpe')::numeric desc nulls last, (c2 ->> 'sla_compliance')::numeric desc nulls last, (c2 ->> 'leads_week')::int, (c2 ->> 'partner_id')::bigint limit 1;
      v_draw := round(b2b.u01(v_seed, 'explore')::numeric, 6);
      if v_draw < v_share then
        v_prob := v_share; v_win := v_x; v_alloc_mode := 'exploration';
      else
        v_prob := 1 - v_share;
      end if;
    end if;
    return jsonb_build_object('winner', v_win, 'scoring_mode', v_mode, 'mode', v_alloc_mode, 'holdout', v_hold, 'draw', v_draw,
                              'selection_probability', round(v_prob, 4), 'why', null, 'candidates', v_kept, 'capped', v_capped,
                              'policy_version', v_pol_ver, 'exploration_share', v_share, 'stats_at', v_stats_at,
                              'pinned', v_pin is not null and v_pin ->> 'mode' = v_mode, 'model_version', null, 'shadow', v_model -> 'shadow');
  end if;

  -- 6b. performance: Thompson sampling; draw 0 decides, draws 0..K estimate the selection probability
  if v_model ->> 'deciding' is not null and not v_hold then
    v_kept := (select jsonb_agg(case when v_model -> 'p' ? (c2 ->> 'partner_id') then
                                  c2 || jsonb_build_object('p_model', (v_model -> 'p' ->> (c2 ->> 'partner_id'))::numeric,
                                    'alpha', round((v_model -> 'p' ->> (c2 ->> 'partner_id'))::numeric * ((c2 ->> 'alpha')::numeric + (c2 ->> 'beta')::numeric), 4),
                                    'beta', round((1 - (v_model -> 'p' ->> (c2 ->> 'partner_id'))::numeric) * ((c2 ->> 'alpha')::numeric + (c2 ->> 'beta')::numeric), 4),
                                    'ncpl', round(coalesce((c2 ->> 'cpe')::numeric, 0) * (v_model -> 'p' ->> (c2 ->> 'partner_id'))::numeric * (1 - (c2 ->> 'refund_rate')::numeric)
                                                  * (c2 ->> 'speed')::numeric * (c2 ->> 'reliability')::numeric * (c2 ->> 'weight')::numeric, 2))
                                  else c2 end order by (c2 ->> 'partner_id')::bigint)
                 from jsonb_array_elements(v_kept) c2);
  end if;
  v_x := b2b.thompson_pick(v_kept, v_seed, v_k);
  v_wins := v_x -> 'wins';
  v_draw := (v_x ->> 'sampled_score')::numeric;
  select c2 into v_win from jsonb_array_elements(v_kept) c2 where c2 ->> 'partner_id' = v_x ->> 'winner';
  v_prob := greatest((v_wins ->> (v_win ->> 'partner_id'))::numeric / (v_k + 1), 0.0001);
  v_kept := (select jsonb_agg(c2 || jsonb_build_object('win_share', round(coalesce((v_wins ->> (c2 ->> 'partner_id'))::numeric, 0) / (v_k + 1), 4))
                              order by (c2 ->> 'partner_id')::bigint)
               from jsonb_array_elements(v_kept) c2);
  select c2 into v_win from jsonb_array_elements(v_kept) c2 where c2 ->> 'partner_id' = v_win ->> 'partner_id';
  return jsonb_build_object('winner', v_win, 'scoring_mode', 'performance', 'mode', 'performance', 'holdout', v_hold, 'draw', null,
                            'sampled_score', v_draw, 'selection_probability', round(v_prob, 4), 'why', null, 'candidates', v_kept, 'capped', v_capped,
                            'policy_version', v_pol_ver, 'exploration_share', 0, 'stats_at', v_stats_at, 'mc_draws', v_k,
                            'pinned', v_pin is not null and v_pin ->> 'mode' = 'performance',
                            'model_version', case when not v_hold then v_model ->> 'deciding' end, 'shadow', v_model -> 'shadow');
end $fn$;

revoke execute on function b2b.route_score(bigint, text, jsonb, numeric, boolean), b2b.thompson_pick(jsonb, text, int), b2b.model_score(bigint, jsonb, numeric, boolean)
  from public, anon, authenticated;
grant execute on function b2b.route_score(bigint, text, jsonb, numeric, boolean), b2b.thompson_pick(jsonb, text, int), b2b.model_score(bigint, jsonb, numeric, boolean)
  to service_role;

/* route_decide as in M17b; step 4d now calls route_score, and the decision log records the seed, scoring mode, holdout,
   policy version, stats time and every candidate's numbers. */
create or replace function b2b.route_decide(p_lead_id bigint, p_commit boolean, p_note text, p_how text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_set_ver int := (select version from b2b.settings where key = 'engine');
  v_actor jsonb := b2b.actor();
  v_int jsonb;
  v_ready jsonb;
  v_test boolean;
  v_cycle int;
  v_prev bigint[];
  v_attempts int;
  v_tried int;
  v_share numeric := least(greatest(coalesce((e ->> 'exploration_share')::numeric, 0.2), 0), 0.5);
  v_min_learn int := coalesce((e ->> 'min_learning_leads')::int, 30);
  v_attempt_limit int := coalesce((e ->> 'attempt_limit')::int, 2);
  v_partner_limit int := coalesce((e ->> 'partner_limit')::int, 3);
  v_agg text := coalesce(e ->> 'cpe_aggregate', 'median');
  v_p_enroll numeric := coalesce((e ->> 'default_p_enroll')::numeric, 0.05);
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_month_frac numeric := extract(day from now() at time zone 'Asia/Kolkata')
                          / extract(day from (date_trunc('month', now() at time zone 'Asia/Kolkata') + interval '1 month - 1 day'));
  v_all jsonb := '[]';      -- every candidate partner with its numbers
  v_kept jsonb;             -- candidates still eligible
  v_excluded jsonb := '[]'; -- {partner_id, name, why}
  v_rules jsonb := '[]';
  v_reason text;
  v_mode text := 'commission_first';
  v_win jsonb;
  v_draw numeric;
  v_prob numeric := 1;
  v_dest text;
  v_dec_id bigint;
  v_alloc_id bigint;
  v_open_id bigint;
  r record;
  v_ids bigint[];
  v_match boolean;
  v_x jsonb;
  v_class jsonb;
  v_lane text;
  v_paid text;
  v_cause text;
  v_last_b2c b2b.allocations;
  v_manual_ctx boolean := p_how = 'to_partners';
  v_fp text;
  v_tried_list jsonb;
  v_none_left text;
  v_seed numeric := round(random()::numeric, 12);
  v_sc jsonb;
  v_hold boolean := false;
  v_smode text;
  v_why text;
  v_pol_ver int;
  v_stats_at timestamptz;
begin
  if p_how not in ('auto', 'pass', 'to_partners') then raise exception 'unknown routing request' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if p_commit then perform 1 from public.student_leads where id = p_lead_id for update; end if;

  v_cycle := coalesce(l.cycle_no, 1);
  v_ready := b2b.lead_readiness(l);
  v_test := (v_ready ->> 'is_test')::boolean;
  v_int := b2b.lead_interest(l);
  v_class := b2b.lead_class(l);

  select a.id into v_open_id from b2b.allocations a
   where a.lead_id = l.id and a.cycle_no = v_cycle and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off') limit 1;
  if p_commit and (v_open_id is not null or l.destination_type is not null) then
    raise exception 'this lead is already routed' using errcode = '22023';
  end if;
  if (l.deleted_at is not null or l.merged_into_id is not null) and p_commit then raise exception 'deleted or merged leads are not routed' using errcode = '22023'; end if;

  select coalesce(array_agg(a.partner_id) filter (where a.status in ('duplicate', 'rejected', 'failed', 'recalled')), '{}'),
         count(*) filter (where a.status in ('duplicate', 'rejected')),
         count(*) filter (where a.destination_type = 'partner')
    into v_prev, v_attempts, v_tried
    from b2b.allocations a where a.lead_id = l.id and a.cycle_no = v_cycle;

  -- E. junk and programme mismatch are not passed to any CRM (Addendum 2: checked before every other rule).
  --    'pass' (the Admin's rescue) and a manual route to partners skip it.
  if p_how = 'auto' and v_class ->> 'class' in ('junk', 'mismatch') then
    v_x := jsonb_build_object('lead_id', l.id, 'cycle_no', v_cycle, 'is_test', v_test, 'readiness', v_ready, 'interest', v_int,
             'destination', 'not_passed', 'reason', v_class ->> 'reason', 'mode', 'rule', 'b2c_lane', null, 'partner_id', null, 'partner_name', null,
             'cpe', null, 'has_rate', null, 'candidates', '[]'::jsonb, 'excluded', '[]'::jsonb, 'rules', '[]'::jsonb, 'draw', null,
             'exploration_share', v_share, 'selection_probability', 1, 'settings_version', v_set_ver,
             'already_routed', v_open_id is not null or l.destination_type is not null, 'committed', false);
    if not p_commit then return v_x; end if;
    v_fp := md5(concat_ws('|', upper(coalesce(l.lead_status, '')), coalesce(nullif(l.interested_course, ''), l.field_of_interest, ''), l.whatsapp_number));
    insert into b2b.not_passed (lead_id, reason, lead_status, requested_course, lead_source, fingerprint)
    values (l.id, v_class ->> 'reason', l.lead_status, coalesce(nullif(l.interested_course, ''), l.field_of_interest), l.lead_source, v_fp)
    on conflict (lead_id) do update
      set reason = excluded.reason, lead_status = excluded.lead_status, requested_course = excluded.requested_course,
          lead_source = excluded.lead_source, fingerprint = excluded.fingerprint, decided_at = now(),
          times = b2b.not_passed.times + 1, passed_at = null, passed_by = null, pass_note = null;
    perform b2b.log_event('lead.not_passed', l.id, null, null, jsonb_build_object('reason', v_class ->> 'reason', 'lead_status', l.lead_status));
    return v_x || jsonb_build_object('committed', true);
  end if;

  -- 0. once handed to B2C, a lead stays with B2C (every later cycle too) unless a manual route to partners moved it.
  select a.* into v_last_b2c from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'in_house'
   order by a.created_at desc, a.id desc limit 1;
  if v_last_b2c.id is not null and exists (select 1 from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner'
                                             and a.mode = 'manual' and a.created_at > v_last_b2c.created_at) then
    v_manual_ctx := true;
  end if;
  if not v_manual_ctx and v_last_b2c.id is not null then
    v_reason := 'b2c_held'; v_lane := coalesce(v_last_b2c.b2c_lane, 'sales');
  -- 0b. created by the B2C CRM
  elsif not v_manual_ctx and lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(coalesce(e -> 'b2c_sources', '["b2c_created","b2c_whatsapp"]')) x) then
    v_reason := 'b2c_created'; v_lane := 'sales';
  -- 0c. its import (or manual entry) chose B2C
  elsif not v_manual_ctx and p_how = 'auto' and exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.directive = 'b2c' and d.released_at is null) then
    v_reason := 'import_choice';
    v_lane := coalesce((select d.b2c_lane from b2b.intake_directives d where d.lead_id = l.id), 'sales');
  end if;
  -- 1. paid campaigns go to B2C sales, never to partners automatically
  if v_reason is null and not v_manual_ctx then
    v_paid := b2b.paid_signal(l);
    if v_paid is not null then v_reason := 'paid_campaign'; v_lane := 'sales'; end if;
  end if;
  -- 2. not qualified at its decision point: B2C nurture
  if v_reason is null and not v_manual_ctx and v_class ->> 'class' <> 'qualified' then
    v_reason := 'not_qualified'; v_lane := 'nurture';
  end if;
  -- 2b. rules that send a lead to B2C (Addendum 1: rules may name B2C), in priority order
  if v_reason is null and not v_manual_ctx then
    for r in select * from b2b.routing_rules where active and action = 'to_b2c' order by priority, id loop
      if b2b.rule_matches(r.conditions, l, v_int) then
        v_reason := 'rule'; v_lane := r.b2c_lane;
        v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', 'sent to B2C ' || r.b2c_lane);
        exit;
      end if;
    end loop;
  end if;

  -- 3. consent (test leads skip it so partner sandboxes can be tested before Witty sends consent)
  if v_reason is not null then
    null;
  elsif not v_test and coalesce((e ->> 'require_partner_consent')::boolean, true) and l.consent_partner_share_at is null then
    v_reason := 'no_partner_consent';
  elsif v_attempts >= v_attempt_limit then
    v_reason := 'duplicate_cascade';
  elsif v_tried >= v_partner_limit then
    v_reason := 'partners_unreachable';
  elsif v_int ->> 'course_key' is null then
    v_reason := 'no_partner_offers_programme';
  end if;

  -- when no partner is left: after a duplicate or rejection this enquiry, duplicate_cascade; after technical
  -- failures only, partners_unreachable; when nobody was tried yet, no_capacity (B7.6)
  v_none_left := case when v_attempts > 0 then 'duplicate_cascade' when v_tried > 0 then 'partners_unreachable' else 'no_capacity' end;

  -- 4. partner routing (B7). Candidates: partners whose published file offers a matching programme today
  if v_reason is null then
    with offers as (
      select o.partner_id, o.programme_id, b2b.cpe_net(o.partner_id, o.programme_id, o.fees) as cpe
        from b2b.partner_programmes o
        join public.catalog_programs c on c.id = o.programme_id and c.active
        join b2b.partners p on p.id = o.partner_id and p.status <> 'closed'
       where o.valid_to is null and o.active
         and (o.season_from is null or o.season_from <= current_date) and (o.season_to is null or o.season_to >= current_date)
         and c.course_key = v_int ->> 'course_key'
         and (v_int ->> 'level' is null or c.level = v_int ->> 'level')
         and (v_int ->> 'mode' is null or c.mode = v_int ->> 'mode')
         and (v_int ->> 'university_id' is null or c.university_id = (v_int ->> 'university_id')::bigint)
         and (v_int ->> 'specialization' is null
              or b2b.norm_key(c.specialization) = b2b.norm_key(v_int ->> 'specialization')
              or public.similarity(lower(c.specialization), lower(v_int ->> 'specialization')) >= 0.5)
         and case when v_test then p.test_endpoint is not null else b2b.is_live('partner:' || p.id) end
    ), per_partner as (
      select o.partner_id,
             count(*) as offers,
             (array_agg(o.programme_id order by o.cpe desc nulls last))[1:20] as programmes,
             case v_agg when 'mean' then avg(o.cpe) when 'max' then max(o.cpe)
                        else percentile_cont(0.5) within group (order by o.cpe) end as cpe
        from offers o group by o.partner_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'partner_id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
             'offers', pp.offers, 'programmes', to_jsonb(pp.programmes),
             'cpe', round(pp.cpe::numeric, 2), 'has_rate', pp.cpe is not null,
             'ncpl', round(coalesce(pp.cpe, 0)::numeric * v_p_enroll, 2),
             'daily_cap', p.daily_cap, 'monthly_cap', p.monthly_cap, 'contract_min_monthly', p.contract_min_monthly,
             'leads_today', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.created_at >= v_today and a.status <> 'failed'),
             'leads_month', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.created_at >= v_month and a.status <> 'failed'),
             'leads_week', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.created_at >= now() - interval '7 days' and a.status <> 'failed'),
             'segment_leads', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.segment = v_int ->> 'segment' and a.status <> 'failed'),
             'criteria', p.lead_criteria)
           order by p.id), '[]')
      into v_all
      from per_partner pp join b2b.partners p on p.id = pp.partner_id;

    if jsonb_array_length(v_all) = 0 then v_reason := 'no_partner_offers_programme'; end if;
  end if;

  -- 4a. exclusions: tried this cycle, not active, outside the partner's lead criteria
  if v_reason is null then
    select coalesce(jsonb_agg(jsonb_build_object('partner_id', c ->> 'partner_id', 'name', c ->> 'name', 'why', w.why)) filter (where w.why is not null), '[]'),
           coalesce(jsonb_agg(c) filter (where w.why is null), '[]')
      into v_excluded, v_kept
      from jsonb_array_elements(v_all) c
      cross join lateral (select case
        when (c ->> 'partner_id')::bigint = any (v_prev) then 'already tried for this enquiry'
        when not v_test and c ->> 'status' <> 'active' then 'partner is ' || (c ->> 'status')
        when jsonb_array_length(coalesce(c -> 'criteria' -> 'states_include', '[]')) > 0
             and not exists (select 1 from jsonb_array_elements_text(c -> 'criteria' -> 'states_include') s where lower(s) = lower(coalesce(l.state, '')))
          then 'outside the partner''s states'
        when exists (select 1 from jsonb_array_elements_text(coalesce(c -> 'criteria' -> 'states_exclude', '[]')) s where lower(s) = lower(coalesce(l.state, '')))
          then 'state excluded by the partner'
        when exists (select 1 from jsonb_array_elements_text(coalesce(c -> 'criteria' -> 'sources_exclude', '[]')) s where lower(s) = lower(coalesce(l.lead_source, '')))
          then 'source excluded by the partner'
      end as why) w;
  end if;

  -- 4b. partner routing rules, in priority order
  if v_reason is null then
    for r in select * from b2b.routing_rules where active and action <> 'to_b2c' order by priority, id loop
      v_match := b2b.rule_matches(r.conditions, l, v_int);
      continue when not v_match;

      select coalesce(array_agg((c ->> 'partner_id')::bigint), '{}') into v_ids
        from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (r.partner_ids);

      if r.action = 'exclude' then
        v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', c ->> 'partner_id', 'name', c ->> 'name', 'why', 'rule: ' || r.name))
                                                from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (v_ids)), '[]');
        v_kept := coalesce((select jsonb_agg(c) from jsonb_array_elements(v_kept) c where not (c ->> 'partner_id')::bigint = any (v_ids)), '[]');
        v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', format('%s excluded', cardinality(v_ids)));
      elsif cardinality(v_ids) = 0 then
        v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', 'skipped: none of its partners is eligible');
      else
        v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', c ->> 'partner_id', 'name', c ->> 'name', 'why', 'rule: ' || r.name))
                                                from jsonb_array_elements(v_kept) c where not (c ->> 'partner_id')::bigint = any (v_ids)), '[]');
        v_kept := (select jsonb_agg(c) from jsonb_array_elements(v_kept) c where (c ->> 'partner_id')::bigint = any (v_ids));
        v_rules := v_rules || jsonb_build_object('id', r.id, 'name', r.name, 'action', r.action, 'effect', format('%s kept', cardinality(v_ids)));
        if r.action = 'fix_partner' then v_mode := 'rule'; exit; end if;
      end if;
    end loop;
    if jsonb_array_length(v_kept) = 0 then v_reason := v_none_left; end if;
  end if;

  -- 4c. capacity, then contractual minimums behind schedule go first
  if v_reason is null then
    v_excluded := v_excluded || coalesce((select jsonb_agg(jsonb_build_object('partner_id', c ->> 'partner_id', 'name', c ->> 'name',
                                            'why', case when (c ->> 'leads_today')::int >= (c ->> 'daily_cap')::int then 'at its daily cap' else 'at its monthly cap' end))
                                          from jsonb_array_elements(v_kept) c
                                         where (c ->> 'leads_today')::int >= coalesce((c ->> 'daily_cap')::int, 2147483647)
                                            or (c ->> 'leads_month')::int >= coalesce((c ->> 'monthly_cap')::int, 2147483647)), '[]');
    v_kept := coalesce((select jsonb_agg(c) from jsonb_array_elements(v_kept) c
                         where (c ->> 'leads_today')::int < coalesce((c ->> 'daily_cap')::int, 2147483647)
                           and (c ->> 'leads_month')::int < coalesce((c ->> 'monthly_cap')::int, 2147483647)), '[]');
    if jsonb_array_length(v_kept) = 0 then
      v_reason := v_none_left;
    elsif v_mode <> 'rule' then
      v_x := (select jsonb_agg(c) from jsonb_array_elements(v_kept) c
               where coalesce((c ->> 'contract_min_monthly')::int, 0) > 0
                 and (c ->> 'leads_month')::int < (c ->> 'contract_min_monthly')::int * v_month_frac);
      if v_x is not null then v_kept := v_x; v_mode := 'minimum'; end if;
    end if;
  end if;

  -- 4d. score (M24, b2b.route_score): commission first with the seeded exploration lane, or performance mode (Thompson
  --     sampling on NCPL), with the holdout, kill switch, share cap and pins. A fix_partner rule or a contractual minimum
  --     keeps the highest CPE among its partners.
  if v_reason is null then
    if v_mode = 'commission_first' then
      v_sc := b2b.route_score(l.id, v_int ->> 'segment', v_kept, v_seed, v_test);
      v_win := v_sc -> 'winner';
      v_mode := v_sc ->> 'mode';
      v_smode := v_sc ->> 'scoring_mode';
      v_hold := (v_sc ->> 'holdout')::boolean;
      v_draw := (v_sc ->> 'draw')::numeric;
      v_prob := (v_sc ->> 'selection_probability')::numeric;
      v_share := coalesce((v_sc ->> 'exploration_share')::numeric, v_share);
      v_why := v_sc ->> 'why';
      v_pol_ver := (v_sc ->> 'policy_version')::int;
      v_stats_at := (v_sc ->> 'stats_at')::timestamptz;
      v_excluded := v_excluded || coalesce(v_sc -> 'capped', '[]');
      v_kept := v_sc -> 'candidates';
    else
      select c into v_win from jsonb_array_elements(v_kept) c
       order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
      v_smode := 'commission_first';
    end if;
    v_dest := 'partner';
    if v_manual_ctx then v_mode := 'manual'; end if;
  else
    v_dest := 'in_house';
    v_mode := case when v_reason in ('paid_campaign', 'b2c_created', 'rule', 'b2c_held', 'import_choice') then 'rule' else 'fallback' end;
    v_lane := coalesce(v_lane, 'sales');
    -- a manual route to partners that no partner can take goes back to B2C sales
    if v_manual_ctx and v_reason not in ('b2c_held') then v_cause := v_reason; v_reason := 'manual_route_failed'; v_lane := 'sales'; end if;
    v_win := null; v_prob := 1;
  end if;

  v_x := jsonb_build_object(
    'lead_id', l.id, 'cycle_no', v_cycle, 'is_test', v_test, 'readiness', v_ready, 'interest', v_int,
    'destination', v_dest, 'reason', v_reason, 'mode', v_mode, 'b2c_lane', v_lane, 'cause', v_cause, 'paid', v_paid,
    'class', v_class,
    'partner_id', (v_win ->> 'partner_id')::bigint, 'partner_name', v_win ->> 'name',
    'cpe', (v_win ->> 'cpe')::numeric, 'ncpl', (v_win ->> 'ncpl')::numeric, 'has_rate', (v_win ->> 'has_rate')::boolean,
    'candidates', (select coalesce(jsonb_agg(c - 'criteria'
                                             || coalesce((select k - 'criteria' from jsonb_array_elements(coalesce(v_kept, '[]')) k where k ->> 'partner_id' = c ->> 'partner_id' limit 1), '{}')
                                             || jsonb_build_object('eligible', exists (select 1 from jsonb_array_elements(coalesce(v_kept, '[]')) k where k ->> 'partner_id' = c ->> 'partner_id'))), '[]')
                     from jsonb_array_elements(v_all) c),
    'excluded', v_excluded, 'rules', v_rules, 'draw', v_draw, 'exploration_share', v_share,
    'selection_probability', round(v_prob, 4), 'settings_version', v_set_ver,
    'scoring_mode', v_smode, 'holdout', v_hold, 'seed', v_seed, 'policy_version', v_pol_ver, 'stats_at', v_stats_at, 'why', v_why,
    'pinned', coalesce((v_sc ->> 'pinned')::boolean, false), 'model_version', v_sc ->> 'model_version', 'sampled_score', (v_sc ->> 'sampled_score')::numeric, 'mc_draws', (v_sc ->> 'mc_draws')::int,
    'already_routed', v_open_id is not null or l.destination_type is not null, 'committed', false);

  if not p_commit then return v_x; end if;

  -- 7. commit
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, reason, candidates, excluded, rules,
                                    seed, selection_probability, settings_version, is_test, actor_type, actor_id, b2c_lane,
                                    scoring_mode, holdout, policy_version, stats_at, model_version, shadow)
  values (l.id, v_cycle, v_int ->> 'segment', v_int, v_mode, v_dest, (v_win ->> 'partner_id')::bigint,
          coalesce(v_reason, v_why, nullif(trim(p_note), '')),
          v_x -> 'candidates', v_excluded, v_rules, v_seed, round(v_prob, 4), v_set_ver, v_test, v_actor ->> 'type', v_actor ->> 'id', v_lane,
          v_smode, v_hold, v_pol_ver, v_stats_at, v_sc ->> 'model_version', v_sc -> 'shadow')
  returning id into v_dec_id;

  update b2b.not_passed set passed_at = now(), passed_by = v_actor ->> 'type',
         pass_note = case when p_how = 'pass' then left(p_note, 300) else 'classification changed' end
   where lead_id = l.id and passed_at is null;

  if v_reason = 'b2c_held' then
    -- no new allocation: B2C still holds the lead; tell it something new happened
    update public.student_leads set destination_type = 'in_house', partner_id = null, allocation_id = coalesce(allocation_id, v_last_b2c.id),
           allocated_at = coalesce(allocated_at, now()), allocation_reason = 'b2c_held', updated_by = 'b2b'
     where id = l.id;
    perform b2b.log_event('b2c.lead_reenquired', l.id, v_last_b2c.id, null,
                          jsonb_build_object('lead_id', l.id, 'decision_id', v_dec_id, 'b2c_lane', v_lane, 'cycle_no', v_cycle,
                                             'what', jsonb_build_object('lead_status', l.lead_status, 'source', l.lead_source, 'paid', b2b.paid_signal(l))));
    return v_x || jsonb_build_object('committed', true, 'decision_id', v_dec_id, 'allocation_id', v_last_b2c.id, 'reference', v_last_b2c.reference);
  end if;

  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, reason,
                               cpe_net_inr, ncpl_inr, selection_probability, engine_decision_id, is_test, b2c_lane, override)
  values (l.id, v_cycle, v_int ->> 'segment', v_dest, (v_win ->> 'partner_id')::bigint,
          case when v_dest = 'partner' then 'queued' else 'handed_off' end, v_mode, v_tried + 1, coalesce(v_reason, v_why),
          (v_win ->> 'cpe')::numeric, (v_win ->> 'ncpl')::numeric, round(v_prob, 4), v_dec_id, v_test,
          case when v_dest = 'in_house' then v_lane end, p_how = 'pass')
  returning id into v_alloc_id;
  update b2b.allocations set reference = 'EDW-' || v_alloc_id where id = v_alloc_id;

  -- B2B writes only the allocation columns; for a B2C hand-off the B2C CRM sets the next stage (Addendum 1 §3)
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
  update b2b.intake_directives set released_at = now(), released_by = coalesce(v_actor ->> 'id', v_actor ->> 'type')
   where lead_id = l.id and released_at is null;

  if v_dest = 'partner' then
    perform b2b.log_event('lead.routed', l.id, v_alloc_id, (v_win ->> 'partner_id')::bigint,
                          jsonb_build_object('decision_id', v_dec_id, 'mode', v_mode, 'reference', 'EDW-' || v_alloc_id, 'test', v_test,
                                             'manual_from_b2c', v_manual_ctx));
  else
    select coalesce(jsonb_agg(jsonb_build_object('partner_id', a.partner_id, 'status', a.status, 'outcome', a.outcome) order by a.created_at), '[]')
      into v_tried_list from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner';
    -- no student message from B2B: the B2C CRM messages the student from its own number (Addendum 1 §2)
    perform b2b.log_event('b2c.lead_handed_off', l.id, v_alloc_id, null,
                          jsonb_build_object('lead_id', l.id, 'b2c_lane', v_lane, 'reason', v_reason, 'cause', v_cause, 'decision_id', v_dec_id,
                                             'reference', 'EDW-' || v_alloc_id, 'partners_tried', v_tried_list, 'paid', v_paid, 'test', v_test));
  end if;

  return v_x || jsonb_build_object('committed', true, 'decision_id', v_dec_id, 'allocation_id', v_alloc_id, 'reference', 'EDW-' || v_alloc_id);
end $fn$;