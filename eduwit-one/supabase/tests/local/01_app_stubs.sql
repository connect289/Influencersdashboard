-- Local test cluster only. Minimal stand-ins for the app objects schema one reads, owned by postgres as on
-- production. Deliberately absent, to prove source_missing handling: schema inf, schema catalog, web_funnel_events,
-- web_audit_log, web_advisor_sessions, b2b.allocation_transitions, b2b.partner_events, b2c.activities, b2c.audit_log.
-- Run as postgres.

create schema b2b;
create schema b2c;

create function public.crm_norm_phone(p text) returns text language sql immutable as $$ select regexp_replace(p, '\D', '', 'g') $$;

create table public.student_leads (id bigserial primary key, whatsapp_number text, student_name text, email_id text,
  is_sales_ready boolean default false, allocation_id bigint, is_test boolean default false, created_at timestamptz default now());
create function public.lead_intake(p jsonb) returns jsonb language sql as $$ select '{"ok":true}'::jsonb $$;

create table public.w2_events (id bigserial primary key, phone text, type text, run_id text, payload jsonb, created_at timestamptz default now());
create table public.w2_messages (id bigserial primary key, phone text, direction text, kind text, content text, reply_source text,
  model text, prompt_tokens int, output_tokens int, latency_ms int, verify_errors jsonb, created_at timestamptz default now());
create table public.w2_outbox (id bigserial primary key, phone text, target text, event_type text, payload jsonb, status text,
  attempts int default 0, last_error text, crm_record_id text, created_at timestamptz default now(), sent_at timestamptz);
create table public.touchpoints (id bigserial primary key, lead_id bigint, phone text, source_system text, event_type text,
  payload jsonb, occurred_at timestamptz default now());
create table public.web_settings (key text primary key, value jsonb);
insert into public.web_settings values ('internal_base_url', '"https://eduwit-website.vercel.app"');

create table b2b.events (id bigserial primary key, occurred_at timestamptz default now(), type text, lead_id bigint,
  allocation_id bigint, partner_id bigint, actor_type text, actor_id text, payload jsonb);
create table b2b.allocations (id bigserial primary key, lead_id bigint, status text);
create table b2c.events (id bigserial primary key, at timestamptz default now(), type text, lead_id bigint, actor_type text, actor_id uuid, payload jsonb);
create table b2c.settings (key text primary key, value jsonb);
insert into b2c.settings values ('app', '{"base_url": null}');

-- Health RPCs, controllable from tests through a stub table.
create table public.stub_health (app text primary key, value jsonb);
insert into public.stub_health values ('witty', '[]'), ('b2b', '{"ok": true}'), ('web', '{"db": true, "outbox_dead": 0, "catalog_checked_seconds_ago": 30, "outbox_oldest_pending_seconds": 0}');
-- Like production (D-042): invoker rights, no search_path, unqualified table name.
create function public.w2_health_alerts() returns jsonb language sql stable as $$ select value from stub_health where app = 'witty' $$;
create function b2b.health_check() returns jsonb language sql security definer as $$ select value from public.stub_health where app = 'b2b' $$;
create function public.web_health() returns jsonb language sql security definer as $$ select value from public.stub_health where app = 'web' $$;
revoke execute on function b2b.health_check(), public.web_health() from public;

-- A pre-existing anon-executable SECURITY DEFINER function, as the apps have many.
create function public.legacy_anon_rpc() returns int language sql security definer as $$ select 1 $$;
grant execute on function public.legacy_anon_rpc() to anon;

-- Witty conversations, for one.witty_escalations() (0008).
create table public.w2_conversations (phone text primary key, conversation_id bigint, account_id bigint, bot_paused boolean default false,
  escalated_at timestamptz, crm_record_id text);
