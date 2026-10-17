-- Communication: who may read and write which thread (staff permissions, the creator, agency grants, staff-only lead
-- notes, per-creator campaign threads), mentions, unread counts and read receipts, attachments, preferences (mandatory
-- events locked), template versions and variables, announcements to segments, digests, signed webhooks whose payloads
-- carry no contact details, and the catalogue events raised by the ledger and fraud checks.
begin;
\ir _helpers.psql
select plan(74);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('cara', array['content_reviewer']);
select tests.make_staff('sam', array['super_admin']);
select tests.make_staff('vic', array['viewer']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set languages = array['Konkani-test'] where id = (select creator_id from tests.people where label = 'riya');

insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000c001', 'Acme Talent'), ('00000000-0000-0000-0000-00000000c002', 'Zen Mgmt');
do $$
declare v_uid uuid; v_sid uuid;
begin
  v_uid := tests.create_user('ola@acme-comm.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000c001', 'ola@acme-comm.test', 'Ola', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('ola', v_uid, v_sid, null);
  v_uid := tests.create_user('zed@zen-comm.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000c002', 'zed@zen-comm.test', 'Zed', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('zed', v_uid, v_sid, null);
end $$;
-- Acme may view Riya and act on her deliverables, but not negotiate.
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_act_deliverables)
select '00000000-0000-0000-0000-00000000c001', creator_id, 'active', true, true from tests.people where label = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert, update on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('deal', gen_random_uuid()), ('campaign', gen_random_uuid());
insert into inf.campaigns (id, name, objective, created_by) values ((select id from ids where label = 'campaign'), 'Comm push', 'leads', (select user_id from tests.people where label = 'mona'));
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at, owner_id)
values ((select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Riya reel deal', 'active', current_date - 10, 'hybrid', now(),
        (select user_id from tests.people where label = 'mona'));
with l as (insert into public.student_leads (whatsapp_number, student_name, stage) values ('910000008801', 'Comm Lead', 'new') returning id)
insert into inf.lead_attributions (student_lead_id, creator_id, code, touch, status, evidence_source, touch_at, lead_created_at, creator_stage)
select l.id, (select id from ids where label = 'riya'), 'RIYA-COMM', 'first', 'credited', 'click', now(), now(), 'new' from l;
insert into ids select 'attribution', id from inf.lead_attributions where code = 'RIYA-COMM';

-- ---------------------------------------------------------------------------------------------------------------
-- Threads: access
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select is(inf.thread_get('deal', (select id from ids where label = 'deal')) ->> 'side', 'eduwit', 'staff with message.read and deal.read open a deal thread');
select is(inf.thread_get('deal', (select id from ids where label = 'deal')) ->> 'thread_id', null, 'nothing is created by reading');
select tests.as_person('riya');
select lives_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), 'When is the shoot?') $$, 'the creator writes on her deal');
select tests.reset();
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id
            where p.label = 'mona' and n.event = 'thread.message' and n.data ->> 'subject' = 'Deal: Riya reel deal'), 1, 'the deal owner is told');
insert into ids select 'deal_thread', id from inf.threads where entity_type = 'deal' and entity_id = (select id from ids where label = 'deal');
-- Everything in a test runs at one now(): date the creator's own read back so later replies count as unread.
update inf.thread_reads set last_read_at = now() - interval '1 minute' where thread_id = (select id from ids where label = 'deal_thread');
select tests.as_person('riya');
select is(jsonb_array_length(inf.thread_get('deal', (select id from ids where label = 'deal')) -> 'messages'), 1, 'and she reads her thread');
select tests.as_person('arjun');
select throws_ok($$ select inf.thread_get('deal', (select id from ids where label = 'deal')) $$, '42501', null, 'another creator cannot read it');
select throws_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), 'hi') $$, '42501', null, 'or write in it');
select tests.as_person('ola');
select throws_ok($$ select inf.thread_get('deal', (select id from ids where label = 'deal')) $$, '42501', null, 'an agency without the negotiate grant cannot read deal threads');
select lives_ok($$ select inf.thread_post('support', (select id from ids where label = 'riya'), 'Question about Riya''s profile') $$,
                'an agency with the view grant writes on the creator''s support thread');
