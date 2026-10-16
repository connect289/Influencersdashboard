-- B2C CRM b22 (Phase 3): the Analytics page (spec B13). Staging first. Idempotent.
--   fact_leads            one row per lead, refreshed every minute from the lead's state and records (never by scanning
--                         student_leads); test leads are kept, flagged, and shown only in test mode
--   an_sources, metric_defs, dim_defs
--                         the catalogue: every B13.2 metric with its SQL, the roles that may use it and its dimensions.
--                         Written only by migrations: a query spec names keys from here, never SQL
--   analytics_run()       validates a spec against the catalogue and the caller's role; the scope is added here (a
--                         counsellor always gets only their own leads, a sales head their team), never by the caller or
--                         the model; returns the rows and the SQL it ran
--   analytics_drill()     the leads behind any number, as a saved list the Leads page opens
--   dashboards            personal and standard (per role); duplicate, set as home, Admin publishes
--   dashboard_schedules   daily / weekly / monthly by email (PDF or CSV); the app renders and sends
--   metric_alerts         a threshold or an unusual move against the last 28 days; phone alert and email
--   ai_calls, insights    every Claude call logged with its cost under a daily cap; the morning insights feed

insert into b2c.settings (key, value) values
  ('ai', '{"model": "claude-sonnet-5-5", "daily_cap_inr": 500, "usd_inr": 85, "insights_hour_ist": 7,
           "price_usd_per_mtok": {"claude-sonnet-5-5": {"in": 3, "out": 15}, "claude-haiku-4-5": {"in": 1, "out": 5}, "claude-opus-5-5": {"in": 5, "out": 25}}}')
on conflict (key) do nothing;

-- ---------- facts ----------
create table if not exists b2c.fact_leads (
  lead_id bigint primary key,
  is_test boolean not null default false,
  deleted boolean not null default false,
  lane text, status text, handoff_reason text, cause text, source text, campaign text, partner text, lost_reason text,
  course text, specialization text, university text, city text, state text,
  owner_id uuid, team text, stage_id smallint, stage text, sub_stage text, canonical text, temperature text, score int, score_band text,
  journey text, pool_reason text, reengage_trigger text, lost_by text, flagged text, missing_count int not null default 0,
  handed_off_at timestamptz, assigned_at timestamptz, first_contacted_at timestamptz, first_contact_minutes numeric,
  sla_due_at timestamptz, sla_met boolean, sla_breached_at timestamptz,
  contacted_at timestamptz, counselled_at timestamptz, applied_at timestamptz, lost_at timestamptz,
  enrolled_on date, enrolled_at timestamptz, enrolled_programme text, enrolled_university text, verified boolean not null default false, refunded boolean not null default false,
  pool_entered_at timestamptz, reengaged_at timestamptz, dormant_at timestamptz, opted_out boolean not null default false,
  last_activity_at timestamptz,
  calls int not null default 0, calls_connected int not null default 0, attempts_before_connect int,
  wa_out int not null default 0, wa_in int not null default 0, email_out int not null default 0, replies int not null default 0,
  marketing_cost numeric(12, 2) not null default 0,
  fee numeric(12, 2), university_gross numeric(12, 2), university_net numeric(12, 2), counsellor_commission numeric(12, 2),
  refreshed_at timestamptz not null default now()
);
create index if not exists fact_leads_handed on b2c.fact_leads (handed_off_at);
create index if not exists fact_leads_owner on b2c.fact_leads (owner_id);

create table if not exists b2c.facts_state (id int primary key default 1 check (id = 1), last_at timestamptz not null default '-infinity', last_run_at timestamptz);
insert into b2c.facts_state (id) values (1) on conflict (id) do nothing;

/* Rebuilds the fact rows of the given leads. */
create or replace function b2c.facts_build(p_leads bigint[]) returns int language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  insert into b2c.fact_leads as t (lead_id, is_test, deleted, lane, status, handoff_reason, cause, source, campaign, partner, lost_reason, course, specialization, university, city, state,
         owner_id, team, stage_id, stage, sub_stage, canonical, temperature, score, score_band, journey, pool_reason, reengage_trigger, lost_by, flagged, missing_count,
         handed_off_at, assigned_at, first_contacted_at, first_contact_minutes, sla_due_at, sla_met, sla_breached_at,
         contacted_at, counselled_at, applied_at, lost_at, enrolled_on, enrolled_at, enrolled_programme, enrolled_university, verified, refunded,
         pool_entered_at, reengaged_at, dormant_at, opted_out, last_activity_at, calls, calls_connected, attempts_before_connect, wa_out, wa_in, email_out, replies,
         marketing_cost, fee, university_gross, university_net, counsellor_commission, refreshed_at)
  select s.lead_id, s.is_test or coalesce(r.is_test, false), s.deleted_at is not null, s.lane, s.status, s.handoff_reason, s.cause,
         r.record -> 'source' ->> 'lead_source', r.record -> 'source' ->> 'campaign',
         coalesce(s.partner_lost ->> 'partner_name', s.partner_lost ->> 'partner'), coalesce(s.partner_lost ->> 'lost_reason', case when s.stage_id = 10 then s.sub_stage end),
         r.record -> 'interest' ->> 'course', r.record -> 'interest' ->> 'specialization', r.record -> 'interest' ->> 'university',
         r.record -> 'student' ->> 'city', r.record -> 'student' ->> 'state',
         s.owner_id, u.team, s.stage_id, st.name, s.sub_stage, st.canon, coalesce(s.temperature, case when s.hot then 'hot' end), s.score, s.score_band,
         s.journey, s.pool_reason, s.reengage_trigger, s.lost_by, s.flagged, coalesce(jsonb_array_length(s.missing), 0),
         s.handed_off_at, s.assigned_at, s.first_contacted_at,
         case when s.first_contacted_at is not null and s.assigned_at is not null then round(extract(epoch from s.first_contacted_at - s.assigned_at) / 60, 1) end,
         s.sla_due_at, case when s.sla_due_at is null then null else s.sla_met_at is not null and s.sla_met_at <= s.sla_due_at end, s.sla_breached_at,
         st2.contacted, st2.counselled, st2.applied, st2.lost,
         en.enrolled_on, (en.enrolled_on::timestamp at time zone 'Asia/Kolkata'), en.programme, en.university, coalesce(en.verified, false), coalesce(en.refunded, false),
         s.pool_entered_at, s.reengaged_at, s.dormant_at, coalesce((r.record -> 'consent' ->> 'opted_out')::boolean, false), s.last_activity_at,
         coalesce(c.calls, 0), coalesce(c.connected, 0), c.before_connect,
         coalesce(w.out_n, 0), coalesce(w.in_n, 0), coalesce(m.out_n, 0), coalesce(rp.n, 0), coalesce(w.mcost, 0),
         en.fee, (select sum(e.gross) from b2c.earnings e join b2c.enrollments x on x.id = e.enrollment_id where x.lead_id = s.lead_id),
         (select sum(e.net) from b2c.earnings e join b2c.enrollments x on x.id = e.enrollment_id where x.lead_id = s.lead_id),
         (select sum(l.amount) from b2c.commission_lines l where l.lead_id = s.lead_id and l.status <> 'void'),
         now()
    from b2c.leads_state s
    left join b2c.lead_records r on r.lead_id = s.lead_id
    left join b2c.stages st on st.id = s.stage_id
    left join b2c.users u on u.user_id = s.owner_id
    left join lateral (select min(a.at) filter (where a.meta ->> 'to' in ('Contacted', 'Qualified', 'Follow Up', 'Program Details Explained', 'Applicant', 'Docs Submitted', 'Enrolled')) contacted,
                              min(a.at) filter (where a.meta ->> 'to' in ('Qualified', 'Follow Up', 'Program Details Explained', 'Applicant', 'Docs Submitted', 'Enrolled')) counselled,
                              min(a.at) filter (where a.meta ->> 'to' in ('Applicant', 'Docs Submitted', 'Enrolled')) applied,
                              max(a.at) filter (where a.meta ->> 'to' = 'Lost') lost
                         from b2c.activities a where a.lead_id = s.lead_id and a.kind = 'stage') st2 on true
    left join lateral (select x.enrolled_on, x.programme, x.university, x.fee, x.status = 'verified' verified, x.status = 'refunded' refunded
                         from b2c.enrollments x where x.lead_id = s.lead_id and x.status in ('reported', 'verified', 'refunded') order by x.enrolled_on limit 1) en on true
    left join lateral (select count(*) filter (where k.logged_at is not null) calls, count(*) filter (where k.outcome = 'connected') connected,
                              (select count(*) from b2c.calls k2 where k2.lead_id = s.lead_id and k2.logged_at is not null
                                 and k2.logged_at < coalesce((select min(k3.logged_at) from b2c.calls k3 where k3.lead_id = s.lead_id and k3.outcome = 'connected'), 'infinity')) before_connect
                         from b2c.calls k where k.lead_id = s.lead_id) c on true
    left join lateral (select count(*) filter (where x.direction = 'out') out_n, count(*) filter (where x.direction = 'in') in_n,
                              coalesce(sum(x.cost_estimate) filter (where x.direction = 'out' and (x.campaign_id is not null or x.journey_run_id is not null or x.purpose = 'marketing')), 0) mcost
                         from b2c.wa_messages x where x.lead_id = s.lead_id) w on true
    left join lateral (select count(*) filter (where x.direction = 'out') out_n from b2c.emails x where x.lead_id = s.lead_id) m on true
    left join lateral (select count(*) n from b2c.replies x where x.lead_id = s.lead_id) rp on true
   where s.lead_id = any (p_leads)
  on conflict (lead_id) do update set
    is_test = excluded.is_test, deleted = excluded.deleted, lane = excluded.lane, status = excluded.status, handoff_reason = excluded.handoff_reason, cause = excluded.cause,
    source = excluded.source, campaign = excluded.campaign, partner = excluded.partner, lost_reason = excluded.lost_reason, course = excluded.course,
    specialization = excluded.specialization, university = excluded.university, city = excluded.city, state = excluded.state, owner_id = excluded.owner_id, team = excluded.team,
    stage_id = excluded.stage_id, stage = excluded.stage, sub_stage = excluded.sub_stage, canonical = excluded.canonical, temperature = excluded.temperature,
    score = excluded.score, score_band = excluded.score_band, journey = excluded.journey, pool_reason = excluded.pool_reason, reengage_trigger = excluded.reengage_trigger,
    lost_by = excluded.lost_by, flagged = excluded.flagged, missing_count = excluded.missing_count, handed_off_at = excluded.handed_off_at, assigned_at = excluded.assigned_at,
    first_contacted_at = excluded.first_contacted_at, first_contact_minutes = excluded.first_contact_minutes, sla_due_at = excluded.sla_due_at, sla_met = excluded.sla_met,
    sla_breached_at = excluded.sla_breached_at, contacted_at = excluded.contacted_at, counselled_at = excluded.counselled_at, applied_at = excluded.applied_at,
    lost_at = excluded.lost_at, enrolled_on = excluded.enrolled_on, enrolled_at = excluded.enrolled_at, enrolled_programme = excluded.enrolled_programme,
    enrolled_university = excluded.enrolled_university, verified = excluded.verified, refunded = excluded.refunded, pool_entered_at = excluded.pool_entered_at,
    reengaged_at = excluded.reengaged_at, dormant_at = excluded.dormant_at, opted_out = excluded.opted_out, last_activity_at = excluded.last_activity_at,
    calls = excluded.calls, calls_connected = excluded.calls_connected, attempts_before_connect = excluded.attempts_before_connect, wa_out = excluded.wa_out,
    wa_in = excluded.wa_in, email_out = excluded.email_out, replies = excluded.replies, marketing_cost = excluded.marketing_cost, fee = excluded.fee,
    university_gross = excluded.university_gross, university_net = excluded.university_net, counsellor_commission = excluded.counsellor_commission, refreshed_at = now();
  get diagnostics n = row_count;
  return n;
end $f$;

