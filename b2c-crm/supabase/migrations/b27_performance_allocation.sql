-- B2C CRM b27 (Phase 4): performance-weighted allocation (spec B7.3, "Mature teams (phase 4)"). Staging first.
--   perf_shares()    the maths: each counsellor's conversion over the rule's window (enrolments ÷ leads assigned), smoothed towards
--                    the team's rate while their sample is small, turned into shares of the turns that stay between a
--                    floor and a cap (by default half and twice an equal share), so nobody is starved or flooded
--   perf_weights()   each counsellor's record over the window (real leads only), through perf_shares()
--   decide()         the 'performance' logic (until now it behaved like weighted round robin) uses those shares; each
--                    decision records every counsellor's rate, weight and share in its eligible list
--   perf_preview()   the Lead Allocation page: the shares a performance rule would use now
-- Rule params: {"window_days": 30 | 90, "floor": 0.5, "cap": 2, "prior": 20, "min_leads": 20}

/* The maths alone: assigned and enrolled per person, the team's rate and the rule's params → each person's share and weight
   (weight 1 = an equal share). Shares follow the smoothed rate relative to the team, clamped to [floor, cap] × an equal
   share, with what the clamped ones give up or take shared out among the rest. */
create or replace function b2c.perf_shares(p_assigned int[], p_enrolled int[], p_team numeric, p_params jsonb) returns numeric[]
language plpgsql immutable set search_path = '' as $f$
declare
  v_floor numeric := least(greatest(coalesce((p_params ->> 'floor')::numeric, 0.5), 0), 1);
  v_cap numeric := greatest(coalesce((p_params ->> 'cap')::numeric, 2), 1);
  v_prior numeric := greatest(coalesce((p_params ->> 'prior')::numeric, 20), 0);
  v_min int := greatest(coalesce((p_params ->> 'min_leads')::int, 20), 0);
  n int := coalesce(cardinality(p_assigned), 0); raw numeric[]; share numeric[]; fixed boolean[]; i int; k int; v_left numeric; v_sum numeric; v_changed boolean;
begin
  if n = 0 then return '{}'; end if;
  raw := array_fill(1::numeric, array[n]);
  for i in 1 .. n loop
    if coalesce(p_team, 0) > 0 and p_assigned[i] >= v_min then
      raw[i] := greatest(((p_enrolled[i] + v_prior * p_team) / (p_assigned[i] + v_prior)) / p_team, 0.0001);
    end if;
  end loop;
  fixed := array_fill(false, array[n]); share := array_fill(0::numeric, array[n]);
  for k in 1 .. 20 loop
    v_left := 1; v_sum := 0;
    for i in 1 .. n loop if fixed[i] then v_left := v_left - share[i]; else v_sum := v_sum + raw[i]; end if; end loop;
    v_changed := false;
    for i in 1 .. n loop
      if not fixed[i] then
        share[i] := case when v_sum > 0 then raw[i] * v_left / v_sum else v_left / n end;
        if share[i] < v_floor / n then share[i] := v_floor / n; fixed[i] := true; v_changed := true;
        elsif share[i] > v_cap / n then share[i] := v_cap / n; fixed[i] := true; v_changed := true; end if;
      end if;
    end loop;
    exit when not v_changed;
  end loop;
  v_sum := 0; for i in 1 .. n loop v_sum := v_sum + share[i]; end loop;
  for i in 1 .. n loop share[i] := share[i] / v_sum; end loop;
  return share;
end $f$;

