-- M6c: routing administration: rules, commission rates, engine settings, the routing screen's reads, and the
-- pg_cron job that runs automatic routing (which does nothing while the 'routing' live switch is off).

-- ---------- rules ----------
create or replace function b2b.routing_rule_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_ids bigint[];
  v_cond jsonb := coalesce(p -> 'conditions', '{}');
  v_who text := coalesce(auth.uid()::text, 'system');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if p ->> 'action' not in ('fix_partner', 'narrow', 'exclude') then raise exception 'choose what the rule does' using errcode = '22023'; end if;
  if jsonb_typeof(v_cond) <> 'object' or exists (select 1 from jsonb_object_keys(v_cond) k
       where k not in ('sources', 'course_keys', 'states', 'modes', 'levels', 'university_ids', 'campaign_contains')) then
    raise exception 'unknown rule condition' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct x::bigint), '{}') into v_ids from jsonb_array_elements_text(coalesce(p -> 'partner_ids', '[]')) x;
  if cardinality(v_ids) = 0 then raise exception 'choose at least one partner' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_ids) i where not exists (select 1 from b2b.partners where id = i)) then
    raise exception 'unknown partner' using errcode = '22023';
  end if;

  if v_id is null then
    insert into b2b.routing_rules (name, priority, conditions, action, partner_ids, active, updated_by)
    values (left(trim(p ->> 'name'), 120), coalesce((p ->> 'priority')::int, 100), v_cond, p ->> 'action', v_ids, coalesce((p ->> 'active')::boolean, true), v_who)
    returning id into v_id;
    perform b2b.log_event('routing.rule_created', null, null, null, jsonb_build_object('rule_id', v_id, 'name', p ->> 'name'));
  else
    update b2b.routing_rules set name = left(trim(p ->> 'name'), 120), priority = coalesce((p ->> 'priority')::int, priority), conditions = v_cond,
           action = p ->> 'action', partner_ids = v_ids, active = coalesce((p ->> 'active')::boolean, active),
           version = version + 1, updated_at = now(), updated_by = v_who
     where id = v_id;
    if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
    perform b2b.log_event('routing.rule_updated', null, null, null, jsonb_build_object('rule_id', v_id, 'name', p ->> 'name'));
  end if;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function b2b.routing_rule_set_active(p_id bigint, p_active boolean)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.routing_rules set active = p_active, version = version + 1, updated_at = now(), updated_by = coalesce(auth.uid()::text, 'system') where id = p_id;
  if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
  perform b2b.log_event(case when p_active then 'routing.rule_enabled' else 'routing.rule_disabled' end, null, null, null, jsonb_build_object('rule_id', p_id));
end $$;

