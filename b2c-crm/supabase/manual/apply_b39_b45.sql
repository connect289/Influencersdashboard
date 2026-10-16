-- Eduwit Spark: migrations b39 to b45 in one file, for the Supabase SQL editor (staging first, then production).
-- Idempotent: safe to run again, and safe where some of it is already applied. Generated from migrations/b39…b45; do not edit here.

-- ===== b39_nurture_completion.sql =====
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

-- ===== b40_leads_admin.sql =====
-- B2C CRM b40: completing the leads table and the Admin's tools (docs/completion-gaps.md, section B, plus A9, D1, D2).
-- Staging first. Idempotent.
--   leads_wide_v           every lead property and sales activity in one row: the table's columns, filters, segments
--   lead_list()            any of those fields as a filter or sort; relative dates; group-by with totals; all ids of a view
--   views                  shared with the same role by link; each person's default view per interface
--   bulk                   journeys (Marketing too) and stage changes in bulk; bulk delete as a background job with typed
--                          confirmation and undo for 30 days
--   lead_erase()           the DPDP erasure request: personal fields anonymised, message bodies and documents removed,
--                          money rows kept, the B2B CRM told
--   exports                large exports in the background with an expiring link
--   events_feed()          the reconciliation feed of what Spark sent the B2B CRM (GET /v1/events?since=)
--   b2c_lead_status_v      the published read-only status of each B2C lead, for the B2B CRM

create index if not exists enrollments_lead on b2c.enrollments (lead_id);
create index if not exists emails_lead_dir on b2c.emails (lead_id, direction, created_at desc);
alter table b2c.leads_state add column if not exists erase_reference text;

-- ---------- one wide row per lead ----------
create or replace view b2c.leads_wide_v with (security_invoker = true) as
select v.*,
       coalesce(nullif(v.lead_created_at #>> '{}', '')::timestamptz, v.handed_off_at) as created_at,
       r.record -> 'interest' ->> 'enrollment_timeline' as timeline,
       nullif(regexp_replace(coalesce(r.record -> 'interest' ->> 'annual_budget_inr', ''), '[^0-9.]', '', 'g'), '')::numeric as budget,
       r.record -> 'education' ->> 'work_experience_years' as work_experience,
       s.partner_lost ->> 'partner_name' as partner,
       s.partner_lost ->> 'lost_reason' as partner_lost_reason,
       jsonb_array_length(coalesce(s.partners_tried, '[]')) as partners_tried_count,
       s.engagement_points, s.fit_points, s.delete_reason,
       c.calls_logged, c.calls_connected, c.last_call_outcome, c.last_call_at,
       w.wa_sent, w.wa_received, w.last_wa_in_at,
       m.emails_sent, m.emails_opened, m.last_email_at,
       rp.last_reply_at, rp.last_reply_class,
       floor(extract(epoch from now() - v.stage_changed_at) / 86400)::int as days_in_stage,
       floor(extract(epoch from now() - coalesce(v.last_activity_at, v.assigned_at, v.handed_off_at)) / 86400)::int as days_untouched,
       case when v.sla_breached_at is not null and v.sla_met_at is null then 'breached'
            when v.sla_met_at is not null then 'met'
            when v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'at_risk'
            when v.sla_due_at is not null then 'running' end as sla_status,
       ap.application_status, ap.application_ref, ap.documents_pending,
       en.enrollment_status, en.enrolled_on, en.fee,
       mo.university_gross, mo.university_net, mo.university_gst, mo.university_status, mo.counsellor_commission
  from b2c.leads_v v
  join b2c.leads_state s on s.lead_id = v.lead_id
  left join b2c.lead_records r on r.lead_id = v.lead_id
  left join lateral (select count(*) filter (where k.logged_at is not null)::int calls_logged, count(*) filter (where k.outcome = 'connected')::int calls_connected,
                            (array_agg(k.outcome order by k.logged_at desc nulls last) filter (where k.logged_at is not null))[1] last_call_outcome,
                            max(k.logged_at) last_call_at
                       from b2c.calls k where k.lead_id = v.lead_id) c on true
  left join lateral (select count(*) filter (where x.direction = 'out')::int wa_sent, count(*) filter (where x.direction = 'in')::int wa_received,
                            max(x.created_at) filter (where x.direction = 'in') last_wa_in_at
                       from b2c.wa_messages x where x.lead_id = v.lead_id) w on true
  left join lateral (select count(*) filter (where x.direction = 'out')::int emails_sent, count(*) filter (where x.opened_at is not null)::int emails_opened,
                            max(x.created_at) last_email_at
                       from b2c.emails x where x.lead_id = v.lead_id) m on true
  left join lateral (select x.created_at last_reply_at, coalesce(x.corrected_class, x.class) last_reply_class
                       from b2c.replies x where x.lead_id = v.lead_id order by x.created_at desc limit 1) rp on true
  left join lateral (select a.status application_status, a.application_ref,
                            (select count(*) from jsonb_each_text(a.checklist) ck where ck.value <> 'received')::int documents_pending
                       from b2c.applications a where a.lead_id = v.lead_id order by a.created_at desc limit 1) ap on true
  left join lateral (select e.status enrollment_status, e.enrolled_on, e.fee from b2c.enrollments e where e.lead_id = v.lead_id order by e.created_at desc limit 1) en on true
  left join lateral (select sum(g.gross) university_gross, sum(g.net) university_net, sum(g.gst) university_gst,
                            case when count(g.id) = 0 then null when bool_and(g.invoice_id is not null) then 'invoiced' when bool_or(g.realised_at is not null) then 'realised' else 'expected' end university_status,
                            (select sum(l.amount) from b2c.commission_lines l where l.lead_id = v.lead_id and l.status <> 'void') counsellor_commission
                       from b2c.enrollments e2 join b2c.earnings g on g.enrollment_id = e2.id where e2.lead_id = v.lead_id) mo on true;
revoke all on b2c.leads_wide_v from public, anon, authenticated;
grant select on b2c.leads_wide_v to service_role;

/* Every field a view, a filter, a segment or a sort may use (B8.2, B9.1, B10.1). */
create or replace function b2c.lead_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at',
    'created_at','timeline','budget','work_experience','partner','partner_lost_reason','partners_tried_count','engagement_points','fit_points',
    'calls_logged','calls_connected','last_call_outcome','last_call_at','wa_sent','wa_received','last_wa_in_at','emails_sent','emails_opened','last_email_at',
    'last_reply_at','last_reply_class','days_in_stage','days_untouched','sla_status','application_status','application_ref','documents_pending',
    'enrollment_status','enrolled_on','fee','university_gross','university_net','university_gst','university_status','counsellor_commission']
$f$;

/* The money columns: Admin and Marketing only (B10.1, B11). */
create or replace function b2c.money_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['university_gross','university_net','university_gst','university_status','counsellor_commission']
$f$;

create or replace function b2c.segment_fields() returns text[] language sql immutable set search_path = '' as $f$
  select b2c.lead_fields()
$f$;

/* One condition as SQL. Fields and operators are whitelisted; values are quoted. Relative dates in India time. */
create or replace function b2c.filter_sql(c jsonb, allowed text[]) returns text language plpgsql stable set search_path = '' as $f$
declare fld text := c ->> 'field'; op text := c ->> 'op'; val jsonb := c -> 'value'; d0 text := '(date_trunc(''day'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata'')';
begin
  if not fld = any (allowed) then raise exception 'cannot filter on %', fld; end if;
  return case op
    when 'eq' then format('%I::text = %L', fld, val #>> '{}')
    when 'neq' then format('%I::text is distinct from %L', fld, val #>> '{}')
    when 'in' then format('%I::text = any (%L::text[])', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'not_in' then format('not coalesce(%I::text = any (%L::text[]), false)', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'contains' then format('%I::text ilike %L', fld, '%' || (val #>> '{}') || '%')
    when 'gte' then format('%I >= %L', fld, val #>> '{}')
    when 'lte' then format('%I <= %L', fld, val #>> '{}')
    when 'gt' then format('%I > %L', fld, val #>> '{}')
    when 'lt' then format('%I < %L', fld, val #>> '{}')
    when 'between' then format('%I between %L and %L', fld, val ->> 0, val ->> 1)
    when 'is_null' then format('%I is null', fld)
    when 'not_null' then format('%I is not null', fld)
    when 'is_true' then format('%I is true', fld)
    when 'is_false' then format('%I is not true', fld)
    when 'lte_now' then format('%I <= now()', fld)
    when 'older_than_days' then format('%I < now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'within_days' then format('%I >= now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'next_days' then format('%I >= now() and %I < now() + make_interval(days => %s)', fld, fld, (val #>> '{}')::int)
    when 'today' then format('%I >= %s and %I < %s + interval ''1 day''', fld, d0, fld, d0)
    when 'this_week' then format('%I >= date_trunc(''week'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'this_month' then format('%I >= date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'last_month' then format('%I >= (date_trunc(''month'', now() at time zone ''Asia/Kolkata'') - interval ''1 month'') at time zone ''Asia/Kolkata'' and %I < date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld, fld)
    when 'has_tag' then format('%L = any (tags)', val #>> '{}')
    when 'not_tag' then format('not (%L = any (coalesce(tags, ''{}'')))', val #>> '{}')
    else 'false' end;
end $f$;

/* Segments, journey conditions and filters read the wide row too. */
create or replace function b2c.segment_leads(p_segment bigint, p_filters jsonb default null, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
declare g b2c.segments;
begin
  if p_segment is not null then select * into g from b2c.segments where id = p_segment; end if;
  if g.kind = 'static' then
    return query select m.lead_id from b2c.segment_members m join b2c.leads_state s on s.lead_id = m.lead_id
                  where m.segment_id = g.id and m.removed_at is null and s.deleted_at is null and s.is_test = p_test;
  else
    return query execute format('select v.lead_id from b2c.leads_wide_v v where v.deleted_at is null and v.is_test = %L and %s',
                                p_test, b2c.filters_where(coalesce(p_filters, g.filters, '{}')));
  end if;
end $f$;

create or replace function b2c.lead_matches(p_lead bigint, p_filters jsonb) returns boolean language plpgsql stable security definer set search_path = '' as $f$
declare v boolean;
begin
  execute format('select exists (select 1 from b2c.leads_wide_v v where v.lead_id = %s and %s)', p_lead, b2c.filters_where(p_filters)) into v;
  return v;
end $f$;

create or replace function b2c.filter_leads(p_filters jsonb, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
begin
  return query execute format('select v.lead_id from b2c.leads_wide_v v where v.deleted_at is null and v.is_test = %L and %s', p_test, b2c.filters_where(coalesce(p_filters, '{}')));
end $f$;

/* Who sees which leads in lists: a counsellor their own; the sales head their team (b42 narrows it); everyone else all. */
create or replace function b2c.lead_scope_sql(p_user uuid, p_role text) returns text language plpgsql stable security definer set search_path = '' as $f$
begin
  return case p_role when 'counsellor' then format('owner_id = %L', p_user) else 'true' end;
end $f$;

/* Filtered, sorted, paged lead list for a view (B8.2, B10.1), on the wide row. Also: p.ids (selected rows only),
   p.mode = 'ids' (every id of the view, for "select all"), p.group_by (counts and totals over the whole view).
   lead_list_as() is the same list for a named person: the background export runs it for the Admin who asked. */
create or replace function b2c.lead_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  return b2c.lead_list_as(p, b2c.uid(), b2c.my_role());
end $f$;

create or replace function b2c.lead_list_as(p jsonb, p_user uuid, p_role text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_role text := p_role; me uuid := p_user; w text;
  v_test_user boolean := coalesce((select u.is_test_user from b2c.users u where u.user_id = p_user), false); c jsonb; v_sql text; v_rows jsonb; v_total int;
  v_any text; f jsonb := coalesce(p -> 'filters', '{}'); v_sort text; v_dir text; v_limit int := least(coalesce((p ->> 'limit')::int, 50), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
  allowed text[] := b2c.lead_fields(); v_drill bigint[]; v_group text; v_groups jsonb; v_ids bigint[]; v_strip text[];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role not in ('admin', 'marketing') then allowed := array(select x from unnest(allowed) x where not x = any (b2c.money_fields())); end if;
  w := b2c.lead_scope_sql(me, v_role);
  if nullif(p ->> 'drill', '') is not null then
    select lead_ids into v_drill from b2c.analytics_drills where id = (p ->> 'drill')::uuid and user_id = me;
    w := w || format(' and lead_id = any (%L::bigint[])', coalesce(v_drill, '{}'));
  end if;
  if jsonb_typeof(p -> 'ids') = 'array' then
    w := w || format(' and lead_id = any (%L::bigint[])', (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(p -> 'ids') x));
  end if;
  w := w || case when coalesce((p ->> 'deleted')::boolean, false)
                 then ' and deleted_at is not null and not exists (select 1 from b2c.leads_state z where z.lead_id = v.lead_id and z.erased_at is not null)'
                 else ' and deleted_at is null' end;
  if not coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_drill is not null or v_test_user) then w := w || ' and not is_test'; end if;
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, allowed);
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  -- AND/OR groups: {"groups": [{"any": [...]}, {"all": [...]}]} each group is one bracket
  for c in select * from jsonb_array_elements(coalesce(f -> 'groups', '[]')) loop
    if jsonb_array_length(coalesce(c -> 'any', '[]')) > 0 then
      select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(c -> 'any') x;
      w := w || ' and (' || v_any || ')';
    end if;
    if jsonb_array_length(coalesce(c -> 'all', '[]')) > 0 then
      select string_agg(b2c.filter_sql(x, allowed), ' and ') into v_any from jsonb_array_elements(c -> 'all') x;
      w := w || ' and (' || v_any || ')';
    end if;
  end loop;
  if coalesce(trim(p ->> 'search'), '') <> '' then
    w := w || format(' and (name ilike %1$L or email ilike %1$L or b2c.norm_phone(phone) like %2$L or lead_id::text = %3$L
                       or exists (select 1 from b2c.lead_contacts lc where lc.lead_id = v.lead_id and lc.value_norm like %2$L)
                       or exists (select 1 from b2c.applications ap where ap.lead_id = v.lead_id and ap.application_ref ilike %1$L))',
                     '%' || trim(p ->> 'search') || '%', '%' || coalesce(nullif(regexp_replace(p ->> 'search', '\D', '', 'g'), ''), '~none~') || '%', trim(p ->> 'search'));
  end if;
  if p ->> 'mode' = 'ids' then
    execute format('select array_agg(lead_id order by lead_id) from (select lead_id from b2c.leads_wide_v v where %s limit 20001) q', w) into v_ids;
    if coalesce(array_length(v_ids, 1), 0) > 20000 then raise exception 'more than 20,000 leads: narrow the view first'; end if;
    return jsonb_build_object('total', coalesce(array_length(v_ids, 1), 0), 'ids', coalesce(to_jsonb(v_ids), '[]'));
  end if;
  v_sort := coalesce(p -> 'sort' ->> 'field', 'next_task_due_at');
  if not v_sort = any (allowed) then v_sort := 'next_task_due_at'; end if;
  v_dir := case when lower(coalesce(p -> 'sort' ->> 'dir', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_strip := case when v_role in ('admin', 'marketing') then '{}'::text[] else b2c.money_fields() end;
  v_sql := format('select count(*) over () total, to_jsonb(v) - ''providers'' - ''handling'' - %L::text[] as row from b2c.leads_wide_v v where %s order by %I %s nulls last, lead_id desc limit %s offset %s',
                  v_strip, w, v_sort, v_dir, v_limit, v_offset);
  execute format('select coalesce(max(total), 0), coalesce(jsonb_agg(row), ''[]'') from (%s) q', v_sql) into v_total, v_rows;
  v_group := nullif(p ->> 'group_by', '');
  if v_group is not null then
    if not v_group = any (allowed) then raise exception 'cannot group by %', v_group; end if;
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''key'', k, ''count'', n, ''expected'', x, ''commission'', y) order by n desc), ''[]'') from (
                      select %I::text k, count(*) n, sum(coalesce(university_gross, 0)) x, sum(coalesce(counsellor_commission, 0)) y
                        from b2c.leads_wide_v v where %s group by 1 order by 2 desc limit 100) g', v_group, w) into v_groups;
    if v_role not in ('admin', 'marketing') then
      select coalesce(jsonb_agg(gx - 'expected' - 'commission'), '[]') into v_groups from jsonb_array_elements(v_groups) gx;
    end if;
  end if;
  return jsonb_build_object('total', v_total, 'rows', v_rows) || case when v_group is not null then jsonb_build_object('groups', v_groups, 'group_by', v_group) else '{}'::jsonb end;
end $f$;

-- ---------- views: shared by link, a default per person (B8.2) ----------
create table if not exists b2c.view_defaults (
  user_id uuid not null references b2c.users (user_id),
  role text not null check (role in ('sales', 'workspace')),
  view_id bigint not null references b2c.saved_views (id),
  set_at timestamptz not null default now(),
  primary key (user_id, role)
);
alter table b2c.view_defaults enable row level security;

/* The views a person may open on an interface: their own, the standard ones, and those shared with their role. */
create or replace function b2c.views_list(p_role text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_role text := b2c.my_role();
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'default', (select view_id from b2c.view_defaults where user_id = me and role = p_role),
    'views', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'filters', v.filters, 'columns', v.columns, 'sort', v.sort, 'group_by', v.group_by,
                     'layout', v.layout, 'is_standard', v.is_standard, 'shared_with_role', v.shared_with_role, 'mine', v.owner_id = me,
                     'owner', (select full_name from b2c.users u where u.user_id = v.owner_id)) order by v.is_standard desc, v.position, v.name), '[]')
                from b2c.saved_views v
               where v.hidden_at is null and coalesce(v.role, 'sales') = p_role
                 and (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = v_role))));
end $f$;

/* Opening a view by link: only if it is the person's, standard, or shared with their role. */
create or replace function b2c.view_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v b2c.saved_views;
begin
  select * into v from b2c.saved_views where id = p_id and hidden_at is null;
  if v.id is null or not (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = b2c.my_role())) then
    raise exception 'this view is not shared with you' using errcode = '42501';
  end if;
  return to_jsonb(v) || jsonb_build_object('mine', v.owner_id = me);
end $f$;

create or replace function b2c.view_pin(p_role text, p_view bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid();
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_view is null then delete from b2c.view_defaults where user_id = me and role = p_role; return; end if;
  perform b2c.view_get(p_view);
  insert into b2c.view_defaults (user_id, role, view_id) values (me, p_role, p_view)
  on conflict (user_id, role) do update set view_id = excluded.view_id, set_at = now();
end $f$;

/* view_save (b13): a view can be shared with a role (the owner's own role only) and carries its columns and group-by. */
create or replace function b2c.view_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; v_std boolean := coalesce((p ->> 'is_standard')::boolean, false);
        v_name text := nullif(trim(p ->> 'name'), ''); v_cols jsonb := p -> 'columns';
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_std and b2c.my_role() <> 'admin' then raise exception 'only the Admin publishes standard views'; end if;
  if v is null and (v_name is null or length(v_name) > 60) then raise exception 'name the view (at most 60 characters)'; end if;
  if coalesce(p ->> 'role', 'sales') not in ('sales', 'workspace') then raise exception 'unknown interface'; end if;
  if nullif(p ->> 'shared_with_role', '') is not null and p ->> 'shared_with_role' <> b2c.my_role() then raise exception 'a view can be shared with your own role only'; end if;
  if v_cols is not null and (jsonb_typeof(v_cols) <> 'array' or exists (select 1 from jsonb_array_elements_text(v_cols) x where not x = any (b2c.lead_fields()))) then
    raise exception 'unknown column';
  end if;
  if p ? 'filters' or p ? 'sort' or p ? 'group_by' then
    perform b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'sort', p -> 'sort', 'limit', 1, 'group_by', p ->> 'group_by'));
  end if;
  if v is null then
    insert into b2c.saved_views (owner_id, role, name, filters, columns, sort, group_by, layout, is_standard, is_default, shared_with_role, position)
    values (case when v_std then null else me end, coalesce(p ->> 'role', 'sales'), v_name, coalesce(p -> 'filters', '{}'), coalesce(v_cols, '[]'),
            coalesce(p -> 'sort', '{"field":"next_task_due_at","dir":"asc"}'), nullif(p ->> 'group_by', ''), coalesce(p ->> 'layout', 'list'), v_std,
            coalesce((p ->> 'is_default')::boolean, false), nullif(p ->> 'shared_with_role', ''), case when v_std then 50 else 100 end)
    returning id into v;
  else
    update b2c.saved_views set name = coalesce(v_name, name), filters = coalesce(p -> 'filters', filters), columns = coalesce(v_cols, columns),
           sort = coalesce(p -> 'sort', sort), group_by = case when p ? 'group_by' then nullif(p ->> 'group_by', '') else group_by end, layout = coalesce(p ->> 'layout', layout),
           is_default = coalesce((p ->> 'is_default')::boolean, is_default),
           shared_with_role = case when p ? 'shared_with_role' then nullif(p ->> 'shared_with_role', '') else shared_with_role end,
           hidden_at = case when p ? 'hidden' then case when (p ->> 'hidden')::boolean then now() end else hidden_at end, updated_at = now()
     where id = v and (owner_id = me or (is_standard and b2c.my_role() = 'admin'));
    if not found then raise exception 'only your own views can be changed'; end if;
  end if;
  return v;
end $f$;

-- ---------- bulk actions (B10.3) ----------
/* Add to a journey or take out of one (Marketing too). Each lead is checked as if done alone. */
create or replace function b2c.bulk_journey(p_leads bigint[], p_action text, p_journey bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare l bigint; n int := 0; refused jsonb := '[]'::jsonb; me uuid := b2c.require('journey_membership');
begin
  if p_action not in ('add', 'remove') then raise exception 'add or remove'; end if;
  if coalesce(cardinality(p_leads), 0) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 5000 then raise exception 'at most 5,000 leads at a time'; end if;
  if p_action = 'add' and not exists (select 1 from b2c.journeys where id = p_journey and current_version > 0 and status <> 'archived') then raise exception 'choose a published journey'; end if;
  foreach l in array p_leads loop
    begin
      if p_action = 'add' then
        if exists (select 1 from b2c.leads_state s where s.lead_id = l and s.status = 'active' and s.owner_id is not null)
           and not (select allow_active_sales from b2c.journeys where id = p_journey) then
          raise exception 'in active sales';
        end if;
        perform b2c.journey_lead(l, 'start', p_journey);
      else
        if b2c.journey_exit(l, 'removed by ' || coalesce(b2c.my_role(), 'staff')) = 0 then raise exception 'not in a journey'; end if;
      end if;
      n := n + 1;
    exception when others then
      refused := refused || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_journey', jsonb_build_object('action', p_action, 'journey', p_journey, 'done', n, 'refused', jsonb_array_length(refused)));
  return jsonb_build_object('done', n, 'refused', refused);
end $f$;

/* Change stage for many (Admin), under the stage rules; the sub-stage and comment apply to all. */
create or replace function b2c.bulk_stage(p_leads bigint[], p_stage smallint, p_sub text, p_comment text default null, p_next_due timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare l bigint; n int := 0; refused jsonb := '[]'::jsonb; me uuid := b2c.require('settings');
begin
  if coalesce(cardinality(p_leads), 0) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 1000 then raise exception 'at most 1,000 leads at a time'; end if;
  foreach l in array p_leads loop
    begin
      perform b2c.set_stage(l, p_stage, p_sub, p_comment, coalesce(p_next_due, case when p_stage not in (9, 10) then now() + interval '1 day' end));
      n := n + 1;
    exception when others then
      refused := refused || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_stage', jsonb_build_object('stage', p_stage, 'sub_stage', p_sub, 'done', n, 'refused', jsonb_array_length(refused)));
  return jsonb_build_object('done', n, 'refused', refused);
end $f$;

/* Bulk delete as a background job (B10.4): typed confirmation, then the minute timer works through it; undo for 30 days. */
create table if not exists b2c.bulk_jobs (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('delete')),
  lead_ids bigint[] not null,
  params jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'running', 'done', 'undone', 'failed')),
  done_count int not null default 0,
  result jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  undone_at timestamptz
);
alter table b2c.bulk_jobs enable row level security;

create or replace function b2c.lead_delete_request(p_leads bigint[], p_reason text, p_confirm text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint; n int := coalesce(cardinality(p_leads), 0);
begin
  if n = 0 then raise exception 'tick at least one lead'; end if;
  if n > 20000 then raise exception 'at most 20,000 leads at a time'; end if;
  if p_reason not in ('junk', 'test', 'duplicate entry', 'spam', 'student request') then raise exception 'choose a reason: junk, test, duplicate entry, spam or student request'; end if;
  if coalesce(trim(p_confirm), '') <> 'DELETE ' || n then raise exception 'type DELETE % to confirm', n; end if;
  insert into b2c.bulk_jobs (kind, lead_ids, params, created_by) values ('delete', p_leads, jsonb_build_object('reason', p_reason), me) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_delete_requested', jsonb_build_object('job', v, 'leads', n, 'reason', p_reason));
  return jsonb_build_object('job_id', v, 'leads', n);
end $f$;

create or replace function b2c.bulk_jobs_tick(p_batch int default 500) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare j b2c.bulk_jobs; v_part bigint[]; r jsonb; n int := 0;
begin
  for j in select * from b2c.bulk_jobs where status in ('queued', 'running') order by id limit 5 for update skip locked loop
    v_part := j.lead_ids[j.done_count + 1 : j.done_count + p_batch];
    if coalesce(cardinality(v_part), 0) = 0 then
      update b2c.bulk_jobs set status = 'done', done_at = now() where id = j.id;
      perform b2c.notify(j.created_by, 'bulk_job', 'Bulk delete finished', (j.result ->> 'deleted') || ' deleted, ' || coalesce(j.result ->> 'kept', '0') || ' kept',
                         '/w/leads?deleted=1', null, 'bulkjob:' || j.id);
      continue;
    end if;
    r := b2c.lead_delete_job_part(v_part, j.params ->> 'reason', j.created_by, j.id);
    update b2c.bulk_jobs set status = 'running', done_count = done_count + cardinality(v_part),
           result = jsonb_build_object('deleted', coalesce((result ->> 'deleted')::int, 0) + (r ->> 'deleted')::int,
                                       'kept', coalesce((result ->> 'kept')::int, 0) + jsonb_array_length(r -> 'kept'),
                                       'kept_leads', coalesce(result -> 'kept_leads', '[]'::jsonb) || (r -> 'kept'))
     where id = j.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('jobs', n);
end $f$;

/* One part of a delete job (the same rules as lead_delete: leads with an enrolment are kept). */
create or replace function b2c.lead_delete_job_part(p_leads bigint[], p_reason text, p_actor uuid, p_job bigint) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v bigint; n int := 0; v_kept jsonb := '[]'::jsonb;
begin
  foreach v in array p_leads loop
    if exists (select 1 from b2c.enrollments e where e.lead_id = v and e.status in ('reported', 'verified')) then
      v_kept := v_kept || jsonb_build_object('lead_id', v, 'why', 'has an enrolment: close it instead'); continue;
    end if;
    update b2c.leads_state set deleted_at = now(), delete_reason = p_reason, journey = null, updated_at = now() where lead_id = v and deleted_at is null;
    if found then
      perform b2c.journey_exit(v, 'deleted');
      update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'deleted' where lead_id = v and status = 'open';
      update b2c.send_queue set status = 'cancelled' where lead_id = v and status = 'queued';
      insert into b2c.audit_log (actor_id, action, lead_id, detail) values (p_actor, 'delete', v, jsonb_build_object('reason', p_reason, 'job', p_job));
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('deleted', n, 'kept', v_kept);
end $f$;

create or replace function b2c.bulk_job_undo(p_job bigint) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); j b2c.bulk_jobs; n int;
begin
  select * into j from b2c.bulk_jobs where id = p_job for update;
  if j.id is null or j.kind <> 'delete' or j.status not in ('done', 'running') then raise exception 'this job cannot be undone'; end if;
  if j.created_at < now() - interval '30 days' then raise exception 'undo is possible for 30 days'; end if;
  update b2c.leads_state set deleted_at = null, delete_reason = null, updated_at = now()
   where lead_id = any (j.lead_ids) and deleted_at is not null and erased_at is null;
  get diagnostics n = row_count;
  update b2c.bulk_jobs set status = 'undone', undone_at = now() where id = p_job;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'restore', jsonb_build_object('job', p_job, 'restored', n));
  return n;
end $f$;

create or replace function b2c.bulk_jobs_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'leads', cardinality(j.lead_ids), 'reason', j.params ->> 'reason', 'status', j.status,
            'done_count', j.done_count, 'result', j.result - 'kept_leads', 'by', u.full_name, 'created_at', j.created_at, 'done_at', j.done_at,
            'undo_until', case when j.status in ('done', 'running') then j.created_at + interval '30 days' end) order by j.id desc), '[]')
            from (select * from b2c.bulk_jobs order by id desc limit 50) j left join b2c.users u on u.user_id = j.created_by);
end $f$;

-- ---------- student erasure (B10.4, B18) ----------
create table if not exists b2c.erase_files (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  bucket text not null,
  path text not null,
  created_at timestamptz not null default now(),
  attempts int not null default 0,
  removed_at timestamptz,
  error text
);
alter table b2c.erase_files enable row level security;

/* The Admin erases a student on request: personal fields anonymised, message bodies and documents removed, money rows
   kept by id, the B2B CRM told (b2ccrm.erasure_requested), logged with the request reference. Cannot be undone. */
create or replace function b2c.lead_erase(p_lead bigint, p_reference text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); s b2c.leads_state; n_msg int; n_doc int;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(coalesce(trim(p_reference), '')) < 3 then raise exception 'give the request reference (the email or ticket the student used)'; end if;
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null then raise exception 'unknown lead'; end if;
  if s.erased_at is not null then raise exception 'this lead was already erased'; end if;
  -- the record: identity and contact gone; programme interest and source kept for the numbers
  update b2c.lead_records set record = jsonb_strip_nulls(jsonb_build_object(
           'id', record -> 'id', 'is_test', record -> 'is_test', 'held_by_b2c', record -> 'held_by_b2c', 'contract_version', record -> 'contract_version',
           'student', jsonb_build_object('name', 'Erased student', 'erased', true),
           'interest', (record -> 'interest') - 'notes', 'source', record -> 'source', 'created_at', record -> 'created_at',
           'consent', jsonb_build_object('state', record -> 'consent' ->> 'state', 'opted_out', true))), received_at = now()
   where lead_id = p_lead;
  perform set_config('b2c.trusted', 'on', true);
  update b2c.lead_contacts set value = 'erased', value_norm = 'erased:' || id, removed_at = coalesce(removed_at, now()) where lead_id = p_lead;
  perform set_config('b2c.trusted', 'off', true);
  update b2c.wa_messages set body = null, media = null where lead_id = p_lead;
  get diagnostics n_msg = row_count;
  update b2c.emails set subject = '[erased]', snippet = null, from_address = case when direction = 'in' then 'erased' else from_address end,
         to_address = case when direction = 'out' then 'erased' else to_address end where lead_id = p_lead;
  update b2c.activities set body = '[erased]' where lead_id = p_lead and kind in ('whatsapp', 'email', 'note', 'call', 'reenquiry', 'partner_history', 'correction');
  update b2c.calls set note = null, number = 'erased', from_number = null where lead_id = p_lead;
  update b2c.replies set text = null where lead_id = p_lead;
  update b2c.field_history set old_value = null, new_value = null where lead_id = p_lead;
  update b2c.wa_conversations set phone = 'erased:' || p_lead where lead_id = p_lead;
  delete from b2c.lead_briefs where lead_id = p_lead;
  update b2c.fact_leads set city = null, state = null, deleted = true where lead_id = p_lead;
  -- files go through the storage API (the app's erase job), never by deleting rows
  insert into b2c.erase_files (lead_id, bucket, path)
  select p_lead, 'b2c-documents', d.storage_path from b2c.documents d where d.lead_id = p_lead and d.removed_at is null
  union all select p_lead, 'b2c-recordings', c.recording_path from b2c.calls c where c.lead_id = p_lead and c.recording_path is not null;
  get diagnostics n_doc = row_count;
  update b2c.documents set removed_at = now(), file_name = null where lead_id = p_lead;
  update b2c.calls set recording_path = null, recording_url = null, recording_status = case when recording_status = 'stored' then 'deleted' else recording_status end where lead_id = p_lead;
  update b2c.send_queue set status = 'cancelled' where lead_id = p_lead and status = 'queued';
  perform b2c.journey_exit(p_lead, 'erased');
  update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'erased' where lead_id = p_lead and status = 'open';
  update b2c.leads_state set erased_at = now(), erase_reference = left(trim(p_reference), 200), deleted_at = coalesce(deleted_at, now()),
         delete_reason = 'student request', tags = '{}', stage_comment = null, missing = '[]', partner_lost = null, partners_tried = '[]', updated_at = now()
   where lead_id = p_lead;
  perform b2c.queue_event('b2ccrm.erasure_requested', p_lead, jsonb_build_object('reference', left(trim(p_reference), 200), 'note', left(p_note, 300)), true);
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'erase', p_lead, jsonb_build_object('reference', p_reference, 'note', p_note, 'messages', n_msg, 'files', n_doc));
  insert into b2c.activities (lead_id, kind, body, actor_id) values (p_lead, 'system', 'Erased on the student''s request (' || left(trim(p_reference), 100) || ')', me);
  return jsonb_build_object('erased', true, 'messages', n_msg, 'files', n_doc);
end $f$;

create or replace function b2c.erase_files_take(p_limit int default 20) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select id from b2c.erase_files where removed_at is null and attempts < 6 order by id limit p_limit for update skip locked),
       m as (update b2c.erase_files f set attempts = f.attempts + 1 from t where f.id = t.id returning f.id, f.bucket, f.path)
  select coalesce(jsonb_agg(to_jsonb(m)), '[]') into v from m;
  return v;
end $f$;

create or replace function b2c.erase_file_done(p_id bigint, p_error text default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.erase_files set removed_at = case when p_error is null then now() end, error = left(p_error, 300) where id = p_id
$f$;

/* The record cache (b3): an erased lead's record is never filled again from the B2B CRM. */
create or replace function b2c.apply_record(p_lead bigint, p_version int, p_seq bigint, p_record jsonb, p_origin text default null)
returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_cur int; v_phone text; v_email text; v_test boolean;
begin
  if p_record is null or p_lead is null then return false; end if;
  if exists (select 1 from b2c.leads_state z where z.lead_id = p_lead and z.erased_at is not null) then
    update b2c.lead_records set version = greatest(version, coalesce(p_version, 0)), seq = p_seq where lead_id = p_lead;
    return false;
  end if;
  select version into v_cur from b2c.lead_records where lead_id = p_lead for update;
  if v_cur is not null and v_cur >= coalesce(p_version, 0) then return false; end if;
  v_phone := p_record -> 'student' ->> 'phone';
  v_email := lower(nullif(trim(p_record -> 'student' ->> 'email'), ''));
  v_test := coalesce((p_record ->> 'is_test')::boolean, false) or b2c.is_test_phone(v_phone);
  insert into b2c.lead_records (lead_id, version, seq, record, held_by_b2c, is_test, deleted, merged_into_id, origin, received_at)
  values (p_lead, coalesce(p_version, 0), p_seq, p_record, coalesce((p_record ->> 'held_by_b2c')::boolean, false), v_test,
          coalesce((p_record ->> 'deleted')::boolean, false), nullif(p_record ->> 'merged_into_id', '')::bigint, p_origin, now())
  on conflict (lead_id) do update set version = excluded.version, seq = excluded.seq, record = excluded.record,
         held_by_b2c = excluded.held_by_b2c, is_test = excluded.is_test, deleted = excluded.deleted,
         merged_into_id = excluded.merged_into_id, origin = excluded.origin, received_at = now();
  perform set_config('b2c.trusted', 'on', true);
  if v_phone is not null and b2c.norm_phone(v_phone) is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_call, primary_wa)
    select p_lead, 'phone', v_phone, b2c.norm_phone(v_phone), 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_call and c.removed_at is null),
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_wa and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  if v_email is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_email)
    select p_lead, 'email', v_email, v_email, 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_email and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  perform set_config('b2c.trusted', 'off', true);
  update b2c.leads_state set is_test = v_test, updated_at = now() where lead_id = p_lead and is_test is distinct from v_test;
  return true;
