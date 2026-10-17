-- Rollback for s04. The website falls back to the overlay in web_settings.
delete from public.w2_prompts where name = 'channel_web';
