-- B2C CRM b6: WhatsApp on the B2C number, email, templates, the send queue and partner-consent requests. Staging first.
--   wa_templates          synced from the B2C number's account; the Admin marks which ones Sales may use (B8.5, B9.2a)
--   wa_conversations      one per student number: the 24-hour customer-service window (last inbound)
--   wa_messages           both directions, with delivery and read receipts; never written to w2_messages (A3)
--   send_queue            every outbound message waits here; the app's sender sends it (dry-run unless LIVE_MODE)
--   sales_email_templates the counsellors' shared library with fork-on-edit (B8.6)
--   wa_compose / wa_queue_template / wa_queue_text   what a counsellor may send now (templates to open, free text inside the window)
--   wa_inbound / wa_status                           the Meta webhook (opt-out words, consent answers, routing)
--   queue_assignment_message / queue_system_template / queue_consent_request   automatic messages

create table if not exists b2c.wa_templates (
  id bigint generated always as identity primary key,
  name text not null,
  language text not null default 'en',
  category text not null default 'utility' check (category in ('utility', 'marketing', 'authentication')),
  audience text not null default 'marketing' check (audience in ('marketing', 'sales', 'system')),
  usable_by_sales boolean not null default false,
  purpose text,                      -- assignment_hours, assignment_after_hours, consent, welcome, opener, followup, documents …
  body text not null,
  variables jsonb not null default '[]'::jsonb,   -- ["first_name","counsellor_first_name","programme"] in body order ({{1}}, {{2}} …)
  buttons jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'rejected', 'paused', 'disabled')),
  meta_template_id text,
  rejection_reason text,
  version int not null default 1,
  synced_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (name, language)
);
create table if not exists b2c.wa_conversations (
  phone text primary key,                        -- normalised, 91XXXXXXXXXX
  lead_id bigint,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  unread int not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists b2c.wa_messages (
  id bigint generated always as identity primary key,
  phone text not null,
  lead_id bigint,
  direction text not null check (direction in ('in', 'out')),
  kind text not null check (kind in ('template', 'text', 'media', 'button', 'reaction', 'other')),
  template_id bigint references b2c.wa_templates (id),
  template_name text,
  body text,
  media jsonb,
  wamid text unique,
  status text not null default 'queued' check (status in ('queued', 'dry_run', 'sent', 'delivered', 'read', 'failed', 'received', 'cancelled')),
  status_at timestamptz,
  error text,
  category text,
  cost_estimate numeric(8, 2),
  purpose text,
  user_id uuid,
  reply_to text,
  created_at timestamptz not null default now()
);
create index if not exists wa_messages_phone on b2c.wa_messages (phone, created_at desc);
create index if not exists wa_messages_lead on b2c.wa_messages (lead_id, created_at desc);

create table if not exists b2c.send_queue (
  id bigint generated always as identity primary key,
  channel text not null check (channel in ('whatsapp', 'email')),
  lead_id bigint,
  to_address text not null,
  wa_message_id bigint references b2c.wa_messages (id),
  payload jsonb not null,             -- whatsapp: {type, template:{name, language, params}, text}; email: {from_user, subject, html, text}
  purpose text,
  dedupe_key text unique,
  not_before timestamptz not null default now(),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'dry_run', 'failed', 'cancelled', 'held')),
  attempts int not null default 0,
  error text,
  consent_request_id bigint,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists send_queue_due on b2c.send_queue (status, not_before) where status = 'queued';

