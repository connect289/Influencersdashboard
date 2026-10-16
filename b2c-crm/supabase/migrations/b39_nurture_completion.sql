-- B2C CRM b39: completing nurture and re-engagement against the spec (docs/completion-gaps.md, section A, plus E1 and E12).
-- Staging first. Idempotent.
--   qualify_requests, qualify_*()   B6.3: a not-qualified lead that re-engages is not sold to. It gets a 3-question form
--                                   (and Witty), then after 48 h a task in the Admin's To qualify queue; the answers go to
--                                   the B2B CRM, which routes the lead again
--   opt_in(), may_message()         B6.5: a student who opted out may opt in again (START on WhatsApp, or staff on request)
--   score triggers                  B9.5: Witty conversation resumed, form filled; fit "qualification meets the minimum"
--   partner-lost sub-stage map      B6.4: the partner's reason maps to a lost sub-stage, which sets the delay and journey;
--                                   the partner's history is written to the timeline
--   flag_review()                   B4.1: flagged leads wait for the Admin; no marketing meanwhile
--   journeys                        B9.4: field, date, email-engagement and WhatsApp-reply triggers; "update" step
--   numbers                         B6.2, B9.0, B9.3, B9.7: pool outflow, deliverability, journey cost, campaign results
--   replies                         B6.3: a designated counsellor may answer the Replies inbox

alter table b2c.leads_state add column if not exists partners_tried jsonb not null default '[]'::jsonb;
alter table b2c.leads_state add column if not exists flag_reviewed_at timestamptz;
alter table b2c.leads_state add column if not exists flag_reviewed_by uuid;
alter table b2c.leads_state add column if not exists erased_at timestamptz;

do $d$ begin
  alter table b2c.field_history drop constraint if exists field_history_kind_check;
  alter table b2c.field_history add constraint field_history_kind_check
    check (kind in ('human_correction', 'admin_edit', 'cross_sell', 'contact', 'journey', 'qualification', 'erasure', 'student'));
end $d$;

insert into b2c.settings (key, value) values
  ('partner_lost_substage', '{"budget": "Can''t afford fee or EMI", "fee": "Can''t afford fee or EMI", "emi": "Can''t afford fee or EMI", "afford": "Can''t afford fee or EMI",
                              "loan": "Loan not approved", "eligib": "Not eligible", "not reachable": "Uncontactable", "unreachable": "Uncontactable",
                              "no answer": "Uncontactable", "not answering": "Uncontactable", "not interested": "Not interested", "later": "Not now, later",
                              "next year": "Not now, later", "competitor": "Lost to competitor", "other provider": "Chose another provider",
                              "another provider": "Chose another provider", "document": "Document verification failed"}'),
  ('qualify', '{"hours": 48, "valid_days": 14, "questions": ["course", "highest_qualification", "enrollment_timeline"]}'),
  ('opt_in_words', '{"words": ["start", "unstop", "subscribe", "resume", "shuru karo"]}')
on conflict (key) do nothing;
update b2c.settings set value = value || '{"replies_user_ids": []}'::jsonb where key = 'nurture' and not value ? 'replies_user_ids';

-- ---------- permissions: the designated Replies counsellor (B6.3) ----------
create or replace function b2c.replies_delegate(p_user uuid) returns boolean language sql stable security definer set search_path = '' as $f$
  select p_user is not null and coalesce(b2c.setting('nurture') -> 'replies_user_ids', '[]'::jsonb) ? p_user::text
$f$;

create or replace function b2c.can(p_perm text) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true
    when 'marketing' then p_perm in ('read_all', 'read_money', 'marketing', 'tags', 'journey_membership', 'replies', 'templates_marketing', 'analytics')
    when 'sales_head' then p_perm in ('read_team', 'work_leads', 'reassign', 'stage_override', 'templates_sales_email')
                           or (p_perm = 'replies' and b2c.replies_delegate(b2c.uid()))
    when 'counsellor' then p_perm in ('work_leads', 'templates_sales_email') or (p_perm = 'replies' and b2c.replies_delegate(b2c.uid()))
    else false end
$f$;

/* A counsellor sees their own leads, a lead whose missing details they were asked to collect (To qualify), and the leads
   of the replies they answer when the Admin made them the Replies counsellor. */
create or replace function b2c.can_see(p_lead bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true when 'marketing' then true when 'sales_head' then true
    when 'counsellor' then exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = b2c.uid() and s.deleted_at is null)
                        or exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.owner_id = b2c.uid() and t.kind = 'qualify' and t.status = 'open')
                        or (b2c.replies_delegate(b2c.uid()) and exists (select 1 from b2c.replies x where x.lead_id = p_lead and x.status in ('inbox', 'pending_ai')))
    else false end
$f$;

create or replace function b2c.notify_marketing(p_kind text, p_title text, p_body text, p_link text, p_lead bigint, p_dedupe text) returns void
language sql security definer set search_path = '' as $f$
  select b2c.notify(u.user_id, p_kind, p_title, p_body,
                    case when u.role in ('admin', 'marketing') then p_link else '/s/replies' end, p_lead, p_dedupe)
    from b2c.users u where u.is_active and (u.role in ('admin', 'marketing') or (p_kind = 'reply' and b2c.replies_delegate(u.user_id)))
$f$;

