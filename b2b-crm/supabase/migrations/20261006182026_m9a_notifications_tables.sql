-- M9a: student notifications (spec B9). When an allocation becomes accepted (the partner's hold window passed with no
-- claim), the student is told which partner will call: WhatsApp and email, independently, once per allocation and
-- channel, inside quiet hours, never to test leads or opted-out students. Sending is m9b (pg_net), behind the
-- 'whatsapp' and 'email' live switches, which stay off until the Admin turns them on. Never writes w2_messages.

create table if not exists b2b.message_templates (
  id            bigint generated always as identity primary key,
  kind          text not null check (kind in ('accepted', 'reroute_update')),
  channel       text not null check (channel in ('whatsapp', 'email')),
  language      text not null check (language in ('en', 'hi')),
  subject       text,
  body          text not null check (length(body) between 1 and 4000),
  wa_template   text,                 -- the Meta-approved template name (WhatsApp)
  wa_language   text,                 -- its Meta language code, e.g. en, hi
  status        text not null default 'draft' check (status in ('draft', 'active')),
  version       int not null default 1,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  unique (kind, channel, language)
);

create table if not exists b2b.student_notifications (
  id                   bigint generated always as identity primary key,
  lead_id              bigint not null,
  allocation_id        bigint not null references b2b.allocations (id) on delete restrict,
  partner_id           bigint references b2b.partners (id) on delete restrict,
  kind                 text not null default 'accepted',
  channel              text not null check (channel in ('whatsapp', 'email')),
  template_id          bigint references b2b.message_templates (id) on delete restrict,
  language             text,
  variables            jsonb not null default '{}',
  recipient            text,
  status               text not null default 'scheduled'
                       check (status in ('scheduled', 'sending', 'sent', 'delivered', 'read', 'failed', 'cancelled', 'skipped')),
  scheduled_for        timestamptz,
  attempts             int not null default 0,
  net_request_id       bigint,
  provider             text,
  provider_message_id  text,
  sent_at              timestamptz,
  error                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (allocation_id, channel, kind)
);
create index if not exists student_notifications_due_idx on b2b.student_notifications (scheduled_for) where status in ('scheduled', 'sending');
create index if not exists student_notifications_lead_idx on b2b.student_notifications (lead_id, created_at desc);