/* Every minute: the leads touched since the last run (state, activities, calls, messages, money), in batches. */
create or replace function b2c.facts_refresh(p_limit int default 5000) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_since timestamptz; v_now timestamptz := now(); v_ids bigint[]; n int := 0;
begin
  select last_at into v_since from b2c.facts_state where id = 1 for update;
  select array_agg(distinct lead_id) into v_ids from (
    select lead_id from b2c.leads_state where updated_at >= v_since
    union select lead_id from b2c.lead_records where received_at >= v_since
    union select lead_id from b2c.activities where at >= v_since
    union select lead_id from b2c.calls where coalesce(logged_at, tapped_at) >= v_since
    union select lead_id from b2c.wa_messages where lead_id is not null and coalesce(status_at, created_at) >= v_since
    union select lead_id from b2c.emails where lead_id is not null and created_at >= v_since
    union select lead_id from b2c.replies where coalesce(corrected_at, created_at) >= v_since
    union select lead_id from b2c.enrollments where updated_at >= v_since
    union select x.lead_id from b2c.earnings e join b2c.enrollments x on x.id = e.enrollment_id where e.created_at >= v_since
    union select lead_id from b2c.commission_lines where created_at >= v_since
    limit p_limit) q;
  if v_ids is not null then n := b2c.facts_build(v_ids); end if;
  update b2c.facts_state set last_at = case when coalesce(array_length(v_ids, 1), 0) >= p_limit then last_at else v_now - interval '5 seconds' end, last_run_at = v_now where id = 1;
  return jsonb_build_object('rebuilt', n);
end $f$;

do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-facts') then
    perform cron.schedule('b2c-facts', '* * * * *', 'select b2c.facts_refresh()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-alerts') then
    perform cron.schedule('b2c-alerts', '*/15 * * * *', 'select b2c.alerts_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-anomalies') then
    perform cron.schedule('b2c-anomalies', '45 1 * * *', 'select b2c.anomalies_tick()');   -- 07:15 IST
  end if;
end $d$;

