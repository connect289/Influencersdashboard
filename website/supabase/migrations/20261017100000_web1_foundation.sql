-- web1_foundation — website-owned foundation objects (spec 3A cross-cutting, Phase 2).
-- Additive only. Every object is web_-prefixed, RLS-enabled, closed to anon/authenticated, and reached only through
-- SECURITY DEFINER functions executed by the website server with the service role (docs/SCHEMA_PLAN.md).

-- ---------------------------------------------------------------------------------------------------------------------
-- Settings and feature flags (cached at the edge with a short TTL; changed from the admin without a redeploy)
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.web_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  value jsonb not null,
  description text,
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.web_settings_history (
  id bigint generated always as identity primary key,
  key text not null,
  value jsonb not null,
  version integer not null,
  changed_at timestamptz not null default now(),
  changed_by uuid
);
create index if not exists web_settings_history_key_idx on public.web_settings_history (key, version desc);

insert into public.web_settings (key, value, description) values
  ('web_advisor_enabled', 'false', 'Witty on the website (hero + /witty). Off until the shared engine is verified (D-012).'),
  ('require_phone_otp', 'false', 'Adds a phone OTP step to the gate and forms using the phone adapter (spec 7.2).'),
  ('push_unverified_gate_leads', 'false', 'Push gate attempts that never verified their email to lead_intake as unverified after N minutes.'),
  ('push_unverified_after_minutes', '60', 'Minutes before an unverified gate attempt may be pushed (only if push_unverified_gate_leads).'),
  ('document_upload_enabled', 'false', 'Document upload in the application form (spec 9.1A; sensitive data, off in v1).'),
  ('design_concept', '"a"', 'Active design concept: "a" (Luminous) or "b" (Prism) (D-023).'),
  ('default_theme', '"system"', 'Default theme: "system", "dark" or "light" (D-022).'),
  ('finder_include_regular_mode', 'false', 'Show on-campus ("Regular") catalogue rows in the finder (D-013).'),
  ('lead_writer', '"lead_intake"', 'How leads are written: "lead_intake" (D-009) or "intake_api".'),
  ('transcript_target', '"web_advisor_messages"', 'Where web chat turns are stored (D-010).'),
  ('counsellor_whatsapp', '"+919643977407"', 'WhatsApp number for "Talk to a counsellor" (D-016, S-42).'),
  ('counsellor_phone', '"+919650683269"', 'Phone number for call buttons.'),
  ('announcement', 'null', 'Announcement bar: {"text": "...", "href": "...", "tone": "info"} or null.'),
  ('web_advisor_models', '{"extractor": "claude-haiku-5-5", "counselor": "claude-sonnet-5-5"}', 'Models for the website agent (D-011).'),
  ('web_advisor_budget', '{"max_tokens_per_session": 60000, "turn_timeout_ms": 20000, "max_turns_per_session": 40}', 'Per-session token budget and per-turn timeout.'),
  ('sections', '{"popular": true, "universities": true, "how_it_works": true, "why": true, "stories": true, "guided": true, "resources": true, "faq": true}', 'Homepage sections on/off.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- Transactional outbox: side effects written in the same transaction as the lead record, processed with retries,
-- exponential backoff and a dead-letter state (spec 3A "never lose a lead").
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.web_outbox (
  id bigint generated always as identity primary key,
  kind text not null check (kind ~ '^[a-z][a-z0-9_]{1,40}$'),
  dedupe_key text not null unique,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'processing', 'done', 'dead')),
  attempts integer not null default 0,
  max_attempts integer not null default 6,
  next_attempt_at timestamptz not null default now(),
  locked_until timestamptz,
  last_error text,
  request_id text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists web_outbox_due_idx on public.web_outbox (next_attempt_at) where status in ('pending', 'processing');
create index if not exists web_outbox_dead_idx on public.web_outbox (created_at desc) where status = 'dead';

-- ---------------------------------------------------------------------------------------------------------------------
-- Audit log (every admin change) and server-side funnel events (no PII; anonymous session ids only)
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.web_audit_log (
  id bigint generated always as identity primary key,
  actor uuid,
  actor_email text,
  action text not null,
  entity text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  request_id text,
  at timestamptz not null default now()
);
create index if not exists web_audit_log_at_idx on public.web_audit_log (at desc);
create index if not exists web_audit_log_entity_idx on public.web_audit_log (entity, entity_id);