create table if not exists b2c.emails (
  id bigint generated always as identity primary key,
  lead_id bigint,
  user_id uuid,
  direction text not null check (direction in ('in', 'out')),
  from_address text,
  to_address text,
  subject text,
  snippet text,
  gmail_message_id text,
  thread_id text,
  template_id bigint,
  status text not null default 'queued',
  opened_at timestamptz,
  clicked_at timestamptz,
  bounced_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists emails_lead on b2c.emails (lead_id, created_at desc);

create table if not exists b2c.sales_email_templates (
  id bigint generated always as identity primary key,
  owner_id uuid not null references b2c.users (user_id),
  name text not null,
  category text not null default 'after_call' check (category in ('first_email', 'after_call', 'brochure', 'fee_emi', 'documents', 'reminder', 'other')),
  subject text not null,
  body text not null,
  attachments jsonb not null default '[]'::jsonb,
  parent_id bigint references b2c.sales_email_templates (id),
  version int not null default 1,
  recommended boolean not null default false,
  hidden boolean not null default false,
  uses int not null default 0,
  replies int not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

/* parent_id never changes (B14 integrity). */
create or replace function b2c.guard_template_parent() returns trigger language plpgsql set search_path = '' as $f$
begin
  if new.parent_id is distinct from old.parent_id then raise exception 'a template''s original cannot change'; end if;
  return new;
end $f$;
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'sales_email_templates_parent') then
    create trigger sales_email_templates_parent before update on b2c.sales_email_templates for each row execute function b2c.guard_template_parent();
  end if;
end $d$;

do $d$
declare t text;
begin
  foreach t in array array['wa_templates', 'wa_conversations', 'wa_messages', 'send_queue', 'emails', 'sales_email_templates'] loop
    execute format('alter table b2c.%I enable row level security', t);
  end loop;
  grant select on b2c.wa_templates, b2c.wa_conversations, b2c.wa_messages, b2c.emails, b2c.sales_email_templates to authenticated;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'wa_templates' and policyname = 'staff read') then
    create policy "staff read" on b2c.wa_templates for select to authenticated using ((select b2c.is_staff()));
    create policy "who may see" on b2c.wa_conversations for select to authenticated using ((select b2c.can('read_all')) or (lead_id is not null and (select b2c.can_see(lead_id))));
    create policy "who may see" on b2c.wa_messages for select to authenticated using ((select b2c.can('read_all')) or (lead_id is not null and (select b2c.can_see(lead_id))));
    create policy "who may see" on b2c.emails for select to authenticated using ((select b2c.can('read_all')) or (lead_id is not null and (select b2c.can_see(lead_id))));
    create policy "staff read" on b2c.sales_email_templates for select to authenticated
      using ((select b2c.is_staff()) and deleted_at is null and (not hidden or owner_id = (select b2c.uid()) or (select b2c.my_role()) = 'admin'));
  end if;
end $d$;

-- Templates the system needs; bodies mirror what will be submitted to Meta. Status stays draft until synced as approved.
insert into b2c.wa_templates (name, language, category, audience, usable_by_sales, purpose, body, variables, buttons) values
  ('counsellor_intro_hours', 'en', 'utility', 'system', false, 'assignment_hours',
   'Hi {{1}}, I''m {{2}} from Eduwit. I''ll call you shortly about {{3}}.', '["first_name","counsellor_first_name","programme"]', '[]'),
  ('counsellor_intro_later', 'en', 'utility', 'system', false, 'assignment_after_hours',
   'Hi {{1}}, I''m {{2}} from Eduwit. I''ll call you after {{3}} about {{4}}.', '["first_name","counsellor_first_name","next_working_time","programme"]', '[]'),
  ('wa_partner_consent_v1', 'en', 'utility', 'system', false, 'consent',
   'To connect you with the best admission counsellor for {{1}}, may we share your details with our admission partner? Reply YES or NO.',
   '["programme"]', '[{"type":"quick_reply","text":"YES"},{"type":"quick_reply","text":"NO"}]'),
  ('explore_programmes', 'en', 'utility', 'system', false, 'welcome',
   'Hi {{1}}, thanks for your interest in studying with Eduwit. Explore programmes that can grow your career, and reply here with any question.',
   '["first_name"]', '[{"type":"quick_reply","text":"Show me programmes"},{"type":"quick_reply","text":"Talk to a counsellor"}]'),
  ('sales_opener_v1', 'en', 'utility', 'sales', true, 'opener',
   'Hi {{1}}, {{2}} from Eduwit here about the {{3}} you asked for. Can I share the fee details?', '["first_name","counsellor_first_name","programme"]', '[]'),
  ('sales_followup_v1', 'en', 'utility', 'sales', true, 'followup',
   'Hi {{1}}, this is {{2}} from Eduwit. Following up on {{3}}. Is now a good time to talk?', '["first_name","counsellor_first_name","programme"]', '[]'),
  ('sales_documents_v1', 'en', 'utility', 'sales', true, 'documents',
   'Hi {{1}}, a reminder to share {{2}} for your {{3}} application.', '["first_name","documents","university"]', '[]')
on conflict (name, language) do nothing;

