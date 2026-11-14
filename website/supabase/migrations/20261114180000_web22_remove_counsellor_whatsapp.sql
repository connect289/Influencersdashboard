-- =====================================================================================================================
-- web22 · No WhatsApp route on the website (owner request, 14 Nov 2026; docs/DECISIONS.md D-103): the site has Witty,
-- the enquiry form, phone and email. The setting that held the counsellor's WhatsApp number goes. Idempotent.
-- Rollback: supabase/rollbacks/20261114180000_web22_remove_counsellor_whatsapp.rollback.sql.
-- =====================================================================================================================
delete from public.web_settings_history where key = 'counsellor_whatsapp';
delete from public.web_settings where key = 'counsellor_whatsapp';
