-- Phase 2.2: agencies / managers (spec 4 "Agency / Manager", 5). An agency has members (people who sign in to the
-- agency portal) and links to creators. Each link carries the permissions the CREATOR granted: view, act on
-- deliverables, negotiate and sign, view earnings. A link is only active once the creator accepts it, and the creator
-- can change or revoke the grants at any time. Payout bank details always stay the creator's (KYC is never visible to
-- an agency). Agency users never see a student's phone or email: every lead path stays creator-masked (spec 2.1).

create table inf.agencies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 120),
  legal_name  text check (char_length(legal_name) <= 160),
  email       text check (email is null or email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone_e164  text check (phone_e164 is null or phone_e164 ~ '^\+[1-9]\d{7,14}$'),
  gstin       text check (gstin is null or inf.valid_gstin(gstin)),
  status      text not null default 'active' check (status in ('active', 'suspended')),
  notes       text check (char_length(notes) <= 2000),
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index agencies_name_uq on inf.agencies (lower(name));

-- One agency per person. `user_id` is filled when the invited person first signs in (matched by verified email).
create table inf.agency_members (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null references inf.agencies (id) on delete cascade,
  email       text not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  full_name   text not null check (char_length(full_name) between 1 and 120),
  role        text not null default 'member' check (role in ('owner', 'member')),
  user_id     uuid unique references auth.users (id) on delete set null,
  status      text not null default 'active' check (status in ('active', 'removed')),
  invited_by  uuid,
  created_at  timestamptz not null default now(),
  linked_at   timestamptz
);
create unique index agency_members_email_uq on inf.agency_members (email) where status = 'active';
create index agency_members_agency_idx on inf.agency_members (agency_id);

create table inf.agency_creator_links (
  id                    uuid primary key default gen_random_uuid(),
  agency_id             uuid not null references inf.agencies (id) on delete cascade,
  creator_id            uuid not null references inf.creators (id) on delete cascade,
  status                text not null default 'pending' check (status in ('pending', 'active', 'declined', 'revoked')),
  can_view              boolean not null default true,
  can_act_deliverables  boolean not null default false,
  can_negotiate_sign    boolean not null default false,
  can_view_earnings     boolean not null default false,
  requested_by          uuid,
  requested_at          timestamptz not null default now(),
  responded_at          timestamptz,
  revoked_at            timestamptz,
  updated_at            timestamptz not null default now(),
  -- Any active grant implies view.
  check (can_view or not (can_act_deliverables or can_negotiate_sign or can_view_earnings))
);
-- At most one live (pending or active) link per agency and creator.
create unique index agency_creator_links_live_uq on inf.agency_creator_links (agency_id, creator_id) where status in ('pending', 'active');
create index agency_creator_links_creator_idx on inf.agency_creator_links (creator_id) where status in ('pending', 'active');

create trigger agencies_touch before update on inf.agencies for each row execute function inf.touch_updated_at();
create trigger agency_creator_links_touch before update on inf.agency_creator_links for each row execute function inf.touch_updated_at();
create trigger agencies_audit after insert or update or delete on inf.agencies for each row execute function inf.audit_row('agency');
create trigger agency_members_audit after insert or update or delete on inf.agency_members for each row execute function inf.audit_row('agency_member');
create trigger agency_creator_links_audit after insert or update or delete on inf.agency_creator_links for each row execute function inf.audit_row('agency_creator_link');

-- A person is staff, a creator or an agency member: never two of them.
create or replace function inf.check_identity_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := new.user_id;
begin
  if v_uid is null then return new; end if;
  if tg_table_name <> 'staff_profiles' and exists (select 1 from inf.staff_profiles where user_id = v_uid) then
    raise exception 'this account is a staff account' using errcode = 'check_violation';
  elsif tg_table_name <> 'creator_accounts' and exists (select 1 from inf.creator_accounts where user_id = v_uid) then
    raise exception 'this account is a creator account' using errcode = 'check_violation';
  elsif tg_table_name <> 'agency_members' and exists (select 1 from inf.agency_members where user_id = v_uid) then
    raise exception 'this account is an agency account' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger agency_members_kind before insert or update of user_id on inf.agency_members
  for each row execute function inf.check_identity_kind();

-- ---------------------------------------------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.current_agency_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.agency_id
    from inf.agency_members m join inf.agencies a on a.id = m.agency_id
   where m.user_id = auth.uid() and m.status = 'active' and a.status = 'active' and inf.session_ok();
$$;

create or replace function inf.current_agency_role() returns text
language sql stable security definer set search_path = '' as $$
  select m.role
    from inf.agency_members m join inf.agencies a on a.id = m.agency_id
   where m.user_id = auth.uid() and m.status = 'active' and a.status = 'active' and inf.session_ok();
$$;

-- Does the signed-in agency user hold this creator-granted permission? p_grant: view | deliverables | negotiate | earnings.
create or replace function inf.agency_can(p_creator uuid, p_grant text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case p_grant
             when 'view' then l.can_view
             when 'deliverables' then l.can_act_deliverables
             when 'negotiate' then l.can_negotiate_sign
             when 'earnings' then l.can_view_earnings
             else false end
      from inf.agency_creator_links l
      join inf.creators c on c.id = l.creator_id
     where l.agency_id = inf.current_agency_id() and l.creator_id = p_creator and l.status = 'active'
       and c.status not in ('blocked', 'archived') and not c.is_blocked), false);
