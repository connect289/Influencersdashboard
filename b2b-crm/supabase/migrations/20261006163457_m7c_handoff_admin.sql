-- M7c: Admin actions for Addenda 1 and 2: rules that send to B2C, hand-off settings, Pass to CRM (one or many),
-- manual route of a B2C-held lead to partners, partner-lost hand-off to B2C nurture, and the review queue.

create or replace function b2b.can_route() returns boolean language sql stable set search_path = '' as $$
  select b2b.is_admin() or coalesce((select auth.role()), '') = 'service_role';
$$;

-- ---------- rules: fix_partner | narrow | exclude (partners) or to_b2c (a lane) ----------
create or replace function b2b.routing_rule_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_ids bigint[];
  v_cond jsonb := coalesce(p -> 'conditions', '{}');
  v_who text := coalesce(auth.uid()::text, 'system');
  v_lane text := case when p ->> 'action' = 'to_b2c' then p ->> 'b2c_lane' end;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if p ->> 'action' not in ('fix_partner', 'narrow', 'exclude', 'to_b2c') then raise exception 'choose what the rule does' using errcode = '22023'; end if;
  if jsonb_typeof(v_cond) <> 'object' or exists (select 1 from jsonb_object_keys(v_cond) k
       where k not in ('sources', 'course_keys', 'states', 'modes', 'levels', 'university_ids', 'campaign_contains')) then
    raise exception 'unknown rule condition' using errcode = '22023';
  end if;
  if p ->> 'action' = 'to_b2c' then
    if v_lane is null or v_lane not in ('sales', 'nurture') then raise exception 'choose the B2C lane: sales or nurture' using errcode = '22023'; end if;
    v_ids := '{}';
  else
    select coalesce(array_agg(distinct x::bigint), '{}') into v_ids from jsonb_array_elements_text(coalesce(p -> 'partner_ids', '[]')) x;
    if cardinality(v_ids) = 0 then raise exception 'choose at least one partner' using errcode = '22023'; end if;
    if exists (select 1 from unnest(v_ids) i where not exists (select 1 from b2b.partners where id = i)) then
      raise exception 'unknown partner' using errcode = '22023';
    end if;
  end if;

  if v_id is null then
    insert into b2b.routing_rules (name, priority, conditions, action, partner_ids, b2c_lane, active, updated_by)
    values (left(trim(p ->> 'name'), 120), coalesce((p ->> 'priority')::int, 100), v_cond, p ->> 'action', v_ids, v_lane, coalesce((p ->> 'active')::boolean, true), v_who)
    returning id into v_id;
    perform b2b.log_event('routing.rule_created', null, null, null, jsonb_build_object('rule_id', v_id, 'name', p ->> 'name'));
  else
    update b2b.routing_rules set name = left(trim(p ->> 'name'), 120), priority = coalesce((p ->> 'priority')::int, priority), conditions = v_cond,
           action = p ->> 'action', partner_ids = v_ids, b2c_lane = v_lane, active = coalesce((p ->> 'active')::boolean, active),
           version = version + 1, updated_at = now(), updated_by = v_who
     where id = v_id;
    if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
    perform b2b.log_event('routing.rule_updated', null, null, null, jsonb_build_object('rule_id', v_id, 'name', p ->> 'name'));
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- ---------- hand-off settings: the paid-campaign rule, B2C-created sources, blocked phones ----------
create or replace function b2b.handoff_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  k text;
  clean jsonb;
  rule jsonb := '{}';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  foreach k in array array['sources', 'click_ids', 'utm_mediums', 'include_campaigns', 'exclude_campaigns'] loop
    if jsonb_typeof(p -> 'paid_rule' -> k) <> 'array' then raise exception 'paid rule: % must be a list', k using errcode = '22023'; end if;
    select coalesce(jsonb_agg(distinct left(trim(x), 100)), '[]') into clean from jsonb_array_elements_text(p -> 'paid_rule' -> k) x where trim(x) <> '';
    if jsonb_array_length(clean) > 100 then raise exception 'paid rule: at most 100 entries per list' using errcode = '22023'; end if;
    rule := rule || jsonb_build_object(k, clean);
  end loop;
  if jsonb_typeof(p -> 'b2c_sources') <> 'array' or jsonb_typeof(p -> 'blocked_phones') <> 'array' then
    raise exception 'B2C sources and blocked phones must be lists' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements_text(p -> 'blocked_phones') x where length(regexp_replace(x, '\D', '', 'g')) not between 10 and 15) then
    raise exception 'each blocked phone needs 10 to 15 digits' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'junk_capi_signal') <> 'boolean' then raise exception 'the junk signal setting must be on or off' using errcode = '22023'; end if;
  v := v || jsonb_build_object(
         'paid_rule', rule,
         'b2c_sources', (select coalesce(jsonb_agg(distinct lower(left(trim(x), 60))), '[]') from jsonb_array_elements_text(p -> 'b2c_sources') x where trim(x) <> ''),
         'blocked_phones', (select coalesce(jsonb_agg(distinct regexp_replace(x, '\D', '', 'g')), '[]') from jsonb_array_elements_text(p -> 'blocked_phones') x),
         'junk_capi_signal', (p ->> 'junk_capi_signal')::boolean,
         'b2c_sends_own_notification', true);
  return b2b.set_setting('engine', v, p_reason);
