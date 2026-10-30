-- B2C CRM b48 (audit of 30 Oct 2026): a sales head's Follow-ups list is their team's, as the Leads list, the pipeline
-- and the page's own picker already are (b2c.in_my_team); the Admin, counsellors and a sales head without a team are
-- unchanged.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

/* The Follow-ups page (B8.2). The Admin may pass another person (or null for everyone); a sales head, someone in their team (or null for the team). */
create or replace function b2c.followups(p_bucket text, p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); v_head boolean := b2c.my_role() = 'sales_head'; v_user uuid;
        d1 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day';
begin
  v_user := case when b2c.my_role() in ('admin', 'sales_head') then p_user else me end;
  if v_head and v_user is not null and not b2c.in_my_team(v_user) then raise exception 'choose someone in your team' using errcode = '42501'; end if;
  if p_bucket = 'not_worked' then
    return (select coalesce(jsonb_agg(jsonb_build_object('lead', to_jsonb(v)) order by v.sla_due_at nulls last), '[]') from b2c.leads_v v
             where (v_user is null or v.owner_id = v_user) and (not v_head or b2c.in_my_team(v.owner_id))
               and v.status = 'active' and v.contact_attempts = 0 and v.stage_id = 1);
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('task', to_jsonb(t), 'lead', to_jsonb(v)) order by t.due_at), '[]')
            from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id
           where (v_user is null or t.owner_id = v_user) and (not v_head or b2c.in_my_team(t.owner_id)) and t.status = 'open'
             and case p_bucket when 'overdue' then t.due_at < now() when 'today' then t.due_at >= now() and t.due_at < d1 else t.due_at >= d1 end);
end $f$;

-- rollback (restores the b5 definition):
-- create or replace function b2c.followups(p_bucket text, p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
-- declare me uuid := b2c.require('work_leads'); v_user uuid; d1 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day';
-- begin
--   v_user := case when b2c.my_role() in ('admin', 'sales_head') then p_user else me end;
--   if p_bucket = 'not_worked' then
--     return (select coalesce(jsonb_agg(jsonb_build_object('lead', to_jsonb(v)) order by v.sla_due_at nulls last), '[]') from b2c.leads_v v
--              where (v_user is null or v.owner_id = v_user) and v.status = 'active' and v.contact_attempts = 0 and v.stage_id = 1);
--   end if;
--   return (select coalesce(jsonb_agg(jsonb_build_object('task', to_jsonb(t), 'lead', to_jsonb(v)) order by t.due_at), '[]')
--             from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id
--            where (v_user is null or t.owner_id = v_user) and t.status = 'open'
--              and case p_bucket when 'overdue' then t.due_at < now() when 'today' then t.due_at >= now() and t.due_at < d1 else t.due_at >= d1 end);
-- end $f$;
