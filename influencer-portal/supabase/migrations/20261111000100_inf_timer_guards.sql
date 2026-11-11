-- Running cost, 11 Nov 2026: the two minute timers stop calling the app for nothing (schema inf only).
-- inf-jobs and inf-lead-sync keep their schedule (every minute, `select inf.cron_dispatch('<path>')`); the dispatcher
-- now asks inf.cron_dispatch_due() first and returns before the Vault reads when the app would have nothing to do.
-- 1. /api/internal/jobs: called only when a job is claimable, by inf.job_claim's own predicate without the kind filter,
--    looking 5 seconds ahead for jobs that fall due between this check and the runner's claim.
-- 2. /api/internal/lead-sync: called every minute while a real sweep recorded its watermark in the last 24 hours
--    (inf.sync_state 'lead_sync' is written only by inf.lead_sync_apply for the every-minute sweep, which runs only with
--    LEAD_SYNC=on); otherwise only on minutes 0, 15, 30 and 45. The database cannot see LEAD_SYNC, so there is no second
--    flag: after it is switched on the first sweep starts within 15 minutes and the minute cadence resumes by itself.
-- Any other path is dispatched as before. Signature, security, search_path, grants and the 25 s timeout are unchanged.
-- Idempotent (create or replace). Inverse statements: see the rollback block at the end.

-- Internal: has the timer for p_path a reason to call the app at p_at? No client grant.
create or replace function inf.cron_dispatch_due(p_path text, p_at timestamptz) returns boolean
language sql stable set search_path = '' as $$
  select case p_path
    when '/api/internal/jobs' then
      -- inf.job_claim: due (queued or failed) or stuck in "running" for 10 minutes. One exists() per index
      -- (jobs_due_idx, jobs_status_idx) so each stops at the first row.
      exists (select 1 from inf.jobs j
               where j.status in ('queued', 'failed') and j.run_at <= p_at + interval '5 seconds')
      or exists (select 1 from inf.jobs j
                  where j.status = 'running' and j.locked_at < p_at - interval '10 minutes' + interval '5 seconds')
    when '/api/internal/lead-sync' then
      extract(minute from p_at at time zone 'UTC')::int % 15 = 0
      or exists (select 1 from inf.sync_state s
                  where s.key = 'lead_sync' and s.updated_at > p_at - interval '24 hours')
    else true
  end
$$;

create or replace function inf.cron_dispatch(p_path text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_base text; v_key text;
begin
  if not inf.cron_dispatch_due(p_path, now()) then return; end if;
  select decrypted_secret into v_base from vault.decrypted_secrets where name = 'inf_app_base_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'inf_internal_key';
  if v_base is null or v_key is null then return; end if;
  perform net.http_post(url := rtrim(v_base, '/') || p_path,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key),
                        body := '{}'::jsonb, timeout_milliseconds := 25000);
end $$;

call inf.apply_client_grants();

-- ---------------------------------------------------------------------------------------------------------------
-- Rollback (inverse statements; the dispatcher as it stood in 20261017000600_inf_ops.sql)
-- ---------------------------------------------------------------------------------------------------------------
-- create or replace function inf.cron_dispatch(p_path text) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare v_base text; v_key text;
-- begin
--   select decrypted_secret into v_base from vault.decrypted_secrets where name = 'inf_app_base_url';
--   select decrypted_secret into v_key from vault.decrypted_secrets where name = 'inf_internal_key';
--   if v_base is null or v_key is null then return; end if;
--   perform net.http_post(url := rtrim(v_base, '/') || p_path,
--                         headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key),
--                         body := '{}'::jsonb, timeout_milliseconds := 25000);
-- end $$;
-- drop function if exists inf.cron_dispatch_due(text, timestamptz);
-- call inf.apply_client_grants();