-- ---------- helpers ----------
create or replace function b2c.live(p_channel text) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((b2c.setting('live_mode') ->> p_channel)::boolean, false)
$f$;

/* A message may go to this lead at all: not opted out, not deleted, not released; test leads only in dry-run. */
create or replace function b2c.may_message(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select case
    when s.lead_id is null then 'not a B2C lead'
    when s.deleted_at is not null then 'deleted'
    when s.status = 'closed' and s.closed_reason in ('released', 'routed_to_partner') then 'no longer with B2C'
    when coalesce((r.record -> 'consent' ->> 'opted_out')::boolean, false) then 'opted out'
    when exists (select 1 from b2c.events e where e.lead_id = s.lead_id and e.type = 'lead.opted_out') then 'opted out'
    else null end
  from (select 1) one left join b2c.leads_state s on s.lead_id = p_lead left join b2c.lead_records r on r.lead_id = p_lead
$f$;

create or replace function b2c.wa_phone(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select value_norm from b2c.lead_contacts where lead_id = p_lead and kind = 'phone' and removed_at is null order by primary_wa desc, origin = 'intake' desc, created_at limit 1
$f$;

create or replace function b2c.window_open(p_phone text) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((select last_inbound_at > now() - interval '24 hours' from b2c.wa_conversations where phone = p_phone), false)
$f$;

create or replace function b2c.first_name(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select coalesce(nullif(split_part(trim(record -> 'student' ->> 'name'), ' ', 1), ''), 'there') from b2c.lead_records where lead_id = p_lead
$f$;

/* Fills a template's variables from the lead and the counsellor. */
create or replace function b2c.template_params(p_tpl b2c.wa_templates, p_lead bigint, p_user uuid, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(coalesce(p_extra ->> v, case v
      when 'first_name' then b2c.first_name(p_lead)
      when 'counsellor_first_name' then (select split_part(coalesce(u.full_name, u.email), ' ', 1) from b2c.users u where u.user_id = p_user)
      when 'counsellor' then (select coalesce(u.full_name, u.email) from b2c.users u where u.user_id = p_user)
      when 'programme' then coalesce((select r.record -> 'interest' ->> 'course' from b2c.lead_records r where r.lead_id = p_lead), 'your programme')
      when 'university' then coalesce((select r.record -> 'interest' ->> 'university' from b2c.lead_records r where r.lead_id = p_lead), 'the university')
      else '' end) order by o), '[]')
  from jsonb_array_elements_text(p_tpl.variables) with ordinality x(v, o)
$f$;

create or replace function b2c.render(p_body text, p_params jsonb) returns text language plpgsql immutable set search_path = '' as $f$
declare i int; v text := p_body;
begin
  for i in 1 .. coalesce(jsonb_array_length(p_params), 0) loop v := replace(v, '{{' || i || '}}', p_params ->> (i - 1)); end loop;
  return v;
end $f$;

/* Puts a WhatsApp template in the send queue. Returns the message id (null when the lead may not be messaged). */
create or replace function b2c.enqueue_template(p_lead bigint, p_tpl b2c.wa_templates, p_user uuid, p_purpose text, p_extra jsonb default '{}'::jsonb,
                                                p_not_before timestamptz default now(), p_dedupe text default null, p_consent bigint default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_phone text := b2c.wa_phone(p_lead); v_params jsonb; v_msg bigint; v_block text := b2c.may_message(p_lead);
begin
  if v_block is not null or v_phone is null then
    insert into b2c.activities (lead_id, kind, body, meta) values (p_lead, 'system', 'WhatsApp not sent (' || coalesce(v_block, 'no number') || '): ' || p_tpl.name, '{}');
    return null;
  end if;
  if p_dedupe is not null and exists (select 1 from b2c.send_queue where dedupe_key = p_dedupe) then return null; end if;
  v_params := b2c.template_params(p_tpl, p_lead, p_user, p_extra);
  insert into b2c.wa_messages (phone, lead_id, direction, kind, template_id, template_name, body, status, category, purpose, user_id)
  values (v_phone, p_lead, 'out', 'template', p_tpl.id, p_tpl.name, b2c.render(p_tpl.body, v_params), 'queued', p_tpl.category, p_purpose, p_user)
  returning id into v_msg;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose, dedupe_key, not_before, consent_request_id)
  values ('whatsapp', p_lead, v_phone, v_msg, jsonb_build_object('type', 'template', 'template', jsonb_build_object('name', p_tpl.name, 'language', p_tpl.language, 'params', v_params)),
          p_purpose, p_dedupe, p_not_before, p_consent);
  insert into b2c.wa_conversations (phone, lead_id) values (v_phone, p_lead) on conflict (phone) do update set lead_id = coalesce(b2c.wa_conversations.lead_id, excluded.lead_id);
  return v_msg;
end $f$;

-- ---------- automatic messages ----------
/* B7.6: once per assignment, in-hours or out-of-hours wording; waits until a live Witty chat has been idle 10 minutes. */
create or replace function b2c.queue_assignment_message(p_lead bigint, p_user uuid, p_in_hours boolean, p_next timestamptz) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare t b2c.wa_templates; v_wait timestamptz := now(); v_last timestamptz; v_idle int := coalesce((b2c.setting('messaging') ->> 'witty_idle_minutes')::int, 10);
begin
  select * into t from b2c.wa_templates where purpose = case when p_in_hours then 'assignment_hours' else 'assignment_after_hours' end order by status = 'approved' desc, id limit 1;
  if t.id is null then return null; end if;
  -- Witty's last message to this student (read-only: w2_messages belongs to Witty)
  select max(m.created_at) into v_last from public.w2_messages m where m.phone = b2c.wa_phone(p_lead);
  if v_last is not null and v_last > now() - make_interval(mins => v_idle) then v_wait := v_last + make_interval(mins => v_idle); end if;
  return b2c.enqueue_template(p_lead, t, p_user, 'assignment',
           jsonb_build_object('next_working_time', to_char(coalesce(p_next, now()) at time zone 'Asia/Kolkata', 'HH12:MI am "on" Dy DD Mon')),
           v_wait, 'assign:' || p_lead || ':' || (select coalesce(max(a.id), 0) from b2c.assignments a where a.lead_id = p_lead));
end $f$;

/* Welcome and other system messages by purpose. */
create or replace function b2c.queue_system_template(p_lead bigint, p_name text, p_purpose text) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare t b2c.wa_templates;
begin
  select * into t from b2c.wa_templates where name = p_name order by status = 'approved' desc, id limit 1;
  if t.id is null then return null; end if;
  return b2c.enqueue_template(p_lead, t, null, p_purpose, '{}', now(), p_purpose || ':' || p_lead || ':' || (select coalesce(handoff_event_id, '') from b2c.leads_state where lead_id = p_lead));
end $f$;

/* Contract §1.3: send the one-tap consent template. Held (and the Admin alerted) when B2B's sentence differs from ours. */
create or replace function b2c.queue_consent_request(p_request bigint) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare q b2c.consent_requests; t b2c.wa_templates; v bigint; v_expected text;
begin
  select * into q from b2c.consent_requests where request_id = p_request for update;
  select * into t from b2c.wa_templates where purpose = 'consent' order by status = 'approved' desc, id limit 1;
  if q.request_id is null or t.id is null then return null; end if;
  v_expected := b2c.render(t.body, jsonb_build_array(coalesce(q.programme, 'your programme')));
  if q.text_body is not null and regexp_replace(lower(q.text_body), '\s+', ' ', 'g') <> regexp_replace(lower(v_expected), '\s+', ' ', 'g') then
    update b2c.consent_requests set status = 'held' where request_id = p_request;
    perform b2c.notify_admins('consent_text', 'Consent request held: wording differs from the approved template', q.text_body, '/w/connectors', q.lead_id, 'consent:' || p_request);
    return null;
  end if;
  v := b2c.enqueue_template(q.lead_id, t, null, 'consent', jsonb_build_object('programme', coalesce(q.programme, 'your programme')), now(), 'consent:' || p_request, p_request);
  update b2c.consent_requests set status = 'queued', send_message_id = v where request_id = p_request;
  return v;
end $f$;

-- ---------- what a counsellor may send (B8.5) ----------
create or replace function b2c.wa_compose(p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_phone text := b2c.wa_phone(p_lead); v_last timestamptz;
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed' using errcode = '42501'; end if;
  select last_inbound_at into v_last from b2c.wa_conversations where phone = v_phone;
  return jsonb_build_object(
    'phone', v_phone, 'blocked', b2c.may_message(p_lead), 'live', b2c.live('whatsapp'),
    'window_open', v_last > now() - interval '24 hours', 'window_closes_at', v_last + interval '24 hours',
    'templates', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'language', t.language, 'purpose', t.purpose, 'status', t.status,
                         'preview', b2c.render(t.body, b2c.template_params(t, p_lead, b2c.uid()))) order by t.purpose, t.name), '[]')
                    from b2c.wa_templates t where t.usable_by_sales and t.audience = 'sales' and t.status in ('approved', 'draft')),
    'messages', (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]') from (select * from b2c.wa_messages m where m.phone = v_phone order by m.created_at desc limit 100) m));
end $f$;

create or replace function b2c.wa_queue_template(p_lead bigint, p_template bigint, p_extra jsonb default '{}'::jsonb) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); t b2c.wa_templates; v bigint;
begin
  select * into t from b2c.wa_templates where id = p_template and usable_by_sales and audience = 'sales' and status in ('approved', 'draft');
  if t.id is null then raise exception 'choose an approved sales template'; end if;
  if t.status <> 'approved' and b2c.live('whatsapp') then raise exception 'this template is not approved by Meta yet'; end if;
  if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
  v := b2c.enqueue_template(p_lead, t, me, 'sales', p_extra, now(), null);
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id) values (p_lead, 'whatsapp', 'out', 'Template ' || t.name, jsonb_build_object('message_id', v), me);
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  perform b2c.queue_activity(p_lead, 'whatsapp', now(), 'template', null, t.name);
  return v;
