-- M34g (31 Oct 2026, audit B2B-H1): erasing a lead no longer depends on a session setting.
--   b2b.lead_anonymise_core(lead, reason, source)  NEW, internal (not executable through the API): the erasure itself, the
--                                                  body of lead_anonymise without its caller check.
--   b2b.lead_anonymise(lead, reason, source)       the Admin's call: b2b.is_admin() only.
--   b2b.retention_tick()                           the nightly retention erases through lead_anonymise_core.
--   erasure_request_close (Admin) keeps calling lead_anonymise. Production definitions with only those lines changed.
-- Re-appliable. Checked by supabase/tests/test_m34g_anonymise_guard.sql.

CREATE OR REPLACE FUNCTION b2b.lead_anonymise_core(p_lead_id bigint, p_reason text, p_source text DEFAULT 'admin'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  l public.student_leads;
  v_partners bigint[];
  n_contacts int := 0; n_notes int := 0; n_edits int := 0; n_writes int := 0; n_notif int := 0; n_out int := 0; n_act int := 0; n_push int := 0;
  p bigint;
begin
  -- M34g: no caller check here; lead_anonymise (the Admin) and retention_tick (the engine) are the callers
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
end $function$;

/* The Admin erases a lead (System → Data protection, erasure requests). M34g: the Admin only. */
create or replace function b2b.lead_anonymise(p_lead_id bigint, p_reason text, p_source text default 'admin')
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.lead_anonymise_core(p_lead_id, p_reason, p_source);
end $fn$;

CREATE OR REPLACE FUNCTION b2b.retention_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
        perform b2b.lead_anonymise_core(r.id, 'retention: no activity for ' || v_months || ' months', 'retention');   -- M34g
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
end $function$;

revoke execute on function b2b.lead_anonymise_core(bigint, text, text) from public, anon, authenticated;
grant execute on function b2b.lead_anonymise_core(bigint, text, text) to service_role;
revoke execute on function b2b.lead_anonymise(bigint, text, text) from public, anon;
grant execute on function b2b.lead_anonymise(bigint, text, text) to authenticated, service_role;
revoke execute on function b2b.retention_tick() from public, anon, authenticated;
grant execute on function b2b.retention_tick() to service_role;

-- rollback: re-run b2b.lead_anonymise and b2b.retention_tick of m33c_data_protection_audit.sql (production's as of 30 Oct
-- 2026); lead_anonymise_core can stay (unused).