-- ---------- the catalogue ----------
create table if not exists b2c.an_sources (
  key text primary key,
  from_sql text not null,          -- a relation aliased x with a lead_id column
  actor_sql text not null,         -- the person a row belongs to (scope and the counsellor dimension)
  lead_based boolean not null default true
);
create table if not exists b2c.metric_defs (
  key text primary key,
  label text not null,
  area text not null,
  source text not null references b2c.an_sources (key),
  agg text not null,               -- an aggregate over x (and f, the lead's facts)
  date_sql text,                   -- the time column the range applies to; null = as of now
  where_sql text,
  fmt text not null default 'count' check (fmt in ('count', 'money', 'pct', 'minutes', 'days', 'number')),
  roles text[] not null,
  counts_leads boolean not null default false,   -- the value is a count of leads: the drill-down has exactly that many
  higher_is_better boolean not null default true,
  description text,
  sort int not null default 100
);
create table if not exists b2c.dim_defs (
  key text primary key,
  label text not null,
  expr text not null,              -- over f (facts), x (source row), u (the row's person); :date is the metric's time column
  sources text[],                  -- null = every source
  money boolean not null default false,
  sort int not null default 100
);

insert into b2c.an_sources (key, from_sql, actor_sql, lead_based) values
  ('leads', 'b2c.fact_leads x', 'x.owner_id', true),
  ('calls', 'b2c.calls x', 'x.user_id', true),
  ('tasks', 'b2c.tasks x', 'x.owner_id', true),
  ('messages', '(select w.lead_id, ''whatsapp''::text as channel, w.direction, w.status, w.user_id, w.created_at as at, w.template_name as template, w.cost_estimate as cost,
                        (w.campaign_id is not null or w.journey_run_id is not null or w.purpose = ''marketing'') as marketing, w.status in (''delivered'', ''read'') as delivered,
                        w.status = ''read'' as opened, false as clicked, w.status = ''failed'' as failed
                   from b2c.wa_messages w where w.lead_id is not null
                 union all
                 select e.lead_id, ''email'', e.direction, e.status, e.user_id, e.created_at, null, 0, (e.purpose = ''marketing'' or e.campaign_id is not null or e.journey_run_id is not null),
                        e.bounced_at is null and e.status in (''sent'', ''delivered''), e.opened_at is not null, e.clicked_at is not null, e.bounced_at is not null
                   from b2c.emails e where e.lead_id is not null) x', 'x.user_id', true),
  ('replies', 'b2c.replies x', 'f.owner_id', true),
  ('journeys', '(select r.*, j.name as journey_name from b2c.journey_runs r join b2c.journeys j on j.id = r.journey_id) x', 'f.owner_id', true),
  ('activities', 'b2c.activities x', 'x.actor_id', true),
  ('assignments', 'b2c.assignments x', 'x.user_id', true),
  ('commission', '(select l.*, e.enrolled_on, (e.enrolled_on::timestamp at time zone ''Asia/Kolkata'') as enrolled_at, e.university as enrolled_university, e.programme as enrolled_programme
                   from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id where l.status <> ''void'') x', 'x.counsellor_id', true),
  ('earnings', '(select g.*, e.lead_id, e.counsellor_id, e.enrolled_on, (e.enrolled_on::timestamp at time zone ''Asia/Kolkata'') as enrolled_at, e.university as enrolled_university
                   from b2c.earnings g join b2c.enrollments e on e.id = g.enrollment_id) x', 'x.counsellor_id', true)
on conflict (key) do update set from_sql = excluded.from_sql, actor_sql = excluded.actor_sql, lead_based = excluded.lead_based;

insert into b2c.metric_defs (key, label, area, source, agg, date_sql, where_sql, fmt, roles, counts_leads, higher_is_better, description, sort) values
  -- inflow
  ('handoffs', 'Hand-offs', 'Inflow', 'leads', 'count(*)', 'x.handed_off_at', null, 'count', '{admin,marketing,sales}', true, true, 'Leads the B2B CRM handed to B2C (or created in B2C)', 10),
  ('handoffs_sales', 'Hand-offs to sales', 'Inflow', 'leads', 'count(*)', 'x.handed_off_at', 'x.lane = ''sales''', 'count', '{admin,marketing,sales}', true, true, null, 11),
  ('handoffs_nurture', 'Hand-offs to nurture', 'Inflow', 'leads', 'count(*)', 'x.handed_off_at', 'x.lane = ''nurture''', 'count', '{admin,marketing}', true, true, null, 12),
  ('partner_lost', 'Partner-lost leads', 'Inflow', 'leads', 'count(*)', 'x.handed_off_at', 'x.partner is not null', 'count', '{admin,marketing}', true, true, null, 13),
  -- nurture
  ('pool_size', 'In the pool now', 'Nurture', 'leads', 'count(*)', null, 'x.status = ''pool''', 'count', '{admin,marketing}', true, true, null, 20),
  ('pool_entries', 'Entered the pool', 'Nurture', 'leads', 'count(*)', 'x.pool_entered_at', null, 'count', '{admin,marketing}', true, true, null, 21),
  ('reengaged', 'Re-engaged', 'Nurture', 'leads', 'count(*)', 'x.reengaged_at', null, 'count', '{admin,marketing}', true, true, 'Pooled leads that came back to a counsellor', 22),
  ('reengage_rate', 'Re-engagement rate', 'Nurture', 'leads', 'round(100.0 * count(*) filter (where x.reengaged_at is not null) / nullif(count(*), 0), 1)', 'x.pool_entered_at',
     'x.pool_entered_at is not null', 'pct', '{admin,marketing}', false, true, 'Of the leads that entered the pool in the range, the share re-engaged since', 23),
  ('reengage_days', 'Days to re-engage', 'Nurture', 'leads', 'round(avg(extract(epoch from x.reengaged_at - x.pool_entered_at) / 86400)::numeric, 1)', 'x.reengaged_at',
     'x.pool_entered_at is not null', 'days', '{admin,marketing}', false, false, null, 24),
  ('cost_per_reengaged', 'WhatsApp cost per re-engaged lead', 'Nurture', 'leads',
     'round(sum(x.marketing_cost) / nullif(count(*) filter (where x.reengaged_at is not null), 0), 2)', 'x.pool_entered_at', 'x.pool_entered_at is not null', 'money', '{admin,marketing}', false, false, null, 25),
  ('dormant', 'Went dormant', 'Nurture', 'leads', 'count(*)', 'x.dormant_at', null, 'count', '{admin,marketing}', true, false, null, 26),
  ('opted_out', 'Opted out', 'Nurture', 'leads', 'count(*)', null, 'x.opted_out', 'count', '{admin,marketing}', true, false, null, 27),
  ('marketing_sent', 'Marketing messages sent', 'Nurture', 'messages', 'count(*)', 'x.at', 'x.marketing and x.direction = ''out''', 'count', '{admin,marketing}', false, true, null, 30),
  ('marketing_delivered', 'Delivered', 'Nurture', 'messages', 'count(*) filter (where x.delivered or x.opened)', 'x.at', 'x.marketing and x.direction = ''out''', 'count', '{admin,marketing}', false, true, null, 31),
  ('marketing_read', 'Read or opened', 'Nurture', 'messages', 'count(*) filter (where x.opened)', 'x.at', 'x.marketing and x.direction = ''out''', 'count', '{admin,marketing}', false, true, null, 32),
  ('email_clicks', 'Email clicks', 'Nurture', 'messages', 'count(*) filter (where x.clicked)', 'x.at', 'x.channel = ''email'' and x.marketing', 'count', '{admin,marketing}', false, true, null, 33),
  ('bounces', 'Bounces and failures', 'Nurture', 'messages', 'count(*) filter (where x.failed)', 'x.at', 'x.direction = ''out''', 'count', '{admin,marketing}', false, false, null, 34),
  ('wa_cost', 'WhatsApp cost (estimate)', 'Nurture', 'messages', 'coalesce(sum(x.cost), 0)', 'x.at', 'x.channel = ''whatsapp'' and x.direction = ''out''', 'money', '{admin,marketing}', false, false, null, 35),
  ('replies', 'Replies', 'Nurture', 'replies', 'count(*)', 'x.created_at', null, 'count', '{admin,marketing}', false, true, null, 36),
  ('replies_positive', 'Positive replies', 'Nurture', 'replies', 'count(*)', 'x.created_at', 'coalesce(x.corrected_class, x.class) = ''positive''', 'count', '{admin,marketing}', false, true, null, 37),
  ('journey_entries', 'Journey entries', 'Nurture', 'journeys', 'count(*)', 'x.entered_at', 'not x.is_test', 'count', '{admin,marketing}', false, true, null, 38),
  ('journey_exits', 'Journey exits', 'Nurture', 'journeys', 'count(*)', 'x.exited_at', 'x.exited_at is not null and not x.is_test', 'count', '{admin,marketing}', false, true, null, 39),
  -- sales funnel (by the date the lead was assigned)
  ('assigned', 'Assigned', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.owner_id is not null', 'count', '{admin,marketing,sales}', true, true, null, 40),
  ('contacted', 'Contacted', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.contacted_at is not null', 'count', '{admin,marketing,sales}', true, true, null, 41),
  ('counselled', 'Counselled', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.counselled_at is not null', 'count', '{admin,marketing,sales}', true, true, 'Qualified or later', 42),
  ('applied', 'Applied', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.applied_at is not null', 'count', '{admin,marketing,sales}', true, true, null, 43),
  ('enrolled', 'Enrolled', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.enrolled_on is not null and not x.refunded', 'count', '{admin,marketing,sales}', true, true, null, 44),
  ('lost', 'Lost', 'Sales funnel', 'leads', 'count(*)', 'x.assigned_at', 'x.stage_id = 10', 'count', '{admin,marketing,sales}', true, false, null, 45),
  ('conversion', 'Conversion to enrolment', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.enrolled_on is not null and not x.refunded) / nullif(count(*), 0), 1)',
     'x.assigned_at', 'x.owner_id is not null', 'pct', '{admin,marketing,sales}', false, true, null, 46),
  ('days_to_enrol', 'Days from assignment to enrolment', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.enrolled_at - x.assigned_at) / 86400)::numeric, 1)', 'x.enrolled_at',
     'x.enrolled_at is not null and x.assigned_at is not null', 'days', '{admin,marketing,sales}', false, false, null, 47),
  ('enrollments', 'Enrolments', 'Sales funnel', 'leads', 'count(*)', 'x.enrolled_at', 'not x.refunded', 'count', '{admin,marketing,sales}', true, true, 'By enrolment date', 48),
  ('open_leads', 'Open leads now', 'Sales funnel', 'leads', 'count(*)', null, 'x.status = ''active'' and x.owner_id is not null', 'count', '{admin,marketing,sales}', true, true, null, 49),
  -- speed and effort
  ('first_contact_min', 'First-contact time (median, min)', 'Speed and effort', 'leads', 'round((percentile_cont(0.5) within group (order by x.first_contact_minutes))::numeric, 0)',
     'x.assigned_at', 'x.first_contact_minutes is not null', 'minutes', '{admin,marketing,sales}', false, false, null, 50),
  ('sla_met_pct', 'First-contact SLA met', 'Speed and effort', 'leads', 'round(100.0 * count(*) filter (where x.sla_met) / nullif(count(*), 0), 1)', 'x.assigned_at',
     'x.sla_due_at is not null', 'pct', '{admin,marketing,sales}', false, true, null, 51),
  ('sla_breaches', 'SLA breaches', 'Speed and effort', 'leads', 'count(*)', 'x.sla_breached_at', null, 'count', '{admin,marketing,sales}', true, false, null, 52),
  ('calls_logged', 'Calls logged', 'Speed and effort', 'calls', 'count(*)', 'x.logged_at', 'x.logged_at is not null', 'count', '{admin,marketing,sales}', false, true, null, 53),
  ('calls_connected', 'Calls connected', 'Speed and effort', 'calls', 'count(*)', 'x.logged_at', 'x.outcome = ''connected''', 'count', '{admin,marketing,sales}', false, true, null, 54),
  ('connect_rate', 'Connect rate', 'Speed and effort', 'calls', 'round(100.0 * count(*) filter (where x.outcome = ''connected'') / nullif(count(*), 0), 1)', 'x.logged_at',
     'x.logged_at is not null', 'pct', '{admin,marketing,sales}', false, true, null, 55),
  ('calls_per_lead', 'Calls per lead', 'Speed and effort', 'leads', 'round(avg(x.calls)::numeric, 1)', 'x.assigned_at', 'x.owner_id is not null', 'number', '{admin,marketing,sales}', false, true, null, 56),
  ('attempts_before_connect', 'Attempts before connect', 'Speed and effort', 'leads', 'round(avg(x.attempts_before_connect)::numeric, 1)', 'x.assigned_at',
     'x.calls_connected > 0', 'number', '{admin,marketing,sales}', false, false, null, 57),
  ('followups_on_time', 'Follow-ups on time', 'Speed and effort', 'tasks', 'count(*)', 'x.due_at', 'x.status = ''done'' and x.done_at <= x.due_at + interval ''15 minutes''', 'count', '{admin,marketing,sales}', false, true, null, 58),
  ('followups_late', 'Follow-ups late', 'Speed and effort', 'tasks', 'count(*)', 'x.due_at', 'x.status = ''done'' and x.done_at > x.due_at + interval ''15 minutes''', 'count', '{admin,marketing,sales}', false, false, null, 59),
  ('followups_missed', 'Follow-ups missed (open, past due)', 'Speed and effort', 'tasks', 'count(*)', 'x.due_at', 'x.status = ''open'' and x.due_at < now()', 'count', '{admin,marketing,sales}', false, false, null, 60),
  ('untouched', 'Untouched 48 h', 'Speed and effort', 'leads', 'count(*)', null,
     'x.status = ''active'' and x.owner_id is not null and coalesce(x.last_activity_at, x.assigned_at) < now() - interval ''48 hours''', 'count', '{admin,marketing,sales}', true, false, null, 61),
  ('unlogged_calls', 'Calls tapped, not logged', 'Speed and effort', 'calls', 'count(*)', 'x.tapped_at', 'x.logged_at is null and x.unlogged_flagged_at is not null', 'count', '{admin,marketing,sales}', false, false, null, 62),
  ('wa_sales_sent', 'Sales WhatsApp sent', 'Speed and effort', 'messages', 'count(*)', 'x.at', 'x.channel = ''whatsapp'' and x.direction = ''out'' and not x.marketing', 'count', '{admin,marketing,sales}', false, true, null, 63),
  ('email_sales_sent', 'Sales emails sent', 'Speed and effort', 'messages', 'count(*)', 'x.at', 'x.channel = ''email'' and x.direction = ''out'' and not x.marketing', 'count', '{admin,marketing,sales}', false, true, null, 64),
  -- fallback value, money
  ('fallback_enrollments', 'Enrolments from partner-lost and duplicate leads', 'Fallback value', 'leads', 'count(*)', 'x.enrolled_at',
     'not x.refunded and (x.partner is not null or x.handoff_reason in (''partner_lost'', ''duplicate'', ''duplicate_cascade''))', 'count', '{admin,marketing}', true, true, null, 70),
  ('fallback_commission', 'University commission from those leads', 'Fallback value', 'leads', 'coalesce(sum(x.university_gross), 0)', 'x.enrolled_at',
     'x.partner is not null or x.handoff_reason in (''partner_lost'', ''duplicate'', ''duplicate_cascade'')', 'money', '{admin,marketing}', false, true, null, 71),
  ('uni_expected', 'University commission expected (gross)', 'Money', 'earnings', 'coalesce(sum(x.gross) filter (where x.realised_at is null), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true, null, 80),
  ('uni_realised', 'University commission realised (gross)', 'Money', 'earnings', 'coalesce(sum(x.gross) filter (where x.realised_at is not null), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true, null, 81),
  ('uni_net', 'University commission net of GST', 'Money', 'earnings', 'coalesce(sum(x.net), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true, null, 82),
  ('uni_gst', 'GST on university commission', 'Money', 'earnings', 'coalesce(sum(x.gst), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true, null, 83),
  ('counsellor_commission', 'Counsellor commission owed', 'Money', 'commission', 'coalesce(sum(x.amount), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing,sales}', false, true,
     'What counsellors owe Eduwit at the highest partner rate', 84),
  ('commission_settled', 'Counsellor commission settled', 'Money', 'commission', 'coalesce(sum(x.amount) filter (where x.status = ''settled''), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing,sales}', false, true, null, 85),
  ('commission_needs_rate', 'Lines waiting for a rate', 'Money', 'commission', 'count(*) filter (where x.status = ''needs_rate'')', null, null, 'count', '{admin,marketing}', false, false, null, 86),
  -- team, quality
  ('assignments', 'Assignments', 'Team', 'assignments', 'count(*)', 'x.at', null, 'count', '{admin,marketing,sales}', false, true, 'Leads given to each person (fairness)', 90),
  ('classified_replies', 'Replies classified', 'Quality', 'replies', 'count(*)', 'x.created_at', 'x.class is not null', 'count', '{admin,marketing}', false, true, null, 95),
  ('classification_accuracy', 'Classification accuracy', 'Quality', 'replies', 'round(100.0 * count(*) filter (where x.corrected_class is null or x.corrected_class = x.class) / nullif(count(*), 0), 1)',
     'x.created_at', 'x.class is not null and x.method in (''rule'', ''claude'')', 'pct', '{admin,marketing}', false, true, 'Share not corrected by a person', 96),
  ('missing_fields', 'Leads missing required fields', 'Quality', 'leads', 'count(*)', null, 'x.missing_count > 0 and x.status <> ''closed''', 'count', '{admin,marketing}', true, false, null, 97),
  ('duplicate_suspects', 'Flagged leads', 'Quality', 'leads', 'count(*)', null, 'x.flagged is not null', 'count', '{admin,marketing}', true, false, null, 98),
  ('cross_sell_changes', 'Cross-sell changes', 'Quality', 'activities', 'count(*)', 'x.at', 'x.kind = ''correction''', 'count', '{admin,marketing,sales}', false, true, null, 99)
on conflict (key) do update set label = excluded.label, area = excluded.area, source = excluded.source, agg = excluded.agg, date_sql = excluded.date_sql, where_sql = excluded.where_sql,
  fmt = excluded.fmt, roles = excluded.roles, counts_leads = excluded.counts_leads, higher_is_better = excluded.higher_is_better, description = excluded.description, sort = excluded.sort;

insert into b2c.dim_defs (key, label, expr, sources, money, sort) values
  ('day', 'Day', 'to_char(:date at time zone ''Asia/Kolkata'', ''YYYY-MM-DD'')', null, false, 1),
  ('week', 'Week', 'to_char(date_trunc(''week'', :date at time zone ''Asia/Kolkata''), ''YYYY-MM-DD'')', null, false, 2),
  ('month', 'Month', 'to_char(date_trunc(''month'', :date at time zone ''Asia/Kolkata''), ''YYYY-MM'')', null, false, 3),
  ('counsellor', 'Counsellor', 'u.full_name', null, false, 10),
  ('team', 'Team', 'u.team', null, false, 11),
  ('lane', 'Lane', 'f.lane', null, false, 20),
  ('reason', 'Hand-off reason', 'f.handoff_reason', null, false, 21),
  ('source', 'Lead source', 'f.source', null, false, 22),
  ('campaign', 'Campaign (source)', 'f.campaign', null, false, 23),
  ('partner', 'Partner (lost)', 'f.partner', null, false, 24),
  ('lost_reason', 'Lost reason', 'f.lost_reason', null, false, 25),
  ('course', 'Course', 'f.course', null, false, 30),
  ('specialization', 'Specialization', 'f.specialization', null, false, 31),
  ('university', 'University (interest)', 'f.university', null, false, 32),
  ('enrolled_university', 'University (enrolled)', 'f.enrolled_university', null, false, 33),
  ('enrolled_programme', 'Programme (enrolled)', 'f.enrolled_programme', null, false, 34),
  ('city', 'City', 'f.city', null, false, 35),
  ('state', 'State', 'f.state', null, false, 36),
  ('stage', 'Stage', 'f.stage', null, false, 40),
  ('sub_stage', 'Sub-stage', 'f.sub_stage', null, false, 41),
  ('canonical', 'Canonical stage', 'f.canonical', null, false, 42),
  ('temperature', 'Temperature', 'f.temperature', null, false, 43),
  ('score_band', 'Score band', 'f.score_band', null, false, 44),
  ('journey', 'Journey (current)', 'f.journey', null, false, 50),
  ('pool_reason', 'Pool reason', 'f.pool_reason', null, false, 51),
  ('reengage_trigger', 'Re-engagement trigger', 'f.reengage_trigger', null, false, 52),
  ('channel', 'Channel', 'x.channel', '{messages,replies}', false, 60),
  ('message_status', 'Message status', 'x.status', '{messages}', false, 61),
  ('template', 'Template', 'x.template', '{messages}', false, 62),
  ('call_outcome', 'Call outcome', 'x.outcome', '{calls}', false, 63),
  ('reply_class', 'Reply class', 'coalesce(x.corrected_class, x.class)', '{replies}', false, 64),
  ('journey_name', 'Journey', 'x.journey_name', '{journeys}', false, 65),
  ('exit_reason', 'Exit reason', 'x.exit_reason', '{journeys}', false, 66),
  ('commission_status', 'Commission status', 'x.status', '{commission}', true, 70),
  ('rate_source', 'Rate source', 'x.rate_source', '{commission}', true, 71),
  ('task_kind', 'Task kind', 'x.kind', '{tasks}', false, 72),
  ('assignment_trigger', 'Assignment trigger', 'x.trigger', '{assignments}', false, 73)
on conflict (key) do update set label = excluded.label, expr = excluded.expr, sources = excluded.sources, money = excluded.money, sort = excluded.sort;

-- ---------- the query layer ----------
/* The role group a person's analytics run under. */
create or replace function b2c.an_group(p_role text) returns text language sql immutable set search_path = '' as $f$
  select case p_role when 'admin' then 'admin' when 'marketing' then 'marketing' when 'counsellor' then 'sales' when 'sales_head' then 'sales' end
$f$;

/* Validates a spec and builds one query per metric. Errors name what is wrong so the Ask feature can retry. The scope
   (own leads for a counsellor, the team for a sales head) is part of every query and cannot be removed by the spec. */
create or replace function b2c.analytics_exec(p_user uuid, p_role text, spec jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  g text := b2c.an_group(p_role); m b2c.metric_defs; s b2c.an_sources; d b2c.dim_defs; v_metrics text[]; v_dims text[]; k text; i int;
  v_from date := coalesce(nullif(spec ->> 'from', '')::date, (now() at time zone 'Asia/Kolkata')::date - 29);
  v_to date := coalesce(nullif(spec ->> 'to', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  v_test boolean := coalesce((spec ->> 'test')::boolean, false); v_limit int := least(greatest(coalesce((spec ->> 'limit')::int, 500), 1), 5000);
  v_where text; v_scope text; v_sel text; v_grp text; v_sql text; v_rows jsonb; v_out jsonb := '{}'; v_sqls jsonb := '[]'; c jsonb; v_expr text; v_op text; v_cmp jsonb;
  v_team text; v_date text; v_cmp_from date; v_cmp_to date; v_all_rows jsonb;
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(x) into v_metrics from jsonb_array_elements_text(coalesce(spec -> 'metrics', '[]')) x;
  select array_agg(x) into v_dims from jsonb_array_elements_text(coalesce(spec -> 'dims', '[]')) x;
  if coalesce(array_length(v_metrics, 1), 0) = 0 then raise exception 'pick at least one metric'; end if;
  if array_length(v_metrics, 1) > 6 then raise exception 'at most 6 metrics'; end if;
  if coalesce(array_length(v_dims, 1), 0) > 2 then raise exception 'at most 2 dimensions'; end if;
  if v_to < v_from or v_to - v_from > 1100 then raise exception 'the date range must run forwards and cover at most 3 years'; end if;
  select team into v_team from b2c.users where user_id = p_user;
  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    if m.key is null then raise exception 'unknown metric: %', k; end if;
    if not g = any (m.roles) then raise exception 'metric % is not available to your role', k; end if;
  end loop;
  foreach k in array coalesce(v_dims, '{}') loop
    select * into d from b2c.dim_defs where key = k;
    if d.key is null then raise exception 'unknown dimension: %', k; end if;
  end loop;
  -- comparison period
  if spec ->> 'compare' = 'previous' then v_cmp_to := v_from - 1; v_cmp_from := v_cmp_to - (v_to - v_from);
  elsif spec ->> 'compare' = 'year' then v_cmp_from := (v_from - interval '1 year')::date; v_cmp_to := (v_to - interval '1 year')::date; end if;

  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    select * into s from b2c.an_sources where key = m.source;
    v_date := coalesce(m.date_sql, 'now()');
    -- the role's scope: never optional
    v_scope := case g
      when 'sales' then case when p_role = 'sales_head'
                             then format('(%1$s in (select w.user_id from b2c.users w where w.role in (''counsellor'', ''sales_head'') and (%2$L is null or w.team = %2$L or w.user_id = %3$L)))', s.actor_sql, v_team, p_user)
                             else format('(%s = %L%s)', s.actor_sql, p_user, case when m.source in ('leads', 'replies', 'journeys', 'commission') then '' else format(' and f.owner_id = %L', p_user) end) end
      else 'true' end;
    v_where := format('%s and coalesce(f.is_test, false) = %L and not coalesce(f.deleted, false)', v_scope, v_test);
    if m.where_sql is not null then v_where := v_where || ' and (' || m.where_sql || ')'; end if;
    -- user filters, by dimension key only
    for c in select * from jsonb_array_elements(coalesce(spec -> 'filters', '[]')) loop
      select * into d from b2c.dim_defs where key = c ->> 'dim';
      if d.key is null then raise exception 'unknown dimension in a filter: %', c ->> 'dim'; end if;
      if d.sources is not null and not m.source = any (d.sources) then continue; end if;
      if d.money and g = 'sales' and m.source <> 'commission' then raise exception 'that filter is not available to your role'; end if;
      v_expr := '(' || replace(d.expr, ':date', v_date) || ')';
      v_op := coalesce(c ->> 'op', 'eq');
      v_where := v_where || ' and ' || case v_op
        when 'eq' then format('%s::text = %L', v_expr, c ->> 'value')
        when 'neq' then format('%s::text is distinct from %L', v_expr, c ->> 'value')
        when 'in' then format('%s::text = any (%L::text[])', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'not_in' then format('not coalesce(%s::text = any (%L::text[]), false)', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'contains' then format('%s::text ilike %L', v_expr, '%' || (c ->> 'value') || '%')
        when 'is_null' then format('%s is null', v_expr)
        when 'not_null' then format('%s is not null', v_expr)
        else null end;
      if v_where is null then raise exception 'unknown filter operator: %', v_op; end if;
    end loop;
    -- dimensions valid for this metric's source
    v_sel := ''; v_grp := '';
    for i in 1 .. coalesce(array_length(v_dims, 1), 0) loop
      select * into d from b2c.dim_defs where key = v_dims[i];
      if d.sources is not null and not m.source = any (d.sources) then
        v_expr := 'null::text';
      elsif d.money and g = 'sales' and m.source <> 'commission' then
        raise exception 'that dimension is not available to your role';
      elsif d.key in ('day', 'week', 'month') and m.date_sql is null then
        v_expr := 'null::text';
      else
        v_expr := '(' || replace(d.expr, ':date', v_date) || ')::text';
      end if;
      v_sel := v_sel || format('%s as d%s, ', v_expr, i);
      v_grp := v_grp || case when v_grp = '' then '' else ', ' end || i;
    end loop;
    v_sql := format('select %s(%s)::numeric as v from %s left join b2c.fact_leads f on f.lead_id = x.lead_id left join b2c.users u on u.user_id = %s where %s%s%s',
                    v_sel, m.agg, s.from_sql, s.actor_sql,
                    v_where,
                    case when m.date_sql is not null then format(' and %1$s >= (%2$L::date::timestamp at time zone ''Asia/Kolkata'') and %1$s < ((%3$L::date + 1)::timestamp at time zone ''Asia/Kolkata'')', m.date_sql, '%FROM%', '%TO%') else '' end,
                    case when v_grp <> '' then ' group by ' || v_grp else '' end);
    v_sqls := v_sqls || jsonb_build_object('metric', k, 'sql', replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text));
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                   coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                   replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text)) into v_rows;
    for c in select * from jsonb_array_elements(v_rows) loop
      v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k, c -> 'v'));
    end loop;
    if v_cmp_from is not null then
      execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                     coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                     replace(replace(v_sql, '%FROM%', v_cmp_from::text), '%TO%', v_cmp_to::text)) into v_rows;
      for c in select * from jsonb_array_elements(v_rows) loop
        v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k || '__cmp', c -> 'v'));
      end loop;
    end if;
  end loop;
  select coalesce(jsonb_agg(x order by x -> 'k'), '[]') into v_all_rows from (select value as x from jsonb_each(v_out) limit v_limit) q;
  return jsonb_build_object('rows', v_all_rows, 'metrics', v_metrics, 'dims', coalesce(to_jsonb(v_dims), '[]'), 'from', v_from, 'to', v_to,
                            'compare', case when v_cmp_from is not null then jsonb_build_object('from', v_cmp_from, 'to', v_cmp_to) end,
                            'test', v_test, 'sql', v_sqls, 'scope', case g when 'sales' then case when p_role = 'sales_head' then 'team' else 'own leads' end else 'all' end,
                            'defs', (select jsonb_agg(jsonb_build_object('key', md.key, 'label', md.label, 'fmt', md.fmt, 'higher_is_better', md.higher_is_better, 'counts_leads', md.counts_leads))
                                       from b2c.metric_defs md where md.key = any (v_metrics)));
end $f$;

create or replace function b2c.analytics_run(spec jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role();
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2c.analytics_exec(b2c.uid(), v_role, spec);
end $f$;

/* Service role (scheduled emails, alerts, insights): the same, as that person. */
create or replace function b2c.analytics_run_for(p_user uuid, spec jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text;
begin
  select role into v_role from b2c.users where user_id = p_user and is_active;
  if v_role is null then raise exception 'not an active user'; end if;
  return b2c.analytics_exec(p_user, v_role, spec);
end $f$;

/* What the caller may ask for: the metrics and dimensions of their role (the Ask feature sends only this to Claude). */
create or replace function b2c.analytics_catalog() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare g text := b2c.an_group(b2c.my_role());
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('group', g, 'scope', case g when 'sales' then case when b2c.my_role() = 'sales_head' then 'team' else 'own leads' end else 'all' end,
    'metrics', (select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'area', area, 'source', source, 'fmt', fmt, 'description', description, 'as_of_now', date_sql is null,
                                                    'counts_leads', counts_leads, 'higher_is_better', higher_is_better) order by sort) from b2c.metric_defs where g = any (roles)),
    'dims', (select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'sources', sources) order by sort) from b2c.dim_defs where not (money and g = 'sales')));
end $f$;

-- ---------- drill-down ----------
create table if not exists b2c.analytics_drills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  label text,
  lead_ids bigint[] not null,
  spec jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists analytics_drills_user on b2c.analytics_drills (user_id, created_at desc);

/* The leads behind one number: the metric's rows under the same spec and scope, narrowed to one cell (dimension values). */
create or replace function b2c.analytics_drill_ids(p_user uuid, p_role text, spec jsonb, p_metric text, p_cell jsonb default '{}'::jsonb) returns bigint[]
language plpgsql stable security definer set search_path = '' as $f$
declare r jsonb; v_sql text; v_where text; i int := 0; k text; d b2c.dim_defs; v_ids bigint[]; m b2c.metric_defs; v_date text;
begin
  r := b2c.analytics_exec(p_user, p_role, jsonb_build_object('metrics', jsonb_build_array(p_metric), 'filters', coalesce(spec -> 'filters', '[]'),
                                                             'from', spec -> 'from', 'to', spec -> 'to', 'test', spec -> 'test'));
  select * into m from b2c.metric_defs where key = p_metric;
  v_date := coalesce(m.date_sql, 'now()');
  v_sql := r -> 'sql' -> 0 ->> 'sql';
  v_where := '';
  for k in select jsonb_object_keys(coalesce(p_cell, '{}')) loop
    select * into d from b2c.dim_defs where key = k;
    if d.key is null then raise exception 'unknown dimension: %', k; end if;
    if d.sources is not null and not m.source = any (d.sources) then continue; end if;
    v_where := v_where || case when p_cell ->> k is null then format(' and (%s) is null', replace(d.expr, ':date', v_date))
                               else format(' and (%s)::text = %L', replace(d.expr, ':date', v_date), p_cell ->> k) end;
  end loop;
  -- the same query, but the leads instead of the aggregate
  v_sql := regexp_replace(v_sql, '^select \(.*?\)::numeric as v from ', 'select distinct x.lead_id from ');
  execute 'select array_agg(lead_id) from (' || v_sql || v_where || ' limit 10000) q' into v_ids;
  return coalesce(v_ids, '{}');
end $f$;

create or replace function b2c.analytics_drill(spec jsonb, p_metric text, p_cell jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); v_ids bigint[]; v uuid;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_ids := b2c.analytics_drill_ids(b2c.uid(), v_role, spec, p_metric, p_cell);
  insert into b2c.analytics_drills (user_id, label, lead_ids, spec) values (b2c.uid(), (select label from b2c.metric_defs where key = p_metric), v_ids,
                                                                          spec || jsonb_build_object('metric', p_metric, 'cell', p_cell))
  returning id into v;
  return jsonb_build_object('drill_id', v, 'count', coalesce(array_length(v_ids, 1), 0));
end $f$;

/* lead_list (b5) learns one more input: p.drill, the id of a drill-down list. Everything else as before. */
create or replace function b2c.lead_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_role text := b2c.my_role(); me uuid := b2c.uid(); w text := 'true'; c jsonb; v_field text; v_op text; v_sql text; v_rows jsonb; v_total int;
  v_any text; f jsonb := coalesce(p -> 'filters', '{}'); v_sort text; v_dir text; v_limit int := least(coalesce((p ->> 'limit')::int, 50), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
  allowed text[] := array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at'];
  v_drill bigint[];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role = 'counsellor' then w := format('owner_id = %L', me); end if;
  if nullif(p ->> 'drill', '') is not null then
    select lead_ids into v_drill from b2c.analytics_drills where id = (p ->> 'drill')::uuid and user_id = me;
    w := w || format(' and lead_id = any (%L::bigint[])', coalesce(v_drill, '{}'));
  end if;
  w := w || case when coalesce((p ->> 'deleted')::boolean, false) then ' and deleted_at is not null' else ' and deleted_at is null' end;
  if not coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_drill is not null) then w := w || ' and not is_test'; end if;
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, allowed);
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  if coalesce(trim(p ->> 'search'), '') <> '' then
    w := w || format(' and (name ilike %1$L or email ilike %1$L or b2c.norm_phone(phone) like %2$L or lead_id::text = %3$L
                       or exists (select 1 from b2c.lead_contacts lc where lc.lead_id = v.lead_id and lc.value_norm like %2$L)
                       or exists (select 1 from b2c.applications ap where ap.lead_id = v.lead_id and ap.application_ref ilike %1$L))',
                     '%' || trim(p ->> 'search') || '%', '%' || coalesce(nullif(regexp_replace(p ->> 'search', '\D', '', 'g'), ''), '~none~') || '%', trim(p ->> 'search'));
  end if;
  v_sort := coalesce(p -> 'sort' ->> 'field', 'next_task_due_at');
  if not v_sort = any (allowed) then v_sort := 'next_task_due_at'; end if;
  v_dir := case when lower(coalesce(p -> 'sort' ->> 'dir', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_sql := format('select count(*) over () total, to_jsonb(v) - ''providers'' - ''handling'' as row from b2c.leads_v v where %s order by %I %s nulls last, lead_id desc limit %s offset %s',
                  w, v_sort, v_dir, v_limit, v_offset);
  execute format('select coalesce(max(total), 0), coalesce(jsonb_agg(row), ''[]'') from (%s) q', v_sql) into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $f$;

-- ---------- dashboards ----------
create table if not exists b2c.dashboards (
  id bigint generated always as identity primary key,
  key text unique,                       -- standard dashboards: a stable key
  name text not null,
  description text,
  owner_id uuid references b2c.users (user_id),   -- null = standard
  roles text[] not null default '{}',    -- standard: the role groups that get it (admin, marketing, sales)
  widgets jsonb not null default '[]'::jsonb,     -- [{id, title, viz, spec, w, note}]
  filters jsonb not null default '{}'::jsonb,     -- dashboard-wide: {from, to, range, compare, filters: [...]}
  sort int not null default 100,
  copied_from bigint,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create table if not exists b2c.dashboard_homes (
  user_id uuid primary key references b2c.users (user_id),
  dashboard_id bigint not null references b2c.dashboards (id),
  set_at timestamptz not null default now()
);

create or replace function b2c.dashboard_may_see(p_id bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from b2c.dashboards d where d.id = p_id and d.archived_at is null
                  and (d.owner_id = b2c.uid() or (d.owner_id is null and b2c.an_group(b2c.my_role()) = any (d.roles)) or b2c.can('settings')))
$f$;

create or replace function b2c.dashboards_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare g text := b2c.an_group(b2c.my_role());
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('home', (select dashboard_id from b2c.dashboard_homes where user_id = b2c.uid()),
    'standard', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'key', key, 'name', name, 'description', description, 'roles', roles, 'widgets', jsonb_array_length(widgets)) order by sort, name), '[]')
                   from b2c.dashboards where owner_id is null and archived_at is null and (g = any (roles) or b2c.can('settings'))),
    'mine', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'description', description, 'widgets', jsonb_array_length(widgets), 'updated_at', updated_at) order by name), '[]')
               from b2c.dashboards where owner_id = b2c.uid() and archived_at is null));
