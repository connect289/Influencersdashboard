-- M34j unsubscribe links, rolled back (local: supabase/local-test.sh; staging: SQL editor after m34j; over an HTTP SQL API use
-- tests/m34j.http.sql instead, which never runs the sender). Builds its own fixtures (ZZ M34j partner, leads, allocations) and
-- points the email and WhatsApp providers at an address that does not exist. Every row must say ok = true.
--   0  the key is in Vault; the token is 40 hex characters, stable, different per lead and per channel; no key, no token
--   1  the link is <site_url>/u/<lead>/<token>, and null without an https site_url
--   2  unsubscribe: a wrong, short, empty or missing token, another lead's or another channel's token, and an unknown lead
--      are all answered false and change nothing; the lead's token records the opt-out once (email only), cancels the due
--      email, leaves WhatsApp alone, logs lead.unsubscribed, follows a merge, and is true again on a repeat
--   3  notify_request: the link in the footer and the text part, List-Unsubscribe and List-Unsubscribe-Post for Resend and
--      Brevo, the mailto from the first real email address; without a site_url the old footer and a mailto-only header
--   4  notify_tick: a due email to an opted-out student is cancelled, not sent; the WhatsApp message still goes
--   5  the limits per caller address, per lead and in total answer P0429; the caller's address is not stored
--   6  notification_settings_save / notifications_overview / notification_preview carry site_url
--   7  anon and authenticated can call none of the new functions; the service role only unsubscribe
--   8  the key is in no function result, setting, event or usage row
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon, service_role;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
-- a lead and its accepted partner allocation
create function pg_temp.lead(p_phone text, p_partner bigint) returns bigint language plpgsql as $f$
declare v_lead bigint; v_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'M34j ' || p_phone, 'interested_course', 'ZZM34j', 'programme_level', 'PG', 'source', 'website',
                               'classification', 'WARM')));
  select id into v_lead from public.student_leads where whatsapp_number = p_phone;
  insert into b2b.allocations (lead_id, destination_type, partner_id, status, mode, push_attempts)
  values (v_lead, 'partner', p_partner, 'queued', 'manual', 0) returning id into v_id;
  update b2b.allocations set status = 'pushing' where id = v_id;
  update b2b.allocations set status = 'accepted' where id = v_id;
  update public.student_leads set allocation_id = v_id, destination_type = 'partner' where id = v_lead;
  return v_lead;
end $f$;
-- one due message for a lead (its own kind, so several fit on one allocation)
create function pg_temp.msg(p_lead bigint, p_channel text, p_kind text) returns bigint language sql as $f$
  insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, template_id, language, variables, recipient, status, scheduled_for)
  select a.lead_id, a.id, a.partner_id, p_kind, p_channel,
         (select id from b2b.message_templates where kind = 'accepted' and channel = p_channel and language = 'en'), 'en',
         jsonb_build_object('student_first_name', 'Ravi', 'programme_label', 'BBA', 'partner_display_name', 'ZZ M34j', 'expected_contact_window', 'today',
                            'eduwit_support_contact', '+91 98100 00000'),
         case p_channel when 'whatsapp' then '919811035999' else 'zz-m34j@example.invalid' end, 'scheduled', now() - interval '1 day'
    from b2b.allocations a where a.lead_id = p_lead order by a.id desc limit 1
  returning id $f$;
create function pg_temp.tok(p_lead bigint, p_channel text default 'email') returns text language sql as $f$ select b2b.unsubscribe_token(p_lead, p_channel) $f$;
create function pg_temp.site(p_url text) returns void language sql as $f$
  update b2b.settings set value = case when p_url is null then value - 'site_url' else value || jsonb_build_object('site_url', p_url) end where key = 'notifications' $f$;
create function pg_temp.events(p_lead bigint) returns int language sql as $f$
  select count(*)::int from b2b.events where lead_id = p_lead and type = 'lead.unsubscribed' $f$;

-- fixtures: one partner, the providers at an address that does not exist, generous limits until section 5
do $x$ declare v_p bigint; w uuid; e uuid;
begin
  insert into b2b.partners (slug, name, display_name, status, api_base_url, notify_enabled)
  values ('zz-m34j-a', 'ZZ m34j a', 'ZZ M34j', 'active', 'https://zz-m34j.example.invalid/leads', true) returning id into v_p;
  perform pg_temp.set('P', v_p::text);
  w := vault.create_secret('zz-m34j-wa-token', 'zz_m34j_wa_' || txid_current(), 'rolled back');
  e := vault.create_secret('zz-m34j-mail-key', 'zz_m34j_mail_' || txid_current(), 'rolled back');
  update b2b.settings set value = (value - 'site_url' - 'unsubscribe_url') || jsonb_build_object('support_contact', '+91 98100 00000',
      'whatsapp', coalesce(value -> 'whatsapp', '{}') || jsonb_build_object('phone_number_id', '123456789012', 'token_secret_id', w, 'base_url', 'https://api.zz-m34j.example.invalid/wa'),
      'email', coalesce(value -> 'email', '{}') || jsonb_build_object('provider', 'resend', 'from_email', 'hello@zz-m34j.example.invalid', 'reply_to', null,
                                                                      'api_key_secret_id', e, 'base_url', 'https://api.zz-m34j.example.invalid/mail'))
   where key = 'notifications';
  update b2b.message_templates set wa_template = coalesce(wa_template, 'zz_m34j_template') where kind = 'accepted' and channel = 'whatsapp' and language = 'en';
  insert into b2b.settings (key, value) values ('api_limits', '{}') on conflict (key) do nothing;
  update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 100000, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';
  perform pg_temp.set('L1', pg_temp.lead('919811035001', v_p)::text);   -- unsubscribes
  perform pg_temp.set('L2', pg_temp.lead('919811035002', v_p)::text);   -- stays subscribed
  perform pg_temp.set('L3', pg_temp.lead('919811035003', v_p)::text);   -- already opted out of WhatsApp
  perform pg_temp.set('L4', pg_temp.lead('919811035004', v_p)::text);   -- merged into L5
  perform pg_temp.set('L5', pg_temp.lead('919811035005', v_p)::text);
  update public.student_leads set opted_out_channels = array['whatsapp'] where id = pg_temp.v('L3')::bigint;
  update public.student_leads set merged_into_id = pg_temp.v('L5')::bigint where id = pg_temp.v('L4')::bigint;
  perform pg_temp.set('KEY', (select decrypted_secret from vault.decrypted_secrets where name = 'b2b_unsubscribe_key'));
  perform pg_temp.set('UNKNOWN', (select (max(id) + 987654321)::text from public.student_leads));