end $f$;

/* Restoring never brings an erased lead back. */
create or replace function b2c.lead_restore(p_leads bigint[]) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); n int;
begin
  update b2c.leads_state set deleted_at = null, delete_reason = null, updated_at = now()
   where lead_id = any (p_leads) and deleted_at > now() - interval '30 days' and erased_at is null;
  get diagnostics n = row_count;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'restore', jsonb_build_object('leads', p_leads));
  return n;
end $f$;

-- ---------- exports (B10.5) ----------
create table if not exists b2c.exports (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  params jsonb not null,                     -- {filters, sort, search, columns, ids, include_test}
  format text not null default 'csv' check (format in ('csv', 'xlsx')),
  status text not null default 'queued' check (status in ('queued', 'running', 'ready', 'failed', 'expired')),
  rows int,
  path text,
  error text,
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  expires_at timestamptz
);
alter table b2c.exports enable row level security;

/* The Admin asks for an export: how many rows it holds, and a background job when it is over 10,000 rows. */
create or replace function b2c.export_request(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v_n int; v bigint; v_fmt text := coalesce(p ->> 'format', 'csv');
begin
  if v_fmt not in ('csv', 'xlsx') then raise exception 'CSV or Excel'; end if;
  v_n := (b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'search', p ->> 'search', 'ids', p -> 'ids',
                                           'include_test', p -> 'include_test', 'limit', 1)) ->> 'total')::int;
  if v_n <= 10000 then return jsonb_build_object('inline', true, 'rows', v_n); end if;
  insert into b2c.exports (user_id, params, format) values (me, p - 'format', v_fmt) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'export', jsonb_build_object('job', v, 'rows', v_n, 'format', v_fmt, 'filters', p -> 'filters', 'columns', p -> 'columns'));
  return jsonb_build_object('inline', false, 'job_id', v, 'rows', v_n);
end $f$;

create or replace function b2c.export_take(p_limit int default 2) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  update b2c.exports set status = 'expired', path = null where status = 'ready' and expires_at < now();
  with t as (select id from b2c.exports where status = 'queued' and attempts < 3 order by id limit p_limit for update skip locked),
       m as (update b2c.exports e set status = 'running', attempts = e.attempts + 1 from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id, 'params', m.params, 'format', m.format)), '[]') into v from m;
  return v;
end $f$;

/* The export job runs the view as the person who asked for it (so the same scope and columns apply). */
create or replace function b2c.export_page(p_export bigint, p_offset int, p_limit int default 1000) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports; v_role text;
begin
  select * into x from b2c.exports where id = p_export and status = 'running';
  if x.id is null then raise exception 'unknown export'; end if;
  select role into v_role from b2c.users where user_id = x.user_id and is_active;
  if v_role is distinct from 'admin' then raise exception 'the person who asked can no longer export'; end if;
  return b2c.lead_list_as(x.params || jsonb_build_object('limit', least(p_limit, 500), 'offset', p_offset), x.user_id, v_role);
end $f$;

create or replace function b2c.export_done(p_export bigint, p_rows int, p_path text, p_error text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports;
begin
  update b2c.exports set status = case when p_error is null then 'ready' when attempts >= 3 then 'failed' else 'queued' end, rows = p_rows, path = p_path,
         error = left(p_error, 300), done_at = now(), expires_at = case when p_error is null then now() + interval '7 days' end
   where id = p_export returning * into x;
  if p_error is null then
    perform b2c.notify(x.user_id, 'export', 'Your export is ready', p_rows || ' rows. The link works for 7 days.', '/w/leads?exports=1', null, 'export:' || p_export);
  end if;
end $f$;

create or replace function b2c.exports_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'format', format, 'status', status, 'rows', rows, 'created_at', created_at, 'expires_at', expires_at, 'error', error) order by id desc), '[]')
    from (select * from b2c.exports where user_id = b2c.uid() order by id desc limit 20) x
$f$;

/* The path of a ready export, for a signed link (the app), logged. */
create or replace function b2c.export_open(p_export bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports;
begin
  perform b2c.require('settings');
  select * into x from b2c.exports where id = p_export and user_id = b2c.uid();
  if x.id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if x.status <> 'ready' or x.expires_at < now() then raise exception 'this export is no longer available'; end if;
  insert into b2c.audit_log (actor_id, action, detail) values (b2c.uid(), 'export_download', jsonb_build_object('export', p_export, 'rows', x.rows));
  return x.path;
end $f$;

-- ---------- what Spark sent the B2B CRM, for its reconciliation (B17: GET /v1/events?since=) ----------
create or replace function b2c.events_feed(p_after bigint default 0, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb; v_last bigint;
begin
  select coalesce(jsonb_agg(jsonb_build_object('seq', o.id, 'event_id', o.body ->> 'event_id', 'type', o.body ->> 'type', 'lead_id', o.lead_id,
           'occurred_at', o.occurred_at, 'data', o.body -> 'data', 'delivery', o.status) order by o.id), '[]'), max(o.id)
    into v, v_last
    from (select * from b2c.outbox where kind = 'event' and id > coalesce(p_after, 0) order by id limit least(greatest(coalesce(p_limit, 200), 1), 1000)) o;
  return jsonb_build_object('events', v, 'next_after', coalesce(v_last, p_after));
end $f$;

-- ---------- the published lead status (B14, B17), for the B2B CRM ----------
create or replace view public.b2c_lead_status_v as
select 1 as view_version,
       s.lead_id, s.lane, s.status, st.name as stage, s.sub_stage, st.canon as canonical_stage, s.stage_changed_at,
       u.full_name as counsellor, u.email as counsellor_email, s.assigned_at, s.pool_reason, s.journey, s.reengaged_at, s.reengage_trigger,
       s.closed_at, s.closed_reason, s.routing_requested_at, s.is_test, s.updated_at
  from b2c.leads_state s
  left join b2c.stages st on st.id = s.stage_id
  left join b2c.users u on u.user_id = s.owner_id
 where s.deleted_at is null;
revoke all on public.b2c_lead_status_v from public, anon, authenticated;
grant select on public.b2c_lead_status_v to service_role;

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-jobs') then
    perform cron.schedule('b2c-jobs', '* * * * *', 'select b2c.bulk_jobs_tick()');
  end if;
end $d$;

-- ---------- grants ----------
grant execute on function b2c.views_list(text), b2c.view_get(bigint), b2c.view_pin(text, bigint), b2c.bulk_journey(bigint[], text, bigint),
  b2c.bulk_stage(bigint[], smallint, text, text, timestamptz), b2c.lead_delete_request(bigint[], text, text), b2c.bulk_job_undo(bigint), b2c.bulk_jobs_list(),
  b2c.lead_erase(bigint, text, text), b2c.export_request(jsonb), b2c.exports_mine(), b2c.export_open(bigint) to authenticated;
grant execute on function b2c.erase_files_take(integer), b2c.erase_file_done(bigint, text), b2c.export_take(integer), b2c.export_page(bigint, integer, integer),
  b2c.export_done(bigint, integer, text, text), b2c.events_feed(bigint, integer), b2c.bulk_jobs_tick(integer) to service_role;
revoke execute on function b2c.erase_files_take(integer), b2c.erase_file_done(bigint, text), b2c.export_take(integer), b2c.export_page(bigint, integer, integer),
  b2c.export_done(bigint, integer, text, text), b2c.events_feed(bigint, integer), b2c.bulk_jobs_tick(integer), b2c.lead_delete_job_part(bigint[], text, uuid, bigint),
  b2c.lead_fields(), b2c.money_fields(), b2c.lead_scope_sql(uuid, text), b2c.lead_list_as(jsonb, uuid, text), b2c.lead_matches(bigint, jsonb), b2c.filter_leads(jsonb, boolean) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;

-- ===== b41_workspace.sql =====
-- B2C CRM b41: completing the counsellor workspace (docs/completion-gaps.md, section C). Staging first. Idempotent.
--   WhatsApp media      images, documents and brochures out inside the window; inbound media stored privately, opened by
--                       signed link, attached to the application checklist in one tap (B8.5, B8.8)
--   programme_cache     the catalogue in one row per programme with duration, EMI, scholarship, intakes, partners and
--                       popularity; search with every filter and sort; compare 2-4; fit by eligibility and budget (B8.3, B8.9)
--   pipeline_board()    columns with expected commission, SLA colour, priority order, filters, counsellor filter (B8.2)
--   inbox_list()        searches message text and template names; counsellor, window and awaiting-reply filters;
--                       Marketing reads every conversation (B8.5, B15)
--   email library       author, uses and reply rate; every merge field from the lead (B8.6)
--   staff WhatsApp      reminders and alerts to a person's own number, by their choice (B8.2, B8.7, B17)
--   custom fields       Admin-defined profile fields with field history (B8.3)
--   checklists          per-university document checklists edited in Settings, with history; documents open by signed link (B8.8)
--   SLA by source       first-contact minutes by source as well as temperature; neglect alerts after 48 h untouched (B8.7)
-- The catalogue stays read-only: duration, EMI, scholarship and intakes come from catalog_programs.fee_other when the
-- B2B CRM's Programme Repository carries them (keys duration_months, emi_monthly, scholarship, intakes, deadline).

-- ---------- WhatsApp media (C1) ----------
alter table b2c.wa_messages add column if not exists media_path text;
alter table b2c.wa_messages add column if not exists media_error text;
alter table b2c.wa_messages add column if not exists media_tries int not null default 0;
create index if not exists wa_messages_media_todo on b2c.wa_messages (id) where direction = 'in' and media is not null and media_path is null;

/* A file or brochure to the student while the 24-hour window is open. p_path is a stored file under the lead's folder;
   p_link a public https link (a brochure from the Programme page). */
create or replace function b2c.wa_queue_media(p_lead bigint, p_kind text, p_path text, p_caption text default null, p_filename text default null, p_link text default null)
returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_phone text := b2c.wa_phone(p_lead); v bigint; v_label text;
begin
  if p_kind not in ('image', 'document') then raise exception 'an image or a document'; end if;
  if (p_path is null) = (p_link is null) then raise exception 'choose a file or a link'; end if;
  if p_path is not null and p_path !~ ('^leads/' || p_lead || '/') then raise exception 'files are sent from the lead''s folder'; end if;
  if p_link is not null and p_link !~ '^https://' then raise exception 'links must start with https://'; end if;
  if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
  if not b2c.window_open(v_phone) then raise exception 'the 24-hour window is closed: start with an approved template'; end if;
  v_label := coalesce(nullif(trim(p_filename), ''), case when p_kind = 'image' then 'image' else 'document' end);
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, media, media_path, status, category, purpose, user_id)
  values (v_phone, p_lead, 'out', 'media', left(nullif(trim(p_caption), ''), 1024),
          jsonb_strip_nulls(jsonb_build_object('kind', p_kind, 'filename', left(v_label, 120), 'link', p_link)), p_path, 'queued', 'service', 'sales', me)
  returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose)
  values ('whatsapp', p_lead, v_phone, v, jsonb_strip_nulls(jsonb_build_object('type', 'media', 'media_kind', p_kind, 'path', p_path, 'link', p_link,
          'caption', left(nullif(trim(p_caption), ''), 1024), 'filename', left(v_label, 120))), 'sales');
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'whatsapp', 'out', '[' || p_kind || '] ' || v_label || coalesce(': ' || left(nullif(trim(p_caption), ''), 300), ''), jsonb_build_object('message_id', v), me);
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  perform b2c.queue_activity(p_lead, 'whatsapp', now(), 'media', null, v_label);
  return v;
end $f$;

/* Inbound media waiting to be fetched from WhatsApp and stored privately (the app's job). */
create or replace function b2c.wa_media_take(p_limit int default 10) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select id from b2c.wa_messages where direction = 'in' and media is not null and media ? 'id' and media_path is null and lead_id is not null and media_tries < 5
              order by id limit p_limit for update skip locked),
       m as (update b2c.wa_messages w set media_tries = w.media_tries + 1 from t where w.id = t.id returning w.id, w.lead_id, w.media)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'lead_id', m.lead_id, 'media', m.media)), '[]') into v from m;
  return v;
end $f$;

create or replace function b2c.wa_media_stored(p_message bigint, p_path text, p_error text default null) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.wa_messages set media_path = case when p_error is null then p_path end, media_error = left(p_error, 300)
   where id = p_message and direction = 'in' and (p_path is null or p_path ~ ('^leads/' || lead_id || '/'));
