-- Migration 20261113140000_inf_unsubscribe (D-198): following an unsubscribe link turns email off for one kind of
-- notification (or the email digest) in the tables the settings page writes, leaves required notices and every other
-- kind alone, records the choice in the consent log with its source, and is closed to everyone but the service role.
begin;
\ir _helpers.psql
select plan(43);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_creator('riya');
select tests.make_creator('arjun');

create temporary table ids (label text primary key, id uuid);
grant select on ids to authenticated, service_role;
insert into ids select label, user_id from tests.people;
create temporary table counts (k text primary key, n int);
grant select, insert on counts to authenticated, service_role;

-- What the catalogue says a creator can turn off, per group (the digest has its own category).
create temporary table expected as
select e.grp, count(*)::int as n from inf.notification_events e
 where not e.mandatory and e.event not like 'digest.%' and 'creator' = any (e.audience) group by e.grp;
grant select on expected to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Who may call it
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.unsubscribe_email((select id from ids where label = 'riya'), 'campaigns') $$, '42501', null,
                 'a signed-in creator cannot call it, even for themselves');
select tests.as_person('mona');
select throws_ok($$ select inf.unsubscribe_email((select id from ids where label = 'riya'), 'campaigns') $$, '42501', null,
                 'nor can staff');
select tests.act_as_anon();
select throws_ok($$ select inf.unsubscribe_email('00000000-0000-0000-0000-000000000001', 'campaigns') $$, '42501', null,
                 'nor a signed-out visitor');
select tests.reset();
select throws_ok($$ select inf.unsubscribe_email((select id from ids where label = 'riya'), 'campaigns') $$, '42501', 'not allowed',
                 'the function itself refuses a caller that is not the service role');
select is((select count(*)::int from inf.notification_preferences), 0, 'a refused call changes nothing');
select ok(not has_function_privilege('authenticated', 'inf.unsubscribe_email(uuid, text)', 'execute')
          and not has_function_privilege('anon', 'inf.unsubscribe_email(uuid, text)', 'execute')
          and has_function_privilege('service_role', 'inf.unsubscribe_email(uuid, text)', 'execute'),
          'only the service role has execute');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
            where p.oid = 'inf.unsubscribe_email(uuid, text)'::regprocedure),
          'it is security definer with an empty search path');

-- ---------------------------------------------------------------------------------------------------------------
-- One notification group: only that group's email, only what can be turned off
-- ---------------------------------------------------------------------------------------------------------------
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'campaigns'),
          (select n from expected where grp = 'campaigns'), 'campaigns: every campaign notification a creator can turn off');
select tests.reset();
select ok((select n from expected where grp = 'campaigns') >= 3, 'the catalogue has several of them');
select is((select count(*)::int from inf.notification_preferences np join inf.notification_events e on e.event = np.event
            where np.user_id = (select id from ids where label = 'riya') and e.grp = 'campaigns' and np.channel = 'email' and not np.enabled),
          (select n from expected where grp = 'campaigns'), 'email is off for each of them');
select is((select count(*)::int from inf.notification_preferences np join inf.notification_events e on e.event = np.event
            where np.user_id = (select id from ids where label = 'riya') and (e.grp <> 'campaigns' or np.channel <> 'email')),
          0, 'no other group and no other channel is touched');
select is((select count(*)::int from inf.notification_preferences where event = 'application.submitted'), 0,
          'an event only staff receive gets no row for a creator');
select is((select count(*)::int from inf.notification_preferences where user_id <> (select id from ids where label = 'riya')), 0,
          'nobody else is touched');
select is((select count(*)::int from inf.communication_consents c
            where c.user_id = (select id from ids where label = 'riya') and c.channel = 'email' and not c.granted and c.source = 'unsubscribe_link'),
          (select n from expected where grp = 'campaigns'), 'each withdrawal is in the consent log with source unsubscribe_link');
select is((select count(*)::int from inf.communication_consents c where c.source <> 'unsubscribe_link' or c.granted), 0,
          'and nothing else was logged');

