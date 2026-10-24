-- 0019 the auto-fixes (spec §8, phase 7). Every fix is a function one.fix_<id>(incident, dry_run) over one engine:
--
--   one.fix_run()       the safety shell every fix goes through: the switch in one.settings.fixes (off, or the
--                       observation window running, means a dry run that only records what it would do); a cooldown
--                       (a real run once per fix per cooldown, whoever ran it; a dry run once per fix and incident);
--                       the rate limit (more rows than per_tick: nothing is done and a proposal is opened); test rows
--                       left out; an action row before and after; no more runs on an incident where one did not hold;
--   one.fix_plan()      what a fix would touch, from what its check last observed, read with Eduwit One's own rights
--                       as the checks read (ids and counts, never a phone or a name);
--   one.fix_act()       the act itself, only through the one.fixer_* functions below;
--   one.fixer_*()       owned by eduwit_one_fixer and SECURITY DEFINER, so every write a fix makes runs with the
--                       fixer's rights: USAGE on three app schemas and EXECUTE on the ten catalogue functions, granted
--                       here and nothing else (no table or column privilege, no RLS bypass: D-030);
--   one.fixes_job()     the minute tick's fix step, after the app call, one transaction per fix (one.fixes_step() for
--                       the tick by hand): starts the observation window, verifies earlier runs and approvals, then
--                       tries each fix on each open incident of its checks;
--   one.fix_verify_due() each real run is judged by the first run of its check from 2 minutes on: ok, it held; failing
--                       while the fix's condition still holds, the second failure: the incident goes up one severity
--                       level (once per failing run) and the fix stops on it; no run to judge by, unverified;
--   one.app_fixes_claim(), one.app_fix_report()   the app's side of its two fixes (n8n retries; the Spark check
--                       before a kick), service role;
--   one.proposal_execute()   an approved proposal a fix opened, run once under the approver's session on the rows the
--                       approver saw that still qualify, checked at check_due_at.
--
-- Three catalogue fixes cannot act from Eduwit One without changing an app (D-080): FIX-OUTBOX-W2 and FIX-CACHE-W2
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
  created_at timestamptz not null default now()
);

insert into one.fixes (id, app, title, checks, trigger, mode, what, grants, rollback, app_functions) values
  ('FIX-OUTBOX-W2', 'witty', 'Send failed Witty outbox rows to the CRM again', '{WITTY-01}',
   'WITTY-01 names outbox_failed',
   'propose',
   'Lists Witty outbox rows in failed with fewer than 8 attempts and no permanent error (INVALID_DATA, MANDATORY_NOT_FOUND, DUPLICATE_DATA), test phones left out, and opens a proposal. It cannot send them itself: Witty has no function that sends a failed row again (public.w2_outbox_retry takes a limit, picks only pending rows and runs lead_intake() with its caller''s rights), and w2_outbox admits only its owner and the service role (D-080).',
   'none: it cannot act', 'none: nothing in Witty changes', '{}'),
  ('FIX-CACHE-W2', 'witty', 'Renew Witty''s expired prompt caches', '{WITTY-01}',
   'WITTY-01 names cache_expired',
   'propose',
   'Lists Witty''s expired prompt caches (names only) and opens a proposal. The n8n API cannot start Witty''s Cache Manager: it has only schedule triggers (every 10 and 15 minutes, which renew the caches themselves) and a sub-workflow trigger (D-080).',
   'none: it cannot act', 'none: nothing in Witty changes', '{}'),
  ('FIX-N8N-RETRY', 'witty', 'Retry a failed execution of the Witty workflow', '{WITTY-02}',
   'WITTY-02 lists executions in error or crashed (failed_15m) that are not themselves retries',
   'app',
   'The app retries each failed execution of the Witty workflow once through the n8n API (POST /api/v1/executions/{id}/retry), after checking it belongs to that workflow and is still in error; an execution is never retried twice, and a retry that fails is not retried. Witty is idempotent by message_id.',
   'the n8n API key (Setup item n8n_api); nothing in the database', 'none needed', '{}'),
  ('FIX-OUTBOX-B2B', 'b2b', 'Send dead or failed B2B deliveries to Spark again', '{B2B-01}',
   'B2B-01 counts dead deliveries or deliveries waiting over an hour',
   'approve',
   'Lists dead deliveries, and failed ones older than an hour, of the last 7 days (test payloads and deliveries already sent again left out) and opens a proposal; the owner''s approval runs B2B''s own b2b.outbox_retry(id) for each, under the owner''s session and with the fixer''s rights. B2B lets only an admin send a delivery again, and the outbox''s row security admits no other role, so the fixer could not change a row itself (D-080).',
   'EXECUTE on b2b.outbox_retry(bigint), used only under the owner''s session (B2B checks that the caller is an admin)',
   'an admin sets the rows back to dead in the B2B CRM', '{b2b.outbox_retry(bigint)}'),
  ('FIX-CURSOR-B2C', 'b2b', 'Run the B2B to Spark sync once', '{B2B-01}',
   'B2B-01 reports the B2C sync cursor over 600 s and the job b2b-b2c-sync-tick did not fail on its last run',
   'act',
   'select b2b.b2c_sync_tick(200) once.',
   'EXECUTE on b2b.b2c_sync_tick(integer)', 'none needed', '{b2b.b2c_sync_tick(integer)}'),
  ('FIX-WEBHOOK-REKICK', 'b2b', 'Kick the B2B outbox once Spark answers', '{B2B-06}',
   'B2B-06 fails',
   'app',
   'The app checks that <hosts.spark>/v1/handoffs answers (HEAD, then GET, within 10 s, with a status that shows the route is there: 2xx, 400, 401, 403, 405, 415 or 422). If it does, select b2b.outbox_kick() runs with the fixer''s rights; if not, nothing is done and the P1 stays.',
   'EXECUTE on b2b.outbox_kick()', 'none needed', '{b2b.outbox_kick()}'),
  ('FIX-INBOX-RETRY', 'b2c', 'Apply Spark''s stuck inbox rows again', '{B2C-02}',
   'B2C-02 fails',
   'act', 'select b2c.inbox_retry(50): Spark applies up to 50 stored or failed envelopes again, as its own retry would, test ones included (the function takes no filter).',
   'EXECUTE on b2c.inbox_retry(integer)', 'none needed', '{b2c.inbox_retry(integer)}'),
  ('FIX-OUTBOX-B2C', 'b2c', 'Unstick Spark''s outbox and run its urgent sync', '{B2C-03}',
   'B2C-03 fails',
   'act', 'select b2c.outbox_unstick() (rows stuck sending over 10 minutes back to queued, test ones included: the function takes no filter), then b2c.job_call(''/api/internal/sync?mode=urgent'').',
   'EXECUTE on b2c.outbox_unstick() and b2c.job_call(text)', 'none needed', array['b2c.outbox_unstick()', 'b2c.job_call(text)']),
  ('FIX-OUTBOX-WEB', 'web', 'Send the website''s dead outbox rows again and run its worker', '{WEB-01}',
   'WEB-01 reports dead outbox rows or the oldest pending row over 900 s',
   'act',
   'public.web_outbox_retry(id, actor) for each dead row with attempts below max_attempts (test payloads, and rows an earlier run already sent again, left out), then public.web_job_call(''/api/internal/outbox'', 55000).',
   'EXECUTE on public.web_outbox_retry(bigint, uuid) and public.web_job_call(text, integer)', 'none needed',
   array['public.web_outbox_retry(bigint,uuid)', 'public.web_job_call(text,integer)']),
  ('FIX-CATALOG-POLL', 'web', 'Run the website''s catalogue poll', '{WEB-01,CAT-02}',
   'WEB-01 reports the catalogue poll older than 600 s, or CAT-02 fails',
   'act', 'select public.web_catalog_poll().', 'EXECUTE on public.web_catalog_poll()', 'none needed', '{public.web_catalog_poll()}'),
  ('FIX-CACHE-B2C', 'b2c', 'Refresh Spark''s programme cache', '{CAT-01}',
   'CAT-01 fails',
   'act', 'select b2c.programme_cache_refresh(true).', 'EXECUTE on b2c.programme_cache_refresh(boolean)', 'none needed',
   '{b2c.programme_cache_refresh(boolean)}');

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

