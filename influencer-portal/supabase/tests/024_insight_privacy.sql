-- Scorecards, tiers, early campaign access, the compliance tracker, consent records, data export and deletion requests,
-- and retention: who may do what, what the facts count, how tier changes are applied and recorded, that deletion keeps
-- financial records and blanks only the creator's own message text, and that append-only tables stay append-only.
begin;
\ir _helpers.psql
select plan(62);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('sam', array['super_admin']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set approved_at = now() - interval '7 months', phone_e164 = '+919812300001'
 where id = (select creator_id from tests.people where label = 'riya');

-- The scorecard period is the current month; dates below are relative to its first day.
create temporary table per as select date_trunc('month', current_date)::date as m0,
       (date_trunc('month', current_date) + interval '1 month - 1 day')::date as m1, to_char(current_date, 'YYYY-MM') as label;
grant select on per to authenticated, service_role;
create temporary table ids (label text primary key, id uuid);
grant select, insert, update on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('deal', gen_random_uuid()), ('campaign', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at, owner_id)
values ((select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Score deal', 'active', date '2026-09-01', 'hybrid',
        now(), (select user_id from tests.people where label = 'mona'));

-- This month: three deliverables due (two on time, one late), one disclosure failure, one upheld banned claim.
insert into inf.deliverables (deal_id, title, platform, format, status, due_dates, live_at, disclosure_failed_at)
select (select id from ids where label = 'deal'), v.t, 'instagram', 'reel', v.st, jsonb_build_object('live', (m0 + v.due)::timestamptz + interval '18 hours'),
       (m0 + v.live)::timestamptz + interval '10 hours', case when v.fail then (m0 + v.live)::timestamptz + interval '12 hours' end
  from per, (values ('Reel A', 'live_verified', 4, 3, false), ('Reel B', 'live_verified', 11, 11, true), ('Reel C', 'live', 19, 21, false))
       v(t, st, due, live, fail);
insert into inf.compliance_checks (deliverable_id, kind, result, passed, overridden)
select x.id, 'banned_claims', '{}'::jsonb, x.title <> 'Reel C', false from inf.deliverables x where x.deal_id = (select id from ids where label = 'deal');
-- Leads: four credited (two qualified, one enrolled), one duplicate, one test lead.
with l as (insert into public.student_leads (whatsapp_number, student_name, stage)
           select '91000000880' || g, 'Lead ' || g, 'new' from generate_series(1, 6) g returning id, whatsapp_number)
insert into inf.lead_attributions (student_lead_id, creator_id, code, touch, status, evidence_source, touch_at, lead_created_at, creator_stage, is_test)
select l.id, (select id from ids where label = 'riya'), 'RIYA-SC', case when right(l.whatsapp_number, 1) = '5' then 'none' else 'first' end,
       case when right(l.whatsapp_number, 1) = '5' then 'duplicate' else 'credited' end, 'click',
       (select m0 from per)::timestamptz + interval '9 days 10 hours', (select m0 from per)::timestamptz + interval '9 days 10 hours',
       case right(l.whatsapp_number, 1) when '1' then 'enrolled' when '2' then 'qualified' else 'new' end, right(l.whatsapp_number, 1) = '6'
  from l;
-- Spend: a ₹1,000 milestone posted now (this month).
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'milestone', 'direction', 'credit', 'amount_paise', 100000, 'source', 'engine', 'event_key', 'sc:m1', 'tds_component', 'milestone',
  'due_on', current_date + 60));

-- ---------------------------------------------------------------------------------------------------------------
-- Tiers
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.tier_save('{"name":"Bronze","rank":1}') $$, '42501', null, 'tiers need tier.manage');
select tests.as_person('sam');
select throws_ok($$ select inf.tier_save('{"name":"Odd","rank":9,"entry_rules":{"min_followers":10}}') $$, '22023', null, 'unknown rule keys are refused');
select throws_ok($$ select inf.tier_save('{"name":"Odd","rank":9,"benefits":{"payout_cycle":"daily"}}') $$, '22023', null, 'invalid benefits are refused');
insert into ids select 'bronze', inf.tier_save('{"name":"Bronze","rank":1}');
insert into ids select 'silver', inf.tier_save('{"name":"Silver","rank":2,"entry_rules":{"min_score":60},"benefits":{"early_access_days":3,"commission_uplift_pct":5}}');
insert into ids select 'gold', inf.tier_save('{"name":"Gold","rank":3,"entry_rules":{"min_score":85}}');
select throws_ok($$ select inf.tier_save('{"name":"Clash","rank":2}') $$, '22023', null, 'two active tiers cannot share a rank');
select tests.as_person('riya');
select is(jsonb_array_length(inf.tiers_list()) >= 3, true, 'creators read the active tiers');
select is((select count(*) from jsonb_array_elements(inf.tiers_list()) e where e ->> 'creators' is not null), 0::bigint,
          'creators do not see how many creators are in each tier');

