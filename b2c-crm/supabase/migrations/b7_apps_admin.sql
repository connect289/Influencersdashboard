-- B2C CRM b7: applications, documents and enrolments (B8.8), new leads made in B2C (B4.3), send to partners (B4.2),
-- the Admin's lead tools (B10), Teams (B3.2), the Programme page (B8.9), notifications and the Admin home. Staging first.

create table if not exists b2c.applications (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  university text not null,
  programme text not null,
  application_ref text,                     -- the university's application ID
  status text not null default 'started' check (status in ('started', 'submitted', 'fee_paid', 'under_review', 'accepted', 'rejected', 'withdrawn')),
  fee_amount numeric(12, 2),
  fee_paid numeric(12, 2),
  checklist jsonb not null default '{}'::jsonb,   -- {"Graduation marksheet": "received", "12th marksheet": "pending", …}
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists applications_lead on b2c.applications (lead_id);
create table if not exists b2c.documents (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  application_id bigint references b2c.applications (id),
  kind text not null,
  storage_path text not null,                -- private bucket b2c-documents; signed links only
  file_name text,
  source text not null default 'upload' check (source in ('upload', 'whatsapp', 'email')),
  uploaded_by uuid,
  created_at timestamptz not null default now(),
  removed_at timestamptz
);
create table if not exists b2c.enrollments (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  application_id bigint references b2c.applications (id),
  counsellor_id uuid references b2c.users (user_id),
  university text not null,
  programme text not null,
  fee numeric(12, 2) not null check (fee > 0),
  fee_paid numeric(12, 2) not null default 0,
  enrolled_on date not null,
  proof_path text not null,
  status text not null default 'reported' check (status in ('reported', 'verified', 'refunded', 'cancelled')),
  note text,
  verified_by uuid,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists b2c.created_leads (
  request_id text primary key,
  phone_norm text not null,
  user_id uuid not null references b2c.users (user_id),
  lead_id bigint,
  created_at timestamptz not null default now()
);
create table if not exists b2c.document_checklists (
  university text primary key,              -- '*' = default
  items jsonb not null
);
insert into b2c.document_checklists (university, items) values
  ('*', '["10th marksheet","12th marksheet","Graduation marksheet","Government ID (Aadhaar or PAN)","Passport photo"]')
on conflict (university) do nothing;

do $d$
declare t text;
begin
  foreach t in array array['applications', 'documents', 'enrollments', 'created_leads', 'document_checklists'] loop
    execute format('alter table b2c.%I enable row level security', t);
  end loop;
  grant select on b2c.applications, b2c.documents, b2c.enrollments, b2c.document_checklists to authenticated;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'applications' and policyname = 'who may see') then
    create policy "who may see" on b2c.applications for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.documents for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.enrollments for select to authenticated using ((select b2c.can_see(lead_id)) or counsellor_id = (select b2c.uid()));
    create policy "staff read" on b2c.document_checklists for select to authenticated using ((select b2c.is_staff()));
  end if;
end $d$;

-- ---------- applications and documents ----------
create or replace function b2c.application_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint := (p ->> 'lead_id')::bigint; me uuid := b2c.require_lead(v_lead); v bigint := nullif(p ->> 'id', '')::bigint; s b2c.leads_state; v_first boolean;
        v_list jsonb;
begin
  if coalesce(trim(p ->> 'university'), '') = '' or coalesce(trim(p ->> 'programme'), '') = '' then raise exception 'choose the university and programme'; end if;
  v_first := not exists (select 1 from b2c.applications where lead_id = v_lead);
  select coalesce((select items from b2c.document_checklists where university = p ->> 'university'), (select items from b2c.document_checklists where university = '*')) into v_list;
  if v is null then
    insert into b2c.applications (lead_id, university, programme, application_ref, status, fee_amount, fee_paid, checklist, created_by)
    values (v_lead, p ->> 'university', p ->> 'programme', nullif(trim(p ->> 'application_ref'), ''), coalesce(p ->> 'status', 'started'),
            nullif(p ->> 'fee_amount', '')::numeric, nullif(p ->> 'fee_paid', '')::numeric,
            coalesce(p -> 'checklist', (select jsonb_object_agg(i, 'pending') from jsonb_array_elements_text(v_list) i)), me)
    returning id into v;
  else
    update b2c.applications set university = p ->> 'university', programme = p ->> 'programme', application_ref = nullif(trim(p ->> 'application_ref'), ''),
           status = coalesce(p ->> 'status', status), fee_amount = nullif(p ->> 'fee_amount', '')::numeric, fee_paid = nullif(p ->> 'fee_paid', '')::numeric,
           checklist = coalesce(p -> 'checklist', checklist), updated_at = now()
     where id = v and lead_id = v_lead;
  end if;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (v_lead, 'application', 'Application ' || coalesce(p ->> 'status', 'started') || ': ' || (p ->> 'university') || ' · ' || (p ->> 'programme'), jsonb_build_object('application_id', v), me);
  select * into s from b2c.leads_state where lead_id = v_lead;
  -- B5.2: recording an application moves the lead to Applicant
  if coalesce(s.stage_id, 1) < 7 then
    update b2c.leads_state set stage_id = 7, sub_stage = case coalesce(p ->> 'status', 'started') when 'started' then 'Application started'
                                                                 when 'fee_paid' then 'Application fee paid' else 'Application submitted' end,
           stage_changed_at = now(), last_activity_at = now() where lead_id = v_lead;
  end if;
  perform b2c.queue_update(v_lead, jsonb_strip_nulls(jsonb_build_object('application_id', nullif(trim(p ->> 'application_ref'), ''),
            'application_status', coalesce(p ->> 'status', 'started'), 'applied_at', case when v_first then now() end,
            'fee_amount_inr', nullif(p ->> 'fee_amount', '')::numeric, 'fee_paid_inr', nullif(p ->> 'fee_paid', '')::numeric))
            || case when coalesce(s.stage_id, 1) < 7 then jsonb_build_object('stage', 'applied', 'b2c_stage', 'Applicant', 'stage_changed_at', now(),
                    'b2c_sub_stage', (select sub_stage from b2c.leads_state where lead_id = v_lead), 'sub_stage', (select sub_stage from b2c.leads_state where lead_id = v_lead)) else '{}'::jsonb end, false);
  return v;
end $f$;

create or replace function b2c.document_add(p_lead bigint, p_application bigint, p_kind text, p_path text, p_name text, p_source text default 'upload') returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v bigint;
begin
  if p_path !~ ('^leads/' || p_lead || '/') then raise exception 'documents are stored under the lead''s folder'; end if;
  insert into b2c.documents (lead_id, application_id, kind, storage_path, file_name, source, uploaded_by)
  values (p_lead, p_application, p_kind, p_path, p_name, coalesce(p_source, 'upload'), me) returning id into v;
  if p_application is not null then
    update b2c.applications set checklist = checklist || jsonb_build_object(p_kind, 'received'), updated_at = now() where id = p_application and lead_id = p_lead;
  end if;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id) values (p_lead, 'application', 'Document received: ' || p_kind, jsonb_build_object('document_id', v), me);
  return v;