-- ---------- rates ----------
/* Adds a rate; an open rate for the same partner and programme ends the day before (rates are versioned, never edited). */
create or replace function b2b.rate_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_scope text := p ->> 'scope';
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_prog bigint := nullif(p ->> 'programme_id', '')::bigint;
  v_from date := coalesce(nullif(p ->> 'valid_from', '')::date, current_date);
  v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_scope not in ('partner', 'partner_programme') then raise exception 'rates are set per partner or per partner programme' using errcode = '22023'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_scope = 'partner_programme' and not exists (select 1 from public.catalog_programs where id = v_prog) then
    raise exception 'choose a catalogue programme' using errcode = '22023';
  end if;
  if p ->> 'rate_type' = 'percent' and not (nullif(p ->> 'value', '')::numeric > 0 and (p ->> 'value')::numeric <= 100) then
    raise exception 'a percentage must be above 0 and at most 100' using errcode = '22023';
  end if;
  if p ->> 'rate_type' = 'fixed' and not (nullif(p ->> 'value', '')::numeric > 0) then raise exception 'enter the amount' using errcode = '22023'; end if;
  if p ->> 'rate_type' = 'tiered' and jsonb_typeof(p -> 'tiers') <> 'array' then raise exception 'tiers must be a list' using errcode = '22023'; end if;

  update b2b.rates set valid_to = greatest(valid_from, v_from - 1)
   where valid_to is null and scope = v_scope and partner_id = v_partner and programme_id is not distinct from (case when v_scope = 'partner' then null else v_prog end);

  insert into b2b.rates (scope, partner_id, programme_id, rate_type, fee_base, value, tiers, gst_inclusive, valid_from, source, source_version_id, note, created_by)
  values (v_scope, v_partner, case when v_scope = 'partner' then null else v_prog end, p ->> 'rate_type', coalesce(nullif(p ->> 'fee_base', ''), 'first_year'),
          case when p ->> 'rate_type' = 'tiered' then null else (p ->> 'value')::numeric end,
          case when p ->> 'rate_type' = 'tiered' then p -> 'tiers' end,
          coalesce((p ->> 'gst_inclusive')::boolean, false), v_from, coalesce(nullif(p ->> 'source', ''), 'manual'),
          nullif(p ->> 'source_version_id', '')::bigint, nullif(left(trim(p ->> 'note'), 300), ''), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  perform b2b.log_event('rate.created', null, null, v_partner, jsonb_build_object('rate_id', v_id, 'scope', v_scope, 'programme_id', v_prog,
                        'rate_type', p ->> 'rate_type', 'value', p -> 'value', 'valid_from', v_from));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function b2b.rate_end(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.rates set valid_to = greatest(valid_from, current_date) where id = p_id and valid_to is null;
  if not found then raise exception 'rate not found or already ended' using errcode = 'P0002'; end if;
  perform b2b.log_event('rate.ended', null, null, (select partner_id from b2b.rates where id = p_id), jsonb_build_object('rate_id', p_id));
end $$;

/* Confirms the commission stated in a partner's published file as partner + programme rates (B5.2.2: proposed until confirmed). */
create or replace function b2b.rates_confirm_from_offers(p_partner_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  o record;
  r b2b.rates;
  v_created int := 0; v_same int := 0; v_tier int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  for o in select * from b2b.partner_programmes where partner_id = p_partner_id and valid_to is null and active and commission is not null loop
    if o.commission ->> 'type' not in ('percent', 'fixed') then v_tier := v_tier + 1; continue; end if;
    select * into r from b2b.rates where scope = 'partner_programme' and partner_id = p_partner_id and programme_id = o.programme_id and valid_to is null;
    if r.id is not null and r.rate_type = o.commission ->> 'type' and r.value = (o.commission ->> 'value')::numeric then v_same := v_same + 1; continue; end if;
    perform b2b.rate_save(jsonb_build_object('scope', 'partner_programme', 'partner_id', p_partner_id, 'programme_id', o.programme_id,
                                             'rate_type', o.commission ->> 'type', 'value', o.commission -> 'value', 'source', 'file',
                                             'source_version_id', o.source_version_id, 'note', 'Confirmed from the partner''s programme file'));
    v_created := v_created + 1;
  end loop;
  return jsonb_build_object('created', v_created, 'unchanged', v_same, 'tiers_skipped', v_tier);
end $$;

-- ---------- engine settings ----------
create or replace function b2b.engine_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not ((p ->> 'exploration_share')::numeric between 0 and 0.5) then raise exception 'exploration share must be between 0 and 50%%' using errcode = '22023'; end if;
  if p ->> 'cpe_aggregate' not in ('median', 'mean', 'max') then raise exception 'unknown commission aggregate' using errcode = '22023'; end if;
  if not ((p ->> 'min_learning_leads')::int between 1 and 1000) then raise exception 'learning leads must be 1 to 1000' using errcode = '22023'; end if;
  if not ((p ->> 'attempt_limit')::int between 1 and 5) or not ((p ->> 'partner_limit')::int between 1 and 5) then
    raise exception 'attempt and partner limits must be 1 to 5' using errcode = '22023';
  end if;
  if not ((p ->> 'witty_idle_minutes')::int between 5 and 1440) then raise exception 'Witty idle time must be 5 to 1440 minutes' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'require_partner_consent') <> 'boolean' then raise exception 'consent setting must be on or off' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'trusted_sources') <> 'array' then raise exception 'trusted sources must be a list' using errcode = '22023'; end if;
  v := v || jsonb_build_object(
         'exploration_share', round((p ->> 'exploration_share')::numeric, 3), 'cpe_aggregate', p ->> 'cpe_aggregate',
         'min_learning_leads', (p ->> 'min_learning_leads')::int, 'attempt_limit', (p ->> 'attempt_limit')::int,
         'partner_limit', (p ->> 'partner_limit')::int, 'witty_idle_minutes', (p ->> 'witty_idle_minutes')::int,
         'require_partner_consent', (p ->> 'require_partner_consent')::boolean,
         'trusted_sources', (select coalesce(jsonb_agg(distinct left(trim(x), 60)), '[]') from jsonb_array_elements_text(p -> 'trusted_sources') x where trim(x) <> ''));
  return b2b.set_setting('engine', v, p_reason);
end $$;

-- ---------- reads ----------
create or replace function b2b.decision_json(d b2b.engine_decisions)
returns jsonb language sql stable set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object(
    'lead_name', (select l.student_name from public.student_leads l where l.id = d.lead_id),
    'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
    'allocation', (select jsonb_build_object('id', a.id, 'reference', a.reference, 'status', a.status, 'cpe_net_inr', a.cpe_net_inr)
                     from b2b.allocations a where a.engine_decision_id = d.id limit 1));
$$;

create or replace function b2b.routing_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'switch', coalesce((select jsonb_build_object('live', s.live, 'reason', s.reason, 'switched_at', s.switched_at) from b2b.live_switches s where s.scope = 'routing'),
                       jsonb_build_object('live', false)),
    'engine', (select jsonb_build_object('value', s.value, 'version', s.version, 'updated_at', s.updated_at) from b2b.settings s where s.key = 'engine'),
    'live_partners', (select count(*) from b2b.partners p where p.status = 'active' and b2b.is_live('partner:' || p.id)),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
                                  'live', b2b.is_live('partner:' || p.id), 'test_endpoint', p.test_endpoint is not null,
                                  'offers', (select count(*) from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active),
                                  'proposed', (select count(*) from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active
                                                  and o.commission ->> 'type' in ('percent', 'fixed')
                                                  and not exists (select 1 from b2b.rates r where r.scope = 'partner_programme' and r.partner_id = p.id
                                                                    and r.programme_id = o.programme_id and r.valid_to is null
                                                                    and r.rate_type = o.commission ->> 'type' and r.value = (o.commission ->> 'value')::numeric)))
                                order by p.status = 'closed', coalesce(p.display_name, p.name)) from b2b.partners p), '[]'),
    'today', jsonb_build_object(
      'to_partners', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test),
      'to_b2c', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test),
      'tests', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.is_test),
      'b2c_reasons', coalesce((select jsonb_object_agg(reason, n) from (select a.reason, count(*) n from b2b.allocations a
                                where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test group by 1) x), '{}'),
      'errors', (select count(*) from b2b.events e where e.type = 'routing.error' and e.occurred_at >= v_today)),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) - 'candidates' - 'excluded' - 'rules' - 'interest' order by d.created_at desc)
                             from (select * from b2b.engine_decisions order by created_at desc limit 50) d), '[]'),
    'rules', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('partner_names',
                              (select jsonb_agg(coalesce(p.display_name, p.name)) from b2b.partners p where p.id = any (r.partner_ids)))
                            order by r.active desc, r.priority, r.id) from b2b.routing_rules r), '[]'),
    'rates', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object(
                              'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = r.partner_id),
                              'programme', b2b.programme_label(r.programme_id))
                            order by r.partner_id, r.programme_id nulls first, r.valid_from desc)
                         from b2b.rates r where r.valid_to is null or r.valid_to >= current_date - 90), '[]'));
