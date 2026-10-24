-- 0019 the auto-fixes (spec §8, phase 7). Every fix is a function one.fix_<id>(incident, dry_run) over one engine:
--
--   one.fix_run()       the safety shell every fix goes through: the switch in one.settings.fixes (off, or the
--                       observation window running, means a dry run that only records what it would do), at most one
--                       run per fix per cooldown, the rate limit (more rows than per_tick: nothing is done and a
--                       proposal is opened), test rows left out, an action row before and after;
--   one.fix_plan()      what a fix would touch, read with Eduwit One's own rights as the checks read (ids and counts,
--                       never a phone or a name);
--   one.fix_act()       the act itself, only through the one.fixer_* functions below;
--   one.fixer_*()       owned by eduwit_one_fixer and SECURITY DEFINER, so every write a fix makes runs with the
--                       fixer's rights: USAGE on the app schemas and EXECUTE on the catalogue's app functions, granted
--                       here and nothing else (no table privilege, no RLS bypass: D-030);
--   one.fixes_step()    the minute tick's fix step: starts the observation window, verifies what ran, then runs each
--                       fix on each open incident of its checks;
--   one.fix_verify_due() a fix that ran is verified 2 minutes later: if its check fails again within the cooldown while
--                       its condition still holds, the incident goes up one severity level instead of a retry;
--   one.app_fixes_claim(), one.app_fix_report()   the app's side of its two fixes (n8n retries; the Spark reachability
--                       check before a kick), service role;
--   one.proposal_execute()   an approved fix proposal, run under the owner's session (spec §8 "Everything else is a
--                       proposal"), verified at check_due_at.
--
-- Three catalogue fixes cannot act from Eduwit One without changing an app (D-079): FIX-OUTBOX-W2 and FIX-CACHE-W2
-- open a proposal describing the change Witty would need; FIX-OUTBOX-B2B opens a proposal whose approval runs B2B's own
-- admin function under the owner's session. Everything ships switched off (seed) and dry-run for the window.
-- App tables are read from PL/pgSQL bodies, so a missing one fails that fix, not this migration; each grant to the
-- fixer is made only when its function exists (staging lacks some apps: D-009).

-- The catalogue ------------------------------------------------------------------------------------------------------

create table one.fixes (
  id text primary key check (id ~ '^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$'),
  app text not null references one.apps (key),
  title text not null,
  -- Checks whose open incident the fix is tried on; fix_plan() decides whether it applies to that incident.
  checks text[] not null,
  trigger text not null,
  -- act: in the database with the fixer's rights; app: the app makes an external call (n8n, a reachability check);
  -- approve: opens a proposal whose approval runs the app's own function under the owner's session; propose: cannot
  -- act from Eduwit One, opens a proposal describing the app change needed.
  mode text not null check (mode in ('act', 'app', 'approve', 'propose')),
  what text not null,
  grants text not null,
  rollback text not null,
  -- The app functions the fix calls (regprocedure text): the Fixes page shows whether each exists and is granted.
  app_functions text[] not null default '{}',
  -- After a failed verification, never again on that incident (FIX-CURSOR-B2C: "open P1 and stop").
  stop_after_failed boolean not null default false,
  created_at timestamptz not null default now()
);

insert into one.fixes (id, app, title, checks, trigger, mode, what, grants, rollback, app_functions, stop_after_failed) values
  ('FIX-OUTBOX-W2', 'witty', 'Send failed Witty outbox rows to the CRM again', '{WITTY-01}',
   'WITTY-01 names outbox_failed',
   'propose',
   'Lists Witty outbox rows in failed with fewer than 8 attempts and no permanent error (INVALID_DATA, MANDATORY_NOT_FOUND, DUPLICATE_DATA), test phones left out, and opens a proposal. It cannot send them itself: Witty has no function that sends a failed row again (public.w2_outbox_retry takes a limit, picks only pending rows and runs lead_intake() with its caller''s rights), and w2_outbox admits only its owner and the service role (D-079).',
   'none: it cannot act', 'none: nothing in Witty changes', '{}', false),
  ('FIX-CACHE-W2', 'witty', 'Renew Witty''s expired prompt caches', '{WITTY-01}',
   'WITTY-01 names cache_expired',
   'propose',
   'Lists Witty''s expired prompt caches (names only) and opens a proposal. The n8n API cannot start Witty''s Cache Manager: it has only schedule triggers (every 10 and 15 minutes, which renew the caches themselves) and a sub-workflow trigger (D-079).',
   'none: it cannot act', 'none: nothing in Witty changes', '{}', false),
  ('FIX-N8N-RETRY', 'witty', 'Retry a failed execution of the Witty workflow', '{WITTY-02}',
   'WITTY-02 lists executions in error or crashed (failed_15m)',
   'app',
   'The app retries each failed execution of the Witty workflow once through the n8n API (POST /api/v1/executions/{id}/retry), never the same execution twice. Witty is idempotent by message_id.',
   'the n8n API key (Setup item n8n_api); nothing in the database', 'none needed', '{}', false),
  ('FIX-OUTBOX-B2B', 'b2b', 'Send dead or failed B2B deliveries to Spark again', '{B2B-01}',
   'B2B-01 counts dead deliveries or deliveries waiting over an hour',
   'approve',
   'Lists dead and failed deliveries of the last 7 days (test payloads left out) and opens a proposal; the owner''s approval runs B2B''s own b2b.outbox_retry(id) for each, under the owner''s session and with the fixer''s rights. B2B lets only an admin send a delivery again, and the outbox''s row security admits no other role, so the fixer could not change a row itself (D-079).',
   'EXECUTE on b2b.outbox_retry(bigint), used only under the owner''s session (B2B checks that the caller is an admin)',
   'an admin sets the rows back to dead in the B2B CRM', '{b2b.outbox_retry(bigint)}', false),
  ('FIX-CURSOR-B2C', 'b2b', 'Run the B2B to Spark sync once', '{B2B-01}',
   'B2B-01 reports the B2C sync cursor over 600 s and the job b2b-b2c-sync-tick did not fail on its last run',
   'act',
   'select b2b.b2c_sync_tick(200) once. If B2B-01 still fails 2 minutes later, the incident is alerted again and this fix stops for it.',
   'EXECUTE on b2b.b2c_sync_tick(integer)', 'none needed', '{b2b.b2c_sync_tick(integer)}', true),
  ('FIX-WEBHOOK-REKICK', 'b2b', 'Kick the B2B outbox once Spark answers', '{B2B-06}',
   'B2B-06 fails',
   'app',
   'The app checks that <hosts.spark>/v1/handoffs answers (HEAD, then GET; any status below 500 within 10 s). If it does, select b2b.outbox_kick() runs with the fixer''s rights; if not, nothing is done and the P1 stays.',
   'EXECUTE on b2b.outbox_kick()', 'none needed', '{b2b.outbox_kick()}', false),
  ('FIX-INBOX-RETRY', 'b2c', 'Apply Spark''s stuck inbox rows again', '{B2C-02}',
   'B2C-02 fails',
   'act', 'select b2c.inbox_retry(50).', 'EXECUTE on b2c.inbox_retry(integer)', 'none needed', '{b2c.inbox_retry(integer)}', false),
  ('FIX-OUTBOX-B2C', 'b2c', 'Unstick Spark''s outbox and run its urgent sync', '{B2C-03}',
   'B2C-03 fails',
   'act', 'select b2c.outbox_unstick(), then b2c.job_call(''/api/internal/sync?mode=urgent'').',
   'EXECUTE on b2c.outbox_unstick() and b2c.job_call(text)', 'none needed', array['b2c.outbox_unstick()', 'b2c.job_call(text)'], false),
  ('FIX-OUTBOX-WEB', 'web', 'Send the website''s dead outbox rows again and run its worker', '{WEB-01}',
   'WEB-01 reports dead outbox rows or the oldest pending row over 900 s',
   'act',
   'public.web_outbox_retry(id, null) for each dead row with attempts below max_attempts (test payloads left out), then public.web_job_call(''/api/internal/outbox'', 55000).',
   'EXECUTE on public.web_outbox_retry(bigint, uuid) and public.web_job_call(text, integer)', 'none needed',
   array['public.web_outbox_retry(bigint,uuid)', 'public.web_job_call(text,integer)'], false),
  ('FIX-CATALOG-POLL', 'web', 'Run the website''s catalogue poll', '{WEB-01,CAT-02}',
   'WEB-01 reports the catalogue poll older than 600 s, or CAT-02 fails',
   'act', 'select public.web_catalog_poll().', 'EXECUTE on public.web_catalog_poll()', 'none needed', '{public.web_catalog_poll()}', false),
  ('FIX-CACHE-B2C', 'b2c', 'Refresh Spark''s programme cache', '{CAT-01}',
   'CAT-01 fails',
   'act', 'select b2c.programme_cache_refresh(true).', 'EXECUTE on b2c.programme_cache_refresh(boolean)', 'none needed',
   '{b2c.programme_cache_refresh(boolean)}', false);

