-- Phase 9: communication (spec 14) and outbound webhooks (spec 18).
--
-- Threads on every entity with attachments, @mentions, read receipts, unread counts and full-text search; the
-- notification catalogue in the database (rows generated from lib/notify/catalogue.ts) so mandatory events and default
-- channels are enforced by inf.notify(); template versions; announcements to segments with scheduling; digest
-- preferences and facts; signed outbound webhooks with a delivery log; the catalogue events still missing (enrolment
-- "₹X earned", clawbacks, payable milestones, KYC action, fraud flags, staff queues). Attachments use the approved
-- private bucket inf-documents under threads/ (SHARED_CHANGES S-4); live updates ride on inf.notifications (S-6).
-- Nothing outside schema inf is created or changed.

-- ---------------------------------------------------------------------------------------------------------------
-- Notification catalogue (rows: generated migration notification_events)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.notification_events (
  event      text primary key check (event ~ '^[a-z_]+(\.[a-z_]+)?$'),
  grp        text not null,
  audience   text[] not null,
  mandatory  boolean not null,
  channels   text[] not null,
  vars       text[] not null
);

-- Digest choice per person (built and sent by the digest.run job; see Digests below).
create table inf.digest_preferences (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  frequency   text not null check (frequency in ('off', 'daily', 'weekly')),
  channel     text not null default 'email' check (channel in ('email', 'whatsapp')),
  updated_at  timestamptz not null default now()
);

-- inf.notify: an event is mandatory when the caller or the catalogue says so; a channel is on by the person's choice,
-- else by the default channels: the caller's when given (announcements), else the catalogue's, else email. Mandatory
-- events always use their default channels.
create or replace function inf.notify(p_user uuid, p_event text, p_title text, p_body text, p_link text, p_data jsonb,
                                      p_mandatory boolean, p_idem_key text, p_channels text[] default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_ch text;
  v_ev inf.notification_events;
  v_mandatory boolean;
  v_default boolean;
  v_pref boolean;
begin
  select * into v_ev from inf.notification_events where event = p_event;
  v_mandatory := coalesce(p_mandatory, false) or coalesce(v_ev.mandatory, false);
  insert into inf.notifications (user_id, event, title, body, link, data, mandatory, idem_key)
  values (p_user, p_event, left(p_title, 200), left(p_body, 2000), p_link, coalesce(p_data, '{}'::jsonb), v_mandatory, p_idem_key)
  on conflict (idem_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from inf.notifications where idem_key = p_idem_key;
    return v_id;
  end if;
  foreach v_ch in array array['email', 'whatsapp'] loop
    v_default := v_ch = any (coalesce(p_channels, v_ev.channels, array['email']));
    select np.enabled into v_pref from inf.notification_preferences np
     where np.user_id = p_user and np.event = p_event and np.channel = v_ch;
    if (v_mandatory and (v_default or coalesce(v_pref, false))) or (not v_mandatory and coalesce(v_pref, v_default)) then
      insert into inf.notification_deliveries (notification_id, channel) values (v_id, v_ch) on conflict do nothing;
    end if;
  end loop;
  if exists (select 1 from inf.notification_deliveries where notification_id = v_id and status = 'queued') then
    perform inf.job_enqueue('notify.deliver', jsonb_build_object('notification_id', v_id), now(), 'notify:' || v_id, 8);
  end if;
  return v_id;
end $$;

-- Preferences: mandatory events cannot be turned off, and in-app is always on.
create or replace function inf.notification_preference_set(p_event text, p_channel text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_channel not in ('email', 'whatsapp') then raise exception 'invalid channel' using errcode = '22023'; end if;
  if not exists (select 1 from inf.notification_events e where e.event = p_event) then
    raise exception 'unknown event' using errcode = '22023';
  end if;
  if not p_enabled and exists (select 1 from inf.notification_events e where e.event = p_event and e.mandatory) then
    raise exception 'this notification cannot be turned off' using errcode = '22023';
  end if;
  insert into inf.notification_preferences (user_id, event, channel, enabled) values (auth.uid(), p_event, p_channel, p_enabled)
  on conflict (user_id, event, channel) do update set enabled = excluded.enabled, updated_at = now();
end $$;

create or replace function inf.my_notification_preferences() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'prefs', coalesce((select jsonb_agg(jsonb_build_object('event', np.event, 'channel', np.channel, 'enabled', np.enabled))
                         from inf.notification_preferences np where np.user_id = auth.uid()), '[]'),
    'digest', (select jsonb_build_object('frequency', d.frequency, 'channel', d.channel) from inf.digest_preferences d where d.user_id = auth.uid()))
   where auth.uid() is not null and inf.session_ok()
$$;

-- The notification centre.
create or replace function inf.my_notifications_page(p_limit int default 30, p_before timestamptz default null, p_unread boolean default false)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'unread', (select count(*) from inf.notifications n where n.user_id = auth.uid() and n.read_at is null),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'event', x.event, 'title', x.title, 'body', x.body, 'link', x.link,
                                                          'read_at', x.read_at, 'created_at', x.created_at, 'mandatory', x.mandatory)
                                         order by x.created_at desc)
                         from (select * from inf.notifications n
                                where n.user_id = auth.uid() and (p_before is null or n.created_at < p_before)
                                  and (not p_unread or n.read_at is null)
                                order by n.created_at desc limit least(greatest(p_limit, 1), 100)) x), '[]'))
   where auth.uid() is not null and inf.session_ok()
$$;

create or replace function inf.notifications_mark_all_read() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if auth.uid() is null or not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.notifications set read_at = now() where user_id = auth.uid() and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Threads on every entity
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.threads drop constraint threads_entity_type_check;
alter table inf.threads add constraint threads_entity_type_check
  check (entity_type in ('application', 'campaign', 'deal', 'contract', 'brief', 'deliverable', 'payout', 'lead', 'support'));
alter table inf.threads drop constraint threads_entity_type_entity_id_key;
alter table inf.threads
  add column creator_id uuid references inf.creators (id) on delete cascade,
  add column staff_only boolean not null default false,
  add column last_message_at timestamptz;