end $f$;

create or replace function b2c.wa_queue_text(p_lead bigint, p_text text) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_phone text := b2c.wa_phone(p_lead); v bigint;
begin
  if length(coalesce(trim(p_text), '')) = 0 then raise exception 'type a message'; end if;
  if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
  if not b2c.window_open(v_phone) then raise exception 'the 24-hour window is closed: start with an approved template'; end if;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, category, purpose, user_id)
  values (v_phone, p_lead, 'out', 'text', left(p_text, 4096), 'queued', 'service', 'sales', me) returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose)
  values ('whatsapp', p_lead, v_phone, v, jsonb_build_object('type', 'text', 'text', left(p_text, 4096)), 'sales');
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id) values (p_lead, 'whatsapp', 'out', left(p_text, 500), jsonb_build_object('message_id', v), me);
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  perform b2c.queue_activity(p_lead, 'whatsapp', now(), 'text', null, left(p_text, 500));
  return v;
end $f$;

-- ---------- the sender (app) ----------
/* Claims due messages. Quiet hours are not applied here: counsellor messages and system messages may go any time;
   marketing (Phase 2) sets not_before inside its window. */
create or replace function b2c.send_take(p_limit int default 50) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with c as (select id from b2c.send_queue where status = 'queued' and not_before <= now() order by not_before limit p_limit for update skip locked),
  u as (update b2c.send_queue q set status = 'sending', attempts = attempts + 1 from c where q.id = c.id
        returning q.id, q.channel, q.lead_id, q.to_address, q.payload, q.purpose, q.wa_message_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'channel', u.channel, 'lead_id', u.lead_id, 'to', u.to_address, 'payload', u.payload,
                  'purpose', u.purpose, 'wa_message_id', u.wa_message_id,
                  'live', b2c.live(u.channel) and not b2c.is_test_phone(u.to_address) and not coalesce((select s.is_test from b2c.leads_state s where s.lead_id = u.lead_id), false))), '[]')
    into v from u;
  return v;