-- An action row's place in a run: dry_run (what it would do), before and after (a real act), skip (nothing done, and
-- why), verify (whether it held). run_key ties the rows of one run together.
alter table one.actions add column step text not null default 'after' check (step in ('dry_run', 'before', 'after', 'skip', 'verify'));
alter table one.actions add column run_key text;
alter table one.actions add column verify_at timestamptz;
alter table one.actions add column claimed_at timestamptz;
alter table one.actions add column claimed_by text;
alter table one.actions add column proposal_id bigint references one.proposals (id);
create index actions_fix_time_idx on one.actions (fix_id, ran_at desc);
create index actions_run_idx on one.actions (run_key);
create index actions_verify_idx on one.actions (verify_at) where step = 'after' and verify_at is not null;

-- The fixer's rights ------------------------------------------------------------------------------------------------

-- Each grant is made only when its object exists (staging lacks some apps: D-009); the Fixes page shows a missing one.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'public') then
    grant usage on schema public to eduwit_one_fixer;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'b2b') then
    grant usage on schema b2b to eduwit_one_fixer;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'b2c') then
    grant usage on schema b2c to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2b.b2c_sync_tick(integer)') is not null then
    grant execute on function b2b.b2c_sync_tick(integer) to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2b.outbox_kick()') is not null then
    grant execute on function b2b.outbox_kick() to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2b.outbox_retry(bigint)') is not null then
    grant execute on function b2b.outbox_retry(bigint) to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.inbox_retry(integer)') is not null then
    grant execute on function b2c.inbox_retry(integer) to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.outbox_unstick()') is not null then
    grant execute on function b2c.outbox_unstick() to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.job_call(text)') is not null then
    grant execute on function b2c.job_call(text) to eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.programme_cache_refresh(boolean)') is not null then
    grant execute on function b2c.programme_cache_refresh(boolean) to eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_outbox_retry(bigint,uuid)') is not null then
    grant execute on function public.web_outbox_retry(bigint, uuid) to eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_job_call(text,integer)') is not null then
    grant execute on function public.web_job_call(text, integer) to eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_catalog_poll()') is not null then
    grant execute on function public.web_catalog_poll() to eduwit_one_fixer;
  end if;
end $$;

-- The fixer's functions: each calls exactly the app functions its fix needs, nothing else. They are created here, then
-- handed to eduwit_one_fixer, which needs CREATE on schema one only for that hand-over (revoked below, in the same
-- transaction) and the migrating user's membership to give it (Postgres 16+). EXECUTE stays with the owner, so only
-- Eduwit One's own functions reach them.

create or replace function one.fixer_b2c_sync() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return b2b.b2c_sync_tick(200);
end $$;

create or replace function one.fixer_outbox_kick() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return b2b.outbox_kick();
end $$;

