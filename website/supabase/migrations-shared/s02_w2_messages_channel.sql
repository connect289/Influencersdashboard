-- =====================================================================================================================
-- s02 · w2_messages: channel and session columns (APPROVALS_NEEDED A-AGENT-2 + A-AGENT-3 — must ship together)
-- SHARED OBJECT. Dev / replica only until the owner approves. Rollback: s02_w2_messages_channel.rollback.sql.
--
-- What this file does: adds two columns, a check and an index. Existing rows become channel 'whatsapp' (metadata-only
-- default, no table rewrite on Postgres 11+). Every existing writer (Witty's inbound mirror, reply writer, nurture
-- mirror) keeps working unchanged and keeps writing 'whatsapp' by default.
--
-- What it does NOT do: change any reader. Before the website writes a single 'web' row here, every reader that means
-- "WhatsApp" must filter channel = 'whatsapp' — otherwise the CRMs would see an open WhatsApp 24-hour window for a
-- website chat and could send free-form WhatsApp messages outside Meta's window. Those readers belong to other
-- products and are handed off, not changed here (APPROVALS_NEEDED A-AGENT-2 lists them):
--   crm_whatsapp_window__impl, b2b.student_last_inbound, b2b.reenquiry_scan, b2c.may_market, b2c.witty_busy,
--   crm_marketing_allowed, w2_health_digest  (filter channel = 'whatsapp')
--   b2c.witty_transcript, b2c.witty_messages, b2b.lead_detail, crm_timeline__impl  (show the channel)
-- Until every reader is updated and released, the website writes only to web_advisor_messages (it has no code path
-- that writes w2_messages). web_advisor_messages has exactly these columns, so its rows can be copied across
-- unchanged afterwards (insert … select, ids not reused), and the website's writer switched in a later release.
-- =====================================================================================================================
alter table public.w2_messages add column if not exists channel text not null default 'whatsapp';
alter table public.w2_messages add column if not exists session_id text;
alter table public.w2_messages drop constraint if exists w2_messages_channel_chk;
alter table public.w2_messages add constraint w2_messages_channel_chk check (channel in ('whatsapp', 'web')) not valid;
alter table public.w2_messages validate constraint w2_messages_channel_chk;
create index if not exists w2_messages_session_idx on public.w2_messages (session_id, created_at) where session_id is not null;
comment on column public.w2_messages.channel is 'whatsapp (Witty via Chatwoot) or web (eduwit.in, web_advisor). Readers that mean WhatsApp must filter channel = ''whatsapp''.';
comment on column public.w2_messages.session_id is 'Website chat session (web_advisor_sessions.id) for channel web; null for WhatsApp.';