end $f$;

-- ---------- enrolment (B8.8) and the Admin's verification ----------
create or replace function b2c.enrollment_record(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint := (p ->> 'lead_id')::bigint; me uuid := b2c.require_lead(v_lead); v bigint; v_sub text; s b2c.leads_state;
begin
  if nullif(p ->> 'fee', '') is null or nullif(p ->> 'enrolled_on', '') is null or coalesce(p ->> 'proof_path', '') = '' then
    raise exception 'an enrolment needs the fee amount, the enrolment date and the proof';
  end if;
  select * into s from b2c.leads_state where lead_id = v_lead;
  insert into b2c.enrollments (lead_id, application_id, counsellor_id, university, programme, fee, fee_paid, enrolled_on, proof_path, note)
  values (v_lead, nullif(p ->> 'application_id', '')::bigint, coalesce(s.owner_id, me), p ->> 'university', p ->> 'programme', (p ->> 'fee')::numeric,
          coalesce(nullif(p ->> 'fee_paid', '')::numeric, 0), (p ->> 'enrolled_on')::date, p ->> 'proof_path', p ->> 'note')
  returning id into v;
  v_sub := case when coalesce(nullif(p ->> 'fee_paid', '')::numeric, 0) >= (p ->> 'fee')::numeric then 'Fee paid (full)' else 'Fee paid (partial)' end;
  update b2c.leads_state set stage_id = 9, sub_stage = v_sub, stage_changed_at = now(), last_activity_at = now() where lead_id = v_lead;
  update b2c.tasks set status = 'done', done_at = now(), outcome = 'enrolled' where lead_id = v_lead and status = 'open';
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (v_lead, 'enrollment', 'Enrolled: ' || (p ->> 'university') || ' · ' || (p ->> 'programme') || ' · fee ₹' || (p ->> 'fee'), jsonb_build_object('enrollment_id', v), me);
  perform b2c.queue_update(v_lead, jsonb_build_object('stage', 'enrolled', 'sub_stage', v_sub, 'b2c_stage', 'Enrolled', 'b2c_sub_stage', v_sub, 'stage_changed_at', now(),
            'enrollment_status', 'reported', 'enrolled_program', p ->> 'programme', 'enrolled_university', p ->> 'university',
            'enrollment_date', p ->> 'enrolled_on', 'fee_amount_inr', (p ->> 'fee')::numeric, 'fee_paid_inr', coalesce(nullif(p ->> 'fee_paid', '')::numeric, 0),
            'next_task_due_at', null), false);
  perform b2c.queue_event('b2ccrm.enrolled', v_lead, jsonb_build_object('programme', p ->> 'programme', 'university', p ->> 'university', 'enrolled_at', p ->> 'enrolled_on'), false);
  perform b2c.notify_admins('enrollment', 'Enrolment to verify', (p ->> 'university') || ' · ' || (p ->> 'programme'), '/w/enrollments', v_lead, 'enrol:' || v);
  return v;
end $f$;

create or replace function b2c.enrollment_verify(p_id bigint, p_ok boolean, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); e b2c.enrollments;
begin
  select * into e from b2c.enrollments where id = p_id for update;
  if e.id is null or e.status <> 'reported' then raise exception 'this enrolment is not waiting for verification'; end if;
  if p_ok then
    update b2c.enrollments set status = 'verified', verified_by = me, verified_at = now(), note = coalesce(p_note, note), updated_at = now() where id = p_id;
    update b2c.leads_state set sub_stage = 'Verified by Admin', stage_changed_at = now(), status = 'closed', closed_at = now(), closed_reason = 'enrolled' where lead_id = e.lead_id;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id) values (e.lead_id, 'enrollment', 'Enrolment verified by the Admin', jsonb_build_object('enrollment_id', p_id), me);
    perform b2c.queue_update(e.lead_id, jsonb_build_object('stage', 'verified', 'sub_stage', 'Verified by Admin', 'b2c_sub_stage', 'Verified by Admin',
              'stage_changed_at', now(), 'enrollment_status', 'verified', 'enrollment_verified_at', now()), false);
    perform b2c.notify(e.counsellor_id, 'enrollment_verified', 'Enrolment verified', e.university || ' · ' || e.programme, '/s/me', e.lead_id, 'verified:' || p_id);
  else
    if length(coalesce(trim(p_note), '')) < 3 then raise exception 'say what is missing'; end if;
    update b2c.enrollments set note = p_note, updated_at = now() where id = p_id;
    insert into b2c.activities (lead_id, kind, body, actor_id) values (e.lead_id, 'enrollment', 'Enrolment sent back: ' || p_note, me);
    perform b2c.notify(e.counsellor_id, 'enrollment_returned', 'Enrolment proof sent back', p_note, '/s/leads/' || e.lead_id, e.lead_id, null);
  end if;