-- One thread per entity, and per creator for campaigns (each creator's conversation about a campaign is private).
create unique index threads_entity_uq on inf.threads (entity_type, entity_id, coalesce(creator_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index threads_creator_idx on inf.threads (creator_id, last_message_at desc);
update inf.threads t set creator_id = a.creator_id from inf.campaign_applications a where t.entity_type = 'application' and a.id = t.entity_id;
update inf.threads t set last_message_at = (select max(m.created_at) from inf.messages m where m.thread_id = t.id);

alter table inf.messages
  add column search tsvector generated always as (to_tsvector('simple', body)) stored;
create index messages_search_idx on inf.messages using gin (search);

create table inf.message_attachments (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references inf.messages (id) on delete cascade,
  path        text not null check (path ~ '^threads/[0-9a-f-]{36}/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$'),
  name        text not null check (char_length(name) between 1 and 200),
  mime        text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png', 'text/csv')),
  size_bytes  int not null check (size_bytes between 1 and 26214400)
);
create index message_attachments_msg_idx on inf.message_attachments (message_id);
create trigger message_attachments_append_only before update or delete on inf.message_attachments
  for each row execute function inf.forbid_mutation();

create table inf.message_mentions (
  message_id  uuid not null references inf.messages (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  primary key (message_id, user_id)
);

create table inf.thread_reads (
  thread_id     uuid not null references inf.threads (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  last_read_at  timestamptz not null default now(),
  primary key (thread_id, user_id)
);

-- Who the caller is on a thread about one entity, and what they may do. The creator is derived from the entity
-- (campaign threads take the creator explicitly). Staff read with message.read plus the entity's read permission and
-- post with message.write; creators read and post on their own threads except staff-only lead notes; agencies follow
-- their grants (negotiate: applications, campaigns, deals, contracts; deliverables: briefs and deliverables;
-- earnings: payouts; view: support).
create or replace function inf.thread_resolve(p_type text, p_entity uuid, p_creator uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_creator uuid;
  v_subject text;
  v_staff_perm text;
  v_agency_grant text;
  v_staff_only boolean := false;
  v_owner uuid;
  v_admin_link text;
  v_creator_link text;
  v_agency_link text;
  v_side text;
  v_read boolean := false;
  v_post boolean := false;
begin
  case p_type
    when 'application' then
      select a.creator_id, 'Application: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/applications/' || a.id,
             '/creator/applications/' || a.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.campaign_applications a join inf.campaigns c on c.id = a.campaign_id where a.id = p_entity;
      v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/applications/' || p_entity;
    when 'campaign' then
      select p_creator, 'Campaign: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/campaigns/' || c.id || '?tab=messages&thread=' || p_creator,
             '/creator/campaigns/' || c.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.campaigns c where c.id = p_entity and p_creator is not null;
      v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate';
      v_agency_link := '/agency/creators/' || p_creator || '/campaigns/' || p_entity;
    when 'deal' then
      select d.creator_id, 'Deal: ' || d.title, d.owner_id, '/admin/deals/' || d.id, '/creator/deals/' || d.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.deals d where d.id = p_entity;
      v_staff_perm := 'deal.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/deals/' || p_entity;
    when 'contract' then
      select d.creator_id, 'Contract ' || k.number, d.owner_id, '/admin/contracts/' || k.id, '/creator/contracts/' || k.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.contracts k join inf.deals d on d.id = k.deal_id where k.id = p_entity;
      v_staff_perm := 'contract.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/contracts/' || p_entity;
    when 'brief' then
      select d.creator_id, 'Brief: ' || d.title, d.owner_id, '/admin/briefs/' || b.id, '/creator/briefs/' || b.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.briefs b join inf.deals d on d.id = b.deal_id where b.id = p_entity;
      v_staff_perm := 'brief.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/briefs/' || p_entity;
    when 'deliverable' then
      select d.creator_id, 'Deliverable: ' || x.title, d.owner_id, '/admin/content/' || x.id, '/creator/deliverables/' || x.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.deliverables x join inf.deals d on d.id = x.deal_id where x.id = p_entity;
      v_staff_perm := 'deliverable.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/deliverables/' || p_entity;
    when 'payout' then
      select p.creator_id, 'Payout ' || p.ref, null, '/admin/finance/payouts/' || p.batch_id || '?payout=' || p.id, '/creator/earnings?payout=' || p.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.payouts p where p.id = p_entity;
      v_staff_perm := 'payout.read'; v_agency_grant := 'earnings'; v_agency_link := '/agency/creators/' || v_creator || '/earnings?payout=' || p_entity;
    when 'lead' then
      select a.creator_id, 'Lead note', null, '/admin/leads?lead=' || a.id, null
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.lead_attributions a where a.id = p_entity;
      v_staff_perm := 'lead.read'; v_agency_grant := null; v_staff_only := true;
    when 'support' then
      select c.id, 'Support: ' || c.display_name, c.owner_id, '/admin/creators/' || c.id || '?tab=messages', '/creator/messages'
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.creators c where c.id = p_entity;
      v_staff_perm := 'creator.read'; v_agency_grant := 'view'; v_agency_link := '/agency/messages?creator=' || p_entity;
    else
      raise exception 'invalid thread type' using errcode = '22023';
  end case;
  if v_creator is null then return null; end if;
  if inf.has_perm('message.read') and inf.has_perm(v_staff_perm) then
    v_side := 'eduwit'; v_read := true; v_post := inf.has_perm('message.write');
  elsif not v_staff_only and coalesce(v_creator = inf.current_creator_id(), false) then
    v_side := 'creator'; v_read := true; v_post := true;
  elsif not v_staff_only and v_agency_grant is not null and inf.agency_can(v_creator, v_agency_grant) then
    v_side := 'agency'; v_read := true; v_post := true;
  end if;
  return jsonb_build_object('creator_id', v_creator, 'subject', v_subject, 'side', v_side, 'can_read', v_read, 'can_post', v_post,
                            'staff_only', v_staff_only, 'owner_id', v_owner, 'admin_link', v_admin_link, 'creator_link', v_creator_link,
                            'agency_link', v_agency_link, 'agency_grant', v_agency_grant);
end $$;

-- A thread with its messages for whoever may read it (null when it has no messages yet but may be started).
create or replace function inf.thread_get(p_type text, p_entity uuid, p_creator uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; t inf.threads;
begin
  r := inf.thread_resolve(p_type, p_entity, p_creator);
  if r is null or not (r ->> 'can_read')::boolean then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into t from inf.threads x
   where x.entity_type = p_type and x.entity_id = p_entity and x.creator_id is not distinct from (r ->> 'creator_id')::uuid;
  return jsonb_build_object(
    'thread_id', t.id, 'subject', r ->> 'subject', 'side', r ->> 'side', 'can_post', (r ->> 'can_post')::boolean,
    'staff_only', (r ->> 'staff_only')::boolean,
    -- Read receipts: when the other side last read the thread.
    'other_read_at', case when t.id is null then null
                          when r ->> 'side' = 'eduwit' then (select max(tr.last_read_at) from inf.thread_reads tr
                                                              where tr.thread_id = t.id and not exists (select 1 from inf.staff_profiles sp where sp.user_id = tr.user_id))
                          else (select max(tr.last_read_at) from inf.thread_reads tr join inf.staff_profiles sp on sp.user_id = tr.user_id
                                 where tr.thread_id = t.id) end,
    'my_read_at', (select tr.last_read_at from inf.thread_reads tr where tr.thread_id = t.id and tr.user_id = auth.uid()),
    'messages', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', m.id, 'author_side', m.author_side, 'body', m.body, 'created_at', m.created_at, 'mine', m.author_id = auth.uid(),
                  -- Staff see colleagues' names; creators and agencies see the Eduwit person's first name only.
                  'author_name', case
                    when m.author_side = 'eduwit' then
                      case when r ->> 'side' = 'eduwit' then (select sp.full_name from inf.staff_profiles sp where sp.user_id = m.author_id)
                           else split_part((select sp.full_name from inf.staff_profiles sp where sp.user_id = m.author_id), ' ', 1) || ' (Eduwit)' end
                    when m.author_side = 'agency' then (select am.full_name || ' (' || ag.name || ')' from inf.agency_members am
                                                          join inf.agencies ag on ag.id = am.agency_id where am.user_id = m.author_id limit 1)
                    else (select c.display_name from inf.creators c where c.id = t.creator_id) end,
                  'attachments', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'path', a.path, 'mime', a.mime,
                                                                               'size_bytes', a.size_bytes))
                                             from inf.message_attachments a where a.message_id = m.id), '[]'))
                  order by m.created_at, m.id)
                  from inf.messages m where m.thread_id = t.id), '[]'));
end $$;

