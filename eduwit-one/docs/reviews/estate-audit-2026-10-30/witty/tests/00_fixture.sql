\set ON_ERROR_STOP 1
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname='eduwit_one_reader') then create role eduwit_one_reader nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='eduwit_one_fixer') then create role eduwit_one_fixer nologin noinherit; end if;
end $$;
grant usage on schema public to anon, authenticated, service_role, eduwit_one_reader, eduwit_one_fixer;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
create table w2_conversations (phone text not null primary key, conversation_id bigint, account_id bigint, state jsonb not null default '{}'::jsonb, classification text not null default 'UNQUALIFIED', readiness text not null default 'EXPLORING', eligibility text not null default 'INSUFFICIENT_DATA', pending_question text not null default 'NONE', bot_paused boolean not null default false, opted_out boolean not null default false, consent_at timestamptz, escalated_at timestamptz, lead_source text, activation_code text, crm_record_id text, version integer not null default 0, lock_id text, lock_until timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), access_code text, access_at timestamptz, attribution jsonb, last_student_at timestamptz, nurture_step integer not null default 0, nurture_next_at timestamptz);
create table w2_inbox (message_id text not null primary key, phone text not null, conversation_id bigint, account_id bigint, content text, content_type text, has_attachment boolean not null default false, labels jsonb, received_at timestamptz not null default now(), claimed_by text, processed_at timestamptz, referral jsonb);
create table w2_messages (id bigserial primary key, phone text not null, direction text not null, kind text not null default 'chat', message_id text, run_id text, content text, answer_mode text, reply_source text, model text, prompt_tokens integer, cached_tokens integer, output_tokens integer, latency_ms integer, verify_errors jsonb, sent boolean, meta jsonb, created_at timestamptz not null default now());
create unique index w2_messages_in_uidx on w2_messages (message_id) where direction = 'in';
create table w2_trusted (phone text not null primary key, note text, created_at timestamptz not null default now(), is_test boolean not null default false);
create table w2_gemini_caches (name text not null primary key, cache_name text, model text, prompt_hash text, prompt_text text, tokens integer, expire_at timestamptz, error text, updated_at timestamptz not null default now());
create table w2_prompts (name text not null primary key, version integer not null default 1, body text not null, updated_at timestamptz not null default now());
create table w2_learnings (id bigserial primary key, report_id bigint, kind text not null, title text, payload jsonb not null default '{}'::jsonb, rationale text, evidence jsonb, confidence numeric, status text not null default 'proposed', auto boolean not null default false, created_at timestamptz not null default now(), decided_at timestamptz, decided_by text);
create table w2_outbox (id bigserial primary key, phone text not null, target text not null default 'crm', event_type text not null, idempotency_key text not null unique, payload jsonb not null, status text not null default 'pending', attempts integer not null default 0, next_attempt_at timestamptz not null default now(), locked_by text, last_error text, crm_record_id text, created_at timestamptz not null default now(), sent_at timestamptz);
create table w2_events (id bigserial primary key, phone text, type text not null, run_id text, payload jsonb, created_at timestamptz not null default now());
create table w2_messages_backup_20261004 as select * from w2_messages;
create table catalog_programs (id bigserial primary key, active boolean not null default true, course_key text, course text, specialization text, mode text, level text);
create function crm_role() returns text language sql stable as $$ select null::text $$;
alter table catalog_programs enable row level security;
create policy crm_staff_select on catalog_programs for select to authenticated using (crm_role() is not null);
do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname like 'w2\_%' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
grant select on all tables in schema public to eduwit_one_reader;
