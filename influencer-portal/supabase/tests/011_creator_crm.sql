-- Creator CRM: staff create/edit, pipeline moves, list filters, outreach and follow-ups, tasks, saved views, bulk
-- actions, CSV import de-duplication, dormancy. Role checks for each write.
begin;
\ir _helpers.psql
select plan(36);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('fin', array['finance']);
select tests.make_staff('rev', array['content_reviewer']);
select tests.make_staff('view', array['viewer']);
select tests.make_creator('riya');

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated;
insert into ids select 'riya', creator_id from tests.people where label = 'riya';
insert into ids select 'mona_user', user_id from tests.people where label = 'mona';
insert into ids select 'rev_user', user_id from tests.people where label = 'rev';

-- Create and edit.
select tests.as_person('mona');
insert into ids select 'kabir', inf.creator_save('{"display_name":"Kabir Codes","handle":"Kabir.Codes","email":"Kabir@Example.test","niches":["Coding","coding"],"tags":["Tech"],"city":"Pune"}');
select is((select handle from inf.creators where id = (select id from ids where label = 'kabir')), 'kabir.codes', 'handle is lower-cased');
select is((select niches from inf.creators where id = (select id from ids where label = 'kabir')), array['coding'], 'niches de-duplicated');
select is((select owner_id from inf.creators where id = (select id from ids where label = 'kabir')), (select id from ids where label = 'mona_user'), 'creator owner defaults to the creating staff member');
select throws_ok($$ select inf.creator_save('{"display_name":"Dup","handle":"kabir.codes"}') $$, '23505', null, 'handles are unique');
select tests.as_person('fin');
select throws_ok($$ select inf.creator_save('{"display_name":"X","handle":"xxx"}') $$, '42501', null, 'finance cannot create creators');
select tests.as_person('view');
select throws_ok($$ select inf.creator_list('{}') $$, '42501', null, 'viewer cannot list creators');

-- Pipeline.
select tests.as_person('mona');
select throws_ok($$ select inf.creator_set_stage((select id from ids where label = 'kabir'), 'active') $$, '22023', null, 'a prospect without an account cannot become active');
select lives_ok($$ select inf.creator_set_stage((select id from ids where label = 'kabir'), 'negotiating') $$, 'moves to negotiating');
select lives_ok($$ select inf.creator_set_stage((select id from ids where label = 'riya'), 'paused') $$, 'active creator paused');
select is((select status from inf.creators where id = (select id from ids where label = 'riya')), 'paused', 'pausing the stage pauses the account');
select inf.creator_set_stage((select id from ids where label = 'riya'), 'active');
select is((select status from inf.creators where id = (select id from ids where label = 'riya')), 'active', 'and back to active');

-- List filters, sorting and paging.
select inf.platform_save((select id from ids where label = 'riya'), '{"platform":"instagram","url":"https://instagram.com/riya","handle":"riya","followers":250000}');
select inf.platform_save((select id from ids where label = 'kabir'), '{"platform":"youtube","url":"https://youtube.com/@kabir","handle":"kabir","followers":40000}');
select is((inf.creator_list('{}') ->> 'total')::int, 2, 'list returns both');
select is((inf.creator_list('{"q":"kab"}') -> 'rows' -> 0 ->> 'handle'), 'kabir.codes', 'search by name/handle');
select is((inf.creator_list('{"q":"%"}') ->> 'total')::int, 0, 'search escapes LIKE wildcards');
select is((inf.creator_list('{"followers_min":100000}') ->> 'total')::int, 1, 'followers filter sums platforms');
select is((inf.creator_list('{"platform":"youtube"}') -> 'rows' -> 0 ->> 'handle'), 'kabir.codes', 'platform filter');
select is((inf.creator_list('{"sort":"followers","dir":"desc"}') -> 'rows' -> 0 ->> 'handle'), 'riya', 'sort by followers');
select is(jsonb_array_length(inf.creator_list('{"page_size":1,"page":2}') -> 'rows'), 1, 'paging');
select is((select n from inf.creator_stage_counts('{"stage":["active"]}') where stage = 'negotiating')::int, 1, 'stage counts ignore the stage filter');

