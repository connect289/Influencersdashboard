-- Local test cluster only (supabase/local-test.sh). Stands in for the parts of Supabase the B2B CRM's migrations use:
-- the API roles, auth (users, sessions, uid/jwt/role from request.jwt.claims), storage.buckets, pg_cron, pg_net (requests
-- recorded, never sent), Vault (plain values) and pgmq (queues created, nothing else). Run as the cluster's bootstrap
-- superuser on a throwaway database. Never run against a Supabase project.

create role postgres login superuser;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role supabase_auth_admin nologin;
create role authenticator login noinherit;
grant anon, authenticated, service_role to authenticator;
grant usage on schema public to anon, authenticated, service_role;

create schema if not exists extensions;
grant usage on schema extensions to public;

-- pgvector: Witty's embedding columns only (the B2B CRM never reads them)
create domain public.vector as real[];

-- ---------- auth ----------
create schema auth;
grant usage on schema auth to anon, authenticated, service_role, supabase_auth_admin;
create table auth.users (
  id uuid primary key default gen_random_uuid(), instance_id uuid, aud text, role text, email text, encrypted_password text,
  email_confirmed_at timestamptz, phone text, last_sign_in_at timestamptz, raw_app_meta_data jsonb default '{}',
  raw_user_meta_data jsonb default '{}', banned_until timestamptz, deleted_at timestamptz, is_anonymous boolean default false,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table auth.sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid references auth.users (id) on delete cascade, created_at timestamptz default now(),
  updated_at timestamptz default now(), factor_id uuid, aal text, not_after timestamptz, refreshed_at timestamp, user_agent text, ip inet, tag text);
create table auth.mfa_factors (
  id uuid primary key default gen_random_uuid(), user_id uuid references auth.users (id) on delete cascade, friendly_name text,
  factor_type text, status text, created_at timestamptz default now(), updated_at timestamptz default now());
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text
$$;
create function auth.email() returns text language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')::text
$$;
grant execute on function auth.jwt(), auth.uid(), auth.role(), auth.email() to public;

-- ---------- storage ----------
create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (
  id text primary key, name text not null, owner uuid, public boolean default false, file_size_limit bigint, allowed_mime_types text[],
  created_at timestamptz default now(), updated_at timestamptz default now());
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id), name text, owner uuid, metadata jsonb,
  created_at timestamptz default now(), updated_at timestamptz default now());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;

-- ---------- pg_cron ----------
create schema cron;
grant usage on schema cron to postgres;
create table cron.job (
  jobid bigserial primary key, schedule text not null, command text not null, nodename text default 'localhost',
  nodeport int default 5432, database text default current_database(), username text default 'postgres', active boolean default true,
  jobname text unique);
create table cron.job_run_details (
  jobid bigint, runid bigserial primary key, job_pid int, database text, username text, command text, status text,
  return_message text, start_time timestamptz, end_time timestamptz);
create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid
$$;
create function cron.schedule(schedule text, command text) returns bigint language sql as $$
  insert into cron.job (schedule, command) values (schedule, command) returning jobid
$$;
create function cron.unschedule(job_id bigint) returns boolean language sql as $$ delete from cron.job where jobid = job_id returning true $$;
create function cron.unschedule(job_name text) returns boolean language sql as $$ delete from cron.job where jobname = job_name returning true $$;
create function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null,
                               username text default null, active boolean default null) returns void language sql as $$
  update cron.job set schedule = coalesce(alter_job.schedule, job.schedule), command = coalesce(alter_job.command, job.command),
         active = coalesce(alter_job.active, job.active) where jobid = job_id
$$;

-- ---------- pg_net: requests are recorded, never sent; a test writes net._http_response itself ----------
create schema net;
grant usage on schema net to public;
create table net.http_request_queue (id bigserial primary key, method text, url text, body bytea, params jsonb, headers jsonb, timeout_milliseconds int);
create table net._http_response (id bigint, status_code int, content_type text, headers jsonb, content text, timed_out boolean,
                                 error_msg text, created timestamptz default now());
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{"Content-Type": "application/json"}',
                              timeout_milliseconds int default 5000) returns bigint language sql as $$
  insert into net.http_request_queue (method, url, body, params, headers, timeout_milliseconds)
  values ('POST', url, convert_to(body::text, 'utf8'), params, headers, timeout_milliseconds) returning id
$$;
create function net.http_get(url text, params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
returns bigint language sql as $$
  insert into net.http_request_queue (method, url, params, headers, timeout_milliseconds) values ('GET', url, params, headers, timeout_milliseconds) returning id
$$;

-- ---------- Vault: names and plain values (no encryption locally) ----------
create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text, description text default '',
                            key_id uuid, nonce bytea, created_at timestamptz default now(), updated_at timestamptz default now());
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '', new_key_id uuid default null)
returns uuid language sql as $$
  insert into vault.secrets (name, secret, description) values (new_name, new_secret, new_description) returning id
$$;
create function vault.update_secret(secret_id uuid, new_secret text default null, new_name text default null, new_description text default null,
                                    new_key_id uuid default null) returns void language sql as $$
  update vault.secrets set secret = coalesce(new_secret, secret), name = coalesce(new_name, name),
         description = coalesce(new_description, description), updated_at = now() where id = secret_id
$$;
create view vault.decrypted_secrets as
  select id, name, description, secret, secret as decrypted_secret, key_id, nonce, created_at, updated_at from vault.secrets;

-- ---------- pgmq: queues can be created; nothing in the B2B CRM sends to them ----------
create schema pgmq;
create table pgmq.meta (queue_name text primary key, created_at timestamptz default now());
create function pgmq.create(queue_name text) returns void language sql as $$
  insert into pgmq.meta (queue_name) values (queue_name) on conflict do nothing
$$;