end $x$;

-- ---------- (0) the key and the token ----------
insert into r select 'key_in_vault', count(*) = 1 and bool_and(decrypted_secret ~ '^[0-9a-f]{64}$'), count(*)::text
  from vault.decrypted_secrets where name = 'b2b_unsubscribe_key';
insert into r select 'token_shape', pg_temp.tok(pg_temp.v('L1')::bigint) ~ '^[0-9a-f]{40}$', null;
insert into r select 'token_stable', pg_temp.tok(pg_temp.v('L1')::bigint) = pg_temp.tok(pg_temp.v('L1')::bigint)
  and pg_temp.tok(pg_temp.v('L1')::bigint) = b2b.unsubscribe_token(pg_temp.v('L1')::bigint), null;
insert into r select 'token_differs_per_lead', pg_temp.tok(pg_temp.v('L1')::bigint) <> pg_temp.tok(pg_temp.v('L2')::bigint), null;
insert into r select 'token_differs_per_channel', pg_temp.tok(pg_temp.v('L1')::bigint, 'email') <> pg_temp.tok(pg_temp.v('L1')::bigint, 'whatsapp'), null;
insert into r select 'token_null_inputs', b2b.unsubscribe_token(null) is null and b2b.unsubscribe_token(1, null) is null, null;
-- not the legacy token (public.crm_unsubscribe_token: an HMAC of the bare lead id), whatever key that one used
insert into r select 'token_not_the_legacy_form',
  pg_temp.tok(pg_temp.v('L1')::bigint) <> left(encode(extensions.hmac(pg_temp.v('L1'), pg_temp.v('KEY'), 'sha256'), 'hex'), 40), null;
do $x$ declare v_id uuid; a text; b text; c boolean;
begin
  select id into v_id from vault.secrets where name = 'b2b_unsubscribe_key';
  perform pg_temp.set('T1', pg_temp.tok(pg_temp.v('L1')::bigint));
  perform pg_temp.site('https://crm.zz-m34j.example.invalid');
  perform vault.update_secret(v_id, null, 'zz_m34j_parked_key');
  a := b2b.unsubscribe_token(pg_temp.v('L1')::bigint);
  b := b2b.unsubscribe_link(pg_temp.v('L1')::bigint);
  c := b2b.unsubscribe(pg_temp.v('L1')::bigint, pg_temp.v('T1'), 'email', '203.0.113.1', 'link');
  perform vault.update_secret(v_id, null, 'b2b_unsubscribe_key');
  perform pg_temp.site(null);
  insert into r values ('no_key_no_token_no_link_no_opt_out', a is null and b is null and c is false
                          and not exists (select 1 from public.student_leads where id = pg_temp.v('L1')::bigint and 'email' = any (coalesce(opted_out_channels, '{}'))),
                        coalesce(a, 'null') || ' / ' || coalesce(b, 'null') || ' / ' || c);
  insert into r values ('token_back_with_the_key', pg_temp.tok(pg_temp.v('L1')::bigint) = pg_temp.v('T1'), null);
end $x$;

-- ---------- (1) the link ----------
insert into r select 'link_null_without_site_url', b2b.unsubscribe_link(pg_temp.v('L1')::bigint) is null, null;
select pg_temp.site('http://crm.zz-m34j.example.invalid');
insert into r select 'link_null_for_http_site_url', b2b.unsubscribe_link(pg_temp.v('L1')::bigint) is null, null;
select pg_temp.site('https://crm.zz-m34j.example.invalid/');
insert into r select 'link_shape', b2b.unsubscribe_link(pg_temp.v('L1')::bigint) = 'https://crm.zz-m34j.example.invalid/u/' || pg_temp.v('L1') || '/' || pg_temp.v('T1'),
  b2b.unsubscribe_link(pg_temp.v('L1')::bigint);
select pg_temp.set('LINK1', b2b.unsubscribe_link(pg_temp.v('L1')::bigint));
select pg_temp.set('LINK2', b2b.unsubscribe_link(pg_temp.v('L2')::bigint));

