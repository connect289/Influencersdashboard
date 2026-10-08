-- M31l: Addendum 3, part 12: Admin actions and reads (docs/B2B_CRM_ADDENDUM_3.md PART 6.2, 6.3, R1, PART 4 "Bounds and
-- weights are Admin settings"; design D20, D21, D24, D27, D36; CONTRACT.md section 10; findings C6, C7, C29, C56-C60, C62,
-- C90, C91, C124-C128).
--   reroute_check / reroute_lead / reroute_many      the PART 6.2 re-route: only before the first contact attempt or after an
--                                                     SLA breach, refused while lost in grace; recall + B2C hand-off or the
--                                                     next-best partner (p_how 'reroute')
--   route_to_partners_many                            bulk route-to-partners with the PART 6.3 skip counts
--   route_test_lead                                   the sandbox (R1) and the B2C test hand-off
--   lost_delays_save                                  first nurture message after partner_lost, 3-90 days
--   pass_to_crm, routing_rule_save                    override = true before the 'pass' decision; rule conditions add
--                                                     specializations and paid
--   engine_settings_save, engine_policy_save          partial updates; the rulebook numbers are fixed, the Phase 3 overrides
--                                                     retired; effort / SLA bounds, step and weights are versioned Admin
--                                                     settings inside the rulebook ranges (owner's correction 1)
--   segment_interest, segment_view, segment_mode,     the Segments tab from the engine's own stage_score (C58, C59), 3- or
--   routing_segments, routing_segment                 4-part keys, no pins / caps / weights
--   segment_policy_save, partner_weight_save          always refused (Addendum 3 removed them)
--   decision_replay                                   deterministic replay of A3 decisions; legacy branches kept (C128)
--   lead_routing, lead_filter_sql, leads_list,        the bar, providers, hold, consent, re-enquiries, lost grace, paid
--   leads_facets, leads_export, decision_json         platform on every lead read
--   routing_overview, pool_overview, command_center   today's A3 numbers, the go-live checklist, insights (C90, C91)
--   alert_feed, settings_history, routing_decisions   the new alert types; version history with a diff; the decision log
--   partner_detail                                    effort / SLA factors and the auto-pause reason (web group W9 gap)
-- Every function: schema b2b, SECURITY DEFINER, set search_path = ''. Admin RPCs raise 42501 unless b2b.is_admin();
-- messages for the Admin use errcode 22023. Settings change only through b2b.set_setting after b2b.setting_for_update.
-- Idempotent: every statement is create or replace / on conflict do nothing; re-applying changes nothing.

-- the lost-delays key exists since m31a; seeded again here so lost_delays_save never meets a missing key
insert into b2b.settings (key, value, actor_type, actor_id)
values ('lost_nurture_delays', '{"default": 14, "reasons": {}}', 'system', 'm31l')
on conflict (key) do nothing;

-- ======================================================================================================== helpers
/* A number inside a range, read from JSON (a JSON number or a plain decimal string); anything else is a 22023 for the Admin. */
create or replace function b2b.setting_num(p jsonb, p_lo numeric, p_hi numeric, p_what text)
returns numeric language plpgsql immutable set search_path = '' as $fn$
declare v numeric := b2b.stats_num(p);
begin
  if v is null or v < p_lo or v > p_hi then
    raise exception '% must be between % and %', p_what, p_lo, p_hi using errcode = '22023';
  end if;
  return v;
end $fn$;

create or replace function b2b.setting_bool(p jsonb, p_what text)
returns boolean language plpgsql immutable set search_path = '' as $fn$
begin
  if coalesce(jsonb_typeof(p), 'missing') <> 'boolean' then
    raise exception '% is on or off', p_what using errcode = '22023';
  end if;
  return (p #>> '{}')::boolean;
end $fn$;

/* The interest a segment key stands for (C59): 'course|level|mode' or 'course|level|mode|u<university_id>'. */
create or replace function b2b.segment_interest(p_segment text)
returns jsonb language sql immutable set search_path = '' as $fn$
  select jsonb_build_object(
    'course_key', split_part(p_segment, '|', 1),
    'level', nullif(nullif(split_part(p_segment, '|', 2), '*'), ''),
    'mode', nullif(nullif(split_part(p_segment, '|', 3), '*'), ''),
    'university_ids', case when cardinality(string_to_array(p_segment, '|')) >= 4 and split_part(p_segment, '|', 4) ~ '^u[0-9]+$'
                           then jsonb_build_array(substr(split_part(p_segment, '|', 4), 2)::bigint) else '[]'::jsonb end,
    'university_id', case when cardinality(string_to_array(p_segment, '|')) >= 4 and split_part(p_segment, '|', 4) ~ '^u[0-9]+$'
                          then substr(split_part(p_segment, '|', 4), 2)::bigint end,
    'segment', split_part(p_segment, '|', 1) || '|' || split_part(p_segment, '|', 2) || '|' || split_part(p_segment, '|', 3),
    'segment_exact', case when cardinality(string_to_array(p_segment, '|')) >= 4 then p_segment end,
    'rank', 1, 'source', 'segment');
$fn$;

/* The lateral joins and the columns every lead list / export adds under Addendum 3 (set-based: no per-row lead_family scan).
   The row alias is l. Columns: partner_bar_reason, partner_barred_at, other_providers_count, other_providers, b2c_lane,
   allocation_reason, hold_kind, reenquired_open, paid_platform, consent_state, lost_grace_until. The bar is read on the lead
   and on the same phone digits (partner_bars.phone_digits, null for test leads); the hold kind follows b2b.b2c_hold's rule;
   paid_platform comes from b2b.lead_campaigns (the attribution m21b/m31g sync for every lead). */
create or replace function b2b.lead_a3_joins_sql()
returns text language sql immutable set search_path = '' as $fn$
  select $j$
         left join lateral (
           select pb.reason as bar_reason, pb.barred_at
             from b2b.partner_bars pb
            where pb.lead_id = l.id
               or (pb.phone_digits is not null and length(pb.phone_digits) >= 10
                   and pb.phone_digits = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
            order by pb.barred_at limit 1) bar on true
         left join lateral (
           select a.b2c_lane, a.reason as alloc_reason,
                  case when a.destination_type = 'partner' and a.lost_at is not null and a.lost_revived_at is null
                            and a.status in ('pushed', 'accepted') then a.lost_grace_until end as lost_grace_until
             from b2b.allocations a where a.id = l.allocation_id) ca on true
         left join lateral (
           select ih.id, ih.status, ih.reason, ih.outcome, ih.created_at
             from b2b.allocations ih
            where ih.lead_id = l.id and ih.destination_type = 'in_house'
            order by ih.created_at desc, ih.id desc limit 1) ih on true
         left join lateral (
           select count(distinct d.partner_id) as n, string_agg(distinct coalesce(p.display_name, p.name), '; ') as names
             from b2b.allocations d join b2b.partners p on p.id = d.partner_id
            where d.status = 'duplicate' and coalesce(d.claim_proof_ok, false) and not coalesce(d.returning_lead, false)
              and (d.lead_id = l.id
                   or (length(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g')) >= 10
                       and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
                       and d.lead_id in (select s.id from public.student_leads s
                                          where regexp_replace(coalesce(s.whatsapp_number, ''), '\D', '', 'g')
                                                = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))))) op on true
         left join lateral (
           select lc.platform from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid order by lc.cycle_no desc limit 1) pc on true
  $j$;
$fn$;

create or replace function b2b.lead_a3_columns_sql()
returns text language sql immutable set search_path = '' as $fn$
  select $c$
               bar.bar_reason as partner_bar_reason, bar.barred_at as partner_barred_at,
               coalesce(op.n, 0)::int as other_providers_count, op.names as other_providers,
               ca.b2c_lane, coalesce(l.allocation_reason, ca.alloc_reason) as allocation_reason,
               case when bar.bar_reason is not null and (l.destination_type = 'in_house' or (ih.status = 'handed_off' and l.allocation_id = ih.id)) then 'barred'
                    when ih.id is null or ih.outcome in ('requalified', 'routed_to_partners') then null
                    when exists (select 1 from b2b.allocations pa where pa.lead_id = l.id and pa.destination_type = 'partner'
                                    and pa.origin in ('to_partners', 'requalify', 'reroute') and (pa.created_at, pa.id) > (ih.created_at, ih.id)) then null
                    when ih.reason in ('not_qualified', 'consent_no_answer') then 'qualification_nurture'
                    else 'selling' end as hold_kind,
               exists (select 1 from b2b.lead_reenquiries rq where rq.lead_id = l.id and rq.acknowledged_at is null) as reenquired_open,
               pc.platform as paid_platform,
               b2b.consent_state_of(b2b.partner_consent(l)) as consent_state,
               ca.lost_grace_until
  $c$;
$fn$;

-- ======================================================================================================== (1) reroute_check
/* PART 6.2: an open partner allocation may be recalled only before the partner's first contact attempt, or after an SLA
   breach (breached or met late). Refused while lost in grace (D20, critic B7). Not Admin-gated: lead_routing and
   reroute_lead call it; the web reads it to enable the Re-route button. */
create or replace function b2b.reroute_check(p_allocation_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_fa timestamptz;
  v_br jsonb;
  v_contact timestamptz;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null or a.destination_type <> 'partner' or a.status not in ('queued', 'pushing', 'pushed', 'accepted') then
    return jsonb_build_object('allowed', false, 'why', 'not an open partner allocation', 'lost_in_grace', false, 'first_attempt_at', null,
                              'breaches', '[]'::jsonb, 'allocation_id', p_allocation_id, 'status', a.status);
  end if;
  if a.lost_at is not null and a.lost_revived_at is null then
    return jsonb_build_object('allowed', false,
                              'why', 'lost, in grace: it returns to the partner on activity, or moves to B2C nurture with a partner bar after the grace',
                              'lost_in_grace', true, 'first_attempt_at', null, 'breaches', '[]'::jsonb, 'allocation_id', a.id, 'status', a.status);
  end if;
  select l.first_contacted_at into v_contact from public.student_leads l
   where l.id = a.lead_id and l.allocation_id = a.id and l.first_contacted_at is not null and l.first_contacted_at >= coalesce(a.pushed_at, a.created_at);
  -- least() skips nulls here: the earliest of the first-attempt SLA met time, the first outbound activity and the contact stamp
  v_fa := least((select min(s.met_at) from b2b.sla_checks s where s.allocation_id = a.id and s.sla = 'first_attempt' and s.met_at is not null),
                (select min(x.occurred_at) from b2b.partner_activities x
                  where x.allocation_id = a.id and x.direction = 'outbound' and x.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting')),
                v_contact);
  v_br := coalesce((select jsonb_agg(jsonb_build_object('sla', s.sla, 'status', s.status, 'due_at', s.due_at, 'met_at', s.met_at) order by s.due_at)
                      from b2b.sla_checks s where s.allocation_id = a.id and s.status in ('breached', 'met_late')), '[]'::jsonb);
  return jsonb_build_object(
    'allowed', v_fa is null or jsonb_array_length(v_br) > 0,
    'why', case when v_fa is null or jsonb_array_length(v_br) > 0 then null
                else 'the partner has already contacted the student and breached no SLA: a re-route needs a breach first' end,
    'lost_in_grace', false, 'first_attempt_at', v_fa, 'breaches', v_br, 'allocation_id', a.id, 'status', a.status);
end $fn$;

-- ======================================================================================================== (2) reroute_lead
/* The Admin recalls the partner's allocation (status 'recalled', the reason kept) and sends the lead to B2C (a manual
   decision, mode manual, origin reroute, never barred) or to the next-best partner (route_decide in the 'reroute' context,
   which excludes the recalled partner as 'tried'). */
create or replace function b2b.reroute_lead(p_lead_id bigint, p_to text, p_reason text, p_b2c_lane text default 'sales')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  v_chk jsonb;
  v_bar jsonb;
  v_hold jsonb;
  v_attr jsonb;
  v_interests jsonb;
  v_actor jsonb := b2b.actor();
  v_reason text := left(trim(coalesce(p_reason, '')), 300);
  v_dec bigint;
  v_new bigint;
  v jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_to not in ('b2c', 'partners') then raise exception 'choose B2C or partners' using errcode = '22023'; end if;
  if length(v_reason) < 3 then raise exception 'a reason of 3 to 300 characters is required' using errcode = '22023'; end if;
  if coalesce(p_b2c_lane, 'sales') not in ('sales', 'nurture') then raise exception 'choose the B2C lane: sales or nurture' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  select * into a from b2b.allocations
   where lead_id = l.id and destination_type = 'partner' and status in ('queued', 'pushing', 'pushed', 'accepted')
   order by created_at desc, id desc limit 1 for update;
  if a.id is null or l.allocation_id is distinct from a.id then
    raise exception 'the lead is not with a partner: nothing to recall' using errcode = '22023';
  end if;
  v_chk := b2b.reroute_check(a.id);
  if not coalesce((v_chk ->> 'allowed')::boolean, false) then
    raise exception '%', coalesce(v_chk ->> 'why', 'this allocation cannot be re-routed') using errcode = '22023';
  end if;
  v_bar := b2b.partner_bar(l);
  if p_to = 'partners' and v_bar is not null then
    raise exception 'partner_barred: partner-barred (%) since %: this lead can never be sent to partners',
      v_bar ->> 'reason', (v_bar ->> 'barred_at')::timestamptz::date using errcode = '22023';
  end if;

  -- 1. the recall
  update b2b.allocations set status = 'recalled', outcome = 'recalled', outcome_at = now(), recall_reason = v_reason, updated_at = now() where id = a.id;
  update b2b.student_notifications set status = 'cancelled', error = 'recalled by the Admin', updated_at = now()
   where allocation_id = a.id and status = 'scheduled';
  update b2b.sla_checks set status = 'void', updated_at = now() where allocation_id = a.id and status = 'pending';
  update public.student_leads
     set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null, allocation_reason = null,
         stage = 'qualifying', updated_by = 'b2b'
   where id = l.id and allocation_id = a.id;
  perform b2b.log_event('lead.recalled', l.id, a.id, a.partner_id,
                        jsonb_build_object('reason', v_reason, 'to', p_to, 'reference', a.reference, 'partner_id', a.partner_id,
                                           'lane', case when p_to = 'b2c' then coalesce(p_b2c_lane, 'sales') end, 'status_before', a.status));
  perform b2b.log_event('alert.partner_recall_notice', l.id, a.id, a.partner_id,
                        jsonb_build_object('allocation_id', a.id, 'reference', a.reference, 'partner_id', a.partner_id, 'reason', v_reason, 'to', p_to));

  if p_to = 'partners' then
    v := b2b.route_decide(l.id, true, v_reason, 'reroute');
    return jsonb_build_object('rerouted', coalesce((v ->> 'committed')::boolean, false), 'to', p_to, 'recalled_allocation_id', a.id,
                              'reference', v ->> 'reference', 'decision_id', (v ->> 'decision_id')::bigint, 'allocation_id', (v ->> 'allocation_id')::bigint,
                              'destination', v ->> 'destination', 'reason', v ->> 'reason', 'partner_id', (v ->> 'partner_id')::bigint, 'route', v);
  end if;

  -- 2. to B2C: a manual decision and a handed-off allocation (reason exactly 'manual', C124; the Admin's text is on the recall)
  select * into l from public.student_leads where id = l.id;
  v_attr := b2b.lead_attribution(l);
  v_hold := b2b.b2c_hold(l);
  if a.engine_decision_id is not null then select d.interests into v_interests from b2b.engine_decisions d where d.id = a.engine_decision_id; end if;
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, segment_exact, interest, interest_rank, interests, mode, destination_type, reason,
                                    settings_version, is_test, actor_type, actor_id, b2c_lane, how, hold, bar, class, attribution)
  values (l.id, a.cycle_no, a.segment, a.segment_exact, b2b.lead_interest(l), a.interest_rank, v_interests, 'manual', 'in_house', 'manual',
          (select version from b2b.settings where key = 'engine'), a.is_test, coalesce(v_actor ->> 'type', 'admin'), v_actor ->> 'id',
          coalesce(p_b2c_lane, 'sales'), 'reroute', v_hold, v_bar, b2b.lead_class(l) ->> 'class', v_attr)
  returning id into v_dec;
  insert into b2b.allocations (lead_id, cycle_no, segment, segment_exact, destination_type, status, mode, attempt_no, reason, engine_decision_id, is_test,
                               b2c_lane, origin, interest_rank, paid, paid_platform, campaign_id)
  values (l.id, a.cycle_no, a.segment, a.segment_exact, 'in_house', 'handed_off', 'manual', coalesce(a.attempt_no, 0) + 1, 'manual', v_dec, a.is_test,
          coalesce(p_b2c_lane, 'sales'), 'reroute', a.interest_rank, coalesce((v_attr ->> 'paid')::boolean, false), v_attr ->> 'platform', v_attr ->> 'campaign_id')
  returning id into v_new;
  update b2b.allocations set reference = 'EDW-' || v_new where id = v_new;
  update public.student_leads
     set destination_type = 'in_house', partner_id = null, allocation_id = v_new, allocated_at = now(), allocation_reason = 'manual', updated_by = 'b2b'
   where id = l.id;
  perform b2b.log_event('b2c.lead_handed_off', l.id, v_new, null, b2b.handoff_payload(v_new, jsonb_build_object('recall_reason', v_reason)));
  return jsonb_build_object('rerouted', true, 'to', p_to, 'recalled_allocation_id', a.id, 'reference', 'EDW-' || v_new, 'decision_id', v_dec,
                            'allocation_id', v_new, 'destination', 'in_house', 'reason', 'manual', 'partner_id', null, 'route', null);
end $fn$;

-- ======================================================================================================== (3) reroute_many
create or replace function b2b.reroute_many(p_lead_ids bigint[], p_to text, p_reason text, p_b2c_lane text default 'sales')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  l public.student_leads;
  a b2b.allocations;
  v_chk jsonb;
  v jsonb;
  res jsonb := '[]';
  n_done int := 0; n_np int := 0; n_cnb int := 0; n_lg int := 0; n_bar int := 0; n_f int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_to not in ('b2c', 'partners') then raise exception 'choose B2C or partners' using errcode = '22023'; end if;
  if length(trim(coalesce(p_reason, ''))) not between 3 and 300 then raise exception 'a reason of 3 to 300 characters is required' using errcode = '22023'; end if;
  if p_lead_ids is null or cardinality(p_lead_ids) not between 1 and 500 then raise exception 'choose 1 to 500 leads' using errcode = '22023'; end if;
  foreach v_id in array (select array_agg(distinct x) from unnest(p_lead_ids) x) loop
    begin
      select * into l from public.student_leads where id = v_id;
      if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
      select * into a from b2b.allocations
       where lead_id = l.id and destination_type = 'partner' and status in ('queued', 'pushing', 'pushed', 'accepted')
       order by created_at desc, id desc limit 1;
      if a.id is null or l.allocation_id is distinct from a.id then
        n_np := n_np + 1;
        res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'skipped', 'no_partner_allocation', 'error', null, 'reference', null);
        continue;
      end if;
      v_chk := b2b.reroute_check(a.id);
      if coalesce((v_chk ->> 'lost_in_grace')::boolean, false) then
        n_lg := n_lg + 1;
        res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'skipped', 'lost_in_grace', 'error', null, 'reference', a.reference);
        continue;
      elsif not coalesce((v_chk ->> 'allowed')::boolean, false) then
        n_cnb := n_cnb + 1;
        res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'skipped', 'contacted_no_breach', 'error', null, 'reference', a.reference);
        continue;
      end if;
      if p_to = 'partners' and b2b.partner_bar(l) is not null then
        n_bar := n_bar + 1;
        res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'skipped', 'partner_barred', 'error', null, 'reference', a.reference);
        continue;
      end if;
      v := b2b.reroute_lead(v_id, p_to, p_reason, p_b2c_lane);
      n_done := n_done + 1;
      res := res || jsonb_build_object('lead_id', v_id, 'ok', true, 'skipped', null, 'error', null, 'reference', v ->> 'reference',
                                       'destination', v ->> 'destination', 'partner_id', v -> 'partner_id');
    exception when others then
      n_f := n_f + 1;
      res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'skipped', null, 'error', left(sqlerrm, 300), 'reference', null);
    end;
  end loop;
  perform b2b.log_event('leads.rerouted_many', null, null, null,
                        jsonb_build_object('to', p_to, 'done', n_done, 'requested', cardinality(p_lead_ids), 'reason', left(trim(p_reason), 300)));
  return jsonb_build_object('done', n_done, 'skipped_no_partner_allocation', n_np, 'skipped_contacted_no_breach', n_cnb, 'skipped_lost_in_grace', n_lg,
                            'skipped_barred', n_bar, 'failed', n_f, 'results', res);