do $rls$
declare t text;
begin
  foreach t in array array['message_templates', 'student_notifications'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- Templates (B9). Variables: {{student_first_name}} {{programme_label}} {{partner_display_name}}
-- {{expected_contact_window}} {{eduwit_support_contact}}. WhatsApp sends them in this order as {{1}}…{{5}} of the
-- Meta-approved template; the body here is the copy submitted for approval. Drafts until the Admin activates them.
insert into b2b.message_templates (kind, channel, language, subject, body, wa_template, wa_language) values
  ('accepted', 'whatsapp', 'en', null,
   'Hi {{student_first_name}}, thank you for your interest in {{programme_label}}. An academic counsellor from {{partner_display_name}} will call you on this number {{expected_contact_window}} to guide you on admission and next steps. If you need help in the meantime, contact Eduwit at {{eduwit_support_contact}}. — Team Eduwit',
   'eduwit_partner_assigned', 'en'),
  ('accepted', 'whatsapp', 'hi', null,
   'Hi {{student_first_name}}, {{programme_label}} mein interest dikhane ke liye thank you! {{partner_display_name}} ke academic counsellor aapko isi number par {{expected_contact_window}} call karenge aur admission aur next steps mein help karenge. Tab tak koi help chahiye to Eduwit se {{eduwit_support_contact}} par contact karein. — Team Eduwit',
   'eduwit_partner_assigned', 'hi'),
  ('accepted', 'email', 'en', 'Your counsellor from {{partner_display_name}} will call you',
   E'Hi {{student_first_name}},\n\nThank you for your interest in {{programme_label}}. An academic counsellor from {{partner_display_name}} will call you {{expected_contact_window}} to guide you on admission and next steps.\n\nWhat to keep ready: your marksheets, a photo ID and any work-experience letters.\n\nIf you need help in the meantime, contact Eduwit at {{eduwit_support_contact}}.\n\nTeam Eduwit',
   null, null),
  ('accepted', 'email', 'hi', 'Aapke counsellor {{partner_display_name}} se call karenge',
   E'Hi {{student_first_name}},\n\n{{programme_label}} mein interest dikhane ke liye thank you! {{partner_display_name}} ke academic counsellor aapko {{expected_contact_window}} call karenge aur admission aur next steps mein help karenge.\n\nYe documents ready rakhein: marksheets, photo ID aur work-experience letters (agar hain).\n\nTab tak koi help chahiye to Eduwit se {{eduwit_support_contact}} par contact karein.\n\nTeam Eduwit',
   null, null)
on conflict (kind, channel, language) do nothing;

-- Notification settings: providers (secrets live in Vault; only their ids are stored here) and the B2C rule from
-- Addendum 1 §2 (the B2C CRM always messages its own students).
update b2b.settings
   set value = value || jsonb_build_object('b2c_sends_own_notification', true)
                     || jsonb_build_object('whatsapp', coalesce(value -> 'whatsapp', jsonb_build_object('provider', 'meta_cloud', 'phone_number_id', null, 'api_version', 'v21.0', 'token_secret_id', null)))
                     || jsonb_build_object('email', coalesce(value -> 'email', jsonb_build_object('provider', 'resend', 'from_email', null, 'from_name', 'Team Eduwit', 'reply_to', null, 'api_key_secret_id', null)))
 where key = 'notifications';

-- ---------- helpers ----------

/* The next moment inside quiet hours (08:00–21:00 IST by default): now, or 09:00 at the next opportunity. */
create or replace function b2b.notify_slot(p_at timestamptz default now())
returns timestamptz language sql stable set search_path = '' as $$
  with s as (select coalesce(value ->> 'timezone', 'Asia/Kolkata') tz, coalesce(value ->> 'quiet_start', '08:00')::time qs,
                    coalesce(value ->> 'quiet_end', '21:00')::time qe from b2b.settings where key = 'notifications'),
       l as (select (p_at at time zone s.tz) lt, s.* from s)
  select case
    when l.lt::time >= l.qs and l.lt::time < l.qe then p_at
    when l.lt::time < l.qs then (l.lt::date + time '09:00') at time zone l.tz
    else (l.lt::date + 1 + time '09:00') at time zone l.tz end
  from l;
$$;

/* "within 2 working hours", "tomorrow morning", "on Monday morning": from the partner's SLA and working hours. */
create or replace function b2b.contact_window(p b2b.partners, p_at timestamptz default now())
returns text language plpgsql stable set search_path = '' as $$
declare
  v_hours int := coalesce((p.sla ->> 'first_contact_hours')::int, 2);
  v_local timestamp := p_at at time zone 'Asia/Kolkata';
  v_day text;
  v_wh jsonb;
  i int;
begin
  if p.working_hours is null or p.working_hours = '{}' then
    return 'within ' || v_hours || case when v_hours = 1 then ' working hour' else ' working hours' end;
  end if;
  v_wh := p.working_hours -> lower(to_char(v_local, 'dy'));
  if jsonb_typeof(v_wh) = 'object' and v_local::time >= (v_wh ->> 'open')::time
     and v_local + make_interval(hours => v_hours) <= v_local::date + (v_wh ->> 'close')::time then
    return 'within ' || v_hours || case when v_hours = 1 then ' working hour' else ' working hours' end;
  end if;
  if jsonb_typeof(v_wh) = 'object' and v_local::time < (v_wh ->> 'open')::time then
    return 'today ' || case when (v_wh ->> 'open')::time < time '12:00' then 'morning' else 'afternoon' end;
  end if;
  for i in 1..7 loop
    v_wh := p.working_hours -> lower(to_char(v_local + make_interval(days => i), 'dy'));
    if jsonb_typeof(v_wh) = 'object' then
      v_day := case when i = 1 then 'tomorrow' else 'on ' || trim(to_char(v_local + make_interval(days => i), 'Day')) end;
      return v_day || case when coalesce((v_wh ->> 'open')::time, time '10:00') < time '12:00' then ' morning' else ' afternoon' end;
    end if;
  end loop;
  return 'soon';
end $$;

/* University + course + specialization when the student chose a university; otherwise course + specialization. */
create or replace function b2b.allocation_programme_label(a b2b.allocations)
returns text language sql stable set search_path = '' as $$
  select coalesce(
    (select concat_ws(' ', case when (b2b.lead_interest(l) ->> 'university_id') is not null then u.name end, c.course,
                      case when c.specialization is not null and lower(c.specialization) not in ('general', '') then '(' || c.specialization || ')' end)
       from public.catalog_programs c left join public.catalog_universities u on u.id = c.university_id
      where c.id = a.programme_id),
    nullif(concat_ws(' ', nullif(trim(l.interested_course), ''), '(' || nullif(trim(l.interested_specialization), '') || ')'), ''),
    'your programme')
  from public.student_leads l where l.id = a.lead_id;
$$;

/* Fills {{variables}} in a template body. */
create or replace function b2b.render_template(p_body text, p_vars jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  k text;
  v_out text := p_body;
begin
  for k in select jsonb_object_keys(p_vars) loop
    v_out := replace(v_out, '{{' || k || '}}', coalesce(p_vars ->> k, ''));
  end loop;
  return v_out;
end $$;

/* Queues the 'accepted' notifications for one allocation (idempotent per allocation and channel). */
create or replace function b2b.notify_accepted(p_allocation_id bigint)
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  p b2b.partners;
  l public.student_leads;
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_lang text;
  v_vars jsonb;
  v_test boolean;
  v_slot timestamptz := b2b.notify_slot(now());
  ch text;
  v_to text;
  v_skip text;
  t b2b.message_templates;
  n int := 0;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null or a.destination_type <> 'partner' or a.status <> 'accepted' then return 0; end if;
  select * into p from b2b.partners where id = a.partner_id;
  select * into l from public.student_leads where id = a.lead_id;
  v_test := a.is_test or coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_lang := case when lower(coalesce(l.preferred_language, '')) ~ '(hindi|hinglish|^hi)' then 'hi' else 'en' end;
  v_vars := jsonb_build_object(
    'student_first_name', coalesce(nullif(split_part(trim(coalesce(l.student_name, '')), ' ', 1), ''), 'there'),
    'programme_label', b2b.allocation_programme_label(a),
    'partner_display_name', coalesce(p.display_name, p.name),
    'expected_contact_window', b2b.contact_window(p, v_slot),
    'eduwit_support_contact', coalesce(s ->> 'support_contact', 'support@eduwit.in'),
    'partner_logo_url', p.logo_url);

  foreach ch in array array['whatsapp', 'email'] loop
    select * into t from b2b.message_templates where kind = 'accepted' and channel = ch and language = v_lang;
    if t.id is null then select * into t from b2b.message_templates where kind = 'accepted' and channel = ch and language = 'en'; end if;
    v_to := case ch when 'whatsapp' then nullif(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), '') else nullif(trim(l.email_id), '') end;
    v_skip := case
      when v_test then 'test lead: never sent on a live channel'
      when not coalesce(p.notify_enabled, true) then 'notifications are off for this partner'
      when coalesce(l.is_opted_out, false) or ch = any (coalesce(l.opted_out_channels, '{}')) then 'student opted out'
      when ch = 'email' and l.email_bounced_at is not null then 'email bounced before'
      when v_to is null then case ch when 'whatsapp' then 'no phone number' else 'no email address' end
      when t.id is null or t.status <> 'active' then 'template not active yet'
    end;
    insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, template_id, language, variables, recipient,
                                           status, scheduled_for, error)
    values (a.lead_id, a.id, a.partner_id, 'accepted', ch, t.id, coalesce(t.language, v_lang), v_vars, v_to,
            case when v_skip is null then 'scheduled' else 'skipped' end, case when v_skip is null then v_slot end, v_skip)
    on conflict (allocation_id, channel, kind) do nothing;
    if found and v_skip is null then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- the hold window passed: accepted, and the notifications are queued in the same transaction
create or replace function b2b.accept_allocation(p_allocation_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare a b2b.allocations;
begin
  update b2b.allocations set status = 'accepted', accepted_at = now() where id = p_allocation_id and status = 'pushed' returning * into a;
  if a.id is null then return; end if;
  perform b2b.log_event('lead.accepted', a.lead_id, a.id, a.partner_id, jsonb_build_object('reference', a.reference, 'record_id', a.partner_record_id,
                        'returning_lead', a.returning_lead));
  begin
    perform b2b.notify_accepted(a.id);
  exception when others then
    -- a notification problem never undoes an acceptance
    perform b2b.log_event('alert.notification_failed', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(sqlerrm, 300), 'stage', 'queue'));
  end;
end $$;

revoke execute on function b2b.notify_slot(timestamptz), b2b.contact_window(b2b.partners, timestamptz), b2b.allocation_programme_label(b2b.allocations),
                           b2b.render_template(text, jsonb), b2b.notify_accepted(bigint) from public, anon, authenticated;
grant execute on function b2b.notify_slot(timestamptz), b2b.contact_window(b2b.partners, timestamptz), b2b.allocation_programme_label(b2b.allocations),
                          b2b.render_template(text, jsonb), b2b.notify_accepted(bigint) to service_role;