end $f$;

/* Results from the sender: {id, ok, dry_run, wamid, error}. A sent consent request is reported to B2B at once. */
create or replace function b2c.send_done(p_results jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare r jsonb; q b2c.send_queue; n int := 0; v_status text;
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]')) loop
    select * into q from b2c.send_queue where id = (r ->> 'id')::bigint for update;
    continue when q.id is null or q.status <> 'sending';
    v_status := case when coalesce((r ->> 'ok')::boolean, false) then case when coalesce((r ->> 'dry_run')::boolean, false) then 'dry_run' else 'sent' end
                     when q.attempts >= 5 then 'failed' else 'queued' end;
    update b2c.send_queue set status = v_status, error = r ->> 'error', sent_at = case when v_status in ('sent', 'dry_run') then now() end,
           not_before = case when v_status = 'queued' then now() + make_interval(mins => 2 * q.attempts) else not_before end
     where id = q.id;
    if q.wa_message_id is not null then
      update b2c.wa_messages set status = case v_status when 'queued' then 'queued' else v_status end, wamid = coalesce(r ->> 'wamid', wamid),
             error = r ->> 'error', status_at = now() where id = q.wa_message_id;
      if v_status in ('sent', 'dry_run') then
        update b2c.wa_conversations set last_outbound_at = now(), updated_at = now() where phone = q.to_address;
      end if;
    end if;
    if q.consent_request_id is not null and v_status in ('sent', 'dry_run') then
      update b2c.consent_requests set status = 'sent', sent_at = now(), sent_wamid = r ->> 'wamid' where request_id = q.consent_request_id;
      perform b2c.queue_event('b2ccrm.consent_request_sent', q.lead_id, jsonb_build_object('request_id', q.consent_request_id, 'sent_at', now(),
                              'message_id', coalesce(r ->> 'wamid', 'dry-run-' || q.id)), true);
    end if;
    if v_status = 'failed' then
      perform b2c.notify_admins('send_failed', 'A message could not be sent', coalesce(r ->> 'error', ''), '/w/connectors', q.lead_id, 'sendfail:' || q.id);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