end $fn$;

-- ======================================================================================================== (4) route_to_partners_many
/* PART 6.3: the bulk 'Send to partners'. Barred leads, leads without consent and leads not held by B2C are skipped with a
   count; every other lead goes through route_to_partners_core (a reason is required). */
create or replace function b2b.route_to_partners_many(p_lead_ids bigint[], p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  v jsonb;
  res jsonb := '[]';
  n_sent int := 0; n_p int := 0; n_b int := 0; n_c int := 0; n_sb int := 0; n_nc int := 0; n_nh int := 0; n_f int := 0;
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_lead_ids is null or cardinality(p_lead_ids) not between 1 and 500 then raise exception 'choose 1 to 500 leads' using errcode = '22023'; end if;
  foreach v_id in array (select array_agg(distinct x) from unnest(p_lead_ids) x) loop
    begin
      v := b2b.route_to_partners_core(v_id, trim(p_reason));
      n_sent := n_sent + 1;
      if v ->> 'destination' = 'partner' then n_p := n_p + 1;
      elsif v ->> 'destination' = 'in_house' then n_b := n_b + 1;
      elsif v ->> 'destination' = 'consent_requested' then n_c := n_c + 1;
      end if;
      res := res || jsonb_build_object('lead_id', v_id, 'ok', true, 'destination', v ->> 'destination', 'reason', v ->> 'reason', 'skipped', null,
                                       'error', null, 'reference', v ->> 'reference', 'partner_id', v -> 'partner_id');
    exception
      when sqlstate '22023' then
        if sqlerrm like 'partner_barred:%' then
          n_sb := n_sb + 1;
          res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'destination', null, 'reason', null, 'skipped', 'partner_barred', 'error', null, 'reference', null);
        elsif sqlerrm like 'no_consent:%' then
          n_nc := n_nc + 1;
          res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'destination', null, 'reason', null, 'skipped', 'no_consent', 'error', null, 'reference', null);
        elsif sqlerrm like 'not_held:%' then
          n_nh := n_nh + 1;
          res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'destination', null, 'reason', null, 'skipped', 'not_held', 'error', null, 'reference', null);
        else
          n_f := n_f + 1;
          res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'destination', null, 'reason', null, 'skipped', null, 'error', left(sqlerrm, 300), 'reference', null);
        end if;
      when others then
        n_f := n_f + 1;
        res := res || jsonb_build_object('lead_id', v_id, 'ok', false, 'destination', null, 'reason', null, 'skipped', null, 'error', left(sqlerrm, 300), 'reference', null);
    end;
  end loop;
  perform b2b.log_event('leads.routed_to_partners_many', null, null, null,
                        jsonb_build_object('sent', n_sent, 'requested', cardinality(p_lead_ids), 'skipped_barred', n_sb, 'skipped_no_consent', n_nc,
                                           'skipped_not_held', n_nh, 'failed', n_f, 'reason', left(trim(p_reason), 300)));
  return jsonb_build_object('sent', n_sent, 'to_partner', n_p, 'back_to_b2c', n_b, 'consent_requested', n_c, 'skipped_barred', n_sb,
                            'skipped_no_consent', n_nc, 'skipped_not_held', n_nh, 'failed', n_f, 'results', res);
end $fn$;

-- ======================================================================================================== (5) route_test_lead
/* R1 / D21: the only routing a test lead gets. 'partner_sandbox' scores the partners with a test endpoint (route_decide
   'sandbox', is_test allocation, pushed to the test endpoint only); 'b2c_test' hands the lead to the B2C CRM flagged test.
   Never counted, never messaged, never in the statistics (every allocation is is_test). */
create or replace function b2b.route_test_lead(p_lead_id bigint, p_target text, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  v_actor jsonb := b2b.actor();
  v_int jsonb;
  v_dec bigint;
  v_new bigint;
  v_attempt int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_target not in ('partner_sandbox', 'b2c_test') then raise exception 'choose the partner sandbox or a B2C test hand-off' using errcode = '22023'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) then
    raise exception 'only a test lead can be routed this way' using errcode = '22023';
  end if;
  if p_target = 'partner_sandbox' then
    return b2b.route_decide(l.id, true, trim(p_reason), 'sandbox');
  end if;
  if l.destination_type is not null or exists (select 1 from b2b.allocations a where a.lead_id = l.id
                                                  and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off')) then
    raise exception 'this test lead is already routed: close or recall its allocation first' using errcode = '22023';
  end if;
  v_int := b2b.lead_interest(l);
  select count(*) + 1 into v_attempt from b2b.allocations a where a.lead_id = l.id and a.cycle_no = coalesce(l.cycle_no, 1) and a.destination_type = 'partner';
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, segment_exact, interest, interest_rank, interests, mode, destination_type, reason,
                                    settings_version, is_test, actor_type, actor_id, b2c_lane, how, hold, bar, class, attribution)
  values (l.id, coalesce(l.cycle_no, 1), v_int ->> 'segment', v_int ->> 'segment_exact', v_int, 1, null, 'manual', 'in_house', 'test_handoff',
          (select version from b2b.settings where key = 'engine'), true, coalesce(v_actor ->> 'type', 'admin'), v_actor ->> 'id', 'sales', 'sandbox',
          b2b.b2c_hold(l), b2b.partner_bar(l), b2b.lead_class(l) ->> 'class', b2b.lead_attribution(l))
  returning id into v_dec;
  insert into b2b.allocations (lead_id, cycle_no, segment, segment_exact, destination_type, status, mode, attempt_no, reason, engine_decision_id, is_test,
                               b2c_lane, origin, interest_rank)
  values (l.id, coalesce(l.cycle_no, 1), v_int ->> 'segment', v_int ->> 'segment_exact', 'in_house', 'handed_off', 'manual', v_attempt, 'test_handoff', v_dec, true,
          'sales', 'sandbox', 1)
  returning id into v_new;
  update b2b.allocations set reference = 'EDW-' || v_new where id = v_new;
  update public.student_leads
     set destination_type = 'in_house', partner_id = null, allocation_id = v_new, allocated_at = now(), allocation_reason = 'test_handoff', updated_by = 'b2b'
   where id = l.id;
  perform b2b.log_event('b2c.lead_handed_off', l.id, v_new, null, b2b.handoff_payload(v_new, jsonb_build_object('test', true, 'note', left(trim(p_reason), 300))));
  return jsonb_build_object('destination', 'in_house', 'reason', 'test_handoff', 'b2c_lane', 'sales', 'allocation_id', v_new, 'reference', 'EDW-' || v_new,
                            'decision_id', v_dec, 'committed', true, 'outcome', 'decided', 'is_test', true);
end $fn$;

-- ======================================================================================================== (6) lost_delays_save
/* PART 6.1 'The lost reason sets when the first nurture message goes out (3-90 days)'. Whole-document save (no partial merge). */
create or replace function b2b.lost_delays_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_def int;
  v_reasons jsonb := '{}';
  r record;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(jsonb_typeof(p), 'missing') <> 'object' then raise exception 'the lost delays are an object {default, reasons}' using errcode = '22023'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  v_def := round(b2b.setting_num(p -> 'default', 3, 90, 'the default delay (days)'))::int;
  if p ? 'reasons' then
    if coalesce(jsonb_typeof(p -> 'reasons'), 'missing') <> 'object' then raise exception 'reasons must map a lost reason to days' using errcode = '22023'; end if;
    if (select count(*) from jsonb_object_keys(p -> 'reasons')) > 50 then raise exception 'at most 50 lost reasons' using errcode = '22023'; end if;
    for r in select k, v from jsonb_each(p -> 'reasons') x(k, v) loop
      if coalesce(trim(r.k), '') = '' or length(trim(r.k)) > 60 then raise exception 'a lost reason is 1 to 60 characters' using errcode = '22023'; end if;
      v_reasons := v_reasons || jsonb_build_object(trim(r.k), round(b2b.setting_num(r.v, 3, 90, 'the delay for ' || trim(r.k) || ' (days)'))::int);
    end loop;
  end if;
  perform b2b.setting_for_update('lost_nurture_delays');
  return b2b.set_setting('lost_nurture_delays', jsonb_build_object('default', v_def, 'reasons', v_reasons), p_reason);
end $fn$;

-- ======================================================================================================== (7) pass_to_crm
/* Pass to CRM: the Admin judges a Not passed lead on its details. override = true and passed_at are set first, so
   lead_class judges on fields (m31d) and route_decide runs in the 'pass' context (R5 skipped; the lead can reach partners). */