end $f$;

/* The stored file of a message, for a signed link: anyone who may see the lead. */
create or replace function b2c.wa_media_open(p_message bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare m b2c.wa_messages;
begin
  select * into m from b2c.wa_messages where id = p_message;
  if m.id is null or m.lead_id is null or not coalesce(b2c.can_see(m.lead_id), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if m.media_path is null then raise exception 'this file is still being fetched'; end if;
  return jsonb_build_object('bucket', 'b2c-documents', 'path', m.media_path, 'filename', coalesce(m.media ->> 'filename', 'file'), 'mime', m.media ->> 'mime_type');
end $f$;

/* One tap: a document the student sent on WhatsApp goes onto the application checklist. */
create or replace function b2c.wa_media_attach(p_message bigint, p_application bigint, p_kind text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare m b2c.wa_messages;
begin
  select * into m from b2c.wa_messages where id = p_message and direction = 'in';
  if m.id is null or m.lead_id is null then raise exception 'unknown message'; end if;
  perform b2c.require_lead(m.lead_id);
  if m.media_path is null then raise exception 'this file is still being fetched'; end if;
  if coalesce(trim(p_kind), '') = '' then raise exception 'choose the checklist item'; end if;
  if p_application is not null and not exists (select 1 from b2c.applications a where a.id = p_application and a.lead_id = m.lead_id) then raise exception 'unknown application'; end if;
  return b2c.document_add(m.lead_id, p_application, trim(p_kind), m.media_path, coalesce(m.media ->> 'filename', p_kind), 'whatsapp');
end $f$;

-- ---------- the programme catalogue, cached (C2, C6) ----------
create table if not exists b2c.programme_cache (
  id bigint primary key,                    -- catalog_programs.id
  university_id bigint,
  university text,
  university_short text,
  name text,
  course text,
  specialization text,
  level text,
  mode text,
  duration_months int,
  fee_yearly numeric,
  fee_semester numeric,
  fee_total numeric,
  fee_exam numeric,
  fee_registration numeric,
  emi_monthly numeric,
  scholarship text,
  intakes text[] not null default '{}',
  deadline text,
  accreditation text,
  recognitions jsonb,
  min_qualification text,
  min_rank int,
  min_pct numeric,
  eligibility text,
  brochure_url text,
  partners jsonb not null default '[]'::jsonb,   -- [{partner_id, name, commission}] Admin and Marketing only
  enrollments int not null default 0,
  search_doc tsvector,
  active boolean not null default true,
  catalog_updated_at timestamptz,
  cached_at timestamptz not null default now()
);
create index if not exists programme_cache_search on b2c.programme_cache using gin (search_doc);
alter table b2c.programme_cache enable row level security;

create or replace function b2c.num_or_null(p text) returns numeric language sql immutable set search_path = '' as $f$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9.]', '', 'g'), '')::numeric
$f$;

/* Rebuilt when the catalogue changes (checked every 15 minutes) or on demand. */
create or replace function b2c.programme_cache_refresh(p_force boolean default false) returns int language plpgsql security definer set search_path = '' as $f$
declare v_cat timestamptz; v_cached timestamptz; n int; v_b2b boolean := to_regclass('b2b.partner_programmes') is not null and to_regclass('b2b.partners') is not null;
begin
  select max(greatest(p.updated_at, u.updated_at)) into v_cat from public.catalog_programs p join public.catalog_universities u on u.id = p.university_id;
  select max(catalog_updated_at) into v_cached from b2c.programme_cache where active;
  if not p_force and v_cached is not null and v_cat <= v_cached
     and (select count(*) from b2c.programme_cache where active) = (select count(*) from public.catalog_programs where active) then
    return 0;
  end if;
  insert into b2c.programme_cache (id, university_id, university, university_short, name, course, specialization, level, mode, duration_months,
         fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, emi_monthly, scholarship, intakes, deadline, accreditation, recognitions,
         min_qualification, min_rank, min_pct, eligibility, brochure_url, enrollments, search_doc, active, catalog_updated_at, cached_at)
  select p.id, u.id, u.name, u.short_name, coalesce(p.program_name, p.course), p.course, p.specialization, p.level, p.mode,
         coalesce(b2c.num_or_null(p.fee_other ->> 'duration_months')::int, (b2c.num_or_null(p.fee_other ->> 'duration_years') * 12)::int,
                  case when p.fee_total > 0 and p.fee_yearly > 0 then round(p.fee_total / p.fee_yearly * 12)::int end),
         p.fee_yearly, p.fee_semester, p.fee_total, p.fee_exam, p.fee_registration,
         coalesce(b2c.num_or_null(p.fee_other ->> 'emi_monthly'), b2c.num_or_null(p.fee_other ->> 'emi')),
         nullif(p.fee_other ->> 'scholarship', ''),
         coalesce(case jsonb_typeof(p.fee_other -> 'intakes') when 'array' then array(select trim(x) from jsonb_array_elements_text(p.fee_other -> 'intakes') x)
                       when 'string' then array(select trim(x) from regexp_split_to_table(p.fee_other ->> 'intakes', '[,;/]') x where trim(x) <> '') end, '{}'),
         nullif(p.fee_other ->> 'deadline', ''), u.accreditation_text, to_jsonb(u.recognitions),
         p.min_qualification, b2c.qual_rank(p.min_qualification), p.min_pct_general, p.eligibility_text, p.brochure_url,
         (select count(*) from b2c.enrollments e where e.programme_id = p.id and e.status in ('reported', 'verified')),
         coalesce(p.search_doc, to_tsvector('simple', concat_ws(' ', p.program_name, p.course, p.specialization, u.name, u.short_name))),
         p.active, greatest(p.updated_at, u.updated_at), now()
    from public.catalog_programs p join public.catalog_universities u on u.id = p.university_id
  on conflict (id) do update set university_id = excluded.university_id, university = excluded.university, university_short = excluded.university_short,
         name = excluded.name, course = excluded.course, specialization = excluded.specialization, level = excluded.level, mode = excluded.mode,
         duration_months = excluded.duration_months, fee_yearly = excluded.fee_yearly, fee_semester = excluded.fee_semester, fee_total = excluded.fee_total,
         fee_exam = excluded.fee_exam, fee_registration = excluded.fee_registration, emi_monthly = excluded.emi_monthly, scholarship = excluded.scholarship,
         intakes = excluded.intakes, deadline = excluded.deadline, accreditation = excluded.accreditation, recognitions = excluded.recognitions,
         min_qualification = excluded.min_qualification, min_rank = excluded.min_rank, min_pct = excluded.min_pct, eligibility = excluded.eligibility,
         brochure_url = excluded.brochure_url, enrollments = excluded.enrollments, search_doc = excluded.search_doc, active = excluded.active,
         catalog_updated_at = excluded.catalog_updated_at, cached_at = now();
  get diagnostics n = row_count;
  update b2c.programme_cache c set active = false, cached_at = now() where c.active and not exists (select 1 from public.catalog_programs p where p.id = c.id);
  if v_b2b then
    execute $q$
      update b2c.programme_cache c set partners = coalesce((
        select jsonb_agg(jsonb_build_object('partner_id', pa.id, 'name', coalesce(pa.display_name, pa.name), 'commission', pp.commission) order by coalesce(pa.display_name, pa.name))
          from b2b.partner_programmes pp join b2b.partners pa on pa.id = pp.partner_id
         where pp.programme_id = c.id and pp.active and (pp.valid_to is null or pp.valid_to > now())
           and coalesce(pa.status, 'active') = 'active'), '[]'::jsonb)
    $q$;
  end if;
  return n;
end $f$;

/* Eduwit's commission on a programme (the counsellor commission owed to Eduwit): the university rate on the fee. */
create or replace function b2c.programme_commission(p_university bigint, p_programme bigint, p_fee_year numeric, p_fee_total numeric) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare r b2c.university_rates; v_base numeric;
begin
  r := b2c.university_rate_for(p_university, p_programme, current_date);
  if r.id is null then return null; end if;
  v_base := case r.fee_base when 'total' then coalesce(p_fee_total, p_fee_year) else coalesce(p_fee_year, p_fee_total) end;
  return jsonb_build_object('rate_type', r.rate_type, 'value', r.value, 'fee_base', r.fee_base,
    'amount', case r.rate_type when 'percent' then round(v_base * r.value / 100) when 'fixed' then r.value end);
end $f$;

/* One programme as the screens show it; partner and commission figures only for the Admin and Marketing. */
create or replace function b2c.programme_json(c b2c.programme_cache, p_money boolean, p_rank int default null, p_budget numeric default null) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('id', c.id, 'name', c.name, 'course', c.course, 'specialization', c.specialization, 'level', c.level, 'mode', c.mode,
           'university', c.university, 'university_id', c.university_id, 'university_short', c.university_short, 'duration_months', c.duration_months,
           'fee_yearly', c.fee_yearly, 'fee_semester', c.fee_semester, 'fee_total', c.fee_total, 'fee_exam', c.fee_exam, 'fee_registration', c.fee_registration,
           'emi_monthly', c.emi_monthly, 'scholarship', c.scholarship, 'intakes', to_jsonb(c.intakes), 'deadline', c.deadline,
           'accreditation', c.accreditation, 'recognitions', c.recognitions, 'min_qualification', c.min_qualification, 'min_pct', c.min_pct,
           'eligibility', c.eligibility, 'brochure_url', c.brochure_url, 'enrollments', c.enrollments,
           'eligible', case when p_rank is null or c.min_rank is null then null else p_rank >= c.min_rank end,
           'within_budget', case when p_budget is null or coalesce(c.fee_yearly, c.fee_total) is null then null else coalesce(c.fee_yearly, c.fee_total) <= p_budget end)
      || case when p_money then jsonb_build_object('partners', c.partners, 'eduwit_commission', b2c.programme_commission(c.university_id, c.id, c.fee_yearly, c.fee_total)) else '{}'::jsonb end
$f$;

/* The Programme page (B8.9): search, filters, sort, paging; "eligible for this lead" when opened from a lead. */
create or replace function b2c.programme_search(p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare q text := nullif(trim(p ->> 'q'), ''); v_money boolean := b2c.my_role() in ('admin', 'marketing'); v_lead bigint := nullif(p ->> 'lead', '')::bigint;
        v_rank int; v_budget numeric; v_sort text := coalesce(p ->> 'sort', 'name'); v jsonb; v_total int;
        v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 300); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_lead is not null then
    if not coalesce(b2c.can_see(v_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
    select b2c.qual_rank(r.record -> 'education' ->> 'highest_qualification'), b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr')
      into v_rank, v_budget from b2c.lead_records r where r.lead_id = v_lead;
  end if;
  if not exists (select 1 from b2c.programme_cache) then perform b2c.programme_cache_refresh(true); end if;
  with f as (
    select c from b2c.programme_cache c
     where c.active
       and (q is null or c.search_doc @@ websearch_to_tsquery('simple', q) or c.name ilike '%' || q || '%' or c.university ilike '%' || q || '%' or c.specialization ilike '%' || q || '%')
       and (p ->> 'level' is null or c.level ilike p ->> 'level')
       and (p ->> 'mode' is null or c.mode ilike p ->> 'mode')
       and (p ->> 'course' is null or c.course ilike '%' || (p ->> 'course') || '%' or c.name ilike '%' || (p ->> 'course') || '%')
       and (p ->> 'university' is null or c.university ilike '%' || (p ->> 'university') || '%' or c.university_short ilike p ->> 'university')
       and (p ->> 'specialization' is null or c.specialization ilike '%' || (p ->> 'specialization') || '%')
       and (p ->> 'fee_max' is null or coalesce(c.fee_total, c.fee_yearly) <= (p ->> 'fee_max')::numeric)
       and (p ->> 'fee_min' is null or coalesce(c.fee_total, c.fee_yearly) >= (p ->> 'fee_min')::numeric)
       and (p ->> 'duration_max' is null or c.duration_months <= (p ->> 'duration_max')::int)
       and (p ->> 'duration_min' is null or c.duration_months >= (p ->> 'duration_min')::int)
       and (p ->> 'intake' is null or exists (select 1 from unnest(c.intakes) i where i ilike '%' || (p ->> 'intake') || '%'))
       and (p ->> 'accreditation' is null or c.accreditation ilike '%' || (p ->> 'accreditation') || '%' or c.recognitions::text ilike '%' || (p ->> 'accreditation') || '%')
       and (p ->> 'emi' is null or not (p ->> 'emi')::boolean or c.emi_monthly is not null)
       and (not coalesce((p ->> 'eligible')::boolean, false) or v_rank is null or c.min_rank is null or v_rank >= c.min_rank))
  select (select count(*) from f),
         coalesce(jsonb_agg(b2c.programme_json(s.c, v_money, v_rank, v_budget) order by s.ord1, s.ord2 nulls last, s.nm, s.fid), '[]')
    into v_total, v
    from (select f.c, case v_sort when 'popularity' then -(f.c).enrollments else 0 end ord1,
                 case v_sort when 'fee' then coalesce((f.c).fee_total, (f.c).fee_yearly) when 'fee_desc' then -coalesce((f.c).fee_total, (f.c).fee_yearly)
                             when 'duration' then (f.c).duration_months end ord2, (f.c).name nm, (f.c).id fid
            from f order by ord1, ord2 nulls last, nm, fid limit v_limit offset v_offset) s;
  return jsonb_build_object('total', v_total, 'rows', v, 'eligible_rank', v_rank, 'budget', v_budget);
end $f$;

/* Filter choices for the Programme page. */
create or replace function b2c.programme_facets() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'universities', (select coalesce(jsonb_agg(distinct university), '[]') from b2c.programme_cache where active),
    'specializations', (select coalesce(jsonb_agg(distinct specialization), '[]') from b2c.programme_cache where active and specialization is not null),
    'levels', (select coalesce(jsonb_agg(distinct level), '[]') from b2c.programme_cache where active and level is not null),
    'modes', (select coalesce(jsonb_agg(distinct mode), '[]') from b2c.programme_cache where active and mode is not null),
    'intakes', (select coalesce(jsonb_agg(distinct i), '[]') from b2c.programme_cache, unnest(intakes) i where active),
    'fee', (select jsonb_build_object('min', min(coalesce(fee_total, fee_yearly)), 'max', max(coalesce(fee_total, fee_yearly))) from b2c.programme_cache where active),
    'duration', (select jsonb_build_object('min', min(duration_months), 'max', max(duration_months)) from b2c.programme_cache where active));
end $f$;

/* Compare 2 to 4 programmes side by side (optionally for a lead's eligibility and budget). */
create or replace function b2c.programme_compare(p_ids bigint[], p_lead bigint default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int; v_budget numeric; v_money boolean := b2c.my_role() in ('admin', 'marketing'); v jsonb;
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(cardinality(p_ids), 0) not between 2 and 4 then raise exception 'compare 2 to 4 programmes'; end if;
  if p_lead is not null then
    if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
    select b2c.qual_rank(r.record -> 'education' ->> 'highest_qualification'), b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr')
      into v_rank, v_budget from b2c.lead_records r where r.lead_id = p_lead;
  end if;
  select coalesce(jsonb_agg(b2c.programme_json(c, v_money, v_rank, v_budget) order by array_position(p_ids, c.id)), '[]') into v
    from b2c.programme_cache c where c.id = any (p_ids);
  if jsonb_array_length(v) <> cardinality(p_ids) then raise exception 'unknown programme'; end if;
  return v;
end $f$;

/* Programme fit (B8.3): the catalogue ranked against the lead's interest (course 4, specialization 3, university 2,
   mode 1), with eligibility (qualification against the minimum), budget, EMI and duration side by side. */
create or replace function b2c.programme_fit(p_lead bigint, p_limit int default 12) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare l record; v_level text; v_rank int; v_budget numeric; v_money boolean := b2c.my_role() in ('admin', 'marketing');
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select lower(nullif(trim(v.course), '')) as course, lower(nullif(trim(v.specialization), '')) as spec, lower(nullif(trim(v.university), '')) as uni,
         lower(nullif(trim(v.study_mode), '')) as mode, lower(nullif(trim(v.programme_level), '')) as level, v.qualification
    into l from b2c.leads_v v where v.lead_id = p_lead;
  select b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr') into v_budget from b2c.lead_records r where r.lead_id = p_lead;
  v_rank := b2c.qual_rank(l.qualification);
  v_level := case when l.level in ('pg', 'postgraduate', 'post graduate', 'post-graduate', 'masters', 'master') then 'pg'
                  when l.level in ('ug', 'undergraduate', 'under graduate', 'under-graduate', 'bachelors', 'bachelor') then 'ug'
                  else l.level end;
  if not exists (select 1 from b2c.programme_cache) then perform b2c.programme_cache_refresh(true); end if;
  return jsonb_build_object(
    'interest', jsonb_build_object('course', l.course, 'specialization', l.spec, 'university', l.uni, 'mode', l.mode, 'level', l.level,
                                   'qualification', l.qualification, 'budget', v_budget),
    'rows', (select coalesce(jsonb_agg(b2c.programme_json(s.c, v_money, v_rank, v_budget)
                               || jsonb_build_object('fit', s.fit, 'matched', to_jsonb(array_remove(array[s.m_course, s.m_spec, s.m_uni, s.m_mode], null))) order by s.ord), '[]')
      from (select s1.*, row_number() over (order by s1.fit desc, (s1.ok is false), (s1.in_budget is false), coalesce((s1.c).fee_total, (s1.c).fee_yearly) nulls last, (s1.c).university) ord
              from (select s0.*, case when s0.m_course is not null then 4 else 0 end + case when s0.m_spec is not null then 3 else 0 end
                                 + case when s0.m_uni is not null then 2 else 0 end + case when s0.m_mode is not null then 1 else 0 end as fit,
                           case when v_rank is null or (s0.c).min_rank is null then null else v_rank >= (s0.c).min_rank end ok,
                           case when v_budget is null or coalesce((s0.c).fee_yearly, (s0.c).fee_total) is null then null else coalesce((s0.c).fee_yearly, (s0.c).fee_total) <= v_budget end in_budget
                      from (select c,
                                   case when l.course is not null and (lower(coalesce(c.course, '')) = l.course or position(l.course in lower(coalesce(c.name, ''))) > 0) then 'course' end as m_course,
                                   case when l.spec is not null and position(l.spec in lower(coalesce(c.specialization, ''))) > 0 then 'specialization' end as m_spec,
                                   case when l.uni is not null and (position(l.uni in lower(coalesce(c.university, ''))) > 0 or lower(coalesce(c.university_short, '')) = l.uni) then 'university' end as m_uni,
                                   case when l.mode is not null and lower(coalesce(c.mode, '')) = l.mode then 'mode' end as m_mode
                              from b2c.programme_cache c
                             where c.active and (v_level is null or lower(c.level) = v_level)) s0) s1
             where s1.fit > 0
             order by 2 limit least(greatest(coalesce(p_limit, 12), 1), 50)) s));
end $f$;

-- ---------- Pipeline (C3) ----------
/* Expected commission on an open lead: the enrolment's earnings when there is one, else the university rate on the
   application's fee or on the interested programme's fee (where the university is known). */
create or replace function b2c.lead_expected_value(p_lead bigint) returns numeric language plpgsql stable security definer set search_path = '' as $f$
declare v numeric; a record; c b2c.programme_cache; l record;
begin
  select sum(g.gross) into v from b2c.enrollments e join b2c.earnings g on g.enrollment_id = e.id where e.lead_id = p_lead;
  if v is not null then return v; end if;
  select lower(nullif(trim(x.course), '')) course, lower(nullif(trim(x.university), '')) uni into l from b2c.leads_v x where x.lead_id = p_lead;
  select ap.fee_amount, ap.university into a from b2c.applications ap where ap.lead_id = p_lead and ap.status not in ('withdrawn', 'rejected') order by ap.created_at desc limit 1;
  select * into c from b2c.programme_cache pc
   where pc.active and ((a.university is not null and pc.university ilike '%' || a.university || '%')
                        or (a.university is null and l.uni is not null and (position(l.uni in lower(pc.university)) > 0 or lower(coalesce(pc.university_short, '')) = l.uni)))
     and (l.course is null or lower(coalesce(pc.course, '')) = l.course or position(l.course in lower(coalesce(pc.name, ''))) > 0)
   order by pc.fee_yearly nulls last limit 1;
  if c.id is null then return null; end if;
  return (b2c.programme_commission(c.university_id, c.id, coalesce(a.fee_amount, c.fee_yearly), coalesce(a.fee_amount, c.fee_total)) ->> 'amount')::numeric;
end $f$;

/* The kanban: one column per Eduwit stage, with the count, expected commission and cards in priority order
   (overdue follow-up, hot, SLA at risk, highest expected value). */
create or replace function b2c.pipeline_board(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin') or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;

-- ---------- Inbox (C5, D3) ----------
/* Every conversation the person may read: counsellors their own leads, the Admin and the sales head all, Marketing all
   read-only. Searches name, number, message text and template name; filters by counsellor, unread, window, awaiting reply. */
create or replace function b2c.inbox_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_q text := nullif(trim(p ->> 'search'), ''); v_digits text;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_digits := nullif(regexp_replace(coalesce(v_q, ''), '\D', '', 'g'), '');
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_id', v.owner_id, 'owner_name', v.owner_name,
                              'status', v.status, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'awaiting_reply', coalesce(lm.direction = 'in', false),
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at), 'read_only', v_role = 'marketing',
                              'last', lm.body, 'last_template', lm.template_name, 'last_direction', lm.direction,
                              'match', case when v_q is not null then (select left(m.body, 160) from b2c.wa_messages m where m.phone = c.phone and m.body ilike '%' || v_q || '%' order by m.created_at desc limit 1) end) x
      from b2c.wa_conversations c
      left join b2c.leads_v v on v.lead_id = c.lead_id
      left join lateral (select m.body, m.template_name, m.direction from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc, m.id desc limit 1) lm on true
     where (v_role in ('admin', 'marketing', 'sales_head') or v.owner_id = me)
       and (v_q is null or v.name ilike '%' || v_q || '%' or (v_digits is not null and c.phone like '%' || v_digits || '%')
            or exists (select 1 from b2c.wa_messages m where m.phone = c.phone and (m.body ilike '%' || v_q || '%' or m.template_name ilike '%' || v_q || '%')))
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
       and (p ->> 'owner' is null or v_role = 'counsellor' or (p ->> 'owner' = 'none' and v.owner_id is null) or v.owner_id::text = p ->> 'owner')
       and (p ->> 'window' is null or (p ->> 'window' = 'open') = coalesce(c.last_inbound_at > now() - interval '24 hours', false))
       and (not coalesce((p ->> 'awaiting')::boolean, false) or lm.direction = 'in')
     order by greatest(c.last_inbound_at, c.last_outbound_at) desc nulls last
     limit least(coalesce((p ->> 'limit')::int, 200), 500)) q);
end $f$;

-- ---------- Sales email library (C4) ----------
/* The shared library: author, uses, reply rate (an inbound email on the same thread after a send). Hidden templates
   only for the Admin and their author. */
create or replace function b2c.email_library(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_sales_email'); v_admin boolean := b2c.my_role() = 'admin';
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'category', t.category, 'subject', t.subject, 'body', t.body,
             'attachments', t.attachments, 'parent_id', t.parent_id, 'version', t.version, 'recommended', t.recommended, 'hidden', t.hidden,
             'owner_id', t.owner_id, 'author', u.full_name, 'mine', t.owner_id = me, 'uses', s.sent, 'replies', s.replied,
             'reply_rate', case when s.sent > 0 then round(100.0 * s.replied / s.sent) end, 'updated_at', t.updated_at)
             order by t.recommended desc, case when s.sent >= 5 then s.replied::numeric / s.sent end desc nulls last, t.updated_at desc), '[]')
    from b2c.sales_email_templates t
    left join b2c.users u on u.user_id = t.owner_id
    left join lateral (select count(*)::int sent,
                              count(*) filter (where exists (select 1 from b2c.emails i where i.direction = 'in' and i.thread_id = e.thread_id and e.thread_id is not null
                                                                and i.created_at > e.created_at))::int replied
                         from b2c.emails e where e.template_id = t.id and e.direction = 'out') s on true
   where t.deleted_at is null and (not t.hidden or v_admin or t.owner_id = me)
     and (p ->> 'category' is null or t.category = p ->> 'category')
     and (not coalesce((p ->> 'mine')::boolean, false) or t.owner_id = me)
     and (coalesce(trim(p ->> 'search'), '') = '' or t.name ilike '%' || trim(p ->> 'search') || '%' or t.subject ilike '%' || trim(p ->> 'search') || '%'));