-- Following the link again changes nothing and logs nothing.
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'campaigns'), 0, 'a second click changes nothing');
select tests.reset();
select is((select count(*)::int from inf.communication_consents), (select n from expected where grp = 'campaigns'), 'and adds no consent row');

-- What is sent afterwards.
select inf.notify((select id from ids where label = 'riya'), 'campaign.invited', 'Invited', 'b', '/creator', '{}', false, 'unsub-test-1');
select is((select string_agg(d.channel, ',' order by d.channel) from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id
            where n.idem_key = 'unsub-test-1'), 'whatsapp', 'a campaign invitation no longer goes by email (WhatsApp is unchanged)');
select inf.notify((select id from ids where label = 'riya'), 'deal.proposed', 'Deal', 'b', '/creator', '{}', false, 'unsub-test-2');
select ok(exists (select 1 from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id
                   where n.idem_key = 'unsub-test-2' and d.channel = 'email'), 'a deal proposal still does');
select inf.notify((select id from ids where label = 'arjun'), 'campaign.invited', 'Invited', 'b', '/creator', '{}', false, 'unsub-test-3');
select ok(exists (select 1 from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id
                   where n.idem_key = 'unsub-test-3' and d.channel = 'email'), 'and another creator still gets the invitation by email');

-- ---------------------------------------------------------------------------------------------------------------
-- Required notices keep arriving
-- ---------------------------------------------------------------------------------------------------------------
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'contracts'),
          (select n from expected where grp = 'contracts'), 'contracts: only the notices that can be turned off');
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'money'), 0, 'money: every notice is required, nothing changes');
select tests.reset();
select is((select count(*)::int from inf.notification_preferences np join inf.notification_events e on e.event = np.event where e.mandatory), 0,
          'no required event has a row');
select inf.notify((select id from ids where label = 'riya'), 'contract.sent', 'Contract', 'b', '/creator', '{}', false, 'unsub-test-4');
select ok(exists (select 1 from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id
                   where n.idem_key = 'unsub-test-4' and d.channel = 'email'), 'a contract sent for review still goes by email');
select inf.notify((select id from ids where label = 'riya'), 'contract.comment', 'Comment', 'b', '/creator', '{}', false, 'unsub-test-5');
select ok(not exists (select 1 from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id
                       where n.idem_key = 'unsub-test-5' and d.channel = 'email'), 'a contract comment does not');

-- ---------------------------------------------------------------------------------------------------------------
-- Announcements: the digest sits in the same group but is its own kind of email
-- ---------------------------------------------------------------------------------------------------------------
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'announcements'),
          (select n from expected where grp = 'announcements'), 'announcements: the announcement email is turned off');
select tests.reset();
select ok(exists (select 1 from inf.notification_preferences where user_id = (select id from ids where label = 'riya')
                    and event = 'announcement' and channel = 'email' and not enabled)
          and not exists (select 1 from inf.notification_preferences where event like 'digest.%')
          and not exists (select 1 from inf.digest_preferences),
          'the digest is left as it was');

-- ---------------------------------------------------------------------------------------------------------------
-- The digest
-- ---------------------------------------------------------------------------------------------------------------
insert into counts select 'consents', count(*)::int from inf.communication_consents;
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'digest'), 1, 'digest: the default (email) digest is turned off');
select is(inf.unsubscribe_email((select id from ids where label = 'riya'), 'digest'), 0, 'a second click changes nothing');
select ok(not exists (select 1 from inf.digest_recipients(date '2026-11-16') r where r.user_id = (select id from ids where label = 'riya'))
          and exists (select 1 from inf.digest_recipients(date '2026-11-16') r where r.user_id = (select id from ids where label = 'arjun')),
          'the creator is no longer a digest recipient; another creator still is');