-- B2B's own admin action; B2B checks that the caller's session is an admin's, so this works only inside an approval.
create or replace function one.fixer_b2b_outbox_retry(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform b2b.outbox_retry(p_id);
end $$;

create or replace function one.fixer_inbox_retry() returns integer
language plpgsql security definer set search_path = '' as $$
begin
  return b2c.inbox_retry(50);
end $$;

create or replace function one.fixer_b2c_outbox() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer;
  v_request bigint;
begin
  v_n := b2c.outbox_unstick();
  v_request := b2c.job_call('/api/internal/sync?mode=urgent');
  return jsonb_build_object('unstuck', v_n, 'sync_request', v_request);
end $$;

create or replace function one.fixer_web_outbox(p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_n integer := 0;
  v_request bigint;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'at most 500 rows in one run' using errcode = '22023';
  end if;
  foreach v_id in array coalesce(p_ids, '{}') loop
    perform public.web_outbox_retry(v_id, null);
    v_n := v_n + 1;
  end loop;
  v_request := public.web_job_call('/api/internal/outbox', 55000);
  return jsonb_build_object('retried', v_n, 'worker_request', v_request);
end $$;

create or replace function one.fixer_catalog_poll() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return public.web_catalog_poll();
end $$;

create or replace function one.fixer_programme_cache() returns integer
language plpgsql security definer set search_path = '' as $$
begin
  return b2c.programme_cache_refresh(true);
end $$;

grant eduwit_one_fixer to current_user;
grant create on schema one to eduwit_one_fixer;
alter function one.fixer_b2c_sync() owner to eduwit_one_fixer;
alter function one.fixer_outbox_kick() owner to eduwit_one_fixer;
alter function one.fixer_b2b_outbox_retry(bigint) owner to eduwit_one_fixer;
alter function one.fixer_inbox_retry() owner to eduwit_one_fixer;
alter function one.fixer_b2c_outbox() owner to eduwit_one_fixer;
alter function one.fixer_web_outbox(bigint[]) owner to eduwit_one_fixer;
alter function one.fixer_catalog_poll() owner to eduwit_one_fixer;
alter function one.fixer_programme_cache() owner to eduwit_one_fixer;
revoke create on schema one from eduwit_one_fixer;

-- Helpers -----------------------------------------------------------------------------------------------------------

-- The observation window: running until observation_started_at + observation_days; not started counts as running.
create or replace function one.fix_window() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
           'started_at', s.started, 'days', s.days,
           'until', s.started + make_interval(days => s.days),
           'running', s.started is null or now() < s.started + make_interval(days => s.days))
    from (select (coalesce(one.setting('fixes'), '{}') ->> 'observation_started_at')::timestamptz as started,
                 coalesce((one.setting('fixes') ->> 'observation_days')::int, 14) as days) s
$$;

-- Whether each app function a fix calls exists and is granted to the fixer, and the fixer's own functions are its.
create or replace function one.fix_grants(p_fix text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
           'ok', coalesce(bool_and(x.ok), true),
           'missing', coalesce(jsonb_agg(x.fn) filter (where not x.ok), '[]'))
    from (select fn, to_regprocedure(fn) is not null and has_function_privilege('eduwit_one_fixer', to_regprocedure(fn), 'EXECUTE') as ok
            from one.fixes f, unnest(f.app_functions) fn where f.id = p_fix) x
$$;

-- One severity level up (P3 to P2, P2 to P1); a P1 is routed again so a person hears that the fix did not hold.
create or replace function one.incident_escalate(p_incident_id bigint, p_why text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_from one.severity;
  v_to one.severity;
begin
  select severity into v_from from one.incidents where id = p_incident_id and resolved_at is null for update;
  if not found then
    return jsonb_build_object('escalated', false, 'why', 'resolved');
  end if;
  v_to := case v_from when 'P3' then 'P2' else 'P1' end;
  update one.incidents
     set severity = v_to, acknowledged_at = null, acknowledged_by = null,
         tags = array(select distinct t from unnest(tags || array['fix_failed']) t)
   where id = p_incident_id;
  perform one.route_incident(p_incident_id);
  return jsonb_build_object('escalated', true, 'from', v_from, 'to', v_to, 'why', left(p_why, 200));
end $$;

-- One row of a fix's history.
create or replace function one.fix_record(p_fix text, p_incident bigint, p_step text, p_status text, p_dry_run boolean, p_target jsonb,
                                          p_result jsonb, p_by text, p_run_key text, p_verify_at timestamptz default null,
                                          p_proposal bigint default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into one.actions (fix_id, incident_id, app, target, dry_run, status, result, ran_by, step, run_key, verify_at, proposal_id)
  select p_fix, p_incident, f.app, coalesce(p_target, '{}'), p_dry_run, p_status, coalesce(p_result, '{}'), left(coalesce(p_by, 'one'), 120),
         p_step, p_run_key, p_verify_at, p_proposal
    from one.fixes f where f.id = p_fix
  returning id into v_id;
  return v_id;
end $$;

-- The plan ----------------------------------------------------------------------------------------------------------

-- What a fix would touch on this incident: {applies, why_not, would, rows (ids, at most 500), count, test_rows,
-- target}. Read with Eduwit One's own rights, as the checks read the same tables; ids and counts only.
create or replace function one.fix_plan(p_fix text, p_inc one.incidents) returns jsonb
language plpgsql set search_path = '' as $$
declare
  e jsonb := coalesce(p_inc.evidence, '{}');
  v_rows jsonb := '[]';
  v_n integer := 0;
  v_test integer := 0;
  v_status text;
  v_url text;
  v_old boolean;
begin
  if not exists (select 1 from one.fixes f where f.id = p_fix and p_inc.check_id = any (f.checks)) then
    return jsonb_build_object('applies', false, 'why_not', 'not one of this fix''s checks');
  end if;
  case p_fix
    when 'FIX-OUTBOX-W2' then
      if not 'outbox_failed' = any (p_inc.subjects) then
        return jsonb_build_object('applies', false, 'why_not', 'WITTY-01 does not name outbox_failed');
      end if;
      -- A test phone as Witty's own w2_is_test() decides (910000 and six digits, or a trusted test phone).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     (coalesce(o.phone, '') similar to '910000[0-9]{6}'
                      or exists (select 1 from public.w2_trusted t where t.phone = o.phone and t.is_test)) as t
                from public.w2_outbox o
               where o.status = 'failed' and o.attempts < 8
                 and coalesce(o.last_error, '') !~ '(INVALID_DATA|MANDATORY_NOT_FOUND|DUPLICATE_DATA)') x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no failed row with a retryable error' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test,
                                'would', 'open a proposal to Witty: these rows cannot be sent again from Eduwit One');
    when 'FIX-CACHE-W2' then
      if not 'cache_expired' = any (p_inc.subjects) then
        return jsonb_build_object('applies', false, 'why_not', 'WITTY-01 does not name cache_expired');
      end if;
      select coalesce(jsonb_agg(c.name order by c.name), '[]'), count(*) into v_rows, v_n
        from public.w2_gemini_caches c where c.expire_at < now();
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no cache has expired' end,
                                'count', v_n, 'target', jsonb_build_object('caches', v_rows),
                                'would', 'open a proposal: the n8n API cannot start Witty''s Cache Manager');
    when 'FIX-N8N-RETRY' then
      -- Each execution once: one retried before (a real run's before row) is left out.
      select coalesce(jsonb_agg(x.id order by x.id) filter (where x.n <= 500), '[]'), count(*) into v_rows, v_n
        from (select x.id, row_number() over (order by x.id) as n
                from jsonb_array_elements_text(coalesce(e -> 'failed_15m', '[]')) as x(id)
               where not exists (select 1 from one.actions a where a.fix_id = 'FIX-N8N-RETRY' and a.step = 'before' and not a.dry_run
                                    and coalesce(a.target -> 'rows', '[]') ? x.id)) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no failed execution that was not retried already' end,
                                'rows', v_rows, 'count', v_n,
                                'target', jsonb_build_object('workflow_id', one.setting('n8n') ->> 'witty_workflow_id'),
                                'would', 'retry each execution once through the n8n API');
    when 'FIX-OUTBOX-B2B' then
      if coalesce((e #>> '{deliveries,dead_7d}')::int, 0) + coalesce((e #>> '{deliveries,waiting_over_1h}')::int, 0) = 0 then
        return jsonb_build_object('applies', false, 'why_not', 'B2B-01 reports no dead or waiting delivery');
      end if;
      -- A test lead's handoff carries test true at the top of its payload or in its data (as Spark reads it).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     coalesce(o.payload @> '{"test": true}' or o.payload -> 'data' @> '{"test": true}', false) as t
                from b2b.integration_outbox o
               where o.status in ('dead', 'failed') and o.created_at > now() - interval '7 days' and o.endpoint_id is not null) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no dead or failed delivery of the last 7 days' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test,
                                'would', 'open a proposal; approving it runs b2b.outbox_retry(id) for each under the owner''s session');
    when 'FIX-CURSOR-B2C' then
      if coalesce((e #>> '{b2c_sync,cursor_age_seconds}')::numeric, 0) <= 600 then
        return jsonb_build_object('applies', false, 'why_not', 'the B2C sync cursor is not over 600 s');
      end if;
      select d.status into v_status from cron.job_run_details d join cron.job j on j.jobid = d.jobid
       where j.jobname = 'b2b-b2c-sync-tick' order by d.runid desc limit 1;
      if v_status = 'failed' then
        return jsonb_build_object('applies', false, 'why_not', 'b2b-b2c-sync-tick failed on its last run: a person looks first');
      end if;
      return jsonb_build_object('applies', true, 'count', 1,
                                'target', jsonb_build_object('cursor_age_seconds', e #> '{b2c_sync,cursor_age_seconds}', 'job_last_status', v_status),
                                'would', 'run b2b.b2c_sync_tick(200) once');
    when 'FIX-WEBHOOK-REKICK' then
      v_url := rtrim(one.setting('hosts') ->> 'spark', '/') || '/v1/handoffs';
      if v_url is null then
        return jsonb_build_object('applies', false, 'why_not', 'hosts.spark is not set');
      end if;
      return jsonb_build_object('applies', true, 'count', 1,
                                'target', jsonb_build_object('url', v_url,
                                          'endpoints', (select coalesce(jsonb_agg(x -> 'id'), '[]') from jsonb_array_elements(coalesce(e -> 'endpoints', '[]')) x)),
                                'would', 'check that ' || v_url || ' answers, then run b2b.outbox_kick()');
    when 'FIX-INBOX-RETRY' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('error', e -> 'error', 'stuck', e -> 'stuck'),
                                'would', 'run b2c.inbox_retry(50)');
    when 'FIX-OUTBOX-B2C' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('count', e -> 'count', 'by_status', e -> 'by_status'),
                                'would', 'run b2c.outbox_unstick(), then b2c.job_call(''/api/internal/sync?mode=urgent'')');
    when 'FIX-OUTBOX-WEB' then
      v_old := coalesce((e ->> 'outbox_oldest_pending_seconds')::numeric, 0) > 900;
      if coalesce((e ->> 'outbox_dead')::int, 0) = 0 and not v_old then
        return jsonb_build_object('applies', false, 'why_not', 'WEB-01 reports no dead row and no old pending row');
      end if;
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     coalesce(o.payload @> '{"is_test": true}' or o.payload @> '{"test": true}', false) as t
                from public.web_outbox o where o.status = 'dead' and o.attempts < o.max_attempts) x;
      return jsonb_build_object('applies', v_n > 0 or v_old,
                                'why_not', case when v_n = 0 and not v_old then 'every dead row has used its attempts: a person decides' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test, 'target', jsonb_build_object('oldest_pending_old', v_old),
                                'would', format('send %s dead rows again (public.web_outbox_retry), then run the website''s outbox worker', v_n));
    when 'FIX-CATALOG-POLL' then
      if p_inc.check_id = 'WEB-01' and coalesce((e ->> 'catalog_checked_seconds_ago')::numeric, 0) <= 600 then
        return jsonb_build_object('applies', false, 'why_not', 'the catalogue poll is not older than 600 s');
      end if;
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('check', p_inc.check_id),
                                'would', 'run public.web_catalog_poll()');
    when 'FIX-CACHE-B2C' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', e, 'would', 'run b2c.programme_cache_refresh(true)');
    else
      raise exception 'no fix %', p_fix using errcode = 'P0002';
  end case;
