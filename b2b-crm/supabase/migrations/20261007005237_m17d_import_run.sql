-- M17d: the import wizard, part 2 (spec B4.1): commit, the batch writer, rollback and release. Part 1 is m17c.
--   import_commit        step 5: source label, campaign, consent basis and routing choice; the job starts
--   import_process       writes rows through lead_intake() in batches (called by the screen, and by pg_cron every minute)
--   import_rollback      within 24 hours: soft-deletes the leads the import created that have not been routed anywhere
--   leads_soft_delete    (m3) fixed for leads not yet routed

/* Step 5. consent: {where, when, text, purposes: [sales, partner_share, marketing]}. */
create or replace function b2b.import_commit(p_import_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  c jsonb := coalesce(p -> 'consent', '{}');
  v_when timestamptz;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.imports where id = p_import_id for update;
  if i.id is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  if i.status <> 'staging' then raise exception 'this import was already committed' using errcode = '22023'; end if;
  if i.total_rows = 0 then raise exception 'the file has no rows' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'source_label', ''))) < 2 then raise exception 'give a source label' using errcode = '22023'; end if;
  if coalesce(p ->> 'routing_choice', '') not in ('route', 'hold', 'b2c') then raise exception 'choose what happens to the leads' using errcode = '22023'; end if;
  if p ->> 'routing_choice' = 'b2c' and coalesce(p ->> 'b2c_lane', '') not in ('sales', 'nurture') then raise exception 'choose the B2C lane' using errcode = '22023'; end if;
  if length(trim(coalesce(c ->> 'where', ''))) < 3 or length(trim(coalesce(c ->> 'text', ''))) < 10 then
    raise exception 'give the consent basis: where the students agreed and the consent text' using errcode = '22023';
  end if;
  begin v_when := (c ->> 'when')::timestamptz; exception when others then v_when := null; end;
  if v_when is null or v_when > now() then raise exception 'give when the students agreed (a date not in the future)' using errcode = '22023'; end if;
  if jsonb_typeof(c -> 'purposes') <> 'array' or not (c -> 'purposes') ? 'sales' then
    raise exception 'the consent must at least cover being contacted about courses' using errcode = '22023';
  end if;
  if p ->> 'routing_choice' = 'route' and not (c -> 'purposes') ? 'partner_share' then
    raise exception 'to route to partners the consent must cover sharing with partner institutions' using errcode = '22023';
  end if;

  update b2b.imports
     set status = 'committing', committed_at = now(), source_label = left(lower(regexp_replace(trim(p ->> 'source_label'), '[^a-zA-Z0-9]+', '_', 'g')), 60),
         campaign = nullif(left(trim(coalesce(p ->> 'campaign', '')), 120), ''),
         consent = jsonb_build_object('where', left(trim(c ->> 'where'), 300), 'when', v_when, 'text', left(trim(c ->> 'text'), 2000), 'purposes', c -> 'purposes'),
         routing_choice = p ->> 'routing_choice', b2c_lane = case when p ->> 'routing_choice' = 'b2c' then p ->> 'b2c_lane' end
   where id = i.id;
  update b2b.import_rows set status = 'skipped', error = case preview when 'invalid' then 'invalid or missing phone' else 'blocked phone' end, done_at = now()
   where import_id = i.id and preview in ('invalid', 'blocked') and status = 'staged';
  perform b2b.log_event('import.committed', null, null, null,
                        jsonb_build_object('import_id', i.id, 'rows', i.total_rows, 'routing_choice', p ->> 'routing_choice', 'source_label', p ->> 'source_label'));
  return b2b.import_process(i.id, 300);
end $fn$;

