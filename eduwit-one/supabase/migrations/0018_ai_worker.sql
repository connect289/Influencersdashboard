-- 0018 the AI worker's database side (spec §11). Detection stays the checks' SQL: everything here only queues advice,
-- builds what a model may read and files what it wrote. The AI never decides what is broken, never changes a check,
-- an alert or another app, and writes only to schema one: an incident's summary and likely cause, briefs, its own
-- task results and open proposals that a person decides (D-075).
--
--   one.ai_schedule()   queues advisory tasks by fixed rules (classify each new incident, explain one open 15 min,
--                       propose a fix after an hour, a weekly feature review, a test idea after a fix), each once;
--   one.ai_step()       runs the schedule and calls the app's worker when a task is due (from the minute tick's app
--                       call: no new cron job);
--   one.ai_claim()      hands the worker one task, the settings and the data it may read, after the budget gate:
--                       at queue_non_triage_at_pct (80%) of today's cap only classify and triage run, at the cap none
--                       (ONE-01 reports it), the rest wait as "deferred" and resume when the budget allows;
--   one.ai_finish(), ai_fail(), ai_defer()   the worker's verdict, with every model call it made (one.ai_calls);
--   one.ai_tool()       Ask's tools: fixed, parameterised reads with Eduwit One's rights, redacted, read-only, and only
--                       for an Ask task the caller holds. No SQL text from a model is ever run (D-076).
--
-- Every context and tool answer passes one.redact() here, and the worker masks it again (lib/ai/pii.ts) before a
-- model sees it. App tables are read from PL/pgSQL bodies, so a missing one fails that read, not this migration.

alter table one.ai_tasks
  add column deferred_reason text,
  add column not_before timestamptz;
create index ai_tasks_open_idx on one.ai_tasks (status, id) where status in ('pending', 'deferred', 'claimed');

alter table one.briefs add column task_id bigint references one.ai_tasks (id);
alter table one.deliveries add column brief_id bigint references one.briefs (id);

-- Helpers ----------------------------------------------------------------------------------------------------------

-- Today's AI spend in rupees, IST day (the same sum ONE-01 compares with the cap).
create or replace function one.ai_spent_today() returns numeric
language sql stable set search_path = '' as $$
  select coalesce(sum(cost_inr), 0) from one.ai_calls
   where created_at >= (((now() at time zone 'Asia/Kolkata')::date)::timestamp at time zone 'Asia/Kolkata')
$$;

-- Claim order: what a person or an alert waits for first.
create or replace function one.ai_priority(p_kind text) returns integer
language sql immutable set search_path = '' as $$
  select case p_kind when 'triage' then 1 when 'classify' then 2 when 'ask' then 3 when 'explain' then 4 when 'brief' then 5
                     when 'propose_fix' then 6 when 'test_author' then 7 when 'propose_feature' then 8 else 9 end
$$;

-- High-risk incidents get the deep tier for fix proposals (settings.ai.routing.propose_fix_high_risk).
create or replace function one.ai_high_risk(p_incident one.incidents) returns boolean
language sql stable set search_path = '' as $$
  select p_incident.severity = 'P1' or p_incident.app = 'integrity'
      or exists (select 1 from one.checks c where c.id = p_incident.check_id
                  and (c.kind = 'integrity' or c.tags && array['money', 'security', 'consent', 'allocation', 'integrity']))
$$;

-- A model's risk word, never below the floor the incident sets (a proposal cannot make itself harmless).
create or replace function one.ai_risk(p_said text, p_floor text) returns text
language sql immutable set search_path = '' as $$
  select (array['low', 'medium', 'high'])[greatest(coalesce(array_position(array['low', 'medium', 'high'], p_said), 2),
                                                   coalesce(array_position(array['low', 'medium', 'high'], p_floor), 1))]
$$;

-- What an AI proposal touches: the model's list, kept only where it names a known kind, plus "ai_written", which
-- one.proposal_sensitive treats as the owner's. A model's own words never lower who decides (review B1).
create or replace function one.ai_touches(p_touches jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(distinct t order by t), '[]'::jsonb)
    from (select x as t from jsonb_array_elements_text(case when jsonb_typeof(p_touches) = 'array' then p_touches else '[]' end) x
           where x ~ '^[a-z_]{2,40}$'
          union select 'ai_written') s
$$;

-- 0010's rule, plus: every proposal the AI wrote is the owner's to approve (review B1, D-077).
create or replace function one.proposal_sensitive(p_kind text, p_change jsonb) returns boolean
language sql immutable set search_path = '' as $$
  -- A proposal cannot vouch for itself (phase review M5): a fix or config proposal names an app function whose effect
  -- the database cannot judge, so it is always the owner's; so is anything touching money, allocation, switches,
  -- partner mappings, prompts, settings, or security (keys, auth, data, retention, staging; security review S6), and
  -- anything the AI wrote (D-077).
  select p_kind in ('fix', 'config')
      or coalesce(p_change -> 'touches', '[]') ?| array['money', 'allocation', 'live_switches', 'partner_mappings', 'prompts', 'versioned_settings',
                                                        'api_keys', 'credentials', 'auth', 'auth_settings', 'database_security', 'data_retention',
                                                        'staging', 'security', 'ai_written']
      or coalesce(p_change, '{}')::text ~* '(allocat|earning|commission|payout|ledger|invoice|live_switch|partner_(map|course)|prompt|settings_put|set_setting)'
