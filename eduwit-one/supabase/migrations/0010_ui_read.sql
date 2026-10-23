-- 0010 what the pages read (spec §12, phase 4). Each function is SECURITY DEFINER, starts with one.ui_require(), and
-- returns the JSON one page needs. None returns contact data: copied events are redacted when copied (D-046), check
-- values carry counts and ids, and the users list shows only staff addresses. Executable by authenticated only
-- (one.api_grants, D-055); the pages call them with the signed-in person's own session (D-058).

-- Which components' heartbeats belong to which app: the HB-* checks carry the app, the component is the id's tail.
create or replace function one.app_heartbeats() returns table (app text, component text, last_ok_at timestamptz, ok boolean)
language sql stable set search_path = '' as $$
  select c.app, substr(c.id, 4), h.last_ok_at, (one.heartbeat_state(substr(c.id, 4)) ->> 'ok')::boolean
    from one.checks c left join one.heartbeats h on h.component = substr(c.id, 4)
   where c.kind = 'heartbeat' and c.enabled
$$;

-- The deep link of each app, from Settings → Hosts (spec §3: Eduwit One links into the apps, it does not redo them).
create or replace function one.app_link(p_app text) returns text
language sql stable set search_path = '' as $$
  select one.setting('hosts') ->> case p_app when 'b2b' then 'b2b_app' when 'b2c' then 'spark' when 'web' then 'website'
                                             when 'influencer' then 'influencer' when 'witty' then 'chatwoot' when 'one' then 'one' end
$$;

