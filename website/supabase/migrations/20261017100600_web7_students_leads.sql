-- web7_students_leads — website identity, email verification, consent ledger, applications and the approved lead path
-- (spec 7.2, 9.1A, 9.1, 12; docs/SCHEMA_PLAN.md §2.3 and §4; D-005, D-009). Students are website-owned identities (not
-- shared Supabase Auth users, D-005). Leads are written only through public.lead_intake() with source_system web_agent.

-- ---------------------------------------------------------------------------------------------------------------
create table if not exists public.web_consent_texts (
  version text primary key,
  channel text not null check (channel in ('gate', 'form', 'marketing')),
  body text not null,
  purposes text[] not null,
  active boolean not null default true,
  legal_reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
insert into public.web_consent_texts (version, channel, body, purposes) values
  ('web-gate-2026-10-v1', 'gate', 'I agree that Eduwit Learning Services may use my name, phone number and email to help me choose a programme and with my admission, and may share them with our partner universities and our admission partners (edtech companies). My chat with Witty, Eduwit''s AI admissions assistant, is stored to answer me and to improve the service. I can withdraw consent or ask for my data to be deleted at any time.', array['sales', 'partner_share', 'ai_chat_storage']),
  ('web-form-2026-10-v1', 'form', 'I agree that Eduwit Learning Services may use the details I have entered to help me with my admission, and may share them with our partner universities and our admission partners (edtech companies). A counsellor may call, WhatsApp or email me about this enquiry. I can withdraw consent or ask for my data to be deleted at any time.', array['sales', 'partner_share']),
  ('web-marketing-2026-10-v1', 'marketing', 'Send me programme updates on WhatsApp and email.', array['marketing'])
on conflict (version) do nothing;

create table if not exists public.web_students (
  id uuid primary key default gen_random_uuid(),
  email_norm text not null unique check (email_norm = lower(email_norm)),
  phone_e164 text check (phone_e164 ~ '^\+91[6-9]\d{9}$'),
  full_name text,
  lead_id bigint,
  email_verified_at timestamptz,
  phone_verified_at timestamptz,          -- null at launch (no phone OTP)
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  deleted_at timestamptz
);

-- One table for email codes and the (disabled) phone-OTP adapter.
create table if not exists public.web_verification_codes (
  id bigint generated always as identity primary key,
  attempt_id uuid not null,
  channel text not null default 'email' check (channel in ('email', 'phone')),
  target text not null,                    -- normalised email or E.164 phone
  code_hash text not null,                 -- HMAC(pepper, attempt:code); the code itself is never stored
  expires_at timestamptz not null,
  resend_after timestamptz not null,
  attempts integer not null default 0,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists web_verification_codes_attempt_idx on public.web_verification_codes (attempt_id, created_at desc);
create index if not exists web_verification_codes_target_idx on public.web_verification_codes (target, created_at desc);

create table if not exists public.web_gate_attempts (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  surface text not null check (surface in ('gate', 'application', 'enquiry', 'signin')),
  context jsonb not null default '{}',     -- {offering_id, group_key, university_slug, programme_label}
  full_name text,
  email_norm text not null,
  phone_e164 text,
  consent_version text references public.web_consent_texts (version),
  consent_marketing boolean not null default false,
  attribution jsonb not null default '{}',
  junk_score smallint not null default 0,
  junk_reasons text[] not null default '{}',
  ip_hash text,
  device_hash text,
  turnstile_ok boolean,
  is_test boolean not null default false,
  submitted_at timestamptz not null default now(),
  code_sent_at timestamptz,
  verified_at timestamptz,
  first_message_at timestamptz,
  student_id uuid references public.web_students (id),
  lead_id bigint,
  lead_action text,
  pushed_unverified_at timestamptz
);
create index if not exists web_gate_attempts_email_idx on public.web_gate_attempts (email_norm, submitted_at desc);
create index if not exists web_gate_attempts_unverified_idx on public.web_gate_attempts (submitted_at) where verified_at is null and pushed_unverified_at is null;

create table if not exists public.web_email_verifications (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.web_students (id),
  email_norm text not null,
  attempt_id uuid not null,
  verified_at timestamptz not null default now(),
  method text not null default 'email_code'
);

create table if not exists public.web_consents (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.web_students (id),
  lead_id bigint,
  version text not null references public.web_consent_texts (version),
  purposes text[] not null,
  surface text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  ip_hash text
);
create index if not exists web_consents_student_idx on public.web_consents (student_id);

create table if not exists public.web_student_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.web_students (id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz,
  ua_hash text
);
create index if not exists web_student_sessions_student_idx on public.web_student_sessions (student_id);

create table if not exists public.web_lead_submissions (
  idempotency_key text primary key,
  student_id uuid,
  kind text not null,
  result jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.web_applications (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  kind text not null default 'application' check (kind in ('application', 'enquiry')),
  attempt_id uuid not null references public.web_gate_attempts (id),
  student_id uuid references public.web_students (id),
  lead_id bigint,
  context jsonb not null default '{}',
  offering_id bigint,
  preferred_offering_ids bigint[] not null default '{}',
  steps jsonb not null default '{}',      -- answers per step, including fields with no lead column (A-LEAD-2)
  eligibility_note text,
  status text not null default 'started' check (status in ('started', 'step_2', 'step_3', 'step_4', 'submitted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz
);
create index if not exists web_applications_student_idx on public.web_applications (student_id, created_at desc);

create table if not exists public.web_shortlists (
  student_id uuid not null references public.web_students (id),
  catalog_program_id bigint not null,
  created_at timestamptz not null default now(),
  primary key (student_id, catalog_program_id)
);
create table if not exists public.web_saved_comparisons (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.web_students (id),
  offering_ids bigint[] not null check (cardinality(offering_ids) between 2 and 4),
  created_at timestamptz not null default now()
);

create table if not exists public.web_block_list (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('email', 'domain', 'phone', 'ip_hash')),
  value text not null,
  reason text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (kind, value)
);
create table if not exists public.web_disposable_domains (domain text primary key);
insert into public.web_disposable_domains (domain)
select unnest(array['mailinator.com','guerrillamail.com','guerrillamail.net','sharklasers.com','10minutemail.com','tempmail.com',
  'temp-mail.org','yopmail.com','yopmail.net','throwawaymail.com','getnada.com','dispostable.com','trashmail.com','maildrop.cc',
  'mailnesia.com','mintemail.com','fakeinbox.com','emailondeck.com','tempr.email','moakt.com','mohmal.com','burnermail.io',
  'spamgourmet.com','mailcatch.com','tempinbox.com','discard.email','spambox.us','mytemp.email','tmpmail.org','tmail.ws',
  'emailfake.com','fakemail.net','inboxkitten.com','mail.tm','mailpoof.com','tempmailo.com','luxusmail.org','cock.li'])
on conflict do nothing;

create table if not exists public.web_deletion_requests (
  id bigint generated always as identity primary key,
  student_id uuid references public.web_students (id),
  email_norm text not null,
  kind text not null default 'delete' check (kind in ('delete', 'opt_out', 'export')),
  requested_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'done', 'rejected')),
  processed_at timestamptz,
  processed_by text,
  note text
);

do $$
declare t text;
begin
  foreach t in array array['web_consent_texts','web_students','web_verification_codes','web_gate_attempts','web_email_verifications',
    'web_consents','web_student_sessions','web_lead_submissions','web_applications','web_shortlists','web_saved_comparisons',
    'web_block_list','web_disposable_domains','web_deletion_requests'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Screening (spec 7.2 abuse protection): block list and disposable domains. Turnstile, rate limits, honeypot and the
-- junk score run in the website before this is called.
create or replace function public.web_email_screen(p_email text, p_phone text, p_ip_hash text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.web_disposable_domains d where d.domain = split_part(lower(p_email), '@', 2))
      then jsonb_build_object('ok', false, 'reason', 'disposable_email')
    when exists (select 1 from public.web_block_list b where (b.expires_at is null or b.expires_at > now()) and (
        (b.kind = 'email' and b.value = lower(p_email)) or (b.kind = 'domain' and b.value = split_part(lower(p_email), '@', 2))
        or (b.kind = 'phone' and b.value = p_phone) or (b.kind = 'ip_hash' and b.value = p_ip_hash)))
      then jsonb_build_object('ok', false, 'reason', 'blocked')
    else jsonb_build_object('ok', true)
  end
$$;

-- Records the attempt (idempotent per key) and stores a new hashed code. 10-minute expiry, resend after 30 s, at most
-- 5 codes per email per hour.
create or replace function public.web_gate_start(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(p->>'email'));
  v_attempt public.web_gate_attempts;
  v_recent int;
  v_screen jsonb;
begin
  v_screen := public.web_email_screen(v_email, p->>'phone', p->>'ip_hash');
  if not (v_screen->>'ok')::boolean then return v_screen; end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_email and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;

  insert into public.web_gate_attempts as a (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version,
    consent_marketing, attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', v_email, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash',
    (p->>'turnstile_ok')::boolean, coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do update set
    full_name = excluded.full_name, email_norm = excluded.email_norm, phone_e164 = excluded.phone_e164,
    consent_version = excluded.consent_version, consent_marketing = excluded.consent_marketing, context = excluded.context,
    junk_score = excluded.junk_score, junk_reasons = excluded.junk_reasons, submitted_at = now()
  where a.verified_at is null
  returning * into v_attempt;
  if v_attempt.id is null then
    select * into v_attempt from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_attempt.id);
  end if;

  update public.web_verification_codes set consumed_at = now() where attempt_id = v_attempt.id and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (v_attempt.id, 'email', v_email, p->>'code_hash', now() + interval '10 minutes', now() + interval '30 seconds');
  update public.web_gate_attempts set code_sent_at = now() where id = v_attempt.id;
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', v_attempt.id, 'resend_in', 30);
end $$;

-- What the website needs to re-derive a code hash for an attempt (the hash is bound to the attempt's idempotency key).
create or replace function public.web_gate_attempt_info(p_attempt uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('key', idempotency_key, 'surface', surface, 'email', email_norm, 'verified', verified_at is not null)
  from public.web_gate_attempts where id = p_attempt
$$;

create or replace function public.web_gate_resend(p_attempt uuid, p_code_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_last public.web_verification_codes; v_recent int;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt;
  if v_a.id is null or v_a.verified_at is not null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select * into v_last from public.web_verification_codes where attempt_id = p_attempt order by created_at desc limit 1;
  if v_last.resend_after > now() then
    return jsonb_build_object('ok', false, 'reason', 'too_soon', 'resend_in', ceil(extract(epoch from v_last.resend_after - now())));
  end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_a.email_norm and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  update public.web_verification_codes set consumed_at = now() where attempt_id = p_attempt and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (p_attempt, 'email', v_a.email_norm, p_code_hash, now() + interval '10 minutes', now() + interval '30 seconds');
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', p_attempt, 'resend_in', 30, 'email', v_a.email_norm);
end $$;

-- The lead_intake payload for an attempt (spec 7.2, docs/SCHEMA_PLAN.md §4.1). Only allow-listed lead keys; catalogue
-- names for the programme context; no IP address (D-019).
create or replace function public.web_lead_payload(p_attempt public.web_gate_attempts, p_session uuid, p_event text, p_extra jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_gate boolean := p_attempt.surface = 'gate';
  v_ctx jsonb := p_attempt.context;
  v_off public.web_offering_search;
  v_ct public.web_consent_texts;
  a jsonb := p_attempt.attribution;
  v_lead jsonb;
begin
  if (v_ctx->>'offering_id') is not null then
    select * into v_off from public.web_offering_search where id = (v_ctx->>'offering_id')::bigint;
  end if;
  select * into v_ct from public.web_consent_texts where version = p_attempt.consent_version;
  v_lead := jsonb_strip_nulls(jsonb_build_object(
    'full_name', p_attempt.full_name, 'is_name_confirmed', true,
    'email', p_attempt.email_norm, 'is_email_confirmed', true,
    'source', case when v_gate then 'website_agent' else 'website_form' end,
    'channel', case when v_gate then 'web' else 'web_form' end,
    'first_agent_channel', case when v_gate then 'web' end,
    'source_detail', p_attempt.surface,
    'web_session_id', p_session::text,
    'interested_course', coalesce(v_off.programme_name, v_ctx->>'programme_label'),
    'interested_specialization', v_off.spec_name,
    'interested_university', v_off.uni_name,
    'programme_level', v_off.level_short,
    'study_mode_preference', v_off.mode,
    'utm_source', a->>'utm_source', 'utm_medium', a->>'utm_medium', 'utm_campaign', a->>'utm_campaign',
    'utm_content', a->>'utm_content', 'utm_term', a->>'utm_term', 'click_ids', a->'click_ids',
    'landing_url', a->>'landing_url', 'referrer_url', a->>'referrer_url', 'referred_by_code', a->>'referred_by_code',
    'campaign', a->>'utm_campaign', 'device_type', a->>'device_type',
    'consent_sales_at', case when 'sales' = any(v_ct.purposes) then p_attempt.verified_at end,
    'consent_partner_share_at', case when 'partner_share' = any(v_ct.purposes) then p_attempt.verified_at end,
    'consent_marketing_at', case when p_attempt.consent_marketing then p_attempt.verified_at end,
    'consent_text_version', p_attempt.consent_version
  )) || coalesce(p_extra, '{}');
  return jsonb_build_object('phone', p_attempt.phone_e164, 'source_system', 'web_agent', 'event_type', p_event,
    'lead', v_lead, 'attribution', a, 'is_test', p_attempt.is_test, 'occurred_at', now());
end $$;

-- After the email is proven (code, or an existing signed-in session for the same email): creates/links the student,
-- records the consent and verification, creates a session, writes the lead through lead_intake (exactly once per
-- attempt) and queues side effects — all in the caller's transaction.
create or replace function public.web_gate_complete(p_attempt uuid, p_ua_hash text, p_method text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_s public.web_students; v_sid uuid; v_ct public.web_consent_texts; v_res jsonb; v_key text;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt for update;
  insert into public.web_students as s (email_norm, phone_e164, full_name, email_verified_at, last_seen_at)
  values (v_a.email_norm, v_a.phone_e164, v_a.full_name, now(), now())
  on conflict (email_norm) do update set phone_e164 = coalesce(excluded.phone_e164, s.phone_e164),
    full_name = coalesce(excluded.full_name, s.full_name), email_verified_at = coalesce(s.email_verified_at, now()),
    last_seen_at = now(), deleted_at = null
  returning * into v_s;
  insert into public.web_email_verifications (student_id, email_norm, attempt_id, method) values (v_s.id, v_a.email_norm, v_a.id, p_method);
  insert into public.web_student_sessions (student_id, expires_at, last_seen_at, ua_hash) values (v_s.id, now() + interval '90 days', now(), p_ua_hash)
  returning id into v_sid;
  update public.web_gate_attempts set verified_at = now(), student_id = v_s.id where id = v_a.id returning * into v_a;

  if v_a.consent_version is not null then
    select * into v_ct from public.web_consent_texts where version = v_a.consent_version;
    insert into public.web_consents (student_id, version, purposes, surface, ip_hash) values (v_s.id, v_ct.version, v_ct.purposes, v_a.surface, v_a.ip_hash);
    if v_a.consent_marketing then
      insert into public.web_consents (student_id, version, purposes, surface, ip_hash)
      select v_s.id, version, purposes, v_a.surface, v_a.ip_hash from public.web_consent_texts where channel = 'marketing' and active limit 1;
    end if;
  end if;

  -- Lead: exactly once per attempt (web_lead_submissions), through the shared lead_intake (D-009).
  if v_a.phone_e164 is not null and v_a.surface <> 'signin' then
    v_key := 'web:verify:' || v_a.id::text;
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_s.id, v_a.surface || '.verified')
    on conflict do nothing;
    if found then
      v_res := public.lead_intake(public.web_lead_payload(v_a, v_sid, 'lead.verified') || jsonb_build_object('idempotency_key', v_key));
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_gate_attempts set lead_id = (v_res->>'lead_id')::bigint, lead_action = v_res->>'action' where id = v_a.id;
      update public.web_students set lead_id = coalesce(lead_id, (v_res->>'lead_id')::bigint) where id = v_s.id;
      update public.web_consents set lead_id = (v_res->>'lead_id')::bigint where student_id = v_s.id and lead_id is null;
      perform public.web_outbox_enqueue('capi_lead', 'capi_lead:' || v_a.id::text,
        jsonb_build_object('event_id', v_a.id, 'email', v_a.email_norm, 'phone', v_a.phone_e164, 'surface', v_a.surface,
                           'attribution', v_a.attribution, 'marketing_consent', v_a.consent_marketing));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'status', 'verified', 'student_id', v_s.id, 'session_id', v_sid,
    'lead_id', coalesce((v_res->>'lead_id')::bigint, v_s.lead_id), 'lead_action', v_res->>'action', 'email', v_s.email_norm);
end $$;

create or replace function public.web_gate_verify(p_attempt uuid, p_code_hash text, p_ua_hash text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_c public.web_verification_codes;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt for update;
  if v_a.id is null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if v_a.verified_at is not null then
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'student_id', v_a.student_id, 'lead_id', v_a.lead_id);
  end if;
  select * into v_c from public.web_verification_codes where attempt_id = p_attempt and consumed_at is null and expires_at > now()
   order by created_at desc limit 1 for update;
  if v_c.id is null then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;
  if v_c.attempts >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_attempts'); end if;
  if v_c.code_hash <> p_code_hash then
    update public.web_verification_codes set attempts = attempts + 1 where id = v_c.id;
    return jsonb_build_object('ok', false, 'reason', case when v_c.attempts + 1 >= 5 then 'too_many_attempts' else 'wrong_code' end, 'attempts_left', greatest(0, 4 - v_c.attempts));
  end if;
  update public.web_verification_codes set consumed_at = now() where id = v_c.id;
  return public.web_gate_complete(p_attempt, p_ua_hash, 'email_code');
end $$;

-- A signed-in student whose session email matches the form email skips the code (spec 9.1A "signed-in users skip
-- email verification"). The website checks the session before calling this.
create or replace function public.web_gate_start_trusted(p jsonb, p_student uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid; s public.web_students;
begin
  select * into s from public.web_students where id = p_student and deleted_at is null;
  if s.id is null or s.email_norm <> lower(btrim(p->>'email')) then return jsonb_build_object('ok', false, 'reason', 'session_mismatch'); end if;
  insert into public.web_gate_attempts (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version, consent_marketing,
    attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', s.email_norm, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash', (p->>'turnstile_ok')::boolean,
    coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_id);
  end if;
  return public.web_gate_complete(v_id, null, 'session') || jsonb_build_object('attempt_id', v_id);
end $$;

-- Application / enquiry: created at verification; steps enrich the same lead; submit marks an application request.
create or replace function public.web_application_open(p_attempt uuid, p_kind text, p_reference text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_app public.web_applications;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt;
  if v_a.id is null or v_a.verified_at is null then return jsonb_build_object('ok', false, 'reason', 'not_verified'); end if;
  select * into v_app from public.web_applications where attempt_id = p_attempt;
  if v_app.id is null then
    insert into public.web_applications (reference, kind, attempt_id, student_id, lead_id, context, offering_id)
    values (p_reference, p_kind, p_attempt, v_a.student_id, v_a.lead_id, v_a.context, (v_a.context->>'offering_id')::bigint)
    returning * into v_app;
  end if;
  return jsonb_build_object('ok', true, 'application_id', v_app.id, 'reference', v_app.reference);
end $$;

create or replace function public.web_application_save_step(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_app public.web_applications; v_a public.web_gate_attempts; v_step int := (p->>'step')::int; v_data jsonb := coalesce(p->'data', '{}');
  v_lead jsonb := case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end; v_key text; v_res jsonb;
begin
  select * into v_app from public.web_applications where attempt_id = (p->>'attempt_id')::uuid for update;
  if v_app.id is null then return jsonb_build_object('ok', false, 'reason', 'no_application'); end if;
  -- Only the verified student who owns the application (from the signed session) may change it.
  if v_app.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  select * into v_a from public.web_gate_attempts where id = v_app.attempt_id;
  update public.web_applications set steps = jsonb_set(steps, array[v_step::text], v_data), updated_at = now(),
    status = case when status = 'submitted' then status else 'step_' || least(4, v_step)::text end,
    preferred_offering_ids = case when p ? 'preferred_offering_ids' then array(select jsonb_array_elements_text(p->'preferred_offering_ids')::bigint) else preferred_offering_ids end,
    eligibility_note = coalesce(p->>'eligibility_note', eligibility_note)
  where id = v_app.id;
  -- Enrich the same lead (approved update path: lead_intake, trusted web_agent; first-touch fields never change).
  if v_a.phone_e164 is not null and v_lead <> '{}' then
    v_key := 'web:step:' || v_app.id::text || ':' || v_step || ':' || md5(v_lead::text);
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_app.student_id, 'application.step_' || v_step)
    on conflict do nothing;
    if found then
      v_res := public.lead_intake(jsonb_build_object('phone', v_a.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.updated',
        'lead', v_lead, 'idempotency_key', v_key, 'is_test', v_a.is_test));
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.web_application_submit(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_app public.web_applications; v_a public.web_gate_attempts; v_key text; v_res jsonb;
begin
  select * into v_app from public.web_applications where attempt_id = (p->>'attempt_id')::uuid for update;
  if v_app.id is null then return jsonb_build_object('ok', false, 'reason', 'no_application'); end if;
  if v_app.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  if v_app.status = 'submitted' then return jsonb_build_object('ok', true, 'reference', v_app.reference, 'status', 'already_submitted'); end if;
  select * into v_a from public.web_gate_attempts where id = v_app.attempt_id;
  update public.web_applications set status = 'submitted', submitted_at = now(), updated_at = now(),
    steps = steps || jsonb_build_object('final', coalesce(p->'data', '{}')) where id = v_app.id;
  v_key := 'web:submit:' || v_app.id::text;
  insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_app.student_id, v_app.kind || '.submitted')
  on conflict do nothing;
  if found and v_a.phone_e164 is not null then
    v_res := public.lead_intake(jsonb_build_object('phone', v_a.phone_e164, 'source_system', 'web_agent',
      'event_type', case when v_app.kind = 'application' then 'lead.application_requested' else 'lead.enquiry' end,
      'lead', jsonb_strip_nulls(case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end || jsonb_build_object('last_intent', case when v_app.kind = 'application' then 'wants_to_apply' else 'enquiry' end)),
      'idempotency_key', v_key, 'is_test', v_a.is_test));
    update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
    perform public.web_outbox_enqueue('email_confirmation', 'email_confirmation:' || v_app.id::text,
      jsonb_build_object('kind', v_app.kind, 'reference', v_app.reference, 'email', v_a.email_norm, 'name', v_a.full_name, 'context', v_app.context));
    if v_app.kind = 'application' then
      perform public.web_outbox_enqueue('capi_submit_application', 'capi_submit:' || v_app.id::text,
        jsonb_build_object('event_id', v_app.id, 'email', v_a.email_norm, 'phone', v_a.phone_e164, 'attribution', v_a.attribution,
                           'marketing_consent', v_a.consent_marketing));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'reference', v_app.reference, 'status', 'submitted');
end $$;

-- Sessions (signed cookie carries the session id; this row allows revocation).
create or replace function public.web_session_check(p_sid uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v public.web_student_sessions; s public.web_students;
begin
  select * into v from public.web_student_sessions where id = p_sid and revoked_at is null and expires_at > now();
  if v.id is null then return null; end if;
  select * into s from public.web_students where id = v.student_id and deleted_at is null;
  if s.id is null then return null; end if;
  if v.last_seen_at is null or v.last_seen_at < now() - interval '10 minutes' then
    update public.web_student_sessions set last_seen_at = now() where id = p_sid;
    update public.web_students set last_seen_at = now() where id = s.id;
  end if;
  return jsonb_build_object('student_id', s.id, 'email', s.email_norm, 'name', s.full_name, 'phone', s.phone_e164, 'lead_id', s.lead_id);
end $$;

create or replace function public.web_session_revoke(p_sid uuid)
returns void language sql volatile security definer set search_path = '' as $$
  update public.web_student_sessions set revoked_at = now() where id = p_sid and revoked_at is null
$$;

-- Account (spec 12).
create or replace function public.web_account(p_student uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'profile', (select jsonb_build_object('email', email_norm, 'name', full_name, 'phone', phone_e164, 'email_verified_at', email_verified_at, 'created_at', created_at)
                from public.web_students where id = p_student),
    'shortlist', coalesce((select jsonb_agg(catalog_program_id order by created_at) from public.web_shortlists where student_id = p_student), '[]'),
    'comparisons', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ids', to_jsonb(offering_ids), 'created_at', created_at) order by created_at desc)
                from public.web_saved_comparisons where student_id = p_student), '[]'),
    'applications', coalesce((select jsonb_agg(jsonb_build_object('reference', reference, 'kind', kind, 'status', status, 'offering_id', offering_id,
                'programme', context->>'programme_label', 'created_at', created_at, 'submitted_at', submitted_at) order by created_at desc)
                from public.web_applications where student_id = p_student), '[]'),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('version', c.version, 'purposes', to_jsonb(c.purposes), 'granted_at', c.granted_at,
                'withdrawn_at', c.withdrawn_at, 'body', t.body) order by c.granted_at desc)
                from public.web_consents c join public.web_consent_texts t on t.version = c.version where c.student_id = p_student), '[]'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'requested_at', requested_at) order by requested_at desc)
                from public.web_deletion_requests where student_id = p_student), '[]'))
$$;

create or replace function public.web_shortlist_merge(p_student uuid, p_ids bigint[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  insert into public.web_shortlists (student_id, catalog_program_id)
  select p_student, i from unnest(p_ids[1:200]) i on conflict do nothing;
  return coalesce((select jsonb_agg(catalog_program_id order by created_at) from public.web_shortlists where student_id = p_student), '[]');
end $$;

create or replace function public.web_shortlist_remove(p_student uuid, p_id bigint)
returns void language sql volatile security definer set search_path = '' as $$
  delete from public.web_shortlists where student_id = p_student and catalog_program_id = p_id
$$;

create or replace function public.web_comparison_save(p_student uuid, p_ids bigint[])
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_saved_comparisons (student_id, offering_ids) values (p_student, p_ids[1:4])
$$;

-- Withdraw consent: recorded in the ledger; withdrawing sales/partner consent opts the lead out of contact
-- (lead_intake can only turn is_opted_out on). Marketing-only withdrawal does not opt out of the enquiry itself.
create or replace function public.web_consent_withdraw(p_student uuid, p_purposes text[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.web_students; v_res jsonb;
begin
  select * into s from public.web_students where id = p_student;
  if s.id is null then return jsonb_build_object('ok', false); end if;
  update public.web_consents set withdrawn_at = now() where student_id = p_student and withdrawn_at is null and purposes && p_purposes;
  if p_purposes && array['sales', 'partner_share'] and s.phone_e164 is not null then
    v_res := public.lead_intake(jsonb_build_object('phone', s.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.opted_out',
      'lead', jsonb_build_object('is_opted_out', true), 'idempotency_key', 'web:optout:' || p_student::text || ':' || extract(epoch from now())::bigint));
  end if;
  insert into public.web_audit_log (action, entity, entity_id, after) values ('student.consent_withdrawn', 'web_students', p_student::text, to_jsonb(p_purposes));
  return jsonb_build_object('ok', true, 'lead', v_res);
end $$;

create or replace function public.web_deletion_request(p_student uuid, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.web_students; v_id bigint;
begin
  select * into s from public.web_students where id = p_student;
  if s.id is null then return jsonb_build_object('ok', false); end if;
  select id into v_id from public.web_deletion_requests where student_id = p_student and kind = p_kind and status = 'open';
  if v_id is null then
    insert into public.web_deletion_requests (student_id, email_norm, kind) values (p_student, s.email_norm, p_kind) returning id into v_id;
    perform public.web_outbox_enqueue('email_confirmation', 'privacy_request:' || v_id, jsonb_build_object('kind', 'privacy_request', 'request', p_kind, 'email', s.email_norm, 'name', s.full_name));
  end if;
  return jsonb_build_object('ok', true, 'request_id', v_id);
end $$;

-- Optional (setting push_unverified_gate_leads, default off): gate attempts never verified are pushed to lead_intake as
-- unverified after N minutes. Called by the outbox worker's cron.
create or replace function public.web_push_unverified()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_on boolean; v_min int; a public.web_gate_attempts; n int := 0; v_key text; v_res jsonb;
begin
  select coalesce((select value = 'true'::jsonb from public.web_settings where key = 'push_unverified_gate_leads'), false) into v_on;
  if not v_on then return jsonb_build_object('enabled', false); end if;
  select coalesce((select (value #>> '{}')::int from public.web_settings where key = 'push_unverified_after_minutes'), 60) into v_min;
  for a in select * from public.web_gate_attempts where verified_at is null and pushed_unverified_at is null and phone_e164 is not null
             and junk_score < 50 and submitted_at < now() - make_interval(mins => v_min) order by submitted_at limit 50 for update skip locked loop
    v_key := 'web:unverified:' || a.id::text;
    insert into public.web_lead_submissions (idempotency_key, kind) values (v_key, a.surface || '.unverified') on conflict do nothing;
    if found then
      v_res := public.lead_intake(public.web_lead_payload(a, null, 'lead.unverified',
        jsonb_build_object('is_email_confirmed', false, 'source_detail', a.surface || '_unverified')) || jsonb_build_object('idempotency_key', v_key));
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_gate_attempts set pushed_unverified_at = now(), lead_id = (v_res->>'lead_id')::bigint where id = a.id;
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('enabled', true, 'pushed', n);
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.web_email_screen(text, text, text)', 'public.web_gate_start(jsonb)', 'public.web_gate_resend(uuid, text)', 'public.web_gate_attempt_info(uuid)',
    'public.web_lead_payload(public.web_gate_attempts, uuid, text, jsonb)', 'public.web_gate_verify(uuid, text, text)',
    'public.web_gate_complete(uuid, text, text)', 'public.web_gate_start_trusted(jsonb, uuid)',
    'public.web_application_open(uuid, text, text)', 'public.web_application_save_step(jsonb)', 'public.web_application_submit(jsonb)',
    'public.web_session_check(uuid)', 'public.web_session_revoke(uuid)', 'public.web_account(uuid)', 'public.web_shortlist_merge(uuid, bigint[])',
    'public.web_shortlist_remove(uuid, bigint)', 'public.web_comparison_save(uuid, bigint[])', 'public.web_consent_withdraw(uuid, text[])',
    'public.web_deletion_request(uuid, text)', 'public.web_push_unverified()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
