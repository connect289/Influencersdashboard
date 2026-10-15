-- M33c (15 Oct): data protection and the audit log.
--   (1) lead_anonymise(lead, reason, source)  Erases a student's personal data in the B2B CRM: student_leads (name, numbers,
--       email, guardian, addresses, identifiers, custom fields; course, city, state, stages and money columns stay for
--       statistics), lead_contacts, notes, field-history values, B2C write logs, notification recipients, partner activity
--       raw data, push responses and delivered webhook payloads. Pending messages and deliveries are cancelled. The lead
--       is marked anonymised_at and opted out, leaves the B2C CRM's copy (b2c.lead_released) and every partner that ever
--       received it gets an Admin alert (alert.partner_erasure_notice): partner copies and Witty's transcripts are erased
--       outside this CRM (the operations runbook says how). b2b.events are append-only and keep ids, not personal data.
--   (2) erasure_request_close REPLACED (m14d): closing a request as done erases the lead first.
--   (3) Retention: setting retention {inactive_months, test_lead_days}, saved through retention_settings_save;
--       retention_preview counts what the next run would do; retention_tick (daily, b2b-retention) anonymises leads idle
--       for inactive_months with no enrolment and no partner working them, soft-deletes test leads older than
--       test_lead_days, and prunes sign-in logs older than a year and finished deliveries older than 90 days.
--   (4) audit_log(p): the append-only event log, filtered (actor, type, lead, partner, period), keyset-paged, with the
--       admin's email resolved; data_protection_overview for the System screen.
-- No triggers on student_leads; nothing on Witty's tables. Re-appliable.

create table if not exists b2b.job_state (
  key         text primary key,
  value       jsonb not null default '{}',
  updated_at  timestamptz not null default now()
);
alter table b2b.job_state enable row level security;
revoke all on b2b.job_state from public, anon, authenticated;
grant all on b2b.job_state to service_role;

insert into b2b.settings (key, value) values ('retention', '{"inactive_months": null, "test_lead_days": 30}') on conflict (key) do nothing;

-- ---------- (1) erasure ----------
create or replace function b2b.lead_anonymise(p_lead_id bigint, p_reason text, p_source text default 'admin')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  v_actor text := coalesce(current_setting('b2b.actor', true), '');
  v_partners bigint[];
  n_contacts int := 0; n_notes int := 0; n_edits int := 0; n_writes int := 0; n_notif int := 0; n_out int := 0; n_act int := 0; n_push int := 0;
  p bigint;