-- ---------------------------------------------------------------------------------------------------------------
-- Scorecard facts and saving
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok($$ select inf.scorecard_facts((select id from ids where label = 'riya'), (select m0 from per), (select m1 from per)) $$, '42501', null,
                 'creators do not read scorecard facts');
select tests.as_person('mona');
create temporary table f as select inf.scorecard_facts((select id from ids where label = 'riya'), (select m0 from per), (select m1 from per)) as v;
grant select on f to service_role;
select is((select (v ->> 'due') || '/' || (v ->> 'on_time') from f), '3/2', 'three due, two live on time');
select is((select (v ->> 'disclosure_misses') || '/' || (v ->> 'claim_violations') || '/' || (v ->> 'checked') from f), '1/1/3', 'compliance misses');
select is((select (v ->> 'leads') || '/' || (v ->> 'qualified') || '/' || (v ->> 'enrolled') || '/' || (v ->> 'duplicates') from f), '4/2/1/1',
          'credited leads without test leads, cumulative stages, duplicates apart');
select is((select (v ->> 'cost_paise')::bigint from f), 100000::bigint, 'spend accrued in the period');
select is((select (v ->> 'months_active')::int from f), 7, 'months since approval');

select throws_ok($$ select inf.scorecard_save(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'kind', 'monthly',
                     'period', (select label from per), 'period_from', (select m0 from per), 'period_to', (select m1 from per), 'facts', '{}'::jsonb, 'scores', '{}'::jsonb,
                     'composite', 70, 'weights', '{}'::jsonb)) $$, '42501', null, 'only the job saves monthly scorecards');
select tests.act_as_service();
insert into ids select 'card', inf.scorecard_save(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'kind', 'monthly',
  'period', (select label from per), 'period_from', (select m0 from per), 'period_to', (select m1 from per), 'facts', (select v from f), 'scores', '{"compliance": 50}'::jsonb,
  'composite', 70, 'weights', '{}'::jsonb, 'tier_after', (select id from ids where label = 'silver'), 'change', 'up', 'months_below', 0));
select is(inf.scorecard_save(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'kind', 'monthly',
  'period', (select label from per), 'period_from', (select m0 from per), 'period_to', (select m1 from per), 'facts', '{}'::jsonb, 'scores', '{}'::jsonb,
  'composite', 10, 'weights', '{}'::jsonb, 'tier_after', (select id from ids where label = 'bronze'), 'change', 'down')),
  (select id from ids where label = 'card'), 'one monthly card per creator and month (a rerun changes nothing)');
select tests.reset();
select is((select tier_id from inf.creators where id = (select id from ids where label = 'riya')), (select id from ids where label = 'silver'),
          'the tier decision is applied');
select is((select reason from inf.tier_history where creator_id = (select id from ids where label = 'riya')), 'eligible', 'and recorded');
select is((select n.title from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'tier.changed'),
          'You reached Silver', 'the creator is told');
select throws_ok($$ update inf.scorecards set composite = 99 $$, '42501', null, 'scorecards are append-only');

select tests.as_person('mona');
select lives_ok($$ select inf.scorecard_save(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'kind', 'on_demand',
                     'period', (select label from per), 'period_from', (select m0 from per), 'period_to', current_date, 'facts', '{}'::jsonb, 'scores', '{}'::jsonb,
                     'composite', 20, 'weights', '{}'::jsonb, 'tier_after', (select id from ids where label = 'bronze'), 'change', 'down')) $$,
                'a manager runs a card on demand');
select tests.reset();
select is((select tier_id from inf.creators where id = (select id from ids where label = 'riya')), (select id from ids where label = 'silver'),
          'an on-demand card never changes the tier');
