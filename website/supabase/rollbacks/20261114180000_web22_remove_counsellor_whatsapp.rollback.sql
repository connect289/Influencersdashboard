-- Rollback of web22: the setting returns with its original default. The links that used it were removed in code.
insert into public.web_settings (key, value, description) values
  ('counsellor_whatsapp', '"+919643977407"', 'WhatsApp number for "Talk to a counsellor" (D-016, S-42).')
on conflict (key) do nothing;
