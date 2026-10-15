-- B2C CRM b31: support tickets. Anyone (counsellor, sales head, Marketing, Admin) raises a ticket: a problem with the
-- CRM, a feature idea, a phone number change, access. A subject, what is happening, links and screenshots.
--   support_tickets / support_messages   the ticket and its thread; screenshots in the private bucket b2c-support
--   email to the developer              each message from the CRM side goes to the developer (settings 'support'), sent
--                                       by the app's job; the developer answers by replying to the email (read from the
--                                       support mailbox) or through the signed link in it, and may change the status
--   statuses                            open → in progress / waiting for you → fixed → closed (closed by the person,
--                                       the Admin, the developer, or by itself 7 days after "fixed")
--   who sees what                       each person their own tickets; the Admin every ticket

insert into b2c.settings (key, value) values
  ('support', '{"developer_emails": [], "mailbox": null, "auto_close_days": 7}')
on conflict (key) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2c-support', 'b2c-support', false, 4194304, array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create table if not exists b2c.support_tickets (
  id bigint generated always as identity primary key,
  created_by uuid not null references b2c.users (user_id),
  kind text not null check (kind in ('bug', 'feature', 'phone', 'access', 'data', 'other')),
  priority text not null default 'normal' check (priority in ('normal', 'urgent')),
  subject text not null check (length(subject) between 3 and 150),
  status text not null default 'open' check (status in ('open', 'in_progress', 'waiting', 'fixed', 'closed')),
  page text,                                   -- the screen the person was on
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  developer_at timestamptz,                    -- the developer's last answer
  fixed_at timestamptz,
  closed_at timestamptz,
  closed_by text
);
create index if not exists support_tickets_by on b2c.support_tickets (created_by, status, updated_at desc);
create index if not exists support_tickets_status on b2c.support_tickets (status, updated_at desc);

create table if not exists b2c.support_messages (
  id bigint generated always as identity primary key,
  ticket_id bigint not null references b2c.support_tickets (id),
  author_kind text not null check (author_kind in ('user', 'admin', 'developer', 'system')),
  author_id uuid references b2c.users (user_id),
  author_email text,
  body text not null default '',
  urls text[] not null default '{}',
  attachments jsonb not null default '[]'::jsonb,      -- [{path, name, type, size}]
  status_to text,                                      -- the status this message set, if any
  to_developer boolean not null default false,         -- goes out by email
  mailed_at timestamptz,
  mail_attempts int not null default 0,
  mail_error text,
  source text,                                         -- crm | email | link
  external_id text unique,                             -- the Gmail message id of an emailed answer (read once)
  created_at timestamptz not null default now()
);
create index if not exists support_messages_ticket on b2c.support_messages (ticket_id, id);
create index if not exists support_messages_unsent on b2c.support_messages (id) where to_developer and mailed_at is null;
alter table b2c.support_tickets enable row level security;
alter table b2c.support_messages enable row level security;

create or replace function b2c.support_number(p_id bigint) returns text language sql immutable set search_path = '' as $f$
  select 'SUP-' || lpad(p_id::text, 4, '0')
$f$;

