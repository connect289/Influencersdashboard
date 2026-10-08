-- M30b: review fixes to already-applied migrations (review of 7 Oct 2026).
--   F195 (spec B14.3 "Grid or list of partners with logo, status, health and this month's NCPL"): b2b.partners_list()
--     (from m4b) gains 'ncpl_month', the expected net commission per lead for the partner's leads this month (IST):
--     the latest stats_snapshots NCPL of the last 7 IST days for each segment the partner received leads in, weighted by
--     this month's non-test pushed / accepted / closed partner allocations per segment. Segments with no NCPL in that
--     window are left out of the weights; null when no segment has one. The rest of the m4b body is unchanged.
-- Sorts after m30a. Apply to staging now; to production in the promotion window right after m30a and before m31a0.
-- Connector-safe: create or replace only, no destructive statements. Re-applying it is harmless.

create or replace function b2b.partners_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(b2b.partner_json(p) || jsonb_build_object(
             'leads_today', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
             'leads_month', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
             'ncpl_month', (select round(sum(s.ncpl_inr * m.n) / nullif(sum(m.n) filter (where s.ncpl_inr is not null), 0), 2)
                              from (select a.segment, count(*) n from b2b.allocations a
                                     where a.partner_id = p.id and a.destination_type = 'partner' and not a.is_test
                                       and a.status in ('pushed', 'accepted', 'closed')
                                       and a.created_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'
                                     group by a.segment) m
                              left join lateral (select x.ncpl_inr from b2b.stats_snapshots x
                                                  where x.partner_id = p.id and x.segment = m.segment
                                                    and x.day >= (now() at time zone 'Asia/Kolkata')::date - 7
                                                  order by x.day desc limit 1) s on true),
             'checklist_done', (select count(*) from jsonb_array_elements(b2b.partner_checklist(p)) c where (c ->> 'done')::boolean),
             'checklist_total', jsonb_array_length(b2b.partner_checklist(p)))
           order by (p.status = 'closed'), lower(coalesce(p.display_name, p.name)))
      from b2b.partners p), '[]'::jsonb);
end $fn$;

revoke execute on function b2b.partners_list() from public, anon;
grant execute on function b2b.partners_list() to authenticated, service_role;