end $$;

-- ---------- Pass to CRM: rescue not-passed leads (one, or a group), through the normal rules ----------
create or replace function b2b.pass_to_crm(p_lead_ids bigint[], p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id bigint;
  v_out jsonb := '[]';
  v_res jsonb;
  n int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if cardinality(p_lead_ids) is null or cardinality(p_lead_ids) = 0 or cardinality(p_lead_ids) > 500 then
    raise exception 'choose 1 to 500 leads' using errcode = '22023';
  end if;
  foreach v_id in array (select array_agg(distinct x) from unnest(p_lead_ids) x) loop
    begin
      if not exists (select 1 from b2b.not_passed where lead_id = v_id and passed_at is null) then
        raise exception 'not in the not-passed list' using errcode = '22023';
      end if;
      v_res := b2b.route_decide(v_id, true, trim(p_reason), 'pass');
      v_out := v_out || jsonb_build_object('lead_id', v_id, 'ok', true, 'destination', v_res ->> 'destination', 'b2c_lane', v_res ->> 'b2c_lane',
                                           'partner_name', v_res ->> 'partner_name', 'reference', v_res ->> 'reference');
      n := n + 1;
    exception when others then
      v_out := v_out || jsonb_build_object('lead_id', v_id, 'ok', false, 'error', left(sqlerrm, 200));
    end;
  end loop;
  perform b2b.log_event('leads.passed_to_crm', null, null, null, jsonb_build_object('count', n, 'requested', cardinality(p_lead_ids), 'reason', left(trim(p_reason), 300)));
  return jsonb_build_object('passed', n, 'results', v_out);
end $$;

-- ---------- manual route of a B2C-held lead to partners (the only way a B2C lead reaches a partner) ----------
create or replace function b2b.route_to_partners(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  l public.student_leads;
  a b2b.allocations;
  v_res jsonb;
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if l.consent_partner_share_at is null and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) then
    raise exception 'the student has not consented to sharing with partners' using errcode = '22023';
  end if;
  select * into a from b2b.allocations where lead_id = l.id and destination_type = 'in_house' and status = 'handed_off'
   order by created_at desc limit 1;
  if a.id is null or l.destination_type is distinct from 'in_house' then raise exception 'only a lead held by B2C can be sent to partners' using errcode = '22023'; end if;

  update b2b.allocations set status = 'closed', outcome = 'routed_to_partners', outcome_at = now(), updated_at = now() where id = a.id;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null, allocation_reason = null,
         updated_by = 'b2b' where id = l.id;
  perform b2b.log_event('lead.route_to_partners', l.id, a.id, null, jsonb_build_object('reason', left(trim(p_reason), 300), 'closed_allocation', a.reference));
  v_res := b2b.route_decide(l.id, true, trim(p_reason), 'to_partners');
  return v_res;
end $$;

-- ---------- a partner marks a lead lost: B2C nurture, automatically (Addendum 1 §1 step 5, §2) ----------
create or replace function b2b.allocation_partner_lost(p_allocation_id bigint, p_detail jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  l public.student_leads;
  v_dec bigint;
  v_new bigint;
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.status not in ('queued', 'pushing', 'pushed', 'accepted') then
    raise exception 'only an open partner allocation can be marked lost' using errcode = '22023';
  end if;
  select * into l from public.student_leads where id = a.lead_id for update;

  update b2b.allocations set status = 'closed', outcome = 'lost', outcome_at = now(), updated_at = now() where id = a.id;
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, reason, settings_version, is_test, actor_type, actor_id, b2c_lane)
  values (a.lead_id, a.cycle_no, a.segment, b2b.lead_interest(l), 'fallback', 'in_house', 'partner_lost',
          (select version from b2b.settings where key = 'engine'), a.is_test, b2b.actor() ->> 'type', b2b.actor() ->> 'id', 'nurture')
  returning id into v_dec;
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, status, mode, attempt_no, reason, engine_decision_id, is_test, b2c_lane)
  values (a.lead_id, a.cycle_no, a.segment, 'in_house', 'handed_off', 'fallback', a.attempt_no + 1, 'partner_lost', v_dec, a.is_test, 'nurture')
  returning id into v_new;
  update b2b.allocations set reference = 'EDW-' || v_new where id = v_new;
  -- the partner-sync columns (partner_record_id, partner_stage_raw…) stay as history
  update public.student_leads set destination_type = 'in_house', partner_id = null, allocation_id = v_new, allocated_at = now(),
         allocation_reason = 'partner_lost', updated_by = 'b2b' where id = a.lead_id;
  perform b2b.log_event('b2c.lead_handed_off', a.lead_id, v_new, a.partner_id, jsonb_build_object(
    'lead_id', a.lead_id, 'b2c_lane', 'nurture', 'reason', 'partner_lost', 'decision_id', v_dec, 'reference', 'EDW-' || v_new,
    'partner_id', a.partner_id, 'partner_record_id', coalesce(a.partner_record_id, l.partner_record_id),
    'lost_reason', p_detail ->> 'lost_reason', 'partner_status', coalesce(p_detail ->> 'status', l.partner_stage_raw),
    'partner_sub_status', coalesce(p_detail ->> 'sub_status', l.partner_sub_stage_raw), 'partner_last_activity', p_detail ->> 'last_activity_at',
    'partners_tried', (select coalesce(jsonb_agg(jsonb_build_object('partner_id', x.partner_id, 'status', x.status, 'outcome', x.outcome) order by x.created_at), '[]')
                         from b2b.allocations x where x.lead_id = a.lead_id and x.destination_type = 'partner')));
  return jsonb_build_object('allocation_id', v_new, 'reference', 'EDW-' || v_new);
