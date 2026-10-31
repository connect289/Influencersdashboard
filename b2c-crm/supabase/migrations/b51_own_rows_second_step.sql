-- B2C CRM b51 (audit of 30 Oct 2026): a person's own rows (tasks, notifications, alerts, schedules, dashboards, exports,
-- enrolments, commission lines, targets, snippets and their user row) need the checked second sign-in step, like every
-- other staff path. me(), device_trust_check and mfa_verify stay open before it: the sign-in steps use them.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

-- ---------- functions that answer from the caller's own rows ----------
create or replace function b2c.alerts_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object('label', m.label) order by a.id), '[]') from b2c.metric_alerts a join b2c.metric_defs m on m.key = a.metric
   where a.user_id = b2c.uid() and (select b2c.is_staff())
$f$;

create or replace function b2c.calendar_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('on', u.calendar_sync, 'error', u.calendar_error, 'synced_at', u.calendar_synced_at,
           'pending', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.state = 'pending'),
           'events', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.event_id is not null))
    from b2c.users u where u.user_id = b2c.uid() and (select b2c.is_staff())
$f$;

create or replace function b2c.dashboard_archive(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.dashboards set archived_at = now()
   where id = p_id and archived_at is null and ((owner_id = b2c.uid() and b2c.is_staff()) or (owner_id is null and b2c.can('settings')));
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $f$;

create or replace function b2c.dashboard_may_see(p_id bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from b2c.dashboards d where d.id = p_id and d.archived_at is null
                  and ((d.owner_id = b2c.uid() and b2c.is_staff()) or (d.owner_id is null and b2c.an_group(b2c.my_role()) = any (d.roles)) or b2c.can('settings')))
$f$;

create or replace function b2c.exports_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'format', format, 'status', status, 'rows', rows, 'created_at', created_at, 'expires_at', expires_at, 'error', error) order by id desc), '[]')
    from (select * from b2c.exports where user_id = b2c.uid() and (select b2c.is_staff()) order by id desc limit 20) x
$f$;

/* Counts for one person. Without a JWT subject (the jobs) any person; staff: themselves, or anyone for the Admin and a sales head. */
create or replace function b2c.followup_counts(p_user uuid) returns jsonb language sql stable security definer set search_path = '' as $f$
  with who as (select case when b2c.uid() is null then p_user
                           when not b2c.is_staff() then null
                           when p_user = b2c.uid() or b2c.my_role() in ('admin', 'sales_head') then p_user else b2c.uid() end as id),
       d as (select date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day' as d1)
  select jsonb_build_object(
    'not_worked', (select count(*) from b2c.leads_state s, who where s.owner_id = who.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
    'overdue', (select count(*) from b2c.tasks t, who where t.owner_id = who.id and t.status = 'open' and t.due_at < now()),
    'today', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= now() and t.due_at < d.d1),
    'upcoming', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= d.d1))
$f$;

create or replace function b2c.leaderboard_opt(p_visible boolean) returns void language sql security definer set search_path = '' as $f$
  update b2c.users set leaderboard_visible = coalesce(p_visible, false), updated_at = now() where user_id = b2c.uid() and is_active and (select b2c.is_staff())
$f$;

create or replace function b2c.nav_counts() returns jsonb language sql stable security definer set search_path = '' as $f$
  with me as (select case when b2c.my_role() is not null then b2c.uid() end as id, b2c.my_role() as role)
  select jsonb_build_object(
    'not_worked', (select count(*) from b2c.leads_state s, me where s.owner_id = me.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
    'overdue', (select count(*) from b2c.tasks t, me where t.owner_id = me.id and t.status = 'open' and t.due_at < now()),
    'unread_alerts', (select count(*) from b2c.notifications n, me where n.user_id = me.id and n.read_at is null),
    'unread_inbox', (select count(*) from b2c.wa_conversations c cross join me left join b2c.leads_state s on s.lead_id = c.lead_id
                      where c.unread > 0 and (me.role in ('admin', 'marketing') or s.owner_id = me.id)))
$f$;

create or replace function b2c.notifications_mine(p_limit integer default 30) returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('unread', (select count(*) from b2c.notifications n where n.user_id = b2c.uid() and n.read_at is null and (select b2c.is_staff())),
    'items', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]')
                from (select * from b2c.notifications n where n.user_id = b2c.uid() and (select b2c.is_staff()) order by n.created_at desc limit p_limit) n))
