-- M9b: sending student notifications (B9) from Postgres with pg_net, every 30 seconds. WhatsApp: Meta Cloud API
-- (an approved template from Eduwit's WhatsApp Business number). Email: Resend or Brevo (HTTP APIs; SMTP is not
-- reachable from pg_net). Each channel sends only while its live switch is on; otherwise due messages are cancelled,
-- so nothing stale goes out when a switch is turned on later. One retry after 5 minutes, then failed and alerted.
-- whatsapp.base_url / email.base_url in the settings (set by SQL, not the screen) point a staging project at a mock.

create or replace function b2b.html_escape(t text)
returns text language sql immutable set search_path = '' as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

/* The branded email: partner logo, the message as paragraphs, Eduwit's support contact and an unsubscribe line. */
create or replace function b2b.email_html(p_text text, p_logo text, p_color text, p_support text, p_unsubscribe text)
returns text language sql immutable set search_path = '' as $$
  select '<!doctype html><html><body style="margin:0;background:#f5f6f8;font-family:Arial,Helvetica,sans-serif;color:#1c2333">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">'
    || '<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;border-top:4px solid '
    || coalesce(nullif(p_color, ''), '#0B2F5E') || '"><tr><td style="padding:28px 28px 8px">'
    || case when p_logo ~ '^https://' then '<img src="' || b2b.html_escape(p_logo) || '" alt="" height="40" style="height:40px;max-width:200px">' else '' end
    || '</td></tr><tr><td style="padding:8px 28px 24px;font-size:15px;line-height:1.55">'
    || (select string_agg('<p style="margin:0 0 14px">' || replace(b2b.html_escape(p), E'\n', '<br>') || '</p>', '' order by n)
          from regexp_split_to_table(coalesce(p_text, ''), E'\n\\s*\n') with ordinality x(p, n))
    || '</td></tr><tr><td style="padding:16px 28px 24px;border-top:1px solid #e6e8ee;font-size:12px;color:#6b7385">'
    || 'You are receiving this because you enquired about a programme with Eduwit. Help: ' || b2b.html_escape(p_support)
    || case when p_unsubscribe is not null then ' · <a href="' || b2b.html_escape(p_unsubscribe) || '" style="color:#6b7385">Unsubscribe</a>' else '' end
    || '</td></tr></table></td></tr></table></body></html>';
$$;

/* The provider request for one notification. */
create or replace function b2b.notify_request(n b2b.student_notifications)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  t b2b.message_templates;
  p b2b.partners;
  v_text text;
  v_subject text;
  v_secret text;
  w jsonb := coalesce(s -> 'whatsapp', '{}');
  m jsonb := coalesce(s -> 'email', '{}');
  v_unsub text;
