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

-- Witty's trusted numbers (a test number is is_test), left out of Eduwit One's metrics (0012).
create table public.w2_trusted (phone text primary key, note text, is_test boolean default true);

-- Witty conversations, for one.witty_escalations() (0008).
create table public.w2_conversations (phone text primary key, conversation_id bigint, account_id bigint, bot_paused boolean default false,
  escalated_at timestamptz, crm_record_id text);

-- The app functions the fixes call (0019), with production's signatures and rights: SECURITY DEFINER, owned by
-- postgres, executable by the service role only (b2b.outbox_retry also by authenticated, and only for a B2B admin).
-- They exist before the migrations so that 0019 grants them to the fixer as it would on production; the tables they
-- touch are created by 99_fixes.sql for its run. Each records its call in public.stub_calls.
create function b2b.is_admin() returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  return exists (select 1 from b2b.app_users u
                  where u.user_id = nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
                    and u.is_active and u.role = 'admin');
end $$;
create function b2b.outbox_retry(p_id bigint) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.integration_outbox set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null where id = p_id and status in ('dead', 'failed');
  if not found then raise exception 'only a failed or dead delivery can be sent again' using errcode = '22023'; end if;
  insert into public.stub_calls (fn, arg) values ('b2b.outbox_retry', to_jsonb(p_id));
end $$;
create function b2b.outbox_kick() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn) values ('b2b.outbox_kick');
  return '{"answers": 0, "sent": 0}';
end $$;
create function b2b.b2c_sync_tick(p_limit integer) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn, arg) values ('b2b.b2c_sync_tick', to_jsonb(p_limit));
  return jsonb_build_object('scanned', 0, 'changed', 0);
end $$;
create function b2c.inbox_retry(p_limit integer) returns integer language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn, arg) values ('b2c.inbox_retry', to_jsonb(p_limit));
  return 0;
end $$;
create function b2c.outbox_unstick() returns integer language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn) values ('b2c.outbox_unstick');
  return 0;
end $$;
create function b2c.job_call(p_path text) returns bigint language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn, arg) values ('b2c.job_call', to_jsonb(p_path));
  return null;
end $$;
create function b2c.programme_cache_refresh(p_force boolean) returns integer language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn, arg) values ('b2c.programme_cache_refresh', to_jsonb(p_force));
  return 0;
end $$;
create function public.web_outbox_retry(p_id bigint, p_actor uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.web_outbox set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null where id = p_id and status = 'dead';
  insert into public.stub_calls (fn, arg) values ('public.web_outbox_retry', to_jsonb(p_id));
end $$;
create function public.web_job_call(p_path text, p_timeout_ms integer) returns bigint language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn, arg) values ('public.web_job_call', to_jsonb(p_path));
  return null;
end $$;
create function public.web_catalog_poll() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stub_calls (fn) values ('public.web_catalog_poll');
  return '{"changed": false}';
end $$;
revoke execute on function b2b.is_admin(), b2b.outbox_retry(bigint), b2b.outbox_kick(), b2b.b2c_sync_tick(integer), b2c.inbox_retry(integer),
  b2c.outbox_unstick(), b2c.job_call(text), b2c.programme_cache_refresh(boolean), public.web_outbox_retry(bigint, uuid),
  public.web_job_call(text, integer), public.web_catalog_poll() from public;
grant execute on function b2b.outbox_kick(), b2b.b2c_sync_tick(integer), b2c.inbox_retry(integer), b2c.outbox_unstick(),
  b2c.programme_cache_refresh(boolean), public.web_outbox_retry(bigint, uuid), public.web_job_call(text, integer), public.web_catalog_poll()
  to service_role;
grant execute on function b2b.is_admin(), b2b.outbox_retry(bigint) to authenticated, service_role;