end $f$;

/* Every merge field a sales email or WhatsApp message may use, from the lead, its best-fitting programme and the counsellor. */
create or replace function b2c.merge_values(p_lead bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); u b2c.users; v jsonb; f jsonb; t timestamptz;
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into u from b2c.users where user_id = coalesce((select owner_id from b2c.leads_state where lead_id = p_lead), me);
  f := b2c.programme_fit(p_lead, 1) -> 'rows' -> 0;
  select min(due_at) into t from b2c.tasks where lead_id = p_lead and status = 'open';
  select jsonb_build_object(
      'first_name', b2c.first_name(p_lead),
      'programme', coalesce(nullif(x.course, ''), f ->> 'name', 'your programme'),
      'university', coalesce(nullif(x.university, ''), f ->> 'university', 'the university'),
      'fee', case when f ->> 'fee_yearly' is not null then 'Rs ' || to_char((f ->> 'fee_yearly')::numeric, 'FM99,99,99,999') || ' a year'
                  when f ->> 'fee_total' is not null then 'Rs ' || to_char((f ->> 'fee_total')::numeric, 'FM99,99,99,999') || ' in all' end,
      'emi', case when f ->> 'emi_monthly' is not null then 'Rs ' || to_char((f ->> 'emi_monthly')::numeric, 'FM99,99,99,999') || ' a month' end,
      'brochure_link', f ->> 'brochure_url',
      'counsellor_name', coalesce(u.full_name, u.email),
      'counsellor_first_name', split_part(coalesce(u.full_name, u.email, ''), ' ', 1),
      'counsellor_number', u.phone,
      'followup_time', case when t is not null then to_char(t at time zone 'Asia/Kolkata', 'FMDD Mon, FMHH12:MI AM') end)
    into v from b2c.leads_v x where x.lead_id = p_lead;
  return jsonb_strip_nulls(v);
end $f$;

-- ---------- WhatsApp to a person's own number (C7, D5) ----------
alter table b2c.users add column if not exists wa_alerts text[] not null default '{}';
alter table b2c.notifications add column if not exists wa_at timestamptz;
insert into b2c.settings (key, value) values ('staff_alerts', '{"template": "staff_alert", "kinds": ["reminder", "overdue", "sla_breach", "escalation", "assignment", "neglect", "metric_alert"]}')
on conflict (key) do nothing;

/* Which alerts a person also wants on WhatsApp (their own number from Teams). */
create or replace function b2c.my_wa_alerts_set(p_kinds text[]) returns text[] language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_allowed text[];
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select array(select jsonb_array_elements_text(b2c.setting('staff_alerts') -> 'kinds')) into v_allowed;
  if exists (select 1 from unnest(coalesce(p_kinds, '{}')) k where not k = any (v_allowed)) then raise exception 'unknown alert'; end if;
  if cardinality(coalesce(p_kinds, '{}')) > 0 and coalesce(b2c.norm_phone((select phone from b2c.users where user_id = me)), '') = '' then
    raise exception 'add your mobile number in Teams first';
  end if;
  update b2c.users set wa_alerts = coalesce(p_kinds, '{}'), updated_at = now() where user_id = me;
  return coalesce(p_kinds, '{}');
end $f$;

/* Every minute: new notifications of the kinds a person chose go to their own number, through the approved staff template.
   Without an approved template nothing is sent (the Connectors page says so). */
create or replace function b2c.staff_wa_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare s jsonb := b2c.setting('staff_alerts'); t b2c.wa_templates; r record; n int := 0; v_base text := b2c.setting('app') ->> 'base_url';
begin
  select * into t from b2c.wa_templates where name = s ->> 'template' and status = 'approved' and archived_at is null order by version desc limit 1;
  if t.id is null then return jsonb_build_object('sent', 0, 'why', 'no approved staff template'); end if;
  for r in select n.id, n.title, n.body, n.link, b2c.norm_phone(u.phone) phone from b2c.notifications n join b2c.users u on u.user_id = n.user_id
            where n.wa_at is null and n.created_at > now() - interval '15 minutes' and n.kind = any (u.wa_alerts) and u.is_active
              and coalesce(b2c.norm_phone(u.phone), '') <> '' order by n.id limit 200 for update of n skip locked loop
    insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
    values ('whatsapp', null, r.phone, jsonb_build_object('type', 'template', 'template', jsonb_build_object('name', t.name, 'language', t.language,
            'params', (select coalesce(jsonb_agg(case o when 1 then left(r.title, 200) when 2 then left(coalesce(r.body, ''), 300)
                                                                 else coalesce(v_base, '') || coalesce(r.link, '') end order by o), '[]')
                         from jsonb_array_elements_text(t.variables) with ordinality x(v, o)))), 'staff_alert', 'staffwa:' || r.id)
    on conflict do nothing;
    update b2c.notifications set wa_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('sent', n);
end $f$;

-- ---------- custom profile fields (C9) ----------
alter table b2c.leads_state add column if not exists custom jsonb not null default '{}'::jsonb;
insert into b2c.settings (key, value) values ('custom_fields', '{"fields": []}') on conflict (key) do nothing;

/* The Admin defines the fields: [{key, label, type: text|number|date|select|yes_no, options}] (versioned like every setting). */
create or replace function b2c.custom_fields_save(p_fields jsonb, p_reason text) returns int language plpgsql security definer set search_path = '' as $f$
declare x jsonb;
begin
  perform b2c.require('settings');
  if jsonb_typeof(p_fields) <> 'array' or jsonb_array_length(p_fields) > 30 then raise exception 'at most 30 fields'; end if;
  for x in select * from jsonb_array_elements(p_fields) loop
    if coalesce(x ->> 'key', '') !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'field keys are lower-case letters, digits and _'; end if;
    if coalesce(trim(x ->> 'label'), '') = '' then raise exception 'every field needs a label'; end if;
    if coalesce(x ->> 'type', '') not in ('text', 'number', 'date', 'select', 'yes_no') then raise exception 'unknown field type %', x ->> 'type'; end if;
    if x ->> 'type' = 'select' and jsonb_array_length(coalesce(x -> 'options', '[]')) = 0 then raise exception '% needs its choices', x ->> 'label'; end if;
  end loop;
  if (select count(distinct y ->> 'key') from jsonb_array_elements(p_fields) y) <> jsonb_array_length(p_fields) then raise exception 'two fields share a key'; end if;
  return b2c.set_setting('custom_fields', jsonb_build_object('fields', p_fields), p_reason);
end $f$;

create or replace function b2c.custom_field_set(p_lead bigint, p_key text, p_value text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); d jsonb; v jsonb; v_old jsonb;
begin
  select x into d from jsonb_array_elements(b2c.setting('custom_fields') -> 'fields') x where x ->> 'key' = p_key;
  if d is null then raise exception 'unknown field'; end if;
  if nullif(trim(p_value), '') is null then v := null;
  else
    v := case d ->> 'type'
      when 'number' then to_jsonb(b2c.num_or_null(p_value))
      when 'date' then to_jsonb(p_value::date::text)
      when 'yes_no' then to_jsonb(lower(p_value) in ('yes', 'true', '1'))
      else to_jsonb(left(trim(p_value), 300)) end;
    if d ->> 'type' = 'select' and not exists (select 1 from jsonb_array_elements_text(d -> 'options') o where o = p_value) then raise exception 'choose one of the options'; end if;
    if d ->> 'type' = 'number' and v = 'null'::jsonb then raise exception 'enter a number'; end if;
  end if;
  select custom -> p_key into v_old from b2c.leads_state where lead_id = p_lead for update;
  if v_old is not distinct from v then return (select custom from b2c.leads_state where lead_id = p_lead); end if;
  update b2c.leads_state set custom = case when v is null then custom - p_key else custom || jsonb_build_object(p_key, v) end, updated_at = now() where lead_id = p_lead;
  insert into b2c.field_history (lead_id, field, old_value, new_value, kind, actor_id) values (p_lead, 'custom.' || p_key, v_old, v, 'human_correction', me);
  return (select custom from b2c.leads_state where lead_id = p_lead);
end $f$;

-- ---------- document checklists (C10, D4) and opening documents ----------
/* The Admin edits a university's checklist ('*' is the default list); each change is kept in the audit log. */
create or replace function b2c.checklist_save(p_university text, p_items text[], p_reason text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v_old jsonb; v_items jsonb;
begin
  if coalesce(trim(p_university), '') = '' then raise exception 'name the university (or * for the default list)'; end if;
  select coalesce(jsonb_agg(trim(x)), '[]') into v_items from (select distinct on (lower(trim(x))) x from unnest(coalesce(p_items, '{}')) x where trim(x) <> '') q;
  select items into v_old from b2c.document_checklists where university = trim(p_university);
  if jsonb_array_length(v_items) = 0 and trim(p_university) = '*' then raise exception 'the default list cannot be empty'; end if;
  insert into b2c.document_checklists (university, items) values (trim(p_university), v_items)
  on conflict (university) do update set items = excluded.items;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'checklist_changed', jsonb_build_object('university', trim(p_university), 'old', v_old, 'new', v_items, 'reason', p_reason));
end $f$;

create or replace function b2c.checklists() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'lists', (select coalesce(jsonb_agg(jsonb_build_object('university', c.university, 'items', c.items) order by c.university <> '*', c.university), '[]') from b2c.document_checklists c),
    'history', case when b2c.my_role() = 'admin' then (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'by', u.full_name, 'detail', a.detail) order by a.at desc), '[]')
                    from (select * from b2c.audit_log where action = 'checklist_changed' order by at desc limit 50) a left join b2c.users u on u.user_id = a.actor_id) end);
end $f$;

/* A stored document, for a signed link: anyone who may see the lead (counsellors their own leads). Logged. */
create or replace function b2c.document_open(p_document bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare d b2c.documents;
begin
  select * into d from b2c.documents where id = p_document and removed_at is null;
  if d.id is null or not coalesce(b2c.can_see(d.lead_id), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (b2c.uid(), 'document_open', d.lead_id, jsonb_build_object('document', d.id));
  return jsonb_build_object('bucket', 'b2c-documents', 'path', d.storage_path, 'filename', coalesce(d.file_name, d.kind));
end $f$;

-- ---------- SLA by source and neglect (C11) ----------
alter table b2c.leads_state add column if not exists neglect_alerted_at timestamptz;
update b2c.settings set value = value || '{"by_source": {}}' where key = 'sla_minutes' and not value ? 'by_source';

/* First-contact minutes: by source when the Admin set one ({"by_source": {"website": {"hot": 10, "warm": 120}}}), else by temperature. */
create or replace function b2c.sla_minutes_for(p_lead bigint, p_hot boolean, p_temperature text, p_default int) returns int language sql stable security definer set search_path = '' as $f$
  select coalesce(b2c.num_or_null(b2c.setting('sla_minutes') -> 'by_source' -> (select r.record -> 'source' ->> 'lead_source' from b2c.lead_records r where r.lead_id = p_lead)
                    ->> case when p_hot then 'hot' else coalesce(nullif(p_temperature, ''), 'warm') end)::int, p_default)
$f$;

/* Leads untouched for 48 hours (setting followups.untouched_hours) are flagged to the counsellor and the Admin once per spell. */
create or replace function b2c.neglect_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare h int := coalesce((b2c.setting('followups') ->> 'untouched_hours')::int, 48); r record; n int := 0;
begin
  for r in select s.lead_id, s.owner_id, s.is_test, coalesce(s.last_activity_at, s.assigned_at) last_at from b2c.leads_state s
            where s.status = 'active' and s.owner_id is not null and s.deleted_at is null and s.stage_id not in (9, 10)
              and coalesce(s.last_activity_at, s.assigned_at) < now() - make_interval(hours => h)
              and (s.neglect_alerted_at is null or s.neglect_alerted_at < coalesce(s.last_activity_at, s.assigned_at))
            limit 300 loop
    perform b2c.notify(r.owner_id, 'neglect', 'Untouched for ' || h || ' hours', 'Work this lead today.', '/s/leads/' || r.lead_id, r.lead_id, 'neglect:' || r.lead_id || ':' || extract(epoch from r.last_at)::bigint);
    if not r.is_test then
      perform b2c.notify_admins('neglect', 'Lead untouched for ' || h || ' hours', null, '/w/leads/' || r.lead_id, r.lead_id, 'neglect:' || r.lead_id || ':' || extract(epoch from r.last_at)::bigint, false);
    end if;
    update b2c.leads_state set neglect_alerted_at = now() where lead_id = r.lead_id;
    n := n + 1;
  end loop;
  return n;
end $f$;

select b2c.programme_cache_refresh(true);

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-programme-cache') then
    perform cron.schedule('b2c-programme-cache', '*/15 * * * *', 'select b2c.programme_cache_refresh(false)');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-staff-alerts') then
    perform cron.schedule('b2c-staff-alerts', '* * * * *', 'select b2c.staff_wa_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-neglect') then
    perform cron.schedule('b2c-neglect', '7,37 * * * *', 'select b2c.neglect_tick()');
  end if;
end $d$;

-- ---------- redefined: assignment uses the SLA by source (b4 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.assign(p_lead bigint, p_user uuid, p_decision bigint, p_trigger text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare
  s b2c.leads_state; u b2c.users; v_sub text; v_sla int; v_due timestamptz; v_start timestamptz; v_in_hours boolean; v_name text;
  m jsonb := b2c.setting('sla_minutes');
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  select * into u from b2c.users where user_id = p_user;
  update b2c.assignments set ended_at = now(), end_reason = coalesce(p_reason, p_trigger) where lead_id = p_lead and ended_at is null;
  insert into b2c.assignments (lead_id, user_id, decision_id, trigger, reason, by_user) values (p_lead, p_user, p_decision, p_trigger, p_reason, b2c.uid());
  v_sub := case p_trigger when 'reengaged' then 'Re-engaged from nurture' when 're_enquiry' then 'Re-enquiry' when 'created' then 'Created by me'
                          when 'returned_from_partners' then 'Returned from partners' else 'Fresh assignment' end;
  v_sla := case when s.hot or p_trigger = 'reengaged' then (m ->> 'hot')::int
                when coalesce(s.temperature, '') = 'warm' then (m ->> 'warm')::int else coalesce((m ->> 'cold')::int, 1440) end;
  if s.temperature is null and not s.hot and p_trigger <> 'reengaged' then v_sla := (m ->> 'warm')::int; end if;
  v_sla := b2c.sla_minutes_for(p_lead, s.hot or p_trigger = 'reengaged', s.temperature, v_sla);
  v_in_hours := b2c.working_now(p_user, now());
  v_start := coalesce(b2c.next_working_at(p_user, now()), now());
  v_due := coalesce(b2c.add_working_minutes(p_user, now(), v_sla), now() + make_interval(mins => v_sla));
  update b2c.leads_state set
    owner_id = p_user, assigned_at = now(), status = 'active',
    previous_owner_id = case when s.owner_id is distinct from p_user then coalesce(s.owner_id, s.previous_owner_id) else s.previous_owner_id end,
    stage_id = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then 1 else s.stage_id end,
    sub_stage = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then v_sub else s.sub_stage end,
    stage_changed_at = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then now() else s.stage_changed_at end,
    hot = s.hot or p_trigger = 'reengaged',
    reengaged_at = case when p_trigger = 'reengaged' then now() else s.reengaged_at end,
    journey = null,
    sla_due_at = case when s.first_contacted_at is null or p_trigger = 'reengaged' then v_due else s.sla_due_at end,
    sla_met_at = case when p_trigger = 'reengaged' then null else s.sla_met_at end,
    sla_breached_at = case when p_trigger = 'reengaged' then null else s.sla_breached_at end,
    next_task_due_at = v_due, updated_at = now()
  where lead_id = p_lead;
  update b2c.tasks set owner_id = p_user where lead_id = p_lead and status = 'open';
  insert into b2c.tasks (lead_id, owner_id, kind, title, due_at, suggested, source)
  select p_lead, p_user, 'call', case when s.handling ->> 'first_contact_script' = 'neutral_adviser' then 'First call: neutral-adviser opening' else 'First call' end,
         v_due, false, 'assignment'
   where not exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.status = 'open' and t.kind = 'call');
  select st.name into v_name from b2c.stages st join b2c.leads_state x on x.stage_id = st.id where x.lead_id = p_lead;
  perform b2c.queue_update(p_lead, jsonb_build_object(
    'owner_user_id', p_user, 'owner_name', u.full_name, 'assigned_at', now(), 'stage', 'assigned', 'stage_changed_at', now(),
    'sub_stage', left(v_sub, 80), 'b2c_stage', v_name, 'b2c_sub_stage', v_sub, 'next_task_due_at', v_due), false);
  insert into b2c.activities (lead_id, kind, body, meta, actor_id, at)
  values (p_lead, 'assignment', 'Assigned to ' || coalesce(u.full_name, u.email) || coalesce(' (' || p_reason || ')', ''),
          jsonb_build_object('decision_id', p_decision, 'trigger', p_trigger), b2c.uid(), now());
  perform b2c.notify(p_user, case when p_trigger = 'reengaged' then 'reengaged' else 'assigned' end,
                     case when p_trigger = 'reengaged' then 'Hot: a nurtured lead re-engaged' else 'New lead assigned' end,
                     coalesce(s.reengage_trigger, s.handoff_reason), '/s/leads/' || p_lead, p_lead, 'assign:' || p_lead || ':' || coalesce(p_decision, 0));
  perform b2c.queue_assignment_message(p_lead, p_user, v_in_hours, v_start);
end $f$;

-- ---------- redefined: share up to 4 programmes, as the comparison allows (b11 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.programme_share(p_lead bigint, p_programmes bigint[], p_channel text, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare me uuid := b2c.require_lead(p_lead); v bigint; v_items jsonb; v_names text;
begin
  if p_channel is null or p_channel not in ('whatsapp', 'email', 'call', 'meeting') then raise exception 'say how the programme was shared'; end if;
  if coalesce(cardinality(p_programmes), 0) = 0 then raise exception 'choose at least one programme'; end if;
  if cardinality(p_programmes) > 4 then raise exception 'share at most 4 programmes at a time'; end if;
  select jsonb_agg(jsonb_build_object('id', pr.id, 'name', coalesce(pr.program_name, pr.course), 'university', un.name) order by array_position(p_programmes, pr.id)),
         string_agg(coalesce(pr.program_name, pr.course) || ' (' || un.name || ')', ', ' order by array_position(p_programmes, pr.id))
    into v_items, v_names
    from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
   where pr.id = any (p_programmes);
  if v_items is null or jsonb_array_length(v_items) <> cardinality(p_programmes) then raise exception 'unknown programme'; end if;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'programme_shared', case when p_channel in ('whatsapp', 'email') then 'out' end,
          case p_channel when 'call' then 'Explained on a call: ' when 'meeting' then 'Explained in a meeting: '
                         when 'whatsapp' then 'Shared on WhatsApp: ' else 'Shared by email: ' end || v_names
            || coalesce(E'\n' || nullif(trim(p_note), ''), ''),
          jsonb_build_object('programmes', v_items, 'channel', p_channel), me)
  returning id into v;
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  return v;
end $f$;

-- ---------- redefined: the lead screen also gets done tasks, custom fields, partner history and documents (b5 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.lead_detail(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'lead', (select to_jsonb(x) from b2c.leads_v x where x.lead_id = p_lead),
    'record', (select r.record from b2c.lead_records r where r.lead_id = p_lead),
    'pending', b2c.pending_set(p_lead),
    'contacts', (select coalesce(jsonb_agg(to_jsonb(c) order by c.origin = 'intake' desc, c.created_at), '[]') from b2c.lead_contacts c where c.lead_id = p_lead and c.removed_at is null),
    'tasks', (select coalesce(jsonb_agg(to_jsonb(t) order by t.due_at), '[]') from b2c.tasks t where t.lead_id = p_lead and t.status = 'open'),
    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'direction', a.direction, 'outcome', a.outcome, 'body', a.body,
                                 'internal', a.internal, 'at', a.at, 'actor', (select u.full_name from b2c.users u where u.user_id = a.actor_id), 'meta', a.meta) order by a.at desc), '[]')
                  from (select * from b2c.activities a where a.lead_id = p_lead and (not a.internal or b2c.my_role() in ('admin', 'sales_head')) order by a.at desc limit 150) a),
    'unlogged_call', (select to_jsonb(c) from b2c.calls c where c.lead_id = p_lead and c.logged_at is null and c.user_id = b2c.uid() order by c.tapped_at desc limit 1),
    'applications', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]') from b2c.applications a where a.lead_id = p_lead),
    'enrollments', (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at), '[]') from b2c.enrollments e where e.lead_id = p_lead),
    'decision', (select to_jsonb(d) from b2c.allocation_decisions d where d.lead_id = p_lead and not d.simulated order by d.at desc limit 1),
    'consent_request', (select to_jsonb(q) from b2c.consent_requests q where q.lead_id = p_lead order by q.created_at desc limit 1),
    'history', (select coalesce(jsonb_agg(to_jsonb(h) order by h.at desc), '[]') from b2c.field_history h where h.lead_id = p_lead),
    'done_tasks', (select coalesce(jsonb_agg(to_jsonb(t) order by t.done_at desc), '[]') from (select * from b2c.tasks t where t.lead_id = p_lead and t.status <> 'open' order by t.done_at desc nulls last limit 30) t),
    'custom_fields', b2c.setting('custom_fields') -> 'fields',
    'custom', (select s.custom from b2c.leads_state s where s.lead_id = p_lead),
    'partner', (select jsonb_build_object('lost', s.partner_lost, 'tried', s.partners_tried, 'flagged', s.flagged, 'routing_requested_at', s.routing_requested_at)
                  from b2c.leads_state s where s.lead_id = p_lead),
    'documents', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'application_id', d.application_id, 'kind', d.kind, 'file_name', d.file_name, 'source', d.source, 'created_at', d.created_at) order by d.created_at desc), '[]')
                    from b2c.documents d where d.lead_id = p_lead and d.removed_at is null))
  into v;
  return v;
end $f$;

-- ---------- grants ----------
grant execute on function b2c.wa_queue_media(bigint, text, text, text, text, text), b2c.wa_media_open(bigint), b2c.wa_media_attach(bigint, bigint, text),
  b2c.programme_search(jsonb), b2c.programme_facets(), b2c.programme_compare(bigint[], bigint), b2c.programme_fit(bigint, integer), b2c.pipeline_board(jsonb),
  b2c.inbox_list(jsonb), b2c.email_library(jsonb), b2c.merge_values(bigint), b2c.my_wa_alerts_set(text[]), b2c.custom_fields_save(jsonb, text),
  b2c.custom_field_set(bigint, text, text), b2c.checklist_save(text, text[], text), b2c.checklists(), b2c.document_open(bigint),
  b2c.programme_share(bigint, bigint[], text, text), b2c.lead_detail(bigint) to authenticated;
grant execute on function b2c.wa_media_take(integer), b2c.wa_media_stored(bigint, text, text), b2c.programme_cache_refresh(boolean), b2c.staff_wa_tick(),
  b2c.neglect_tick() to service_role;
revoke execute on function b2c.wa_media_take(integer), b2c.wa_media_stored(bigint, text, text), b2c.programme_cache_refresh(boolean), b2c.staff_wa_tick(),
  b2c.neglect_tick(), b2c.num_or_null(text), b2c.programme_commission(bigint, bigint, numeric, numeric), b2c.programme_json(b2c.programme_cache, boolean, integer, numeric),
  b2c.lead_expected_value(bigint), b2c.sla_minutes_for(bigint, boolean, text, integer), b2c.assign(bigint, uuid, bigint, text, text) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;