select tests.as_person('zed');
select throws_ok($$ select inf.thread_get('support', (select id from ids where label = 'riya')) $$, '42501', null, 'an unlinked agency cannot');
select tests.as_person('vic');
select throws_ok($$ select inf.thread_get('deal', (select id from ids where label = 'deal')) $$, '42501', null, 'staff without message.read cannot');
select tests.as_person('cara');
select throws_ok($$ select inf.thread_get('deal', (select id from ids where label = 'deal')) $$, '42501', null, 'message.read alone is not enough without the entity''s read permission');

-- Mentions, the other side, unread counts and receipts
select tests.as_person('mona');
select lives_ok(format($$ select inf.thread_post('deal', %L, %L) $$, (select id from ids where label = 'deal'),
                       'Next Tuesday. @[Sam](user:' || (select user_id from tests.people where label = 'sam') || ') please book the studio.'),
                'staff reply and mention a colleague');
select tests.reset();
select is((select count(*)::int from inf.message_mentions mm join tests.people p on p.user_id = mm.user_id where p.label = 'sam'), 1, 'the mention is recorded');
select is((select n.body from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'sam' and n.event = 'thread.mention'),
          'Next Tuesday. @Sam please book the studio.', 'the colleague is told, with the mention as plain text');
select tests.reset();
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'ola' and n.event = 'thread.message'
             and n.data ->> 'subject' = 'Deal: Riya reel deal'), 0, 'an agency without the negotiate grant is not told about deal messages');
select tests.as_person('riya');
select is((select (x ->> 'unread')::int from jsonb_array_elements(inf.my_threads()) x where x ->> 'entity_type' = 'deal'), 1, 'the creator has one unread reply');
select is((inf.my_unread_counts() ->> 'messages')::int, 1, 'and the header badge shows it');
select ok((select m ->> 'author_name' from jsonb_array_elements(inf.thread_get('deal', (select id from ids where label = 'deal')) -> 'messages') m
            where m ->> 'author_side' = 'eduwit') = 'Mona (Eduwit)', 'creators see the Eduwit person''s first name');
select lives_ok($$ select inf.thread_mark_read((inf.thread_get('deal', (select id from ids where label = 'deal')) ->> 'thread_id')::uuid) $$, 'she reads it');
select is((inf.my_unread_counts() ->> 'messages')::int, 0, 'which clears the message notification');
select tests.as_person('mona');
select isnt(inf.thread_get('deal', (select id from ids where label = 'deal')) ->> 'other_read_at', null, 'staff see when the creator read the thread');
select tests.as_person('riya');
select lives_ok(format($$ select inf.thread_post('deal', %L, %L) $$, (select id from ids where label = 'deal'),
                       'Thanks @[Sam](user:' || (select user_id from tests.people where label = 'sam') || ')'), 'a creator can type a mention token');
select tests.reset();
select is((select count(*)::int from inf.message_mentions mm join tests.people p on p.user_id = mm.user_id where p.label = 'sam'), 1, 'but only staff posts mention staff');

-- Staff-only lead notes
select tests.as_person('mona');
select is(inf.thread_post('lead', (select id from ids where label = 'attribution'), 'Called twice, no answer') ? 'thread_id', true, 'staff keep notes on a lead');
select tests.as_person('riya');
select throws_ok($$ select inf.thread_get('lead', (select id from ids where label = 'attribution')) $$, '42501', null, 'lead notes are staff-only');
select is((select count(*)::int from jsonb_array_elements(inf.my_threads()) x where x ->> 'entity_type' = 'lead'), 0, 'and never listed for the creator');