/* Meta status receipts: sent → delivered → read, or failed. */
create or replace function b2c.wa_status(p_wamid text, p_status text, p_at timestamptz, p_error text default null) returns void
language sql security definer set search_path = '' as $f$
  update b2c.wa_messages set status = p_status, status_at = p_at, error = coalesce(p_error, error)
   where wamid = p_wamid and p_status in ('sent', 'delivered', 'read', 'failed')
     and array_position(array['queued', 'dry_run', 'sent', 'delivered', 'read'], status) <= coalesce(array_position(array['queued', 'dry_run', 'sent', 'delivered', 'read'], p_status), 99)
$f$;

/* An inbound WhatsApp message on the B2C number (B8.5): opens the 24-hour window, opts out on STOP words, answers a
   pending consent request, routes to the counsellor or the Replies flow; an unknown number becomes a new lead through
   the Intake API (urgent outbox item). Returns what happened. */
create or replace function b2c.wa_inbound(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_phone text := b2c.norm_phone(p ->> 'from'); v_text text := trim(coalesce(p ->> 'text', p ->> 'button', ''));
  v_lead bigint; s b2c.leads_state; v_low text := lower(trim(coalesce(p ->> 'text', p ->> 'button', ''))); q b2c.consent_requests; v_ans text; v_id bigint;
begin
  if p ->> 'wamid' is not null and exists (select 1 from b2c.wa_messages where wamid = p ->> 'wamid') then return jsonb_build_object('status', 'duplicate'); end if;
  select c.lead_id into v_lead from b2c.lead_contacts c join b2c.leads_state s2 on s2.lead_id = c.lead_id
   where c.kind = 'phone' and c.value_norm = v_phone and c.removed_at is null order by s2.status = 'active' desc, s2.updated_at desc limit 1;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, media, wamid, status, status_at, reply_to)
  values (v_phone, v_lead, 'in', coalesce(p ->> 'kind', 'text'), left(v_text, 4096), p -> 'media', p ->> 'wamid', 'received', now(), p ->> 'context_wamid')
  returning id into v_id;
  insert into b2c.wa_conversations (phone, lead_id, last_inbound_at, unread) values (v_phone, v_lead, now(), 1)
  on conflict (phone) do update set last_inbound_at = now(), unread = b2c.wa_conversations.unread + 1, lead_id = coalesce(b2c.wa_conversations.lead_id, excluded.lead_id), updated_at = now();

  if v_lead is null then
    -- a new student writing to the B2C number: created through the B2B Intake API (B4.3, contract §3.6)
    insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
    values ('intake', null, 'b2c-in-' || v_phone, jsonb_build_object('phone', v_phone, 'lead_source', 'b2c_whatsapp', 'name', p ->> 'profile_name',
            'first_message', left(v_text, 500)), true)
    on conflict (request_id) do nothing;
    perform b2c.notify_admins('new_whatsapp', 'New student on the B2C WhatsApp number', left(v_text, 200), '/w/inbox', null, 'newwa:' || v_phone);
    return jsonb_build_object('status', 'new_lead_requested');
  end if;

  select * into s from b2c.leads_state where lead_id = v_lead;
  insert into b2c.activities (lead_id, kind, direction, body, meta) values (v_lead, 'whatsapp', 'in', left(v_text, 500), jsonb_build_object('message_id', v_id));
  update b2c.leads_state set last_activity_at = now() where lead_id = v_lead;

  -- opt-out words: at once, everywhere (A3, B8.5)
  if exists (select 1 from jsonb_array_elements_text(coalesce(b2c.setting('opt_out_words') -> 'words', '[]')) w where v_low = w or v_low like w || ' %') then
    insert into b2c.events (type, lead_id, actor_type, payload) values ('lead.opted_out', v_lead, 'student', jsonb_build_object('channel', 'whatsapp', 'text', v_text));
    perform b2c.queue_event('b2ccrm.opted_out', v_lead, '{}'::jsonb, true);
    update b2c.send_queue set status = 'cancelled' where lead_id = v_lead and status = 'queued';
    update b2c.leads_state set journey = null where lead_id = v_lead;
    return jsonb_build_object('status', 'opted_out');
  end if;

  -- an answer to a pending partner-sharing request (contract §1.3): strict YES / NO, buttons or typed
  select * into q from b2c.consent_requests where lead_id = v_lead and status in ('queued', 'sent') order by created_at desc limit 1;
  if q.request_id is not null then
    v_ans := case when v_low in ('yes', 'y', 'haan', 'ha', 'han', 'yes please', 'ok share') then 'yes'
                  when v_low in ('no', 'n', 'nahi', 'nahin', 'no thanks', 'mat karo') then 'no' end;
    if v_ans is not null then
      update b2c.consent_requests set status = 'answered', answer = v_ans, answer_wamid = p ->> 'wamid', answered_at = now() where request_id = q.request_id;
      perform b2c.queue_event('b2ccrm.partner_consent', v_lead, jsonb_build_object('request_id', q.request_id, 'answer', v_ans, 'answered_at', now(),
                              'channel', 'whatsapp', 'message_id', p ->> 'wamid', 'text_version', coalesce(q.text_version, 'wa_partner_consent:v1')), true);
      return jsonb_build_object('status', 'consent_' || v_ans);
    end if;
  end if;

  if s.owner_id is not null and s.status = 'active' then
    perform b2c.notify(s.owner_id, 'whatsapp', 'WhatsApp from ' || coalesce(b2c.first_name(v_lead), 'a student'), left(v_text, 200), '/s/inbox?lead=' || v_lead, v_lead, null);
    perform b2c.queue_activity(v_lead, 'whatsapp', now(), 'reply', null, left(v_text, 500));
    return jsonb_build_object('status', 'to_counsellor');
  end if;
  -- pooled or unassigned: the Replies flow (classification and re-engagement arrive in Phase 2)
  perform b2c.notify_admins('reply', 'Reply from a pooled lead', left(v_text, 200), '/w/inbox', v_lead, 'reply:' || v_id);
  return jsonb_build_object('status', 'to_replies');