create or replace function b2b.pass_to_crm(p_lead_ids bigint[], p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  v_out jsonb := '[]';
  v_res jsonb;
  v_actor jsonb := b2b.actor();
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
      update b2b.not_passed
         set override = true, passed_at = now(), passed_by = coalesce(v_actor ->> 'id', v_actor ->> 'type', 'admin'), pass_note = left(trim(p_reason), 300)
       where lead_id = v_id and passed_at is null;
      v_res := b2b.route_decide(v_id, true, trim(p_reason), 'pass');
      v_out := v_out || jsonb_build_object('lead_id', v_id, 'ok', true, 'destination', v_res ->> 'destination', 'b2c_lane', v_res ->> 'b2c_lane',
                                           'partner_name', v_res ->> 'partner_name', 'reference', v_res ->> 'reference', 'outcome', v_res ->> 'outcome');
      n := n + 1;
    exception when others then
      v_out := v_out || jsonb_build_object('lead_id', v_id, 'ok', false, 'error', left(sqlerrm, 200));
    end;
  end loop;
  perform b2b.log_event('leads.passed_to_crm', null, null, null, jsonb_build_object('count', n, 'requested', cardinality(p_lead_ids), 'reason', left(trim(p_reason), 300)));
  return jsonb_build_object('passed', n, 'results', v_out);
end $fn$;

-- ======================================================================================================== (8) routing_rule_save
create or replace function b2b.routing_rule_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_ids bigint[];
  v_cond jsonb := coalesce(p -> 'conditions', '{}');
  v_who text := coalesce(auth.uid()::text, 'system');
  v_lane text := case when p ->> 'action' = 'to_b2c' then p ->> 'b2c_lane' end;
  k text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if p ->> 'action' not in ('fix_partner', 'narrow', 'exclude', 'to_b2c') then raise exception 'choose what the rule does' using errcode = '22023'; end if;
  if jsonb_typeof(v_cond) <> 'object' or exists (select 1 from jsonb_object_keys(v_cond) x
       where x not in ('sources', 'course_keys', 'states', 'modes', 'levels', 'university_ids', 'campaign_contains', 'specializations', 'paid')) then
    raise exception 'unknown rule condition' using errcode = '22023';
  end if;
  foreach k in array array['sources', 'course_keys', 'states', 'modes', 'levels', 'university_ids', 'campaign_contains', 'specializations'] loop
    if v_cond ? k and jsonb_typeof(v_cond -> k) not in ('array', 'null') then
      raise exception 'rule condition % must be a list', k using errcode = '22023';
    end if;
  end loop;
  if v_cond ? 'paid' then
    if jsonb_typeof(v_cond -> 'paid') = 'null' then v_cond := v_cond - 'paid';
    elsif jsonb_typeof(v_cond -> 'paid') <> 'boolean' then raise exception 'rule condition paid is true or false (Meta / Google attribution label)' using errcode = '22023';
    end if;
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
end $fn$;

-- ======================================================================================================== (9) engine_settings_save
/* Partial update of the Admin's engine settings (CONTRACT 1.4). The rulebook numbers (engine.a3_fixed and their legacy
   aliases) are refused with 'fixed by Addendum 3: <key>'; the Phase 3 overrides with 'retired by Addendum 3: <key>'.
   Effort bounds, SLA floor / ceiling / step and the weights are versioned Admin settings inside the a3_fixed ranges
   (owner's correction 1). The row is locked first (C126). */
create or replace function b2b.engine_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v jsonb;
  fx jsonb;
  k text;
  x jsonb;
  ef jsonb;
  w jsonb;
  v_lo numeric; v_hi numeric; v_r_lo numeric; v_r_hi numeric;
  v_w_lo numeric; v_w_hi numeric;
  v_floor numeric; v_ceil numeric;
  v_sum numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(jsonb_typeof(p), 'missing') <> 'object' then raise exception 'settings must be an object' using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required for every settings change' using errcode = '22023'; end if;
  v := b2b.setting_for_update('engine');
  fx := coalesce(v -> 'a3_fixed', '{}');
  v_w_lo := coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0);
  v_w_hi := coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5);

  for k in select jsonb_object_keys(p) loop
    if k in ('kill_switch', 'fixed_split', 'speed_factor', 'reliability_factor', 'require_partner_consent') then
      raise exception 'retired by Addendum 3: %', k using errcode = '22023';
    elsif k = 'a3_fixed' or k in ('exploration_share', 'min_learning_leads', 'learn_leads', 'attempt_limit', 'partner_limit', 'witty_idle_minutes',
                                 'consent_wait_hours', 'lost_grace_days', 'stages', 'maturity_days', 'matured_days', 'min_matured_leads', 'push_retry_seconds',
                                 'stage_b_min_leads', 'stage_b_min_age_days', 'stage_c_min_matured', 'stage_c_min_partners', 'exact_segment_min_leads',
                                 'tier_projected_min_matured', 'effort_range', 'sla_range', 'sla_step_range', 'weight_range', 'factor_window_days',
                                 'hold_minutes_sync', 'hold_minutes_async', 'duplicate_window_hours', 'auto_pause_breaches', 'auto_pause_sync_minutes') then
      raise exception 'fixed by Addendum 3: %', k using errcode = '22023';
    elsif k = 'cpe_aggregate' then
      if p ->> 'cpe_aggregate' is distinct from 'median' then raise exception 'fixed by Addendum 3: cpe_aggregate' using errcode = '22023'; end if;
    elsif k not in ('enabled', 'witty_unqualified_idle_hours', 'consent_policy', 'consent_admin_yes', 'consent_requests_per_hour', 'reenquiry_quiet_hours',
                    'max_interests', 'criteria_unknown', 'welcome_for_all_nurture', 'require_verified_phone_sources', 'effort_factor', 'sla_factor',
                    'requalify', 'guard', 'half_life_days', 'prior_weight', 'default_p_enroll', 'trusted_sources') then
      raise exception 'unknown engine setting: %', k using errcode = '22023';
    end if;
  end loop;

  if p ? 'enabled' then v := v || jsonb_build_object('enabled', b2b.setting_bool(p -> 'enabled', 'the engine switch')); end if;
  if p ? 'witty_unqualified_idle_hours' then
    v := v || jsonb_build_object('witty_unqualified_idle_hours', round(b2b.setting_num(p -> 'witty_unqualified_idle_hours', 1, 72, 'the Witty inactivity wait (hours)'), 2));
  end if;
  if p ? 'consent_policy' then
    if p ->> 'consent_policy' not in ('ask', 'b2c_sales') then
      raise exception 'the consent policy is ''ask'' or ''b2c_sales'' (Addendum 3 has no ''off'')' using errcode = '22023';
    end if;
    v := v || jsonb_build_object('consent_policy', p ->> 'consent_policy');
  end if;
  if p ? 'consent_admin_yes' then v := v || jsonb_build_object('consent_admin_yes', b2b.setting_bool(p -> 'consent_admin_yes', 'recording a YES given on a call')); end if;
  if p ? 'consent_requests_per_hour' then
    v := v || jsonb_build_object('consent_requests_per_hour', round(b2b.setting_num(p -> 'consent_requests_per_hour', 10, 1000, 'consent requests per hour'))::int);
  end if;
  if p ? 'reenquiry_quiet_hours' then
    v := v || jsonb_build_object('reenquiry_quiet_hours', round(b2b.setting_num(p -> 'reenquiry_quiet_hours', 1, 168, 'the re-enquiry quiet period (hours)'))::int);
  end if;
  if p ? 'max_interests' then
    v := v || jsonb_build_object('max_interests', round(b2b.setting_num(p -> 'max_interests', 1, 10, 'interests tried'))::int);
  end if;
  if p ? 'criteria_unknown' then
    if p ->> 'criteria_unknown' not in ('pass', 'fail') then raise exception 'when a lead''s data is unknown the partner criteria pass or fail' using errcode = '22023'; end if;
    v := v || jsonb_build_object('criteria_unknown', p ->> 'criteria_unknown');
  end if;
  if p ? 'welcome_for_all_nurture' then v := v || jsonb_build_object('welcome_for_all_nurture', b2b.setting_bool(p -> 'welcome_for_all_nurture', 'the welcome request for every nurture hand-off')); end if;
  if p ? 'require_verified_phone_sources' then
    if coalesce(jsonb_typeof(p -> 'require_verified_phone_sources'), 'missing') <> 'array' then raise exception 'verified-phone sources must be a list' using errcode = '22023'; end if;
    if jsonb_array_length(p -> 'require_verified_phone_sources') > 50 then raise exception 'at most 50 verified-phone sources' using errcode = '22023'; end if;
    v := v || jsonb_build_object('require_verified_phone_sources',
           (select coalesce(jsonb_agg(distinct lower(left(trim(s), 60))), '[]') from jsonb_array_elements_text(p -> 'require_verified_phone_sources') s where trim(s) <> ''));
  end if;

  -- the sales-effort factor: on/off, bounds inside a3_fixed.effort_range, six weights 0-5 with a positive sum, minimum sample
  if p ? 'effort_factor' then
    x := p -> 'effort_factor';
    if coalesce(jsonb_typeof(x), 'missing') <> 'object' then raise exception 'effort_factor is an object {enabled, bounds, weights, min_sample}' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(x) loop
      if k not in ('enabled', 'bounds', 'weights', 'min_sample') then raise exception 'unknown effort_factor key: %', k using errcode = '22023'; end if;
    end loop;
    ef := coalesce(v -> 'effort_factor', '{}');
    if x ? 'enabled' then ef := ef || jsonb_build_object('enabled', b2b.setting_bool(x -> 'enabled', 'the sales-effort factor')); end if;
    if x ? 'bounds' then
      v_r_lo := coalesce(b2b.stats_num(fx -> 'effort_range' -> 0), 0.85);
      v_r_hi := coalesce(b2b.stats_num(fx -> 'effort_range' -> 1), 1.15);
      if jsonb_typeof(x -> 'bounds') = 'array' then
        v_lo := b2b.stats_num(x -> 'bounds' -> 0); v_hi := b2b.stats_num(x -> 'bounds' -> 1);
      elsif jsonb_typeof(x -> 'bounds') = 'object' then
        v_lo := b2b.stats_num(coalesce(x -> 'bounds' -> 'lo', x -> 'bounds' -> 'low')); v_hi := b2b.stats_num(coalesce(x -> 'bounds' -> 'hi', x -> 'bounds' -> 'high'));
      end if;
      if v_lo is null or v_hi is null then raise exception 'effort bounds are [low, high]' using errcode = '22023'; end if;
      if v_lo < v_r_lo or v_lo > 1 or v_hi < 1 or v_hi > v_r_hi then
        raise exception 'effort bounds stay inside the rulebook range % to % (low <= 1 <= high)', v_r_lo, v_r_hi using errcode = '22023';
      end if;
      ef := ef || jsonb_build_object('bounds', jsonb_build_array(round(v_lo, 4), round(v_hi, 4)));
    end if;
    if x ? 'weights' then
      if coalesce(jsonb_typeof(x -> 'weights'), 'missing') <> 'object' then raise exception 'effort weights are an object of the six metrics' using errcode = '22023'; end if;
      w := coalesce(ef -> 'weights', '{}');
      for k in select jsonb_object_keys(x -> 'weights') loop
        if k not in ('first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share') then
          raise exception 'unknown effort weight: %', k using errcode = '22023';
        end if;
        w := w || jsonb_build_object(k, round(b2b.setting_num(x -> 'weights' -> k, v_w_lo, v_w_hi, 'the effort weight ' || k), 3));
      end loop;
      select coalesce(sum(b2b.stats_num(e.value)), 0) into v_sum from jsonb_each(w) e;
      if v_sum <= 0 then raise exception 'effort weights need a positive sum' using errcode = '22023'; end if;
      ef := ef || jsonb_build_object('weights', w);
    end if;
    if x ? 'min_sample' then ef := ef || jsonb_build_object('min_sample', round(b2b.setting_num(x -> 'min_sample', 3, 100, 'the minimum sample'))::int); end if;
    v := v || jsonb_build_object('effort_factor', ef);
  end if;

  -- the SLA-adherence factor: on/off, floor <= ceiling inside a3_fixed.sla_range, the step per 10 points, three weights
  if p ? 'sla_factor' then
    x := p -> 'sla_factor';
    if coalesce(jsonb_typeof(x), 'missing') <> 'object' then raise exception 'sla_factor is an object {enabled, floor, ceiling, step, weights}' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(x) loop
      if k not in ('enabled', 'floor', 'ceiling', 'step', 'weights') then raise exception 'unknown sla_factor key: %', k using errcode = '22023'; end if;
    end loop;
    ef := coalesce(v -> 'sla_factor', '{}');
    v_r_lo := coalesce(b2b.stats_num(fx -> 'sla_range' -> 0), 0.80);
    v_r_hi := coalesce(b2b.stats_num(fx -> 'sla_range' -> 1), 1.00);
    if x ? 'enabled' then ef := ef || jsonb_build_object('enabled', b2b.setting_bool(x -> 'enabled', 'the SLA-adherence factor')); end if;
    v_floor := case when x ? 'floor' then b2b.setting_num(x -> 'floor', v_r_lo, v_r_hi, 'the SLA floor') else coalesce(b2b.stats_num(ef -> 'floor'), v_r_lo) end;
    v_ceil := case when x ? 'ceiling' then b2b.setting_num(x -> 'ceiling', v_r_lo, v_r_hi, 'the SLA ceiling') else coalesce(b2b.stats_num(ef -> 'ceiling'), v_r_hi) end;
    if v_floor > v_ceil then raise exception 'the SLA floor cannot be above the SLA ceiling' using errcode = '22023'; end if;
    if x ? 'floor' then ef := ef || jsonb_build_object('floor', round(v_floor, 4)); end if;
    if x ? 'ceiling' then ef := ef || jsonb_build_object('ceiling', round(v_ceil, 4)); end if;
    if x ? 'step' then
      ef := ef || jsonb_build_object('step', round(b2b.setting_num(x -> 'step', coalesce(b2b.stats_num(fx -> 'sla_step_range' -> 0), 0.01),
                                                                      coalesce(b2b.stats_num(fx -> 'sla_step_range' -> 1), 0.20), 'the SLA step per 10 points'), 4));
    end if;
    if x ? 'weights' then
      if coalesce(jsonb_typeof(x -> 'weights'), 'missing') <> 'object' then raise exception 'SLA weights are an object of the three SLAs' using errcode = '22023'; end if;
      w := coalesce(ef -> 'weights', '{}');
      for k in select jsonb_object_keys(x -> 'weights') loop
        if k not in ('first_attempt', 'status_update', 'enrollment_proof') then raise exception 'unknown SLA weight: %', k using errcode = '22023'; end if;
        w := w || jsonb_build_object(k, round(b2b.setting_num(x -> 'weights' -> k, v_w_lo, v_w_hi, 'the SLA weight ' || k), 3));
      end loop;
      select coalesce(sum(b2b.stats_num(e.value)), 0) into v_sum from jsonb_each(w) e;
      if v_sum <= 0 then raise exception 'SLA weights need a positive sum' using errcode = '22023'; end if;
      ef := ef || jsonb_build_object('weights', w);
    end if;
    v := v || jsonb_build_object('sla_factor', ef);
  end if;

  if p ? 'requalify' then
    x := p -> 'requalify';
    if coalesce(jsonb_typeof(x), 'missing') <> 'object' then raise exception 'requalify is an object {enabled, wait_for_chat_gate, max_per_run}' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(x) loop
      if k not in ('enabled', 'wait_for_chat_gate', 'max_per_run') then raise exception 'unknown requalify key: %', k using errcode = '22023'; end if;
    end loop;
    ef := coalesce(v -> 'requalify', '{}');
    if x ? 'enabled' then ef := ef || jsonb_build_object('enabled', b2b.setting_bool(x -> 'enabled', 'requalification')); end if;
    if x ? 'wait_for_chat_gate' then ef := ef || jsonb_build_object('wait_for_chat_gate', b2b.setting_bool(x -> 'wait_for_chat_gate', 'waiting for the chat gate')); end if;
    if x ? 'max_per_run' then ef := ef || jsonb_build_object('max_per_run', round(b2b.setting_num(x -> 'max_per_run', 10, 100, 'requalifications per run'))::int); end if;
    v := v || jsonb_build_object('requalify', ef);
  end if;
  if p ? 'guard' then
    x := p -> 'guard';
    if coalesce(jsonb_typeof(x), 'missing') <> 'object' then raise exception 'guard is an object {duplicate_rate_pause}' using errcode = '22023'; end if;
    for k in select jsonb_object_keys(x) loop
      if k <> 'duplicate_rate_pause' then raise exception 'unknown guard key: %', k using errcode = '22023'; end if;
    end loop;
    ef := coalesce(v -> 'guard', '{}');
    if x ? 'duplicate_rate_pause' then ef := ef || jsonb_build_object('duplicate_rate_pause', b2b.setting_bool(x -> 'duplicate_rate_pause', 'the duplicate-rate pause')); end if;
    v := v || jsonb_build_object('guard', ef);
  end if;
  if p ? 'half_life_days' then v := v || jsonb_build_object('half_life_days', round(b2b.setting_num(p -> 'half_life_days', 7, 120, 'the recency half-life (days)'))::int); end if;
  if p ? 'prior_weight' then v := v || jsonb_build_object('prior_weight', round(b2b.setting_num(p -> 'prior_weight', 1, 100, 'prior strength (leads)'), 1)); end if;
  if p ? 'default_p_enroll' then v := v || jsonb_build_object('default_p_enroll', round(b2b.setting_num(p -> 'default_p_enroll', 0.001, 0.5, 'the default enrolment rate'), 4)); end if;
  -- trusted_sources is deprecated: accepted for old callers, never stored again
  return b2b.set_setting('engine', v, p_reason);