$$;

-- Marketing and Analytics as data, for the pages and for Ask (the pages keep their sign-in check) -----------------

create or replace function one.marketing_data(p_days integer) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 180);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_out jsonb := jsonb_build_object('days', v_days);
  v_ms jsonb := '{}';
  v_t timestamptz;
begin
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('leads', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'platform', p, 'campaign', c, 'leads', n) order by d desc, n desc), '[]')
      from (select (touched_at at time zone 'Asia/Kolkata')::date as d, coalesce(platform, 'organic') as p, coalesce(campaign_name, utm_campaign, '—') as c, count(*) as n
              from b2b.lead_campaigns lc
             where lc.touched_at > v_from
               and not exists (select 1 from public.student_leads l where l.id = lc.lead_id and coalesce(l.is_test, false))
             group by 1, 2, 3) s));
  exception when others then v_out := v_out || jsonb_build_object('leads_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('leads', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('touchpoints', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'source', s, 'event', e, 'n', n) order by d desc), '[]')
      from (select (occurred_at at time zone 'Asia/Kolkata')::date as d, coalesce(source_system, '?') as s, event_type as e, count(*) as n
              from public.touchpoints tp
             where tp.occurred_at > v_from and regexp_replace(coalesce(tp.phone, ''), '\D', '', 'g') !~ '^910000[0-9]{6}$'
               and not exists (select 1 from public.student_leads l where l.id = tp.lead_id and coalesce(l.is_test, false))
             group by 1, 2, 3) t));
  exception when others then v_out := v_out || jsonb_build_object('touchpoints_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('touchpoints', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('spend', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'b2b_inr', b, 'b2c_inr', c) order by d desc), '[]')
      from (select coalesce(x.day, y.day) as d, x.b, y.c
              from (select day, sum(spend_inr) as b from b2b.ad_spend_daily where day > v_from::date group by 1) x
              full join (select day, sum(spend) as c from b2c.ad_spend_daily where day > v_from::date group by 1) y on y.day = x.day) s));
  exception when others then v_out := v_out || jsonb_build_object('spend_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('spend', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('nurture', b2c.nurture_overview());
  exception
    when insufficient_privilege then v_out := v_out || jsonb_build_object('nurture_error', 'needs your Spark marketing access');
    when others then v_out := v_out || jsonb_build_object('nurture_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('nurture', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_out := v_out || jsonb_build_object('numbers', (select coalesce(jsonb_agg(one.heartbeat_state(h.component) || jsonb_build_object('detail', h.detail) order by h.component), '[]')
                                                     from one.heartbeats h where h.component like 'whatsapp:%'));
  return one.redact(v_out, one.pii_keys()) || jsonb_build_object('ms', v_ms);
end $$;

create or replace function one.ui_marketing(p_days integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return one.marketing_data(p_days);
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
  hits as (
    select st.ord, e.lead_id, min(e.occurred_at) as at, count(*) as n
      from steps st join one.events e on e.occurred_at > v_from
       and exists (select 1 from jsonb_array_elements(st.match) m
                    where (m ->> 'app' is null or e.app = m ->> 'app') and e.type like (m ->> 'type'))
     group by st.ord, e.lead_id),
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

create or replace function one.ui_analytics(p_days integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return one.analytics_data(p_days) || jsonb_build_object('views', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'params', v.params, 'schedule', v.schedule,
                                                                                                                  'created_by', v.created_by) order by v.name), '[]')
                                                                      from one.saved_views v where v.page = 'analytics'));
end $$;

-- What a model may read --------------------------------------------------------------------------------------------

-- Witty's replies around an incident, only for explain on a Witty incident and only while ai.allow_message_excerpts is
-- on (off by default). No phone; test traffic left out; each text cut to 280 characters and masked again in the app.
create or replace function one.ai_witty_excerpts(p_at timestamptz) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('at', m.created_at, 'direction', m.direction, 'kind', m.kind, 'text', left(m.content, 280),
                                                       'reply_source', m.reply_source, 'latency_ms', m.latency_ms) order by m.created_at), '[]')
            from (select w.* from public.w2_messages w
                   where w.created_at between p_at - interval '30 minutes' and p_at + interval '10 minutes'
                     and regexp_replace(coalesce(w.phone, ''), '\D', '', 'g') !~ '^910000[0-9]{6}$'
                     and not exists (select 1 from public.w2_trusted t where t.phone = w.phone and t.is_test)
                   order by w.created_at desc limit 10) m);