select tests.as_person('mona');
select is(jsonb_array_length(inf.creator_scorecards((select id from ids where label = 'riya')) -> 'cards'), 2, 'staff see the creator''s cards');
select is(inf.programme_scorecards((select label from per)) -> 'items' -> 0 ->> 'tier', 'Silver', 'and the programme list for a month');
select is((inf.programme_scorecards((select label from per), 0, 1) ->> 'total')::int >= 1, true, 'which is paginated with a total');
select throws_ok($$ select inf.tier_set_manual((select id from ids where label = 'riya'), current_date + 30, 'VIP', (select id from ids where label = 'gold')) $$,
                 '42501', null, 'manual tiers need tier.manage');

select tests.as_person('riya');
select is(inf.creator_scorecards((select id from ids where label = 'riya')), null, 'creators do not read the scorecards');
select is((inf.tier_status((select id from ids where label = 'riya')) ->> 'tier_id')::uuid, (select id from ids where label = 'silver'),
          'the creator sees their tier');
select ok(not (inf.tier_status((select id from ids where label = 'riya')) ? 'scores'), 'but never the sub-scores');
select tests.as_person('arjun');
select throws_ok($$ select inf.tier_status((select id from ids where label = 'riya')) $$, '42501', null, 'nor anyone else''s');

select tests.as_person('sam');
select throws_ok($$ select inf.tier_set_manual((select id from ids where label = 'riya'), current_date + 30, 'x', (select id from ids where label = 'gold')) $$,
                 '22023', null, 'a manual tier needs a reason');
select lives_ok($$ select inf.tier_set_manual((select id from ids where label = 'riya'), current_date + 30, 'Flagship partner this quarter',
                     (select id from ids where label = 'gold')) $$, 'the Super Admin sets a manual tier');
select tests.reset();
select is((select reason || ':' || note from inf.tier_history where creator_id = (select id from ids where label = 'riya') order by id desc limit 1),
          'manual:Flagship partner this quarter', 'with its reason in the history');

-- ---------------------------------------------------------------------------------------------------------------
-- Early campaign access (Gold has none, Silver 3 days: the longest is 3)
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('sam');
select inf.tier_set_manual((select id from ids where label = 'riya'), current_date + 30, 'Back to Silver', (select id from ids where label = 'silver'));
select tests.reset();
insert into inf.campaigns (id, name, objective, status, visibility, created_by)
values ((select id from ids where label = 'campaign'), 'Early access drive', 'leads', 'open', 'open', (select user_id from tests.people where label = 'mona'));
select tests.as_person('arjun');
select is((select count(*)::int from jsonb_array_elements(inf.marketplace(null, true)) x where x ->> 'name' = 'Early access drive'), 0,
          'a creator without a tier waits for a newly opened campaign');
select tests.as_person('riya');
select is((select count(*)::int from jsonb_array_elements(inf.marketplace(null, true)) x where x ->> 'name' = 'Early access drive'), 1,
          'a Silver creator sees it at once');
select tests.reset();
update inf.campaigns set opened_at = now() - interval '4 days' where id = (select id from ids where label = 'campaign');
select tests.as_person('arjun');
select is((select count(*)::int from jsonb_array_elements(inf.marketplace(null, true)) x where x ->> 'name' = 'Early access drive'), 1,
          'everyone sees it after the early-access days');

-- ---------------------------------------------------------------------------------------------------------------
-- Compliance tracker
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select is(jsonb_array_length(inf.compliance_facts((select id from ids where label = 'riya'))), 3, 'the creator sees their obligations');
select tests.as_person('arjun');
select throws_ok($$ select inf.compliance_facts((select id from ids where label = 'riya')) $$, '42501', null, 'nobody else does');

-- ---------------------------------------------------------------------------------------------------------------
-- Consent records
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select inf.notification_preference_set('deliverable.due', 'whatsapp', false);
select inf.digest_preference_set('off', 'email');
select is((select string_agg(x ->> 'purpose' || ':' || (x ->> 'granted'), ',' order by x ->> 'purpose') from jsonb_array_elements(inf.my_consents()) x),
          'deliverable.due:false,digest:false', 'every change to what the creator receives is recorded');
select throws_ok($$ select count(*) from inf.communication_consents $$, '42501', null, 'consent rows are read through my_consents only');
select tests.reset();
select throws_ok($$ delete from inf.communication_consents $$, '42501', null, 'and are append-only');

-- ---------------------------------------------------------------------------------------------------------------
-- Data export
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
insert into ids select 'export', inf.privacy_request_create('export');
select throws_ok($$ select inf.privacy_request_create('export') $$, '22023', null, 'one export a day');
select is((select x ->> 'file_ready' from jsonb_array_elements(inf.my_privacy_requests()) x), 'true', 'the export is ready at once');
select ok(inf.privacy_export_allowed((select id from ids where label = 'export')), 'the creator may download it');
select tests.reset();
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id
            where p.label = 'riya' and n.event = 'privacy.export_ready'), 1, 'and is told');