-- Campaign threads are per creator
select tests.as_person('riya');
insert into ids select 'riya_campaign_thread', (inf.thread_post('campaign', (select id from ids where label = 'campaign'), 'Can I join?', '[]', (select id from ids where label = 'riya')) ->> 'thread_id')::uuid;
select tests.as_person('arjun');
insert into ids select 'arjun_campaign_thread', (inf.thread_post('campaign', (select id from ids where label = 'campaign'), 'Me too', '[]', (select id from ids where label = 'arjun')) ->> 'thread_id')::uuid;
select isnt((select id from ids where label = 'riya_campaign_thread'), (select id from ids where label = 'arjun_campaign_thread'), 'each creator has a private campaign thread');
select throws_ok($$ select inf.thread_get('campaign', (select id from ids where label = 'campaign'), (select id from ids where label = 'riya')) $$, '42501', null,
                 'and cannot read another creator''s');

-- Attachments
select tests.as_person('riya');
select throws_ok(format($$ select inf.thread_post('deal', %L, 'file', %L::jsonb) $$, (select id from ids where label = 'deal'),
                        jsonb_build_array(jsonb_build_object('path', 'threads/' || (select id from ids where label = 'arjun_campaign_thread') || '/' || gen_random_uuid() || '-x.pdf',
                                                             'name', 'x.pdf', 'mime', 'application/pdf', 'size_bytes', 10))::text),
                 '22023', null, 'files must be uploaded under the thread they are posted to');
insert into ids values ('file', gen_random_uuid());
select lives_ok(format($$ select inf.thread_post('deal', %L, '', %L::jsonb) $$, (select id from ids where label = 'deal'),
                       jsonb_build_array(jsonb_build_object('path', 'threads/' || (inf.thread_open('deal', (select id from ids where label = 'deal'))) || '/' || (select id from ids where label = 'file') || '-script.pdf',
                                                            'name', 'script.pdf', 'mime', 'application/pdf', 'size_bytes', 2048))::text),
                'a file can be sent on its own');
select ok(inf.thread_file_allowed('threads/' || inf.thread_open('deal', (select id from ids where label = 'deal')) || '/' || (select id from ids where label = 'file') || '-script.pdf'),
          'the creator may download it');
select throws_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), '   ') $$, '22023', null, 'an empty message is refused');
select throws_ok($$ select count(*) from inf.message_attachments $$, '42501', null, 'attachment rows are closed to clients');
select tests.as_person('arjun');
select ok(not inf.thread_file_allowed(('threads/' || (select id from ids where label = 'deal_thread') || '/' || (select id from ids where label = 'file') || '-script.pdf')),
          'another creator may not');

-- ---------------------------------------------------------------------------------------------------------------
-- Preferences and digests
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.notification_preference_set('payout.paid', 'email', false) $$, '22023', null, 'mandatory notifications cannot be turned off');
select lives_ok($$ select inf.notification_preference_set('deliverable.due', 'whatsapp', false) $$, 'optional ones can');
select is((select (x ->> 'enabled')::boolean from jsonb_array_elements(inf.my_notification_preferences() -> 'prefs') x
            where x ->> 'event' = 'deliverable.due' and x ->> 'channel' = 'whatsapp'), false, 'and the choice is listed');
select throws_ok($$ select inf.digest_preference_set('hourly', 'email') $$, '22023', null, 'only daily, weekly or off');
select lives_ok($$ select inf.digest_preference_set('daily', 'email') $$, 'the creator asks for a daily digest');
select tests.act_as_service();
select is((select string_agg(p.label || ':' || r.frequency, ',' order by p.label) from inf.digest_recipients(date '2026-10-20') r
             join tests.people p on p.user_id = r.user_id where p.label in ('riya', 'arjun', 'mona')),
          'mona:daily,riya:daily', 'on a Tuesday only daily digests go out (staff default to daily, setting notifications.delivery)');
select is((select string_agg(p.label || ':' || r.frequency, ',' order by p.label) from inf.digest_recipients(date '2026-10-19') r
             join tests.people p on p.user_id = r.user_id where p.label in ('riya', 'arjun', 'mona')),
          'arjun:weekly,mona:daily,riya:daily', 'on Monday creators get the weekly one by default');
select ok(inf.digest_facts((select user_id from tests.people where label = 'riya'), 'creator', 7, (select id from ids where label = 'riya')) ?& array['new_leads', 'earned_paise', 'due_soon'],
          'the digest facts for a creator');