-- Staff who follow a thread: the entity's owner, or else staff who already wrote in it.
create or replace function inf.thread_staff_followers(p_thread uuid, p_owner uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select sp.user_id from inf.staff_profiles sp
   where sp.status = 'active'
     and (sp.user_id = p_owner
          or (p_owner is null and exists (select 1 from inf.messages m where m.thread_id = p_thread and m.author_id = sp.user_id)))
$$;

-- Post a message (with optional attachments uploaded beforehand under threads/<thread>/). Notifies the other side and
-- anyone mentioned (staff only, and only on staff posts).
create or replace function inf.thread_post(p_type text, p_entity uuid, p_body text, p_attachments jsonb default '[]', p_creator uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  v_thread uuid;
  v_msg uuid;
  v_side text;
  v_creator uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_plain text;
  v_user uuid;
  v_sender text;
  a jsonb;
  v_mentions uuid[] := '{}';
begin
  r := inf.thread_resolve(p_type, p_entity, p_creator);
  if r is null or not coalesce((r ->> 'can_post')::boolean, false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(v_body) = 0 and coalesce(jsonb_array_length(p_attachments), 0) = 0 then
    raise exception 'a message is required' using errcode = '22023';
  end if;
  if char_length(v_body) > 4000 then raise exception 'message too long' using errcode = '22023'; end if;
  if coalesce(jsonb_array_length(p_attachments), 0) > 5 then raise exception 'at most 5 attachments' using errcode = '22023'; end if;
  v_side := r ->> 'side';
  v_creator := (r ->> 'creator_id')::uuid;
  insert into inf.threads (entity_type, entity_id, creator_id, staff_only)
  values (p_type, p_entity, v_creator, (r ->> 'staff_only')::boolean)
  on conflict (entity_type, entity_id, coalesce(creator_id, '00000000-0000-0000-0000-000000000000'::uuid)) do nothing;
  select id into v_thread from inf.threads
   where entity_type = p_type and entity_id = p_entity and creator_id is not distinct from v_creator;
  insert into inf.messages (thread_id, author_side, body) values (v_thread, v_side, coalesce(nullif(v_body, ''), '📎'))
  returning id into v_msg;
  for a in select * from jsonb_array_elements(coalesce(p_attachments, '[]')) loop
    if (a ->> 'path') not like 'threads/' || v_thread || '/%' then raise exception 'invalid file' using errcode = '22023'; end if;
    insert into inf.message_attachments (message_id, path, name, mime, size_bytes)
    values (v_msg, a ->> 'path', left(a ->> 'name', 200), a ->> 'mime', (a ->> 'size_bytes')::int);
  end loop;
  update inf.threads set last_message_at = now() where id = v_thread;
  insert into inf.thread_reads (thread_id, user_id, last_read_at) values (v_thread, auth.uid(), now())
  on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;

  v_plain := regexp_replace(v_body, '@\[([^\]]+)\]\(user:[0-9a-f-]{36}\)', '@\1', 'g');
  v_sender := case v_side when 'eduwit' then 'Eduwit'
                          when 'agency' then coalesce((select ag.name from inf.agency_members am join inf.agencies ag on ag.id = am.agency_id
                                                       where am.user_id = auth.uid() limit 1), 'Agency')
                          else (select c.display_name from inf.creators c where c.id = v_creator) end;
  -- Mentions (staff posting about staff only).
  if v_side = 'eduwit' then
    select coalesce(array_agg(distinct m[1]::uuid), '{}') into v_mentions
      from regexp_matches(v_body, '@\[[^\]]+\]\(user:([0-9a-f-]{36})\)', 'g') m
     where exists (select 1 from inf.staff_profiles sp where sp.user_id = m[1]::uuid and sp.status = 'active');
    insert into inf.message_mentions (message_id, user_id) select v_msg, u from unnest(v_mentions) u on conflict do nothing;
    perform inf.notify(u, 'thread.mention', 'You were mentioned: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
                       jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                       'thread_mention:' || v_msg || ':' || u)
      from unnest(v_mentions) u where u <> auth.uid();
  end if;
  -- The other side.
  if v_side = 'eduwit' then
    if not (r ->> 'staff_only')::boolean then
      select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = v_creator;
      if v_user is not null then
        perform inf.notify(v_user, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'creator_link',
                           jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                           'thread_message:' || v_msg || ':' || v_user);
      end if;
      perform inf.notify(am.user_id, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300),
                         coalesce(r ->> 'agency_link', '/agency'),
                         jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                         'thread_message:' || v_msg || ':' || am.user_id)
        from inf.agency_creator_links l join inf.agency_members am on am.agency_id = l.agency_id
       where l.creator_id = v_creator and l.status = 'active' and am.user_id is not null and am.status = 'active'
         and r ->> 'agency_grant' is not null
         and case r ->> 'agency_grant' when 'view' then l.can_view when 'deliverables' then l.can_act_deliverables
                                       when 'negotiate' then l.can_negotiate_sign when 'earnings' then l.can_view_earnings else false end;
    end if;
  else
    perform inf.notify(f, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
                       jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                       'thread_message:' || v_msg || ':' || f)
      from inf.thread_staff_followers(v_thread, (r ->> 'owner_id')::uuid) f;
  end if;
  return jsonb_build_object('thread_id', v_thread, 'message_id', v_msg);
end $$;

create or replace function inf.thread_mark_read(p_thread uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare t inf.threads; r jsonb;
begin
  select * into t from inf.threads where id = p_thread;
  if t.id is null then return; end if;
  r := inf.thread_resolve(t.entity_type, t.entity_id, t.creator_id);
  if r is null or not (r ->> 'can_read')::boolean then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.thread_reads (thread_id, user_id, last_read_at) values (p_thread, auth.uid(), now())
  on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;
  -- Reading a thread clears its message notifications.
  update inf.notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and event in ('thread.message', 'thread.mention') and data ->> 'thread_id' = p_thread::text;
end $$;

-- Whether the caller may upload to a thread (returns the thread id to upload under, creating the thread if needed).
create or replace function inf.thread_open(p_type text, p_entity uuid, p_creator uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_thread uuid; v_creator uuid;
begin
  r := inf.thread_resolve(p_type, p_entity, p_creator);
  if r is null or not coalesce((r ->> 'can_post')::boolean, false) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_creator := (r ->> 'creator_id')::uuid;
  insert into inf.threads (entity_type, entity_id, creator_id, staff_only) values (p_type, p_entity, v_creator, (r ->> 'staff_only')::boolean)
  on conflict (entity_type, entity_id, coalesce(creator_id, '00000000-0000-0000-0000-000000000000'::uuid)) do nothing;
  select id into v_thread from inf.threads where entity_type = p_type and entity_id = p_entity and creator_id is not distinct from v_creator;
  return v_thread;
end $$;

-- Whether the caller may open a thread attachment.
create or replace function inf.thread_file_allowed(p_path text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare t inf.threads; r jsonb;
begin
  if p_path !~ '^threads/[0-9a-f-]{36}/' then return false; end if;
  if not exists (select 1 from inf.message_attachments a where a.path = p_path) then return false; end if;
  select * into t from inf.threads where id = split_part(p_path, '/', 2)::uuid;
  if t.id is null then return false; end if;
  r := inf.thread_resolve(t.entity_type, t.entity_id, t.creator_id);
  return coalesce((r ->> 'can_read')::boolean, false);
end $$;

-- The caller's conversations (inbox) with unread counts; staff can search, filter by type, unread or mentions.
create or replace function inf.my_threads(p jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_creator uuid := inf.current_creator_id();
  v_agency uuid := inf.current_agency_id();
  v_staff boolean := inf.has_perm('message.read');
  v_q text := nullif(trim(p ->> 'q'), '');
  v_type text := nullif(p ->> 'type', '');
  v_unread boolean := coalesce((p ->> 'unread')::boolean, false);
  v_mentions boolean := coalesce((p ->> 'mentions')::boolean, false);
  v_creator_filter uuid := nullif(p ->> 'creator_id', '')::uuid;
begin
  if auth.uid() is null or not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(x.j order by x.last desc nulls last)
      from (
        select jsonb_build_object(
                 'id', t.id, 'entity_type', t.entity_type, 'entity_id', t.entity_id, 'creator_id', t.creator_id,
                 'creator_name', (select c.display_name from inf.creators c where c.id = t.creator_id),
                 'subject', r1.r ->> 'subject', 'link', case when v_staff then r1.r ->> 'admin_link'
                                                           when v_agency is not null then coalesce(r1.r ->> 'agency_link', '/agency')
                                                           else r1.r ->> 'creator_link' end,
                 'last_message_at', t.last_message_at,
                 'last_message', (select left(regexp_replace(m.body, '@\[([^\]]+)\]\(user:[0-9a-f-]{36}\)', '@\1', 'g'), 160)
                                    from inf.messages m where m.thread_id = t.id order by m.created_at desc limit 1),
                 'unread', (select count(*) from inf.messages m where m.thread_id = t.id and m.author_id <> auth.uid()
                              and m.created_at > coalesce((select tr.last_read_at from inf.thread_reads tr where tr.thread_id = t.id and tr.user_id = auth.uid()), '-infinity'::timestamptz)),
                 'staff_only', t.staff_only) as j,
               t.last_message_at as last
          from inf.threads t
          cross join lateral (select inf.thread_resolve(t.entity_type, t.entity_id, t.creator_id) as r) r1
         where t.last_message_at is not null
           and coalesce((r1.r ->> 'can_read')::boolean, false)
           and (v_staff or t.creator_id = v_creator or v_agency is not null)
           and (v_type is null or t.entity_type = v_type)
           and (v_creator_filter is null or t.creator_id = v_creator_filter)
           and (v_q is null or exists (select 1 from inf.messages m where m.thread_id = t.id and m.search @@ websearch_to_tsquery('simple', v_q))
                or (r1.r ->> 'subject') ilike '%' || v_q || '%')
           and (not v_mentions or exists (select 1 from inf.message_mentions mm join inf.messages m on m.id = mm.message_id
                                           where m.thread_id = t.id and mm.user_id = auth.uid()))
         order by t.last_message_at desc
         limit 200
      ) x
     where not v_unread or (x.j ->> 'unread')::int > 0), '[]');
end $$;

-- Badge counts for the header.
create or replace function inf.my_unread_counts() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'notifications', (select count(*) from inf.notifications n where n.user_id = auth.uid() and n.read_at is null),
    'messages', (select count(*) from inf.notifications n where n.user_id = auth.uid() and n.read_at is null
                   and n.event in ('thread.message', 'thread.mention')))
   where auth.uid() is not null and inf.session_ok()
$$;

-- Staff colleagues to @mention.
create or replace function inf.mentionable_staff() returns table (user_id uuid, full_name text)
language sql stable security definer set search_path = '' as $$
  select sp.user_id, sp.full_name from inf.staff_profiles sp
   where sp.status = 'active' and inf.has_perm('message.write')
     and exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                  where g.user_id = sp.user_id and rp.permission = 'message.read')
   order by sp.full_name
$$;

-- Applications keep their API; messages now go through the shared thread functions.
create or replace function inf.application_message(p_app uuid, p_body text) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  return (inf.thread_post('application', p_app, p_body) ->> 'message_id')::uuid;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Templates (versions; the newest active one per event, channel and locale is used, else the built-in copy)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.notification_template_vars_ok(p_event text, p_text text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from regexp_matches(coalesce(p_text, ''), '\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}', 'g') m
     where lower(m[1]) <> all (array['name', 'title', 'body', 'link']
                                || coalesce((select e.vars from inf.notification_events e where e.event = p_event), '{}')))
$$;

create or replace function inf.notification_template_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_event text := p ->> 'event';
  v_channel text := p ->> 'channel';
  v_version int;
  v_id uuid;
begin
  if not inf.has_perm('notification_template.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from inf.notification_events e where e.event = v_event) then raise exception 'unknown event' using errcode = '22023'; end if;
  if v_channel not in ('email', 'whatsapp') then raise exception 'invalid channel' using errcode = '22023'; end if;
  if coalesce(char_length(trim(p ->> 'body')), 0) not between 1 and 5000 then raise exception 'invalid body' using errcode = '22023'; end if;
  if v_channel = 'email' and coalesce(char_length(trim(p ->> 'subject')), 0) not between 1 and 200 then
    raise exception 'invalid subject' using errcode = '22023';
  end if;
  if v_channel = 'whatsapp' and (coalesce(p ->> 'wa_template_name', '') !~ '^[a-z0-9_]+$'
                                  or char_length(p ->> 'wa_template_name') > 512) then
    raise exception 'invalid WhatsApp template name' using errcode = '22023';
  end if;
  if not (inf.notification_template_vars_ok(v_event, p ->> 'body') and inf.notification_template_vars_ok(v_event, p ->> 'subject')) then
    raise exception 'unknown template variable' using errcode = '22023';
  end if;
  select coalesce(max(t.version), 0) + 1 into v_version from inf.notification_templates t
   where t.event = v_event and t.channel = v_channel and t.locale = 'en';
  update inf.notification_templates set active = false, updated_by = auth.uid()
   where event = v_event and channel = v_channel and locale = 'en' and active;
  insert into inf.notification_templates (event, channel, locale, version, subject, body, wa_template_name, active, updated_by)
  values (v_event, v_channel, 'en', v_version, nullif(trim(p ->> 'subject'), ''), trim(p ->> 'body'), nullif(p ->> 'wa_template_name', ''),
          true, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- Back to the built-in copy (the saved versions stay in the history).
create or replace function inf.notification_template_reset(p_event text, p_channel text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('notification_template.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.notification_templates set active = false, updated_by = auth.uid()
   where event = p_event and channel = p_channel and locale = 'en' and active;
end $$;

create or replace function inf.notification_templates_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'event', e.event, 'group', e.grp, 'audience', e.audience, 'mandatory', e.mandatory, 'channels', e.channels, 'vars', e.vars,
           'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'channel', t.channel, 'version', t.version, 'subject', t.subject,
                                                                      'body', t.body, 'wa_template_name', t.wa_template_name, 'active', t.active,
                                                                      'updated_at', t.updated_at,
                                                                      'updated_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = t.updated_by))
                                                    order by t.channel, t.version desc)
                                    from inf.notification_templates t where t.event = e.event and t.locale = 'en'), '[]'))
           order by e.grp, e.event), '[]')
    from inf.notification_events e
   where inf.has_perm('notification_template.write')
