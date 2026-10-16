-- One call for the numbers the navigation shows (16 Oct 2026): new leads and overdue follow-ups, unread alerts, unread
-- WhatsApp chats. The Sales app used to make two calls on every page; the Workspace none. Counsellors count their own
-- chats; the Admin and Marketing count every chat.

create or replace function b2c.nav_counts() returns jsonb language sql stable security definer set search_path = '' as $f$
  with me as (select b2c.uid() as id, b2c.my_role() as role)
  select jsonb_build_object(
    'not_worked', (select count(*) from b2c.leads_state s, me where s.owner_id = me.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
    'overdue', (select count(*) from b2c.tasks t, me where t.owner_id = me.id and t.status = 'open' and t.due_at < now()),
    'unread_alerts', (select count(*) from b2c.notifications n, me where n.user_id = me.id and n.read_at is null),
    'unread_inbox', (select count(*) from b2c.wa_conversations c cross join me left join b2c.leads_state s on s.lead_id = c.lead_id
                      where c.unread > 0 and (me.role in ('admin', 'marketing') or s.owner_id = me.id)))
$f$;
revoke execute on function b2c.nav_counts() from public, anon;
grant execute on function b2c.nav_counts() to authenticated;