exception when undefined_table or undefined_column then
  return '[]'::jsonb;
end $$;

-- One incident with what explains it: the check and its rule, recent runs, earlier incidents of the same check, what
-- else is open in the app, heartbeats that are down, fixes already run, and earlier AI notes. Redacted.
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
    'recent_results', (select coalesce(jsonb_agg(jsonb_build_object('at', r.ran_at, 'status', r.status, 'value', r.value, 'error', left(r.error, 300),
                                                                    'ms', r.duration_ms) order by r.ran_at desc), '[]')
                         from (select * from one.results where check_id = v_i.check_id order by ran_at desc
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

-- The numbers a brief is written from: the IST day before p_for_date (the brief built at 02:30 IST on a day reports
-- the day before). Kept on the brief as its stats, so the page shows what the text was built from.
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
                         where h.last_error_at is not null and h.last_error_at > coalesce(h.last_ok_at, '-infinity')));
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

-- The week behind a feature review: what kept failing, what is blocked, what is already proposed or was decided.
create or replace function one.ai_week_context() returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  return one.redact(jsonb_build_object(
    'apps', (select coalesce(jsonb_agg(key order by key), '[]') from one.apps),
    'incidents_by_check', (select coalesce(jsonb_agg(to_jsonb(s) order by s.incidents desc, s.check_id), '[]') from (
        select i.check_id, i.app, max(i.title) as title, count(*) as incidents, sum(i.reopened_count) as reopened,
               count(*) filter (where i.severity = 'P1') as p1,
               round(sum(extract(epoch from coalesce(i.resolved_at, now()) - i.opened_at)) / 60) as minutes_open
          from one.incidents i where i.opened_at > now() - interval '7 days' and i.check_id <> 'ONE-SYNTH'
         group by 1, 2 order by count(*) desc limit 30) s),
    'tests', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'app', t.app, 'title', t.title, 'enabled', t.enabled, 'needs', to_jsonb(t.needs),
                                                          'runs_7d', (select count(*) from one.test_runs r where r.test_id = t.id and r.started_at > now() - interval '7 days'),
                                                          'failed_7d', (select count(*) from one.test_runs r where r.test_id = t.id and r.ok = false
                                                                                                               and r.started_at > now() - interval '7 days'))
                                      order by t.id), '[]') from one.tests t),
    'checks_blocked', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'app', c.app, 'title', c.title, 'disabled_reason', c.disabled_reason) order by c.id), '[]')
                         from one.checks c where not c.enabled),
    'open_proposals', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'app', p.app, 'title', p.title, 'source', p.source) order by p.id), '[]')
                         from (select * from one.proposals where status in ('open', 'snoozed') order by id desc limit 60) p),
    'decided_30d', (select coalesce(jsonb_agg(jsonb_build_object('kind', p.kind, 'app', p.app, 'title', p.title, 'status', p.status) order by p.decided_at desc), '[]')
                      from (select * from one.proposals where decided_at > now() - interval '30 days' order by decided_at desc limit 40) p),
    'ai_spend_7d_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where created_at > now() - interval '7 days')),
    one.pii_keys());
end $$;

-- The data for one task, by kind. Raises when it cannot be built; the claim then fails that task without a model call.
create or replace function one.ai_context(p_task one.ai_tasks) returns jsonb
language plpgsql stable set search_path = '' as $$
begin
  case p_task.kind
    when 'classify', 'triage', 'explain', 'propose_fix', 'test_author' then
      if p_task.incident_id is null then
        raise exception 'task % has no incident', p_task.id using errcode = '22023';
      end if;
      return one.ai_incident_context(p_task.incident_id, p_task.kind);
    when 'brief' then
      return jsonb_build_object('for_date', p_task.input ->> 'for_date', 'stats', one.ai_brief_stats((p_task.input ->> 'for_date')::date));
    when 'propose_feature' then
      return one.ai_week_context();
    when 'ask' then
      return jsonb_build_object('question', p_task.input ->> 'question', 'now', now(), 'today_ist', (now() at time zone 'Asia/Kolkata')::date);
    else
      raise exception 'unknown task kind %', p_task.kind using errcode = '22023';
  end case;
end $$;

-- The schedule: fixed rules, each task once (its idempotency key) -------------------------------------------------

create or replace function one.ai_schedule() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_s jsonb := coalesce(one.setting('ai') -> 'schedule', '{}');
  v_local timestamp := now() at time zone 'Asia/Kolkata';
  v_week text := to_char(now() at time zone 'Asia/Kolkata', 'IYYY-"W"IW');
  v_out jsonb := '{}';
  v_n integer;
  v_i one.incidents;
