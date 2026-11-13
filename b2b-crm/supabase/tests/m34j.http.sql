-- M34j unsubscribe links: the check to send through an HTTP SQL API (one request, no psql).
-- Send migrations/m34j_unsubscribe.sql followed by this file as ONE request, with no begin or commit added: a request of
-- several statements is one transaction, and this file is a single statement that always ends with
--     ERROR: TESTRESULT total=<checks> failed=<failed> <the failed checks, or "all passed">
-- so the answer is visible and the whole request rolls back, the migration included; nothing is left behind. (An API that
-- commits each statement on its own would keep the migration: where that is not known, send a harmless pair first, e.g.
-- "create table public.zz_probe (); select 1/0;", and see that the table is not there.) Where m34j is already applied,
-- send this file alone.
-- It never runs the sender (notify_tick, notify_accepted) and queues no HTTP request: the provider request is only built
-- (notify_request) and read; the last check counts pg_net's queue. Its rows are test rows (is_test leads with test phone
-- numbers, an is_test allocation each, a "ZZ M34j" partner still onboarding, messages due in ten years) and its settings
-- changes (a made-up web address and provider, raised limits) live only inside the rolled-back transaction. No token, link,
-- key or address is printed. A step that fails unexpectedly is reported the same way: total=0 failed=1 stopped by <error>.
-- The fuller suite, with the sender, is tests/test_m34j_unsubscribe.sql (local-test.sh).
do $m34j$
declare
  v_total int := 0; v_failed int := 1; v_detail text;
  k text; v_p bigint; l1 bigint; l2 bigint; u bigint; a1 bigint; a2 bigint; n1m bigint; n1w bigint; n2m bigint;
  t1 text; t2 text; wrong text; lk1 text; lk2 text; x boolean[]; y boolean; z boolean; c0 int; c1 int; q0 bigint; q1 bigint;
  w uuid; e uuid; msg b2b.student_notifications; tpl b2b.message_templates; rq jsonb; b jsonb; body_text text; h text; err text; out text := '';
  f text;
