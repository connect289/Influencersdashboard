-- M2 (approved 6 Oct 2026): foundations of the B2B CRM, applied as five parts (m2a…m2e) because the
-- Supabase connector holds large or destructive-looking migrations for manual confirmation.
--   * extensions pgmq (job queues) and pg_cron (timers)
--   * schema b2b, the Admin allowlist and sign-in log, versioned settings, the append-only event log,
--     API keys, the integration outbox and live switches
--   * one index on student_leads so lead_intake()'s phone lookup stays fast at volume
-- Nothing here changes Witty's tables or functions. Idempotent where Postgres allows it.

-- ---------- extensions ----------
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pgmq;

-- ---------- schema ----------
create schema if not exists b2b;
comment on schema b2b is 'Eduwit B2B Partner CRM. See b2b-crm/ and docs/b2b-design.md in connect289/Influencersdashboard.';
revoke all on schema b2b from public, anon;
grant usage on schema b2b to authenticated, service_role;
alter default privileges in schema b2b revoke all on tables from public, anon, authenticated;
alter default privileges in schema b2b revoke execute on functions from public, anon, authenticated;
alter default privileges in schema b2b grant all on tables to service_role;
alter default privileges in schema b2b grant all on sequences to service_role;
alter default privileges in schema b2b grant execute on functions to service_role;
