-- Local test cluster only (scripts/db/local-test.sh). Reproduces the parts of Supabase that schema one depends on:
-- a non-superuser postgres that owns the apps, the API roles, and cron / net / vault owned by an admin role.
-- Run as the cluster's bootstrap superuser (supabase_admin). Never run against a Supabase project.

create role postgres login createrole bypassrls;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
alter database rehearsal owner to postgres;
grant usage on schema public to anon, authenticated, service_role;

create extension if not exists pgcrypto;

-- pg_cron: tables owned by the admin, postgres may read them with grant option (as measured on production).
create schema cron;
grant usage on schema cron to postgres with grant option;
create table cron.job (
  jobid bigserial primary key, schedule text not null, command text not null, nodename text default 'localhost',
  nodeport int default 5432, database text default 'rehearsal', username text default 'postgres', active boolean default true,
  jobname text unique);
create table cron.job_run_details (
  jobid bigint, runid bigserial primary key, job_pid int, database text, username text, command text, status text,
  return_message text, start_time timestamptz, end_time timestamptz);
grant select on cron.job, cron.job_run_details to postgres with grant option;
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint
language sql security definer as $$
  insert into cron.job (jobname, schedule, command) values (p_name, p_schedule, p_command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid
$$;
create function cron.unschedule(p_jobid bigint) returns boolean language sql security definer as $$
  delete from cron.job where jobid = p_jobid returning true
$$;
grant execute on function cron.schedule(text, text, text), cron.unschedule(bigint) to postgres;

-- pg_net: requests are recorded, never sent.
create schema net;
grant usage on schema net to postgres, public;
create table net.http_request_queue (id bigserial primary key, url text, body jsonb, headers jsonb, timeout_milliseconds int);
create table net._http_response (id bigint, status_code int, content_type text, headers jsonb, content text, timed_out boolean, error_msg text, created timestamptz default now());
grant all on net.http_request_queue, net._http_response to public;
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
returns bigint language sql security definer as $$
  insert into net.http_request_queue (url, body, headers, timeout_milliseconds) values (url, body, headers, timeout_milliseconds) returning id
$$;
grant execute on function net.http_post(text, jsonb, jsonb, jsonb, int) to postgres;

-- Vault: names and plain values (the local cluster has no encryption).
create schema vault;
grant usage on schema vault to postgres;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text);
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;
grant select on vault.secrets, vault.decrypted_secrets to postgres;
