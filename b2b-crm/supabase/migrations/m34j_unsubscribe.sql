-- M34j (13 Nov 2026, audit finding M6, approved by Vikas). A student's email from the CRM ("partner assigned", "new
-- counsellor") offered only a mailto "Unsubscribe" that a person had to process by hand, and carried no List-Unsubscribe
-- header. Now every such email carries a link the student can use alone, and the one-click headers mail providers ask for.
-- Every replaced function is its current definition (the file named next to it) with only the change described.
-- Re-appliable (create or replace, if not exists); no DROP. Checked by supabase/tests/test_m34j_unsubscribe.sql (local:
-- supabase/local-test.sh; staging: SQL editor) and, over an HTTP SQL API, by supabase/tests/m34j.http.sql (never runs the
-- sender; ends with TESTRESULT and rolls back).
--   0  Vault secret b2b_unsubscribe_key  NEW, made here (32 random bytes), never leaves the database. The old CRM's
--      unsubscribe_token (new)           public.crm_unsubscribe_token is not used: its key is a table setting (audit S3)
--                                        and its token is not bound to a channel. The token is the first 40 hex
--                                        characters of HMAC-SHA256("unsubscribe:v1:<channel>:<lead id>") under the Vault key
--   1  unsubscribe_link (new)            <notifications.site_url>/u/<lead id>/<token>, or null while the CRM's web address
--                                        or the key is missing. Token and link are internal (no client role, not even the
--                                        service role, can call them)
--   2  unsubscribe (new)                 service role only (the button on the web app's /u/<lead>/<token> page and its
--                                        one-click route; opening the page changes nothing, because mail scanners follow
--                                        links): per-minute limits (per caller address, per lead, in total; SQLSTATE P0429 as
--                                        api_key_check), the token compared without a timing signal, then 'email' added to
--                                        student_leads.opted_out_channels (the flag notify_accepted already honours), due
--                                        emails cancelled, event lead.unsubscribed, the B2C link told. WhatsApp is untouched.
--   3  notify_request (m9b)              email only: the footer link and a last text line are the lead's unsubscribe link;
--                                        the provider request carries List-Unsubscribe: <https one-click>, <mailto> and
--                                        List-Unsubscribe-Post: List-Unsubscribe=One-Click (Resend and Brevo: "headers").
--                                        Without a site_url: the old footer link and a mailto-only List-Unsubscribe
--   4  notify_tick (m34i)                a due message is also cancelled when the student opted out of its channel
--   5  notification_settings_save,       notifications.site_url: the CRM's public https address (the web app sends its
--      notifications_overview,           NEXT_PUBLIC_SITE_URL as the default); a caller that does not send the key keeps the
--      notification_preview (m9b)        stored value; the preview shows a sample link
-- Deploy order: this migration and the web release with /u/[lead]/[token] in either order (until site_url is saved the
-- emails keep the old footer and no link points at the web app); then Notifications -> Providers -> save once with "CRM web
-- address" filled in. That save is what switches the links on, so it comes last.
-- Rollback: clear "CRM web address" and save (the next email has the old footer again); only if the functions themselves
-- must go back, re-run notify_request, notification_settings_save, notifications_overview and notification_preview from m9b
-- and notify_tick from m34i. The new functions, the table and the Vault secret stay, and so does the web route: links in
-- emails already sent must keep working.

-- ---------- (0) the key and the token ----------
do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'b2b_unsubscribe_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'b2b_unsubscribe_key',
                                'B2B CRM: key for the unsubscribe links in student emails (m34j)');
  end if;
end $v$;

/* The unsubscribe token of one lead and channel: 40 hex characters (160 bits) of an HMAC under the Vault key, so it cannot
   be guessed or built from the lead id, and a token for one channel or lead opens no other. Null while the key is missing.
   Internal. */