end $f$;

create or replace function b2c.dashboard_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.dashboard_may_see(p_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select to_jsonb(d) || jsonb_build_object('mine', d.owner_id = b2c.uid(), 'standard', d.owner_id is null,
                   'home', exists (select 1 from b2c.dashboard_homes h where h.user_id = b2c.uid() and h.dashboard_id = d.id))
            from b2c.dashboards d where d.id = p_id);
end $f$;

/* Checks every widget's spec against the catalogue for the caller (a widget the role may not run is refused). */
create or replace function b2c.dashboard_check(p_widgets jsonb) returns void language plpgsql stable security definer set search_path = '' as $f$
declare w jsonb; v_role text := b2c.my_role();
begin
  if jsonb_typeof(p_widgets) <> 'array' or jsonb_array_length(p_widgets) > 40 then raise exception 'a dashboard has at most 40 widgets'; end if;
  for w in select * from jsonb_array_elements(p_widgets) loop
    if coalesce(w ->> 'viz', '') not in ('kpi', 'line', 'bar', 'stacked', 'funnel', 'cohort', 'table', 'pivot', 'leaderboard', 'gauge', 'map', 'text') then
      raise exception 'unknown widget type: %', w ->> 'viz';
    end if;
    if w ->> 'viz' <> 'text' then
      perform b2c.analytics_exec(b2c.uid(), v_role, (w -> 'spec') || jsonb_build_object('from', current_date, 'to', current_date, 'compare', null));
    end if;
  end loop;