end $f$;

/* The counsellor opened the conversation: unread clears. */
create or replace function b2c.wa_mark_read(p_lead bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed'; end if;
  update b2c.wa_conversations set unread = 0 where phone = b2c.wa_phone(p_lead);
end $f$;

/* The inbox list, scoped by role. */
create or replace function b2c.inbox_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid();
begin
  if v_role is null then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_name', v.owner_name, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at),
                              'last', (select m.body from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc limit 1)) x
      from b2c.wa_conversations c left join b2c.leads_v v on v.lead_id = c.lead_id
     where (v_role in ('admin', 'marketing') or v.owner_id = me)
       and (coalesce(p ->> 'search', '') = '' or v.name ilike '%' || (p ->> 'search') || '%' or c.phone like '%' || regexp_replace(p ->> 'search', '\D', '', 'g') || '%')
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
     limit 200) q);
end $f$;

-- ---------- sales email templates: fork on edit (B8.6) ----------
create or replace function b2c.email_template_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_sales_email'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.sales_email_templates;
begin
  if coalesce(trim(p ->> 'name'), '') = '' or coalesce(trim(p ->> 'subject'), '') = '' or coalesce(trim(p ->> 'body'), '') = '' then
    raise exception 'a template needs a name, a subject and a body';
  end if;
  if v is not null then select * into t from b2c.sales_email_templates where id = v and deleted_at is null; end if;
  if v is null or t.id is null then
    insert into b2c.sales_email_templates (owner_id, name, category, subject, body, attachments)
    values (me, p ->> 'name', coalesce(p ->> 'category', 'other'), p ->> 'subject', p ->> 'body', coalesce(p -> 'attachments', '[]')) returning id into v;
  elsif t.owner_id = me or b2c.my_role() = 'admin' then
    update b2c.sales_email_templates set name = p ->> 'name', category = coalesce(p ->> 'category', category), subject = p ->> 'subject', body = p ->> 'body',
           attachments = coalesce(p -> 'attachments', attachments), version = version + 1, updated_at = now() where id = t.id;
  else
    -- someone else's template: save as my own copy; the original stays exactly as it was
    insert into b2c.sales_email_templates (owner_id, name, category, subject, body, attachments, parent_id)
    values (me, p ->> 'name', coalesce(p ->> 'category', t.category), p ->> 'subject', p ->> 'body', coalesce(p -> 'attachments', t.attachments), t.id)
    returning id into v;
  end if;
  return v;
