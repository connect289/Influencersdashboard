-- Dashboards and analytics: who may read which aggregates, that the summary views count what METRICS.md says
-- (credited leads, cumulative stages, duplicates, bots, test leads, spend net of debits, revenue net of GST), that
-- creators see only their own live figures and never revenue, and that the views themselves stay closed to clients.
begin;
\ir _helpers.psql
select plan(29);

select tests.make_staff('vic', array['viewer']);
select tests.make_staff('fin', array['finance']);
select tests.make_staff('mona', array['influencer_manager']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set leaderboard_opt_in = true where id = (select creator_id from tests.people where label = 'riya');

create temporary table ids (label text primary key, id uuid);
grant select on ids to authenticated, anon, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('campaign', gen_random_uuid()), ('deal', gen_random_uuid()), ('link', gen_random_uuid());
insert into inf.campaigns (id, name, objective, budget_paise, created_by) values ((select id from ids where label = 'campaign'), 'MBA push', 'leads', 5000000, (select user_id from tests.people where label = 'mona'));
insert into inf.deals (id, creator_id, campaign_id, title, status, starts_on, deal_model, agreed_at)
values ((select id from ids where label = 'deal'), (select id from ids where label = 'riya'), (select id from ids where label = 'campaign'),
        'Riya deal', 'active', (now() at time zone 'Asia/Kolkata')::date - 30, 'hybrid', now());
insert into inf.tracking_links (id, code, creator_id, deal_id, campaign_id, destination, platform)
values ((select id from ids where label = 'link'), 'RIYA-IG-AB', (select id from ids where label = 'riya'), (select id from ids where label = 'deal'),
        (select id from ids where label = 'campaign'), 'whatsapp_witty', 'instagram');

-- Four enquiries: enrolled, qualified, a duplicate (not credited) and a test lead; five clicks and two bot clicks.
create temporary table leads (label text primary key, id bigint, attribution uuid default gen_random_uuid());
grant select on leads to authenticated, service_role;
with l as (insert into public.student_leads (whatsapp_number, student_name, stage)
           values ('910000007701', 'A', 'new'), ('910000007702', 'B', 'new'), ('910000007703', 'C', 'new'), ('910000007704', 'D', 'new')
           returning id, whatsapp_number)
insert into leads (label, id) select case right(whatsapp_number, 1) when '1' then 'enrolled' when '2' then 'qualified' when '3' then 'dup' else 'test' end, id from l;
insert into inf.lead_attributions (id, student_lead_id, creator_id, link_id, deal_id, campaign_id, code, touch, status, evidence_source,
                                   touch_at, lead_created_at, is_test, creator_stage)
select l.attribution, l.id, (select id from ids where label = 'riya'), (select id from ids where label = 'link'), (select id from ids where label = 'deal'),
       (select id from ids where label = 'campaign'), 'RIYA-IG-AB', case l.label when 'dup' then 'none' else 'first' end,
       case l.label when 'dup' then 'duplicate' else 'credited' end, 'click', now(), now(), l.label = 'test',
       case l.label when 'enrolled' then 'enrolled' when 'qualified' then 'allocated' when 'dup' then 'duplicate' else 'new' end
  from leads l;
-- The qualified lead reached Qualified, then went Lost: it still counts as qualified (stages are cumulative).
insert into inf.lead_stage_events (attribution_id, student_lead_id, creator_stage, source, idem_key, occurred_at)
select l.attribution, l.id, s.stage, 'sweep', l.label || ':' || s.stage, now()
  from leads l cross join (values ('qualified'), ('enrolled')) s(stage)
 where l.label = 'enrolled' or (l.label = 'qualified' and s.stage = 'qualified');
update inf.lead_attributions set creator_stage = 'lost' where id = (select attribution from leads where label = 'qualified');
insert into inf.link_clicks (link_id, clicked_at, is_bot)
select (select id from ids where label = 'link'), now(), g > 5 from generate_series(1, 7) g;

-- Spend: a commission line for the enrolled lead and a milestone; a TDS settlement line that must not count.
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'commission', 'direction', 'credit', 'amount_paise', 100000, 'source', 'engine', 'event_key', 'an:commission',
  'attribution_id', (select attribution from leads where label = 'enrolled'), 'tds_component', 'commission', 'due_on', (now() at time zone 'Asia/Kolkata')::date));
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'milestone', 'direction', 'credit', 'amount_paise', 500000, 'confirmed_paise', 500000, 'source', 'engine', 'event_key', 'an:milestone',
  'tds_component', 'milestone', 'due_on', (now() at time zone 'Asia/Kolkata')::date + 10));
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'type', 'tds', 'direction', 'debit',
  'amount_paise', 50000, 'confirmed_paise', 50000, 'paid_paise', 50000, 'source', 'payout', 'event_key', 'an:tds', 'due_on', (now() at time zone 'Asia/Kolkata')::date));
-- Eduwit received ₹11,800 for the enrolment (₹10,000 net of GST).
insert into inf.eduwit_commission_receipts (student_lead_id, enrollment_ref, gross_paise, gst_paise, net_paise, received_paise, received_on, status,
                                            source, source_version, reason)
select l.id, 'b2b:77', 1180000, 180000, 1000000, 1180000, (now() at time zone 'Asia/Kolkata')::date, 'received', 'manual', 'm1', 'Bank statement'
  from leads l where l.label = 'enrolled';

select tests.act_as_service();
select lives_ok($$ select inf.deal_committed_set((select id from ids where label = 'deal'), 1500000) $$, 'the runner records committed spend');
select tests.reset();
select isnt(inf.analytics_refresh(), null, 'the summary views refresh');