-- ---------- opting in again (B6.5) ----------
/* When the lead last opted out and opted in (events), and whether it is opted out now. */
create or replace function b2c.opted_out_now(p_lead bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  with o as (select (select e.type from b2c.events e where e.lead_id = p_lead and e.type in ('lead.opted_out', 'lead.opted_in') order by e.at desc, e.id desc limit 1) as last_type)
  select case when o.last_type is not null then o.last_type = 'lead.opted_out'
              else coalesce((select (r.record -> 'consent' ->> 'opted_out')::boolean from b2c.lead_records r where r.lead_id = p_lead), false) end
    from o
$f$;

create or replace function b2c.may_message(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select case
    when s.lead_id is null then 'not a B2C lead'
    when s.deleted_at is not null then 'deleted'
    when s.erased_at is not null then 'erased'
    when s.status = 'closed' and s.closed_reason in ('released', 'routed_to_partner') then 'no longer with B2C'
    when b2c.opted_out_now(s.lead_id) then 'opted out'
    else null end
  from (select 1) one left join b2c.leads_state s on s.lead_id = p_lead
$f$;

/* Opt-out (B9.6), as in b14, but a new opt-out after an opt-in is recorded again. */
create or replace function b2c.opt_out(p_lead bigint, p_channels text[] default null, p_source text default 'admin', p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_all boolean := p_channels is null or p_channels @> array['whatsapp', 'email']; c text;
begin
  if b2c.uid() is not null and not (b2c.can('marketing') or b2c.can_see(p_lead) and b2c.can('work_leads')) then raise exception 'not allowed' using errcode = '42501'; end if;
  foreach c in array coalesce(p_channels, array['whatsapp', 'email']) loop
    insert into b2c.consents (lead_id, channel, given, source, actor_id) values (p_lead, c, false, p_source, b2c.uid());
  end loop;
  if v_all then
    if not b2c.opted_out_now(p_lead) or not exists (select 1 from b2c.events e where e.lead_id = p_lead and e.type = 'lead.opted_out') then
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

/* Opting in again (B6.5): the student (START on WhatsApp) or staff with marketing rights on the student's request.
   Messages are allowed again; marketing consent is given again on the channels named (both by default). */
create or replace function b2c.opt_in(p_lead bigint, p_channels text[] default null, p_source text default 'student', p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare c text; me uuid := b2c.uid();
begin
  if me is not null then
    perform b2c.require('marketing');
    if length(coalesce(trim(p_note), '')) < 5 then raise exception 'say how the student asked to hear from Eduwit again'; end if;
  end if;
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead) then raise exception 'unknown lead'; end if;
  if not b2c.opted_out_now(p_lead) and p_channels is null and exists (select 1 from b2c.events e where e.lead_id = p_lead and e.type = 'lead.opted_in') then
    return jsonb_build_object('already', true);
  end if;
  insert into b2c.events (type, lead_id, actor_type, actor_id, payload)
  values ('lead.opted_in', p_lead, case when me is null then 'student' else 'user' end, me, jsonb_build_object('source', p_source, 'note', p_note, 'channels', to_jsonb(p_channels)));
  foreach c in array coalesce(p_channels, array['whatsapp', 'email']) loop
    insert into b2c.consents (lead_id, channel, given, source, actor_id, text_version) values (p_lead, c, true, p_source, me, 'opt_in_again');
  end loop;
  perform b2c.queue_event('b2ccrm.opted_in', p_lead, jsonb_build_object('source', p_source, 'channels', to_jsonb(coalesce(p_channels, array['whatsapp', 'email']))), true);
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (p_lead, 'system', 'Opted in again (' || p_source || coalesce(': ' || nullif(trim(p_note), ''), '') || ')', jsonb_build_object('source', p_source), me);
  return jsonb_build_object('opted_in', true);
end $f$;

-- ---------- fit: qualification meets the programme minimum (B9.5) ----------
/* A rough order of qualifications: 10th < 12th < diploma < bachelor's < master's < doctorate. Null when unknown. */
create or replace function b2c.qual_rank(p_text text) returns int language sql immutable set search_path = '' as $f$
  select case
    when p_text is null or trim(p_text) = '' then null
    when p_text ~* '(ph\.?d|doctor)' then 6
    when p_text ~* '(master|post ?grad|\mpg\M|m\.?b\.?a|m\.?com|m\.?sc|m\.?tech|\mma\M|mca)' then 5
    when p_text ~* '(bachelor|grad|degree|\mug\M|b\.?com|b\.?sc|b\.?tech|b\.?e\M|\mba\M|bba|bca|b\.?a\M)' then 4
    when p_text ~* '(diploma|polytechnic|iti)' then 3
    when p_text ~* '(12|xii|hsc|higher secondary|intermediate|puc|senior secondary)' then 2
    when p_text ~* '(10|\mx\M|ssc|matric|secondary)' then 1
    else null end
$f$;

create or replace function b2c.score_fit(p_lead bigint) returns int language plpgsql stable security definer set search_path = '' as $f$
declare r jsonb; v int := 0; v_tl text; v_d date; pts jsonb; v_have int; v_need int;
begin
  select record into r from b2c.lead_records where lead_id = p_lead;
  if r is null then return 0; end if;
  select jsonb_object_agg(key, points) into pts from b2c.score_rules where kind = 'fit' and active;
  v_tl := lower(coalesce(r -> 'interest' ->> 'enrollment_timeline', ''));
  if v_tl ~ '(immediate|asap|this month|next month|within (1|2|3|one|two|three) month|1 month|2 months|3 months|this intake)' then v := v + coalesce((pts ->> 'timeline_3m')::int, 0);
  else
    begin
      v_d := to_date(regexp_replace(v_tl, '[^a-z0-9 ]', '', 'g'), 'mon yyyy');
      if v_d <= current_date + 92 and v_d >= current_date - 31 then v := v + coalesce((pts ->> 'timeline_3m')::int, 0); end if;
    exception when others then null;
    end;
  end if;
  if coalesce(nullif(regexp_replace(r -> 'interest' ->> 'annual_budget_inr', '[^0-9.]', '', 'g'), '')::numeric, 0) >= 50000 then v := v + coalesce((pts ->> 'budget_50k')::int, 0); end if;
  -- known, and at least the lowest minimum among the programmes of interest (when the catalogue says one)
  v_have := b2c.qual_rank(r -> 'education' ->> 'highest_qualification');
  if v_have is not null then
    select min(b2c.qual_rank(cp.min_qualification)) into v_need from public.catalog_programs cp
     where cp.active and coalesce(r -> 'interest' ->> 'course', '') <> ''
       and (cp.course ilike r -> 'interest' ->> 'course' or coalesce(cp.program_name, '') ilike '%' || (r -> 'interest' ->> 'course') || '%');
    if v_need is null or v_have >= v_need then v := v + coalesce((pts ->> 'qualification_known')::int, 0); end if;
  end if;
  if coalesce(r -> 'interest' ->> 'course', '') ~* 'exec' and coalesce(nullif(regexp_replace(r -> 'education' ->> 'work_experience_years', '[^0-9.]', '', 'g'), '')::numeric, 0) >= 2 then
    v := v + coalesce((pts ->> 'working_exec')::int, 0);
  end if;
  if coalesce((r -> 'student' ->> 'phone_verified')::boolean, false) or r -> 'verification' ->> 'phone_verified_at' is not null then v := v + coalesce((pts ->> 'phone_verified')::int, 0); end if;
  return v;
end $f$;
update b2c.score_rules set label = 'Qualification known and meets the programme minimum' where key = 'qualification_known' and label = 'Qualification known';

-- ---------- partner-lost: sub-stage, delay, journey, history (B6.4) ----------
create or replace function b2c.partner_lost_sub_stage(p_reason text) returns text language plpgsql stable security definer set search_path = '' as $f$
declare m record; v_reason text := lower(coalesce(p_reason, ''));
begin
  if v_reason <> '' then
    for m in select key, value from jsonb_each_text(coalesce(b2c.setting('partner_lost_substage'), '{}'::jsonb)) order by length(key) desc loop
      if position(m.key in v_reason) > 0 then return m.value; end if;
    end loop;
  end if;
  return 'Other';
end $f$;

/* When a partner-lost lead's first nurture message goes out: B2B's time, else B2B's days, else the mapped sub-stage's delay. */
create or replace function b2c.partner_lost_due(d jsonb) returns timestamptz language sql stable security definer set search_path = '' as $f$
  select coalesce(nullif(d ->> 'nurture_first_message_at', '')::timestamptz,
                  now() + make_interval(days => nullif(coalesce(d ->> 'nurture_first_message_after_days', d -> 'handling' ->> 'nurture_first_message_after_days'), '')::int),
                  now() + make_interval(days => coalesce((select ss.first_message_days from b2c.sub_stages ss
                                                          where ss.stage_id = 10 and ss.name = b2c.partner_lost_sub_stage(d -> 'lost' ->> 'lost_reason')), 30)))
$f$;

/* The partner's history, one line for the timeline (calls made, last outcome, raw status). */
create or replace function b2c.partner_history_text(d jsonb) returns text language sql stable set search_path = '' as $f$
  select 'Partner history: ' || concat_ws(' · ',
           'lost by ' || coalesce(d -> 'lost' ->> 'partner_name', 'a partner') || coalesce(' (' || (d -> 'lost' ->> 'lost_reason') || ')', ''),
           'raw status ' || nullif(concat_ws(' / ', d -> 'lost' ->> 'partner_status', d -> 'lost' ->> 'partner_sub_status'), ''),
           'last activity ' || nullif(d -> 'lost' ->> 'partner_last_activity', ''),
           case when jsonb_array_length(coalesce(d -> 'partners_tried', '[]')) > 0 then
             'tried: ' || (select string_agg(coalesce(x ->> 'partner_name', '?') || coalesce(' (' || coalesce(x ->> 'outcome', x ->> 'status') || ')', ''), ', ')
                             from jsonb_array_elements(d -> 'partners_tried') x) end,
           case when d -> 'lost' ? 'calls_made' then (d -> 'lost' ->> 'calls_made') || ' calls made' end)
$f$;

create or replace function b2c.journey_for(p_lead bigint) returns bigint language plpgsql stable security definer set search_path = '' as $f$
declare s b2c.leads_state; v_key text; v_reason text; m record; v bigint;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.pool_reason = 'counsellor_lost' then v_key := s.journey;
  elsif s.pool_reason = 'partner_lost' then
    v_reason := lower(coalesce(s.partner_lost ->> 'lost_reason', ''));
    -- the mapped sub-stage's journey first (B6.4), then the older reason-to-journey map
    select ss.journey into v_key from b2c.sub_stages ss where ss.stage_id = 10 and ss.name = b2c.partner_lost_sub_stage(v_reason) and ss.name <> 'Other';
    if v_key is null then
      for m in select key, value from jsonb_each_text(b2c.setting('partner_lost_map')) where key <> 'default' loop
        if position(m.key in v_reason) > 0 then v_key := m.value; exit; end if;
      end loop;
    end if;
    v_key := coalesce(v_key, b2c.setting('partner_lost_map') ->> 'default', 'partner_lost_reengage');
  end if;
  if v_key is not null then
    select id into v from b2c.journeys where key = v_key and status = 'active' and current_version > 0 and (not test_mode or s.is_test);
    if v is not null then return v; end if;
  end if;
  select j.id into v from b2c.journeys j
   where j.status = 'active' and j.current_version > 0 and j.trigger ->> 'type' = 'pool_entry' and (not j.test_mode or s.is_test)
     and (j.trigger -> 'reasons' is null or j.trigger -> 'reasons' ? coalesce(s.pool_reason, s.handoff_reason, ''))
     and (j.trigger -> 'sub_stages' is null or j.trigger -> 'sub_stages' ? coalesce(s.sub_stage, b2c.partner_lost_sub_stage(s.partner_lost ->> 'lost_reason'), ''))
   order by j.priority, j.id limit 1;
  return v;
end $f$;

-- ---------- system email (qualification link, assignment fallback) ----------
create or replace function b2c.queue_system_email(p_lead bigint, p_subject text, p_text text, p_purpose text, p_dedupe text default null, p_not_before timestamptz default now())
returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_to text := b2c.email_of(p_lead); v bigint; v_from text := coalesce(b2c.setting('system_email') ->> 'from', b2c.setting('marketing_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
begin
  if v_to is null or b2c.may_message(p_lead) is not null then return null; end if;
  if p_dedupe is not null and exists (select 1 from b2c.send_queue where dedupe_key = p_dedupe) then return null; end if;
  insert into b2c.emails (lead_id, direction, from_address, to_address, subject, snippet, status, purpose)
  values (p_lead, 'out', v_from, v_to, left(p_subject, 300), left(p_text, 200), 'queued', p_purpose) returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key, not_before)
  values ('email', p_lead, v_to, jsonb_build_object('email_id', v, 'from', v_from, 'subject', p_subject, 'text', p_text, 'html', null, 'marketing', false, 'lead_id', p_lead),
          p_purpose, p_dedupe, p_not_before);
  insert into b2c.activities (lead_id, kind, direction, body, meta) values (p_lead, 'email', 'out', 'Email: ' || left(p_subject, 200), jsonb_build_object('email_id', v, 'purpose', p_purpose));
  return v;
end $f$;

/* A free-text WhatsApp message from the system inside the 24-hour window (no user). */
create or replace function b2c.queue_system_text(p_lead bigint, p_text text, p_purpose text, p_dedupe text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_phone text := b2c.wa_phone(p_lead); v bigint;
begin
  if v_phone is null or b2c.may_message(p_lead) is not null or not b2c.window_open(v_phone) then return null; end if;
  if p_dedupe is not null and exists (select 1 from b2c.send_queue where dedupe_key = p_dedupe) then return null; end if;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, category, purpose)
  values (v_phone, p_lead, 'out', 'text', left(p_text, 4096), 'queued', 'service', p_purpose) returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose, dedupe_key)
  values ('whatsapp', p_lead, v_phone, v, jsonb_build_object('type', 'text', 'text', left(p_text, 4096)), p_purpose, p_dedupe);
  insert into b2c.activities (lead_id, kind, direction, body, meta) values (p_lead, 'whatsapp', 'out', left(p_text, 500), jsonb_build_object('message_id', v, 'purpose', p_purpose));
  return v;
end $f$;

-- ---------- qualification first (B6.3: re-engaged qualification-nurture leads) ----------
create table if not exists b2c.qualify_requests (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  token text not null unique,
  trigger text,
  missing jsonb not null default '[]'::jsonb,
  questions jsonb not null default '[]'::jsonb,
  status text not null default 'waiting' check (status in ('waiting', 'escalated', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  due_at timestamptz not null,
  expires_at timestamptz not null,
  task_id bigint,
  answered_at timestamptz,
  answered_via text,
  answers jsonb,
  actor_id uuid
);
create unique index if not exists qualify_requests_open on b2c.qualify_requests (lead_id) where status in ('waiting', 'escalated');
create index if not exists qualify_requests_due on b2c.qualify_requests (due_at) where status = 'waiting';
alter table b2c.qualify_requests enable row level security;

/* The questions to ask: the lead's missing fields that the form can collect, else the default three. */
create or replace function b2c.qualify_questions(p_missing jsonb) returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(
    (select jsonb_agg(q order by o) from (
       select distinct on (q) q, o from (
         select case when m ~* 'course|programme|program' then 'course' when m ~* 'qualif|education' then 'highest_qualification'
                     when m ~* 'timeline|start|when' then 'enrollment_timeline' when m ~* 'name' then 'name' when m ~* 'email' then 'email'
                     when m ~* 'budget' then 'annual_budget_inr' end q, o
           from jsonb_array_elements_text(coalesce(p_missing, '[]')) with ordinality x(m, o)) a
        where q is not null order by q, o) b
     having count(*) > 0),
    b2c.setting('qualify') -> 'questions', '["course", "highest_qualification", "enrollment_timeline"]'::jsonb)
$f$;

create or replace function b2c.qualify_link(p_token text) returns text language sql stable security definer set search_path = '' as $f$
  select coalesce(nullif(b2c.setting('app') ->> 'base_url', ''), 'https://spark.eduwit.in') || '/q/' || p_token
$f$;

/* Sends the qualification step: WhatsApp (free text inside the window, else the approved template) and email. */
create or replace function b2c.qualify_send(p_request bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare q b2c.qualify_requests; t b2c.wa_templates; v_wa bigint; v_mail bigint; v_link text; v_name text;
begin
  select * into q from b2c.qualify_requests where id = p_request;
  if q.id is null then raise exception 'unknown request'; end if;
  v_link := b2c.qualify_link(q.token); v_name := b2c.first_name(q.lead_id);
  v_wa := b2c.queue_system_text(q.lead_id, 'Hi ' || v_name || ', thanks for getting back to us. Answer 3 quick questions so we can suggest the right programme: '
                                           || v_link || E'\nOr just reply here, or chat with Witty, Eduwit''s assistant.', 'qualify', 'qualify:' || q.id || ':wa:' || to_char(now(), 'YYYYMMDDHH24'));
  if v_wa is null then
    select * into t from b2c.wa_templates where name = 'nurture_qualify' and archived_at is null order by status = 'approved' desc, id limit 1;
    if t.id is not null then v_wa := b2c.enqueue_template(q.lead_id, t, null, 'qualify', '{}'::jsonb, now(), 'qualify:' || q.id || ':tpl:' || to_char(now(), 'YYYYMMDDHH24')); end if;
  end if;
  v_mail := b2c.queue_system_email(q.lead_id, 'Three quick questions from Eduwit',
              'Hi ' || v_name || E',\n\nThanks for your interest. Answer three quick questions and we will suggest programmes that fit you:\n\n' || v_link
              || E'\n\nThe link works for ' || coalesce((b2c.setting('qualify') ->> 'valid_days'), '14') || E' days.\n\nTeam Eduwit', 'qualify', 'qualify:' || q.id || ':mail');
  return jsonb_build_object('whatsapp', v_wa, 'email', v_mail);
end $f$;

/* A not-qualified lead re-engaged: no assignment for selling; the qualification step instead (B6.3). */
create or replace function b2c.qualify_start(p_lead bigint, p_trigger text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare s b2c.leads_state; v bigint; cfg jsonb := b2c.setting('qualify'); v_q jsonb;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.lead_id is null then return jsonb_build_object('outcome', 'skipped', 'why', 'unknown lead'); end if;
  select id into v from b2c.qualify_requests where lead_id = p_lead and status in ('waiting', 'escalated');
  if v is not null then return jsonb_build_object('outcome', 'qualifying', 'request_id', v, 'already', true); end if;
  perform b2c.journey_exit(p_lead, 'qualifying: ' || p_trigger);
  v_q := b2c.qualify_questions(s.missing);
  insert into b2c.qualify_requests (lead_id, token, trigger, missing, questions, due_at, expires_at)
  values (p_lead, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), p_trigger, coalesce(s.missing, '[]'), v_q,
          now() + make_interval(hours => coalesce((cfg ->> 'hours')::int, 48)), now() + make_interval(days => coalesce((cfg ->> 'valid_days')::int, 14)))
  returning id into v;
  update b2c.leads_state set tags = array(select distinct unnest(tags || array['to_qualify'])), last_activity_at = now(), updated_at = now() where lead_id = p_lead;
  insert into b2c.activities (lead_id, kind, body, meta)
  values (p_lead, 'reengaged', 'Re-engaged (' || p_trigger || '), still missing details: asked to complete them first (not assigned for selling)',
          jsonb_build_object('trigger', p_trigger, 'qualify_request', v, 'missing', s.missing));
  perform b2c.qualify_send(v);
  return jsonb_build_object('outcome', 'qualifying', 'request_id', v);
end $f$;

/* Records the details (form, staff or reply), sends them to the B2B CRM, which routes the lead again (B4.2). */
create or replace function b2c.qualify_apply(p_lead bigint, p_answers jsonb, p_via text, p_actor uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare k text; v_set jsonb := '{}'::jsonb; r jsonb; v_group text; q b2c.qualify_requests; v_val text;
begin
  select record into r from b2c.lead_records where lead_id = p_lead;
  for k in select jsonb_object_keys(coalesce(p_answers, '{}')) loop
    continue when k not in ('course', 'highest_qualification', 'enrollment_timeline', 'name', 'email', 'annual_budget_inr', 'specialization', 'study_mode');
    v_val := left(trim(coalesce(p_answers ->> k, '')), 200);
    continue when v_val = '';
    if k = 'email' and v_val !~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then raise exception 'that email does not look right'; end if;
    v_group := case when k in ('name', 'email') then 'student' when k = 'highest_qualification' then 'education' else 'interest' end;
    continue when (r -> v_group ->> k) is not distinct from v_val;
    insert into b2c.field_history (lead_id, field, old_value, new_value, kind, reason, actor_id)
    values (p_lead, k, r -> v_group -> k, to_jsonb(v_val), 'qualification', 'missing details (' || p_via || ')', p_actor);
    v_set := v_set || jsonb_build_object(k, v_val);
  end loop;
  if v_set = '{}'::jsonb then raise exception 'answer at least one question'; end if;
  perform b2c.queue_update(p_lead, v_set, true);
  perform b2c.queue_event('b2ccrm.qualification_completed', p_lead, jsonb_build_object('fields', v_set, 'via', p_via), true);
  update b2c.qualify_requests set status = 'answered', answered_at = now(), answered_via = p_via, answers = v_set, actor_id = p_actor
   where lead_id = p_lead and status in ('waiting', 'escalated') returning * into q;
  update b2c.tasks set status = 'done', done_at = now(), outcome = 'details recorded'
   where lead_id = p_lead and kind = 'qualify' and status = 'open';
  perform b2c.refresh_next_task(p_lead);
  update b2c.leads_state set tags = array_remove(tags, 'to_qualify'), last_activity_at = now(), updated_at = now() where lead_id = p_lead;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (p_lead, 'correction', 'Missing details recorded (' || p_via || '): ' || (select string_agg(key || ' = ' || value, ', ') from jsonb_each_text(v_set))
                                || '. Sent to the B2B CRM for routing.', v_set, p_actor);
  if p_via = 'form' then perform b2c.score_add(p_lead, 'form_filled', null, jsonb_build_object('qualify_request', q.id)); end if;
  return jsonb_build_object('recorded', v_set, 'request_id', q.id);
end $f$;

/* The public form (service role, from the /q/<token> page): what to ask. */
create or replace function b2c.qualify_form(p_token text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare q b2c.qualify_requests; r jsonb;
begin
  select * into q from b2c.qualify_requests where token = p_token;
  if q.id is null then return jsonb_build_object('status', 'unknown'); end if;
  if q.status in ('answered', 'closed') then return jsonb_build_object('status', q.status); end if;
  if q.expires_at < now() then return jsonb_build_object('status', 'expired'); end if;
  select record into r from b2c.lead_records where lead_id = q.lead_id;
  return jsonb_build_object('status', 'open', 'first_name', b2c.first_name(q.lead_id), 'questions', q.questions,
                            'known', jsonb_strip_nulls(jsonb_build_object('course', r -> 'interest' ->> 'course', 'highest_qualification', r -> 'education' ->> 'highest_qualification',
                                                                          'enrollment_timeline', r -> 'interest' ->> 'enrollment_timeline')));
end $f$;

create or replace function b2c.qualify_submit(p_token text, p_answers jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare q b2c.qualify_requests;
begin
  select * into q from b2c.qualify_requests where token = p_token for update;
  if q.id is null or q.status in ('answered', 'closed') or q.expires_at < now() then raise exception 'this link is no longer open'; end if;
  return b2c.qualify_apply(q.lead_id, p_answers, 'form', null);
end $f$;

/* Staff record the details (the Admin, or the counsellor given the To qualify task). */
create or replace function b2c.qualify_record(p_lead bigint, p_answers jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid();
begin
  if not (b2c.my_role() = 'admin' or exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.kind = 'qualify' and t.status = 'open' and t.owner_id = me)) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return b2c.qualify_apply(p_lead, p_answers, 'staff', me);
end $f$;

/* Every minute: after 48 h without answers the Admin's To qualify queue gets a task; stale requests close. */
create or replace function b2c.qualify_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare q record; v_task bigint; n_esc int := 0; n_closed int := 0;
begin
  update b2c.qualify_requests r set status = 'closed'
    from b2c.leads_state s where s.lead_id = r.lead_id and r.status in ('waiting', 'escalated')
     and (s.status <> 'pool' or s.deleted_at is not null or b2c.may_message(s.lead_id) is not null);
  get diagnostics n_closed = row_count;
  update b2c.tasks t set status = 'cancelled', outcome = 'lead left the pool'
    from b2c.qualify_requests r where r.task_id = t.id and r.status = 'closed' and t.status = 'open';
  for q in select * from b2c.qualify_requests where status = 'waiting' and due_at <= now() order by due_at limit 200 for update skip locked loop
    v_task := b2c.add_task(q.lead_id, null, 'qualify',
                           'Collect the missing details: ' || coalesce((select string_agg(replace(x, '_', ' '), ', ') from jsonb_array_elements_text(q.questions) x), 'course, qualification, timeline'),
                           now(), 'Re-engaged (' || coalesce(q.trigger, '?') || ') but did not complete the form in 48 hours. Call only to collect these details.', false, 'qualify');
    update b2c.qualify_requests set status = 'escalated', task_id = v_task where id = q.id;
    perform b2c.notify_admins('to_qualify', 'To qualify: a re-engaged lead is still missing details', null, '/w/qualify', q.lead_id, 'qualify:' || q.id);
    n_esc := n_esc + 1;
  end loop;
  return jsonb_build_object('escalated', n_esc, 'closed', n_closed);
end $f$;

/* The Admin's To qualify queue. */
create or replace function b2c.qualify_queue(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'lead_id', q.lead_id, 'name', v.name, 'course', v.course, 'phone', v.phone,
            'trigger', q.trigger, 'questions', q.questions, 'status', q.status, 'created_at', q.created_at, 'due_at', q.due_at,
            'task_id', q.task_id, 'task_owner', t.owner_id, 'task_owner_name', u.full_name, 'link', b2c.qualify_link(q.token)) order by q.status = 'escalated' desc, q.created_at), '[]')
            from b2c.qualify_requests q join b2c.leads_v v on v.lead_id = q.lead_id
            left join b2c.tasks t on t.id = q.task_id left join b2c.users u on u.user_id = t.owner_id
           where q.status in ('waiting', 'escalated') and (coalesce((p ->> 'test')::boolean, false) or not v.is_test));
end $f$;

/* The Admin gives the To qualify task to a counsellor (to collect the details only), or takes it back. */
create or replace function b2c.qualify_assign(p_request bigint, p_user uuid) returns void language plpgsql security definer set search_path = '' as $f$
declare q b2c.qualify_requests;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into q from b2c.qualify_requests where id = p_request and status in ('waiting', 'escalated') for update;
  if q.id is null then raise exception 'this request is closed'; end if;
  if q.task_id is null then
    q.task_id := b2c.add_task(q.lead_id, p_user, 'qualify', 'Collect the missing details', now(), 'Call only to collect the missing details.', false, 'qualify');
    update b2c.qualify_requests set task_id = q.task_id, status = 'escalated' where id = q.id;
  else
    update b2c.tasks set owner_id = p_user where id = q.task_id;
  end if;
  if p_user is not null then
    perform b2c.notify(p_user, 'to_qualify', 'Collect a student''s missing details', 'Call only to record what is missing; the lead then goes back to routing.',
                       '/s/leads/' || q.lead_id, q.lead_id, 'qualify-assign:' || q.id || ':' || p_user);
  end if;
end $f$;

create or replace function b2c.qualify_resend(p_request bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2c.qualify_requests where id = p_request and status in ('waiting', 'escalated')) then raise exception 'this request is closed'; end if;
  return b2c.qualify_send(p_request);
end $f$;

/* Re-engagement (B6.3). A not-qualified lead gets the qualification step instead of a counsellor, unless a person hands it
   over on purpose. */
create or replace function b2c.reengage(p_lead bigint, p_trigger text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare s b2c.leads_state;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.status = 'pool' and s.pool_reason = 'not_qualified' and p_trigger not like 'handed over:%' then
    return b2c.qualify_start(p_lead, p_trigger);
  end if;
  update b2c.leads_state set status = 'active', hot = true, reengaged_at = now(), reengage_trigger = p_trigger, journey = null, updated_at = now()
   where lead_id = p_lead and status = 'pool';
  if not found then return jsonb_build_object('outcome', 'skipped', 'why', 'not in the pool'); end if;
  perform b2c.journey_exit(p_lead, 're-engaged: ' || p_trigger);
  update b2c.qualify_requests set status = 'closed' where lead_id = p_lead and status in ('waiting', 'escalated');
  insert into b2c.activities (lead_id, kind, body, meta, at) values (p_lead, 'reengaged', 'Re-engaged: ' || p_trigger, jsonb_build_object('trigger', p_trigger), now());
  return b2c.allocate(p_lead, 'reengaged');
end $f$;

-- ---------- flagged leads (B4.1) ----------
/* The Admin agrees (close as junk or test / cannot be served) or keeps the lead. */
create or replace function b2c.flag_review(p_lead bigint, p_action text, p_note text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); s b2c.leads_state;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.flagged is null then raise exception 'this lead is not flagged'; end if;
  if p_action = 'keep' then
    update b2c.leads_state set flagged = null, flag_reviewed_at = now(), flag_reviewed_by = me, updated_at = now() where lead_id = p_lead;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id) values (p_lead, 'system', 'Flag reviewed: kept' || coalesce(' (' || nullif(trim(p_note), '') || ')', ''),
                                                                           jsonb_build_object('flag', s.flagged), me);
  elsif p_action in ('junk', 'cannot_serve') then
    perform b2c.journey_exit(p_lead, 'flagged: ' || p_action);
    perform b2c.close_lead(p_lead, 'closed', case when p_action = 'junk' then 'junk_or_test' else 'cannot_be_served' end);
    update b2c.leads_state set flag_reviewed_at = now(), flag_reviewed_by = me, stage_id = 10,
           sub_stage = case when p_action = 'junk' then 'Junk or test' else 'Other' end, stage_comment = coalesce(nullif(trim(p_note), ''), 'Flagged: ' || s.flagged),
           stage_changed_at = now(), updated_at = now() where lead_id = p_lead;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id) values (p_lead, 'stage', 'Lost · ' || case when p_action = 'junk' then 'Junk or test' else 'Cannot be served' end
                                                                           || ' (flag agreed)', jsonb_build_object('to', 'Lost', 'flag', s.flagged), me);
    perform b2c.queue_update(p_lead, jsonb_build_object('stage', 'lost', 'b2c_stage', 'Lost', 'b2c_sub_stage', case when p_action = 'junk' then 'Junk or test' else 'Other' end), true);
  else
    raise exception 'keep, junk or cannot_serve';
  end if;
  perform b2c.log('lead.flag_reviewed', p_lead, jsonb_build_object('action', p_action, 'flag', s.flagged));
end $f$;

create or replace function b2c.flagged_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'course', v.course, 'flag', v.flagged, 'status', v.status, 'stage', v.stage,
            'owner_name', v.owner_name, 'lane', v.lane, 'since', (select max(a.at) from b2c.activities a where a.lead_id = v.lead_id and a.body like 'Lead flagged%'))
            order by v.updated_at desc), '[]')
            from b2c.leads_v v where v.flagged is not null and v.deleted_at is null and v.status <> 'closed');
end $f$;

/* No marketing while a lead is flagged and not yet reviewed (B4.1: "journeys pause while it is flagged"). */
create or replace function b2c.may_market(p_lead bigint, p_channel text, p_allow_active boolean default false, p_at timestamptz default now())
returns text language plpgsql stable security definer set search_path = '' as $f$
declare s b2c.leads_state; v_block text := b2c.may_message(p_lead); v_to text; v_cfg jsonb := b2c.setting('messaging'); v_n int; v_last timestamptz;
        d0 timestamptz := date_trunc('day', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if v_block is not null then return v_block; end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.status = 'closed' then return 'closed'; end if;
  if s.dormant_at is not null then return 'dormant'; end if;
  if s.flagged is not null then return 'wait: flagged for review'; end if;
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
  if to_regclass('public.w2_messages') is not null then
    select max(m.created_at) into v_last from public.w2_messages m where m.phone = b2c.wa_phone(p_lead);
    if v_last > p_at - make_interval(mins => coalesce((b2c.setting('nurture') ->> 'witty_quiet_minutes')::int, 30)) then return 'wait: in a Witty chat'; end if;
  end if;
  return null;
end $f$;

-- ---------- the hand-off intake (b3), with the partner's history, the sub-stage delay, scoring and qualification ----------
create or replace function b2c.apply_envelope(p_id text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  e b2c.inbox; d jsonb; v_type text; v_lead bigint; s b2c.leads_state; x jsonb; v_out jsonb := '{}'::jsonb; v_reason text; v_lane text;
  v_sub b2c.sub_stages; v_test boolean; v_src text;
begin
  select * into e from b2c.inbox where envelope_id = p_id for update;
  if e.envelope_id is null then raise exception 'no such envelope'; end if;
  if e.status = 'applied' then return jsonb_build_object('status', 'applied'); end if;
  d := coalesce(e.payload -> 'data', '{}'); v_type := e.type; v_lead := e.lead_id;
  update b2c.inbox set attempts = attempts + 1 where envelope_id = p_id;
  begin
    if v_type = 'b2c.lead_upserted' then
      perform b2c.apply_record(v_lead, (d ->> 'version')::int, (d ->> 'seq')::bigint, d -> 'record', d ->> 'origin');

    elsif v_type = 'b2c.leads_batch' then
      for x in select * from jsonb_array_elements(coalesce(d -> 'leads', '[]')) loop
        if x ->> 'type' = 'b2c.lead_released' then
          perform b2c.apply_released((x ->> 'lead_id')::bigint, x -> 'record');
        else
          perform b2c.apply_record((x ->> 'lead_id')::bigint, (x ->> 'version')::int, (x ->> 'seq')::bigint, x -> 'record', x ->> 'origin');
        end if;
      end loop;

    elsif v_type = 'b2c.lead_released' then
      perform b2c.apply_released(v_lead, d -> 'record');

    elsif v_type = 'b2c.lead_handed_off' then
      v_reason := d ->> 'reason'; v_lane := coalesce(d ->> 'b2c_lane', 'sales');
      v_test := coalesce((e.payload ->> 'test')::boolean, false) or coalesce((d ->> 'test')::boolean, false);
      insert into b2c.leads_state (lead_id, lane, status, handoff_reason, cause, allocation_id, handoff_event_id, handed_off_at, handling,
                                   partner_bar_reason, providers, b2c_actions, missing, partner_lost, partners_tried, is_test,
                                   pool_entered_at, pool_reason, first_message_due_at, lost_by, hot)
      values (v_lead, v_lane, case when v_lane = 'nurture' then 'pool' else 'active' end, v_reason, d ->> 'cause',
              (d ->> 'allocation_id')::bigint, e.envelope_id, coalesce(e.occurred_at, now()), coalesce(d -> 'handling', '{}'),
              d -> 'partner_bar' ->> 'reason', coalesce(d -> 'already_with_providers', '[]'), coalesce(d -> 'b2c_actions', '[]'),
              coalesce(d -> 'missing', '[]'), d -> 'lost', coalesce(d -> 'partners_tried', '[]'), v_test,
              case when v_lane = 'nurture' then now() end, case when v_lane = 'nurture' then v_reason end,
              case when v_reason = 'partner_lost' then b2c.partner_lost_due(d) end,
              case when v_reason = 'partner_lost' then 'partner' end,
              coalesce(v_reason = 'duplicate_cascade' or d -> 'handling' ->> 'assignment' = 'round_robin_now', false))
      on conflict (lead_id) do update set
        lane = excluded.lane,
        status = excluded.status,
        handoff_reason = excluded.handoff_reason, cause = excluded.cause, allocation_id = excluded.allocation_id,
        handoff_event_id = excluded.handoff_event_id, handed_off_at = excluded.handed_off_at, handling = excluded.handling,
        partner_bar_reason = coalesce(excluded.partner_bar_reason, b2c.leads_state.partner_bar_reason),
        providers = case when excluded.providers <> '[]'::jsonb then excluded.providers else b2c.leads_state.providers end,
        b2c_actions = excluded.b2c_actions, missing = excluded.missing, partner_lost = coalesce(excluded.partner_lost, b2c.leads_state.partner_lost),
        partners_tried = case when excluded.partners_tried <> '[]'::jsonb then excluded.partners_tried else b2c.leads_state.partners_tried end,
        is_test = excluded.is_test,
        pool_entered_at = case when excluded.lane = 'nurture' then now() else b2c.leads_state.pool_entered_at end,
        pool_reason = case when excluded.lane = 'nurture' then excluded.pool_reason else b2c.leads_state.pool_reason end,
        first_message_due_at = excluded.first_message_due_at,
        lost_by = coalesce(excluded.lost_by, b2c.leads_state.lost_by),
        hot = excluded.hot,
        closed_at = null, closed_reason = null, released_at = null, routing_requested_at = null,
        previous_owner_id = coalesce(b2c.leads_state.owner_id, b2c.leads_state.previous_owner_id),
        owner_id = case when excluded.lane = 'nurture' then null else b2c.leads_state.owner_id end,
        updated_at = now();
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'handoff', 'Handed to B2C: ' || coalesce(v_reason, '?') || coalesce(' (' || (d ->> 'cause') || ')', '') || ', ' || v_lane || ' lane',
              jsonb_build_object('envelope', e.envelope_id, 'reason', v_reason, 'lane', v_lane), coalesce(e.occurred_at, now()));
      -- the partner's history on the timeline, so the counsellor who later takes the lead knows what the partner tried (B6.4)
      if v_reason = 'partner_lost' or d -> 'lost' is not null or jsonb_array_length(coalesce(d -> 'partners_tried', '[]')) > 0 then
        insert into b2c.activities (lead_id, kind, body, meta, at)
        values (v_lead, 'partner_history', b2c.partner_history_text(d),
                jsonb_strip_nulls(jsonb_build_object('lost', d -> 'lost', 'partners_tried', d -> 'partners_tried',
                                                     'mapped_sub_stage', case when v_reason = 'partner_lost' then b2c.partner_lost_sub_stage(d -> 'lost' ->> 'lost_reason') end)),
                coalesce(e.occurred_at, now()));
      end if;
      if v_lane = 'sales' then
        v_out := b2c.allocate(v_lead, case when v_reason = 'manual_route_failed' then 'returned_from_partners' else 'handoff' end);
      elsif d -> 'b2c_actions' ? 'welcome_explore_programmes' then
        perform b2c.queue_system_template(v_lead, 'explore_programmes', 'welcome');
      end if;

    elsif v_type = 'b2c.lead_reenquired' then
      select * into s from b2c.leads_state where lead_id = v_lead;
      update b2c.leads_state set reenquired_at = now(), updated_at = now() where lead_id = v_lead;
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'reenquiry', 'New enquiry: ' || coalesce(d -> 'what' ->> 'source_system', '') || ' ' || coalesce(d -> 'what' ->> 'event_type', ''),
              d, coalesce(e.occurred_at, now()));
      v_src := lower(coalesce(d -> 'what' ->> 'source_system', d ->> 'source_system', ''));
      if s.owner_id is not null and s.status = 'active' then
        perform b2c.notify(s.owner_id, 'reenquiry', 'New enquiry from a lead you own', coalesce(d -> 'what' ->> 'source', 'A new form or message'),
                           '/s/leads/' || v_lead, v_lead, 'reenq:' || e.envelope_id);
      elsif s.lead_id is not null and s.status = 'pool' and coalesce(s.pool_reason, '') in ('partner_lost', 'counsellor_lost') then
        v_out := b2c.reengage(v_lead, case when coalesce((d ->> 'interest')::boolean, false) then 'witty_interest' else 'new_enquiry' end);
      elsif s.lead_id is not null and s.status = 'pool' and s.pool_reason = 'not_qualified' then
        v_out := b2c.qualify_start(v_lead, case when coalesce((d ->> 'interest')::boolean, false) then 'witty_interest' else 'new_enquiry' end);
      elsif s.lead_id is not null and s.status = 'active' and s.owner_id is null then
        v_out := b2c.allocate(v_lead, 're_enquiry');
      end if;
      -- engagement (B9.5): Witty or the website agent again, or a new form
      if s.lead_id is not null then
        perform b2c.score_add(v_lead, case when v_src in ('witty', 'web_agent') or coalesce((d ->> 'interest')::boolean, false) then 'witty_resumed' else 'form_filled' end,
                              null, jsonb_build_object('envelope', e.envelope_id));
      end if;

    elsif v_type = 'b2c.lead_requalified' then
      perform b2c.close_lead(v_lead, 'closed', 'requalified');
      update b2c.qualify_requests set status = 'closed' where lead_id = v_lead and status in ('waiting', 'escalated');
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'system', 'Qualified: back to partner routing (' || coalesce(d ->> 'destination', '?') || ')', d, coalesce(e.occurred_at, now()));

    elsif v_type = 'b2c.lead_reengaged' then
      update b2c.leads_state set missing = coalesce(d -> 'missing', missing), tags = (select array(select distinct unnest(tags || array['to_qualify']))), updated_at = now()
       where lead_id = v_lead;
      select * into s from b2c.leads_state where lead_id = v_lead;
      if s.status = 'pool' and coalesce(s.pool_reason, s.handoff_reason) = 'not_qualified' then
        v_out := b2c.qualify_start(v_lead, coalesce(d ->> 'trigger', 'witty_interest'));
      else
        insert into b2c.activities (lead_id, kind, body, meta, at)
        values (v_lead, 'reengaged', 'Re-engaged, still missing: ' || coalesce((select string_agg(m, ', ') from jsonb_array_elements_text(d -> 'missing') m), '?'), d, coalesce(e.occurred_at, now()));
      end if;

    elsif v_type = 'b2c.consent_requested' then
      insert into b2c.consent_requests (request_id, lead_id, context, programme, text_body, text_version, expires_at)
      values ((d ->> 'request_id')::bigint, v_lead, d ->> 'context', d ->> 'programme', d ->> 'text', d ->> 'text_version', nullif(d ->> 'expires_at', '')::timestamptz)
      on conflict (request_id) do nothing;
      perform b2c.queue_consent_request((d ->> 'request_id')::bigint);

    elsif v_type = 'b2c.consent_closed' then
      update b2c.consent_requests set status = coalesce(d ->> 'status', status), answer = coalesce(d ->> 'answer', answer),
             closed_at = coalesce(nullif(d ->> 'closed_at', '')::timestamptz, now()), close_why = d ->> 'why'
       where request_id = (d ->> 'request_id')::bigint;
      update b2c.send_queue set status = 'cancelled' where consent_request_id = (d ->> 'request_id')::bigint and status = 'queued';

    elsif v_type = 'b2c.lead_flagged' then
      update b2c.leads_state set flagged = coalesce(d ->> 'classification', 'flagged'), flag_reviewed_at = null, flag_reviewed_by = null, updated_at = now() where lead_id = v_lead;
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'system', 'Lead flagged: ' || coalesce(d ->> 'classification', 'flagged') || '. Waiting for the Admin; no marketing meanwhile.', d, coalesce(e.occurred_at, now()));
      perform b2c.notify_admins('flagged', 'Lead flagged: ' || coalesce(d ->> 'classification', ''), 'Review it: close as junk or keep it.',
                                '/w/leads/flagged', v_lead, 'flag:' || e.envelope_id);

    elsif v_type = 'b2c.lead_close_agreed' then
      perform b2c.notify_admins('close_agreed', 'A partner agreed to stop working a lead you hold', null, '/w/leads/' || v_lead, v_lead, 'close:' || e.envelope_id);

    elsif v_type = 'b2b.lead_routed_to_partner' then
      update b2c.leads_state set routed_to_partner_at = now(), updated_at = now() where lead_id = v_lead;
      perform b2c.close_lead(v_lead, 'closed', 'routed_to_partner');
      update b2c.qualify_requests set status = 'closed' where lead_id = v_lead and status in ('waiting', 'escalated');
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'system', 'Accepted by a partner: closed in B2C', d, coalesce(e.occurred_at, now()));

    elsif v_type = 'ping' then
      null;
    else
      update b2c.inbox set status = 'ignored', applied_at = now() where envelope_id = p_id;
      return jsonb_build_object('status', 'ignored');
    end if;
    update b2c.inbox set status = 'applied', applied_at = now(), error = null where envelope_id = p_id;
    return jsonb_build_object('status', 'applied') || coalesce(v_out, '{}');
  exception when others then
    update b2c.inbox set status = 'error', error = left(sqlerrm, 500) where envelope_id = p_id;
    return jsonb_build_object('status', 'error', 'error', sqlerrm);
  end;