end $fn$;

-- ======================================================================================================== (10) engine_policy_save
/* Only the holdout share is an Admin lever now (C63, C125, C126); every other key is refused. */
create or replace function b2b.engine_policy_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pol jsonb;
  k text;
  v_share numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(jsonb_typeof(p), 'missing') <> 'object' then raise exception 'the policy is an object {holdout_share}' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k <> 'holdout_share' then
      raise exception 'Addendum 3 fixed the routing policy: only holdout_share can be changed here (not %)', k using errcode = '22023';
    end if;
  end loop;
  if not (p ? 'holdout_share') then raise exception 'holdout_share is required' using errcode = '22023'; end if;
  v_share := b2b.setting_num(p -> 'holdout_share', 0, 0.5, 'the holdout share');
  pol := b2b.setting_for_update('engine_policy');
  pol := pol || jsonb_build_object('holdout_share', round(v_share, 3));
  return b2b.set_setting('engine_policy', pol, p_reason);
end $fn$;

-- ======================================================================================================== (11) segments
/* Everything the Segments tab shows for one key, from the engine's own stage_score (C58, C59): the offering partners
   (offer_candidates of the key's interest), the competing ones (status active) scored for a non-holdout lead and, when
   there is a holdout, for a holdout lead; the stage, the progress to Stage B and C and the variant. Internal. */
create or replace function b2b.segment_view(p_segment text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_int jsonb := b2b.segment_interest(p_segment);
  v_cands jsonb;
  v_active jsonb;
  v_live jsonb;
  v_hold jsonb;
  v_share numeric := least(greatest(coalesce(b2b.stats_num((select s.value -> 'holdout_share' from b2b.settings s where s.key = 'engine_policy')), 0.1), 0), 0.5);
  v_variant text;
  v_auto text;
  fx jsonb := coalesce((select s.value -> 'a3_fixed' from b2b.settings s where s.key = 'engine'), '{}');
  v_b_leads numeric := coalesce(b2b.stats_num(fx -> 'stage_b_min_leads'), 20);
  v_b_days numeric := coalesce(b2b.stats_num(fx -> 'stage_b_min_age_days'), 7);
  v_c_matured numeric := coalesce(b2b.stats_num(fx -> 'stage_c_min_matured'), 30);
  v_c_partners int := greatest(coalesce(b2b.stats_num(fx -> 'stage_c_min_partners'), 2)::int, 1);
  v_pb_leads numeric := 0;
  v_pb_age numeric := 0;
  v_pc numeric := 0;
  v_n int;
begin
  v_cands := coalesce(b2b.offer_candidates(v_int, false), '[]'::jsonb);
  select coalesce(jsonb_agg(c), '[]'::jsonb) into v_active from jsonb_array_elements(v_cands) c where c ->> 'status' = 'active';
  v_live := b2b.stage_score(jsonb_build_object('lead_id', null::bigint, 'seed', '0.5', 'seed_source', 'given', 'is_test', false,
                                               'segment', v_int ->> 'segment', 'segment_exact', v_int ->> 'segment_exact',
                                               'lane_allowed', false, 'holdout', false), v_active);
  if v_share > 0 then
    v_hold := b2b.stage_score(jsonb_build_object('lead_id', null::bigint, 'seed', '0.5', 'seed_source', 'given', 'is_test', false,
                                                 'segment', v_int ->> 'segment', 'segment_exact', v_int ->> 'segment_exact',
                                                 'lane_allowed', false, 'holdout', true), v_active);
  end if;
  v_variant := case when b2b.engine_params(false) ->> 'variant' = 'ai' and exists (select 1 from b2b.segment_stats where variant = 'ai') then 'ai' else 'base' end;
  select s.auto_stage into v_auto from b2b.segment_stats s where s.variant = 'base' and s.segment = p_segment;
  -- progress towards the stage gates, over the competing partners (the scored candidates carry the received counts)
  select count(*) into v_n from jsonb_array_elements(v_live -> 'candidates');
  if v_n > 0 then
    select least(1, coalesce(min((c ->> 'n_received')::numeric), 0) / v_b_leads),
           least(1, coalesce(min(case when (c ->> 'first_lead_at') is null then 0
                                      else extract(epoch from (now() - (c ->> 'first_lead_at')::timestamptz)) / 86400 end), 0) / v_b_days)
      into v_pb_leads, v_pb_age
      from jsonb_array_elements(v_live -> 'candidates') c;
    select least(1, coalesce((select x.m from (select (c ->> 'n_matured_c')::numeric m, row_number() over (order by (c ->> 'n_matured_c')::numeric desc) rn
                                                 from jsonb_array_elements(v_live -> 'candidates') c) x where x.rn = v_c_partners), 0) / v_c_matured)
      into v_pc;
  end if;
  return jsonb_build_object(
    'segment', p_segment, 'rollup_segment', v_int ->> 'segment', 'segment_exact', v_int ->> 'segment_exact', 'interest', v_int,
    'stage', v_live ->> 'stage', 'auto_stage', v_auto, 'variant', v_variant,
    'progress_b', jsonb_build_object('leads', round(v_pb_leads, 3), 'age', round(v_pb_age, 3)), 'progress_c', round(v_pc, 3),
    'competing', coalesce((select jsonb_agg((c ->> 'partner_id')::bigint) from jsonb_array_elements(v_active) c), '[]'::jsonb),
    'candidates', v_cands, 'live', v_live, 'holdout', v_hold, 'holdout_share', round(v_share, 3));
end $fn$;

/* The segment's stage for non-holdout leads (stage_score), the stored auto_stage and the statistics variant. No pin, no
   kill switch (C7, C127). */
create or replace function b2b.segment_mode(p_segment text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v jsonb := b2b.segment_view(p_segment);
begin
  return jsonb_build_object('stage', v ->> 'stage', 'auto_stage', v ->> 'auto_stage', 'variant', v ->> 'variant');
end $fn$;

create or replace function b2b.routing_segments()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  prm jsonb := b2b.engine_params(true);
  steered jsonb := b2b.engine_params(false);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'params', prm,
    'steered_params', steered,
    'policy', pol,
    'policy_version', (select version from b2b.settings where key = 'engine_policy'),
    'stats_at', (select max(refreshed_at) from b2b.segment_stats where variant = 'base'),
    'stage_rates', coalesce((select jsonb_agg(jsonb_build_object('stage', stage, 'n', n, 'enrolled', enrolled, 'rate', rate)
                                              order by array_position(array['applied', 'interested', 'contacted', 'accepted', 'none'], stage))
                               from b2b.stage_rates), '[]'),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'segment', k.segment, 'rollup', b2b.segment_rollup(k.segment), 'exact', cardinality(string_to_array(k.segment, '|')) >= 4,
               'leads', coalesce(s.n_leads, 0), 'matured', coalesce(s.n_matured, 0), 'prior', coalesce(s.prior, b2b.stats_num(prm -> 'default_p_enroll')),
               'partners', coalesce(s.partners, 0), 'partners_matured', coalesce(s.partners_matured, 0),
               'best_partner_matured', coalesce((select max(x.n_matured_c) from b2b.partner_segment_stats x where x.variant = 'base' and x.segment = k.segment), 0),
               'mode', jsonb_build_object('stage', sv.v ->> 'stage', 'auto_stage', sv.v ->> 'auto_stage', 'variant', sv.v ->> 'variant'),
               'progress_b', sv.v -> 'progress_b', 'progress_c', sv.v -> 'progress_c',
               'competing', jsonb_array_length(coalesce(sv.v -> 'competing', '[]'::jsonb)),
               'rules_active', (select count(*) from b2b.routing_rules r
                                 where r.active
                                   and (r.conditions -> 'course_keys' is null or jsonb_array_length(r.conditions -> 'course_keys') = 0 or r.conditions -> 'course_keys' ? split_part(k.segment, '|', 1))
                                   and (r.conditions -> 'levels' is null or jsonb_array_length(r.conditions -> 'levels') = 0 or r.conditions -> 'levels' ? split_part(k.segment, '|', 2))
                                   and (r.conditions -> 'modes' is null or jsonb_array_length(r.conditions -> 'modes') = 0 or r.conditions -> 'modes' ? split_part(k.segment, '|', 3))),
               'leads_30d', (select count(*) from b2b.allocations a
                              where a.destination_type = 'partner' and not a.is_test and a.created_at > now() - interval '30 days'
                                and case when cardinality(string_to_array(k.segment, '|')) >= 4 then a.segment_exact = k.segment else a.segment = k.segment end),
               'last_routed_at', (select max(a.created_at) from b2b.allocations a
                                   where a.destination_type = 'partner' and not a.is_test
                                     and case when cardinality(string_to_array(k.segment, '|')) >= 4 then a.segment_exact = k.segment else a.segment = k.segment end))
             order by coalesce(s.n_leads, 0) desc, k.segment)
        from (select segment from b2b.segment_stats where variant = 'base' and (n_leads > 0 or partners > 0)
              union select a.segment from b2b.allocations a where a.segment is not null and a.destination_type = 'partner' and not a.is_test
                                                              and a.created_at > now() - interval '90 days'
              union select a.segment_exact from b2b.allocations a where a.segment_exact is not null and a.destination_type = 'partner' and not a.is_test
                                                                    and a.created_at > now() - interval '90 days') k
        left join b2b.segment_stats s on s.variant = 'base' and s.segment = k.segment
        cross join lateral (select b2b.segment_view(k.segment) v) sv
       where k.segment ~ '^[^|]+\|[^|]+\|[^|]+(\|u[0-9]+)?$'), '[]'));
end $fn$;

