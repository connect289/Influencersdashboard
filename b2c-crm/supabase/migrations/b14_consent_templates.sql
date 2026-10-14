-- B2C CRM b14 (Phase 2): consent per channel, suppression, the marketing guardrail, marketing templates and sends.
-- Staging first. Idempotent.
--   consents, suppressions          per-channel marketing consent with text, source and time; a global suppression list (B9.6)
--   marketing_consent() / opt_out() recorded here and sent to the B2B CRM at once (b2ccrm.marketing_consent, b2ccrm.opted_out)
--   may_market()                    the one guardrail check every journey and campaign send goes through (B9.4, B6.1)
--   email_templates, wa_template_save()   marketing templates (Admin and Marketing); sales WhatsApp templates stay Admin only
--   queue_marketing_wa() / queue_marketing_email()   a marketing message, through the same send queue as everything else

-- ---------- consent and suppression ----------
create table if not exists b2c.consents (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  channel text not null check (channel in ('whatsapp', 'email')),
  given boolean not null,
  text_version text,
  source text not null,          -- witty, wa_button, web_form, counsellor_call, unsubscribe_link, stop_word, admin, b2b_record
  at timestamptz not null default now(),
  actor_id uuid
);
create index if not exists consents_lead on b2c.consents (lead_id, channel, at desc);

create table if not exists b2c.suppressions (
  value_norm text primary key,   -- a phone (91XXXXXXXXXX) or a lower-case email
  kind text not null check (kind in ('phone', 'email')),
  reason text not null,
  at timestamptz not null default now(),
  actor_id uuid,
  lifted_at timestamptz
);

alter table b2c.wa_messages add column if not exists campaign_id bigint;
alter table b2c.wa_messages add column if not exists journey_run_id bigint;
alter table b2c.emails add column if not exists purpose text;
alter table b2c.emails add column if not exists campaign_id bigint;
alter table b2c.emails add column if not exists journey_run_id bigint;
alter table b2c.emails add column if not exists marketing_template_id bigint;
alter table b2c.wa_templates add column if not exists tags text[] not null default '{}';
alter table b2c.wa_templates add column if not exists header jsonb;
alter table b2c.wa_templates add column if not exists archived_at timestamptz;
alter table b2c.wa_templates add column if not exists uses int not null default 0;
create index if not exists wa_messages_marketing on b2c.wa_messages (lead_id, created_at desc) where purpose in ('journey', 'campaign', 'marketing');
create index if not exists emails_marketing on b2c.emails (lead_id, created_at desc) where purpose in ('journey', 'campaign', 'marketing');

insert into b2c.settings (key, value) values
  ('marketing_email', '{"from": "Eduwit <connect@eduwit.in>", "reply_to": null}'),
  ('wa_rates', '{"marketing": 0.88, "utility": 0.13, "authentication": 0.13, "service": 0, "currency": "INR", "note": "Meta India rate card estimate per delivered template; edit when Meta changes it"}'),
  ('nurture', '{"witty_quiet_minutes": 30, "dormant_after_months": 12, "reply_confidence": 0.8, "ab_wait_hours": 4, "classify_model": "claude-haiku-4-5-20251001"}')
on conflict (key) do nothing;

/* The current marketing consent for a channel: B2C's own latest record, else the master record's consent_marketing_at
   (Witty's v3 notice and web forms cover WhatsApp and email). */