select tests.reset();
select is((select c.purpose || ':' || c.channel || ':' || c.granted || ':' || c.detail || ':' || c.source from inf.communication_consents c
            where c.id > (select max(id) - 1 from inf.communication_consents)), 'digest:email:false:off:unsubscribe_link',
          'the digest withdrawal is in the consent log with its source');
select is((select count(*)::int from inf.communication_consents), (select n + 1 from counts where k = 'consents'), 'once');

-- A digest sent by WhatsApp is not an email: the link leaves it alone.
select tests.as_person('arjun');
select inf.digest_preference_set('daily', 'whatsapp');
select inf.notification_preference_set('lead.new', 'email', true);
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'arjun'), 'digest'), 0, 'a WhatsApp digest is left alone');
select tests.reset();
select is((select frequency || ':' || channel from inf.digest_preferences where user_id = (select id from ids where label = 'arjun')),
          'daily:whatsapp', 'and stays as chosen');

-- An email copy of the digest switched on next to the WhatsApp digest is an email: the link stops it.
select tests.as_person('arjun');
select inf.notification_preference_set('digest.creator', 'email', true);
select tests.act_as_service();
select is(inf.unsubscribe_email((select id from ids where label = 'arjun'), 'digest'), 1, 'an email copy switched on by itself is turned off');
select tests.reset();
select is((select enabled from inf.notification_preferences where user_id = (select id from ids where label = 'arjun') and event = 'digest.creator' and channel = 'email'),
          false, 'the email copy is off');
select is((select frequency || ':' || channel from inf.digest_preferences where user_id = (select id from ids where label = 'arjun')),
          'daily:whatsapp', 'and the WhatsApp digest still stays as chosen');
select is((select c.purpose || ':' || c.granted || ':' || c.source from inf.communication_consents c
            where c.user_id = (select id from ids where label = 'arjun') order by c.id desc limit 1),
          'digest.creator:false:unsubscribe_link', 'with its own line in the consent log');

-- ---------------------------------------------------------------------------------------------------------------
-- Choices made in settings keep their own source, before and after a link in the same transaction
-- ---------------------------------------------------------------------------------------------------------------
select tests.act_as_service();
select ok(inf.unsubscribe_email((select id from ids where label = 'arjun'), 'leads') >= 1, 'leads: a channel switched on in settings is switched off');
select tests.as_person('arjun');
select inf.notification_preference_set('lead.new', 'email', true);
select is((select string_agg((x ->> 'granted') || ':' || (x ->> 'source'), ',' order by ord)
             from jsonb_array_elements(inf.my_consents()) with ordinality as t(x, ord) where x ->> 'purpose' = 'lead.new'),
          'true:settings,false:unsubscribe_link,true:settings',
          'the person sees each choice with its source, newest first: settings, the link, settings again');

-- ---------------------------------------------------------------------------------------------------------------
-- Staff, and inputs that match nothing
-- ---------------------------------------------------------------------------------------------------------------
select tests.act_as_service();
select inf.unsubscribe_email((select id from ids where label = 'mona'), 'campaigns');
select is(inf.unsubscribe_email('00000000-0000-0000-0000-000000000001', 'campaigns')
          + inf.unsubscribe_email((select id from ids where label = 'mona'), 'no_such_group')
          + inf.unsubscribe_email((select id from ids where label = 'mona'), null)
          + inf.unsubscribe_email(null, 'campaigns'), 0, 'an unknown person, an unknown category and nulls change nothing');
select tests.reset();
select ok(exists (select 1 from inf.notification_preferences where user_id = (select id from ids where label = 'mona') and event = 'application.submitted' and not enabled)
          and not exists (select 1 from inf.notification_preferences where user_id = (select id from ids where label = 'mona') and event = 'campaign.invited'),
          'staff get the staff events of the group, not the creator ones');
select throws_ok($$ insert into inf.communication_consents (user_id, purpose, channel, granted, source)
                    values ((select id from ids where label = 'riya'), 'digest', 'email', false, 'import') $$, '23514', null,
                 'the consent log accepts only known sources');

select tests.reset();
select * from finish();
rollback;