create or replace function b2b.unsubscribe_token(p_lead bigint, p_channel text default 'email')
returns text language sql stable security definer set search_path = '' as $fn$
  select left(encode(extensions.hmac('unsubscribe:v1:' || p_channel || ':' || p_lead::text, s.decrypted_secret, 'sha256'), 'hex'), 40)
    from vault.decrypted_secrets s
   where s.name = 'b2b_unsubscribe_key' and p_lead is not null and p_channel is not null and coalesce(s.decrypted_secret, '') <> '';
$fn$;

-- ---------- (1) the link ----------
/* The page a student opens to stop the CRM's emails about their enquiry: <site_url>/u/<lead>/<token>. The one-click address
   of RFC 8058 is this link plus /one-click. Null while notifications.site_url or the key is not set. Internal. */
create or replace function b2b.unsubscribe_link(p_lead bigint, p_channel text default 'email')
returns text language sql stable security definer set search_path = '' as $fn$
  select x.base || '/u/' || p_lead::text || '/' || b2b.unsubscribe_token(p_lead, p_channel)
    from (select nullif(rtrim(coalesce((select s.value ->> 'site_url' from b2b.settings s where s.key = 'notifications'), ''), '/'), '') as base) x
   where x.base ~ '^https://';
$fn$;

-- ---------- (2) the opt-out ----------
create table if not exists b2b.unsubscribe_usage (
  bucket  text not null,
  minute  timestamptz not null,
  n       int not null default 0,
  primary key (bucket, minute)
);
create index if not exists unsubscribe_usage_minute_idx on b2b.unsubscribe_usage (minute);
comment on table b2b.unsubscribe_usage is
  'M34j: calls of b2b.unsubscribe per minute and bucket (ip:<keyed hash of the caller address>, lead:<id>, all); rows older than an hour are removed by the next call';
alter table b2b.unsubscribe_usage enable row level security;
revoke all on b2b.unsubscribe_usage from public, anon, authenticated;
grant all on b2b.unsubscribe_usage to service_role;

/* A student stops the CRM's emails about their enquiry. Called only by the web app's server (service role), for the button
   on /u/<lead>/<token> and for POST /u/<lead>/<token>/one-click, never for opening the page; p_source is 'link' (the
   button) or 'one_click' (the mail provider's List-Unsubscribe-Post). Returns true when the token is this lead's, false for
   anything else; the web app answers both the same way.
   Limits per minute, counted before the token is looked at: 60 per caller address, 10 per lead, 600 in total (setting
   api_limits.unsubscribe {per_ip, per_lead, total} overrides them). Over a limit: SQLSTATE P0429 with the hint
   'retry after N seconds', as api_key_check; the raise rolls the call back, so the count stays at the limit.
   The token is compared as two HMACs under the key, so the time taken says nothing about how much of it matched; a lead that
   does not exist costs the same as a wrong token.
   A valid call adds the channel to student_leads.opted_out_channels of the lead and of the lead it was merged into (the
   flag notify_accepted and notify_tick read; is_opted_out and WhatsApp stay as they are), cancels the lead's due messages
   on that channel, logs lead.unsubscribed and tells the B2C link. A repeat changes and logs nothing and still returns true.
   Only 'email' can be unsubscribed here. */
create or replace function b2b.unsubscribe(p_lead bigint, p_token text, p_channel text default 'email', p_ip text default null,
                                           p_source text default 'link')
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  lim jsonb := coalesce((select s.value -> 'unsubscribe' from b2b.settings s where s.key = 'api_limits'), '{}');
  v_key text := (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'b2b_unsubscribe_key');
  v_minute timestamptz := date_trunc('minute', now());
  v_expected text;
  v_source text := case when p_source = 'one_click' then 'one_click' else 'link' end;
  v_n int;
  v_id bigint := p_lead;
  v_hops int := 0;
  b record;
  l public.student_leads;
