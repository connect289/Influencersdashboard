-- =====================================================================================================================
-- s07 · Let website leads route without an OTP-verified phone (APPROVALS_NEEDED A-B2B-1, 🔴 blocking for go-live).
-- SHARED SETTING (b2b.settings key `engine`, field `require_verified_phone_sources`). Preferred route: the B2B admin
-- makes this change in the CRM (Settings → Routing → engine). This file is the same change through the CRM's own
-- versioned, audited writer (b2b.set_setting), for the dry run and for the owner if they prefer SQL.
-- Effect: website leads (lead_source website_agent/web_agent, a web_session_id, or a web_agent touchpoint) are no longer
-- held as `phone_not_verified`; every other routing rule is unchanged. Rollback: s07_b2b_routing_web_leads.rollback.sql
-- (puts the two sources back; takes effect on the next routing sweep). Affects: B2B CRM routing.
-- =====================================================================================================================
select b2b.set_setting(
  'engine',
  coalesce((select value from b2b.settings where key = 'engine'), '{}'::jsonb) || jsonb_build_object('require_verified_phone_sources', '[]'::jsonb),
  'A-B2B-1: website leads are email-verified (no phone OTP at launch, spec 7.2); approved by the owner on <date>'
);
