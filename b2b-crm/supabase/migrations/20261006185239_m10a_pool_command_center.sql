-- M10a: the pre-routing pool (spec B13, "leads not yet routable, grouped by what is missing, with counts and age") and
-- the basic Command Center (KPIs, 7-day flow, lead stream, alerts, partner health). Reads only; both re-check
-- b2b.is_admin(). Test leads appear in the pool under their own group and are left out of every Command Center number.

/* Why a lead without a destination is still waiting, and what will happen to it at its decision point. */
create or replace function b2b.pool_lead(l public.student_leads, p_routing_on boolean)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  r jsonb := b2b.lead_readiness(l);
  v_group text;
begin
  v_group := case
    when (r ->> 'is_test')::boolean then 'test'
    when coalesce(l.is_opted_out, false) then 'opted_out'
    when r -> 'missing' ? 'still chatting with Witty' then 'chatting'
    when l.created_at <= now() - interval '90 days' then 'too_old'
    when not p_routing_on then 'routing_off'
    else 'due' end;
  return jsonb_build_object('group', v_group, 'class', r ->> 'class', 'class_reason', r ->> 'class_reason',
                            'not_qualified', coalesce(r -> 'not_qualified', '[]'), 'paid', coalesce((r ->> 'paid')::boolean, false),
                            'outlook', case
                              when r ->> 'class' in ('junk', 'mismatch') then 'not_passed'
                              when coalesce((r ->> 'paid')::boolean, false) then 'b2c_sales'
                              when r ->> 'class' = 'unqualified' then 'b2c_nurture'
                              else 'partners' end);
end $$;

/* The pool: every lead with no destination yet (not deleted, merged or held back as not passed). */
create or replace function b2b.pool_overview(p_group text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_on boolean := b2b.is_live('routing') and coalesce((e ->> 'enabled')::boolean, true) and not coalesce((e ->> 'kill_switch')::boolean, false);
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
      'idle_minutes', coalesce((e ->> 'witty_idle_minutes')::int, 30),
      'total', (select count(*) from pool),
      'groups', coalesce((select jsonb_object_agg(grp, jsonb_build_object('n', n, 'oldest', oldest, 'ages', jsonb_build_array(h1, d1, d7, older))) from g), '{}'),
      'outlook', coalesce((select jsonb_object_agg(o, n) from (select p ->> 'outlook' o, count(*) n from pool where p ->> 'group' <> 'test' group by 1) x), '{}'),
      'missing', coalesce((select jsonb_object_agg(m, n) from (select m, count(*) n from pool, jsonb_array_elements_text(p -> 'not_qualified') m
                                                               where p ->> 'group' <> 'test' group by 1) x), '{}'),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', student_name, 'source', lead_source,
                                                            'course', coalesce(nullif(interested_course, ''), field_of_interest), 'status', lead_status,
                                                            'created_at', created_at, 'last_seen', last_seen) || p order by created_at)
                        from (select * from pool where p_group is null or p ->> 'group' = p_group order by created_at limit 200) x), '[]')));
end $$;

/* The Command Center: today's numbers against yesterday's, the 7-day flow, the lead stream, alerts and partner health. */
create or replace function b2b.command_center()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_tz text := 'Asia/Kolkata';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_yday timestamptz := v_today - interval '1 day';
  v_month timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_since timestamptz := now() - interval '1 day';  -- yesterday's figures cover the same hours as today's so far
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
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
        'accepted_month', (select count(*) from al where status = 'accepted' and accepted_at >= v_month))),
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
      select jsonb_agg(jsonb_build_object('id', e.id, 'type', e.type, 'at', e.occurred_at, 'lead_id', e.lead_id, 'lead_name', l.student_name,
                                          'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
                                          'detail', coalesce(e.payload ->> 'reason', e.payload ->> 'reference', e.payload ->> 'channel')) order by e.occurred_at desc)
        from (select * from b2b.events
               where type in ('lead.routed', 'lead.rerouted', 'b2c.lead_handed_off', 'lead.pushed', 'lead.accepted', 'lead.duplicate',
                              'lead.push_failed', 'lead.not_passed', 'lead.route_to_partners', 'notification.sent')
                 and (lead_id is null or not exists (select 1 from public.student_leads t where t.id = lead_id
                                                       and (coalesce(t.is_test, false) or b2b.is_test_phone(t.whatsapp_number))))
               order by occurred_at desc limit 25) e
        left join public.student_leads l on l.id = e.lead_id), '[]'),
    'alerts', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'type', e.type, 'at', e.occurred_at, 'lead_id', e.lead_id,
                                          'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
                                          'detail', left(coalesce(e.payload ->> 'error', e.payload ->> 'reason', e.payload::text), 200)) order by e.occurred_at desc)
        from (select * from b2b.events where (type like 'alert.%' or type = 'routing.error') and occurred_at > now() - interval '7 days'
               order by occurred_at desc limit 20) e), '[]'),
    'alert_counts', coalesce((select jsonb_object_agg(type, n) from (select type, count(*) n from b2b.events
                                where (type like 'alert.%' or type = 'routing.error') and occurred_at > now() - interval '7 days' group by 1) x), '{}'),
    'partners', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status, 'live', b2b.is_live('partner:' || p.id),
                                          'daily_cap', p.daily_cap,
                                          'today', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.created_at >= v_today),
                                          'accepted_7d', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.status = 'accepted'
                                                            and a.accepted_at > now() - interval '7 days'),
                                          'duplicates_7d', (select count(*) from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.status = 'duplicate'
                                                              and a.created_at > now() - interval '7 days'),
                                          'failing', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.status in ('queued', 'pushing')
                                                        and a.push_attempts > 0 and a.last_error is not null),
                                          'failed_24h', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.status = 'failed'
                                                           and a.updated_at > now() - interval '1 day'),
                                          'last_event_at', (select max(received_at) from b2b.partner_events pe where pe.partner_id = p.id))
                       order by b2b.is_live('partner:' || p.id) desc, coalesce(p.display_name, p.name))
        from b2b.partners p where p.status <> 'closed'), '[]'),
    'pool', (select jsonb_build_object('total', count(*), 'chatting', count(*) filter (where r -> 'missing' ? 'still chatting with Witty'))
               from (select b2b.lead_readiness(l) r from public.student_leads l
                      where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
                        and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
                        and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)
                      order by l.created_at desc limit 5000) x),
    'switches', coalesce((select jsonb_object_agg(scope, live) from b2b.live_switches where scope not like 'partner:%'), '{}'),
    'live_partners', (select count(*) from b2b.partners p where p.status = 'active' and b2b.is_live('partner:' || p.id)),
    'has_partners', exists (select 1 from b2b.partners where status <> 'closed'),
    'has_offers', exists (select 1 from b2b.partner_programmes where valid_to is null));
end $$;

revoke execute on function b2b.pool_lead(public.student_leads, boolean) from public, anon, authenticated;
grant execute on function b2b.pool_lead(public.student_leads, boolean) to service_role;
revoke execute on function b2b.pool_overview(text), b2b.command_center() from public, anon;
grant execute on function b2b.pool_overview(text), b2b.command_center() to authenticated, service_role;
