-- Local test database only: the minimum of Supabase's objects the b2c migrations use. Never run against a Supabase project.
do $r$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $r$;
create schema extensions; create extension pgcrypto schema extensions;
create schema auth;
create table auth.users (id uuid primary key, email text, aud text, role text);
create schema vault;
create table vault.secrets_store (name text primary key, decrypted_secret text);
create view vault.decrypted_secrets as select name, decrypted_secret from vault.secrets_store;
create schema cron;
create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as $$ insert into cron.job (jobname, schedule, command) values (n, s, c) returning jobid $$;
create schema net;
create table net.calls (id bigserial primary key, url text, body jsonb, headers jsonb);
create function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int) returns bigint language sql as $$ insert into net.calls (url, body, headers) values (url, body, headers) returning id $$;
create table public.w2_messages (id bigserial primary key, phone text, direction text, kind text, content text, created_at timestamptz default now(), sent boolean, meta jsonb);
create table public.catalog_universities (id bigint primary key, name text, short_name text, institution_type text, recognitions text[], accreditation_text text, updated_at timestamptz);
create table public.catalog_programs (id bigint primary key, university_id bigint, level text, level_raw text, course text, course_key text, dual boolean, specialization text,
  program_name text, mode text, fee_yearly numeric, fee_semester numeric, fee_total numeric, fee_exam numeric, fee_registration numeric, fee_other jsonb,
  min_qualification text, min_pct_general numeric, min_pct_reserved numeric, eligibility_text text, brochure_url text, source_row int, flags text[], active boolean,
  updated_at timestamptz, program_key text, search_doc tsvector, source_file text);

insert into public.catalog_universities (id, name, short_name) values (1, 'Amity University Online', 'Amity'), (2, 'Jain Online', 'Jain');
insert into public.catalog_programs (id, university_id, level, course, specialization, program_name, mode, fee_total, active) values
  (11, 1, 'PG', 'MBA', 'Marketing', 'Online MBA', 'Online', 179000, true),
  (12, 2, 'PG', 'MBA', 'Finance', 'Online MBA', 'Online', 160000, true),
  (13, 2, 'UG', 'BBA', null, 'Online BBA', 'Online', 120000, true);

-- storage (Supabase Storage's bucket table, for b10)
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text not null, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);

-- the B2B CRM's partner tables (read-only for B2C; shapes as on staging), for b20's partner rates
create schema if not exists b2b;
create table if not exists b2b.partners (id bigint primary key, slug text, name text, display_name text, status text);
create table if not exists b2b.partner_programmes (id bigserial primary key, partner_id bigint references b2b.partners (id), programme_id bigint, commission jsonb not null default '{}',
  active boolean not null default true, valid_from timestamptz, valid_to timestamptz);
create table if not exists b2b.rates (id bigserial primary key, scope text, partner_id bigint, programme_id bigint, university_id bigint, rate_type text, fee_base text,
  value numeric, tiers jsonb, gst_inclusive boolean default false, valid_from date, valid_to date, source text default 'manual');