end $f$;

-- ---------- new leads made in B2C (B4.3) ----------
/* The app has already looked the phone up in the B2B CRM (contract §3.3). p_existing = that answer for this phone:
   null (new), or {lead_id, held_by_b2c, holder}. */
create or replace function b2c.new_lead(p jsonb, p_existing jsonb default null) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); v_phone text := b2c.norm_phone(p ->> 'phone'); v_lead bigint := nullif(p_existing ->> 'lead_id', '')::bigint;
        s b2c.leads_state; v_req text;
begin
  if v_phone is null or length(v_phone) not between 11 and 13 then raise exception 'enter a valid phone number'; end if;
  if v_lead is not null then
    select * into s from b2c.leads_state where lead_id = v_lead;
    if s.lead_id is null or not coalesce((p_existing ->> 'held_by_b2c')::boolean, false) then
      return jsonb_build_object('outcome', 'with_partner', 'holder', p_existing -> 'holder');      -- "Already with {partner} since {date}"
    elsif s.status = 'pool' then
      update b2c.leads_state set status = 'active', hot = true, reengaged_at = now(), reengage_trigger = 'walk_in', journey = null where lead_id = v_lead;
      perform b2c.assign(v_lead, me, null, 'reengaged', 'came back to ' || coalesce((select full_name from b2c.users where user_id = me), 'a counsellor'));
      return jsonb_build_object('outcome', 'reengaged', 'lead_id', v_lead);
    elsif s.owner_id is not null and s.owner_id <> me then
      return jsonb_build_object('outcome', 'with_counsellor', 'lead_id', v_lead, 'owner', (select full_name from b2c.users where user_id = s.owner_id));
    else
      return jsonb_build_object('outcome', 'yours', 'lead_id', v_lead);
    end if;
  end if;
  v_req := 'b2c-in-' || v_phone || '-' || to_char(now(), 'YYYYMMDDHH24MI');
  insert into b2c.created_leads (request_id, phone_norm, user_id) values (v_req, v_phone, me) on conflict (request_id) do nothing;
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
  values ('intake', null, v_req, jsonb_strip_nulls(jsonb_build_object('phone', v_phone, 'lead_source', 'b2c_created', 'name', p ->> 'name', 'email', p ->> 'email',
          'course', p ->> 'course', 'city', p ->> 'city', 'other_courses', p -> 'other_courses', 'notes', p ->> 'notes', 'consent_text_version', p ->> 'consent_text_version')), true)
  on conflict (request_id) do nothing;
  return jsonb_build_object('outcome', 'requested', 'request_id', v_req);