-- The fixer's functions: each calls exactly the app functions its fix needs, nothing else (the guards check each body).
-- They are created here, then handed to eduwit_one_fixer, which needs CREATE on schema one only for that hand-over
-- (revoked below, in the same transaction) and the migrating user's membership to give it (Postgres 16+). That
-- membership stays (INHERIT, SET): it is how the migrating user, which owns every other function of schema one, may
-- execute them, since their ACL names only the fixer (one.apply_grants revokes PUBLIC). No API role reaches them. Like
-- every role, the fixer also holds what PUBLIC holds; only these bodies ever run as it, and they call nothing else.

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

-- p_actor: the approver's user id when an approval runs it (the website's audit records them), null for the tick.
create or replace function one.fixer_web_outbox(p_ids bigint[], p_actor uuid) returns jsonb
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
    perform public.web_outbox_retry(v_id, p_actor);
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
alter function one.fixer_web_outbox(bigint[], uuid) owner to eduwit_one_fixer;
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

-- Whether each app function a fix calls exists and is granted to the fixer.
create or replace function one.fix_grants(p_fix text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
           'ok', coalesce(bool_and(x.ok), true),
           'missing', coalesce(jsonb_agg(x.fn) filter (where not x.ok), '[]'))
    from (select fn, coalesce(to_regprocedure(fn) is not null and has_function_privilege('eduwit_one_fixer', to_regprocedure(fn), 'EXECUTE'), false) as ok
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
-- target}. Read with Eduwit One's own rights, as the checks read the same tables; ids and counts only. It works from
-- what the check last observed (the incident's evidence: {status, value, error}); a check that could not run (error,
-- source_missing) observed nothing to fix. Rows an earlier run already sent again are left out: a row that fails again
-- after that is a person's to look at (phase 7 review M10).
create or replace function one.fix_plan(p_fix text, p_inc one.incidents) returns jsonb
language plpgsql set search_path = '' as $$
declare
  e jsonb := coalesce(p_inc.evidence -> 'value', '{}');
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
  if coalesce(p_inc.evidence ->> 'status', '') <> 'fail' then
    return jsonb_build_object('applies', false,
                              'why_not', format('%s could not run (%s): it observed nothing to fix', p_inc.check_id, coalesce(p_inc.evidence ->> 'status', 'no reading')));
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
      -- Each execution once, never a retry of a retry: left out are the probe's retries_15m and any id an earlier run
      -- named, unless that run's report says the app never sent it (skipped: out of time, not configured, not this
      -- workflow's, no longer in error). An unreported run counts as sent (phase 7 review M9, M10).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where x.n <= 500), '[]'), count(*) into v_rows, v_n
        from (select x.id, row_number() over (order by x.id) as n
                from jsonb_array_elements_text(coalesce(e -> 'failed_15m', '[]')) as x(id)
               where not coalesce(e -> 'retries_15m', '[]') ? x.id
                 and not exists (
                   select 1 from one.actions b
                    where b.fix_id = 'FIX-N8N-RETRY' and b.step = 'before' and not b.dry_run and coalesce(b.target -> 'rows', '[]') ? x.id
                      and not exists (select 1 from one.actions a2
                                       where a2.run_key = b.run_key and a2.step = 'after'
                                         and exists (select 1 from jsonb_array_elements(coalesce(a2.result -> 'skipped', '[]')) k where k ->> 'id' = x.id)))) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no failed execution that was not retried already' end,
                                'rows', v_rows, 'count', v_n,
                                'target', jsonb_build_object('workflow_id', one.setting('n8n') ->> 'witty_workflow_id'),
                                'would', 'retry each execution once through the n8n API');
    when 'FIX-OUTBOX-B2B' then
      if coalesce((e #>> '{deliveries,dead_7d}')::int, 0) + coalesce((e #>> '{deliveries,waiting_over_1h}')::int, 0) = 0 then
        return jsonb_build_object('applies', false, 'why_not', 'B2B-01 reports no dead or waiting delivery');
      end if;
      -- As B2B-01 counts them: dead, or failed and waiting over an hour (a younger failed one is still in B2B's own
      -- backoff). A test lead's handoff carries test true at the top of its payload or in its data (as Spark reads it).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     coalesce(o.payload @> '{"test": true}' or o.payload -> 'data' @> '{"test": true}', false) as t
                from b2b.integration_outbox o
               where (o.status = 'dead' or (o.status = 'failed' and o.created_at < now() - interval '1 hour'))
                 and o.created_at > now() - interval '7 days' and o.endpoint_id is not null
                 and not exists (select 1 from one.actions a where a.fix_id = 'FIX-OUTBOX-B2B' and a.step = 'after' and not a.dry_run
                                    and coalesce(a.result -> 'done', '[]') @> to_jsonb(o.id))) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no dead or long-failed delivery that was not sent again already' end,
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
                from public.web_outbox o
               where o.status = 'dead' and o.attempts < o.max_attempts
                 and not exists (select 1 from one.actions b join one.actions a on a.run_key = b.run_key and a.step = 'after' and a.status = 'done'
                                  where b.fix_id = 'FIX-OUTBOX-WEB' and b.step = 'before' and not b.dry_run
                                    and coalesce(b.target -> 'rows', '[]') @> to_jsonb(o.id))) x;
      return jsonb_build_object('applies', v_n > 0 or v_old,
                                'why_not', case when v_n = 0 and not v_old then 'no dead row with attempts left that was not sent again already: a person decides' end,
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
         else p_plan || jsonb_build_object('rows', r.rows, 'count', jsonb_array_length(r.rows),
                                           'applies', jsonb_array_length(r.rows) > 0 or coalesce((p_plan #>> '{target,oldest_pending_old}')::boolean, false))
         end
    from (select coalesce(jsonb_agg(x order by x::text), '[]') as rows from jsonb_array_elements(coalesce(p_plan -> 'rows', '[]')) x
           where coalesce(p_rows, '[]') @> jsonb_build_array(x)) r
$$;

-- The act: only through the fixer's functions, so it runs with the fixer's rights.
create or replace function one.fix_act(p_fix text, p_plan jsonb, p_actor uuid default null) returns jsonb
language plpgsql set search_path = '' as $$
begin
  case p_fix
    when 'FIX-CURSOR-B2C' then return jsonb_build_object('sync', one.fixer_b2c_sync());
    when 'FIX-WEBHOOK-REKICK' then return jsonb_build_object('kick', one.fixer_outbox_kick());
    when 'FIX-INBOX-RETRY' then return jsonb_build_object('applied', one.fixer_inbox_retry());
    when 'FIX-OUTBOX-B2C' then return one.fixer_b2c_outbox();
    when 'FIX-OUTBOX-WEB' then
      return one.fixer_web_outbox(array(select x::bigint from jsonb_array_elements_text(coalesce(p_plan -> 'rows', '[]')) x), p_actor);
    when 'FIX-CATALOG-POLL' then return jsonb_build_object('poll', one.fixer_catalog_poll());
    when 'FIX-CACHE-B2C' then return jsonb_build_object('refreshed', one.fixer_programme_cache());
    else raise exception '% does not act in the database', p_fix using errcode = '22023';
  end case;
end $$;

-- A fix's proposal: one open proposal per fix and incident, refreshed while it waits (source check, owner's decision).
-- Only a fix that acts (act, app, approve) gets an execute part; a proposing fix's proposal only describes a change.
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
    v_rationale := format('%s would touch %s rows on incident %s (%s), more than its rate limit of %s a run, so it did nothing (spec §8). Approving runs it once on the rows listed that still qualify then, with the fixer''s rights; remove rows from the change to leave them out.',
                          p_fix.id, v_n, p_inc.id, p_inc.check_id, v_limit);
  elsif p_fix.id = 'FIX-OUTBOX-B2B' then
    v_title := format('B2B: send %s dead or failed deliveries to Spark again', v_n);
    v_rationale := 'B2B lets only an admin send a delivery again (b2b.outbox_retry), and its outbox admits no other role, so FIX-OUTBOX-B2B cannot act on its own (D-080). Approving runs b2b.outbox_retry for each listed delivery that is still dead or failed, under your session: B2B refuses unless you are a B2B admin. Ten minutes later Eduwit One checks which were delivered. Remove rows from the change to leave them out.';
  elsif p_fix.id = 'FIX-OUTBOX-W2' then
    v_title := format('Witty: %s failed outbox rows cannot be sent again from Eduwit One', v_n);
    v_rationale := 'Witty has no function that sends a failed outbox row again: public.w2_outbox_retry(p_limit) picks only pending rows and runs lead_intake() with its caller''s rights, and w2_outbox admits only its owner and the service role. Witty''s maintainer could add a SECURITY DEFINER public.w2_outbox_requeue(p_id bigint) that sets a failed row with a retryable error back to pending, and grant EXECUTE on it to eduwit_one_fixer; FIX-OUTBOX-W2 would then use it (D-080). Approving records your decision; nothing runs.';
  elsif p_fix.id = 'FIX-CACHE-W2' then
    v_title := format('Witty: %s prompt caches expired and were not renewed', v_n);
    v_rationale := 'Witty renews its prompt caches itself every 10 and 15 minutes; caches still expired mean that renewal is failing (Gemini, or the workflow). The n8n API cannot start the Cache Manager, which has only schedule and sub-workflow triggers, so FIX-CACHE-W2 cannot act. Look at the Witty workflow''s recent executions in n8n. A webhook trigger on the Cache Manager would let Eduwit One start it (D-080). Approving records your decision; nothing runs.';
  else
    v_title := format('%s on incident %s', p_fix.id, p_inc.id);
    v_rationale := p_fix.what;
  end if;
  v_change := jsonb_build_object('fix', p_fix.id, 'incident', p_inc.id, 'rows', coalesce(p_plan -> 'rows', '[]'), 'target', p_plan -> 'target');
  if p_fix.mode <> 'propose' then
    v_change := v_change || jsonb_build_object('execute', jsonb_build_object('fix', p_fix.id, 'mode', p_fix.mode, 'incident', p_inc.id,
                                                                             'rows', coalesce(p_plan -> 'rows', '[]')));
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
-- observation window has ended. p_by is 'one' for the minute tick, else who ran it. p_approval is the approved proposal
-- this run carries out: the owner's consent for one run, on p_rows (the rows the approver saw) where they still qualify;
-- p_actor is the approver's user id. The cooldown: a dry run of the tick's once per fix and incident; a real run once
-- per fix, whoever ran it (the tick, by hand, an approval), approvals themselves not held (phase 7 review M11).
create or replace function one.fix_run(p_fix text, p_incident bigint, p_dry_run boolean default true, p_by text default 'one',
                                       p_approval bigint default null, p_rows jsonb default null, p_actor uuid default null) returns jsonb
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
  -- A run on this incident did not hold: the incident went up a level instead of a retry (spec §8), and the fix stays
  -- off it; only an approval runs it again, and a person may still ask for a dry run (phase 7 review M10).
  if p_approval is null and not (v_dry and p_by <> 'one')
     and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.step = 'verify' and a.status = 'failed') then
    return jsonb_build_object('fix', p_fix, 'skipped', 'stopped: a run on this incident did not hold');
  end if;
  if p_approval is null then
    if v_dry then
      if p_by = 'one' and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.dry_run and a.ran_by = 'one'
                                     and a.ran_at > now() - make_interval(mins => v_cool)) then
        return jsonb_build_object('fix', p_fix, 'skipped', 'cooldown');
      end if;
    elsif exists (select 1 from one.actions a where a.fix_id = p_fix and not a.dry_run and a.step in ('before', 'after', 'skip')
                     and a.ran_at > now() - make_interval(mins => v_cool)) then
      return jsonb_build_object('fix', p_fix, 'skipped', 'cooldown');
    end if;
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
  -- More rows than the rate limit: nothing is done, a proposal is opened instead (spec §8). A proposing fix's act is the
  -- proposal itself, so it has no row limit (phase 7 review M3).
  if p_approval is null and v_f.mode <> 'propose' and coalesce((v_plan ->> 'count')::int, 0) > v_limit then
    if v_dry then
      v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                             jsonb_build_object('would', format('open a proposal: %s rows is over the limit of %s', v_plan ->> 'count', v_limit),
                                                'over_limit', true, 'mode', v_f.mode), p_by, v_key);
      return jsonb_build_object('fix', p_fix, 'dry_run', true, 'action', v_id, 'over_limit', true);
    end if;
    v_prop := one.fix_propose(v_f, v_inc, v_plan, 'over_limit');
    v_id := one.fix_record(p_fix, p_incident, 'skip', 'skipped', false, v_target,
                           jsonb_build_object('reason', 'over_limit', 'limit', v_limit, 'proposal', v_prop), p_by, v_key, null, v_prop);
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
    v_res := one.redact(v_res || jsonb_build_object('partial', jsonb_array_length(v_res -> 'done') > 0 and jsonb_array_length(v_res -> 'refused') > 0),
                        one.pii_keys());
    v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, v_res, p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id, 'result', v_res);
  end if;
  if v_f.mode = 'app' then
    v_id := one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target,
                           jsonb_build_object('waiting', 'the app', 'approval', p_approval), p_by, v_key, null, p_approval);
    return jsonb_build_object('fix', p_fix, 'queued_for_app', v_id);
  end if;
  perform one.fix_record(p_fix, p_incident, 'before', 'planned', false, v_target, jsonb_build_object('approval', p_approval), p_by, v_key, null, p_approval);
  -- An app row held by another session makes the act give up after the checks' lock timeout instead of waiting
  -- (phase 7 review M8).
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  begin
    v_res := one.fix_act(p_fix, v_plan, p_actor);
    v_status := 'done';
  exception when others then
    v_res := jsonb_build_object('error', left(sqlerrm, 300), 'sqlstate', sqlstate);
    v_status := 'failed';
  end;
  v_id := one.fix_record(p_fix, p_incident, 'after', v_status, false, v_target, one.redact(coalesce(v_res, '{}'), one.pii_keys()), p_by, v_key,
                         case when v_status = 'done' then now() + make_interval(mins => least(2, v_cool)) end, p_approval);
  return jsonb_build_object('fix', p_fix, 'status', v_status, 'action', v_id);