$$;

-- For the delivery job (service role).
create or replace function inf.notification_template_for(p_event text, p_channel text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('subject', t.subject, 'body', t.body, 'wa_template_name', t.wa_template_name, 'version', t.version)
    from inf.notification_templates t
   where coalesce(auth.role(), '') = 'service_role' and t.event = p_event and t.channel = p_channel and t.locale = 'en' and t.active
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Announcements to all creators or a segment, now or scheduled
-- ---------------------------------------------------------------------------------------------------------------
create table inf.announcements (
  id            uuid primary key default gen_random_uuid(),
  title         text not null check (char_length(title) between 3 and 120),
  body          text not null check (char_length(body) between 3 and 2000),
  link          text check (link is null or link ~ '^/creator(/[A-Za-z0-9/_\-?=&.%]*)?$'),
  segment       jsonb not null default '{}'::jsonb check (jsonb_typeof(segment) = 'object'),
  channels      text[] not null default '{}' check (channels <@ array['email', 'whatsapp']),
  status        text not null default 'draft' check (status in ('draft', 'scheduled', 'sent', 'cancelled')),
  scheduled_at  timestamptz,
  sent_at       timestamptz,
  recipients    int,
  created_by    uuid not null default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (status <> 'scheduled' or scheduled_at is not null)
);
create index announcements_due_idx on inf.announcements (scheduled_at) where status = 'scheduled';
create trigger announcements_touch before update on inf.announcements for each row execute function inf.touch_updated_at();
create trigger announcements_audit after insert or update on inf.announcements for each row execute function inf.audit_row('announcement');

-- Creators (with an account, active) in a segment: every list that is set must match, any value within a list.
create or replace function inf.announcement_audience(p_segment jsonb) returns table (creator_id uuid, user_id uuid)
language sql stable security definer set search_path = '' as $$
  select c.id, ca.user_id
    from inf.creators c join inf.creator_accounts ca on ca.creator_id = c.id
   where c.status = 'active' and not c.is_blocked
     and (jsonb_array_length(coalesce(p_segment -> 'tiers', '[]')) = 0
          or c.tier_id::text in (select jsonb_array_elements_text(p_segment -> 'tiers')))
     and (jsonb_array_length(coalesce(p_segment -> 'campaigns', '[]')) = 0
          or exists (select 1 from inf.deals d where d.creator_id = c.id
                        and d.campaign_id::text in (select jsonb_array_elements_text(p_segment -> 'campaigns')))
          or exists (select 1 from inf.campaign_applications a where a.creator_id = c.id and a.status in ('submitted', 'shortlisted', 'countered', 'accepted')
                        and a.campaign_id::text in (select jsonb_array_elements_text(p_segment -> 'campaigns'))))
     and (jsonb_array_length(coalesce(p_segment -> 'platforms', '[]')) = 0
          or exists (select 1 from inf.creator_platforms pl where pl.creator_id = c.id
                        and pl.platform in (select jsonb_array_elements_text(p_segment -> 'platforms'))))
     and (jsonb_array_length(coalesce(p_segment -> 'languages', '[]')) = 0
          or exists (select 1 from unnest(c.languages) l
                      where lower(l) in (select lower(x) from jsonb_array_elements_text(p_segment -> 'languages') x)))
$$;

create or replace function inf.announcement_audience_count(p_segment jsonb) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from inf.announcement_audience(p_segment) where inf.has_perm('announcement.write')
$$;

create or replace function inf.announcement_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_at timestamptz := nullif(p ->> 'scheduled_at', '')::timestamptz; v_status text;
begin
  if not inf.has_perm('announcement.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  v_status := case p ->> 'action' when 'send' then 'scheduled' when 'schedule' then 'scheduled' else 'draft' end;
  if p ->> 'action' = 'send' then v_at := now(); end if;
  if v_status = 'scheduled' and (v_at is null or v_at < now() - interval '5 minutes') then
    raise exception 'choose a time in the future' using errcode = '22023';
  end if;
  if v_id is null then
    insert into inf.announcements (title, body, link, segment, channels, status, scheduled_at)
    values (trim(p ->> 'title'), trim(p ->> 'body'), nullif(p ->> 'link', ''), coalesce(p -> 'segment', '{}'),
            coalesce(array(select jsonb_array_elements_text(p -> 'channels')), '{}'), v_status, v_at)
    returning id into v_id;
  else
    update inf.announcements set title = trim(p ->> 'title'), body = trim(p ->> 'body'), link = nullif(p ->> 'link', ''),
           segment = coalesce(p -> 'segment', '{}'), channels = coalesce(array(select jsonb_array_elements_text(p -> 'channels')), '{}'),
           status = v_status, scheduled_at = v_at
     where id = v_id and status in ('draft', 'scheduled');
    if not found then raise exception 'only drafts and scheduled announcements can change' using errcode = '22023'; end if;
  end if;
  if p ->> 'action' = 'send' then perform inf.announcements_send_due(); end if;
  return v_id;
end $$;

create or replace function inf.announcement_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('announcement.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.announcements set status = 'cancelled' where id = p_id and status in ('draft', 'scheduled');
  if not found then raise exception 'only drafts and scheduled announcements can be cancelled' using errcode = '22023'; end if;
end $$;

-- Sends every scheduled announcement that is due (pg_cron every 5 minutes, and at once when staff press Send).
create or replace function inf.announcements_send_due() returns int
language plpgsql security definer set search_path = '' as $$
declare a inf.announcements; v_n int; v_total int := 0;
begin
  for a in select * from inf.announcements where status = 'scheduled' and scheduled_at <= now() order by scheduled_at for update skip locked loop
    select count(*) into v_n from (
      select inf.notify(x.user_id, 'announcement', a.title, a.body, coalesce(a.link, '/creator'),
                        jsonb_build_object('announcement_id', a.id), false, 'announcement:' || a.id || ':' || x.user_id, a.channels)
        from inf.announcement_audience(a.segment) x) s;
    update inf.announcements set status = 'sent', sent_at = now(), recipients = v_n where id = a.id;
    v_total := v_total + v_n;
  end loop;
  return v_total;
end $$;

create or replace function inf.announcements_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'link', a.link, 'segment', a.segment,
                                               'channels', a.channels, 'status', a.status, 'scheduled_at', a.scheduled_at, 'sent_at', a.sent_at,
                                               'recipients', a.recipients, 'created_at', a.created_at,
                                               'created_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = a.created_by))
                             order by coalesce(a.sent_at, a.scheduled_at, a.created_at) desc), '[]')
    from inf.announcements a
   where inf.has_perm('announcement.write')
$$;

-- Announcements a creator received (newest first), for the home page.
create or replace function inf.my_announcements(p_limit int default 3) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'body', x.body, 'link', x.link, 'created_at', x.created_at,
                                               'read_at', x.read_at) order by x.created_at desc), '[]')
    from (select n.* from inf.notifications n where n.user_id = auth.uid() and n.event = 'announcement'
           order by n.created_at desc limit least(greatest(p_limit, 1), 20)) x
   where inf.session_ok()
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Digests (built and sent by the digest.run job)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.digest_preference_set(p_frequency text, p_channel text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_frequency not in ('off', 'daily', 'weekly') or p_channel not in ('email', 'whatsapp') then
    raise exception 'invalid digest choice' using errcode = '22023';
  end if;
  insert into inf.digest_preferences (user_id, frequency, channel) values (auth.uid(), p_frequency, p_channel)
  on conflict (user_id) do update set frequency = excluded.frequency, channel = excluded.channel, updated_at = now();
end $$;

-- Who gets a digest today (service role). Creators default to weekly email, staff to off.
create or replace function inf.digest_recipients(p_today date) returns table (user_id uuid, kind text, frequency text, channel text, creator_id uuid)
language sql stable security definer set search_path = '' as $$
  with people as (
    select ca.user_id, 'creator' as kind, ca.creator_id from inf.creator_accounts ca join inf.creators c on c.id = ca.creator_id
     where c.status = 'active' and not c.is_blocked
    union all
    select sp.user_id, 'staff', null from inf.staff_profiles sp where sp.status = 'active')
  select p.user_id, p.kind, coalesce(d.frequency, case p.kind when 'creator' then 'weekly' else 'off' end), coalesce(d.channel, 'email'), p.creator_id
    from people p left join inf.digest_preferences d on d.user_id = p.user_id
   where coalesce(auth.role(), '') = 'service_role'
     and (coalesce(d.frequency, case p.kind when 'creator' then 'weekly' else 'off' end) = 'daily'
          or (coalesce(d.frequency, case p.kind when 'creator' then 'weekly' else 'off' end) = 'weekly' and extract(isodow from p_today) = 1))
$$;

-- The facts a digest summarises (service role): a creator's last day or week, or the staff queues now.
create or replace function inf.digest_facts(p_user uuid, p_kind text, p_days int, p_creator uuid default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case p_kind
    when 'creator' then jsonb_build_object(
      'name', (select split_part(c.display_name, ' ', 1) from inf.creators c where c.id = p_creator),
      'new_leads', (select count(*) from inf.lead_attributions a where a.creator_id = p_creator and not a.is_test
                      and a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last')
                      and a.lead_created_at >= now() - make_interval(days => p_days)),
      'enrolled', (select count(*) from inf.lead_stage_events e join inf.lead_attributions a on a.id = e.attribution_id
                    where a.creator_id = p_creator and e.creator_stage = 'enrolled' and e.occurred_at >= now() - make_interval(days => p_days)),
      'earned_paise', (select coalesce(sum(case when e.direction = 'credit' then e.amount_paise else -e.amount_paise end), 0)
                         from inf.ledger_entries e where e.creator_id = p_creator and e.type not in ('tds', 'gst', 'payout')
                          and e.posted_at >= now() - make_interval(days => p_days)),
      'payable_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                                 else -(e.confirmed_paise - e.paid_paise) end), 0)
                          from inf.ledger_entries e where e.creator_id = p_creator and e.status = 'payable'),
      'due_soon', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id where d.creator_id = p_creator
                     and v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                     and (v.due_dates ->> 'live')::date between inf.ist_date(now()) and inf.ist_date(now()) + 7),
      'overdue', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id where d.creator_id = p_creator
                    and v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                    and (v.due_dates ->> 'live')::date < inf.ist_date(now())),
      'unread_messages', (select count(*) from inf.notifications n where n.user_id = p_user and n.read_at is null
                            and n.event in ('thread.message', 'thread.mention')))
    else jsonb_build_object(
      'overdue_deliverables', (select count(*) from inf.deliverables v
                                where v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                                  and (v.due_dates ->> 'live')::date < inf.ist_date(now())),
      'pending_reviews', (select count(*) from inf.deliverables v where v.status in ('concept_submitted', 'draft_submitted')),
      'pending_negotiations', (select count(*) from inf.deals d where d.status in ('proposed', 'negotiating'))
                              + (select count(*) from inf.contracts k where k.status in ('sent', 'in_negotiation')),
      'contracts_expiring', (select count(*) from inf.contracts k join inf.deals d on d.id = k.deal_id
                              where k.status = 'active' and d.ends_on between inf.ist_date(now()) and inf.ist_date(now()) + 30),
      'payouts_due_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                                     else -(e.confirmed_paise - e.paid_paise) end), 0)
                              from inf.ledger_entries e where e.status = 'payable'),
      'kyc_pending', (select count(*) from inf.creator_kyc k where k.status = 'submitted'),
      'fraud_flags', (select count(*) from inf.fraud_flags f where f.status = 'open'),
      'unread_messages', (select count(*) from inf.notifications n where n.user_id = p_user and n.read_at is null
                            and n.event in ('thread.message', 'thread.mention')))
  end
   where coalesce(auth.role(), '') = 'service_role'