end $f$;

/* Saves a personal dashboard (or, for the Admin, a standard one). A standard dashboard edited by anyone else is copied. */
create or replace function b2c.dashboard_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; d b2c.dashboards;
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'widgets' then perform b2c.dashboard_check(p -> 'widgets'); end if;
  if v is not null then
    select * into d from b2c.dashboards where id = v and archived_at is null;
    if d.id is null then raise exception 'unknown dashboard'; end if;
    if d.owner_id is distinct from me and not (d.owner_id is null and b2c.can('settings')) then
      v := null;   -- not theirs: save as their own copy
      p := p || jsonb_build_object('name', coalesce(p ->> 'name', d.name), 'widgets', coalesce(p -> 'widgets', d.widgets), 'filters', coalesce(p -> 'filters', d.filters));
    end if;
  end if;
  if v is null then
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the dashboard'; end if;
    insert into b2c.dashboards (name, description, owner_id, widgets, filters, copied_from, created_by)
    values (left(trim(p ->> 'name'), 120), p ->> 'description', me, coalesce(p -> 'widgets', '[]'), coalesce(p -> 'filters', '{}'), d.id, me)
    returning id into v;
  else
    update b2c.dashboards set name = coalesce(nullif(left(trim(p ->> 'name'), 120), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           widgets = coalesce(p -> 'widgets', widgets), filters = coalesce(p -> 'filters', filters), updated_at = now()
     where id = v;
  end if;
  return v;
end $f$;

create or replace function b2c.dashboard_duplicate(p_id bigint, p_name text default null) returns bigint language plpgsql security definer set search_path = '' as $f$
declare d b2c.dashboards; v bigint;
begin
  if not b2c.dashboard_may_see(p_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from b2c.dashboards where id = p_id;
  insert into b2c.dashboards (name, description, owner_id, widgets, filters, copied_from, created_by)
  values (coalesce(nullif(trim(p_name), ''), d.name || ' (copy)'), d.description, b2c.uid(), d.widgets, d.filters, d.id, b2c.uid()) returning id into v;
  return v;
end $f$;

create or replace function b2c.dashboard_home(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if not b2c.dashboard_may_see(p_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2c.dashboard_homes (user_id, dashboard_id) values (b2c.uid(), p_id)
  on conflict (user_id) do update set dashboard_id = excluded.dashboard_id, set_at = now();
end $f$;

/* The Admin publishes a dashboard as a standard one for role groups (a personal one is copied; the copy is standard). */
create or replace function b2c.dashboard_publish(p_id bigint, p_roles text[]) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); d b2c.dashboards; v bigint;
begin
  if p_roles is null or not p_roles <@ array['admin', 'marketing', 'sales'] then raise exception 'roles are admin, marketing and sales'; end if;
  select * into d from b2c.dashboards where id = p_id and archived_at is null;
  if d.id is null then raise exception 'unknown dashboard'; end if;
  if d.owner_id is null then
    update b2c.dashboards set roles = p_roles, updated_at = now() where id = p_id;
    v := p_id;
  else
    insert into b2c.dashboards (name, description, owner_id, roles, widgets, filters, copied_from, created_by)
    values (d.name, d.description, null, p_roles, d.widgets, d.filters, d.id, me) returning id into v;
  end if;
  perform b2c.log('analytics.dashboard_published', null, jsonb_build_object('dashboard_id', v, 'roles', p_roles));
  return v;
end $f$;

create or replace function b2c.dashboard_archive(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.dashboards set archived_at = now() where id = p_id and archived_at is null and (owner_id = b2c.uid() or (owner_id is null and b2c.can('settings')));
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $f$;

-- ---------- schedules ----------
create table if not exists b2c.dashboard_schedules (
  id bigint generated always as identity primary key,
  dashboard_id bigint not null references b2c.dashboards (id),
  user_id uuid not null references b2c.users (user_id),
  freq text not null check (freq in ('daily', 'weekly', 'monthly')),
  format text not null default 'pdf' check (format in ('pdf', 'csv')),
  hour_ist int not null default 8 check (hour_ist between 0 and 23),
  weekday int check (weekday between 1 and 7),     -- weekly: ISO day
  monthday int check (monthday between 1 and 28),  -- monthly
  next_at timestamptz not null,
  last_sent_at timestamptz,
  last_error text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function b2c.schedule_next(p_freq text, p_hour int, p_weekday int, p_monthday int, p_after timestamptz) returns timestamptz
language plpgsql immutable set search_path = '' as $f$
declare t timestamp := (p_after at time zone 'Asia/Kolkata'); c timestamp;
begin
  c := date_trunc('day', t) + make_interval(hours => p_hour);
  if p_freq = 'daily' then
    if c <= t then c := c + interval '1 day'; end if;
  elsif p_freq = 'weekly' then
    c := c + make_interval(days => ((coalesce(p_weekday, 1) - extract(isodow from c)::int + 7) % 7));
    if c <= t then c := c + interval '7 days'; end if;
  else
    c := date_trunc('month', t) + make_interval(days => coalesce(p_monthday, 1) - 1, hours => p_hour);
    if c <= t then c := date_trunc('month', t) + interval '1 month' + make_interval(days => coalesce(p_monthday, 1) - 1, hours => p_hour); end if;
  end if;
  return c at time zone 'Asia/Kolkata';
end $f$;

create or replace function b2c.schedule_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint := nullif(p ->> 'id', '')::bigint; me uuid := b2c.uid();
begin
  if not b2c.dashboard_may_see((p ->> 'dashboard_id')::bigint) then raise exception 'not allowed' using errcode = '42501'; end if;
  if v is null then
    insert into b2c.dashboard_schedules (dashboard_id, user_id, freq, format, hour_ist, weekday, monthday, next_at)
    values ((p ->> 'dashboard_id')::bigint, me, p ->> 'freq', coalesce(p ->> 'format', 'pdf'), coalesce((p ->> 'hour_ist')::int, 8), nullif(p ->> 'weekday', '')::int,
            nullif(p ->> 'monthday', '')::int,
            b2c.schedule_next(p ->> 'freq', coalesce((p ->> 'hour_ist')::int, 8), nullif(p ->> 'weekday', '')::int, nullif(p ->> 'monthday', '')::int, now()))
    returning id into v;
  else
    update b2c.dashboard_schedules set active = coalesce((p ->> 'active')::boolean, active) where id = v and user_id = me;
    if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v;
end $f$;

create or replace function b2c.schedules_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('dashboard', d.name) order by s.id), '[]')
    from b2c.dashboard_schedules s join b2c.dashboards d on d.id = s.dashboard_id where s.user_id = b2c.uid()
$f$;

/* Service role: the schedules due now (each claimed: next_at moves on at once). */
create or replace function b2c.schedules_take(p_limit int default 5) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with due as (select s.id from b2c.dashboard_schedules s join b2c.users u on u.user_id = s.user_id and u.is_active
                where s.active and s.next_at <= now() order by s.next_at limit p_limit for update of s skip locked),
       moved as (update b2c.dashboard_schedules s set next_at = b2c.schedule_next(s.freq, s.hour_ist, s.weekday, s.monthday, now())
                   from due where s.id = due.id returning s.*)
  select coalesce(jsonb_agg(jsonb_build_object('schedule', to_jsonb(m), 'dashboard', to_jsonb(d), 'email', u.email, 'name', u.full_name)), '[]') into v
    from moved m join b2c.dashboards d on d.id = m.dashboard_id join b2c.users u on u.user_id = m.user_id;
  return v;
end $f$;

create or replace function b2c.schedule_done(p_id bigint, p_error text default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.dashboard_schedules set last_sent_at = case when p_error is null then now() else last_sent_at end, last_error = p_error where id = p_id
$f$;

-- ---------- alerts ----------
create table if not exists b2c.metric_alerts (
  id bigint generated always as identity primary key,
  user_id uuid not null references b2c.users (user_id),
  name text not null,
  metric text not null references b2c.metric_defs (key),
  filters jsonb not null default '[]'::jsonb,
  kind text not null default 'threshold' check (kind in ('threshold', 'anomaly')),
  op text check (op in ('above', 'below')),
  threshold numeric,
  win text not null default 'today' check (win in ('today', '7d')),
  channels text[] not null default '{push}',
  last_value numeric,
  last_checked_at timestamptz,
  last_fired_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (kind = 'anomaly' or (op is not null and threshold is not null))
);
create table if not exists b2c.alert_events (
  id bigint generated always as identity primary key,
  alert_id bigint not null references b2c.metric_alerts (id),
  value numeric,
  detail jsonb not null default '{}'::jsonb,
  fired_at timestamptz not null default now(),
  email boolean not null default false,
  emailed_at timestamptz
);

create or replace function b2c.alert_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint := nullif(p ->> 'id', '')::bigint; me uuid := b2c.uid();
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  perform b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array(p ->> 'metric'), 'filters', coalesce(p -> 'filters', '[]')));
  if v is null then
    insert into b2c.metric_alerts (user_id, name, metric, filters, kind, op, threshold, win, channels)
    values (me, coalesce(nullif(trim(p ->> 'name'), ''), (select label from b2c.metric_defs where key = p ->> 'metric')), p ->> 'metric', coalesce(p -> 'filters', '[]'),
            coalesce(p ->> 'kind', 'threshold'), p ->> 'op', nullif(p ->> 'threshold', '')::numeric, coalesce(p ->> 'win', 'today'),
            coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'channels') x where x in ('push', 'email')), '{push}'))
    returning id into v;
  else
    update b2c.metric_alerts set active = coalesce((p ->> 'active')::boolean, active) where id = v and user_id = me;
    if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v;