end $$;

-- The spec's one function per fix (spec §8): one.fix_<id>(incident, dry_run). By hand they default to a dry run; a real
-- one acts only when switched on after the window, and is held by the cooldown like any other.
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

-- Judges one real run by the first run of its check from verify_at (2 minutes on, at most the cooldown): ok, it held;
-- failing while the fix's condition still holds on what that run saw, the second failure (spec §8): the incident goes
-- up one level, once per failing run however many fixes ran (phase 7 review M6), and the fix stops on it; the check
-- could not run, or never ran by the cooldown plus two of its cadences, unverified (review M5). Null while it waits.
create or replace function one.fix_verify_one(p_run one.actions) returns text
language plpgsql set search_path = '' as $$
declare
  v_inc one.incidents;
  v_seen one.incidents;
  v_next one.results;
  v_cool integer := coalesce((one.setting('fixes') -> p_run.fix_id ->> 'cooldown_min')::int, 60);
  v_cadence integer;
  v_applies boolean;
  v_esc jsonb;
begin
  select * into v_inc from one.incidents where id = p_run.incident_id;
  if v_inc.resolved_at is not null then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'why', 'the incident resolved (' || v_inc.resolution || ')'), 'one', p_run.run_key);
    return 'held';
  end if;
  select cadence_s into v_cadence from one.checks where id = v_inc.check_id;
  select * into v_next from one.results x where x.check_id = v_inc.check_id and x.ran_at >= p_run.verify_at order by x.ran_at, x.id limit 1;
  if not found then
    if now() > p_run.ran_at + make_interval(mins => v_cool) + make_interval(secs => 2 * coalesce(v_cadence, 60)) then
      perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'skipped', false, p_run.target,
                             jsonb_build_object('held', null, 'why', format('no run of %s to judge it by', v_inc.check_id)), 'one', p_run.run_key);
      return 'unverified';
    end if;
    return null;
  end if;
  if v_next.status = 'ok' then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'judged_by', v_next.id, 'why', format('%s passed at %s', v_inc.check_id, v_next.ran_at)),
                           'one', p_run.run_key);
    return 'held';
  end if;
  if v_next.status <> 'fail' then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'skipped', false, p_run.target,
                           jsonb_build_object('held', null, 'judged_by', v_next.id, 'why', format('%s could not run (%s)', v_inc.check_id, v_next.status)),
                           'one', p_run.run_key);
    return 'unverified';
  end if;
  -- What that failing run saw, as the plan reads it. A retried execution that failed again shows as a retry.
  v_seen := v_inc;
  v_seen.evidence := jsonb_build_object('status', 'fail', 'value', v_next.value);
  v_seen.subjects := coalesce(case when jsonb_typeof(v_next.value -> 'subjects') = 'array'
                                   then array(select jsonb_array_elements_text(v_next.value -> 'subjects')) end, v_inc.subjects);
  v_applies := coalesce((one.fix_plan(p_run.fix_id, v_seen) ->> 'applies')::boolean, false)
               or (p_run.fix_id = 'FIX-N8N-RETRY' and jsonb_array_length(coalesce(v_next.value -> 'retries_15m', '[]')) > 0);
  if not v_applies then
    perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'done', false, p_run.target,
                           jsonb_build_object('held', true, 'judged_by', v_next.id, 'why', format('%s still fails, for another reason', v_inc.check_id)),
                           'one', p_run.run_key);
    return 'held';
  end if;
  if exists (select 1 from one.actions a where a.step = 'verify' and a.incident_id = p_run.incident_id
                and a.result ->> 'judged_by' = v_next.id::text and coalesce((a.result ->> 'escalated')::boolean, false)) then
    v_esc := jsonb_build_object('escalated', false, 'why', 'already escalated on this failing run');
  else
    v_esc := one.incident_escalate(v_inc.id, format('%s ran at %s and %s failed again', p_run.fix_id, p_run.ran_at, v_inc.check_id));
  end if;
  perform one.fix_record(p_run.fix_id, p_run.incident_id, 'verify', 'failed', false, p_run.target,
                         jsonb_build_object('held', false, 'judged_by', v_next.id, 'failed_again_at', v_next.ran_at) || v_esc, 'one', p_run.run_key);
  return 'did not hold';
