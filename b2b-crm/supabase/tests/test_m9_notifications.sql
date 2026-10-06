-- M9 student notifications, on STAGING. Three transactions, each rolled back. pg_net only sends after commit, so
-- nothing leaves the database: provider answers are written straight into net._http_response and notify_tick()
-- reads them as if the provider had answered. Every row of each final select must say ok = true.
-- Not covered here (run by hand once templates may be activated): b2b.notify_accepted's queue and skip rules.

-- 1. Sender: request shapes, answers, one retry then failed and alerted, switch off cancels
begin;
create temp table r (name text, ok boolean, detail text);
do $t$
declare w uuid; e uuid; a1 b2b.allocations; a2 b2b.allocations;
begin
  w := vault.create_secret('test-token', 'b2b_test_wa_' || txid_current(), 'rolled back');
  e := vault.create_secret('test-key', 'b2b_test_mail_' || txid_current(), 'rolled back');
  update b2b.settings set value = value || jsonb_build_object('support_contact', '+91 98100 00000', 'retry_after_minutes', 1,
      'whatsapp', value -> 'whatsapp' || jsonb_build_object('phone_number_id', '123456789012', 'token_secret_id', w, 'base_url', 'https://mock.invalid/notify'),
      'email', value -> 'email' || jsonb_build_object('from_email', 'hello@eduwit.in', 'reply_to', 'support@eduwit.in', 'api_key_secret_id', e, 'base_url', 'https://mock.invalid/notify'))
   where key = 'notifications';
  update b2b.live_switches set live = true where scope in ('whatsapp', 'email');
  select * into a1 from b2b.allocations where status = 'accepted' order by id limit 1;
  select * into a2 from b2b.allocations where status = 'accepted' and id > a1.id order by id limit 1;
  insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, template_id, language, variables, recipient, status, scheduled_for)
  select a.lead_id, a.id, a.partner_id, 'accepted', c.ch, (select id from b2b.message_templates where channel = c.ch and language = 'en'), 'en',
         jsonb_build_object('student_first_name', 'Ravi', 'programme_label', 'BBA', 'partner_display_name', 'Sync Edu', 'expected_contact_window', 'today', 'eduwit_support_contact', '+91 98100 00000'),
         case when a.id = a1.id then (case c.ch when 'whatsapp' then '919876543270' else 'n1@example.com' end)
              else (case c.ch when 'whatsapp' then '919876543299' else 'fail.n3@example.com' end) end,
         'scheduled', now() - interval '1 second'
    from b2b.allocations a, (values ('whatsapp'), ('email')) c(ch) where a.id in (a1.id, a2.id);
  perform set_config('t.ok', a1.id::text, true);
end $t$;