begin
  select * into t from b2b.message_templates where id = n.template_id;
  select * into p from b2b.partners where id = n.partner_id;
  v_text := b2b.render_template(t.body, n.variables);
  if n.channel = 'whatsapp' then
    v_secret := case when w ->> 'token_secret_id' is not null then b2b.partner_secret((w ->> 'token_secret_id')::uuid) end;
    if v_secret is null or w ->> 'phone_number_id' is null or t.wa_template is null then return jsonb_build_object('error', 'WhatsApp provider is not configured'); end if;
    return jsonb_build_object('provider', 'meta_cloud',
      'url', coalesce(w ->> 'base_url', 'https://graph.facebook.com') || '/' || coalesce(w ->> 'api_version', 'v21.0') || '/' || (w ->> 'phone_number_id') || '/messages',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
      'body', jsonb_build_object('messaging_product', 'whatsapp', 'to', n.recipient, 'type', 'template',
        'template', jsonb_build_object('name', t.wa_template, 'language', jsonb_build_object('code', coalesce(t.wa_language, t.language)),
          'components', jsonb_build_array(jsonb_build_object('type', 'body', 'parameters', jsonb_build_array(
            jsonb_build_object('type', 'text', 'text', n.variables ->> 'student_first_name'),
            jsonb_build_object('type', 'text', 'text', n.variables ->> 'programme_label'),
            jsonb_build_object('type', 'text', 'text', n.variables ->> 'partner_display_name'),
            jsonb_build_object('type', 'text', 'text', n.variables ->> 'expected_contact_window'),
            jsonb_build_object('type', 'text', 'text', n.variables ->> 'eduwit_support_contact')))))));
  end if;
  v_secret := case when m ->> 'api_key_secret_id' is not null then b2b.partner_secret((m ->> 'api_key_secret_id')::uuid) end;
  if v_secret is null or m ->> 'from_email' is null then return jsonb_build_object('error', 'email provider is not configured'); end if;
  v_subject := b2b.render_template(coalesce(t.subject, 'Your counsellor will call you'), n.variables);
  v_unsub := coalesce(s ->> 'unsubscribe_url', 'mailto:' || coalesce(m ->> 'reply_to', s ->> 'support_contact', m ->> 'from_email') || '?subject=Unsubscribe');
  if coalesce(m ->> 'provider', 'resend') = 'brevo' then
    return jsonb_build_object('provider', 'brevo', 'url', coalesce(m ->> 'base_url', 'https://api.brevo.com') || '/v3/smtp/email',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'api-key', v_secret),
      'body', jsonb_strip_nulls(jsonb_build_object(
        'sender', jsonb_build_object('name', coalesce(m ->> 'from_name', 'Team Eduwit'), 'email', m ->> 'from_email'),
        'to', jsonb_build_array(jsonb_build_object('email', n.recipient)), 'subject', v_subject, 'textContent', v_text,
        'htmlContent', b2b.email_html(v_text, p.logo_url, p.brand_color, n.variables ->> 'eduwit_support_contact', v_unsub),
        'replyTo', case when m ->> 'reply_to' is not null then jsonb_build_object('email', m ->> 'reply_to') end)));
  end if;
  return jsonb_build_object('provider', 'resend', 'url', coalesce(m ->> 'base_url', 'https://api.resend.com') || '/emails',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret, 'Idempotency-Key', 'notify-' || n.id),
    'body', jsonb_strip_nulls(jsonb_build_object(
      'from', coalesce(m ->> 'from_name', 'Team Eduwit') || ' <' || (m ->> 'from_email') || '>', 'to', jsonb_build_array(n.recipient),
      'subject', v_subject, 'text', v_text, 'reply_to', m ->> 'reply_to',
      'html', b2b.email_html(v_text, p.logo_url, p.brand_color, n.variables ->> 'eduwit_support_contact', v_unsub))));
end $$;

/* Collects provider answers, then sends what is due. Runs every 30 seconds. */
create or replace function b2b.notify_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_retry int := coalesce((s ->> 'retry_after_minutes')::int, 5);
  r record;
  n b2b.student_notifications;
  j jsonb;
  req jsonb;
  v_net bigint;
  v_sent int := 0;
  v_done int := 0;
  v_why text;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    select x.id, x.attempts, x.lead_id, x.allocation_id, x.partner_id, x.channel, x.updated_at, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null as done
      from b2b.student_notifications x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 200
  loop
    if not r.done and r.updated_at > now() - interval '2 minutes' then continue; end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.student_notifications set status = 'sent', sent_at = now(), updated_at = now(), net_request_id = null, error = null,
             provider_message_id = left(coalesce(j -> 'messages' -> 0 ->> 'id', j ->> 'id', j ->> 'messageId'), 200)
       where id = r.id;
      perform b2b.log_event('notification.sent', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'notification_id', r.id));
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer from the provider' end,
                             'HTTP ' || r.status_code || ': ' || coalesce(j -> 'error' ->> 'message', j ->> 'message', left(r.content, 200))), 300);
      if r.attempts < 2 then
        update b2b.student_notifications set status = 'scheduled', scheduled_for = now() + make_interval(mins => v_retry), net_request_id = null,
               error = v_why, updated_at = now() where id = r.id;
      else
        update b2b.student_notifications set status = 'failed', net_request_id = null, error = v_why, updated_at = now() where id = r.id;
        perform b2b.log_event('alert.notification_failed', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'error', v_why));
      end if;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due messages
  for n in
    select * from b2b.student_notifications where status = 'scheduled' and scheduled_for <= now()
     order by scheduled_for limit 50 for update skip locked
  loop
    begin
      v_why := case
        when not exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.status = 'accepted') then 'the allocation is no longer accepted'
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and (coalesce(l.is_opted_out, false) or coalesce(l.is_test, false)
                                                                                       or b2b.is_test_phone(l.whatsapp_number))) then 'student opted out or is a test lead'
        when not b2b.is_live(n.channel) then n.channel || ' is switched off'
      end;
      if v_why is not null then
        update b2b.student_notifications set status = 'cancelled', error = v_why, updated_at = now() where id = n.id;
        continue;
      end if;
      req := b2b.notify_request(n);
      if req ? 'error' then
        update b2b.student_notifications set status = 'failed', error = req ->> 'error', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', req ->> 'error'));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 15000);
      update b2b.student_notifications set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider',
             updated_at = now() where id = n.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.student_notifications set status = 'failed', error = left(sqlerrm, 300), updated_at = now() where id = n.id;
      perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $$;