end $f$;

create or replace function b2c.alerts_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object('label', m.label) order by a.id), '[]') from b2c.metric_alerts a join b2c.metric_defs m on m.key = a.metric where a.user_id = b2c.uid()
$f$;

/* Every 15 minutes: each active alert is evaluated as its owner (so in their scope). Threshold: today's (or 7 days')
   value crosses the line. Anomaly: today's value is more than 3 standard deviations from the last 28 days (at least 14
   days of history). At most one firing per alert per day. */
create or replace function b2c.alerts_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare a record; r jsonb; v numeric; n int := 0; hist numeric[]; mu numeric; sd numeric; fire boolean; d0 date := (now() at time zone 'Asia/Kolkata')::date; v_role text;
begin
  for a in select x.* from b2c.metric_alerts x join b2c.users u on u.user_id = x.user_id and u.is_active
            where x.active and (x.last_checked_at is null or x.last_checked_at < now() - interval '14 minutes') order by x.id limit 200 loop
    begin
      select role into v_role from b2c.users where user_id = a.user_id;
      r := b2c.analytics_exec(a.user_id, v_role, jsonb_build_object('metrics', jsonb_build_array(a.metric), 'filters', a.filters,
                                                                    'from', case when a.win = '7d' then d0 - 6 else d0 end, 'to', d0));
      v := coalesce((r -> 'rows' -> 0 ->> a.metric)::numeric, 0);
      fire := false;
      if a.kind = 'threshold' then
        fire := (a.op = 'above' and v > a.threshold) or (a.op = 'below' and v < a.threshold);
      else
        r := b2c.analytics_exec(a.user_id, v_role, jsonb_build_object('metrics', jsonb_build_array(a.metric), 'dims', jsonb_build_array('day'), 'filters', a.filters,
                                                                      'from', d0 - 28, 'to', d0 - 1));
        select array_agg(coalesce((x ->> a.metric)::numeric, 0)) into hist from jsonb_array_elements(r -> 'rows') x;
        if coalesce(array_length(hist, 1), 0) >= 14 then
          select avg(h), stddev_samp(h) into mu, sd from unnest(hist) h;
          fire := sd > 0 and abs(v - mu) > 3 * sd;
        end if;
      end if;
      update b2c.metric_alerts set last_value = v, last_checked_at = now() where id = a.id;
      if fire and (a.last_fired_at is null or (a.last_fired_at at time zone 'Asia/Kolkata')::date < d0) then
        update b2c.metric_alerts set last_fired_at = now() where id = a.id;
        insert into b2c.alert_events (alert_id, value, detail, email) values (a.id, v, jsonb_build_object('mean', mu, 'sd', sd, 'threshold', a.threshold, 'op', a.op), 'email' = any (a.channels));
        perform b2c.notify(a.user_id, 'alert', left(a.name, 150), case when a.kind = 'threshold' then 'Now ' || v || ' (' || a.op || ' ' || a.threshold || ')'
                                                                 else 'Now ' || v || ', usually about ' || round(mu, 1) end, '/w/analytics?alert=' || a.id, null, 'alert:' || a.id || ':' || d0);
        n := n + 1;
      end if;
    exception when others then
      update b2c.metric_alerts set last_checked_at = now() where id = a.id;
    end;
  end loop;
  return jsonb_build_object('fired', n);
end $f$;

/* Service role: alert firings that asked for an email and have not had one. */
create or replace function b2c.alert_emails_take(p_limit int default 20) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select e.id from b2c.alert_events e where e.email and e.emailed_at is null order by e.id limit p_limit for update skip locked),
       m as (update b2c.alert_events e set emailed_at = now() from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('event', to_jsonb(m), 'alert', to_jsonb(a), 'email', u.email, 'name', u.full_name, 'label', d.label)), '[]') into v
    from m join b2c.metric_alerts a on a.id = m.alert_id join b2c.users u on u.user_id = a.user_id join b2c.metric_defs d on d.key = a.metric;
  return v;
end $f$;

-- ---------- AI: the log, the cap, insights ----------
create table if not exists b2c.ai_calls (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  user_id uuid,
  purpose text not null check (purpose in ('ask', 'explain', 'insights', 'brief', 'classify')),
  model text not null,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  cost_inr numeric(10, 4) not null default 0,
  ms int,
  ok boolean not null default true,
  error text,
  question text,                 -- the user's question (Ask) or the chart title (Explain); never lead data
  spec jsonb,                    -- the query spec the model produced
  sql jsonb,                     -- the SQL that ran
  lead_id bigint                 -- brief only
);
create index if not exists ai_calls_at on b2c.ai_calls (at desc);

create or replace function b2c.ai_spent_today() returns numeric language sql stable security definer set search_path = '' as $f$
  select coalesce(sum(cost_inr), 0) from b2c.ai_calls where at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
$f$;

/* Before a Claude call: is there budget left today? Returns the model and the prices to cost the call. */
create or replace function b2c.ai_budget(p_purpose text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare s jsonb := b2c.setting('ai'); v_spent numeric := b2c.ai_spent_today(); v_cap numeric := coalesce((s ->> 'daily_cap_inr')::numeric, 500);
begin
  if b2c.uid() is not null and b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('allowed', v_spent < v_cap, 'spent_inr', round(v_spent, 2), 'cap_inr', v_cap, 'model', coalesce(s ->> 'model', 'claude-sonnet-5-5'),
                            'usd_inr', coalesce((s ->> 'usd_inr')::numeric, 85), 'prices', s -> 'price_usd_per_mtok', 'purpose', p_purpose);
end $f$;

/* Service role: log one call; the cost is computed here from the token counts and the price table. */
create or replace function b2c.ai_log(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare s jsonb := b2c.setting('ai'); pr jsonb; v bigint; v_cost numeric;
begin
  pr := s -> 'price_usd_per_mtok' -> (p ->> 'model');
  v_cost := (coalesce((p ->> 'input_tokens')::numeric, 0) * coalesce((pr ->> 'in')::numeric, 5) + coalesce((p ->> 'output_tokens')::numeric, 0) * coalesce((pr ->> 'out')::numeric, 25))
            / 1000000 * coalesce((s ->> 'usd_inr')::numeric, 85);
  insert into b2c.ai_calls (user_id, purpose, model, input_tokens, output_tokens, cost_inr, ms, ok, error, question, spec, sql, lead_id)
  values (nullif(p ->> 'user_id', '')::uuid, p ->> 'purpose', p ->> 'model', coalesce((p ->> 'input_tokens')::int, 0), coalesce((p ->> 'output_tokens')::int, 0), v_cost,
          nullif(p ->> 'ms', '')::int, coalesce((p ->> 'ok')::boolean, true), left(p ->> 'error', 500), left(p ->> 'question', 1000), p -> 'spec', p -> 'sql', nullif(p ->> 'lead_id', '')::bigint)
  returning id into v;
  return v;
end $f$;

create or replace function b2c.ai_usage(p_days int default 30) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return jsonb_build_object('today', b2c.ai_spent_today(), 'cap', (b2c.setting('ai') ->> 'daily_cap_inr')::numeric,
    'by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'purpose', purpose, 'calls', n, 'cost_inr', c) order by d desc, purpose), '[]') from (
                 select (at at time zone 'Asia/Kolkata')::date d, purpose, count(*) n, round(sum(cost_inr), 2) c from b2c.ai_calls
                  where at > now() - make_interval(days => p_days) group by 1, 2) s),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'user', (select full_name from b2c.users where user_id = a.user_id), 'purpose', purpose, 'model', model,
                 'cost_inr', cost_inr, 'ok', ok, 'question', question, 'sql', sql) order by at desc), '[]') from (select * from b2c.ai_calls order by at desc limit 50) a));
end $f$;

create table if not exists b2c.insights (
  id bigint generated always as identity primary key,
  role_group text not null check (role_group in ('admin', 'marketing', 'sales')),
  user_id uuid,                  -- sales: one counsellor's feed
  day date not null,
  kind text not null default 'feed' check (kind in ('feed', 'anomaly')),
  items jsonb not null,          -- [{title, body, metric, spec, change}]
  model text,
  created_at timestamptz not null default now()
);
create index if not exists insights_day on b2c.insights (role_group, day desc);

/* What moved: the role's key metrics over the last 7 days against the 7 before, overall and by the main dimensions.
   Aggregates only; this is what the insights prompt receives. */
