-- M9c: the lead drawer's Routing tab lists the student's notifications (channel, status, why not sent). Recipients
-- are not repeated here: the drawer already shows the lead's contact details to the Admin.

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
    'not_passed', (select to_jsonb(n) from b2b.not_passed n where n.lead_id = l.id),
    'flags', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from b2b.review_flags f where f.lead_id = l.id), '[]'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) order by d.created_at desc) from b2b.engine_decisions d where d.lead_id = l.id), '[]'),
    'allocations', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id))
                                              order by a.created_at desc) from b2b.allocations a where a.lead_id = l.id), '[]'),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'channel', n.channel, 'kind', n.kind, 'language', n.language, 'status', n.status,
                                                                   'error', n.error, 'scheduled_for', n.scheduled_for, 'sent_at', n.sent_at, 'created_at', n.created_at,
                                                                   'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = n.partner_id))
                                                order by n.created_at desc, n.channel desc) from b2b.student_notifications n where n.lead_id = l.id), '[]'));
end $$;