-- ---------- Admin ----------

/* Providers and quiet hours. Secrets go to Vault; leave a secret empty to keep the stored one. */
create or replace function b2b.notification_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  w jsonb := coalesce(v -> 'whatsapp', '{}');
  m jsonb := coalesce(v -> 'email', '{}');
  v_id uuid;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'quiet_start', '08:00') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(p ->> 'quiet_end', '21:00') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or (p ->> 'quiet_start')::time >= (p ->> 'quiet_end')::time then
    raise exception 'quiet hours must be HH:MM with the start before the end' using errcode = '22023';
  end if;
  if length(coalesce(p ->> 'support_contact', '')) not between 5 and 120 then raise exception 'give a staffed support phone or email' using errcode = '22023'; end if;
  if coalesce(p -> 'email' ->> 'provider', 'resend') not in ('resend', 'brevo') then raise exception 'unknown email provider' using errcode = '22023'; end if;
  if nullif(p -> 'email' ->> 'from_email', '') is not null and p -> 'email' ->> 'from_email' !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    raise exception 'the sender address is not an email address' using errcode = '22023';
  end if;
  if nullif(p -> 'whatsapp' ->> 'phone_number_id', '') is not null and p -> 'whatsapp' ->> 'phone_number_id' !~ '^\d{6,30}$' then
    raise exception 'the WhatsApp phone number ID is the number Meta shows (digits only)' using errcode = '22023';
  end if;

  if coalesce(p -> 'whatsapp' ->> 'token', '') <> '' then
    v_id := (w ->> 'token_secret_id')::uuid;
    if v_id is null then v_id := vault.create_secret(p -> 'whatsapp' ->> 'token', 'b2b_whatsapp_token', 'Meta WhatsApp Cloud API token');
    else perform vault.update_secret(v_id, p -> 'whatsapp' ->> 'token'); end if;
    w := w || jsonb_build_object('token_secret_id', v_id);
  end if;
  if coalesce(p -> 'email' ->> 'api_key', '') <> '' then
    v_id := (m ->> 'api_key_secret_id')::uuid;
    if v_id is null then v_id := vault.create_secret(p -> 'email' ->> 'api_key', 'b2b_email_api_key', 'Email provider API key');
    else perform vault.update_secret(v_id, p -> 'email' ->> 'api_key'); end if;
    m := m || jsonb_build_object('api_key_secret_id', v_id);
  end if;
  w := w || jsonb_build_object('provider', 'meta_cloud', 'phone_number_id', nullif(p -> 'whatsapp' ->> 'phone_number_id', ''),
                               'api_version', coalesce(nullif(p -> 'whatsapp' ->> 'api_version', ''), 'v21.0'));
  m := m || jsonb_build_object('provider', coalesce(p -> 'email' ->> 'provider', 'resend'), 'from_email', nullif(lower(trim(p -> 'email' ->> 'from_email')), ''),
                               'from_name', coalesce(nullif(trim(p -> 'email' ->> 'from_name'), ''), 'Team Eduwit'),
                               'reply_to', nullif(lower(trim(p -> 'email' ->> 'reply_to')), ''));
  v := v || jsonb_build_object('quiet_start', p ->> 'quiet_start', 'quiet_end', p ->> 'quiet_end', 'support_contact', trim(p ->> 'support_contact'),
                               'unsubscribe_url', nullif(trim(p ->> 'unsubscribe_url'), ''), 'b2c_sends_own_notification', true, 'whatsapp', w, 'email', m);
  return b2b.set_setting('notifications', v, p_reason);
