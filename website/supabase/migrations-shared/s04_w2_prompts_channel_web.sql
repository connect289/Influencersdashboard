-- =====================================================================================================================
-- s04 · w2_prompts row `channel_web` (APPROVALS_NEEDED A-AGENT-4). SHARED DATA. Dev / replica only until approved.
-- One row, versioned like the others; Witty reads only the prompts it names (extractor, counselor), so it ignores this
-- row. The website then reads the web formatting overlay from w2_prompts instead of web_settings. The body below is the
-- overlay as stored in web_settings.web_advisor_channel_overlay (version 1).
-- Rollback: s04_w2_prompts_channel_web.rollback.sql. Affects: nothing else (no reader of other names).
-- =====================================================================================================================
insert into public.w2_prompts (name, version, body)
values ('channel_web', 1, $t$CHANNEL: website chat (not WhatsApp). The student is on eduwit.in. Keep every HARD RULE. You may use short markdown bullets ("- ") instead of "•" and **bold** at most once. Programme rows you list with {{Pn.*}} placeholders are also shown as cards under your reply, so keep each bullet to one line. Never ask for the student's name, email or phone: the website already has them. Instead of "reply STOP", say they can stop any time and manage their data in their account.$t$)
on conflict (name) do nothing;
