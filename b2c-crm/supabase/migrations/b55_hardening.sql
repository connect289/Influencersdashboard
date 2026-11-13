-- B2C CRM b55 (13 Nov 2026): hardening after the November audit. Staging first. Idempotent.
--
-- 1. Erasure: b2c.lead_erase also queues every WhatsApp file of the lead (wa_messages.media_path, bucket b2c-documents)
--    for removal through the storage API (b2c.erase_files, the app's erase job), and clears media_path and the number
--    on those messages (phone becomes 'erased:<lead>', as on the conversation; the column is required). A media fetch
--    that finishes after the erasure no longer records its file: b2c.wa_media_stored queues it for removal instead.
-- 2. Expired exports: b2c.export_take queues the expired file (bucket b2c-exports) on the same removal queue before it
--    clears the path, so it is deleted from storage, not only forgotten. erase_files.lead_id may now be empty (exports
--    belong to no lead).
-- 3. STOP on WhatsApp (b2c.wa_inbound): the opt-out words are matched first, on the message lower-cased, without
--    punctuation or emoji and with single spaces (b2c.wa_norm_text): the message is a stop word or phrase, starts with
--    one, or has at most 5 words and contains one ("Stop.", "STOP!!", "please stop", "stop messaging me"). The words are
--    Settings → opt_out_words plus the built-in list (b2c.is_stop_message), which adds "unsub" and Devanagari. A STOP
--    from a number Spark does not know is suppressed (b2c.suppressions) and is not sent to the B2B CRM as a new lead; a
--    STOP from a lead in active sales is recorded (b2c.opt_out) and the counsellor is told. START is unchanged.
-- 4. Opt-out at send time: b2c.send_take cancels, instead of sending, a message whose lead may no longer be messaged
--    (b2c.may_message) and a marketing message (journey, campaign, marketing) to a suppressed address, so a message
--    released (send_release) or queued again (send_done) after a STOP or an erasure never goes out. b2c.suppress()
--    cancels queued marketing messages to the address it suppresses.
-- 5. Ambiguous failures: send_done takes "retry": false on a result (the app's "it may have gone out": no answer from
--    Meta in time, or a 5xx): the message is failed and never queued again, as b2c.send_unstick does.
-- 6. b2c.enrollment_record locks the lead and refuses a lead that is closed, lost, deleted or erased, and a lead that
--    already has a reported or verified enrolment.
-- 10. b2c.wa_unmatched_thread(phone): the Admin reads a conversation from a number with no Spark lead yet (read-only).
--
-- Rollback: run the previous definitions again (b40 lead_erase, b41 wa_media_stored, b43 export_take, b39 wa_inbound,
-- b53 send_take, b42 send_done, b14 suppress, b7 enrollment_record); drop b2c.wa_norm_text, b2c.is_stop_message and
-- b2c.wa_unmatched_thread. erase_files.lead_id can be made required again once no row has it empty.

-- ---------- 1, 2: the file-removal queue also takes export files (no lead) ----------
alter table b2c.erase_files alter column lead_id drop not null;

-- ---------- 1. erasure: WhatsApp files and numbers too (b40's definition otherwise) ----------
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
  -- files go through the storage API (the app's erase job), never by deleting rows; WhatsApp files are queued before
  -- their paths are cleared below
  insert into b2c.erase_files (lead_id, bucket, path)
  select p_lead, 'b2c-documents', d.storage_path from b2c.documents d where d.lead_id = p_lead and d.removed_at is null
  union all select p_lead, 'b2c-recordings', c.recording_path from b2c.calls c where c.lead_id = p_lead and c.recording_path is not null
  union all select distinct p_lead, 'b2c-documents', m.media_path from b2c.wa_messages m
             where m.lead_id = p_lead and m.media_path is not null
               and not exists (select 1 from b2c.documents d where d.lead_id = p_lead and d.removed_at is null and d.storage_path = m.media_path);
  get diagnostics n_doc = row_count;
  update b2c.wa_messages set body = null, media = null, media_path = null, phone = 'erased:' || p_lead where lead_id = p_lead;
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

/* The media job stored a file (b41): recorded on the message, unless the lead was erased meanwhile; then the file just
   uploaded is queued for removal and nothing is recorded. */
create or replace function b2c.wa_media_stored(p_message bigint, p_path text, p_error text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint;
begin
  select m.lead_id into v_lead from b2c.wa_messages m join b2c.leads_state s on s.lead_id = m.lead_id
   where m.id = p_message and m.direction = 'in' and s.erased_at is not null;
  if v_lead is not null then
    if p_error is null and p_path is not null and p_path ~ ('^leads/' || v_lead || '/') then
      insert into b2c.erase_files (lead_id, bucket, path) values (v_lead, 'b2c-documents', p_path);
    end if;
    return;
  end if;
  update b2c.wa_messages set media_path = case when p_error is null then p_path end, media_error = left(p_error, 300)
   where id = p_message and direction = 'in' and (p_path is null or p_path ~ ('^leads/' || lead_id || '/'));
end $f$;

-- ---------- 2. an expired export's file is removed from storage (b43's definition otherwise) ----------
create or replace function b2c.export_take(p_limit integer default 2) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with e as (select id, path from b2c.exports where status = 'ready' and expires_at < now() for update),
       f as (insert into b2c.erase_files (lead_id, bucket, path) select null, 'b2c-exports', e.path from e where e.path is not null)
  update b2c.exports x set status = 'expired', path = null from e where x.id = e.id;
  -- a job that died part-way is tried again (at most 3 times)
  update b2c.exports set status = case when attempts >= 3 then 'failed' else 'queued' end, error = coalesce(error, 'the export job stopped part-way')
   where status = 'running' and coalesce(done_at, created_at) < now() - interval '15 minutes' and created_at < now() - interval '15 minutes';
  with t as (select id from b2c.exports where status = 'queued' and attempts < 3 order by id limit p_limit for update skip locked),
       m as (update b2c.exports e set status = 'running', attempts = e.attempts + 1 from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id, 'params', m.params, 'format', m.format)), '[]') into v from m;
  return v;
end $f$;

-- ---------- 3. STOP on WhatsApp ----------
/* A message as the opt-out words are matched: lower case; punctuation, symbols and emoji gone (letters and digits of
   English and Devanagari kept); single spaces. */
create or replace function b2c.wa_norm_text(p text) returns text language sql immutable set search_path = '' as $f$
  select trim(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p, '')), '[​-‍⁠︎️]', '', 'g'),
                                            '[^a-z0-9À-ɏऀ-ॣ०-ॿ]+', ' ', 'g'), '\s+', ' ', 'g'))
