-- Dashboard performance check (spec 12: under 2 seconds at p95 with 100k leads and 1,000 creators).
-- LOCAL ONLY. Everything runs in one transaction that is rolled back, so the database is left as it was.
-- Usage: psql "postgresql://postgres:postgres@127.0.0.1:54422/postgres" -f scripts/perf/analytics.sql
\set ON_ERROR_STOP on
begin;
\ir ../../supabase/tests/_helpers.psql
select setseed(0.42);

-- 1,000 creators, one deal each across 20 campaigns, three links each.
create temp table pc as
  select gen_random_uuid() as id, g as n from generate_series(1, 1000) g;
insert into inf.creators (id, display_name, handle, email, status, leaderboard_opt_in)
  select id, 'Perf Creator ' || n, 'perf' || n, 'perf' || n || '@example.test', 'active', random() < 0.3 from pc;
select tests.make_staff('perfstaff', array['finance']) \gset
create temp table pcmp as select gen_random_uuid() as id, g as n from generate_series(1, 20) g;
insert into inf.campaigns (id, name, objective, budget_paise, created_by)
  select id, 'Perf campaign ' || n, 'leads', 50000000, (select user_id from tests.people where label = 'perfstaff') from pcmp;
create temp table pd as
  select gen_random_uuid() as id, pc.id as creator_id, (select id from pcmp where n = 1 + (pc.n % 20)) as campaign_id, pc.n from pc;
insert into inf.deals (id, creator_id, campaign_id, title, status, starts_on, deal_model, agreed_at, committed_paise)
  select id, creator_id, campaign_id, 'Perf deal ' || n, 'active', current_date - 365,
         (array['hybrid', 'commission_only', 'fixed_only'])[1 + n % 3], now(), 1500000 from pd;
create temp table pl as
  select gen_random_uuid() as id, pd.creator_id, pd.id as deal_id, pd.campaign_id, k, pd.n
    from pd cross join generate_series(1, 3) k;
insert into inf.tracking_links (id, code, creator_id, deal_id, campaign_id, destination, platform)
  select id, 'PERF-' || n || '-' || k, creator_id, deal_id, campaign_id, 'whatsapp_witty',
         (array['instagram', 'youtube', 'facebook'])[k] from pl;

-- 100,000 attributions over a year (10% duplicates), with stage events, 400,000 clicks, 60,000 ledger lines and
-- 5,000 receipts.
create temp table plx as select array_agg(id order by n, k) as ids from pl;
create temp table pa as
  select gen_random_uuid() as id, g as lead_id, l.id as link_id, l.creator_id, l.deal_id, l.campaign_id,
         now() - (random() * 365 || ' days')::interval as at, random() as r
    from generate_series(1, 100000) g
    join pl l on l.id = (select ids[1 + (g::bigint * 7919) % 3000] from plx);
insert into inf.lead_attributions (id, student_lead_id, creator_id, link_id, deal_id, campaign_id, code, touch, status, evidence_source,
                                   touch_at, lead_created_at, creator_stage)
  select id, 900000000 + lead_id, creator_id, link_id, deal_id, campaign_id, 'PERF', case when r < 0.1 then 'none' else 'first' end,
         case when r < 0.1 then 'duplicate' else 'credited' end, 'click', at, at,
         case when r < 0.1 then 'duplicate' when r < 0.2 then 'junk' when r < 0.55 then 'new' when r < 0.75 then 'qualified'
              when r < 0.9 then 'applied' else 'enrolled' end
    from pa;
insert into inf.lead_stage_events (attribution_id, student_lead_id, creator_stage, source, idem_key, occurred_at)
  select a.id, 900000000 + a.lead_id, s.stage, 'sweep', 'perf:' || a.id || ':' || s.stage, a.at
    from pa a cross join (values ('qualified', 0.55), ('applied', 0.75), ('enrolled', 0.9)) s(stage, min_r)
   where a.r >= s.min_r;