end $f$;

-- ---------- send to partner routing (B4.2, contract §3.2) ----------
create or replace function b2c.route_to_partners(p_leads bigint[], p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint; s b2c.leads_state; r jsonb; v_ok int := 0; v_refused jsonb := '[]'::jsonb;
begin
  if length(coalesce(trim(p_reason), '')) not between 3 and 300 then raise exception 'give a reason (3 to 300 characters)'; end if;
  foreach v in array p_leads loop
    select * into s from b2c.leads_state where lead_id = v;
    select record into r from b2c.lead_records where lead_id = v;
    if s.lead_id is null or s.status = 'closed' then v_refused := v_refused || jsonb_build_object('lead_id', v, 'why', 'not held by B2C');
    elsif s.partner_bar_reason is not null or r -> 'allocation' ->> 'partner_bar_reason' is not null then v_refused := v_refused || jsonb_build_object('lead_id', v, 'why', 'partner-barred');
    elsif coalesce(r -> 'consent' ->> 'state', 'none') <> 'given' then v_refused := v_refused || jsonb_build_object('lead_id', v, 'why', 'no partner-sharing consent');
    elsif s.routing_requested_at is not null then v_refused := v_refused || jsonb_build_object('lead_id', v, 'why', 'already routing');
    else
      insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
      values ('route', v, 'b2c-r-' || gen_random_uuid(), jsonb_build_object('reason', trim(p_reason)), true);
      update b2c.leads_state set routing_requested_at = now() where lead_id = v;
      insert into b2c.activities (lead_id, kind, body, actor_id) values (v, 'system', 'Sent to partner routing: ' || trim(p_reason), me);
      v_ok := v_ok + 1;
    end if;
  end loop;
  return jsonb_build_object('sent', v_ok, 'refused', v_refused);
end $f$;

/* After B2B answers an outbox item: routing results and new-lead ids. */
create or replace function b2c.outbox_after(p_id bigint, p_ok boolean) returns void language plpgsql security definer set search_path = '' as $f$
declare o b2c.outbox; v_res jsonb;
begin
  select * into o from b2c.outbox where id = p_id;
  if o.kind = 'route' then
    v_res := coalesce(o.answer -> 'result', o.answer);
    if not p_ok or coalesce(v_res ->> 'destination', '') <> 'partner' then
      update b2c.leads_state set routing_requested_at = null where lead_id = o.lead_id;
      insert into b2c.activities (lead_id, kind, body, meta) values (o.lead_id, 'system',
        case when p_ok then 'No partner took it: stays in B2C' else 'Partner routing refused: ' || coalesce(o.answer ->> 'error_code', o.answer ->> 'error', '?') end, coalesce(o.answer, '{}'));
      perform b2c.notify_admins('routing', case when p_ok then 'No partner took the lead' else 'Partner routing refused' end,
                                coalesce(o.answer ->> 'error', ''), '/w/leads/' || o.lead_id, o.lead_id, 'route:' || o.id);
    end if;
  elsif o.kind = 'intake' and p_ok then
    update b2c.created_leads set lead_id = coalesce((o.answer ->> 'lead_id')::bigint, (o.answer -> 'result' ->> 'lead_id')::bigint) where request_id = o.request_id;
  end if;
end $f$;

-- ---------- Admin lead tools (B10) ----------
create or replace function b2c.lead_delete(p_leads bigint[], p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint; n int := 0; v_kept jsonb := '[]'::jsonb;
begin
  if p_reason not in ('junk', 'test', 'duplicate entry', 'spam', 'student request') then raise exception 'choose a reason: junk, test, duplicate entry, spam or student request'; end if;
  foreach v in array p_leads loop
    if exists (select 1 from b2c.enrollments e where e.lead_id = v and e.status in ('reported', 'verified')) then
      v_kept := v_kept || jsonb_build_object('lead_id', v, 'why', 'has an enrolment: close it instead'); continue;
    end if;
    update b2c.leads_state set deleted_at = now(), delete_reason = p_reason, journey = null, updated_at = now() where lead_id = v and deleted_at is null;
    if found then
      update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'deleted' where lead_id = v and status = 'open';
      update b2c.send_queue set status = 'cancelled' where lead_id = v and status = 'queued';
      insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'delete', v, jsonb_build_object('reason', p_reason));
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('deleted', n, 'kept', v_kept);
end $f$;

create or replace function b2c.lead_restore(p_leads bigint[]) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); n int;
begin
  update b2c.leads_state set deleted_at = null, delete_reason = null, updated_at = now()
   where lead_id = any (p_leads) and deleted_at > now() - interval '30 days';
  get diagnostics n = row_count;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'restore', jsonb_build_object('leads', p_leads));
  return n;