-- ---------- (2) the opt-out ----------
select pg_temp.set('N1_MAIL', pg_temp.msg(pg_temp.v('L1')::bigint, 'email', 'm34j_due')::text);
select pg_temp.set('N1_WA', pg_temp.msg(pg_temp.v('L1')::bigint, 'whatsapp', 'm34j_due')::text);
select pg_temp.set('N2_MAIL', pg_temp.msg(pg_temp.v('L2')::bigint, 'email', 'm34j_due')::text);
do $x$ declare l1 bigint := pg_temp.v('L1')::bigint; l2 bigint := pg_temp.v('L2')::bigint; tk text := pg_temp.v('T1'); u bigint := pg_temp.v('UNKNOWN')::bigint;
  wrong text; x boolean[]; y boolean; z boolean; n0 int; n1 int;
begin
  wrong := case when left(tk, 1) = '0' then '1' else '0' end || substr(tk, 2);   -- right length, one character off
  x := array[
    b2b.unsubscribe(l1, wrong, 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, left(tk, 39), 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, tk || '0', 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, upper(tk), 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, '', 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, null, 'email', '203.0.113.2', 'one_click'),
    b2b.unsubscribe(l1, repeat('a', 5000), 'email', '203.0.113.2', 'link'),
    b2b.unsubscribe(l1, pg_temp.tok(l2), 'email', '203.0.113.2', 'link'),              -- another lead's token
    b2b.unsubscribe(l1, pg_temp.tok(l1, 'whatsapp'), 'email', '203.0.113.2', 'link'),  -- another channel's token
    b2b.unsubscribe(l1, pg_temp.tok(l1, 'whatsapp'), 'whatsapp', '203.0.113.2', 'link'),  -- only email can be unsubscribed here
    b2b.unsubscribe(l1, tk, 'sms', '203.0.113.2', 'link'),
    b2b.unsubscribe(null, tk, 'email', '203.0.113.2', 'link')];
  insert into r values ('wrong_tokens_refused', not (true = any (x)) and array_position(x, null) is null, x::text);
  insert into r values ('refused_changes_nothing',
    (select coalesce(opted_out_channels, '{}') = '{}' and not is_opted_out from public.student_leads where id = l1) and pg_temp.events(l1) = 0
    and (select status = 'scheduled' from b2b.student_notifications where id = pg_temp.v('N1_MAIL')::bigint), null);

  -- an unknown lead and a wrong token: the same answer, the same count, nothing else written
  select coalesce(sum(n), 0) into n0 from b2b.unsubscribe_usage where bucket in ('lead:' || l1, 'lead:' || u);
  y := b2b.unsubscribe(u, wrong, 'email', '203.0.113.2', 'link');
  z := b2b.unsubscribe(l1, wrong, 'email', '203.0.113.2', 'link');
  select coalesce(sum(n), 0) into n1 from b2b.unsubscribe_usage where bucket in ('lead:' || l1, 'lead:' || u);
  insert into r values ('unknown_lead_same_as_wrong_token', y is false and z is false and n1 = n0 + 2 and pg_temp.events(u) = 0
                          and (select n from b2b.unsubscribe_usage where bucket = 'lead:' || u) = 1, y || ' / ' || z);

  -- the lead's own token
  y := b2b.unsubscribe(l1, tk, 'email', '203.0.113.2', 'link');
  insert into r values ('own_token_accepted', y is true, null);
  insert into r values ('opt_out_recorded_email_only',
    (select opted_out_channels = array['email'] and not is_opted_out and updated_by = 'b2b:unsubscribe' from public.student_leads where id = l1), null);
  insert into r values ('due_email_cancelled',
    (select status = 'cancelled' and error = 'student opted out of email (unsubscribe link)' from b2b.student_notifications where id = pg_temp.v('N1_MAIL')::bigint), null);
  insert into r values ('due_whatsapp_untouched', (select status = 'scheduled' and error is null from b2b.student_notifications where id = pg_temp.v('N1_WA')::bigint), null);
  insert into r values ('other_lead_untouched', (select coalesce(opted_out_channels, '{}') = '{}' from public.student_leads where id = l2)
    and (select status = 'scheduled' from b2b.student_notifications where id = pg_temp.v('N2_MAIL')::bigint), null);
  insert into r select 'event_logged', count(*) = 1 and bool_and(actor_type = 'student' and payload ->> 'channel' = 'email' and payload ->> 'source' = 'link'
                                                                and (payload ->> 'link_lead_id')::bigint = l1), max(payload::text)
    from b2b.events where lead_id = l1 and type = 'lead.unsubscribed';

  -- a repeat (the page's button after the mail provider's one-click, or twice): true, nothing more written
  y := b2b.unsubscribe(l1, tk, 'email', '203.0.113.3', 'one_click');
  z := b2b.unsubscribe(l1, tk);
  insert into r values ('repeat_is_true_and_writes_nothing', y is true and z is true and pg_temp.events(l1) = 1
    and (select opted_out_channels = array['email'] from public.student_leads where id = l1), null);
