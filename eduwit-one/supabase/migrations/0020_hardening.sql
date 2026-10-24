-- 0020 hardening: the AI's set-up and running tools (D-083). Redefines one.ai_tool_data (0018) with five more read-only
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

-- No new API grant: the worker reaches these through one.ai_tool(bigint,text,text,jsonb) (0018).
call one.apply_grants();