begin
  if not (b2b.is_admin() or v_actor in ('engine', 'system')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if l.anonymised_at is not null then return jsonb_build_object('lead_id', l.id, 'already', true, 'anonymised_at', l.anonymised_at); end if;
  select coalesce(array_agg(distinct a.partner_id), '{}') into v_partners
    from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner' and a.status in ('pushed', 'accepted', 'duplicate', 'rejected', 'closed', 'recalled');

  -- the lead row: identity gone, statistics kept
  update public.student_leads
     set student_name = 'Erased', whatsapp_number = 'ERASED-' || id, email_id = null, alternate_phone = null, guardian_name = null, guardian_phone = null,
         ip_address = null, device = null, fingerprint = null, activation_code = null, current_city_country = null, custom_fields = '{}',
         landing_url = null, referrer_url = null, click_ids = null, chatwoot_conversation_id = null, web_session_id = null, portal_user_id = null,
         zoho_lead_id = null, partner_record_id = null, application_id = null, name_confirmed = null, email_confirmed = null,
         phone_verified_at = null, email_verified_at = null,
         is_opted_out = true, opted_out_at = coalesce(opted_out_at, now()), opted_out_channels = array['whatsapp', 'email'],
         anonymised_at = now(), deleted_at = coalesce(deleted_at, now()), updated_by = 'b2b:erasure'
   where id = l.id;
  -- copies inside the B2B CRM
  update b2b.lead_contacts set value = 'erased:' || id, removed_at = coalesce(removed_at, now()), actor = '{}' where lead_id = l.id; get diagnostics n_contacts = row_count;
  update b2b.lead_notes set body = '[erased]', deleted_at = coalesce(deleted_at, now()) where lead_id = l.id; get diagnostics n_notes = row_count;
  update b2b.lead_edits set old_value = '[erased]', new_value = '[erased]' where lead_id = l.id; get diagnostics n_edits = row_count;
  update b2b.b2c_writes set changes = '{}', actor = '{}', response = null where lead_id = l.id; get diagnostics n_writes = row_count;
  update b2b.student_notifications set status = 'cancelled', error = 'erased', updated_at = now() where lead_id = l.id and status = 'scheduled';
  update b2b.student_notifications set recipient = 'erased', variables = '{}' where lead_id = l.id; get diagnostics n_notif = row_count;
  update b2b.partner_activities set raw = null, mapped = '{}', counsellor_name = null where lead_id = l.id; get diagnostics n_act = row_count;
  update b2b.push_requests set response = null where allocation_id in (select a.id from b2b.allocations a where a.lead_id = l.id); get diagnostics n_push = row_count;
  update b2b.integration_outbox set status = 'cancelled', last_error = 'erased' where (payload ->> 'lead_id')::bigint = l.id and status in ('pending', 'failed');
  update b2b.integration_outbox
     set payload = jsonb_build_object('id', payload ->> 'id', 'type', payload ->> 'type', 'lead_id', l.id, 'erased', true, 'occurred_at', payload ->> 'occurred_at')
   where (payload ->> 'lead_id')::bigint = l.id; get diagnostics n_out = row_count;
  update b2b.consent_requests set evidence = '{}' where lead_id = l.id;
  -- the B2C CRM's copy is released (anonymised leads are out of its scope); partners are told through the Admin
  perform b2b.b2c_sync_lead(l.id, true, 'erasure');
  foreach p in array v_partners loop
    perform b2b.log_event('alert.partner_erasure_notice', l.id, null, p, jsonb_build_object('source', p_source));
  end loop;
  perform b2b.log_event('lead.anonymised', l.id, l.allocation_id, null, jsonb_build_object('reason', left(trim(p_reason), 300), 'source', p_source,
                        'partners_to_notify', to_jsonb(v_partners), 'contacts', n_contacts, 'notes', n_notes, 'edits', n_edits, 'b2c_writes', n_writes,
                        'notifications', n_notif, 'activities', n_act, 'push_responses', n_push, 'deliveries', n_out));
  return jsonb_build_object('lead_id', l.id, 'anonymised_at', now(), 'partners_to_notify', to_jsonb(v_partners),
                            'erased', jsonb_build_object('contacts', n_contacts, 'notes', n_notes, 'edits', n_edits, 'b2c_writes', n_writes,
                                                         'notifications', n_notif, 'activities', n_act, 'push_responses', n_push, 'deliveries', n_out));
end $fn$;

-- ---------- (2) closing an erasure request erases first ----------
create or replace function b2b.erasure_request_close(p_id bigint, p_status text, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare r b2b.erasure_requests; x jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status is null or p_status not in ('done', 'rejected') then raise exception 'status must be done or rejected' using errcode = '22023'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required' using errcode = '22023'; end if;
  select * into r from b2b.erasure_requests where id = p_id and status = 'open' for update;
  if r.id is null then raise exception 'open request not found' using errcode = 'P0002'; end if;
  if p_status = 'done' then
    x := b2b.lead_anonymise(r.lead_id, 'erasure request #' || r.id || ': ' || left(trim(p_note), 200), 'erasure');
  end if;
  update b2b.erasure_requests set status = p_status, note = left(trim(p_note), 300), closed_at = now() where id = r.id;
  perform b2b.log_event('erasure.' || p_status, r.lead_id, null, null, jsonb_build_object('erasure_request_id', r.id, 'note', left(trim(p_note), 300),
                        'partners_to_notify', coalesce(x -> 'partners_to_notify', '[]'::jsonb)));
end $fn$;

-- ---------- (3) retention ----------
create or replace function b2b.retention_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cur jsonb := coalesce((select value from b2b.settings where key = 'retention'), '{}');
  v_months int;
  v_days int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'give a reason (it goes in the settings history)' using errcode = '22023'; end if;
  v_months := case when p ? 'inactive_months' then case when (p ->> 'inactive_months') ~ '^[0-9]+$' then (p ->> 'inactive_months')::int end else (cur ->> 'inactive_months')::int end;
  v_days := case when p ? 'test_lead_days' then case when (p ->> 'test_lead_days') ~ '^[0-9]+$' then (p ->> 'test_lead_days')::int end else (cur ->> 'test_lead_days')::int end;
  if v_months is not null and v_months not between 6 and 120 then raise exception 'inactive_months is 6 to 120, or empty to keep leads forever' using errcode = '22023'; end if;
  if v_days is not null and v_days not between 1 and 365 then raise exception 'test_lead_days is 1 to 365, or empty to keep test leads' using errcode = '22023'; end if;
  perform b2b.set_setting('retention', jsonb_build_object('inactive_months', v_months, 'test_lead_days', v_days), trim(p_reason));
  return (select value from b2b.settings where key = 'retention');
end $fn$;

/* The inactive leads the next run would erase: idle (no activity, update or creation) for inactive_months, not yet
   erased, with no enrolment and no partner or B2C counsellor working them (no live allocation). */
create or replace function b2b.retention_candidates_sql()
returns text language sql immutable set search_path = '' as $fn$
  select $q$
    l.anonymised_at is null
    and greatest(coalesce(l.last_activity_at, l.created_at), coalesce(l.updated_at, l.created_at), coalesce(l.last_contacted_at, l.created_at), l.created_at) < now() - make_interval(months => %1$s)
    and not exists (select 1 from public.enrollments e where e.lead_id = l.id)
    and not exists (select 1 from b2b.allocations a where a.lead_id = l.id and a.status in ('queued', 'pushing', 'pushed', 'accepted'))
    and not exists (select 1 from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'in_house' and a.status = 'handed_off' and a.created_at > now() - make_interval(months => %1$s))
  $q$;
$fn$;

create or replace function b2b.retention_preview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'retention'), '{}');
  v_months int := nullif(s ->> 'inactive_months', '')::int;
  v_days int := nullif(s ->> 'test_lead_days', '')::int;
  n_inactive bigint := 0;
  n_test bigint := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_months is not null then
    execute format('select count(*) from public.student_leads l where ' || b2b.retention_candidates_sql(), v_months) into n_inactive;
  end if;
  if v_days is not null then
    select count(*) into n_test from public.student_leads l
     where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
       and l.created_at < now() - make_interval(days => v_days) and not exists (select 1 from public.enrollments e where e.lead_id = l.id);
  end if;
  return jsonb_build_object('settings', s, 'inactive_to_erase', n_inactive, 'test_leads_to_delete', n_test,
                            'anonymised_total', (select count(*) from public.student_leads where anonymised_at is not null),
                            'last_run', (select value from b2b.job_state where key = 'retention'));