end $f$;

create or replace function b2c.tag(p_leads bigint[], p_tag text, p_add boolean) returns int language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  perform b2c.require('tags');
  if coalesce(trim(p_tag), '') = '' then raise exception 'name the tag'; end if;
  update b2c.leads_state set tags = case when p_add then array(select distinct unnest(tags || array[lower(trim(p_tag))])) else array_remove(tags, lower(trim(p_tag))) end,
         updated_at = now() where lead_id = any (p_leads);
  get diagnostics n = row_count;
  return n;
end $f$;

/* Phone reveals, Call taps, exports and "view as Sales" are logged (B3.1, B8.4, B10.5). */
create or replace function b2c.audit(p_action text, p_lead bigint default null, p_detail jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  if p_action not in ('phone_reveal', 'export', 'view_as_sales', 'contact_copy') then raise exception 'unknown audit action'; end if;
  if p_action = 'export' then perform b2c.require('settings'); end if;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (b2c.uid(), p_action, p_lead, coalesce(p_detail, '{}'));
end $f$;

-- ---------- Teams (B3.2) ----------
/* The Admin gives an @eduwit.in account a role (the app creates the Auth identity first when it does not exist). */
create or replace function b2c.user_save(p jsonb) returns uuid language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v uuid := (p ->> 'user_id')::uuid; v_email text := lower(trim(p ->> 'email'));
begin
  if v_email !~ '@eduwit\.in$' then raise exception 'only @eduwit.in accounts'; end if;
  if v is null or not exists (select 1 from auth.users u where u.id = v and lower(u.email) = v_email) then raise exception 'unknown account'; end if;
  insert into b2c.users (user_id, email, full_name, role, is_active, phone, languages, skills, weight, monthly_cap, open_cap, daily_cap, monthly_target,
                         takes_leads, on_call, job_title, photo_url, workspace_user_id, is_test_user, invited_at, actor_id)
  values (v, v_email, p ->> 'full_name', coalesce(p ->> 'role', 'counsellor'), coalesce((p ->> 'is_active')::boolean, true), p ->> 'phone',
          coalesce(array(select jsonb_array_elements_text(p -> 'languages')), '{}'), coalesce(p -> 'skills', '{}'), coalesce((p ->> 'weight')::int, 1),
          coalesce((p ->> 'monthly_cap')::int, 200), (p ->> 'open_cap')::int, (p ->> 'daily_cap')::int, coalesce(p -> 'monthly_target', '{}'),
          coalesce((p ->> 'takes_leads')::boolean, true), coalesce((p ->> 'on_call')::boolean, false), p ->> 'job_title', p ->> 'photo_url',
          p ->> 'workspace_user_id', coalesce((p ->> 'is_test_user')::boolean, false), now(), me)
  on conflict (user_id) do update set
    full_name = coalesce(excluded.full_name, b2c.users.full_name), role = coalesce(p ->> 'role', b2c.users.role),
    is_active = coalesce((p ->> 'is_active')::boolean, b2c.users.is_active), phone = coalesce(p ->> 'phone', b2c.users.phone),
    languages = case when p ? 'languages' then excluded.languages else b2c.users.languages end,
    skills = case when p ? 'skills' then excluded.skills else b2c.users.skills end,
    weight = coalesce((p ->> 'weight')::int, b2c.users.weight), monthly_cap = coalesce((p ->> 'monthly_cap')::int, b2c.users.monthly_cap),
    open_cap = case when p ? 'open_cap' then excluded.open_cap else b2c.users.open_cap end,
    daily_cap = case when p ? 'daily_cap' then excluded.daily_cap else b2c.users.daily_cap end,
    monthly_target = case when p ? 'monthly_target' then excluded.monthly_target else b2c.users.monthly_target end,
    takes_leads = coalesce((p ->> 'takes_leads')::boolean, b2c.users.takes_leads), on_call = coalesce((p ->> 'on_call')::boolean, b2c.users.on_call),
    job_title = coalesce(excluded.job_title, b2c.users.job_title), photo_url = coalesce(excluded.photo_url, b2c.users.photo_url),
    is_test_user = coalesce((p ->> 'is_test_user')::boolean, b2c.users.is_test_user), updated_at = now(), actor_id = me;
  if v = me and coalesce(p ->> 'role', 'admin') <> 'admin' then raise exception 'you cannot remove your own Admin role'; end if;
  perform b2c.log('team.user_saved', null, jsonb_build_object('user_id', v, 'role', p ->> 'role'));
  return v;
end $f$;

/* Deactivation: signed out (the app revokes sessions), trusted devices revoked, open leads reassigned by the rules (B3.2, B7.5). */
create or replace function b2c.user_deactivate(p_user uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); r record; n int := 0;
begin
  if p_user = me then raise exception 'you cannot deactivate yourself'; end if;
  update b2c.users set is_active = false, deactivated_at = now(), on_call = false, updated_at = now(), actor_id = me where user_id = p_user;
  update b2c.trusted_devices set revoked_at = now() where user_id = p_user and revoked_at is null;
  for r in select lead_id from b2c.leads_state where owner_id = p_user and status = 'active' loop
    perform b2c.allocate(r.lead_id, 'deactivated', p_user); n := n + 1;
  end loop;
  perform b2c.log('team.user_deactivated', null, jsonb_build_object('user_id', p_user, 'reason', p_reason, 'reassigned', n));
  return jsonb_build_object('reassigned', n);
end $f$;

/* Workspace directory sync (service role): name, photo, title stay current; a suspended account is deactivated. */
create or replace function b2c.directory_sync(p_users jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := 0; d int := 0;
begin
  for x in select * from jsonb_array_elements(coalesce(p_users, '[]')) loop
    update b2c.users set full_name = coalesce(x ->> 'name', full_name), photo_url = coalesce(x ->> 'photo_url', photo_url), job_title = coalesce(x ->> 'job_title', job_title),
           workspace_user_id = coalesce(x ->> 'id', workspace_user_id), synced_at = now()
     where email = lower(x ->> 'email');
    if found then n := n + 1; end if;
    if coalesce((x ->> 'suspended')::boolean, false) then
      update b2c.users set is_active = false, deactivated_at = now() where email = lower(x ->> 'email') and is_active;
      if found then d := d + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('updated', n, 'deactivated', d);
end $f$;

create or replace function b2c.team() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_all') and not b2c.can('settings') then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('user', to_jsonb(u) - 'invite_token_hash' - 'push_subscription',
            'load', b2c.load_of(u.user_id, now(), false), 'working_now', b2c.working_now(u.user_id, now()),
            'patterns', (select coalesce(jsonb_agg(jsonb_build_object('isodow', w.isodow, 'start', w.start_t, 'end', w.end_t) order by w.isodow), '[]') from b2c.work_patterns w where w.user_id = u.user_id),
            'leave', (select coalesce(jsonb_agg(to_jsonb(l) order by l.from_day), '[]') from b2c.leaves l where l.user_id = u.user_id and l.to_day >= current_date),
            'enrolled_month', (select count(*) from b2c.enrollments e where e.counsellor_id = u.user_id and e.created_at >= date_trunc('month', now()) and e.status in ('reported', 'verified')),
            'calls_today', (select count(*) from b2c.calls c where c.user_id = u.user_id and c.logged_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'))
          order by u.role, u.full_name), '[]') from b2c.users u);