end $f$;

-- ---------- WhatsApp in (b17), with START to opt in again ----------
create or replace function b2c.wa_inbound(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_phone text := b2c.norm_phone(p ->> 'from'); v_text text := trim(coalesce(p ->> 'text', p ->> 'button', p -> 'media' ->> 'caption', ''));
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
    insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
    values ('intake', null, 'b2c-in-' || v_phone, jsonb_build_object('phone', v_phone, 'lead_source', 'b2c_whatsapp', 'name', p ->> 'profile_name',
            'first_message', left(v_text, 500)), true)
    on conflict (request_id) do nothing;
    perform b2c.notify_admins('new_whatsapp', 'New student on the B2C WhatsApp number', left(v_text, 200), '/w/inbox', null, 'newwa:' || v_phone);
    return jsonb_build_object('status', 'new_lead_requested');
  end if;

  select * into s from b2c.leads_state where lead_id = v_lead;
  insert into b2c.activities (lead_id, kind, direction, body, meta)
  values (v_lead, 'whatsapp', 'in', case when p -> 'media' is not null then '[' || coalesce(p ->> 'kind', 'file') || '] ' else '' end || left(v_text, 500),
          jsonb_build_object('message_id', v_id) || case when p -> 'media' is not null then jsonb_build_object('media', true) else '{}'::jsonb end);
  update b2c.leads_state set last_activity_at = now() where lead_id = v_lead;

  if exists (select 1 from jsonb_array_elements_text(coalesce(b2c.setting('opt_out_words') -> 'words', '[]')) w where v_low = w or v_low like w || ' %') then
    perform b2c.opt_out(v_lead, null, 'stop_word', v_text);
    return jsonb_build_object('status', 'opted_out');
  end if;
  if b2c.opted_out_now(v_lead) then
    if exists (select 1 from jsonb_array_elements_text(coalesce(b2c.setting('opt_in_words') -> 'words', '[]')) w where v_low = w) then
      perform b2c.opt_in(v_lead, null, 'start_word', v_text);
      return jsonb_build_object('status', 'opted_in');
    end if;
    return jsonb_build_object('status', 'opted_out_received');
  end if;

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
  perform b2c.queue_activity(v_lead, 'whatsapp', now(), 'reply', null, left(v_text, 500));
  if coalesce(p ->> 'text', p ->> 'button', '') = '' then return jsonb_build_object('status', 'media_received'); end if;
  return b2c.reply_receive(v_lead, 'whatsapp', nullif(p ->> 'text', ''), nullif(p ->> 'button', ''), jsonb_build_object('message_id', v_id));
end $f$;

-- ---------- journeys: more triggers and the "update" step (B9.4) ----------
/* Fields an "update" step may set: the temperature, a tag removed, or a profile field (sent to the B2B CRM). */
create or replace function b2c.journey_check_steps(p_steps jsonb) returns void language plpgsql stable set search_path = '' as $f$
declare s jsonb; v_ids text[] := '{}'; t text;
begin
  if jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) = 0 then raise exception 'a journey needs at least one step'; end if;
  if jsonb_array_length(p_steps) > 60 then raise exception 'at most 60 steps'; end if;
  for s in select * from jsonb_array_elements(p_steps) loop
    if coalesce(s ->> 'id', '') = '' then raise exception 'every step needs an id'; end if;
    if s ->> 'id' = any (v_ids) then raise exception 'step id % is used twice', s ->> 'id'; end if;
    v_ids := v_ids || (s ->> 'id');
    t := s ->> 'type';
    if t not in ('send', 'wait', 'branch', 'score', 'tag', 'update', 'task', 'assign', 'move', 'exit') then raise exception 'unknown step type %', t; end if;
    if t = 'send' and (s ->> 'channel' not in ('whatsapp', 'email') or s -> 'template' is null) then raise exception 'step %: choose the channel and the template', s ->> 'id'; end if;
    if t = 'wait' and coalesce((s ->> 'days')::numeric, (s ->> 'hours')::numeric, (s ->> 'minutes')::numeric) is null and s ->> 'until' is null then raise exception 'step %: how long to wait', s ->> 'id'; end if;
    if t = 'branch' and s ->> 'on' not in ('reply', 'condition', 'ab') then raise exception 'step %: branch on a reply, a condition or an A/B split', s ->> 'id'; end if;
    if t = 'branch' and s ->> 'on' = 'condition' then perform b2c.filters_where(coalesce(s -> 'filters', '{}')); end if;
    if t = 'update' then
      if coalesce(s ->> 'field', '') = '' or coalesce(s ->> 'value', '') = '' then raise exception 'step %: choose the field and its value', s ->> 'id'; end if;
      if s ->> 'field' = 'temperature' and s ->> 'value' not in ('hot', 'warm', 'cold') then raise exception 'step %: temperature is hot, warm or cold', s ->> 'id'; end if;
      if s ->> 'field' not in ('temperature', 'untag') and not (s ->> 'field' = any (array['preferred_language', 'enrollment_timeline', 'annual_budget_inr', 'study_mode', 'programme_level'])) then
        raise exception 'step %: a journey cannot change %', s ->> 'id', s ->> 'field';
      end if;
    end if;
  end loop;
  for s in select * from jsonb_array_elements(p_steps) loop
    if s ->> 'then' is not null and not (s ->> 'then' = any (v_ids)) then raise exception 'step % goes to a missing step %', s ->> 'id', s ->> 'then'; end if;
    if s ->> 'else' is not null and not (s ->> 'else' = any (v_ids)) then raise exception 'step % goes to a missing step %', s ->> 'id', s ->> 'else'; end if;
  end loop;