create or replace function b2b.routing_segment(p_segment text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  prm jsonb := b2b.engine_params(true);
  steered jsonb := b2b.engine_params(false);
  sv jsonb;
  v_live jsonb;
  v_hold jsonb;
  v_exact boolean;
  v_rollup text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_segment), '') = '' then raise exception 'choose a segment' using errcode = '22023'; end if;
  if p_segment !~ '^[^|]+\|[^|]+\|[^|]+(\|u[0-9]+)?$' or length(p_segment) > 160 then raise exception 'unknown segment' using errcode = '22023'; end if;
  v_exact := cardinality(string_to_array(p_segment, '|')) >= 4;
  v_rollup := b2b.segment_rollup(p_segment);
  sv := b2b.segment_view(p_segment);
  v_live := sv -> 'live';
  v_hold := sv -> 'holdout';
  return jsonb_build_object(
    'segment', p_segment, 'rollup', v_rollup, 'exact', v_exact,
    'mode', jsonb_build_object('stage', sv ->> 'stage', 'auto_stage', sv ->> 'auto_stage', 'variant', sv ->> 'variant'),
    'stage', sv ->> 'stage', 'variant', sv ->> 'variant', 'params', prm, 'steered_params', steered,
    'eval_segment', v_live ->> 'eval_segment', 'holdout_share', sv -> 'holdout_share',
    'progress_b', sv -> 'progress_b', 'progress_c', sv -> 'progress_c', 'stats_at', v_live -> 'stats_at',
    'stats', (select to_jsonb(s) from b2b.segment_stats s where s.variant = 'base' and s.segment = p_segment),
    -- every partner offering the key's programme: competing (active) ones with the engine's numbers, the others listed without a score
    'partners', coalesce((
      select jsonb_agg(jsonb_build_object(
               'partner_id', (c ->> 'partner_id')::bigint, 'name', c ->> 'name', 'status', c ->> 'status', 'competing', c ->> 'status' = 'active',
               'score', lc.cand -> 'score', 'tie_rank', (lc.cand ->> 'tie_rank')::int, 'cpe', coalesce(lc.cand -> 'cpe', c -> 'cpe'), 'cpe_basis', lc.cand -> 'cpe_basis',
               'has_rate', coalesce(lc.cand -> 'has_rate', c -> 'has_rate'), 'p_used', lc.cand -> 'p_used', 'p_source', lc.cand -> 'p_source', 'p_hat', coalesce(lc.cand -> 'p_hat', to_jsonb(ex.p_hat)),
               'effort_factor', lc.cand -> 'effort_factor', 'effort_raw', lc.cand -> 'effort_raw', 'effort_detail', coalesce(lc.cand -> 'effort_detail', ex.effort_detail),
               'has_activity', coalesce(lc.cand -> 'has_activity', to_jsonb(ex.has_activity)),
               'sla_adherence', coalesce(lc.cand -> 'sla_adherence', to_jsonb(ex.sla_adherence)), 'sla_factor', lc.cand -> 'sla_factor', 'sla_raw', lc.cand -> 'sla_raw',
               'n_received', coalesce(lc.cand -> 'n_received', to_jsonb(coalesce(ex.n_received, 0))), 'first_lead_at', coalesce(lc.cand -> 'first_lead_at', to_jsonb(ex.first_lead_at)),
               'n_matured_c', coalesce(lc.cand -> 'n_matured_c', to_jsonb(coalesce(ex.n_matured_c, 0))), 'under_tested', lc.cand -> 'under_tested',
               'progress_b', jsonb_build_object('leads', round(least(1, coalesce((lc.cand ->> 'n_received')::numeric, ex.n_received, 0) / coalesce(b2b.stats_num(prm -> 'stages' -> 'stage_b_min_leads'), 20)), 3),
                                                'age', round(least(1, coalesce(extract(epoch from (now() - coalesce((lc.cand ->> 'first_lead_at')::timestamptz, ex.first_lead_at))) / 86400, 0)
                                                                        / coalesce(b2b.stats_num(prm -> 'stages' -> 'stage_b_min_age_days'), 7)), 3)),
               'progress_c', round(least(1, coalesce((lc.cand ->> 'n_matured_c')::numeric, ex.n_matured_c, 0) / coalesce(b2b.stats_num(prm -> 'stages' -> 'stage_c_min_matured'), 30)), 3),
               'holdout', case when hc.cand is not null and (hc.cand -> 'score', hc.cand -> 'p_used', hc.cand -> 'effort_factor', hc.cand -> 'sla_factor')
                                                         is distinct from (lc.cand -> 'score', lc.cand -> 'p_used', lc.cand -> 'effort_factor', lc.cand -> 'sla_factor')
                               then jsonb_build_object('score', hc.cand -> 'score', 'p_used', hc.cand -> 'p_used', 'effort_factor', hc.cand -> 'effort_factor', 'sla_factor', hc.cand -> 'sla_factor') end,
               'exact', case when ex.partner_id is not null then jsonb_build_object('leads', ex.n_leads, 'matured', ex.n_matured, 'enrolled', ex.enrolled,
                               'p_hat', ex.p_hat, 'alpha', ex.alpha, 'beta', ex.beta, 'interval', b2b.beta_interval(ex.alpha, ex.beta),
                               'n_received', ex.n_received, 'n_matured_c', ex.n_matured_c) end,
               'rollup', case when ru.partner_id is not null then jsonb_build_object('leads', ru.n_leads, 'matured', ru.n_matured, 'enrolled', ru.enrolled,
                               'p_hat', ru.p_hat, 'alpha', ru.alpha, 'beta', ru.beta, 'interval', b2b.beta_interval(ru.alpha, ru.beta)) end,
               'refund_rate', coalesce(lc.cand -> 'refund_rate', to_jsonb(coalesce(ex.refund_rate, ru.refund_rate, 0))),
               'offers', (c ->> 'offers_count')::int, 'programmes', c -> 'programmes',
               'daily_cap', c -> 'daily_cap', 'monthly_cap', c -> 'monthly_cap', 'leads_today', c -> 'leads_today', 'leads_month', c -> 'leads_month', 'leads_week', c -> 'leads_week',
               'leads_30d', (select count(*) from b2b.allocations a where a.partner_id = (c ->> 'partner_id')::bigint and not a.is_test and a.status <> 'failed'
                               and a.created_at > now() - interval '30 days'
                               and case when v_exact then a.segment_exact = p_segment else a.segment = p_segment end))
             order by (lc.cand ->> 'tie_rank')::int nulls last, (c ->> 'cpe')::numeric desc nulls last, (c ->> 'partner_id')::bigint)
        from jsonb_array_elements(sv -> 'candidates') c
        left join lateral (select x as cand from jsonb_array_elements(v_live -> 'candidates') x where x ->> 'partner_id' = c ->> 'partner_id' limit 1) lc on true
        left join lateral (select x as cand from jsonb_array_elements(coalesce(v_hold -> 'candidates', '[]'::jsonb)) x where x ->> 'partner_id' = c ->> 'partner_id' limit 1) hc on true
        left join b2b.partner_segment_stats ex on ex.variant = 'base' and ex.partner_id = (c ->> 'partner_id')::bigint and ex.segment = p_segment
        left join b2b.partner_segment_stats ru on ru.variant = 'base' and ru.partner_id = (c ->> 'partner_id')::bigint and ru.segment = v_rollup and v_rollup <> p_segment), '[]'),
    'not_offering', coalesce((
      select jsonb_agg(jsonb_build_object('partner_id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
                                          'n_received', x.n_received, 'n_matured_c', x.n_matured_c) order by x.n_received desc, p.id)
        from b2b.partner_segment_stats x join b2b.partners p on p.id = x.partner_id
       where x.variant = 'base' and x.segment = p_segment and x.n_received > 0
         and not exists (select 1 from jsonb_array_elements(sv -> 'candidates') c where (c ->> 'partner_id')::bigint = x.partner_id)), '[]'),
    'flow_30d', coalesce((select jsonb_agg(jsonb_build_object('mode', x.mode, 'stage', x.stage, 'holdout', x.holdout, 'n', x.n) order by x.mode, x.stage, x.holdout)
                            from (select d.mode, d.stage, d.holdout, count(*) n from b2b.engine_decisions d
                                   where d.destination_type = 'partner' and not d.is_test and d.created_at > now() - interval '30 days'
                                     and case when v_exact then d.segment_exact = p_segment else d.segment = p_segment end
                                   group by 1, 2, 3) x), '[]'),
    'flow_weekly', coalesce((select jsonb_agg(jsonb_build_object('week', x.w, 'partner_id', x.partner_id, 'n', x.n) order by x.w, x.partner_id)
                               from (select date_trunc('week', a.created_at at time zone 'Asia/Kolkata')::date w, a.partner_id, count(*) n
                                       from b2b.allocations a
                                      where a.destination_type = 'partner' and not a.is_test and a.status <> 'failed'
                                        and case when v_exact then a.segment_exact = p_segment else a.segment = p_segment end
                                        and a.created_at > now() - interval '12 weeks'
                                      group by 1, 2) x), '[]'),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'lead_id', d.lead_id, 'at', d.created_at, 'mode', d.mode, 'scoring_mode', d.scoring_mode,
                                                               'stage', d.stage, 'holdout', d.holdout, 'partner_id', d.winner_partner_id,
                                                               'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
                                                               'selection_probability', d.selection_probability, 'is_test', d.is_test) order by d.id desc)
                             from (select * from b2b.engine_decisions d
                                    where d.destination_type = 'partner' and case when v_exact then d.segment_exact = p_segment else d.segment = p_segment end
                                    order by d.id desc limit 15) d), '[]'));
end $fn$;

-- ======================================================================================================== (12) (13) retired saves
/* Addendum 3 removed segment pins, share caps, per-segment exploration and the per-segment kill switch (D24, C7, C29,
   C56, C60, C127). The Admin's override tool is a routing rule. Refused before anything in p is read. */
create or replace function b2b.segment_policy_save(p_segment text, p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  raise exception 'Addendum 3 removed segment pins, share caps and per-segment exploration: use a routing rule' using errcode = '22023';
end $fn$;

create or replace function b2b.partner_weight_save(p_partner_id bigint, p_weight numeric, p_until timestamptz, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  raise exception 'Partner weights were removed by Addendum 3: use a routing rule or pause the partner' using errcode = '22023';
end $fn$;

-- ======================================================================================================== (14) decision_replay
/* A3 decisions (a stage): the stored eligible candidates are re-sorted by the A3 order and the exploration lane is recomputed
   from u01(seed, 'explore') against the exploration share fixed in the decision's settings version; reproduced = the winner
   matches. Legacy decisions keep the m24c branches (C125, C128). */
create or replace function b2b.decision_replay(p_decision_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  d b2b.engine_decisions;
  v_k int;
  v_x jsonb;
  v_cands jsonb;
  v_w jsonb;
  v_xc jsonb;
  v_share numeric;
  v_draw numeric;
  v_lane boolean := false;
  v_learn numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from b2b.engine_decisions where id = p_decision_id;
  if d.id is null then raise exception 'decision not found' using errcode = 'P0002'; end if;

  if d.stage is not null then
    if d.seed is null then return jsonb_build_object('replayable', false, 'why', 'no seed was logged for this decision'); end if;
    select coalesce(jsonb_agg(c order by (c ->> 'score')::numeric desc nulls last, (c ->> 'cpe')::numeric desc nulls last,
                                (c ->> 'sla_adherence')::numeric desc nulls last, (c ->> 'leads_week')::int nulls last, (c ->> 'partner_id')::bigint), '[]')
      into v_cands from jsonb_array_elements(coalesce(d.candidates, '[]')) c where coalesce((c ->> 'eligible')::boolean, true);
    if jsonb_array_length(v_cands) = 0 then return jsonb_build_object('replayable', false, 'why', 'no eligible candidates were logged'); end if;
    v_w := v_cands -> 0;
    v_share := coalesce((select b2b.stats_num(sv.value -> 'a3_fixed' -> 'exploration_share') from b2b.settings_versions sv
                          where sv.key = 'engine' and sv.version = d.settings_version), 0.2);
    v_learn := coalesce((select b2b.stats_num(sv.value -> 'a3_fixed' -> 'learn_leads') from b2b.settings_versions sv
                          where sv.key = 'engine' and sv.version = d.settings_version), 30);
    if d.mode in ('commission_first', 'performance', 'exploration') and jsonb_array_length(v_cands) > 1 and v_share > 0 then
      select c into v_xc from jsonb_array_elements(v_cands) c
       where coalesce((c ->> 'under_tested')::boolean, coalesce((c ->> 'n_received')::numeric, 0) < v_learn)
       order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_adherence')::numeric desc nulls last, (c ->> 'leads_week')::int nulls last, (c ->> 'partner_id')::bigint
       limit 1;
      v_lane := v_xc is not null and v_xc ->> 'partner_id' <> v_w ->> 'partner_id';
    end if;
    if v_lane then
      v_draw := round(b2b.u01(d.seed::text, 'explore')::numeric, 12);
      if v_draw < v_share then v_w := v_xc; end if;
    end if;
    return jsonb_build_object('replayable', true, 'stage', d.stage, 'scoring_mode', d.scoring_mode, 'mode', d.mode,
                              'winner', (v_w ->> 'partner_id')::bigint, 'logged_winner', d.winner_partner_id,
                              'reproduced', (v_w ->> 'partner_id')::bigint = d.winner_partner_id,
                              'lane_applied', v_lane, 'draw', v_draw, 'share', case when v_lane then round(v_share, 3) else 0 end,
                              'logged_draw', d.draw, 'selection_probability', d.selection_probability,
                              'order', (select jsonb_agg((c ->> 'partner_id')::bigint) from jsonb_array_elements(v_cands) c));
  end if;

  -- legacy (pre-A3) decisions
  if d.seed is null or d.scoring_mode is null then
    return jsonb_build_object('replayable', false, 'why', 'decided before seeded scoring (M24) or not a scored decision');
  end if;
  if d.scoring_mode = 'kill_switch' then
    return jsonb_build_object('replayable', false, 'why', 'the retired kill switch split leads in fixed shares; no scoring draw was involved');
  end if;
  if d.mode in ('rule', 'minimum') then
    return jsonb_build_object('replayable', false, 'why', 'a rule or contractual minimum chose the highest commission; no draw was involved');
  end if;
  select coalesce(jsonb_agg(c), '[]') into v_cands from jsonb_array_elements(coalesce(d.candidates, '[]')) c where (c ->> 'eligible')::boolean;
  if d.scoring_mode = 'performance' then
    v_k := coalesce((select (value ->> 'mc_draws')::int from b2b.settings_versions where key = 'engine_policy' and version = d.policy_version), 200);
    v_x := b2b.thompson_pick(v_cands, d.seed::text, v_k);
    return jsonb_build_object('replayable', true, 'scoring_mode', d.scoring_mode, 'winner', (v_x ->> 'winner')::bigint,
                              'logged_winner', d.winner_partner_id, 'reproduced', (v_x ->> 'winner')::bigint = d.winner_partner_id,
                              'selection_probability', (v_x ->> 'selection_probability')::numeric, 'logged_probability', d.selection_probability,
                              'wins', v_x -> 'wins', 'draws', v_x -> 'draws');
  end if;
  return jsonb_build_object('replayable', true, 'scoring_mode', d.scoring_mode, 'logged_winner', d.winner_partner_id,
                            'holdout_draw', round(b2b.u01(d.seed::text, 'holdout')::numeric, 6), 'holdout', d.holdout,
                            'exploration_draw', round(b2b.u01(d.seed::text, 'explore')::numeric, 6), 'mode', d.mode,
                            'selection_probability', d.selection_probability);
end $fn$;

-- ======================================================================================================== (20) decision_json
create or replace function b2b.decision_json(d b2b.engine_decisions)
returns jsonb language sql stable set search_path = '' as $fn$
  select to_jsonb(d) || jsonb_build_object(
    'lead_name', (select l.student_name from public.student_leads l where l.id = d.lead_id),
    'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
    'allocation', (select jsonb_build_object('id', a.id, 'reference', a.reference, 'status', a.status, 'cpe_net_inr', a.cpe_net_inr, 'b2c_lane', a.b2c_lane, 'outcome', a.outcome,
                                             'stage', a.stage, 'score_inr', a.score_inr, 'origin', a.origin, 'effort_factor', a.effort_factor, 'sla_factor', a.sla_factor,
                                             'p_enroll', a.p_enroll, 'model_version', a.model_version, 'cause', a.cause, 'ncpl_inr', a.ncpl_inr)
                     from b2b.allocations a where a.engine_decision_id = d.id order by a.id limit 1));
$fn$;

-- ======================================================================================================== (15) lead_routing
/* The lead drawer's Routing tab: readiness, interest, consent, decisions, allocations, notifications (m9c) plus the bar
   with its providers, the hold, the outlook, the consent ledger and requests, the re-enquiries, the interests tried, the lost
   grace, the re-route check of the open partner allocation, the nurture watch, the go-live checklist and the attribution. */
create or replace function b2b.lead_routing(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  v_cons jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return null; end if;
  select * into a from b2b.allocations x where x.id = l.allocation_id and x.destination_type = 'partner';
  v_cons := b2b.partner_consent(l);
  return jsonb_build_object(
    'readiness', b2b.lead_readiness(l), 'interest', b2b.lead_interest(l),
    'consent', coalesce((v_cons ->> 'given')::boolean, false), 'routing_live', b2b.is_live('routing'),
    'not_passed', (select to_jsonb(n) from b2b.not_passed n where n.lead_id = l.id),
    'flags', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from b2b.review_flags f where f.lead_id = l.id), '[]'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) order by d.created_at desc) from b2b.engine_decisions d where d.lead_id = l.id), '[]'),
    'allocations', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = x.partner_id))
                                              order by x.created_at desc) from b2b.allocations x where x.lead_id = l.id), '[]'),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'channel', n.channel, 'kind', n.kind, 'language', n.language, 'status', n.status,
                                                                   'error', n.error, 'scheduled_for', n.scheduled_for, 'sent_at', n.sent_at, 'created_at', n.created_at,
                                                                   'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = n.partner_id))
                                                order by n.created_at desc, n.channel desc) from b2b.student_notifications n where n.lead_id = l.id), '[]'),
    -- Addendum 3
    'bar', b2b.partner_bar(l),
    'other_providers', coalesce(b2b.lead_other_providers(l.id), '[]'),
    'hold', b2b.b2c_hold(l),
    'outlook', b2b.route_outlook(l),
    'consent_detail', jsonb_build_object(
      'partner_consent', v_cons, 'state', b2b.consent_state_of(v_cons),
      'ledger', coalesce((select jsonb_agg(to_jsonb(c) order by c.at desc, c.id desc) from (select * from b2b.lead_consents c where c.lead_id = l.id order by c.at desc, c.id desc limit 20) c), '[]'),
      'requests', coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select * from b2b.consent_requests q where q.lead_id = l.id order by q.created_at desc limit 5) q), '[]')),
    'reenquiries', coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object('partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = q.partner_id))
                                              order by q.occurred_at desc)
                               from (select * from b2b.lead_reenquiries q where q.lead_id = l.id order by q.occurred_at desc limit 20) q), '[]'),
    'reenquiries_open', (select count(*) from b2b.lead_reenquiries q where q.lead_id = l.id and q.acknowledged_at is null),
    'interests', b2b.lead_interest_list(l),
    'lost_grace', case when a.id is not null and a.lost_at is not null
                       then jsonb_build_object('allocation_id', a.id, 'reference', a.reference, 'partner_id', a.partner_id, 'lost_at', a.lost_at, 'grace_until', a.lost_grace_until,
                                               'lost_reason', a.lost_detail ->> 'lost_reason', 'revived', a.lost_revived_at is not null, 'revived_at', a.lost_revived_at,
                                               'in_grace', a.lost_revived_at is null and a.status in ('pushed', 'accepted'), 'lost_count', a.lost_count) end,
    'reroute', case when a.id is not null and a.status in ('queued', 'pushing', 'pushed', 'accepted') then b2b.reroute_check(a.id) end,
    'nurture_watch', (select to_jsonb(w) from b2b.nurture_watch w where w.lead_id = l.id),
    'wait', (select to_jsonb(w) from b2b.lead_waits w where w.lead_id = l.id),
    'golive', b2b.routing_golive_check(),
    'attribution', b2b.lead_attribution(l),
    'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number));
