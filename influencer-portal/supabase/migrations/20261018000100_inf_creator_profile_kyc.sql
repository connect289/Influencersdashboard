-- Phase 2.1: creator profile (platforms, rate cards, portfolio, extra contacts) and KYC (spec 5, 7, 11, 16).
-- PAN and bank account numbers are encrypted at rest with pgcrypto (AES-256) using a key in Supabase Vault
-- (`inf_pii_key`, SHARED_CHANGES S-5); only the last four characters are kept in clear for masked display. Only the
-- Finance permission `kyc.reveal` decrypts, and every reveal is audit-logged (spec 2.8, D-08).
-- BACK UP THE VAULT KEY: without it, stored PAN and bank numbers cannot be read (docs/RUNBOOK.md).

-- ---------------------------------------------------------------------------------------------------------------
-- PII key and helpers
-- ---------------------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'inf_pii_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'inf_pii_key',
                                'Influencer Portal: encryption key for PAN and bank account numbers. Back it up.');
  end if;
end $$;

create or replace function inf.pii_key() returns text
language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  select decrypted_secret into v from vault.decrypted_secrets where name = 'inf_pii_key';
  if v is null or length(v) < 32 then raise exception 'PII key missing (Vault secret inf_pii_key)'; end if;
  return v;
end $$;

create or replace function inf.pii_encrypt(p text) returns bytea
language sql volatile security definer set search_path = '' as $$
  select case when p is null then null else extensions.pgp_sym_encrypt(p, inf.pii_key(), 'cipher-algo=aes256') end;
$$;

create or replace function inf.pii_decrypt(p bytea) returns text
language sql stable security definer set search_path = '' as $$
  select case when p is null then null else extensions.pgp_sym_decrypt(p, inf.pii_key()) end;
$$;

-- Keyed hash for matching (self-referral checks) without keeping extra plain copies.
create or replace function inf.pii_hash(p text) returns text
language sql stable security definer set search_path = '' as $$
  select case when nullif(trim(p), '') is null then null
              else encode(extensions.hmac(lower(trim(p)), inf.pii_key() || ':match', 'sha256'), 'hex') end;
$$;

-- Indian phone to the digits form student_leads uses (91XXXXXXXXXX), mirroring public.crm_norm_phone.
create or replace function inf.norm_phone(p text) returns text
language sql immutable set search_path = '' as $$
  select case when d = '' then null when length(d) = 10 then '91' || d
              when length(d) = 11 and left(d, 1) = '0' then '91' || substr(d, 2) else d end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

-- Validators (also enforced in the app with zod).
create or replace function inf.valid_pan(p text) returns boolean language sql immutable set search_path = '' as $$
  select p ~ '^[A-Z]{3}[ABCFGHLJPT][A-Z][0-9]{4}[A-Z]$';
$$;
create or replace function inf.valid_ifsc(p text) returns boolean language sql immutable set search_path = '' as $$
  select p ~ '^[A-Z]{4}0[A-Z0-9]{6}$';
$$;
-- GSTIN: 2-digit state code (01–38 or 97), the PAN, entity number, 'Z', check character.
create or replace function inf.valid_gstin(p text) returns boolean language sql immutable set search_path = '' as $$
  select p ~ '^(0[1-9]|[12][0-9]|3[0-8]|97)[A-Z]{3}[ABCFGHLJPT][A-Z][0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$';
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Profile tables
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.creators
  add column onboarding_step text not null default 'profile'
    check (onboarding_step in ('profile', 'platforms', 'kyc', 'terms', 'course', 'review', 'done')),
  add column onboarding_submitted_at timestamptz,
  add column approved_at timestamptz,
  add column approved_by uuid;