-- ===== b42_access_allocation.sql =====
-- B2C CRM b42: completing access, stages and allocation (docs/completion-gaps.md, section E, plus D4 and D13). Staging first. Idempotent.
--   sales head          sees and works their own team's leads; approves counsellors' stage overrides (B3.1)
--   stages editor       the Admin renames stages and edits sub-stages, with a change history (B5.1, B15)
--   assignment message  by email when WhatsApp cannot reach the student or fails; Witty's idle wait checked at send time (B7.6)
--   on-call             a hot lead outside hours goes to the on-call counsellor, whatever the rule's fallbacks (B7.1, B7.3)
--   queues              unassigned, waiting for hours and manual queues apart; the manual queue waits for a person (B7.3, B7.4)
--   calendar            breaks and lunch (hot leads only then), holiday import, a week view with "nobody on duty" (B7.1, B7.4)
--   capacity            alerts to the Admin at 90% of a cap and at the hiring trigger; today's intake (B7.5)
--   Teams               every Workspace account not yet added; invitations that expire after 7 days (B3.2)
--   sessions            trusted devices for 7 days, a list of signed-in sessions and devices, remote sign-out (B3.2)
--   rules               simulation can include disabled or future rules (B7.4)
--   student_leads       team_id and expected / realised net revenue through the B2B write API, once the B2B CRM accepts them (B3.3)
--   view as Sales       the Admin sees a chosen counsellor's list, logged (B3.1, B15)

-- ---------- the sales head's team (E15) ----------
/* True when the lead's owner is in the sales head's team (a sales head without a team sees everyone). Others: true. */
create or replace function b2c.in_my_team(p_owner uuid) returns boolean language sql stable security definer set search_path = '' as $f$
  select case when b2c.my_role() <> 'sales_head' then true
              when (select team from b2c.users where user_id = b2c.uid()) is null then true
              when p_owner is null then false
              else (select u.team from b2c.users u where u.user_id = p_owner) is not distinct from (select team from b2c.users where user_id = b2c.uid()) end
$f$;

create or replace function b2c.can_see(p_lead bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true when 'marketing' then true
    when 'sales_head' then b2c.in_my_team((select s.owner_id from b2c.leads_state s where s.lead_id = p_lead))
    when 'counsellor' then exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = b2c.uid() and s.deleted_at is null)
                        or exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.owner_id = b2c.uid() and t.kind = 'qualify' and t.status = 'open')
                        or (b2c.replies_delegate(b2c.uid()) and exists (select 1 from b2c.replies x where x.lead_id = p_lead and x.status in ('inbox', 'pending_ai')))
    else false end
$f$;

create or replace function b2c.require_lead(p_lead bigint) returns uuid language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads');
begin
  if b2c.my_role() = 'admin' then return me; end if;
  if b2c.my_role() = 'sales_head' then
    if b2c.in_my_team((select owner_id from b2c.leads_state where lead_id = p_lead)) then return me; end if;
    raise exception 'not your team''s lead' using errcode = '42501';
  end if;
  if not exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = me and s.deleted_at is null) then
    raise exception 'not your lead' using errcode = '42501';
  end if;
  return me;
end $f$;

create or replace function b2c.lead_scope_sql(p_user uuid, p_role text) returns text language plpgsql stable security definer set search_path = '' as $f$
declare v_team text;
begin
  if p_role = 'counsellor' then return format('owner_id = %L', p_user); end if;
  if p_role = 'sales_head' then
    select team into v_team from b2c.users where user_id = p_user;
    if v_team is not null then
      return format('owner_id in (select tu.user_id from b2c.users tu where tu.team = %L)', v_team);
    end if;
  end if;
  return 'true';
end $f$;

/* Moving a lead back a stage needs the sales head or the Admin: a counsellor asks, they approve (B3.1, B5). */
create table if not exists b2c.stage_requests (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  requested_by uuid not null,
  from_stage smallint,
  to_stage smallint not null,
  sub_stage text not null,
  comment text not null,
  next_due timestamptz,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index if not exists stage_requests_pending on b2c.stage_requests (status, created_at) where status = 'pending';
alter table b2c.stage_requests enable row level security;

create or replace function b2c.stage_override_request(p_lead bigint, p_stage smallint, p_sub text, p_comment text, p_next_due timestamptz default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); s b2c.leads_state; v bigint; v_team text; r record;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if length(coalesce(trim(p_comment), '')) < 3 then raise exception 'give a reason for moving back'; end if;
  if not exists (select 1 from b2c.sub_stages where stage_id = p_stage and name = p_sub and active) then raise exception 'choose a sub-stage'; end if;
  if not exists (select 1 from b2c.stages a join b2c.stages b on b.id = s.stage_id where a.id = p_stage and a.rank < b.rank and not a.reachable_from_any) then
    raise exception 'only a move back needs approval: change the stage yourself';
  end if;
  if p_stage not in (9, 10) and p_next_due is null then raise exception 'set the next follow-up'; end if;
  if exists (select 1 from b2c.stage_requests where lead_id = p_lead and status = 'pending') then raise exception 'a request for this lead is already waiting'; end if;
  insert into b2c.stage_requests (lead_id, requested_by, from_stage, to_stage, sub_stage, comment, next_due)
  values (p_lead, me, s.stage_id, p_stage, p_sub, trim(p_comment), p_next_due) returning id into v;
  select team into v_team from b2c.users where user_id = me;
  for r in select user_id from b2c.users where role = 'sales_head' and is_active and (team is null or team is not distinct from v_team) loop
    perform b2c.notify(r.user_id, 'stage_request', 'Stage change to approve', trim(p_comment), '/s/leads/' || p_lead, p_lead, 'stagereq:' || v);
  end loop;
  if not found then
    perform b2c.notify_admins('stage_request', 'Stage change to approve', trim(p_comment), '/w/leads/' || p_lead, p_lead, 'stagereq:' || v, false);
  end if;
  insert into b2c.activities (lead_id, kind, body, actor_id) values (p_lead, 'stage', 'Asked to move back: ' || trim(p_comment), me);
  return v;
end $f$;

create or replace function b2c.stage_override_decide(p_request bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('stage_override'); q b2c.stage_requests; j jsonb;
begin
  select * into q from b2c.stage_requests where id = p_request for update;
  if q.id is null or q.status <> 'pending' then raise exception 'this request was already decided'; end if;
  perform b2c.require_lead(q.lead_id);
  if p_approve then
    j := b2c.set_stage(q.lead_id, q.to_stage, q.sub_stage, q.comment || coalesce(' (approved: ' || nullif(trim(p_note), '') || ')', ' (approved)'), q.next_due);
  end if;
  update b2c.stage_requests set status = case when p_approve then 'approved' else 'declined' end, decided_by = me, decided_at = now(), decision_note = left(p_note, 300)
   where id = p_request;
  perform b2c.notify(q.requested_by, 'stage_request', case when p_approve then 'Stage change approved' else 'Stage change declined' end,
                     p_note, '/s/leads/' || q.lead_id, q.lead_id, 'stagedec:' || p_request);
  return coalesce(j, '{}'::jsonb) || jsonb_build_object('approved', p_approve);
end $f$;

create or replace function b2c.stage_requests_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_role text := b2c.my_role();
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'lead_id', q.lead_id, 'name', v.name, 'from', fs.name, 'to', ts.name, 'sub_stage', q.sub_stage,
            'comment', q.comment, 'by', u.full_name, 'created_at', q.created_at, 'mine', q.requested_by = me) order by q.created_at), '[]')
    from b2c.stage_requests q join b2c.leads_v v on v.lead_id = q.lead_id
    left join b2c.stages fs on fs.id = q.from_stage left join b2c.stages ts on ts.id = q.to_stage left join b2c.users u on u.user_id = q.requested_by
   where q.status = 'pending' and (q.requested_by = me or (v_role in ('admin', 'sales_head') and b2c.in_my_team(v.owner_id))));
end $f$;

-- ---------- stages and sub-stages (E2, D4) ----------
/* The Admin renames a stage, changes what it requires, or switches it off. Ids and the canonical stage never change
   (they are the contract with the B2B CRM). Each change is kept in the audit log. */
create or replace function b2c.stage_save(p jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); st b2c.stages; v_req jsonb := p -> 'required';
begin
  select * into st from b2c.stages where id = (p ->> 'id')::smallint for update;
  if st.id is null then raise exception 'unknown stage'; end if;
  if p ? 'name' and coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the stage'; end if;
  if v_req is not null and (jsonb_typeof(v_req) <> 'array' or exists (select 1 from jsonb_array_elements_text(v_req) x
        where x not in ('call_attempt', 'contact', 'profile', 'followup', 'programme_shared', 'application', 'checklist', 'enrollment', 'comment'))) then
    raise exception 'unknown requirement';
  end if;
  if p ? 'active' and not (p ->> 'active')::boolean and (st.id in (1, 9, 10) or exists (select 1 from b2c.leads_state s where s.stage_id = st.id and s.status = 'active')) then
    raise exception 'this stage is in use: move its leads first';
  end if;
  update b2c.stages set name = coalesce(nullif(trim(p ->> 'name'), ''), name), required = coalesce(v_req, required),
         reachable_from_any = coalesce((p ->> 'reachable_from_any')::boolean, reachable_from_any), active = coalesce((p ->> 'active')::boolean, active)
   where id = st.id;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'stage_changed', jsonb_build_object('stage', st.id, 'old', to_jsonb(st), 'new', p, 'reason', p ->> 'reason'));
end $f$;

create or replace function b2c.sub_stage_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint := nullif(p ->> 'id', '')::bigint; old b2c.sub_stages;
begin
  if v is null then
    if not exists (select 1 from b2c.stages where id = (p ->> 'stage_id')::smallint) then raise exception 'unknown stage'; end if;
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the sub-stage'; end if;
    if exists (select 1 from b2c.sub_stages where stage_id = (p ->> 'stage_id')::smallint and lower(name) = lower(trim(p ->> 'name'))) then raise exception 'that sub-stage exists'; end if;
    insert into b2c.sub_stages (stage_id, name, rank, returns_to_pool, journey, first_message_days, comment_required, active)
    values ((p ->> 'stage_id')::smallint, trim(p ->> 'name'),
            coalesce((p ->> 'rank')::int, (select coalesce(max(rank), 0) + 10 from b2c.sub_stages where stage_id = (p ->> 'stage_id')::smallint)),
            coalesce((p ->> 'returns_to_pool')::boolean, false), nullif(p ->> 'journey', ''), nullif(p ->> 'first_message_days', '')::int,
            coalesce((p ->> 'comment_required')::boolean, false), true)
    returning id into v;
  else
    select * into old from b2c.sub_stages where id = v for update;
    if old.id is null then raise exception 'unknown sub-stage'; end if;
    if p ? 'name' and trim(p ->> 'name') <> old.name and exists (select 1 from b2c.leads_state s where s.stage_id = old.stage_id and s.sub_stage = old.name and s.status = 'active') then
      raise exception 'leads are in "%": add a new sub-stage and switch this one off instead', old.name;
    end if;
    update b2c.sub_stages set name = coalesce(nullif(trim(p ->> 'name'), ''), name), rank = coalesce((p ->> 'rank')::int, rank),
           returns_to_pool = coalesce((p ->> 'returns_to_pool')::boolean, returns_to_pool),
           journey = case when p ? 'journey' then nullif(p ->> 'journey', '') else journey end,
           first_message_days = case when p ? 'first_message_days' then nullif(p ->> 'first_message_days', '')::int else first_message_days end,
           comment_required = coalesce((p ->> 'comment_required')::boolean, comment_required), active = coalesce((p ->> 'active')::boolean, active)
     where id = v;
  end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'sub_stage_changed', jsonb_build_object('sub_stage', v, 'old', to_jsonb(old), 'new', p));
  return v;
end $f$;

create or replace function b2c.stages_admin() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return jsonb_build_object(
    'stages', (select coalesce(jsonb_agg(to_jsonb(st) || jsonb_build_object('leads', (select count(*) from b2c.leads_state s where s.stage_id = st.id and s.status = 'active'),
                 'sub_stages', (select coalesce(jsonb_agg(to_jsonb(ss) || jsonb_build_object('leads', (select count(*) from b2c.leads_state s where s.stage_id = st.id and s.sub_stage = ss.name and s.status = 'active')) order by ss.rank), '[]')
                                  from b2c.sub_stages ss where ss.stage_id = st.id)) order by st.rank), '[]') from b2c.stages st),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'by', u.full_name, 'action', a.action, 'detail', a.detail) order by a.at desc), '[]')
                  from (select * from b2c.audit_log where action in ('stage_changed', 'sub_stage_changed') order by at desc limit 100) a left join b2c.users u on u.user_id = a.actor_id));
end $f$;

-- ---------- queues (E6) ----------
/* Leads without a counsellor, apart: unassigned (nobody eligible), waiting for working hours, the manual queue. */
create or replace function b2c.queues() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('read_all') or b2c.can('reassign')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select jsonb_build_object(
      'unassigned', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'unassigned'), '[]'),
      'waiting_hours', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'waiting_hours'), '[]'),
      'manual', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'manual'), '[]'))
    from (select jsonb_build_object('lead_id', s.lead_id, 'name', v.name, 'course', v.course, 'hot', s.hot, 'temperature', s.temperature, 'source', v.source,
                   'waiting_since', s.handed_off_at, 'is_test', s.is_test,
                   'queue', case d.outcome when 'manual_queue' then 'manual' when 'waiting_hours' then 'waiting_hours' else 'unassigned' end,
                   'rule', d.rule_name, 'why', d.why, 'eligible', d.eligible, 'decided_at', d.at) x
            from b2c.leads_state s join b2c.leads_v v on v.lead_id = s.lead_id
            left join lateral (select * from b2c.allocation_decisions ad where ad.lead_id = s.lead_id and not ad.simulated order by ad.at desc limit 1) d on true
           where s.status = 'active' and s.owner_id is null and s.deleted_at is null
           order by s.hot desc, s.handed_off_at) q);
end $f$;

/* One click: decide again now (the manual queue included, which the minute timer leaves for a person). */
create or replace function b2c.queue_allocate(p_lead bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('reassign');
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead and status = 'active' and owner_id is null) then raise exception 'this lead already has a counsellor'; end if;
  return b2c.allocate(p_lead, 'manual');
end $f$;

-- ---------- working calendar (E7) ----------
create table if not exists b2c.work_breaks (
  id bigint generated always as identity primary key,
  user_id uuid references b2c.users (user_id),   -- null: everyone
  isodow smallint check (isodow between 1 and 7), -- null: every day
  start_t time not null,
  end_t time not null check (end_t > start_t),
  label text not null default 'Lunch',
  active boolean not null default true
);
alter table b2c.work_breaks enable row level security;

create or replace function b2c.on_break(p_user uuid, p_at timestamptz default now()) returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from b2c.work_breaks b
                  where b.active and (b.user_id is null or b.user_id = p_user)
                    and (b.isodow is null or b.isodow = extract(isodow from (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))))
                    and (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))::time >= b.start_t
                    and (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))::time < b.end_t)
$f$;

create or replace function b2c.breaks_save(p jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); x jsonb; n int := 0;
begin
  if jsonb_typeof(p) <> 'array' then raise exception 'a list of breaks'; end if;
  update b2c.work_breaks set active = false where active;
  for x in select * from jsonb_array_elements(p) loop
    if (x ->> 'end')::time <= (x ->> 'start')::time then raise exception 'a break ends after it starts'; end if;
    insert into b2c.work_breaks (user_id, isodow, start_t, end_t, label)
    values (nullif(x ->> 'user_id', '')::uuid, nullif(x ->> 'isodow', '')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(nullif(trim(x ->> 'label'), ''), 'Break'));
    n := n + 1;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'breaks_changed', jsonb_build_object('breaks', p));
  return n;
end $f$;

/* Holidays from a pasted list or a CSV: [{day, name, kind}]. */
create or replace function b2c.holidays_import(p jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := 0;
begin
  perform b2c.require('settings');
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 200 then raise exception 'at most 200 holidays at a time'; end if;
  for x in select * from jsonb_array_elements(p) loop
    perform b2c.holiday_save((x ->> 'day')::date, coalesce(nullif(trim(x ->> 'name'), ''), 'Holiday'), coalesce(nullif(x ->> 'kind', ''), 'company'));
    n := n + 1;
  end loop;
  return n;
end $f$;

/* The week: each person's hours, leave and overrides per day; holidays; days or hours with nobody on duty. */
create or replace function b2c.calendar_week(p_from date default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 date := coalesce(p_from, date_trunc('week', now() at time zone 'Asia/Kolkata')::date);
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('from', d0, 'days', (
    select jsonb_agg(jsonb_build_object('day', d, 'holiday', (select h.name from b2c.holidays h where h.day = d),
             'people', (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'on_call', u.on_call,
                           'start', w.w_start, 'end', w.w_end,
                           'leave', exists (select 1 from b2c.leaves lv where lv.user_id = u.user_id and d between lv.from_day and lv.to_day),
                           'override', exists (select 1 from b2c.shift_overrides o where o.user_id = u.user_id and o.day = d)) order by u.full_name), '[]')
                          from b2c.users u, lateral b2c.working_window(u.user_id, d) w
                         where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head') and not u.is_test_user),
             'nobody_on_duty', not exists (select 1 from b2c.users u, lateral b2c.working_window(u.user_id, d) w
                                            where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head') and not u.is_test_user and w.w_start is not null))
           order by d)
      from generate_series(d0, d0 + 6, interval '1 day') g(ts), lateral (select g.ts::date d) dd),
    'breaks', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'user_id', b.user_id, 'isodow', b.isodow, 'start', b.start_t, 'end', b.end_t, 'label', b.label)), '[]')
                 from b2c.work_breaks b where b.active));
end $f$;

-- ---------- capacity (E8) ----------
/* Daily: the Admin hears when someone passes the alert share of their monthly cap, and when the team reaches the hiring trigger. */
create or replace function b2c.capacity_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare c jsonb; x jsonb; n int := 0; v_month text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM');
begin
  select jsonb_build_object('rows', jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
           'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ b2c.ist_month((now() at time zone 'Asia/Kolkata')::date)))))
    into c from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user;
  for x in select * from jsonb_array_elements(coalesce(c -> 'rows', '[]')) loop
    if (x ->> 'cap')::numeric > 0 and (x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100 >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
      perform b2c.notify_admins('capacity', (x ->> 'name') || ' is at ' || round((x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100) || '% of their monthly cap',
                                (x ->> 'assigned') || ' of ' || (x ->> 'cap') || ' leads this month', '/w/allocation', null, 'cap:' || (x ->> 'user_id') || ':' || v_month, false);
      n := n + 1;
    end if;
  end loop;
  if (select avg((y ->> 'assigned')::numeric / nullif((y ->> 'cap')::numeric, 0)) from jsonb_array_elements(coalesce(c -> 'rows', '[]')) y) * 100
       >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
    perform b2c.notify_admins('capacity', 'The team is near capacity: time to hire', null, '/w/allocation', null, 'hire:' || v_month, true);
    n := n + 1;
  end if;
  return n;
end $f$;

-- ---------- Teams: the Workspace directory and invitations (E9) ----------
create table if not exists b2c.directory_people (
  email text primary key,
  name text,
  job_title text,
  photo_url text,
  workspace_user_id text,
  suspended boolean not null default false,
  seen_at timestamptz not null default now()
);
alter table b2c.directory_people enable row level security;
alter table b2c.users add column if not exists invite_expires_at timestamptz;
alter table b2c.users add column if not exists first_sign_in_at timestamptz;

/* Every Workspace account the CRM has not been given yet, for one-click adding with a role. */
create or replace function b2c.directory_unadded() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('email', d.email, 'name', d.name, 'job_title', d.job_title, 'photo_url', d.photo_url, 'seen_at', d.seen_at) order by d.name, d.email), '[]')
            from b2c.directory_people d where not d.suspended and d.seen_at > now() - interval '3 days'
             and not exists (select 1 from b2c.users u where u.email = d.email));
end $f$;

/* An invitation is good for 7 days (setting access.invite_days) until the first sign-in. The app checks at sign-in. */
create or replace function b2c.invite_ok(p_email text) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((select u.first_sign_in_at is not null or u.invite_expires_at is null or u.invite_expires_at > now()
                     from b2c.users u where u.email = lower(trim(p_email))), true)
$f$;

create or replace function b2c.invite_sent(p_user uuid) returns timestamptz language plpgsql security definer set search_path = '' as $f$
declare v timestamptz := now() + make_interval(days => coalesce((b2c.setting('access') ->> 'invite_days')::int, 7));
begin
  perform b2c.require('settings');
  update b2c.users set invited_at = now(), invite_expires_at = v, updated_at = now() where user_id = p_user and first_sign_in_at is null;
  return v;
end $f$;

-- ---------- sessions and devices (E10) ----------
insert into b2c.settings (key, value) values ('access', '{"trusted_days": 7, "invite_days": 7}') on conflict (key) do nothing;
alter table b2c.session_checks add column if not exists user_agent text;
alter table b2c.session_checks add column if not exists ip text;
alter table b2c.session_checks add column if not exists last_seen_at timestamptz;
alter table b2c.session_checks add column if not exists revoked_at timestamptz;
alter table b2c.trusted_devices add column if not exists last_used_at timestamptz;

/* A revoked session is signed out of the CRM at its next request. */
create or replace function b2c.my_role() returns text language sql stable security definer set search_path = '' as $f$
  select u.role from b2c.users u
   where u.user_id = b2c.uid() and u.is_active
     and exists (select 1 from b2c.session_checks c where c.session_id = b2c.session_id() and c.user_id = u.user_id and c.revoked_at is null)
$f$;

/* Trusted devices last 7 days (setting access.trusted_days), whatever the code path that created them. */
create or replace function b2c.trusted_device_days() returns trigger language plpgsql set search_path = '' as $f$
begin
  new.expires_at := least(new.expires_at, now() + make_interval(days => coalesce((b2c.setting('access') ->> 'trusted_days')::int, 7)));
  return new;
end $f$;
drop trigger if exists trusted_device_days on b2c.trusted_devices;
create trigger trusted_device_days before insert on b2c.trusted_devices for each row execute function b2c.trusted_device_days();

/* The app notes the browser and address of the current session, and the first sign-in. */
create or replace function b2c.session_note(p_user_agent text, p_ip text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.session_checks set user_agent = coalesce(left(p_user_agent, 300), user_agent), ip = coalesce(left(p_ip, 60), ip), last_seen_at = now()
   where session_id = b2c.session_id() and user_id = b2c.uid();
  update b2c.users set first_sign_in_at = now() where user_id = b2c.uid() and first_sign_in_at is null;
end $f$;

create or replace function b2c.my_devices(p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_user uuid := b2c.uid();
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_user is not null and p_user <> v_user then perform b2c.require('settings'); v_user := p_user; end if;
  return jsonb_build_object(
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object('session_id', c.session_id, 'method', c.method, 'signed_in_at', c.at, 'last_seen_at', c.last_seen_at,
                   'user_agent', c.user_agent, 'ip', c.ip, 'current', c.session_id = b2c.session_id()) order by coalesce(c.last_seen_at, c.at) desc), '[]')
                   from b2c.session_checks c where c.user_id = v_user and c.revoked_at is null and c.at > now() - interval '30 days'),
    'devices', (select coalesce(jsonb_agg(jsonb_build_object('id', left(d.token_hash, 16), 'label', d.label, 'created_at', d.created_at, 'expires_at', d.expires_at,
                   'last_used_at', d.last_used_at) order by d.created_at desc), '[]')
                  from b2c.trusted_devices d where d.user_id = v_user and d.revoked_at is null and d.expires_at > now()));
end $f$;

/* Sign out one session or forget one device (one's own; the Admin anyone's), or everything for a person. */
create or replace function b2c.session_revoke(p_session uuid default null, p_device text default null, p_user uuid default null) returns int
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_user uuid := coalesce(p_user, b2c.uid()); n int := 0; m int;
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_user <> me then perform b2c.require('settings'); end if;
  if p_session is null and p_device is null then
    update b2c.session_checks set revoked_at = now() where user_id = v_user and revoked_at is null and session_id is distinct from case when v_user = me then b2c.session_id() end;
    get diagnostics n = row_count;
    update b2c.trusted_devices set revoked_at = now() where user_id = v_user and revoked_at is null;
    get diagnostics m = row_count;
    n := n + m;
  else
    if p_session is not null then
      update b2c.session_checks set revoked_at = now() where session_id = p_session and user_id = v_user and revoked_at is null;
      get diagnostics n = row_count;
    end if;
    if p_device is not null then
      update b2c.trusted_devices set revoked_at = now() where left(token_hash, 16) = p_device and user_id = v_user and revoked_at is null;
      get diagnostics m = row_count;
      n := n + m;
    end if;
  end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'sign_out_remote', jsonb_build_object('user', v_user, 'session', p_session, 'device', p_device, 'count', n));
  return n;
