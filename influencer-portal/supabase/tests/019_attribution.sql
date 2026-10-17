-- Attribution: links (who may create, codes unique forever), the redirect's service-role functions, the sweep's
-- gather (evidence from referral codes, touchpoints, access codes and clicks; self-referral) and apply (attributions,
-- history, stage events, the masked creator feed), masking proofs, overrides, fraud review and who sees what.
begin;
\ir _helpers.psql
select plan(76);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('asha', array['super_admin']);
select tests.make_staff('fin', array['finance']);
select tests.make_staff('cara', array['content_reviewer']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set phone_e164 = '+919811100022' where handle = 'arjun';

create temporary table ids (label text primary key, id uuid);
grant select, insert, update on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Riya deal', 'agreed', current_date, 'fixed_only', now();
insert into ids values ('arjun_deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'arjun_deal'), (select id from ids where label = 'arjun'), 'Arjun deal', 'active', current_date, 'fixed_only', now();
create temporary table leads (label text primary key, id bigint);
grant select, insert on leads to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Masking and references
-- ---------------------------------------------------------------------------------------------------------------
select is(inf.mask_phone('919812345621'), '98XXXXXX21', 'phone: national number, first two and last two digits');
select is(inf.mask_phone('+91 98123 45621'), '98XXXXXX21', 'phone: formatting ignored');
select is(inf.mask_phone('09812345621'), '98XXXXXX21', 'phone: trunk prefix removed');
select is(inf.mask_phone('15551234567'), 'XXXXXXXXXX', 'phone: anything else fully masked');
select is(inf.mask_phone(null), 'XXXXXXXXXX', 'phone: missing is masked');
select is(inf.mask_email('riya.sharma@gmail.com', array['gmail.com']), 'r****@gmail.com', 'email: public mailbox domain kept');
select is(inf.mask_email('riya@iitd.ac.in', array['gmail.com']), 'r****@****.in', 'email: other domains hidden');
select is(inf.mask_email('nope', array['gmail.com']), null, 'email: invalid is dropped');
select matches(inf.lead_ref(42), '^L-[0-9A-F]{10}$', 'lead reference format');
select is(inf.lead_ref(42), inf.lead_ref(42), 'lead reference is stable');
select isnt(inf.lead_ref(42), inf.lead_ref(43), 'and differs per lead');

-- ---------------------------------------------------------------------------------------------------------------
-- Per-campaign attribution settings
-- ---------------------------------------------------------------------------------------------------------------
insert into ids values ('camp', gen_random_uuid());
insert into inf.campaigns (id, name, objective, created_by)
select (select id from ids where label = 'camp'), 'Diwali push', 'leads', (select user_id from tests.people where label = 'mona');
select tests.as_person('fin');
select throws_ok($$ select inf.campaign_attribution_save((select id from ids where label = 'camp'), 'last_touch', '') $$, '42501', null,
  'finance does not change campaign tracking');
select tests.as_person('mona');
select throws_ok($$ select inf.campaign_attribution_save((select id from ids where label = 'camp'), '', 'Hello, tell me more please') $$, '23514', null,
  'a campaign message must keep the creator code');
select lives_ok($$ select inf.campaign_attribution_save((select id from ids where label = 'camp'), 'last_touch', 'Hi Eduwit, {creator_name} sent me. Code {code}') $$,
  'a manager sets the campaign model and message');

-- ---------------------------------------------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select lives_ok($$ insert into ids select 'link', inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
  'deal_id', (select id from ids where label = 'deal'), 'code', 'riya-ig-aa', 'destination', 'whatsapp_witty', 'platform', 'instagram')) $$,
  'a creator makes a link for her agreed deal');
select is((select code from inf.tracking_links where id = (select id from ids where label = 'link')), 'RIYA-IG-AA', 'codes are stored uppercase');
select throws_ok($$ select inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'code', 'RIYA-X-11', 'destination', 'whatsapp_witty')) $$,
  '22023', 'links need an agreed deal', 'creators need a deal');
select throws_ok($$ select inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
  'deal_id', (select id from ids where label = 'deal'), 'code', 'Riya-Ig-Aa', 'destination', 'whatsapp_witty')) $$, '23505', null,
  'codes are unique whatever their case');
