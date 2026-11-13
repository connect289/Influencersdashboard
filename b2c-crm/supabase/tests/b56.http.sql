-- b56 checks for an HTTP SQL API: the checks of test_job_budget_2026_11.sql in one self-contained file, with no psql
-- commands and no test extension. Send it in the same transaction as b56_send_final_and_job_budget.sql:
--     begin;  <the migration>  <this file>  rollback;
-- It writes only test users (*.jb@eduwit.in), test leads (phones 9100009956xx) and rows named "jb", records each check
-- in a temporary table, and always ends with an error that carries the result:
--     TESTRESULT total=<checks> failed=0
-- failed=0 is a pass; any failed check is listed after it by number and name. The error is what guarantees nothing the
-- checks write is kept, whatever the caller does next. It calls the take functions of the queues (rows already waiting
-- there are taken too, inside this transaction only, and are as they were once it rolls back).
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e561', 'asha.jb@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e564', 'admin.jb@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, languages) values
  ('aaaaaaaa-0000-0000-0000-00000000e561', 'asha.jb@eduwit.in', 'Asha JB', 'counsellor', true, true, false, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e564', 'admin.jb@eduwit.in', 'Admin JB', 'admin', true, true, false, '{English}');
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
update b2c.settings set value = value || '{"quiet_start": "00:00", "quiet_end": "23:59"}' where key = 'messaging';

/* A test sales lead owned by Asha JB (phone 9100009956 + the last two digits of the id). */
create function pg_temp.lead(p_id bigint) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'jb-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'JB Student ' || p_id, 'phone', '9100009956' || right(p_id::text, 2), 'email', 'jb' || p_id || '@example.com'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false, 'marketing_consent_at', now()), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'jb-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', '{"b2c_lane": "sales", "reason": "qualified"}'::jsonb), 'test');
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000e561', status = 'active' where lead_id = p_id;
end $f$;
/* Whether a take's answer (a JSON array of rows, or of ids) holds the row with this id under this key. */
create function pg_temp.took(p_taken jsonb, p_key text, p_id bigint) returns boolean language sql as $f$
  select exists (select 1 from jsonb_array_elements(p_taken) x where (case when p_key is null then x #>> '{}' else x ->> p_key end)::bigint = p_id)
$f$;

do $t$
declare j jsonb; v_before jsonb; q b2c.send_queue; v_a bigint; v_b bigint; v_c bigint; v_wa bigint; v_task bigint; v_dash bigint; n int; n2 int; e text; t0 timestamptz;
  c_asha constant uuid := 'aaaaaaaa-0000-0000-0000-00000000e561'; c_admin constant uuid := 'aaaaaaaa-0000-0000-0000-00000000e564';
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(995601); perform pg_temp.lead(995602);
  delete from b2c.send_queue where to_address like '9100009956%' or lead_id between 995600 and 995699;

  -- ---------- 1a. outbox: back to queued, the attempt not counted ----------
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent) values ('activity', 995601, 'jb-act-1', '{"kind": "note", "note": "jb"}', true) returning id into v_a;
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent) values ('update', 995601, 'jb-upd-1', '{"set": {"jb": 1}}', true) returning id into v_b;
  select to_jsonb(o) - 'sent_at' into v_before from b2c.outbox o where id = v_a;
  j := b2c.outbox_take('urgent', 100000);
  insert into r (name, ok, detail) values ('outbox_taken', pg_temp.took(j, 'id', v_a) and pg_temp.took(j, 'id', v_b)
    and (select bool_and(status = 'sending' and attempts = 1) from b2c.outbox where id in (v_a, v_b)), null);
  n := b2c.job_release('outbox', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('outbox_released_as_it_was', n = 2 and (select to_jsonb(o) - 'sent_at' from b2c.outbox o where id = v_a) = v_before
    and (select status = 'queued' and attempts = 0 from b2c.outbox where id = v_b), n::text);
  j := b2c.outbox_take('urgent', 100000);
  insert into r (name, ok, detail) values ('outbox_due_again_one_attempt', pg_temp.took(j, 'id', v_a) and pg_temp.took(j, 'id', v_b)
    and (select bool_and(status = 'sending' and attempts = 1) from b2c.outbox where id in (v_a, v_b)), null);
  update b2c.outbox set status = 'applied', done_at = now() where id = v_a;
  v_c := b2c.queue_update(995601, '{"jb": 2}', true);
  n := b2c.job_release('outbox', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('outbox_done_and_superseded_rows_left_alone', n = 0 and v_c <> v_b
    and (select status from b2c.outbox where id = v_a) = 'applied' and (select status = 'sending' and attempts = 1 from b2c.outbox where id = v_b)
    and (select status from b2c.outbox where id = v_c) = 'queued', n::text);

  -- ---------- 1b. files to remove ----------
  insert into b2c.erase_files (lead_id, bucket, path) values (null, 'b2c-exports', 'jb/not-started.csv') returning id into v_a;
  insert into b2c.erase_files (lead_id, bucket, path) values (null, 'b2c-exports', 'jb/removed.csv') returning id into v_b;
  j := b2c.erase_files_take(100000);
  perform b2c.erase_file_done(v_b, null);
  n := b2c.job_release('erase_files', array[v_a, v_b]);
  n2 := b2c.job_release('erase_files', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('erase_files_released', pg_temp.took(j, 'id', v_a) and n = 1 and n2 = 0
    and (select attempts = 0 and removed_at is null from b2c.erase_files where id = v_a)
    and (select attempts = 1 and removed_at is not null from b2c.erase_files where id = v_b)
    and pg_temp.took(b2c.erase_files_take(100000), 'id', v_a), n || ',' || n2);

  -- ---------- 1c. exports ----------
  insert into b2c.exports (user_id, params, format) values (c_admin, '{"jb": true}', 'csv') returning id into v_a;
  insert into b2c.exports (user_id, params, format) values (c_admin, '{"jb": true}', 'csv') returning id into v_b;
  j := b2c.export_take(100000);
  perform b2c.export_done(v_b, 5, c_admin || '/jb.csv', null);
  n := b2c.job_release('exports', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('exports_released', pg_temp.took(j, 'id', v_a) and n = 1
    and (select status = 'queued' and attempts = 0 from b2c.exports where id = v_a)
    and (select status = 'ready' and attempts = 1 from b2c.exports where id = v_b), n::text);
  j := b2c.export_take(100000);
  insert into r (name, ok, detail) values ('exports_due_again_one_attempt', pg_temp.took(j, 'id', v_a)
    and (select status = 'running' and attempts = 1 from b2c.exports where id = v_a), null);

  -- ---------- 1d. files students sent on WhatsApp ----------
  insert into b2c.wa_messages (phone, lead_id, direction, kind, media, status) values ('910000995601', 995601, 'in', 'media', '{"id": "jb-m1", "type": "image"}', 'received') returning id into v_a;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, media, status) values ('910000995601', 995601, 'in', 'media', '{"id": "jb-m2", "type": "image"}', 'received') returning id into v_b;
  j := b2c.wa_media_take(100000);
  perform b2c.wa_media_stored(v_b, 'leads/995601/wa/' || v_b || '-jb.jpg', null);
  n := b2c.job_release('wa_media', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('wa_media_released', pg_temp.took(j, 'id', v_a) and n = 1
    and (select media_tries = 0 and media_path is null from b2c.wa_messages where id = v_a)
    and (select media_tries = 1 and media_path is not null from b2c.wa_messages where id = v_b)
    and pg_temp.took(b2c.wa_media_take(100000), 'id', v_a), n::text);

  -- ---------- 1e. phone alerts ----------
  update b2c.users set push_subscription = '[{"endpoint": "https://push.example/jb", "keys": {"p256dh": "jb", "auth": "jb"}}]' where user_id = c_asha;
  insert into b2c.notifications (user_id, kind, title) values (c_asha, 'jb', 'jb not started') returning id into v_a;
  insert into b2c.notifications (user_id, kind, title, pushed_at) values (c_asha, 'jb', 'jb pushed long ago', now() - interval '20 minutes') returning id into v_b;
  j := b2c.push_take(100000);
  n := b2c.job_release('push', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('push_released', pg_temp.took(j, 'id', v_a) and not pg_temp.took(j, 'id', v_b) and n = 1
    and (select pushed_at is null from b2c.notifications where id = v_a) and (select pushed_at is not null from b2c.notifications where id = v_b)
    and pg_temp.took(b2c.push_take(100000), 'id', v_a), n::text);

  -- ---------- 1f. support mail ----------
  insert into b2c.settings as s (key, value) values ('support', '{"developer_emails": ["dev.jb@example.com"], "mailbox": null, "auto_close_days": 7}')
  on conflict (key) do update set value = s.value || '{"developer_emails": ["dev.jb@example.com"]}';
  insert into b2c.support_tickets (created_by, kind, subject) values (c_asha, 'other', 'jb ticket') returning id into v_c;
  insert into b2c.support_messages (ticket_id, author_kind, author_id, body, to_developer, source) values (v_c, 'user', c_asha, 'jb not started', true, 'crm') returning id into v_a;
  insert into b2c.support_messages (ticket_id, author_kind, author_id, body, to_developer, source) values (v_c, 'user', c_asha, 'jb mailed', true, 'crm') returning id into v_b;
  j := b2c.support_mail_take(100000);
  perform b2c.support_mail_done(v_b, null);
  n := b2c.job_release('support_mail', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('support_mail_released', pg_temp.took(j, 'message_id', v_a) and n = 1
    and (select mail_attempts = 0 and mailed_at is null from b2c.support_messages where id = v_a)
    and (select mail_attempts = 1 and mailed_at is not null from b2c.support_messages where id = v_b)
    and pg_temp.took(b2c.support_mail_take(100000), 'message_id', v_a), n::text);

  -- ---------- 1g. call recordings ----------
  insert into b2c.calls (lead_id, user_id, provider, number, recording_url, recording_status) values (995601, c_asha, 'mock', '910000995601', 'mock://recording/jb-1', 'pending') returning id into v_a;
  insert into b2c.calls (lead_id, user_id, provider, number, recording_url, recording_status) values (995601, c_asha, 'mock', '910000995601', 'mock://recording/jb-2', 'pending') returning id into v_b;
  j := b2c.recordings_take(100000);
  perform b2c.recording_saved(v_b, 'leads/995601/calls/jb-2.mp3', null);
  n := b2c.job_release('recordings', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('recordings_released', pg_temp.took(j, 'id', v_a) and n = 1
    and (select recording_attempts = 0 and recording_status = 'pending' from b2c.calls where id = v_a)
    and (select recording_attempts = 1 and recording_status = 'stored' from b2c.calls where id = v_b)
    and pg_temp.took(b2c.recordings_take(100000), 'id', v_a), n::text);

  -- ---------- 1h. follow-ups for Google Calendar ----------
  insert into b2c.tasks (lead_id, owner_id, kind, title, due_at) values (995601, c_asha, 'followup', 'jb follow-up', now() + interval '2 days') returning id into v_task;
  insert into b2c.calendar_events (task_id, user_id, want) values (v_task, c_asha, 'upsert') on conflict (task_id) do nothing;
  select to_jsonb(c) into v_before from b2c.calendar_events c where task_id = v_task;
  j := b2c.calendar_take(100000);
  n := b2c.job_release('calendar', array[v_task]);
  insert into r (name, ok, detail) values ('calendar_released_as_it_was', pg_temp.took(j, 'task_id', v_task) and n = 1
    and (select to_jsonb(c) from b2c.calendar_events c where task_id = v_task) = v_before
    and pg_temp.took(b2c.calendar_take(100000), 'task_id', v_task), n::text);
  perform b2c.calendar_done(v_task, 'jb-event', 'jb-etag', null);
  n := b2c.job_release('calendar', array[v_task]);
  insert into r (name, ok, detail) values ('calendar_synced_row_left_alone', n = 0 and (select state = 'synced' and attempts = 0 from b2c.calendar_events where task_id = v_task), n::text);

  -- ---------- 1i. alert emails ----------
  insert into b2c.metric_alerts (user_id, name, metric, kind, op, threshold) values (c_admin, 'jb alert', 'handoffs', 'threshold', 'above', 1) returning id into v_c;
  insert into b2c.alert_events (alert_id, value, email) values (v_c, 5, true) returning id into v_a;
  insert into b2c.alert_events (alert_id, value, email, emailed_at) values (v_c, 6, true, now() - interval '20 minutes') returning id into v_b;
  j := b2c.alert_emails_take(100000);
  n := b2c.job_release('alert_emails', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('alert_emails_released', exists (select 1 from jsonb_array_elements(j) x where (x -> 'event' ->> 'id')::bigint = v_a) and n = 1
    and (select emailed_at is null from b2c.alert_events where id = v_a) and (select emailed_at is not null from b2c.alert_events where id = v_b)
    and exists (select 1 from jsonb_array_elements(b2c.alert_emails_take(100000)) x where (x -> 'event' ->> 'id')::bigint = v_a), n::text);

  -- ---------- 1j. scheduled dashboards ----------
  insert into b2c.dashboards (name, owner_id) values ('jb dashboard', c_admin) returning id into v_dash;
  insert into b2c.dashboard_schedules (dashboard_id, user_id, freq, format, hour_ist, next_at) values (v_dash, c_admin, 'daily', 'csv', 8, now() - interval '1 minute') returning id into v_a;
  insert into b2c.dashboard_schedules (dashboard_id, user_id, freq, format, hour_ist, next_at) values (v_dash, c_admin, 'daily', 'csv', 9, now() - interval '1 minute') returning id into v_b;
  j := b2c.schedules_take(100000);
  perform b2c.schedule_done(v_b, null);
  select next_at into t0 from b2c.dashboard_schedules where id = v_b;
  n := b2c.job_release('schedules', array[v_a, v_b]);
  insert into r (name, ok, detail) values ('schedules_released', exists (select 1 from jsonb_array_elements(j) x where (x -> 'schedule' ->> 'id')::bigint = v_a) and n = 1
    and (select next_at <= now() and last_sent_at is null from b2c.dashboard_schedules where id = v_a)
    and (select next_at = t0 and next_at > now() and last_sent_at is not null from b2c.dashboard_schedules where id = v_b), n::text);
  j := b2c.schedules_take(100000);
  insert into r (name, ok, detail) values ('schedules_due_again_then_moved_on', exists (select 1 from jsonb_array_elements(j) x where (x -> 'schedule' ->> 'id')::bigint = v_a)
    and not exists (select 1 from jsonb_array_elements(j) x where (x -> 'schedule' ->> 'id')::bigint = v_b)
    and (select next_at > now() from b2c.dashboard_schedules where id = v_a), null);

  -- ---------- 1k. briefs before a call ----------
  update b2c.leads_state set is_test = false where lead_id = 995602;   -- the job writes briefs for real leads only; rolled back with the rest
  insert into b2c.tasks (lead_id, owner_id, kind, title, due_at) values (995602, c_asha, 'call', 'jb call', now() + interval '10 minutes');
  j := to_jsonb(b2c.brief_due_take(100000));
  n := b2c.job_release('briefs', array[995602]);
  insert into r (name, ok, detail) values ('briefs_released', pg_temp.took(j, null, 995602) and n = 1
    and (select attempted_at is null from b2c.lead_briefs where lead_id = 995602)
    and pg_temp.took(to_jsonb(b2c.brief_due_take(100000)), null, 995602), n::text);
  update b2c.lead_briefs set attempted_at = now() - interval '20 minutes' where lead_id = 995602;
  n := b2c.job_release('briefs', array[995602]);
  insert into r (name, ok, detail) values ('briefs_old_attempt_left_alone', n = 0 and (select attempted_at is not null from b2c.lead_briefs where lead_id = 995602), n::text);
  update b2c.leads_state set is_test = true where lead_id = 995602;

  -- ---------- 1l. nothing to release, and a kind that does not exist ----------
  insert into r (name, ok, detail) values ('release_nothing', b2c.job_release('push', '{}') = 0 and b2c.job_release('outbox', null) = 0, null);
  begin
    perform b2c.job_release('send_queue', array[1]);
    insert into r (name, ok, detail) values ('release_unknown_kind_refused', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('release_unknown_kind_refused', sqlstate = '22023' and sqlerrm like 'job_release: unknown kind%', sqlerrm);
  end;

  -- ---------- 2. a message Meta refuses for good: failed at once, the reason kept, never queued again ----------
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, purpose)
  values ('910000995601', 995601, 'out', 'text', 'jb outside the window', 'queued', 'sales') returning id into v_wa;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose, not_before)
  values ('whatsapp', 995601, '910000995601', v_wa, '{"type": "text", "text": "jb outside the window"}', 'sales', now() - interval '1 minute') returning id into v_a;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, not_before)
  values ('whatsapp', 995601, '910000995601', '{"type": "text", "text": "jb rate limited"}', 'sales', now() - interval '1 minute') returning id into v_b;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, not_before)
  values ('whatsapp', 995601, '910000995601', '{"type": "text", "text": "jb token expired"}', 'sales', now() - interval '1 minute') returning id into v_c;
  j := b2c.send_take(100000);
  e := 'WhatsApp refused it: more than 24 hours have passed since the student last wrote, so only an approved template can be sent. It is not sent again automatically. (131047: Re-engagement message)';
  n := b2c.send_done(jsonb_build_array(
         jsonb_build_object('id', v_a, 'ok', false, 'dry_run', false, 'retry', false, 'error', e),
         jsonb_build_object('id', v_b, 'ok', false, 'dry_run', false, 'error', '130429: Rate limit hit'),
         jsonb_build_object('id', v_c, 'ok', false, 'dry_run', false, 'error', 'WhatsApp refused Spark''s connection, not this message: the access token has expired or is no longer valid. (190: Session has expired)')));
  select * into q from b2c.send_queue where id = v_a;
  insert into r (name, ok, detail) values ('refused_message_failed_on_first_attempt',
    pg_temp.took(j, 'id', v_a) and n = 3 and q.status = 'failed' and q.attempts = 1 and q.error = e and q.sent_at is null, row_to_json(q)::text);
  insert into r (name, ok, detail) values ('refused_message_reason_on_the_conversation',
    (select status = 'failed' and error = e from b2c.wa_messages where id = v_wa), null);
  insert into r (name, ok, detail) values ('refused_message_admins_told_with_reason',
    (select count(*) from b2c.notifications where user_id = c_admin and kind = 'send_failed' and dedupe_key = 'sendfail:' || v_a and body = e) = 1, null);
  insert into r (name, ok, detail) values ('rate_limit_and_refused_token_tried_again',
    (select bool_and(status = 'queued' and attempts = 1 and not_before > now() and error is not null) from b2c.send_queue where id in (v_b, v_c))
    and not exists (select 1 from b2c.notifications where kind = 'send_failed' and dedupe_key in ('sendfail:' || v_b, 'sendfail:' || v_c)), null);
  update b2c.send_queue set not_before = now() - interval '1 minute' where id in (v_a, v_b, v_c);
  j := b2c.send_take(100000);
  insert into r (name, ok, detail) values ('refused_message_never_taken_again',
    not pg_temp.took(j, 'id', v_a) and pg_temp.took(j, 'id', v_b) and pg_temp.took(j, 'id', v_c) and (select status from b2c.send_queue where id = v_a) = 'failed', null);
  -- messages the job held back when Meta refused the connection go back with send_release, the attempt not counted
  n := b2c.send_release(array[v_b, v_c]);
  insert into r (name, ok, detail) values ('held_messages_released_uncounted',
    n = 2 and (select bool_and(status = 'queued' and attempts = 1) from b2c.send_queue where id in (v_b, v_c)), n::text);
end $t$;

insert into r (name, ok, detail)
select 'grants', bool_and(ok), string_agg(detail, '; ') filter (where not ok)
  from (select has_function_privilege('service_role', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
               and not has_function_privilege('anon', f, 'execute') and not has_function_privilege('public', f, 'execute') as ok, f as detail
          from unnest(array['b2c.job_release(text,bigint[])', 'b2c.send_release(bigint[])', 'b2c.send_done(jsonb)', 'b2c.send_take(integer)']) f) x;
insert into r (name, ok, detail)
select 'job_release_definer_with_empty_search_path', p.prosecdef and p.proconfig @> array['search_path=""'], p.proconfig::text
  from pg_proc p where p.oid = 'b2c.job_release(text,bigint[])'::regprocedure;
insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

do $z$
declare f text;
begin
  select string_agg(n || ' ' || name || ': ' || coalesce(detail, ''), ' | ' order by n) into f from r where not ok;
  raise exception 'TESTRESULT total=% failed=% %', (select count(*) from r), (select count(*) from r where not ok), coalesce(f, '');
end $z$;
