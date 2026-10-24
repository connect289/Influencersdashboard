-- 0020 hardening: the AI's set-up and running tools (D-083) and the fixes' proof-before-power rules (D-084). Redefines one.ai_tool_data (0018) with five more read-only
-- tools for Ask: setup (the Setup catalogue with each item's state), app_status (one app's heartbeats, checks, open
-- incidents, cron jobs, fixes and tests), fixes (the catalogue with counts and recent rows), actions (fix rows) and
-- audit (who changed what, without the values). Everything still runs inside one.ai_tool's read-only transaction and
-- through one.redact. The runbook and operate tools live in the app (lib/ai/worker.ts), from the generated docs module.

create or replace function one.ai_tool_data(p_name text, p_args jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  a jsonb := case when jsonb_typeof(p_args) = 'object' then p_args else '{}' end;
  v_hours integer := least(greatest(coalesce((a ->> 'since_hours')::int, 168), 1), 720);
  v_limit integer := least(greatest(coalesce((a ->> 'limit')::int, 20), 1), 50);
  v_days integer := least(greatest(coalesce((a ->> 'days')::int, 7), 1), 90);
  v jsonb;
begin
  case p_name
    when 'incidents' then
      select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'severity', i.severity, 'title', i.title,
                                                   'opened_at', i.opened_at, 'resolved_at', i.resolved_at, 'resolution', i.resolution,
                                                   'occurrences', i.occurrences, 'acknowledged', i.acknowledged_at is not null, 'summary', i.summary,
                                                   'value', i.evidence -> 'value') order by i.opened_at desc), '[]')
        into v
        from (select * from one.incidents i
               where i.check_id <> 'ONE-SYNTH'
                 and (a ->> 'app' is null or i.app = a ->> 'app')
                 and (a ->> 'check_id' is null or i.check_id = a ->> 'check_id')
                 and (a ->> 'severity' is null or i.severity::text = a ->> 'severity')
                 and case coalesce(a ->> 'status', 'open')
                       when 'open' then i.resolved_at is null
                       when 'resolved' then i.resolved_at is not null and i.opened_at > now() - make_interval(hours => v_hours)
                       else i.resolved_at is null or i.opened_at > now() - make_interval(hours => v_hours) end
               order by i.opened_at desc limit v_limit) i;
    when 'incident' then
      v := one.ai_incident_context((a ->> 'id')::bigint, 'triage');
    when 'check' then
      select jsonb_build_object('check', jsonb_build_object('id', c.id, 'app', c.app, 'title', c.title, 'description', c.description, 'kind', c.kind,
                                                            'severity', c.severity, 'cadence_s', c.cadence_s, 'enabled', c.enabled,
                                                            'disabled_reason', c.disabled_reason, 'tags', to_jsonb(c.tags)),
                                'last_results', (select coalesce(jsonb_agg(jsonb_build_object('at', r.ran_at, 'status', r.status, 'value', r.value,
                                                                                              'error', left(r.error, 200)) order by r.ran_at desc), '[]')
                                                   from (select * from one.results where check_id = c.id order by ran_at desc limit 20) r))
        into v from one.checks c where c.id = a ->> 'check_id';
      if v is null then
        raise exception 'no check %', a ->> 'check_id' using errcode = 'P0002';
      end if;
    when 'checks_failing' then
      select coalesce(jsonb_agg(jsonb_build_object('check_id', x.check_id, 'app', x.app, 'severity', x.severity, 'title', x.title, 'status', x.status,
                                                   'at', x.ran_at, 'value', x.value) order by x.severity, x.check_id), '[]')
        into v
        from (select distinct on (r.check_id) r.check_id, r.status, r.ran_at, r.value, c.app, c.severity, c.title
                from one.results r join one.checks c on c.id = r.check_id
               where c.enabled and r.ran_at > now() - interval '1 day' and (a ->> 'app' is null or c.app = a ->> 'app')
               order by r.check_id, r.ran_at desc) x
       where x.status <> 'ok';
    when 'tests' then
      select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'app', t.app, 'title', t.title, 'enabled', t.enabled, 'needs', to_jsonb(t.needs),
                                                   'last_runs', (select coalesce(jsonb_agg(jsonb_build_object('at', r.started_at, 'ok', r.ok, 'error', r.error,
                                                                                                              'failed_steps', (select coalesce(jsonb_agg(s ->> 'key'), '[]')
                                                                                                                                 from jsonb_array_elements(r.step_results) s
                                                                                                                                where (s ->> 'ok')::boolean is false))
                                                                                          order by r.started_at desc), '[]')
                                                                   from (select * from one.test_runs r where r.test_id = t.id order by started_at desc limit 5) r))
                                order by t.id), '[]')
        into v from one.tests t where a ->> 'test_id' is null or t.id = a ->> 'test_id';
    when 'events' then
      select coalesce(jsonb_agg(jsonb_build_object('bucket', b, 'app', app, 'type', type, 'n', n) order by b desc, n desc), '[]')
        into v
        from (select date_trunc(case when a ->> 'bucket' = 'hour' then 'hour' else 'day' end, occurred_at at time zone 'Asia/Kolkata') as b,
                     app, type, count(*) as n
                from one.events
               where occurred_at > now() - make_interval(hours => least(v_hours, 24 * 14))
                 and (a ->> 'app' is null or app = a ->> 'app')
                 and (a ->> 'type' is null or type = a ->> 'type')
               group by 1, 2, 3 order by 1 desc, 4 desc limit 200) s;
    when 'analytics' then
      v := one.analytics_data(v_days);
    when 'marketing' then
      v := one.marketing_data(v_days);
    when 'witty' then
      if coalesce(a ->> 'panel', '') not in ('replies', 'outbox', 'digest', 'health_alerts', 'learnings', 'n8n') then
        raise exception 'panel is one of replies, outbox, digest, health_alerts, learnings, n8n' using errcode = '22023';
      end if;
      v := one.embed_data('witty.' || (a ->> 'panel'));
      perform set_config('search_path', '', true);
    when 'health' then
      v := jsonb_build_object('one', one.health(),
                              'heartbeats', (select coalesce(jsonb_agg(jsonb_build_object('component', h.component) || one.heartbeat_state(h.component)
                                                                       order by h.component), '[]') from one.heartbeats h));
      begin v := v || jsonb_build_object('b2b', b2b.health_check()); exception when others then v := v || jsonb_build_object('b2b_error', left(sqlerrm, 160)); end;
      begin v := v || jsonb_build_object('website', public.web_health()); exception when others then v := v || jsonb_build_object('website_error', left(sqlerrm, 160)); end;
      begin v := v || jsonb_build_object('influencer', one.inf_health()); exception when others then v := v || jsonb_build_object('influencer_error', left(sqlerrm, 160)); end;
    when 'cron' then
      select coalesce(jsonb_agg(to_jsonb(s) order by s.failed desc, s.job), '[]')
        into v
        from (select j.jobname as job, count(*) as runs, count(*) filter (where d.status = 'failed') as failed,
                     max(d.start_time) filter (where d.status = 'failed') as last_failed_at,
                     left((array_agg(d.return_message order by d.start_time desc) filter (where d.status = 'failed'))[1], 200) as last_failure
                from cron.job_run_details d join cron.job j on j.jobid = d.jobid
               where d.start_time > now() - make_interval(hours => least(v_hours, 48))
               group by j.jobname) s;
    when 'ai_spend' then
      select coalesce(jsonb_agg(to_jsonb(s) order by s.day desc, s.model), '[]')
        into v
        from (select (created_at at time zone 'Asia/Kolkata')::date as day, provider, model, count(*) as calls, count(*) filter (where not ok) as failed,
                     sum(cost_inr) as inr, sum(input_tokens) as input_tokens, sum(output_tokens) as output_tokens
                from one.ai_calls where created_at > now() - make_interval(days => least(v_days, 30)) group by 1, 2, 3) s;
    when 'proposals' then
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'app', p.app, 'title', p.title, 'status', p.status, 'risk', p.risk,
                                                   'source', p.source, 'created_at', p.created_at) order by p.id desc), '[]')
        into v
        from (select * from one.proposals where status = coalesce(a ->> 'status', 'open') order by id desc limit v_limit) p;
    when 'deliveries' then
      select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
        into v
        from (select kind, status, count(*) as n from one.deliveries where created_at > now() - make_interval(hours => v_hours) group by 1, 2) s;
    -- Set-up and running (hardening, D-083): what each app needs, how it stands, what the fixes did, who changed what.
    when 'setup' then
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.item ->> 'id', 'title', c.item ->> 'title', 'who', c.item ->> 'who', 'how', c.item ->> 'how',
               'unblocks', c.item -> 'unblocks',
               'status', case when coalesce((s ->> 'validated')::boolean, false) then 'validated' else coalesce(s ->> 'status', 'unfilled') end,
               'validated_at', s ->> 'validated_at', 'detail', s ->> 'detail', 'fix', case when coalesce((s ->> 'validated')::boolean, false) then null else s ->> 'fix' end,
               'secrets', (select coalesce(jsonb_agg(jsonb_build_object('name', m[1], 'present', exists (select 1 from one.vault_names() vn where vn = m[1]))), '[]')
                             from regexp_matches(c.item ->> 'stores', 'vault:([a-z0-9_]+)', 'g') m),
               'checks_waiting', (select coalesce(jsonb_agg(k.id order by k.id), '[]') from one.checks k where k.disabled_reason = 'setup:' || (c.item ->> 'id')))
             order by c.ord), '[]')
        into v
        from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) with ordinality c(item, ord)
             left join lateral (select coalesce(one.setting('setup') -> 'items' -> (c.item ->> 'id'), '{}') as s) st on true
       where a ->> 'item' is null or c.item ->> 'id' = a ->> 'item';
    when 'app_status' then
      if coalesce(a ->> 'app', '') not in ('witty', 'b2b', 'b2c', 'web', 'influencer', 'one', 'platform', 'catalogue', 'integrity') then
        raise exception 'app is one of witty, b2b, b2c, web, influencer, one, platform, catalogue, integrity' using errcode = '22023';
      end if;
      v := jsonb_build_object(
        'app', a ->> 'app',
        'heartbeats', (select coalesce(jsonb_agg(jsonb_build_object('component', substr(c.id, 4), 'enabled', c.enabled, 'disabled_reason', c.disabled_reason)
                                                 || one.heartbeat_state(substr(c.id, 4)) order by c.id), '[]')
                         from one.checks c where c.kind = 'heartbeat' and c.app = a ->> 'app'),
        'checks', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'title', c.title, 'severity', c.severity, 'enabled', c.enabled,
                                                                'disabled_reason', c.disabled_reason, 'last_status', s.last_status, 'last_ran_at', s.last_ran_at,
                                                                'muted', one.is_muted(c.id, c.app)) order by c.id), '[]')
                     from one.checks c left join one.check_state s on s.check_id = c.id where c.app = a ->> 'app' and c.kind <> 'heartbeat'),
        'open_incidents', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'severity', i.severity, 'title', i.title,
                                                                        'opened_at', i.opened_at, 'acknowledged', i.acknowledged_at is not null) order by i.severity, i.opened_at), '[]')
                             from one.incidents i where i.app = a ->> 'app' and i.resolved_at is null and i.check_id <> 'ONE-SYNTH'),
        'cron_jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'last', r.status, 'at', r.start_time,
                                                                   'error', case when r.status = 'failed' then left(r.return_message, 160) end) order by j.jobname), '[]')
                        from cron.job j left join lateral (select d.status, d.start_time, d.return_message from cron.job_run_details d
                                                            where d.jobid = j.jobid and d.status in ('succeeded', 'failed')
                                                              and d.runid > (select coalesce(max(x.runid), 0) - 100000 from cron.job_run_details x)
                                                            order by d.runid desc limit 1) r on true
                       where j.jobname like case a ->> 'app' when 'b2b' then 'b2b-%' when 'b2c' then 'b2c-%' when 'influencer' then 'inf%' when 'one' then 'one-%' else '' end),
        'fixes', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'mode', f.mode, 'title', f.title, 'checks', to_jsonb(f.checks),
                                                               'enabled', coalesce((one.setting('fixes') -> f.id ->> 'enabled')::boolean, false),
                                                               'last_row', (select jsonb_build_object('step', x.step, 'status', x.status, 'dry_run', x.dry_run, 'at', x.ran_at,
                                                                                                      'would', x.result ->> 'would', 'reason', x.result ->> 'reason')
                                                                              from one.actions x where x.fix_id = f.id order by x.id desc limit 1)) order by f.id), '[]')
                    from one.fixes f where f.app = a ->> 'app'),
        'tests', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'enabled', t.enabled, 'disabled_reason', t.disabled_reason,
                                                               'needs', to_jsonb(t.needs),
                                                               'last_run', (select jsonb_build_object('at', r.started_at, 'ok', r.ok) from one.test_runs r
                                                                             where r.test_id = t.id order by r.started_at desc limit 1)) order by t.id), '[]')
                    from one.tests t where t.app = a ->> 'app'));
    when 'fixes' then
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', f.id, 'app', f.app, 'title', f.title, 'checks', to_jsonb(f.checks), 'trigger', f.trigger, 'mode', f.mode, 'what', f.what,
               'grants', f.grants, 'rollback', f.rollback,
               'settings', coalesce(one.setting('fixes') -> f.id, '{}'),
               'counts', (select jsonb_build_object('dry_runs', count(*) filter (where x.step = 'dry_run'),
                                                    'runs', count(*) filter (where x.step = 'after' and not x.dry_run and x.result ? 'proposal' = false),
                                                    'failed', count(*) filter (where x.step = 'after' and x.status = 'failed'),
                                                    'skipped', count(*) filter (where x.step = 'skip'),
                                                    'held', count(*) filter (where x.step = 'verify' and x.status = 'done'),
                                                    'did_not_hold', count(*) filter (where x.step = 'verify' and x.status = 'failed'),
                                                    'last_at', max(x.ran_at))
                            from one.actions x where x.fix_id = f.id),
               'recent', (select coalesce(jsonb_agg(jsonb_build_object('step', x.step, 'status', x.status, 'dry_run', x.dry_run, 'at', x.ran_at, 'incident_id', x.incident_id,
                                                                       'by', x.ran_by, 'would', x.result ->> 'would', 'reason', x.result ->> 'reason',
                                                                       'held', x.result -> 'held', 'count', x.target -> 'count') order by x.id desc), '[]')
                            from (select * from one.actions where fix_id = f.id order by id desc limit 5) x)) order by f.id), '[]')
        into v from one.fixes f where a ->> 'fix_id' is null or f.id = a ->> 'fix_id';
    when 'actions' then
      select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'fix_id', x.fix_id, 'incident_id', x.incident_id, 'app', x.app, 'step', x.step, 'status', x.status,
                                                   'dry_run', x.dry_run, 'at', x.ran_at, 'by', x.ran_by, 'count', x.target -> 'count',
                                                   'would', x.result ->> 'would', 'reason', x.result ->> 'reason', 'held', x.result -> 'held', 'error', left(x.result ->> 'error', 160))
                                order by x.id desc), '[]')
        into v
        from (select * from one.actions
               where ran_at > now() - make_interval(hours => v_hours) and (a ->> 'fix_id' is null or fix_id = a ->> 'fix_id')
               order by id desc limit v_limit) x;
    when 'audit' then
      select coalesce(jsonb_agg(jsonb_build_object('at', x.at, 'actor', x.actor, 'action', x.action, 'target', x.target) order by x.id desc), '[]')
        into v
        from (select * from one.audit
               where at > now() - make_interval(hours => v_hours) and (a ->> 'action' is null or action like (a ->> 'action') || '%')
               order by id desc limit v_limit) x;
    else
      raise exception 'unknown tool %', p_name using errcode = '22023';
  end case;
  return one.redact(v, one.pii_keys());