end $f$;

create or replace function b2c.journey_check_trigger(p jsonb) returns void language plpgsql stable set search_path = '' as $f$
begin
  if p is null then return; end if;
  if coalesce(p ->> 'type', '') not in ('pool_entry', 'segment', 'tag', 'inactive', 'manual', 'field', 'date', 'email_engaged', 'wa_reply') then
    raise exception 'unknown trigger %', p ->> 'type';
  end if;
  if p ->> 'type' = 'field' then perform b2c.filters_where(coalesce(p -> 'filters', '{}')); if jsonb_array_length(coalesce(p -> 'filters' -> 'all', '[]')) + jsonb_array_length(coalesce(p -> 'filters' -> 'any', '[]')) = 0 then raise exception 'a field trigger needs a condition'; end if; end if;
  if p ->> 'type' = 'date' then
    if nullif(p ->> 'at', '') is null then raise exception 'a date trigger needs the date'; end if;
    perform (p ->> 'at')::date;
    if p -> 'filters' is not null then perform b2c.filters_where(p -> 'filters'); end if;
  end if;
  if p ->> 'type' = 'email_engaged' and coalesce(p ->> 'kind', 'open') not in ('open', 'click') then raise exception 'email trigger: open or click'; end if;
end $f$;

create or replace function b2c.journey_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint := nullif(p ->> 'id', '')::bigint;
begin
  if p ? 'draft_steps' then perform b2c.journey_check_steps(p -> 'draft_steps'); end if;
  if p ? 'trigger' then perform b2c.journey_check_trigger(p -> 'trigger'); end if;
  if coalesce((p ->> 'allow_active_sales')::boolean, false) and b2c.my_role() <> 'admin' then raise exception 'only the Admin lets a journey reach leads in active sales'; end if;
  if v is null then
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the journey'; end if;
    insert into b2c.journeys (key, name, description, trigger, priority, allow_active_sales, test_mode, draft_steps, created_by)
    values (coalesce(nullif(p ->> 'key', ''), trim(both '_' from regexp_replace(lower(p ->> 'name'), '[^a-z0-9]+', '_', 'g')) || '_' || to_char(now(), 'YYMMDDHH24MISS')),
            trim(p ->> 'name'), p ->> 'description', coalesce(p -> 'trigger', '{"type":"manual"}'), coalesce((p ->> 'priority')::int, 100),
            coalesce((p ->> 'allow_active_sales')::boolean, false), coalesce((p ->> 'test_mode')::boolean, true), coalesce(p -> 'draft_steps', '[]'), me)
    returning id into v;
  else
    update b2c.journeys set name = coalesce(nullif(trim(p ->> 'name'), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           trigger = coalesce(p -> 'trigger', trigger), priority = coalesce((p ->> 'priority')::int, priority),
           allow_active_sales = coalesce((p ->> 'allow_active_sales')::boolean, allow_active_sales), test_mode = coalesce((p ->> 'test_mode')::boolean, test_mode),
           draft_steps = coalesce(p -> 'draft_steps', draft_steps), updated_at = now()
     where id = v;
    if not found then raise exception 'unknown journey'; end if;
  end if;
  return v;
end $f$;

/* Runs one lead's journey from its current step until it has to wait (b16), plus the "update" step. */
create or replace function b2c.journey_step(p_run bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare r b2c.journey_runs; j b2c.journeys; v_steps jsonb; s jsonb; v_idx int; v_res jsonb; v_why text; v_goto text; v_ok boolean; v_n int := 0;
        st b2c.leads_state; v_out text := 'idle'; v_old jsonb;
begin
  select * into r from b2c.journey_runs where id = p_run for update skip locked;
  if r.id is null or r.status <> 'running' then return 'skip'; end if;
  select * into j from b2c.journeys where id = r.journey_id;
  select steps into v_steps from b2c.journey_versions where journey_id = r.journey_id and version = r.version;
  select * into st from b2c.leads_state where lead_id = r.lead_id;
  v_why := b2c.may_message(r.lead_id);
  if v_why is not null then perform b2c.journey_exit(r.lead_id, v_why); return 'exited'; end if;
  if st.status = 'closed' then perform b2c.journey_exit(r.lead_id, coalesce('closed: ' || st.closed_reason, 'closed')); return 'exited'; end if;
  if st.dormant_at is not null then perform b2c.journey_exit(r.lead_id, 'dormant'); return 'exited'; end if;
  if st.status = 'active' and st.owner_id is not null and not j.allow_active_sales then
    perform b2c.journey_exit(r.lead_id, case when st.reengaged_at >= r.entered_at then 're-engaged' else 'assigned' end); return 'exited';
  end if;
  if j.status in ('paused', 'archived') then return 'journey ' || j.status; end if;
  if st.flagged is not null then
    update b2c.journey_runs set next_at = now() + interval '1 hour' where id = r.id;
    return 'waiting: flagged';
  end if;

  v_idx := r.step_idx;
  loop
    v_n := v_n + 1;
    if v_idx >= jsonb_array_length(v_steps) or v_n > 25 then
      update b2c.journey_runs set status = 'done', exited_at = now(), exit_reason = 'completed', step_idx = v_idx where id = r.id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, outcome) values (r.id, r.lead_id, v_idx, 'completed');
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'completed';
    end if;
    s := v_steps -> v_idx; v_goto := null;
    case s ->> 'type'
    when 'send' then
      v_res := case s ->> 'channel' when 'whatsapp'
                 then b2c.queue_marketing_wa(r.lead_id, b2c.journey_template('whatsapp', s -> 'template'), 'journey', jsonb_build_object('run_id', r.id, 'journey', j.key), j.allow_active_sales)
                 else b2c.queue_marketing_email(r.lead_id, b2c.journey_template('email', s -> 'template'), 'journey', jsonb_build_object('run_id', r.id, 'journey', j.key), j.allow_active_sales) end;
      if v_res ? 'blocked' and v_res ->> 'blocked' like 'wait:%' then
        update b2c.journey_runs set step_idx = v_idx, next_at = case v_res ->> 'blocked'
            when 'wait: quiet hours' then b2c.next_send_window(now())
            when 'wait: daily cap' then b2c.next_send_window(((now() at time zone 'Asia/Kolkata')::date + 1)::timestamp at time zone 'Asia/Kolkata')
            when 'wait: 30-day cap' then b2c.next_send_window(now() + interval '3 days')
            else now() + interval '30 minutes' end where id = r.id;
        insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'send', 'waiting', v_res);
        return 'waiting';
      end if;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail)
      values (r.id, r.lead_id, v_idx, 'send', case when v_res ? 'blocked' then 'blocked' else 'sent' end, v_res || jsonb_build_object('channel', s ->> 'channel'));
      v_out := 'sent';
    when 'wait' then
      update b2c.journey_runs set step_idx = v_idx + 1, step_started_at = now(),
             next_at = case when s ? 'until' then
                         case when (now() at time zone 'Asia/Kolkata')::time < (s ->> 'until')::time
                              then ((now() at time zone 'Asia/Kolkata')::date + (s ->> 'until')::time) at time zone 'Asia/Kolkata'
                              else ((now() at time zone 'Asia/Kolkata')::date + 1 + (s ->> 'until')::time) at time zone 'Asia/Kolkata' end
                       else now() + make_interval(days => coalesce((s ->> 'days')::int, 0), hours => coalesce((s ->> 'hours')::int, 0), mins => coalesce((s ->> 'minutes')::int, 0)) end
       where id = r.id;
      return 'waiting';
    when 'branch' then
      v_ok := case s ->> 'on'
        when 'reply' then exists (select 1 from b2c.replies x where x.lead_id = r.lead_id and x.created_at >= r.entered_at
                                     and coalesce(x.corrected_class, x.class) in (select jsonb_array_elements_text(coalesce(s -> 'classes', '["positive"]'))))
        when 'ab' then (r.id % 100) < coalesce((s ->> 'pct')::int, 50)
        else b2c.lead_matches(r.lead_id, coalesce(s -> 'filters', '{}')) end;
      v_goto := case when v_ok then s ->> 'then' else s ->> 'else' end;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'branch', case when v_ok then 'branch:then' else 'branch:else' end, '{}');
    when 'score' then
      perform b2c.score_add(r.lead_id, 'journey', coalesce((s ->> 'delta')::numeric, 0), jsonb_build_object('journey', j.key));
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'score', 'scored', jsonb_build_object('delta', s -> 'delta'));
    when 'tag' then
      update b2c.leads_state set tags = array(select distinct unnest(tags || array[lower(s ->> 'tag')])) where lead_id = r.lead_id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'tag', 'tagged', jsonb_build_object('tag', s ->> 'tag'));
    when 'update' then
      if s ->> 'field' = 'temperature' then
        update b2c.leads_state set temperature = s ->> 'value', updated_at = now() where lead_id = r.lead_id;
      elsif s ->> 'field' = 'untag' then
        update b2c.leads_state set tags = array_remove(tags, lower(s ->> 'value')), updated_at = now() where lead_id = r.lead_id;
      else
        select x.record -> case when s ->> 'field' = 'preferred_language' then 'student' else 'interest' end -> (s ->> 'field') into v_old from b2c.lead_records x where x.lead_id = r.lead_id;
        if v_old is distinct from to_jsonb(s ->> 'value') then
          insert into b2c.field_history (lead_id, field, old_value, new_value, kind, reason) values (r.lead_id, s ->> 'field', v_old, to_jsonb(s ->> 'value'), 'journey', 'journey ' || j.key);
          perform b2c.queue_update(r.lead_id, jsonb_build_object(s ->> 'field', s ->> 'value'), false);
        end if;
      end if;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail)
      values (r.id, r.lead_id, v_idx, 'update', 'updated', jsonb_build_object('field', s ->> 'field', 'value', s ->> 'value'));
    when 'task' then
      insert into b2c.tasks (lead_id, owner_id, kind, title, due_at, source) values (r.lead_id, null, 'qualify', left(coalesce(s ->> 'title', 'Nurture follow-up'), 200), now(), 'journey:' || j.key);
      perform b2c.notify_admins('journey_task', left(coalesce(s ->> 'title', 'Nurture follow-up'), 120), j.name, '/w/leads/' || r.lead_id, r.lead_id, 'jtask:' || r.id || ':' || v_idx);
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome) values (r.id, r.lead_id, v_idx, 'task', 'task');
    when 'assign' then
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome) values (r.id, r.lead_id, v_idx, 'assign', 'assigned');
      perform b2c.reengage(r.lead_id, 'journey:' || j.key);
      update b2c.journey_runs set status = 'exited', exited_at = now(), exit_reason = 'assigned' where id = r.id and status = 'running';
      return 'assigned';
    when 'move' then
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'move', 'moved', jsonb_build_object('to', s ->> 'journey'));
      if exists (select 1 from b2c.journeys where key = s ->> 'journey' and current_version > 0 and status <> 'archived' and (not test_mode or r.is_test)) then
        perform b2c.journey_start(r.lead_id, (select id from b2c.journeys where key = s ->> 'journey'), 'move');
        return 'moved';
      end if;
      update b2c.journey_runs set status = 'done', exited_at = now(), exit_reason = 'completed (next journey unavailable)' where id = r.id;
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'completed';
    when 'exit' then
      update b2c.journey_runs set status = 'exited', exited_at = now(), exit_reason = coalesce(s ->> 'reason', 'exit step'), step_idx = v_idx where id = r.id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'exit', 'exited', jsonb_build_object('reason', s ->> 'reason'));
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'exited';
    else
      null;
    end case;
    v_idx := case when v_goto is not null then (select (o - 1)::int from jsonb_array_elements(v_steps) with ordinality e(x, o) where x ->> 'id' = v_goto) else v_idx + 1 end;
    update b2c.journey_runs set step_idx = v_idx, step_started_at = now() where id = r.id;
  end loop;