create or replace function b2c.support_may_see(p_ticket bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select b2c.my_role() = 'admin' or exists (select 1 from b2c.support_tickets t where t.id = p_ticket and t.created_by = b2c.uid())
$f$;

/* p: kind, priority, subject, body, urls [], page. Returns the ticket and its first message (for the screenshots). */
create or replace function b2c.support_create(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint; m bigint; v_urls text[];
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'kind', '') not in ('bug', 'feature', 'phone', 'access', 'data', 'other') then raise exception 'choose what the ticket is about'; end if;
  if length(coalesce(trim(p ->> 'subject'), '')) < 3 then raise exception 'write a subject'; end if;
  if length(coalesce(trim(p ->> 'body'), '')) < 5 then raise exception 'describe the issue'; end if;
  if (select count(*) from b2c.support_tickets where created_by = me and created_at > now() - interval '1 hour') >= 10 then raise exception 'at most 10 tickets an hour'; end if;
  select coalesce(array_agg(left(trim(x), 500)), '{}') into v_urls from jsonb_array_elements_text(coalesce(p -> 'urls', '[]')) x where trim(x) ~* '^https?://';
  insert into b2c.support_tickets (created_by, kind, priority, subject, page)
  values (me, p ->> 'kind', case when p ->> 'priority' = 'urgent' then 'urgent' else 'normal' end, left(trim(p ->> 'subject'), 150), left(p ->> 'page', 300))
  returning id into v;
  insert into b2c.support_messages (ticket_id, author_kind, author_id, body, urls, to_developer, source)
  values (v, case when b2c.my_role() = 'admin' then 'admin' else 'user' end, me, left(trim(p ->> 'body'), 8000), v_urls[1:10], true, 'crm')
  returning id into m;
  if p ->> 'kind' = 'phone' or p ->> 'priority' = 'urgent' then
    perform b2c.notify_admins('support', b2c.support_number(v) || ': ' || left(trim(p ->> 'subject'), 120),
                              (select full_name from b2c.users where user_id = me), '/w/support?t=' || v, null, 'support:' || v, false);
  end if;
  perform b2c.log('support.created', null, jsonb_build_object('ticket', v, 'kind', p ->> 'kind'));
  return jsonb_build_object('ticket_id', v, 'number', b2c.support_number(v), 'message_id', m);
end $f$;

/* A reply from the person who raised it, or from the Admin. A reply to a fixed or closed ticket reopens it. */
create or replace function b2c.support_reply(p_ticket bigint, p_body text, p_urls text[] default '{}') returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); t b2c.support_tickets; m bigint;
begin
  if not b2c.support_may_see(p_ticket) then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(coalesce(trim(p_body), '')) < 2 then raise exception 'write your reply'; end if;
  select * into t from b2c.support_tickets where id = p_ticket for update;
  insert into b2c.support_messages (ticket_id, author_kind, author_id, body, urls, to_developer, source, status_to)
  values (p_ticket, case when b2c.my_role() = 'admin' and t.created_by <> me then 'admin' else 'user' end, me, left(trim(p_body), 8000),
          (select coalesce(array_agg(left(trim(x), 500)), '{}') from unnest(coalesce(p_urls, '{}')) x where trim(x) ~* '^https?://'), true, 'crm',
          case when t.status in ('fixed', 'closed', 'waiting') then 'open' end)
  returning id into m;
  update b2c.support_tickets set status = case when status in ('fixed', 'closed', 'waiting') then 'open' else status end,
         closed_at = case when status = 'closed' then null else closed_at end, updated_at = now() where id = p_ticket;
  return m;
end $f$;

/* Screenshots, after the app has stored them under tickets/<ticket>/. Only the message's author adds them. */
create or replace function b2c.support_attach(p_message bigint, p_files jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare m b2c.support_messages;
begin
  select * into m from b2c.support_messages where id = p_message;
  if m.id is null or m.author_id is distinct from b2c.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  if jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) > 5 then raise exception 'at most 5 files'; end if;
  if exists (select 1 from jsonb_array_elements(p_files) f where f ->> 'path' not like 'tickets/' || m.ticket_id || '/%') then raise exception 'unknown file'; end if;
  update b2c.support_messages set attachments = attachments || p_files where id = p_message;
end $f$;

/* Closing, reopening: the person who raised it and the Admin. Any status: the Admin. */
create or replace function b2c.support_set_status(p_ticket bigint, p_status text, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); t b2c.support_tickets; v_admin boolean := b2c.my_role() = 'admin';
begin
  if not b2c.support_may_see(p_ticket) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('open', 'in_progress', 'waiting', 'fixed', 'closed') then raise exception 'unknown status'; end if;
  if not v_admin and p_status not in ('open', 'closed') then raise exception 'you can close or reopen your ticket'; end if;
  select * into t from b2c.support_tickets where id = p_ticket for update;
  if t.status = p_status then return; end if;
  update b2c.support_tickets set status = p_status, updated_at = now(),
         closed_at = case when p_status = 'closed' then now() else null end, closed_by = case when p_status = 'closed' then case when v_admin and t.created_by <> me then 'admin' else 'person' end end,
         fixed_at = case when p_status = 'fixed' then now() else fixed_at end
   where id = p_ticket;
  insert into b2c.support_messages (ticket_id, author_kind, author_id, body, status_to, to_developer, source)
  values (p_ticket, case when v_admin and t.created_by <> me then 'admin' else 'user' end, me,
          coalesce(nullif(trim(p_note), ''), case p_status when 'closed' then 'Closed the ticket.' when 'open' then 'Reopened the ticket.' else 'Changed the status.' end),
          p_status, true, 'crm');