end $$;

-- The worker reaches the Ask tools above through one.ai_tool(bigint,text,text,jsonb) (0018): no grant for them.

-- Proof before power (owner, 24 Oct; D-084) --------------------------------------------------------------------------
-- A fix applies itself to an app only once it has shown it works: a newly switched-on fix acts on one row (a trial)
-- until a real run of it has held; no second real run on an incident before the verdict on the last one; and a fix
-- whose runs did not hold twice within 7 days pauses itself (dry runs only) until the owner clears it.

create table one.fix_state (
  fix_id text primary key references one.fixes (id),
  paused_at timestamptz,
  paused_reason text,
  paused_by text,
  cleared_at timestamptz,
  cleared_by text,
  cleared_reason text,
  updated_at timestamptz not null default now()
);
comment on table one.fix_state is 'The breaker state of each fix (D-084): paused by its own failures, cleared by the owner.';

-- Why a fix is paused, or null.
create or replace function one.fix_paused_reason(p_fix text) returns text
language sql stable set search_path = '' as $$
  select s.paused_reason from one.fix_state s where s.fix_id = p_fix and s.paused_at is not null and s.cleared_at is null
$$;

-- A fix is proven once a real run of it held (its check passed at the first run after the act, or the incident
-- resolved) within the last 30 days.
create or replace function one.fix_proven(p_fix text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from one.actions a
                  where a.fix_id = p_fix and a.step = 'verify' and a.status = 'done' and coalesce((a.result ->> 'held')::boolean, false)
                    and a.ran_at > now() - interval '30 days')
$$;

-- Pauses a fix (idempotent while it is paused); true when this call paused it.
create or replace function one.fix_pause(p_fix text, p_reason text, p_by text default 'one') returns boolean
language plpgsql set search_path = '' as $$
begin
  insert into one.fix_state (fix_id, paused_at, paused_reason, paused_by)
  values (p_fix, now(), left(p_reason, 300), left(p_by, 120))
  on conflict (fix_id) do update
    set paused_at = now(), paused_reason = left(p_reason, 300), paused_by = left(p_by, 120),
        cleared_at = null, cleared_by = null, cleared_reason = null, updated_at = now()
    where one.fix_state.paused_at is null or one.fix_state.cleared_at is not null;
  return found;
end $$;

-- The breaker: two runs of a fix that did not hold within 7 days pause it.
create or replace function one.fix_breaker(p_fix text) returns boolean
language plpgsql set search_path = '' as $$
declare
  v_n integer;
begin
  select count(*) into v_n from one.actions a
   where a.fix_id = p_fix and a.step = 'verify' and a.status = 'failed' and a.ran_at > now() - interval '7 days';
  if v_n >= 2 then
    return one.fix_pause(p_fix, format('%s runs did not hold within 7 days', v_n));
  end if;
  return false;
end $$;

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
  v_trial boolean := false;
  v_paused text;
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
  -- Paused by its breaker (D-084): dry runs only, like switched off, until the owner clears it.
  v_paused := one.fix_paused_reason(p_fix);
  v_dry := p_approval is null
           and (p_dry_run or not coalesce((v_cfg ->> 'enabled')::boolean, false) or v_paused is not null
                or (one.fix_window() ->> 'running')::boolean);
  -- A run on this incident did not hold: the incident went up a level instead of a retry (spec §8), and the fix stays
  -- off it; only an approval runs it again, and a person may still ask for a dry run (phase 7 review M10).
  if p_approval is null and not (v_dry and p_by <> 'one')
     and exists (select 1 from one.actions a where a.fix_id = p_fix and a.incident_id = p_incident and a.step = 'verify' and a.status = 'failed') then
    return jsonb_build_object('fix', p_fix, 'skipped', 'stopped: a run on this incident did not hold');
  end if;
  -- Proof before power (D-084): no second real run on an incident before the verdict on the last one (held, did not
  -- hold, or unverified), so a fix never repeats what it is not yet sure of.
  if p_approval is null and not v_dry
     and exists (select 1 from one.actions a
                  where a.fix_id = p_fix and a.incident_id = p_incident and a.step = 'after' and not a.dry_run and a.status = 'done'
                    and a.verify_at is not null
                    and not exists (select 1 from one.actions v where v.run_key = a.run_key and v.step = 'verify')) then
    return jsonb_build_object('fix', p_fix, 'skipped', 'waiting for the verdict on its last run');
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
                                                                         'test_rows_left_out', coalesce(v_plan -> 'test_rows', '0'), 'trial', false);
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
  -- Proof before power (D-084): until a real run of this fix has held (within 30 days), a real run within the limit acts
  -- on one row only; the check's verdict on that trial is what earns it its configured limit. A proposal (over the limit
  -- above, or a proposing or approval fix below) shows the owner the whole plan, and an approved run is the owner's and
  -- runs whole.
  if not v_dry and p_approval is null and v_f.mode not in ('propose', 'approve')
     and jsonb_typeof(v_plan -> 'rows') = 'array' and jsonb_array_length(v_plan -> 'rows') > 1 and not one.fix_proven(p_fix) then
    v_plan := one.fix_plan_within(v_plan, jsonb_build_array(v_plan -> 'rows' -> 0)) || jsonb_build_object('trial', true);
    v_trial := true;
    v_target := coalesce(v_plan -> 'target', '{}') || jsonb_build_object('rows', v_plan -> 'rows', 'count', v_plan -> 'count',
                                                                           'test_rows_left_out', coalesce(v_plan -> 'test_rows', '0'), 'trial', true);
  end if;
  if v_dry then
    v_id := one.fix_record(p_fix, p_incident, 'dry_run', 'planned', true, v_target,
                           jsonb_build_object('would', v_plan ->> 'would', 'mode', v_f.mode,
                                              'why_dry', case when p_dry_run then 'asked for a dry run'
                                                              when v_paused is not null then 'paused: ' || v_paused
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
  -- Proof before power (D-084): a second run of this fix that did not hold within 7 days pauses the fix until the owner
  -- clears it on Settings → Fixes; ONE-FIXES opens an incident while it is paused.
  perform one.fix_breaker(p_run.fix_id);
  return 'did not hold';
end $$;

-- The Fixes page: each fix's proof state (proven, trial, paused, runs awaiting their verdict).
create or replace function one.ui_fix_states() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'fix_id', f.id,
      'proven', one.fix_proven(f.id),
      'proven_at', (select max(a.ran_at) from one.actions a
                     where a.fix_id = f.id and a.step = 'verify' and a.status = 'done' and coalesce((a.result ->> 'held')::boolean, false)),
      'paused', s.paused_at is not null and s.cleared_at is null,
      'paused_at', case when s.cleared_at is null then s.paused_at end,
      'paused_reason', case when s.cleared_at is null then s.paused_reason end,
      'did_not_hold_7d', (select count(*) from one.actions a
                           where a.fix_id = f.id and a.step = 'verify' and a.status = 'failed' and a.ran_at > now() - interval '7 days'),
      'awaiting_verdict', (select coalesce(jsonb_agg(a.incident_id order by a.id), '[]') from one.actions a
                            where a.fix_id = f.id and a.step = 'after' and not a.dry_run and a.status = 'done' and a.verify_at is not null
                              and not exists (select 1 from one.actions v where v.run_key = a.run_key and v.step = 'verify'))) order by f.id), '[]')
    from one.fixes f left join one.fix_state s on s.fix_id = f.id);
end $$;

