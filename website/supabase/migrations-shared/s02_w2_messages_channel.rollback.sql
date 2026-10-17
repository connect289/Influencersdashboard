-- Rollback for s02. Only safe while no row has channel = 'web' (otherwise first copy those rows back to
-- web_advisor_messages, then delete them here). Readers updated to filter channel would need reverting first.
drop index if exists public.w2_messages_session_idx;
alter table public.w2_messages drop constraint if exists w2_messages_channel_chk;
alter table public.w2_messages drop column if exists session_id;
alter table public.w2_messages drop column if exists channel;