end $$;

-- The plan narrowed to rows an approval named: what still qualifies now.
create or replace function one.fix_plan_within(p_plan jsonb, p_rows jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_rows is null or jsonb_typeof(p_plan -> 'rows') <> 'array' then p_plan
         else p_plan || jsonb_build_object('rows', r.rows, 'count', jsonb_array_length(r.rows), 'applies', jsonb_array_length(r.rows) > 0)
         end
    from (select coalesce(jsonb_agg(x order by x::text), '[]') as rows from jsonb_array_elements(coalesce(p_plan -> 'rows', '[]')) x
           where coalesce(p_rows, '[]') @> jsonb_build_array(x)) r
$$;

-- The act: only through the fixer's functions, so it runs with the fixer's rights.
create or replace function one.fix_act(p_fix text, p_plan jsonb) returns jsonb
language plpgsql set search_path = '' as $$
begin
  case p_fix
    when 'FIX-CURSOR-B2C' then return jsonb_build_object('sync', one.fixer_b2c_sync());
    when 'FIX-WEBHOOK-REKICK' then return jsonb_build_object('kick', one.fixer_outbox_kick());
    when 'FIX-INBOX-RETRY' then return jsonb_build_object('applied', one.fixer_inbox_retry());
    when 'FIX-OUTBOX-B2C' then return one.fixer_b2c_outbox();
    when 'FIX-OUTBOX-WEB' then
      return one.fixer_web_outbox(array(select x::bigint from jsonb_array_elements_text(coalesce(p_plan -> 'rows', '[]')) x));
    when 'FIX-CATALOG-POLL' then return jsonb_build_object('poll', one.fixer_catalog_poll());
    when 'FIX-CACHE-B2C' then return jsonb_build_object('refreshed', one.fixer_programme_cache());
    else raise exception '% does not act in the database', p_fix using errcode = '22023';
  end case;
end $$;

-- A fix's proposal: one open proposal per fix and incident, refreshed while it waits (source check, owner's decision).
create or replace function one.fix_propose(p_fix one.fixes, p_inc one.incidents, p_plan jsonb, p_why text) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
  v_title text;
  v_rationale text;
  v_change jsonb;
  v_n integer := coalesce((p_plan ->> 'count')::int, 0);
  v_limit integer := coalesce((one.setting('fixes') -> p_fix.id ->> 'per_tick')::int, 1);
begin
  if p_why = 'over_limit' then
    v_title := format('%s: %s rows is over its limit of %s', p_fix.id, v_n, v_limit);
    v_rationale := format('%s would touch %s rows on incident %s (%s), more than its rate limit of %s a run, so it did nothing (spec §8). Approving runs it once on the rows listed, those that still qualify then, with the fixer''s rights.',
                          p_fix.id, v_n, p_inc.id, p_inc.check_id, v_limit);
  elsif p_fix.id = 'FIX-OUTBOX-B2B' then
    v_title := format('B2B: send %s dead or failed deliveries to Spark again', v_n);
    v_rationale := 'B2B lets only an admin send a delivery again (b2b.outbox_retry), and its outbox admits no other role, so FIX-OUTBOX-B2B cannot act on its own (D-079). Approving runs b2b.outbox_retry for each listed delivery that is still dead or failed, under your session: B2B refuses unless you are a B2B admin. Ten minutes later Eduwit One checks which were delivered.';
  elsif p_fix.id = 'FIX-OUTBOX-W2' then
    v_title := format('Witty: %s failed outbox rows cannot be sent again from Eduwit One', v_n);
    v_rationale := 'Witty has no function that sends a failed outbox row again: public.w2_outbox_retry(p_limit) picks only pending rows and runs lead_intake() with its caller''s rights, and w2_outbox admits only its owner and the service role. Witty''s maintainer could add a SECURITY DEFINER public.w2_outbox_requeue(p_id bigint) that sets a failed row with a retryable error back to pending, and grant EXECUTE on it to eduwit_one_fixer; FIX-OUTBOX-W2 would then use it (D-079). Approving records your decision; nothing runs.';
  elsif p_fix.id = 'FIX-CACHE-W2' then
    v_title := format('Witty: %s prompt caches expired and were not renewed', v_n);
    v_rationale := 'Witty renews its prompt caches itself every 10 and 15 minutes; caches still expired mean that renewal is failing (Gemini, or the workflow). The n8n API cannot start the Cache Manager, which has only schedule and sub-workflow triggers, so FIX-CACHE-W2 cannot act. Look at the Witty workflow''s recent executions in n8n. A webhook trigger on the Cache Manager would let Eduwit One start it (D-079). Approving records your decision; nothing runs.';
  else
    v_title := format('%s on incident %s', p_fix.id, p_inc.id);
    v_rationale := p_fix.what;
  end if;
  v_change := jsonb_build_object('fix', p_fix.id, 'incident', p_inc.id, 'rows', coalesce(p_plan -> 'rows', '[]'), 'target', p_plan -> 'target');
  if p_why = 'over_limit' or p_fix.mode = 'approve' then
    v_change := v_change || jsonb_build_object('execute', jsonb_build_object('fix', p_fix.id, 'incident', p_inc.id, 'rows', coalesce(p_plan -> 'rows', '[]')));
  end if;
  select id into v_id from one.proposals
   where source = 'check' and source_key like format('fix:%s:%s:%%', p_fix.id, p_inc.id) and status in ('open', 'snoozed')
   order by id desc limit 1 for update;
  if found then
    update one.proposals set title = left(v_title, 200), rationale = v_rationale, change = v_change,
                             evidence = jsonb_build_object('plan', p_plan, 'incident_evidence', p_inc.evidence)
     where id = v_id;
    return v_id;
  end if;
  insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key, incident_id, expires_at)
  values ('fix', p_fix.app, left(v_title, 200), v_rationale, jsonb_build_object('plan', p_plan, 'incident_evidence', p_inc.evidence), v_change,
          case when p_why = 'over_limit' then 'high' else 'medium' end, 'check',
          format('fix:%s:%s:%s', p_fix.id, p_inc.id, floor(extract(epoch from clock_timestamp()) * 1000)::bigint), p_inc.id,
          now() + make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14)))
  returning id into v_id;
  return v_id;
end $$;

-- The safety shell ----------------------------------------------------------------------------------------------------

-- One fix on one incident (spec §8). p_dry_run true only records; false acts when the fix is switched on and the
-- observation window has ended. p_by is 'one' for the minute tick (the only runs the cooldown counts), else who ran
-- it. p_approval is the approved proposal this run carries out: the owner's consent for one run on the rows it named.
create or replace function one.fix_run(p_fix text, p_incident bigint, p_dry_run boolean default true, p_by text default 'one',
                                       p_approval bigint default null, p_rows jsonb default null) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_f one.fixes;
  v_cfg jsonb;
  v_inc one.incidents;
  v_plan jsonb;
  v_dry boolean;
  v_limit integer;
  v_cool integer;
  v_key text;
  v_target jsonb;
  v_res jsonb;
  v_status text;
  v_prop bigint;
  v_id bigint;