begin
  delete from b2b.unsubscribe_usage where minute < v_minute - interval '1 hour';
  for b in
    select x.bucket, x.cap from (values
      ('ip:' || coalesce(left(encode(extensions.hmac(coalesce(nullif(trim(p_ip), ''), 'unknown'), coalesce(v_key, 'no-key'), 'sha256'), 'hex'), 16), 'unknown'),
       case when (lim ->> 'per_ip') ~ '^[0-9]{1,6}$' then (lim ->> 'per_ip')::int else 60 end),
      ('lead:' || p_lead::text, case when (lim ->> 'per_lead') ~ '^[0-9]{1,6}$' then (lim ->> 'per_lead')::int else 10 end),
      ('all', case when (lim ->> 'total') ~ '^[0-9]{1,6}$' then (lim ->> 'total')::int else 600 end)) x(bucket, cap)
     where x.bucket is not null
  loop
    insert into b2b.unsubscribe_usage (bucket, minute, n) values (b.bucket, v_minute, 1)
    on conflict (bucket, minute) do update set n = b2b.unsubscribe_usage.n + 1
    returning n into v_n;
    if v_n > b.cap then
      raise exception 'rate limited: too many unsubscribe requests' using errcode = 'P0429',
        hint = 'retry after ' || greatest(1, (60 - extract(second from now()))::int) || ' seconds';
    end if;
  end loop;

  if p_lead is null or p_channel is distinct from 'email' or coalesce(v_key, '') = '' then return false; end if;
  v_expected := b2b.unsubscribe_token(p_lead, p_channel);
  if v_expected is null
     or extensions.hmac(left(coalesce(p_token, ''), 128), v_key, 'sha256') is distinct from extensions.hmac(v_expected, v_key, 'sha256') then
    return false;
  end if;

  perform set_config('b2b.actor', 'student', true);
  -- the lead, and the lead it was merged into (an old email's link must also stop the kept lead's emails)
  while v_id is not null and v_hops < 5 loop
    select * into l from public.student_leads x where x.id = v_id for update;
    exit when l.id is null;
    if not (p_channel = any (coalesce(l.opted_out_channels, '{}'))) then
      update public.student_leads
         set opted_out_channels = array(select distinct c from unnest(coalesce(opted_out_channels, '{}') || p_channel) c order by 1),
             updated_at = now(), updated_by = 'b2b:unsubscribe'
       where id = l.id;
      update b2b.student_notifications set status = 'cancelled', error = 'student opted out of ' || p_channel || ' (unsubscribe link)', updated_at = now()
       where lead_id = l.id and status = 'scheduled' and channel = p_channel;
      perform b2b.log_event('lead.unsubscribed', l.id, l.allocation_id, null,
                            jsonb_build_object('channel', p_channel, 'source', v_source, 'link_lead_id', p_lead));
      begin
        perform b2b.b2c_sync_lead(l.id);   -- the B2C CRM reads consent.opted_out_channels; never a reason to refuse the student
      exception when others then null;
      end;
    end if;
    v_id := l.merged_into_id;
    v_hops := v_hops + 1;
  end loop;
  return true;
end $fn$;

-- Token and link are for the sender only (definer functions call them as their owner): the web app needs neither, so the
-- service role cannot ask for a lead's token. The opt-out itself is the service role's.
revoke execute on function b2b.unsubscribe_token(bigint, text), b2b.unsubscribe_link(bigint, text)
  from public, anon, authenticated, service_role;
revoke execute on function b2b.unsubscribe(bigint, text, text, text, text) from public, anon, authenticated;
grant execute on function b2b.unsubscribe(bigint, text, text, text, text) to service_role;

-- ---------- (3) the provider request ----------
/* As m9b, email only: the lead's unsubscribe link in the footer and as the last line of the text part, and the
   List-Unsubscribe headers. The mailto address is the first of reply-to, support contact and sender that is an email
   address (the support contact may be a phone number). WhatsApp is unchanged. */