select tests.as_person('riya');
select throws_ok($$ select inf.digest_facts((select user_id from tests.people where label = 'riya'), 'creator', 7, (select id from ids where label = 'riya')) $$,
                 '42501', null, 'only the job reads digest facts');

-- ---------------------------------------------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.notification_template_save('{"event":"payout.paid","channel":"email","subject":"Paid","body":"Hi {{name}}"}') $$, '42501', null,
                 'templates need notification_template.write');
select tests.as_person('sam');
select throws_ok($$ select inf.notification_template_save('{"event":"payout.paid","channel":"email","subject":"Paid","body":"Call {{phone}}"}') $$, '22023', null,
                 'unknown variables are refused');
select lives_ok($$ select inf.notification_template_save('{"event":"payout.paid","channel":"email","subject":"Paid {{amount}}","body":"Hi {{name}}, UTR {{utr}}"}') $$, 'version 1');
select lives_ok($$ select inf.notification_template_save('{"event":"payout.paid","channel":"email","subject":"Paid {{ amount }}","body":"Hello {{name}}, UTR {{utr}}"}') $$, 'version 2');
select throws_ok($$ select inf.notification_template_save('{"event":"payout.paid","channel":"whatsapp","body":"Hi {{name}}"}') $$, '22023', null,
                 'WhatsApp templates name the approved provider template');
select tests.act_as_service();
select is(inf.notification_template_for('payout.paid', 'email') ->> 'version', '2', 'the newest version is used');
select tests.as_person('sam');
select lives_ok($$ select inf.notification_template_reset('payout.paid', 'email') $$, 'back to the built-in copy');
select tests.act_as_service();
select is(inf.notification_template_for('payout.paid', 'email'), null, 'no active custom template');

-- ---------------------------------------------------------------------------------------------------------------
-- Announcements
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.announcement_save('{"title":"Hi","body":"Hello all","action":"send"}') $$, '42501', null, 'creators cannot announce');
select tests.as_person('mona');
select is(inf.announcement_audience_count('{"languages":["konkani-test"]}'), 1, 'the segment preview counts matching creators');
select throws_ok($$ select inf.announcement_save(jsonb_build_object('title', 'Later', 'body', 'Scheduled note', 'action', 'schedule', 'scheduled_at', now() - interval '1 day')) $$,
                 '22023', null, 'a schedule must be in the future');
insert into ids select 'announcement', inf.announcement_save('{"title":"Konkani creators meet-up","body":"Join us on Friday.","link":"/creator/campaigns","segment":{"languages":["konkani-test"]},"action":"send"}');
select tests.reset();
select is((select status || ':' || recipients from inf.announcements where id = (select id from ids where label = 'announcement')), 'sent:1', 'sent at once to the segment');
select tests.as_person('riya');
select is(inf.my_announcements(3) -> 0 ->> 'title', 'Konkani creators meet-up', 'the creator sees it on her home page');
select tests.as_person('arjun');
select is(jsonb_array_length(inf.my_announcements(3)), 0, 'creators outside the segment do not');

-- ---------------------------------------------------------------------------------------------------------------
-- Webhooks
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.webhook_endpoint_create('{"url":"https://hooks.example.com/x","events":["lead.attributed"],"secret":"0123456789abcdef0123456789abcdef"}') $$,
                 '42501', null, 'webhooks need webhook.manage');
select tests.as_person('sam');
select throws_ok($$ select inf.webhook_endpoint_create('{"url":"https://10.0.0.5/x","events":["lead.attributed"],"secret":"0123456789abcdef0123456789abcdef"}') $$,
                 '22023', null, 'private addresses cannot receive webhooks');
insert into ids select 'endpoint', inf.webhook_endpoint_create('{"url":"https://hooks.example.com/eduwit","events":["lead.attributed","creator.activated"],"secret":"0123456789abcdef0123456789abcdef-secret"}');
select tests.reset();
select ok((select position(convert_to('0123456789abcdef', 'utf8') in secret_enc) = 0 from inf.webhook_endpoints where id = (select id from ids where label = 'endpoint')),
          'the signing secret is stored encrypted');