begin
  select * into v_f from one.fixes where id = p_fix;
  if not found then
    raise exception 'no fix %', p_fix using errcode = 'P0002';
  end if;
  v_cfg := coalesce(one.setting('fixes') -> p_fix, '{}');
  v_limit := coalesce((v_cfg ->> 'per_tick')::int, 1);
  v_cool := coalesce((v_cfg ->> 'cooldown_min')::int, 60);
  select * into v_inc from one.incidents where id = p_incident;
  if not found then
    raise exception 'no incident %', p_incident using errcode = 'P0002';
  end if;
  if v_inc.resolved_at is not null and p_approval is null then
    return jsonb_build_object('fix', p_fix, 'skipped', 'the incident is resolved');
  end if;
  v_dry := p_approval is null
           and (p_dry_run or not coalesce((v_cfg ->> 'enabled')::boolean, false) or (one.fix_window() ->> 'running')::boolean);
  -- At most once per cooldown: the tick's own runs count, whatever the incident (a person's dry run does not).
  if p_by = 'one' and exists (select 1 from one.actions a where a.fix_id = p_fix and a.ran_by = 'one' and a.step <> 'verify'
                                 and a.ran_at > now() - make_interval(mins => v_cool)) then
    return jsonb_build_object('fix', p_fix, 'skipped', 'cooldown');
  end if;
  if v_f.stop_after_failed and p_approval is null
     and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.step = 'verify' and a.status = 'failed') then
    return jsonb_build_object('fix', p_fix, 'skipped', 'stopped: it did not hold on this incident');
  end if;
  v_plan := one.fix_plan(p_fix, v_inc);
  if p_approval is not null then
    v_plan := one.fix_plan_within(v_plan, p_rows);
  end if;
  if not coalesce((v_plan ->> 'applies')::boolean, false) then
    return jsonb_build_object('fix', p_fix, 'applies', false, 'why_not', v_plan ->> 'why_not');
  end if;
  v_key := format('%s:%s:%s', p_fix, p_incident, to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
  v_target := coalesce(v_plan -> 'target', '{}') || jsonb_build_object('rows', coalesce(v_plan -> 'rows', '[]'), 'count', v_plan -> 'count',
                                                                         'test_rows_left_out', coalesce(v_plan -> 'test_rows', '0'));
  -- More rows than the rate limit: nothing is done, a proposal is opened instead (spec §8).
  if p_approval is null and coalesce((v_plan ->> 'count')::int, 0) > v_limit then
    if v_dry then
      v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                             jsonb_build_object('would', format('open a proposal: %s rows is over the limit of %s', v_plan ->> 'count', v_limit),
                                                'over_limit', true, 'mode', v_f.mode), p_by, v_key);
      return jsonb_build_object('fix', p_fix, 'dry_run', true, 'action', v_id, 'over_limit', true);
    end if;
    v_prop := one.fix_propose(v_f, v_inc, v_plan, 'over_limit');
    v_id := one.fix_record(p_fix, p_incident, 'skip', 'skipped', false, v_target,
                           jsonb_build_object('reason', 'over_limit', 'limit', v_limit), p_by, v_key, null, v_prop);
    return jsonb_build_object('fix', p_fix, 'skipped', 'over_limit', 'proposal', v_prop, 'action', v_id);
  end if;
  if v_dry then
    v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                           jsonb_build_object('would', v_plan ->> 'would', 'mode', v_f.mode,
                                              'why_dry', case when p_dry_run then 'asked for a dry run'
                                                              when not coalesce((v_cfg ->> 'enabled')::boolean, false) then 'switched off'
                                                              else 'observation window' end), p_by, v_key);
    return jsonb_build_object('fix', p_fix, 'dry_run', true, 'action', v_id);
  end if;
  if v_f.mode = 'propose' or (v_f.mode = 'approve' and p_approval is null) then
    v_prop := one.fix_propose(v_f, v_inc, v_plan, v_f.mode);
    v_id := one.fix_record(p_fix, p_incident, 'after', 'done', false, v_target,
                           jsonb_build_object('proposal', v_prop, 'waiting', case when v_f.mode = 'approve' then 'the owner''s approval' end),
                           p_by, v_key, null, v_prop);
    return jsonb_build_object('fix', p_fix, 'proposal', v_prop, 'action', v_id);
  end if;
  if v_f.mode = 'approve' then
    -- An approved FIX-OUTBOX-B2B: B2B's admin action for each row, under the approver's session, with the fixer's rights.
    perform one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target, jsonb_build_object('approval', p_approval), p_by, v_key, null, p_approval);
    v_res := jsonb_build_object('done', '[]'::jsonb, 'refused', '[]'::jsonb);
    for v_id in select x::bigint from jsonb_array_elements_text(coalesce(v_plan -> 'rows', '[]')) x loop
      begin
        perform one.fixer_b2b_outbox_retry(v_id);
        v_res := jsonb_set(v_res, '{done}', (v_res -> 'done') || to_jsonb(v_id));
      exception when others then
        v_res := jsonb_set(v_res, '{refused}', (v_res -> 'refused') || jsonb_build_object('id', v_id, 'error', left(sqlerrm, 200)));
      end;
    end loop;
    v_status := case when jsonb_array_length(v_res -> 'done') > 0 then 'done' else 'failed' end;
    v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, v_res, p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id, 'result', v_res);
  end if;
  if v_f.mode = 'app' then
    v_id := one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target,
                           jsonb_build_object('waiting', 'the app', 'approval', p_approval), p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'queued_for_app', v_id);
  end if;
  perform one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target, jsonb_build_object('approval', p_approval), p_by, v_key, null, p_approval);
  begin
    v_res := one.fix_act(p_fix, v_plan);
    v_status := 'done';
  exception when others then
    v_res := jsonb_build_object('error', left(sqlerrm, 300), 'sqlstate', sqlstate);
    v_status := 'failed';
  end;
  v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, one.redact(coalesce(v_res, '{}'), one.pii_keys()), p_by, v_key,
                         case when v_status = 'done' then now() + make_interval(mins => least(2, v_cool)) end, p_approval);
  return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id);
end $$;

