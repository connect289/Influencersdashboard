-- B2C CRM b47 (audit of 30 Oct 2026): qualify_record, the support ticket check (support_may_see) and view_get admit only
-- staff with a checked session; insights_candidates, which only the insights job calls, is for the service role only.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

/* Staff record the details (the Admin, or the counsellor given the To qualify task). */
create or replace function b2c.qualify_record(p_lead bigint, p_answers jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid();
begin
  if not (coalesce(b2c.my_role() = 'admin', false)
          or (b2c.is_staff() and exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.kind = 'qualify' and t.status = 'open' and t.owner_id = me))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return b2c.qualify_apply(p_lead, p_answers, 'staff', me);
end $f$;

create or replace function b2c.support_may_see(p_ticket bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce(b2c.my_role() = 'admin', false)
      or (b2c.is_staff() and exists (select 1 from b2c.support_tickets t where t.id = p_ticket and t.created_by = b2c.uid()))
$f$;

/* Opening a view by link: only if it is the person's, standard, or shared with their role; staff only. */
create or replace function b2c.view_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v b2c.saved_views;
begin
  select * into v from b2c.saved_views where id = p_id and hidden_at is null;
  if v.id is null or not coalesce(b2c.is_staff() and (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = b2c.my_role())), false) then
    raise exception 'this view is not shared with you' using errcode = '42501';
  end if;
  return to_jsonb(v) || jsonb_build_object('mine', v.owner_id = me);
end $f$;

revoke execute on function b2c.insights_candidates(uuid) from public, anon, authenticated;
grant execute on function b2c.insights_candidates(uuid) to service_role;

-- rollback (restores the b39, b31, b40 and b22 definitions and grants):
-- create or replace function b2c.qualify_record(p_lead bigint, p_answers jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
-- declare me uuid := b2c.uid();
-- begin
--   if not (b2c.my_role() = 'admin' or exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.kind = 'qualify' and t.status = 'open' and t.owner_id = me)) then
--     raise exception 'not allowed' using errcode = '42501';
--   end if;
--   return b2c.qualify_apply(p_lead, p_answers, 'staff', me);
-- end $f$;
-- create or replace function b2c.support_may_see(p_ticket bigint) returns boolean language sql stable security definer set search_path = '' as $f$
--   select b2c.my_role() = 'admin' or exists (select 1 from b2c.support_tickets t where t.id = p_ticket and t.created_by = b2c.uid())
-- $f$;
-- create or replace function b2c.view_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
-- declare me uuid := b2c.uid(); v b2c.saved_views;
-- begin
--   select * into v from b2c.saved_views where id = p_id and hidden_at is null;
--   if v.id is null or not (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = b2c.my_role())) then
--     raise exception 'this view is not shared with you' using errcode = '42501';
--   end if;
--   return to_jsonb(v) || jsonb_build_object('mine', v.owner_id = me);
-- end $f$;
-- grant execute on function b2c.insights_candidates(uuid) to authenticated;