$f$;

create or replace function b2c.notifications_read(p_ids bigint[] default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.notifications set read_at = now() where user_id = b2c.uid() and read_at is null and (p_ids is null or id = any (p_ids)) and (select b2c.is_staff())
$f$;

create or replace function b2c.phone_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('mobile', phone, 'caller_id', coalesce(caller_id, b2c.setting('telephony') ->> 'caller_id'), 'own_caller_id', caller_id is not null)
    from b2c.users where user_id = b2c.uid() and (select b2c.is_staff())
$f$;

create or replace function b2c.schedules_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('dashboard', d.name) order by s.id), '[]')
    from b2c.dashboard_schedules s join b2c.dashboards d on d.id = s.dashboard_id where s.user_id = b2c.uid() and (select b2c.is_staff())
$f$;

/* Records the browser and address of a checked session (the app calls it after the second step). */
create or replace function b2c.session_note(p_user_agent text, p_ip text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then return; end if;
  update b2c.session_checks set user_agent = coalesce(left(p_user_agent, 300), user_agent), ip = coalesce(left(p_ip, 60), ip), last_seen_at = now()
   where session_id = b2c.session_id() and user_id = b2c.uid();
  update b2c.users set first_sign_in_at = now() where user_id = b2c.uid() and first_sign_in_at is null;
end $f$;

create or replace function b2c.snippet_delete(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.snippets set deleted_at = now() where id = p_id and deleted_at is null and ((owner_id = b2c.uid() and b2c.is_staff()) or b2c.my_role() = 'admin');
  if not found then raise exception 'not your snippet' using errcode = '42501'; end if;
end $f$;

create or replace function b2c.support_attach(p_message bigint, p_files jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare m b2c.support_messages;
begin
  select * into m from b2c.support_messages where id = p_message;
  if m.id is null or m.author_id is distinct from b2c.uid() or not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) > 5 then raise exception 'at most 5 files'; end if;
  if exists (select 1 from jsonb_array_elements(p_files) f where f ->> 'path' not like 'tickets/' || m.ticket_id || '/%') then raise exception 'unknown file'; end if;
  update b2c.support_messages set attachments = attachments || p_files where id = p_message;
end $f$;

-- ---------- own-row branches of the read policies ----------
alter policy "own or money read" on b2c.commission_lines
  using ((select b2c.can('read_money')) or (counsellor_id = (select b2c.uid()) and (select b2c.is_staff())));
alter policy "own" on b2c.dashboard_schedules using (user_id = (select b2c.uid()) and (select b2c.is_staff()));
alter policy "who may see" on b2c.enrollments
  using ((select b2c.can_see(enrollments.lead_id)) or (counsellor_id = (select b2c.uid()) and (select b2c.is_staff())));
alter policy "own" on b2c.metric_alerts using (user_id = (select b2c.uid()) and (select b2c.is_staff()));
alter policy "own notifications" on b2c.notifications using (user_id = (select b2c.uid()) and (select b2c.is_staff()));
alter policy "own or team" on b2c.targets
  using ((user_id = (select b2c.uid()) and (select b2c.is_staff())) or (select b2c.can('read_all')) or (select b2c.can('read_team')));
alter policy "who may see" on b2c.tasks using ((select b2c.can_see(tasks.lead_id)) or (owner_id = (select b2c.uid()) and (select b2c.is_staff())));
alter policy "staff read users" on b2c.users using ((select b2c.is_staff()));
alter policy "snippets_read" on b2c.snippets using (deleted_at is null and (select b2c.is_staff()) and (owner_id = (select b2c.uid()) or shared));

-- rollback (restores the b7, b21, b22, b28, b30, b31, b34, b35, b37, b40 and b42 definitions and the policies' earlier expressions):
-- create or replace function b2c.alerts_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
--   select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object('label', m.label) order by a.id), '[]') from b2c.metric_alerts a join b2c.metric_defs m on m.key = a.metric where a.user_id = b2c.uid()
-- $f$;
-- create or replace function b2c.calendar_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
--   select jsonb_build_object('on', u.calendar_sync, 'error', u.calendar_error, 'synced_at', u.calendar_synced_at,
--            'pending', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.state = 'pending'),
--            'events', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.event_id is not null))
--     from b2c.users u where u.user_id = b2c.uid()
-- $f$;
-- create or replace function b2c.dashboard_archive(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
-- begin
--   update b2c.dashboards set archived_at = now() where id = p_id and archived_at is null and (owner_id = b2c.uid() or (owner_id is null and b2c.can('settings')));
--   if not found then raise exception 'not allowed' using errcode = '42501'; end if;
-- end $f$;
-- create or replace function b2c.dashboard_may_see(p_id bigint) returns boolean language sql stable security definer set search_path = '' as $f$
--   select exists (select 1 from b2c.dashboards d where d.id = p_id and d.archived_at is null
--                   and (d.owner_id = b2c.uid() or (d.owner_id is null and b2c.an_group(b2c.my_role()) = any (d.roles)) or b2c.can('settings')))
-- $f$;
-- create or replace function b2c.exports_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
--   select coalesce(jsonb_agg(jsonb_build_object('id', id, 'format', format, 'status', status, 'rows', rows, 'created_at', created_at, 'expires_at', expires_at, 'error', error) order by id desc), '[]')
--     from (select * from b2c.exports where user_id = b2c.uid() order by id desc limit 20) x
-- $f$;
-- create or replace function b2c.followup_counts(p_user uuid) returns jsonb language sql stable security definer set search_path = '' as $f$
--   with who as (select case when b2c.uid() is null or p_user = b2c.uid() or b2c.my_role() in ('admin', 'sales_head') then p_user else b2c.uid() end as id),
--        d as (select date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day' as d1)
--   select jsonb_build_object(
--     'not_worked', (select count(*) from b2c.leads_state s, who where s.owner_id = who.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
--     'overdue', (select count(*) from b2c.tasks t, who where t.owner_id = who.id and t.status = 'open' and t.due_at < now()),
--     'today', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= now() and t.due_at < d.d1),
--     'upcoming', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= d.d1))
-- $f$;
-- create or replace function b2c.leaderboard_opt(p_visible boolean) returns void language sql security definer set search_path = '' as $f$
--   update b2c.users set leaderboard_visible = coalesce(p_visible, false), updated_at = now() where user_id = b2c.uid() and is_active
-- $f$;
-- create or replace function b2c.nav_counts() returns jsonb language sql stable security definer set search_path = '' as $f$
--   with me as (select b2c.uid() as id, b2c.my_role() as role)
--   select jsonb_build_object(
--     'not_worked', (select count(*) from b2c.leads_state s, me where s.owner_id = me.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
--     'overdue', (select count(*) from b2c.tasks t, me where t.owner_id = me.id and t.status = 'open' and t.due_at < now()),
--     'unread_alerts', (select count(*) from b2c.notifications n, me where n.user_id = me.id and n.read_at is null),
--     'unread_inbox', (select count(*) from b2c.wa_conversations c cross join me left join b2c.leads_state s on s.lead_id = c.lead_id
--                       where c.unread > 0 and (me.role in ('admin', 'marketing') or s.owner_id = me.id)))
-- $f$;
-- create or replace function b2c.notifications_mine(p_limit integer default 30) returns jsonb language sql stable security definer set search_path = '' as $f$
--   select jsonb_build_object('unread', (select count(*) from b2c.notifications n where n.user_id = b2c.uid() and n.read_at is null),
--     'items', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]') from (select * from b2c.notifications n where n.user_id = b2c.uid() order by n.created_at desc limit p_limit) n))
-- $f$;
-- create or replace function b2c.notifications_read(p_ids bigint[] default null) returns void language sql security definer set search_path = '' as $f$
--   update b2c.notifications set read_at = now() where user_id = b2c.uid() and read_at is null and (p_ids is null or id = any (p_ids))
-- $f$;
-- create or replace function b2c.phone_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
--   select jsonb_build_object('mobile', phone, 'caller_id', coalesce(caller_id, b2c.setting('telephony') ->> 'caller_id'), 'own_caller_id', caller_id is not null)
--     from b2c.users where user_id = b2c.uid()
-- $f$;
-- create or replace function b2c.schedules_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
--   select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('dashboard', d.name) order by s.id), '[]')
--     from b2c.dashboard_schedules s join b2c.dashboards d on d.id = s.dashboard_id where s.user_id = b2c.uid()
-- $f$;
-- create or replace function b2c.session_note(p_user_agent text, p_ip text) returns void language plpgsql security definer set search_path = '' as $f$
-- begin
--   update b2c.session_checks set user_agent = coalesce(left(p_user_agent, 300), user_agent), ip = coalesce(left(p_ip, 60), ip), last_seen_at = now()
--    where session_id = b2c.session_id() and user_id = b2c.uid();
--   update b2c.users set first_sign_in_at = now() where user_id = b2c.uid() and first_sign_in_at is null;
-- end $f$;
-- create or replace function b2c.snippet_delete(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
-- begin
--   update b2c.snippets set deleted_at = now() where id = p_id and deleted_at is null and (owner_id = b2c.uid() or b2c.my_role() = 'admin');
--   if not found then raise exception 'not your snippet' using errcode = '42501'; end if;
-- end $f$;
-- create or replace function b2c.support_attach(p_message bigint, p_files jsonb) returns void language plpgsql security definer set search_path = '' as $f$
-- declare m b2c.support_messages;
-- begin
--   select * into m from b2c.support_messages where id = p_message;
--   if m.id is null or m.author_id is distinct from b2c.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
--   if jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) > 5 then raise exception 'at most 5 files'; end if;
--   if exists (select 1 from jsonb_array_elements(p_files) f where f ->> 'path' not like 'tickets/' || m.ticket_id || '/%') then raise exception 'unknown file'; end if;
--   update b2c.support_messages set attachments = attachments || p_files where id = p_message;
-- end $f$;
-- alter policy "own or money read" on b2c.commission_lines using ((select b2c.can('read_money')) or counsellor_id = (select b2c.uid()));
-- alter policy "own" on b2c.dashboard_schedules using (user_id = (select b2c.uid()));
-- alter policy "who may see" on b2c.enrollments using ((select b2c.can_see(enrollments.lead_id)) or counsellor_id = (select b2c.uid()));
-- alter policy "own" on b2c.metric_alerts using (user_id = (select b2c.uid()));
-- alter policy "own notifications" on b2c.notifications using (user_id = (select b2c.uid()));
-- alter policy "own or team" on b2c.targets using (user_id = (select b2c.uid()) or (select b2c.can('read_all')) or (select b2c.can('read_team')));
-- alter policy "who may see" on b2c.tasks using ((select b2c.can_see(tasks.lead_id)) or owner_id = (select b2c.uid()));
-- alter policy "staff read users" on b2c.users using ((select b2c.is_staff()) or user_id = (select b2c.uid()));
-- alter policy "snippets_read" on b2c.snippets using (deleted_at is null and (owner_id = b2c.uid() or (shared and b2c.is_staff())));
