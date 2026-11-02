-- Rollback of web15: removes the WhatsApp widget setting (the site then hides the widget).
delete from public.web_settings_history where key = 'whatsapp_widget_id';
delete from public.web_settings where key = 'whatsapp_widget_id';