-- Outreach and follow-ups.
insert into ids select 'act', inf.outreach_log((select id from ids where label = 'kabir'), 'instagram_dm', 'outbound', 'follow_up', 'Liked the MBA idea', now() - interval '2 hours');
select is((select count(*)::int from inf.follow_ups_due('all')), 1, 'overdue follow-up appears in the widget');
select is((inf.creator_list('{"follow_up":"overdue"}') ->> 'total')::int, 1, 'and in the overdue filter');
select inf.outreach_log((select id from ids where label = 'kabir'), 'call', 'outbound', 'interested', 'Call done', null);
select is((select count(*)::int from inf.follow_ups_due('all')), 0, 'new outreach closes earlier follow-ups');
select throws_ok($$ select inf.outreach_log((select id from ids where label = 'kabir'), 'call', 'outbound', 'info', null, now() - interval '3 days') $$, '22023', null, 'follow-up dates cannot be in the past');
select tests.as_person('rev');
select throws_ok($$ select inf.outreach_log((select id from ids where label = 'kabir'), 'call', 'outbound', 'info', null, null) $$, '42501', null, 'content reviewer cannot log outreach');

-- Tasks: the assignee can complete but not create; others can't see it.
select tests.as_person('mona');
insert into ids select 'task', inf.task_save(jsonb_build_object('title', 'Send Kabir the brief', 'assignee_id', (select id from ids where label = 'rev_user'), 'related_type', 'creator', 'related_id', (select id from ids where label = 'kabir')));
select tests.as_person('rev');
select is((select count(*)::int from inf.tasks), 1, 'assignee sees their task');
select is((select count(*)::int from inf.my_notifications()), 1, 'and was notified');
select lives_ok($$ select inf.task_set_status((select id from ids where label = 'task'), 'done') $$, 'assignee completes it');
select throws_ok($$ select inf.task_save('{"title":"Mine"}') $$, '42501', null, 'but cannot create tasks');
select tests.as_person('fin');
select is((select count(*)::int from inf.tasks), 0, 'others do not see it');

-- Saved views: private unless shared.
select tests.as_person('mona');
select inf.saved_view_save('Big Instagram', '{"platform":"instagram","followers_min":100000}', false);
select tests.as_person('fin');
select is((select count(*)::int from inf.saved_views), 0, 'private view is hidden from others');

-- Bulk.
select tests.as_person('mona');
select is(inf.creators_bulk(array[(select id from ids where label = 'kabir'), (select id from ids where label = 'riya')], 'tag_add', 'Q4'), 2, 'bulk tag');
select is(inf.creators_bulk(array[(select id from ids where label = 'kabir'), (select id from ids where label = 'riya')], 'stage', 'active'), 1, 'bulk stage skips creators who cannot move');

-- Import: duplicates against the database and within the file.
select is((inf.creator_import('p.csv', '[
  {"row":2,"display_name":"Neha","handle":"neha.talks","email":"neha@x.test"},
  {"row":3,"display_name":"Kabir again","handle":"kabir_2","email":"kabir@example.test"},
  {"row":4,"display_name":"Neha twin","handle":"neha.twin","email":"NEHA@x.test"},
  {"row":5,"display_name":"Riya IG","handle":"riya_ig","platform":"instagram","platform_handle":"riya","platform_url":"https://instagram.com/riya"}
]'::jsonb, '[{"row":6,"result":"error","reason":"handle"}]'::jsonb, false) ->> 'created')::int, 1, 'import creates only new prospects');
select is((select duplicates from inf.creator_imports order by created_at desc limit 1), 3, 'existing email, in-file email and platform handle are duplicates');

-- Dormancy.
select tests.reset();
update inf.creators set last_activity_at = now() - interval '100 days' where id = (select id from ids where label = 'riya');
select inf.creators_flag_dormant();
select is((select pipeline_stage from inf.creators where id = (select id from ids where label = 'riya')), 'dormant', 'inactive active creator flagged dormant');
select tests.as_person('riya');
select inf.creator_profile_update((select id from ids where label = 'riya'), '{"bio":"Back again"}');
select tests.reset();
select is((select pipeline_stage from inf.creators where id = (select id from ids where label = 'riya')), 'active', 'creator activity moves a dormant creator back to active');

select * from finish();
rollback;