begin
  -- Every new incident is classified once (synthetic test incidents never are).
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.opened_at > now() - interval '1 day' and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'classify:' || i.id)
              order by i.id limit 20 loop
    v_n := v_n + (one.enqueue_ai('classify', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'classify:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('classify', v_n);
  -- An explanation for a P1 or P2 still open after explain_after_min, and for every storm.
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.check_id <> 'ONE-SYNTH' and not ('synthetic' = any (i.tags))
                and (i.check_id = 'ONE-STORM'
                     or (i.severity in ('P1', 'P2') and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'explain_after_min')::int, 15))))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'explain:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('explain', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'explain:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('explain', v_n);
  -- A fix proposal for a P1 or P2 still open after propose_fix_after_min (the deep tier when it is high-risk).
  v_n := 0;
  for v_i in select * from one.incidents i
              where i.resolved_at is null and i.severity in ('P1', 'P2') and i.check_id not in ('ONE-SYNTH', 'ONE-STORM')
                and not ('synthetic' = any (i.tags))
                and i.opened_at < now() - make_interval(mins => coalesce((v_s ->> 'propose_fix_after_min')::int, 60))
                and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'propose_fix:' || i.id)
              order by i.id limit 10 loop
    v_n := v_n + (one.enqueue_ai('propose_fix', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id),
                                 case when one.ai_high_risk(v_i) then v_ai #>> '{routing,propose_fix_high_risk}' end,
                                 'propose_fix:' || v_i.id, v_i.id) is not null)::int;
  end loop;
  v_out := v_out || jsonb_build_object('propose_fix', v_n);
  -- A test idea for each incident resolved as fixed in the last day.
  v_n := 0;
  if coalesce((v_s ->> 'test_author_on_fixed')::boolean, true) then
    for v_i in select * from one.incidents i
                where i.resolution = 'fixed' and i.resolved_at > now() - interval '1 day' and i.check_id <> 'ONE-SYNTH'
                  and not ('synthetic' = any (i.tags))
                  and not exists (select 1 from one.ai_tasks t where t.idempotency_key = 'test_author:' || i.id)
                order by i.id limit 5 loop
      v_n := v_n + (one.enqueue_ai('test_author', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id), null, 'test_author:' || v_i.id, v_i.id) is not null)::int;
    end loop;
  end if;
  v_out := v_out || jsonb_build_object('test_author', v_n);
  -- The weekly feature review, on propose_feature_weekday (ISO, 1 = Monday) after 03:00 IST.
  if extract(isodow from v_local) = coalesce((v_s ->> 'propose_feature_weekday')::int, 1) and v_local::time >= time '03:00' then
    v_out := v_out || jsonb_build_object('propose_feature',
               (one.enqueue_ai('propose_feature', jsonb_build_object('week', v_week), null, 'propose_feature:' || v_week, null) is not null)::int);
  end if;
  return v_out;
end $$;