-- ---------------------------------------------------------------------------------------------------------------
-- Staff with analytics.read
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('vic');
create temporary table t as
  select inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'campaign_id', (select id from ids where label = 'campaign'))) -> 0 as r;
select is((select (r ->> 'leads')::int from t), 2, 'credited leads only (no duplicates, no test leads)');
select is((select (r ->> 'qualified')::int from t), 2, 'stages are cumulative: a lead lost after qualifying still counts as qualified');
select is((select (r ->> 'enrolled')::int from t), 1, 'one enrolment');
select is((select (r ->> 'attributions')::int || '/' || (r ->> 'duplicates') from t), '3/1', 'duplicates count against every decision');
select is((select (r ->> 'clicks')::int from t), 5, 'bot clicks are left out');
select is((select (r ->> 'cost_paise')::bigint from t), 600000::bigint, 'spend is earnings posted, without settlement lines');
select is((select (r ->> 'revenue_paise')::bigint from t), 1000000::bigint, 'revenue is the commission received, net of GST');
select is((inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'include_test', true, 'campaign_id', (select id from ids where label = 'campaign'))) -> 0 ->> 'leads')::int, 3,
          'test leads only on request');
select is((select jsonb_object_agg(coalesce(x ->> 'key', 'none'), (x ->> 'cost_paise')::bigint)
             from jsonb_array_elements(inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'dim', 'platform', 'campaign_id', (select id from ids where label = 'campaign')))) x),
          '{"instagram": 100000, "none": 500000}'::jsonb, 'by platform, deal-level fees stay unsplit');
select is((select (x ->> 'label') from jsonb_array_elements(inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date,
                                                                                                  'dim', 'campaign', 'campaign_id', (select id from ids where label = 'campaign')))) x where x ->> 'key' is not null),
          'MBA push', 'breakdowns carry the label');
select is((inf.analytics_spend(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'campaign_id', (select id from ids where label = 'campaign'))) -> 0 ->> 'committed_paise')::bigint, 1500000::bigint,
          'committed spend from agreed and active deals');
select is((select (x ->> 'budget_paise')::bigint from jsonb_array_elements(inf.analytics_spend(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6,
                                                                       'to', (now() at time zone 'Asia/Kolkata')::date, 'dim', 'campaign', 'campaign_id', (select id from ids where label = 'campaign')))) x), 5000000::bigint,
          'campaign spend comes with its budget');
select is((select (x ->> 'leads')::int from jsonb_array_elements(inf.analytics_creators(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'campaign_id', (select id from ids where label = 'campaign')))) x
            where x ->> 'handle' = 'riya'), 2, 'per-creator figures for the leaderboards');
select ok(inf.analytics_operations() ? 'overdue_deliverables', 'operations counts');
select is((inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'bucket', 'week',
                                                   'campaign_id', (select id from ids where label = 'campaign'))) -> -1 ->> 'key')::date,
          (now() at time zone 'Asia/Kolkata')::date - (extract(isodow from (now() at time zone 'Asia/Kolkata')::date)::int - 1), 'weekly buckets start on Monday');
select throws_ok($$ select inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'dim', 'x; drop table y')) $$,
                 '22023', null, 'only known dimensions are accepted');
select throws_ok($$ select inf.analytics_finance(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date)) $$, '42501', null,
                 'the finance dashboard also needs ledger.read');
select tests.as_person('fin');
select ok((inf.analytics_finance(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date)) ->> 'liabilities_paise')::bigint >= 600000,
          'finance sees what is owed');

-- ---------------------------------------------------------------------------------------------------------------
-- Creators and closed doors
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.analytics_totals(jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'campaign_id', (select id from ids where label = 'campaign'))) $$, '42501', null,
                 'creators cannot read programme analytics');
select throws_ok($$ select count(*) from inf.an_leads $$, '42501', null, 'the summary views are closed to clients');
create temporary table cd as
  select inf.creator_dashboard((select id from ids where label = 'riya'),
           jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'prev_from', (now() at time zone 'Asia/Kolkata')::date - 13, 'prev_to', (now() at time zone 'Asia/Kolkata')::date - 7)) as d;
select is((select (d -> 'current' ->> 'leads')::int || '/' || (d -> 'current' ->> 'enrolled') || '/' || (d -> 'current' ->> 'clicks') from cd), '2/1/5',
          'the creator sees their own live funnel');
select is((select d -> 'leaderboard' ->> 'rank' from cd), '1', 'and their leaderboard position when opted in');
select ok((select not (d::text ~ 'revenue') from cd), 'and never Eduwit''s revenue');
select is((select (d -> 'actions' ->> 'kyc')::boolean from cd), true, 'KYC incomplete shows in the action centre');
select tests.as_person('arjun');
select throws_ok($$ select inf.creator_dashboard((select id from ids where label = 'riya'),
                     jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'prev_from', (now() at time zone 'Asia/Kolkata')::date - 13, 'prev_to', (now() at time zone 'Asia/Kolkata')::date - 7)) $$,
                 '42501', null, 'nobody else''s dashboard');
select tests.as_person('mona');
select lives_ok($$ select inf.creator_dashboard((select id from ids where label = 'riya'),
                    jsonb_build_object('from', (now() at time zone 'Asia/Kolkata')::date - 6, 'to', (now() at time zone 'Asia/Kolkata')::date, 'prev_from', (now() at time zone 'Asia/Kolkata')::date - 13, 'prev_to', (now() at time zone 'Asia/Kolkata')::date - 7)) $$,
                'staff with creator.read open it from the creator 360');
select throws_ok($$ select inf.deal_committed_set((select id from ids where label = 'deal'), 1) $$, '42501', null, 'only the runner writes committed spend');

select * from finish();
rollback;