end $$;

create or replace function b2b.routing_decision(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select b2b.decision_json(d) from b2b.engine_decisions d where d.id = p_id);
end $$;

/* For the lead drawer: readiness, interest, and the lead's decisions and allocations. */
create or replace function b2b.lead_routing(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.student_leads;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return null; end if;
  return jsonb_build_object(
    'readiness', b2b.lead_readiness(l), 'interest', b2b.lead_interest(l),
    'consent', l.consent_partner_share_at is not null, 'routing_live', b2b.is_live('routing'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) order by d.created_at desc) from b2b.engine_decisions d where d.lead_id = l.id), '[]'),
    'allocations', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id))
                                              order by a.created_at desc) from b2b.allocations a where a.lead_id = l.id), '[]'));
end $$;

revoke execute on function b2b.decision_json(b2b.engine_decisions) from public, anon, authenticated;
grant execute on function b2b.decision_json(b2b.engine_decisions) to service_role;
revoke execute on function b2b.routing_rule_save(jsonb), b2b.routing_rule_set_active(bigint, boolean), b2b.rate_save(jsonb), b2b.rate_end(bigint),
                           b2b.rates_confirm_from_offers(bigint), b2b.engine_settings_save(jsonb, text), b2b.routing_overview(),
                           b2b.routing_decision(bigint), b2b.lead_routing(bigint)
  from public, anon;
grant execute on function b2b.routing_rule_save(jsonb), b2b.routing_rule_set_active(bigint, boolean), b2b.rate_save(jsonb), b2b.rate_end(bigint),
                          b2b.rates_confirm_from_offers(bigint), b2b.engine_settings_save(jsonb, text), b2b.routing_overview(),
                          b2b.routing_decision(bigint), b2b.lead_routing(bigint)
  to authenticated, service_role;

-- ---------- automatic routing: every minute; a no-op until the 'routing' live switch is turned on ----------
select cron.schedule('b2b-route-ready-leads', '* * * * *', 'select b2b.route_ready_leads(50)');