-- The spec's one function per fix (spec §8): one.fix_<id>(incident, dry_run). By hand they default to a dry run.
create or replace function one.fix_outbox_w2(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-OUTBOX-W2', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_cache_w2(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-CACHE-W2', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_n8n_retry(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-N8N-RETRY', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_outbox_b2b(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-OUTBOX-B2B', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_cursor_b2c(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-CURSOR-B2C', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_webhook_rekick(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-WEBHOOK-REKICK', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_inbox_retry(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-INBOX-RETRY', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_outbox_b2c(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-OUTBOX-B2C', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_outbox_web(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-OUTBOX-WEB', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_catalog_poll(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-CATALOG-POLL', p_incident, p_dry_run, 'sql:' || session_user) $$;
create or replace function one.fix_cache_b2c(p_incident bigint, p_dry_run boolean default true) returns jsonb
language sql set search_path = '' as $$ select one.fix_run('FIX-CACHE-B2C', p_incident, p_dry_run, 'sql:' || session_user) $$;

-- Verification --------------------------------------------------------------------------------------------------------

-- A real run is checked from verify_at (2 minutes after it, at most its cooldown): a failing run of the incident's check
-- from then, within the cooldown, while the fix's condition still holds, is the second failure (spec §8) and moves the
-- incident up one severity level; no failure by the end of the cooldown, or the incident resolved, means it held.
create or replace function one.fix_verify_due() returns jsonb
language plpgsql set search_path = '' as $$
declare
  r record;
  v_inc one.incidents;
  v_fail one.results;
  v_cool integer;
  v_n integer := 0;
  v_esc jsonb;
begin
  for r in
    select a.* from one.actions a
     where a.step = 'after' and a.status = 'done' and not a.dry_run and a.verify_at <= now()
       and not exists (select 1 from one.actions v where v.run_key = a.run_key and v.step = 'verify')
     order by a.id limit 50
  loop
    v_cool := coalesce((one.setting('fixes') -> r.fix_id ->> 'cooldown_min')::int, 60);
    select * into v_inc from one.incidents where id = r.incident_id;
    if v_inc.resolved_at is not null then
      perform one.fix_record(r.fix_id, r.incident_id, 'verify', 'done', false, r.target,
                             jsonb_build_object('held', true, 'incident', 'resolved ' || v_inc.resolution), 'one', r.run_key);
      v_n := v_n + 1;
      continue;
    end if;
    select * into v_fail from one.results x
     where x.check_id = v_inc.check_id and x.ran_at >= r.verify_at and x.ran_at <= r.ran_at + make_interval(mins => v_cool)
       and x.status in ('fail', 'error')
     order by x.ran_at limit 1;
    if found and coalesce((one.fix_plan(r.fix_id, v_inc) ->> 'applies')::boolean, false) then
      v_esc := one.incident_escalate(v_inc.id, format('%s ran at %s and %s failed again', r.fix_id, r.ran_at, v_inc.check_id));
      perform one.fix_record(r.fix_id, r.incident_id, 'verify', 'failed', false, r.target,
                             jsonb_build_object('held', false, 'failed_again_at', v_fail.ran_at) || v_esc, 'one', r.run_key);
      v_n := v_n + 1;
    elsif now() > r.ran_at + make_interval(mins => v_cool) then
      perform one.fix_record(r.fix_id, r.incident_id, 'verify', 'done', false, r.target,
                             jsonb_build_object('held', true, 'why', 'no second failure within the cooldown'), 'one', r.run_key);
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('verified', v_n);
end $$;

-- An executed approval, checked at its check_due_at: which of its rows the fix would still pick (spec §8: "the result is
-- written back to check_result").
create or replace function one.proposals_verify_due() returns jsonb
language plpgsql set search_path = '' as $$
declare
  p one.proposals;
  v_inc one.incidents;
  v_plan jsonb;
  v_rows jsonb;
  v_left jsonb;
  v_n integer := 0;
begin
  for p in
    select * from one.proposals
     where status = 'applied' and source = 'check' and change ? 'execute' and check_result is null and check_due_at <= now()
     order by id limit 20 for update skip locked
  loop
    v_rows := coalesce(p.change #> '{execute,rows}', '[]');
    select * into v_inc from one.incidents where id = (p.change #>> '{execute,incident}')::bigint;
    begin
      v_plan := one.fix_plan(p.change #>> '{execute,fix}', v_inc);
      v_left := coalesce(one.fix_plan_within(v_plan, v_rows) -> 'rows', '[]');
      update one.proposals
         set check_result = jsonb_build_object('checked_at', now(), 'rows', jsonb_array_length(v_rows), 'still_failing', v_left,
                                               'ok', jsonb_array_length(v_left) = 0, 'incident_resolved', v_inc.resolved_at is not null)
       where id = p.id;
    exception when others then
      update one.proposals set check_result = jsonb_build_object('checked_at', now(), 'error', left(sqlerrm, 200), 'ok', false) where id = p.id;
    end;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('proposals_checked', v_n);
end $$;

-- The tick's step ---------------------------------------------------------------------------------------------------

-- Starts the observation window on the first tick that reaches it (so it starts with production, D-079), verifies what
-- ran, then tries each fix on each open incident of its checks (synthetic ones aside), each in its own block.
create or replace function one.fixes_step() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_fixes jsonb := coalesce(one.setting('fixes'), '{}');
  v_out jsonb := '{}';
  r record;
  v jsonb;
begin
  if v_fixes ->> 'observation_started_at' is null then
    perform one.settings_put('fixes', v_fixes || jsonb_build_object('observation_started_at', now()), 'one',
                             'the observation window starts with the first tick that runs the fixes (D-079)');
    v_out := v_out || jsonb_build_object('observation_started', now());
  end if;
  begin
    v_out := v_out || one.fix_verify_due() || one.proposals_verify_due();
  exception when others then
    v_out := v_out || jsonb_build_object('verify_error', left(sqlerrm, 200));
  end;
  for r in
    select f.id as fix, i.id as incident from one.fixes f join one.incidents i on i.check_id = any (f.checks)
     where i.resolved_at is null and not 'synthetic' = any (i.tags)
     order by i.severity, f.id, i.id
  loop
    begin
      v := one.fix_run(r.fix, r.incident, false, 'one');
      if v ? 'action' or v ? 'queued_for_app' or v ? 'proposal' then
        v_out := v_out || jsonb_build_object(r.fix, coalesce(v ->> 'status', case when (v ->> 'dry_run')::boolean then 'dry_run' end, v ->> 'skipped', 'queued'));
      end if;
    exception when others then
      v_out := v_out || jsonb_build_object(r.fix, 'error: ' || left(sqlerrm, 160));
    end;
  end loop;
  return jsonb_build_object('fixes', v_out);
end $$;

-- The fixes run first, each isolated; then the app call and the AI step as in 0018. A failure of one never undoes the
-- others (each has its own block).
create or replace function one.tick_app_call() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v jsonb := '{}';
begin
  begin
    v := v || one.fixes_step();
  exception when others then
    v := v || jsonb_build_object('fixes_error', left(sqlerrm, 200));
  end;
  begin
    v := v || jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
  exception when others then
    return v || jsonb_build_object('app_error', sqlerrm);
  end;
  begin
    v := v || one.ai_step();
  exception when others then
    v := v || jsonb_build_object('ai_error', sqlerrm);
  end;
  return v;
end $$;

-- The app's side (service role) ---------------------------------------------------------------------------------------

-- Up to 10 real runs of the app's fixes (FIX-N8N-RETRY, FIX-WEBHOOK-REKICK) for the app to carry out, each held 5
-- minutes; a run the app never reports within 15 minutes is closed as failed.
create or replace function one.app_fixes_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v jsonb;
begin
  for r in
    select a.* from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run and a.ran_at <= now() - interval '15 minutes'
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
     order by a.id limit 50 for update of a skip locked
  loop
    perform one.fix_record(r.fix_id, r.incident_id, 'after', 'failed', false, r.target,
                           jsonb_build_object('error', 'the app did not report within 15 minutes'), 'one', r.run_key, null, r.proposal_id);
  end loop;
  with c as (
    select a.id from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run and a.ran_at > now() - interval '15 minutes'
       and (a.claimed_at is null or a.claimed_at < now() - interval '5 minutes')
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
     order by a.id limit 10 for update of a skip locked),
  u as (
    update one.actions a set claimed_at = now(), claimed_by = left(p_holder, 120) from c where a.id = c.id
    returning a.id, a.fix_id, a.incident_id, a.target)
  select coalesce(jsonb_agg(jsonb_build_object('action_id', u.id, 'fix_id', u.fix_id, 'incident_id', u.incident_id, 'target', u.target) order by u.id), '[]')
    into v from u;
  return jsonb_build_object('runs', v);
end $$;

-- The app's report on one run it claimed. FIX-N8N-RETRY: the retries, done if any succeeded. FIX-WEBHOOK-REKICK: p_ok
-- says whether Spark answered; then the kick runs here with the fixer's rights, else nothing is done and the P1 stays.
create or replace function one.app_fix_report(p_action bigint, p_ok boolean, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a one.actions;
  v_res jsonb := one.redact(coalesce(p_result, '{}'), one.pii_keys());
  v_status text;
  v_cool integer;
  v_id bigint;
begin
  select * into a from one.actions where id = p_action for update;
  if not found or a.step <> 'before' or a.dry_run or a.fix_id not in ('FIX-N8N-RETRY', 'FIX-WEBHOOK-REKICK') then
    raise exception 'action % is not an app fix waiting for its report', p_action using errcode = '22023';
  end if;
  if exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip')) then
    raise exception 'action % has its report already', p_action using errcode = '22023';
  end if;
  v_cool := coalesce((one.setting('fixes') -> a.fix_id ->> 'cooldown_min')::int, 60);
  if a.fix_id = 'FIX-WEBHOOK-REKICK' and not coalesce(p_ok, false) then
    v_id := one.fix_record(a.fix_id, a.incident_id, 'skip', 'skipped', false, a.target,
                           jsonb_build_object('reason', 'Spark did not answer: nothing done, the P1 stays', 'reachability', v_res), 'one', a.run_key);
    return jsonb_build_object('status', 'skipped', 'action', v_id);
  end if;
  if a.fix_id = 'FIX-WEBHOOK-REKICK' then
    begin
      v_res := jsonb_build_object('reachability', v_res, 'kick', one.fix_act('FIX-WEBHOOK-REKICK', '{}'));
      v_status := 'done';
    exception when others then
      v_res := jsonb_build_object('reachability', v_res, 'error', left(sqlerrm, 300));
      v_status := 'failed';
    end;
  else
    v_status := case when coalesce(p_ok, false) then 'done' else 'failed' end;
  end if;
  v_id := one.fix_record(a.fix_id, a.incident_id, 'after', v_status, false, a.target, v_res, 'one', a.run_key,
                         case when v_status = 'done' then now() + make_interval(mins => least(2, v_cool)) end, a.proposal_id);
  return jsonb_build_object('status', v_status, 'action', v_id);
end $$;

-- Approvals (the owner's session) ---------------------------------------------------------------------------------------

-- Runs an approved fix proposal once: FIX-OUTBOX-B2B's B2B admin action under the approver's session, or an over-limit
-- fix on the rows it named, each with the fixer's rights. Only proposals a fix opened itself execute (source check,
-- source_key fix:…), and only on rows that still qualify. Applied, with check_due_at 10 minutes on.
create or replace function one.proposal_execute(p_id bigint, p_actor text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  p one.proposals;
  v_x jsonb;
  v_res jsonb;
begin
  select * into p from one.proposals where id = p_id for update;
  v_x := p.change -> 'execute';
  if p.source <> 'check' or p.source_key not like 'fix:%' or v_x is null
     or p.source_key not like format('fix:%s:%s:%%', v_x ->> 'fix', v_x ->> 'incident') then
    return jsonb_build_object('executed', false, 'why', 'nothing to run: this proposal records a decision');
  end if;
  v_res := one.fix_run(v_x ->> 'fix', (v_x ->> 'incident')::bigint, false, p_actor, p_id, coalesce(v_x -> 'rows', '[]'));
  if coalesce(v_res ->> 'status', '') = 'done' or v_res ? 'queued_for_app' then
    update one.proposals set status = 'applied', applied_at = now(), check_due_at = now() + interval '10 minutes', check_result = null where id = p_id;
  end if;
  return jsonb_build_object('executed', true) || v_res;
end $$;

-- 0011's decision, and an approved fix proposal runs at once under the approver's session (spec §8).
create or replace function one.ui_proposal_decide(p_id bigint, p_decision text, p_note text default null, p_change jsonb default null,
                                                  p_snooze_days integer default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_p one.proposals;
  v_change jsonb;
  v_exec jsonb;
begin
  select * into v_p from one.proposals where id = p_id for update;
  if not found or v_p.status not in ('open', 'snoozed') then
    raise exception 'proposal % is not open', p_id using errcode = 'P0002';
  end if;
  case p_decision
    when 'approve' then
      v_change := coalesce(p_change, v_p.change);
      if one.proposal_sensitive(v_p.kind, v_p.change) or one.proposal_sensitive(v_p.kind, v_change) then
        perform one.ui_require('owner');
      end if;
      update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000),
                               change = v_change, check_due_at = now() + interval '1 day'
       where id = p_id;
      -- What runs is what the fix proposed (the stored change), on rows that still qualify: an edited change is kept
      -- in the audit and cannot widen it.
      if v_p.source = 'check' and v_p.change ? 'execute' then
        update one.proposals set change = v_p.change || jsonb_build_object('edited', v_change) where id = p_id and v_change is distinct from v_p.change;
        v_exec := one.proposal_execute(p_id, v_actor);
      end if;
    when 'reject' then
      update one.proposals set status = 'rejected', decided_by = v_actor, decided_at = now(), decision_note = one.ui_reason(p_note) where id = p_id;
    when 'snooze' then
      if coalesce(p_snooze_days, 0) not between 1 and 30 then
        raise exception 'snooze for 1 to 30 days' using errcode = '22023';
      end if;
      update one.proposals set status = 'snoozed', decision_note = left(p_note, 1000), expires_at = now() + make_interval(days => p_snooze_days)
       where id = p_id;
    else
      raise exception 'decision must be approve, reject or snooze' using errcode = '22023';
  end case;
  perform one.ui_audit_write(v_actor, 'proposal.' || p_decision, 'proposal:' || p_id,
                             jsonb_build_object('status', v_p.status, 'change', v_p.change),
                             jsonb_build_object('note', p_note, 'change', v_change, 'snooze_days', p_snooze_days, 'executed', v_exec), p_request_id);
  return jsonb_build_object('ok', true, 'executed', v_exec);
end $$;

-- The Fixes page ------------------------------------------------------------------------------------------------------

-- Every fix with its catalogue entry, settings, grants, evidence (counts and the latest rows) and open incidents, and
-- the observation window. can_enable: the window has ended and the fix has at least one dry run (enable on evidence).
create or replace function one.ui_fixes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_win jsonb := one.fix_window();
begin
  return jsonb_build_object(
    'window', v_win,
    'fixes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id, 'app', f.app, 'title', f.title, 'checks', to_jsonb(f.checks), 'trigger', f.trigger, 'mode', f.mode,
        'what', f.what, 'grants', f.grants, 'rollback', f.rollback, 'app_functions', to_jsonb(f.app_functions),
        'settings', coalesce(one.setting('fixes') -> f.id, '{}'),
        'grants_state', one.fix_grants(f.id),
        'counts', (select jsonb_build_object('dry_runs', count(*) filter (where a.step = 'dry_run'),
                                             'runs', count(*) filter (where a.step = 'after'),
                                             'failed', count(*) filter (where a.step = 'after' and a.status = 'failed'),
                                             'skipped', count(*) filter (where a.step = 'skip'),
                                             'held', count(*) filter (where a.step = 'verify' and a.status = 'done'),
                                             'escalated', count(*) filter (where a.step = 'verify' and a.status = 'failed'),
                                             'last_at', max(a.ran_at))
                     from one.actions a where a.fix_id = f.id),
        'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
                     from (select * from one.actions where fix_id = f.id order by id desc limit 10) a),
        'open_incidents', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'severity', i.severity, 'title', i.title)
                                                     order by i.id), '[]')
                             from one.incidents i where i.check_id = any (f.checks) and i.resolved_at is null),
        'can_enable', not (v_win ->> 'running')::boolean and exists (select 1 from one.actions a where a.fix_id = f.id and a.dry_run))
      order by f.id), '[]') from one.fixes f));
end $$;

-- The owner switches a fix or changes its limits, with a reason (versioned through one.settings_put, which refuses
-- enabling before the window ends or without a dry run).
create or replace function one.ui_fix_set(p_fix text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_entry jsonb;
  v_version integer;
begin
  if not exists (select 1 from one.fixes where id = p_fix) then
    raise exception 'no fix %', p_fix using errcode = 'P0002';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or exists (select 1 from jsonb_object_keys(p_patch) k where k not in ('enabled', 'per_tick', 'cooldown_min')) then
    raise exception 'change enabled, per_tick or cooldown_min' using errcode = '22023';
  end if;
  select value into v_before from one.settings where key = 'fixes' for update;
  v_entry := coalesce(v_before -> p_fix, '{}') || p_patch;
  if v_entry = coalesce(v_before -> p_fix, '{}') then
    raise exception 'nothing changed' using errcode = '22023';
  end if;
  v_version := one.settings_put('fixes', v_before || jsonb_build_object(p_fix, v_entry), v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'fix.set', 'fix:' || p_fix, v_before -> p_fix, v_entry, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

-- A dry run now, on an open incident of the fix's checks (operate). It records what the fix would do and changes
-- nothing; the tick's cooldown does not count it.
create or replace function one.ui_fix_dry_run(p_fix text, p_incident bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v jsonb;
begin
  v := one.fix_run(p_fix, p_incident, true, v_actor);
  perform one.ui_audit_write(v_actor, 'fix.dry_run', 'fix:' || p_fix, null, jsonb_build_object('incident', p_incident, 'result', v), p_request_id);
  return jsonb_build_object('ok', true) || v;
end $$;

-- The brief ---------------------------------------------------------------------------------------------------------

-- 0018's numbers, and what the fixes did that day (spec §8: every action is in the next morning brief).
create or replace function one.ai_brief_stats(p_for_date date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_from timestamptz := ((p_for_date - 1)::timestamp) at time zone 'Asia/Kolkata';
  v_to timestamptz := (p_for_date::timestamp) at time zone 'Asia/Kolkata';
  v jsonb;
  v_witty jsonb;
begin
  v := jsonb_build_object(
    'window', jsonb_build_object('day_ist', p_for_date - 1, 'from', v_from, 'to', v_to),
    'incidents_opened', (select coalesce(jsonb_agg(jsonb_build_object('app', app, 'severity', severity, 'n', n) order by app, severity), '[]')
                           from (select app, severity, count(*) as n from one.incidents
                                  where opened_at >= v_from and opened_at < v_to and check_id <> 'ONE-SYNTH' group by 1, 2) s),
    'p1', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                        'resolved_at', i.resolved_at, 'resolution', i.resolution, 'summary', i.summary,
                                                        'minutes_open', round(extract(epoch from coalesce(i.resolved_at, now()) - i.opened_at) / 60))
                                     order by i.opened_at), '[]')
             from (select * from one.incidents where severity = 'P1' and opened_at >= v_from and opened_at < v_to order by opened_at limit 30) i),
    'resolved', (select coalesce(jsonb_object_agg(coalesce(resolution, '?'), n), '{}')
                   from (select resolution, count(*) as n from one.incidents where resolved_at >= v_from and resolved_at < v_to and check_id <> 'ONE-SYNTH' group by 1) s),
    'open_now', jsonb_build_object(
       'by_severity', (select coalesce(jsonb_object_agg(severity, n), '{}') from (select severity, count(*) as n from one.incidents where resolved_at is null group by 1) s),
       'oldest', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'severity', i.severity, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                              'acknowledged', i.acknowledged_at is not null) order by i.opened_at), '[]')
                    from (select * from one.incidents where resolved_at is null and check_id <> 'ONE-SYNTH' order by opened_at limit 10) i)),
    'checks_failing_now', (select coalesce(jsonb_agg(jsonb_build_object('check_id', x.check_id, 'app', x.app, 'severity', x.severity, 'status', x.status)
                                                     order by x.severity, x.check_id), '[]')
                             from (select distinct on (r.check_id) r.check_id, r.status, c.app, c.severity
                                     from one.results r join one.checks c on c.id = r.check_id
                                    where c.enabled and r.ran_at > now() - interval '1 day'
                                    order by r.check_id, r.ran_at desc) x where x.status <> 'ok'),
    'checks_off', (select coalesce(jsonb_object_agg(reason, n), '{}')
                     from (select coalesce(split_part(disabled_reason, ':', 1), 'off') as reason, count(*) as n from one.checks where not enabled group by 1) s),
    'tests', (select coalesce(jsonb_agg(jsonb_build_object('test', test_id, 'runs', n, 'passed', ok_n, 'failed', bad_n, 'last_error', last_error) order by test_id), '[]')
                from (select test_id, count(*) as n, count(*) filter (where ok) as ok_n, count(*) filter (where ok = false) as bad_n,
                             (array_agg(error order by started_at desc) filter (where ok = false))[1] as last_error
                        from one.test_runs where started_at >= v_from and started_at < v_to group by 1) s),
    'deliveries', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
                     from (select kind, status, count(*) as n from one.deliveries where created_at >= v_from and created_at < v_to group by 1, 2) s),
    'ai', jsonb_build_object(
       'spend_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where created_at >= v_from and created_at < v_to),
       'calls', (select count(*) from one.ai_calls where created_at >= v_from and created_at < v_to),
       'tasks', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
                   from (select kind, status, count(*) as n from one.ai_tasks where created_at >= v_from and created_at < v_to group by 1, 2) s)),
    'proposals', jsonb_build_object(
       'opened', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'app', p.app, 'title', p.title, 'source', p.source, 'risk', p.risk) order by p.id), '[]')
                    from (select * from one.proposals where created_at >= v_from and created_at < v_to order by id limit 20) p),
       'open_total', (select count(*) from one.proposals where status = 'open')),
    'events_by_app', (select coalesce(jsonb_object_agg(app, n), '{}') from (select app, count(*) as n from one.events where occurred_at >= v_from and occurred_at < v_to group by 1) s),
    'heartbeats_down', (select coalesce(jsonb_agg(h.component order by h.component), '[]') from one.heartbeats h
                         where h.last_error_at is not null and h.last_error_at > coalesce(h.last_ok_at, '-infinity')),
    'fixes', jsonb_build_object(
       'window', one.fix_window(),
       'by_fix', (select coalesce(jsonb_agg(jsonb_build_object('fix', fix_id, 'dry_runs', d, 'runs', n, 'failed', bad, 'skipped', sk, 'escalated', esc) order by fix_id), '[]')
                    from (select fix_id, count(*) filter (where step = 'dry_run') as d, count(*) filter (where step = 'after') as n,
                                 count(*) filter (where step = 'after' and status = 'failed') as bad, count(*) filter (where step = 'skip') as sk,
                                 count(*) filter (where step = 'verify' and status = 'failed') as esc
                            from one.actions where ran_at >= v_from and ran_at < v_to group by 1) s)));
  begin
    perform set_config('lock_timeout', '2s', true);
    select e into v_witty from jsonb_array_elements(one.embed_data('witty.replies')) e where e ->> 'day' = (p_for_date - 1)::text;
    perform set_config('search_path', '', true);
    v := v || jsonb_build_object('witty_replies', v_witty);
  exception when others then
    perform set_config('search_path', '', true);
    v := v || jsonb_build_object('witty_replies_error', left(sqlerrm, 160));
  end;
  v := one.redact(v, one.pii_keys());
  -- Answers pinned to this brief (Ask page). Questions are staff's own words; the app masks them like everything else.
  return v || jsonb_build_object('pins', (select coalesce(jsonb_agg(jsonb_build_object('question', t.input ->> 'question', 'answer', t.result ->> 'answer')
                                                                    order by p.created_at), '[]')
                                            from one.brief_pins p join one.ai_tasks t on t.id = p.task_id where p.for_date = p_for_date));
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.app_fixes_claim(text)', 'service_role', 'fixes (0019): the app''s fix runs to carry out (n8n retries, the Spark check)'),
  ('one.app_fix_report(bigint,boolean,jsonb)', 'service_role', 'fixes (0019): the app''s report on a fix run it claimed'),
  ('one.ui_fixes()', 'authenticated', 'Fixes page (0019): the catalogue, switches, grants and evidence'),
  ('one.ui_fix_set(text,jsonb,text,text)', 'authenticated', 'Fixes page (0019): the owner switches a fix or its limits'),
  ('one.ui_fix_dry_run(text,bigint,text)', 'authenticated', 'Fixes page (0019): a dry run now on an open incident')
on conflict do nothing;
call one.apply_grants();