select tests.act_as_service();
create temporary table ex as select inf.privacy_export_data((select id from ids where label = 'export')) as v;
select ok((select v ? 'profile' and v ? 'earnings' and v ? 'leads' and not (v -> 'profile' ? 'internal_notes') from ex), 'the export covers the creator''s data');
select ok((select v::text !~ '91000000880' from ex), 'and never a student''s phone number');
select tests.as_person('arjun');
select ok(not inf.privacy_export_allowed((select id from ids where label = 'export')), 'nobody else may download it');

-- ---------------------------------------------------------------------------------------------------------------
-- Deletion
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
insert into ids select 'deletion', inf.privacy_request_create('deletion', 'Leaving the programme');
select inf.thread_post('support', (select id from ids where label = 'riya'), 'Please delete my data.');
select throws_ok($$ select inf.privacy_request_create('deletion') $$, '22023', null, 'one open deletion request');
select tests.reset();
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'sam' and n.event = 'staff.privacy_request'), 1,
          'staff who handle privacy are told');
select tests.as_person('mona');
select is(inf.privacy_requests_list(), '[]'::jsonb, 'requests need privacy.manage');
select tests.as_person('sam');
select throws_ok($$ select inf.privacy_deletion_decide((select id from ids where label = 'deletion'), true, 'Verified by email', current_date + 2920) $$,
                 '22023', null, 'not while a deal is open');
select tests.reset();
update inf.deals set status = 'completed' where id = (select id from ids where label = 'deal');
select tests.as_person('sam');
select is((inf.privacy_deletion_facts((select id from ids where label = 'deletion')) ->> 'last_record_on')::date, (now() at time zone 'Asia/Kolkata')::date, 'the last financial record');
select lives_ok($$ select inf.privacy_deletion_decide((select id from ids where label = 'deletion'), true, 'Verified by email', current_date + 2922) $$,
                'the request is carried out');
select tests.reset();
select is((select display_name || ':' || coalesce(email, '-') || ':' || status from inf.creators where id = (select id from ids where label = 'riya')),
          'Deleted creator:-:archived', 'the profile is erased');
select is((select m.body from inf.messages m join inf.threads t on t.id = m.thread_id where t.creator_id = (select id from ids where label = 'riya')
            and m.author_side = 'creator' limit 1), '[removed at the creator''s request]', 'the creator''s message text is blanked');
select is((select count(*)::int from inf.ledger_entries where creator_id = (select id from ids where label = 'riya')), 1, 'financial records are kept');
select is((select count(*)::int from inf.user_sessions s join tests.people p on p.user_id = s.user_id where p.label = 'riya' and s.revoked_at is null), 0,
          'every session ends');
select throws_ok($$ update inf.messages set body = 'x' $$, '42501', null, 'messages stay append-only outside an erasure');

-- ---------------------------------------------------------------------------------------------------------------
-- Retention
-- ---------------------------------------------------------------------------------------------------------------
insert into inf.creator_kyc (creator_id, status) values ((select id from ids where label = 'riya'), 'verified') on conflict do nothing;
update inf.privacy_requests set purge_on = current_date - 1 where id = (select id from ids where label = 'deletion');
insert into inf.sign_in_log (at, email, portal, method, outcome) values (now() - interval '3 years', 'old@example.test', 'creator', 'email_otp', 'ok');
insert into inf.audit_log (at, entity_type, action) values (now() - interval '9 years', 'test', 'insert'), (now(), 'test', 'insert');
create temporary table rr as select inf.retention_run() as v;
select is((select (v ->> 'kyc_purged')::int from rr), 1, 'KYC kept for a deleted creator goes when the retention period ends');
select is((select status from inf.privacy_requests where id = (select id from ids where label = 'deletion')), 'purged', 'and the request says so');
select is((select count(*)::int from inf.audit_log where entity_type = 'test'), 1, 'audit entries older than the retention period are removed');
select is((select count(*)::int from inf.sign_in_log where email = 'old@example.test'), 0, 'and old sign-in records');
select throws_ok($$ delete from inf.audit_log where entity_type = 'test' $$, '42501', null, 'the audit log stays append-only otherwise');

select * from finish();
rollback;