/* Writes up to p_limit staged rows of a committing import through lead_intake(). Safe to call concurrently. */
create or replace function b2b.import_process(p_import_id bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  x record;
  v_lead jsonb;
  v_res jsonb;
  v_key text;
  v_course text;
  v_purposes jsonb;
  n int := 0;
  v_left int;
begin
  select * into i from b2b.imports where id = p_import_id;
  if i.id is null or i.status <> 'committing' then return jsonb_build_object('processed', 0, 'left', 0, 'status', i.status); end if;
  v_purposes := coalesce(i.consent -> 'purposes', '[]');
  perform set_config('b2b.actor', coalesce(nullif(current_setting('b2b.actor', true), ''), 'system'), true);
  for x in select * from b2b.import_rows where import_id = i.id and status = 'staged' order by row_no
            limit least(greatest(coalesce(p_limit, 300), 1), 2000) for update skip locked loop
    begin
      v_lead := x.lead - 'phone' - 'course' - 'specialization' - 'university' - 'study_mode' - 'academic_score' - 'work_experience' - 'annual_budget';
      v_key := i.course_choices ->> (x.lead ->> 'course');
      v_course := coalesce((select p.course from public.catalog_programs p where p.course_key = v_key limit 1), x.lead ->> 'course');
      v_lead := v_lead || jsonb_strip_nulls(jsonb_build_object(
        'interested_course', v_course, 'interested_specialization', x.lead ->> 'specialization', 'interested_university', x.lead ->> 'university',
        'study_mode_preference', x.lead ->> 'study_mode', 'academic_score_raw', x.lead ->> 'academic_score',
        'work_experience_raw', x.lead ->> 'work_experience', 'annual_budget_raw', x.lead ->> 'annual_budget',
        'source', i.source_label, 'channel', 'import', 'campaign', coalesce(x.lead ->> 'campaign', i.campaign),
        'consent_sales_at', case when v_purposes ? 'sales' then i.consent ->> 'when' end,
        'consent_partner_share_at', case when v_purposes ? 'partner_share' then i.consent ->> 'when' end,
        'consent_marketing_at', case when v_purposes ? 'marketing' then i.consent ->> 'when' end,
        'consent_text_version', 'import:' || i.id));
      v_res := public.lead_intake(jsonb_build_object('phone', x.phone, 'source_system', 'import', 'event_type', 'lead.imported', 'lead', v_lead,
                                                     'idempotency_key', 'import:' || i.id || ':' || x.row_no,
                                                     'attribution', jsonb_build_object('import_id', i.id, 'source_label', i.source_label, 'campaign', i.campaign, 'row_no', x.row_no)));
      if exists (select 1 from public.student_leads l where l.id = (v_res ->> 'lead_id')::bigint and l.destination_type is null) then
        insert into b2b.intake_directives (lead_id, source, import_id, directive, b2c_lane, phone_trusted)
        values ((v_res ->> 'lead_id')::bigint, 'import', i.id, i.routing_choice, i.b2c_lane, true)
        on conflict (lead_id) do update set source = 'import', import_id = excluded.import_id, directive = excluded.directive, b2c_lane = excluded.b2c_lane,
                                            phone_trusted = true, created_at = now(), released_at = null, released_by = null;
      end if;
      update b2b.import_rows set status = 'imported', lead_id = (v_res ->> 'lead_id')::bigint, action = v_res ->> 'action', done_at = now() where id = x.id;
    exception when others then
      update b2b.import_rows set status = 'error', error = left(sqlerrm, 300), done_at = now() where id = x.id;
    end;
    n := n + 1;
  end loop;

  select count(*) into v_left from b2b.import_rows where import_id = i.id and status = 'staged';
  if v_left = 0 then
    update b2b.imports set status = 'done', finished_at = now(),
           counts = (select jsonb_build_object('imported', count(*) filter (where status = 'imported'), 'skipped', count(*) filter (where status = 'skipped'),
                                               'errors', count(*) filter (where status = 'error'), 'created', count(*) filter (where action = 'created'),
                                               'merged', count(*) filter (where action = 'merged'), 'reopened', count(*) filter (where action = 'reopened'))
                       from b2b.import_rows where import_id = i.id)
     where id = i.id and status = 'committing';
    if found then perform b2b.log_event('import.done', null, null, null, (select counts || jsonb_build_object('import_id', id) from b2b.imports where id = i.id)); end if;
  end if;
  return jsonb_build_object('processed', n, 'left', v_left, 'status', case when v_left = 0 then 'done' else 'committing' end);
end $fn$;

/* The screen keeps an import moving while it is open (pg_cron does the same every minute). */
create or replace function b2b.import_continue(p_import_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.import_process(p_import_id, 500);
end $fn$;

/* pg_cron, every minute: carries on any import whose screen was closed. */
create or replace function b2b.import_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare r record; n int := 0;
begin
  perform set_config('b2b.actor', 'system', true);
  for r in select id from b2b.imports where status = 'committing' order by id loop
    n := n + coalesce((b2b.import_process(r.id, 2000) ->> 'processed')::int, 0);
  end loop;
  return n;
end $fn$;

/* Within 24 hours: soft-deletes the leads this import created that nothing has routed yet, and releases its directives.
   Leads it merged into or reopened are not changed back (their earlier data is kept by lead_intake's merge rules). */
create or replace function b2b.import_rollback(p_import_id bigint, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  v_ids bigint[];
  v_kept int;
  v_chunk bigint[];
  v_deleted int := 0;
  k int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into i from b2b.imports where id = p_import_id for update;
  if i.id is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  if i.status <> 'done' then raise exception 'only a finished import can be rolled back' using errcode = '22023'; end if;
  if i.finished_at < now() - make_interval(hours => coalesce((select (value ->> 'rollback_hours')::int from b2b.settings where key = 'intake'), 24)) then
    raise exception 'the rollback window has passed' using errcode = '22023';
  end if;

  select coalesce(array_agg(r.lead_id), '{}') into v_ids
    from b2b.import_rows r join public.student_leads l on l.id = r.lead_id
   where r.import_id = i.id and r.status = 'imported' and r.action = 'created' and l.deleted_at is null
     and l.destination_type is null and not exists (select 1 from b2b.allocations a where a.lead_id = r.lead_id);
  select count(*) into v_kept from b2b.import_rows r
   where r.import_id = i.id and r.status = 'imported' and not (r.lead_id = any (v_ids));

  update b2b.intake_directives set released_at = now(), released_by = 'rollback'
   where import_id = i.id and released_at is null;
  for k in 0 .. coalesce(cardinality(v_ids), 0) / 500 loop
    v_chunk := v_ids[k * 500 + 1 : k * 500 + 500];
    continue when coalesce(cardinality(v_chunk), 0) = 0;
    v_deleted := v_deleted + jsonb_array_length(b2b.leads_soft_delete(v_chunk, 'other') -> 'deleted');
  end loop;
  update b2b.import_rows set status = 'rolled_back' where import_id = i.id and lead_id = any (v_ids);
  update b2b.imports set status = 'rolled_back', rolled_back_at = now(), rollback_note = left(trim(p_note), 300) where id = i.id;
  perform b2b.log_event('import.rolled_back', null, null, null,
                        jsonb_build_object('import_id', i.id, 'deleted', v_deleted, 'kept', v_kept, 'note', trim(p_note)));
  return jsonb_build_object('deleted', v_deleted, 'kept', v_kept);
end $fn$;

/* Abandon an import that was never committed (its staged rows stay, marked with the job). */
create or replace function b2b.import_abandon(p_import_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.imports set status = 'abandoned', finished_at = now() where id = p_import_id and status = 'staging';
  if not found then raise exception 'only an import that was not committed can be abandoned' using errcode = '22023'; end if;
end $fn$;

/* Release held leads of an import (or all held manual entries when p_import_id is null and p_lead_ids given). */
create or replace function b2b.intake_release(p_import_id bigint, p_lead_ids bigint[])
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare n int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.intake_directives set released_at = now(), released_by = b2b.actor() ->> 'id'
   where directive = 'hold' and released_at is null
     and ((p_import_id is not null and import_id = p_import_id) or (p_lead_ids is not null and lead_id = any (p_lead_ids)));
  get diagnostics n = row_count;
  perform b2b.log_event('intake.released', null, null, null, jsonb_build_object('import_id', p_import_id, 'leads', n));
  return n;
end $fn$;

/* As in m3, fixed: a lead not yet routed (destination_type null) made the partner check null, so it could only be
   deleted as junk, spam or a student request ("test", "duplicate entry" and "other" silently deleted nothing). */
create or replace function b2b.leads_soft_delete(p_ids bigint[], p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_batch   uuid := gen_random_uuid();
  v_a       jsonb := b2b.actor();
  v_blocked jsonb;
  v_done    bigint[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_reason is null or p_reason not in ('junk', 'test', 'duplicate entry', 'spam', 'student request', 'other') then
    raise exception 'choose a reason';
  end if;
  if cardinality(p_ids) is null or cardinality(p_ids) = 0 then return jsonb_build_object('deleted', '[]'::jsonb, 'blocked', '[]'::jsonb); end if;
  if cardinality(p_ids) > 500 then raise exception 'at most 500 leads per delete'; end if;

  -- Money rows must survive: a lead with an enrollment can only be closed, never deleted (B6.1.4).
  -- A lead with a partner may be deleted only as junk, spam or a student request.
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'why',
           case when exists (select 1 from public.enrollments e where e.lead_id = l.id) then 'has an enrollment'
                else 'with a partner: use junk, spam or student request' end)), '[]')
    into v_blocked
    from public.student_leads l
   where l.id = any (p_ids) and l.deleted_at is null
     and (exists (select 1 from public.enrollments e where e.lead_id = l.id)
          or (coalesce(l.destination_type, '') = 'partner' and p_reason not in ('junk', 'spam', 'student request')));

  with upd as (
    update public.student_leads l
       set deleted_at = now(), updated_by = 'b2b'
     where l.id = any (p_ids) and l.deleted_at is null
       and not exists (select 1 from public.enrollments e where e.lead_id = l.id)
       and not (coalesce(l.destination_type, '') = 'partner' and p_reason not in ('junk', 'spam', 'student request'))
    returning l.id
  )
  select coalesce(array_agg(id), '{}') into v_done from upd;

  insert into b2b.lead_deletions (lead_id, action, reason, batch_id, actor_type, actor_id)
  select id, 'delete', p_reason, v_batch, v_a ->> 'type', v_a ->> 'id' from unnest(v_done) id;
  insert into b2b.events (type, lead_id, actor_type, actor_id, payload)
  select 'lead.deleted', id, v_a ->> 'type', v_a ->> 'id', jsonb_build_object('reason', p_reason, 'batch_id', v_batch) from unnest(v_done) id;

  return jsonb_build_object('deleted', to_jsonb(v_done), 'blocked', v_blocked, 'batch_id', v_batch);
end $fn$;


revoke execute on function b2b.import_commit(bigint, jsonb), b2b.import_process(bigint, int), b2b.import_continue(bigint), b2b.import_tick(),
                           b2b.import_rollback(bigint, text), b2b.import_abandon(bigint), b2b.intake_release(bigint, bigint[])
  from public, anon, authenticated;
grant execute on function b2b.import_process(bigint, int), b2b.import_tick() to service_role;
grant execute on function b2b.import_commit(bigint, jsonb), b2b.import_continue(bigint), b2b.import_rollback(bigint, text), b2b.import_abandon(bigint),
                          b2b.intake_release(bigint, bigint[])
  to authenticated, service_role;

select cron.schedule('b2b-import-tick', '* * * * *', 'select b2b.import_tick()');