end $f$;

/* The list. p: scope (mine | all: Admin only), group (open | ongoing | closed | all), q (search), kind. */
create or replace function b2c.support_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_all boolean := b2c.my_role() = 'admin' and coalesce(p ->> 'scope', 'mine') = 'all'; v_group text := coalesce(p ->> 'group', 'all');
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'counts', (select jsonb_build_object('open', count(*) filter (where status = 'open'), 'ongoing', count(*) filter (where status in ('in_progress', 'waiting', 'fixed')),
                                        'closed', count(*) filter (where status = 'closed'))
                 from b2c.support_tickets where v_all or created_by = me),
    'tickets', (select coalesce(jsonb_agg(x order by x ->> 'updated_at' desc), '[]') from (
      select jsonb_build_object('id', t.id, 'number', b2c.support_number(t.id), 'kind', t.kind, 'priority', t.priority, 'subject', t.subject, 'status', t.status,
               'created_at', t.created_at, 'updated_at', t.updated_at, 'developer_at', t.developer_at, 'by', u.full_name, 'by_role', u.role, 'mine', t.created_by = me,
               'messages', (select count(*) from b2c.support_messages m where m.ticket_id = t.id),
               'last', (select left(m.body, 160) from b2c.support_messages m where m.ticket_id = t.id order by m.id desc limit 1),
               'last_from', (select m.author_kind from b2c.support_messages m where m.ticket_id = t.id order by m.id desc limit 1)) x
        from b2c.support_tickets t join b2c.users u on u.user_id = t.created_by
       where (v_all or t.created_by = me)
         and (v_group = 'all' or (v_group = 'open' and t.status = 'open') or (v_group = 'ongoing' and t.status in ('in_progress', 'waiting', 'fixed')) or (v_group = 'closed' and t.status = 'closed'))
         and (coalesce(p ->> 'kind', '') = '' or t.kind = p ->> 'kind')
         and (coalesce(trim(p ->> 'q'), '') = '' or t.subject ilike '%' || trim(p ->> 'q') || '%' or b2c.support_number(t.id) ilike '%' || trim(p ->> 'q') || '%')
       order by t.updated_at desc limit 300) s));
end $f$;

create or replace function b2c.support_get(p_ticket bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.support_may_see(p_ticket) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select to_jsonb(t) || jsonb_build_object('number', b2c.support_number(t.id), 'by', u.full_name, 'by_email', u.email, 'by_role', u.role, 'mine', t.created_by = b2c.uid(),
            'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'author_kind', m.author_kind, 'author', coalesce(a.full_name, case when m.author_kind = 'developer' then 'Developer' end),
                           'body', m.body, 'urls', m.urls, 'attachments', m.attachments, 'status_to', m.status_to, 'created_at', m.created_at,
                           'mailed', m.mailed_at is not null, 'mail_error', case when b2c.my_role() = 'admin' then m.mail_error end) order by m.id), '[]')
                         from b2c.support_messages m left join b2c.users a on a.user_id = m.author_id where m.ticket_id = t.id))
            from b2c.support_tickets t join b2c.users u on u.user_id = t.created_by where t.id = p_ticket);
end $f$;

/* Whether this person may open a stored screenshot. */
create or replace function b2c.support_file_ok(p_path text) returns boolean language sql stable security definer set search_path = '' as $f$
  select case when coalesce(p_path, '') !~ '^tickets/\d{1,15}/[0-9a-f-]{36}\.(png|jpe?g|webp|gif|pdf)$' then false
              else b2c.support_may_see(split_part(p_path, '/', 2)::bigint)
                   and exists (select 1 from b2c.support_messages m, jsonb_array_elements(m.attachments) f where m.ticket_id = split_part(p_path, '/', 2)::bigint and f ->> 'path' = p_path) end
$f$;

