-- Rollback of web21: the setting returns, hidden (null). The widget's code was removed with it and must be restored too.
insert into public.web_settings (key, value, description) values
  ('whatsapp_widget_id', 'null'::jsonb,
   'AiSensy WhatsApp chat widget id shown on the public pages; null hides the widget.')
on conflict (key) do nothing;