end $f$;

/* The leads matching a filter (journey triggers). b40 widens it to every lead property and sales activity. */
create or replace function b2c.filter_leads(p_filters jsonb, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
begin
  return query execute format('select v.lead_id from b2c.leads_v v where v.deleted_at is null and v.is_test = %L and %s', p_test, b2c.filters_where(coalesce(p_filters, '{}')));
end $f$;

/* Every minute: leads that should enter a journey now (b16), with the field, date, email and WhatsApp-reply triggers. */
create or replace function b2c.journey_enroll_tick(p_limit int default 200) returns int language plpgsql security definer set search_path = '' as $f$
declare r record; v bigint; n int := 0; j b2c.journeys; v_pred text;
begin
  for r in select s.lead_id from b2c.leads_state s
            where s.status = 'pool' and s.deleted_at is null and s.dormant_at is null and s.flagged is null
              and coalesce(s.first_message_due_at, s.pool_entered_at, s.handed_off_at) <= now()
              and not exists (select 1 from b2c.journey_runs x where x.lead_id = s.lead_id and (x.status in ('running', 'paused') or x.entered_at >= coalesce(s.pool_entered_at, s.handed_off_at)))
              and not exists (select 1 from b2c.qualify_requests q where q.lead_id = s.lead_id and q.status in ('waiting', 'escalated'))
              and b2c.may_message(s.lead_id) is null
            order by coalesce(s.first_message_due_at, s.pool_entered_at) limit p_limit loop
    v := b2c.journey_for(r.lead_id);
    if v is not null then perform b2c.journey_start(r.lead_id, v, 'pool_entry'); n := n + 1; end if;
  end loop;
  for j in select * from b2c.journeys where status = 'active' and current_version > 0
              and trigger ->> 'type' in ('segment', 'tag', 'inactive', 'field', 'date', 'email_engaged', 'wa_reply') order by priority, id loop
    v_pred := case j.trigger ->> 'type'
      when 'segment' then format('s.lead_id in (select b2c.segment_leads(%s, null, %L))', (j.trigger ->> 'segment_id')::bigint, j.test_mode)
      when 'tag' then format('%L = any (s.tags)', lower(j.trigger ->> 'tag'))
      when 'inactive' then format('coalesce(s.last_activity_at, s.pool_entered_at) < now() - make_interval(days => %s)', coalesce((j.trigger ->> 'days')::int, 30))
      when 'field' then format('s.lead_id in (select b2c.filter_leads(%L::jsonb, %L))', coalesce(j.trigger -> 'filters', '{}'), j.test_mode)
      when 'date' then format('now() >= ((%L::date - %s)::timestamp at time zone %L) and now() < ((%L::date + 1)::timestamp at time zone %L)%s',
                              j.trigger ->> 'at', coalesce((j.trigger ->> 'days_before')::int, 0), 'Asia/Kolkata', j.trigger ->> 'at', 'Asia/Kolkata',
                              case when j.trigger -> 'filters' is not null then format(' and s.lead_id in (select b2c.filter_leads(%L::jsonb, %L))', j.trigger -> 'filters', j.test_mode) else '' end)
      when 'email_engaged' then format('exists (select 1 from b2c.emails e where e.lead_id = s.lead_id and e.direction = %L and e.%s > now() - make_interval(days => %s))',
                                       'out', case when j.trigger ->> 'kind' = 'click' then 'clicked_at' else 'opened_at' end, coalesce((j.trigger ->> 'within_days')::int, 2))
      else format('exists (select 1 from b2c.replies x where x.lead_id = s.lead_id and x.channel = %L and x.created_at > now() - make_interval(days => %s) and coalesce(x.corrected_class, x.class) = any (%L::text[]))',
                  'whatsapp', coalesce((j.trigger ->> 'within_days')::int, 2),
                  coalesce((select array_agg(c) from jsonb_array_elements_text(j.trigger -> 'classes') c), array['positive', 'question', 'other'])) end;
    for r in execute format(
      'select s.lead_id from b2c.leads_state s where s.deleted_at is null and s.dormant_at is null and s.flagged is null and s.is_test = %L
          and (s.status = %L or (%L and s.status = %L))
          and not exists (select 1 from b2c.journey_runs x where x.lead_id = s.lead_id and (x.status in (%L, %L) or x.journey_id = %s))
          and %s limit %s',
      j.test_mode, 'pool', j.allow_active_sales, 'active', 'running', 'paused', j.id, v_pred, p_limit) loop
      exit when n >= p_limit;
      continue when b2c.may_message(r.lead_id) is not null;
      perform b2c.journey_start(r.lead_id, j.id, j.trigger ->> 'type'); n := n + 1;
    end loop;
  end loop;
  return n;
end $f$;

/* The journey page's numbers (b16), with WhatsApp spend next to what it produced (B9.7). */
create or replace function b2c.journey_stats(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return jsonb_build_object(
    'entered', (select count(*) from b2c.journey_runs where journey_id = p_id and not is_test),
    'running', (select count(*) from b2c.journey_runs where journey_id = p_id and status in ('running', 'paused') and not is_test),
    'completed', (select count(*) from b2c.journey_runs where journey_id = p_id and status = 'done' and not is_test),
    'at_step', (select coalesce(jsonb_object_agg(step_idx, n), '{}') from (select step_idx, count(*) n from b2c.journey_runs where journey_id = p_id and status in ('running', 'paused') group by step_idx) a),
    'exits', (select coalesce(jsonb_object_agg(coalesce(exit_reason, '?'), n), '{}') from (select exit_reason, count(*) n from b2c.journey_runs where journey_id = p_id and status = 'exited' and not is_test group by exit_reason) e),
    'sent', (select count(*) from b2c.journey_log l join b2c.journey_runs x on x.id = l.run_id where x.journey_id = p_id and l.outcome = 'sent'),
    'blocked', (select coalesce(jsonb_object_agg(k, n), '{}') from (select l.detail ->> 'blocked' k, count(*) n from b2c.journey_log l join b2c.journey_runs x on x.id = l.run_id
                 where x.journey_id = p_id and l.outcome in ('blocked', 'waiting') and l.at > now() - interval '30 days' group by 1) b),
    're_engaged', (select count(*) from b2c.journey_runs x join b2c.leads_state s on s.lead_id = x.lead_id where x.journey_id = p_id and s.reengaged_at >= x.entered_at and not x.is_test),
    'enrolled', (select count(*) from b2c.journey_runs x where x.journey_id = p_id and not x.is_test and exists (select 1 from b2c.enrollments e where e.lead_id = x.lead_id and e.created_at >= x.entered_at)),
    'wa_cost', (select coalesce(sum(m.cost_estimate), 0) from b2c.wa_messages m join b2c.journey_runs x on x.id = m.journey_run_id
                 where x.journey_id = p_id and not x.is_test and m.status in ('sent', 'delivered', 'read')),
    'emails', (select count(*) from b2c.emails e join b2c.journey_runs x on x.id = e.journey_run_id where x.journey_id = p_id and not x.is_test and e.direction = 'out'),
    'test_runs', (select count(*) from b2c.journey_runs where journey_id = p_id and is_test));
end $f$;

-- ---------- the Nurture page's numbers (B6.2, B9.0) ----------
create or replace function b2c.nurture_overview() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'pool', (select count(*) from b2c.leads_state where status = 'pool' and deleted_at is null and dormant_at is null and not is_test),
    'dormant', (select count(*) from b2c.leads_state where dormant_at is not null and deleted_at is null and not is_test),
    'by_reason', (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'age', age, 'n', n) order by reason, age), '[]') from (
                   select coalesce(case when pool_reason = 'counsellor_lost' then 'lost: ' || coalesce(sub_stage, '?')
                                        when pool_reason = 'partner_lost' then 'partner lost: ' || lower(b2c.partner_lost_sub_stage(partner_lost ->> 'lost_reason'))
                                        else pool_reason end, '?') reason,
                          case when pool_entered_at > now() - interval '30 days' then '0–30 days' when pool_entered_at > now() - interval '90 days' then '31–90 days'
                               when pool_entered_at > now() - interval '180 days' then '91–180 days' else 'over 180 days' end age, count(*) n
                     from b2c.leads_state where status = 'pool' and deleted_at is null and dormant_at is null and not is_test group by 1, 2) q),
    'flow_14d', (select coalesce(jsonb_agg(jsonb_build_object('day', d::date,
                    'in', (select count(*) from b2c.leads_state s where not s.is_test and s.pool_entered_at >= d and s.pool_entered_at < d + interval '1 day'),
                    'reengaged', (select count(*) from b2c.leads_state s where not s.is_test and s.reengaged_at >= d and s.reengaged_at < d + interval '1 day'),
                    'dormant', (select count(*) from b2c.leads_state s where not s.is_test and s.dormant_at >= d and s.dormant_at < d + interval '1 day'),
                    'opted_out', (select count(distinct ev.lead_id) from b2c.events ev join b2c.leads_state s on s.lead_id = ev.lead_id
                                   where ev.type = 'lead.opted_out' and not s.is_test and ev.at >= d and ev.at < d + interval '1 day'),
                    'closed', (select count(*) from b2c.leads_state s where not s.is_test and s.pool_entered_at is not null and s.closed_at >= d and s.closed_at < d + interval '1 day'
                                 and s.closed_reason in ('requalified', 'routed_to_partner', 'released', 'enrolled_elsewhere'))) order by d), '[]')
                 from generate_series(d0 - interval '13 days', d0, interval '1 day') d),
    'reengaged_30d', (select count(*) from b2c.leads_state where reengaged_at > now() - interval '30 days' and not is_test),
    'entered_30d', (select count(*) from b2c.leads_state where pool_entered_at > now() - interval '30 days' and not is_test),
    'hours_to_reengage', (select round(extract(epoch from percentile_cont(0.5) within group (order by reengaged_at - pool_entered_at)) / 3600)
                            from b2c.leads_state where reengaged_at > now() - interval '90 days' and pool_entered_at < reengaged_at and not is_test),
    'cost_per_reengaged', (select round(coalesce(sum(m.cost_estimate), 0) / nullif((select count(*) from b2c.leads_state where reengaged_at > now() - interval '30 days' and not is_test), 0), 2)
                             from b2c.wa_messages m where m.purpose in ('journey', 'campaign', 'marketing') and m.status in ('sent', 'delivered', 'read') and m.created_at > now() - interval '30 days'),
    'messages_today', jsonb_build_object(
       'whatsapp', (select count(*) from b2c.wa_messages where purpose in ('journey', 'campaign', 'marketing') and created_at >= d0),
       'email', (select count(*) from b2c.emails where purpose in ('journey', 'campaign', 'marketing') and created_at >= d0)),
    'email_allowance', jsonb_build_object('limit', coalesce((b2c.setting('messaging') ->> 'gmail_daily_allowance')::int, 2000), 'left', b2c.email_allowance_left()),
    'deliverability_7d', (select jsonb_build_object(
        'wa_sent', count(*) filter (where status in ('sent', 'delivered', 'read', 'failed')),
        'wa_delivered', count(*) filter (where status in ('delivered', 'read')),
        'wa_read', count(*) filter (where status = 'read'),
        'wa_failed', count(*) filter (where status = 'failed'),
        'email_sent', (select count(*) from b2c.emails e where e.purpose in ('journey', 'campaign', 'marketing') and e.direction = 'out' and e.created_at > now() - interval '7 days'),
        'email_bounced', (select count(*) from b2c.emails e where e.purpose in ('journey', 'campaign', 'marketing') and e.bounced_at > now() - interval '7 days'),
        'email_opened', (select count(*) from b2c.emails e where e.purpose in ('journey', 'campaign', 'marketing') and e.opened_at is not null and e.created_at > now() - interval '7 days'))
        from b2c.wa_messages where purpose in ('journey', 'campaign', 'marketing') and direction = 'out' and created_at > now() - interval '7 days'),
    'wa_cost_30d', (select coalesce(sum(cost_estimate), 0) from b2c.wa_messages where purpose in ('journey', 'campaign', 'marketing') and status in ('sent', 'delivered', 'read')
                      and created_at > now() - interval '30 days'),
    'replies_today', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(corrected_class, class, 'unclassified') k, count(*) n from b2c.replies where created_at >= d0 group by 1) r),
    'replies_waiting', (select count(*) from b2c.replies where status in ('inbox', 'pending_ai')),
    'to_qualify', (select count(*) from b2c.qualify_requests where status in ('waiting', 'escalated')),
    'suppressed_today', (select coalesce(jsonb_object_agg(k, n), '{}') from (
                           select k, count(distinct lead_id) n from (
                             select l.detail ->> 'blocked' k, l.lead_id from b2c.journey_log l where l.at >= d0 and l.outcome in ('blocked', 'waiting')
                             union all select x.reason, x.lead_id from b2c.campaign_sends x where x.done_at >= d0 and x.status in ('blocked', 'skipped')) a
                           where k is not null group by k) s),
    'wa_quality', b2c.setting('wa_quality'),
    'journeys_running', (select count(*) from b2c.journey_runs where status = 'running' and not is_test));