-- ---------- the developer's side (service role: the app's job and the signed reply page) ----------
create or replace function b2c.support_mail_take(p_limit int default 10) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  -- nothing is taken until a developer address is set, so no attempt is spent
  if jsonb_array_length(coalesce(b2c.setting('support') -> 'developer_emails', '[]')) = 0 then return '[]'; end if;
  with due as (select m.id from b2c.support_messages m where m.to_developer and m.mailed_at is null and m.mail_attempts < 6
                and m.created_at <= now() - make_interval(secs => power(2, m.mail_attempts)::int * 30 - 30)
                order by m.id limit p_limit for update skip locked),
       x as (update b2c.support_messages m set mail_attempts = m.mail_attempts + 1 from due where m.id = due.id returning m.*)
  select coalesce(jsonb_agg(jsonb_build_object('message_id', x.id, 'ticket_id', t.id, 'number', b2c.support_number(t.id), 'subject', t.subject, 'kind', t.kind,
           'priority', t.priority, 'status', t.status, 'page', t.page, 'first', (select min(id) from b2c.support_messages where ticket_id = t.id) = x.id,
           'body', x.body, 'urls', x.urls, 'attachments', x.attachments, 'status_to', x.status_to,
           'author', coalesce(a.full_name, ''), 'author_email', a.email, 'author_role', a.role, 'by', u.full_name, 'by_email', u.email, 'by_role', u.role,
           'developer_emails', b2c.setting('support') -> 'developer_emails', 'mailbox', b2c.setting('support') ->> 'mailbox')), '[]') into v
    from x join b2c.support_tickets t on t.id = x.ticket_id join b2c.users u on u.user_id = t.created_by left join b2c.users a on a.user_id = x.author_id;
  return v;
end $f$;

create or replace function b2c.support_mail_done(p_message bigint, p_error text default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.support_messages set mailed_at = case when p_error is null then now() end, mail_error = left(p_error, 300) where id = p_message
$f$;

/* The developer's answer, by email (source email, external_id the Gmail id) or the signed page (source link).
   p: ticket_id, body, status (in_progress | waiting | fixed | closed | null), from_email, source, external_id. */
create or replace function b2c.support_developer_reply(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare t b2c.support_tickets; v_status text := nullif(p ->> 'status', ''); m bigint;
begin
  select * into t from b2c.support_tickets where id = (p ->> 'ticket_id')::bigint for update;
  if t.id is null then raise exception 'unknown ticket'; end if;
  if v_status is not null and v_status not in ('in_progress', 'waiting', 'fixed', 'closed', 'open') then raise exception 'unknown status'; end if;
  if length(coalesce(trim(p ->> 'body'), '')) < 2 and v_status is null then raise exception 'write the answer'; end if;
  insert into b2c.support_messages (ticket_id, author_kind, author_email, body, status_to, source, external_id)
  values (t.id, 'developer', left(p ->> 'from_email', 200), left(coalesce(trim(p ->> 'body'), ''), 8000), v_status, coalesce(p ->> 'source', 'link'), nullif(p ->> 'external_id', ''))
  on conflict (external_id) do nothing returning id into m;
  if m is null then return jsonb_build_object('duplicate', true); end if;
  update b2c.support_tickets set developer_at = now(), updated_at = now(),
         status = coalesce(v_status, case when status = 'open' then 'in_progress' else status end),
         fixed_at = case when v_status = 'fixed' then now() else fixed_at end,
         closed_at = case when v_status = 'closed' then now() when v_status is not null then null else closed_at end,
         closed_by = case when v_status = 'closed' then 'developer' when v_status is not null then null else closed_by end
   where id = t.id;
  perform b2c.notify(t.created_by, 'support', b2c.support_number(t.id) || case v_status when 'fixed' then ': fixed' when 'closed' then ': closed'
                                                  when 'waiting' then ': the developer needs something from you' else ': the developer answered' end,
                     left(coalesce(nullif(trim(p ->> 'body'), ''), t.subject), 200),
                     case when (select role from b2c.users where user_id = t.created_by) in ('admin', 'marketing') then '/w/support?t=' else '/s/support?t=' end || t.id, null, null);
  return jsonb_build_object('message_id', m, 'status', coalesce(v_status, t.status));
end $f$;

/* The signed reply page shows the ticket without signing in. */
create or replace function b2c.support_for_developer(p_ticket bigint) returns jsonb language sql stable security definer set search_path = '' as $f$
  select to_jsonb(t) || jsonb_build_object('number', b2c.support_number(t.id), 'by', u.full_name, 'by_role', u.role,
           'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'author_kind', m.author_kind, 'author', coalesce(a.full_name, 'Developer'), 'body', m.body,
                          'urls', m.urls, 'attachments', m.attachments, 'status_to', m.status_to, 'created_at', m.created_at) order by m.id), '[]')
                        from b2c.support_messages m left join b2c.users a on a.user_id = m.author_id where m.ticket_id = t.id))
    from b2c.support_tickets t join b2c.users u on u.user_id = t.created_by where t.id = p_ticket