insert into inf.link_clicks (link_id, clicked_at, is_bot)
  select (select ids[1 + (g::bigint * 104729) % 3000] from plx), now() - (random() * 365 || ' days')::interval, random() < 0.05
    from generate_series(1, 400000) g;
insert into inf.ledger_entries (creator_id, deal_id, type, direction, amount_paise, confirmed_paise, status, source, event_key, period, due_on, attribution_id, tds_component)
  select a.creator_id, a.deal_id, 'commission', 'credit', 100000, 100000, 'payable', 'engine', 'perf:' || a.id, to_char(a.at, 'YYYY-MM'),
         a.at::date, a.id, 'commission'
    from pa a where a.r >= 0.4 limit 60000;
insert into inf.eduwit_commission_receipts (student_lead_id, enrollment_ref, gross_paise, net_paise, received_paise, received_on, status, source, source_version)
  select 900000000 + a.lead_id, 'b2b:' || (800000000 + a.lead_id), 1180000, 1000000, 1180000, a.at::date, 'received', 'b2b', 'perf'
    from pa a where a.r >= 0.9 limit 5000;
analyze inf.creators, inf.deals, inf.tracking_links, inf.lead_attributions, inf.lead_stage_events, inf.link_clicks,
        inf.ledger_entries, inf.eduwit_commission_receipts;
grant select on pc to authenticated;

\echo
\echo == Refresh of the summary views
\timing on
select inf.analytics_refresh() is not null as refreshed;
\timing off

select tests.as_person('perfstaff');
create temp table runs (name text, ms numeric);
grant all on runs to authenticated;
do $$
declare
  t0 timestamptz; i int;
  r jsonb := jsonb_build_object('from', current_date - 89, 'to', current_date);
  q text;
  checks text[][] := array[
    array['totals (all)', format('select inf.analytics_totals(%L)', r)],
    array['totals (previous period)', format('select inf.analytics_totals(%L)', jsonb_build_object('from', current_date - 179, 'to', current_date - 90))],
    array['totals (series)', format('select inf.analytics_totals(%L)', r || '{"bucket": "week"}')],
    array['totals (by creator)', format('select inf.analytics_totals(%L)', r || '{"dim": "creator"}')],
    array['totals (by platform)', format('select inf.analytics_totals(%L)', r || '{"dim": "platform"}')],
    array['spend (by campaign)', format('select inf.analytics_spend(%L)', r || '{"dim": "campaign"}')],
    array['creators (leaderboards)', format('select inf.analytics_creators(%L)', r)],
    array['health', format('select inf.analytics_health(%L)', r || jsonb_build_object('prev_from', current_date - 179, 'prev_to', current_date - 90))],
    array['operations', 'select inf.analytics_operations()'],
    array['finance', format('select inf.analytics_finance(%L)', r)],
    array['creator home (live)', format('select inf.creator_dashboard(%L, %L)', (select id from pc where n = 7),
          r || jsonb_build_object('prev_from', current_date - 179, 'prev_to', current_date - 90, 'bucket', 'week'))]];
begin
  for k in 1 .. array_length(checks, 1) loop
    for i in 1 .. 10 loop
      t0 := clock_timestamp();
      execute checks[k][2];
      insert into runs values (checks[k][1], extract(epoch from clock_timestamp() - t0) * 1000);
    end loop;
  end loop;
end $$;
select tests.reset();
\echo
\echo == Dashboard queries, 10 runs each (ms)
select name, round((percentile_cont(0.5) within group (order by ms))::numeric, 1) as p50,
       round((percentile_cont(0.95) within group (order by ms))::numeric, 1) as p95, round(max(ms), 1) as max
  from runs group by name order by max desc;
select (select count(*) from inf.lead_attributions where code = 'PERF') as attributions,
       (select count(*) from inf.creators where handle like 'perf%') as creators,
       (select max(ms) from runs) < 2000 as all_under_2s;
rollback;