end $$;

-- Every run due, each in its own block: a run that cannot be judged gets a verify row saying why, so it never blocks
-- the others (phase 7 review M7).
create or replace function one.fix_verify_due() returns jsonb
language plpgsql set search_path = '' as $$
declare
  r one.actions;
  v text;
  v_n integer := 0;
begin
  for r in
    select a.* from one.actions a
     where a.step = 'after' and a.status = 'done' and not a.dry_run and a.verify_at <= now()
       and not exists (select 1 from one.actions v where v.run_key = a.run_key and v.step = 'verify')
     order by a.id limit 50
  loop
    begin
      v := one.fix_verify_one(r);
    exception when others then
      perform one.fix_record(r.fix_id, r.incident_id, 'verify', 'skipped', false, r.target,
                             jsonb_build_object('held', null, 'error', left(sqlerrm, 200)), 'one', r.run_key);
      v := 'error';
    end;
    if v is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return jsonb_build_object('verified', v_n);
end $$;

-- The state of the rows an approved run acted on, read from each app's own table: delivered (B2B), done (website), or
-- the app's report on its retries (n8n). ok is null when nothing can be read yet or at all (phase 7 review M4).
create or replace function one.fix_rows_state(p_fix text, p_proposal bigint) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_before one.actions;
  v_after one.actions;
  v_rows bigint[];
  v jsonb;