$f$;

/* Daily: a ticket marked fixed closes by itself after auto_close_days unless the person reopens it. */
create or replace function b2c.support_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare n int := 0; t record;
begin
  for t in select id from b2c.support_tickets where status = 'fixed'
            and fixed_at < now() - make_interval(days => coalesce((b2c.setting('support') ->> 'auto_close_days')::int, 7)) for update skip locked loop
    update b2c.support_tickets set status = 'closed', closed_at = now(), closed_by = 'auto', updated_at = now() where id = t.id;
    insert into b2c.support_messages (ticket_id, author_kind, body, status_to, source) values (t.id, 'system', 'Closed by itself: no reply after it was marked fixed.', 'closed', 'crm');
    n := n + 1;
  end loop;
  return n;
end $f$;

grant execute on function b2c.support_create(jsonb), b2c.support_reply(bigint, text, text[]), b2c.support_attach(bigint, jsonb), b2c.support_set_status(bigint, text, text),
  b2c.support_list(jsonb), b2c.support_get(bigint), b2c.support_file_ok(text), b2c.support_number(bigint) to authenticated;
grant execute on function b2c.support_mail_take(integer), b2c.support_mail_done(bigint, text), b2c.support_developer_reply(jsonb), b2c.support_for_developer(bigint),
  b2c.support_tick(), b2c.support_file_ok(text) to service_role;
revoke execute on function b2c.support_mail_take(integer), b2c.support_mail_done(bigint, text), b2c.support_developer_reply(jsonb), b2c.support_for_developer(bigint),
  b2c.support_tick(), b2c.support_may_see(bigint) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;

-- ---------- guide articles ----------
insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort) values
('sales', 'support', 'Help', 'Support tickets', $t$Something not working, an idea, or a new phone number? Open **Support** and press **New ticket**: choose what it is about, write a subject and what is happening, add the link of the page and screenshots (up to 4, 4 MB in all). Tick **Urgent** only if you cannot work.

The ticket goes to the developer by email. Their answers appear under the ticket number (SUP-0001) and you get an alert. **Open**, **In progress** and **Closed** show where each ticket is; "Waiting for you" means the developer needs something from you. When a fix is in, check it and **close** the ticket, or reply if it still does not work. A fixed ticket closes by itself after 7 days.$t$, '{/s/support}', 150),
('marketing', 'support', 'Help', 'Support tickets', $t$Open **Support** → **New ticket** to report a problem, suggest a feature or ask for a change: a subject, what is happening, links and screenshots. The developer's answers appear under the ticket number and you get an alert. Close the ticket once it works.$t$, '{/w/support}', 150),
('admin', 'support', 'Company', 'Support tickets and phone numbers', $t$**Support** shows **everyone's tickets** (switch to **Mine** for your own) by Open, In progress and Closed. You can reply on any ticket and set any status; phone number requests and urgent tickets also alert you.

Tickets and replies are emailed to the addresses in **Settings → support → developer_emails**. Set **mailbox** to a Workspace mailbox (for example support@eduwit.in) so the developer can simply reply to the email; otherwise they answer through the link in each email. A message that could not be emailed shows why on the ticket.

**Teams → Phone numbers**: give each counsellor and sales manager a **work mobile** (the number they dial from; Exotel rings it first when calling through the CRM is on) and, if they have one, their own **caller ID**. A number held by someone else can be **moved**; both people are told and the history keeps who, when and why.$t$, '{/w/support,/w/teams}', 140)
on conflict (role, slug) do update set title = excluded.title, body = excluded.body, screens = excluded.screens, updated_at = now()
 where g.updated_by is null and g.version = 1;