end $f$;

-- ---------- team and revenue on student_leads (E14) ----------
insert into b2c.settings (key, value) values ('b2b_writes', '{"team_and_revenue": false}') on conflict (key) do nothing;

/* Off until the B2B CRM's write API accepts team_id, expected_net_revenue_inr and realised_net_revenue_inr
   (docs/b2b-developer-notes.md): a refused field would hold back the other changes in the same update. */
create or replace function b2c.write_team_revenue() returns trigger language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint; v_exp numeric; v_real numeric;
begin
  if not coalesce((b2c.setting('b2b_writes') ->> 'team_and_revenue')::boolean, false) then return null; end if;
  if tg_table_name = 'assignments' then
    perform b2c.queue_update(new.lead_id, jsonb_build_object('team_id', (select team from b2c.users where user_id = new.user_id)), false);
  else
    select e.lead_id into v_lead from b2c.enrollments e where e.id = new.enrollment_id;
    select sum(g.net), sum(g.net) filter (where g.realised_at is not null) into v_exp, v_real
      from b2c.earnings g join b2c.enrollments e on e.id = g.enrollment_id where e.lead_id = v_lead;
    perform b2c.queue_update(v_lead, jsonb_build_object('expected_net_revenue_inr', v_exp, 'realised_net_revenue_inr', coalesce(v_real, 0)), false);
  end if;
  return null;
end $f$;
drop trigger if exists write_team on b2c.assignments;
create trigger write_team after insert on b2c.assignments for each row execute function b2c.write_team_revenue();
drop trigger if exists write_revenue on b2c.earnings;
create trigger write_revenue after insert or update of net, realised_at on b2c.earnings for each row execute function b2c.write_team_revenue();

-- ---------- view as Sales for a chosen counsellor (D13) ----------
create or replace function b2c.view_as_sales(p_user uuid, p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); u b2c.users;
begin
  select * into u from b2c.users where user_id = p_user and role in ('counsellor', 'sales_head');
  if u.user_id is null then raise exception 'choose a counsellor'; end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'view_as_sales', jsonb_build_object('as', p_user, 'name', u.full_name));
  return jsonb_build_object('user', jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'role', u.role),
    'leads', b2c.lead_list_as(p || jsonb_build_object('include_test', u.is_test_user), u.user_id, u.role),
    'followups', (select jsonb_build_object('overdue', count(*) filter (where t.due_at < now()), 'today', count(*) filter (where t.due_at >= now() and t.due_at < now() + interval '1 day'))
                    from b2c.tasks t where t.owner_id = p_user and t.status = 'open'));
end $f$;

-- ---------- the assignment message (E4) ----------
/* Witty is still talking to the student: its last message is within the idle wait (read-only: w2_messages belongs to Witty). */
create or replace function b2c.witty_busy(p_lead bigint) returns boolean language plpgsql stable security definer set search_path = '' as $f$
declare v_last timestamptz; v_idle int := coalesce((b2c.setting('messaging') ->> 'witty_idle_minutes')::int, 10);
begin
  if to_regclass('public.w2_messages') is null then return false; end if;
  execute 'select max(m.created_at) from public.w2_messages m where m.phone = $1' into v_last using b2c.wa_phone(p_lead);
  return v_last is not null and v_last > now() - make_interval(mins => v_idle);
end $f$;

/* The assignment message by email: when the student has no WhatsApp the CRM may use, no template, or WhatsApp failed. */
create or replace function b2c.assignment_email(p_lead bigint, p_next timestamptz) returns bigint language plpgsql security definer set search_path = '' as $f$
declare u b2c.users; v_course text; v_assign bigint;
begin
  select * into u from b2c.users where user_id = (select owner_id from b2c.leads_state where lead_id = p_lead);
  if u.user_id is null then return null; end if;
  select coalesce(max(id), 0) into v_assign from b2c.assignments where lead_id = p_lead;
  select coalesce(nullif(course, ''), 'your programme') into v_course from b2c.leads_v where lead_id = p_lead;
  return b2c.queue_system_email(p_lead, 'Your Eduwit counsellor: ' || coalesce(u.full_name, 'Eduwit'),
    'Hi ' || coalesce(b2c.first_name(p_lead), 'there') || ',' || E'\n\n' ||
    'I am ' || coalesce(u.full_name, 'your counsellor') || ' from Eduwit. I will call you ' ||
    case when p_next is not null and p_next > now() + interval '10 minutes' then 'at ' || to_char(p_next at time zone 'Asia/Kolkata', 'HH12:MI am "on" Dy DD Mon') else 'shortly' end ||
    ' about ' || v_course || '.' || coalesce(E'\n' || 'You can also reach me on ' || nullif(u.phone, '') || '.', '') || E'\n\n' || 'Eduwit',
    'assignment', 'assign-mail:' || p_lead || ':' || v_assign);
end $f$;

create or replace function b2c.queue_assignment_message(p_lead bigint, p_user uuid, p_in_hours boolean, p_next timestamptz) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare t b2c.wa_templates; v_wait timestamptz := now(); v_dedupe text; v bigint; v_idle int := coalesce((b2c.setting('messaging') ->> 'witty_idle_minutes')::int, 10);
begin
  v_dedupe := 'assign:' || p_lead || ':' || (select coalesce(max(a.id), 0) from b2c.assignments a where a.lead_id = p_lead);
  if exists (select 1 from b2c.send_queue where dedupe_key = v_dedupe) then return null; end if;
  select * into t from b2c.wa_templates where purpose = case when p_in_hours then 'assignment_hours' else 'assignment_after_hours' end and archived_at is null
   order by status = 'approved' desc, id limit 1;
  if b2c.witty_busy(p_lead) then v_wait := now() + make_interval(mins => v_idle); end if;
  if t.id is not null and b2c.wa_phone(p_lead) is not null then
    v := b2c.enqueue_template(p_lead, t, p_user, 'assignment',
           jsonb_build_object('next_working_time', to_char(coalesce(p_next, now()) at time zone 'Asia/Kolkata', 'HH12:MI am "on" Dy DD Mon')), v_wait, v_dedupe);
  end if;
  if v is null then v := b2c.assignment_email(p_lead, p_next); end if;
  return v;
end $f$;

-- ---------- redefined: pipeline: the sales head sees their team ----------
CREATE OR REPLACE FUNCTION b2c.pipeline_board(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me) and b2c.in_my_team(v.owner_id)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin') or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;

-- ---------- redefined: inbox: the sales head sees their team ----------
CREATE OR REPLACE FUNCTION b2c.inbox_list(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_q text := nullif(trim(p ->> 'search'), ''); v_digits text;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_digits := nullif(regexp_replace(coalesce(v_q, ''), '\D', '', 'g'), '');
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_id', v.owner_id, 'owner_name', v.owner_name,
                              'status', v.status, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'awaiting_reply', coalesce(lm.direction = 'in', false),
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at), 'read_only', v_role = 'marketing',
                              'last', lm.body, 'last_template', lm.template_name, 'last_direction', lm.direction,
                              'match', case when v_q is not null then (select left(m.body, 160) from b2c.wa_messages m where m.phone = c.phone and m.body ilike '%' || v_q || '%' order by m.created_at desc limit 1) end) x
      from b2c.wa_conversations c
      left join b2c.leads_v v on v.lead_id = c.lead_id
      left join lateral (select m.body, m.template_name, m.direction from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc, m.id desc limit 1) lm on true
     where (v_role in ('admin', 'marketing') or (v_role = 'sales_head' and b2c.in_my_team(v.owner_id)) or v.owner_id = me)
       and (v_q is null or v.name ilike '%' || v_q || '%' or (v_digits is not null and c.phone like '%' || v_digits || '%')
            or exists (select 1 from b2c.wa_messages m where m.phone = c.phone and (m.body ilike '%' || v_q || '%' or m.template_name ilike '%' || v_q || '%')))
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
       and (p ->> 'owner' is null or v_role = 'counsellor' or (p ->> 'owner' = 'none' and v.owner_id is null) or v.owner_id::text = p ->> 'owner')
       and (p ->> 'window' is null or (p ->> 'window' = 'open') = coalesce(c.last_inbound_at > now() - interval '24 hours', false))
       and (not coalesce((p ->> 'awaiting')::boolean, false) or lm.direction = 'in')
     order by greatest(c.last_inbound_at, c.last_outbound_at) desc nulls last
     limit least(coalesce((p ->> 'limit')::int, 200), 500)) q);
end $f$;

-- ---------- redefined: sending: the assignment message waits while Witty is still talking to the student (checked at send time) ----------
CREATE OR REPLACE FUNCTION b2c.send_take(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  with c as (select id from b2c.send_queue where status = 'queued' and not_before <= now()
                and not (purpose = 'assignment' and channel = 'whatsapp' and lead_id is not null and b2c.witty_busy(lead_id))
              order by not_before limit p_limit for update skip locked),
  u as (update b2c.send_queue q set status = 'sending', attempts = attempts + 1 from c where q.id = c.id
        returning q.id, q.channel, q.lead_id, q.to_address, q.payload, q.purpose, q.wa_message_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'channel', u.channel, 'lead_id', u.lead_id, 'to', u.to_address, 'payload', u.payload,
                  'purpose', u.purpose, 'wa_message_id', u.wa_message_id,
                  'live', b2c.live(u.channel) and not b2c.is_test_phone(u.to_address) and not coalesce((select s.is_test from b2c.leads_state s where s.lead_id = u.lead_id), false))), '[]')
    into v from u;
  return v;
end $f$;

-- ---------- redefined: sending: a failed assignment WhatsApp falls back to email ----------
CREATE OR REPLACE FUNCTION b2c.send_done(p_results jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
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
    if v_status = 'failed' and q.purpose = 'assignment' and q.channel = 'whatsapp' then
      perform b2c.assignment_email(q.lead_id, null);
    end if;
    if v_status = 'failed' then
      perform b2c.notify_admins('send_failed', 'A message could not be sent', coalesce(r ->> 'error', ''), '/w/connectors', q.lead_id, 'sendfail:' || q.id);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

-- ---------- redefined: allocation: on-call for hot leads outside hours; simulation may include disabled or future rules ----------
CREATE OR REPLACE FUNCTION b2c.decide(p_lead bigint, p_trigger text, p_at timestamp with time zone DEFAULT now(), p_exclude uuid DEFAULT NULL::uuid, p_sim boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare
  f jsonb := b2c.lead_facts(p_lead, p_trigger, p_at);
  s b2c.leads_state; r b2c.allocation_rules; u b2c.users;
  v_hot boolean; v_why text; v_cands jsonb; v_skip jsonb; v_chosen uuid; v_turn int; v_n int; v_i int; v_fb text;
  v_ids uuid[]; v_ok uuid[]; v_match text[]; v_pool text; v_tried jsonb := '[]'::jsonb; v_perf jsonb;
begin
  if f is null then return jsonb_build_object('outcome', 'skipped', 'why', 'unknown lead'); end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_hot := coalesce(s.hot, false) or p_trigger in ('reengaged', 're_enquiry_hot');
  for r in select * from b2c.allocation_rules
             where (enabled and applies_from <= p_at)
                or (p_sim and id = any (coalesce(nullif(current_setting('b2c.sim_rules', true), '')::bigint[], '{}')))
             order by position, id loop
    continue when not b2c.rule_matches(r.condition, f);
    v_pool := coalesce((select p.name from b2c.pools p where p.id = r.pool_id), 'Everyone');
    -- the pool, in a stable order
    select array_agg(x.user_id order by x.pos, x.email) into v_ids from (
      select u2.user_id, coalesce(pm.position, 0) pos, u2.email from b2c.users u2
        left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = u2.user_id
       where (r.pool_id is null or pm.user_id is not null) and u2.user_id is distinct from p_exclude) x;
    v_cands := '[]'; v_skip := '[]'; v_ok := '{}';
    foreach v_chosen in array coalesce(v_ids, '{}') loop
      select * into u from b2c.users where user_id = v_chosen;
      v_why := b2c.ineligible(u, f, p_at, v_hot, p_sim);
      -- skill and territory logics narrow the pool
      if v_why is null and r.logic = 'skill_match' then
        v_match := array(select jsonb_array_elements_text(coalesce(r.params -> 'match', '["language"]')));
        if 'language' = any (v_match) and f ->> 'language' is not null and not exists (select 1 from unnest(u.languages) g where lower(g) = lower(f ->> 'language')) then v_why := 'language'; end if;
        if v_why is null and 'programme' = any (v_match) and f ->> 'course' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'programmes', '[]')) g where lower(f ->> 'course') like '%' || lower(g) || '%') then v_why := 'programme skill'; end if;
        if v_why is null and 'university' = any (v_match) and f ->> 'university' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'universities', '[]')) g where lower(g) = lower(f ->> 'university')) then v_why := 'university skill'; end if;
        if v_why is null and 'level' = any (v_match) and f ->> 'level' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'levels', '[]')) g where lower(g) = lower(f ->> 'level')) then v_why := 'level skill'; end if;
      elsif v_why is null and r.logic = 'territory' then
        if not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'territories', '[]')) g where lower(g) in (lower(f ->> 'city'), lower(f ->> 'state'))) then v_why := 'territory'; end if;
      end if;
      if v_why is null then v_ok := v_ok || v_chosen; v_cands := v_cands || jsonb_build_object('user_id', v_chosen, 'name', u.full_name);
      else v_skip := v_skip || jsonb_build_object('user_id', v_chosen, 'name', u.full_name, 'why', v_why); end if;
    end loop;

    v_chosen := null; v_turn := null;
    if r.logic = 'manual' then
      return jsonb_build_object('outcome', 'manual_queue', 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'manual queue');
    elsif r.logic = 'returning' then
      if coalesce(s.previous_owner_id, s.lost_by_user) = any (v_ok) then v_chosen := coalesce(s.previous_owner_id, s.lost_by_user); end if;
      if v_chosen is null then v_tried := v_tried || jsonb_build_object('rule', r.name, 'why', 'previous counsellor not eligible'); continue; end if;
    elsif cardinality(v_ok) > 0 then
      if r.logic in ('round_robin', 'pinning', 'skill_match', 'territory') then
        v_turn := r.turn;
        if p_sim then
          execute 'select turn from pg_temp.sim_turns where rule_id = $1' into v_turn using r.id;
          v_turn := coalesce(v_turn, r.turn);
        end if;
        v_n := cardinality(v_ids);
        for v_i in 1 .. v_n loop
          if v_ids[((v_turn + v_i) % v_n) + 1] = any (v_ok) then v_chosen := v_ids[((v_turn + v_i) % v_n) + 1]; v_turn := (v_turn + v_i) % v_n; exit; end if;
        end loop;
      elsif r.logic = 'performance' then
        -- B7.3 performance-weighted: each eligible counsellor's share of turns follows their conversion (b2c.perf_weights),
        -- within the floor and cap; the next lead goes to whoever is furthest below their share this month
        v_perf := b2c.perf_weights(v_ok, r.params, p_at);
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce((w.e ->> 'weight')::numeric, 1), 0.01) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join lateral (select e from jsonb_array_elements(v_perf -> 'rows') e where (e ->> 'user_id')::uuid = c.uid) w on true) x
         order by x.score, x.email limit 1;
        select coalesce(jsonb_agg(c || coalesce((select e - 'user_id' - 'name' from jsonb_array_elements(v_perf -> 'rows') e where e ->> 'user_id' = c ->> 'user_id'), '{}')), '[]')
          into v_cands from jsonb_array_elements(v_cands) c;
      elsif r.logic = 'weighted_round_robin' then
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce(pm.weight, uu.weight, 1), 1) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = c.uid) x
         order by x.score, x.email limit 1;
      elsif r.logic = 'least_loaded' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> case when p_sim then 'month' else 'open' end)::int n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      elsif r.logic = 'capacity' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(uu.monthly_cap, 1) n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      end if;
    end if;

    if v_chosen is not null then
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'turn', v_turn, 'hot', v_hot, 'facts', f, 'tried', v_tried)
             || case when v_perf is not null then jsonb_build_object('performance', v_perf - 'rows',
                       'why', format('performance over %s days: team conversion %s%%, shares kept between %s and %s of an equal share',
                                     v_perf ->> 'window_days', round((v_perf ->> 'team_rate')::numeric * 100, 1), v_perf ->> 'floor', v_perf ->> 'cap')) else '{}'::jsonb end;
    end if;
    -- a hot lead outside hours goes to the on-call counsellor, whatever the rule's fallbacks (B7.1)
    if v_hot and cardinality(v_ok) = 0 and exists (select 1 from jsonb_array_elements(v_skip) x where x ->> 'why' = 'off hours') then
      select uu.user_id into v_chosen from b2c.users uu
       where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
         and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
         and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
       order by uu.email limit 1;
      if v_chosen is not null then
        return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                  'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'hot lead outside hours: on call', 'tried', v_tried);
      end if;
    end if;
    -- nobody eligible under this rule: its fallbacks, in order
    v_tried := v_tried || jsonb_build_object('rule', r.name, 'skipped', v_skip);
    for v_fb in select jsonb_array_elements_text(r.fallbacks) loop
      if v_fb = 'next_rule' then exit;
      elsif v_fb = 'on_call' then
        select uu.user_id into v_chosen from b2c.users uu
         where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
           and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
           and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
         order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'on-call fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'admin' then
        select uu.user_id into v_chosen from b2c.users uu where uu.role = 'admin' and uu.is_active and uu.takes_leads and uu.user_id is distinct from p_exclude order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'admin',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'Admin fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'unassigned' then
        return b2c.decide_none(f, v_hot, v_tried, r, v_pool, v_cands, v_skip, p_exclude, p_at);
      end if;
    end loop;
  end loop;
  return b2c.decide_none(f, v_hot, v_tried, null, null, '[]', '[]', p_exclude, p_at);
end $f$;

-- ---------- redefined: allocation: the minute timer leaves the manual queue alone ----------
CREATE OR REPLACE FUNCTION b2c.allocation_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare r record; n int := 0; v_alert int := coalesce((b2c.setting('allocation') ->> 'unassigned_alert_minutes')::int, 5);
begin
  for r in select s.lead_id, s.handed_off_at from b2c.leads_state s
            where s.status = 'active' and s.owner_id is null and s.deleted_at is null
              -- the manual queue waits for a person, unless the rules changed since it was decided
              and not exists (select 1 from (select d.outcome, d.at from b2c.allocation_decisions d where d.lead_id = s.lead_id and not d.simulated order by d.at desc limit 1) d
                               where d.outcome = 'manual_queue' and d.at > coalesce((select max(coalesce(ar.updated_at, ar.created_at)) from b2c.allocation_rules ar), '-infinity'))
            order by s.handed_off_at limit 100 loop
    perform b2c.allocate(r.lead_id, 'retry'); n := n + 1;
    if not exists (select 1 from b2c.leads_state where lead_id = r.lead_id and owner_id is not null)
       and r.handed_off_at < now() - make_interval(mins => v_alert) and b2c.working_now(null, now()) then
      perform b2c.notify_admins('unassigned', 'A sales lead is waiting unassigned', 'Waiting since ' || to_char(r.handed_off_at at time zone 'Asia/Kolkata', 'HH24:MI'),
                                '/w/allocation', r.lead_id, 'unassigned:' || r.lead_id || ':' || to_char(now(), 'YYYYMMDDHH24'));
    end if;
  end loop;
  for r in select lv.id, lv.user_id from b2c.leaves lv
            where lv.mode = 'reassign' and lv.reassigned_at is null and current_date between lv.from_day and lv.to_day
              and (lv.from_day::timestamp at time zone 'Asia/Kolkata') + make_interval(hours => coalesce(lv.reassign_after_hours, 0)) <= now() loop
    perform b2c.allocate(s.lead_id, 'leave', r.user_id) from b2c.leads_state s where s.owner_id = r.user_id and s.status = 'active';
    update b2c.leaves set reassigned_at = now() where id = r.id;
  end loop;
  return jsonb_build_object('retried', n);
end $f$;