-- The owner clears a paused fix, with a reason, after reading what went wrong.
create or replace function one.ui_fix_unpause(p_fix text, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
begin
  select to_jsonb(s) into v_before from one.fix_state s where s.fix_id = p_fix and s.paused_at is not null and s.cleared_at is null;
  if v_before is null then
    raise exception 'fix % is not paused', p_fix using errcode = 'P0002';
  end if;
  update one.fix_state set cleared_at = now(), cleared_by = v_actor, cleared_reason = v_reason, updated_at = now() where fix_id = p_fix;
  perform one.ui_audit_write(v_actor, 'fix.unpause', 'fix:' || p_fix, v_before, jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.ui_fix_states()', 'authenticated', 'Fixes page (0020): proven, trial, paused and awaiting-verdict state per fix'),
  ('one.ui_fix_unpause(text,text,text)', 'authenticated', 'Fixes page (0020): the owner clears a fix its breaker paused')
on conflict do nothing;
-- >>> hardening batch (self-healing, security, efficiency)
-- Self-healing, security and efficiency (reviews of 24 Oct; D-085, D-086, D-087) ----------------------------------------

-- Reopens are counted by the storm guard and damped when a check flaps (review F4).
alter table one.incidents add column reopened_at timestamptz;
-- A copy killed three times stops, with a halved batch each time (review F3).
alter table one.event_watermarks add column killed_count integer not null default 0;

-- Indexes the per-minute readers and the pages were missing (efficiency review 4, 2b, 6, 7, 15, 11, 3).
create index runs_kind_started_idx on one.runs (kind, started_at desc);
create index runs_kind_finished_idx on one.runs (kind, finished_at desc);
create index actions_fix_incident_idx on one.actions (fix_id, incident_id, step);
create index actions_before_idx on one.actions (ran_at) where step = 'before' and not dry_run;
create index audit_target_idx on one.audit (target, id);
create index incidents_opened_idx on one.incidents (opened_at desc);
create index events_app_time_idx on one.events (app, occurred_at desc);
create index events_app_type_time_idx on one.events (app, type, occurred_at);
-- Rows rewritten many times a minute stay HOT updates (efficiency review 12).
alter table one.runs set (fillfactor = 70);
alter table one.check_state set (fillfactor = 70);
alter table one.event_watermarks set (fillfactor = 50);

-- Append-only histories, enforced (security review m4): the audit, settings versions, the sign-in log and check results
-- refuse UPDATE and DELETE unless the session says it is a retention step (one.retention sets one.history_writer).
create or replace function one.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('one.history_writer', true), '') = 'on' then
    return coalesce(new, old);
  end if;
  raise exception 'one.%: history is append-only (D-085)', tg_table_name using errcode = '42501';
end $$;
create trigger forbid_mutation before update or delete on one.audit for each row execute function one.forbid_mutation();
create trigger forbid_mutation before update or delete on one.settings_versions for each row execute function one.forbid_mutation();
create trigger forbid_mutation before update or delete on one.sign_in_log for each row execute function one.forbid_mutation();
create trigger forbid_mutation before update or delete on one.results for each row execute function one.forbid_mutation();

-- Contact data inside free text (an app's error message, a libpq DETAIL line): phones and emails masked, the rest kept,
-- so a diagnostic stays readable (security review M1). one.redact() masks whole strings; this keeps the words around.
create or replace function one.mask_text(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null when p !~ '[0-9@]' then p else
    regexp_replace(
      regexp_replace(
        regexp_replace(p, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
        '(\+?91[\s-]?)?[6-9][0-9]{4}[\s-]?[0-9]{5}(?![0-9])', '[phone]', 'g'),
      '(?<![0-9])[0-9]{11,15}(?![0-9])', '[phone]', 'g') end
$$;

-- A JSON value with every string masked by one.mask_text and phone-shaped numbers masked; keys and structure kept.
create or replace function one.mask_json(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
begin
  case jsonb_typeof(p)
    when 'object' then
      return (select coalesce(jsonb_object_agg(e.key, one.mask_json(e.value)), '{}'::jsonb) from jsonb_each(p) e);
    when 'array' then
      return (select coalesce(jsonb_agg(one.mask_json(a.value) order by a.ord), '[]'::jsonb) from jsonb_array_elements(p) with ordinality a(value, ord));
    when 'string' then
      return to_jsonb(one.mask_text(p #>> '{}'));
    when 'number' then
      if p::text ~ '^[0-9]{10,15}$' then
        return '"[phone]"'::jsonb;
      end if;
      return p;
    else
      return p;
  end case;
end $$;

-- Who holds the tick's session lock for longer than p_min_age, other than this session and of this role; null when
-- nobody does (review F2). pg_try_advisory_lock(hashtext(...)) takes the bigint form: pg_locks shows it with objsubid 1,
-- classid the key's high half (0, or 4294967295 for a negative hash) and objid its low half as an unsigned int.
create or replace function one.tick_lock_holder(p_min_age interval) returns integer
language sql stable set search_path = '' as $$
  select a.pid from pg_catalog.pg_locks l join pg_catalog.pg_stat_activity a on a.pid = l.pid
   where l.locktype = 'advisory' and l.objsubid = 1 and l.granted
     and l.classid = case when pg_catalog.hashtext('one.tick') < 0 then 4294967295 else 0 end::oid
     and l.objid = ((pg_catalog.hashtext('one.tick')::bigint + 4294967296) % 4294967296)::oid
     and a.pid <> pg_catalog.pg_backend_pid() and a.usename = current_user
     and coalesce(a.xact_start, a.backend_start) < now() - p_min_age
   order by a.backend_start limit 1
$$;

create or replace function one.evaluate(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_state one.check_state;
  v_open bigint;
  v_severity one.severity;
  v_failing boolean;
  v_subjects text[];
  -- Check values and errors carry app text; contact data in them is masked before anything stores or shows it (M1).
  v_red jsonb := one.mask_json(p_value);
  v_err text := one.mask_text(left(p_error, 1000));
begin
  select * into strict v_check from one.checks where id = p_check_id;
  v_failing := p_status in ('fail', 'error')
               or (p_status = 'source_missing' and coalesce((one.setting('checks') ->> 'source_missing_opens_incident')::boolean, true));
  insert into one.results (check_id, status, value, error, duration_ms) values (p_check_id, p_status, v_red, v_err, p_duration_ms);
  insert into one.check_state (check_id) values (p_check_id) on conflict do nothing;
  update one.check_state set
    last_ran_at = now(), last_status = p_status, killed_count = 0,
    consecutive_fail = case when v_failing then consecutive_fail + 1 when p_status = 'ok' then 0 else consecutive_fail end,
    consecutive_ok = case when p_status = 'ok' then consecutive_ok + 1 when v_failing then 0 else consecutive_ok end
   where check_id = p_check_id
   returning * into v_state;
  select id into v_open from one.incidents where check_id = p_check_id and resolved_at is null;
  if v_failing and v_state.consecutive_fail >= v_check.open_after then
    v_severity := case when p_status = 'fail' then coalesce(nullif(p_value ->> 'severity', '')::one.severity, v_check.severity) else v_check.severity end;
    v_subjects := case when p_status = 'fail' and jsonb_typeof(p_value -> 'subjects') = 'array'
                       then array(select jsonb_array_elements_text(p_value -> 'subjects')) else '{}' end;
    perform one.open_or_touch_incident(p_check_id, v_severity,
      jsonb_build_object('status', p_status, 'value', v_red, 'error', left(v_err, 300), 'at', now()), v_subjects);
    return case when v_open is null then 'opened' else 'touched' end;
  end if;
  if p_status = 'ok' and v_open is not null and v_state.consecutive_ok >= v_check.resolve_after then
    perform one.resolve_incident(v_open, 'one', 'recovered');
    return 'resolved';
  end if;
  return 'none';
end $$;

create or replace function one.claim_deliveries(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_out jsonb := '[]';
  v_row record;
begin
  update one.deliveries d set status = case when i.alert_state = 'muted' then 'muted' else 'suppressed' end
    from one.incidents i
   where d.incident_id = i.id and d.status = 'pending' and d.channel = 'email'
     and (i.resolved_at is not null or i.alert_state in ('muted', 'suppressed')
          or (d.kind = 'escalation' and i.acknowledged_at is not null));
  for v_row in
    with c as (
      select d.id from one.deliveries d
       where d.channel = 'email'
         and ((d.status = 'pending' and d.next_attempt_at <= now()) or (d.status = 'sending' and d.claimed_at < now() - interval '5 minutes'))
       order by d.created_at limit least(greatest(p_limit, 1), 100) for update skip locked)
    update one.deliveries d set status = 'sending', claimed_at = now() from c where d.id = c.id
    returning d.id, d.incident_id, d.brief_id, d.recipient, d.kind, d.escalation_level, d.attempts, d.idempotency_key
  loop
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row.id, 'recipient', v_row.recipient, 'kind', v_row.kind, 'escalation_level', v_row.escalation_level,
      'attempts', v_row.attempts, 'idempotency_key', v_row.idempotency_key,
      'incident', (select jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'severity', i.severity, 'title', i.title,
                                             'opened_at', i.opened_at, 'occurrences', i.occurrences, 'reopened_count', i.reopened_count,
                                             'subjects', to_jsonb(i.subjects), 'summary', i.summary, 'value', one.mask_json(i.evidence -> 'value'),
                                             'status', i.evidence ->> 'status', 'error', one.mask_text(i.evidence ->> 'error'))
                     from one.incidents i where i.id = v_row.incident_id),
      'digest', case when v_row.kind = 'digest' then (
        select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                     'resolved', i.resolved_at is not null) order by i.opened_at), '[]')
          from one.incidents i
         where i.severity = 'P2' and (i.opened_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
           and i.check_id <> 'ONE-SYNTH') end,
      -- With the saved views people asked to have emailed: daily ones every day, weekly ones on Mondays (links only;
      -- their numbers stay on the page).
      'brief', case when v_row.kind = 'brief' then (
        select jsonb_build_object('id', b.id, 'for_date', b.for_date, 'body_md', b.body_md, 'model', b.model,
                                  'views', (select coalesce(jsonb_agg(jsonb_build_object('name', v.name, 'page', v.page, 'days', v.params -> 'days')
                                                                      order by v.page, v.name), '[]')
                                              from one.saved_views v
                                             where v.schedule = 'daily' or (v.schedule = 'weekly' and extract(isodow from b.for_date) = 1)))
          from one.briefs b where b.id = v_row.brief_id) end));
  end loop;
  return v_out;
end $$;

create or replace function one.ui_incident(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_inc one.incidents;
begin
  select * into v_inc from one.incidents where id = p_id;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'incident', one.mask_json(to_jsonb(v_inc)),
    'check', (select jsonb_build_object('id', c.id, 'title', c.title, 'description', c.description, 'kind', c.kind, 'severity', c.severity,
                                        'cadence_s', c.cadence_s, 'sql', c.sql, 'tags', c.tags, 'auto_fix_id', c.auto_fix_id, 'enabled', c.enabled,
                                        'disabled_reason', c.disabled_reason, 'open_after', c.open_after, 'resolve_after', c.resolve_after,
                                        'muted', one.is_muted(c.id, c.app),
                                        'fix_enabled', coalesce((one.setting('fixes') -> c.auto_fix_id ->> 'enabled')::boolean, false))
                from one.checks c where c.id = v_inc.check_id),
    -- The fixes tried on this check, light (efficiency review 2c): the page no longer reads the whole Fixes catalogue.
    'fixes', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'mode', f.mode, 'title', f.title,
                                                          'enabled', coalesce((one.setting('fixes') -> f.id ->> 'enabled')::boolean, false),
                                                          'paused', one.fix_paused_reason(f.id) is not null,
                                                          'stopped', exists (select 1 from one.actions a where a.fix_id = f.id and a.incident_id = p_id
                                                                                and a.step = 'verify' and a.status = 'failed'))
                                        order by f.id), '[]')
                from one.fixes f where v_inc.check_id = any (f.checks)),
    'results', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'ran_at', r.ran_at, 'status', r.status, 'value', one.mask_json(r.value),
                                                            'error', one.mask_text(r.error), 'duration_ms', r.duration_ms) order by r.id desc), '[]')
                  from (select * from one.results where check_id = v_inc.check_id order by ran_at desc, id desc limit 30) r),
    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.occurred_at, 'app', e.app, 'source', e.source_table,
                                                             'type', e.type, 'lead_id', e.lead_id, 'actor_type', e.actor_type, 'payload', e.payload)
                                           order by e.occurred_at), '[]')
                   from (select * from one.events e
                          where e.app = v_inc.app and e.occurred_at between v_inc.opened_at - interval '30 minutes' and v_inc.opened_at + interval '30 minutes'
                          order by e.occurred_at limit 200) e),
    'deliveries', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'recipient', d.recipient, 'kind', d.kind, 'level', d.escalation_level,
                                                               'status', d.status, 'attempts', d.attempts, 'sent_at', d.sent_at, 'error', d.error,
                                                               'created_at', d.created_at) order by d.id), '[]')
                     from one.deliveries d where d.incident_id = p_id),
    'actions', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]') from one.actions a where a.incident_id = p_id),
    'ai_tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'model_hint', t.model_hint, 'status', t.status,
                                                             'result', t.result, 'error', t.error, 'created_at', t.created_at) order by t.id desc), '[]')
                   from one.ai_tasks t where t.incident_id = p_id),
    'proposals', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'title', p.title, 'status', p.status, 'risk', p.risk)
                                            order by p.id desc), '[]')
                    from one.proposals p where p.incident_id = p_id),
    'tests', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'enabled', t.enabled,
                                                          'last_ok', (select r.ok from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 1))
                                        order by t.id), '[]')
                from one.tests t where t.app = v_inc.app),
    'children', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'check_id', c.check_id, 'title', c.title, 'severity', c.severity,
                                                             'resolved_at', c.resolved_at) order by c.id), '[]')
                   from one.incidents c where c.parent_id = p_id),
    'mutes', (select coalesce(jsonb_agg(to_jsonb(m) order by m.ends_at desc), '[]') from one.mutes m
               where m.ends_at > now() and ((m.target_type = 'check' and m.target = v_inc.check_id) or (m.target_type = 'app' and m.target = v_inc.app))));
end $$;

create or replace function one.ui_check_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_c one.checks;
  v_enabled boolean;
begin
  select * into v_c from one.checks where id = p_id for update;
  if not found then
    raise exception 'no check %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_c.enabled);
  -- Switching off, lowering the severity of, running less often, or needing more failures to open a check that guards
  -- the platform is the owner's (security review S7, hardening M2): every P1, the integrity checks, and those tagged
  -- security, integrity, money or consent. A cadence of a week or an open_after of 60 is a switch-off by another name.
  if (v_c.severity = 'P1' or v_c.app = 'integrity' or v_c.tags && array['security', 'integrity', 'money', 'consent'])
     and ((v_c.enabled and not v_enabled)
          or coalesce((p_patch ->> 'severity')::one.severity, v_c.severity) > v_c.severity
          or coalesce((p_patch ->> 'cadence_s')::int, v_c.cadence_s) > v_c.cadence_s
          or coalesce((p_patch ->> 'open_after')::int, v_c.open_after) > v_c.open_after) then
    perform one.ui_require('owner');
  end if;
  if v_enabled and not v_c.enabled and v_c.disabled_reason like 'blocked:%' then
    raise exception 'check % cannot run: %', p_id, v_c.disabled_reason using errcode = '22023';
  end if;
  update one.checks set
    enabled = v_enabled,
    disabled_reason = case when v_enabled then null
                           when v_c.enabled then 'owner:' || coalesce(nullif(trim(both '-' from regexp_replace(lower(left(v_reason, 40)), '[^a-z0-9_.:-]+', '-', 'g')), ''),
                                                                     'switched-off')
                           else disabled_reason end,
    severity = coalesce((p_patch ->> 'severity')::one.severity, severity),
    cadence_s = coalesce((p_patch ->> 'cadence_s')::int, cadence_s),
    threshold = case when jsonb_typeof(p_patch -> 'threshold') = 'object' then p_patch -> 'threshold' else threshold end,
    open_after = coalesce((p_patch ->> 'open_after')::int, open_after),
    resolve_after = coalesce((p_patch ->> 'resolve_after')::int, resolve_after),
    updated_by = v_actor, updated_at = now(), version = version + 1
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'check.update', 'check:' || p_id,
    jsonb_build_object('enabled', v_c.enabled, 'severity', v_c.severity, 'cadence_s', v_c.cadence_s, 'threshold', v_c.threshold,
                       'open_after', v_c.open_after, 'resolve_after', v_c.resolve_after),
    p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.ui_test_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_t one.tests;
  v_enabled boolean;
  v_item text;