-- Whether a proposal needs the owner's approval: any kind that touches money, allocation, live switches, partner
-- mappings, prompts or versioned settings (the owner's rule), and every fix or config proposal that does not say
-- what it touches. When unsure, the owner decides (writes less).
create or replace function one.proposal_sensitive(p_kind text, p_change jsonb) returns boolean
language sql immutable set search_path = '' as $$
  -- A proposal cannot vouch for itself (phase review M5): a fix or config proposal names an app function whose effect
  -- the database cannot judge, so it is always the owner's; so is anything touching money, allocation, switches,
  -- partner mappings, prompts, settings, or security (keys, auth, data, retention, staging; security review S6).
  select p_kind in ('fix', 'config')
      or coalesce(p_change -> 'touches', '[]') ?| array['money', 'allocation', 'live_switches', 'partner_mappings', 'prompts', 'versioned_settings',
                                                        'api_keys', 'credentials', 'auth', 'auth_settings', 'database_security', 'data_retention',
                                                        'staging', 'security']
      or coalesce(p_change, '{}')::text ~* '(allocat|earning|commission|payout|ledger|invoice|live_switch|partner_(map|course)|prompt|settings_put|set_setting)'
$$;

-- The banner and counts on every page (spec §12 behaviours).
create or replace function one.ui_shell() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_fixes jsonb := coalesce(one.setting('fixes'), '{}');
begin
  return jsonb_build_object(
    'me', (select jsonb_build_object('email', o.email, 'role', o.role) from one.users o where o.user_id = one.uid()),
    'now', now(),
    'tick_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'open', (select jsonb_build_object('P1', count(*) filter (where severity = 'P1'), 'P2', count(*) filter (where severity = 'P2'),
                                       'P3', count(*) filter (where severity = 'P3'))
               from one.incidents where resolved_at is null),
    'unacked_p1', (select count(*) from one.incidents
                    where resolved_at is null and severity = 'P1' and acknowledged_at is null and alert_state not in ('suppressed', 'muted')),
    'proposals_open', (select count(*) from one.proposals where status = 'open'),
    -- Mutes and maintenance windows in force, so a silenced check or app is visible on every page.
    'mutes_active', (select count(*) from one.mutes m where now() between m.starts_at and m.ends_at)
                  + (select count(*) from one.checks c where c.muted_until > now()),
    'observation_until', case when v_fixes ->> 'observation_started_at' is not null
                              then (v_fixes ->> 'observation_started_at')::timestamptz + make_interval(days => coalesce((v_fixes ->> 'observation_days')::int, 14)) end,
    'setup_open', (select count(*) from jsonb_each(coalesce(one.setting('setup') -> 'items', '{}')) i
                    where not coalesce((i.value ->> 'validated')::boolean, false) and i.value ->> 'status' is distinct from 'not_applicable'),
    'whatsapp_alerts', coalesce((one.setting('alerts') #>> '{channels,whatsapp}')::boolean, false));
end $$;

-- The overview (spec §12): a tile per app, the action list, the latest brief and today's AI spend.
create or replace function one.ui_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_day timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  return jsonb_build_object(
    'apps', (select coalesce(jsonb_agg(t order by t.ord, t.key), '[]') from (
      select a.key, a.name, a.enabled, one.app_link(a.key) as link,
             case a.key when 'witty' then 1 when 'b2b' then 2 when 'b2c' then 3 when 'web' then 4 when 'influencer' then 5
                        when 'one' then 6 else 7 end as ord,
             (select jsonb_build_object('P1', count(*) filter (where i.severity = 'P1'), 'P2', count(*) filter (where i.severity = 'P2'),
                                        'P3', count(*) filter (where i.severity = 'P3'))
                from one.incidents i where i.app = a.key and i.resolved_at is null) as open,
             (select max(h.last_ok_at) from one.app_heartbeats() h where h.app = a.key) as last_heartbeat_at,
             (select bool_and(h.ok) from one.app_heartbeats() h where h.app = a.key) as heartbeats_ok,
             (select count(*) from one.events e where e.app = a.key and e.occurred_at >= v_day) as events_today,
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
                   from one.ai_calls where created_at >= v_day));
end $$;

-- The incident list, newest first, keyset-paged by id.
create or replace function one.ui_incidents(p_status text default 'open', p_app text default null, p_severity text default null,
                                            p_q text default null, p_limit integer default 50, p_before bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id desc), '[]') into v_rows from (
    select i.id, i.check_id, i.app, i.severity, i.title, i.opened_at, i.last_seen_at, i.occurrences, i.reopened_count,
           i.acknowledged_at, i.acknowledged_by, i.resolved_at, i.resolution, i.alert_state, i.summary, i.subjects, i.parent_id
      from one.incidents i
     where (p_status = 'all' or (p_status = 'resolved') = (i.resolved_at is not null))
       and (p_app is null or i.app = p_app) and (p_severity is null or i.severity = p_severity)
       and (p_q is null or i.title ilike '%' || p_q || '%' or i.check_id ilike '%' || p_q || '%')
       and (p_before is null or i.id < p_before)
     order by i.id desc limit v_limit) r;
  return jsonb_build_object('rows', v_rows,
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

-- One incident with everything its page shows (spec §12 Incidents detail).
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
    'incident', to_jsonb(v_inc),
    'check', (select jsonb_build_object('id', c.id, 'title', c.title, 'description', c.description, 'kind', c.kind, 'severity', c.severity,
                                        'cadence_s', c.cadence_s, 'sql', c.sql, 'tags', c.tags, 'auto_fix_id', c.auto_fix_id, 'enabled', c.enabled,
                                        'disabled_reason', c.disabled_reason, 'open_after', c.open_after, 'resolve_after', c.resolve_after,
                                        'muted', one.is_muted(c.id, c.app),
                                        'fix_enabled', coalesce((one.setting('fixes') -> c.auto_fix_id ->> 'enabled')::boolean, false))
                from one.checks c where c.id = v_inc.check_id),
    'results', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'ran_at', r.ran_at, 'status', r.status, 'value', r.value,
                                                            'error', r.error, 'duration_ms', r.duration_ms) order by r.id desc), '[]')
                  from (select * from one.results where check_id = v_inc.check_id order by id desc limit 30) r),
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

