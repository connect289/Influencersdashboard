-- M34a (30 Oct 2026, audit): internal definer helpers are internal again, and reroute_check checks its caller.
--   b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint), b2b.is_live(text), b2b.mapping_ready(bigint): EXECUTE revoked from
--   public, anon and authenticated (service_role keeps it). Every caller is a SECURITY DEFINER function owned by postgres
--   (leads_list / leads_export / leads_export_page through lead_a3_columns_sql, api_referral_outcomes, partner_json and
--   partner_checklist via their definer callers, mapping_overview, the ticks), so nothing that uses them changes; the web
--   app never calls them.
--   b2b.reroute_check(bigint): the web app calls it as the signed-in Admin (lib/routing-data.ts), so it keeps its grant and
--   now starts with the b2b.is_admin() check every other Admin read has; its database callers are Admin-only already.
-- Re-appliable. Checked by supabase/tests/test_m34_audit_fixes.sql.

revoke execute on function b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint), b2b.is_live(text), b2b.mapping_ready(bigint)
  from public, anon, authenticated;
grant execute on function b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint), b2b.is_live(text), b2b.mapping_ready(bigint)
  to service_role;

create or replace function b2b.reroute_check(p_allocation_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_fa timestamptz;
  v_br jsonb;
  v_contact timestamptz;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
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
revoke execute on function b2b.reroute_check(bigint) from public, anon;
grant execute on function b2b.reroute_check(bigint) to authenticated, service_role;

-- rollback (restores the 30 Oct grants and the unguarded reroute_check; not recommended):
--   grant execute on function b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint), b2b.is_live(text), b2b.mapping_ready(bigint)
--     to authenticated;
--   then re-run the create or replace function b2b.reroute_check(bigint) of m31l_a3_admin_reads.sql (lines 133 to 165),
--   which is this definition without its first line ("if not b2b.is_admin() then raise ...").