-- ---------- redefined: allocation: breaks and lunch take hot leads only ----------
CREATE OR REPLACE FUNCTION b2c.ineligible(u b2c.users, p_facts jsonb, p_at timestamp with time zone, p_hot boolean, p_sim boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare l jsonb; v_test boolean := coalesce((p_facts ->> 'is_test')::boolean, false); a jsonb := b2c.setting('allocation');
begin
  if not u.is_active then return 'inactive'; end if;
  if u.role = 'marketing' then return 'marketing'; end if;
  if u.role = 'admin' and not (u.takes_leads and coalesce((a ->> 'admin_takes_leads')::boolean, true)) then return 'admin does not take leads'; end if;
  if v_test and not (u.is_test_user or u.role = 'admin') then return 'test lead'; end if;
  if not v_test and u.is_test_user then return 'test user'; end if;
  if exists (select 1 from b2c.leaves lv where lv.user_id = u.user_id and b2c.local_day(u.user_id, p_at) between lv.from_day and lv.to_day) then return 'on leave'; end if;
  if u.away_until > p_at then return 'away'; end if;
  l := b2c.load_of(u.user_id, p_at, p_sim);
  if (l ->> 'month')::int >= u.monthly_cap then return 'monthly cap'; end if;
  if u.open_cap is not null and (l ->> 'open')::int >= u.open_cap then return 'open-lead cap'; end if;
  if u.daily_cap is not null and (l ->> 'day')::int >= u.daily_cap then return 'daily cap'; end if;
  if not b2c.working_now(u.user_id, p_at) then
    if p_hot then return 'off hours'; end if;
    if not coalesce((a ->> 'allow_outside_hours_non_hot')::boolean, true) then return 'off hours'; end if;
  end if;
  if not p_hot and b2c.on_break(u.user_id, p_at) then return 'on break'; end if;
  return null;
end $f$;

-- ---------- redefined: capacity: today's intake beside each person's load ----------
CREATE OR REPLACE FUNCTION b2c.capacity()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare m tstzrange := b2c.ist_month((now() at time zone 'Asia/Kolkata')::date); a jsonb := b2c.setting('allocation'); v jsonb;
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]') into v from (
    select jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
             'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ m),
             'open', (select count(*) from b2c.leads_state s where s.owner_id = u.user_id and s.status = 'active' and s.deleted_at is null),
             'enrollments', (select count(*) from b2c.enrollments e where e.counsellor_id = u.user_id and e.status in ('reported', 'verified')
                               and (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') <@ m)) x
      from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user) s;
  return jsonb_build_object('rows', v,
    'today', jsonb_build_object('handed_off', (select count(*) from b2c.leads_state s where s.handed_off_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' and not s.is_test),
                                'assigned', (select count(*) from b2c.assignments g join b2c.leads_state s on s.lead_id = g.lead_id
                                              where g.at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' and not s.is_test),
                                'waiting', (select count(*) from b2c.leads_state s where s.status = 'active' and s.owner_id is null and s.deleted_at is null and not s.is_test)),
    'capacity_alert_pct', coalesce((a ->> 'capacity_alert_pct')::int, 90),
    'hiring_trigger_enrollments', coalesce((a ->> 'hiring_trigger_enrollments')::int, 10),
    'hiring', coalesce((select avg((x ->> 'enrollments')::numeric) from jsonb_array_elements(v) x), 0) >= coalesce((a ->> 'hiring_trigger_enrollments')::int, 10)
              or coalesce((select avg((x ->> 'assigned')::numeric / nullif((x ->> 'cap')::numeric, 0)) from jsonb_array_elements(v) x), 0) * 100 >= coalesce((a ->> 'capacity_alert_pct')::int, 90));
end $f$;

-- ---------- redefined: directory: every Workspace account is kept, for "not yet added" ----------
CREATE OR REPLACE FUNCTION b2c.directory_sync(p_users jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare x jsonb; n int := 0; d int := 0; v_user uuid; r record; moved int := 0; m int;
begin
  for x in select * from jsonb_array_elements(coalesce(p_users, '[]')) loop
    if coalesce(x ->> 'email', '') <> '' then
      insert into b2c.directory_people (email, name, job_title, photo_url, workspace_user_id, suspended, seen_at)
      values (lower(x ->> 'email'), x ->> 'name', x ->> 'job_title', x ->> 'photo_url', x ->> 'id', coalesce((x ->> 'suspended')::boolean, false), now())
      on conflict (email) do update set name = excluded.name, job_title = excluded.job_title, photo_url = excluded.photo_url,
             workspace_user_id = excluded.workspace_user_id, suspended = excluded.suspended, seen_at = now();
    end if;
    update b2c.users set full_name = coalesce(nullif(x ->> 'name', ''), full_name), photo_url = coalesce(nullif(x ->> 'photo_url', ''), photo_url),
           job_title = coalesce(nullif(x ->> 'job_title', ''), job_title), workspace_user_id = coalesce(x ->> 'id', workspace_user_id), synced_at = now()
     where email = lower(x ->> 'email')
    returning user_id into v_user;
    if v_user is null then continue; end if;
    n := n + 1;
    if coalesce((x ->> 'suspended')::boolean, false)
       and exists (select 1 from b2c.users where user_id = v_user and is_active)
       and not ((select role from b2c.users where user_id = v_user) = 'admin'
                and (select count(*) from b2c.users where role = 'admin' and is_active) <= 1) then
      update b2c.users set is_active = false, deactivated_at = now(), on_call = false, updated_at = now() where user_id = v_user;
      update b2c.trusted_devices set revoked_at = now() where user_id = v_user and revoked_at is null;
      m := 0;
      for r in select lead_id from b2c.leads_state where owner_id = v_user and status = 'active' loop
        perform b2c.allocate(r.lead_id, 'deactivated', v_user); m := m + 1;
      end loop;
      perform b2c.log('team.user_deactivated', null, jsonb_build_object('user_id', v_user, 'reason', 'suspended in Google Workspace', 'reassigned', m), 'system');
      d := d + 1; moved := moved + m;
    end if;
    v_user := null;
  end loop;
  perform b2c.sync_set('directory_at', to_jsonb(now()));
  return jsonb_build_object('updated', n, 'deactivated', d, 'reassigned', moved);
end $f$;

-- ---------- redefined: reassign: the sales head within their team ----------
CREATE OR REPLACE FUNCTION b2c.reassign(p_leads bigint[], p_user uuid, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v bigint; n int := 0; v_d bigint;
begin
  perform b2c.require('reassign');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason'; end if;
  if b2c.my_role() = 'sales_head' then
    if exists (select 1 from b2c.leads_state s where s.lead_id = any (p_leads) and not b2c.in_my_team(s.owner_id)) then raise exception 'not your team''s lead' using errcode = '42501'; end if;
    if p_user is not null and not b2c.in_my_team(p_user) then raise exception 'choose someone in your team'; end if;
  end if;
  foreach v in array p_leads loop
    if p_user is null then perform b2c.allocate(v, 'reassign', (select owner_id from b2c.leads_state where lead_id = v));
    else
      if not exists (select 1 from b2c.users where user_id = p_user and is_active and role in ('counsellor', 'sales_head', 'admin')) then raise exception 'not an active counsellor'; end if;
      insert into b2c.allocation_decisions (lead_id, trigger, chosen, outcome, why) values (v, 'reassign', p_user, 'assigned', 'manual: ' || p_reason) returning id into v_d;
      perform b2c.assign(v, p_user, v_d, 'reassign', p_reason);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

-- ---------- redefined: devices: last used ----------
CREATE OR REPLACE FUNCTION b2c.device_trust_check(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_ok boolean;
begin
  if b2c.uid() is null or b2c.session_id() is null or p_token is null then return false; end if;
  select true into v_ok from b2c.trusted_devices d join b2c.users u on u.user_id = d.user_id and u.is_active
   where d.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and d.user_id = b2c.uid()
     and d.revoked_at is null and d.expires_at > now();
  if coalesce(v_ok, false) then
    update b2c.trusted_devices set last_used_at = now() where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
    insert into b2c.session_checks (session_id, user_id, method) values (b2c.session_id(), b2c.uid(), 'trusted_device') on conflict (session_id) do nothing;
  end if;
  return coalesce(v_ok, false);
end $f$;

drop function if exists b2c.simulate(date, date);
CREATE OR REPLACE FUNCTION b2c.simulate(p_from date, p_to date, p_include bigint[] DEFAULT NULL::bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare r record; d jsonb; v_rows jsonb;
begin
  perform b2c.require('settings');
  -- disabled or future rules to try as if they were live
  perform set_config('b2c.sim_rules', coalesce(p_include, '{}')::text, true);
  -- fresh scratch tables, dropped at commit: one simulation per transaction (each RPC call is its own transaction)
  if to_regclass('pg_temp.sim_out') is not null then raise exception 'a simulation already ran in this transaction'; end if;
  create temp table sim_load (user_id uuid, m date, d date, n int) on commit drop;
  create temp table sim_turns (rule_id bigint primary key, turn int) on commit drop;
  create temp table sim_out (lead_id bigint, actual uuid, simulated uuid, outcome text, rule text) on commit drop;
  for r in select s.lead_id, coalesce(a.at, s.handed_off_at) at, a.user_id actual, a.trigger
             from b2c.leads_state s
             left join lateral (select x.at, x.user_id, x.trigger from b2c.assignments x where x.lead_id = s.lead_id order by x.at limit 1) a on true
            where coalesce(a.at, s.handed_off_at) >= p_from and coalesce(a.at, s.handed_off_at) < p_to + 1 and not s.is_test
            order by 2 loop
    d := b2c.decide(r.lead_id, coalesce(r.trigger, 'handoff'), r.at, null, true);
    if d ->> 'outcome' = 'assigned' then
      insert into pg_temp.sim_load values ((d ->> 'chosen')::uuid, date_trunc('month', r.at at time zone 'Asia/Kolkata')::date, (r.at at time zone 'Asia/Kolkata')::date, 1);
      if d ->> 'turn' is not null then
        insert into pg_temp.sim_turns values ((d ->> 'rule_id')::bigint, (d ->> 'turn')::int) on conflict (rule_id) do update set turn = excluded.turn;
      end if;
    end if;
    insert into pg_temp.sim_out values (r.lead_id, r.actual, (d ->> 'chosen')::uuid, d ->> 'outcome', d ->> 'rule_name');
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('user_id', x.uid, 'name', u.full_name, 'actual', x.actual, 'simulated', x.simulated) order by u.full_name), '[]')
    into v_rows
    from (select coalesce(a.uid, s.uid) uid, coalesce(a.n, 0) actual, coalesce(s.n, 0) simulated
            from (select actual uid, count(*) n from pg_temp.sim_out where actual is not null group by 1) a
            full join (select simulated uid, count(*) n from pg_temp.sim_out where simulated is not null group by 1) s on s.uid = a.uid) x
    left join b2c.users u on u.user_id = x.uid;
  return jsonb_build_object('leads', (select count(*) from pg_temp.sim_out), 'unassigned', (select count(*) from pg_temp.sim_out where simulated is null),
                            'by_person', v_rows);
end $f$;

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-capacity') then
    perform cron.schedule('b2c-capacity', '15 4 * * *', 'select b2c.capacity_tick()');
  end if;
end $d$;

-- ---------- grants ----------
grant execute on function b2c.stage_override_request(bigint, smallint, text, text, timestamptz), b2c.stage_override_decide(bigint, boolean, text), b2c.stage_requests_list(),
  b2c.stage_save(jsonb), b2c.sub_stage_save(jsonb), b2c.stages_admin(), b2c.queues(), b2c.queue_allocate(bigint), b2c.breaks_save(jsonb), b2c.holidays_import(jsonb),
  b2c.calendar_week(date), b2c.directory_unadded(), b2c.invite_sent(uuid), b2c.session_note(text, text), b2c.my_devices(uuid), b2c.session_revoke(uuid, text, uuid),
  b2c.view_as_sales(uuid, jsonb), b2c.simulate(date, date, bigint[]), b2c.pipeline_board(jsonb), b2c.inbox_list(jsonb), b2c.capacity(), b2c.reassign(bigint[], uuid, text),
  b2c.device_trust_check(text) to authenticated;
grant execute on function b2c.invite_ok(text), b2c.capacity_tick(), b2c.directory_sync(jsonb) to service_role;
revoke execute on function b2c.invite_ok(text), b2c.capacity_tick(), b2c.witty_busy(bigint), b2c.assignment_email(bigint, timestamptz), b2c.on_break(uuid, timestamptz),
  b2c.write_team_revenue(), b2c.trusted_device_days(), b2c.in_my_team(uuid) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;

-- ===== b43_platform.sql =====
-- B2C CRM b43: completing money, analytics, connectors, templates and platform (docs/completion-gaps.md D5-D12, D14, A12).
-- Staging first. Idempotent.
--   connectors         each connector's last success and last error; one overview (B2B, WhatsApp, Gmail, Claude, telephony) (B17)
--   user_connections   each person's own Gmail by OAuth; tokens sealed by the app, readable only by the service role (B16, B18)
--   metrics            Eduwit stage conversion and time per stage, B2C-created leads, duplicate cascades, suppression by cause,
--                      margin, receivables (B13.2)
--   alerts             metric alerts also by WhatsApp to one's own number (B13.3)
--   commission         the Admin's dashboard by counsellor, status and month, and the run calendar (B11.3)
--   emails             invoices to the university with the PDF; run statements to each counsellor (B11.1, B11.2)
--   guides             screenshots on guide articles (B15)
--   rate limits        counters the public /v1 endpoints check (B18)
--   templates          media headers, import from the WhatsApp account, version history, preview on a test lead,
--                      performance, a block editor for marketing email (B9.2, B9.2a)

-- ---------- connectors (D5) ----------
create table if not exists b2c.connector_status (
  key text primary key,                    -- b2b, whatsapp, gmail_system, gmail_marketing, claude, telephony, directory, calendar
  last_ok_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  detail jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table b2c.connector_status enable row level security;

/* The app's jobs report each call's outcome; detail carries figures such as WhatsApp's quality rating. */
create or replace function b2c.connector_report(p_key text, p_ok boolean, p_detail jsonb default null, p_error text default null) returns void
language sql security definer set search_path = '' as $f$
  insert into b2c.connector_status (key, last_ok_at, last_error_at, last_error, detail, updated_at)
  values (p_key, case when p_ok then now() end, case when not p_ok then now() end, case when not p_ok then left(p_error, 500) end, coalesce(p_detail, '{}'), now())
  on conflict (key) do update set
    last_ok_at = case when p_ok then now() else b2c.connector_status.last_ok_at end,
    last_error_at = case when not p_ok then now() else b2c.connector_status.last_error_at end,
    last_error = case when not p_ok then left(p_error, 500) else b2c.connector_status.last_error end,
    detail = b2c.connector_status.detail || coalesce(p_detail, '{}'), updated_at = now()
$f$;

create or replace function b2c.connectors_overview() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  perform b2c.require('settings');
  return jsonb_build_object(
    'status', (select coalesce(jsonb_object_agg(c.key, to_jsonb(c) - 'key'), '{}') from b2c.connector_status c),
    'b2b', jsonb_build_object(
       'queued', (select count(*) from b2c.outbox where status in ('queued', 'sending')),
       'refused_7d', (select count(*) from b2c.outbox where status in ('refused', 'conflict', 'failed') and done_at > now() - interval '7 days'),
       'last_applied_at', (select max(done_at) from b2c.outbox where status = 'applied')),
    'whatsapp', jsonb_build_object(
       'sent_today', (select count(*) from b2c.wa_messages where direction = 'out' and created_at >= d0 and status in ('sent', 'delivered', 'read')),
       'failed_today', (select count(*) from b2c.wa_messages where direction = 'out' and created_at >= d0 and status = 'failed'),
       'templates', (select jsonb_object_agg(status, n) from (select status, count(*) n from b2c.wa_templates where archived_at is null group by 1) t),
       'last_synced_at', (select max(synced_at) from b2c.wa_templates),
       'staff_template', exists (select 1 from b2c.wa_templates where name = b2c.setting('staff_alerts') ->> 'template' and status = 'approved' and archived_at is null)),
    'gmail', jsonb_build_object(
       'sent_today', (select count(*) from b2c.emails where direction = 'out' and created_at >= d0 and status in ('sent', 'delivered')),
       'marketing_today', (select count(*) from b2c.emails where direction = 'out' and created_at >= d0 and (purpose = 'marketing' or campaign_id is not null or journey_run_id is not null)),
       'allowance', coalesce((b2c.setting('messaging') ->> 'gmail_daily_allowance')::int, 2000),
       'by_user', (select coalesce(jsonb_agg(jsonb_build_object('name', u.full_name, 'sent_today', x.n)), '[]')
                     from (select user_id, count(*) n from b2c.emails where direction = 'out' and created_at >= d0 and user_id is not null group by 1) x
                     join b2c.users u on u.user_id = x.user_id),
       'connections', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from b2c.user_connections where provider = 'gmail' group by 1) c)),
    'claude', jsonb_build_object('spent_today', b2c.ai_spent_today(), 'budget', b2c.setting('ai')));
end $f$;

-- ---------- each person's own Gmail (D6) ----------
create table if not exists b2c.user_connections (
  user_id uuid not null references b2c.users (user_id),
  provider text not null check (provider in ('gmail')),
  account_email text not null,
  scopes text[] not null default '{}',
  token_sealed text,                       -- the refresh token, encrypted by the app (AES-GCM, key in the environment)
  status text not null default 'connected' check (status in ('connected', 'revoked', 'error', 'disconnected')),
  last_ok_at timestamptz,
  last_error text,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);
alter table b2c.user_connections enable row level security;
revoke all on b2c.user_connections from anon, authenticated;

/* After the OAuth callback (service role): the account must be the person's own @eduwit.in mailbox. */
create or replace function b2c.connection_save(p_user uuid, p_provider text, p_email text, p_scopes text[], p_token_sealed text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if lower(trim(p_email)) is distinct from (select lower(email) from b2c.users where user_id = p_user) then raise exception 'connect your own @eduwit.in mailbox'; end if;
  if not ('https://www.googleapis.com/auth/gmail.send' = any (coalesce(p_scopes, '{}'))) then raise exception 'Spark needs permission to send from Gmail'; end if;
  insert into b2c.user_connections (user_id, provider, account_email, scopes, token_sealed, status, last_ok_at, last_error, connected_at, updated_at)
  values (p_user, p_provider, lower(trim(p_email)), p_scopes, p_token_sealed, 'connected', now(), null, now(), now())
  on conflict (user_id, provider) do update set account_email = excluded.account_email, scopes = excluded.scopes, token_sealed = excluded.token_sealed,
         status = 'connected', last_ok_at = now(), last_error = null, connected_at = now(), updated_at = now();
  insert into b2c.audit_log (actor_id, action, detail) values (p_user, 'connection_saved', jsonb_build_object('provider', p_provider, 'scopes', p_scopes));
end $f$;

/* A send or a refresh failed; invalid_grant means the person revoked access in Google: they are told and asked to reconnect. */
create or replace function b2c.connection_mark(p_user uuid, p_provider text, p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_revoked boolean := not p_ok and coalesce(p_error, '') ~* '(invalid_grant|revoked|unauthorized_client)';
begin
  update b2c.user_connections set status = case when p_ok then 'connected' when v_revoked then 'revoked' else 'error' end,
         last_ok_at = case when p_ok then now() else last_ok_at end, last_error = case when p_ok then null else left(p_error, 300) end, updated_at = now()
   where user_id = p_user and provider = p_provider;
  if v_revoked then
    perform b2c.notify(p_user, 'connection', 'Reconnect your Gmail', 'Spark can no longer send from your mailbox.', '/s/me#connections', null,
                       'conn:' || p_user || ':' || to_char(now(), 'YYYYMMDD'));
  end if;
end $f$;

create or replace function b2c.my_connections() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('provider', c.provider, 'account_email', c.account_email, 'status', c.status, 'scopes', c.scopes,
            'last_ok_at', c.last_ok_at, 'last_error', c.last_error, 'connected_at', c.connected_at)), '[]')
            from b2c.user_connections c where c.user_id = b2c.uid());
end $f$;

create or replace function b2c.connection_disconnect(p_provider text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2c.user_connections set status = 'disconnected', token_sealed = null, updated_at = now() where user_id = b2c.uid() and provider = p_provider;
  insert into b2c.audit_log (actor_id, action, detail) values (b2c.uid(), 'connection_removed', jsonb_build_object('provider', p_provider));
end $f$;

/* The sealed token for a send (service role only). */
create or replace function b2c.connection_token(p_user uuid, p_provider text) returns text language sql stable security definer set search_path = '' as $f$
  select token_sealed from b2c.user_connections where user_id = p_user and provider = p_provider and status in ('connected', 'error')
$f$;

-- ---------- more metrics (D7) ----------
insert into b2c.an_sources (key, from_sql, actor_sql, lead_based) values
  ('suppressions', '(select s.*, null::bigint as lead_id from b2c.suppressions s) x', 'x.actor_id', false),
  ('invoices', '(select i.*, (i.issue_date::timestamp at time zone ''Asia/Kolkata'') as issued_at, u.name as university_name, null::bigint as lead_id from b2c.invoices i left join public.catalog_universities u on u.id = i.university_id where i.status not in (''draft'', ''discarded'')) x', 'null::uuid', false)
on conflict (key) do update set from_sql = excluded.from_sql, actor_sql = excluded.actor_sql, lead_based = excluded.lead_based;

insert into b2c.dim_defs (key, label, expr, sources, money, sort) values
  ('suppression_cause', 'Suppression cause', 'x.reason', '{suppressions}', false, 300),
  ('invoice_university', 'University (invoice)', 'x.university_name', '{invoices}', true, 301),
  ('invoice_status', 'Invoice status', 'x.status', '{invoices}', true, 302)
on conflict (key) do update set label = excluded.label, expr = excluded.expr, sources = excluded.sources, money = excluded.money;

insert into b2c.metric_defs (key, label, area, source, agg, date_sql, where_sql, fmt, roles, counts_leads, higher_is_better, description, sort) values
  ('b2c_created', 'Leads created by B2C', 'Intake', 'leads', 'count(*)', 'x.handed_off_at', 'x.source in (''b2c_created'', ''b2c_whatsapp'')', 'count', '{admin,marketing,sales}', true, true,
   'Leads the B2C team created itself (new lead form, WhatsApp from an unknown number)', 200),
  ('duplicate_cascades', 'Duplicate cascades', 'Intake', 'leads', 'count(*)', 'x.handed_off_at', 'x.handoff_reason like ''duplicate%''', 'count', '{admin,marketing}', true, false,
   'Leads handed over because they were already with partners; split by partner', 201),
  ('contact_rate', 'Assigned to contacted', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.contacted_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.assigned_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of assigned leads that were contacted', 202),
  ('counsel_rate', 'Contacted to counselled', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.counselled_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.contacted_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of contacted leads that were counselled', 203),
  ('apply_rate', 'Counselled to applied', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.applied_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.counselled_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of counselled leads that applied', 204),
  ('enrol_rate_applied', 'Applied to enrolled', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.enrolled_on is not null and not x.refunded) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.applied_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of applicants that enrolled', 205),
  ('days_to_contact', 'Days assigned to contacted', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.contacted_at - x.assigned_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.contacted_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time spent before the first contact', 206),
  ('days_to_counsel', 'Days contacted to counselled', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.counselled_at - x.contacted_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.counselled_at is not null and x.contacted_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from first contact to counselling', 207),
  ('days_to_apply', 'Days counselled to applied', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.applied_at - x.counselled_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.applied_at is not null and x.counselled_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from counselling to application', 208),
  ('days_applied_to_enrol', 'Days applied to enrolled', 'Sales funnel', 'leads', 'round(avg(x.enrolled_on - (x.applied_at at time zone ''Asia/Kolkata'')::date)::numeric, 1)', 'x.assigned_at', 'x.enrolled_on is not null and x.applied_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from application to enrolment', 209),
  ('suppressions', 'Suppressions', 'Nurture', 'suppressions', 'count(*)', 'x.at', 'x.lifted_at is null', 'count', '{admin,marketing}', false, false,
   'Numbers and emails that may not be messaged, by cause', 210),
  ('margin', 'Margin after counsellor commission', 'Money', 'leads', 'coalesce(sum(coalesce(x.university_net, 0) - coalesce(x.counsellor_commission, 0)) filter (where x.enrolled_on is not null and not x.refunded), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true,
   'University commission net of GST, less the counsellor commission; split by university', 211),
  ('receivables', 'Receivables', 'Money', 'invoices', 'coalesce(sum(x.gross) filter (where x.status in (''approved'', ''sent'', ''part_paid'') and x.kind = ''invoice''), 0)', 'x.issued_at', null, 'money', '{admin,marketing}', false, false,
   'Invoiced to universities and not yet paid', 212),
  ('overdue_receivables', 'Overdue receivables', 'Money', 'invoices', 'coalesce(sum(x.gross) filter (where x.status in (''approved'', ''sent'', ''part_paid'') and x.kind = ''invoice'' and x.due_on < current_date), 0)', 'x.issued_at', null, 'money', '{admin,marketing}', false, false,
   'Invoices past their due date', 213)
on conflict (key) do update set label = excluded.label, area = excluded.area, source = excluded.source, agg = excluded.agg, date_sql = excluded.date_sql,
  where_sql = excluded.where_sql, fmt = excluded.fmt, roles = excluded.roles, counts_leads = excluded.counts_leads, higher_is_better = excluded.higher_is_better,
  description = excluded.description, sort = excluded.sort;

-- ---------- metric alerts by WhatsApp (D9) ----------
update b2c.settings set value = jsonb_set(value, '{kinds}', (select coalesce(jsonb_agg(distinct k), '[]') from jsonb_array_elements_text(value -> 'kinds' || '["alert"]') k))
 where key = 'staff_alerts' and not (value -> 'kinds') ? 'alert';

create or replace function b2c.alert_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint := nullif(p ->> 'id', '')::bigint; me uuid := b2c.uid(); v_channels text[];
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_channels := coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'channels') x where x in ('push', 'email', 'whatsapp')), '{push}');
  if 'whatsapp' = any (v_channels) then
    if coalesce(b2c.norm_phone((select phone from b2c.users where user_id = me)), '') = '' then raise exception 'add your mobile number in Teams first'; end if;
    update b2c.users set wa_alerts = (select array_agg(distinct k) from unnest(wa_alerts || array['alert']) k) where user_id = me;
  end if;
  if v is null then
    perform b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array(p ->> 'metric'), 'filters', coalesce(p -> 'filters', '[]')));
    insert into b2c.metric_alerts (user_id, name, metric, filters, kind, op, threshold, win, channels)
    values (me, coalesce(nullif(trim(p ->> 'name'), ''), (select label from b2c.metric_defs where key = p ->> 'metric')), p ->> 'metric', coalesce(p -> 'filters', '[]'),
            coalesce(p ->> 'kind', 'threshold'), p ->> 'op', nullif(p ->> 'threshold', '')::numeric, coalesce(p ->> 'win', 'today'), v_channels)
    returning id into v;
  else
    update b2c.metric_alerts set active = coalesce((p ->> 'active')::boolean, active), channels = case when p ? 'channels' then v_channels else channels end
     where id = v and user_id = me;
    if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v;
end $f$;

-- ---------- the Admin's commission dashboard (D10) ----------
create or replace function b2c.commission_dashboard(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_from date := coalesce((p ->> 'from')::date, (date_trunc('month', now() at time zone 'Asia/Kolkata') - interval '11 months')::date);
        v_to date := coalesce((p ->> 'to')::date, (now() at time zone 'Asia/Kolkata')::date); v_test boolean := coalesce((p ->> 'test')::boolean, false);
begin
  if not b2c.can('read_money') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (with l as (
      select l.*, e.enrolled_on, e.university, e.programme, u.full_name counsellor
        from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id left join b2c.users u on u.user_id = l.counsellor_id
       where l.status <> 'void' and l.is_test = v_test and e.enrolled_on between v_from and v_to
         and (p ->> 'counsellor' is null or l.counsellor_id::text = p ->> 'counsellor') and (p ->> 'status' is null or l.status = p ->> 'status'))
    select jsonb_build_object(
      'totals', (select jsonb_build_object('amount', coalesce(sum(amount), 0), 'lines', count(*), 'enrollments', count(distinct enrollment_id)) from l),
      'by_counsellor', (select coalesce(jsonb_agg(jsonb_build_object('counsellor_id', counsellor_id, 'name', counsellor, 'amount', amount, 'lines', n, 'by_status', st, 'enrollment_ids', ids) order by amount desc), '[]')
                          from (select counsellor_id, counsellor, sum(amount) amount, count(*) n, jsonb_object_agg(status, s) st, array_agg(distinct enrollment_id) ids
                                  from (select counsellor_id, counsellor, status, enrollment_id, amount, sum(amount) over (partition by counsellor_id, status) s from l) q
                                 group by 1, 2) c),
      'by_status', (select coalesce(jsonb_object_agg(status, jsonb_build_object('amount', a, 'lines', n)), '{}') from (select status, sum(amount) a, count(*) n from l group by 1) s),
      'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'amount', a, 'lines', n, 'enrollment_ids', ids) order by m), '[]')
                     from (select to_char(enrolled_on, 'YYYY-MM') m, sum(amount) a, count(*) n, array_agg(distinct enrollment_id) ids from l group by 1) s),
      'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'period', r.period, 'status', r.status, 'totals', r.totals, 'approved_at', r.approved_at,
                       'pay_on', (r.period + interval '1 month' + make_interval(days => coalesce((b2c.setting('money') ->> 'commission_pay_day')::int, 10) - 1))::date) order by r.period desc), '[]')
                 from b2c.commission_runs r where r.is_test = v_test and r.period >= v_from - 31),
      'next_run', (date_trunc('month', now() at time zone 'Asia/Kolkata') + interval '1 month' - interval '1 day')::date));
end $f$;

-- ---------- invoices and statements by email (D11) ----------
/* The approved invoice to the university's billing email with the PDF (the app renders it when it sends). */
create or replace function b2c.invoice_send(p_id bigint, p_note text default null) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); i b2c.invoices; b b2c.university_billing; v bigint; v_from text := coalesce(b2c.setting('system_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
begin
  select * into i from b2c.invoices where id = p_id;
  if i.id is null or i.status not in ('approved', 'sent', 'part_paid') then raise exception 'approve the invoice first'; end if;
  select * into b from b2c.university_billing where university_id = i.university_id;
  if coalesce(b.email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'add the university''s billing email first'; end if;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
  values ('email', null, lower(b.email), jsonb_build_object('from', v_from, 'subject', case when i.kind = 'credit_note' then 'Credit note ' else 'Invoice ' end || i.number || ' from Eduwit',
          'text', 'Dear ' || coalesce(b.legal_name, 'Accounts team') || ',' || E'\n\n' || 'Please find attached ' || case when i.kind = 'credit_note' then 'credit note ' else 'invoice ' end
                  || i.number || ' for Rs ' || to_char(i.gross, 'FM99,99,99,999') || coalesce(', due on ' || to_char(i.due_on, 'DD Mon YYYY'), '') || '.'
                  || coalesce(E'\n\n' || nullif(trim(p_note), ''), '') || E'\n\n' || 'Eduwit',
          'html', null, 'marketing', false, 'attachments', jsonb_build_array(jsonb_build_object('kind', 'invoice_pdf', 'invoice_id', i.id))),
          'invoice', 'invoice:' || i.id || ':' || to_char(now(), 'YYYYMMDDHH24MI'))
  returning id into v;
  perform b2c.invoice_mark_sent(p_id);
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'invoice_emailed', jsonb_build_object('invoice', p_id, 'to', b.email));
  return v;
end $f$;

/* Each counsellor's statement for an approved run, to their own mailbox, with the PDF. */
create or replace function b2c.run_statements_send(p_run bigint) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); r b2c.commission_runs; x record; n int := 0; v_from text := coalesce(b2c.setting('system_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
begin
  select * into r from b2c.commission_runs where id = p_run;
  if r.id is null or r.status not in ('approved', 'paid') then raise exception 'approve the run first'; end if;
  for x in select l.counsellor_id, u.email, u.full_name, sum(l.amount) amount from b2c.commission_lines l join b2c.users u on u.user_id = l.counsellor_id
            where l.run_id = p_run and l.status <> 'void' group by 1, 2, 3 loop
    insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
    values ('email', null, x.email, jsonb_build_object('from', v_from, 'subject', 'Your commission statement for ' || to_char(r.period, 'Mon YYYY'),
            'text', 'Hi ' || split_part(coalesce(x.full_name, ''), ' ', 1) || ',' || E'\n\n' || 'Your commission statement for ' || to_char(r.period, 'Mon YYYY')
                    || ' is attached: Rs ' || to_char(x.amount, 'FM99,99,99,999') || '. It is also on the Money page in Spark.' || E'\n\n' || 'Eduwit',
            'html', null, 'marketing', false, 'attachments', jsonb_build_array(jsonb_build_object('kind', 'statement_pdf', 'run_id', p_run, 'user_id', x.counsellor_id))),
            'statement', 'statement:' || p_run || ':' || x.counsellor_id)
    on conflict do nothing;
    n := n + 1;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'statements_emailed', jsonb_build_object('run', p_run, 'counsellors', n));
  return n;
end $f$;

-- ---------- guide screenshots (D12) ----------
alter table b2c.user_guides add column if not exists images jsonb not null default '[]'::jsonb;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2c-guides', 'b2c-guides', false, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

/* Screenshots for an article: [{path, caption}] under guides/; the body shows one with ![caption](image:N). */
create or replace function b2c.guide_images_set(p_id bigint, p_images jsonb) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  if jsonb_typeof(p_images) <> 'array' or jsonb_array_length(p_images) > 12 then raise exception 'at most 12 screenshots'; end if;
  if exists (select 1 from jsonb_array_elements(p_images) x where coalesce(x ->> 'path', '') !~ '^guides/[A-Za-z0-9/_.-]+$') then raise exception 'screenshots are stored under guides/'; end if;
  update b2c.user_guides set images = p_images, updated_at = now(), updated_by = b2c.uid() where id = p_id;
  if not found then raise exception 'unknown article'; end if;
end $f$;

-- ---------- rate limits on the public endpoints (D14) ----------
create table if not exists b2c.rate_hits (
  key text not null,
  bucket timestamptz not null,
  n int not null default 0,
  primary key (key, bucket)
);
alter table b2c.rate_hits enable row level security;

/* One hit for key (e.g. 'v1:handoffs:<ip>') in a fixed window; false when over the limit. Old windows are cleared. */
create or replace function b2c.rate_check(p_key text, p_limit int, p_seconds int default 60) returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_bucket timestamptz := to_timestamp(floor(extract(epoch from now()) / p_seconds) * p_seconds); v int;
begin
  insert into b2c.rate_hits (key, bucket, n) values (left(p_key, 200), v_bucket, 1)
  on conflict (key, bucket) do update set n = b2c.rate_hits.n + 1 returning n into v;
  if random() < 0.01 then
    delete from b2c.rate_hits where bucket < now() - interval '1 hour';
  end if;
  return v <= p_limit;
end $f$;

-- ---------- templates (A12) ----------
alter table b2c.email_templates add column if not exists blocks jsonb;

/* A WhatsApp template header: text, or an image, document or video with a sample link Meta reviews. */
create or replace function b2c.wa_header_ok(p jsonb) returns boolean language sql immutable set search_path = '' as $f$
  select p is null or p = 'null'::jsonb or (
    jsonb_typeof(p) = 'object' and p ->> 'type' in ('text', 'image', 'document', 'video')
    and case when p ->> 'type' = 'text' then coalesce(length(trim(p ->> 'text')), 0) between 1 and 60
             else coalesce(p ->> 'example_url', '') ~ '^https://' end)
$f$;

create or replace function b2c.guard_wa_header() returns trigger language plpgsql set search_path = '' as $f$
begin
  if not b2c.wa_header_ok(new.header) then
    raise exception 'a header is text (at most 60 characters) or an image, document or video with a sample https link';
  end if;
  return new;
end $f$;
drop trigger if exists guard_wa_header on b2c.wa_templates;
create trigger guard_wa_header before insert or update of header on b2c.wa_templates for each row execute function b2c.guard_wa_header();

/* Templates already on the WhatsApp account (the app fetches them from Meta): new ones are added as marketing templates,
   known ones get Meta's status and id. Each change is a new version. */
create or replace function b2c.wa_template_import(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x jsonb; c jsonb; v_body text; v_header jsonb; v_buttons jsonb; v_vars jsonb; t b2c.wa_templates; n_new int := 0; n_upd int := 0; me uuid := b2c.uid();
begin
  if me is not null then perform b2c.require('settings'); end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'a list of templates'; end if;
  for x in select * from jsonb_array_elements(p) loop
    continue when coalesce(x ->> 'name', '') !~ '^[a-z0-9_]+$';
    v_body := null; v_header := null; v_buttons := '[]';
    for c in select * from jsonb_array_elements(coalesce(x -> 'components', '[]')) loop
      if c ->> 'type' = 'BODY' then v_body := c ->> 'text';
      elsif c ->> 'type' = 'HEADER' then
        v_header := case when c ->> 'format' = 'TEXT' then jsonb_build_object('type', 'text', 'text', left(c ->> 'text', 60))
                         else jsonb_build_object('type', lower(c ->> 'format'), 'example_url', coalesce(c -> 'example' -> 'header_handle' ->> 0, 'https://example.com')) end;
      elsif c ->> 'type' = 'BUTTONS' then v_buttons := coalesce(c -> 'buttons', '[]');
      end if;
    end loop;
    continue when v_body is null;
    select coalesce(jsonb_agg('var_' || m[1] order by m[1]::int), '[]') into v_vars from (select distinct regexp_matches(v_body, '\{\{(\d+)\}\}', 'g') m) q;
    select * into t from b2c.wa_templates where name = x ->> 'name' and language = coalesce(x ->> 'language', 'en');
    if t.id is null then
      insert into b2c.wa_templates (name, language, category, audience, body, variables, buttons, header, status, meta_template_id, synced_at, created_by)
      values (x ->> 'name', coalesce(x ->> 'language', 'en'), lower(coalesce(x ->> 'category', 'marketing')), 'marketing', v_body, v_vars, v_buttons, v_header,
              case lower(coalesce(x ->> 'status', '')) when 'approved' then 'approved' when 'rejected' then 'rejected' when 'paused' then 'paused' when 'disabled' then 'disabled' else 'submitted' end, x ->> 'id', now(), me)
      returning * into t;
      n_new := n_new + 1;
    else
      update b2c.wa_templates set status = case lower(coalesce(x ->> 'status', '')) when 'approved' then 'approved' when 'rejected' then 'rejected' when 'paused' then 'paused' when 'disabled' then 'disabled' else 'submitted' end, meta_template_id = coalesce(x ->> 'id', meta_template_id), synced_at = now(),
             body = case when lower(x ->> 'status') = 'approved' then v_body else body end, header = case when lower(x ->> 'status') = 'approved' then v_header else header end,
             version = version + case when body is distinct from v_body and lower(x ->> 'status') = 'approved' then 1 else 0 end, updated_at = now()
       where id = t.id returning * into t;
      n_upd := n_upd + 1;
    end if;
    insert into b2c.template_versions (kind, template_id, version, content, actor_id)
    select 'whatsapp', t.id, t.version, to_jsonb(t), me
     where not exists (select 1 from b2c.template_versions v where v.kind = 'whatsapp' and v.template_id = t.id and v.version = t.version);
  end loop;
  return jsonb_build_object('added', n_new, 'updated', n_upd);
end $f$;

create or replace function b2c.template_history(p_kind text, p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'at', v.at, 'by', u.full_name, 'content', v.content) order by v.version desc, v.at desc), '[]')
            from b2c.template_versions v left join b2c.users u on u.user_id = v.actor_id where v.kind = p_kind and v.template_id = p_id);