end $f$;

-- ---------- the Programme page (B8.9): over the catalogue until B2B publishes catalog.* (Addendum 4 §6) ----------
create or replace function b2c.programme_search(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare q text := nullif(trim(p ->> 'q'), '');
begin
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  return (select jsonb_build_object('total', count(*) over (), 'rows', coalesce(jsonb_agg(x order by x ->> 'university', x ->> 'name'), '[]')) from (
    select jsonb_build_object('id', pr.id, 'name', coalesce(pr.program_name, pr.course), 'course', pr.course, 'specialization', pr.specialization, 'level', pr.level,
             'mode', pr.mode, 'university', un.name, 'university_short', un.short_name, 'accreditation', un.accreditation_text, 'recognitions', to_jsonb(un.recognitions),
             'fee_yearly', pr.fee_yearly, 'fee_semester', pr.fee_semester, 'fee_total', pr.fee_total, 'fee_exam', pr.fee_exam, 'fee_registration', pr.fee_registration,
             'min_qualification', pr.min_qualification, 'min_pct', pr.min_pct_general, 'eligibility', pr.eligibility_text, 'brochure_url', pr.brochure_url) x
      from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
     where pr.active
       and (q is null or pr.search_doc @@ websearch_to_tsquery('simple', q) or coalesce(pr.program_name, pr.course) ilike '%' || q || '%' or un.name ilike '%' || q || '%')
       and (p ->> 'level' is null or pr.level ilike p ->> 'level')
       and (p ->> 'mode' is null or pr.mode ilike p ->> 'mode')
       and (p ->> 'university' is null or un.name ilike '%' || (p ->> 'university') || '%')
       and (p ->> 'fee_max' is null or coalesce(pr.fee_total, pr.fee_yearly) <= (p ->> 'fee_max')::numeric)
       and (p ->> 'fee_min' is null or coalesce(pr.fee_total, pr.fee_yearly) >= (p ->> 'fee_min')::numeric)
     limit least(coalesce((p ->> 'limit')::int, 100), 300)) s);
end $f$;

-- ---------- notifications, Admin home ----------
create or replace function b2c.notifications_mine(p_limit int default 30) returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('unread', (select count(*) from b2c.notifications n where n.user_id = b2c.uid() and n.read_at is null),
    'items', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]') from (select * from b2c.notifications n where n.user_id = b2c.uid() order by n.created_at desc limit p_limit) n))
$f$;
create or replace function b2c.notifications_read(p_ids bigint[] default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.notifications set read_at = now() where user_id = b2c.uid() and read_at is null and (p_ids is null or id = any (p_ids))
$f$;

create or replace function b2c.admin_home() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
        m0 timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2c.can('read_all') then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'handoffs_today', (select jsonb_build_object('sales', count(*) filter (where lane = 'sales'), 'nurture', count(*) filter (where lane = 'nurture'))
                         from b2c.leads_state where handed_off_at >= d0 and not is_test),
    'unassigned', (select jsonb_build_object('count', count(*), 'oldest', min(handed_off_at)) from b2c.leads_state where status = 'active' and owner_id is null and deleted_at is null and not is_test),
    'sla_month', (select jsonb_build_object('met', count(*) filter (where sla_met_at <= sla_due_at), 'breached', count(*) filter (where sla_breached_at is not null))
                    from b2c.leads_state where assigned_at >= m0 and not is_test),
    'enrolled_month', (select count(*) from b2c.enrollments where created_at >= m0 and status in ('reported', 'verified')),
    'to_verify', (select count(*) from b2c.enrollments where status = 'reported'),
    'pool', (select count(*) from b2c.leads_state where status = 'pool' and deleted_at is null and not is_test),
    'funnel', (select coalesce(jsonb_agg(jsonb_build_object('stage', st.name, 'n', (select count(*) from b2c.leads_state s where s.stage_id = st.id and s.deleted_at is null and not s.is_test))
                 order by st.rank), '[]') from b2c.stages st),
    'handoffs_14d', (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'sales', (select count(*) from b2c.leads_state s where s.lane = 'sales' and not s.is_test and s.handed_off_at >= d and s.handed_off_at < d + interval '1 day'),
                                                                   'nurture', (select count(*) from b2c.leads_state s where s.lane = 'nurture' and not s.is_test and s.handed_off_at >= d and s.handed_off_at < d + interval '1 day')) order by d), '[]')
                       from generate_series(d0 - interval '13 days', d0, interval '1 day') d),
    'sync', jsonb_build_object('last_batch_at', b2c.sync_get('last_batch_at'), 'queued', (select count(*) from b2c.outbox where status = 'queued'),
                               'failed', (select count(*) from b2c.outbox where status in ('failed', 'refused', 'conflict') and done_at > now() - interval '7 days'),
                               'inbox_errors', (select count(*) from b2c.inbox where status = 'error'),
                               'last_received_at', (select max(received_at) from b2c.inbox)));
end $f$;

-- ---------- grants ----------
grant execute on function b2c.application_save(jsonb), b2c.document_add(bigint, bigint, text, text, text, text), b2c.enrollment_record(jsonb),
  b2c.enrollment_verify(bigint, boolean, text), b2c.new_lead(jsonb, jsonb), b2c.route_to_partners(bigint[], text), b2c.lead_delete(bigint[], text),
  b2c.lead_restore(bigint[]), b2c.tag(bigint[], text, boolean), b2c.audit(text, bigint, jsonb), b2c.user_save(jsonb), b2c.user_deactivate(uuid, text),
  b2c.team(), b2c.programme_search(jsonb), b2c.notifications_mine(int), b2c.notifications_read(bigint[]), b2c.admin_home() to authenticated;
revoke execute on function b2c.outbox_after(bigint, boolean), b2c.directory_sync(jsonb) from public, authenticated;
grant execute on function b2c.directory_sync(jsonb) to service_role;
grant all on all tables in schema b2c to service_role;