end $x$;
do $x$ declare l3 bigint := pg_temp.v('L3')::bigint; l4 bigint := pg_temp.v('L4')::bigint; l5 bigint := pg_temp.v('L5')::bigint; y boolean;
begin
  y := b2b.unsubscribe(l3, pg_temp.tok(l3), 'email', '203.0.113.4', 'one_click');
  insert into r values ('added_to_existing_channels', y and (select opted_out_channels = array['email', 'whatsapp'] and not is_opted_out from public.student_leads where id = l3)
    and (select payload ->> 'source' = 'one_click' from b2b.events where lead_id = l3 and type = 'lead.unsubscribed'), null);
  -- an old email's link of a merged lead also stops the kept lead's emails
  y := b2b.unsubscribe(l4, pg_temp.tok(l4), 'email', '203.0.113.4', 'link');
  insert into r values ('merged_lead_reaches_the_kept_lead', y
    and (select 'email' = any (opted_out_channels) from public.student_leads where id = l4)
    and (select 'email' = any (opted_out_channels) from public.student_leads where id = l5)
    and (select (payload ->> 'link_lead_id')::bigint = l4 from b2b.events where lead_id = l5 and type = 'lead.unsubscribed'), null);
end $x$;
-- the service role (the web app's server) can call it; the answer is a boolean and nothing else
set local role service_role;
insert into r select 'service_role_call', b2b.unsubscribe(pg_temp.v('UNKNOWN')::bigint, repeat('0', 40), 'email', '203.0.113.5', 'link') is false, null;
reset role;

-- ---------- (3) the provider request ----------
do $x$ declare l2 bigint := pg_temp.v('L2')::bigint; n b2b.student_notifications; q jsonb; b jsonb; lk text := pg_temp.v('LINK2'); wa jsonb;
begin
  select * into n from b2b.student_notifications where id = pg_temp.v('N2_MAIL')::bigint;
  -- Resend, support contact is a phone number, no reply-to: the mailto is the sender address
  q := b2b.notify_request(n); b := q -> 'body';
  insert into r values ('resend_headers', b -> 'headers' ->> 'List-Unsubscribe' = '<' || lk || '/one-click>, <mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe>'
    and b -> 'headers' ->> 'List-Unsubscribe-Post' = 'List-Unsubscribe=One-Click', b -> 'headers' ->> 'List-Unsubscribe');
  insert into r values ('resend_footer_and_text', b ->> 'html' like '%<a href="' || lk || '" style="color:#6b7385">Unsubscribe</a>%'
    and b ->> 'text' like '%' || E'\n\nUnsubscribe: ' || lk and b ->> 'html' not like '%mailto:%', right(b ->> 'text', 120));
  insert into r values ('resend_request_otherwise_as_before', q ->> 'provider' = 'resend' and q ->> 'url' = 'https://api.zz-m34j.example.invalid/mail/emails'
    and q -> 'headers' ->> 'Idempotency-Key' = 'notify-' || n.id and q -> 'headers' ->> 'Authorization' = 'Bearer zz-m34j-mail-key'
    and b ->> 'from' = 'Team Eduwit <hello@zz-m34j.example.invalid>' and b -> 'to' = jsonb_build_array(n.recipient) and not (b ? 'reply_to')
    and (select array_agg(k order by k) from jsonb_object_keys(b) k) = array['from', 'headers', 'html', 'subject', 'text', 'to'], null);
  insert into r values ('link_is_this_leads', lk = 'https://crm.zz-m34j.example.invalid/u/' || l2 || '/' || pg_temp.tok(l2) and lk <> pg_temp.v('LINK1'), null);

  -- Brevo with a reply-to: the mailto is the reply-to
  update b2b.settings set value = jsonb_set(jsonb_set(value, '{email,provider}', '"brevo"'), '{email,reply_to}', '"help@zz-m34j.example.invalid"') where key = 'notifications';
  q := b2b.notify_request(n); b := q -> 'body';
  insert into r values ('brevo_headers', q ->> 'provider' = 'brevo'
    and b -> 'headers' ->> 'List-Unsubscribe' = '<' || lk || '/one-click>, <mailto:help@zz-m34j.example.invalid?subject=Unsubscribe>'
    and b -> 'headers' ->> 'List-Unsubscribe-Post' = 'List-Unsubscribe=One-Click', b -> 'headers' ->> 'List-Unsubscribe');
  insert into r values ('brevo_footer_and_text', b ->> 'htmlContent' like '%<a href="' || lk || '"%' and b ->> 'textContent' like '%' || E'\n\nUnsubscribe: ' || lk
    and b -> 'replyTo' ->> 'email' = 'help@zz-m34j.example.invalid' and q -> 'headers' ->> 'api-key' = 'zz-m34j-mail-key', null);

  -- a support contact that is an email address comes before the sender, after the reply-to
  update b2b.settings set value = jsonb_set(value, '{email,reply_to}', 'null') || '{"support_contact": "care@zz-m34j.example.invalid"}' where key = 'notifications';
  insert into r values ('mailto_prefers_support_email', b2b.notify_request(n) -> 'body' -> 'headers' ->> 'List-Unsubscribe' like '%<mailto:care@zz-m34j.example.invalid?subject=Unsubscribe>', null);
  update b2b.settings set value = jsonb_set(value, '{email,provider}', '"resend"') || '{"support_contact": "+91 98100 00000"}' where key = 'notifications';

  -- no site_url: the old footer (the configured link, else a mailto) and a mailto-only header; nothing points at the web app
  perform pg_temp.site(null);
  q := b2b.notify_request(n); b := q -> 'body';
  insert into r values ('fallback_without_site_url', b -> 'headers' = jsonb_build_object('List-Unsubscribe', '<mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe>')
    and b ->> 'html' like '%<a href="mailto:hello@zz-m34j.example.invalid?subject=Unsubscribe"%' and b ->> 'text' not like '%Unsubscribe%' and b::text not like '%/u/%',
    b -> 'headers' ->> 'List-Unsubscribe');
  update b2b.settings set value = value || '{"unsubscribe_url": "https://zz-m34j.example.invalid/old-unsubscribe"}' where key = 'notifications';
  b := b2b.notify_request(n) -> 'body';
  insert into r values ('fallback_keeps_configured_link', b ->> 'html' like '%<a href="https://zz-m34j.example.invalid/old-unsubscribe"%'
    and not (b -> 'headers' ? 'List-Unsubscribe-Post'), null);
  -- with a site_url the lead's own link wins over the configured one
  perform pg_temp.site('https://crm.zz-m34j.example.invalid');
  b := b2b.notify_request(n) -> 'body';
  insert into r values ('own_link_wins_over_configured_link', b ->> 'html' like '%<a href="' || lk || '"%' and b ->> 'html' not like '%old-unsubscribe%', null);
  update b2b.settings set value = value - 'unsubscribe_url' where key = 'notifications';

  -- WhatsApp: as before, no email headers
  select * into n from b2b.student_notifications where id = pg_temp.v('N1_WA')::bigint;
  wa := b2b.notify_request(n);
  insert into r values ('whatsapp_request_unchanged', wa ->> 'provider' = 'meta_cloud' and not (wa -> 'body' ? 'headers') and wa::text not like '%nsubscribe%'
    and wa ->> 'url' = 'https://api.zz-m34j.example.invalid/wa/v21.0/123456789012/messages'
    and jsonb_array_length(wa #> '{body,template,components,0,parameters}') = 5, null);
end $x$;

-- ---------- (4) the sender ----------
do $x$ declare l1 bigint := pg_temp.v('L1')::bigint; l2 bigint := pg_temp.v('L2')::bigint; later bigint; x jsonb; a b2b.student_notifications; b b2b.student_notifications;
  c b2b.student_notifications; body jsonb; n_before bigint;
begin
  insert into b2b.live_switches (scope, live, reason) values ('email', true, 'm34j test'), ('whatsapp', true, 'm34j test') on conflict (scope) do update set live = true;
  -- queued after the opt-out (an Admin's "Send again", or a row that slipped past the queueing check)
  later := pg_temp.msg(l1, 'email', 'm34j_later');
  select count(*) into n_before from net.http_request_queue;
  x := b2b.notify_tick();
  select * into a from b2b.student_notifications where id = later;
  select * into b from b2b.student_notifications where id = pg_temp.v('N1_WA')::bigint;
  select * into c from b2b.student_notifications where id = pg_temp.v('N2_MAIL')::bigint;
  insert into r values ('later_email_cancelled_not_sent', a.status = 'cancelled' and a.error = 'student opted out' and a.net_request_id is null and a.attempts = 0,
                        a.status || ' / ' || coalesce(a.error, '-'));
  insert into r values ('whatsapp_still_sent', b.status = 'sending' and b.net_request_id is not null, b.status || ' / ' || coalesce(b.error, '-'));
  insert into r values ('subscribed_lead_still_sent', c.status = 'sending' and c.net_request_id is not null, c.status || ' / ' || coalesce(c.error, '-'));
  insert into r select 'nothing_queued_for_the_opted_out_email', count(*) = 0, count(*)::text
    from net.http_request_queue q where convert_from(q.body, 'utf8') like '%' || pg_temp.v('LINK1') || '%';
  select convert_from(q.body, 'utf8')::jsonb into body from net.http_request_queue q where q.id = c.net_request_id;
  insert into r values ('sent_request_carries_link_and_headers', body ->> 'html' like '%' || pg_temp.v('LINK2') || '%'
    and body -> 'headers' ->> 'List-Unsubscribe' like '<' || pg_temp.v('LINK2') || '/one-click>, <mailto:%'
    and body -> 'headers' ->> 'List-Unsubscribe-Post' = 'List-Unsubscribe=One-Click', body -> 'headers' ->> 'List-Unsubscribe');
end $x$;
insert into r select 'notify_tick_keeps_earlier_rules', prosrc ~ 'b2b.url_allowed' and prosrc ~ 'http_maybe_delivered' and prosrc ~ 'student opted out or is a test lead'
                                                        and prosrc ~ 'opted_out_channels', null
  from pg_proc where oid = 'b2b.notify_tick()'::regprocedure;
insert into r select 'resend_idempotency_key_kept', prosrc ~ $q$'Idempotency-Key', 'notify-' \|\| n.id$q$, null
  from pg_proc where oid = 'b2b.notify_request(b2b.student_notifications)'::regprocedure;
-- queueing after the opt-out: notify_accepted (m31i) skips the email, as it already did for the B2C CRM's opt-outs
do $x$ declare l1 bigint := pg_temp.v('L1')::bigint; v_a bigint; n int;
begin
  update public.student_leads set email_id = 'zz-m34j-l1@example.invalid' where id = l1;
  update b2b.message_templates set status = 'active' where kind = 'accepted' and language = 'en';
  select id into v_a from b2b.allocations where lead_id = l1;
  delete from b2b.student_notifications where allocation_id = v_a and kind = 'accepted';
  n := b2b.notify_accepted(v_a);
  insert into r select 'queueing_skips_the_opted_out_channel', n = 1 and count(*) filter (where channel = 'email' and status = 'skipped' and error = 'student opted out') = 1
                         and count(*) filter (where channel = 'whatsapp' and status = 'scheduled') = 1, n::text
    from b2b.student_notifications where allocation_id = v_a and kind = 'accepted';
end $x$;

-- ---------- (5) the limits ----------
update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 3, "per_lead": 5, "total": 100000}}' where key = 'api_limits';
do $x$ declare u bigint := pg_temp.v('UNKNOWN')::bigint; e text; i int; ok boolean := true; h text; n0 int;
  v_none text := 'ip:' || left(encode(extensions.hmac('unknown', pg_temp.v('KEY'), 'sha256'), 'hex'), 16);
begin
  -- per caller address: three pass (each for a different lead), the fourth is refused
  for i in 1..3 loop ok := ok and b2b.unsubscribe(u + i, repeat('0', 40), 'email', '198.51.100.7', 'link') is false; end loop;
  e := pg_temp.err(format($q$select b2b.unsubscribe(%s, repeat('0', 40), 'email', '198.51.100.7', 'link')$q$, u + 4));
  insert into r values ('limit_per_caller_address', ok and e like 'P0429 rate limited%', e);
  begin
    perform b2b.unsubscribe(u + 4, repeat('0', 40), 'email', '198.51.100.7', 'link');
  exception when sqlstate 'P0429' then get stacked diagnostics h = pg_exception_hint;
  end;
  insert into r values ('limit_hint_for_retry_after', h ~ '^retry after [0-9]{1,2} seconds$', h);
  -- the bucket is a keyed hash of the address; the refused call rolled back, so it stays at the limit and left no lead row
  insert into r select 'refused_call_is_not_counted', count(*) = 1 and max(n) = 3 and not exists (select 1 from b2b.unsubscribe_usage where bucket = 'lead:' || (u + 4)), max(n)::text
    from b2b.unsubscribe_usage where bucket = 'ip:' || left(encode(extensions.hmac('198.51.100.7', pg_temp.v('KEY'), 'sha256'), 'hex'), 16);
  insert into r values ('another_address_still_served', pg_temp.err(format($q$select b2b.unsubscribe(%s, repeat('0', 40), 'email', '198.51.100.8', 'link')$q$, u + 4)) = 'ok', null);
  -- per lead: five from different addresses pass, the sixth is refused, even with the right token
  ok := true;
  for i in 1..5 loop ok := ok and b2b.unsubscribe(pg_temp.v('L2')::bigint, repeat('0', 40), 'email', '198.51.100.' || (20 + i), 'link') is false; end loop;
  e := pg_temp.err(format($q$select b2b.unsubscribe(%s, %L, 'email', '198.51.100.30', 'link')$q$, pg_temp.v('L2'), pg_temp.tok(pg_temp.v('L2')::bigint)));
  insert into r values ('limit_per_lead', ok and e like 'P0429 rate limited%'
    and (select coalesce(opted_out_channels, '{}') = '{}' from public.student_leads where id = pg_temp.v('L2')::bigint), e);
  -- in total
  update b2b.settings set value = value || jsonb_build_object('unsubscribe', jsonb_build_object('per_ip', 100000, 'per_lead', 100000,
           'total', (select n from b2b.unsubscribe_usage where bucket = 'all'))) where key = 'api_limits';
  e := pg_temp.err(format($q$select b2b.unsubscribe(%s, repeat('0', 40), 'email', '198.51.100.40', 'link')$q$, u + 50));
  insert into r values ('limit_in_total', e like 'P0429 rate limited%', e);
  -- the defaults (60 per address, 10 per lead, 600 in total) when the setting has no entry or a bad one
  update b2b.settings set value = (value - 'unsubscribe') || '{"unsubscribe": {"per_lead": "many"}}' where key = 'api_limits';
  delete from b2b.unsubscribe_usage where bucket = 'all';
  ok := true;
  for i in 1..10 loop ok := ok and b2b.unsubscribe(u + 60, repeat('0', 40), 'email', '198.51.100.' || (50 + i), 'link') is false; end loop;
  e := pg_temp.err(format($q$select b2b.unsubscribe(%s, repeat('0', 40), 'email', '198.51.100.99', 'link')$q$, u + 60));
  insert into r values ('default_limit_per_lead_is_10', ok and e like 'P0429 rate limited%', e);
  -- a caller without an address shares one bucket; old minutes are removed by the next call
  insert into b2b.unsubscribe_usage (bucket, minute, n) values ('lead:zz-m34j-old', date_trunc('minute', now()) - interval '2 hours', 9);
  select coalesce(max(n), 0) into n0 from b2b.unsubscribe_usage where bucket = v_none;
  ok := b2b.unsubscribe(u + 70, repeat('0', 40)) is false and b2b.unsubscribe(u + 71, repeat('0', 40), 'email', '  ', 'link') is false;
  insert into r select 'no_address_one_bucket', ok and count(*) = 1 and max(n) = n0 + 2, max(n)::text from b2b.unsubscribe_usage where bucket = v_none;
  insert into r values ('old_minutes_removed', not exists (select 1 from b2b.unsubscribe_usage where bucket = 'lead:zz-m34j-old'), null);
  insert into r select 'caller_address_not_stored', count(*) > 0 and bool_and(bucket ~ '^(ip:[0-9a-f]{16}|lead:[0-9]+|all)$'), string_agg(distinct split_part(bucket, ':', 1), ',')
    from b2b.unsubscribe_usage;
end $x$;
update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 100000, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';

-- ---------- (6) the CRM's web address in the notification settings ----------
insert into auth.users (id, email, aud, role, email_confirmed_at)
values ('aaaaaaaa-0000-0000-0000-0000000034b1', 'zz-m34j-admin@test.local', 'authenticated', 'authenticated', now());
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000034b1', 'zz-m34j-admin@test.local');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000034b1","role":"authenticated","aal":"aal2","email":"zz-m34j-admin@test.local"}', true);
do $x$ declare base jsonb := jsonb_build_object('quiet_start', '08:00', 'quiet_end', '21:00', 'support_contact', '+91 98100 00000', 'unsubscribe_url', '',
    'whatsapp', jsonb_build_object('phone_number_id', '123456789012', 'api_version', 'v21.0', 'token', ''),
    'email', jsonb_build_object('provider', 'resend', 'from_email', 'hello@zz-m34j.example.invalid', 'from_name', 'Team Eduwit', 'reply_to', '', 'api_key', ''));
  e text; o jsonb; pv jsonb; s jsonb;
begin
  perform b2b.notification_settings_save(base || '{"site_url": " https://crm2.zz-m34j.example.invalid/ "}', 'm34j test: web address');
  insert into r select 'site_url_saved_trimmed', value ->> 'site_url' = 'https://crm2.zz-m34j.example.invalid', value ->> 'site_url' from b2b.settings where key = 'notifications';
  insert into r values ('link_follows_saved_site_url', b2b.unsubscribe_link(pg_temp.v('L2')::bigint) like 'https://crm2.zz-m34j.example.invalid/u/%', null);
  -- a caller that does not send the key (a web release older than m34j) keeps the stored address
  perform b2b.notification_settings_save(base, 'm34j test: older web release');
  select value into s from b2b.settings where key = 'notifications';
  insert into r values ('site_url_kept_when_not_sent', s ->> 'site_url' = 'https://crm2.zz-m34j.example.invalid', s ->> 'site_url');
  insert into r values ('other_settings_saved_as_before', s ->> 'support_contact' = '+91 98100 00000' and s -> 'email' ->> 'from_email' = 'hello@zz-m34j.example.invalid'
    and s -> 'email' ->> 'api_key_secret_id' is not null and s -> 'whatsapp' ->> 'token_secret_id' is not null and s ->> 'unsubscribe_url' is null
    and (s ->> 'b2c_sends_own_notification')::boolean, null);
  o := b2b.notifications_overview();
  insert into r values ('overview_has_site_url', o -> 'settings' ->> 'site_url' = 'https://crm2.zz-m34j.example.invalid' and o -> 'settings' -> 'email' ? 'has_key'
    and not (o -> 'settings' -> 'email' ? 'api_key_secret_id'), null);
  pv := b2b.notification_preview((select id from b2b.message_templates where kind = 'accepted' and channel = 'email' and language = 'en'), pg_temp.v('P')::bigint);
  insert into r values ('preview_shows_a_sample_link', pv ->> 'html' like '%<a href="https://crm2.zz-m34j.example.invalid/u/0/' || repeat('0', 40) || '"%', null);
  insert into r select 'bad_site_url_refused', bool_and(pg_temp.err(format('select b2b.notification_settings_save(%L::jsonb || jsonb_build_object(''site_url'', %L), ''m34j test'')', base, u))
                          like '22023 the CRM web address must be%'), null
    from unnest(array['http://crm.zz-m34j.example.invalid', 'https://crm.zz-m34j.example.invalid/?next=x', 'https://crm.zz-m34j.example.invalid/#a',
                      'crm.zz-m34j.example.invalid', 'https://user:pw@crm.zz-m34j.example.invalid', 'javascript:alert(1)', 'https://' || repeat('a', 200) || '.in']) u;
  insert into r select 'refused_save_changes_nothing', value ->> 'site_url' = 'https://crm2.zz-m34j.example.invalid', null from b2b.settings where key = 'notifications';
  perform b2b.notification_settings_save(base || '{"site_url": ""}', 'm34j test: cleared');
  insert into r select 'site_url_cleared_by_empty', value ->> 'site_url' is null and b2b.unsubscribe_link(pg_temp.v('L2')::bigint) is null, null from b2b.settings where key = 'notifications';
  pv := b2b.notification_preview((select id from b2b.message_templates where kind = 'accepted' and channel = 'email' and language = 'en'), pg_temp.v('P')::bigint);
  insert into r values ('preview_without_site_url_as_before', pv ->> 'html' not like '%/u/0/%' and pv ->> 'html' not like '%Unsubscribe</a>%', null);
  perform b2b.notification_settings_save(base || '{"site_url": "https://crm.zz-m34j.example.invalid"}', 'm34j test: web address again');
end $x$;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
insert into r select 'settings_save_needs_an_admin',
  pg_temp.err($q$select b2b.notification_settings_save('{"quiet_start":"08:00","quiet_end":"21:00","support_contact":"+91 98100 00000","site_url":"https://x.example.invalid"}', 'm34j test')$q$)
    like '42501%', null;

-- ---------- (7) who may call what ----------
insert into r select 'new_functions_closed_to_clients', bool_and(not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
                                                                 and not has_function_privilege('public', f, 'execute')), string_agg(f, ', ')
  from unnest(array['b2b.unsubscribe_token(bigint, text)', 'b2b.unsubscribe_link(bigint, text)', 'b2b.unsubscribe(bigint, text, text, text, text)']) f;
insert into r select 'service_role_only_the_opt_out', has_function_privilege('service_role', 'b2b.unsubscribe(bigint, text, text, text, text)', 'execute')
  and not has_function_privilege('service_role', 'b2b.unsubscribe_token(bigint, text)', 'execute')
  and not has_function_privilege('service_role', 'b2b.unsubscribe_link(bigint, text)', 'execute'), null;
insert into r select 'usage_table_closed_to_clients', relrowsecurity and not has_table_privilege('anon', c.oid, 'select, insert, update, delete')
  and not has_table_privilege('authenticated', c.oid, 'select, insert, update, delete') and not exists (select 1 from pg_policy p where p.polrelid = c.oid), null
  from pg_class c where c.oid = 'b2b.unsubscribe_usage'::regclass;
insert into r select 'replaced_functions_keep_their_grants',
  bool_and(not has_function_privilege('anon', f, 'execute')) and bool_and(has_function_privilege('authenticated', f, 'execute') = (f ~ '^b2b\.notification'))
  and bool_and(has_function_privilege('service_role', f, 'execute')), null
  from unnest(array['b2b.notify_request(b2b.student_notifications)', 'b2b.notify_tick()', 'b2b.notification_settings_save(jsonb, text)',
                    'b2b.notification_preview(bigint, bigint)', 'b2b.notifications_overview()']) f;
insert into r select 'definer_with_empty_search_path', bool_and(p.prosecdef and p.proconfig @> array['search_path=""']), string_agg(p.proname, ', ')
  from pg_proc p where p.pronamespace = 'b2b'::regnamespace and p.proname in ('unsubscribe_token', 'unsubscribe_link', 'unsubscribe');
do $x$ declare e1 text; e2 text; e3 text;
begin
  set local role anon;
  e1 := pg_temp.err($q$select b2b.unsubscribe(1, repeat('0', 40))$q$);
  e2 := pg_temp.err($q$select b2b.unsubscribe_token(1)$q$);
  reset role;
  set local role authenticated;
  e3 := pg_temp.err($q$select b2b.unsubscribe(1, repeat('0', 40))$q$) || ' / ' || pg_temp.err($q$select b2b.unsubscribe_link(1)$q$) || ' / ' || pg_temp.err($q$select count(*) from b2b.unsubscribe_usage$q$);
  reset role;
  insert into r values ('anon_refused', e1 like '42501%' and e2 like '42501%', e1);
  insert into r values ('authenticated_refused', e3 ~ '^42501.* / 42501.* / 42501', e3);
end $x$;

-- ---------- (8) the key stays in Vault ----------
do $x$ declare k text := pg_temp.v('KEY'); l2 bigint := pg_temp.v('L2')::bigint; n b2b.student_notifications; out text := ''; e text;
begin
  select * into n from b2b.student_notifications where id = pg_temp.v('N2_MAIL')::bigint;
  out := out || coalesce(b2b.unsubscribe_token(l2), '') || coalesce(b2b.unsubscribe_token(l2, 'whatsapp'), '') || coalesce(b2b.unsubscribe_link(l2), '')
             || b2b.unsubscribe(l2, k)::text || b2b.unsubscribe(l2, pg_temp.tok(l2), 'email', k, 'link')::text
             || b2b.notify_request(n)::text;
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000034b1","role":"authenticated","aal":"aal2","email":"zz-m34j-admin@test.local"}', true) into e;
  out := out || b2b.notifications_overview()::text
             || b2b.notification_preview((select id from b2b.message_templates where kind = 'accepted' and channel = 'email' and language = 'en'), pg_temp.v('P')::bigint)::text;
  update b2b.settings set value = value || '{"unsubscribe": {"per_ip": 0, "per_lead": 100000, "total": 100000}}' where key = 'api_limits';
  out := out || pg_temp.err(format($q$select b2b.unsubscribe(%s, %L, 'email', %L, 'link')$q$, l2, k, k));
  insert into r values ('key_in_no_function_result', length(k) = 64 and length(out) > 500 and position(k in out) = 0, length(out)::text);
  insert into r values ('key_in_no_table', not exists (select 1 from b2b.settings where value::text like '%' || k || '%')
    and not exists (select 1 from b2b.events where payload::text like '%' || k || '%')
    and not exists (select 1 from b2b.unsubscribe_usage where bucket like '%' || k || '%')
    and not exists (select 1 from b2b.student_notifications where coalesce(error, '') like '%' || k || '%'), null);
  insert into r select 'key_not_in_function_source', bool_and(position(k in p.prosrc) = 0) and count(*) > 100, count(*)::text
    from pg_proc p where p.pronamespace = 'b2b'::regnamespace;
end $x$;

select name, ok, detail from r order by name;
rollback;