select throws_ok($$ select inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
  'deal_id', (select id from ids where label = 'deal'), 'code', 'ABCDEF', 'destination', 'whatsapp_witty')) $$, '23514', null,
  'a code shaped like a Witty access code is refused');
select tests.as_person('arjun');
select throws_ok($$ select inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
  'deal_id', (select id from ids where label = 'deal'), 'code', 'ARJUN-FOR-RIYA', 'destination', 'whatsapp_witty')) $$, '42501', null,
  'another creator cannot make links for her');
select lives_ok($$ insert into ids select 'arjun_link', inf.link_create(jsonb_build_object('creator_id', (select id from ids where label = 'arjun'),
  'deal_id', (select id from ids where label = 'arjun_deal'), 'code', 'ARJUN-YT-22', 'destination', 'custom_url', 'custom_url', 'https://eduwit.in/mba')) $$,
  'arjun makes his own custom link');
select is((select count(*)::int from inf.tracking_links), 1, 'creators only see their own links');
select tests.as_person('mona');
select is(jsonb_array_length(inf.links_list((select id from ids where label = 'riya'))), 1, 'staff list a creator''s links');
select tests.reset();
select throws_ok($$ update inf.tracking_links set code = 'RIYA-NEW-11' where id = (select id from ids where label = 'link') $$, '42501', null,
  'a code never changes');

select tests.as_person('riya');
select throws_ok($$ select inf.link_resolve('RIYA-IG-AA') $$, '42501', null, 'only the server resolves codes for the redirect');
select tests.act_as_service();
select is(inf.link_resolve('riya-ig-aa') ->> 'creator_name', 'Riya', 'the server resolves a code, any case');
select is((inf.witty_resolve_code('riya-ig-aa') ->> 'valid')::boolean, true, 'Witty can validate a typed code');
select is((inf.witty_resolve_code('NOPE-11') ->> 'valid')::boolean, false, 'unknown codes are invalid');
select lives_ok($$ select inf.click_log(jsonb_build_object('link_id', (select id from ids where label = 'link'), 'ip_hash', 'h1', 'device', 'mobile',
  'w2_access_code', 'K7QM2X', 'user_agent', 'Mozilla/5.0 iPhone')) $$, 'the server logs a click with the issued access code');
select tests.reset();
select throws_ok($$ delete from inf.link_clicks $$, '42501', null, 'clicks are append-only');

-- ---------------------------------------------------------------------------------------------------------------
-- Leads arrive (as Witty writes them, locally) and the sweep gathers facts
-- ---------------------------------------------------------------------------------------------------------------
insert into leads select 'typed', (public.lead_intake(jsonb_build_object('phone', '9812345621', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Meera Kapoor', 'email', 'meera.k@gmail.com', 'city', 'Pune', 'classification', 'HOT',
                             'referral_code', 'RIYA-IG-AA', 'annual_budget_inr', 300000, 'notes', 'Calls after 6'),
  'attribution', jsonb_build_object('creator_code', 'RIYA-IG-AA'))) ->> 'lead_id')::bigint;