create table inf.creator_platforms (
  id                uuid primary key default gen_random_uuid(),
  creator_id        uuid not null references inf.creators (id) on delete cascade,
  platform          text not null check (platform in ('instagram', 'youtube', 'facebook', 'linkedin', 'x', 'telegram', 'moj_josh', 'other')),
  url               text not null check (char_length(url) <= 500 and url ~ '^https://[^\s]{4,}$'),
  handle            text not null check (char_length(handle) between 1 and 100),
  followers         bigint check (followers >= 0),
  avg_views         bigint check (avg_views >= 0),
  engagement_rate   numeric(6, 3) check (engagement_rate between 0 and 100),
  audience          jsonb not null default '{}'::jsonb check (jsonb_typeof(audience) = 'object'),
  source            text not null default 'manual' check (source in ('manual', 'api')),
  stats_updated_at  timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (creator_id, platform, handle)
);
create index creator_platforms_creator_idx on inf.creator_platforms (creator_id);
create index creator_platforms_followers_idx on inf.creator_platforms (platform, followers desc);

create table inf.creator_rate_cards (
  id               uuid primary key default gen_random_uuid(),
  creator_id       uuid not null references inf.creators (id) on delete cascade,
  platform         text not null check (platform in ('instagram', 'youtube', 'facebook', 'linkedin', 'x', 'telegram', 'moj_josh', 'other')),
  format           text not null check (format in ('reel', 'story', 'post', 'youtube_video', 'short', 'live', 'carousel', 'blog', 'other')),
  suggested_paise  bigint not null check (suggested_paise >= 0),
  notes            text check (char_length(notes) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (creator_id, platform, format)
);

create table inf.creator_portfolio (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references inf.creators (id) on delete cascade,
  url         text not null check (char_length(url) <= 1000 and url ~ '^https://[^\s]{4,}$'),
  title       text check (char_length(title) <= 200),
  caption     text check (char_length(caption) <= 1000),
  position    int not null default 0,
  created_at  timestamptz not null default now()
);
create index creator_portfolio_creator_idx on inf.creator_portfolio (creator_id, position);

-- Extra numbers and emails linked to a creator (self, family, team) as keyed hashes, for self-referral checks.
create table inf.creator_contacts (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references inf.creators (id) on delete cascade,
  kind        text not null check (kind in ('self', 'family', 'team')),
  label       text check (char_length(label) <= 80),
  phone_hash  text,
  email_hash  text,
  phone_last2 text check (phone_last2 ~ '^\d{2}$'),
  created_by  uuid,
  created_at  timestamptz not null default now(),
  check (phone_hash is not null or email_hash is not null)
);
create index creator_contacts_phone_idx on inf.creator_contacts (phone_hash) where phone_hash is not null;
create index creator_contacts_email_idx on inf.creator_contacts (email_hash) where email_hash is not null;

create table inf.creator_kyc (
  creator_id        uuid primary key references inf.creators (id) on delete cascade,
  pan_enc           bytea,
  pan_last4         text check (pan_last4 ~ '^[A-Z0-9]{4}$'),
  name_on_pan       text check (char_length(name_on_pan) between 2 and 120),
  gstin             text check (gstin is null or inf.valid_gstin(gstin)),
  gst_status        text not null default 'unregistered' check (gst_status in ('unregistered', 'registered', 'composition')),
  gstin_verified    boolean not null default false,
  bank_account_enc  bytea,
  bank_last4        text check (bank_last4 ~ '^\d{4}$'),
  ifsc              text check (ifsc is null or inf.valid_ifsc(ifsc)),
  account_holder    text check (char_length(account_holder) between 2 and 120),
  proof_path        text check (proof_path is null or proof_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  status            text not null default 'pending' check (status in ('pending', 'submitted', 'verified', 'rejected')),
  rejection_reason  text,
  submitted_at      timestamptz,
  verified_by       uuid,
  verified_at       timestamptz,
  updated_at        timestamptz not null default now(),
  constraint registered_needs_gstin check (gst_status = 'unregistered' or gstin is not null)
);

create trigger creator_platforms_touch before update on inf.creator_platforms for each row execute function inf.touch_updated_at();
create trigger creator_rate_cards_touch before update on inf.creator_rate_cards for each row execute function inf.touch_updated_at();
create trigger creator_kyc_touch before update on inf.creator_kyc for each row execute function inf.touch_updated_at();

create trigger creator_platforms_audit after insert or update or delete on inf.creator_platforms for each row execute function inf.audit_row('creator_platform');
create trigger creator_rate_cards_audit after insert or update or delete on inf.creator_rate_cards for each row execute function inf.audit_row('creator_rate_card');
create trigger creator_portfolio_audit after insert or update or delete on inf.creator_portfolio for each row execute function inf.audit_row('creator_portfolio');
create trigger creator_contacts_audit after insert or update or delete on inf.creator_contacts for each row execute function inf.audit_row('creator_contact', 'phone_hash', 'email_hash');
create trigger creator_kyc_audit after insert or update or delete on inf.creator_kyc for each row execute function inf.audit_row('creator_kyc', 'pan_enc', 'bank_account_enc');

-- ---------------------------------------------------------------------------------------------------------------
-- Access: who may edit a creator's profile. The creator themself, or staff with creator.write. (Agency grants are
-- added with the agency migration.)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.can_edit_creator(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write');
$$;

create or replace function inf.can_view_creator(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.read');
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Profile writes
-- ---------------------------------------------------------------------------------------------------------------
-- Fields a creator may change about themself. Staff use creator_save() (adds owner, tags, tier, status…).
create or replace function inf.creator_profile_update(p_creator uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_phone text;
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'phone_e164' then
    v_phone := nullif(trim(p ->> 'phone_e164'), '');
    if v_phone is not null and v_phone !~ '^\+[1-9]\d{7,14}$' then raise exception 'invalid phone number' using errcode = '22023'; end if;
  end if;
  update inf.creators set
    display_name = coalesce(nullif(trim(p ->> 'display_name'), ''), display_name),
    legal_name = case when p ? 'legal_name' then nullif(trim(p ->> 'legal_name'), '') else legal_name end,
    bio = case when p ? 'bio' then nullif(trim(p ->> 'bio'), '') else bio end,
    city = case when p ? 'city' then nullif(trim(p ->> 'city'), '') else city end,
    state = case when p ? 'state' then nullif(trim(p ->> 'state'), '') else state end,
    phone_e164 = case when p ? 'phone_e164' then v_phone else phone_e164 end,
    languages = case when p ? 'languages' then coalesce((select array_agg(distinct left(trim(x), 40)) from jsonb_array_elements_text(p -> 'languages') x where trim(x) <> ''), '{}') else languages end,
    niches = case when p ? 'niches' then coalesce((select array_agg(distinct left(lower(trim(x)), 40)) from jsonb_array_elements_text(p -> 'niches') x where trim(x) <> ''), '{}') else niches end,
    avatar_path = case when p ? 'avatar_path' then nullif(p ->> 'avatar_path', '') else avatar_path end,
    public_page_enabled = coalesce((p ->> 'public_page_enabled')::boolean, public_page_enabled),
    leaderboard_opt_in = coalesce((p ->> 'leaderboard_opt_in')::boolean, leaderboard_opt_in),
    last_activity_at = now()
  where id = p_creator;
end $$;

create or replace function inf.platform_save(p_creator uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.creator_platforms (creator_id, platform, url, handle, followers, avg_views, engagement_rate, audience, stats_updated_at)
    values (p_creator, p ->> 'platform', p ->> 'url', trim(p ->> 'handle'), (p ->> 'followers')::bigint, (p ->> 'avg_views')::bigint,
            (p ->> 'engagement_rate')::numeric, coalesce(p -> 'audience', '{}'::jsonb), now())
    returning id into v_id;
  else
    update inf.creator_platforms set platform = p ->> 'platform', url = p ->> 'url', handle = trim(p ->> 'handle'),
           followers = (p ->> 'followers')::bigint, avg_views = (p ->> 'avg_views')::bigint,
           engagement_rate = (p ->> 'engagement_rate')::numeric, audience = coalesce(p -> 'audience', audience), stats_updated_at = now()
     where id = v_id and creator_id = p_creator;
    if not found then raise exception 'no such platform' using errcode = '22023'; end if;
  end if;
  update inf.creators set last_activity_at = now() where id = p_creator;
  return v_id;
end $$;

create or replace function inf.platform_delete(p_creator uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.creator_platforms where id = p_id and creator_id = p_creator;
end $$;

create or replace function inf.rate_card_save(p_creator uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.creator_rate_cards (creator_id, platform, format, suggested_paise, notes)
  values (p_creator, p ->> 'platform', p ->> 'format', (p ->> 'suggested_paise')::bigint, nullif(trim(p ->> 'notes'), ''))
  on conflict (creator_id, platform, format) do update set suggested_paise = excluded.suggested_paise, notes = excluded.notes
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.rate_card_delete(p_creator uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.creator_rate_cards where id = p_id and creator_id = p_creator;
end $$;

create or replace function inf.portfolio_save(p_creator uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if (select count(*) from inf.creator_portfolio where creator_id = p_creator) >= 30 then
    raise exception 'at most 30 portfolio items' using errcode = '22023';
  end if;
  insert into inf.creator_portfolio (creator_id, url, title, caption, position)
  values (p_creator, p ->> 'url', nullif(trim(p ->> 'title'), ''), nullif(trim(p ->> 'caption'), ''),
          coalesce((select max(position) + 1 from inf.creator_portfolio where creator_id = p_creator), 0))
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.portfolio_delete(p_creator uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.creator_portfolio where id = p_id and creator_id = p_creator;
end $$;

-- Extra contact numbers/emails (stored only as keyed hashes plus the last two digits for display).
create or replace function inf.creator_contact_add(p_creator uuid, p_kind text, p_label text, p_phone text, p_email text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_phone text := inf.norm_phone(p_phone);
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_phone is not null and length(v_phone) < 10 then raise exception 'invalid phone number' using errcode = '22023'; end if;
  if nullif(trim(p_email), '') is not null and p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email' using errcode = '22023'; end if;
  insert into inf.creator_contacts (creator_id, kind, label, phone_hash, email_hash, phone_last2, created_by)
  values (p_creator, p_kind, nullif(trim(p_label), ''), inf.pii_hash(v_phone), inf.pii_hash(p_email), right(v_phone, 2), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.creator_contact_delete(p_creator uuid, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.creator_contacts where id = p_id and creator_id = p_creator;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- KYC
-- ---------------------------------------------------------------------------------------------------------------
-- Save KYC details. Null PAN / account number keeps the stored value (so other fields can change without re-entry).
-- A change to PAN, bank account, IFSC or GSTIN after verification sends KYC back for verification.
create or replace function inf.kyc_save(p_creator uuid, p_pan text, p_name_on_pan text, p_gst_status text, p_gstin text,
                                        p_bank_account text, p_ifsc text, p_account_holder text, p_proof_path text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cur     inf.creator_kyc;
  v_pan     text := upper(nullif(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'), ''));
  v_acct    text := nullif(regexp_replace(coalesce(p_bank_account, ''), '\s', '', 'g'), '');
  v_ifsc    text := upper(nullif(trim(coalesce(p_ifsc, '')), ''));
  v_gstin   text := upper(nullif(trim(coalesce(p_gstin, '')), ''));
  v_status  text := coalesce(nullif(p_gst_status, ''), 'unregistered');
  v_changed boolean;
  v_complete boolean;
  v_pan_eff text;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write') or inf.has_perm('kyc.verify')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_pan is not null and not inf.valid_pan(v_pan) then return jsonb_build_object('ok', false, 'error', 'invalid_pan'); end if;
  if v_acct is not null and v_acct !~ '^\d{9,18}$' then return jsonb_build_object('ok', false, 'error', 'invalid_account'); end if;
  if v_ifsc is not null and not inf.valid_ifsc(v_ifsc) then return jsonb_build_object('ok', false, 'error', 'invalid_ifsc'); end if;
  if v_status not in ('unregistered', 'registered', 'composition') then return jsonb_build_object('ok', false, 'error', 'invalid_gst_status'); end if;
  if v_status <> 'unregistered' and (v_gstin is null or not inf.valid_gstin(v_gstin)) then return jsonb_build_object('ok', false, 'error', 'invalid_gstin'); end if;
  if v_status = 'unregistered' then v_gstin := null; end if;

  select * into v_cur from inf.creator_kyc where creator_id = p_creator for update;
  v_pan_eff := coalesce(v_pan, case when v_cur.pan_enc is not null then inf.pii_decrypt(v_cur.pan_enc) end);
  -- GSTIN characters 3–12 are the PAN.
  if v_gstin is not null and v_pan_eff is not null and substr(v_gstin, 3, 10) <> v_pan_eff then
    return jsonb_build_object('ok', false, 'error', 'gstin_pan_mismatch');
  end if;
  v_changed := v_cur.creator_id is not null and (v_pan is not null or v_acct is not null
                 or v_ifsc is distinct from v_cur.ifsc or v_gstin is distinct from v_cur.gstin);

  insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, gst_status, gstin, bank_account_enc, bank_last4, ifsc, account_holder, proof_path)
  values (p_creator, inf.pii_encrypt(v_pan), right(v_pan, 4), nullif(trim(p_name_on_pan), ''), v_status, v_gstin,
          inf.pii_encrypt(v_acct), right(v_acct, 4), v_ifsc, nullif(trim(p_account_holder), ''), nullif(p_proof_path, ''))
  on conflict (creator_id) do update set
    pan_enc = coalesce(excluded.pan_enc, inf.creator_kyc.pan_enc),
    pan_last4 = coalesce(excluded.pan_last4, inf.creator_kyc.pan_last4),
    name_on_pan = coalesce(excluded.name_on_pan, inf.creator_kyc.name_on_pan),
    gst_status = excluded.gst_status,
    gstin = excluded.gstin,
    gstin_verified = case when excluded.gstin is distinct from inf.creator_kyc.gstin then false else inf.creator_kyc.gstin_verified end,
    bank_account_enc = coalesce(excluded.bank_account_enc, inf.creator_kyc.bank_account_enc),
    bank_last4 = coalesce(excluded.bank_last4, inf.creator_kyc.bank_last4),
    ifsc = coalesce(excluded.ifsc, inf.creator_kyc.ifsc),
    account_holder = coalesce(excluded.account_holder, inf.creator_kyc.account_holder),
    proof_path = coalesce(excluded.proof_path, inf.creator_kyc.proof_path);

  select (pan_enc is not null and name_on_pan is not null and bank_account_enc is not null and ifsc is not null and account_holder is not null)
    into v_complete from inf.creator_kyc where creator_id = p_creator;
  update inf.creator_kyc set
    status = case when not v_complete then 'pending'
                  when status = 'verified' and not v_changed then 'verified'
                  else 'submitted' end,
    submitted_at = case when v_complete and (status <> 'verified' or v_changed) then now() else submitted_at end,
    verified_at = case when v_changed then null else verified_at end,
    verified_by = case when v_changed then null else verified_by end,
    rejection_reason = case when v_complete then null else rejection_reason end
  where creator_id = p_creator;
  update inf.creators set last_activity_at = now() where id = p_creator;
  return jsonb_build_object('ok', true, 'status', (select status from inf.creator_kyc where creator_id = p_creator), 'complete', v_complete);
end $$;

-- Masked view for the creator (own) and staff with kyc.read_masked.
create or replace function inf.kyc_view(p_creator uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare k inf.creator_kyc;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('kyc.read_masked')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into k from inf.creator_kyc where creator_id = p_creator;
  if k.creator_id is null then return jsonb_build_object('status', 'pending', 'exists', false); end if;
  return jsonb_build_object(
    'exists', true, 'status', k.status, 'rejection_reason', k.rejection_reason,
    'pan_masked', case when k.pan_last4 is null then null else 'XXXXXX' || k.pan_last4 end,
    'name_on_pan', k.name_on_pan, 'gst_status', k.gst_status, 'gstin', k.gstin, 'gstin_verified', k.gstin_verified,
    'bank_masked', case when k.bank_last4 is null then null else 'XXXXXXXX' || k.bank_last4 end,
    'ifsc', k.ifsc, 'account_holder', k.account_holder, 'has_proof', k.proof_path is not null,
    'submitted_at', k.submitted_at, 'verified_at', k.verified_at);
end $$;

-- Finance only: the full PAN and account number. Audited every time.
create or replace function inf.kyc_reveal(p_creator uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k inf.creator_kyc;
begin
  if not inf.has_perm('kyc.reveal') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into k from inf.creator_kyc where creator_id = p_creator;
  if k.creator_id is null then raise exception 'no KYC on file' using errcode = '22023'; end if;
  perform inf.audit('creator_kyc', p_creator::text, 'reveal', null, jsonb_build_object('reason', left(p_reason, 300)));
  return jsonb_build_object('pan', inf.pii_decrypt(k.pan_enc), 'bank_account', inf.pii_decrypt(k.bank_account_enc), 'proof_path', k.proof_path);
end $$;

create or replace function inf.kyc_verify(p_creator uuid, p_approve boolean, p_reason text, p_gstin_verified boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid;
begin
  if not inf.has_perm('kyc.verify') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not p_approve and coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required to reject' using errcode = '22023'; end if;
  update inf.creator_kyc set
    status = case when p_approve then 'verified' else 'rejected' end,
    rejection_reason = case when p_approve then null else left(p_reason, 500) end,
    gstin_verified = case when p_approve then coalesce(p_gstin_verified, false) and gstin is not null else gstin_verified end,
    verified_by = auth.uid(), verified_at = now()
  where creator_id = p_creator and status in ('submitted', 'verified', 'rejected');
  if not found then raise exception 'KYC is not ready for review' using errcode = '22023'; end if;
  perform inf.audit('creator_kyc', p_creator::text, case when p_approve then 'verify' else 'reject' end, null, jsonb_build_object('reason', p_reason));
  select user_id into v_user from inf.creator_accounts where creator_id = p_creator;
  if v_user is not null then
    perform inf.notify(v_user, 'kyc.reviewed', case when p_approve then 'Your KYC is verified' else 'Your KYC needs changes' end,
                       case when p_approve then 'You can now receive payouts.' else 'Reason: ' || left(p_reason, 300) end,
                       '/creator/kyc', '{}'::jsonb, true, 'kyc_review:' || p_creator || ':' || extract(epoch from now())::bigint);
  end if;
end $$;

-- Staff KYC review queue.
create or replace function inf.kyc_queue() returns table (creator_id uuid, display_name text, handle text, status text, submitted_at timestamptz, gst_status text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.display_name, c.handle, k.status, k.submitted_at, k.gst_status
    from inf.creator_kyc k join inf.creators c on c.id = k.creator_id
   where inf.has_perm('kyc.read_masked') and k.status = 'submitted'
   order by k.submitted_at;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.creator_platforms enable row level security;
alter table inf.creator_rate_cards enable row level security;
alter table inf.creator_portfolio enable row level security;
alter table inf.creator_contacts enable row level security;
alter table inf.creator_kyc enable row level security;

create policy creator_platforms_read on inf.creator_platforms for select to authenticated using ((select inf.can_view_creator(creator_id)));
create policy creator_rate_cards_read on inf.creator_rate_cards for select to authenticated using ((select inf.can_view_creator(creator_id)));
create policy creator_portfolio_read on inf.creator_portfolio for select to authenticated using ((select inf.can_view_creator(creator_id)));
-- Contacts: only the label, kind and last two digits are useful to read; hashes are never selected by the app.
create policy creator_contacts_read on inf.creator_contacts for select to authenticated using ((select inf.can_edit_creator(creator_id)));
-- creator_kyc: no policy. Read through kyc_view() (masked) and kyc_reveal() (Finance, audited) only.

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.creator_platforms', 'authenticated', 'select'),
  ('table', 'inf.creator_rate_cards', 'authenticated', 'select'),
  ('table', 'inf.creator_portfolio', 'authenticated', 'select'),
  ('table', 'inf.creator_contacts', 'authenticated', 'select'),
  ('function', 'inf.norm_phone(text)', 'authenticated', 'execute'),
  ('function', 'inf.valid_pan(text)', 'authenticated', 'execute'),
  ('function', 'inf.valid_ifsc(text)', 'authenticated', 'execute'),
  ('function', 'inf.valid_gstin(text)', 'authenticated', 'execute'),
  ('function', 'inf.can_edit_creator(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.can_view_creator(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creator_profile_update(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.platform_save(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.platform_delete(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.rate_card_save(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.rate_card_delete(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.portfolio_save(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.portfolio_delete(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creator_contact_add(uuid, text, text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.creator_contact_delete(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.kyc_save(uuid, text, text, text, text, text, text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.kyc_view(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.kyc_reveal(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.kyc_verify(uuid, boolean, text, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.kyc_queue()', 'authenticated', 'execute');
call inf.apply_client_grants();