create or replace function b2c.insights_candidates(p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_user uuid := coalesce(p_user, b2c.uid()); v_role text; g text; k text; dm text; r jsonb; cands jsonb := '[]'; d0 date := (now() at time zone 'Asia/Kolkata')::date - 1;
        keys text[]; dims text[] := array['source', 'counsellor', 'reason', 'university'];
begin
  select role into v_role from b2c.users where user_id = v_user and is_active;
  g := b2c.an_group(v_role);
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_user is not null and b2c.uid() is not null and p_user <> b2c.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  keys := case g when 'sales' then array['assigned', 'contacted', 'calls_connected', 'connect_rate', 'enrollments', 'sla_breaches', 'followups_missed']
                 when 'marketing' then array['pool_entries', 'reengaged', 'reengage_rate', 'marketing_sent', 'replies_positive', 'opted_out', 'wa_cost']
                 else array['handoffs', 'assigned', 'reengaged', 'enrollments', 'connect_rate', 'sla_breaches', 'counsellor_commission', 'uni_expected'] end;
  foreach k in array keys loop
    r := b2c.analytics_exec(v_user, v_role, jsonb_build_object('metrics', jsonb_build_array(k), 'from', d0 - 6, 'to', d0, 'compare', 'previous'));
    cands := cands || jsonb_build_object('metric', k, 'dim', null, 'value', r -> 'rows' -> 0 -> k, 'previous', r -> 'rows' -> 0 -> (k || '__cmp'), 'spec',
                                     jsonb_build_object('metrics', jsonb_build_array(k), 'dims', jsonb_build_array('day'), 'from', d0 - 27, 'to', d0));
    if g <> 'sales' then
      foreach dm in array dims loop
        r := b2c.analytics_exec(v_user, v_role, jsonb_build_object('metrics', jsonb_build_array(k), 'dims', jsonb_build_array(dm), 'from', d0 - 6, 'to', d0, 'compare', 'previous', 'limit', 50));
        cands := cands || coalesce((select jsonb_agg(jsonb_build_object('metric', k, 'dim', dm, 'dim_value', x -> 'k' -> 0, 'value', x -> k, 'previous', x -> (k || '__cmp'),
                                    'spec', jsonb_build_object('metrics', jsonb_build_array(k), 'dims', jsonb_build_array(dm), 'from', d0 - 6, 'to', d0, 'compare', 'previous')))
                                  from (select x from jsonb_array_elements(r -> 'rows') x
                                         where greatest(coalesce((x ->> k)::numeric, 0), coalesce((x ->> (k || '__cmp'))::numeric, 0)) >= 5
                                           and abs(coalesce((x ->> k)::numeric, 0) - coalesce((x ->> (k || '__cmp'))::numeric, 0))
                                               >= 0.2 * greatest(coalesce((x ->> (k || '__cmp'))::numeric, 0), 1)
                                         order by abs(coalesce((x ->> k)::numeric, 0) - coalesce((x ->> (k || '__cmp'))::numeric, 0)) desc limit 3) s), '[]');
      end loop;
    end if;
  end loop;
  return jsonb_build_object('role_group', g, 'week', jsonb_build_object('from', d0 - 6, 'to', d0), 'candidates', cands,
                            'labels', (select jsonb_object_agg(key, label) from b2c.metric_defs where key = any (keys)));
end $f$;

/* Service role: store a feed (written by Claude from the candidates) or anomalies. */
create or replace function b2c.insights_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint;
begin
  insert into b2c.insights (role_group, user_id, day, kind, items, model)
  values (p ->> 'role_group', nullif(p ->> 'user_id', '')::uuid, coalesce(nullif(p ->> 'day', '')::date, (now() at time zone 'Asia/Kolkata')::date), coalesce(p ->> 'kind', 'feed'),
          coalesce(p -> 'items', '[]'), p ->> 'model')
  returning id into v;
  return v;
end $f$;

create or replace function b2c.insights_latest() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare g text := b2c.an_group(b2c.my_role());
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(i) order by i.day desc, i.id desc), '[]') from (
            select * from b2c.insights where role_group = g and (g <> 'sales' or user_id = b2c.uid()) and day >= (now() at time zone 'Asia/Kolkata')::date - 6
             order by day desc, id desc limit 10) i);
end $f$;

/* Service role: who gets a morning feed today and has none yet (Admin and Marketing feeds are shared per role). */
create or replace function b2c.insights_due() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('role_group', g, 'user_id', uid)), '[]') from (
    select distinct on (b2c.an_group(u.role)) b2c.an_group(u.role) g, u.user_id uid from b2c.users u
     where u.is_active and u.role in ('admin', 'marketing') and not u.is_test_user
       and not exists (select 1 from b2c.insights i where i.role_group = b2c.an_group(u.role) and i.kind = 'feed' and i.day = (now() at time zone 'Asia/Kolkata')::date)
     order by b2c.an_group(u.role), u.created_at) s
$f$;

/* Nightly: hand-offs, replies, SLA breaches and enrolments yesterday against the last 28 days; more than 3 standard
   deviations off is an anomaly for the Admin (no AI needed). */
create or replace function b2c.anomalies_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare k text; r jsonb; hist numeric[]; v numeric; mu numeric; sd numeric; d0 date := (now() at time zone 'Asia/Kolkata')::date - 1; items jsonb := '[]'; v_admin uuid;
begin
  select user_id into v_admin from b2c.users where is_active and role = 'admin' and not is_test_user order by created_at limit 1;
  if v_admin is null then return '{"skipped": "no admin"}'; end if;
  foreach k in array array['handoffs', 'replies', 'sla_breaches', 'enrollments'] loop
    r := b2c.analytics_exec(v_admin, 'admin', jsonb_build_object('metrics', jsonb_build_array(k), 'dims', jsonb_build_array('day'), 'from', d0 - 28, 'to', d0));
    select coalesce((select (x ->> k)::numeric from jsonb_array_elements(r -> 'rows') x where x -> 'k' ->> 0 = d0::text), 0) into v;
    select array_agg(coalesce(n, 0)) into hist from (
      select (select (x ->> k)::numeric from jsonb_array_elements(r -> 'rows') x where x -> 'k' ->> 0 = g::date::text) n
        from generate_series(d0 - 28, d0 - 1, interval '1 day') g) s;
    select avg(h), stddev_samp(h) into mu, sd from unnest(hist) h;
    if sd > 0 and abs(v - mu) > 3 * sd and greatest(v, mu) >= 3 then
      items := items || jsonb_build_object('title', (select label from b2c.metric_defs where key = k) || case when v > mu then ' unusually high' else ' unusually low' end,
                                           'body', 'Yesterday ' || v || ' against a usual ' || round(mu, 1) || ' a day.', 'metric', k, 'change', round(v - mu, 1),
                                           'spec', jsonb_build_object('metrics', jsonb_build_array(k), 'dims', jsonb_build_array('day'), 'from', d0 - 28, 'to', d0));
    end if;
  end loop;
  if jsonb_array_length(items) > 0 then
    insert into b2c.insights (role_group, day, kind, items) values ('admin', d0 + 1, 'anomaly', items);
    perform b2c.notify_admins('alert', 'Unusual numbers yesterday', (select string_agg(x ->> 'title', ' · ') from jsonb_array_elements(items) x), '/w/analytics', null, 'anomaly:' || d0);
  end if;
  return jsonb_build_object('anomalies', jsonb_array_length(items));
end $f$;

-- ---------- standard dashboards (B13.1) ----------
create or replace function b2c.w(p_id text, p_title text, p_viz text, p_metrics text[], p_dims text[] default '{}', p_w int default 1, p_extra jsonb default '{}') returns jsonb
language sql immutable set search_path = '' as $f$
  select jsonb_build_object('id', p_id, 'title', p_title, 'viz', p_viz, 'w', p_w, 'spec', jsonb_build_object('metrics', to_jsonb(p_metrics), 'dims', to_jsonb(p_dims)) || p_extra)
$f$;

insert into b2c.dashboards (key, name, description, roles, sort, widgets, filters) values
('admin_overview', 'Admin overview', 'The whole funnel from hand-off to commission', '{admin}', 10, jsonb_build_array(
   b2c.w('a1', 'Hand-offs', 'kpi', '{handoffs}'), b2c.w('a2', 'Assigned', 'kpi', '{assigned}'), b2c.w('a3', 'Enrolments', 'kpi', '{enrollments}'),
   b2c.w('a4', 'University commission expected', 'kpi', '{uni_expected}'), b2c.w('a5', 'Counsellor commission owed', 'kpi', '{counsellor_commission}'),
   b2c.w('a6', 'Re-engaged from the pool', 'kpi', '{reengaged}'),
   b2c.w('a7', 'Funnel', 'funnel', '{assigned,contacted,counselled,applied,enrolled}', '{}', 2),
   b2c.w('a8', 'Hand-offs by day and lane', 'stacked', '{handoffs}', '{day,lane}', 2),
   b2c.w('a9', 'Enrolments by counsellor', 'bar', '{enrollments}', '{counsellor}'),
   b2c.w('a10', 'Speed', 'table', '{first_contact_min,sla_met_pct,connect_rate}', '{counsellor}'),
   b2c.w('a11', 'Leads by state', 'map', '{handoffs}', '{state}'),
   b2c.w('a12', 'Money by university', 'table', '{uni_expected,uni_realised,uni_net}', '{enrolled_university}', 2)), '{"range": "30d", "compare": "previous"}'),
('nurture', 'Nurture and re-engagement', 'Pool, journeys, replies and what came back', '{admin,marketing}', 20, jsonb_build_array(
   b2c.w('n1', 'In the pool now', 'kpi', '{pool_size}'), b2c.w('n2', 'Entered the pool', 'kpi', '{pool_entries}'), b2c.w('n3', 'Re-engaged', 'kpi', '{reengaged}'),
   b2c.w('n4', 'Re-engagement rate', 'gauge', '{reengage_rate}'),
   b2c.w('n5', 'Re-engagement by reason', 'bar', '{reengage_rate}', '{pool_reason}'),
   b2c.w('n6', 'Re-engaged by trigger', 'bar', '{reengaged}', '{reengage_trigger}'),
   b2c.w('n7', 'Pool entries by day', 'line', '{pool_entries,reengaged}', '{day}', 2),
   b2c.w('n8', 'Reply classes', 'bar', '{replies}', '{reply_class}'),
   b2c.w('n9', 'Days to re-engage by partner', 'table', '{reengage_days,reengaged}', '{partner}'),
   b2c.w('n10', 'Cost per re-engaged lead', 'kpi', '{cost_per_reengaged}')), '{"range": "30d", "compare": "previous"}'),
('campaigns_journeys', 'Campaigns and journeys', 'What nurture sends and what it gets back', '{admin,marketing}', 25, jsonb_build_array(
   b2c.w('c1', 'Marketing messages sent', 'kpi', '{marketing_sent}'), b2c.w('c2', 'Read or opened', 'kpi', '{marketing_read}'), b2c.w('c3', 'Positive replies', 'kpi', '{replies_positive}'),
   b2c.w('c4', 'Journey entries and exits', 'table', '{journey_entries,journey_exits}', '{journey_name}', 2),
   b2c.w('c5', 'Exits by reason', 'bar', '{journey_exits}', '{exit_reason}'),
   b2c.w('c6', 'Sent by template', 'table', '{marketing_sent,marketing_read}', '{template}'),
   b2c.w('c7', 'Messages by day and channel', 'stacked', '{marketing_sent}', '{day,channel}', 2)), '{"range": "30d"}'),
('deliverability', 'Deliverability and WhatsApp cost', null, '{admin,marketing}', 27, jsonb_build_array(
   b2c.w('d1', 'Delivered', 'kpi', '{marketing_delivered}'), b2c.w('d2', 'Bounces and failures', 'kpi', '{bounces}'), b2c.w('d3', 'WhatsApp cost', 'kpi', '{wa_cost}'),
   b2c.w('d4', 'Status by channel', 'stacked', '{marketing_sent}', '{channel,message_status}', 2),
   b2c.w('d5', 'WhatsApp cost by day', 'line', '{wa_cost}', '{day}', 2)), '{"range": "30d", "compare": "previous"}'),
