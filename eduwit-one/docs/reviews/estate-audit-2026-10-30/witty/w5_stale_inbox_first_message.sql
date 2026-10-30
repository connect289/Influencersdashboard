-- w5_stale_inbox_first_message (proposed 30 Oct 2026, Witty audit; not applied)
--
-- What: w2_stale_inbox also returns unprocessed messages whose phone has no w2_conversations row yet (LEFT JOIN).
-- Why: that row is created by w2_try_claim at the start of a turn. When a turn failed before that step, the minute job
-- ("Find Stuck Chats") and the stale_inbox health alert never saw the message, so the student was not answered.
-- Phones that have a row are filtered exactly as before. Signature, language, volatility, default and grants are
-- unchanged (CREATE OR REPLACE keeps the ACL). Idempotent.

create or replace function public.w2_stale_inbox(p_older_than_seconds integer default 40)
 returns table(phone text)
 language sql
 stable
as $function$
select distinct i.phone
from w2_inbox i left join w2_conversations c on c.phone = i.phone
where i.processed_at is null
and i.received_at < now() - make_interval(secs => p_older_than_seconds)
and (c.phone is null or ((c.lock_until is null or c.lock_until < now()) and not c.opted_out))
limit 50;
$function$;

-- rollback (the definition live on production on 30 Oct 2026):
-- create or replace function public.w2_stale_inbox(p_older_than_seconds integer default 40)
--  returns table(phone text)
--  language sql
--  stable
-- as $function$
-- select distinct i.phone
-- from w2_inbox i join w2_conversations c on c.phone = i.phone
-- where i.processed_at is null
-- and i.received_at < now() - make_interval(secs => p_older_than_seconds)
-- and (c.lock_until is null or c.lock_until < now())
-- and not c.opted_out
-- limit 50;
-- $function$;