select inf.emit_event('lead.attributed', 'lead_attribution', (select id::text from ids where label = 'attribution'), '{}'::jsonb, 'comm-test-attributed');
select is((select d.payload -> 'data' ->> 'creator_handle' from inf.webhook_deliveries d where d.endpoint_id = (select id from ids where label = 'endpoint') and d.event = 'lead.attributed'),
          'riya', 'a subscribed event is queued with the creator''s handle');
select ok((select d.payload::text !~ '910000008801' and d.payload::text !~ '@' from inf.webhook_deliveries d where d.endpoint_id = (select id from ids where label = 'endpoint')),
          'payloads carry no phone number or email');
select tests.act_as_service();
select is(inf.webhook_delivery_get((select id from inf.webhook_deliveries where endpoint_id = (select id from ids where label = 'endpoint') limit 1)) ->> 'secret',
          '0123456789abcdef0123456789abcdef-secret', 'the delivery job gets the secret to sign with');
select lives_ok($$ select inf.webhook_delivery_result((select id from inf.webhook_deliveries where endpoint_id = (select id from ids where label = 'endpoint') limit 1),
                                                       'retry', 503, 'Service Unavailable', now() + interval '1 minute') $$, 'a failed attempt is recorded');
select is((select status || ':' || attempts from inf.webhook_deliveries where endpoint_id = (select id from ids where label = 'endpoint') limit 1), 'queued:1',
          'and retried later');
select tests.as_person('sam');
select throws_ok($$ select count(*) from inf.webhook_deliveries $$, '42501', null, 'the delivery log is read through webhooks_list only');
select tests.as_person('riya');
select throws_ok($$ select inf.webhook_delivery_get(1) $$, '42501', null, 'clients never get a secret');

-- ---------------------------------------------------------------------------------------------------------------
-- Catalogue events from the ledger and fraud checks
-- ---------------------------------------------------------------------------------------------------------------
select tests.reset();
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'commission', 'direction', 'credit', 'amount_paise', 123450, 'source', 'engine', 'event_key', 'comm:enrol', 'subject', 'enrol:b2b:991',
  'attribution_id', (select id from ids where label = 'attribution'), 'tds_component', 'commission', 'due_on', current_date));
select is((select n.title from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'lead.enrolled'),
          'A student enrolled: ₹1,234.50 earned', 'an enrolment tells the creator what she earned');
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'milestone', 'direction', 'credit', 'amount_paise', 500000, 'confirmed_paise', 500000, 'source', 'engine', 'event_key', 'comm:milestone',
  'tds_component', 'milestone', 'due_on', current_date, 'note', 'First reel live'));
select is((select n.title || '|' || n.mandatory from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'ledger.payable'),
          '₹5,000.00 is due to you|true', 'a fixed amount that is due is announced (mandatory)');
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'deal_id', (select id from ids where label = 'deal'),
  'type', 'reversal', 'direction', 'debit', 'amount_paise', 123450, 'confirmed_paise', 0, 'source', 'reversal', 'event_key', 'rev:comm:enrol',
  'subject', 'enrol:b2b:991', 'reverses_id', (select id from inf.ledger_entries where event_key = 'comm:enrol'), 'due_on', current_date, 'note', 'No longer earned'));
select is((select n.title || '|' || n.body from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'lead.clawed_back'),
          '₹1,234.50 commission no longer earned|The enrolment was cancelled or refunded. It had not been paid, so nothing is recovered.',
          'a refunded enrolment is explained to the creator');
select lives_ok($$ select inf.comm_daily() $$, 'the daily nudges run');
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id where p.label = 'riya' and n.event = 'kyc.action_needed'), 1,
          'money is due but KYC is not verified: the creator is asked to finish it');
insert into inf.fraud_flags (creator_id, signal) values ((select id from ids where label = 'riya'), 'velocity');
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id where n.event = 'fraud.flagged' and p.label in ('mona', 'cara', 'sam')), 2,
          'fraud flags reach the staff who review them');

select * from finish();
rollback;
