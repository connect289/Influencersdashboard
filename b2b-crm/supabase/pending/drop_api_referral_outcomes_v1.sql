-- Pending (manual run, after m34d and after the web app that calls b2b.api_referral_outcomes_v2 is deployed): drops the
-- first referral API function, which m34d kept only for a web deploy older than it (its first page answers through v2).
-- Check first that nothing else calls it:
--   select n.nspname, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where p.prosrc ~ 'api_referral_outcomes\(' and p.proname <> 'api_referral_outcomes';
-- Rollback: re-run the create or replace function b2b.api_referral_outcomes of m34d_referral_outcomes_scoped.sql and its grant.
drop function if exists b2b.api_referral_outcomes(text, text, bigint, integer);