create or replace function b2c.has_marketing_consent(p_lead bigint, p_channel text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce(
    (select c.given from b2c.consents c where c.lead_id = p_lead and c.channel = p_channel order by c.at desc, c.id desc limit 1),
    (select (r.record -> 'consent' ->> 'marketing_consent_at') is not null from b2c.lead_records r where r.lead_id = p_lead),
    false)
$f$;

/* A student gives (or withdraws) marketing consent on a channel. Staff with marketing rights, or the system. */
create or replace function b2c.marketing_consent(p_lead bigint, p_channel text, p_given boolean, p_source text, p_text_version text default null, p_text text default null)
returns void language plpgsql security definer set search_path = '' as $f$
begin
  if b2c.uid() is not null and not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_channel not in ('whatsapp', 'email') then raise exception 'unknown channel'; end if;
  insert into b2c.consents (lead_id, channel, given, text_version, source, actor_id) values (p_lead, p_channel, p_given, p_text_version, p_source, b2c.uid());
  perform b2c.queue_event('b2ccrm.marketing_consent', p_lead, jsonb_strip_nulls(jsonb_build_object('channel', p_channel, 'given', p_given, 'text', p_text,
                          'text_version', p_text_version, 'source', p_source, 'at', now())), true);
end $f$;

/* Opt-out (B9.6): one channel or all. All channels: the lead is opted out everywhere (as STOP on WhatsApp), every queued
   message is cancelled and its journey ends. Staff with marketing rights, the counsellor who owns the lead, or the system. */
create or replace function b2c.opt_out(p_lead bigint, p_channels text[] default null, p_source text default 'admin', p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_all boolean := p_channels is null or p_channels @> array['whatsapp', 'email']; c text;
begin
  if b2c.uid() is not null and not (b2c.can('marketing') or b2c.can_see(p_lead) and b2c.can('work_leads')) then raise exception 'not allowed' using errcode = '42501'; end if;
  foreach c in array coalesce(p_channels, array['whatsapp', 'email']) loop
    insert into b2c.consents (lead_id, channel, given, source, actor_id) values (p_lead, c, false, p_source, b2c.uid());
  end loop;
  if v_all then
    if not exists (select 1 from b2c.events e where e.lead_id = p_lead and e.type = 'lead.opted_out') then
      insert into b2c.events (type, lead_id, actor_type, actor_id, payload)
      values ('lead.opted_out', p_lead, case when b2c.uid() is null then 'student' else 'user' end, b2c.uid(), jsonb_build_object('source', p_source, 'note', p_note));
    end if;
    update b2c.send_queue set status = 'cancelled' where lead_id = p_lead and status = 'queued';
  else
    update b2c.send_queue q set status = 'cancelled' where q.lead_id = p_lead and q.status = 'queued' and q.channel = any (p_channels)
       and q.purpose in ('journey', 'campaign', 'marketing');
  end if;
  perform b2c.queue_event('b2ccrm.opted_out', p_lead, case when v_all then jsonb_build_object('source', p_source) else jsonb_build_object('channels', to_jsonb(p_channels), 'source', p_source) end, true);
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (p_lead, 'system', 'Opted out of ' || case when v_all then 'all messages' else array_to_string(p_channels, ' and ') || ' marketing' end || ' (' || p_source || ')',
          jsonb_build_object('channels', to_jsonb(coalesce(p_channels, array['whatsapp', 'email'])), 'source', p_source), b2c.uid());
  if v_all then perform b2c.journey_exit(p_lead, 'opted_out'); end if;
  return jsonb_build_object('all', v_all);
end $f$;

/* Global suppression (B9.6): a number or address that must never get marketing, whoever it belongs to. */
create or replace function b2c.suppress(p_value text, p_reason text, p_on boolean default true) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_norm text; v_kind text;
begin
  if b2c.uid() is not null then perform b2c.require('marketing'); end if;
  if p_value like '%@%' then v_norm := lower(trim(p_value)); v_kind := 'email'; else v_norm := b2c.norm_phone(p_value); v_kind := 'phone'; end if;
  if v_norm is null then raise exception 'give a phone or an email'; end if;
  if p_on then
    insert into b2c.suppressions (value_norm, kind, reason, actor_id) values (v_norm, v_kind, coalesce(p_reason, 'manual'), b2c.uid())
    on conflict (value_norm) do update set reason = excluded.reason, at = now(), lifted_at = null, actor_id = excluded.actor_id;
  else
    update b2c.suppressions set lifted_at = now() where value_norm = v_norm;
  end if;
end $f$;

create or replace function b2c.email_of(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select value_norm from b2c.lead_contacts where lead_id = p_lead and kind = 'email' and removed_at is null order by primary_email desc, origin = 'intake' desc, created_at limit 1
$f$;

/* Is the IST time inside the marketing send window? */
create or replace function b2c.in_send_window(p_at timestamptz default now()) returns boolean language sql stable security definer set search_path = '' as $f$
  select (p_at at time zone 'Asia/Kolkata')::time >= coalesce((b2c.setting('messaging') ->> 'quiet_start')::time, '09:00')
     and (p_at at time zone 'Asia/Kolkata')::time < coalesce((b2c.setting('messaging') ->> 'quiet_end')::time, '20:00')
$f$;

/* The next moment the send window opens (now, if it is open). */
create or replace function b2c.next_send_window(p_at timestamptz default now()) returns timestamptz language sql stable security definer set search_path = '' as $f$
  select case when b2c.in_send_window(p_at) then p_at
              when (p_at at time zone 'Asia/Kolkata')::time < coalesce((b2c.setting('messaging') ->> 'quiet_start')::time, '09:00')
                then ((p_at at time zone 'Asia/Kolkata')::date + coalesce((b2c.setting('messaging') ->> 'quiet_start')::time, '09:00')) at time zone 'Asia/Kolkata'
              else ((p_at at time zone 'Asia/Kolkata')::date + 1 + coalesce((b2c.setting('messaging') ->> 'quiet_start')::time, '09:00')) at time zone 'Asia/Kolkata' end
$f$;

/* The guardrail (B9.4, B9.6, B6.1). Null when a marketing message may go now; otherwise why not. Reasons starting with
   "wait:" pass later the same way (quiet hours, caps, a live Witty chat); the others do not. */
create or replace function b2c.may_market(p_lead bigint, p_channel text, p_allow_active boolean default false, p_at timestamptz default now())
returns text language plpgsql stable security definer set search_path = '' as $f$
declare s b2c.leads_state; v_block text := b2c.may_message(p_lead); v_to text; v_cfg jsonb := b2c.setting('messaging'); v_n int; v_last timestamptz;
        d0 timestamptz := date_trunc('day', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if v_block is not null then return v_block; end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.status = 'closed' then return 'closed'; end if;
  if s.dormant_at is not null then return 'dormant'; end if;
  if s.status = 'active' and s.owner_id is not null and not p_allow_active then return 'in active sales'; end if;
  if coalesce((select not r.held_by_b2c from b2c.lead_records r where r.lead_id = p_lead), false) then return 'held by a partner'; end if;
  v_to := case p_channel when 'whatsapp' then b2c.wa_phone(p_lead) else b2c.email_of(p_lead) end;
  if v_to is null then return case p_channel when 'whatsapp' then 'no WhatsApp number' else 'no email' end; end if;
  if exists (select 1 from b2c.suppressions x where x.value_norm = v_to and x.lifted_at is null) then return 'suppressed'; end if;
  if p_channel = 'email' and exists (select 1 from b2c.emails e where e.lead_id = p_lead and e.bounced_at is not null and e.to_address = v_to) then return 'email bounced'; end if;
  if not b2c.has_marketing_consent(p_lead, p_channel) then return 'no marketing consent'; end if;
  if not b2c.in_send_window(p_at) then return 'wait: quiet hours'; end if;
  if p_channel = 'whatsapp' then
    select count(*) into v_n from b2c.wa_messages m where m.lead_id = p_lead and m.direction = 'out' and m.purpose in ('journey', 'campaign', 'marketing')
       and m.status <> 'cancelled' and m.created_at >= d0;
    if v_n >= coalesce((v_cfg ->> 'wa_marketing_per_day')::int, 1) then return 'wait: daily cap'; end if;
    select count(*) into v_n from b2c.wa_messages m where m.lead_id = p_lead and m.direction = 'out' and m.purpose in ('journey', 'campaign', 'marketing')
       and m.status <> 'cancelled' and m.created_at >= p_at - interval '30 days';
    if v_n >= coalesce((v_cfg ->> 'wa_marketing_per_30d')::int, 6) then return 'wait: 30-day cap'; end if;
  else
    select count(*) into v_n from b2c.emails e where e.lead_id = p_lead and e.direction = 'out' and e.purpose in ('journey', 'campaign', 'marketing') and e.created_at >= d0;
    if v_n >= coalesce((v_cfg ->> 'email_marketing_per_day')::int, 2) then return 'wait: daily cap'; end if;
  end if;
  -- no marketing while the student is in a Witty chat (read-only: w2_messages belongs to Witty)
  if to_regclass('public.w2_messages') is not null then
    select max(m.created_at) into v_last from public.w2_messages m where m.phone = b2c.wa_phone(p_lead);
    if v_last > p_at - make_interval(mins => coalesce((b2c.setting('nurture') ->> 'witty_quiet_minutes')::int, 30)) then return 'wait: in a Witty chat'; end if;
  end if;
  return null;
end $f$;

-- ---------- marketing templates ----------
create table if not exists b2c.email_templates (
  id bigint generated always as identity primary key,
  name text not null,
  language text not null default 'en' check (language in ('en', 'hi', 'hinglish')),
  subject text not null,
  body text not null,               -- plain text with merge fields; the app renders HTML and adds the unsubscribe footer
  tags text[] not null default '{}',
  version int not null default 1,
  uses int not null default 0,
  archived_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (name, language)
);
create table if not exists b2c.template_versions (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('whatsapp', 'email')),
  template_id bigint not null,
  version int not null,
  content jsonb not null,
  actor_id uuid,
  at timestamptz not null default now()
);

/* Merge fields for marketing text: {{first_name}}, {{programme}}, {{university}}, {{city}}. */
create or replace function b2c.merge(p_text text, p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select replace(replace(replace(replace(coalesce(p_text, ''),
           '{{first_name}}', coalesce(b2c.first_name(p_lead), 'there')),
           '{{programme}}', coalesce(r.record -> 'interest' ->> 'course', 'your programme')),
           '{{university}}', coalesce(r.record -> 'interest' ->> 'university', 'the university')),
           '{{city}}', coalesce(r.record -> 'student' ->> 'city', ''))
    from (select 1) one left join b2c.lead_records r on r.lead_id = p_lead
$f$;

/* Marketing email template: Admin and Marketing. Each save is a version. */
create or replace function b2c.email_template_m_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_marketing'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.email_templates;
begin
  if coalesce(trim(p ->> 'name'), '') = '' or coalesce(trim(p ->> 'subject'), '') = '' or coalesce(trim(p ->> 'body'), '') = '' then
    raise exception 'a template needs a name, a subject and a text';
  end if;
  if v is null then
    insert into b2c.email_templates (name, language, subject, body, tags, created_by)
    values (trim(p ->> 'name'), coalesce(p ->> 'language', 'en'), left(p ->> 'subject', 300), left(p ->> 'body', 50000),
            coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'), me)
    returning * into t;
  else
    update b2c.email_templates set name = trim(p ->> 'name'), language = coalesce(p ->> 'language', language), subject = left(p ->> 'subject', 300),
           body = left(p ->> 'body', 50000), tags = case when p ? 'tags' then coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}') else tags end,
           archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
           version = version + 1, updated_at = now()
     where id = v returning * into t;
    if t.id is null then raise exception 'unknown template'; end if;
  end if;
  insert into b2c.template_versions (kind, template_id, version, content, actor_id) values ('email', t.id, t.version, to_jsonb(t), me);
  return t.id;
end $f$;

/* WhatsApp template (B9.2a): marketing ones by Admin and Marketing; sales and system ones by the Admin only. A changed
   body or buttons goes back to draft (Meta must approve it again). */
create or replace function b2c.wa_template_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_marketing'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.wa_templates; v_aud text := coalesce(p ->> 'audience', 'marketing');
begin
  if v is not null then select * into t from b2c.wa_templates where id = v; if t.id is null then raise exception 'unknown template'; end if; v_aud := coalesce(p ->> 'audience', t.audience); end if;
  if (v_aud <> 'marketing' or t.audience in ('sales', 'system')) and b2c.my_role() <> 'admin' then raise exception 'only the Admin creates sales and system templates'; end if;
  if coalesce(trim(p ->> 'name'), t.name, '') !~ '^[a-z0-9_]+$' or length(coalesce(trim(p ->> 'name'), t.name, '')) > 512 then raise exception 'a WhatsApp template name uses lower-case letters, digits and _ only'; end if;
  if coalesce(trim(p ->> 'body'), t.body, '') = '' then raise exception 'write the template text'; end if;
  if v is null then
    insert into b2c.wa_templates (name, language, category, audience, usable_by_sales, purpose, body, variables, buttons, header, tags, created_by)
    values (trim(p ->> 'name'), coalesce(p ->> 'language', 'en'), coalesce(p ->> 'category', case when v_aud = 'marketing' then 'marketing' else 'utility' end), v_aud,
            v_aud = 'sales' and coalesce((p ->> 'usable_by_sales')::boolean, true), p ->> 'purpose', p ->> 'body', coalesce(p -> 'variables', '[]'),
            coalesce(p -> 'buttons', '[]'), p -> 'header', coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'), me)
    returning * into t;
  else
    update b2c.wa_templates set
      category = coalesce(p ->> 'category', category), purpose = case when p ? 'purpose' then p ->> 'purpose' else purpose end,
      usable_by_sales = case when audience = 'sales' then coalesce((p ->> 'usable_by_sales')::boolean, usable_by_sales) else false end,
      body = coalesce(p ->> 'body', body), variables = coalesce(p -> 'variables', variables), buttons = coalesce(p -> 'buttons', buttons),
      header = case when p ? 'header' then p -> 'header' else header end,
      tags = case when p ? 'tags' then coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}') else tags end,
      status = case when coalesce(p ->> 'body', body) is distinct from body or coalesce(p -> 'buttons', buttons) is distinct from buttons
                    or coalesce(p ->> 'category', category) is distinct from category then 'draft' else status end,
      archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
      version = version + 1, updated_at = now()
     where id = v returning * into t;
  end if;
  insert into b2c.template_versions (kind, template_id, version, content, actor_id) values ('whatsapp', t.id, t.version, to_jsonb(t), me);
  return t.id;
end $f$;

/* Meta's answer for a template (the app syncs from the WhatsApp Business account). Service role. */
create or replace function b2c.wa_template_status(p_name text, p_language text, p_status text, p_meta_id text default null, p_reason text default null) returns int
language sql security definer set search_path = '' as $f$
  with u as (update b2c.wa_templates set status = case lower(p_status) when 'approved' then 'approved' when 'rejected' then 'rejected' when 'paused' then 'paused'
                                                                         when 'disabled' then 'disabled' when 'pending' then 'submitted' else status end,
                     meta_template_id = coalesce(p_meta_id, meta_template_id), rejection_reason = p_reason, synced_at = now()
              where name = p_name and language = p_language returning 1)
  select count(*)::int from u
$f$;

/* A template is being submitted to Meta (the app makes the call). */
create or replace function b2c.wa_template_submitted(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('templates_marketing');
  if (select audience from b2c.wa_templates where id = p_id) <> 'marketing' and b2c.my_role() <> 'admin' then raise exception 'only the Admin submits sales templates'; end if;
  update b2c.wa_templates set status = 'submitted', updated_at = now() where id = p_id and status in ('draft', 'rejected');
end $f$;

-- ---------- marketing sends ----------
/* One marketing WhatsApp to one lead (journeys, campaigns, one-off from the Nurture page). Returns
   {message_id} when queued, or {blocked: reason}. In test mode an unapproved template may be used: nothing is sent. */
create or replace function b2c.queue_marketing_wa(p_lead bigint, p_template bigint, p_purpose text, p_ref jsonb default '{}'::jsonb, p_allow_active boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare t b2c.wa_templates; v_why text; v bigint;
begin
  if b2c.uid() is not null then perform b2c.require('marketing'); end if;
  select * into t from b2c.wa_templates where id = p_template and archived_at is null;
  if t.id is null then return jsonb_build_object('blocked', 'unknown template'); end if;
  if t.status <> 'approved' and b2c.live('whatsapp') and not coalesce((select is_test from b2c.leads_state where lead_id = p_lead), false) then
    return jsonb_build_object('blocked', 'template not approved by Meta');
  end if;
  v_why := b2c.may_market(p_lead, 'whatsapp', p_allow_active);
  if v_why is not null then return jsonb_build_object('blocked', v_why); end if;
  v := b2c.enqueue_template(p_lead, t, null, p_purpose, '{}'::jsonb, now(), null);
  if v is null then return jsonb_build_object('blocked', 'could not queue'); end if;
  update b2c.wa_messages set campaign_id = (p_ref ->> 'campaign_id')::bigint, journey_run_id = (p_ref ->> 'run_id')::bigint where id = v;
  update b2c.wa_messages set cost_estimate = coalesce((b2c.setting('wa_rates') ->> t.category)::numeric, 0) where id = v;
  update b2c.wa_templates set uses = uses + 1 where id = t.id;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'whatsapp', 'out', 'Marketing WhatsApp: ' || t.name, jsonb_build_object('message_id', v) || p_ref, b2c.uid());
  perform b2c.queue_update(p_lead, jsonb_strip_nulls(jsonb_build_object('last_marketing_message_at', now(), 'last_campaign_id', p_ref ->> 'campaign_id')), false);
  return jsonb_build_object('message_id', v);
end $f$;

/* One marketing email (from the marketing sender, settings 'marketing_email'). The app adds the unsubscribe footer and
   the List-Unsubscribe header. Returns {email_id} or {blocked: reason}. */
create or replace function b2c.queue_marketing_email(p_lead bigint, p_template bigint, p_purpose text, p_ref jsonb default '{}'::jsonb, p_allow_active boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare t b2c.email_templates; v_why text; v bigint; v_to text := b2c.email_of(p_lead); v_from text := coalesce(b2c.setting('marketing_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
        v_subject text; v_text text;
begin
  if b2c.uid() is not null then perform b2c.require('marketing'); end if;
  select * into t from b2c.email_templates where id = p_template and archived_at is null;
  if t.id is null then return jsonb_build_object('blocked', 'unknown template'); end if;
  v_why := b2c.may_market(p_lead, 'email', p_allow_active);
  if v_why is not null then return jsonb_build_object('blocked', v_why); end if;
  v_subject := b2c.merge(t.subject, p_lead); v_text := b2c.merge(t.body, p_lead);
  insert into b2c.emails (lead_id, user_id, direction, from_address, to_address, subject, snippet, status, purpose, campaign_id, journey_run_id, marketing_template_id)
  values (p_lead, null, 'out', v_from, v_to, left(v_subject, 300), left(v_text, 200), 'queued', p_purpose, (p_ref ->> 'campaign_id')::bigint, (p_ref ->> 'run_id')::bigint, t.id)
  returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose)
  values ('email', p_lead, v_to, jsonb_build_object('email_id', v, 'from', v_from, 'reply_to', b2c.setting('marketing_email') ->> 'reply_to', 'subject', v_subject,
          'text', v_text, 'html', null, 'marketing', true, 'lead_id', p_lead), p_purpose);
  update b2c.email_templates set uses = uses + 1 where id = t.id;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'email', 'out', 'Marketing email: ' || left(v_subject, 200), jsonb_build_object('email_id', v) || p_ref, b2c.uid());
  perform b2c.queue_update(p_lead, jsonb_strip_nulls(jsonb_build_object('last_marketing_message_at', now(), 'last_campaign_id', p_ref ->> 'campaign_id')), false);
  return jsonb_build_object('email_id', v);
end $f$;

/* Today's marketing email count against the mailbox's daily allowance (B8.6). */
create or replace function b2c.email_allowance_left() returns int language sql stable security definer set search_path = '' as $f$
  select greatest(0, coalesce((b2c.setting('messaging') ->> 'gmail_daily_allowance')::int, 2000)
         - (select count(*) from b2c.emails e where e.purpose in ('journey', 'campaign', 'marketing')
              and e.created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'))::int
$f$;

-- placeholder until b16 defines journeys (never overwrites b16's version on a re-run)
do $d$
begin
  if to_regprocedure('b2c.journey_exit(bigint,text)') is null then
    execute 'create function b2c.journey_exit(p_lead bigint, p_reason text) returns int language sql security definer set search_path = '''' as ''select 0''';
  end if;
end $d$;

-- ---------- grants ----------
alter table b2c.consents enable row level security;
alter table b2c.suppressions enable row level security;
alter table b2c.email_templates enable row level security;
alter table b2c.template_versions enable row level security;
grant select on b2c.consents, b2c.email_templates, b2c.template_versions to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'consents' and policyname = 'who may see') then
    create policy "who may see" on b2c.consents for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "marketing read" on b2c.email_templates for select to authenticated using ((select b2c.can('templates_marketing')));
    create policy "marketing read" on b2c.template_versions for select to authenticated using ((select b2c.can('templates_marketing')));
  end if;
end $p$;
grant execute on function b2c.marketing_consent(bigint, text, boolean, text, text, text), b2c.opt_out(bigint, text[], text, text), b2c.suppress(text, text, boolean),
  b2c.email_template_m_save(jsonb), b2c.wa_template_save(jsonb), b2c.wa_template_submitted(bigint), b2c.queue_marketing_wa(bigint, bigint, text, jsonb, boolean),
  b2c.queue_marketing_email(bigint, bigint, text, jsonb, boolean), b2c.has_marketing_consent(bigint, text), b2c.email_allowance_left() to authenticated;
revoke execute on function b2c.wa_template_status(text, text, text, text, text), b2c.may_market(bigint, text, boolean, timestamptz), b2c.journey_exit(bigint, text)
  from public, authenticated;
grant execute on function b2c.wa_template_status(text, text, text, text, text), b2c.marketing_consent(bigint, text, boolean, text, text, text), b2c.opt_out(bigint, text[], text, text)
  to service_role;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