$$;

-- Profile reads now include agencies the creator granted "view".
create or replace function inf.can_view_creator(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.read') or inf.agency_can(p_creator, 'view');
$$;

create or replace function inf.actor_role() returns text
language sql stable security definer set search_path = '' as $$
  select case
    when auth.role() = 'service_role' then 'service'
    when auth.uid() is null then coalesce(auth.role(), 'system')
    when exists (select 1 from inf.staff_profiles p where p.user_id = auth.uid()) then
      coalesce((select 'staff:' || string_agg(g.role, ',' order by g.role) from inf.staff_role_grants g where g.user_id = auth.uid()), 'staff')
    when exists (select 1 from inf.creator_accounts a where a.user_id = auth.uid()) then 'creator'
    when exists (select 1 from inf.agency_members m where m.user_id = auth.uid()) then 'agency'
    else 'authenticated' end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Sessions and me(): add the agency kind. Agency members sign in like creators (email OTP or Google).
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.session_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_sid     uuid := inf.current_session_id();
  v_kind    text;
  v_amr     text := coalesce(auth.jwt() -> 'amr' -> 0 ->> 'method', 'unknown');
  v_via     text := case when coalesce(auth.jwt() -> 'amr' -> 0 ->> 'method', '') = 'oauth' then 'oauth' else 'otp' end;
begin
  if v_uid is null or v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'not_signed_in');
  end if;
  if exists (select 1 from inf.staff_profiles where user_id = v_uid and status = 'active') then
    v_kind := 'staff';
  elsif exists (select 1 from inf.creator_accounts a join inf.creators c on c.id = a.creator_id
                 where a.user_id = v_uid and c.status not in ('blocked', 'archived') and not c.is_blocked) then
    v_kind := 'creator';
  elsif exists (select 1 from inf.agency_members m join inf.agencies a on a.id = m.agency_id
                 where m.user_id = v_uid and m.status = 'active' and a.status = 'active') then
    v_kind := 'agency';
  else
    return jsonb_build_object('ok', false, 'error', 'no_portal_access');
  end if;

  insert into inf.user_sessions (session_id, user_id, kind, auth_method, verified_at, verified_via, ip, user_agent)
  values (v_sid, v_uid, v_kind, v_amr,
          case when v_kind <> 'staff' then now() end, case when v_kind <> 'staff' then v_via end,
          inf.request_ip(), inf.request_user_agent())
  on conflict (session_id) do update set last_seen_at = now()
    where inf.user_sessions.user_id = excluded.user_id;
  if not exists (select 1 from inf.user_sessions where session_id = v_sid and user_id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'session_mismatch');
  end if;
  return jsonb_build_object('ok', true, 'kind', v_kind);
end $$;

create or replace function inf.me() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_sid  uuid := inf.current_session_id();
  v_sess inf.user_sessions;
  v_staff inf.staff_profiles;
  v_creator inf.creators;
  v_member inf.agency_members;
  v_agency inf.agencies;