$f$;

/* Whether a WhatsApp text asks to stop: it is a stop word or phrase, starts with one, or is at most 5 words and contains
   one. The words: Settings → opt_out_words and the built-in list (the b1 defaults, "unsub" and Devanagari; the bare word बंद is left out because it also means "closed"). */
create or replace function b2c.is_stop_message(p_text text) returns boolean language sql stable security definer set search_path = '' as $f$
  with m as (select b2c.wa_norm_text(p_text) as t),
       w as (select distinct b2c.wa_norm_text(x) as word
               from (select jsonb_array_elements_text(case when jsonb_typeof(b2c.setting('opt_out_words') -> 'words') = 'array' then b2c.setting('opt_out_words') -> 'words' else '[]'::jsonb end) as x
                     union all
                     select unnest(array['stop', 'unsubscribe', 'unsub', 'band karo', 'bandh karo', 'mat bhejo', 'no more messages',
                                         'बंद करो', 'मत भेजो', 'रोको'])) a)
  select exists (select 1 from m, w
                  where m.t <> '' and w.word <> ''
                    and (m.t = w.word or m.t like w.word || ' %'
                         or (cardinality(string_to_array(m.t, ' ')) <= 5 and ' ' || m.t || ' ' like '% ' || w.word || ' %')))
$f$;