end $f$;

/* A template filled from a real test lead (test leads only, so no student's data is shown in the editor). */
create or replace function b2c.template_preview(p_kind text, p_id bigint, p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare t b2c.wa_templates; e b2c.email_templates; v_params jsonb;
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead and is_test) then raise exception 'preview with a test lead'; end if;
  if p_kind = 'whatsapp' then
    select * into t from b2c.wa_templates where id = p_id;
    if t.id is null then raise exception 'unknown template'; end if;
    v_params := b2c.template_params(t, p_lead, b2c.uid(), '{}');
    return jsonb_build_object('header', case when t.header ->> 'type' = 'text' then jsonb_build_object('type', 'text', 'text', b2c.render(t.header ->> 'text', v_params)) else t.header end,
                              'body', b2c.render(t.body, v_params), 'params', v_params, 'buttons', t.buttons);
  end if;
  select * into e from b2c.email_templates where id = p_id;
  if e.id is null then raise exception 'unknown template'; end if;
  return jsonb_build_object('subject', b2c.merge(e.subject, p_lead), 'body', b2c.merge(e.body, p_lead));
end $f$;

/* How each template does: sent, delivered, read or opened, clicked, replied, failed, cost. */
create or replace function b2c.template_performance(p_kind text, p_days int default 90) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind = 'whatsapp' then
    return (select coalesce(jsonb_object_agg(template_id, jsonb_build_object('sent', sent, 'delivered', delivered, 'read', rd, 'failed', failed, 'replied', replied, 'cost', cost)), '{}')
      from (select m.template_id, count(*) filter (where m.status in ('sent', 'delivered', 'read')) sent, count(*) filter (where m.status in ('delivered', 'read')) delivered,
                   count(*) filter (where m.status = 'read') rd, count(*) filter (where m.status = 'failed') failed, coalesce(sum(m.cost_estimate), 0) cost,
                   count(*) filter (where exists (select 1 from b2c.wa_messages i where i.phone = m.phone and i.direction = 'in' and i.created_at > m.created_at
                                                   and i.created_at < m.created_at + interval '7 days')) replied
              from b2c.wa_messages m where m.direction = 'out' and m.template_id is not null and m.created_at > now() - make_interval(days => p_days) group by 1) s);
  end if;
  return (select coalesce(jsonb_object_agg(marketing_template_id, jsonb_build_object('sent', sent, 'opened', opened, 'clicked', clicked, 'bounced', bounced, 'replied', replied)), '{}')
    from (select e.marketing_template_id, count(*) sent, count(*) filter (where e.opened_at is not null) opened, count(*) filter (where e.clicked_at is not null) clicked,
                 count(*) filter (where e.bounced_at is not null) bounced,
                 count(*) filter (where exists (select 1 from b2c.emails i where i.direction = 'in' and i.lead_id = e.lead_id and i.created_at > e.created_at
                                                 and i.created_at < e.created_at + interval '14 days')) replied
            from b2c.emails e where e.direction = 'out' and e.marketing_template_id is not null and e.created_at > now() - make_interval(days => p_days) group by 1) s);
end $f$;

/* Marketing email templates may carry the block editor's layout; body stays the HTML that is sent. */
create or replace function b2c.email_template_m_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_marketing'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.email_templates;
begin
  if coalesce(trim(p ->> 'name'), '') = '' or coalesce(trim(p ->> 'subject'), '') = '' or coalesce(trim(p ->> 'body'), '') = '' then
    raise exception 'a template needs a name, a subject and a text';
  end if;
  if p ? 'blocks' and p -> 'blocks' <> 'null'::jsonb and (jsonb_typeof(p -> 'blocks') <> 'array' or jsonb_array_length(p -> 'blocks') > 60
       or exists (select 1 from jsonb_array_elements(p -> 'blocks') b where b ->> 'type' not in ('heading', 'text', 'image', 'button', 'divider', 'spacer', 'programme'))) then
    raise exception 'unknown block';
  end if;
  if v is null then
    insert into b2c.email_templates (name, language, subject, body, blocks, tags, created_by)
    values (trim(p ->> 'name'), coalesce(p ->> 'language', 'en'), left(p ->> 'subject', 300), left(p ->> 'body', 50000), p -> 'blocks',
            coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'), me)
    returning * into t;
  else
    update b2c.email_templates set name = trim(p ->> 'name'), language = coalesce(p ->> 'language', language), subject = left(p ->> 'subject', 300),
           body = left(p ->> 'body', 50000), blocks = case when p ? 'blocks' then p -> 'blocks' else blocks end,
           tags = case when p ? 'tags' then coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}') else tags end,
           archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
           version = version + 1, updated_at = now()
     where id = v returning * into t;
    if t.id is null then raise exception 'unknown template'; end if;
  end if;
  insert into b2c.template_versions (kind, template_id, version, content, actor_id) values ('email', t.id, t.version, to_jsonb(t), me);
  return t.id;
end $f$;

-- ---------- fixes found while building the screens ----------
-- yes/no filters also work on text fields (flagged is a reason, not a boolean), so older saved views keep working
CREATE OR REPLACE FUNCTION b2c.filter_sql(c jsonb, allowed text[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $f$
declare fld text := c ->> 'field'; op text := c ->> 'op'; val jsonb := c -> 'value'; d0 text := '(date_trunc(''day'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata'')';
begin
  if not fld = any (allowed) then raise exception 'cannot filter on %', fld; end if;
  return case op
    when 'eq' then format('%I::text = %L', fld, val #>> '{}')
    when 'neq' then format('%I::text is distinct from %L', fld, val #>> '{}')
    when 'in' then format('%I::text = any (%L::text[])', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'not_in' then format('not coalesce(%I::text = any (%L::text[]), false)', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'contains' then format('%I::text ilike %L', fld, '%' || (val #>> '{}') || '%')
    when 'gte' then format('%I >= %L', fld, val #>> '{}')
    when 'lte' then format('%I <= %L', fld, val #>> '{}')
    when 'gt' then format('%I > %L', fld, val #>> '{}')
    when 'lt' then format('%I < %L', fld, val #>> '{}')
    when 'between' then format('%I between %L and %L', fld, val ->> 0, val ->> 1)
    when 'is_null' then format('%I is null', fld)
    when 'not_null' then format('%I is not null', fld)
    when 'is_true' then format('coalesce(%I::text, '''') not in ('''', ''false'')', fld)
    when 'is_false' then format('coalesce(%I::text, '''') in ('''', ''false'')', fld)
    when 'lte_now' then format('%I <= now()', fld)
    when 'older_than_days' then format('%I < now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'within_days' then format('%I >= now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'next_days' then format('%I >= now() and %I < now() + make_interval(days => %s)', fld, fld, (val #>> '{}')::int)
    when 'today' then format('%I >= %s and %I < %s + interval ''1 day''', fld, d0, fld, d0)
    when 'this_week' then format('%I >= date_trunc(''week'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'this_month' then format('%I >= date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'last_month' then format('%I >= (date_trunc(''month'', now() at time zone ''Asia/Kolkata'') - interval ''1 month'') at time zone ''Asia/Kolkata'' and %I < date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld, fld)
    when 'has_tag' then format('%L = any (tags)', val #>> '{}')
    when 'not_tag' then format('not (%L = any (coalesce(tags, ''{}'')))', val #>> '{}')
    else 'false' end;
end $f$;

-- an export whose job died part-way is queued again
CREATE OR REPLACE FUNCTION b2c.export_take(p_limit integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  update b2c.exports set status = 'expired', path = null where status = 'ready' and expires_at < now();
  -- a job that died part-way is tried again (at most 3 times)
  update b2c.exports set status = case when attempts >= 3 then 'failed' else 'queued' end, error = coalesce(error, 'the export job stopped part-way')
   where status = 'running' and coalesce(done_at, created_at) < now() - interval '15 minutes' and created_at < now() - interval '15 minutes';
  with t as (select id from b2c.exports where status = 'queued' and attempts < 3 order by id limit p_limit for update skip locked),
       m as (update b2c.exports e set status = 'running', attempts = e.attempts + 1 from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id, 'params', m.params, 'format', m.format)), '[]') into v from m;
  return v;
end $f$;

-- an Analytics drill-down can be exported
CREATE OR REPLACE FUNCTION b2c.export_request(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare me uuid := b2c.require('settings'); v_n int; v bigint; v_fmt text := coalesce(p ->> 'format', 'csv');
begin
  if v_fmt not in ('csv', 'xlsx') then raise exception 'CSV or Excel'; end if;
  v_n := (b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'search', p ->> 'search', 'ids', p -> 'ids', 'drill', p ->> 'drill',
                                           'include_test', p -> 'include_test', 'limit', 1)) ->> 'total')::int;
  if v_n <= 10000 then return jsonb_build_object('inline', true, 'rows', v_n); end if;
  insert into b2c.exports (user_id, params, format) values (me, p - 'format', v_fmt) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'export', jsonb_build_object('job', v, 'rows', v_n, 'format', v_fmt, 'filters', p -> 'filters', 'columns', p -> 'columns'));
  return jsonb_build_object('inline', false, 'job_id', v, 'rows', v_n);
end $f$;

/* The replies that followed a campaign (within 7 days of the send), for the campaign's results. */
create or replace function b2c.campaign_replies(p_campaign bigint, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return (select coalesce(jsonb_agg(x order by x ->> 'at' desc), '[]') from (
    select distinct on (r.id) jsonb_build_object('reply_id', r.id, 'lead_id', r.lead_id, 'name', v.name, 'channel', r.channel, 'text', left(coalesce(r.text, r.button), 300),
             'class', coalesce(r.corrected_class, r.class), 'status', r.status, 'at', r.created_at, 'variant', s.variant) x
      from b2c.campaign_sends s join b2c.replies r on r.lead_id = s.lead_id and r.created_at > s.done_at and r.created_at < s.done_at + interval '7 days'
      left join b2c.leads_v v on v.lead_id = r.lead_id
     where s.campaign_id = p_campaign and s.done_at is not null
     order by r.id, s.done_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q);
end $f$;

-- ---------- grants ----------
grant execute on function b2c.connectors_overview(), b2c.my_connections(), b2c.connection_disconnect(text), b2c.alert_save(jsonb), b2c.commission_dashboard(jsonb),
  b2c.invoice_send(bigint, text), b2c.run_statements_send(bigint), b2c.guide_images_set(bigint, jsonb), b2c.wa_template_import(jsonb), b2c.template_history(text, bigint),
  b2c.template_preview(text, bigint, bigint), b2c.template_performance(text, integer), b2c.email_template_m_save(jsonb), b2c.campaign_replies(bigint, integer) to authenticated;
grant execute on function b2c.connector_report(text, boolean, jsonb, text), b2c.connection_save(uuid, text, text, text[], text), b2c.connection_mark(uuid, text, boolean, text),
  b2c.connection_token(uuid, text), b2c.rate_check(text, integer, integer), b2c.wa_template_import(jsonb) to service_role;
revoke execute on function b2c.connector_report(text, boolean, jsonb, text), b2c.connection_save(uuid, text, text, text[], text), b2c.connection_mark(uuid, text, boolean, text),
  b2c.connection_token(uuid, text), b2c.rate_check(text, integer, integer), b2c.wa_header_ok(jsonb), b2c.guard_wa_header() from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;

-- ===== b44_programme_facets.sql =====
-- B2C CRM b44: the Programme page's filter choices also list the course families (MBA, BBA, BCA…). Staging first. Idempotent.
create or replace function b2c.programme_facets() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'universities', (select coalesce(jsonb_agg(distinct university), '[]') from b2c.programme_cache where active),
    'courses', (select coalesce(jsonb_agg(distinct course), '[]') from b2c.programme_cache where active and course is not null),
    'specializations', (select coalesce(jsonb_agg(distinct specialization), '[]') from b2c.programme_cache where active and specialization is not null),
    'levels', (select coalesce(jsonb_agg(distinct level), '[]') from b2c.programme_cache where active and level is not null),
    'modes', (select coalesce(jsonb_agg(distinct mode), '[]') from b2c.programme_cache where active and mode is not null),
    'intakes', (select coalesce(jsonb_agg(distinct i), '[]') from b2c.programme_cache, unnest(intakes) i where active),
    'fee', (select jsonb_build_object('min', min(coalesce(fee_total, fee_yearly)), 'max', max(coalesce(fee_total, fee_yearly))) from b2c.programme_cache where active),
    'duration', (select jsonb_build_object('min', min(duration_months), 'max', max(duration_months)) from b2c.programme_cache where active));
end $f$;
grant execute on function b2c.programme_facets() to authenticated;
revoke execute on all functions in schema b2c from public, anon;

-- ===== b45_pipeline_test_users.sql =====
-- B2C CRM b45: a test user's pipeline shows their test leads without asking (as the lead list does). Staging first. Idempotent.
CREATE OR REPLACE FUNCTION b2c.pipeline_board(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
        v_test_user boolean := coalesce((select u.is_test_user from b2c.users u where u.user_id = b2c.uid()), false);
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me) and b2c.in_my_team(v.owner_id)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_test_user) or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;
grant execute on function b2c.pipeline_board(jsonb) to authenticated;
revoke execute on all functions in schema b2c from public, anon;