begin
  select * into v_t from one.tests where id = p_id for update;
  if not found then
    raise exception 'no test %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_t.enabled);
  -- A test runs only on validated identities: every Setup item it needs (spec §10, §15).
  select u.n into v_item from unnest(v_t.needs) with ordinality u(n, o)
   where not coalesce((one.setting('setup') #>> array['items', u.n, 'validated'])::boolean, false) order by u.o limit 1;
  if v_enabled and not v_t.enabled and v_t.disabled_reason like 'blocked:%' then
    raise exception 'test % cannot run: %', p_id, v_t.disabled_reason using errcode = '22023';
  end if;
  if v_enabled and not v_t.enabled and v_item is not null then
    raise exception 'test % waits for Setup item %', p_id, v_item using errcode = '22023';
  end if;
  -- Switching off a P1 test is the owner's, as for a P1 check (D-065).
  if v_t.enabled and not v_enabled and v_t.severity = 'P1' then
    perform one.ui_require('owner');
  end if;
  if p_patch ? 'schedule' and p_patch ->> 'schedule' !~ '^(\S+\s+){4}\S+$' then
    raise exception 'a schedule is a 5-field cron expression' using errcode = '22023';
  end if;
  -- A day of month above 28 with a fixed month may never come ("0 0 31 2 *"): refused, whoever asks (hardening M2).
  if p_patch ? 'schedule' and split_part(p_patch ->> 'schedule', ' ', 3) ~ '^[0-9]+$' and split_part(p_patch ->> 'schedule', ' ', 3)::int > 28 then
    raise exception 'a day of month above 28 may never come; use 1 to 28 or *' using errcode = '22023';
  end if;
  -- Rescheduling a P1 test is the owner's, like switching it off: a schedule that never fires is a switch-off.
  if p_patch ? 'schedule' and p_patch ->> 'schedule' is distinct from v_t.schedule and v_t.severity = 'P1' then
    perform one.ui_require('owner');
  end if;
  update one.tests set enabled = v_enabled,
         disabled_reason = case when v_enabled then null when v_t.enabled then 'owner:' || left(v_reason, 60) else disabled_reason end,
         schedule = coalesce(p_patch ->> 'schedule', schedule), updated_by = v_actor
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'test.update', 'test:' || p_id, jsonb_build_object('enabled', v_t.enabled, 'schedule', v_t.schedule),
                             p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.settings_check(p_key text, p_value jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare
  v_email text := '^[^@\s]+@[^@\s]+\.[a-z]{2,}$';
  v_bad text;
begin
  if jsonb_typeof(p_value) is distinct from 'object' then
    raise exception 'setting %: the value must be a JSON object', p_key using errcode = '22023';
  end if;
  case p_key
    when 'events' then
      if jsonb_typeof(p_value -> 'pii_columns') is distinct from 'array' or jsonb_array_length(p_value -> 'pii_columns') = 0
         or exists (select 1 from jsonb_array_elements(p_value -> 'pii_columns') e where jsonb_typeof(e) <> 'string') then
        raise exception 'setting events: pii_columns must be a non-empty list of key patterns' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'batch')::int, 5000) not between 100 and 50000
         or coalesce((p_value ->> 'id_overlap')::int, 0) not between 0 and 10000
         or coalesce((p_value ->> 'window_hours')::int, 48) not between 1 and 720 then
        raise exception 'setting events: batch 100–50000, id_overlap 0–10000, window_hours 1–720' using errcode = '22023';
      end if;
    when 'alerts' then
      if jsonb_typeof(p_value #> '{p1,email}') is distinct from 'array' or jsonb_array_length(p_value #> '{p1,email}') = 0 then
        raise exception 'setting alerts: p1.email must be a non-empty list of addresses' using errcode = '22023';
      end if;
      select string_agg(x, ', ') into v_bad
        from (select jsonb_array_elements_text(p_value #> '{p1,email}') x
              union all select jsonb_array_elements_text(coalesce(p_value #> '{escalation,second_contact}', '[]'))
              union all select p_value ->> 'developer_email' where p_value ->> 'developer_email' is not null) a
       where lower(x) !~ v_email;
      if v_bad is not null then
        raise exception 'setting alerts: not an email address: %', left(v_bad, 200) using errcode = '22023';
      end if;
      if coalesce((p_value #>> '{escalation,resend_min}')::numeric, 30) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,second_contact_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,repeat_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value ->> 'p2_digest_hour_ist')::numeric, 18) not between 0 and 23
         or coalesce((p_value ->> 'p2_digest_min_count')::numeric, 5) not between 0 and 1000
         or coalesce((p_value #>> '{storm,p1_count}')::numeric, 10) not between 2 and 1000
         or coalesce((p_value #>> '{storm,window_min}')::numeric, 5) not between 1 and 120
         or coalesce((p_value #>> '{storm,suppress_min}')::numeric, 15) not between 1 and 240 then
        raise exception 'setting alerts: an escalation, digest or storm number is out of range' using errcode = '22023';
      end if;
    when 'thresholds' then
      select string_agg(key, ', ') into v_bad from jsonb_each(p_value) where jsonb_typeof(value) <> 'number';
      if v_bad is not null then
        raise exception 'setting thresholds: not a number: %', left(v_bad, 200) using errcode = '22023';
      end if;
    when 'checks' then
      if coalesce(p_value ->> 'lock_timeout', '2s') !~ '^[0-9]{1,5}(ms|s)$'
         or coalesce(p_value ->> 'transaction_timeout', '30s') !~ '^[0-9]{1,5}(s|min)$'
         or (coalesce(p_value ->> 'transaction_timeout', '30s') ~ '^[0-9]+s$' and regexp_replace(coalesce(p_value ->> 'transaction_timeout', '30s'), 's$', '')::int < 5)
         or jsonb_typeof(coalesce(p_value -> 'source_missing_opens_incident', 'true')) <> 'boolean'
         or coalesce((p_value ->> 'slow_ms')::int, 5000) not between 100 and 600000 then
        raise exception 'setting checks: lock_timeout like "2s", transaction_timeout like "30s" (5s or more), a boolean source_missing_opens_incident, slow_ms 100–600000'
          using errcode = '22023';
      end if;
    when 'access' then
      if jsonb_typeof(p_value -> 'owners') is distinct from 'array'
         or exists (select 1 from jsonb_array_elements_text(p_value -> 'owners') x where lower(x) !~ '^[^@\s]+@eduwit\.in$') then
        raise exception 'setting access: owners must be a list of @eduwit.in addresses' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'trusted_days')::int, 30) not between 0 and 90
         or coalesce((p_value ->> 'idle_hours')::int, 12) not between 1 and 72
         or coalesce((p_value ->> 'code_minutes')::int, 10) not between 2 and 30 then
        raise exception 'setting access: trusted_days 0–90, idle_hours 1–72, code_minutes 2–30' using errcode = '22023';
      end if;
    when 'app' then
      if p_value ->> 'base_url' is not null and p_value ->> 'base_url' !~ '^https://[a-z0-9.-]+(:[0-9]+)?$' then
        raise exception 'setting app: base_url must be https://host with no path' using errcode = '22023';
      end if;
    -- The shapes the pages cast or parse (phase review m12): a bad edit must be refused here, not break a page.
    when 'analytics' then
      if jsonb_typeof(p_value -> 'funnel') is distinct from 'array' or jsonb_array_length(p_value -> 'funnel') not between 1 and 20
         or exists (select 1 from jsonb_array_elements(p_value -> 'funnel') s
                     where jsonb_typeof(s) <> 'object' or coalesce(s ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,30}$'
                        or jsonb_typeof(s -> 'label') is distinct from 'string' or length(s ->> 'label') not between 1 and 80
                        or jsonb_typeof(s -> 'match') is distinct from 'array' or jsonb_array_length(s -> 'match') = 0
                        or exists (select 1 from jsonb_array_elements(s -> 'match') m
                                    where jsonb_typeof(m) <> 'object' or jsonb_typeof(m -> 'type') is distinct from 'string'
                                       or (m ? 'app' and jsonb_typeof(m -> 'app') is distinct from 'string')))
         or (select count(distinct s ->> 'key') from jsonb_array_elements(p_value -> 'funnel') s) <> jsonb_array_length(p_value -> 'funnel') then
        raise exception 'setting analytics: funnel is 1 to 20 steps, each {key (a-z_), label, match: [{type, app?}]}, keys unique' using errcode = '22023';
      end if;
    when 'ai' then
      if exists (select 1 from unnest(array['daily_cap_inr', 'per_task_cap_inr', 'queue_non_triage_at_pct', 'usd_inr']) k
                  where p_value ? k and (jsonb_typeof(p_value -> k) <> 'number' or (p_value ->> k)::numeric < 0)) then
        raise exception 'setting ai: daily_cap_inr, per_task_cap_inr, queue_non_triage_at_pct and usd_inr are numbers, 0 or more' using errcode = '22023';
      end if;
      -- The worker reads these on every task (phase 6, D-075): a bad edit is refused here, not found by a failing task.
      -- Claude only (owner, 24 Oct; D-004): there is no provider to choose.
      if p_value ? 'provider'
         or (p_value ? 'effort' and (jsonb_typeof(p_value -> 'effort') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'effort') e where e.key not in ('quick', 'regular', 'deep')
                                                                         or e.value not in ('null', '"low"', '"medium"', '"high"', '"xhigh"', '"max"'))))
         or (p_value ? 'prices' and (jsonb_typeof(p_value -> 'prices') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'prices') e
                        where jsonb_typeof(e.value) not in ('null', 'object')
                           or (jsonb_typeof(e.value) = 'object'
                               and (not (e.value ? 'input' and e.value ? 'output')
                                    or exists (select 1 from jsonb_each(e.value) f
                                                where f.key not in ('input', 'output', 'cache_read', 'cache_write')
                                                   or jsonb_typeof(f.value) <> 'number' or (f.value #>> '{}')::numeric < 0))))))
         or (p_value ? 'queue_non_triage_at_pct' and (p_value ->> 'queue_non_triage_at_pct')::numeric > 100)
         or (p_value ? 'allow_message_excerpts' and jsonb_typeof(p_value -> 'allow_message_excerpts') <> 'boolean')
         or coalesce((p_value ->> 'max_parallel')::numeric, 2) not between 1 and 5
         or coalesce((p_value ->> 'task_max_age_h')::numeric, 48) not between 1 and 720
         or coalesce(p_value #>> '{schedule,brief_mail_at_ist}', '08:00') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         or coalesce((p_value #>> '{schedule,propose_feature_weekday}')::numeric, 1) not between 1 and 7
         or coalesce((p_value #>> '{schedule,explain_after_min}')::numeric, 15) not between 1 and 1440
         or coalesce((p_value #>> '{schedule,propose_fix_after_min}')::numeric, 60) not between 1 and 10080
         -- Routing and models are read by the schedule and every claim (phase 6 review m1).
         or (p_value ? 'usd_inr' and (p_value ->> 'usd_inr')::numeric <= 0)
         or (p_value ? 'routing' and (jsonb_typeof(p_value -> 'routing') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'routing') e where e.value not in ('"quick"', '"regular"', '"deep"'))))
         or (p_value ? 'fallback_when_model_missing' and p_value -> 'fallback_when_model_missing' not in ('null', '"quick"', '"regular"', '"deep"'))
         or (p_value ? 'models' and (jsonb_typeof(p_value -> 'models') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'models') m
                         where m.key not in ('quick', 'regular', 'deep')
                            or (jsonb_typeof(m.value) <> 'null'
                                and (jsonb_typeof(m.value) <> 'string' or (m.value #>> '{}') !~ '^claude-[a-z0-9.-]{1,80}$')))))
         or (p_value ? 'refusal_fallback' and jsonb_typeof(p_value -> 'refusal_fallback') <> 'null'
             and (jsonb_typeof(p_value -> 'refusal_fallback') <> 'string' or (p_value ->> 'refusal_fallback') !~ '^claude-[a-z0-9.-]{1,80}$')) then
        raise exception 'setting ai: Claude only, so no provider; effort per tier null, low, medium, high, xhigh or max; prices per model null or {input, output, cache_read?, cache_write?} in USD per million tokens, 0 or more; queue_non_triage_at_pct at most 100; allow_message_excerpts a boolean; max_parallel 1–5; task_max_age_h 1–720; schedule: brief_mail_at_ist HH:MM, propose_feature_weekday 1–7, explain_after_min 1–1440, propose_fix_after_min 1–10080; usd_inr above 0; routing values quick, regular or deep; fallback_when_model_missing null or a tier; models {tier: a claude-… model or null}; refusal_fallback null or a claude-… model'
          using errcode = '22023';
      end if;
    when 'fixes' then
      if (p_value ? 'observation_days' and (jsonb_typeof(p_value -> 'observation_days') <> 'number' or (p_value ->> 'observation_days')::numeric not between 14 and 90))
         or (jsonb_typeof(p_value -> 'observation_started_at') not in ('null') and coalesce(p_value ->> 'observation_started_at', '')
             !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?)?$') then
        raise exception 'setting fixes: observation_days 14–90 (spec §8: two weeks at least), observation_started_at null or an ISO time' using errcode = '22023';
      end if;
      -- The window's start is set once, by the first tick that runs the fixes; nobody moves it afterwards (phase 7 review m8).
      if (select s.value ->> 'observation_started_at' from one.settings s where s.key = 'fixes') is not null
         and ((p_value ->> 'observation_started_at') is null
              or (p_value ->> 'observation_started_at')::timestamptz <> (select (s.value ->> 'observation_started_at')::timestamptz from one.settings s where s.key = 'fixes')) then
        raise exception 'setting fixes: the observation window started at its first tick and its start cannot change' using errcode = '22023';
      end if;
      -- Each fix: {enabled, per_tick 1–500, cooldown_min 1–1440}. A fix is switched on only on evidence (spec §8):
      -- after the observation window, and once it has at least one dry run.
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key not in ('observation_days', 'observation_started_at')
                    and (f.key !~ '^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$' or jsonb_typeof(f.value) <> 'object'
                         or exists (select 1 from jsonb_object_keys(f.value) k where k not in ('enabled', 'per_tick', 'cooldown_min'))
                         or jsonb_typeof(f.value -> 'enabled') is distinct from 'boolean'
                         or jsonb_typeof(f.value -> 'per_tick') is distinct from 'number' or (f.value ->> 'per_tick')::numeric not between 1 and 500
                         or (f.value ->> 'per_tick')::numeric <> trunc((f.value ->> 'per_tick')::numeric)
                         or jsonb_typeof(f.value -> 'cooldown_min') is distinct from 'number' or (f.value ->> 'cooldown_min')::numeric not between 1 and 1440
                         or (f.value ->> 'cooldown_min')::numeric <> trunc((f.value ->> 'cooldown_min')::numeric))) then
        raise exception 'setting fixes: each FIX-… is {enabled: boolean, per_tick: 1–500, cooldown_min: 1–1440}' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean)
         and (p_value ->> 'observation_started_at' is null
              or (p_value ->> 'observation_started_at')::timestamptz + make_interval(days => coalesce((p_value ->> 'observation_days')::int, 14)) > now()) then
        raise exception 'setting fixes: a fix is switched on only after the observation window ends' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean
                    and not exists (select 1 from one.actions a where a.fix_id = f.key and a.dry_run)) then
        raise exception 'setting fixes: a fix is switched on only once it has a dry run to judge it by' using errcode = '22023';
      end if;
    -- The keys the app parses each minute and the engineer-editable ones have a shape too (hardening F6, m2): a typo
    -- is refused here instead of making every tick route fail.
    when 'tests' then
      if coalesce((p_value ->> 'purge_after_days')::int, 2) not between 1 and 30
         or jsonb_typeof(coalesce(p_value -> 'schedules', '{}')) <> 'object'
         or exists (select 1 from jsonb_each_text(coalesce(p_value -> 'schedules', '{}')) sc where sc.value !~ '^(\S+\s+){4}\S+$') then
        raise exception 'setting tests: purge_after_days 1–30, schedules {T-…: a 5-field cron expression}' using errcode = '22023';
      end if;
    when 'witty' then
      if exists (select 1 from jsonb_each(p_value) w where w.key in ('expect_nurture', 'expect_learning') and jsonb_typeof(w.value) <> 'boolean') then
        raise exception 'setting witty: expect_nurture and expect_learning are booleans' using errcode = '22023';
      end if;
    when 'hosts' then
      if exists (select 1 from unnest(array['website', 'spark', 'b2b_app', 'influencer', 'chatwoot', 'n8n', 'one']) h where coalesce(p_value ->> h, '') !~ '^https://[a-z0-9.-]+$')
         or exists (select 1 from jsonb_each(p_value) h where jsonb_typeof(h.value) <> 'string' or (h.value #>> '{}') !~ '^https://[a-z0-9.-]+$') then
        raise exception 'setting hosts: website, spark, b2b_app, influencer, chatwoot, n8n and one are https://host values with no path' using errcode = '22023';
      end if;
    when 'vendors' then
      if exists (select 1 from jsonb_each(p_value) v where jsonb_typeof(v.value) <> 'string' or (v.value #>> '{}') !~ '^https://[a-z0-9.-]+(/[A-Za-z0-9._/-]*)?$') then
        raise exception 'setting vendors: every value is an https URL' using errcode = '22023';
      end if;
    when 'vercel' then
      if jsonb_typeof(p_value -> 'team') <> 'string' or jsonb_typeof(coalesce(p_value -> 'projects', '{}')) <> 'object'
         or exists (select 1 from jsonb_each(coalesce(p_value -> 'projects', '{}')) pr where jsonb_typeof(pr.value) <> 'string') then
        raise exception 'setting vercel: team a string, projects {app: project name}' using errcode = '22023';
      end if;
    when 'chatwoot' then
      if coalesce(p_value ->> 'account_id', '') !~ '^[0-9]{1,10}$' then
        raise exception 'setting chatwoot: account_id is a number' using errcode = '22023';
      end if;
    when 'n8n' then
      if exists (select 1 from jsonb_each(p_value) n where n.key like '%workflow_id' and (jsonb_typeof(n.value) <> 'string' or (n.value #>> '{}') !~ '^[A-Za-z0-9_-]{1,64}$')) then
        raise exception 'setting n8n: each *_workflow_id is an n8n workflow id' using errcode = '22023';
      end if;
    when 'whatsapp' then
      if jsonb_typeof(coalesce(p_value -> 'waba_ids', '[]')) <> 'array'
         or exists (select 1 from jsonb_array_elements(coalesce(p_value -> 'waba_ids', '[]')) w where jsonb_typeof(w) <> 'string') then
        raise exception 'setting whatsapp: waba_ids is a list of ids' using errcode = '22023';
      end if;
    when 'health_paths' then
      if exists (select 1 from jsonb_each(p_value) h where jsonb_typeof(h.value) <> 'string' or (h.value #>> '{}') !~ '^/') then
        raise exception 'setting health_paths: every value is a path starting with /' using errcode = '22023';
      end if;
    when 'retention' then
      if exists (select 1 from jsonb_each(p_value) r where r.key like '%_days' and (jsonb_typeof(r.value) <> 'number' or (r.value #>> '{}')::numeric not between 1 and 3650))
         or coalesce((p_value ->> 'results_days')::int, 90) < 7 or coalesce((p_value ->> 'events_days')::int, 180) < 7
         or coalesce((p_value ->> 'ai_calls_days')::int, 365) < 7 then
        raise exception 'setting retention: *_days are numbers up to 3650; results, events and ai_calls at least 7, ok_results_days at least 1' using errcode = '22023';
      end if;
    else
      null;
  end case;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'setting %: a number field holds something else', p_key using errcode = '22023';
end $$;

create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_version integer;
  v_value jsonb := p_value;
begin
  select value into v_before from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  -- The observation window's start is the first tick's to write, never a page's (security review m1): the stored
  -- value is kept whatever the form sends, so the window cannot be backdated before it starts.
  if p_key = 'fixes' then
    v_value := v_value || jsonb_build_object('observation_started_at', v_before -> 'observation_started_at');
  end if;
  if v_value = v_before then
    raise exception 'nothing changed: the value is the current version' using errcode = '22023';
  end if;
  v_version := one.settings_put(p_key, v_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, v_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

-- Restores an earlier version of a setting as a new version (D-065 promised it; review F14): the same checks and
-- rights as any write, the reason naming the version restored.
create or replace function one.ui_settings_restore(p_key text, p_version integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_value jsonb;
begin
  -- The gate first, as every UI function (80_ui_api §10); the key's own rule (owner or engineer) applies in ui_settings_put.
  perform one.ui_require('read');
  select v.value into v_value from one.settings_versions v where v.key = p_key and v.version = p_version;
  if v_value is null then
    raise exception 'no version % of setting %', p_version, p_key using errcode = 'P0002';
  end if;
  return one.ui_settings_put(p_key, v_value, format('restore version %s: %s', p_version, p_reason), p_request_id);
end $$;

create or replace function one.ui_view_save(p_page text, p_name text, p_params jsonb, p_schedule text default null,
                                            p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  -- A saved view's days must be a whole number of days: a bad one would make every brief email unreadable (security m3).
  if p_params ? 'days' and (jsonb_typeof(p_params -> 'days') <> 'number' or (p_params ->> 'days')::numeric not between 1 and 365
                            or (p_params ->> 'days')::numeric <> trunc((p_params ->> 'days')::numeric)) then
    raise exception 'a view''s days is a whole number from 1 to 365' using errcode = '22023';
  end if;
  insert into one.saved_views (page, name, params, schedule, created_by) values (p_page, trim(p_name), coalesce(p_params, '{}'), p_schedule, v_actor)
  on conflict (page, name) do update set params = excluded.params, schedule = excluded.schedule
  returning id into v_id;
  perform one.ui_audit_write(v_actor, 'view.save', 'view:' || v_id, null, jsonb_build_object('page', p_page, 'name', p_name, 'schedule', p_schedule), p_request_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- The request id travels with the mute so its audit row is written once (append-only histories, D-085).
drop function if exists one.mute(text, text, integer, text, text);
create or replace function one.mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_by text, p_request_id text default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  if p_target_type = 'check' and not exists (select 1 from one.checks where id = p_target)
     or p_target_type = 'app' and not exists (select 1 from one.apps where key = p_target) then
    raise exception 'one.mute: unknown % %', p_target_type, p_target using errcode = '22023';
  end if;
  if coalesce(p_minutes, 0) not between 1 and 10080 or nullif(trim(p_reason), '') is null then
    raise exception 'one.mute: a duration of 1 minute to 7 days and a reason are required' using errcode = '22023';
  end if;
  insert into one.mutes (target_type, target, ends_at, reason, created_by)
  values (p_target_type, p_target, now() + make_interval(mins => p_minutes), left(p_reason, 300), left(p_by, 120))
  returning id into v_id;
  update one.incidents set alert_state = 'muted'
   where resolved_at is null and alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2', 'digest')
     and ((p_target_type = 'check' and check_id = p_target) or (p_target_type = 'app' and app = p_target));
  insert into one.audit (actor, action, target, after, request_id) values (left(p_by, 120), 'mute', p_target_type || ':' || p_target,
    jsonb_build_object('mute_id', v_id, 'minutes', p_minutes, 'reason', left(p_reason, 300)), left(p_request_id, 80));
  return v_id;
end $$;

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor, p_request_id);
begin
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

-- Redaction compiled (efficiency review 8, D-088). The PII key list becomes one anchored pattern per call ("*" a
-- wildcard, everything else literal), tested once per key instead of a like per key per node, and one.has_contact runs
-- only on text that holds a digit or an @ (nothing else can be a phone or an email). one.redact(jsonb, text[]) keeps
-- its signature as a thin wrapper, so every caller and test is unchanged.
create or replace function one.redact_pattern(p_keys text[]) returns text
language sql immutable set search_path = '' as $$
  select case when p_keys is null or cardinality(p_keys) = 0 then null
              else '^(' || (select string_agg(replace(regexp_replace(lower(k), '([.+?^$(){}|\[\]\\])', '\\\1', 'g'), '*', '.*'), '|')
                              from unnest(p_keys) k) || ')$' end
$$;

create or replace function one.redact_with(p_value jsonb, p_pattern text) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_out jsonb;
  v_text text;
  v_kind text;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select coalesce(jsonb_object_agg(coalesce(case when e.key ~ '[0-9@]' then '[' || one.has_contact(e.key) || ']' end, e.key),
                                       one.redact_with(e.value, p_pattern)), '{}'::jsonb) into v_out
        from jsonb_each(p_value) e
       where p_pattern is null or lower(e.key) !~ p_pattern;
      return v_out;
    when 'array' then
      select coalesce(jsonb_agg(one.redact_with(a.value, p_pattern) order by a.ord), '[]'::jsonb) into v_out
        from jsonb_array_elements(p_value) with ordinality a(value, ord);
      return v_out;
    when 'string' then
      v_text := p_value #>> '{}';
      -- A JSON document kept as text (a partner reply, a webhook body): redacted as JSON, then stored as text again.
      if v_text ~ '^\s*[\[{]' and length(v_text) <= 20000 then
        begin
          return to_jsonb(one.redact_with(v_text::jsonb, p_pattern)::text);
        exception when invalid_text_representation then
          null;
        end;
      end if;
      if v_text ~ '[0-9@]' then
        v_kind := one.has_contact(v_text);
        if v_kind is not null then
          return to_jsonb('[' || v_kind || ']');
        end if;
      end if;
      return p_value;
    when 'number' then
      -- A phone stored as a number (S2): 10 digits starting 3 to 9 (an Indian mobile, or a non-Indian number such as
      -- 5551234567: security review m8), or any whole number of 11 to 15 digits (an international number with its
      -- country code). Counts, ids, amounts and epoch seconds (10 digits starting 1 or 2 until 2065) stay.
      if p_value::text ~ '^([3-9][0-9]{9}|[0-9]{11,15})$' then
        return '"[phone]"'::jsonb;
      end if;
      return p_value;
    else
      return p_value;
  end case;
end $$;

create or replace function one.redact(p_value jsonb, p_keys text[]) returns jsonb
language sql immutable set search_path = '' as $$
  select one.redact_with(p_value, one.redact_pattern(p_keys))
$$;

-- A plan with no row list is kept whole (security review m10: jsonb_typeof(null) fell through to "applies false").
create or replace function one.fix_plan_within(p_plan jsonb, p_rows jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_rows is null or coalesce(jsonb_typeof(p_plan -> 'rows'), '') <> 'array' then p_plan
         else p_plan || jsonb_build_object('rows', r.rows, 'count', jsonb_array_length(r.rows),
                                           'applies', jsonb_array_length(r.rows) > 0 or coalesce((p_plan #>> '{target,oldest_pending_old}')::boolean, false))
         end
    from (select coalesce(jsonb_agg(x order by x::text), '[]') as rows from jsonb_array_elements(coalesce(p_plan -> 'rows', '[]')) x
           where coalesce(p_rows, '[]') @> jsonb_build_array(x)) r
$$;

create or replace function one.finish_delivery(p_id bigint, p_ok boolean, p_error text default null, p_provider_id text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_d one.deliveries;
begin
  select * into v_d from one.deliveries where id = p_id and status = 'sending' for update;
  if not found then
    return 'not_claimed';
  end if;
  if p_ok then
    update one.deliveries set status = 'sent', sent_at = now(), provider_id = left(p_provider_id, 120), error = null, attempts = attempts + 1 where id = p_id;
    update one.incidents set alert_state = 'sent' where id = v_d.incident_id and alert_state = 'pending';
    update one.briefs set sent_at = now() where id = v_d.brief_id and sent_at is null;
    return 'sent';
  end if;
  -- An alert, escalation or storm email is tried up to 8 times with a growing wait (2, 4, 8, 16, 32, 60, 60 minutes):
  -- a provider outage of a few hours does not lose the page, and a delivery still pending shows in ONE-02 and the
  -- watchdog all the while (review F1). Briefs and digests keep their two tries.
  update one.deliveries
     set attempts = attempts + 1, error = left(p_error, 500),
         status = case when attempts + 1 >= case when v_d.kind in ('alert', 'escalation', 'storm') then 8 else 2 end then 'failed' else 'pending' end,
         next_attempt_at = now() + make_interval(mins => least(60, (2 ^ least(attempts + 1, 6))::int))
   where id = p_id;
  return case when v_d.attempts + 1 >= case when v_d.kind in ('alert', 'escalation', 'storm') then 8 else 2 end then 'failed' else 'retry' end;
end $$;

create or replace function one.watchdog() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'tick_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'app_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:app'),
    -- A page still waiting, or one that failed for good in the last 6 hours (review F1): the monitor must not read ok
    -- while a P1 never reached anyone.
    'delivery_wait_s', (select round(extract(epoch from now() - min(created_at))) from one.deliveries
                         where kind in ('alert', 'escalation', 'storm')
                           and (status in ('pending', 'sending') or (status = 'failed' and created_at > now() - interval '6 hours'))))
$$;

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

create or replace function one.events_due() returns table (source text, app text, sql text)
language sql stable set search_path = '' as $$
  select s.source, s.app, s.sql from one.events_sources() s left join one.event_watermarks w on w.source = s.source
   where coalesce(w.killed_count, 0) < 3
     and (w.last_status is distinct from 'killed' or w.last_started_at < now() - interval '10 minutes')
     -- A source whose table or function is missing is tried again after 10 minutes, not every minute (D-088).
     and (w.last_status is distinct from 'source_missing' or w.updated_at < now() - interval '10 minutes')
   order by w.last_status = 'killed' nulls first, w.last_started_at nulls first, s.source
$$;

create or replace function one.events_copy(p_source text, p_app text, p_sql text) returns integer
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('events'), '{}');
  v_wm one.event_watermarks;
  v_batch integer := coalesce((v_cfg ->> 'batch')::int, 5000);
  v_overlap bigint := coalesce((v_cfg ->> 'id_overlap')::bigint, 1000);
  v_window interval := make_interval(hours => coalesce((v_cfg ->> 'window_hours')::int, 48));
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(v_cfg -> 'pii_columns')), '{}');
  v_inserted integer;
  v_max_id bigint;
  v_max_at timestamptz;
begin
  -- Nothing is copied without a PII list: an empty or missing one would store names and free text (M4).
  if cardinality(v_pii) = 0 then
    raise exception 'events.pii_columns is missing or empty: nothing is copied without a PII list' using errcode = '22023';
  end if;
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  insert into one.event_watermarks (source) values (p_source) on conflict do nothing;
  select * into v_wm from one.event_watermarks where source = p_source for update;
  -- Each kill halves the batch (floor 100), so a source that cannot copy 5,000 rows in time copies fewer (review F3).
  v_batch := greatest(100, v_batch / power(2, least(coalesce(v_wm.killed_count, 0), 6))::int);
  execute format($q$
    with src (source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id, wm_at) as (%s),
    ins as (
      insert into one.events (app, source_table, source_id, occurred_at, type, lead_id, actor_type, actor_id, payload)
      select %L, %L, s.source_id, s.occurred_at, s.type, s.lead_id, s.actor_type, s.actor_id, one.redact(coalesce(s.payload, '{}'), $4)
        from src s
       where s.occurred_at is not null
         -- Rows copied before are skipped before they are redacted: the overlap and the state window re-read them (M9).
         and not exists (select 1 from one.events e where e.app = %L and e.source_table = %L and e.source_id = s.source_id)
      on conflict (app, source_table, source_id) do nothing
      returning 1)
    select (select count(*) from ins)::int, (select max(wm_id) from src), (select max(wm_at) from src)$q$, p_sql, p_app, p_source, p_app, p_source)
    into v_inserted, v_max_id, v_max_at
    using greatest(coalesce(v_wm.last_id, 0) - v_overlap, 0), now() - v_window, v_batch, v_pii;
  update one.event_watermarks
     set last_id = greatest(last_id, v_max_id), last_at = greatest(last_at, v_max_at), last_status = 'ok', last_error = null,
         rows_copied = rows_copied + v_inserted, updated_at = now(), killed_count = 0
   where source = p_source;
  return v_inserted;
exception
  when undefined_table or undefined_function or undefined_column or invalid_schema_name then
    -- The body's writes were rolled back with the error, including the watermark row, so upsert it.
    insert into one.event_watermarks (source, last_status, last_error) values (p_source, 'source_missing', left(sqlerrm, 300))
    on conflict (source) do update set last_status = 'source_missing', last_error = excluded.last_error, updated_at = now();
    return -1;
end $$;

create or replace function one.open_or_touch_incident(p_check_id text, p_severity one.severity, p_evidence jsonb,
                                                      p_subjects text[] default '{}') returns bigint
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_inc one.incidents;
  v_new text[];
  v_escalated boolean;
begin
  select * into strict v_check from one.checks where id = p_check_id;
  select * into v_inc from one.incidents where check_id = p_check_id and resolved_at is null for update;
  if found then
    v_new := array(select x from unnest(coalesce(p_subjects, '{}')) x where not x = any (v_inc.subjects));
    v_escalated := p_severity < v_inc.severity;
    update one.incidents
       set occurrences = occurrences + 1, last_seen_at = now(), evidence = p_evidence,
           severity = least(severity, p_severity)::one.severity,
           subjects = case when cardinality(coalesce(p_subjects, '{}')) > 0 then p_subjects else subjects end,
           acknowledged_at = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_at end,
           acknowledged_by = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_by end
     where id = v_inc.id;
    if v_escalated or cardinality(v_new) > 0 then
      perform one.route_incident(v_inc.id);
    end if;
    return v_inc.id;
  end if;
  -- Reopen, not duplicate, when the same check fails again within 24 h of recovering.
  select * into v_inc from one.incidents
   where check_id = p_check_id and resolved_at > now() - interval '24 hours' and resolution = 'recovered'
   order by resolved_at desc limit 1 for update;
  if found then
    update one.incidents
       set resolved_at = null, resolved_by = null, resolution = null, resolution_note = null,
           reopened_count = reopened_count + 1, reopened_at = now(), occurrences = occurrences + 1, last_seen_at = now(),
           evidence = p_evidence, severity = p_severity, acknowledged_at = null, acknowledged_by = null,
           subjects = coalesce(p_subjects, '{}')
     where id = v_inc.id
     returning * into v_inc;
    -- A check that flaps (its third reopen) is damped: listed in the digest and tagged, no email per flap (review F4).
    if v_inc.reopened_count >= 3 then
      update one.incidents set alert_state = 'digest', tags = case when 'flapping' = any (tags) then tags else array_append(tags, 'flapping') end
       where id = v_inc.id;
      return v_inc.id;
    end if;
  else
    insert into one.incidents (check_id, app, severity, title, evidence, first_evidence, tags, subjects)
    values (p_check_id, v_check.app, p_severity, v_check.title, p_evidence, p_evidence, v_check.tags, coalesce(p_subjects, '{}'))
    returning * into v_inc;
  end if;
  perform one.route_incident(v_inc.id);
  return v_inc.id;
end $$;

create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
begin
  -- The histories are append-only (D-085); this is the one step that may prune them.
  perform set_config('one.history_writer', 'on', true);
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (14); failures and errors stay
  -- results_days (90) for the incident pages and the comparisons (efficiency review 10).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 14)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 90));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept 30 days; a person's audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - interval '30 days';
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 180));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  delete from one.runs where started_at < now() - interval '30 days';
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit);
end $$;

create or replace function one.nightly() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:nightly', true, jsonb_build_object('at', now()), null, 90000);
  -- The day's bucket is the IST date at UTC midnight, whatever the session time zone (review F12).
  insert into one.runs (kind, bucket) values ('nightly', v_day::timestamp at time zone 'UTC') on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran today');
  end if;
  begin v_report := v_report || jsonb_build_object('privileges', one.privilege_audit());
  exception when others then v_report := v_report || jsonb_build_object('privileges_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('baselines', one.capture_baselines());
  exception when others then v_report := v_report || jsonb_build_object('baselines_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('retention', one.retention());
  exception when others then v_report := v_report || jsonb_build_object('retention_error', sqlerrm); end;
  begin
    -- A snooze ends: the proposal is back in the queue with a fresh expiry (the builder's never expire). Before the
    -- expiry step, so the snooze end it kept in expires_at does not expire it at once (phase review M2).
    update one.proposals
       set status = 'open',
           expires_at = case when source = 'builder' then null
                             else now() + make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14)) end
     where status = 'snoozed' and expires_at <= now();
    update one.proposals set status = 'expired' where status = 'open' and expires_at < now();
    v_report := v_report || jsonb_build_object('proposals_expired', true);
  exception when others then v_report := v_report || jsonb_build_object('proposals_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('test_purge', one.purge_test_rows());
  exception when others then v_report := v_report || jsonb_build_object('test_purge_error', sqlerrm); end;
  begin
    perform one.enqueue_ai('brief', jsonb_build_object('for_date', v_day), null, format('brief:%s', v_day));
    v_report := v_report || jsonb_build_object('brief', 'queued');
  exception when others then v_report := v_report || jsonb_build_object('brief_error', sqlerrm); end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
end $$;

create or replace procedure one.fixes_job(inout p_report jsonb default null)
language plpgsql as $$
declare
  v_out jsonb;
  r record;
  v text;
begin
  perform pg_catalog.set_config('search_path', '', false);
  -- A refusal in the window start must not abort the tick after its app call (review F9): the report says so instead.
  begin
    v_out := one.fixes_start_window() || one.fixes_verify_safe();
  exception when others then
    v_out := jsonb_build_object('fixes_window_error', left(sqlerrm, 200));
  end;
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

create or replace procedure one.tick_job()
language plpgsql as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now(), 'mode', 'job');
  v_id text;
  v_src record;
  v_fixes jsonb;
  v_pid integer;
  v_job record;
begin
  perform pg_catalog.set_config('search_path', '', false);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', coalesce(one.setting('checks') ->> 'transaction_timeout', '30s'), false);
  end if;
  if not pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('one.tick')) then
    -- Self-repair (D-085): a session of this role that has held the tick's lock for over 10 minutes is wedged; it is
    -- ended, the heartbeat says so (HB-one:tick's last_error), and the next minute runs. No heartbeat is written
    -- otherwise, so a blocked tick leaves it stale instead of refreshing it (review F2).
    v_pid := one.tick_lock_holder(interval '10 minutes');
    if v_pid is not null then
      perform pg_catalog.pg_terminate_backend(v_pid);
      perform one.heartbeat('one:tick', false, jsonb_build_object('at', now()),
                            format('tick lock broken: holder pid %s of this role terminated after 10 minutes', v_pid), 60);
      commit;
    end if;
    return;
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
    commit;
    return;
  end if;
  -- The heartbeat is written once the tick holds the lock and its minute (review F2).
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  v_report := v_report || one.reap_killed();
  update one.runs set report = v_report where id = v_run;
  commit;
  -- One commit per check (efficiency review 12, D-088): this check's start mark leaves with the previous check's results
  -- and the report in one transaction, so the mark is still committed before the run (B1) and a kill still takes only
  -- the run it hit; the phase ends with its own commit.
  for v_id in select one.due_checks(false) loop
    perform one.mark_started(v_id);
    update one.runs set report = v_report where id = v_run;
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
  end loop;
  update one.runs set report = v_report where id = v_run;
  commit;
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
  -- One commit per source, as for the checks (D-088); the report always carries an events key.
  v_report := jsonb_set(v_report, '{events}', coalesce(v_report -> 'events', '{}'));
  for v_src in select * from one.events_due() loop
    perform one.mark_source_started(v_src.source);
    update one.runs set report = v_report where id = v_run;
    commit;
    v_report := jsonb_set(v_report, '{events}', (v_report -> 'events') || one.events_copy_safe(v_src.source, v_src.app, v_src.sql));
  end loop;
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_id in select one.due_checks(true) loop
    perform one.mark_started(v_id);
    update one.runs set report = v_report where id = v_run;
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
  end loop;
  update one.runs set report = v_report where id = v_run;
  commit;
  -- Self-repair (D-085): Eduwit One's own two cron jobs are re-created when one is gone (review F5). A job a person
  -- set inactive is left alone: that is a choice, not a loss.
  for v_job in select * from (values ('one-tick', '* * * * *', 'call one.tick_job()'),
                                     ('one-nightly', '0 21 * * *', 'select one.nightly()')) j(name, sched, cmd) loop
    if not exists (select 1 from cron.job where jobname = v_job.name) then
      perform cron.schedule(v_job.name, v_job.sched, v_job.cmd);
      v_report := v_report || jsonb_build_object('rescheduled', v_job.name);
      update one.runs set report = v_report where id = v_run;
      commit;
    end if;
  end loop;
  perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
  commit;
end $$;

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
       -- A run is judged within its cooldown plus two cadences; nothing older waits (efficiency review 7).
       and a.ran_at > now() - interval '7 days'
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

create or replace function one.app_fixes_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v jsonb;
begin
  for r in
    select a.* from one.actions a join one.fixes f on f.id = a.fix_id
     where f.mode = 'app' and a.step = 'before' and not a.dry_run
       -- Every unreported run is closed within 15 minutes, so two days bounds the scan (efficiency review 7).
       and a.ran_at > now() - interval '2 days'
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

create or replace function one.ui_actions(p_fix text default null, p_app text default null, p_day date default null,
                                          p_limit integer default 100, p_before bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]') into v_rows from (
    select a.* from one.actions a
     where (p_fix is null or a.fix_id = p_fix) and (p_app is null or a.app = p_app)
       and (p_day is null or (a.ran_at >= (p_day::timestamp at time zone 'Asia/Kolkata') and a.ran_at < ((p_day + 1)::timestamp at time zone 'Asia/Kolkata'))) and (p_before is null or a.id < p_before)
     order by a.id desc limit v_limit) a;
  return jsonb_build_object('rows', v_rows, 'fixes', coalesce(one.setting('fixes'), '{}'),
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

create or replace function one.analytics_data(p_days integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_steps jsonb := coalesce(one.setting('analytics') -> 'funnel', '[]');
  v_out jsonb := jsonb_build_object('days', v_days);
  v_ms jsonb := '{}';
  v_t timestamptz := clock_timestamp();
begin
  with steps as (
    select s.ord, s.step ->> 'key' as key, s.step ->> 'label' as label, s.step -> 'match' as match
      from jsonb_array_elements(v_steps) with ordinality s(step, ord)),
  -- Patterns are matched against the distinct (app, type) pairs first, then the events join by equality (efficiency
  -- review 3: the per-event pattern test was the whole cost).
  kinds as (select distinct e.app, e.type from one.events e where e.occurred_at > v_from),
  matched as (
    select st.ord, k.app, k.type from steps st, kinds k
     where exists (select 1 from jsonb_array_elements(st.match) m
                    where (m ->> 'app' is null or k.app = m ->> 'app') and k.type like (m ->> 'type'))),
  hits as (
    select m.ord, e.lead_id, min(e.occurred_at) as at, count(*) as n
      from one.events e join matched m on m.app = e.app and m.type = e.type
     where e.occurred_at > v_from
     group by m.ord, e.lead_id),
  per_step as (
    select st.ord, st.key, st.label,
           coalesce((select sum(h.n) from hits h where h.ord = st.ord), 0) as events,
           (select count(distinct h.lead_id) from hits h where h.ord = st.ord and h.lead_id is not null) as leads,
           (select round(percentile_cont(0.5) within group (order by extract(epoch from h.at - p.at) / 60)::numeric, 1)
              from hits h join hits p on p.lead_id = h.lead_id and p.ord = st.ord - 1 and h.at >= p.at where h.ord = st.ord) as median_min_from_previous
      from steps st)
  select v_out || jsonb_build_object('funnel', coalesce(jsonb_agg(to_jsonb(p) order by p.ord), '[]')) into v_out from per_step p;
  v_out := v_out || jsonb_build_object('events_by_app', (select coalesce(jsonb_object_agg(app, n), '{}') from (
             select app, count(*) as n from one.events where occurred_at > v_from group by 1) s));
  v_ms := v_ms || jsonb_build_object('funnel', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('partners', (select coalesce(jsonb_agg(jsonb_build_object('partner', coalesce(p.display_name, p.name, a.partner_id::text), 'allocated', a.n,
                                                                                                  'accepted', a.acc, 'enrolled', a.enr, 'lost', a.lost) order by a.n desc), '[]')
      from (select partner_id, count(*) as n, count(accepted_at) as acc, count(*) filter (where outcome = 'enrolled' or stage = 'enrolled') as enr, count(lost_at) as lost
              from b2b.allocations where not coalesce(is_test, false) and created_at > v_from group by 1) a
      left join b2b.partners p on p.id = a.partner_id));
  exception when others then v_out := v_out || jsonb_build_object('partners_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('partners', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('counsellors', (select coalesce(jsonb_agg(jsonb_build_object('counsellor', coalesce(u.full_name, 'unassigned'), 'leads', t.n,
                                                                                                     'contacted', t.c, 'applied', t.a, 'enrolled', t.e,
                                                                                                     'median_first_contact_min', t.m) order by t.n desc), '[]')
      from (select owner_id, count(*) as n, count(contacted_at) as c, count(applied_at) as a, count(enrolled_at) as e,
                   round(percentile_cont(0.5) within group (order by first_contact_minutes)::numeric, 1) as m
              from b2c.fact_leads where not coalesce(is_test, false) and not coalesce(deleted, false) and assigned_at > v_from group by 1) t
      left join b2c.users u on u.user_id = t.owner_id));
  exception when others then v_out := v_out || jsonb_build_object('counsellors_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('counsellors', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  return v_out || jsonb_build_object('ms', v_ms);
end $$;

-- The Fixes page's counts in one grouped pass over one.actions instead of a lateral probe per row (efficiency review 2a);
-- the output is unchanged.
create or replace function one.ui_fixes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_win jsonb := one.fix_window();
begin
  return (
    with bk as (select distinct run_key from one.actions where step = 'before'),
    cnt as (
      select a.fix_id,
             count(*) filter (where a.step = 'dry_run') as dry_runs,
             count(*) filter (where a.step = 'after' and bk.run_key is not null) as runs,
             count(*) filter (where a.step = 'after' and bk.run_key is not null and a.status = 'failed') as failed,
             count(distinct a.proposal_id) filter (where a.step in ('after', 'skip') and bk.run_key is null) as proposals,
             count(*) filter (where a.step = 'skip') as skipped,
             count(*) filter (where a.step = 'verify' and a.status = 'done') as held,
             count(*) filter (where a.step = 'verify' and a.status = 'failed') as escalated,
             max(a.ran_at) as last_at
        from one.actions a left join bk on bk.run_key = a.run_key
       group by a.fix_id)
    select jsonb_build_object(
      'window', v_win,
      'fixes', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', f.id, 'app', f.app, 'title', f.title, 'checks', to_jsonb(f.checks), 'trigger', f.trigger, 'mode', f.mode,
          'what', f.what, 'grants', f.grants, 'rollback', f.rollback, 'app_functions', to_jsonb(f.app_functions),
          'settings', coalesce(one.setting('fixes') -> f.id, '{}'),
          'grants_state', one.fix_grants(f.id),
          'counts', jsonb_build_object('dry_runs', coalesce(c.dry_runs, 0), 'runs', coalesce(c.runs, 0), 'failed', coalesce(c.failed, 0),
                                       'proposals', coalesce(c.proposals, 0), 'skipped', coalesce(c.skipped, 0), 'held', coalesce(c.held, 0),
                                       'escalated', coalesce(c.escalated, 0), 'last_at', c.last_at),
          'recent', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
                       from (select * from one.actions where fix_id = f.id order by id desc limit 10) a),
          'open_incidents', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'severity', i.severity, 'title', i.title,
                                                                          'stopped', exists (select 1 from one.actions a where a.fix_id = f.id and a.incident_id = i.id
                                                                                                and a.step = 'verify' and a.status = 'failed'))
                                                       order by i.id), '[]')
                               from one.incidents i where i.check_id = any (f.checks) and i.resolved_at is null),
          'can_enable', not (v_win ->> 'running')::boolean and exists (select 1 from one.actions a where a.fix_id = f.id and a.dry_run))
        order by f.id), '[]') from one.fixes f left join cnt c on c.fix_id = f.id)));
end $$;

create or replace function one.ui_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_day timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  -- Heartbeats and today's events are read once each, not per app (efficiency review 11).
  return (with hb as (select h.app, max(h.last_ok_at) as last_ok_at, bool_and(h.ok) as ok from one.app_heartbeats() h group by h.app),
               ev as (select e.app, count(*) as n from one.events e where e.occurred_at >= v_day group by e.app)
          select jsonb_build_object(
    'apps', (select coalesce(jsonb_agg(t order by t.ord, t.key), '[]') from (
      select a.key, a.name, a.enabled, one.app_link(a.key) as link,
             case a.key when 'witty' then 1 when 'b2b' then 2 when 'b2c' then 3 when 'web' then 4 when 'influencer' then 5
                        when 'one' then 6 else 7 end as ord,
             (select jsonb_build_object('P1', count(*) filter (where i.severity = 'P1'), 'P2', count(*) filter (where i.severity = 'P2'),
                                        'P3', count(*) filter (where i.severity = 'P3'))
                from one.incidents i where i.app = a.key and i.resolved_at is null) as open,
             (select hb.last_ok_at from hb where hb.app = a.key) as last_heartbeat_at,
             (select hb.ok from hb where hb.app = a.key) as heartbeats_ok,
             coalesce((select ev.n from ev where ev.app = a.key), 0) as events_today,
             (select count(*) from one.checks c where c.app = a.key and c.enabled) as checks_on,
             (select count(*) from one.checks c where c.app = a.key and not c.enabled and c.disabled_reason like 'setup:%') as checks_waiting_setup
        from one.apps a) t),
    'actions', (select coalesce(jsonb_agg(x order by x.rank, x.at desc), '[]') from (
      select * from (
        select 'incident' as kind, i.id::text as id, i.severity as level, i.title, i.app, i.opened_at as at,
               case i.severity when 'P1' then 0 when 'P2' then 3 else 6 end as rank, '/incidents/' || i.id as href
          from one.incidents i where i.resolved_at is null and i.acknowledged_at is null and i.alert_state <> 'suppressed'
        union all
        select 'proposal', p.id::text, p.risk, p.title, p.app, p.created_at, case p.risk when 'high' then 1 when 'medium' then 4 else 7 end,
               '/proposals/' || p.id
          from one.proposals p where p.status = 'open'
        union all
        select 'test', t.id, t.severity, t.title, t.app, r.started_at, case t.severity when 'P1' then 2 else 5 end, '/tests#' || t.id
          from one.tests t join lateral (select * from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 1) r on true
         where t.enabled and r.ok = false
        union all
        select 'delivery', d.id::text, 'failed', 'An alert email failed: ' || coalesce(i.title, d.kind), coalesce(i.app, 'one'), d.created_at, 2,
               coalesce('/incidents/' || d.incident_id, '/audit')
          from one.deliveries d left join one.incidents i on i.id = d.incident_id
         where d.status = 'failed' and d.created_at > now() - interval '24 hours') u
      order by rank, at desc limit 10) x),
    'brief', (select jsonb_build_object('id', b.id, 'for_date', b.for_date, 'model', b.model, 'excerpt', left(b.body_md, 800))
                from one.briefs b order by b.for_date desc, b.id desc limit 1),
    'ai_today', (select jsonb_build_object('inr', coalesce(sum(cost_inr), 0), 'usd', coalesce(sum(cost_usd), 0), 'calls', count(*),
                                           'cap_inr', (one.setting('ai') ->> 'daily_cap_inr')::numeric)
                   from one.ai_calls where created_at >= v_day)));
end $$;

-- one.record_action was replaced by one.fix_record in 0019 and nothing calls it (efficiency review §3).
drop function if exists one.record_action(text, bigint, text, jsonb, boolean, text, jsonb, text, text);

insert into one.api_grants (fn, role, why) values
  ('one.ui_settings_restore(text,integer,text,text)', 'authenticated', 'Settings (0020): restore an earlier version as a new one (D-065, review F14)')
on conflict do nothing;
-- <<< hardening batch
-- >>> hardening batch 2 (the app token)
-- HMAC-SHA256 as lowercase hex, through pgcrypto wherever the platform keeps it (extensions on Supabase, public on
-- the local cluster). Used by one.job_call to sign the database's calls to the app (D-086).
create or replace function one.hmac_hex(p_message text, p_key text) returns text
language plpgsql immutable set search_path = '' as $$
begin
  return encode(extensions.hmac(p_message, p_key, 'sha256'), 'hex');
exception when undefined_function or invalid_schema_name then
  return encode(public.hmac(p_message, p_key, 'sha256'), 'hex');
end $$;

create or replace function one.job_call(p_path text, p_timeout_ms integer default 55000) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_base text := one.setting('app') ->> 'base_url';
  v_key text;
  v_ts text := floor(extract(epoch from now()))::bigint::text;
begin
  if p_path !~ '^/api/internal/[a-z0-9/-]+$' then
    raise exception 'one.job_call: bad path %', p_path using errcode = '22023';
  end if;
  -- https only (m15). A bad value is "not configured", and PLAT-05 reports it.
  if v_base is null or v_base !~ '^https://[^/\s]+$' then
    return null;
  end if;
  v_key := one.secret('one_internal_key');
  if v_key is null then
    return null;
  end if;
  return net.http_post(
    url := v_base || p_path,
    body := '{}'::jsonb,
    -- The key never travels: the call carries a token good for 90 seconds, HMAC-SHA256(key, "<ts>|<path>"), which
    -- pg_net's queue (readable by every role on production, D-028) cannot replay later (security review m6, D-086).
    headers := jsonb_build_object('content-type', 'application/json', 'x-one-token', v_ts || '.' || one.hmac_hex(v_ts || '|' || p_path, v_key)),
    timeout_milliseconds := greatest(1000, least(p_timeout_ms, 300000)));
end $$;
-- <<< hardening batch 2
-- >>> efficiency leftovers (D-088)
-- The Witty sources look a lead up by phone for each row they return; rows the overlap re-reads are skipped first now,
-- so the lookup runs only for rows not copied yet (efficiency review 17). Everything else is 0004's text.
create or replace function one.events_sources() returns table (source text, app text, sql text)
language sql immutable set search_path = '' as $src$
  values
  ('public.w2_events', 'witty', $$select r.id::text as source_id, r.created_at as occurred_at, r.type,
      (select sl.id from public.student_leads sl where sl.whatsapp_number = public.crm_norm_phone(r.phone) limit 1) as lead_id,
      'run'::text as actor_type, r.run_id as actor_id, to_jsonb(r) as payload, r.id as wm_id, null::timestamptz as wm_at
    from public.w2_events r where r.id > $1
     and not exists (select 1 from one.events e where e.app = 'witty' and e.source_table = 'public.w2_events' and e.source_id = r.id::text)
    order by r.id limit $3$$),
  ('public.w2_messages', 'witty', $$select r.id::text, r.created_at, 'msg.' || coalesce(r.direction, '?') || '.' || coalesce(r.kind, '?'),
      (select sl.id from public.student_leads sl where sl.whatsapp_number = public.crm_norm_phone(r.phone) limit 1),
      'model'::text, r.model,
      jsonb_build_object('direction', r.direction, 'kind', r.kind, 'reply_source', r.reply_source, 'latency_ms', r.latency_ms,
                         'prompt_tokens', r.prompt_tokens, 'output_tokens', r.output_tokens, 'verify_errors', r.verify_errors),
      r.id, null::timestamptz
    from public.w2_messages r where r.id > $1
     and not exists (select 1 from one.events e where e.app = 'witty' and e.source_table = 'public.w2_messages' and e.source_id = r.id::text)
    order by r.id limit $3$$),
  ('public.w2_outbox', 'witty', $$select r.id || ':' || r.status, coalesce(r.sent_at, r.created_at), 'outbox.' || r.status,
      case when r.crm_record_id ~ '^[0-9]+$' then r.crm_record_id::bigint end, 'outbox'::text, r.target,
      jsonb_build_object('status', r.status, 'attempts', r.attempts, 'target', r.target, 'event_type', r.event_type, 'last_error', left(r.last_error, 300)),
      null::bigint, coalesce(r.sent_at, r.created_at)
    from public.w2_outbox r where r.created_at > $2 order by r.id desc limit $3$$),
  ('b2b.events', 'b2b', $$select r.id::text, r.occurred_at, r.type, r.lead_id, r.actor_type, r.actor_id, to_jsonb(r), r.id, null::timestamptz
    from b2b.events r where r.id > $1 order by r.id limit $3$$),
  ('b2b.allocation_transitions', 'b2b', $$select r.id::text, r.at, 'allocation.' || r.to_status,
      (select a.lead_id from b2b.allocations a where a.id = r.allocation_id), r.actor_type, r.actor_id, to_jsonb(r), r.id, null::timestamptz
    from b2b.allocation_transitions r where r.id > $1 order by r.id limit $3$$),
  ('b2b.partner_events', 'b2b', $$select r.id::text, r.received_at, 'partner.' || coalesce(r.event_type, '?'), r.lead_id, 'partner'::text, r.partner_id::text,
      jsonb_build_object('status', r.status, 'result', left(r.result, 300), 'allocation_id', r.allocation_id, 'record_id', r.record_id), r.id, null::timestamptz
    from b2b.partner_events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.events', 'b2c', $$select r.id::text, r.at, r.type, r.lead_id, r.actor_type, r.actor_id::text, to_jsonb(r), r.id, null::timestamptz
    from b2c.events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.activities', 'b2c', $$select r.id::text, r.at, 'activity.' || coalesce(r.kind, '?'), r.lead_id, 'user'::text, r.actor_id::text,
      to_jsonb(r) - 'body' - 'meta', r.id, null::timestamptz
    from b2c.activities r where r.id > $1 order by r.id limit $3$$),
  ('b2c.audit_log', 'b2c', $$select r.id::text, r.at, 'audit.' || r.action, r.lead_id, 'user'::text, r.actor_id::text, to_jsonb(r) - 'detail', r.id, null::timestamptz
    from b2c.audit_log r where r.id > $1 order by r.id limit $3$$),
  ('public.web_funnel_events', 'web', $$select r.id::text, r.at, 'funnel.' || r.funnel || '.' || r.step, null::bigint, 'anon'::text, r.anon_id,
      to_jsonb(r), r.id, null::timestamptz
    from public.web_funnel_events r where r.id > $1 order by r.id limit $3$$),
  ('public.web_audit_log', 'web', $$select r.id::text, r.at, 'audit.' || r.action, null::bigint, 'staff'::text, r.actor_email,
      jsonb_build_object('entity', r.entity, 'entity_id', r.entity_id, 'request_id', r.request_id), r.id, null::timestamptz
    from public.web_audit_log r where r.id > $1 order by r.id limit $3$$),
  ('public.web_advisor_sessions', 'web', $$select x.source_id, x.at, x.type, x.lead_id, 'session'::text, x.session, x.payload, null::bigint, x.at from (
      select r.id || ':open' as source_id, r.created_at as at, 'advisor.open' as type, r.lead_id, r.id::text as session,
             jsonb_build_object('phase', r.phase, 'is_test', r.is_test) as payload from public.web_advisor_sessions r
      union all select r.id || ':escalate', r.escalated_at, 'advisor.escalate', r.lead_id, r.id::text, jsonb_build_object('classification', r.classification)
        from public.web_advisor_sessions r where r.escalated_at is not null
      union all select r.id || ':end', r.ended_at, 'advisor.end', r.lead_id, r.id::text,
             jsonb_build_object('turns', r.turns, 'cost_usd', r.cost_usd, 'readiness', r.readiness) from public.web_advisor_sessions r where r.ended_at is not null) x
    where x.at > $2 order by x.at desc limit $3$$),
  ('public.touchpoints', 'integrity', $$select r.id::text, r.occurred_at, 'touch.' || coalesce(r.event_type, '?'), r.lead_id, 'system'::text, r.source_system,
      to_jsonb(r) - 'payload', r.id, null::timestamptz
    from public.touchpoints r where r.id > $1 order by r.id limit $3$$),
  ('cron.job_run_details', 'platform', $$select d.runid::text, d.start_time, 'cron.failed', null::bigint, 'job'::text, j.jobname,
      jsonb_build_object('jobid', d.jobid, 'message', left(d.return_message, 300)), null::bigint, d.end_time
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
    where d.status = 'failed' and d.runid > (select max(x.runid) from cron.job_run_details x) - 20000 and d.start_time > $2
    order by d.runid desc limit $3$$),
  ('inf.domain_events', 'influencer', $$select r.id::text, r.occurred_at, r.type, null::bigint, 'user'::text, r.actor_id::text,
      jsonb_build_object('subject_type', r.subject_type, 'subject_id', r.subject_id), r.id, null::timestamptz
    from inf.domain_events r where r.id > $1 order by r.id limit $3$$),
  ('one.incidents', 'one', $$select r.id::text, r.opened_at, 'one.incident.' || lower(r.severity), null::bigint, 'one'::text, r.check_id,
      jsonb_build_object('check_id', r.check_id, 'app', r.app, 'severity', r.severity), r.id, null::timestamptz
    from one.incidents r where r.id > $1 order by r.id limit $3$$),
  ('one.actions', 'one', $$select r.id::text, r.ran_at, 'one.action.' || r.status, null::bigint, 'one'::text, r.fix_id,
      jsonb_build_object('fix_id', r.fix_id, 'dry_run', r.dry_run, 'incident_id', r.incident_id), r.id, null::timestamptz
    from one.actions r where r.id > $1 order by r.id limit $3$$)
$src$;

-- A JSON value cut down for a model's context (D-088): arrays keep their first p_items elements and say how many were
-- left out, strings their first p_chars characters; objects and scalars are kept, recursively.
create or replace function one.jsonb_compact(p jsonb, p_items integer default 5, p_chars integer default 200) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v jsonb;
  n integer;
begin
  case jsonb_typeof(p)
    when 'object' then
      select coalesce(jsonb_object_agg(e.key, one.jsonb_compact(e.value, p_items, p_chars)), '{}'::jsonb) into v from jsonb_each(p) e;
      return v;
    when 'array' then
      n := jsonb_array_length(p);
      select coalesce(jsonb_agg(one.jsonb_compact(a.value, p_items, p_chars) order by a.ord), '[]'::jsonb) into v
        from jsonb_array_elements(p) with ordinality a(value, ord) where a.ord <= p_items;
      return case when n > p_items then v || to_jsonb(format('… %s more', n - p_items)) else v end;
    when 'string' then
      return case when length(p #>> '{}') > p_chars then to_jsonb(left(p #>> '{}', p_chars) || '…') else p end;
    else
      return p;
  end case;
end $$;

create or replace function one.ai_incident_context(p_id bigint, p_kind text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_i one.incidents;
  v_c one.checks;
  v jsonb;
begin
  select * into v_i from one.incidents where id = p_id;
  if not found then
    raise exception 'no incident %', p_id using errcode = 'P0002';
  end if;
  select * into v_c from one.checks where id = v_i.check_id;
  v := jsonb_build_object(
    'incident', jsonb_build_object('id', v_i.id, 'check_id', v_i.check_id, 'app', v_i.app, 'severity', v_i.severity, 'title', v_i.title,
                                   'opened_at', v_i.opened_at, 'last_seen_at', v_i.last_seen_at, 'occurrences', v_i.occurrences,
                                   'reopened_count', v_i.reopened_count, 'acknowledged', v_i.acknowledged_at is not null,
                                   'resolved_at', v_i.resolved_at, 'resolution', v_i.resolution, 'subjects', to_jsonb(v_i.subjects),
                                   'tags', to_jsonb(v_i.tags), 'alert_state', v_i.alert_state, 'evidence', v_i.evidence,
                                   'first_evidence', v_i.first_evidence, 'summary', v_i.summary, 'root_cause', v_i.root_cause,
                                   'parent_id', v_i.parent_id,
                                   'minutes_open', round(extract(epoch from coalesce(v_i.resolved_at, now()) - v_i.opened_at) / 60)),
    'check', jsonb_build_object('id', v_c.id, 'app', v_c.app, 'title', v_c.title, 'description', v_c.description, 'kind', v_c.kind,
                                'severity', v_c.severity, 'cadence_s', v_c.cadence_s, 'tags', to_jsonb(v_c.tags), 'auto_fix_id', v_c.auto_fix_id,
                                'open_after', v_c.open_after, 'resolve_after', v_c.resolve_after,
                                'rule_sql', case when p_kind in ('explain', 'propose_fix', 'test_author') then left(v_c.sql, 4000) end),
    -- The newest result whole; the older ones compacted (arrays to 5 items, strings to 120 characters): they are the bulk
    -- of the context and the prompts cite their status, time and counts (efficiency review 13, D-088).
    'recent_results', (select coalesce(jsonb_agg(jsonb_build_object('at', r.ran_at, 'status', r.status,
                                                                    'value', case when r.rn = 1 then r.value else one.jsonb_compact(r.value, 5, 120) end,
                                                                    'error', left(r.error, 300), 'ms', r.duration_ms) order by r.ran_at desc), '[]')
                         from (select x.*, row_number() over (order by x.ran_at desc, x.id desc) as rn
                                 from one.results x where x.check_id = v_i.check_id order by x.ran_at desc, x.id desc
                                limit case when p_kind = 'classify' then 5 else 20 end) r),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'opened_at', h.opened_at, 'resolved_at', h.resolved_at, 'resolution', h.resolution,
                                                             'occurrences', h.occurrences,
                                                             'minutes_open', round(extract(epoch from coalesce(h.resolved_at, now()) - h.opened_at) / 60))
                                          order by h.opened_at desc), '[]')
                  from (select * from one.incidents where check_id = v_i.check_id and id <> v_i.id order by opened_at desc limit 10) h),
    'open_same_app', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'check_id', o.check_id, 'severity', o.severity, 'title', o.title,
                                                                   'opened_at', o.opened_at) order by o.opened_at desc), '[]')
                        from (select * from one.incidents where app = v_i.app and resolved_at is null and id <> v_i.id and check_id <> 'ONE-SYNTH'
                               order by opened_at desc limit 15) o),
    'children', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'check_id', c.check_id, 'app', c.app, 'severity', c.severity, 'title', c.title)
                                           order by c.id), '[]')
                   from (select * from one.incidents where parent_id = v_i.id order by id limit 30) c),
    'heartbeats_down', (select coalesce(jsonb_agg(jsonb_build_object('component', h.component, 'last_ok_at', h.last_ok_at, 'last_error_at', h.last_error_at,
                                                                     'last_error', left(h.last_error, 200)) order by h.component), '[]')
                          from one.heartbeats h where h.last_error_at is not null and h.last_error_at > coalesce(h.last_ok_at, '-infinity')),
    'fixes_run', (select coalesce(jsonb_agg(jsonb_build_object('fix_id', a.fix_id, 'status', a.status, 'dry_run', a.dry_run, 'at', a.ran_at) order by a.ran_at desc), '[]')
                    from (select * from one.actions where incident_id = v_i.id order by ran_at desc limit 10) a),
    'ai_notes', (select coalesce(jsonb_agg(jsonb_build_object('kind', t.kind, 'result', t.result - 'meta', 'at', t.created_at) order by t.id desc), '[]')
                   from (select * from one.ai_tasks where incident_id = v_i.id and status = 'done' and kind in ('classify', 'triage', 'explain')
                          order by id desc limit 5) t));
  if p_kind = 'test_author' then
    v := v || jsonb_build_object('tests', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'app', t.app, 'title', t.title, 'enabled', t.enabled,
                                                                                       'description', t.description) order by t.id), '[]')
                                             from one.tests t));
  end if;
  v := one.redact(v, one.pii_keys());
  if p_kind = 'explain' and v_i.app = 'witty' and coalesce((one.setting('ai') ->> 'allow_message_excerpts')::boolean, false) then
    v := v || jsonb_build_object('messages', one.ai_witty_excerpts(v_i.opened_at));
  end if;
  return v;
end $$;
-- <<< efficiency leftovers
call one.apply_grants();