insert into r select 'tick1', (t ->> 'sent')::int = 4, t::text from (select b2b.notify_tick() t) x;
insert into r select 'wa_request', q.url = 'https://mock.invalid/notify/v21.0/123456789012/messages' and q.headers ->> 'Authorization' = 'Bearer test-token'
    and convert_from(q.body, 'utf8')::jsonb #>> '{template,name}' = 'eduwit_partner_assigned'
    and jsonb_array_length(convert_from(q.body, 'utf8')::jsonb #> '{template,components,0,parameters}') = 5, left(convert_from(q.body, 'utf8'), 300)
  from b2b.student_notifications n join net.http_request_queue q on q.id = n.net_request_id where n.allocation_id = current_setting('t.ok')::bigint and n.channel = 'whatsapp';
insert into r select 'email_request', q.url = 'https://mock.invalid/notify/emails' and q.headers ->> 'Idempotency-Key' = 'notify-' || n.id
    and convert_from(q.body, 'utf8')::jsonb ->> 'from' = 'Team Eduwit <hello@eduwit.in>' and convert_from(q.body, 'utf8')::jsonb ->> 'html' like '%Unsubscribe%',
  convert_from(q.body, 'utf8')::jsonb ->> 'subject'
  from b2b.student_notifications n join net.http_request_queue q on q.id = n.net_request_id where n.allocation_id = current_setting('t.ok')::bigint and n.channel = 'email';
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select n.net_request_id, case when n.allocation_id = current_setting('t.ok')::bigint then 200 else 500 end, 'application/json',
       case when n.allocation_id = current_setting('t.ok')::bigint then '{"messages":[{"id":"wamid.TEST"}],"id":"em_TEST"}' else '{"error":{"message":"provider error"}}' end, false, null, now()
  from b2b.student_notifications n where n.status = 'sending';
insert into r select 'tick2', (t ->> 'answers')::int = 4, t::text from (select b2b.notify_tick() t) x;
insert into r select 'sent', count(*) = 2 and bool_and(provider_message_id in ('wamid.TEST', 'em_TEST')), string_agg(channel || ':' || provider_message_id, ' ')
  from b2b.student_notifications where allocation_id = current_setting('t.ok')::bigint and status = 'sent';
insert into r select 'retry_scheduled', count(*) = 2 and bool_and(error like 'HTTP 500: provider error%' and scheduled_for > now()), max(error)
  from b2b.student_notifications where allocation_id <> current_setting('t.ok')::bigint and status = 'scheduled';
update b2b.student_notifications set scheduled_for = now() - interval '1 second' where status = 'scheduled';
insert into r select 'tick3', (t ->> 'sent')::int = 2, t::text from (select b2b.notify_tick() t) x;
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select n.net_request_id, 500, 'application/json', '{"error":{"message":"provider error"}}', false, null, now() from b2b.student_notifications n where n.status = 'sending';
insert into r select 'tick4', (t ->> 'answers')::int = 2, t::text from (select b2b.notify_tick() t) x;
insert into r select 'failed_after_retry', count(*) = 2 and bool_and(attempts = 2), string_agg(channel || ':' || attempts, ' ')
  from b2b.student_notifications where status = 'failed';
insert into r select 'failure_alerted', count(*) = 2, null from b2b.events where type = 'alert.notification_failed' and occurred_at = now();
update b2b.student_notifications set status = 'scheduled', scheduled_for = now() - interval '1 second', attempts = 0 where status = 'failed' and channel = 'email';
update b2b.live_switches set live = false where scope = 'email';
insert into r select 'switch_off_tick', true, b2b.notify_tick()::text;
insert into r select 'switch_off_cancels', count(*) = 1, max(error) from b2b.student_notifications where channel = 'email' and status = 'cancelled' and error = 'email is switched off';
select name, ok, left(detail, 200) detail from r order by ok, name;
rollback;

-- 2. Admin: template and settings validation
begin;
create temp table r (name text, ok boolean, detail text);
grant all on r to authenticated, anon;
-- an accepted allocation; the student has an email, the partner has notifications on
create temp table t0 as select a.id alloc, a.lead_id, a.partner_id from b2b.allocations a where a.status = 'accepted' order by a.id desc limit 1;
grant all on t0 to authenticated;
update b2b.partners set notify_enabled = true where id = (select partner_id from t0);
update public.student_leads set email_id = 'n9@example.com', preferred_language = 'Hinglish' where id = (select lead_id from t0);

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'notify-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'notify-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"notify-admin@test.local"}', true);
do $t$
declare j jsonb; o jsonb; tid bigint;
begin
  select id into tid from b2b.message_templates where channel = 'email' and language = 'hi';
  begin perform b2b.template_save(jsonb_build_object('id', tid, 'subject', 'Hello', 'body', 'Hi {{student_first_name}}, {{fee}} is due. Thanks for asking.'));
        insert into r values ('template_unknown_variable', false, 'saved');
  exception when others then insert into r values ('template_unknown_variable', sqlerrm like 'unknown variable: fee%', sqlerrm); end;
  begin perform b2b.template_save(jsonb_build_object('id', (select id from b2b.message_templates where channel = 'whatsapp' and language = 'hi'),
          'body', 'Hi {{student_first_name}}, a counsellor will call you soon.', 'wa_template', '', 'status', 'active'));
        insert into r values ('wa_activate_keeps_name', true, 'kept the stored name');
  exception when others then insert into r values ('wa_activate_keeps_name', false, sqlerrm); end;
  j := b2b.template_save(jsonb_build_object('id', tid, 'subject', 'Aapke counsellor {{partner_display_name}} se',
         'body', 'Hi {{student_first_name}}, {{partner_display_name}} aapko {{expected_contact_window}} call karenge.', 'status', 'active'));
  insert into r values ('template_saved', (j ->> 'version')::int = 2 and j ->> 'status' = 'active' and j ->> 'updated_by' is not null, j ->> 'subject');

  begin perform b2b.notification_settings_save(jsonb_build_object('quiet_start', '21:00', 'quiet_end', '08:00', 'support_contact', 'support@eduwit.in'), 'test');
        insert into r values ('settings_bad_hours', false, 'saved');
  exception when others then insert into r values ('settings_bad_hours', sqlerrm like 'quiet hours%', sqlerrm); end;
  begin perform b2b.notification_settings_save(jsonb_build_object('quiet_start', '08:00', 'quiet_end', '21:00', 'support_contact', 'x'), 'test');
        insert into r values ('settings_needs_support', false, 'saved');
  exception when others then insert into r values ('settings_needs_support', sqlerrm like 'give a staffed%', sqlerrm); end;
  j := b2b.notification_settings_save(jsonb_build_object('quiet_start', '09:00', 'quiet_end', '20:00', 'support_contact', 'support@eduwit.in',
         'whatsapp', jsonb_build_object('phone_number_id', '123456789012', 'token', 'wa-secret'),
         'email', jsonb_build_object('provider', 'brevo', 'from_email', 'Hello@Eduwit.in', 'api_key', 'mail-secret')), 'test');
  o := b2b.notifications_overview();
  insert into r values ('settings_saved_secrets_hidden', o -> 'settings' ->> 'quiet_start' = '09:00' and o -> 'settings' -> 'email' ->> 'from_email' = 'hello@eduwit.in'
                        and (o -> 'settings' -> 'whatsapp' ->> 'has_token')::boolean and (o -> 'settings' -> 'email' ->> 'has_key')::boolean
                        and o::text not like '%secret_id%' and o::text not like '%wa-secret%', (o -> 'settings')::text);
