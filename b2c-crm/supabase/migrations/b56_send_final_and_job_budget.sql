-- B2C CRM b56 (13 Nov 2026): the every-minute job gives each of its jobs its own deadline, and a message Meta refuses
-- for good is failed at once. Staging first. Idempotent.
--
-- 1. One deadline per job. The app's every-minute call (/api/internal/sync) ran all its jobs one after another inside
--    the platform's 60 seconds, so a slow job early in the list left the later ones cut off part-way. The app now gives
--    each job its own deadline (web/lib/job-budget.ts): a job with no time left is not started, and a job that runs out
--    of time between two items stops there. What it had taken but not started must go back as it was, with no attempt
--    spent: b2c.job_release(kind, ids) does that for every queue the job takes from (messages already have
--    b2c.send_release, b53):
--      outbox        back to queued, the attempt not counted (an update whose lead has a newer queued update stays for
--                    b2c.outbox_unstick, as the lead may have only one queued update)
--      erase_files, wa_media, support_mail, recordings, calendar
--                    the attempt not counted
--      exports       back to queued, the attempt not counted
--      push, alert_emails
--                    marked as not sent again (only what was taken in the last 10 minutes)
--      schedules     due again now (only a schedule not sent in the last 10 minutes)
--      briefs        to be tried on the next run, not in 30 minutes
--    Each kind changes only rows still in the state the take left them in, so a row the job did finish is never reopened.
-- 2. A message Meta clearly refuses is final. No database change: b2c.send_done already fails a result that carries
--    "retry": false and never queues it again (b55), and keeps its error on the message, the queue row and the admins'
--    notice. The app now sends "retry": false, with the reason in words and Meta's code, for the refusals that cannot
--    succeed on a second try (the number is not on WhatsApp, the template is not approved or paused, the 24-hour window
--    has closed, the person stopped marketing messages); rate limits and a refused token are tried again as before
--    (web/lib/whatsapp.ts, classifyWaError).
--
-- Rollback: drop function if exists b2c.job_release(text, bigint[]); (deploy the app's previous version first: the new
-- one calls it when a job runs out of time).

-- ---------- 1. work a job took but did not start goes back as it was ----------
create or replace function b2c.job_release(p_kind text, p_ids bigint[]) returns integer
language plpgsql security definer set search_path = '' as $f$
declare
  v_ids constant bigint[] := coalesce(p_ids, '{}'::bigint[]);
  n integer := 0;
begin
  case p_kind
    when 'outbox' then
      update b2c.outbox o set status = 'queued', attempts = greatest(o.attempts - 1, 0)
       where o.id = any (v_ids) and o.status = 'sending'
         and not (o.kind = 'update' and exists (select 1 from b2c.outbox q where q.lead_id = o.lead_id and q.kind = 'update' and q.status = 'queued' and q.urgent = o.urgent));
    when 'erase_files' then
      update b2c.erase_files set attempts = attempts - 1 where id = any (v_ids) and removed_at is null and attempts > 0;
    when 'exports' then
      update b2c.exports set status = 'queued', attempts = greatest(attempts - 1, 0) where id = any (v_ids) and status = 'running';
    when 'wa_media' then
      update b2c.wa_messages set media_tries = media_tries - 1 where id = any (v_ids) and direction = 'in' and media_path is null and media_tries > 0;
    when 'push' then
      update b2c.notifications set pushed_at = null where id = any (v_ids) and pushed_at > now() - interval '10 minutes';
    when 'support_mail' then
      update b2c.support_messages set mail_attempts = mail_attempts - 1 where id = any (v_ids) and to_developer and mailed_at is null and mail_attempts > 0;
    when 'recordings' then
      update b2c.calls set recording_attempts = recording_attempts - 1 where id = any (v_ids) and recording_status = 'pending' and recording_attempts > 0;
    when 'calendar' then
      update b2c.calendar_events set attempts = attempts - 1 where task_id = any (v_ids) and state = 'pending' and attempts > 0;
    when 'alert_emails' then
      update b2c.alert_events set emailed_at = null where id = any (v_ids) and email and emailed_at > now() - interval '10 minutes';
    when 'schedules' then
      update b2c.dashboard_schedules set next_at = now()
       where id = any (v_ids) and active and next_at > now() and (last_sent_at is null or last_sent_at < now() - interval '10 minutes');
    when 'briefs' then
      update b2c.lead_briefs set attempted_at = null where lead_id = any (v_ids) and attempted_at > now() - interval '10 minutes';
    else
      raise exception 'job_release: unknown kind %', p_kind using errcode = '22023';
  end case;
  get diagnostics n = row_count;
  return n;
end $f$;

-- ---------- grants ----------
-- The new function is the service role's (the app's machine endpoint). No existing function is redefined.
revoke execute on function b2c.job_release(text, bigint[]) from public, anon, authenticated;
grant execute on function b2c.job_release(text, bigint[]) to service_role;

-- last: nothing in b2c is executable by PUBLIC or anon
revoke execute on all functions in schema b2c from public, anon;