$$;

-- Sends one digest (service role): an in-app notification and the chosen channel.
create or replace function inf.digest_send(p_user uuid, p_kind text, p_title text, p_body text, p_channel text, p_date date) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  return inf.notify(p_user, 'digest.' || p_kind, p_title, p_body, case p_kind when 'creator' then '/creator' else '/admin' end,
                    jsonb_build_object('date', p_date), false, 'digest:' || p_user || ':' || p_date, array[p_channel]);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Outbound webhooks (spec 18): signed, retried, logged; payloads never carry student contact details
-- ---------------------------------------------------------------------------------------------------------------
create table inf.webhook_endpoints (
  id               uuid primary key default gen_random_uuid(),
  url              text not null check (url ~ '^https://[A-Za-z0-9.-]+(:\d{2,5})?(/[^\s]*)?$' and char_length(url) <= 500),
  description      text check (char_length(description) <= 200),
  events           text[] not null check (array_length(events, 1) >= 1
                                          and events <@ array['lead.attributed', 'lead.enrolled', 'contract.signed', 'deliverable.live',
                                                              'payout.paid', 'creator.activated']),
  secret_enc       bytea not null,
  active           boolean not null default true,
  created_by       uuid not null default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  last_success_at  timestamptz,
  failing_since    timestamptz
);
create trigger webhook_endpoints_touch before update on inf.webhook_endpoints for each row execute function inf.touch_updated_at();
create trigger webhook_endpoints_audit after insert or update or delete on inf.webhook_endpoints
  for each row execute function inf.audit_row('webhook_endpoint', 'secret_enc');