-- Every auto-fix and approved execution (spec §12 Actions), filtered by fix, app and IST day.
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
       and (p_day is null or (a.ran_at at time zone 'Asia/Kolkata')::date = p_day) and (p_before is null or a.id < p_before)
     order by a.id desc limit v_limit) a;
  return jsonb_build_object('rows', v_rows, 'fixes', coalesce(one.setting('fixes'), '{}'),
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

-- The proposal queue (spec §12 Proposals), with whether approving needs the owner.
create or replace function one.ui_proposals(p_status text default 'open', p_kind text default null, p_limit integer default 100,
                                            p_before bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(r order by r.id desc), '[]') into v_rows from (
    select p.id, p.kind, p.app, p.title, p.risk, p.source, p.status, p.created_at, p.decided_by, p.decided_at, p.expires_at, p.incident_id,
           one.proposal_sensitive(p.kind, p.change) as owner_only, left(p.rationale, 300) as rationale
      from one.proposals p
     where (p_status = 'all' or p.status = p_status) and (p_kind is null or p.kind = p_kind) and (p_before is null or p.id < p_before)
     order by p.id desc limit v_limit) r;
  return jsonb_build_object('rows', v_rows,
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

create or replace function one.ui_proposal(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select jsonb_build_object(
      'proposal', to_jsonb(p),
      'owner_only', one.proposal_sensitive(p.kind, p.change),
      'incident', (select jsonb_build_object('id', i.id, 'check_id', i.check_id, 'title', i.title, 'severity', i.severity, 'resolved_at', i.resolved_at)
                     from one.incidents i where i.id = p.incident_id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'actor', a.actor, 'action', a.action, 'after', a.after) order by a.id), '[]')
                    from one.audit a where a.target = 'proposal:' || p.id))
    from one.proposals p where p.id = p_id);
end $$;

-- The synthetic test catalogue with its last 30 runs (spec §12 Tests).
create or replace function one.ui_tests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'app', t.app, 'title', t.title, 'schedule', t.schedule, 'severity', t.severity, 'timeout_s', t.timeout_s,
      'enabled', t.enabled, 'disabled_reason', t.disabled_reason, 'steps', jsonb_array_length(t.steps),
      'run_requested_at', t.run_requested_at,
      'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'started_at', r.started_at, 'finished_at', r.finished_at, 'ok', r.ok,
                                                           'duration_ms', round(extract(epoch from r.finished_at - r.started_at) * 1000),
                                                           'steps', r.step_results) order by r.started_at desc), '[]')
                 from (select * from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 30) r)) order by t.id), '[]')
    from one.tests t);
end $$;

create or replace function one.ui_briefs(p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'for_date', b.for_date, 'tier', b.tier, 'model', b.model, 'cost_usd', b.cost_usd,
                                                      'sent_at', b.sent_at, 'excerpt', left(b.body_md, 400)) order by b.for_date desc, b.id desc), '[]')
    from (select * from one.briefs order by for_date desc, id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) b);
end $$;

create or replace function one.ui_brief(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select jsonb_build_object('brief', to_jsonb(b),
      'pins', (select coalesce(jsonb_agg(jsonb_build_object('task_id', p.task_id, 'question', t.input ->> 'question', 'answer', t.result ->> 'answer',
                                                           'pinned_by', p.pinned_by, 'at', p.created_at) order by p.created_at), '[]')
                 from one.brief_pins p join one.ai_tasks t on t.id = p.task_id where p.for_date = b.for_date))
    from one.briefs b where b.id = p_id);
end $$;

-- The audit trail and the AI call log (spec §12 Audit), newest first.
create or replace function one.ui_audit(p_kind text default 'audit', p_q text default null, p_limit integer default 100,
                                        p_before bigint default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 1000);
  v_rows jsonb;
begin
  if p_kind = 'ai_calls' then
    select coalesce(jsonb_agg(to_jsonb(c) order by c.id desc), '[]') into v_rows
      from (select * from one.ai_calls c where (p_before is null or c.id < p_before)
              and (p_q is null or c.model ilike '%' || p_q || '%' or c.purpose ilike '%' || p_q || '%') order by c.id desc limit v_limit) c;
  else
    select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]') into v_rows
      from (select * from one.audit a where (p_before is null or a.id < p_before)
              and (p_q is null or a.actor ilike '%' || p_q || '%' or a.action ilike '%' || p_q || '%' or a.target ilike '%' || p_q || '%')
             order by a.id desc limit v_limit) a;
  end if;
  return jsonb_build_object('rows', v_rows,
    'next_before', case when jsonb_array_length(v_rows) = v_limit then (v_rows -> (v_limit - 1) ->> 'id')::bigint end);
