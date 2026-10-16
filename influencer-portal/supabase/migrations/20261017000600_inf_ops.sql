-- Influencer Portal: operations foundation.
-- Domain events, jobs (retries, backoff, dead letter, idempotency), notifications core (in-app + delivery queue for
-- email and WhatsApp), rate limiting, platform terms, storage buckets (SHARED_CHANGES S-4), Realtime (S-6) and the
-- pg_cron dispatcher (S-3).

-- ---------------------------------------------------------------------------------------------------------------
-- Domain events (append-only). Feed the compensation runner, notifications and outbound webhooks.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.domain_events (
  id            bigint generated always as identity primary key,
  type          text not null check (type ~ '^[a-z_]+\.[a-z_.]+$'),
  subject_type  text not null,
  subject_id    text not null,
  payload       jsonb not null default '{}'::jsonb,
  idem_key      text not null unique,
  actor_id      uuid,
  occurred_at   timestamptz not null default now()
);
create index domain_events_subject_idx on inf.domain_events (subject_type, subject_id, occurred_at desc);
create index domain_events_type_idx on inf.domain_events (type, id);
create trigger domain_events_append_only before update or delete on inf.domain_events
  for each row execute function inf.forbid_mutation();

-- Internal: idempotent on idem_key; returns the event id (existing or new).
create or replace function inf.emit_event(p_type text, p_subject_type text, p_subject_id text, p_payload jsonb, p_idem_key text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into inf.domain_events (type, subject_type, subject_id, payload, idem_key, actor_id)
  values (p_type, p_subject_type, p_subject_id, coalesce(p_payload, '{}'::jsonb), p_idem_key, auth.uid())
  on conflict (idem_key) do nothing
  returning id into v_id;
  if v_id is null then select id into v_id from inf.domain_events where idem_key = p_idem_key; end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Jobs. Claimed with SKIP LOCKED by the job runner (/api/internal/jobs), retried with exponential backoff, dead after
-- max_attempts. idem_key makes enqueueing idempotent.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.jobs (
  id            bigint generated always as identity primary key,
  kind          text not null check (kind ~ '^[a-z_]+(\.[a-z_]+)*$'),
  payload       jsonb not null default '{}'::jsonb,
  status        text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed', 'dead', 'cancelled')),
  attempts      int not null default 0,
  max_attempts  int not null default 6 check (max_attempts between 1 and 20),
  run_at        timestamptz not null default now(),
  locked_at     timestamptz,
  locked_by     text,
  last_error    text,
  idem_key      text unique,
  created_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index jobs_due_idx on inf.jobs (run_at) where status in ('queued', 'failed');
create index jobs_status_idx on inf.jobs (status, kind);

create or replace function inf.job_enqueue(p_kind text, p_payload jsonb, p_run_at timestamptz default now(),
                                           p_idem_key text default null, p_max_attempts int default 6)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into inf.jobs (kind, payload, run_at, idem_key, max_attempts)
  values (p_kind, coalesce(p_payload, '{}'::jsonb), coalesce(p_run_at, now()), p_idem_key, p_max_attempts)
  on conflict (idem_key) do nothing
  returning id into v_id;
  if v_id is null then select id into v_id from inf.jobs where idem_key = p_idem_key; end if;
  return v_id;
end $$;

-- service_role: claim up to p_limit due jobs. A job stuck in "running" for 10 minutes is claimable again.
create or replace function inf.job_claim(p_worker text, p_limit int default 20, p_kinds text[] default null)
returns setof inf.jobs language plpgsql security definer set search_path = '' as $$
begin
  return query
  with due as (
    select j.id from inf.jobs j
     where ((j.status in ('queued', 'failed') and j.run_at <= now())
            or (j.status = 'running' and j.locked_at < now() - interval '10 minutes'))
       and (p_kinds is null or j.kind = any (p_kinds))
     order by j.run_at
     limit least(greatest(p_limit, 1), 100)
     for update skip locked)
  update inf.jobs j set status = 'running', attempts = j.attempts + 1, locked_at = now(), locked_by = left(p_worker, 80)
    from due where j.id = due.id
  returning j.*;
end $$;

-- service_role: finish a claimed job. Failures back off 1, 2, 4, 8… minutes (capped at 6 h), then go dead.
create or replace function inf.job_finish(p_id bigint, p_ok boolean, p_error text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_job inf.jobs; v_status text;
begin
  select * into v_job from inf.jobs where id = p_id for update;
  if v_job.id is null or v_job.status <> 'running' then return 'ignored'; end if;
  if p_ok then
    v_status := 'done';
    update inf.jobs set status = 'done', finished_at = now(), locked_at = null, last_error = null where id = p_id;
  elsif v_job.attempts >= v_job.max_attempts then
    v_status := 'dead';
    update inf.jobs set status = 'dead', finished_at = now(), locked_at = null, last_error = left(p_error, 2000) where id = p_id;
    perform inf.emit_event('system.job_dead', 'job', p_id::text, jsonb_build_object('kind', v_job.kind, 'error', left(p_error, 500)), 'job_dead:' || p_id);
  else
    v_status := 'failed';
    update inf.jobs set status = 'failed', locked_at = null, last_error = left(p_error, 2000),
           run_at = now() + least(interval '6 hours', make_interval(mins => power(2, v_job.attempts - 1)::int))
     where id = p_id;
  end if;
  return v_status;
end $$;

-- Staff with system.read: retry a dead or failed job now.
create or replace function inf.job_retry(p_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('system.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.jobs set status = 'queued', run_at = now(), attempts = 0, max_attempts = greatest(max_attempts, 1), finished_at = null
   where id = p_id and status in ('dead', 'failed', 'cancelled');
  if found then perform inf.audit('job', p_id::text, 'retry'); end if;
  return found;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Notifications core (spec 14). In-app rows are the record; deliveries queue email and WhatsApp sends.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.notification_templates (
  id          uuid primary key default gen_random_uuid(),
  event       text not null check (event ~ '^[a-z_]+\.[a-z_.]+$'),
  channel     text not null check (channel in ('email', 'whatsapp', 'in_app')),
  locale      text not null default 'en' check (locale ~ '^[a-z]{2}$'),
  version     int not null default 1,
  subject     text,
  body        text not null,
  wa_template_name text,
  active      boolean not null default true,
  updated_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index notification_templates_active_uq on inf.notification_templates (event, channel, locale) where active;
create trigger notification_templates_touch before update on inf.notification_templates for each row execute function inf.touch_updated_at();
create trigger notification_templates_audit after insert or update or delete on inf.notification_templates
  for each row execute function inf.audit_row('notification_template');

create table inf.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  event       text not null,
  title       text not null check (char_length(title) <= 200),
  body        text check (char_length(body) <= 2000),
  link        text check (link is null or link ~ '^/[A-Za-z0-9/_\-?=&.%]*$'),
  data        jsonb not null default '{}'::jsonb,
  mandatory   boolean not null default false,
  idem_key    text not null unique,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on inf.notifications (user_id, created_at desc);
create index notifications_unread_idx on inf.notifications (user_id) where read_at is null;

create table inf.notification_deliveries (
  id               bigint generated always as identity primary key,
  notification_id  uuid not null references inf.notifications (id) on delete cascade,
  channel          text not null check (channel in ('email', 'whatsapp')),
  status           text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'skipped')),
  attempts         int not null default 0,
  provider         text,
  provider_ref     text,
  error            text,
  created_at       timestamptz not null default now(),
  sent_at          timestamptz,
  unique (notification_id, channel)
);
create index notification_deliveries_queue_idx on inf.notification_deliveries (status, created_at) where status = 'queued';

create table inf.notification_preferences (
  user_id   uuid not null references auth.users (id) on delete cascade,
  event     text not null,
  channel   text not null check (channel in ('email', 'whatsapp', 'in_app')),
  enabled   boolean not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, event, channel)
);

-- Internal: create an in-app notification and queue its email/WhatsApp deliveries (respecting preferences unless
-- mandatory). Idempotent on p_idem_key. Returns the notification id.
create or replace function inf.notify(p_user uuid, p_event text, p_title text, p_body text, p_link text, p_data jsonb,
                                      p_mandatory boolean, p_idem_key text, p_channels text[] default array['email'])
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_ch text;
begin
  insert into inf.notifications (user_id, event, title, body, link, data, mandatory, idem_key)
  values (p_user, p_event, left(p_title, 200), left(p_body, 2000), p_link, coalesce(p_data, '{}'::jsonb), coalesce(p_mandatory, false), p_idem_key)
  on conflict (idem_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from inf.notifications where idem_key = p_idem_key;
    return v_id;
  end if;
  foreach v_ch in array coalesce(p_channels, '{}') loop
    continue when v_ch not in ('email', 'whatsapp');
    if coalesce(p_mandatory, false) or coalesce((select np.enabled from inf.notification_preferences np
                                                 where np.user_id = p_user and np.event = p_event and np.channel = v_ch), true) then
      insert into inf.notification_deliveries (notification_id, channel) values (v_id, v_ch) on conflict do nothing;
    end if;
  end loop;
  if exists (select 1 from inf.notification_deliveries where notification_id = v_id and status = 'queued') then
    perform inf.job_enqueue('notify.deliver', jsonb_build_object('notification_id', v_id), now(), 'notify:' || v_id, 8);
  end if;
  return v_id;
end $$;

create or replace function inf.my_notifications(p_limit int default 30, p_before timestamptz default null)
returns table (id uuid, event text, title text, body text, link text, data jsonb, read_at timestamptz, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select n.id, n.event, n.title, n.body, n.link, n.data, n.read_at, n.created_at from inf.notifications n
   where n.user_id = auth.uid() and inf.session_ok() and (p_before is null or n.created_at < p_before)
   order by n.created_at desc limit least(greatest(p_limit, 1), 100);
$$;

create or replace function inf.notifications_mark_read(p_ids uuid[]) returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function inf.notification_preference_set(p_event text, p_channel text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_channel not in ('email', 'whatsapp', 'in_app') or p_event !~ '^[a-z_]+\.[a-z_.]+$' then
    raise exception 'invalid preference' using errcode = '22023';
  end if;
  insert into inf.notification_preferences (user_id, event, channel, enabled) values (auth.uid(), p_event, p_channel, p_enabled)
  on conflict (user_id, event, channel) do update set enabled = excluded.enabled, updated_at = now();
end $$;

-- service_role: delivery bookkeeping for the job runner.
create or replace function inf.delivery_result(p_id bigint, p_status text, p_provider text default null, p_ref text default null, p_error text default null)
returns void language sql security definer set search_path = '' as $$
  update inf.notification_deliveries
     set status = p_status, attempts = attempts + 1, provider = p_provider, provider_ref = left(p_ref, 200),
         error = left(p_error, 1000), sent_at = case when p_status = 'sent' then now() else sent_at end
   where id = p_id;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Rate limiting: fixed windows per key (sign-in, OTP, redirects, public API). Keys carry no personal data except a
-- network prefix; rows older than a day are pruned nightly.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.rate_hits (
  key           text not null check (char_length(key) <= 200),
  window_start  timestamptz not null,
  hits          int not null default 1,
  primary key (key, window_start)
);

create or replace function inf.rate_check(p_key text, p_limit int, p_seconds int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_window timestamptz; v_hits int;
begin
  if p_key is null or char_length(p_key) > 200 or p_limit < 1 or p_seconds not between 1 and 86400 then return false; end if;
  v_window := to_timestamp(floor(extract(epoch from now()) / p_seconds) * p_seconds);
  insert into inf.rate_hits (key, window_start) values (p_key, v_window)
  on conflict (key, window_start) do update set hits = inf.rate_hits.hits + 1
  returning hits into v_hits;
  return v_hits <= p_limit;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Platform terms and privacy notices (spec 16): versioned; creators re-accept on change.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.terms_versions (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('platform_terms', 'privacy', 'sign_consent', 'communications_consent')),
  version       int not null check (version >= 1),
  title         text not null,
  body          text not null,
  effective_at  timestamptz not null default now(),
  created_by    uuid,
  created_at    timestamptz not null default now(),
  unique (kind, version)
);
create trigger terms_versions_append_only before update or delete on inf.terms_versions
  for each row execute function inf.forbid_mutation();

create table inf.terms_acceptances (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  terms_version_id  uuid not null references inf.terms_versions (id),
  ip                inet,
  user_agent        text,
  accepted_at       timestamptz not null default now(),
  unique (user_id, terms_version_id)
);
create trigger terms_acceptances_append_only before update or delete on inf.terms_acceptances
  for each row execute function inf.forbid_mutation();

-- The current version of each kind that the user has not accepted yet.
create or replace function inf.terms_pending() returns table (id uuid, kind text, version int, title text, body text, effective_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.id, t.kind, t.version, t.title, t.body, t.effective_at
    from inf.terms_versions t
   where t.kind in ('platform_terms', 'privacy') and t.effective_at <= now()
     and t.version = (select max(t2.version) from inf.terms_versions t2 where t2.kind = t.kind and t2.effective_at <= now())
     and auth.uid() is not null
     and not exists (select 1 from inf.terms_acceptances a where a.user_id = auth.uid() and a.terms_version_id = t.id)
   order by t.kind;
$$;

create or replace function inf.terms_accept(p_terms_version_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from inf.terms_versions where id = p_terms_version_id and effective_at <= now()) then
    raise exception 'unknown terms version' using errcode = '22023';
  end if;
  insert into inf.terms_acceptances (user_id, terms_version_id, ip, user_agent)
  values (auth.uid(), p_terms_version_id, inf.request_ip(), inf.request_user_agent())
  on conflict do nothing;
end $$;

create or replace function inf.terms_publish(p_kind text, p_title text, p_body text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_ver int;
begin
  if not inf.has_perm('settings.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind not in ('platform_terms', 'privacy', 'sign_consent', 'communications_consent') then raise exception 'unknown kind' using errcode = '22023'; end if;
  if char_length(coalesce(p_title, '')) < 3 or char_length(coalesce(p_body, '')) < 20 then raise exception 'title and body are required' using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from inf.terms_versions where kind = p_kind;
  insert into inf.terms_versions (kind, version, title, body, created_by) values (p_kind, v_ver, p_title, p_body, auth.uid()) returning id into v_id;
  perform inf.audit('terms_version', v_id::text, 'publish', null, jsonb_build_object('kind', p_kind, 'version', v_ver));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- System status (spec 19: admin System status page; spec 18: /api/health)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.system_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (inf.has_perm('system.read') or auth.role() = 'service_role') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'db_time', now(),
    'jobs', jsonb_build_object(
      'queued', (select count(*) from inf.jobs where status = 'queued'),
      'due', (select count(*) from inf.jobs where status in ('queued', 'failed') and run_at <= now()),
      'running', (select count(*) from inf.jobs where status = 'running'),
      'failed', (select count(*) from inf.jobs where status = 'failed'),
      'dead', (select count(*) from inf.jobs where status = 'dead'),
      'oldest_due_seconds', (select extract(epoch from now() - min(run_at))::int from inf.jobs where status in ('queued', 'failed') and run_at <= now())),
    'deliveries', jsonb_build_object(
      'queued', (select count(*) from inf.notification_deliveries where status = 'queued'),
      'failed_24h', (select count(*) from inf.notification_deliveries where status = 'failed' and created_at > now() - interval '24 hours')),
    'cron', coalesce((select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active,
                         'last_status', r.status, 'last_run', r.start_time) order by j.jobname)
                        from cron.job j
                        left join lateral (select d.status, d.start_time from cron.job_run_details d where d.jobid = j.jobid
                                            order by d.start_time desc limit 1) r on true
                       where j.jobname like 'inf-%'), '[]'::jsonb));
end $$;

create or replace function inf.health() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('db', true,
    'queue_ok', coalesce((select extract(epoch from now() - min(run_at)) < 900 from inf.jobs
                           where status in ('queued', 'failed') and run_at <= now()), true));
$$;

create or replace function inf.jobs_recent(p_status text default null, p_limit int default 50)
returns table (id bigint, kind text, status text, attempts int, max_attempts int, run_at timestamptz, last_error text, created_at timestamptz, finished_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select j.id, j.kind, j.status, j.attempts, j.max_attempts, j.run_at, j.last_error, j.created_at, j.finished_at
    from inf.jobs j
   where inf.has_perm('system.read') and (p_status is null or j.status = p_status)
   order by j.id desc limit least(greatest(p_limit, 1), 200);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Storage buckets (SHARED_CHANGES S-4). Private buckets are reached through signed URLs created by the server;
-- object policies for creator uploads are added with the features that need them.
-- ---------------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('inf-contracts', 'inf-contracts', false, 26214400, array['application/pdf']),
  ('inf-kyc', 'inf-kyc', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('inf-deliverables', 'inf-deliverables', false, 2147483648, array['video/mp4', 'video/quicktime', 'video/webm', 'image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('inf-briefs', 'inf-briefs', false, 104857600, array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml', 'video/mp4', 'application/pdf', 'font/ttf', 'font/otf', 'font/woff2', 'application/zip']),
  ('inf-invoices', 'inf-invoices', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png']),
  ('inf-documents', 'inf-documents', false, 26214400, array['application/pdf', 'text/csv', 'image/jpeg', 'image/png']),
  ('inf-public-avatars', 'inf-public-avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.domain_events enable row level security;
alter table inf.jobs enable row level security;
alter table inf.notification_templates enable row level security;
alter table inf.notifications enable row level security;
alter table inf.notification_deliveries enable row level security;
alter table inf.notification_preferences enable row level security;
alter table inf.rate_hits enable row level security;
alter table inf.terms_versions enable row level security;
alter table inf.terms_acceptances enable row level security;

-- In-app notifications: only the recipient, only with a live session. Also the Realtime channel (RLS applies).
create policy notifications_own on inf.notifications for select to authenticated
  using (user_id = (select auth.uid()) and (select inf.session_ok()));
create policy notification_preferences_own on inf.notification_preferences for select to authenticated
  using (user_id = (select auth.uid()));
create policy notification_templates_staff on inf.notification_templates for select to authenticated
  using ((select inf.has_perm('notification_template.write')));
create policy terms_versions_read on inf.terms_versions for select to authenticated
  using ((select inf.is_staff()) or (select inf.current_creator_id()) is not null);
create policy terms_acceptances_own on inf.terms_acceptances for select to authenticated
  using (user_id = (select auth.uid()) or (select inf.has_perm('audit.read')));
create policy domain_events_audit on inf.domain_events for select to authenticated using ((select inf.has_perm('system.read')));
create policy jobs_system on inf.jobs for select to authenticated using ((select inf.has_perm('system.read')));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.notifications', 'authenticated', 'select'),
  ('table', 'inf.notification_preferences', 'authenticated', 'select'),
  ('table', 'inf.notification_templates', 'authenticated', 'select'),
  ('table', 'inf.terms_versions', 'authenticated', 'select'),
  ('table', 'inf.terms_acceptances', 'authenticated', 'select'),
  ('table', 'inf.domain_events', 'authenticated', 'select'),
  ('table', 'inf.jobs', 'authenticated', 'select'),
  ('function', 'inf.job_retry(bigint)', 'authenticated', 'execute'),
  ('function', 'inf.my_notifications(int, timestamptz)', 'authenticated', 'execute'),
  ('function', 'inf.notifications_mark_read(uuid[])', 'authenticated', 'execute'),
  ('function', 'inf.notification_preference_set(text, text, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.terms_pending()', 'authenticated', 'execute'),
  ('function', 'inf.terms_accept(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.terms_publish(text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.system_status()', 'authenticated', 'execute'),
  ('function', 'inf.jobs_recent(text, int)', 'authenticated', 'execute'),
  ('function', 'inf.rate_check(text, int, int)', 'authenticated', 'execute'),
  ('function', 'inf.health()', 'authenticated', 'execute'),
  ('function', 'inf.rate_check(text, int, int)', 'anon', 'execute'),
  ('function', 'inf.health()', 'anon', 'execute');

-- Realtime: in-app notifications (S-6). RLS above limits each subscriber to their own rows.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'inf' and tablename = 'notifications') then
    alter publication supabase_realtime add table inf.notifications;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Scheduler (S-3). The dispatcher calls the app's job runner over HTTPS with the internal key from Vault. Until the
-- app URL (setting-free: Vault secret `inf_app_base_url`) and key (`inf_internal_key`) exist, it does nothing.
-- ---------------------------------------------------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

create or replace function inf.cron_dispatch(p_path text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_base text; v_key text;
begin
  select decrypted_secret into v_base from vault.decrypted_secrets where name = 'inf_app_base_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'inf_internal_key';
  if v_base is null or v_key is null then return; end if;
  perform net.http_post(url := rtrim(v_base, '/') || p_path,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key),
                        body := '{}'::jsonb, timeout_milliseconds := 25000);
end $$;

-- Nightly housekeeping inside the database (no app needed).
create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('inf-jobs', '* * * * *', $c$select inf.cron_dispatch('/api/internal/jobs')$c$);
    perform cron.schedule('inf-nightly', '50 20 * * *', $c$select inf.nightly_prune()$c$);  -- 02:20 IST
  end if;
end $$;

call inf.apply_client_grants();