end $$;

-- ---------- review queue ----------
create or replace function b2b.review_flag_resolve(p_id bigint, p_resolution text, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare f b2b.review_flags;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_resolution not in ('keep', 'close') then raise exception 'choose keep or close' using errcode = '22023'; end if;
  update b2b.review_flags set resolved_at = now(), resolution = p_resolution, resolved_by = coalesce(auth.uid()::text, 'system'), note = left(trim(p_note), 300)
   where id = p_id and resolved_at is null returning * into f;
  if f.id is null then raise exception 'flag not found or already resolved' using errcode = 'P0002'; end if;
  perform b2b.log_event('lead.flag_resolved', f.lead_id, f.allocation_id, null, jsonb_build_object('resolution', p_resolution, 'note', left(trim(p_note), 300)));
  -- the B2C CRM closes the lead itself when the Admin agrees; a partner-held lead stays with the partner either way
  if p_resolution = 'close' and f.destination_type = 'in_house' then
    perform b2b.log_event('b2c.lead_close_agreed', f.lead_id, f.allocation_id, null, jsonb_build_object('lead_id', f.lead_id, 'classification', f.lead_status));
  end if;
end $$;

revoke execute on function b2b.can_route(), b2b.routing_rule_save(jsonb), b2b.handoff_settings_save(jsonb, text), b2b.pass_to_crm(bigint[], text),
                           b2b.route_to_partners(bigint, text), b2b.allocation_partner_lost(bigint, jsonb), b2b.review_flag_resolve(bigint, text, text)
  from public, anon;
grant execute on function b2b.can_route(), b2b.routing_rule_save(jsonb), b2b.handoff_settings_save(jsonb, text), b2b.pass_to_crm(bigint[], text),
                          b2b.route_to_partners(bigint, text), b2b.allocation_partner_lost(bigint, jsonb), b2b.review_flag_resolve(bigint, text, text)
  to authenticated, service_role;
