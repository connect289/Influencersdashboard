-- PENDING (hand-applied in the Supabase SQL editor right after m31a_a3_schema): Addendum 3 immutability guards.
-- m31a installs b2b.append_only_guard() with UPDATE-only triggers on b2b.partner_bars (the permanent partner bar) and
-- b2b.lead_consents (the consent ledger). This file extends them to DELETE, and adds TRUNCATE statement triggers, as
-- m2c does for b2b.events (events_append_only / events_no_truncate). It is a pending file because the Supabase
-- connector refuses migrations that contain these words.
--   Staging and production: apply right after m31a_a3_schema (production: in the promotion window, before m31b).
--   Re-applying is safe: every trigger is created with CREATE OR REPLACE.
-- Erasure: with the GUC b2b.erasure = 'on' in the same transaction, an UPDATE of a partner_bars row may only change
-- phone_digits, providers and erased_at (null the digits and the providers' details, stamp erased_at); the bar itself
-- (lead, reason, date, allocation, set_by) is kept. Rows are never removed, not even by an erasure, and the consent
-- ledger never changes.

create or replace trigger partner_bars_append_only before update or delete on b2b.partner_bars
  for each row execute function b2b.append_only_guard();
create or replace trigger partner_bars_no_truncate before truncate on b2b.partner_bars
  for each statement execute function b2b.append_only_guard();

create or replace trigger lead_consents_append_only before update or delete on b2b.lead_consents
  for each row execute function b2b.append_only_guard();
create or replace trigger lead_consents_no_truncate before truncate on b2b.lead_consents
  for each statement execute function b2b.append_only_guard();

select b2b.log_event('migration.manual_applied', null, null, null, jsonb_build_object('file', 'pending/m31a_guards'));