end $f$;

/* The pool, lead by lead (B6.2), with the last message and the student's last activity on either channel. */
create or replace function b2c.pool_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_limit int := least(coalesce((p ->> 'limit')::int, 100), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0); q text := nullif(trim(p ->> 'q'), '');
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select jsonb_build_object('total', coalesce(max(t.total), 0), 'rows', coalesce(jsonb_agg(t.x order by t.ord), '[]')) from (
    select count(*) over () as total, row_number() over (order by v.pool_entered_at desc nulls last, v.lead_id desc) as ord,
           jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'course', v.course, 'reason', v.pool_reason, 'sub_stage', v.sub_stage, 'lost_by', v.lost_by,
             'lost_detail', coalesce(s.partner_lost ->> 'partner_name', u.full_name),
             'lost_reason', coalesce(s.partner_lost ->> 'lost_reason', v.sub_stage),
             'mapped_sub_stage', case when v.pool_reason = 'partner_lost' then b2c.partner_lost_sub_stage(s.partner_lost ->> 'lost_reason') end,
             'missing', s.missing, 'score', v.score, 'trend_7d', (select coalesce(sum(points), 0) from b2c.score_events e where e.lead_id = v.lead_id and e.at > now() - interval '7 days'),
             'marketing_consent', jsonb_build_object('whatsapp', b2c.has_marketing_consent(v.lead_id, 'whatsapp'), 'email', b2c.has_marketing_consent(v.lead_id, 'email')),
             'journey', (select jsonb_build_object('name', j.name, 'step', r.step_idx + 1, 'status', r.status, 'next_at', r.next_at) from b2c.journey_runs r join b2c.journeys j on j.id = r.journey_id
                          where r.lead_id = v.lead_id and r.status in ('running', 'paused') limit 1),
             'qualifying', exists (select 1 from b2c.qualify_requests qr where qr.lead_id = v.lead_id and qr.status in ('waiting', 'escalated')),
             'flagged', v.flagged,
             'first_message_due_at', s.first_message_due_at, 'pool_entered_at', v.pool_entered_at,
             'last_message', (select jsonb_build_object('channel', z.channel, 'status', z.status, 'at', z.at) from (
                                select 'whatsapp' channel, m.status, m.created_at at from b2c.wa_messages m
                                 where m.lead_id = v.lead_id and m.direction = 'out' and m.purpose in ('journey', 'campaign', 'marketing')
                                union all
                                select 'email', case when e.bounced_at is not null then 'bounced' when e.clicked_at is not null then 'clicked' when e.opened_at is not null then 'opened' else e.status end, e.created_at
                                  from b2c.emails e where e.lead_id = v.lead_id and e.direction = 'out' and e.purpose in ('journey', 'campaign', 'marketing')
                                order by at desc limit 1) z),
             'last_student_at', greatest((select max(m.created_at) from b2c.wa_messages m where m.lead_id = v.lead_id and m.direction = 'in'),
                                         (select max(e.created_at) from b2c.emails e where e.lead_id = v.lead_id and e.direction = 'in'),
                                         (select max(e.clicked_at) from b2c.emails e where e.lead_id = v.lead_id))) x
      from b2c.leads_v v join b2c.leads_state s on s.lead_id = v.lead_id left join b2c.users u on u.user_id = s.lost_by_user
     where v.status = 'pool' and v.deleted_at is null and s.dormant_at is null and v.is_test = coalesce((p ->> 'test')::boolean, false)
       and (p ->> 'reason' is null or v.pool_reason = p ->> 'reason')
       and (q is null or v.name ilike '%' || q || '%' or v.lead_id::text = q or (regexp_replace(q, '\D', '', 'g') <> '' and b2c.norm_phone(v.phone) like '%' || regexp_replace(q, '\D', '', 'g') || '%'))
     order by v.pool_entered_at desc nulls last, v.lead_id desc
     limit v_limit offset v_offset) t);