create or replace function b2b.notify_request(n b2b.student_notifications)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
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
  v_link text;
  v_mailto text;
  v_list jsonb;
  v_plain text;
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
  -- M34j: the student's own link (null until notifications.site_url is saved), and a mailto as the second way
  v_link := b2b.unsubscribe_link(n.lead_id, 'email');
  v_mailto := 'mailto:' || coalesce((select a from unnest(array[m ->> 'reply_to', s ->> 'support_contact', m ->> 'from_email']) with ordinality x(a, i)
                                      where a ~ '^[^@\s<>,]+@[^@\s<>,]+\.[A-Za-z]{2,}$' order by i limit 1), m ->> 'from_email') || '?subject=Unsubscribe';
  v_unsub := coalesce(v_link, s ->> 'unsubscribe_url', v_mailto);
  v_list := case when v_link is not null
                 then jsonb_build_object('List-Unsubscribe', '<' || v_link || '/one-click>, <' || v_mailto || '>',
                                         'List-Unsubscribe-Post', 'List-Unsubscribe=One-Click')
                 else jsonb_build_object('List-Unsubscribe', '<' || v_mailto || '>') end;
  v_plain := v_text || coalesce(E'\n\nUnsubscribe: ' || v_link, '');
  if coalesce(m ->> 'provider', 'resend') = 'brevo' then
    return jsonb_build_object('provider', 'brevo', 'url', coalesce(m ->> 'base_url', 'https://api.brevo.com') || '/v3/smtp/email',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'api-key', v_secret),
      'body', jsonb_strip_nulls(jsonb_build_object(
        'sender', jsonb_build_object('name', coalesce(m ->> 'from_name', 'Team Eduwit'), 'email', m ->> 'from_email'),
        'to', jsonb_build_array(jsonb_build_object('email', n.recipient)), 'subject', v_subject, 'textContent', v_plain,
        'htmlContent', b2b.email_html(v_text, p.logo_url, p.brand_color, n.variables ->> 'eduwit_support_contact', v_unsub),
        'replyTo', case when m ->> 'reply_to' is not null then jsonb_build_object('email', m ->> 'reply_to') end,
        'headers', v_list)));
  end if;
  return jsonb_build_object('provider', 'resend', 'url', coalesce(m ->> 'base_url', 'https://api.resend.com') || '/emails',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret, 'Idempotency-Key', 'notify-' || n.id),
    'body', jsonb_strip_nulls(jsonb_build_object(
      'from', coalesce(m ->> 'from_name', 'Team Eduwit') || ' <' || (m ->> 'from_email') || '>', 'to', jsonb_build_array(n.recipient),
      'subject', v_subject, 'text', v_plain, 'reply_to', m ->> 'reply_to',
      'html', b2b.email_html(v_text, p.logo_url, p.brand_color, n.variables ->> 'eduwit_support_contact', v_unsub),
      'headers', v_list)));
end $fn$;

-- ---------- (4) the sender ----------
/* As m34i, plus: a due message is cancelled when the student opted out of its channel (opted_out_channels), not only when
   they opted out of everything. notify_accepted checks the same when it queues; this covers a message queued before the
   opt-out, or sent again by the Admin after it. */