create table inf.webhook_deliveries (
  id               bigint generated always as identity primary key,
  endpoint_id      uuid not null references inf.webhook_endpoints (id) on delete cascade,
  event            text not null,
  event_id         text not null,
  payload          jsonb not null,
  status           text not null default 'queued' check (status in ('queued', 'delivered', 'failed')),
  attempts         int not null default 0,
  next_attempt_at  timestamptz not null default now(),
  last_status      int,
  last_error       text check (char_length(last_error) <= 500),
  created_at       timestamptz not null default now(),
  delivered_at     timestamptz,
  unique (endpoint_id, event_id)
);
create index webhook_deliveries_endpoint_idx on inf.webhook_deliveries (endpoint_id, created_at desc);

-- Hosts that must never receive webhooks (loopback, private and link-local ranges, metadata services).
create or replace function inf.webhook_host_ok(p_url text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(substring(p_url from '^https://([^/:]+)'), '') !~* '^(localhost|.*\.local|.*\.internal|127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|0\.|\[|::1|metadata)'
$$;

create or replace function inf.webhook_endpoint_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not inf.has_perm('webhook.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not inf.webhook_host_ok(p ->> 'url') then raise exception 'this address cannot receive webhooks' using errcode = '22023'; end if;
  if coalesce(char_length(p ->> 'secret'), 0) < 32 then raise exception 'invalid secret' using errcode = '22023'; end if;
  insert into inf.webhook_endpoints (url, description, events, secret_enc)
  values (p ->> 'url', nullif(trim(p ->> 'description'), ''), array(select jsonb_array_elements_text(p -> 'events')), inf.pii_encrypt(p ->> 'secret'))
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.webhook_endpoint_update(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('webhook.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.webhook_endpoints set
    description = coalesce(nullif(trim(p ->> 'description'), ''), description),
    events = case when p ? 'events' then array(select jsonb_array_elements_text(p -> 'events')) else events end,
    active = coalesce((p ->> 'active')::boolean, active),
    secret_enc = case when coalesce(char_length(p ->> 'secret'), 0) >= 32 then inf.pii_encrypt(p ->> 'secret') else secret_enc end,
    failing_since = case when (p ->> 'active')::boolean then null else failing_since end
   where id = p_id;
  if not found then raise exception 'no such endpoint' using errcode = '22023'; end if;
end $$;

create or replace function inf.webhook_endpoint_delete(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('webhook.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.webhook_endpoints where id = p_id;
end $$;

create or replace function inf.webhooks_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', w.id, 'url', w.url, 'description', w.description, 'events', w.events, 'active', w.active, 'created_at', w.created_at,
           'last_success_at', w.last_success_at, 'failing_since', w.failing_since,
           'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'event', d.event, 'event_id', d.event_id, 'status', d.status,
                                                                       'attempts', d.attempts, 'last_status', d.last_status, 'last_error', d.last_error,
                                                                       'created_at', d.created_at, 'delivered_at', d.delivered_at,
                                                                       'next_attempt_at', d.next_attempt_at) order by d.id desc)
                                     from (select * from inf.webhook_deliveries d2 where d2.endpoint_id = w.id order by d2.id desc limit 20) d), '[]'))
           order by w.created_at), '[]')
    from inf.webhook_endpoints w
   where inf.has_perm('webhook.manage')
$$;