end $f$;

-- ---------- campaign results (B9.3) ----------
create or replace function b2c.campaign_stats(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare c b2c.campaigns;
begin
  perform b2c.require('marketing');
  select * into c from b2c.campaigns where id = p_id;
  if c.id is null then raise exception 'unknown campaign'; end if;
  return (select jsonb_build_object(
    'audience', count(*), 'queued', count(*) filter (where x.status = 'queued'), 'pending', count(*) filter (where x.status in ('pending', 'held')),
    'sent', count(*) filter (where m.status in ('sent', 'delivered', 'read') or e.status in ('sent', 'delivered') or e.opened_at is not null),
    'blocked', count(*) filter (where x.status in ('blocked', 'skipped')),
    'blocked_by', (select coalesce(jsonb_object_agg(reason, n), '{}') from (select reason, count(*) n from b2c.campaign_sends where campaign_id = p_id and status in ('blocked', 'skipped') group by reason) b),
    'by_variant', (select coalesce(jsonb_object_agg(variant, n), '{}') from (select variant, count(*) n from b2c.campaign_sends where campaign_id = p_id and status = 'queued' and variant is not null group by variant) v),
    'delivered', count(*) filter (where m.status in ('delivered', 'read')), 'read', count(*) filter (where m.status = 'read'),
    'test_mode', count(*) filter (where m.status = 'dry_run' or e.status = 'dry_run'),
    'opened', count(*) filter (where e.opened_at is not null), 'clicked', count(*) filter (where e.clicked_at is not null),
    'bounced', count(*) filter (where e.bounced_at is not null),
    'replied', count(*) filter (where exists (select 1 from b2c.replies rp where rp.lead_id = x.lead_id and rp.created_at > x.done_at)),
    'replied_positive', count(*) filter (where exists (select 1 from b2c.replies rp where rp.lead_id = x.lead_id and rp.created_at > x.done_at and coalesce(rp.corrected_class, rp.class) = 'positive')),
    'replied_negative', count(*) filter (where exists (select 1 from b2c.replies rp where rp.lead_id = x.lead_id and rp.created_at > x.done_at and coalesce(rp.corrected_class, rp.class) = 'negative')),
    'opted_out', count(*) filter (where exists (select 1 from b2c.events ev where ev.lead_id = x.lead_id and ev.type = 'lead.opted_out' and ev.at > x.done_at)),
    're_engaged', count(*) filter (where exists (select 1 from b2c.leads_state ls where ls.lead_id = x.lead_id and ls.reengaged_at > x.done_at)),
    'enrolled', count(*) filter (where exists (select 1 from b2c.enrollments en where en.lead_id = x.lead_id and en.created_at > x.done_at)),
    'cost', coalesce(sum(m.cost_estimate) filter (where m.status in ('sent', 'delivered', 'read')), 0),
    'winner', c.winner)
    from b2c.campaign_sends x left join b2c.wa_messages m on m.id = x.wa_message_id left join b2c.emails e on e.id = x.email_id
   where x.campaign_id = p_id);
end $f$;

-- ---------- the minute timer (b17) with the qualification step ----------
create or replace function b2c.nurture_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('journeys', b2c.journey_tick(300)); exception when others then v := v || jsonb_build_object('journeys_error', sqlerrm); end;
  begin v := v || jsonb_build_object('campaigns', b2c.campaign_tick()); exception when others then v := v || jsonb_build_object('campaigns_error', sqlerrm); end;
  begin v := v || jsonb_build_object('qualify', b2c.qualify_tick()); exception when others then v := v || jsonb_build_object('qualify_error', sqlerrm); end;
  update b2c.replies set status = 'inbox', method = coalesce(method, 'none') where status = 'pending_ai' and created_at < now() - interval '10 minutes';
  return v;
end $f$;

/* The designated Replies counsellors (B6.3), set by the Admin. */
create or replace function b2c.replies_delegates_set(p_users uuid[]) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from unnest(coalesce(p_users, '{}')) x where not exists (select 1 from b2c.users u where u.user_id = x and u.is_active and u.role in ('counsellor', 'sales_head'))) then
    raise exception 'choose active counsellors';
  end if;
  update b2c.settings set value = value || jsonb_build_object('replies_user_ids', to_jsonb(coalesce(p_users, '{}'))), updated_at = now(), version = version + 1, actor_id = b2c.uid()
   where key = 'nurture';
  perform b2c.log('settings.replies_delegates', null, jsonb_build_object('users', to_jsonb(p_users)));