end $$;

-- Settings with their version (spec §12 Settings), and which keys only the owner may change.
create or replace function one.ui_settings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_object_agg(s.key, jsonb_build_object('value', s.value, 'version', s.version, 'actor', s.actor,
                                                                     'updated_at', s.updated_at, 'owner_only', one.setting_owner_only(s.key))), '{}')
    from one.settings s where s.key not in ('setup', 'setup_catalog'));
end $$;

create or replace function one.ui_setting_versions(p_key text, p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'value', v.value, 'reason', v.reason, 'actor', v.actor, 'at', v.at)
                                    order by v.version desc), '[]')
    from (select * from one.settings_versions where key = p_key order by version desc limit least(greatest(coalesce(p_limit, 20), 1), 200)) v);
end $$;

-- Keys only the owner may change: fixes (the owner's rule: nothing switches on without their approval), access and
-- users, the PII list, proposal approvers, retention. In alerts, only the recipients are the owner's (spec §12); the
-- write function compares them (one.alert_recipients).
-- Engineers tune how the checks and tests run; every other key is the owner's, because it decides where a credential,
-- an alert or a sign-in code is sent (app.base_url, hosts, vendors, chatwoot, n8n, whatsapp, alerts), what is spent
-- (ai), what is kept (events, retention) or who gets in (access) (security review S1, phase review M6).
create or replace function one.setting_owner_only(p_key text) returns boolean
language sql immutable set search_path = '' as $$
  select p_key not in ('thresholds', 'checks', 'tests', 'witty', 'analytics')
$$;

create or replace function one.alert_recipients(p_alerts jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('p1', p_alerts -> 'p1', 'second', p_alerts #> '{escalation,second_contact}',
                            'developer', p_alerts -> 'developer_email', 'from', p_alerts -> 'email_from')
$$;

-- The Setup checklist (spec §15): each item's description, who fills it, what it unblocks, its status, and whether
-- the Vault secrets it names exist (names only).
create or replace function one.ui_setup() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(c.item || jsonb_build_object(
      'state', coalesce(one.setting('setup') -> 'items' -> (c.item ->> 'id'), '{}'),
      'secrets', (select coalesce(jsonb_agg(jsonb_build_object('name', m[1], 'present', exists (select 1 from one.vault_names() v where v = m[1]))), '[]')
                    from regexp_matches(c.item ->> 'stores', 'vault:([a-z0-9_]+)', 'g') m),
      'waiting', (select coalesce(jsonb_agg(k.id order by k.id), '[]') from one.checks k where k.disabled_reason = 'setup:' || (c.item ->> 'id'))
    ) order by c.ord), '[]')
    from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) with ordinality c(item, ord));
end $$;

-- Checks with their state, for Settings → Checks (thresholds per check) and the Apps pages.
create or replace function one.ui_checks(p_app text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'app', c.app, 'title', c.title, 'kind', c.kind, 'severity', c.severity, 'cadence_s', c.cadence_s, 'threshold', c.threshold,
      'open_after', c.open_after, 'resolve_after', c.resolve_after, 'enabled', c.enabled, 'disabled_reason', c.disabled_reason, 'tags', c.tags,
      'version', c.version, 'updated_by', c.updated_by, 'last_status', s.last_status, 'last_ran_at', s.last_ran_at, 'killed_count', s.killed_count,
      'muted', one.is_muted(c.id, c.app),
      'open_incident', (select i.id from one.incidents i where i.check_id = c.id and i.resolved_at is null)) order by c.app, c.id), '[]')
    from one.checks c left join one.check_state s on s.check_id = c.id
   where p_app is null or c.app = p_app);
end $$;

create or replace function one.ui_mutes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('active', m.ends_at > now() and m.starts_at <= now()) order by m.ends_at desc), '[]')
    from (select * from one.mutes order by ends_at desc limit 100) m);