('segments', 'Segments', 'Where the pool and the leads come from', '{marketing}', 28, jsonb_build_array(
   b2c.w('g1', 'Pool by reason', 'bar', '{pool_size}', '{pool_reason}'), b2c.w('g2', 'Pool by course', 'bar', '{pool_size}', '{course}'),
   b2c.w('g3', 'Pool by score band', 'bar', '{pool_size}', '{score_band}'), b2c.w('g4', 'Pool by state', 'map', '{pool_size}', '{state}')), '{"range": "30d"}'),
('sales_funnel', 'Sales funnel', 'Every Eduwit stage, with conversion', '{admin,marketing}', 30, jsonb_build_array(
   b2c.w('s1', 'Funnel', 'funnel', '{assigned,contacted,counselled,applied,enrolled}', '{}', 2),
   b2c.w('s2', 'Conversion', 'kpi', '{conversion}'), b2c.w('s3', 'Days to enrol', 'kpi', '{days_to_enrol}'),
   b2c.w('s4', 'Funnel by source', 'table', '{assigned,counselled,enrolled,conversion}', '{source}', 2),
   b2c.w('s5', 'Funnel by counsellor', 'table', '{assigned,contacted,counselled,applied,enrolled,conversion}', '{counsellor}', 2),
   b2c.w('s6', 'Lost by sub-stage', 'bar', '{lost}', '{sub_stage}'),
   b2c.w('s7', 'Open leads by stage', 'bar', '{open_leads}', '{stage}'),
   b2c.w('s8', 'Assigned by week (cohort)', 'cohort', '{assigned,contacted,counselled,enrolled}', '{week}', 2)), '{"range": "90d"}'),
('lead_sources', 'Lead sources', null, '{marketing}', 35, jsonb_build_array(
   b2c.w('l1', 'Hand-offs by source', 'bar', '{handoffs}', '{source}'), b2c.w('l2', 'Conversion by source', 'bar', '{conversion}', '{source}'),
   b2c.w('l3', 'By campaign', 'table', '{handoffs,assigned,enrolled}', '{campaign}', 2), b2c.w('l4', 'By hand-off reason', 'pivot', '{handoffs}', '{reason,lane}', 2)), '{"range": "30d", "compare": "previous"}'),
('fallback_value', 'Fallback value', 'What B2C recovers from leads partners lost or reported as duplicates', '{admin}', 40, jsonb_build_array(
   b2c.w('f1', 'Enrolments recovered', 'kpi', '{fallback_enrollments}'), b2c.w('f2', 'University commission recovered', 'kpi', '{fallback_commission}'),
   b2c.w('f3', 'By partner', 'table', '{fallback_enrollments,fallback_commission}', '{partner}', 2),
   b2c.w('f4', 'By source', 'bar', '{fallback_enrollments}', '{source}'),
   b2c.w('f5', 'Partner-lost leads by partner', 'bar', '{partner_lost}', '{partner}')), '{"range": "90d"}'),
('team', 'Team and capacity', null, '{admin}', 45, jsonb_build_array(
   b2c.w('t1', 'Leaderboard', 'leaderboard', '{enrollments,counsellor_commission,calls_connected}', '{counsellor}', 2),
   b2c.w('t2', 'Assignments (fairness)', 'bar', '{assignments}', '{counsellor}'),
   b2c.w('t3', 'Open leads per counsellor', 'bar', '{open_leads}', '{counsellor}'),
   b2c.w('t4', 'Assignments by trigger', 'pivot', '{assignments}', '{counsellor,assignment_trigger}', 2)), '{"range": "30d"}'),
('money', 'Money and margin', 'Eduwit''s two amounts', '{admin,marketing}', 50, jsonb_build_array(
   b2c.w('m1', 'University commission expected', 'kpi', '{uni_expected}'), b2c.w('m2', 'Realised', 'kpi', '{uni_realised}'),
   b2c.w('m3', 'Counsellor commission owed', 'kpi', '{counsellor_commission}'), b2c.w('m4', 'Settled', 'kpi', '{commission_settled}'),
   b2c.w('m5', 'By university', 'table', '{uni_expected,uni_realised,uni_gst,uni_net}', '{enrolled_university}', 2),
   b2c.w('m6', 'Counsellor commission by status', 'bar', '{counsellor_commission}', '{commission_status}'),
   b2c.w('m7', 'By month', 'stacked', '{uni_realised,counsellor_commission}', '{month}', 2),
   b2c.w('m8', 'Lines waiting for a rate', 'kpi', '{commission_needs_rate}')), '{"range": "365d"}'),
('speed', 'Speed and effort', null, '{admin}', 55, jsonb_build_array(
   b2c.w('p1', 'First-contact time (median)', 'kpi', '{first_contact_min}'), b2c.w('p2', 'SLA met', 'gauge', '{sla_met_pct}'), b2c.w('p3', 'Connect rate', 'kpi', '{connect_rate}'),
   b2c.w('p4', 'Effort by counsellor', 'table', '{calls_logged,connect_rate,calls_per_lead,attempts_before_connect,unlogged_calls}', '{counsellor}', 2),
   b2c.w('p5', 'Follow-ups', 'stacked', '{followups_on_time,followups_late,followups_missed}', '{counsellor}', 2),
   b2c.w('p6', 'Untouched 48 h', 'bar', '{untouched}', '{counsellor}'),
   b2c.w('p7', 'Messages sent', 'table', '{wa_sales_sent,email_sales_sent}', '{counsellor}')), '{"range": "30d", "compare": "previous"}'),
('quality', 'Quality', null, '{admin}', 60, jsonb_build_array(
   b2c.w('q1', 'Classification accuracy', 'gauge', '{classification_accuracy}'), b2c.w('q2', 'Missing fields', 'kpi', '{missing_fields}'),
   b2c.w('q3', 'Flagged leads', 'kpi', '{duplicate_suspects}'), b2c.w('q4', 'Cross-sell changes', 'kpi', '{cross_sell_changes}'),
   b2c.w('q5', 'Replies by class and method', 'pivot', '{classified_replies}', '{reply_class}', 2)), '{"range": "30d"}'),
('my_funnel', 'My funnel', null, '{sales}', 70, jsonb_build_array(
   b2c.w('y1', 'Assigned', 'kpi', '{assigned}'), b2c.w('y2', 'Counselled', 'kpi', '{counselled}'), b2c.w('y3', 'Enrolled', 'kpi', '{enrolled}'), b2c.w('y4', 'Conversion', 'kpi', '{conversion}'),
   b2c.w('y5', 'My funnel', 'funnel', '{assigned,contacted,counselled,applied,enrolled}', '{}', 2),
   b2c.w('y6', 'Open leads by stage', 'bar', '{open_leads}', '{stage}'), b2c.w('y7', 'Lost by sub-stage', 'bar', '{lost}', '{sub_stage}')), '{"range": "30d", "compare": "previous"}'),
('my_followups', 'My follow-ups and SLAs', null, '{sales}', 72, jsonb_build_array(
   b2c.w('z1', 'SLA met', 'gauge', '{sla_met_pct}'), b2c.w('z2', 'First-contact time', 'kpi', '{first_contact_min}'), b2c.w('z3', 'Untouched 48 h', 'kpi', '{untouched}'),
   b2c.w('z4', 'Follow-ups by day', 'stacked', '{followups_on_time,followups_late,followups_missed}', '{day}', 2)), '{"range": "30d"}'),
('my_activity', 'My activity', null, '{sales}', 74, jsonb_build_array(
   b2c.w('v1', 'Calls logged', 'kpi', '{calls_logged}'), b2c.w('v2', 'Connected', 'kpi', '{calls_connected}'), b2c.w('v3', 'Connect rate', 'kpi', '{connect_rate}'),
   b2c.w('v4', 'Calls by day and outcome', 'stacked', '{calls_logged}', '{day,call_outcome}', 2),
   b2c.w('v5', 'Messages', 'table', '{wa_sales_sent,email_sales_sent}', '{week}'), b2c.w('v6', 'Calls tapped, not logged', 'kpi', '{unlogged_calls}')), '{"range": "30d", "compare": "previous"}'),
('my_money', 'My enrolments and commission', null, '{sales}', 76, jsonb_build_array(
   b2c.w('x1', 'Enrolments', 'kpi', '{enrollments}'), b2c.w('x2', 'Commission owed', 'kpi', '{counsellor_commission}'), b2c.w('x3', 'Settled', 'kpi', '{commission_settled}'),
   b2c.w('x4', 'By status', 'bar', '{counsellor_commission}', '{commission_status}'), b2c.w('x5', 'By month', 'bar', '{counsellor_commission}', '{month}', 2)), '{"range": "365d"}'),
('my_week', 'My week', null, '{sales}', 78, jsonb_build_array(
   b2c.w('w1', 'Calls this week', 'kpi', '{calls_logged}'), b2c.w('w2', 'Counselled', 'kpi', '{counselled}'), b2c.w('w3', 'Enrolments', 'kpi', '{enrollments}'),
   b2c.w('w4', 'Calls by day', 'bar', '{calls_logged,calls_connected}', '{day}', 2)), '{"range": "7d", "compare": "previous"}')
on conflict (key) do nothing;

-- ---------- grants ----------
do $d$
declare t text;
begin
  foreach t in array array['fact_leads', 'facts_state', 'an_sources', 'metric_defs', 'dim_defs', 'analytics_drills', 'dashboards', 'dashboard_homes', 'dashboard_schedules',
                           'metric_alerts', 'alert_events', 'ai_calls', 'insights'] loop
    execute format('alter table b2c.%I enable row level security', t);
  end loop;
  grant select on b2c.metric_defs, b2c.dim_defs, b2c.dashboards, b2c.dashboard_schedules, b2c.metric_alerts, b2c.insights to authenticated;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'metric_defs' and policyname = 'staff read') then
    create policy "staff read" on b2c.metric_defs for select to authenticated using ((select b2c.is_staff()));
    create policy "staff read" on b2c.dim_defs for select to authenticated using ((select b2c.is_staff()));
    create policy "who may see" on b2c.dashboards for select to authenticated using ((select b2c.dashboard_may_see(id)));
    create policy "own" on b2c.dashboard_schedules for select to authenticated using (user_id = (select b2c.uid()));
    create policy "own" on b2c.metric_alerts for select to authenticated using (user_id = (select b2c.uid()));
    create policy "own role" on b2c.insights for select to authenticated using (role_group = (select b2c.an_group(b2c.my_role())) and (role_group <> 'sales' or user_id = (select b2c.uid())));
  end if;
end $d$;
grant execute on function b2c.analytics_run(jsonb), b2c.analytics_catalog(), b2c.analytics_drill(jsonb, text, jsonb), b2c.dashboards_list(), b2c.dashboard_get(bigint),
  b2c.dashboard_save(jsonb), b2c.dashboard_duplicate(bigint, text), b2c.dashboard_home(bigint), b2c.dashboard_publish(bigint, text[]), b2c.dashboard_archive(bigint),
  b2c.schedule_save(jsonb), b2c.schedules_mine(), b2c.alert_save(jsonb), b2c.alerts_mine(), b2c.ai_budget(text), b2c.ai_usage(integer), b2c.insights_latest(),
  b2c.insights_candidates(uuid), b2c.lead_list(jsonb), b2c.an_group(text) to authenticated;
grant execute on function b2c.analytics_run_for(uuid, jsonb), b2c.schedules_take(integer), b2c.schedule_done(bigint, text), b2c.alert_emails_take(integer),
  b2c.ai_log(jsonb), b2c.ai_budget(text), b2c.insights_candidates(uuid), b2c.insights_save(jsonb), b2c.insights_due() to service_role;
revoke execute on function b2c.facts_build(bigint[]), b2c.facts_refresh(integer), b2c.analytics_exec(uuid, text, jsonb), b2c.analytics_drill_ids(uuid, text, jsonb, text, jsonb),
  b2c.dashboard_check(jsonb), b2c.alerts_tick(), b2c.anomalies_tick(), b2c.ai_spent_today() from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