begin
  select * into v_before from one.actions where proposal_id = p_proposal and step = 'before' order by id desc limit 1;
  select * into v_after from one.actions where proposal_id = p_proposal and step = 'after' order by id desc limit 1;
  if v_after.id is null then
    return jsonb_build_object('ok', null, 'why', 'no report of the run yet', 'wait', true);
  end if;
  case p_fix
    when 'FIX-OUTBOX-B2B' then
      v_rows := array(select x::bigint from jsonb_array_elements_text(coalesce(v_after.result -> 'done', '[]')) x);
      select jsonb_build_object('rows', cardinality(v_rows),
                                'delivered', count(*) filter (where o.status = 'delivered'),
                                'still_sending', count(*) filter (where o.status in ('pending', 'sending', 'failed')),
                                'dead_again', count(*) filter (where o.status = 'dead'),
                                'ok', cardinality(v_rows) > 0 and count(*) filter (where o.status = 'delivered') = cardinality(v_rows),
                                'refused', coalesce(jsonb_array_length(v_after.result -> 'refused'), 0))
        into v from b2b.integration_outbox o where o.id = any (v_rows);
    when 'FIX-OUTBOX-WEB' then
      v_rows := array(select x::bigint from jsonb_array_elements_text(coalesce(v_before.target -> 'rows', '[]')) x);
      select jsonb_build_object('rows', cardinality(v_rows),
                                'done', count(*) filter (where o.status = 'done'),
                                'pending', count(*) filter (where o.status in ('pending', 'processing')),
                                'dead_again', count(*) filter (where o.status = 'dead'),
                                'ok', v_after.status = 'done' and count(*) filter (where o.status = 'done') = cardinality(v_rows))
        into v from public.web_outbox o where o.id = any (v_rows);
    when 'FIX-N8N-RETRY' then
      v := jsonb_build_object('retried', coalesce(jsonb_array_length(v_after.result -> 'retried'), 0),
                              'failed', coalesce(jsonb_array_length(v_after.result -> 'failed'), 0),
                              'skipped', coalesce(jsonb_array_length(v_after.result -> 'skipped'), 0),
                              'ok', v_after.status = 'done' and coalesce(jsonb_array_length(v_after.result -> 'failed'), 0) = 0
                                    and coalesce(jsonb_array_length(v_after.result -> 'skipped'), 0) = 0,
                              'note', 'whether each new execution succeeded shows in WITTY-02');
    else
      v := jsonb_build_object('ok', null, 'why', 'no row state to read for this fix', 'status', v_after.status);
  end case;
  return v;