begin
  create temp table zz_m34j_check (seq serial, name text, ok boolean, detail text) on commit drop;
  begin
    select count(*) into q0 from net.http_request_queue;
    select decrypted_secret into k from vault.decrypted_secrets where name = 'b2b_unsubscribe_key';
    insert into zz_m34j_check (name, ok) values ('key_in_vault', coalesce(k ~ '^[0-9a-f]{64}$', false)
      and (select count(*) = 1 from vault.secrets where name = 'b2b_unsubscribe_key'));

    -- ---------- test rows and settings (this transaction only) ----------
    perform set_config('b2b.actor', 'system', true);
    insert into b2b.partners (slug, name, display_name, status) values ('zz-m34j-http', 'ZZ M34j HTTP test (rolled back)', 'ZZ M34j', 'onboarding')
    returning id into v_p;
    insert into public.student_leads (whatsapp_number, student_name, email_id, is_test) values ('910000347001', 'ZZ M34j test one', 'zz-m34j-1@example.invalid', true)
    returning id into l1;
    insert into public.student_leads (whatsapp_number, student_name, email_id, is_test) values ('910000347002', 'ZZ M34j test two', 'zz-m34j-2@example.invalid', true)
    returning id into l2;
    select max(id) + 987654321 into u from public.student_leads;   -- a lead id that does not exist
    insert into b2b.allocations (lead_id, destination_type, partner_id, status, mode, push_attempts, is_test) values (l1, 'partner', v_p, 'queued', 'manual', 0, true)
    returning id into a1;
    insert into b2b.allocations (lead_id, destination_type, partner_id, status, mode, push_attempts, is_test) values (l2, 'partner', v_p, 'queued', 'manual', 0, true)
    returning id into a2;
    w := vault.create_secret('zz-m34j-wa-token', 'zz_m34j_http_wa_' || txid_current(), 'rolled back');
    e := vault.create_secret('zz-m34j-mail-key', 'zz_m34j_http_mail_' || txid_current(), 'rolled back');
    insert into b2b.settings (key, value) values ('notifications', '{}') on conflict (key) do nothing;
    update b2b.settings set value = (value - 'site_url' - 'unsubscribe_url') || jsonb_build_object('support_contact', '+91 00000 00000',
        'whatsapp', coalesce(value -> 'whatsapp', '{}') || jsonb_build_object('phone_number_id', '123456789012', 'token_secret_id', w, 'api_version', 'v21.0',
                                                                             'base_url', 'https://api.zz-m34j.example.invalid/wa'),
        'email', coalesce(value -> 'email', '{}') || jsonb_build_object('provider', 'resend', 'from_email', 'hello@zz-m34j.example.invalid', 'from_name', 'Team Eduwit',
                                                                        'reply_to', null, 'api_key_secret_id', e, 'base_url', 'https://api.zz-m34j.example.invalid/mail'))
     where key = 'notifications';
    insert into b2b.settings (key, value) values ('api_limits', '{}') on conflict (key) do nothing;
    update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 100000, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';
    update b2b.message_templates set wa_template = coalesce(wa_template, 'zz_m34j_template') where kind = 'accepted' and channel = 'whatsapp' and language = 'en';
    insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, template_id, language, variables, recipient, status, scheduled_for)
    select x.lead_id, x.alloc, v_p, 'zz_m34j_test', x.ch, (select id from b2b.message_templates where kind = 'accepted' and channel = x.ch and language = 'en'), 'en',
           jsonb_build_object('student_first_name', 'Test', 'programme_label', 'ZZ M34j', 'partner_display_name', 'ZZ M34j', 'expected_contact_window', 'today',
                              'eduwit_support_contact', '+91 00000 00000'),
           case x.ch when 'whatsapp' then '910000347001' else 'zz-m34j@example.invalid' end, 'scheduled', now() + interval '10 years'
      from (values (l1, a1, 'email'), (l1, a1, 'whatsapp'), (l2, a2, 'email')) x(lead_id, alloc, ch);
    select id into n1m from b2b.student_notifications where allocation_id = a1 and channel = 'email';
    select id into n1w from b2b.student_notifications where allocation_id = a1 and channel = 'whatsapp';
    select id into n2m from b2b.student_notifications where allocation_id = a2 and channel = 'email';

    -- ---------- the token and the link ----------
    t1 := b2b.unsubscribe_token(l1); t2 := b2b.unsubscribe_token(l2);
    insert into zz_m34j_check (name, ok) values
      ('token_shape_and_stable', coalesce(t1 ~ '^[0-9a-f]{40}$' and t1 = b2b.unsubscribe_token(l1, 'email'), false)),
      ('token_differs_per_lead', coalesce(t1 <> t2, false)),
      ('token_differs_per_channel', coalesce(t1 <> b2b.unsubscribe_token(l1, 'whatsapp'), false)),
      ('link_null_without_site_url', b2b.unsubscribe_link(l1) is null);
    update b2b.settings set value = value || '{"site_url": "https://crm.zz-m34j.example.invalid/"}' where key = 'notifications';
    lk1 := b2b.unsubscribe_link(l1); lk2 := b2b.unsubscribe_link(l2);
    insert into zz_m34j_check (name, ok) values
      ('link_shape', coalesce(lk1 = 'https://crm.zz-m34j.example.invalid/u/' || l1 || '/' || t1 and lk2 = 'https://crm.zz-m34j.example.invalid/u/' || l2 || '/' || t2, false));

    -- ---------- the opt-out ----------
    wrong := case when left(t1, 1) = '0' then '1' else '0' end || substr(t1, 2);
    x := array[
      b2b.unsubscribe(l1, wrong, 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, left(t1, 39), 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, t1 || '0', 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, '', 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, null, 'email', '203.0.113.2', 'one_click'),
      b2b.unsubscribe(l1, t2, 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, b2b.unsubscribe_token(l1, 'whatsapp'), 'email', '203.0.113.2', 'link'),
      b2b.unsubscribe(l1, b2b.unsubscribe_token(l1, 'whatsapp'), 'whatsapp', '203.0.113.2', 'link'),
      b2b.unsubscribe(null, t1, 'email', '203.0.113.2', 'link')];
    insert into zz_m34j_check (name, ok) values
      ('wrong_tokens_refused', not (true = any (x)) and array_position(x, null) is null),
      ('refused_changes_nothing', (select coalesce(opted_out_channels, '{}') = '{}' and not is_opted_out from public.student_leads where id = l1)
         and not exists (select 1 from b2b.events where lead_id = l1 and type = 'lead.unsubscribed')
         and (select status = 'scheduled' from b2b.student_notifications where id = n1m));
    select coalesce(sum(n), 0) into c0 from b2b.unsubscribe_usage where bucket in ('lead:' || l1, 'lead:' || u);
    y := b2b.unsubscribe(u, wrong, 'email', '203.0.113.2', 'link');
    z := b2b.unsubscribe(l1, wrong, 'email', '203.0.113.2', 'link');
    select coalesce(sum(n), 0) into c1 from b2b.unsubscribe_usage where bucket in ('lead:' || l1, 'lead:' || u);
    insert into zz_m34j_check (name, ok) values
      ('unknown_lead_same_as_wrong_token', y is false and z is false and c1 = c0 + 2 and not exists (select 1 from b2b.events where lead_id = u));

    y := b2b.unsubscribe(l1, t1, 'email', '203.0.113.2', 'link');
    insert into zz_m34j_check (name, ok, detail) values
      ('own_token_accepted', y is true, null),
      ('opt_out_recorded_email_only', (select opted_out_channels = array['email'] and not is_opted_out from public.student_leads where id = l1), null),
      ('due_email_cancelled', (select status = 'cancelled' and error = 'student opted out of email (unsubscribe link)' from b2b.student_notifications where id = n1m),
         (select status from b2b.student_notifications where id = n1m)),
      ('due_whatsapp_untouched', (select status = 'scheduled' and error is null from b2b.student_notifications where id = n1w), null),
      ('other_lead_untouched', (select coalesce(opted_out_channels, '{}') = '{}' from public.student_leads where id = l2)
         and (select status = 'scheduled' from b2b.student_notifications where id = n2m), null),
      ('event_logged', (select count(*) = 1 and bool_and(actor_type = 'student' and payload ->> 'channel' = 'email' and payload ->> 'source' = 'link')
                          from b2b.events where lead_id = l1 and type = 'lead.unsubscribed'), null);
    y := b2b.unsubscribe(l1, t1, 'email', '203.0.113.3', 'one_click');
    insert into zz_m34j_check (name, ok) values
      ('repeat_is_true_and_writes_nothing', y is true and (select count(*) = 1 from b2b.events where lead_id = l1 and type = 'lead.unsubscribed')
         and (select opted_out_channels = array['email'] from public.student_leads where id = l1));

    -- ---------- the provider request (built and read, never sent) ----------
    select * into msg from b2b.student_notifications where id = n2m;
    select * into tpl from b2b.message_templates where id = msg.template_id;
    body_text := b2b.render_template(tpl.body, msg.variables);
    rq := b2b.notify_request(msg); b := rq -> 'body'; out := out || rq::text;
    insert into zz_m34j_check (name, ok) values
      ('resend_headers', coalesce(b -> 'headers' ->> 'List-Unsubscribe' = '<' || lk2 || '/one-click>, <mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe>'
         and b -> 'headers' ->> 'List-Unsubscribe-Post' = 'List-Unsubscribe=One-Click', false)),
      ('resend_footer_and_text', coalesce(b ->> 'html' like '%<a href="' || lk2 || '" style="color:#6b7385">Unsubscribe</a>%'
         and b ->> 'text' = body_text || E'\n\nUnsubscribe: ' || lk2, false)),
      ('resend_request_otherwise_as_before', coalesce(rq ->> 'provider' = 'resend' and rq ->> 'url' = 'https://api.zz-m34j.example.invalid/mail/emails'
         and rq -> 'headers' ->> 'Idempotency-Key' = 'notify-' || msg.id and b -> 'to' = jsonb_build_array(msg.recipient)
         and (select array_agg(key order by key) from jsonb_object_keys(b) key) = array['from', 'headers', 'html', 'subject', 'text', 'to'], false));
    update b2b.settings set value = jsonb_set(jsonb_set(value, '{email,provider}', '"brevo"'), '{email,reply_to}', '"help@zz-m34j.example.invalid"') where key = 'notifications';
    rq := b2b.notify_request(msg); b := rq -> 'body'; out := out || rq::text;
    insert into zz_m34j_check (name, ok) values
      ('brevo_headers_footer_text', coalesce(rq ->> 'provider' = 'brevo'
         and b -> 'headers' ->> 'List-Unsubscribe' = '<' || lk2 || '/one-click>, <mailto:help@zz-m34j.example.invalid?subject=Unsubscribe>'
         and b -> 'headers' ->> 'List-Unsubscribe-Post' = 'List-Unsubscribe=One-Click'
         and b ->> 'htmlContent' like '%<a href="' || lk2 || '"%' and b ->> 'textContent' = body_text || E'\n\nUnsubscribe: ' || lk2, false));
    update b2b.settings set value = jsonb_set(jsonb_set(value, '{email,provider}', '"resend"'), '{email,reply_to}', 'null') - 'site_url' where key = 'notifications';
    rq := b2b.notify_request(msg); b := rq -> 'body'; out := out || rq::text;
    insert into zz_m34j_check (name, ok) values
      ('fallback_without_site_url', coalesce(b -> 'headers' = jsonb_build_object('List-Unsubscribe', '<mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe>')
         and b ->> 'html' like '%<a href="mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe"%' and b ->> 'text' = body_text
         and b::text not like '%crm.zz-m34j.example.invalid%', false));
    update b2b.settings set value = value || '{"site_url": "https://crm.zz-m34j.example.invalid"}' where key = 'notifications';
    select * into msg from b2b.student_notifications where id = n1w;
    rq := b2b.notify_request(msg); out := out || rq::text;
    insert into zz_m34j_check (name, ok, detail) values
      ('whatsapp_request_unchanged', coalesce(rq ->> 'provider' = 'meta_cloud' and not (rq -> 'body' ? 'headers') and rq::text not like '%nsubscribe%'
         and jsonb_array_length(rq #> '{body,template,components,0,parameters}') = 5, false), rq ->> 'error');

    -- ---------- the sender's rule (read, not run) ----------
    insert into zz_m34j_check (name, ok)
    select 'sender_cancels_an_opted_out_channel', prosrc ~ 'n\.channel = any \(coalesce\(l\.opted_out_channels' and prosrc ~ 'b2b\.url_allowed'
                                                  and prosrc ~ 'http_maybe_delivered' and prosrc ~ 'student opted out or is a test lead'
      from pg_proc where oid = 'b2b.notify_tick()'::regprocedure;
    insert into zz_m34j_check (name, ok)
    select 'settings_functions_carry_site_url', bool_and(prosrc ~ 'site_url') and count(*) = 3
      from pg_proc where pronamespace = 'b2b'::regnamespace and proname in ('notification_settings_save', 'notifications_overview', 'notification_preview');
    begin
      perform b2b.notification_settings_save('{"quiet_start":"08:00","quiet_end":"21:00","support_contact":"+91 00000 00000","site_url":"https://x.example.invalid"}', 'm34j http test');
      err := 'no error';
    exception when others then err := sqlstate;
    end;
    insert into zz_m34j_check (name, ok, detail) values ('settings_save_needs_an_admin', err = '42501', err);

    -- ---------- the limits ----------
    update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 2, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';
    y := b2b.unsubscribe(u + 1, repeat('0', 40), 'email', '198.51.100.7', 'link') is false and b2b.unsubscribe(u + 2, repeat('0', 40), 'email', '198.51.100.7', 'link') is false;
    begin
      perform b2b.unsubscribe(u + 3, repeat('0', 40), 'email', '198.51.100.7', 'link');
      err := 'no error';
    exception when others then
      get stacked diagnostics h = pg_exception_hint;
      err := sqlstate; out := out || sqlerrm || coalesce(h, '');
    end;
    insert into zz_m34j_check (name, ok, detail) values
      ('limit_per_caller_address', y and err = 'P0429' and h ~ '^retry after [0-9]{1,2} seconds$', err),
      ('refused_call_is_not_counted', (select n = 2 from b2b.unsubscribe_usage where bucket = 'ip:' || left(encode(extensions.hmac('198.51.100.7', k, 'sha256'), 'hex'), 16)
                                         and minute = date_trunc('minute', now()))
         and not exists (select 1 from b2b.unsubscribe_usage where bucket = 'lead:' || (u + 3)), null),
      ('caller_address_not_stored', (select bool_and(bucket ~ '^(ip:[0-9a-f]{16}|lead:[0-9]+|all)$') from b2b.unsubscribe_usage), null);
    update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 100000, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';

    -- ---------- who may call what ----------
    insert into zz_m34j_check (name, ok)
    select 'new_functions_closed_to_clients', bool_and(not has_function_privilege('anon', fn, 'execute') and not has_function_privilege('authenticated', fn, 'execute')
                                                       and not has_function_privilege('public', fn, 'execute'))
      from unnest(array['b2b.unsubscribe_token(bigint, text)', 'b2b.unsubscribe_link(bigint, text)', 'b2b.unsubscribe(bigint, text, text, text, text)']) fn;
    insert into zz_m34j_check (name, ok) values
      ('service_role_only_the_opt_out', has_function_privilege('service_role', 'b2b.unsubscribe(bigint, text, text, text, text)', 'execute')
         and not has_function_privilege('service_role', 'b2b.unsubscribe_token(bigint, text)', 'execute')
         and not has_function_privilege('service_role', 'b2b.unsubscribe_link(bigint, text)', 'execute')),
      ('usage_table_closed_to_clients', (select relrowsecurity from pg_class where oid = 'b2b.unsubscribe_usage'::regclass)
         and not has_table_privilege('anon', 'b2b.unsubscribe_usage', 'select, insert, update, delete')
         and not has_table_privilege('authenticated', 'b2b.unsubscribe_usage', 'select, insert, update, delete')
         and not exists (select 1 from pg_policy where polrelid = 'b2b.unsubscribe_usage'::regclass));
    insert into zz_m34j_check (name, ok)
    select 'replaced_functions_keep_their_grants', bool_and(not has_function_privilege('anon', fn, 'execute'))
           and bool_and(has_function_privilege('authenticated', fn, 'execute') = (fn ~ '^b2b\.notification')) and bool_and(has_function_privilege('service_role', fn, 'execute'))
      from unnest(array['b2b.notify_request(b2b.student_notifications)', 'b2b.notify_tick()', 'b2b.notification_settings_save(jsonb, text)',
                        'b2b.notification_preview(bigint, bigint)', 'b2b.notifications_overview()']) fn;

    -- ---------- the key stays in Vault; nothing was queued for sending ----------
    out := out || coalesce(t1, '') || coalesce(t2, '') || coalesce(lk1, '') || coalesce(lk2, '') || coalesce(b2b.unsubscribe_token(l2, 'whatsapp'), '')
               || b2b.unsubscribe(l2, k, 'email', k, 'link')::text;
    insert into zz_m34j_check (name, ok) values
      ('key_in_no_function_result', length(k) = 64 and length(out) > 500 and position(k in out) = 0),
      ('key_in_no_table', not exists (select 1 from b2b.settings where value::text like '%' || k || '%')
         and not exists (select 1 from b2b.events where lead_id in (l1, l2) and payload::text like '%' || k || '%')
         and not exists (select 1 from b2b.unsubscribe_usage where bucket like '%' || k || '%'));
    insert into zz_m34j_check (name, ok)
    select 'key_not_in_function_source', bool_and(position(k in p.prosrc) = 0) from pg_proc p where p.pronamespace = 'b2b'::regnamespace;
    select count(*) into q1 from net.http_request_queue;
    insert into zz_m34j_check (name, ok, detail) values
      ('no_http_request_queued', q1 = q0 and not exists (select 1 from b2b.student_notifications where id in (n1m, n1w, n2m) and (net_request_id is not null or attempts > 0)),
         (q1 - q0)::text);

    select count(*), count(*) filter (where ok is not true),
           coalesce(string_agg(name || coalesce(' (' || left(detail, 80) || ')', ''), ', ' order by seq) filter (where ok is not true), 'all passed')
      into v_total, v_failed, v_detail from zz_m34j_check;
  exception when others then
    get stacked diagnostics f = pg_exception_context;
    v_total := 0; v_failed := 1; v_detail := 'stopped by ' || sqlstate || ' ' || left(sqlerrm, 200) || ' at ' || left(split_part(f, E'\n', 1), 120);
  end;
  raise exception 'TESTRESULT total=% failed=% %', v_total, v_failed, v_detail;
end $m34j$;