-- Queue a delivery and its job.
create or replace function inf.webhook_enqueue(p_endpoint uuid, p_event text, p_event_id text, p_payload jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into inf.webhook_deliveries (endpoint_id, event, event_id, payload) values (p_endpoint, p_event, p_event_id, p_payload)
  on conflict (endpoint_id, event_id) do nothing
  returning id into v_id;
  if v_id is not null then
    perform inf.job_enqueue('webhook.deliver', jsonb_build_object('delivery_id', v_id), now(), 'webhook:' || v_id, 8);
  end if;
end $$;

-- A test event to one endpoint (staff).
create or replace function inf.webhook_test(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_event text; v_eid text := 'evt_test_' || replace(gen_random_uuid()::text, '-', '');
begin
  if not inf.has_perm('webhook.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  select w.events[1] into v_event from inf.webhook_endpoints w where w.id = p_id;
  if v_event is null then raise exception 'no such endpoint' using errcode = '22023'; end if;
  perform inf.webhook_enqueue(p_id, v_event, v_eid, jsonb_build_object('id', v_eid, 'type', v_event, 'created_at', now(), 'test', true,
                                                                      'data', jsonb_build_object('message', 'Test delivery from the Eduwit creator portal')));
end $$;

-- Domain events → webhook payloads (only ids, handles, amounts and references; never contact details).
create or replace function inf.webhook_on_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_type text;
  v_data jsonb;
  v_creator uuid;
  w record;
begin
  v_type := case new.type
    when 'lead.attributed' then 'lead.attributed'
    when 'lead.enrolled' then 'lead.enrolled'
    when 'contract.countersigned' then 'contract.signed'
    when 'deliverable.live' then 'deliverable.live'
    when 'payout.paid' then 'payout.paid'
    when 'creator.approved' then 'creator.activated' end;
  if v_type is null or not exists (select 1 from inf.webhook_endpoints e where e.active and v_type = any (e.events)) then return null; end if;
  if v_type in ('lead.attributed', 'lead.enrolled') then
    select jsonb_build_object('attribution_id', a.id, 'lead_ref', inf.lead_ref(a.student_lead_id), 'creator_id', a.creator_id,
                              'creator_handle', c.handle, 'deal_id', a.deal_id, 'campaign_id', a.campaign_id, 'link_id', a.link_id,
                              'test', a.is_test)
      into v_data from inf.lead_attributions a join inf.creators c on c.id = a.creator_id where a.id = new.subject_id::uuid;
  elsif v_type = 'contract.signed' then
    select jsonb_build_object('contract_id', k.id, 'contract_number', k.number, 'deal_id', k.deal_id, 'creator_id', d.creator_id,
                              'creator_handle', c.handle, 'document_sha256', new.payload ->> 'sha256')
      into v_data from inf.contracts k join inf.deals d on d.id = k.deal_id join inf.creators c on c.id = d.creator_id
     where k.id = new.subject_id::uuid;
  elsif v_type = 'deliverable.live' then
    select jsonb_build_object('deliverable_id', x.id, 'deal_id', x.deal_id, 'creator_id', d.creator_id, 'creator_handle', c.handle,
                              'platform', x.platform, 'format', x.format,
                              'live_url', (select pp.live_url from inf.published_posts pp where pp.deliverable_id = x.id
                                            order by pp.created_at desc limit 1))
      into v_data from inf.deliverables x join inf.deals d on d.id = x.deal_id join inf.creators c on c.id = d.creator_id
     where x.id = new.subject_id::uuid;
  elsif v_type = 'payout.paid' then
    select jsonb_build_object('payout_id', p.id, 'payout_ref', p.ref, 'creator_id', p.creator_id, 'creator_handle', c.handle,
                              'net_paise', p.net_paise, 'paid_on', p.paid_on)
      into v_data from inf.payouts p join inf.creators c on c.id = p.creator_id where p.id = new.subject_id::uuid;
  else
    select jsonb_build_object('creator_id', c.id, 'creator_handle', c.handle) into v_data from inf.creators c where c.id = new.subject_id::uuid;
  end if;
  if v_data is null then return null; end if;
  for w in select e.id from inf.webhook_endpoints e where e.active and v_type = any (e.events) loop
    perform inf.webhook_enqueue(w.id, v_type, 'evt_' || new.id,
                                jsonb_build_object('id', 'evt_' || new.id, 'type', v_type, 'created_at', new.occurred_at, 'data', v_data));
  end loop;
  return null;
end $$;
create trigger domain_events_webhooks after insert on inf.domain_events for each row execute function inf.webhook_on_event();

-- For the delivery job (service role): the request to make, with the decrypted signing secret.
create or replace function inf.webhook_delivery_get(p_id bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', d.id, 'url', w.url, 'secret', inf.pii_decrypt(w.secret_enc), 'payload', d.payload, 'event', d.event,
                            'attempts', d.attempts, 'status', d.status, 'active', w.active)
    from inf.webhook_deliveries d join inf.webhook_endpoints w on w.id = d.endpoint_id
   where coalesce(auth.role(), '') = 'service_role' and d.id = p_id
$$;

-- Records an attempt (service role). p_next_at is the next attempt (from lib/webhooks/sign.ts), or null to stop.
create or replace function inf.webhook_delivery_result(p_id bigint, p_outcome text, p_status int default null,
                                                       p_error text default null, p_next_at timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare d inf.webhook_deliveries;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.webhook_deliveries set
    attempts = attempts + 1, last_status = p_status, last_error = left(p_error, 500),
    status = case when p_outcome = 'delivered' then 'delivered' when p_outcome = 'retry' and p_next_at is not null then 'queued' else 'failed' end,
    delivered_at = case when p_outcome = 'delivered' then now() else delivered_at end,
    next_attempt_at = coalesce(p_next_at, next_attempt_at)
   where id = p_id
  returning * into d;
  if d.id is null then return; end if;
  update inf.webhook_endpoints set
    last_success_at = case when p_outcome = 'delivered' then now() else last_success_at end,
    failing_since = case when p_outcome = 'delivered' then null else coalesce(failing_since, now()) end
   where id = d.endpoint_id;
  if d.status = 'queued' then
    perform inf.job_enqueue('webhook.deliver', jsonb_build_object('delivery_id', d.id), p_next_at, 'webhook:' || d.id || ':' || d.attempts, 8);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- The catalogue events still missing
-- ---------------------------------------------------------------------------------------------------------------
-- "₹X earned" for an enrolment, a commission that is no longer earned (with what is recovered if it was paid), and
-- fixed amounts that became due (on posting or later). One message per enrolment: a re-post after an amount change
-- (reversal note 'Amount changed', see inf.ledger_apply) does not repeat it.
create or replace function inf.ledger_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_user uuid; v_lead text; v_orig inf.ledger_entries;
begin
  select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = new.creator_id;
  if v_user is null then return null; end if;
  if tg_op = 'INSERT' and new.type = 'commission' and new.direction = 'credit' and new.subject like 'enrol:%' then
    select inf.lead_ref(a.student_lead_id) into v_lead from inf.lead_attributions a where a.id = new.attribution_id;
    perform inf.notify(v_user, 'lead.enrolled', 'A student enrolled: ' || inf.inr(new.amount_paise) || ' earned',
                       'Commission for lead ' || coalesce(v_lead, 'from your link') || '. It is confirmed when Eduwit receives its commission.',
                       '/creator/earnings', jsonb_build_object('entry_id', new.id, 'amount', inf.inr(new.amount_paise), 'lead', v_lead), false,
                       'lead_enrolled:' || new.creator_id || ':' || new.subject);
  elsif tg_op = 'INSERT' and new.type = 'reversal' and new.note = 'No longer earned' then
    select * into v_orig from inf.ledger_entries where id = new.reverses_id;
    if v_orig.type = 'commission' and v_orig.subject like 'enrol:%' then
      perform inf.notify(v_user, 'lead.clawed_back', inf.inr(v_orig.amount_paise) || ' commission no longer earned',
                         'The enrolment was cancelled or refunded. '
                         || case when new.confirmed_paise > 0 then inf.inr(new.confirmed_paise) || ' already paid is recovered from your next payouts.'
                                 else 'It had not been paid, so nothing is recovered.' end,
                         '/creator/earnings', jsonb_build_object('entry_id', new.id, 'amount', inf.inr(v_orig.amount_paise)), true,
                         'lead_clawed_back:' || new.creator_id || ':' || v_orig.subject);
    end if;
  end if;
  if new.status = 'payable' and (tg_op = 'INSERT' or old.status is distinct from 'payable')
     and new.type in ('fixed_fee', 'milestone', 'bonus', 'usage_fee', 'exclusivity_fee') then
    perform inf.notify(v_user, 'ledger.payable', inf.inr(new.confirmed_paise - new.paid_paise) || ' is due to you',
                       coalesce(new.note, 'A payment') || ' goes out in the next payout run.', '/creator/earnings',
                       jsonb_build_object('entry_id', new.id, 'amount', inf.inr(new.confirmed_paise - new.paid_paise)), true,
                       'ledger_payable:' || new.id);
  end if;
  return null;
end $$;

-- ₹ amounts for notification text.
create or replace function inf.inr(p_paise bigint) returns text
language sql immutable set search_path = '' as $$
  -- Same output as formatPaise() in lib/format.ts: Indian grouping, exact paise, sign before the symbol.
  select case when p_paise < 0 then '-' else '' end || '₹'
         || case when r < 1000 then r::text
                 else regexp_replace(left(r::text, -3), '(\d)(?=(\d\d)+$)', '\1,', 'g') || ',' || right(r::text, 3) end
         || '.' || lpad((abs(p_paise) % 100)::text, 2, '0')
    from (select abs(p_paise) / 100 as r) x
$$;

create trigger ledger_entries_notify after insert or update of status on inf.ledger_entries
  for each row execute function inf.ledger_notify();

-- Fraud flags reach the staff who review them.
create or replace function inf.fraud_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform inf.notify(sp.user_id, 'fraud.flagged', 'Fraud flag: ' || c.display_name,
                     'Signal: ' || replace(new.signal, '_', ' ') || '. Review it in Leads → Fraud review.', '/admin/leads/fraud',
                     jsonb_build_object('flag_id', new.id, 'creator', c.display_name), false, 'fraud_flagged:' || new.id || ':' || sp.user_id)
    from inf.staff_profiles sp, inf.creators c
   where c.id = new.creator_id and sp.status = 'active'
     and exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                  where g.user_id = sp.user_id and rp.permission = 'fraud.review');
  return null;
end $$;
create trigger fraud_flags_notify after insert on inf.fraud_flags for each row execute function inf.fraud_notify();

-- Daily nudges (pg_cron 09:00 IST): KYC needed for payouts, reviews waiting, negotiations waiting.
create or replace function inf.comm_daily() returns void
language plpgsql security definer set search_path = '' as $$
declare v_week text := to_char(inf.ist_date(now()), 'IYYY-IW'); v_day text := to_char(inf.ist_date(now()), 'YYYY-MM-DD');
begin
  perform inf.notify(ca.user_id, 'kyc.action_needed', 'Complete your KYC to get paid',
                     'You have earnings due, but payouts need a verified PAN and bank account.', '/creator/kyc', '{}'::jsonb, true,
                     'kyc_action_needed:' || ca.creator_id || ':' || v_week)
    from inf.creator_accounts ca
   where exists (select 1 from inf.ledger_entries e where e.creator_id = ca.creator_id and e.status = 'payable')
     and not exists (select 1 from inf.creator_kyc k where k.creator_id = ca.creator_id and k.status = 'verified');
  perform inf.notify(sp.user_id, 'staff.review_pending', q.n || ' waiting for review', 'Concepts and drafts submitted more than a day ago.',
                     '/admin/content', jsonb_build_object('count', q.n), false, 'review_pending:' || sp.user_id || ':' || v_day)
    from inf.staff_profiles sp,
         lateral (select count(*) as n from inf.deliverables v
                   where v.status in ('concept_submitted', 'draft_submitted') and v.updated_at < now() - interval '24 hours') q
   where sp.status = 'active' and q.n > 0
     and exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                  where g.user_id = sp.user_id and rp.permission = 'deliverable.review');
  perform inf.notify(sp.user_id, 'staff.negotiation_pending', q.n || ' negotiations waiting', 'Deals or contracts with no answer for three days.',
                     '/admin/deals', jsonb_build_object('count', q.n), false, 'negotiation_pending:' || sp.user_id || ':' || v_day)
    from inf.staff_profiles sp,
         lateral (select (select count(*) from inf.deals d where d.owner_id = sp.user_id and d.status in ('proposed', 'negotiating')
                            and d.updated_at < now() - interval '3 days')
                         + (select count(*) from inf.contracts k join inf.deals d on d.id = k.deal_id
                             where d.owner_id = sp.user_id and k.status in ('sent', 'in_negotiation') and k.updated_at < now() - interval '3 days') as n) q
   where sp.status = 'active' and q.n > 0;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Schedules, RLS, grants
-- ---------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('inf-announcements', '*/5 * * * *', $c$select inf.announcements_send_due()$c$);
    perform cron.schedule('inf-comm-daily', '30 3 * * *', $c$select inf.comm_daily()$c$);  -- 09:00 IST
    perform cron.schedule('inf-digests', '30 2 * * *',
      $c$select inf.job_enqueue('digest.run', jsonb_build_object('date', inf.ist_date(now())), now(), 'digest:' || inf.ist_date(now()))$c$);  -- 08:00 IST
  end if;
end $$;

alter table inf.notification_events enable row level security;
alter table inf.message_attachments enable row level security;
alter table inf.message_mentions enable row level security;
alter table inf.thread_reads enable row level security;
alter table inf.announcements enable row level security;
alter table inf.digest_preferences enable row level security;
alter table inf.webhook_endpoints enable row level security;
alter table inf.webhook_deliveries enable row level security;
-- The catalogue is public knowledge inside the portal.
create policy notification_events_read on inf.notification_events for select to authenticated using (true);

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.notification_events', 'authenticated', 'select'),
  ('function', 'inf.my_notification_preferences()', 'authenticated', 'execute'),
  ('function', 'inf.my_notifications_page(int, timestamptz, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.notifications_mark_all_read()', 'authenticated', 'execute'),
  ('function', 'inf.thread_get(text, uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.thread_post(text, uuid, text, jsonb, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.thread_mark_read(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.thread_open(text, uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.thread_file_allowed(text)', 'authenticated', 'execute'),
  ('function', 'inf.my_threads(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.my_unread_counts()', 'authenticated', 'execute'),
  ('function', 'inf.mentionable_staff()', 'authenticated', 'execute'),
  ('function', 'inf.notification_template_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.notification_template_reset(text, text)', 'authenticated', 'execute'),
  ('function', 'inf.notification_templates_list()', 'authenticated', 'execute'),
  ('function', 'inf.announcement_audience_count(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.announcement_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.announcement_cancel(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.announcements_list()', 'authenticated', 'execute'),
  ('function', 'inf.my_announcements(int)', 'authenticated', 'execute'),
  ('function', 'inf.digest_preference_set(text, text)', 'authenticated', 'execute'),
  ('function', 'inf.webhook_endpoint_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.webhook_endpoint_update(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.webhook_endpoint_delete(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.webhooks_list()', 'authenticated', 'execute'),
  ('function', 'inf.webhook_test(uuid)', 'authenticated', 'execute');
call inf.apply_client_grants();