end $f$;

-- ---------- grants ----------
grant select on b2c.qualify_requests to service_role;
grant execute on function b2c.opt_in(bigint, text[], text, text), b2c.qualify_record(bigint, jsonb), b2c.qualify_queue(jsonb), b2c.qualify_assign(bigint, uuid),
  b2c.qualify_resend(bigint), b2c.flag_review(bigint, text, text), b2c.flagged_list(), b2c.replies_delegates_set(uuid[]) to authenticated;
grant execute on function b2c.qualify_form(text), b2c.qualify_submit(text, jsonb) to service_role;
revoke execute on function b2c.qualify_form(text), b2c.qualify_submit(text, jsonb), b2c.qualify_apply(bigint, jsonb, text, uuid), b2c.qualify_start(bigint, text),
  b2c.qualify_send(bigint), b2c.qualify_tick(), b2c.qualify_questions(jsonb), b2c.qualify_link(text), b2c.queue_system_email(bigint, text, text, text, text, timestamptz),
  b2c.queue_system_text(bigint, text, text, text), b2c.partner_lost_sub_stage(text), b2c.partner_lost_due(jsonb), b2c.partner_history_text(jsonb),
  b2c.opted_out_now(bigint), b2c.qual_rank(text), b2c.filter_leads(jsonb, boolean), b2c.journey_check_trigger(jsonb), b2c.replies_delegate(uuid) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