-- Each minute, from the tick's app call: the schedule, then the worker when a task is due. The worker may run up to
-- about four minutes; overlapping runs share the queue (the claim's lease and max_parallel).
create or replace function one.ai_step() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_sched jsonb;
  v_due boolean;
begin
  v_sched := one.ai_schedule();
  select exists (select 1 from one.ai_tasks
                  where status = 'pending'
                     or (status = 'deferred' and coalesce(not_before, '-infinity') <= now())
                     or (status = 'claimed' and claimed_at < now() - interval '10 minutes')) into v_due;
  return jsonb_build_object('ai', jsonb_build_object('scheduled', v_sched,
           'request', case when v_due then coalesce(one.job_call('/api/internal/ai/run', 290000)::text, 'not_configured') else 'idle' end));
end $$;

create or replace function one.tick_app_call() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v jsonb;
begin
  v := jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
  begin
    v := v || one.ai_step();
  exception when others then
    v := v || jsonb_build_object('ai_error', sqlerrm);
  end;
  return v;
exception when others then
  return jsonb_build_object('app_error', sqlerrm);
end $$;

-- The worker's API (service role) ----------------------------------------------------------------------------------

-- One task for p_holder, or null. Expired, synthetic and abandoned tasks are tidied first; the budget gate then
-- defers what may not run (visibly, with the reason, retried every 15 minutes) and the most urgent task is claimed
-- with the settings, today's budget and its context. A context that cannot be built fails that task, not the claim.
create or replace function one.ai_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_pct numeric := coalesce((one.setting('ai') ->> 'queue_non_triage_at_pct')::numeric, 80);
  v_all text[] := array['classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author'];
  v_spent numeric;
  v_allowed text[];
  v_task one.ai_tasks;
  v_context jsonb;
begin
  if coalesce(p_holder, '') !~ '^[a-z0-9:._-]{3,80}$' then
    raise exception 'one.ai_claim: bad holder' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('one.ai_claim'));
  update one.ai_tasks set status = 'cancelled', error = 'older than ai.task_max_age_h', claimed_by = null
   where status in ('pending', 'deferred') and created_at < now() - make_interval(hours => coalesce((v_ai ->> 'task_max_age_h')::int, 48));
  update one.ai_tasks t set status = 'cancelled', error = 'a synthetic test incident is not analysed'
    from one.incidents i
   where t.incident_id = i.id and t.status in ('pending', 'deferred') and (i.check_id = 'ONE-SYNTH' or 'synthetic' = any (i.tags));
  update one.ai_tasks set status = case when attempts >= 3 then 'failed' else 'pending' end,
                          error = 'the worker stopped during this task', claimed_by = null
   where status = 'claimed' and claimed_at < now() - interval '10 minutes';
  if (select count(*) from one.ai_tasks where status = 'claimed') >= coalesce((v_ai ->> 'max_parallel')::int, 2) then
    return null;
  end if;
  v_spent := one.ai_spent_today();
  v_allowed := case when v_cap <= 0 or v_spent >= v_cap then '{}'::text[]
                    when v_spent >= v_cap * v_pct / 100 then array['classify', 'triage']
                    else v_all end;
  -- The reason is also the task's error, which the incident and Ask pages show.
  update one.ai_tasks
     set status = 'deferred', not_before = now() + interval '15 minutes',
         deferred_reason = case when cardinality(v_allowed) = 0
                                then format('budget (cap reached): today''s AI spend ₹%s has reached the cap ₹%s', round(v_spent, 2), v_cap)
                                else format('budget (over %s%%): today''s AI spend ₹%s is %s%% of the cap ₹%s, so only classify and triage run', v_pct,
                                            round(v_spent, 2), round(v_spent / v_cap * 100), v_cap) end
   where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
     and not (kind = any (v_allowed));
  update one.ai_tasks set error = deferred_reason where status = 'deferred' and deferred_reason like 'budget (%' and error is distinct from deferred_reason;
  for i in 1..5 loop
    select * into v_task from one.ai_tasks
     where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
       and kind = any (v_allowed)
     order by one.ai_priority(kind), id
     limit 1 for update skip locked;
    if not found then
      return null;
    end if;
    begin
      v_context := one.ai_context(v_task);
    exception
      -- OTHERS does not catch a cancelled statement: a statement timeout while one context is built must fail that
      -- task, or it would come first again every minute (review M3).
      when query_canceled then
        update one.ai_tasks set status = 'failed', error = 'building the data for this task took too long' where id = v_task.id;
        continue;
      when others then
        update one.ai_tasks set status = 'failed', error = left('could not build the data for this task: ' || sqlerrm, 300) where id = v_task.id;
        continue;
    end;
    update one.ai_tasks
       set status = 'claimed', claimed_by = p_holder, claimed_at = now(), attempts = attempts + 1, deferred_reason = null, not_before = null,
           -- A brief keeps the numbers it was written from (they become the brief's stats).
           input = case when kind = 'brief' then input || jsonb_build_object('stats', v_context -> 'stats') else input end
     where id = v_task.id returning * into v_task;
    return jsonb_build_object(
      'task', jsonb_build_object('id', v_task.id, 'kind', v_task.kind, 'input', v_task.input - 'stats', 'model_hint', v_task.model_hint,
                                 'attempts', v_task.attempts, 'incident_id', v_task.incident_id),
      'ai', v_ai,
      -- task_spent_inr: what earlier attempts of this task spent, so per_task_cap_inr holds across attempts (review M6).
      'budget', jsonb_build_object('spent_inr', v_spent, 'cap_inr', v_cap, 'remaining_inr', greatest(v_cap - v_spent, 0),
                                   'task_spent_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where task_id = v_task.id)),
      'context', v_context);
  end loop;
  return null;
end $$;

-- The model calls a task made, whatever its outcome (the spend counts either way).
create or replace function one.ai_record_calls(p_task bigint, p_calls jsonb) returns integer
language plpgsql set search_path = '' as $$
declare
  v_n integer := 0;
  c jsonb;
begin
  if p_calls is null then
    return 0;
  end if;
  if jsonb_typeof(p_calls) <> 'array' or jsonb_array_length(p_calls) > 20 then
    raise exception 'calls must be a list of at most 20' using errcode = '22023';
  end if;
  for c in select * from jsonb_array_elements(p_calls) loop
    if jsonb_typeof(c) <> 'object' or c ->> 'provider' not in ('anthropic', 'gemini') or coalesce(c ->> 'model', '') !~ '^[A-Za-z0-9._:/-]{1,100}$'
       or exists (select 1 from unnest(array['input_tokens', 'output_tokens', 'cache_read', 'cost_usd', 'cost_inr', 'latency_ms']) k
                   where c ? k and (jsonb_typeof(c -> k) <> 'number' or (c ->> k)::numeric < 0)) then
      raise exception 'a call record is malformed' using errcode = '22023';
    end if;
    insert into one.ai_calls (task_id, provider, model, purpose, prompt_version, input_tokens, output_tokens, cache_read, cost_usd, cost_inr,
                              latency_ms, ok, error)
    values (p_task, c ->> 'provider', c ->> 'model', left(coalesce(c ->> 'purpose', 'task'), 40), left(c ->> 'prompt_version', 80),
            (c ->> 'input_tokens')::int, (c ->> 'output_tokens')::int, (c ->> 'cache_read')::int,
            -- least() skips a null, so a missing cost stays missing instead of becoming the bound.
            case when c ? 'cost_usd' then least((c ->> 'cost_usd')::numeric, 99999) end,
            case when c ? 'cost_inr' then least((c ->> 'cost_inr')::numeric, 99999999) end,
            (c ->> 'latency_ms')::int, coalesce((c ->> 'ok')::boolean, false), left(c ->> 'error', 300));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

create or replace function one.ai_held(p_task bigint, p_holder text) returns one.ai_tasks
language plpgsql set search_path = '' as $$
declare
  v_t one.ai_tasks;
begin
  select * into v_t from one.ai_tasks where id = p_task for update;
  if not found or v_t.status <> 'claimed' or v_t.claimed_by is distinct from p_holder then
    raise exception 'task % is not held by this worker', p_task using errcode = '55000';
  end if;
  return v_t;
end $$;

-- The worker's answer, validated by the app against the kind's schema, filed by kind. Only these writes exist:
--   classify, ask      the task's result (shown on the incident and the Ask page);
--   triage             the incident's summary, and a fix proposal task when it says one is worth writing;
--   explain            the incident's likely cause;
--   propose_fix, propose_feature, test_author   open proposals (source ai) that a person decides (D-065);
--   brief              a brief, and for the nightly one an email to the P1 inbox at ai.schedule.brief_mail_at_ist.
create or replace function one.ai_finish(p_task bigint, p_holder text, p_result jsonb, p_calls jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_i one.incidents;
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_expire interval := make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14));
  v_meta jsonb := coalesce(p_result -> 'meta', '{}');
  v_p jsonb;
  v_n integer := 0;
  v_brief bigint;
  v_to text;
  v_mail_at timestamptz;
  v_filed jsonb := '[]';
  v_id bigint;
begin
  if jsonb_typeof(p_result) is distinct from 'object' or length(p_result::text) > 60000 then
    raise exception 'a result is one JSON object of at most 60,000 characters' using errcode = '22023';
  end if;
  perform one.ai_record_calls(p_task, p_calls);
  if v_t.incident_id is not null then
    select * into v_i from one.incidents where id = v_t.incident_id;
  end if;
  case v_t.kind
    when 'classify', 'ask' then
      null;
    when 'triage' then
      if nullif(trim(p_result ->> 'summary'), '') is not null then
        update one.incidents set summary = left(trim(p_result ->> 'summary'), 600) where id = v_t.incident_id;
      end if;
      if coalesce((p_result ->> 'propose_fix')::boolean, false) and v_i.resolved_at is null and v_i.check_id not in ('ONE-SYNTH', 'ONE-STORM') then
        v_id := one.enqueue_ai('propose_fix', jsonb_build_object('incident_id', v_i.id, 'check_id', v_i.check_id, 'from', 'triage'),
                               case when one.ai_high_risk(v_i) then v_ai #>> '{routing,propose_fix_high_risk}' end, 'propose_fix:' || v_i.id, v_i.id);
        v_filed := v_filed || jsonb_build_array(jsonb_build_object('ai_task', v_id));
      end if;
    when 'explain' then
      if nullif(trim(p_result ->> 'likely_cause'), '') is not null then
        update one.incidents set root_cause = left(trim(p_result ->> 'likely_cause'), 600) where id = v_t.incident_id;
      end if;
    when 'propose_fix' then
      insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key, model, incident_id, expires_at)
      values ('fix', v_i.app, left(trim(p_result ->> 'title'), 200), left(trim(p_result ->> 'rationale'), 4000),
              jsonb_build_object('written_by', 'ai', 'task_id', v_t.id, 'incident_id', v_i.id, 'check_id', v_i.check_id,
                                 'prompt_version', v_meta ->> 'prompt_version', 'tier', v_meta ->> 'tier'),
              jsonb_build_object('where', left(p_result ->> 'where', 300), 'owner_action', left(p_result ->> 'owner_action', 4000),
                                 'steps', coalesce(p_result -> 'steps', '[]'), 'touches', one.ai_touches(p_result -> 'touches'),
                                 'uses_fix', p_result -> 'uses_fix', 'verify', left(p_result ->> 'verify', 1000)),
              one.ai_risk(p_result ->> 'risk', case when one.ai_high_risk(v_i) then 'medium' else 'low' end),
              'ai', 'ai:' || v_t.id, v_meta ->> 'model', v_i.id, now() + v_expire)
      on conflict (source_key) do nothing returning id into v_id;
      v_filed := v_filed || jsonb_build_array(jsonb_build_object('proposal', v_id));
    when 'propose_feature' then
      for v_p in select * from jsonb_array_elements(coalesce(p_result -> 'proposals', '[]')) loop
        v_n := v_n + 1;
        exit when v_n > 3;
        insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key, model, expires_at)
        values (case when v_p ->> 'kind' in ('feature', 'cleanup', 'config') then v_p ->> 'kind' else 'feature' end,
                v_p ->> 'app', left(trim(v_p ->> 'title'), 200), left(trim(v_p ->> 'rationale'), 4000),
                jsonb_build_object('written_by', 'ai', 'task_id', v_t.id, 'week', v_t.input ->> 'week', 'evidence', coalesce(v_p -> 'evidence', '[]'),
                                   'prompt_version', v_meta ->> 'prompt_version', 'tier', v_meta ->> 'tier'),
                jsonb_build_object('where', left(v_p ->> 'where', 300), 'owner_action', left(v_p ->> 'owner_action', 4000),
                                   'touches', one.ai_touches(v_p -> 'touches')),
                one.ai_risk(v_p ->> 'risk', 'low'), 'ai', 'ai:' || v_t.id || ':' || v_n, v_meta ->> 'model', now() + v_expire)
        on conflict (source_key) do nothing returning id into v_id;
        v_filed := v_filed || jsonb_build_array(jsonb_build_object('proposal', v_id));
      end loop;
    when 'test_author' then
      if coalesce((p_result ->> 'needed')::boolean, true) and jsonb_typeof(p_result -> 'test') = 'object' then
        insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key, model, incident_id, expires_at)
        values ('feature', v_i.app, left('Test: ' || trim(p_result #>> '{test,title}'), 200), left(trim(p_result ->> 'rationale'), 4000),
                jsonb_build_object('written_by', 'ai', 'task_id', v_t.id, 'incident_id', v_i.id, 'check_id', v_i.check_id,
                                   'prompt_version', v_meta ->> 'prompt_version', 'tier', v_meta ->> 'tier'),
                jsonb_build_object('where', 'Eduwit One synthetic tests (config/tests.json, web/lib/tests/journeys)',
                                   'owner_action', 'Review the test below; a builder adds it as a journey with its guard and purge.',
                                   'test', p_result -> 'test', 'touches', one.ai_touches('["tests"]')),
                one.ai_risk(p_result ->> 'risk', 'low'), 'ai', 'ai:' || v_t.id, v_meta ->> 'model', v_i.id, now() + v_expire)
        on conflict (source_key) do nothing returning id into v_id;
        v_filed := v_filed || jsonb_build_array(jsonb_build_object('proposal', v_id));
      end if;
    when 'brief' then
      if nullif(trim(p_result ->> 'body_md'), '') is null then
        raise exception 'a brief needs its text' using errcode = '22023';
      end if;
      insert into one.briefs (for_date, tier, body_md, stats, model, cost_usd, task_id)
      values ((v_t.input ->> 'for_date')::date, v_meta ->> 'tier', left(p_result ->> 'body_md', 20000), coalesce(v_t.input -> 'stats', '{}'),
              v_meta ->> 'model', (select sum(cost_usd) from one.ai_calls where task_id = v_t.id), v_t.id)
      returning id into v_brief;
      v_filed := v_filed || jsonb_build_array(jsonb_build_object('brief', v_brief));
      -- The nightly brief is mailed to the P1 inbox in the morning; one regenerated on the Brief page is not.
      if v_t.input ->> 'requested_by' is null then
        v_mail_at := greatest(now(), ((v_t.input ->> 'for_date')::date
                                      + coalesce((v_ai #>> '{schedule,brief_mail_at_ist}')::time, time '08:00'))::timestamp at time zone 'Asia/Kolkata');
        for v_to in select distinct lower(x) from jsonb_array_elements_text(coalesce(one.setting('alerts') #> '{p1,email}', '[]')) x
                     where x ~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' loop
          insert into one.deliveries (channel, recipient, kind, brief_id, next_attempt_at, idempotency_key)
          values ('email', v_to, 'brief', v_brief, v_mail_at, format('brief:%s:%s', v_t.input ->> 'for_date', v_to))
          on conflict (idempotency_key) do nothing;
        end loop;
      end if;
  end case;
  update one.ai_tasks set status = 'done', result = p_result, error = null, claimed_by = null where id = p_task;
  return jsonb_build_object('ok', true, 'filed', v_filed);
end $$;

-- A failed task: back in the queue when a retry can help (at most 3 attempts), else failed with the reason.
create or replace function one.ai_fail(p_task bigint, p_holder text, p_error text, p_calls jsonb, p_retry boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_retry boolean := coalesce(p_retry, false) and v_t.attempts < 3;
begin
  perform one.ai_record_calls(p_task, p_calls);
  -- A retry waits 2, 4, then 8 minutes, so an overloaded provider does not use up the attempts at once (review M5).
  update one.ai_tasks
     set status = case when v_retry then 'deferred' else 'failed' end,
         error = left(coalesce(p_error, 'failed'), 300), claimed_by = null,
         deferred_reason = case when v_retry then left('retry: ' || coalesce(p_error, 'failed'), 300) end,
         not_before = case when v_retry then now() + make_interval(mins => (2 ^ v_t.attempts)::int) end
   where id = p_task;
  return case when v_retry then 'pending' else 'failed' end;
end $$;

-- The calls a worker made, recorded as each one ends (an invocation cut short keeps the spend it made, review M6),
-- with today's budget as it now stands.
create or replace function one.ai_calls_add(p_task bigint, p_holder text, p_calls jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_spent numeric;
begin
  perform one.ai_record_calls(v_t.id, p_calls);
  v_spent := one.ai_spent_today();
  return jsonb_build_object('spent_inr', v_spent, 'remaining_inr', greatest(v_cap - v_spent, 0));
end $$;

-- A task that cannot run yet (no key, no price, not enough budget left today): back as deferred, not counted as an
-- attempt, retried after p_minutes; ai.task_max_age_h later it is cancelled.
create or replace function one.ai_defer(p_task bigint, p_holder text, p_reason text, p_minutes integer) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
begin
  update one.ai_tasks
     set status = 'deferred', deferred_reason = left(coalesce(p_reason, 'deferred'), 300), error = left(coalesce(p_reason, 'deferred'), 300),
         claimed_by = null,
         attempts = greatest(v_t.attempts - 1, 0),
         not_before = now() + make_interval(mins => least(greatest(coalesce(p_minutes, 30), 1), 1440))
   where id = p_task;
  return 'deferred';
end $$;

-- Ask's tools (D-076). Each is a fixed read with bounded arguments and rows; the answer is redacted.
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
    else
      raise exception 'unknown tool %', p_name using errcode = '22023';
  end case;
  return one.redact(v, one.pii_keys());
end $$;

-- One tool call for an Ask task the caller holds. Read-only: the transaction is set read only before the read, so no
-- tool can write even by mistake. Errors come back as data for the model, never as the task's failure. A statement
-- timeout cannot be armed from inside a function (D-044), so each read is bounded by its rows and ranges instead (the
-- role's own statement timeout still applies).
create or replace function one.ai_tool(p_task bigint, p_holder text, p_name text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_started timestamptz := clock_timestamp();
  v jsonb;
begin
  if not exists (select 1 from one.ai_tasks where id = p_task and status = 'claimed' and claimed_by = p_holder and kind = 'ask') then
    raise exception 'task % is not a question held by this worker', p_task using errcode = '42501';
  end if;
  perform set_config('transaction_read_only', 'on', true);
  begin
    perform set_config('lock_timeout', '2s', true);
    v := jsonb_build_object('ok', true, 'data', one.ai_tool_data(p_name, p_args));
  exception
    when sqlstate '22023' or sqlstate 'P0002' or invalid_text_representation or numeric_value_out_of_range then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
    when undefined_table or undefined_function or undefined_column or invalid_schema_name then
      v := jsonb_build_object('ok', false, 'error', 'not available on this database');
    when insufficient_privilege then
      v := jsonb_build_object('ok', false, 'error', 'needs a person''s own access in the app');
    when lock_not_available or query_canceled then
      v := jsonb_build_object('ok', false, 'error', 'the read took too long; try a smaller range');
    when others then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
  end;
  perform set_config('search_path', '', true);
  return v || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_started) * 1000));
end $$;

-- The AI settings, for the Setup page's ai_key validator (service role).
create or replace function one.app_ai_settings() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(one.setting('ai'), '{}')
$$;

-- The brief email (0008's claim and verdict, with the brief) ----------------------------------------------------------

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
                                             'subjects', to_jsonb(i.subjects), 'summary', i.summary, 'value', i.evidence -> 'value',
                                             'status', i.evidence ->> 'status', 'error', i.evidence ->> 'error')
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
  update one.deliveries
     set attempts = attempts + 1, error = left(p_error, 500),
         status = case when attempts + 1 >= 2 then 'failed' else 'pending' end,
         next_attempt_at = now() + interval '2 minutes'
   where id = p_id;
  return case when v_d.attempts + 1 >= 2 then 'failed' else 'retry' end;
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.ai_claim(text)', 'service_role', 'AI worker (0018): one task, its settings, budget and masked data'),
  ('one.ai_finish(bigint,text,jsonb,jsonb)', 'service_role', 'AI worker (0018): the validated answer, filed by kind, and its calls'),
  ('one.ai_fail(bigint,text,text,jsonb,boolean)', 'service_role', 'AI worker (0018): a failed task and its calls'),
  ('one.ai_defer(bigint,text,text,integer)', 'service_role', 'AI worker (0018): a task that cannot run yet'),
  ('one.ai_tool(bigint,text,text,jsonb)', 'service_role', 'AI worker (0018): one read-only Ask tool for a task it holds'),
  ('one.ai_calls_add(bigint,text,jsonb)', 'service_role', 'AI worker (0018): the calls a task made, as each one ends'),
  ('one.app_ai_settings()', 'service_role', 'AI worker (0018): the AI settings for the Setup validator')
on conflict do nothing;
call one.apply_grants();