end $$;

-- An executed approval, checked at its check_due_at (spec §8: "the result is written back to check_result"); one with
-- no report yet waits up to an hour more.
create or replace function one.proposals_verify_due() returns jsonb
language plpgsql set search_path = '' as $$
declare
  p one.proposals;
  v jsonb;
  v_n integer := 0;
begin
  for p in
    select * from one.proposals
     where status = 'applied' and source = 'check' and change ? 'execute' and check_result is null and check_due_at <= now()
     order by id limit 20 for update skip locked
  loop
    begin
      v := one.fix_rows_state(p.change #>> '{execute,fix}', p.id);
      if coalesce((v ->> 'wait')::boolean, false) and now() < p.check_due_at + interval '1 hour' then
        continue;
      end if;
      update one.proposals set check_result = (v - 'wait') || jsonb_build_object('checked_at', now()) where id = p.id;
    exception when others then
      update one.proposals set check_result = jsonb_build_object('checked_at', now(), 'ok', null, 'error', left(sqlerrm, 200)) where id = p.id;
    end;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('proposals_checked', v_n);
end $$;

-- The tick's step ---------------------------------------------------------------------------------------------------

-- The observation window starts on the first tick that reaches the fixes (so it starts with production, D-079).
create or replace function one.fixes_start_window() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_fixes jsonb := coalesce(one.setting('fixes'), '{}');
begin
  if v_fixes ->> 'observation_started_at' is not null then
    return '{}';
  end if;
  perform one.settings_put('fixes', v_fixes || jsonb_build_object('observation_started_at', now()), 'one',
                           'the observation window starts with the first tick that runs the fixes (D-079)');
  return jsonb_build_object('observation_started', now());
end $$;

-- Each fix and each open incident of its checks (synthetic ones aside), the most severe first.
create or replace function one.fixes_pairs() returns table (fix text, incident bigint)
language sql stable set search_path = '' as $$
  select f.id, i.id from one.fixes f join one.incidents i on i.check_id = any (f.checks)
   where i.resolved_at is null and not 'synthetic' = any (i.tags)
   order by i.severity, f.id, i.id
$$;

-- Verification of earlier runs and approvals, each in its own block.
create or replace function one.fixes_verify_safe() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v jsonb := '{}';
begin
  begin
    v := v || one.fix_verify_due();
  exception when others then
    v := v || jsonb_build_object('verify_error', left(sqlerrm, 200));
  end;
  begin
    v := v || one.proposals_verify_due();
  exception when others then
    v := v || jsonb_build_object('proposals_verify_error', left(sqlerrm, 200));
  end;
  return v;
end $$;

-- One fix on one incident for the tick, never raising: the outcome in a word, or "error: …". A lock wait gives up
-- after the checks' lock timeout, and a cancelled statement is caught as well (phase 7 review M8).
create or replace function one.fix_run_safe(p_fix text, p_incident bigint) returns text
language plpgsql set search_path = '' as $$
declare
  v jsonb;
begin
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  v := one.fix_run(p_fix, p_incident, false, 'one');
  return coalesce(v ->> 'status', case when (v ->> 'dry_run')::boolean then 'dry_run' end, v ->> 'skipped',
                  case when v ? 'queued_for_app' then 'queued' end, case when v ? 'proposal' then 'proposal' end,
                  case when v ? 'applies' then 'not applicable' end, 'ran');
exception
  when query_canceled then
    return 'error: cancelled (' || left(sqlerrm, 120) || ')';
  when others then
    return 'error: ' || left(sqlerrm, 160);
end $$;

-- The fix step's report: what each fix did this tick (the quiet outcomes left out), and fixes_error when one failed,
-- so a tick report with an error key shows it (phase 7 review: smoke reads top-level keys).
create or replace function one.fixes_report(p_out jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('fixes', p_out)
         || coalesce((select jsonb_build_object('fixes_error', string_agg(key || ' ' || value, '; ' order by key))
                        from jsonb_each_text(p_out) where value like 'error:%' or key like '%verify_error'
                      having count(*) > 0), '{}')
$$;

-- The fix step in one transaction, for one.tick() by hand.
create or replace function one.fixes_step() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_out jsonb;
  r record;
  v text;
begin
  v_out := one.fixes_start_window() || one.fixes_verify_safe();
  for r in select * from one.fixes_pairs() loop
    begin
      v := one.fix_run_safe(r.fix, r.incident);
    exception when others then
      v := 'error: ' || left(sqlerrm, 160);
    end;
    if v not in ('cooldown', 'not applicable') then
      v_out := v_out || jsonb_build_object(r.fix || '#' || r.incident, v);
    end if;
  end loop;
  return one.fixes_report(v_out);
end $$;

-- The fix step pg_cron runs, after the app call: one transaction for the window and verification, then one per fix
-- and incident, so a slow or failing fix never costs the app call, the others or their action rows (phase 7 review M8).
create or replace procedure one.fixes_job(inout p_report jsonb default null)
language plpgsql as $$
declare
  v_out jsonb;
  r record;
  v text;
begin
  perform pg_catalog.set_config('search_path', '', false);
  v_out := one.fixes_start_window() || one.fixes_verify_safe();
  commit;
  for r in select * from one.fixes_pairs() loop
    v := one.fix_run_safe(r.fix, r.incident);
    if v not in ('cooldown', 'not applicable') then
      v_out := v_out || jsonb_build_object(r.fix || '#' || r.incident, v);
    end if;
    commit;
  end loop;
  p_report := one.fixes_report(v_out);
end $$;

-- 0003's tick by hand, with the fix step after the app call.
create or replace function one.tick() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('one.tick')) then
    return v_report || jsonb_build_object('skipped', 'another tick is running');
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran this minute');
  end if;
  v_report := v_report || one.reap_killed();
  begin
    v_report := v_report || one.run_sql_checks();
  exception when others then v_report := v_report || jsonb_build_object('checks_error', sqlerrm);
  end;
  v_report := v_report || one.alerts_step();
  v_report := v_report || one.tick_app_call();
  begin
    v_report := v_report || one.fixes_step();
  exception when others then v_report := v_report || jsonb_build_object('fixes_error', sqlerrm);
  end;
  begin
    v_report := v_report || jsonb_build_object('events', one.events_refresh());
  exception when others then v_report := v_report || jsonb_build_object('events_error', sqlerrm);
  end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
end $$;

-- 0005's minute job, with the fix step after the app call (step 4b): its own transactions, so the app call and the
-- run's finish time are committed first.
create or replace procedure one.tick_job()
language plpgsql as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now(), 'mode', 'job');
  v_id text;
  v_src record;
  v_fixes jsonb;
