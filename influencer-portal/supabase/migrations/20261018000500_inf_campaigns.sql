-- Phase 2.5: campaigns, the creator marketplace, invites, applications and negotiation (spec 5, 13).
-- A campaign links catalogue programmes (soft references: Witty's catalogue loads must never be blocked by our rows),
-- has eligibility rules, slots and visibility. Creators see open campaigns they're eligible for and apply with a
-- pitch and proposed terms; staff invite creators directly. Both sides negotiate with structured offers plus a message
-- thread. Accepting an offer emits `application.accepted` with the agreed terms; Phase 3 turns it into a deal,
-- contract, brief and deliverables. Agencies with the creator's "negotiate" grant can act for the creator.

-- ---------------------------------------------------------------------------------------------------------------
-- Campaigns
-- ---------------------------------------------------------------------------------------------------------------
create table inf.campaigns (
  id                     uuid primary key default gen_random_uuid(),
  name                   text not null check (char_length(name) between 3 and 120),
  objective              text not null check (objective in ('leads', 'enrolments', 'awareness', 'content')),
  description            text check (char_length(description) <= 8000),
  status                 text not null default 'draft'
                           check (status in ('draft', 'open', 'invite_only', 'active', 'paused', 'completed', 'archived')),
  visibility             text not null default 'open' check (visibility in ('open', 'invite_only', 'both')),
  starts_on              date,
  ends_on                date,
  apply_by               date,
  budget_paise           bigint check (budget_paise >= 0),
  slots                  int check (slots between 1 and 10000),
  eligibility            jsonb not null default '{}'::jsonb check (jsonb_typeof(eligibility) = 'object'),
  deliverables           jsonb not null default '[]'::jsonb check (jsonb_typeof(deliverables) = 'array' and jsonb_array_length(deliverables) <= 20),
  compensation_summary   text check (char_length(compensation_summary) <= 1000),
  internal_notes         text check (char_length(internal_notes) <= 4000),
  owner_id               uuid references inf.staff_profiles (user_id) on delete set null,
  created_by             uuid not null default auth.uid(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on),
  check (apply_by is null or ends_on is null or apply_by <= ends_on)
);
create index campaigns_status_idx on inf.campaigns (status, apply_by);

-- Programme ids from the shared catalogue (public.catalog_programs). No foreign key, on purpose (see header).
create table inf.campaign_programmes (
  campaign_id   uuid not null references inf.campaigns (id) on delete cascade,
  programme_id  bigint not null,
  position      int not null default 0,
  primary key (campaign_id, programme_id)
);

create table inf.campaign_invites (
  id            uuid primary key default gen_random_uuid(),
  campaign_id   uuid not null references inf.campaigns (id) on delete cascade,
  creator_id    uuid not null references inf.creators (id) on delete cascade,
  status        text not null default 'sent' check (status in ('sent', 'accepted', 'declined', 'countered', 'withdrawn')),
  message       text check (char_length(message) <= 2000),
  sent_by       uuid not null default auth.uid(),
  sent_at       timestamptz not null default now(),
  responded_at  timestamptz,
  application_id uuid,
  unique (campaign_id, creator_id)
);

create table inf.campaign_applications (
  id                uuid primary key default gen_random_uuid(),
  campaign_id       uuid not null references inf.campaigns (id) on delete cascade,
  creator_id        uuid not null references inf.creators (id) on delete cascade,
  source            text not null default 'marketplace' check (source in ('marketplace', 'invite')),
  pitch             text check (char_length(pitch) <= 4000),
  sample_links      text[] not null default '{}' check (cardinality(sample_links) <= 10),
  status            text not null default 'submitted'
                      check (status in ('submitted', 'shortlisted', 'countered', 'accepted', 'rejected', 'withdrawn')),
  rejection_reason  text check (char_length(rejection_reason) <= 1000),
  accepted_terms    jsonb,
  decided_by        uuid,
  decided_at        timestamptz,
  submitted_by      uuid not null default auth.uid(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (campaign_id, creator_id)
);
create index campaign_applications_status_idx on inf.campaign_applications (status, created_at);
alter table inf.campaign_invites add constraint campaign_invites_application_fk
  foreign key (application_id) references inf.campaign_applications (id) on delete set null;

-- Structured offers on an application. The newest open offer is "on the table"; any new offer supersedes it.
-- terms: {deal_type: fixed|commission|hybrid|barter, fixed_fee_paise?, includes_commission?, deliverables:[{platform,
--         format, count}], usage_rights?, exclusivity_days?, notes?}  (validated in the app with zod)
create table inf.application_offers (
  id              uuid primary key default gen_random_uuid(),
  application_id  uuid not null references inf.campaign_applications (id) on delete cascade,
  from_side       text not null check (from_side in ('creator', 'eduwit')),
  terms           jsonb not null check (jsonb_typeof(terms) = 'object' and pg_column_size(terms) < 8192),
  message         text check (char_length(message) <= 2000),
  status          text not null default 'open' check (status in ('open', 'superseded', 'accepted', 'rejected')),
  created_by      uuid not null default auth.uid(),
  created_at      timestamptz not null default now()
);
create index application_offers_app_idx on inf.application_offers (application_id, created_at desc);
create unique index application_offers_one_open on inf.application_offers (application_id) where status = 'open';

-- Message threads attached to a record (Phase 9 adds attachments, read receipts and mentions).
create table inf.threads (
  id           uuid primary key default gen_random_uuid(),
  entity_type  text not null check (entity_type in ('application')),
  entity_id    uuid not null,
  created_at   timestamptz not null default now(),
  unique (entity_type, entity_id)
);
create table inf.messages (
  id           uuid primary key default gen_random_uuid(),
  thread_id    uuid not null references inf.threads (id) on delete cascade,
  author_id    uuid not null default auth.uid(),
  author_side  text not null check (author_side in ('creator', 'agency', 'eduwit')),
  body         text not null check (char_length(body) between 1 and 4000),
  created_at   timestamptz not null default now()
);
create index messages_thread_idx on inf.messages (thread_id, created_at);
create trigger messages_append_only before update or delete on inf.messages for each row execute function inf.forbid_mutation();

-- Reasons staff pick from when rejecting an application (editable list).
create table inf.reason_templates (
  id        uuid primary key default gen_random_uuid(),
  kind      text not null check (kind in ('application_rejection')),
  label     text not null check (char_length(label) between 2 and 80),
  body      text not null check (char_length(body) between 5 and 1000),
  position  int not null default 0,
  active    boolean not null default true,
  unique (kind, label)
);
insert into inf.reason_templates (kind, label, body, position) values
  ('application_rejection', 'Audience fit', 'Thank you for applying. Your audience isn''t the best match for this campaign''s programmes, so we won''t go ahead this time. We''ll keep you in mind for future campaigns.', 1),
  ('application_rejection', 'Slots filled', 'Thank you for applying. All slots for this campaign are now filled. Watch the marketplace for new campaigns.', 2),
  ('application_rejection', 'Terms', 'Thank you for applying. We couldn''t agree on terms that work within this campaign''s budget.', 3),
  ('application_rejection', 'Content fit', 'Thank you for applying. Your recent content isn''t the right fit for this campaign''s brief.', 4);

create trigger campaigns_touch before update on inf.campaigns for each row execute function inf.touch_updated_at();
create trigger campaign_applications_touch before update on inf.campaign_applications for each row execute function inf.touch_updated_at();
create trigger campaigns_audit after insert or update or delete on inf.campaigns for each row execute function inf.audit_row('campaign');
create trigger campaign_programmes_audit after insert or delete on inf.campaign_programmes for each row execute function inf.audit_row('campaign_programme');
create trigger campaign_invites_audit after insert or update on inf.campaign_invites for each row execute function inf.audit_row('campaign_invite');
create trigger campaign_applications_audit after insert or update on inf.campaign_applications for each row execute function inf.audit_row('campaign_application');
create trigger application_offers_audit after insert or update on inf.application_offers for each row execute function inf.audit_row('application_offer');
create trigger reason_templates_audit after insert or update or delete on inf.reason_templates for each row execute function inf.audit_row('reason_template');

-- ---------------------------------------------------------------------------------------------------------------
-- Catalogue reads (SHARED_CHANGES S-11): programme picker for staff, programme cards for creators.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.catalog_programmes_search(p_q text, p_limit int default 20)
returns table (id bigint, program_name text, specialization text, level text, mode text, university text, fee_total numeric)
language sql stable security definer set search_path = '' as $$
  select p.id, p.program_name, p.specialization, p.level, p.mode, u.name, p.fee_total
    from public.catalog_programs p join public.catalog_universities u on u.id = p.university_id
   where inf.has_perm('campaign.write') and p.active
     and (nullif(trim(p_q), '') is null or p.search_doc @@ plainto_tsquery('simple', p_q)
          or p.program_name ilike '%' || replace(replace(trim(p_q), '%', '\%'), '_', '\_') || '%'
          or u.name ilike '%' || replace(replace(trim(p_q), '%', '\%'), '_', '\_') || '%')
   order by u.name, p.program_name
   limit least(greatest(p_limit, 1), 50);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Eligibility and visibility
-- ---------------------------------------------------------------------------------------------------------------
-- Reasons a creator doesn't meet a campaign's rules (empty array = eligible). Rules keys (all optional):
-- min_followers (sum over the listed platforms, or all platforms), platforms[], niches[], languages[], states[].
create or replace function inf.eligibility_gaps(p_campaign uuid, p_creator uuid) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare
  r jsonb; c inf.creators; v_platforms text[]; v_followers bigint; v_gaps text[] := '{}';
begin
  select eligibility into r from inf.campaigns where id = p_campaign;
  select * into c from inf.creators where id = p_creator;
  if c.id is null or r is null then return array['unknown']; end if;
  if c.approved_at is null or c.status <> 'active' or c.is_blocked then v_gaps := array_append(v_gaps, 'not_approved'); end if;
  v_platforms := coalesce((select array_agg(x) from jsonb_array_elements_text(r -> 'platforms') x), '{}');
  select coalesce(sum(p.followers), 0) into v_followers from inf.creator_platforms p
   where p.creator_id = p_creator and (cardinality(v_platforms) = 0 or p.platform = any(v_platforms));
  if cardinality(v_platforms) > 0 and not exists (select 1 from inf.creator_platforms p where p.creator_id = p_creator and p.platform = any(v_platforms)) then
    v_gaps := array_append(v_gaps, 'platform');
  end if;
  if coalesce((r ->> 'min_followers')::bigint, 0) > v_followers then v_gaps := array_append(v_gaps, 'followers'); end if;
  if jsonb_array_length(coalesce(r -> 'niches', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(r -> 'niches') n where lower(n) = any(c.niches)) then
    v_gaps := array_append(v_gaps, 'niche');
  end if;
  if jsonb_array_length(coalesce(r -> 'languages', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(r -> 'languages') l, unnest(c.languages) cl where lower(l) = lower(cl)) then
    v_gaps := array_append(v_gaps, 'language');
  end if;
  if jsonb_array_length(coalesce(r -> 'states', '[]')) > 0
     and not exists (select 1 from jsonb_array_elements_text(r -> 'states') s where lower(s) = lower(coalesce(c.state, ''))) then
    v_gaps := array_append(v_gaps, 'geography');
  end if;
  return v_gaps;
end $$;

-- Who acts for the creator: the creator themself or an agency with the "negotiate" grant.
create or replace function inf.can_negotiate_for(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'negotiate');
$$;

-- Staff with campaign.read; a creator (or their negotiating agency) who was invited or applied, or for whom the
-- campaign is open in the marketplace.
create or replace function inf.can_see_campaign(p_campaign uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select inf.has_perm('campaign.read') or exists (
    select 1 from inf.campaigns c
     where c.id = p_campaign and c.status not in ('draft', 'archived')
       and ((c.visibility in ('open', 'both') and c.status in ('open', 'active') and inf.current_creator_id() is not null)
            or exists (select 1 from inf.campaign_invites i where i.campaign_id = c.id and inf.can_negotiate_for(i.creator_id))
            or exists (select 1 from inf.campaign_applications a where a.campaign_id = c.id and inf.can_negotiate_for(a.creator_id))));
$$;

-- Programmes of a campaign, for anyone who may see the campaign.
create or replace function inf.campaign_programmes_view(p_campaign uuid)
returns table (id bigint, program_name text, specialization text, level text, mode text, university text, fee_total numeric, available boolean)
language sql stable security definer set search_path = '' as $$
  select cp.programme_id, p.program_name, p.specialization, p.level, p.mode, u.name, p.fee_total, coalesce(p.active, false)
    from inf.campaign_programmes cp
    left join public.catalog_programs p on p.id = cp.programme_id
    left join public.catalog_universities u on u.id = p.university_id
   where cp.campaign_id = p_campaign and inf.can_see_campaign(p_campaign)
   order by cp.position, cp.programme_id;
$$;

-- What creators may see of a campaign (no budget or internal notes), plus their own standing.
create or replace function inf.campaign_public(c inf.campaigns, p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'objective', c.objective, 'description', c.description, 'status', c.status,
    'visibility', c.visibility, 'starts_on', c.starts_on, 'ends_on', c.ends_on, 'apply_by', c.apply_by,
    'deliverables', c.deliverables, 'compensation_summary', c.compensation_summary, 'eligibility', c.eligibility,
    'slots', c.slots,
    'slots_left', case when c.slots is null then null
                       else greatest(c.slots - (select count(*) from inf.campaign_applications a where a.campaign_id = c.id and a.status = 'accepted'), 0) end,
    'gaps', to_jsonb(inf.eligibility_gaps(c.id, p_creator)),
    'application', (select jsonb_build_object('id', a.id, 'status', a.status) from inf.campaign_applications a where a.campaign_id = c.id and a.creator_id = p_creator),
    'invite', (select jsonb_build_object('id', i.id, 'status', i.status, 'message', i.message) from inf.campaign_invites i where i.campaign_id = c.id and i.creator_id = p_creator));
$$;

-- Creator marketplace: open campaigns they're eligible for (or all open ones with their gaps when p_all).
create or replace function inf.marketplace(p_creator uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_creator uuid := coalesce(p_creator, inf.current_creator_id());
begin
  if v_creator is null or not inf.can_negotiate_for(v_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(x order by (x ->> 'apply_by') nulls last, x ->> 'name')
      from (select inf.campaign_public(c, v_creator) as x
              from inf.campaigns c
             where c.visibility in ('open', 'both') and c.status in ('open', 'active')
               and (c.apply_by is null or c.apply_by >= (now() at time zone 'Asia/Kolkata')::date)) s
     where p_all or jsonb_array_length(x -> 'gaps') = 0 or x -> 'application' <> 'null'::jsonb), '[]');
end $$;

create or replace function inf.campaign_for_creator(p_campaign uuid, p_creator uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_creator uuid := coalesce(p_creator, inf.current_creator_id()); c inf.campaigns;
begin
  if v_creator is null or not inf.can_negotiate_for(v_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.campaigns where id = p_campaign;
  if c.id is null or c.status in ('draft', 'archived') then return null; end if;
  if not (c.visibility in ('open', 'both') and c.status in ('open', 'active'))
     and not exists (select 1 from inf.campaign_invites i where i.campaign_id = c.id and i.creator_id = v_creator)
     and not exists (select 1 from inf.campaign_applications a where a.campaign_id = c.id and a.creator_id = v_creator) then
    return null;
  end if;
  return inf.campaign_public(c, v_creator);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff: campaigns
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.campaign_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_prog bigint; v_pos int := 0;
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.campaigns (name, objective, description, visibility, starts_on, ends_on, apply_by, budget_paise, slots,
                               eligibility, deliverables, compensation_summary, internal_notes, owner_id)
    values (trim(p ->> 'name'), p ->> 'objective', nullif(trim(p ->> 'description'), ''), coalesce(nullif(p ->> 'visibility', ''), 'open'),
            nullif(p ->> 'starts_on', '')::date, nullif(p ->> 'ends_on', '')::date, nullif(p ->> 'apply_by', '')::date,
            nullif(p ->> 'budget_paise', '')::bigint, nullif(p ->> 'slots', '')::int, coalesce(p -> 'eligibility', '{}'),
            coalesce(p -> 'deliverables', '[]'), nullif(trim(p ->> 'compensation_summary'), ''), nullif(trim(p ->> 'internal_notes'), ''),
            coalesce(nullif(p ->> 'owner_id', '')::uuid, auth.uid()))
    returning id into v_id;
  else
    update inf.campaigns set name = trim(p ->> 'name'), objective = p ->> 'objective', description = nullif(trim(p ->> 'description'), ''),
           visibility = coalesce(nullif(p ->> 'visibility', ''), visibility), starts_on = nullif(p ->> 'starts_on', '')::date,
           ends_on = nullif(p ->> 'ends_on', '')::date, apply_by = nullif(p ->> 'apply_by', '')::date,
           budget_paise = nullif(p ->> 'budget_paise', '')::bigint, slots = nullif(p ->> 'slots', '')::int,
           eligibility = coalesce(p -> 'eligibility', '{}'), deliverables = coalesce(p -> 'deliverables', '[]'),
           compensation_summary = nullif(trim(p ->> 'compensation_summary'), ''), internal_notes = nullif(trim(p ->> 'internal_notes'), ''),
           owner_id = nullif(p ->> 'owner_id', '')::uuid
     where id = v_id;
    if not found then raise exception 'no such campaign' using errcode = '22023'; end if;
  end if;
  if p ? 'programme_ids' then
    delete from inf.campaign_programmes where campaign_id = v_id
      and programme_id not in (select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x);
    for v_prog in select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x loop
      if not exists (select 1 from public.catalog_programs where id = v_prog) then
        raise exception 'unknown programme %', v_prog using errcode = '22023';
      end if;
      insert into inf.campaign_programmes (campaign_id, programme_id, position) values (v_id, v_prog, v_pos)
      on conflict (campaign_id, programme_id) do update set position = excluded.position;
      v_pos := v_pos + 1;
    end loop;
  end if;
  return v_id;
end $$;

-- Status changes with the allowed transitions. Opening needs a name, objective, deliverables and an end date.
create or replace function inf.campaign_set_status(p_campaign uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.campaigns; v_ok boolean;
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.campaigns where id = p_campaign for update;
  if c.id is null then raise exception 'no such campaign' using errcode = '22023'; end if;
  v_ok := case c.status
    when 'draft' then p_status in ('open', 'invite_only', 'archived')
    when 'open' then p_status in ('active', 'invite_only', 'paused', 'completed')
    when 'invite_only' then p_status in ('open', 'active', 'paused', 'completed')
    when 'active' then p_status in ('paused', 'completed')
    when 'paused' then p_status in ('open', 'invite_only', 'active', 'completed')
    when 'completed' then p_status in ('archived')
    else false end;
  if not v_ok then raise exception 'cannot move a % campaign to %', c.status, p_status using errcode = '22023'; end if;
  if p_status in ('open', 'invite_only', 'active') and (jsonb_array_length(c.deliverables) = 0 or c.ends_on is null) then
    raise exception 'add deliverables and an end date before opening' using errcode = '22023';
  end if;
  update inf.campaigns set status = p_status,
         visibility = case when p_status = 'invite_only' then 'invite_only' when p_status = 'open' and visibility = 'invite_only' then 'both' else visibility end
   where id = p_campaign;
end $$;

-- Invite creators. Returns how many new invites were sent (already-invited or applied creators are skipped).
create or replace function inf.campaign_invite(p_campaign uuid, p_creators uuid[], p_message text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_n int := 0; v_user uuid; c inf.campaigns;
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.campaigns where id = p_campaign;
  if c.status not in ('open', 'invite_only', 'active') then raise exception 'open the campaign before inviting' using errcode = '22023'; end if;
  if coalesce(array_length(p_creators, 1), 0) > 200 then raise exception 'at most 200 at a time' using errcode = '22023'; end if;
  foreach v_id in array p_creators loop
    continue when not exists (select 1 from inf.creators where id = v_id and approved_at is not null and status = 'active' and not is_blocked);
    continue when exists (select 1 from inf.campaign_applications where campaign_id = p_campaign and creator_id = v_id);
    insert into inf.campaign_invites (campaign_id, creator_id, message) values (p_campaign, v_id, nullif(trim(p_message), ''))
    on conflict (campaign_id, creator_id) do nothing;
    if found then
      v_n := v_n + 1;
      select user_id into v_user from inf.creator_accounts where creator_id = v_id;
      if v_user is not null then
        perform inf.notify(v_user, 'campaign.invited', 'You''re invited: ' || c.name, coalesce(left(p_message, 300), 'Open the invitation to accept, decline or counter.'),
                           '/creator/campaigns/' || p_campaign, jsonb_build_object('campaign_id', p_campaign), false, 'campaign_invite:' || p_campaign || ':' || v_id);
      end if;
    end if;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Applications and offers
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.application_side(p_creator uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when coalesce(p_creator = inf.current_creator_id(), false) then 'creator'
              when inf.agency_can(p_creator, 'negotiate') then 'agency'
              when inf.has_perm('application.review') then 'eduwit' end;
$$;

-- Notify the other side of an application about something new.
create or replace function inf.application_notify(p_app uuid, p_to text, p_event text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = '' as $$
declare a inf.campaign_applications; c inf.campaigns; v_user uuid;
begin
  select * into a from inf.campaign_applications where id = p_app;
  select * into c from inf.campaigns where id = a.campaign_id;
  if p_to = 'creator' then
    select user_id into v_user from inf.creator_accounts where creator_id = a.creator_id;
    if v_user is not null then
      perform inf.notify(v_user, p_event, p_title, p_body, '/creator/applications/' || p_app, jsonb_build_object('application_id', p_app), false,
                         p_event || ':' || p_app || ':' || extract(epoch from clock_timestamp())::bigint);
    end if;
  else
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/applications/' || p_app, jsonb_build_object('application_id', p_app), false,
                       p_event || ':' || p_app || ':' || sp.user_id || ':' || extract(epoch from clock_timestamp())::bigint)
      from inf.staff_profiles sp
     where sp.status = 'active' and (sp.user_id = c.owner_id or (c.owner_id is null and exists (
             select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
              where g.user_id = sp.user_id and rp.permission = 'application.review')));
  end if;
end $$;

-- A creator (or their negotiating agency) applies, or accepts/counters an invite (p_from_invite).
create or replace function inf.campaign_apply(p_campaign uuid, p_creator uuid, p_pitch text, p_samples text[], p_terms jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  c inf.campaigns; v_id uuid; v_invite inf.campaign_invites; v_gaps text[]; v_left int;
begin
  if not inf.can_negotiate_for(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.campaigns where id = p_campaign for share;
  select * into v_invite from inf.campaign_invites where campaign_id = p_campaign and creator_id = p_creator;
  if c.id is null or c.status not in ('open', 'invite_only', 'active') then raise exception 'campaign is not open' using errcode = '22023'; end if;
  if v_invite.id is null then
    if c.visibility = 'invite_only' or c.status = 'invite_only' then raise exception 'campaign is invite-only' using errcode = '22023'; end if;
    if c.apply_by is not null and c.apply_by < (now() at time zone 'Asia/Kolkata')::date then raise exception 'applications closed' using errcode = '22023'; end if;
    v_gaps := inf.eligibility_gaps(p_campaign, p_creator);
    if cardinality(v_gaps) > 0 then raise exception 'not eligible: %', array_to_string(v_gaps, ',') using errcode = '22023'; end if;
  elsif v_invite.status not in ('sent') then
    raise exception 'invite already answered' using errcode = '22023';
  end if;
  v_left := case when c.slots is null then 1 else c.slots - (select count(*) from inf.campaign_applications where campaign_id = p_campaign and status = 'accepted') end;
  if v_left <= 0 then raise exception 'no slots left' using errcode = '22023'; end if;
  if exists (select 1 from inf.campaign_applications where campaign_id = p_campaign and creator_id = p_creator) then
    raise exception 'already applied' using errcode = '23505';
  end if;
  if (select count(*) from unnest(coalesce(p_samples, '{}')) s where s !~ '^https://\S{4,}$') > 0 then
    raise exception 'sample links must start with https://' using errcode = '22023';
  end if;
  insert into inf.campaign_applications (campaign_id, creator_id, source, pitch, sample_links)
  values (p_campaign, p_creator, case when v_invite.id is null then 'marketplace' else 'invite' end,
          nullif(trim(p_pitch), ''), coalesce(p_samples, '{}'))
  returning id into v_id;
  insert into inf.application_offers (application_id, from_side, terms) values (v_id, 'creator', p_terms);
  if v_invite.id is not null then
    update inf.campaign_invites set status = case when p_terms ? 'counter' and (p_terms ->> 'counter')::boolean then 'countered' else 'accepted' end,
           responded_at = now(), application_id = v_id
     where id = v_invite.id;
  end if;
  update inf.creators set last_activity_at = now() where id = p_creator and coalesce(p_creator = inf.current_creator_id(), false);
  perform inf.application_notify(v_id, 'eduwit', 'application.submitted', 'New application: ' || c.name, null);
  return v_id;
end $$;

create or replace function inf.invite_decline(p_invite uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare i inf.campaign_invites;
begin
  select * into i from inf.campaign_invites where id = p_invite for update;
  if i.id is null or not inf.can_negotiate_for(i.creator_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if i.status <> 'sent' then raise exception 'invite already answered' using errcode = '22023'; end if;
  update inf.campaign_invites set status = 'declined', responded_at = now(), message = coalesce(message, '') where id = p_invite;
  perform inf.audit('campaign_invite', p_invite::text, 'decline', null, jsonb_build_object('reason', left(p_reason, 300)));
end $$;

create or replace function inf.invite_withdraw(p_invite uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.campaign_invites set status = 'withdrawn', responded_at = now() where id = p_invite and status = 'sent';
  if not found then raise exception 'invite already answered' using errcode = '22023'; end if;
end $$;

-- Make a new offer on an application (either side). Supersedes the open offer; status becomes "countered".
create or replace function inf.offer_make(p_app uuid, p_terms jsonb, p_message text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a inf.campaign_applications; v_side text; v_id uuid; v_name text;
begin
  select * into a from inf.campaign_applications where id = p_app for update;
  if a.id is null then raise exception 'no such application' using errcode = '22023'; end if;
  v_side := inf.application_side(a.creator_id);
  if v_side is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if a.status not in ('submitted', 'shortlisted', 'countered') then raise exception 'application is closed' using errcode = '22023'; end if;
  update inf.application_offers set status = 'superseded' where application_id = p_app and status = 'open';
  insert into inf.application_offers (application_id, from_side, terms, message)
  values (p_app, case when v_side = 'eduwit' then 'eduwit' else 'creator' end, p_terms, nullif(trim(p_message), ''))
  returning id into v_id;
  update inf.campaign_applications set status = 'countered' where id = p_app;
  select name into v_name from inf.campaigns where id = a.campaign_id;
  perform inf.application_notify(p_app, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'application.countered',
                                 'New offer: ' || v_name, nullif(left(trim(p_message), 300), ''));
  return v_id;
end $$;

-- Accept the open offer. Only the side that did NOT make it can accept. Emits application.accepted (Phase 3 builds
-- the deal from it).
create or replace function inf.offer_accept(p_offer uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare o inf.application_offers; a inf.campaign_applications; c inf.campaigns; v_side text; v_left int;
begin
  select * into o from inf.application_offers where id = p_offer for update;
  if o.id is null or o.status <> 'open' then raise exception 'offer is no longer open' using errcode = '22023'; end if;
  select * into a from inf.campaign_applications where id = o.application_id for update;
  select * into c from inf.campaigns where id = a.campaign_id for update;
  v_side := inf.application_side(a.creator_id);
  if v_side is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if (v_side = 'eduwit') = (o.from_side = 'eduwit') then raise exception 'the other side must accept this offer' using errcode = '22023'; end if;
  v_left := case when c.slots is null then 1 else c.slots - (select count(*) from inf.campaign_applications where campaign_id = c.id and status = 'accepted') end;
  if v_left <= 0 then raise exception 'no slots left' using errcode = '22023'; end if;
  update inf.application_offers set status = 'accepted' where id = p_offer;
  update inf.campaign_applications set status = 'accepted', accepted_terms = o.terms, decided_by = auth.uid(), decided_at = now()
   where id = a.id;
  perform inf.emit_event('application.accepted', 'campaign_application', a.id::text,
                         jsonb_build_object('campaign_id', c.id, 'creator_id', a.creator_id, 'offer_id', o.id, 'terms', o.terms),
                         'application_accepted:' || a.id);
  perform inf.application_notify(a.id, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'application.accepted',
                                 'Accepted: ' || c.name, 'The agreed terms are now final. Your deal and contract come next.');
end $$;

create or replace function inf.application_shortlist(p_app uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('application.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.campaign_applications set status = 'shortlisted' where id = p_app and status in ('submitted', 'countered');
  if not found then raise exception 'application is closed' using errcode = '22023'; end if;
  perform inf.application_notify(p_app, 'creator', 'application.shortlisted', 'You''re shortlisted',
                                 'The Eduwit team is reviewing your application.');
end $$;

create or replace function inf.application_reject(p_app uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  if not inf.has_perm('application.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.campaign_applications set status = 'rejected', rejection_reason = left(p_reason, 1000), decided_by = auth.uid(), decided_at = now()
   where id = p_app and status in ('submitted', 'shortlisted', 'countered');
  if not found then raise exception 'application is closed' using errcode = '22023'; end if;
  update inf.application_offers set status = 'rejected' where application_id = p_app and status = 'open';
  select c.name into v_name from inf.campaign_applications a join inf.campaigns c on c.id = a.campaign_id where a.id = p_app;
  perform inf.application_notify(p_app, 'creator', 'application.rejected', 'Update on ' || v_name, left(p_reason, 300));
end $$;

create or replace function inf.application_withdraw(p_app uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare a inf.campaign_applications;
begin
  select * into a from inf.campaign_applications where id = p_app for update;
  if a.id is null or not inf.can_negotiate_for(a.creator_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if a.status not in ('submitted', 'shortlisted', 'countered') then raise exception 'application is closed' using errcode = '22023'; end if;
  update inf.campaign_applications set status = 'withdrawn', decided_at = now() where id = p_app;
  update inf.application_offers set status = 'rejected' where application_id = p_app and status = 'open';
end $$;

-- One application with its offers and messages, for whoever may see it.
create or replace function inf.application_detail(p_app uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a inf.campaign_applications; v_side text; v_thread uuid;
begin
  select * into a from inf.campaign_applications where id = p_app;
  if a.id is null then return null; end if;
  v_side := inf.application_side(a.creator_id);
  if v_side is null and not inf.has_perm('campaign.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  select id into v_thread from inf.threads where entity_type = 'application' and entity_id = p_app;
  return jsonb_build_object(
    'id', a.id, 'campaign_id', a.campaign_id, 'creator_id', a.creator_id, 'source', a.source, 'pitch', a.pitch,
    'sample_links', to_jsonb(a.sample_links), 'status', a.status, 'rejection_reason', a.rejection_reason,
    'accepted_terms', a.accepted_terms, 'created_at', a.created_at, 'decided_at', a.decided_at, 'viewer_side', coalesce(v_side, 'eduwit_readonly'),
    'campaign', (select jsonb_build_object('id', c.id, 'name', c.name, 'status', c.status, 'compensation_summary', c.compensation_summary,
                                           'deliverables', c.deliverables, 'ends_on', c.ends_on) from inf.campaigns c where c.id = a.campaign_id),
    'creator', (select jsonb_build_object('id', cr.id, 'display_name', cr.display_name, 'handle', cr.handle,
                                          'followers', coalesce((select sum(p.followers) from inf.creator_platforms p where p.creator_id = cr.id), 0))
                  from inf.creators cr where cr.id = a.creator_id),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'from_side', o.from_side, 'terms', o.terms, 'message', o.message,
                                                            'status', o.status, 'created_at', o.created_at) order by o.created_at desc)
                          from inf.application_offers o where o.application_id = a.id), '[]'),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'author_side', m.author_side, 'body', m.body,
                                                              'created_at', m.created_at, 'mine', m.author_id = auth.uid()) order by m.created_at)
                            from inf.messages m where m.thread_id = v_thread), '[]'));
end $$;

-- Post a message on an application thread (either side; read-only staff can't post).
create or replace function inf.application_message(p_app uuid, p_body text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a inf.campaign_applications; v_side text; v_thread uuid; v_id uuid; v_name text;
begin
  select * into a from inf.campaign_applications where id = p_app;
  if a.id is null then raise exception 'no such application' using errcode = '22023'; end if;
  v_side := inf.application_side(a.creator_id);
  if v_side is null then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.threads (entity_type, entity_id) values ('application', p_app) on conflict (entity_type, entity_id) do nothing;
  select id into v_thread from inf.threads where entity_type = 'application' and entity_id = p_app;
  insert into inf.messages (thread_id, author_side, body) values (v_thread, v_side, trim(p_body)) returning id into v_id;
  select name into v_name from inf.campaigns where id = a.campaign_id;
  perform inf.application_notify(p_app, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'application.message',
                                 'New message: ' || v_name, left(trim(p_body), 200));
  return v_id;
end $$;

-- Lists ------------------------------------------------------------------------------------------------------------
create or replace function inf.my_applications(p_creator uuid default null) returns table (
  id uuid, campaign_id uuid, campaign_name text, status text, source text, created_at timestamptz, updated_at timestamptz,
  open_offer_from text)
language plpgsql stable security definer set search_path = '' as $$
declare v_creator uuid := coalesce(p_creator, inf.current_creator_id());
begin
  if v_creator is null or not inf.can_negotiate_for(v_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
  select a.id, c.id, c.name, a.status, a.source, a.created_at, a.updated_at,
         (select o.from_side from inf.application_offers o where o.application_id = a.id and o.status = 'open')
    from inf.campaign_applications a join inf.campaigns c on c.id = a.campaign_id
   where a.creator_id = v_creator
   order by a.updated_at desc;
end $$;

create or replace function inf.my_invites(p_creator uuid default null) returns table (
  id uuid, campaign_id uuid, campaign_name text, status text, message text, sent_at timestamptz, apply_by date, compensation_summary text)
language plpgsql stable security definer set search_path = '' as $$
declare v_creator uuid := coalesce(p_creator, inf.current_creator_id());
begin
  if v_creator is null or not inf.can_negotiate_for(v_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
  select i.id, c.id, c.name, i.status, i.message, i.sent_at, c.apply_by, c.compensation_summary
    from inf.campaign_invites i join inf.campaigns c on c.id = i.campaign_id
   where i.creator_id = v_creator and c.status not in ('draft', 'archived')
   order by (i.status = 'sent') desc, i.sent_at desc;
end $$;

-- Staff review queue across campaigns.
create or replace function inf.applications_list(p_campaign uuid default null, p_status text[] default null) returns table (
  id uuid, campaign_id uuid, campaign_name text, creator_id uuid, display_name text, handle text, followers bigint,
  status text, source text, created_at timestamptz, updated_at timestamptz, open_offer_from text)
language sql stable security definer set search_path = '' as $$
  select a.id, c.id, c.name, cr.id, cr.display_name, cr.handle,
         coalesce((select sum(p.followers) from inf.creator_platforms p where p.creator_id = cr.id), 0)::bigint,
         a.status, a.source, a.created_at, a.updated_at,
         (select o.from_side from inf.application_offers o where o.application_id = a.id and o.status = 'open')
    from inf.campaign_applications a
    join inf.campaigns c on c.id = a.campaign_id
    join inf.creators cr on cr.id = a.creator_id
   where inf.has_perm('campaign.read')
     and (p_campaign is null or a.campaign_id = p_campaign)
     and (p_status is null or cardinality(p_status) = 0 or a.status = any(p_status))
   order by (a.status in ('submitted', 'countered')) desc, a.updated_at desc
   limit 500;
$$;

create or replace function inf.campaign_stats(p_campaign uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'invites', (select count(*) from inf.campaign_invites where campaign_id = p_campaign),
    'invites_open', (select count(*) from inf.campaign_invites where campaign_id = p_campaign and status = 'sent'),
    'applications', (select count(*) from inf.campaign_applications where campaign_id = p_campaign),
    'to_review', (select count(*) from inf.campaign_applications where campaign_id = p_campaign and status in ('submitted', 'countered')),
    'accepted', (select count(*) from inf.campaign_applications where campaign_id = p_campaign and status = 'accepted'))
  where inf.has_perm('campaign.read');
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.campaigns enable row level security;
alter table inf.campaign_programmes enable row level security;
alter table inf.campaign_invites enable row level security;
alter table inf.campaign_applications enable row level security;
alter table inf.application_offers enable row level security;
alter table inf.threads enable row level security;
alter table inf.messages enable row level security;
alter table inf.reason_templates enable row level security;

-- Staff read tables directly; creators and agencies only through the functions above (which hide budget and notes).
create policy campaigns_staff_read on inf.campaigns for select to authenticated using ((select inf.has_perm('campaign.read')));
create policy campaign_programmes_staff_read on inf.campaign_programmes for select to authenticated using ((select inf.has_perm('campaign.read')));
create policy campaign_invites_staff_read on inf.campaign_invites for select to authenticated using ((select inf.has_perm('campaign.read')));
create policy campaign_applications_staff_read on inf.campaign_applications for select to authenticated using ((select inf.has_perm('campaign.read')));
create policy application_offers_staff_read on inf.application_offers for select to authenticated using ((select inf.has_perm('campaign.read')));
create policy reason_templates_staff_read on inf.reason_templates for select to authenticated using ((select inf.has_perm('application.review')));
-- threads/messages: no policies; read through application_detail().

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.campaigns', 'authenticated', 'select'),
  ('table', 'inf.campaign_programmes', 'authenticated', 'select'),
  ('table', 'inf.campaign_invites', 'authenticated', 'select'),
  ('table', 'inf.campaign_applications', 'authenticated', 'select'),
  ('table', 'inf.application_offers', 'authenticated', 'select'),
  ('table', 'inf.reason_templates', 'authenticated', 'select'),
  ('function', 'inf.catalog_programmes_search(text, int)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_programmes_view(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.eligibility_gaps(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.can_see_campaign(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.marketplace(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_for_creator(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_set_status(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_invite(uuid, uuid[], text)', 'authenticated', 'execute'),
  ('function', 'inf.campaign_apply(uuid, uuid, text, text[], jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.invite_decline(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.invite_withdraw(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.offer_make(uuid, jsonb, text)', 'authenticated', 'execute'),
  ('function', 'inf.offer_accept(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.application_shortlist(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.application_reject(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.application_withdraw(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.application_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.application_message(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.my_applications(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.my_invites(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.applications_list(uuid, text[])', 'authenticated', 'execute'),
  ('function', 'inf.campaign_stats(uuid)', 'authenticated', 'execute');
call inf.apply_client_grants();