end $t$;
reset role;
insert into r select 'vault_stored', b2b.partner_secret(((value -> 'whatsapp' ->> 'token_secret_id'))::uuid) = 'wa-secret', null from b2b.settings where key = 'notifications';

-- queued on acceptance: email in Hindi (active), WhatsApp Hindi (active, kept name)
insert into r select 'notify_accepted', b2b.notify_accepted((select alloc from t0)) = 2, null;
insert into r select 'queued_rows', count(*) = 2 and bool_and(status = 'scheduled' and language = 'hi'), string_agg(channel || ':' || status || ':' || language || ':' || coalesce(recipient, '-'), ' ')
  from b2b.student_notifications where allocation_id = (select alloc from t0);
insert into r select 'slot_in_quiet_hours', bool_and((scheduled_for at time zone 'Asia/Kolkata')::time between '09:00' and '20:00'), min(scheduled_for)::text
  from b2b.student_notifications where allocation_id = (select alloc from t0);
insert into r select 'idempotent', b2b.notify_accepted((select alloc from t0)) = 0, null;
-- a test phone is never queued
update public.student_leads set whatsapp_number = '919000000071' where id = (select lead_id from t0);
delete from b2b.student_notifications where allocation_id = (select alloc from t0);
insert into r select 'test_lead_skipped', b2b.notify_accepted((select alloc from t0)) = 0
   and (select bool_and(status = 'skipped' and error like 'test lead%') from b2b.student_notifications where allocation_id = (select alloc from t0)), null;
-- the Admin can send a cancelled message again
update b2b.student_notifications set status = 'cancelled' where allocation_id = (select alloc from t0) and channel = 'email';
set local role authenticated;
do $t$ declare nid bigint; begin
  select id into nid from b2b.student_notifications where allocation_id = (select alloc from t0) and channel = 'email';
  perform b2b.notification_retry(nid);
  insert into r select 'retry_requeued', status = 'scheduled' and attempts = 1, status from b2b.student_notifications where id = nid;
  begin perform b2b.notification_retry(nid); insert into r values ('retry_only_failed', false, 'ran');
  exception when others then insert into r values ('retry_only_failed', sqlerrm like 'only a failed%', sqlerrm); end;
  begin perform b2b.notify_tick(); insert into r values ('tick_not_for_admins', false, 'ran');
  exception when others then insert into r values ('tick_not_for_admins', sqlstate = '42501', sqlerrm); end;
end $t$;
reset role;
set local role anon;
do $t$ begin
  begin perform b2b.notifications_overview(); insert into r values ('anon_blocked', false, 'ran');
  exception when others then insert into r values ('anon_blocked', sqlstate = '42501', sqlerrm); end;
end $t$;
reset role;
select name, ok, left(detail, 200) detail from r order by ok, name;
rollback;

-- 3. Admin: settings with secrets go to Vault and are never returned
begin;
create temp table r (name text, ok boolean, detail text);
grant all on r to authenticated, anon;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'notify-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'notify-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"notify-admin@test.local"}', true);
do $t$
declare j jsonb; o jsonb; tid bigint;
begin
  select id into tid from b2b.message_templates where channel = 'email' and language = 'hi';
  begin perform b2b.template_save(jsonb_build_object('id', tid, 'subject', 'Hello', 'body', 'Hi {{student_first_name}}, {{fee}} is due. Thanks for asking.'));
        insert into r values ('template_unknown_variable', false, 'saved');
  exception when others then insert into r values ('template_unknown_variable', sqlerrm like 'unknown variable: fee%', sqlerrm); end;
  j := b2b.template_save(jsonb_build_object('id', tid, 'subject', 'Aapke counsellor {{partner_display_name}} se',
         'body', 'Hi {{student_first_name}}, {{partner_display_name}} aapko {{expected_contact_window}} call karenge.', 'status', 'draft'));
  insert into r values ('template_saved', (j ->> 'version')::int = 2 and j ->> 'updated_by' is not null, j ->> 'subject');
  begin perform b2b.notification_settings_save(jsonb_build_object('quiet_start', '21:00', 'quiet_end', '08:00', 'support_contact', 'support@eduwit.in'), 'test');
        insert into r values ('settings_bad_hours', false, 'saved');
  exception when others then insert into r values ('settings_bad_hours', sqlerrm like 'quiet hours%', sqlerrm); end;
  begin perform b2b.notification_settings_save(jsonb_build_object('quiet_start', '08:00', 'quiet_end', '21:00', 'support_contact', 'x'), 'test');
        insert into r values ('settings_needs_support', false, 'saved');
  exception when others then insert into r values ('settings_needs_support', sqlerrm like 'give a staffed%', sqlerrm); end;
end $t$;
reset role;
select name, ok, left(detail, 200) detail from r order by ok, name;
rollback;