create table if not exists public.web_funnel_events (
  id bigint generated always as identity primary key,
  funnel text not null check (funnel in ('gate', 'form', 'enquiry', 'finder')),
  step text not null check (step ~ '^[a-z][a-z0-9_]{1,40}$'),
  anon_id text not null check (length(anon_id) between 8 and 64),
  context jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index if not exists web_funnel_events_idx on public.web_funnel_events (funnel, step, at desc);

-- Postgres fallback limiter (used only when the key-value store is unavailable).
create table if not exists public.web_rate_events (
  bucket text not null,
  at timestamptz not null default now()
);
create index if not exists web_rate_events_idx on public.web_rate_events (bucket, at desc);

-- ---------------------------------------------------------------------------------------------------------------------
-- Lock down: RLS on, nothing for anon/authenticated (the browser never queries tables).
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.web_settings enable row level security;
alter table public.web_settings_history enable row level security;
alter table public.web_outbox enable row level security;
alter table public.web_audit_log enable row level security;
alter table public.web_funnel_events enable row level security;
alter table public.web_rate_events enable row level security;
revoke all on public.web_settings, public.web_settings_history, public.web_outbox, public.web_audit_log,
  public.web_funnel_events, public.web_rate_events from anon, authenticated, public;

-- ---------------------------------------------------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.web_settings_all()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from public.web_settings s;
$$;

create or replace function public.web_settings_set(p_key text, p_value jsonb, p_actor uuid default null, p_actor_email text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_old public.web_settings;
  v_new public.web_settings;
begin
  if p_value is null then raise exception 'setting value is required' using errcode = '22023'; end if;
  select * into v_old from public.web_settings where key = p_key for update;
  if v_old.key is null then raise exception 'unknown setting %', p_key using errcode = '22023'; end if;
  insert into public.web_settings_history (key, value, version, changed_by) values (v_old.key, v_old.value, v_old.version, v_old.updated_by);
  update public.web_settings set value = p_value, version = version + 1, updated_at = now(), updated_by = p_actor
   where key = p_key returning * into v_new;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before, after)
  values (p_actor, p_actor_email, 'settings.update', 'web_settings', p_key, v_old.value, p_value);
  return jsonb_build_object('key', v_new.key, 'value', v_new.value, 'version', v_new.version);
end $$;

create or replace function public.web_outbox_enqueue(p_kind text, p_dedupe_key text, p_payload jsonb, p_request_id text default null, p_delay_seconds integer default 0)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.web_outbox (kind, dedupe_key, payload, request_id, next_attempt_at)
  values (p_kind, p_dedupe_key, coalesce(p_payload, '{}'::jsonb), p_request_id, now() + make_interval(secs => greatest(0, coalesce(p_delay_seconds, 0))))
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null then select id into v_id from public.web_outbox where dedupe_key = p_dedupe_key; end if;
  return v_id;
end $$;

-- Claims due work for a worker: pending, or processing whose lock expired (a worker died). Locks for 2 minutes.
create or replace function public.web_outbox_claim(p_limit integer default 20, p_kinds text[] default null)
returns setof public.web_outbox language plpgsql volatile security definer set search_path = '' as $$
begin
  return query
  with due as (
    select o.id from public.web_outbox o
     where (o.status = 'pending' or (o.status = 'processing' and o.locked_until < now()))
       and o.next_attempt_at <= now()
       and (p_kinds is null or o.kind = any (p_kinds))
     order by o.next_attempt_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  )
  update public.web_outbox o
     set status = 'processing', attempts = o.attempts + 1, locked_until = now() + interval '2 minutes'
    from due where o.id = due.id
  returning o.*;
end $$;

create or replace function public.web_outbox_done(p_id bigint)
returns void language sql volatile security definer set search_path = '' as $$
  update public.web_outbox set status = 'done', processed_at = now(), locked_until = null, last_error = null where id = p_id;
$$;

-- Failure: exponential backoff 1 m, 5 m, 30 m, 2 h, 12 h; dead after max_attempts (visible in the admin).
create or replace function public.web_outbox_fail(p_id bigint, p_error text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v public.web_outbox; v_status text;
begin
  select * into v from public.web_outbox where id = p_id for update;
  if v.id is null then return null; end if;
  v_status := case when v.attempts >= v.max_attempts then 'dead' else 'pending' end;
  update public.web_outbox
     set status = v_status, locked_until = null, last_error = left(coalesce(p_error, 'unknown error'), 2000),
         next_attempt_at = now() + case least(v.attempts, 5)
           when 1 then interval '1 minute' when 2 then interval '5 minutes' when 3 then interval '30 minutes'
           when 4 then interval '2 hours' else interval '12 hours' end
   where id = p_id;
  return v_status;
end $$;

create or replace function public.web_outbox_retry(p_id bigint, p_actor uuid default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.web_outbox set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null where id = p_id and status = 'dead';
  insert into public.web_audit_log (actor, action, entity, entity_id) values (p_actor, 'outbox.retry', 'web_outbox', p_id::text);
end $$;

create or replace function public.web_funnel_track(p_funnel text, p_step text, p_anon_id text, p_context jsonb default '{}'::jsonb)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_funnel_events (funnel, step, anon_id, context) values (p_funnel, p_step, p_anon_id, coalesce(p_context, '{}'::jsonb) - 'email' - 'phone' - 'name');
$$;

-- Fallback sliding-window limiter: records a hit and reports whether the bucket is within its limit.
create or replace function public.web_rate_hit(p_bucket text, p_window_seconds integer, p_limit integer)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_count integer;
begin
  delete from public.web_rate_events where bucket = p_bucket and at < now() - make_interval(secs => p_window_seconds);
  select count(*) into v_count from public.web_rate_events where bucket = p_bucket;
  if v_count >= p_limit then return false; end if;
  insert into public.web_rate_events (bucket) values (p_bucket);
  return true;
end $$;

-- Health snapshot for /api/health and the oversight system.
create or replace function public.web_health()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'db', true,
    'at', now(),
    'catalogue_rows', (select count(*) from public.catalog_programs where active),
    'outbox_pending', (select count(*) from public.web_outbox where status in ('pending', 'processing')),
    'outbox_dead', (select count(*) from public.web_outbox where status = 'dead'),
    'outbox_oldest_pending_seconds', (select coalesce(extract(epoch from now() - min(created_at))::int, 0) from public.web_outbox where status = 'pending')
  );
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.web_settings_all()', 'public.web_settings_set(text, jsonb, uuid, text)',
    'public.web_outbox_enqueue(text, text, jsonb, text, integer)', 'public.web_outbox_claim(integer, text[])',
    'public.web_outbox_done(bigint)', 'public.web_outbox_fail(bigint, text)', 'public.web_outbox_retry(bigint, uuid)',
    'public.web_funnel_track(text, text, text, jsonb)', 'public.web_rate_hit(text, integer, integer)', 'public.web_health()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
