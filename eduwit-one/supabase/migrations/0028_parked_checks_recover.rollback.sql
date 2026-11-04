-- Rollback of 0028 parked checks recover: restores 0020's one.due_checks() and one.reap_killed() verbatim, re-seeds
-- ONE-01 with the rule 0006 carried before, and puts the checks setting back to the version before 0028's seed when
-- that seed is still the latest version (a later edit by a person stays). The one-time reset of killed_count is not
-- undone: a reset is what a person would have done by hand (D-085).

create or replace function one.due_checks(p_killed boolean default false) returns setof text
language sql stable set search_path = '' as $$
  select c.id from one.checks c left join one.check_state s on s.check_id = c.id
   where c.enabled and c.sql is not null
     and (coalesce(s.killed_count, 0) > 0) = p_killed
     and (s.last_ran_at is null
          or s.last_ran_at < date_trunc('minute', now()) - make_interval(secs => c.cadence_s - 60))
     -- Killed three times in a row: it stops until a person fixes its SQL and resets killed_count (review F3).
     and (not p_killed or (s.killed_count < 3 and s.last_started_at < now() - make_interval(mins => least(10 * s.killed_count, 60))))
   order by s.last_started_at nulls first, c.id
$$;

create or replace function one.reap_killed() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row record;
  v_checks text[] := '{}';
  v_sources text[] := '{}';
begin
  for v_row in
    select s.check_id, s.killed_count from one.check_state s
     where s.last_started_at > coalesce(s.last_ran_at, '-infinity'::timestamptz)
     order by s.check_id
  loop
    perform one.evaluate(v_row.check_id, 'error', null,
      case when v_row.killed_count + 1 >= 3
           then 'killed 3 times: the run started and did not finish each time; it is stopped until its SQL is fixed and one.check_state.killed_count reset (D-085)'
           else 'killed: the run started and did not finish (transaction_timeout, a cancel or a crash); it now runs after the alert step' end, null);
    update one.check_state set killed_count = v_row.killed_count + 1 where check_id = v_row.check_id;
    v_checks := v_checks || v_row.check_id;
  end loop;
  update one.event_watermarks set last_status = 'killed', killed_count = killed_count + 1, updated_at = now(),
         last_error = case when killed_count + 1 >= 3 then 'the copy was killed 3 times: stopped until killed_count is reset (D-085)'
                           else 'the copy started and did not finish; the next batch is half the size' end
   where last_started_at >= updated_at and last_status is distinct from 'killed';
  select coalesce(array_agg(source order by source), '{}') into v_sources from one.event_watermarks where last_status = 'killed' and updated_at = now();
  return case when cardinality(v_checks) + cardinality(v_sources) = 0 then '{}'::jsonb
              else jsonb_build_object('killed_error', jsonb_build_object('checks', to_jsonb(v_checks), 'sources', to_jsonb(v_sources))) end;
end $$;

select one.seed_check(jsonb_build_object(
  'id', 'ONE-01',
  'app', 'one',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 60,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'Eduwit One itself is unwell: tick errors, AI backlog, failed deliveries or AI overspend',
  'description', 'More than fix_failed_acts_max fix acts that failed, or more than ai_failed_tasks_max AI tasks that failed, in 24 h (hardening F16). A tick report in the last 10 min with an _error key (a killed check or event copy included); a tick that started 2 to 15 min ago and never finished its alert step and app call; an event source in error, killed or missing (where missing counts, D-042; m13 of the second review); a check slower than checks.slow_ms in the last 10 min (a statement timeout cannot be armed per check, D-044); more than ai_queue_max AI tasks pending or held past their 10-minute lease; a failed delivery in the last 24 h; AI spend today (one.ai_calls.cost_inr, IST) at or above one.settings.ai.daily_cap_inr, or AI work held back because the day''s cap is reached or the Anthropic API credits are used up (spec §11: ONE-01 fires at 100%; phase 6 review M1; D-078). A cap of 0 means the owner switched the AI off and raises nothing.',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with v as (
  select (select count(*) from one.runs where kind = 'tick' and started_at > now() - interval '10 minutes' and report::text ~ '_error"') as tick_errors_10m,
         (select count(*) from one.runs where kind = 'tick' and finished_at is null
             and started_at between now() - interval '15 minutes' and now() - interval '2 minutes') as ticks_unfinished_15m,
         (select coalesce(jsonb_agg(w.source order by w.source), '[]') from one.event_watermarks w
           where w.last_status in ('error', 'killed')
              or (w.last_status = 'source_missing' and coalesce(((select one.setting('checks')) ->> 'source_missing_opens_incident')::boolean, true))) as event_sources_failing,
         (select coalesce(jsonb_agg(distinct r.check_id), '[]') from one.results r
           where r.ran_at > now() - interval '10 minutes' and r.duration_ms > coalesce(((select one.setting('checks')) ->> 'slow_ms')::int, 5000)) as slow_checks,
         (select count(*) from one.ai_tasks
           where status = 'pending' or (status = 'claimed' and claimed_at < now() - interval '10 minutes')) as ai_pending,
         (select count(*) from one.ai_tasks
           where status = 'deferred' and (deferred_reason like 'budget (cap reached)%' or deferred_reason like 'budget (credits exhausted)%')) as ai_held_at_cap,
         (select count(*) from one.deliveries where status = 'failed' and created_at > now() - interval '24 hours') as deliveries_failed_24h,
         (select one.ai_spent_today()) as ai_spent_inr_today,
         (select count(*) from one.actions where step = 'after' and status = 'failed' and not dry_run and ran_at > now() - interval '24 hours') as fix_acts_failed_24h,
         (select count(*) from one.ai_tasks where status = 'failed' and created_at > now() - interval '24 hours') as ai_failed_24h,
         ((select one.setting('ai')) ->> 'daily_cap_inr')::numeric as ai_cap_inr)
select tick_errors_10m = 0 and ticks_unfinished_15m = 0 and jsonb_array_length(event_sources_failing) = 0
       and jsonb_array_length(slow_checks) = 0 and ai_pending <= (select one.threshold('ai_queue_max')) and deliveries_failed_24h = 0
       and fix_acts_failed_24h <= (select one.threshold('fix_failed_acts_max')) and ai_failed_24h <= (select one.threshold('ai_failed_tasks_max'))
       and (coalesce(ai_cap_inr, 0) = 0 or (ai_spent_inr_today < ai_cap_inr and ai_held_at_cap = 0)) as ok, to_jsonb(v) as value
  from v
$sql$));

do $$
declare
  v_row one.settings;
  v_prev one.settings_versions;
begin
  select * into v_row from one.settings where key = 'checks';
  if found and v_row.actor = 'seed'
     and exists (select 1 from one.settings_versions where key = 'checks' and version = v_row.version and reason like 'D-102 (0028)%') then
    select * into v_prev from one.settings_versions where key = 'checks' and version = v_row.version - 1;
    if found then
      perform one.settings_put('checks', v_prev.value, 'seed', 'rollback of 0028: the version before D-102');
    end if;
  end if;
end $$;

call one.apply_grants();