begin
  if v_uid is null then return jsonb_build_object('signed_in', false); end if;
  select * into v_sess from inf.user_sessions where session_id = v_sid and user_id = v_uid;
  select * into v_staff from inf.staff_profiles where user_id = v_uid;
  select c.* into v_creator from inf.creator_accounts a join inf.creators c on c.id = a.creator_id where a.user_id = v_uid;
  select * into v_member from inf.agency_members where user_id = v_uid;
  if v_member.id is not null then select * into v_agency from inf.agencies where id = v_member.agency_id; end if;
  return jsonb_build_object(
    'signed_in', true,
    'user_id', v_uid,
    'email', auth.jwt() ->> 'email',
    'session', case when v_sess.session_id is null then null else jsonb_build_object(
        'registered', true, 'verified', v_sess.verified_at is not null,
        'revoked', v_sess.revoked_at is not null or v_sess.last_seen_at <= now() - inf.idle_limit(),
        'verified_via', v_sess.verified_via) end,
    'kind', case when v_staff.user_id is not null then 'staff' when v_creator.id is not null then 'creator'
                 when v_member.id is not null then 'agency' else 'none' end,
    'staff', case when v_staff.user_id is null then null else jsonb_build_object(
        'full_name', v_staff.full_name, 'status', v_staff.status, 'is_signatory', v_staff.is_signatory,
        'roles', coalesce((select jsonb_agg(g.role order by g.role) from inf.staff_role_grants g where g.user_id = v_uid), '[]'::jsonb)) end,
    'creator', case when v_creator.id is null then null else jsonb_build_object(
        'id', v_creator.id, 'display_name', v_creator.display_name, 'handle', v_creator.handle,
        'status', v_creator.status, 'is_blocked', v_creator.is_blocked, 'is_test', v_creator.is_test) end,
    'agency', case when v_member.id is null then null else jsonb_build_object(
        'id', v_agency.id, 'name', v_agency.name, 'status', v_agency.status,
        'member_name', v_member.full_name, 'role', v_member.role, 'member_status', v_member.status) end);
end $$;

