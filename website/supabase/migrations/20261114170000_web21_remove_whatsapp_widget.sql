-- =====================================================================================================================
-- web21 · The WhatsApp chat widget (AiSensy, web15 / D-091) is removed from the website (owner request, 14 Nov 2026;
-- docs/DECISIONS.md D-102). Its one setting goes with it. Idempotent.
-- Rollback: supabase/rollbacks/20261114170000_web21_remove_whatsapp_widget.rollback.sql (puts the setting back, hidden).
-- =====================================================================================================================
delete from public.web_settings_history where key = 'whatsapp_widget_id';
delete from public.web_settings where key = 'whatsapp_widget_id';