end $$;

-- Heartbeats with their verdict (Overview tiles, Apps pages, Setup).
create or replace function one.ui_heartbeats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(one.heartbeat_state(substr(c.id, 4)) || jsonb_build_object('app', c.app, 'check_id', c.id, 'enabled', c.enabled,
                                                                                               'disabled_reason', c.disabled_reason) order by c.app, c.id), '[]')
    from one.checks c where c.kind = 'heartbeat');
end $$;

-- Users and their sign-ins (owner only): staff addresses, roles, last sign-in, trusted devices.
create or replace function one.ui_users() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
begin
  return jsonb_build_object(
    'users', (select coalesce(jsonb_agg(jsonb_build_object('user_id', o.user_id, 'email', o.email, 'role', o.role, 'is_active', o.is_active,
        'last_sign_in', (select max(l.at) from one.sign_in_log l where l.user_id = o.user_id and l.outcome = 'success'),
        'devices', (select count(*) from one.trusted_devices d where d.user_id = o.user_id and d.revoked_at is null and d.expires_at > now())) order by o.email), '[]')
      from one.users o),
    'sign_ins', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'email', l.email, 'method', l.method, 'outcome', l.outcome) order by l.id desc), '[]')
                   from (select * from one.sign_in_log order by id desc limit 100) l));
end $$;

create or replace function one.ui_privileges() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return jsonb_build_object(
    'functions', (select coalesce(jsonb_agg(to_jsonb(b) order by b.acknowledged, b.schema, b.fn), '[]') from one.privilege_baseline b),
    'baselines', (select coalesce(jsonb_agg(jsonb_build_object('key', b.key, 'captured_at', b.captured_at, 'acknowledged_by', b.acknowledged_by) order by b.key), '[]')
                    from one.baselines b),
    'vault', (select coalesce(jsonb_agg(v order by v), '[]') from one.vault_names() v));
end $$;

-- The Ask page: questions and their answers (spec §12 Ask); the AI worker answers them (phase 6).
create or replace function one.ui_asks(p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'question', t.input ->> 'question', 'asked_by', t.input ->> 'asked_by',
                                                      'status', t.status, 'result', t.result, 'error', t.error, 'created_at', t.created_at,
                                                      'pinned', exists (select 1 from one.brief_pins p where p.task_id = t.id)) order by t.id desc), '[]')
    from (select * from one.ai_tasks where kind = 'ask' order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) t);
end $$;

-- Answers pinned to a day's brief (spec §12 Ask: "pin an answer to the brief"), and saved Analytics views.
create table one.brief_pins (
  task_id bigint primary key references one.ai_tasks (id),
  for_date date not null,
  pinned_by text not null,
  created_at timestamptz not null default now()
);

create table one.saved_views (
  id bigint generated always as identity primary key,
  page text not null check (page in ('analytics', 'marketing')),
  name text not null check (length(name) between 1 and 80),
  params jsonb not null default '{}',
  schedule text check (schedule is null or schedule in ('daily', 'weekly')),
  created_by text not null,
  created_at timestamptz not null default now(),
  unique (page, name)
);

insert into one.api_grants (fn, role, why)
select f, 'authenticated', 'page read (0010)' from unnest(array[
  'one.ui_shell()', 'one.ui_overview()', 'one.ui_incidents(text,text,text,text,integer,bigint)', 'one.ui_incident(bigint)',
  'one.ui_actions(text,text,date,integer,bigint)', 'one.ui_proposals(text,text,integer,bigint)', 'one.ui_proposal(bigint)',
  'one.ui_tests()', 'one.ui_briefs(integer)', 'one.ui_brief(bigint)', 'one.ui_audit(text,text,integer,bigint)', 'one.ui_settings()',
  'one.ui_setting_versions(text,integer)', 'one.ui_setup()', 'one.ui_checks(text)', 'one.ui_mutes()', 'one.ui_heartbeats()',
  'one.ui_users()', 'one.ui_privileges()', 'one.ui_asks(integer)']) f
on conflict do nothing;
call one.apply_grants();
