-- =====================================================================================================================
-- Rollback of web17 (20261113170000_web17_privacy_requests.sql). Restores the two functions web17 replaced (verbatim
-- from 20261017100800_web9_admin.sql, which is what production ran before web17), then removes what web17 added: the
-- admin functions web_admin_privacy_fulfil / _export / _system, web_outbox_scrub, the helpers web_privacy_*, and the
-- columns web_deletion_requests.systems and .leads (the checklists recorded meanwhile go with them; the requests, their
-- status and the audit log stay). An erasure that was carried out is NOT undone: the data is gone. A confirmation email
-- still waiting in the outbox is cancelled, because the previous website version does not know that kind of job.
-- Roll the website back to the previous deployment first (the web17 admin page calls the functions dropped here).
-- Run in a transaction:
--   psql "<url>" -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261113170000_web17_privacy_requests.rollback.sql
-- =====================================================================================================================

-- web_admin_privacy_done: as in 20261017100800_web9_admin.sql
create or replace function public.web_admin_privacy_done(p_id bigint, p_status text, p_note text, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_before jsonb;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status not in ('done', 'rejected') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  select to_jsonb(r) into v_before from public.web_deletion_requests r where id = p_id;
  update public.web_deletion_requests set status = p_status, processed_at = now(), processed_by = p_actor_email, note = left(p_note, 500) where id = p_id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before, after)
  values (p_actor, p_actor_email, 'privacy.' || p_status, 'web_deletion_requests', p_id::text, v_before, jsonb_build_object('status', p_status, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

-- web_admin_privacy_requests: as in 20261017100800_web9_admin.sql
create or replace function public.web_admin_privacy_requests()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.requested_at desc), '[]') from public.web_deletion_requests r
$$;

update public.web_outbox set status = 'done', processed_at = now(), locked_until = null, last_error = 'cancelled: web17 rolled back',
       payload = jsonb_build_object('kind', 'privacy_done', 'erased', true)
 where kind = 'email_confirmation' and payload ->> 'kind' = 'privacy_done' and status <> 'done';

drop function if exists public.web_admin_privacy_fulfil(bigint, uuid, text, text);
drop function if exists public.web_admin_privacy_export(bigint, uuid, text, text);
drop function if exists public.web_admin_privacy_system(bigint, text, text, text, uuid, text, text);
drop function if exists public.web_outbox_scrub(bigint);
drop function if exists public.web_privacy_close(bigint, uuid, text);
drop function if exists public.web_privacy_erase(uuid);
drop function if exists public.web_privacy_export_doc(uuid);
drop function if exists public.web_privacy_counts(uuid);
drop function if exists public.web_privacy_leads(uuid);
drop function if exists public.web_privacy_requester_problem(uuid, text);
alter table public.web_deletion_requests drop column if exists systems;
alter table public.web_deletion_requests drop column if exists leads;