end $fn$;

/* Daily. At most 200 erasures and 500 test-lead deletions per run; the rest follow the next day. */
create or replace function b2b.retention_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'retention'), '{}');
  v_months int := nullif(s ->> 'inactive_months', '')::int;
  v_days int := nullif(s ->> 'test_lead_days', '')::int;
  r record;
  n_erased int := 0;
  n_test int := 0;
  n_signin int := 0;
  n_out int := 0;
  v_err int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.retention_tick')) then return jsonb_build_object('skipped', 'busy'); end if;
  perform set_config('b2b.actor', 'engine', true);
  if v_months is not null then
    for r in execute format('select l.id from public.student_leads l where ' || b2b.retention_candidates_sql() || ' order by l.id limit 200', v_months) loop
      begin
        perform b2b.lead_anonymise(r.id, 'retention: no activity for ' || v_months || ' months', 'retention');
        n_erased := n_erased + 1;
      exception when others then
        v_err := v_err + 1;
        perform b2b.log_event('alert.retention_failed', r.id, null, null, jsonb_build_object('error', left(sqlerrm, 300)));
      end;
    end loop;
  end if;
  if v_days is not null then
    for r in
      update public.student_leads l set deleted_at = now(), updated_by = 'b2b:retention'
       where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
         and l.created_at < now() - make_interval(days => v_days) and not exists (select 1 from public.enrollments e where e.lead_id = l.id)
         and l.id in (select x.id from public.student_leads x where x.deleted_at is null and x.merged_into_id is null
                       and (coalesce(x.is_test, false) or b2b.is_test_phone(x.whatsapp_number)) and x.created_at < now() - make_interval(days => v_days)
                       order by x.id limit 500)
       returning l.id
    loop
      perform b2b.log_event('lead.deleted', r.id, null, null, jsonb_build_object('reason', 'test', 'retention', true, 'days', v_days));
      n_test := n_test + 1;
    end loop;
  end if;
  delete from b2b.sign_in_log where at < now() - interval '365 days'; get diagnostics n_signin = row_count;
  delete from b2b.integration_outbox where status in ('delivered', 'cancelled') and created_at < now() - interval '90 days'; get diagnostics n_out = row_count;
  insert into b2b.job_state (key, value, updated_at)
  values ('retention', jsonb_build_object('at', now(), 'erased', n_erased, 'test_deleted', n_test, 'errors', v_err, 'sign_in_pruned', n_signin, 'deliveries_pruned', n_out), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('erased', n_erased, 'test_deleted', n_test, 'errors', v_err, 'sign_in_pruned', n_signin, 'deliveries_pruned', n_out);
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-retention';
  perform cron.schedule('b2b-retention', '45 20 * * *', 'select b2b.retention_tick()');
end $cron$;

-- ---------- (4) the audit log and the overview ----------
/* p = {actor_type? (admin | engine | system | b2c_crm | api | all; default admin), q? (type contains), lead_id?, partner_id?,
   since?, until?, after? (keyset id), limit? (<= 200)}. Newest first. */
create or replace function b2b.audit_log(p jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_actor text := coalesce(nullif(p ->> 'actor_type', ''), 'admin');
  v_q text := nullif(lower(trim(coalesce(p ->> 'q', ''))), '');
  v_lead bigint := nullif(p ->> 'lead_id', '')::bigint;
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_since timestamptz := b2b.try_timestamptz(p ->> 'since');
  v_until timestamptz := b2b.try_timestamptz(p ->> 'until');
  v_after bigint := nullif(p ->> 'after', '')::bigint;
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 50), 1), 200);
  v_rows jsonb;
  v_last bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  with page as (
    select e.* from b2b.events e
     where (v_actor = 'all' or e.actor_type = v_actor)
       and (v_q is null or lower(e.type) like '%' || v_q || '%')
       and (v_lead is null or e.lead_id = v_lead)
       and (v_partner is null or e.partner_id = v_partner)
       and (v_since is null or e.occurred_at >= v_since)
       and (v_until is null or e.occurred_at < v_until)
       and (v_after is null or e.id < v_after)
     order by e.id desc limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'at', x.occurred_at, 'type', x.type, 'actor_type', x.actor_type, 'actor_id', x.actor_id,
           'actor_email', (select u.email from b2b.app_users u where u.user_id::text = x.actor_id),
           'lead_id', x.lead_id, 'allocation_id', x.allocation_id, 'partner_id', x.partner_id,
           'partner_name', (select coalesce(pt.display_name, pt.name) from b2b.partners pt where pt.id = x.partner_id),
           'payload', case when length(x.payload::text) > 4000 then jsonb_build_object('truncated', true, 'keys', (select jsonb_agg(k) from jsonb_object_keys(x.payload) k)) else x.payload end)
           order by x.id desc), '[]'), min(x.id)
    into v_rows, v_last from page x;
  return jsonb_build_object('rows', v_rows, 'next_after', case when jsonb_array_length(v_rows) = v_limit then v_last end);