/* Each person's record over the rule's window (real leads only) and their share. */
create or replace function b2c.perf_weights(p_users uuid[], p_params jsonb, p_at timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare
  v_days int := least(greatest(coalesce((p_params ->> 'window_days')::int, 90), 7), 365);
  v_from timestamptz := p_at - make_interval(days => v_days);
  v_team_a numeric; v_team_e numeric; v_team numeric; n int;
  uid uuid[]; nm text[]; a int[]; e int[]; share numeric[]; i int; v_rows jsonb := '[]';
  v_min int := greatest(coalesce((p_params ->> 'min_leads')::int, 20), 0);
begin
  select count(distinct g.lead_id) into v_team_a from b2c.assignments g join b2c.users u on u.user_id = g.user_id and u.role in ('counsellor', 'sales_head')
    join b2c.leads_state s on s.lead_id = g.lead_id and not s.is_test where g.at >= v_from and g.at < p_at;
  select count(*) into v_team_e from b2c.enrollments en join b2c.users u on u.user_id = en.counsellor_id and u.role in ('counsellor', 'sales_head')
    join b2c.leads_state s on s.lead_id = en.lead_id and not s.is_test
   where en.status in ('reported', 'verified') and en.enrolled_on >= (v_from at time zone 'Asia/Kolkata')::date and en.enrolled_on <= (p_at at time zone 'Asia/Kolkata')::date;
  v_team := case when v_team_a > 0 then v_team_e / v_team_a else 0 end;
  select array_agg(x.user_id order by x.ord), array_agg(x.full_name order by x.ord), array_agg(x.a order by x.ord), array_agg(x.e order by x.ord) into uid, nm, a, e from (
    select p.user_id, p.ord, u.full_name,
           (select count(distinct g.lead_id) from b2c.assignments g join b2c.leads_state s on s.lead_id = g.lead_id and not s.is_test
             where g.user_id = p.user_id and g.at >= v_from and g.at < p_at)::int a,
           (select count(*) from b2c.enrollments en join b2c.leads_state s on s.lead_id = en.lead_id and not s.is_test
             where en.counsellor_id = p.user_id and en.status in ('reported', 'verified')
               and en.enrolled_on >= (v_from at time zone 'Asia/Kolkata')::date and en.enrolled_on <= (p_at at time zone 'Asia/Kolkata')::date)::int e
      from unnest(coalesce(p_users, '{}')) with ordinality p(user_id, ord) join b2c.users u on u.user_id = p.user_id) x;
  n := coalesce(cardinality(uid), 0);
  share := b2c.perf_shares(a, e, v_team, p_params);
  for i in 1 .. n loop
    v_rows := v_rows || jsonb_build_object('user_id', uid[i], 'name', nm[i], 'assigned', a[i], 'enrolled', e[i],
                          'rate', case when a[i] > 0 then round(e[i]::numeric / a[i], 4) end, 'new', a[i] < v_min,
                          'share', round(share[i], 4), 'weight', round(share[i] * n, 4));
  end loop;
  return jsonb_build_object('rows', v_rows, 'team_rate', round(v_team, 4), 'team_assigned', v_team_a, 'team_enrolled', v_team_e, 'window_days', v_days,
                            'floor', least(greatest(coalesce((p_params ->> 'floor')::numeric, 0.5), 0), 1), 'cap', greatest(coalesce((p_params ->> 'cap')::numeric, 2), 1),
                            'prior', greatest(coalesce((p_params ->> 'prior')::numeric, 20), 0), 'min_leads', v_min);
end $f$;

/* decide() as in b4, with the performance logic of B7.3. */
create or replace function b2c.decide(p_lead bigint, p_trigger text, p_at timestamptz default now(), p_exclude uuid default null, p_sim boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  f jsonb := b2c.lead_facts(p_lead, p_trigger, p_at);
  s b2c.leads_state; r b2c.allocation_rules; u b2c.users;
  v_hot boolean; v_why text; v_cands jsonb; v_skip jsonb; v_chosen uuid; v_turn int; v_n int; v_i int; v_fb text;
  v_ids uuid[]; v_ok uuid[]; v_match text[]; v_pool text; v_tried jsonb := '[]'::jsonb; v_perf jsonb;
begin
  if f is null then return jsonb_build_object('outcome', 'skipped', 'why', 'unknown lead'); end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_hot := coalesce(s.hot, false) or p_trigger in ('reengaged', 're_enquiry_hot');
  for r in select * from b2c.allocation_rules where enabled and applies_from <= p_at order by position, id loop
    continue when not b2c.rule_matches(r.condition, f);
    v_pool := coalesce((select p.name from b2c.pools p where p.id = r.pool_id), 'Everyone');
    -- the pool, in a stable order
    select array_agg(x.user_id order by x.pos, x.email) into v_ids from (
      select u2.user_id, coalesce(pm.position, 0) pos, u2.email from b2c.users u2
        left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = u2.user_id
       where (r.pool_id is null or pm.user_id is not null) and u2.user_id is distinct from p_exclude) x;
    v_cands := '[]'; v_skip := '[]'; v_ok := '{}';
    foreach v_chosen in array coalesce(v_ids, '{}') loop
      select * into u from b2c.users where user_id = v_chosen;
      v_why := b2c.ineligible(u, f, p_at, v_hot, p_sim);
      -- skill and territory logics narrow the pool
      if v_why is null and r.logic = 'skill_match' then
        v_match := array(select jsonb_array_elements_text(coalesce(r.params -> 'match', '["language"]')));
        if 'language' = any (v_match) and f ->> 'language' is not null and not exists (select 1 from unnest(u.languages) g where lower(g) = lower(f ->> 'language')) then v_why := 'language'; end if;
        if v_why is null and 'programme' = any (v_match) and f ->> 'course' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'programmes', '[]')) g where lower(f ->> 'course') like '%' || lower(g) || '%') then v_why := 'programme skill'; end if;
        if v_why is null and 'university' = any (v_match) and f ->> 'university' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'universities', '[]')) g where lower(g) = lower(f ->> 'university')) then v_why := 'university skill'; end if;
        if v_why is null and 'level' = any (v_match) and f ->> 'level' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'levels', '[]')) g where lower(g) = lower(f ->> 'level')) then v_why := 'level skill'; end if;
      elsif v_why is null and r.logic = 'territory' then
        if not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'territories', '[]')) g where lower(g) in (lower(f ->> 'city'), lower(f ->> 'state'))) then v_why := 'territory'; end if;
      end if;
      if v_why is null then v_ok := v_ok || v_chosen; v_cands := v_cands || jsonb_build_object('user_id', v_chosen, 'name', u.full_name);
      else v_skip := v_skip || jsonb_build_object('user_id', v_chosen, 'name', u.full_name, 'why', v_why); end if;
    end loop;

    v_chosen := null; v_turn := null;
    if r.logic = 'manual' then
      return jsonb_build_object('outcome', 'manual_queue', 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'manual queue');
    elsif r.logic = 'returning' then
      if coalesce(s.previous_owner_id, s.lost_by_user) = any (v_ok) then v_chosen := coalesce(s.previous_owner_id, s.lost_by_user); end if;
      if v_chosen is null then v_tried := v_tried || jsonb_build_object('rule', r.name, 'why', 'previous counsellor not eligible'); continue; end if;
    elsif cardinality(v_ok) > 0 then
      if r.logic in ('round_robin', 'pinning', 'skill_match', 'territory') then
        v_turn := r.turn;
        if p_sim then
          execute 'select turn from pg_temp.sim_turns where rule_id = $1' into v_turn using r.id;
          v_turn := coalesce(v_turn, r.turn);
        end if;
        v_n := cardinality(v_ids);
        for v_i in 1 .. v_n loop
          if v_ids[((v_turn + v_i) % v_n) + 1] = any (v_ok) then v_chosen := v_ids[((v_turn + v_i) % v_n) + 1]; v_turn := (v_turn + v_i) % v_n; exit; end if;
        end loop;
      elsif r.logic = 'performance' then
        -- B7.3 performance-weighted: each eligible counsellor's share of turns follows their conversion (b2c.perf_weights),
        -- within the floor and cap; the next lead goes to whoever is furthest below their share this month
        v_perf := b2c.perf_weights(v_ok, r.params, p_at);
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce((w.e ->> 'weight')::numeric, 1), 0.01) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join lateral (select e from jsonb_array_elements(v_perf -> 'rows') e where (e ->> 'user_id')::uuid = c.uid) w on true) x
         order by x.score, x.email limit 1;
        select coalesce(jsonb_agg(c || coalesce((select e - 'user_id' - 'name' from jsonb_array_elements(v_perf -> 'rows') e where e ->> 'user_id' = c ->> 'user_id'), '{}')), '[]')
          into v_cands from jsonb_array_elements(v_cands) c;
      elsif r.logic = 'weighted_round_robin' then
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce(pm.weight, uu.weight, 1), 1) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = c.uid) x
         order by x.score, x.email limit 1;
      elsif r.logic = 'least_loaded' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> case when p_sim then 'month' else 'open' end)::int n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      elsif r.logic = 'capacity' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(uu.monthly_cap, 1) n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      end if;
    end if;

    if v_chosen is not null then
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'turn', v_turn, 'hot', v_hot, 'facts', f, 'tried', v_tried)
             || case when v_perf is not null then jsonb_build_object('performance', v_perf - 'rows',
                       'why', format('performance over %s days: team conversion %s%%, shares kept between %s and %s of an equal share',
                                     v_perf ->> 'window_days', round((v_perf ->> 'team_rate')::numeric * 100, 1), v_perf ->> 'floor', v_perf ->> 'cap')) else '{}'::jsonb end;
    end if;
    -- nobody eligible under this rule: its fallbacks, in order
    v_tried := v_tried || jsonb_build_object('rule', r.name, 'skipped', v_skip);
    for v_fb in select jsonb_array_elements_text(r.fallbacks) loop
      if v_fb = 'next_rule' then exit;
      elsif v_fb = 'on_call' then
        select uu.user_id into v_chosen from b2c.users uu
         where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
           and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
           and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
         order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'on-call fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'admin' then
        select uu.user_id into v_chosen from b2c.users uu where uu.role = 'admin' and uu.is_active and uu.takes_leads and uu.user_id is distinct from p_exclude order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'admin',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'Admin fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'unassigned' then
        return b2c.decide_none(f, v_hot, v_tried, r, v_pool, v_cands, v_skip, p_exclude, p_at);
      end if;
    end loop;
  end loop;
  return b2c.decide_none(f, v_hot, v_tried, null, null, '[]', '[]', p_exclude, p_at);
end $f$;

create or replace function b2c.perf_preview(p_rule bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare r b2c.allocation_rules; v_ids uuid[];
begin
  perform b2c.require('settings');
  select * into r from b2c.allocation_rules where id = p_rule;
  if r.id is null then raise exception 'unknown rule'; end if;
  select array_agg(u.user_id order by u.email) into v_ids from b2c.users u
    left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = u.user_id
   where u.is_active and u.takes_leads and not u.is_test_user and u.role in ('counsellor', 'sales_head', 'admin') and (r.pool_id is null or pm.user_id is not null);
  return b2c.perf_weights(coalesce(v_ids, '{}'), r.params, now()) || jsonb_build_object('rule', r.name, 'logic', r.logic);
end $f$;

grant execute on function b2c.perf_preview(bigint) to authenticated;
revoke execute on function b2c.perf_weights(uuid[], jsonb, timestamptz), b2c.perf_shares(integer[], integer[], numeric, jsonb) from public, authenticated;
revoke execute on all functions in schema b2c from public, anon;