-- First sign-in of an invited agency member: a verified email matching exactly one active, unlinked membership.
create or replace function inf.agency_account_link() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_email text; v_ok boolean; v_id uuid; v_n int;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select id into v_id from inf.agency_members where user_id = v_uid and status = 'active';
  if v_id is not null then return jsonb_build_object('ok', true, 'linked', false); end if;
  if exists (select 1 from inf.staff_profiles where user_id = v_uid) or exists (select 1 from inf.creator_accounts where user_id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'other_account_kind');
  end if;
  select lower(u.email), u.email_confirmed_at is not null into v_email, v_ok from auth.users u where u.id = v_uid;
  if v_email is null or not v_ok then return jsonb_build_object('ok', false, 'error', 'email_not_verified'); end if;
  select count(*), min(m.id::text)::uuid into v_n, v_id
    from inf.agency_members m join inf.agencies a on a.id = m.agency_id
   where m.email = v_email and m.status = 'active' and m.user_id is null and a.status = 'active';
  if v_n <> 1 then return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  update inf.agency_members set user_id = v_uid, linked_at = now() where id = v_id;
  return jsonb_build_object('ok', true, 'linked', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff administration (agency.manage)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.agency_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('agency.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.agencies (name, legal_name, email, phone_e164, gstin, notes, created_by)
    values (trim(p ->> 'name'), nullif(trim(p ->> 'legal_name'), ''), nullif(lower(trim(p ->> 'email')), ''),
            nullif(trim(p ->> 'phone_e164'), ''), nullif(upper(trim(p ->> 'gstin')), ''), nullif(trim(p ->> 'notes'), ''), auth.uid())
    returning id into v_id;
  else
    update inf.agencies set name = trim(p ->> 'name'), legal_name = nullif(trim(p ->> 'legal_name'), ''),
           email = nullif(lower(trim(p ->> 'email')), ''), phone_e164 = nullif(trim(p ->> 'phone_e164'), ''),
           gstin = nullif(upper(trim(p ->> 'gstin')), ''), notes = nullif(trim(p ->> 'notes'), '')
     where id = v_id;
    if not found then raise exception 'no such agency' using errcode = '22023'; end if;
  end if;
  return v_id;
end $$;

create or replace function inf.agency_set_status(p_agency uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('agency.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.agencies set status = p_status where id = p_agency;
  if not found then raise exception 'no such agency' using errcode = '22023'; end if;
  perform inf.audit('agency', p_agency::text, 'status:' || p_status, null, jsonb_build_object('reason', p_reason));
end $$;

-- Add a member (staff with agency.manage, or the agency's owner). Returns the member id.
create or replace function inf.agency_member_add(p_agency uuid, p_email text, p_full_name text, p_role text default 'member') returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_email text := lower(trim(p_email));
begin
  if not (inf.has_perm('agency.manage') or (inf.current_agency_id() = p_agency and inf.current_agency_role() = 'owner')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from inf.staff_profiles where lower(email) = v_email)
     or exists (select 1 from inf.creators c join inf.creator_accounts a on a.creator_id = c.id where lower(c.email) = v_email) then
    raise exception 'this email belongs to a staff or creator account' using errcode = '22023';
  end if;
  insert into inf.agency_members (agency_id, email, full_name, role, invited_by)
  values (p_agency, v_email, trim(p_full_name), coalesce(p_role, 'member'), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.agency_member_remove(p_member uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_agency uuid;
begin
  select agency_id into v_agency from inf.agency_members where id = p_member and status = 'active';
  if v_agency is null then raise exception 'no such member' using errcode = '22023'; end if;
  if not (inf.has_perm('agency.manage') or (inf.current_agency_id() = v_agency and inf.current_agency_role() = 'owner')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (select role from inf.agency_members where id = p_member) = 'owner'
     and (select count(*) from inf.agency_members where agency_id = v_agency and role = 'owner' and status = 'active') = 1 then
    raise exception 'an agency needs at least one owner' using errcode = '22023';
  end if;
  update inf.agency_members set status = 'removed' where id = p_member;
  -- End the removed person's sessions at once.
  update inf.user_sessions set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = 'removed from agency'
   where user_id = (select user_id from inf.agency_members where id = p_member) and revoked_at is null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Links: requested by staff (agency.manage) or an agency owner; accepted, re-scoped or revoked by the creator.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.agency_link_request(p_agency uuid, p_creator uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_user uuid; v_agency_name text;
begin
  if not (inf.has_perm('agency.manage') or (inf.current_agency_id() = p_agency and inf.current_agency_role() = 'owner')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from inf.creators where id = p_creator and status not in ('blocked', 'archived')) then
    raise exception 'no such creator' using errcode = '22023';
  end if;
  insert into inf.agency_creator_links (agency_id, creator_id, requested_by) values (p_agency, p_creator, auth.uid())
  returning id into v_id;
  select user_id into v_user from inf.creator_accounts where creator_id = p_creator;
  select name into v_agency_name from inf.agencies where id = p_agency;
  if v_user is not null then
    perform inf.notify(v_user, 'agency.link_requested', v_agency_name || ' wants to manage your account',
                       'Choose what they can do, or decline.', '/creator/agency', jsonb_build_object('link_id', v_id), true,
                       'agency_link:' || v_id);
  end if;
  return v_id;
end $$;

-- Same, by creator handle (agency owners can't read the creators table). Permission is checked before the lookup.
create or replace function inf.agency_link_request_by_handle(p_agency uuid, p_handle text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_creator uuid;
begin
  if not (inf.has_perm('agency.manage') or (inf.current_agency_id() = p_agency and inf.current_agency_role() = 'owner')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select id into v_creator from inf.creators
   where handle = lower(trim(leading '@' from trim(p_handle))) and status not in ('blocked', 'archived');
  if v_creator is null then raise exception 'no such creator' using errcode = '22023'; end if;
  return inf.agency_link_request(p_agency, v_creator);
end $$;

-- The creator accepts (with grants) or updates grants on an active link.
create or replace function inf.agency_link_respond(p_link uuid, p_accept boolean, p_view boolean, p_deliverables boolean,
                                                   p_negotiate boolean, p_earnings boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare l inf.agency_creator_links;
begin
  select * into l from inf.agency_creator_links where id = p_link for update;
  if l.id is null or not coalesce(l.creator_id = inf.current_creator_id(), false) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if l.status not in ('pending', 'active') then raise exception 'this link has ended' using errcode = '22023'; end if;
  if not p_accept then
    update inf.agency_creator_links
       set status = case when l.status = 'pending' then 'declined' else 'revoked' end,
           responded_at = coalesce(responded_at, now()), revoked_at = case when l.status = 'active' then now() end
     where id = p_link;
    return;
  end if;
  update inf.agency_creator_links set
    status = 'active', responded_at = coalesce(responded_at, now()),
    can_view = true, can_act_deliverables = coalesce(p_deliverables, false),
    can_negotiate_sign = coalesce(p_negotiate, false), can_view_earnings = coalesce(p_earnings, false)
  where id = p_link;
end $$;

-- Staff can end a link (e.g. agency suspended); the creator does it through agency_link_respond(false).
create or replace function inf.agency_link_revoke(p_link uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('agency.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.agency_creator_links set status = 'revoked', revoked_at = now() where id = p_link and status in ('pending', 'active');
  if not found then raise exception 'no live link' using errcode = '22023'; end if;
  perform inf.audit('agency_creator_link', p_link::text, 'revoke', null, jsonb_build_object('reason', p_reason));
end $$;

-- What the agency portal shows: its creators (name, handle, avatar, status) and the grants. No creator contact
-- details, no KYC.
create or replace function inf.agency_creators() returns table (
  link_id uuid, creator_id uuid, display_name text, handle text, avatar_path text, creator_status text, link_status text,
  can_view boolean, can_act_deliverables boolean, can_negotiate_sign boolean, can_view_earnings boolean, requested_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select l.id, c.id, c.display_name, c.handle, c.avatar_path, c.status, l.status,
         l.can_view, l.can_act_deliverables, l.can_negotiate_sign, l.can_view_earnings, l.requested_at
    from inf.agency_creator_links l join inf.creators c on c.id = l.creator_id
   where l.agency_id = inf.current_agency_id() and l.status in ('pending', 'active')
   order by l.status, c.display_name;
$$;

-- The creator's view of agencies linked to them.
create or replace function inf.my_agency_links() returns table (
  link_id uuid, agency_name text, status text, can_view boolean, can_act_deliverables boolean, can_negotiate_sign boolean,
  can_view_earnings boolean, requested_at timestamptz, responded_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select l.id, a.name, l.status, l.can_view, l.can_act_deliverables, l.can_negotiate_sign, l.can_view_earnings,
         l.requested_at, l.responded_at
    from inf.agency_creator_links l join inf.agencies a on a.id = l.agency_id
   where l.creator_id = inf.current_creator_id() and l.status in ('pending', 'active')
   order by l.requested_at desc;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.agencies enable row level security;
alter table inf.agency_members enable row level security;
alter table inf.agency_creator_links enable row level security;

create policy agencies_staff_read on inf.agencies for select to authenticated
  using ((select inf.has_perm('agency.manage')) or (select inf.has_perm('creator.read')));
create policy agencies_own_read on inf.agencies for select to authenticated using (id = (select inf.current_agency_id()));
create policy agency_members_staff_read on inf.agency_members for select to authenticated using ((select inf.has_perm('agency.manage')));
create policy agency_members_own_read on inf.agency_members for select to authenticated using (agency_id = (select inf.current_agency_id()));
create policy agency_creator_links_staff_read on inf.agency_creator_links for select to authenticated
  using ((select inf.has_perm('agency.manage')) or (select inf.has_perm('creator.read')));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.agencies', 'authenticated', 'select'),
  ('table', 'inf.agency_members', 'authenticated', 'select'),
  ('table', 'inf.agency_creator_links', 'authenticated', 'select'),
  ('function', 'inf.current_agency_id()', 'authenticated', 'execute'),
  ('function', 'inf.current_agency_role()', 'authenticated', 'execute'),
  ('function', 'inf.agency_can(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.agency_account_link()', 'authenticated', 'execute'),
  ('function', 'inf.agency_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.agency_set_status(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.agency_member_add(uuid, text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.agency_member_remove(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.agency_link_request(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.agency_link_request_by_handle(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.agency_link_respond(uuid, boolean, boolean, boolean, boolean, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.agency_link_revoke(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.agency_creators()', 'authenticated', 'execute'),
  ('function', 'inf.my_agency_links()', 'authenticated', 'execute');
call inf.apply_client_grants();