end $$;

create or replace function b2b.template_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  t b2b.message_templates;
  v_bad text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into t from b2b.message_templates where id = (p ->> 'id')::bigint for update;
  if t.id is null then raise exception 'template not found' using errcode = 'P0002'; end if;
  if length(trim(coalesce(p ->> 'body', ''))) not between 20 and 4000 then raise exception 'the message must be 20 to 4000 characters' using errcode = '22023'; end if;
  select string_agg(distinct m[1], ', ') into v_bad from regexp_matches(p ->> 'body' || ' ' || coalesce(p ->> 'subject', ''), '\{\{([^}]*)\}\}', 'g') m
   where m[1] not in ('student_first_name', 'programme_label', 'partner_display_name', 'expected_contact_window', 'eduwit_support_contact');
  if v_bad is not null then raise exception 'unknown variable: %', v_bad using errcode = '22023'; end if;
  if t.channel = 'email' and length(trim(coalesce(p ->> 'subject', ''))) not between 3 and 150 then raise exception 'the subject must be 3 to 150 characters' using errcode = '22023'; end if;
  if t.channel = 'whatsapp' and coalesce(p ->> 'status', t.status) = 'active' and coalesce(nullif(trim(p ->> 'wa_template'), ''), t.wa_template) is null then
    raise exception 'give the approved WhatsApp template name before activating' using errcode = '22023';
  end if;
  if coalesce(p ->> 'status', t.status) not in ('draft', 'active') then raise exception 'unknown status' using errcode = '22023'; end if;
  update b2b.message_templates set body = trim(p ->> 'body'), subject = case when channel = 'email' then trim(p ->> 'subject') end,
         wa_template = case when channel = 'whatsapp' then coalesce(nullif(trim(p ->> 'wa_template'), ''), wa_template) end,
         wa_language = case when channel = 'whatsapp' then coalesce(nullif(trim(p ->> 'wa_language'), ''), wa_language) end,
         status = coalesce(p ->> 'status', status), version = version + 1, updated_at = now(), updated_by = auth.uid()::text
   where id = t.id returning * into t;
  perform b2b.log_event('template.saved', null, null, null, jsonb_build_object('template_id', t.id, 'version', t.version, 'status', t.status));
  return to_jsonb(t);
end $$;