end $fn$;

-- ======================================================================================================== (16) lead_filter_sql
create or replace function b2b.lead_filter_sql(p jsonb)
returns text language plpgsql immutable set search_path = '' as $fn$
declare
  w      text[] := array['l.merged_into_id is null'];
  q      text := left(trim(coalesce(p ->> 'q', '')), 100);
  digits text;
  pat    text;
  arr    text[];
begin
  if coalesce((p ->> 'bin')::boolean, false) then
    w := array_append(w, 'l.deleted_at is not null');
  else
    w := array_append(w, 'l.deleted_at is null');
  end if;

  if not coalesce((p ->> 'include_test')::boolean, false) then
    w := array_append(w, 'not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))');
  end if;

  if q <> '' then
    pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    digits := regexp_replace(q, '\D', '', 'g');
    w := array_append(w, format('(l.student_name ilike %1$L or l.email_id ilike %1$L%2$s%3$s)',
      pat,
      case when length(digits) >= 4 then format(' or regexp_replace(coalesce(l.whatsapp_number, ''''), ''\D'', '''', ''g'') like %L', '%' || digits || '%') else '' end,
      case when q ~ '^\d{1,18}$' then format(' or l.id = %L::bigint', q) else '' end));
  end if;

  if jsonb_typeof(p -> 'stage') = 'array' and jsonb_array_length(p -> 'stage') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'stage') x;
    w := array_append(w, format('l.stage = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'source') = 'array' and jsonb_array_length(p -> 'source') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'source') x;
    w := array_append(w, format('coalesce(l.lead_source, ''(none)'') = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0 then
    select array_agg(upper(x)) into arr from jsonb_array_elements_text(p -> 'status') x;
    w := array_append(w, format('upper(coalesce(nullif(l.lead_status, ''''), ''NONE'')) = any (%L::text[])', arr));
  end if;
  case p ->> 'destination'
    when 'unrouted' then w := array_append(w, 'l.destination_type is null');
    when 'partner'  then w := array_append(w, 'l.destination_type = ''partner''');
    when 'in_house' then w := array_append(w, 'l.destination_type = ''in_house''');
    when 'not_passed' then w := array_append(w, 'exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
    -- Addendum 3 views
    when 'barred' then w := array_append(w, 'exists (select 1 from b2b.partner_bars pb where pb.lead_id = l.id or (pb.phone_digits is not null and length(pb.phone_digits) >= 10 '
                                            || 'and pb.phone_digits = regexp_replace(coalesce(l.whatsapp_number, ''''), ''\D'', '''', ''g'')))');
    when 'qualification_nurture' then w := array_append(w, 'exists (select 1 from b2b.allocations qa where qa.id = l.allocation_id and qa.destination_type = ''in_house'' '
                                            || 'and qa.status = ''handed_off'' and qa.reason in (''not_qualified'', ''consent_no_answer''))');
    when 'awaiting_consent' then w := array_append(w, 'exists (select 1 from b2b.consent_requests cr where cr.lead_id = l.id and cr.status in (''queued'', ''requested'', ''sent'', ''unsendable''))');
    when 'reenquired' then w := array_append(w, 'exists (select 1 from b2b.lead_reenquiries rq where rq.lead_id = l.id and rq.acknowledged_at is null)');
    when 'lost_grace' then w := array_append(w, 'exists (select 1 from b2b.allocations ga where ga.id = l.allocation_id and ga.destination_type = ''partner'' '
                                            || 'and ga.lost_at is not null and ga.lost_revived_at is null and ga.status in (''pushed'', ''accepted''))');
    else null;
  end case;
  -- the paid label (Meta / Google attribution, no routing effect)
  case p ->> 'paid'
    when 'meta'   then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid and lc.platform = ''meta'')');
    when 'google' then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid and lc.platform = ''google'')');
    when 'any'    then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid)');
    else null;
  end case;
  -- Addendum 2: default views hide not-passed (junk / mismatch) leads; the "Not passed" view and the recycle bin show them
  if coalesce(p ->> 'destination', '') <> 'not_passed' and not coalesce((p ->> 'bin')::boolean, false)
     and not coalesce((p ->> 'with_not_passed')::boolean, false) then
    w := array_append(w, 'not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
  end if;

  return array_to_string(w, ' and ');
end $fn$;

-- ======================================================================================================== (17) leads_list
create or replace function b2b.leads_list(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_where text;
  v_sort  text;
  v_dir   text := case when lower(coalesce(p ->> 'dir', 'desc')) = 'asc' then 'asc' else 'desc' end;
  v_cmp   text := case when lower(coalesce(p ->> 'dir', 'desc')) = 'asc' then '>' else '<' end;
  v_cast  text;
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 50), 1), 200);
  v_keyset text := '';
  v_rows  jsonb;
  v_total bigint;
  v_next  jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;

  case coalesce(p ->> 'sort', 'created_at')
    when 'name'          then v_sort := 'lower(coalesce(nullif(l.student_name, ''''), ''~''))'; v_cast := 'text';
    when 'last_activity' then v_sort := 'coalesce(l.last_activity_at, l.created_at)';             v_cast := 'timestamptz';
    else                      v_sort := 'l.created_at';                                           v_cast := 'timestamptz';
  end case;

  v_where := b2b.lead_filter_sql(p);
  if p ? 'after' and p -> 'after' ->> 'id' is not null then
    v_keyset := format(' and (%s, l.id) %s (%L::%s, %L::bigint)', v_sort, v_cmp, p -> 'after' ->> 'v', v_cast, p -> 'after' ->> 'id');
  end if;

  -- the page is chosen on the lead row alone; the Addendum 3 columns join only the page's rows
  execute format($q$
    select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb)
      from (
        select pg.ord, pg.sort_key,
               l.id, l.created_at, l.student_name, l.whatsapp_number, l.email_id, l.city, l.state,
               l.interested_course, l.interested_specialization, l.program_level, l.study_mode_preference,
               l.lead_source, l.channel, l.campaign, l.lead_status, l.temperature, l.stage, l.sub_stage, l.lead_stage,
               l.destination_type, l.partner_id, l.last_activity_at, l.deleted_at, l.is_opted_out,
               (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) as is_test,
               l.consent_partner_share_at is not null as partner_consent,
               l.is_bot_paused,
               (select jsonb_build_object('reason', np.reason, 'decided_at', np.decided_at, 'detail', np.detail) from b2b.not_passed np
                 where np.lead_id = l.id and np.passed_at is null) as not_passed,
               %6$s
          from (select row_number() over (order by %1$s %4$s, l.id %4$s) as ord, %1$s::text as sort_key, l.id
                  from public.student_leads l
                 where %2$s%3$s
                 order by %1$s %4$s, l.id %4$s
                 limit %5$s) pg
          join public.student_leads l on l.id = pg.id
          %7$s
      ) r
  $q$, v_sort, v_where, v_keyset, v_dir, v_limit + 1, b2b.lead_a3_columns_sql(), b2b.lead_a3_joins_sql()) into v_rows;

  if jsonb_array_length(v_rows) > v_limit then
    v_rows := v_rows - v_limit;   -- the probe row is removed; its presence means there is a next page
    v_next := jsonb_build_object('v', v_rows -> (v_limit - 1) ->> 'sort_key', 'id', v_rows -> (v_limit - 1) ->> 'id');
  end if;
  select coalesce(jsonb_agg(e.value - 'sort_key' - 'ord' order by e.i), '[]'::jsonb)
    into v_rows from jsonb_array_elements(v_rows) with ordinality e(value, i);

  if not (p ? 'after') then
    execute format('select count(*) from public.student_leads l where %s', v_where) into v_total;
  end if;

  return jsonb_build_object('rows', v_rows, 'next', v_next, 'total', v_total);
end $fn$;

-- ======================================================================================================== (18) leads_facets
create or replace function b2b.leads_facets(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_where text;
  v_all   text;
  v_base  jsonb := jsonb_build_object('include_test', p -> 'include_test', 'bin', p -> 'bin', 'q', p -> 'q');
  v_out   jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- facet counts ignore the facet filters themselves, so every option stays visible; only the routing facet counts
  -- not-passed leads (its "Not passed" option), the others follow the list, which hides them
  v_where := b2b.lead_filter_sql(v_base);
  v_all := b2b.lead_filter_sql(v_base || '{"with_not_passed": true}');
  execute format($q$
    select jsonb_build_object(
      'stage',       (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.stage, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'source',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.lead_source, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'status',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select upper(coalesce(nullif(l.lead_status, ''), 'NONE')) k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'destination', (select coalesce(jsonb_object_agg(k, n), '{}') from (select case when exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null) then 'not_passed' else coalesce(l.destination_type, 'unrouted') end k, count(*) n from public.student_leads l where %2$s group by 1) s)
                     || jsonb_build_object(
                          'barred', (select count(*) from public.student_leads l where %3$s),
                          'qualification_nurture', (select count(*) from public.student_leads l where %4$s),
                          'awaiting_consent', (select count(*) from public.student_leads l where %5$s),
                          'reenquired', (select count(*) from public.student_leads l where %6$s),
                          'lost_grace', (select count(*) from public.student_leads l where %7$s)),
      'paid',        jsonb_build_object('meta', (select count(*) from public.student_leads l where %8$s),
                                        'google', (select count(*) from public.student_leads l where %9$s),
                                        'any', (select count(*) from public.student_leads l where %10$s)),
      'bin',         (select count(*) from public.student_leads l where l.deleted_at is not null and l.merged_into_id is null),
      'tests',       (select count(*) from public.student_leads l where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)))
    )
  $q$, v_where, v_all,
       b2b.lead_filter_sql(v_base || '{"destination": "barred"}'), b2b.lead_filter_sql(v_base || '{"destination": "qualification_nurture"}'),
       b2b.lead_filter_sql(v_base || '{"destination": "awaiting_consent"}'), b2b.lead_filter_sql(v_base || '{"destination": "reenquired"}'),
       b2b.lead_filter_sql(v_base || '{"destination": "lost_grace"}'),
       b2b.lead_filter_sql(v_base || '{"paid": "meta"}'), b2b.lead_filter_sql(v_base || '{"paid": "google"}'), b2b.lead_filter_sql(v_base || '{"paid": "any"}')) into v_out;
  return v_out;
end $fn$;

-- ======================================================================================================== (19) routing_overview
create or replace function b2b.routing_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'switch', coalesce((select jsonb_build_object('live', s.live, 'reason', s.reason, 'switched_at', s.switched_at) from b2b.live_switches s where s.scope = 'routing'),
                       jsonb_build_object('live', false)),
    'engine', (select jsonb_build_object('value', s.value, 'version', s.version, 'updated_at', s.updated_at) from b2b.settings s where s.key = 'engine'),
    'golive', b2b.routing_golive_check(),
    'live_partners', (select count(*) from b2b.partners p where p.status = 'active' and b2b.is_live('partner:' || p.id)),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
                                  'live', b2b.is_live('partner:' || p.id), 'test_endpoint', p.test_endpoint is not null,
                                  'paused_reason', p.paused_reason, 'auto_paused_at', p.auto_paused_at,
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
      'b2c_reasons_by_lane', jsonb_build_object(
        'sales', coalesce((select jsonb_object_agg(reason, n) from (select a.reason, count(*) n from b2b.allocations a
                            where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test and a.b2c_lane = 'sales' group by 1) x), '{}'),
        'nurture', coalesce((select jsonb_object_agg(reason, n) from (select a.reason, count(*) n from b2b.allocations a
                              where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test and a.b2c_lane = 'nurture' group by 1) x), '{}')),
      'errors', (select count(*) from b2b.events e where e.type = 'routing.error' and e.occurred_at >= v_today),
      'nurture', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.b2c_lane = 'nurture' and not a.is_test),
      'sales', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.b2c_lane = 'sales' and not a.is_test),
      'not_passed', (select count(*) from b2b.not_passed n where n.decided_at >= v_today and n.passed_at is null),
      'requalified_to_partners', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test and a.origin = 'requalify'),
      'manual_to_partners', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test and a.origin in ('to_partners', 'reroute')),
      'reenquiries', jsonb_build_object(
        'partner', (select count(*) from b2b.lead_reenquiries q where q.created_at >= v_today and q.holder = 'partner'),
        'b2c_selling', (select count(*) from b2b.lead_reenquiries q where q.created_at >= v_today and q.holder = 'b2c_selling'),
        'barred', (select count(*) from b2b.lead_reenquiries q where q.created_at >= v_today and q.holder = 'barred'),
        'qualification_nurture', (select count(*) from b2b.lead_reenquiries q where q.created_at >= v_today and q.holder = 'qualification_nurture')),
      'barred', (select count(*) from b2b.partner_bars b where b.barred_at >= v_today),
      'consent', jsonb_build_object(
        'requested', (select count(*) from b2b.consent_requests c where c.created_at >= v_today and not c.is_test),
        'queued', (select count(*) from b2b.consent_requests c where c.status = 'queued' and not c.is_test),
        'yes', (select count(*) from b2b.consent_requests c where c.answered_at >= v_today and c.answer = 'yes' and not c.is_test),
        'no', (select count(*) from b2b.consent_requests c where c.answered_at >= v_today and c.answer = 'no' and not c.is_test),
        'expired', (select count(*) from b2b.consent_requests c where c.status = 'expired' and c.closed_at >= v_today and not c.is_test)),
      'stages', jsonb_build_object(
        'A', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test and a.stage = 'A'),
        'B', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test and a.stage = 'B'),
        'C', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test and a.stage = 'C')),
      'lost_in_grace', (select count(*) from b2b.allocations a where a.destination_type = 'partner' and not a.is_test and a.lost_at is not null and a.lost_revived_at is null
                          and a.status in ('pushed', 'accepted'))),
    'not_passed_open', (select count(*) from b2b.not_passed n where n.passed_at is null),
    'flags_open', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'lead_id', f.lead_id, 'lead_name', l.student_name, 'lead_status', f.lead_status,
                              'destination_type', f.destination_type, 'reference', a.reference,
                              'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id),
                              'created_at', f.created_at) order by f.created_at desc)
                            from b2b.review_flags f join b2b.allocations a on a.id = f.allocation_id
                            left join public.student_leads l on l.id = f.lead_id where f.resolved_at is null), '[]'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) - 'candidates' - 'excluded' - 'rules' - 'interest' - 'features' - 'shadow' order by d.created_at desc)
                             from (select * from b2b.engine_decisions order by created_at desc limit 50) d), '[]'),
    'rules', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('partner_names',
                              (select jsonb_agg(coalesce(p.display_name, p.name)) from b2b.partners p where p.id = any (r.partner_ids)))
                            order by r.active desc, r.priority, r.id) from b2b.routing_rules r), '[]'),
    'rates', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object(
                              'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = r.partner_id),
                              'programme', b2b.programme_label(r.programme_id))
                            order by r.partner_id, r.programme_id nulls first, r.valid_from desc)
                         from b2b.rates r where r.valid_to is null or r.valid_to >= current_date - 90), '[]'));
end $fn$;

-- ======================================================================================================== (21) pool_overview, command_center
/* Routing counts as on whenever the switch is live and the engine is enabled (no kill switch, C6). Groups come from
   pool_lead (m31f): test, opted_out, held, awaiting_consent, waiting_inactivity, chatting, too_old, routing_off, due. */
create or replace function b2b.pool_overview(p_group text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_on boolean := b2b.is_live('routing') and coalesce((e ->> 'enabled')::boolean, true);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with pool as (
      select l.id, l.student_name, l.lead_source, l.interested_course, l.field_of_interest, l.lead_status, l.created_at,
             greatest(l.created_at, l.last_activity_at, l.last_agent_message_at) as last_seen, b2b.pool_lead(l, v_on) as p
        from public.student_leads l
       where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
         and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)
       order by l.created_at desc
       limit 5000),
    g as (
      select p ->> 'group' grp, count(*) n, min(created_at) oldest,
             count(*) filter (where created_at > now() - interval '1 hour') h1,
             count(*) filter (where created_at <= now() - interval '1 hour' and created_at > now() - interval '1 day') d1,
             count(*) filter (where created_at <= now() - interval '1 day' and created_at > now() - interval '7 days') d7,
             count(*) filter (where created_at <= now() - interval '7 days') older
        from pool group by 1)
    select jsonb_build_object(
      'routing_on', v_on,
      'routing_live', b2b.is_live('routing'),
      'engine_enabled', coalesce((e ->> 'enabled')::boolean, true),
      'idle_minutes', coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'witty_idle_minutes'), 30)::int,
      'unqualified_idle_hours', coalesce(b2b.stats_num(e -> 'witty_unqualified_idle_hours'), 18),
      'golive', b2b.routing_golive_check(),
      'total', (select count(*) from pool),
      'groups', coalesce((select jsonb_object_agg(grp, jsonb_build_object('n', n, 'oldest', oldest, 'ages', jsonb_build_array(h1, d1, d7, older))) from g), '{}'),
      'outlook', coalesce((select jsonb_object_agg(o, n) from (select p ->> 'outlook' o, count(*) n from pool where p ->> 'group' <> 'test' group by 1) x), '{}'),
      'missing', coalesce((select jsonb_object_agg(m, n) from (select m, count(*) n from pool, jsonb_array_elements_text(p -> 'not_qualified') m
                                                               where p ->> 'group' <> 'test' group by 1) x), '{}'),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', student_name, 'source', lead_source,
                                                            'course', coalesce(nullif(interested_course, ''), field_of_interest), 'status', lead_status,
                                                            'created_at', created_at, 'last_seen', last_seen) || p order by created_at)
                        from (select * from pool where p_group is null or p ->> 'group' = p_group order by created_at limit 200) x), '[]')));
end $fn$;

/* The Command Center: today's numbers against yesterday's, the 7-day flow, the lead stream, alerts, partner health, plus
   the Addendum 3 counts (re-enquiries to acknowledge, consent pending and queued, lost in grace, barred today), the realised
   commission of the month (C90), the go-live checklist and the three most valuable AI insights (C91). */
create or replace function b2b.command_center()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_tz text := 'Asia/Kolkata';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_yday timestamptz := v_today - interval '1 day';
  v_month timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_since timestamptz := now() - interval '1 day';  -- yesterday's figures cover the same hours as today's so far
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_on boolean := b2b.is_live('routing') and coalesce((e ->> 'enabled')::boolean, true);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'routing_on', v_on,
    'kpis', (
      with leads as (
        select created_at from public.student_leads
         where created_at >= v_yday and deleted_at is null and merged_into_id is null
           and not (coalesce(is_test, false) or b2b.is_test_phone(whatsapp_number))),
      al as (select * from b2b.allocations where not is_test and created_at >= v_month - interval '7 days'),
      pushed7 as (select status from al where destination_type = 'partner' and created_at > now() - interval '7 days'
                    and status in ('pushed', 'accepted', 'duplicate', 'rejected', 'recalled')),
      sla as (
        select a.id, l.first_contacted_at, coalesce(a.pushed_at, a.accepted_at) + make_interval(hours => coalesce((p.sla ->> 'first_contact_hours')::int, 2)) due
          from al a join public.student_leads l on l.id = a.lead_id join b2b.partners p on p.id = a.partner_id
         where a.destination_type = 'partner' and a.status = 'accepted' and a.accepted_at > now() - interval '7 days')
      select jsonb_build_object(
        'leads_today', (select count(*) from leads where created_at >= v_today),
        'leads_yday', (select count(*) from leads where created_at >= v_yday and created_at < v_since),
        'to_partners_today', (select count(*) from al where destination_type = 'partner' and created_at >= v_today),
        'to_partners_yday', (select count(*) from al where destination_type = 'partner' and created_at >= v_yday and created_at < v_since),
        'to_b2c_today', (select count(*) from al where destination_type = 'in_house' and created_at >= v_today),
        'accepted_today', (select count(*) from al where status = 'accepted' and accepted_at >= v_today),
        'accepted_yday', (select count(*) from al where status = 'accepted' and accepted_at >= v_yday and accepted_at < v_since),
        'duplicate_rate_7d', (select case when count(*) = 0 then null else round(count(*) filter (where status = 'duplicate')::numeric / count(*), 3) end from pushed7),
        'sla_due_7d', (select count(*) from sla where due < now()),
        'sla_met_7d', (select count(*) from sla where due < now() and first_contacted_at is not null and first_contacted_at <= due),
        'commission_expected_month', (select coalesce(sum(cpe_net_inr), 0) from al where status = 'accepted' and accepted_at >= v_month),
        'commission_realised_month', (select coalesce(sum(er.net_inr), 0) from b2b.earnings er left join b2b.allocations a on a.id = er.allocation_id
                                        where er.status = 'realised' and er.realised_at >= v_month and not coalesce(a.is_test, false)),
        'accepted_month', (select count(*) from al where status = 'accepted' and accepted_at >= v_month))),
    'counts', jsonb_build_object(
      'reenquiries_open', (select count(*) from b2b.lead_reenquiries q where q.acknowledged_at is null),
      'consent_pending', (select count(*) from b2b.consent_requests c where c.status in ('requested', 'sent', 'unsendable') and not c.is_test),
      'consent_queued', (select count(*) from b2b.consent_requests c where c.status = 'queued' and not c.is_test),
      'lost_in_grace', (select count(*) from b2b.allocations a where a.destination_type = 'partner' and not a.is_test and a.lost_at is not null
                          and a.lost_revived_at is null and a.status in ('pushed', 'accepted')),
      'barred_today', (select count(*) from b2b.partner_bars b where b.barred_at >= v_today),
      'barred_total', (select count(*) from b2b.partner_bars),
      'not_passed_open', (select count(*) from b2b.not_passed n where n.passed_at is null),
      'flags_open', (select count(*) from b2b.review_flags f where f.resolved_at is null)),
    'golive', b2b.routing_golive_check(),
    -- C91: the three most valuable current recommendations or anomalies (`as` aliases: a bare 'at' is ambiguous with AT TIME ZONE)
    'insights', coalesce((select jsonb_agg(to_jsonb(x) - 'ord' order by x.ord, x.gain_pct desc nulls last, x.occurred_at desc) from (
        (select 1 as ord, 'recommendation' as source, r.id, r.kind, r.title, b2b.stats_num(r.simulation -> 'gain_pct') as gain_pct,
                r.created_at as occurred_at, null::bigint as partner_id
           from b2b.ai_recommendations r
          where r.status = 'open' and (r.expires_at is null or r.expires_at > now())
          order by b2b.stats_num(r.simulation -> 'gain_pct') desc nulls last, r.created_at desc limit 3)
        union all
        (select 2 as ord, 'anomaly' as source, ev.id, ev.type as kind, ev.type as title, null::numeric as gain_pct, ev.occurred_at, ev.partner_id
           from b2b.events ev
          where ev.type in ('alert.ncpl_drop', 'alert.model_fallback', 'alert.partner_auto_paused', 'alert.ai_rollback', 'alert.ai_review_worse')
            and ev.occurred_at > now() - interval '7 days'
          order by ev.occurred_at desc limit 3)
        order by ord, gain_pct desc nulls last, occurred_at desc limit 3) x), '[]'),
    'flow', coalesce((
      select jsonb_agg(jsonb_build_object('source', src, 'destination', dst, 'n', n) order by n desc)
        from (select coalesce(nullif(l.lead_source, ''), 'unknown') src,
                     case when a.destination_type = 'partner' then coalesce(p.display_name, p.name)
                          when a.destination_type = 'in_house' then case when a.b2c_lane = 'nurture' then 'B2C nurture' else 'B2C sales' end
                          when np.lead_id is not null then 'Not passed'
                          else 'Waiting' end dst,
                     count(*) n
                from public.student_leads l
                left join b2b.allocations a on a.id = l.allocation_id
                left join b2b.partners p on p.id = a.partner_id
                left join b2b.not_passed np on np.lead_id = l.id and np.passed_at is null
               where l.created_at > now() - interval '7 days' and l.deleted_at is null and l.merged_into_id is null
                 and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
               group by 1, 2) x), '[]'),
    'stream', coalesce((
      select jsonb_agg(jsonb_build_object('id', ev.id, 'type', ev.type, 'at', ev.occurred_at, 'lead_id', ev.lead_id, 'lead_name', l.student_name,
                                          'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = ev.partner_id),
                                          'detail', coalesce(ev.payload ->> 'reason', ev.payload ->> 'reference', ev.payload ->> 'channel')) order by ev.occurred_at desc)
        from (select * from b2b.events
               where type in ('lead.routed', 'lead.rerouted', 'lead.recalled', 'b2c.lead_handed_off', 'lead.pushed', 'lead.accepted', 'lead.duplicate',
                              'lead.push_failed', 'lead.not_passed', 'lead.route_to_partners', 'notification.sent', 'lead.requalified', 'lead.reenquired',
                              'lead.partner_lost', 'lead.partner_revived', 'lead.partner_barred', 'lead.consent_requested', 'lead.consent_answered')
                 and (lead_id is null or not exists (select 1 from public.student_leads t where t.id = lead_id
                                                       and (coalesce(t.is_test, false) or b2b.is_test_phone(t.whatsapp_number))))
               order by occurred_at desc limit 25) ev
        left join public.student_leads l on l.id = ev.lead_id), '[]'),
    'alerts', coalesce((
      select jsonb_agg(jsonb_build_object('id', ev.id, 'type', ev.type, 'at', ev.occurred_at, 'lead_id', ev.lead_id,
                                          'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = ev.partner_id),
                                          'detail', left(coalesce(ev.payload ->> 'error', ev.payload ->> 'reason', ev.payload ->> 'why', ev.payload::text), 200)) order by ev.occurred_at desc)
        from (select * from b2b.events where (type like 'alert.%' or type = 'routing.error') and occurred_at > now() - interval '7 days'
               order by occurred_at desc limit 20) ev), '[]'),
    'alert_counts', coalesce((select jsonb_object_agg(type, n) from (select type, count(*) n from b2b.events
                                where (type like 'alert.%' or type = 'routing.error') and occurred_at > now() - interval '7 days' group by 1) x), '{}'),
    'partners', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status, 'live', b2b.is_live('partner:' || p.id),
                                          'daily_cap', p.daily_cap, 'paused_reason', p.paused_reason, 'auto_paused_at', p.auto_paused_at,
                                          'today', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.created_at >= v_today),
                                          'accepted_7d', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.status = 'accepted'
                                                            and a.accepted_at > now() - interval '7 days'),
                                          'duplicates_7d', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.status = 'duplicate'
                                                              and a.created_at > now() - interval '7 days'),
                                          'lost_in_grace', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.lost_at is not null
                                                              and a.lost_revived_at is null and a.status in ('pushed', 'accepted')),
                                          'failing', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.status in ('queued', 'pushing')
                                                        and a.push_attempts > 0 and a.last_error is not null),
                                          'failed_24h', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.status = 'failed'
                                                           and a.updated_at > now() - interval '1 day'),
                                          'last_event_at', (select max(received_at) from b2b.partner_events pe where pe.partner_id = p.id))
                       order by b2b.is_live('partner:' || p.id) desc, coalesce(p.display_name, p.name))
        from b2b.partners p where p.status <> 'closed'), '[]'),
    -- the pool: a cheap total; the wait kinds only over leads touched in the last 3 days (a chat or inactivity wait is never older)
    'pool', (select jsonb_build_object(
               'total', (select count(*) from public.student_leads l
                          where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
                            and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
                            and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)),
               'chatting', count(*) filter (where x.r -> 'wait' ->> 'kind' = 'chatting'),
               'waiting_inactivity', count(*) filter (where x.r -> 'wait' ->> 'kind' = 'inactivity'),
               'awaiting_consent', count(*) filter (where x.r -> 'wait' ->> 'kind' = 'consent'))
               from (select b2b.lead_readiness(l) r from public.student_leads l
                      where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
                        and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
                        and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)
                        and greatest(l.created_at, l.updated_at, l.last_activity_at, l.last_agent_message_at) > now() - interval '3 days'
                      order by l.created_at desc limit 2000) x),
    'switches', coalesce((select jsonb_object_agg(scope, live) from b2b.live_switches where scope not like 'partner:%'), '{}'),
    'live_partners', (select count(*) from b2b.partners p where p.status = 'active' and b2b.is_live('partner:' || p.id)),
    'has_partners', exists (select 1 from b2b.partners where status <> 'closed'),
    'has_offers', exists (select 1 from b2b.partner_programmes where valid_to is null));
end $fn$;

-- ======================================================================================================== (22) leads_export
create or replace function b2b.leads_export(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_where  text;
  v_masked boolean := coalesce((p ->> 'masked')::boolean, false);
  v_rows   jsonb;
  v_a      jsonb := b2b.actor();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  v_where := b2b.lead_filter_sql(p);
  execute format($q$
    select coalesce(jsonb_agg(r order by r.created_at desc), '[]'::jsonb) from (
      select l.id, l.created_at, l.student_name,
             case when %2$L::boolean then '******' || right(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), 4) else l.whatsapp_number end as phone,
             case when %2$L::boolean and position('@' in coalesce(l.email_id, '')) > 0 then left(l.email_id, 1) || '***@' || split_part(l.email_id, '@', 2) else l.email_id end as email,
             l.city, l.state, l.interested_course, l.interested_specialization, l.program_level, l.study_mode_preference,
             l.highest_qualification, l.lead_status, l.stage, l.lead_source, l.channel, l.campaign, l.utm_source, l.utm_medium, l.utm_campaign,
             l.destination_type, l.partner_id, l.consent_partner_share_at, l.last_activity_at,
             (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) as is_test,
             %3$s
        from public.student_leads l
        %4$s
       where %1$s
       order by l.created_at desc
       limit 10000
    ) r
  $q$, v_where, v_masked, b2b.lead_a3_columns_sql(), b2b.lead_a3_joins_sql()) into v_rows;

  insert into b2b.lead_exports (actor_id, filters, row_count, masked) values (v_a ->> 'id', p, jsonb_array_length(v_rows), v_masked);
  perform b2b.log_event('leads.exported', null, null, null, jsonb_build_object('rows', jsonb_array_length(v_rows), 'masked', v_masked));
  return v_rows;
end $fn$;

-- ======================================================================================================== (23) alert_feed
create or replace function b2b.alert_feed(p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', ev.id, 'type', ev.type, 'at', ev.occurred_at,
                                                       'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = ev.partner_id),
                                                       'partner_id', ev.partner_id, 'lead_id', ev.lead_id, 'allocation_id', ev.allocation_id, 'payload', ev.payload)
                                    order by ev.occurred_at desc)
                     from (select * from b2b.events ev
                            where ev.type like 'alert.%' or ev.type in ('routing.error', 'lead.reenquired', 'lead.partner_barred')
                            order by ev.occurred_at desc limit least(greatest(coalesce(p_limit, 20), 1), 100)) ev), '[]');
end $fn$;

-- ======================================================================================================== (24) settings_history
/* Version history with a diff per key (C62). Never exposed through ai_tool: the 'engine' value holds blocked_phones. */
create or replace function b2b.settings_history(p_key text, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_key is null or p_key not in ('engine', 'engine_policy', 'ml', 'ai', 'attribution', 'lost_nurture_delays', 'golive_acks') then
    raise exception 'unknown setting' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'version', v.version, 'at', v.created_at, 'actor', v.actor_type, 'actor_id', v.actor_id, 'ai_run_id', v.ai_run_id, 'reason', v.reason,
             'changed', coalesce((select jsonb_object_agg(k, jsonb_build_object('from', prev.value -> k, 'to', v.value -> k))
                                    from jsonb_object_keys(v.value || coalesce(prev.value, '{}'::jsonb)) k
                                   where (v.value -> k) is distinct from (prev.value -> k)), '{}'::jsonb))
           order by v.version desc)
      from (select * from b2b.settings_versions s where s.key = p_key order by s.version desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) v
      left join lateral (select pv.value from b2b.settings_versions pv where pv.key = v.key and pv.version < v.version order by pv.version desc limit 1) prev on true), '[]');
end $fn$;

-- ======================================================================================================== (25) routing_decisions
/* The searchable decision log (C62): q = a lead id (1-9 digits), a phone (10-13 digits) or part of a name; filters partner_id,
   segment (3- or 4-part), reason, stage, how, destination; keyset paging on before_id. */
create or replace function b2b.routing_decisions(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_q text := left(trim(coalesce(p ->> 'q', '')), 100);
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 50), 1), 200);
  v_rows jsonb;
  v_ids bigint[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_q <> '' then
    if v_q ~ '^[0-9]{1,9}$' then
      v_ids := array[v_q::bigint];
    elsif v_q ~ '^[0-9]{10,13}$' then
      select coalesce(array_agg(l.id), '{}') into v_ids from public.student_leads l
       where regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') in (v_q, '91' || right(v_q, 10));
    else
      select coalesce(array_agg(l.id), '{}') into v_ids
        from (select l.id from public.student_leads l where position(lower(v_q) in lower(coalesce(l.student_name, ''))) > 0 limit 500) l;
    end if;
  end if;
  select coalesce(jsonb_agg(b2b.decision_json(d) - 'candidates' - 'excluded' - 'rules' - 'interest' - 'features' - 'shadow' order by d.id desc), '[]')
    into v_rows
    from (select * from b2b.engine_decisions d
           where (v_ids is null or d.lead_id = any (v_ids))
             and (nullif(p ->> 'partner_id', '') is null or d.winner_partner_id = (p ->> 'partner_id')::bigint)
             and (nullif(p ->> 'segment', '') is null or d.segment = p ->> 'segment' or d.segment_exact = p ->> 'segment' or d.eval_segment = p ->> 'segment')
             and (nullif(p ->> 'reason', '') is null or d.reason = p ->> 'reason')
             and (nullif(p ->> 'stage', '') is null or d.stage = p ->> 'stage')
             and (nullif(p ->> 'how', '') is null or d.how = p ->> 'how')
             and (nullif(p ->> 'destination', '') is null or d.destination_type = p ->> 'destination')
             and (nullif(p ->> 'before_id', '') is null or d.id < (p ->> 'before_id')::bigint)
             and (not coalesce((p ->> 'hide_test')::boolean, false) or not d.is_test)
           order by d.id desc limit v_limit) d;
  return jsonb_build_object('rows', v_rows,
                            'next_before_id', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $fn$;

-- ======================================================================================================== (26) partner_detail
/* The partner page (m4b) plus the Addendum 3 factors (effort with has_activity, SLA adherence and factor, per segment and
   partner-wide, from the base statistics) and the auto-pause reason (web group W9). */
create or replace function b2b.partner_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  p b2b.partners;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_id;
  if p.id is null then return null; end if;
  return jsonb_build_object(
    'partner', b2b.partner_json(p),
    'checklist', b2b.partner_checklist(p),
    'leads_month', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'leads_total', (select count(*) from public.student_leads l where l.partner_id = p.id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', ev.occurred_at, 'type', ev.type, 'actor', ev.actor_type, 'payload', ev.payload) order by ev.occurred_at desc)
                          from (select * from b2b.events where partner_id = p.id order by occurred_at desc limit 30) ev), '[]'),
    'auto_pause', case when p.auto_paused_at is not null then jsonb_build_object('reason', p.paused_reason, 'at', p.auto_paused_at, 'active', p.status = 'paused') end,
    'factors', (
      select jsonb_build_object(
               'sla_adherence', (select x.sla_adherence from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id order by x.refreshed_at desc nulls last, x.n_received desc limit 1),
               'sla_factor', (select x.sla_factor from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id order by x.refreshed_at desc nulls last, x.n_received desc limit 1),
               'sla_met', (select x.sla_met from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id order by x.refreshed_at desc nulls last, x.n_received desc limit 1),
               'sla_total', (select x.sla_total from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id order by x.refreshed_at desc nulls last, x.n_received desc limit 1),
               'effort_factor', (select case when sum(x.n_received) > 0 then round(sum(x.effort_factor * x.n_received) / sum(x.n_received), 4) else round(avg(x.effort_factor), 4) end
                                   from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id and not x.is_rollup
                                    and cardinality(string_to_array(x.segment, '|')) = 3),
               'has_activity', coalesce((select bool_or(x.has_activity) from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id), false),
               'n_received', coalesce((select sum(x.n_received) from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id and not x.is_rollup
                                        and cardinality(string_to_array(x.segment, '|')) = 3), 0),
               'stats_at', (select max(x.refreshed_at) from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id),
               'segments', coalesce((select jsonb_agg(jsonb_build_object('segment', x.segment, 'auto_stage', s.auto_stage, 'n_received', x.n_received, 'first_lead_at', x.first_lead_at,
                                                                         'n_matured_c', x.n_matured_c, 'leads_30d', x.leads_30d, 'p_hat', x.p_hat,
                                                                         'effort_factor', x.effort_factor, 'has_activity', x.has_activity, 'effort_detail', x.effort_detail,
                                                                         'sla_adherence', x.sla_adherence, 'sla_factor', x.sla_factor, 'refund_rate', x.refund_rate)
                                                      order by x.n_received desc, x.segment)
                                       from (select * from b2b.partner_segment_stats x where x.variant = 'base' and x.partner_id = p.id and not x.is_rollup
                                                and cardinality(string_to_array(x.segment, '|')) = 3 order by x.n_received desc, x.segment limit 20) x
                                       left join b2b.segment_stats s on s.variant = 'base' and s.segment = x.segment), '[]'))));
end $fn$;

-- ======================================================================================================== grants
revoke execute on function b2b.setting_num(jsonb, numeric, numeric, text), b2b.setting_bool(jsonb, text), b2b.segment_interest(text),
                           b2b.lead_a3_joins_sql(), b2b.lead_a3_columns_sql(), b2b.segment_view(text), b2b.segment_mode(text)
  from public, anon, authenticated;
grant execute on function b2b.setting_num(jsonb, numeric, numeric, text), b2b.setting_bool(jsonb, text), b2b.segment_interest(text),
                          b2b.lead_a3_joins_sql(), b2b.lead_a3_columns_sql(), b2b.segment_view(text), b2b.segment_mode(text)
  to service_role;
revoke execute on function b2b.reroute_check(bigint), b2b.reroute_lead(bigint, text, text, text), b2b.reroute_many(bigint[], text, text, text),
                           b2b.route_to_partners_many(bigint[], text), b2b.route_test_lead(bigint, text, text), b2b.lost_delays_save(jsonb, text),
                           b2b.settings_history(text, int), b2b.routing_decisions(jsonb)
  from public, anon;
grant execute on function b2b.reroute_check(bigint), b2b.reroute_lead(bigint, text, text, text), b2b.reroute_many(bigint[], text, text, text),
                          b2b.route_to_partners_many(bigint[], text), b2b.route_test_lead(bigint, text, text), b2b.lost_delays_save(jsonb, text),
                          b2b.settings_history(text, int), b2b.routing_decisions(jsonb)
  to authenticated, service_role;
-- replaced Admin RPCs keep their grants (create or replace); restated for clarity
revoke execute on function b2b.pass_to_crm(bigint[], text), b2b.routing_rule_save(jsonb), b2b.engine_settings_save(jsonb, text), b2b.engine_policy_save(jsonb, text),
                           b2b.routing_segments(), b2b.routing_segment(text), b2b.segment_policy_save(text, jsonb, text),
                           b2b.partner_weight_save(bigint, numeric, timestamptz, text), b2b.decision_replay(bigint), b2b.lead_routing(bigint),
                           b2b.leads_list(jsonb), b2b.leads_facets(jsonb), b2b.routing_overview(), b2b.pool_overview(text), b2b.command_center(),
                           b2b.leads_export(jsonb), b2b.alert_feed(int), b2b.partner_detail(bigint)
  from public, anon;
grant execute on function b2b.pass_to_crm(bigint[], text), b2b.routing_rule_save(jsonb), b2b.engine_settings_save(jsonb, text), b2b.engine_policy_save(jsonb, text),
                          b2b.routing_segments(), b2b.routing_segment(text), b2b.segment_policy_save(text, jsonb, text),
                          b2b.partner_weight_save(bigint, numeric, timestamptz, text), b2b.decision_replay(bigint), b2b.lead_routing(bigint),
                          b2b.leads_list(jsonb), b2b.leads_facets(jsonb), b2b.routing_overview(), b2b.pool_overview(text), b2b.command_center(),
                          b2b.leads_export(jsonb), b2b.alert_feed(int), b2b.partner_detail(bigint)
  to authenticated, service_role;
revoke execute on function b2b.lead_filter_sql(jsonb) from public, anon, authenticated;
grant execute on function b2b.lead_filter_sql(jsonb) to service_role;
