-- Jobs (idempotent enqueue, claim, backoff, dead letter) and notifications (idempotent, preferences, privacy).
begin;
\ir _helpers.psql
select plan(16);

select tests.make_creator('alice');
select tests.make_creator('bob');

-- Jobs
select is(inf.job_enqueue('test.job', '{}', now(), 'once'), inf.job_enqueue('test.job', '{}', now(), 'once'), 'enqueue is idempotent on its key');
select is((select count(*)::int from inf.job_claim('w1', 10, array['test.job'])), 1, 'claimed once');
select is((select count(*)::int from inf.job_claim('w2', 10, array['test.job'])), 0, 'a running job is not claimed twice');
select is(inf.job_finish((select id from inf.jobs where idem_key = 'once'), false, 'boom'), 'failed', 'failure schedules a retry');
select ok((select run_at > now() from inf.jobs where idem_key = 'once'), 'retry is in the future (backoff)');
update inf.jobs set run_at = now(), max_attempts = 2 where idem_key = 'once';
select is((select count(*)::int from inf.job_claim('w1', 10, array['test.job'])), 1, 'due again after the backoff');
select is(inf.job_finish((select id from inf.jobs where idem_key = 'once'), false, 'boom again'), 'dead', 'after max attempts the job is dead');
select is((select count(*)::int from inf.domain_events where type = 'system.job_dead'), 1, 'a dead job emits an event');

-- Notifications
select inf.notification_preference_set('deliverable.due', 'email', false)
  from (select tests.as_person('alice')) x;
select tests.reset();
select ok(inf.notify((select user_id from tests.people where label = 'alice'), 'deliverable.due', 'Post due', 'Your post is due', '/creator/content', '{}', false, 'n1') is not null, 'notification created');
select is(inf.notify((select user_id from tests.people where label = 'alice'), 'deliverable.due', 'Post due', null, null, '{}', false, 'n1'),
          (select id from inf.notifications where idem_key = 'n1'), 'notify is idempotent');
select is((select string_agg(d.channel, ',') from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id where n.idem_key = 'n1'),
          'whatsapp', 'email skipped because the creator turned it off; WhatsApp stays on by the catalogue default');
select ok(inf.notify((select user_id from tests.people where label = 'alice'), 'payout.paid', 'Payout sent', null, null, '{}', true, 'n2') is not null, 'mandatory notification');
select is((select count(*)::int from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id where n.idem_key = 'n2'), 2,
          'mandatory events go to every default channel (email and WhatsApp) regardless of preferences');
select throws_ok($$ select inf.notify(gen_random_uuid(), 'x.y', 't', null, 'https://evil.example', '{}', false, 'n3') $$, '23514', null,
                 'links must be in-app paths');

select tests.as_person('bob');
select is((select count(*)::int from inf.my_notifications()), 0, 'bob sees none of alice''s notifications');
select tests.as_person('alice');
select is(inf.notifications_mark_read(null), 2, 'alice marks her two notifications read');

select tests.reset();
select * from finish();
rollback;