insert into leads select 'clicked', (public.lead_intake(jsonb_build_object('phone', '9822233344', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Kabir', 'access_code', 'K7QM2X'), 'attribution', jsonb_build_object('source', 'influencer'))) ->> 'lead_id')::bigint;
insert into leads select 'organic', (public.lead_intake(jsonb_build_object('phone', '9833344455', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Organic Student'))) ->> 'lead_id')::bigint;
insert into leads select 'self', (public.lead_intake(jsonb_build_object('phone', '9811100022', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Arjun Himself', 'referral_code', 'ARJUN-YT-22'))) ->> 'lead_id')::bigint;

select tests.as_person('mona');
select throws_ok($$ select inf.lead_sync_candidates('{"since":"-infinity"}') $$, '42501', null, 'staff cannot run the sweep');
select tests.act_as_service();
select ok(inf.witty_issue_code('{"source":"influencer","utm_source":"influencer","creator_code":"RIYA-IG-AA"}') ->> 'code' ~ '^[A-Z0-9]{6}$',
          'the redirect gets a Witty access code through the wrapper');
create temporary table cand as select inf.lead_sync_candidates('{"since":"-infinity"}') as c;
grant select on cand to service_role, authenticated;
select is(jsonb_array_length((select c -> 'leads' from cand)), 3, 'three leads carry creator evidence (the organic one is skipped)');
select is((select x -> 'touches' -> 0 ->> 'source' from cand, jsonb_array_elements(c -> 'leads') x where (x ->> 'id')::bigint = (select id from leads where label = 'clicked')),
          'click', 'the access code is matched to the logged click');
select ok((select jsonb_array_length(x -> 'touches') >= 1 from cand, jsonb_array_elements(c -> 'leads') x where (x ->> 'id')::bigint = (select id from leads where label = 'typed')),
          'the typed code is found');
select is((select x -> 'self_referral_creators' ->> 0 from cand, jsonb_array_elements(c -> 'leads') x where (x ->> 'id')::bigint = (select id from leads where label = 'self'))::uuid,
          (select id from ids where label = 'arjun'), 'a creator''s own number is a self-referral');
select ok((select jsonb_array_length(c -> 'stage_rules') > 20 from cand), 'the stage rules come with the facts');
select is((select c -> 'campaign_models' ->> (select id::text from ids where label = 'camp') from cand), 'last_touch',
          'campaign model overrides come with the facts');
select isnt((select c ->> 'watermark' from cand), null, 'a watermark is returned');

-- The app applies the pure rules; here the decisions are written as it would send them.
create temporary table payload (k text primary key, v jsonb);
grant select on payload to service_role;
insert into payload values ('riya', jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'link_id', (select id from ids where label = 'link'),
  'code', 'RIYA-IG-AA', 'deal_id', (select id from ids where label = 'deal'), 'touch', 'first', 'status', 'credited', 'touch_at', now(),
  'evidence_source', 'referral_code', 'stage', jsonb_build_object('stage', 'qualifying', 'reason', null, 'flags', '[]'::jsonb)));
insert into payload values ('arjun', jsonb_build_object('creator_id', (select id from ids where label = 'arjun'), 'link_id', (select id from ids where label = 'arjun_link'),
  'code', 'ARJUN-YT-22', 'touch', 'none', 'status', 'self_referral', 'reason', 'self_referral', 'touch_at', now(), 'evidence_source', 'referral_code',
  'stage', jsonb_build_object('stage', 'not_attributed', 'reason', 'self-referral', 'flags', '[]'::jsonb)));
insert into payload values ('first', jsonb_build_object('watermark', now(), 'leads', jsonb_build_array(
  jsonb_build_object('id', (select id from leads where label = 'typed'), 'created_at', now(), 'is_test', false,
                     'decisions', jsonb_build_array((select v from payload where k = 'riya'))),
  jsonb_build_object('id', (select id from leads where label = 'self'), 'created_at', now(), 'is_test', false,
                     'decisions', jsonb_build_array((select v from payload where k = 'arjun'))))));
insert into payload values ('again', jsonb_build_object('leads', jsonb_build_array(
  jsonb_build_object('id', (select id from leads where label = 'typed'), 'created_at', now(), 'decisions', jsonb_build_array((select v from payload where k = 'riya'))))));
select tests.act_as_service();
select lives_ok($$ select inf.lead_sync_apply((select v from payload where k = 'first')) $$, 'the sweep writes its decisions');
select is((select count(*)::int from inf.lead_attributions), 2, 'two attributions');
select is((select count(*)::int from inf.attribution_decisions where actor = 'system'), 2, 'each with a history row');
select is((select count(*)::int from inf.lead_stage_events), 2, 'and a stage event');
select is((select count(*)::int from inf.domain_events where type = 'lead.attributed'), 1, 'one lead.attributed event (credited only)');
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'lead.new'), 1,
          'the creator is told about the new lead');
select is((select (watermark is not null) from inf.sync_state where key = 'lead_sync'), true, 'the watermark moves');
select lives_ok($$ select inf.lead_sync_apply((select v from payload where k = 'again')) $$, 'applying the same outcome again');
select is((select count(*)::int from inf.lead_stage_events), 2, 'adds no new stage event');

-- ---------------------------------------------------------------------------------------------------------------
-- What creators see
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select is((select count(*)::int from inf.creator_lead_feed), 1, 'the creator sees her lead in the feed');
select is((select phone_masked from inf.creator_lead_feed), '98XXXXXX21', 'phone masked in the database');
select is((select email_masked from inf.creator_lead_feed), 'm****@gmail.com', 'email masked in the database');
select is((select display_name from inf.creator_lead_feed), 'Meera K.', 'first name and last initial');
select is((select fields ->> 'city' from inf.creator_lead_feed), 'Pune', 'whitelisted fields are shown');
select ok((select not (fields ? 'annual_budget_inr') and not (fields ? 'Comments') from inf.creator_lead_feed), 'hidden fields never reach the feed');
select ok((select position('9812345621' in row_to_json(f)::text) = 0 and position('meera.k@' in row_to_json(f)::text) = 0 from inf.creator_lead_feed f),
          'the raw phone and email appear nowhere in her row');
select is((select count(*)::int from public.student_leads), 0, 'creators read nothing from the shared lead table');
select is((select count(*)::int from inf.lead_attributions), 0, 'nor raw attributions');
select is(inf.lead_detail((select id from inf.lead_attributions where creator_id = (select id from ids where label = 'riya') limit 1)), null,
          'lead detail needs the attribution id she can see');
select tests.reset();
select tests.as_person('riya');
select ok((select inf.lead_detail(attribution_id) ->> 'contact' is null from inf.creator_lead_feed limit 1), 'no contact details in her lead detail');
select tests.as_person('arjun');
select is((select array_agg(creator_stage) from inf.creator_lead_feed), array['not_attributed'], 'arjun sees only his own (self-referral) lead');
select is((select attribution_reason from inf.creator_lead_feed), 'self_referral', 'with the reason and no personal data');

-- ---------------------------------------------------------------------------------------------------------------
-- Staff
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select is(((inf.leads_list('{}') -> 'rows' -> 0) ->> 'phone'), null, 'a manager without the contacts permission sees no phone');
select tests.as_person('asha');
select isnt(((inf.leads_list('{}') -> 'rows') -> 0 ->> 'phone'), null, 'a Super Admin sees contact details');
select tests.as_person('cara');
select throws_ok($$ select inf.leads_list('{}') $$, '42501', null, 'a content reviewer cannot read leads');

select tests.as_person('mona');
select throws_ok($$ select inf.attribution_override(jsonb_build_object('student_lead_id', (select id from leads where label = 'typed'),
  'creator_id', (select id from ids where label = 'arjun'), 'status', 'manually_credited', 'reason', '')) $$, '22023', 'a reason is required',
  'an override needs a reason');
select lives_ok($$ select inf.attribution_override(jsonb_build_object('student_lead_id', (select id from leads where label = 'typed'),
  'creator_id', (select id from ids where label = 'arjun'), 'status', 'manually_credited', 'reason', 'Proof of the story mention')) $$,
  'a manager credits another creator by hand');
select tests.reset();
select is((select status || ':' || touch from inf.lead_attributions where creator_id = (select id from ids where label = 'riya')), 'duplicate:none',
          'the previous holder loses the credit');
select is((select count(*)::int from inf.attribution_decisions where actor = 'staff'), 1, 'the override is recorded');
select is((select count(*)::int from inf.jobs where kind = 'leads.rerun'), 1, 'and the lead is queued for a re-run');

-- Fraud
select tests.act_as_service();
select is(inf.fraud_apply(jsonb_build_object('flags', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'attribution_id', null, 'signal', 'velocity', 'detail', jsonb_build_object('leads', 40))))), 1,
  'a creator-level flag opens');
select is(inf.fraud_apply(jsonb_build_object('flags', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'attribution_id', null, 'signal', 'velocity', 'detail', jsonb_build_object('leads', 41))))), 0,
  'an open flag is not duplicated');
select tests.as_person('fin');
select throws_ok($$ select inf.fraud_queue('{}') $$, '42501', null, 'finance does not review fraud');
select tests.as_person('mona');
select is(jsonb_array_length(inf.fraud_queue('{}')), 1, 'the manager sees the queue');
select lives_ok($$ select inf.fraud_decide((select id from inf.fraud_flags limit 1), false, 'Launch day spike, expected') $$, 'and clears it with a reason');
select throws_ok($$ select inf.stage_mapping_save('{"priority":5,"conditions":[{"field":"stage","in":["x"]}],"creator_stage":"new"}') $$, '42501', null,
  'only settings editors change stage rules');
select lives_ok($$ select inf.lead_backfill(current_date - 30, current_date) $$, 'a manager queues a backfill');

select * from finish();
rollback;
