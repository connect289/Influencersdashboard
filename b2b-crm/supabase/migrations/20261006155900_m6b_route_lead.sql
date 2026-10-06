-- M6b: the routing engine (spec B7.1–B7.6, commission-first; performance mode and the ML model are Phase 3).
-- b2b.route_core runs every step for one lead and either returns the decision (simulation) or commits it in one
-- transaction: engine_decisions, allocations (EDW-<id>), the lead's B2B columns and an event.

create or replace function b2b.route_core(p_lead_id bigint, p_commit boolean, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
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
begin
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if p_commit then perform 1 from public.student_leads where id = p_lead_id for update; end if;

  v_cycle := coalesce(l.cycle_no, 1);
  v_ready := b2b.lead_readiness(l);
  v_test := (v_ready ->> 'is_test')::boolean;
  v_int := b2b.lead_interest(l);

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

  -- 1. consent (test leads skip it so partner sandboxes can be tested before Witty sends consent)
  if not v_test and coalesce((e ->> 'require_partner_consent')::boolean, true) and l.consent_partner_share_at is null then
    v_reason := 'no_partner_consent';
  elsif v_attempts >= v_attempt_limit then
    v_reason := 'duplicate_cascade';
  elsif v_tried >= v_partner_limit then
    v_reason := 'partners_unreachable';
  elsif v_int ->> 'course_key' is null then
    v_reason := 'no_partner_offers_programme';
  end if;

  -- 2. candidates: partners whose published file offers a matching programme today
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

  -- 3. exclusions: tried this cycle, not active, outside the partner's lead criteria
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

  -- 4. routing rules, in priority order
  if v_reason is null then
    for r in select * from b2b.routing_rules where active order by priority, id loop
      v_match :=
            (jsonb_array_length(coalesce(r.conditions -> 'sources', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'sources') s where lower(s) = lower(coalesce(l.lead_source, ''))))
        and (jsonb_array_length(coalesce(r.conditions -> 'course_keys', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'course_keys') s where s = v_int ->> 'course_key'))
        and (jsonb_array_length(coalesce(r.conditions -> 'states', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'states') s where lower(s) = lower(coalesce(l.state, ''))))
        and (jsonb_array_length(coalesce(r.conditions -> 'modes', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'modes') s where s = v_int ->> 'mode'))
        and (jsonb_array_length(coalesce(r.conditions -> 'levels', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'levels') s where s = v_int ->> 'level'))
        and (jsonb_array_length(coalesce(r.conditions -> 'university_ids', '[]')) = 0 or exists (select 1 from jsonb_array_elements_text(r.conditions -> 'university_ids') s where s = v_int ->> 'university_id'))
        and (coalesce(r.conditions ->> 'campaign_contains', '') = '' or coalesce(l.campaign, '') ilike '%' || replace(replace(replace(r.conditions ->> 'campaign_contains', '\', '\\'), '%', '\%'), '_', '\_') || '%');
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
    if jsonb_array_length(v_kept) = 0 then v_reason := 'no_capacity'; end if;
  end if;

  -- 5. capacity, then contractual minimums behind schedule go first
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
      v_reason := 'no_capacity';
    elsif v_mode <> 'rule' then
      v_x := (select jsonb_agg(c) from jsonb_array_elements(v_kept) c
               where coalesce((c ->> 'contract_min_monthly')::int, 0) > 0
                 and (c ->> 'leads_month')::int < (c ->> 'contract_min_monthly')::int * v_month_frac);
      if v_x is not null then v_kept := v_x; v_mode := 'minimum'; end if;
    end if;
  end if;

  -- 6. score: highest CPE net; exploration lane while a candidate is under-sampled in the segment
  if v_reason is null then
    select c into v_win from jsonb_array_elements(v_kept) c
     order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
    if v_mode = 'commission_first' and v_share > 0 and jsonb_array_length(v_kept) > 1
       and exists (select 1 from jsonb_array_elements(v_kept) c where (c ->> 'segment_leads')::int < v_min_learn) then
      select c into v_x from jsonb_array_elements(v_kept) c where (c ->> 'segment_leads')::int < v_min_learn
       order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
      v_draw := round(random()::numeric, 6);
      if v_draw < v_share then
        v_prob := v_share + case when v_x = v_win then 1 - v_share else 0 end;
        v_win := v_x;
        if v_win <> (select c from jsonb_array_elements(v_kept) c order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1) then
          v_mode := 'exploration';
        end if;
      else
        v_prob := 1 - v_share + case when v_x = v_win then v_share else 0 end;
      end if;
    end if;
    v_dest := 'partner';
  else
    v_dest := 'in_house';
    v_mode := 'fallback';
  end if;

  v_x := jsonb_build_object(
    'lead_id', l.id, 'cycle_no', v_cycle, 'is_test', v_test, 'readiness', v_ready, 'interest', v_int,
    'destination', v_dest, 'reason', v_reason, 'mode', v_mode,
    'partner_id', (v_win ->> 'partner_id')::bigint, 'partner_name', v_win ->> 'name',
    'cpe', (v_win ->> 'cpe')::numeric, 'ncpl', (v_win ->> 'ncpl')::numeric, 'has_rate', (v_win ->> 'has_rate')::boolean,
    'candidates', (select coalesce(jsonb_agg(c - 'criteria' || jsonb_build_object('eligible', exists (select 1 from jsonb_array_elements(coalesce(v_kept, '[]')) k where k ->> 'partner_id' = c ->> 'partner_id'))), '[]')
                     from jsonb_array_elements(v_all) c),
    'excluded', v_excluded, 'rules', v_rules, 'draw', v_draw, 'exploration_share', v_share,
    'selection_probability', round(v_prob, 4), 'settings_version', v_set_ver,
    'already_routed', v_open_id is not null or l.destination_type is not null, 'committed', false);

  if not p_commit then return v_x; end if;

  -- 7. commit
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, reason, candidates, excluded, rules,
                                    seed, selection_probability, settings_version, is_test, actor_type, actor_id)
  values (l.id, v_cycle, v_int ->> 'segment', v_int, v_mode, v_dest, (v_win ->> 'partner_id')::bigint, coalesce(v_reason, nullif(trim(p_note), '')),
          v_x -> 'candidates', v_excluded, v_rules, v_draw, round(v_prob, 4), v_set_ver, v_test, v_actor ->> 'type', v_actor ->> 'id')
  returning id into v_dec_id;

  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, reason,
                               cpe_net_inr, ncpl_inr, selection_probability, engine_decision_id, is_test)
  values (l.id, v_cycle, v_int ->> 'segment', v_dest, (v_win ->> 'partner_id')::bigint,
          case when v_dest = 'partner' then 'queued' else 'handed_off' end, v_mode, v_tried + 1, v_reason,
          (v_win ->> 'cpe')::numeric, (v_win ->> 'ncpl')::numeric, round(v_prob, 4), v_dec_id, v_test)
  returning id into v_alloc_id;
  update b2b.allocations set reference = 'EDW-' || v_alloc_id where id = v_alloc_id;

  update public.student_leads
     set destination_type = v_dest,
         partner_id = (v_win ->> 'partner_id')::bigint,
         allocation_id = v_alloc_id,
         allocated_at = now(),
         allocation_reason = coalesce(v_reason, v_mode),
         stage = case when v_dest = 'partner' then 'allocated' else stage end,
         updated_by = 'b2b'
   where id = l.id;

  perform b2b.log_event(case when v_dest = 'partner' then 'lead.routed' else 'lead.handed_to_b2c' end, l.id, v_alloc_id, (v_win ->> 'partner_id')::bigint,
                        jsonb_build_object('decision_id', v_dec_id, 'mode', v_mode, 'reason', v_reason, 'reference', 'EDW-' || v_alloc_id, 'test', v_test));

  return v_x || jsonb_build_object('committed', true, 'decision_id', v_dec_id, 'allocation_id', v_alloc_id, 'reference', 'EDW-' || v_alloc_id);
end $$;

/* What the engine would do with a lead, without writing anything. */
create or replace function b2b.route_simulate(p_lead_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.route_core(p_lead_id, false);
end $$;

/* Routes one lead now, by the Admin (works while automatic routing is off; real leads still need live partners). */
create or replace function b2b.route_now(p_lead_id bigint, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.route_core(p_lead_id, true, p_note);
end $$;

/*
 * Automatic routing, run by pg_cron every minute. Does nothing unless the 'routing' live switch is on, the engine is
 * enabled and the kill switch is off. Routes ready, unrouted, non-test leads; one failure never stops the others.
 */
create or replace function b2b.route_ready_leads(p_limit int default 50)
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  r record;
  n int := 0;
begin
  if not b2b.is_live('routing') or not coalesce((e ->> 'enabled')::boolean, true) or coalesce((e ->> 'kill_switch')::boolean, false) then
    return 0;
  end if;
  perform set_config('b2b.actor', 'engine', true);
  for r in
    select l.id from public.student_leads l
     where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
       and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
       and l.created_at > now() - interval '90 days'
     order by l.created_at
     limit 500
  loop
    exit when n >= least(greatest(p_limit, 1), 200);
    begin
      if (b2b.lead_readiness((select x from public.student_leads x where x.id = r.id)) ->> 'ready')::boolean then
        perform b2b.route_core(r.id, true);
        n := n + 1;
      end if;
    exception when others then
      perform b2b.log_event('routing.error', r.id, null, null, jsonb_build_object('error', left(sqlerrm, 300), 'code', sqlstate));
    end;
  end loop;
  return n;
end $$;

revoke execute on function b2b.route_core(bigint, boolean, text), b2b.route_ready_leads(int) from public, anon, authenticated;
grant execute on function b2b.route_core(bigint, boolean, text), b2b.route_ready_leads(int) to service_role;
revoke execute on function b2b.route_simulate(bigint), b2b.route_now(bigint, text) from public, anon;
grant execute on function b2b.route_simulate(bigint), b2b.route_now(bigint, text) to authenticated, service_role;