/* What a student would receive for this template and partner (a sample student; real partner name and timing). */
create or replace function b2b.notification_preview(p_template_id bigint, p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  t b2b.message_templates;
  p b2b.partners;
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v jsonb;
  v_text text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into t from b2b.message_templates where id = p_template_id;
  select * into p from b2b.partners where id = p_partner_id;
  if t.id is null then return null; end if;
  v := jsonb_build_object('student_first_name', case when t.language = 'hi' then 'Priya' else 'Ravi' end, 'programme_label', 'Online MBA (Finance)',
                          'partner_display_name', coalesce(p.display_name, p.name, 'Partner name'),
                          'expected_contact_window', case when p.id is null then 'within 2 working hours' else b2b.contact_window(p, b2b.notify_slot(now())) end,
                          'eduwit_support_contact', coalesce(s ->> 'support_contact', 'support@eduwit.in'));
  v_text := b2b.render_template(t.body, v);
  return jsonb_build_object('subject', b2b.render_template(t.subject, v), 'text', v_text, 'variables', v,
    'html', case when t.channel = 'email' then b2b.email_html(v_text, p.logo_url, p.brand_color, v ->> 'eduwit_support_contact', s ->> 'unsubscribe_url') end);
end $$;

/* The Notifications screen: settings without secrets, switches, templates, and the send log (recipients masked). */
create or replace function b2b.notifications_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', jsonb_build_object(
      'quiet_start', s ->> 'quiet_start', 'quiet_end', s ->> 'quiet_end', 'support_contact', s ->> 'support_contact', 'unsubscribe_url', s ->> 'unsubscribe_url',
      'whatsapp', (coalesce(s -> 'whatsapp', '{}') - 'token_secret_id') || jsonb_build_object('has_token', s -> 'whatsapp' ->> 'token_secret_id' is not null),
      'email', (coalesce(s -> 'email', '{}') - 'api_key_secret_id') || jsonb_build_object('has_key', s -> 'email' ->> 'api_key_secret_id' is not null)),
    'version', (select version from b2b.settings where key = 'notifications'),
    'switches', jsonb_build_object('whatsapp', b2b.is_live('whatsapp'), 'email', b2b.is_live('email')),
    'templates', coalesce((select jsonb_agg(to_jsonb(t) order by t.kind, t.channel, t.language) from b2b.message_templates t), '[]'),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'notify_enabled', p.notify_enabled) order by coalesce(p.display_name, p.name))
                          from b2b.partners p where p.status <> 'closed'), '[]'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from b2b.student_notifications where created_at > now() - interval '7 days' group by 1) x), '{}'),
    'log', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'lead_id', x.lead_id, 'lead_name', l.student_name, 'channel', x.channel, 'kind', x.kind,
                        'language', x.language, 'status', x.status, 'error', x.error, 'scheduled_for', x.scheduled_for, 'sent_at', x.sent_at, 'created_at', x.created_at,
                        'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = x.partner_id),
                        'recipient', case when x.channel = 'whatsapp' then '•••• ' || right(coalesce(x.recipient, ''), 4)
                                          else regexp_replace(coalesce(x.recipient, ''), '^(.).*(@.*)$', '\1•••\2') end) order by x.created_at desc)
                     from (select * from b2b.student_notifications order by created_at desc limit 100) x left join public.student_leads l on l.id = x.lead_id), '[]'));
end $$;

/* Send a failed or cancelled message again (once), at the next slot inside quiet hours. */
create or replace function b2b.notification_retry(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.student_notifications set status = 'scheduled', scheduled_for = b2b.notify_slot(now()), attempts = 1, error = null, updated_at = now()
   where id = p_id and status in ('failed', 'cancelled');
  if not found then raise exception 'only a failed or cancelled message can be sent again' using errcode = '22023'; end if;
  perform b2b.log_event('notification.retry', null, null, null, jsonb_build_object('notification_id', p_id));
end $$;

revoke execute on function b2b.html_escape(text), b2b.email_html(text, text, text, text, text), b2b.notify_request(b2b.student_notifications), b2b.notify_tick()
  from public, anon, authenticated;
grant execute on function b2b.html_escape(text), b2b.email_html(text, text, text, text, text), b2b.notify_request(b2b.student_notifications), b2b.notify_tick() to service_role;
revoke execute on function b2b.notification_settings_save(jsonb, text), b2b.template_save(jsonb), b2b.notification_preview(bigint, bigint),
                           b2b.notifications_overview(), b2b.notification_retry(bigint) from public, anon;
grant execute on function b2b.notification_settings_save(jsonb, text), b2b.template_save(jsonb), b2b.notification_preview(bigint, bigint),
                          b2b.notifications_overview(), b2b.notification_retry(bigint) to authenticated, service_role;

select cron.schedule('b2b-notify-tick', '30 seconds', 'select b2b.notify_tick()');