end $fn$;

create or replace function b2b.data_protection_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.retention_preview() || jsonb_build_object(
    'erasures', jsonb_build_object('open', (select count(*) from b2b.erasure_requests where status = 'open'),
                                   'done_30d', (select count(*) from b2b.erasure_requests where status = 'done' and closed_at > now() - interval '30 days')),
    'partner_notices_open', (select count(*) from b2b.events e where e.type = 'alert.partner_erasure_notice' and e.occurred_at > now() - interval '90 days'),
    'consents_30d', (select count(*) from b2b.lead_consents c where c.created_at > now() - interval '30 days'),
    'opted_out_total', (select count(*) from public.student_leads l where coalesce(l.is_opted_out, false) and l.anonymised_at is null));
end $fn$;

revoke execute on function b2b.lead_anonymise(bigint, text, text), b2b.erasure_request_close(bigint, text, text), b2b.retention_settings_save(jsonb, text),
                           b2b.retention_preview(), b2b.audit_log(jsonb), b2b.data_protection_overview() from public, anon;
grant execute on function b2b.lead_anonymise(bigint, text, text), b2b.erasure_request_close(bigint, text, text), b2b.retention_settings_save(jsonb, text),
                          b2b.retention_preview(), b2b.audit_log(jsonb), b2b.data_protection_overview() to authenticated, service_role;
revoke execute on function b2b.retention_tick(), b2b.retention_candidates_sql() from public, anon, authenticated;
grant execute on function b2b.retention_tick(), b2b.retention_candidates_sql() to service_role;