create or replace function b2b.notify_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
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
  v_maybe boolean;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    select x.id, x.attempts, x.lead_id, x.allocation_id, x.partner_id, x.channel, x.provider, x.updated_at, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null as done
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
      -- M34i: no answer, a timeout, a 5xx or a cut connection may mean the provider sent it. Only Resend, which received the
      -- notification's Idempotency-Key (notify_request), is asked again automatically; Meta and Brevo would send it twice.
      v_maybe := b2b.http_maybe_delivered(r.done, r.timed_out, r.status_code, r.error_msg);
      if r.attempts < 2 and (not v_maybe or r.provider = 'resend') then
        update b2b.student_notifications set status = 'scheduled', scheduled_for = now() + make_interval(mins => v_retry), net_request_id = null,
               error = v_why, updated_at = now() where id = r.id;
      else
        if v_maybe and r.provider is distinct from 'resend' then
          v_why := left('may have been sent (' || v_why || '), so it is not sent again automatically: check with the student before Send again', 300);
        end if;
        update b2b.student_notifications set status = 'failed', net_request_id = null, error = v_why, updated_at = now() where id = r.id;
        perform b2b.log_event('alert.notification_failed', r.lead_id, r.allocation_id, r.partner_id,
                              jsonb_build_object('channel', r.channel, 'error', v_why, 'maybe_sent', v_maybe and r.provider is distinct from 'resend'));
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
        when exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.lost_at is not null and a.lost_revived_at is null) then 'lost, in grace'
        when exists (select 1 from b2b.commission_disputes d where d.allocation_id = n.allocation_id and d.kind = 'duplicate_after_acceptance'
                        and d.status in ('open', 'upheld')) then 'duplicate claimed after acceptance'
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and (coalesce(l.is_opted_out, false) or coalesce(l.is_test, false)
                                                                                       or b2b.is_test_phone(l.whatsapp_number))) then 'student opted out or is a test lead'
        -- M34j: the channel's own opt-out (the unsubscribe link, or the B2C CRM's per-channel event)
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and n.channel = any (coalesce(l.opted_out_channels, '{}'))) then 'student opted out'
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
      -- M34e: the provider must be on the public internet
      if not b2b.url_allowed(req ->> 'url') then
        update b2b.student_notifications set status = 'failed', error = 'the provider address is not allowed (a private, loopback, link-local or metadata address)', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id,
                              jsonb_build_object('channel', n.channel, 'error', 'the provider address is not allowed'));
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
end $fn$;

-- ---------- (5) the CRM's web address in the notification settings ----------
/* As m9b, plus site_url: the public https address of this CRM's web app (no query or fragment; a trailing slash is
   removed), where /u/<lead>/<token> is served. A caller that does not send the key (a web release older than this file)
   keeps the stored value; an empty value clears it. */
create or replace function b2b.notification_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  w jsonb := coalesce(v -> 'whatsapp', '{}');
  m jsonb := coalesce(v -> 'email', '{}');
  v_id uuid;
  v_site text := case when p ? 'site_url' then nullif(rtrim(trim(coalesce(p ->> 'site_url', '')), '/'), '') else v ->> 'site_url' end;
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
  -- M34j
  if p ? 'site_url' and v_site is not null and (length(v_site) > 200 or v_site !~ '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$') then
    raise exception 'the CRM web address must be an https:// address without a query, e.g. https://b2b.eduwit.in' using errcode = '22023';
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
                               'unsubscribe_url', nullif(trim(p ->> 'unsubscribe_url'), ''), 'site_url', v_site,
                               'b2c_sends_own_notification', true, 'whatsapp', w, 'email', m);
  return b2b.set_setting('notifications', v, p_reason);
end $fn$;

/* As m9b; the footer shows a sample of the student's link once site_url is saved (lead 0 and a made-up token: the page
   answers it like any wrong link). */
create or replace function b2b.notification_preview(p_template_id bigint, p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
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
    'html', case when t.channel = 'email' then b2b.email_html(v_text, p.logo_url, p.brand_color, v ->> 'eduwit_support_contact',
                   coalesce(case when s ->> 'site_url' ~ '^https://' then rtrim(s ->> 'site_url', '/') || '/u/0/' || repeat('0', 40) end, s ->> 'unsubscribe_url')) end);
end $fn$;

/* As m9b, plus settings.site_url. */
create or replace function b2b.notifications_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', jsonb_build_object(
      'quiet_start', s ->> 'quiet_start', 'quiet_end', s ->> 'quiet_end', 'support_contact', s ->> 'support_contact', 'unsubscribe_url', s ->> 'unsubscribe_url',
      'site_url', s ->> 'site_url',
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
end $fn$;

-- create or replace keeps each replaced function's grants; the new functions' are set in (2).