end $f$;

create or replace function b2c.email_template_flag(p_id bigint, p_recommended boolean, p_hidden boolean) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  update b2c.sales_email_templates set recommended = coalesce(p_recommended, recommended), hidden = coalesce(p_hidden, hidden), updated_at = now() where id = p_id;
end $f$;

create or replace function b2c.email_template_delete(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_sales_email');
begin
  update b2c.sales_email_templates set deleted_at = now() where id = p_id and (owner_id = me or b2c.my_role() = 'admin');
  if not found then raise exception 'only the author or the Admin can delete a template'; end if;
end $f$;

/* A counsellor's one-to-one email (sent from their own Gmail by the app). */
create or replace function b2c.email_queue(p_lead bigint, p_subject text, p_html text, p_text text, p_template bigint default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_to text; v_from text; v bigint; v_block text := b2c.may_message(p_lead);
begin
  if v_block is not null then raise exception 'cannot email this student: %', v_block; end if;
  select value_norm into v_to from b2c.lead_contacts where lead_id = p_lead and kind = 'email' and removed_at is null order by primary_email desc, created_at limit 1;
  if v_to is null then raise exception 'this lead has no email'; end if;
  select email into v_from from b2c.users where user_id = me;
  insert into b2c.emails (lead_id, user_id, direction, from_address, to_address, subject, snippet, template_id, status)
  values (p_lead, me, 'out', v_from, v_to, left(p_subject, 300), left(coalesce(p_text, ''), 200), p_template, 'queued') returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose)
  values ('email', p_lead, v_to, jsonb_build_object('email_id', v, 'from_user', me, 'from', v_from, 'subject', p_subject, 'html', p_html, 'text', p_text), 'sales');
  if p_template is not null then update b2c.sales_email_templates set uses = uses + 1 where id = p_template; end if;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id) values (p_lead, 'email', 'out', 'Email: ' || left(p_subject, 200), jsonb_build_object('email_id', v), me);
  perform b2c.queue_activity(p_lead, 'email', now(), 'sent', null, left(p_subject, 300));
  return v;
end $f$;

grant execute on function b2c.wa_compose(bigint), b2c.wa_queue_template(bigint, bigint, jsonb), b2c.wa_queue_text(bigint, text), b2c.wa_mark_read(bigint),
  b2c.inbox_list(jsonb), b2c.email_template_save(jsonb), b2c.email_template_flag(bigint, boolean, boolean), b2c.email_template_delete(bigint),
  b2c.email_queue(bigint, text, text, text, bigint), b2c.window_open(text) to authenticated;
revoke execute on function b2c.enqueue_template(bigint, b2c.wa_templates, uuid, text, jsonb, timestamptz, text, bigint),
  b2c.queue_assignment_message(bigint, uuid, boolean, timestamptz), b2c.queue_system_template(bigint, text, text), b2c.queue_consent_request(bigint),
  b2c.send_take(int), b2c.send_done(jsonb), b2c.wa_status(text, text, timestamptz, text), b2c.wa_inbound(jsonb) from public, authenticated;
grant execute on function b2c.send_take(int), b2c.send_done(jsonb), b2c.wa_status(text, text, timestamptz, text), b2c.wa_inbound(jsonb) to service_role;
grant all on all tables in schema b2c to service_role;
