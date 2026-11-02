-- =====================================================================================================================
-- web15 · WhatsApp chat widget (AiSensy) on the public pages (owner request, 2 Nov 2026; docs/DECISIONS.md D-091).
-- One setting, editable in Admin → Flags and settings: the AiSensy widget id, or null to hide the widget.
-- Idempotent. Rollback: supabase/rollbacks/20261102100000_web15_whatsapp_widget.rollback.sql.
-- =====================================================================================================================
insert into public.web_settings (key, value, description) values
  ('whatsapp_widget_id', '"aabsod"'::jsonb,
   'AiSensy WhatsApp chat widget id shown on the public pages (from the AiSensy widget snippet, widget-id="…"); null hides the widget.')
on conflict (key) do nothing;