-- WhatsApp in (b39), with the opt-out words checked first
create or replace function b2c.wa_inbound(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_phone text := b2c.norm_phone(p ->> 'from'); v_text text := trim(coalesce(p ->> 'text', p ->> 'button', p -> 'media' ->> 'caption', ''));
  v_lead bigint; s b2c.leads_state; v_low text := lower(trim(coalesce(p ->> 'text', p ->> 'button', ''))); q b2c.consent_requests; v_ans text; v_id bigint;
  v_stop boolean := b2c.is_stop_message(coalesce(p ->> 'text', p ->> 'button', ''));
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
    -- a STOP from a number Spark does not know: never market to it, and no new-lead request
    if v_stop then
      perform b2c.suppress(v_phone, 'stop_word');
      return jsonb_build_object('status', 'suppressed');
    end if;
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

  if v_stop then
    perform b2c.opt_out(v_lead, null, 'stop_word', v_text);
    -- a lead in active sales: the counsellor sees it too
    if s.owner_id is not null and s.status = 'active' then
      perform b2c.notify(s.owner_id, 'whatsapp', coalesce(b2c.first_name(v_lead), 'A student') || ' asked to stop WhatsApp messages', left(v_text, 200),
                         '/s/inbox?lead=' || v_lead, v_lead, null);
      perform b2c.queue_activity(v_lead, 'whatsapp', now(), 'reply', null, left(v_text, 500));
    end if;
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

-- ---------- 4. opt-out and suppression checked again at send time (b53's definition otherwise) ----------
create or replace function b2c.send_take(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v jsonb; v_ids bigint[];
begin
  select coalesce(array_agg(c.id), '{}') into v_ids
    from (select id from b2c.send_queue where status = 'queued' and not_before <= now()
             and not (purpose = 'assignment' and channel = 'whatsapp' and lead_id is not null and b2c.witty_busy(lead_id))
           order by not_before limit p_limit for update skip locked) c;
  -- no longer allowed (opted out, erased, deleted, gone to a partner; marketing to a suppressed address): cancelled
  with x as (update b2c.send_queue q set status = 'cancelled', taken_at = null,
                    error = 'not sent: ' || coalesce(case when q.lead_id is not null then b2c.may_message(q.lead_id) end, 'suppressed')
              where q.id = any (v_ids)
                and ((q.lead_id is not null and b2c.may_message(q.lead_id) is not null)
                     or (q.purpose in ('journey', 'campaign', 'marketing')
                         and exists (select 1 from b2c.suppressions sp where sp.lifted_at is null
                                        and sp.value_norm = case when q.channel = 'email' then lower(trim(q.to_address)) else b2c.norm_phone(q.to_address) end)))
             returning q.wa_message_id)
  update b2c.wa_messages w set status = 'cancelled', status_at = now() from x where w.id = x.wa_message_id and w.status = 'queued';
  with u as (update b2c.send_queue q set status = 'sending', attempts = attempts + 1, taken_at = now() where q.id = any (v_ids) and q.status = 'queued'
             returning q.id, q.channel, q.lead_id, q.to_address, q.payload, q.purpose, q.wa_message_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'channel', u.channel, 'lead_id', u.lead_id, 'to', u.to_address, 'payload', u.payload,
                  'purpose', u.purpose, 'wa_message_id', u.wa_message_id,
                  'live', b2c.live(u.channel) and not b2c.is_test_phone(u.to_address) and not coalesce((select s.is_test from b2c.leads_state s where s.lead_id = u.lead_id), false))), '[]')
    into v from u;
  return v;
end $f$;

/* Global suppression (B9.6), as in b14; suppressing also cancels the marketing messages queued to that address. */
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
    with x as (update b2c.send_queue q set status = 'cancelled', error = 'not sent: suppressed'
                where q.status = 'queued' and q.purpose in ('journey', 'campaign', 'marketing')
                  and q.channel = case when v_kind = 'email' then 'email' else 'whatsapp' end
                  and case when v_kind = 'email' then lower(trim(q.to_address)) else b2c.norm_phone(q.to_address) end = v_norm
               returning q.wa_message_id)
    update b2c.wa_messages w set status = 'cancelled', status_at = now() from x where w.id = x.wa_message_id and w.status = 'queued';
  else
    update b2c.suppressions set lifted_at = now() where value_norm = v_norm;
  end if;
end $f$;

-- ---------- 5. a result that may have gone out is failed, never queued again (b42's definition otherwise) ----------
create or replace function b2c.send_done(p_results jsonb) returns integer
language plpgsql security definer set search_path = '' as $f$
declare r jsonb; q b2c.send_queue; n int := 0; v_status text;
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]')) loop
    select * into q from b2c.send_queue where id = (r ->> 'id')::bigint for update;
    continue when q.id is null or q.status <> 'sending';
    v_status := case when coalesce((r ->> 'ok')::boolean, false) then case when coalesce((r ->> 'dry_run')::boolean, false) then 'dry_run' else 'sent' end
                     when q.attempts >= 5 or not coalesce((r ->> 'retry')::boolean, true) then 'failed' else 'queued' end;
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

-- ---------- 6. one enrolment per lead, on an active lead only (b7's definition otherwise) ----------
create or replace function b2c.enrollment_record(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint := (p ->> 'lead_id')::bigint; me uuid := b2c.require_lead(v_lead); v bigint; v_sub text; s b2c.leads_state;
begin
  if nullif(p ->> 'fee', '') is null or nullif(p ->> 'enrolled_on', '') is null or coalesce(p ->> 'proof_path', '') = '' then
    raise exception 'an enrolment needs the fee amount, the enrolment date and the proof';
  end if;
  select * into s from b2c.leads_state where lead_id = v_lead for update;
  if s.lead_id is null or s.status <> 'active' or s.stage_id = 10 or s.deleted_at is not null or s.erased_at is not null then
    raise exception 'this lead is closed, lost or erased, so an enrolment cannot be recorded on it';
  end if;
  if exists (select 1 from b2c.enrollments e where e.lead_id = v_lead and e.status in ('reported', 'verified')) then
    raise exception 'this lead already has an enrolment (reported or verified); ask the Admin to correct that one instead';
  end if;
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

-- ---------- 10. the Admin reads a conversation from a number with no Spark lead yet ----------
/* The messages of a conversation whose number matches no Spark lead (a new student waiting for the B2B CRM to route
   it). Admin only, read-only: nothing is marked read and nothing can be sent from here. */
create or replace function b2c.wa_unmatched_thread(p_phone text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare c b2c.wa_conversations;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from b2c.wa_conversations where phone = b2c.norm_phone(p_phone);
  if c.phone is null then raise exception 'unknown conversation'; end if;
  if c.lead_id is not null then raise exception 'this conversation belongs to a lead: open it from the lead'; end if;
  return jsonb_build_object('phone', c.phone, 'last_inbound_at', c.last_inbound_at,
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'kind', m.kind, 'template_name', m.template_name, 'body', m.body,
                                                              'status', m.status, 'created_at', m.created_at, 'media', m.media) order by m.created_at, m.id), '[]')
                   from (select * from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc, m.id desc limit 100) m));
end $f$;

-- ---------- grants ----------
-- Redefined functions keep their grants (create or replace, same signatures). The new helpers run only inside Spark's
-- own functions; the unmatched thread is for signed-in staff (the function checks the Admin role).
revoke execute on function b2c.wa_norm_text(text), b2c.is_stop_message(text) from public, anon, authenticated;
grant execute on function b2c.wa_norm_text(text), b2c.is_stop_message(text) to service_role;
grant execute on function b2c.wa_unmatched_thread(text) to authenticated;
grant all on all tables in schema b2c to service_role;

-- last: nothing in b2c is executable by PUBLIC or anon
revoke execute on all functions in schema b2c from public, anon;
