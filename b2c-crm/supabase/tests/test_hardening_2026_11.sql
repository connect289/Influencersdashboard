-- b55 checks (the November 2026 hardening), rolled back. Every row of the final select must say ok = true. Writes only
-- test users and test leads (phones 9100009955xx); safe on staging (SQL editor) and on a local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e551', 'asha.hd@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e554', 'admin.hd@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, languages) values
  ('aaaaaaaa-0000-0000-0000-00000000e551', 'asha.hd@eduwit.in', 'Asha HD', 'counsellor', true, true, false, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e554', 'admin.hd@eduwit.in', 'Admin HD', 'admin', true, true, false, '{English}');
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.hd@eduwit.in' on conflict do nothing;
update b2c.settings set value = value || '{"quiet_start": "00:00", "quiet_end": "23:59"}' where key = 'messaging';

/* A test sales lead owned by Asha HD (phone 9100009955 + the last two digits of the id). */
create function pg_temp.lead(p_id bigint) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'hd-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'HD Student ' || p_id, 'phone', '9100009955' || right(p_id::text, 2), 'email', 'hd' || p_id || '@example.com'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false, 'marketing_consent_at', now()), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'hd-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', '{"b2c_lane": "sales", "reason": "qualified"}'::jsonb), 'test');
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000e551', status = 'active' where lead_id = p_id;
end $f$;

do $t$
declare j jsonb; v jsonb; q b2c.send_queue; v_id bigint; v_id2 bigint; v_wa bigint; v_late bigint; v_x bigint; e text; w text; n int;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(995501); perform pg_temp.lead(995503); perform pg_temp.lead(995504); perform pg_temp.lead(995505);
  perform pg_temp.lead(995506); perform pg_temp.lead(995507);
  delete from b2c.send_queue where to_address like '9100009955%' or lead_id between 995500 and 995599;

  -- ---------- 1. erasure removes WhatsApp files and numbers; a late media job does not store the file ----------
  insert into b2c.documents (lead_id, kind, storage_path, file_name, source) values (995501, 'marksheet', 'leads/995501/doc-a.pdf', 'a.pdf', 'whatsapp');
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, media, media_path, status)
  values ('910000995501', 995501, 'in', 'media', 'my marksheet', '{"id": "m1", "type": "document"}', 'leads/995501/wa/1-marks.pdf', 'received'),
         ('910000995501', 995501, 'out', 'media', 'brochure', '{"kind": "document"}', 'leads/995501/brochure.pdf', 'sent'),
         ('910000995501', 995501, 'in', 'media', 'same file', '{"id": "m2", "type": "document"}', 'leads/995501/doc-a.pdf', 'received');
  insert into b2c.wa_messages (phone, lead_id, direction, kind, media, status)
  values ('910000995501', 995501, 'in', 'media', '{"id": "m3", "type": "image"}', 'received') returning id into v_late;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e554');
  j := b2c.lead_erase(995501, 'ticket HD-1');
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('erase_queues_wa_files',
    (select count(*) from b2c.erase_files where lead_id = 995501 and bucket = 'b2c-documents'
        and path in ('leads/995501/wa/1-marks.pdf', 'leads/995501/brochure.pdf', 'leads/995501/doc-a.pdf')) = 3
    and (select count(*) from b2c.erase_files where lead_id = 995501 and path = 'leads/995501/doc-a.pdf') = 1, j::text);
  insert into r (name, ok, detail) values ('erase_clears_wa_paths_and_numbers',
    not exists (select 1 from b2c.wa_messages where lead_id = 995501 and (media_path is not null or phone <> 'erased:995501' or body is not null or media is not null))
    and not exists (select 1 from b2c.wa_messages where phone = '910000995501'), null);
  perform b2c.wa_media_stored(v_late, 'leads/995501/wa/' || v_late || '-late.jpg', null);
  insert into r (name, ok, detail) values ('media_stored_refuses_erased_lead',
    (select media_path is null from b2c.wa_messages where id = v_late)
    and exists (select 1 from b2c.erase_files where lead_id = 995501 and path = 'leads/995501/wa/' || v_late || '-late.jpg'), null);

  -- ---------- 2. an expired export's file is queued for removal ----------
  insert into b2c.exports (user_id, params, format, status, rows, path, done_at, expires_at)
  values ('aaaaaaaa-0000-0000-0000-00000000e554', '{}', 'csv', 'ready', 12000, 'aaaaaaaa-0000-0000-0000-00000000e554/export-hd.csv', now() - interval '8 days', now() - interval '1 day')
  returning id into v_x;
  perform b2c.export_take(0);
  insert into r (name, ok, detail) values ('expired_export_queued_for_removal',
    (select status = 'expired' and path is null from b2c.exports where id = v_x)
    and exists (select 1 from b2c.erase_files where bucket = 'b2c-exports' and path = 'aaaaaaaa-0000-0000-0000-00000000e554/export-hd.csv' and lead_id is null and removed_at is null), null);
  j := b2c.erase_files_take(500);
  insert into r (name, ok, detail) values ('removal_job_takes_export_file',
    exists (select 1 from jsonb_array_elements(j) x where x ->> 'bucket' = 'b2c-exports' and x ->> 'path' = 'aaaaaaaa-0000-0000-0000-00000000e554/export-hd.csv'), null);

  -- ---------- 3. STOP: normalised, matched first ----------
  select string_agg(x, ', ') into w from unnest(array['STOP', 'Stop.', 'STOP!!', 'stop 🙏', 'please stop', 'Stop messaging me', 'pls stop sending these',
      'Unsubscribe', 'unsub', 'band karo', 'Mat bhejo!', 'no more messages', 'बंद करो', 'बंद करो।', 'मत भेजो', 'रोको']) x where not b2c.is_stop_message(x);
  insert into r (name, ok, detail) values ('stop_variants_match', w is null, w);
  select string_agg(x, ', ') into w from unnest(array['hello', 'Yes, call me', 'when does the next batch start', 'can you share the fee structure and tell me when the classes stop for summer',
      '', '🙏', 'bandstand', 'क्या कॉलेज बंद है', 'कल ऑफिस बंद रहेगा?']) x where b2c.is_stop_message(x);
  insert into r (name, ok, detail) values ('stop_ordinary_messages_do_not_match', w is null, w);

  j := b2c.wa_inbound(jsonb_build_object('from', '910000995590', 'text', 'Stop.', 'wamid', 'hd-wamid-90'));
  insert into r (name, ok, detail) values ('stop_unknown_number_suppressed',
    j ->> 'status' = 'suppressed' and exists (select 1 from b2c.suppressions where value_norm = '910000995590' and kind = 'phone' and lifted_at is null)
    and not exists (select 1 from b2c.outbox where kind = 'intake' and request_id = 'b2c-in-910000995590')
    and exists (select 1 from b2c.wa_messages where wamid = 'hd-wamid-90'), j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000995591', 'text', 'बंद करो', 'wamid', 'hd-wamid-91'));
  insert into r (name, ok, detail) values ('stop_unknown_number_devanagari',
    j ->> 'status' = 'suppressed' and exists (select 1 from b2c.suppressions where value_norm = '910000995591')
    and not exists (select 1 from b2c.outbox where kind = 'intake' and request_id = 'b2c-in-910000995591'), j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000995592', 'text', 'Hi, I want an MBA', 'wamid', 'hd-wamid-92'));
  insert into r (name, ok, detail) values ('unknown_number_still_requests_lead',
    j ->> 'status' = 'new_lead_requested' and exists (select 1 from b2c.outbox where kind = 'intake' and request_id = 'b2c-in-910000995592')
    and not exists (select 1 from b2c.suppressions where value_norm = '910000995592'), j::text);

  j := b2c.wa_inbound(jsonb_build_object('from', '910000995503', 'text', 'please stop', 'wamid', 'hd-wamid-03'));
  insert into r (name, ok, detail) values ('stop_active_sales_lead_opts_out',
    j ->> 'status' = 'opted_out' and b2c.may_message(995503) = 'opted out'
    and exists (select 1 from b2c.consents where lead_id = 995503 and not given and source = 'stop_word')
    and exists (select 1 from b2c.outbox where kind = 'event' and lead_id = 995503 and body ->> 'type' = 'b2ccrm.opted_out')
    and exists (select 1 from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000e551' and lead_id = 995503 and title like '%asked to stop%'), j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000995503', 'text', 'START', 'wamid', 'hd-wamid-03b'));
  insert into r (name, ok, detail) values ('start_still_opts_in', j ->> 'status' = 'opted_in' and b2c.may_message(995503) is null, j::text);

  -- ---------- 4. opt-out and suppression at send time ----------
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, purpose)
  values ('910000995504', 995504, 'out', 'text', 'hd taken before the stop', 'queued', 'sales') returning id into v_wa;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose, status, attempts, taken_at, not_before)
  values ('whatsapp', 995504, '910000995504', v_wa, '{"type": "text", "text": "hd taken"}', 'sales', 'sending', 1, now(), now() - interval '1 minute')
  returning id into v_id;
  j := b2c.wa_inbound(jsonb_build_object('from', '910000995504', 'text', 'STOP!!', 'wamid', 'hd-wamid-04'));
  n := b2c.send_release(array[v_id]);
  v := b2c.send_take(200);
  select * into q from b2c.send_queue where id = v_id;
  insert into r (name, ok, detail) values ('send_take_cancels_released_after_stop',
    n = 1 and q.status = 'cancelled' and q.error like 'not sent: opted out%' and not exists (select 1 from jsonb_array_elements(v) x where (x ->> 'id')::bigint = v_id)
    and (select status from b2c.wa_messages where id = v_wa) = 'cancelled', row_to_json(q)::text);

  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, not_before)
  values ('whatsapp', 995505, '910000995505', '{"type": "text", "text": "hd journey"}', 'journey', now() + interval '1 hour') returning id into v_id;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, not_before)
  values ('whatsapp', 995505, '910000995505', '{"type": "text", "text": "hd sales"}', 'sales', now() + interval '1 hour') returning id into v_id2;
  perform b2c.suppress('910000995505', 'hd test');
  insert into r (name, ok, detail) values ('suppress_cancels_queued_marketing',
    (select status from b2c.send_queue where id = v_id) = 'cancelled' and (select status from b2c.send_queue where id = v_id2) = 'queued', null);
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, status, attempts, taken_at, not_before)
  values ('whatsapp', 995505, '910000995505', '{"type": "text", "text": "hd campaign"}', 'campaign', 'sending', 1, now(), now() - interval '1 minute') returning id into v_id;
  update b2c.send_queue set not_before = now() - interval '1 minute' where id = v_id2;
  perform b2c.send_release(array[v_id]);
  v := b2c.send_take(200);
  insert into r (name, ok, detail) values ('send_take_cancels_suppressed_marketing_only',
    (select status from b2c.send_queue where id = v_id) = 'cancelled' and (select status from b2c.send_queue where id = v_id2) = 'sending'
    and exists (select 1 from jsonb_array_elements(v) x where (x ->> 'id')::bigint = v_id2), v::text);

  -- ---------- 5. "may have gone out": failed, never queued again ----------
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, status, attempts, taken_at, not_before)
  values ('whatsapp', 995505, '910000995505', '{"type": "text", "text": "hd maybe sent"}', 'sales', 'sending', 1, now(), now() - interval '1 minute') returning id into v_id;
  perform b2c.send_done(jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'retry', false, 'error', 'no answer from WhatsApp in time: it may have gone out'),
                                          jsonb_build_object('id', v_id2, 'ok', false, 'error', '400: bad parameter')));
  insert into r (name, ok, detail) values ('send_done_no_retry_fails',
    (select status = 'failed' and sent_at is null and error like '%may have gone out' from b2c.send_queue where id = v_id), null);
  insert into r (name, ok, detail) values ('send_done_default_still_retries', (select status from b2c.send_queue where id = v_id2) = 'queued', null);

  -- ---------- 6. one enrolment, active leads only ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e551');
  v_x := b2c.enrollment_record(jsonb_build_object('lead_id', 995506, 'university', 'HD University', 'programme', 'MBA', 'fee', 150000, 'fee_paid', 50000,
                                                  'enrolled_on', current_date, 'proof_path', 'leads/995506/proof.pdf'));
  begin
    perform b2c.enrollment_record(jsonb_build_object('lead_id', 995506, 'university', 'HD University', 'programme', 'MBA', 'fee', 150000,
                                                     'enrolled_on', current_date, 'proof_path', 'leads/995506/proof2.pdf'));
    e := 'recorded twice';
  exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('second_enrolment_refused',
    v_x is not null and e like 'this lead already has an enrolment%' and (select count(*) from b2c.enrollments where lead_id = 995506) = 1, e);
  perform pg_temp.as_system();
  update b2c.leads_state set status = 'closed', closed_reason = 'released', closed_at = now() where lead_id = 995507;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e554');
  begin
    perform b2c.enrollment_record(jsonb_build_object('lead_id', 995507, 'university', 'HD University', 'programme', 'MBA', 'fee', 150000,
                                                     'enrolled_on', current_date, 'proof_path', 'leads/995507/proof.pdf'));
    e := 'recorded';
  exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('closed_lead_enrolment_refused',
    e like 'this lead is closed, lost or erased%' and not exists (select 1 from b2c.enrollments where lead_id = 995507), e);

  -- ---------- 10. a conversation with no lead: the Admin reads it, nobody else ----------
  j := b2c.wa_unmatched_thread('910000995592');
  insert into r (name, ok, detail) values ('unmatched_thread_admin_reads',
    j ->> 'phone' = '910000995592' and jsonb_array_length(j -> 'messages') = 1 and j -> 'messages' -> 0 ->> 'body' = 'Hi, I want an MBA', j::text);
  begin
    perform b2c.wa_unmatched_thread('910000995504');
    e := 'allowed';
  exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('unmatched_thread_not_for_a_lead', e like 'this conversation belongs to a lead%', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e551');
  begin
    perform b2c.wa_unmatched_thread('910000995592');
    insert into r (name, ok, detail) values ('unmatched_thread_refuses_non_admin', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('unmatched_thread_refuses_non_admin', sqlstate = '42501', sqlerrm);
  end;
  perform pg_temp.as_system();
  begin
    perform b2c.wa_unmatched_thread('910000995592');
    insert into r (name, ok, detail) values ('unmatched_thread_refuses_no_user', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('unmatched_thread_refuses_no_user', sqlstate = '42501', sqlerrm);
  end;
end $t$;

insert into r (name, ok, detail)
select 'grants', bool_and(ok), string_agg(detail, '; ') filter (where not ok)
  from (select case when f = 'b2c.wa_unmatched_thread(text)' then has_function_privilege('authenticated', f, 'execute')
                    else not has_function_privilege('authenticated', f, 'execute') end
               and not has_function_privilege('anon', f, 'execute') as ok, f as detail
          from unnest(array['b2c.wa_unmatched_thread(text)', 'b2c.is_stop_message(text)', 'b2c.wa_norm_text(text)', 'b2c.send_take(integer)', 'b2c.send_done(jsonb)',
                            'b2c.wa_media_stored(bigint,text,text)', 'b2c.export_take(integer)']) f) x;
insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