begin
  perform pg_catalog.set_config('search_path', '', false);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', coalesce(one.setting('checks') ->> 'transaction_timeout', '30s'), false);
  end if;
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  commit;
  if not pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('one.tick')) then
    return;
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
    commit;
    return;
  end if;
  v_report := v_report || one.reap_killed();
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_id in select one.due_checks(false) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  v_report := v_report || one.alerts_step();
  update one.runs set report = v_report where id = v_run;
  commit;
  v_report := v_report || one.tick_app_call();
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  commit;
  call one.fixes_job(v_fixes);
  v_report := v_report || coalesce(v_fixes, '{}');
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_src in select * from one.events_due() loop
    perform one.mark_source_started(v_src.source);
    commit;
    v_report := jsonb_set(v_report, '{events}', coalesce(v_report -> 'events', '{}') || one.events_copy_safe(v_src.source, v_src.app, v_src.sql));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  for v_id in select one.due_checks(true) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
  commit;
end $$;

-- The app's side (service role) ---------------------------------------------------------------------------------------

-- Up to 10 waiting runs of the app's fixes (FIX-N8N-RETRY, FIX-WEBHOOK-REKICK), each handed out once: a run the app
-- claimed and never reported is closed after 15 minutes as unknown and never handed out again, so no execution is
-- retried twice (phase 7 review M9). A tick's run of a fix switched off since is closed as skipped (review m5);
-- an approved one still runs.
create or replace function one.app_fixes_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v jsonb;
begin
  for r in
    select a.* from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
       and (a.ran_at <= now() - interval '15 minutes'
            or (a.claimed_at is null and a.proposal_id is null and not coalesce((one.setting('fixes') -> a.fix_id ->> 'enabled')::boolean, false)))
     order by a.id limit 50 for update of a skip locked
  loop
    if r.ran_at > now() - interval '15 minutes' then
      perform one.fix_record(r.fix_id, r.incident_id, 'skip', 'skipped', false, r.target,
                             jsonb_build_object('reason', 'switched off before the app ran it'), 'one', r.run_key);
    else
      perform one.fix_record(r.fix_id, r.incident_id, 'after', 'failed', false, r.target,
                             jsonb_build_object('error', case when r.claimed_at is null then 'the app did not run it within 15 minutes'
                                                              else 'the app claimed it and did not report within 15 minutes: outcome unknown' end,
                                                'unknown', r.claimed_at is not null),
                             'one', r.run_key, null, r.proposal_id);
    end if;
  end loop;
  with c as (
    select a.id from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run and a.ran_at > now() - interval '15 minutes' and a.claimed_at is null
       and not exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip'))
     order by a.id limit 10 for update of a skip locked),
  u as (
    update one.actions a set claimed_at = now(), claimed_by = left(p_holder, 120) from c where a.id = c.id
    returning a.id, a.fix_id, a.incident_id, a.target)
  select coalesce(jsonb_agg(jsonb_build_object('action_id', u.id, 'fix_id', u.fix_id, 'incident_id', u.incident_id, 'target', u.target) order by u.id), '[]')
    into v from u;
  return jsonb_build_object('runs', v);
end $$;

-- The app's report on one run it claimed. FIX-N8N-RETRY: {retried, failed, skipped}, done if any was retried.
-- FIX-WEBHOOK-REKICK: p_ok says whether Spark answered; then the kick runs here with the fixer's rights, else nothing
-- is done and the P1 stays.
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
  if not found or a.step <> 'before' or a.dry_run or a.claimed_at is null or a.fix_id not in ('FIX-N8N-RETRY', 'FIX-WEBHOOK-REKICK') then
    raise exception 'action % is not an app fix the app claimed', p_action using errcode = '22023';
  end if;
  if exists (select 1 from one.actions b where b.run_key = a.run_key and b.step in ('after', 'skip')) then
    raise exception 'action % has its report already', p_action using errcode = '22023';
  end if;
  v_cool := coalesce((one.setting('fixes') -> a.fix_id ->> 'cooldown_min')::int, 60);
  if a.fix_id = 'FIX-WEBHOOK-REKICK' and not coalesce(p_ok, false) then
    v_id := one.fix_record(a.fix_id, a.incident_id, 'skip', 'skipped', false, a.target,
                           jsonb_build_object('reason', 'Spark did not answer: nothing done, the P1 stays', 'reachability', v_res), 'one', a.run_key,
                           null, a.proposal_id);
    return jsonb_build_object('status', 'skipped', 'action', v_id);
  end if;
  if a.fix_id = 'FIX-WEBHOOK-REKICK' then
    perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
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

-- Runs an approved proposal a fix opened, once: FIX-OUTBOX-B2B's B2B admin action under the approver's session, or an
-- over-limit fix, each with the fixer's rights, on p_rows (what the approver saw) where they still qualify. Applied,
-- with check_due_at 10 minutes on; a run that did nothing leaves it approved, with check_result saying why.
create or replace function one.proposal_execute(p_id bigint, p_actor text, p_rows jsonb, p_actor_id uuid) returns jsonb
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
  v_res := one.fix_run(v_x ->> 'fix', (v_x ->> 'incident')::bigint, false, p_actor, p_id, coalesce(p_rows, '[]'), p_actor_id);
  if coalesce(v_res ->> 'status', '') = 'done' or v_res ? 'queued_for_app' then
    update one.proposals set status = 'applied', applied_at = now(), check_due_at = now() + interval '10 minutes', check_result = null where id = p_id;
  else
    update one.proposals set check_result = jsonb_build_object('ran', false, 'ok', false, 'checked_at', now(),
                                                               'why', coalesce(v_res ->> 'why_not', v_res ->> 'skipped', 'the run failed'),
                                                               'result', v_res -> 'result')
     where id = p_id;
  end if;
  return jsonb_build_object('executed', true) || v_res;
end $$;

-- 0011's decision. An approved proposal a fix opened runs at once under the approver's session (spec §8), on the rows
-- that were both proposed and shown to the approver: an edit can remove rows, and a refresh after the page was shown
-- cannot add any (phase 7 review M2). Only that run is checked later; other approvals record the decision and the
-- change is made in the app, so nothing sets a check_due_at for them (review M12; D-079).
create or replace function one.ui_proposal_decide(p_id bigint, p_decision text, p_note text default null, p_change jsonb default null,
                                                  p_snooze_days integer default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_p one.proposals;
  v_change jsonb;
  v_rows jsonb;
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
      if v_p.source = 'check' and v_p.change ? 'execute' then
        select coalesce(jsonb_agg(x order by x::text), '[]') into v_rows
          from jsonb_array_elements(coalesce(v_p.change #> '{execute,rows}', '[]')) x
         where jsonb_typeof(v_change #> '{execute,rows}') <> 'array' or (v_change #> '{execute,rows}') @> jsonb_build_array(x);
        update one.proposals
           set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000), check_due_at = null,
               change = v_p.change || jsonb_build_object('approved_rows', v_rows)
                        || case when v_change is distinct from v_p.change then jsonb_build_object('approved_change', v_change) else '{}' end
         where id = p_id;
        v_exec := one.proposal_execute(p_id, v_actor, v_rows, one.uid());
      else
        update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000),
                                 change = v_change, check_due_at = null
         where id = p_id;
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

-- Every fix with its catalogue entry, settings, grants, evidence and open incidents, and the observation window.
-- "runs" counts only runs that acted (a before row and its after row); proposals a fix opened are counted apart
-- (phase 7 review m3). can_enable: the window has ended and the fix has at least one dry run (enable on evidence).
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
                                             'runs', count(*) filter (where a.step = 'after' and b.id is not null),
                                             'failed', count(*) filter (where a.step = 'after' and b.id is not null and a.status = 'failed'),
                                             'proposals', count(distinct a.proposal_id) filter (where a.step in ('after', 'skip') and b.id is null),
                                             'skipped', count(*) filter (where a.step = 'skip'),
                                             'held', count(*) filter (where a.step = 'verify' and a.status = 'done'),
                                             'escalated', count(*) filter (where a.step = 'verify' and a.status = 'failed'),
                                             'last_at', max(a.ran_at))
                     from one.actions a
                     left join lateral (select x.id from one.actions x where x.run_key = a.run_key and x.step = 'before' limit 1) b on true
                    where a.fix_id = f.id),
        'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
                     from (select * from one.actions where fix_id = f.id order by id desc limit 10) a),
        'open_incidents', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'severity', i.severity, 'title', i.title,
                                                                        'stopped', exists (select 1 from one.actions a where a.fix_id = f.id and a.incident_id = i.id
                                                                                              and a.step = 'verify' and a.status = 'failed'))
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
       'by_fix', (select coalesce(jsonb_agg(jsonb_build_object('fix', fix_id, 'dry_runs', d, 'runs', n, 'failed', bad, 'proposals', pr, 'skipped', sk,
                                                               'held', held, 'escalated', esc) order by fix_id), '[]')
                    from (select a.fix_id, count(*) filter (where a.step = 'dry_run') as d,
                                 count(*) filter (where a.step = 'after' and b.id is not null) as n,
                                 count(*) filter (where a.step = 'after' and b.id is not null and a.status = 'failed') as bad,
                                 count(distinct a.proposal_id) filter (where a.step in ('after', 'skip') and b.id is null) as pr,
                                 count(*) filter (where a.step = 'skip') as sk,
                                 count(*) filter (where a.step = 'verify' and a.status = 'done') as held,
                                 count(*) filter (where a.step = 'verify' and a.status = 'failed') as esc
                            from one.actions a
                            left join lateral (select x.id from one.actions x where x.run_key = a.run_key and x.step = 'before' limit 1) b on true
                           where a.ran_at >= v_from and a.ran_at < v_to group by 1) s)));
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
