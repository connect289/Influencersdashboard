-- M34c (30 Oct 2026, audit): a refused webhook signature or key is logged at most once a minute per alert type, partner and
-- source, instead of once per call (new helper b2b.log_auth_failure, read through the existing (type, occurred_at) index).
-- b2ccrm_event_ingest, partner_event_ingest, meta_webhook_ingest and google_leadform_ingest are their current definitions
-- (m32b, m15c, m17e) with only that log line changed; their answers are unchanged.
-- Re-appliable. Checked by supabase/tests/test_m34_audit_fixes.sql.

/* A refused signature or key: logged at most once a minute per alert type, partner and payload source.
   Returns the event id, or null when an identical alert was logged in the last minute. */
create or replace function b2b.log_auth_failure(p_type text, p_partner bigint default null, p_payload jsonb default '{}')
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if exists (select 1 from b2b.events e
              where e.type = p_type and e.occurred_at > now() - interval '1 minute'
                and e.partner_id is not distinct from p_partner
                and coalesce(e.payload ->> 'source', '') = coalesce(p_payload ->> 'source', '')) then
    return null;
  end if;
  return b2b.log_event(p_type, null, null, p_partner, coalesce(p_payload, '{}'));
end $fn$;
revoke execute on function b2b.log_auth_failure(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function b2b.log_auth_failure(text, bigint, jsonb) to service_role;

create or replace function b2b.b2ccrm_event_ingest(p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  w b2b.webhook_endpoints;
  j jsonb;
  v_ts bigint;
  v_type text;
  v_event_id text;
  v_lead bigint;
  v_req bigint;
  v_id bigint;
  l public.student_leads;
  cr b2b.consent_requests;
  v_result text;
  v_answer text;
  v_res jsonb;
  v_sent timestamptz;
  v_wait int;
  a record;
  d jsonb;
  v_ch text;
  v_chs text[];
  v_all text[] := array['whatsapp', 'email'];
  v_given boolean;
  v_mc jsonb;
  v_at timestamptz;
  v_val text;
  v_lbl text;
  v_cid bigint;
begin
  perform set_config('b2b.actor', 'b2c_crm', true);
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  if w.id is null or w.secret_id is null then return jsonb_build_object('ok', false, 'status', 503, 'error', 'the B2C connection is not set up'); end if;
  if length(coalesce(p_body, '')) > 100000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  if p_signature is distinct from 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                                     convert_to(b2b.partner_secret(w.secret_id), 'UTF8'), 'sha256'), 'hex') then
    perform b2b.log_auth_failure('alert.b2c_bad_signature', null, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  begin v_lead := (j -> 'data' ->> 'lead_id')::bigint; exception when others then v_lead := null; end;
  begin v_req := nullif(trim(coalesce(j -> 'data' ->> 'request_id', '')), '')::bigint; exception when others then v_req := null; end;
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  insert into b2b.product_events (source, event_id, event_type, lead_id, raw) values ('b2c_crm', v_event_id, v_type, v_lead, j)
  on conflict (source, event_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;

  if v_type not in ('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested',
                    'b2ccrm.partner_consent', 'b2ccrm.consent_request_sent',
                    -- Addendum 4 §4
                    'b2ccrm.marketing_consent', 'b2ccrm.contact_added', 'b2ccrm.lead_updated', 'b2ccrm.commission_booked') then
    update b2b.product_events set status = 'ignored', result = 'unknown event type' where id = v_id;
    return jsonb_build_object('ok', true, 'status', 200, 'result', 'ignored: unknown type');
  end if;
  -- the consent events may name the request instead of the lead
  if v_lead is null and v_req is not null then
    select q.lead_id into v_lead from b2b.consent_requests q where q.id = v_req;
    if v_lead is not null then update b2b.product_events set lead_id = v_lead where id = v_id; end if;
  end if;
  select * into l from public.student_leads where id = v_lead;
  if l.id is null then
    update b2b.product_events set status = 'error',
           result = case when v_type = 'b2ccrm.consent_request_sent' then 'unknown request_id' else 'unknown lead_id' end where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404,
                              'error', case when v_type = 'b2ccrm.consent_request_sent' then 'unknown request_id' else 'unknown lead_id' end);
  end if;

  d := coalesce(j -> 'data', '{}');
  begin
    case v_type
      when 'b2ccrm.marketing_consent' then
        -- Addendum 4 §4: per channel; consent_marketing_at is set while any channel is given, cleared when none is
        v_ch := lower(trim(coalesce(d ->> 'channel', '')));
        if v_ch not in ('whatsapp', 'email') then raise exception 'channel must be whatsapp or email' using errcode = '22023'; end if;
        if jsonb_typeof(d -> 'given') is distinct from 'boolean' then raise exception 'given must be true or false' using errcode = '22023'; end if;
        v_given := (d ->> 'given')::boolean;
        v_at := least(coalesce(b2b.try_timestamptz(d ->> 'at'), now()), now());
        v_mc := coalesce(l.custom_fields -> 'b2c' -> 'marketing_consent', '{}')
                || jsonb_build_object(v_ch, jsonb_strip_nulls(jsonb_build_object('given', v_given, 'at', v_at, 'text_version', left(d ->> 'text_version', 80),
                                                                                 'source', left(d ->> 'source', 40), 'event_id', v_event_id)));
        update public.student_leads
           set custom_fields = coalesce(custom_fields, '{}') || jsonb_build_object('b2c', coalesce(custom_fields -> 'b2c', '{}') || jsonb_build_object('marketing_consent', v_mc)),
               consent_marketing_at = case when exists (select 1 from jsonb_each(v_mc) e where (e.value ->> 'given')::boolean)
                                           then coalesce(consent_marketing_at, v_at) end,
               updated_at = now(), updated_by = 'b2c_crm:marketing_consent'
         where id = l.id;
        if v_given then
          perform b2b.consent_ledger_record(l.id, jsonb_build_object('marketing_at', v_at, 'text_version', d ->> 'text_version'), 'b2c_crm',
                                            jsonb_strip_nulls(jsonb_build_object('channel', v_ch, 'source', d ->> 'source', 'text', left(d ->> 'text', 1000), 'event_id', v_event_id)));
        else
          insert into b2b.lead_consents (lead_id, purpose, state, at, text_version, source, evidence, actor)
          values (l.id, 'marketing', 'withdrawn', v_at, nullif(left(d ->> 'text_version', 80), ''), 'b2c_crm',
                  jsonb_strip_nulls(jsonb_build_object('channel', v_ch, 'source', d ->> 'source', 'event_id', v_event_id)), b2b.actor());
        end if;
        perform b2b.log_event('b2c.marketing_consent', l.id, l.allocation_id, null, d - 'lead_id');
        perform b2b.b2c_sync_lead(l.id, false, 'event:' || v_event_id);
        v_result := 'marketing consent ' || v_ch || ' ' || case when v_given then 'given' else 'withdrawn' end;
      when 'b2ccrm.contact_added' then
        -- Addendum 4 §4: another number or email of the same student; never changes whatsapp_number or email_id
        v_ch := lower(trim(coalesce(d ->> 'kind', '')));
        if v_ch not in ('phone', 'email') then raise exception 'kind must be phone or email' using errcode = '22023'; end if;
        v_val := case when v_ch = 'phone' then public.crm_norm_phone(d ->> 'value') else lower(trim(coalesce(d ->> 'value', ''))) end;
        if v_ch = 'phone' and (v_val is null or length(v_val) not between 11 and 15) then raise exception 'value is not a phone number' using errcode = '22023'; end if;
        if v_ch = 'email' and (v_val !~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$' or length(v_val) > 200) then raise exception 'value is not an email address' using errcode = '22023'; end if;
        v_lbl := lower(trim(coalesce(d ->> 'label', 'alternate')));
        if v_lbl not in ('alternate', 'parent', 'office', 'whatsapp_only') then raise exception 'label must be alternate, parent, office or whatsapp_only' using errcode = '22023'; end if;
        insert into b2b.lead_contacts (lead_id, kind, value, label, primary_for, origin, actor, event_id)
        values (l.id, v_ch, v_val, v_lbl,
                coalesce((select array_agg(lower(x)) from jsonb_array_elements_text(case when jsonb_typeof(d -> 'primary_for') = 'array' then d -> 'primary_for' else '[]'::jsonb end) x), '{}'),
                'b2c', case when jsonb_typeof(d -> 'actor') = 'object' then d -> 'actor' else '{}'::jsonb end, v_event_id)
        on conflict (lead_id, kind, value) do update set label = excluded.label, primary_for = excluded.primary_for, removed_at = null
        returning id into v_cid;
        if v_ch = 'phone' and nullif(trim(coalesce(l.alternate_phone, '')), '') is null and v_val is distinct from public.crm_norm_phone(l.whatsapp_number) then
          update public.student_leads set alternate_phone = v_val, updated_at = now(), updated_by = 'b2c_crm:contact_added' where id = l.id;
        end if;
        perform b2b.log_event('b2c.contact_added', l.id, l.allocation_id, null, jsonb_build_object('kind', v_ch, 'label', v_lbl, 'contact_id', v_cid));
        perform b2b.b2c_sync_lead(l.id, false, 'event:' || v_event_id);
        v_result := v_ch || ' recorded';
      when 'b2ccrm.lead_updated' then
        -- timeline only: the fields themselves arrive in the 15-minute batch
        perform b2b.log_event('b2c.crm_lead_updated', l.id, l.allocation_id, null, d - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.commission_booked' then
        perform b2b.log_event('b2c.commission_booked', l.id, l.allocation_id, null, d - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.lead_assigned' then
        perform b2b.log_event('b2c.counsellor_assigned', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.stage_changed' then
        perform b2b.log_event('b2c.stage_changed', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.enrolled' then
        perform b2b.log_event('b2c.enrolled', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.opted_out' then
        -- Addendum 4 §4: optional channels; is_opted_out only when every channel is out
        if jsonb_typeof(d -> 'channels') = 'array' then
          v_chs := array(select distinct lower(trim(x)) from jsonb_array_elements_text(d -> 'channels') x);
          if cardinality(v_chs) = 0 or exists (select 1 from unnest(v_chs) x where x <> all (v_all)) then
            raise exception 'channels must list whatsapp and/or email' using errcode = '22023';
          end if;
          v_chs := array(select distinct x from unnest(coalesce(l.opted_out_channels, '{}') || v_chs) x order by 1);
          if not (v_all <@ v_chs) then
            update public.student_leads set opted_out_channels = v_chs, updated_at = now(), updated_by = 'b2c_crm:opted_out' where id = l.id;
            update b2b.student_notifications set status = 'cancelled', error = 'student opted out of ' || array_to_string(v_chs, ', ') || ' (B2C CRM)', updated_at = now()
             where lead_id = l.id and status = 'scheduled' and channel = any (v_chs);
            perform b2b.log_event('b2c.opted_out_channels', l.id, l.allocation_id, null, jsonb_build_object('channels', to_jsonb(v_chs)));
            perform b2b.b2c_sync_lead(l.id, false, 'event:' || v_event_id);
            v_result := 'opted out of ' || array_to_string(v_chs, ', ');
            update b2b.product_events set status = 'applied', result = v_result where id = v_id;
            return jsonb_build_object('ok', true, 'status', 200, 'result', v_result);
          end if;
        end if;
        update public.student_leads set opted_out_channels = array(select distinct x from unnest(coalesce(opted_out_channels, '{}') || v_all) x order by 1)
         where id = l.id;
        perform public.lead_intake(jsonb_build_object('phone', l.whatsapp_number, 'source_system', 'b2c_crm', 'event_type', 'lead.opted_out',
                                                      'lead', jsonb_build_object('is_opted_out', true)));
        update b2b.student_notifications set status = 'cancelled', error = 'student opted out (B2C CRM)', updated_at = now()
         where lead_id = l.id and status = 'scheduled';
        -- every partner that ever received the lead must be told (adapters later; an alert for the Admin until then)
        for a in select distinct x.partner_id from b2b.allocations x where x.lead_id = l.id and x.destination_type = 'partner'
                   and x.status in ('pushed', 'accepted', 'duplicate', 'rejected', 'closed') loop
          perform b2b.log_event('alert.partner_optout_notice', l.id, null, a.partner_id, jsonb_build_object('source', 'b2c_crm'));
        end loop;
        v_result := 'opted out';
      when 'b2ccrm.erasure_requested' then
        insert into b2b.erasure_requests (lead_id, source, note) values (l.id, 'b2c_crm', left(j -> 'data' ->> 'note', 300))
        on conflict (lead_id) where status = 'open' do nothing;
        perform b2b.log_event('alert.erasure_requested', l.id, null, null, jsonb_build_object('source', 'b2c_crm'));
        v_result := 'erasure request recorded for the Admin';
      when 'b2ccrm.partner_consent' then
        v_answer := lower(trim(coalesce(j -> 'data' ->> 'answer', '')));
        if v_answer not in ('yes', 'no') then raise exception 'answer must be yes or no' using errcode = '22023'; end if;
        if v_answer = 'yes' and nullif(trim(coalesce(j -> 'data' ->> 'message_id', '')), '') is null then
          raise exception 'message_id is required for a YES' using errcode = '22023';
        end if;
        v_res := b2b.consent_answer(l.id, v_req, v_answer, 'b2c_crm', jsonb_build_object(
                   'message_id', nullif(trim(coalesce(j -> 'data' ->> 'message_id', '')), ''), 'channel', j -> 'data' ->> 'channel',
                   'answered_at', j -> 'data' ->> 'answered_at', 'text_version', j -> 'data' ->> 'text_version', 'event_id', v_event_id));
        v_result := 'consent ' || v_answer || case when coalesce((v_res ->> 'duplicate')::boolean, false) then ': already recorded'
                                                   else ': ' || coalesce(v_res ->> 'effect', 'recorded') end;
      when 'b2ccrm.consent_request_sent' then
        if v_req is null then raise exception 'request_id is required' using errcode = '22023'; end if;
        select * into cr from b2b.consent_requests q where q.id = v_req for update;
        if cr.id is null then raise exception 'unknown request_id' using errcode = '22023'; end if;
        if cr.status in ('queued', 'requested', 'unsendable', 'sent') then
          v_wait := greatest(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'consent_wait_hours' from b2b.settings s where s.key = 'engine')), 48), 1)::int;
          v_sent := least(coalesce(b2b.try_timestamptz(j -> 'data' ->> 'sent_at'), now()), now());
          update b2b.consent_requests
             set status = 'sent', sent_at = v_sent, published_at = coalesce(published_at, v_sent), expires_at = v_sent + make_interval(hours => v_wait),
                 evidence = evidence || jsonb_build_object('sent_message_id', j -> 'data' ->> 'message_id', 'sent_event_id', v_event_id)
           where id = cr.id returning * into cr;
          if cr.context = 'decision' and l.destination_type is null then
            perform b2b.lead_wait_set(l.id, cr.expires_at, 'awaiting partner-sharing consent', l.updated_at);
          end if;
          v_result := 'sent at ' || v_sent::text || '; expires at ' || cr.expires_at::text;
        else
          v_result := 'ignored: request is ' || cr.status;
        end if;
    end case;
    update b2b.product_events set status = 'applied', result = v_result where id = v_id;
  exception
    when sqlstate '22023' then
      update b2b.product_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
      return jsonb_build_object('ok', false, 'status', 422, 'error', sqlerrm);
    when others then
      update b2b.product_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
      return jsonb_build_object('ok', false, 'status', 500, 'error', 'stored; it will be reviewed');
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', v_result);
end $fn$;

create or replace function b2b.partner_event_ingest(p_slug text, p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  j jsonb;
  a b2b.allocations;
  v_expected text;
  v_type text;
  v_event_id text;
  v_id bigint;
  v_ts bigint;
  x jsonb;
begin
  perform set_config('b2b.actor', 'partner', true);
  select * into p from b2b.partners where slug = lower(trim(p_slug));
  if p.id is null or p.inbound_secret_id is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'unknown partner'); end if;
  if length(coalesce(p_body, '')) > 200000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  v_expected := 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                    convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex');
  if p_signature is distinct from v_expected then
    perform b2b.log_auth_failure('alert.partner_bad_signature', p.id, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  -- find the allocation by our reference (EDW-<id>), else by the partner's record id
  select * into a from b2b.allocations x
   where x.partner_id = p.id and (x.reference = j ->> 'reference' or (j ->> 'record_id' is not null and x.partner_record_id = j ->> 'record_id'))
   order by x.created_at desc limit 1;

  insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
  values (p.id, v_event_id, v_type, j ->> 'reference', j ->> 'record_id', a.id, a.lead_id, j)
  on conflict (partner_id, event_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no lead matches this reference');
  end if;

  x := b2b.partner_event_apply(v_id);
  if x ->> 'status' = 'error' then
    return jsonb_build_object('ok', false, 'status', 500, 'error', 'could not apply the event; it is stored and will be reviewed');
  end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', coalesce(x ->> 'result', 'stored'));
end $fn$;

create or replace function b2b.meta_webhook_ingest(p_body text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_secret text := b2b.intake_secret('meta.app_secret_id');
  j jsonb;
  ch jsonb;
  n int := 0;
begin
  if v_secret is null then return jsonb_build_object('ok', false, 'status', 503, 'error', 'Meta is not connected'); end if;
  if p_signature is distinct from 'sha256=' || encode(extensions.hmac(convert_to(p_body, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'), 'hex') then
    perform b2b.log_auth_failure('alert.intake_bad_signature', null, jsonb_build_object('source', 'meta'));
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  for ch in select c from jsonb_array_elements(coalesce(j -> 'entry', '[]')) e, jsonb_array_elements(coalesce(e -> 'changes', '[]')) c
             where c ->> 'field' = 'leadgen' and c -> 'value' ->> 'leadgen_id' is not null loop
    insert into b2b.intake_requests (source, idempotency_key, form_ref, raw, status)
    values ('meta', ch -> 'value' ->> 'leadgen_id', ch -> 'value' ->> 'form_id', ch -> 'value', 'received')
    on conflict (source, idempotency_key) do nothing;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('leads', n));
end $fn$;

create or replace function b2b.google_leadform_ingest(p_body text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_key text := b2b.intake_secret('google.key_id');
  j jsonb;
  v_id bigint;
  m jsonb;
  f jsonb;
  v_res jsonb;
  v_form text;
  v_test boolean;
begin
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  if v_key is null then return jsonb_build_object('ok', false, 'status', 503, 'error', 'Google lead forms are not connected'); end if;
  if j ->> 'google_key' is distinct from v_key then
    perform b2b.log_auth_failure('alert.intake_bad_signature', null, jsonb_build_object('source', 'google'));
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad google_key');
  end if;
  if nullif(j ->> 'lead_id', '') is null then return jsonb_build_object('ok', false, 'status', 400, 'error', 'lead_id is missing'); end if;
  v_form := coalesce(j ->> 'form_id', 'unknown');
  v_test := coalesce((j ->> 'is_test')::boolean, false);
  insert into b2b.intake_requests (source, idempotency_key, form_ref, raw, status, is_test)
  values ('google', j ->> 'lead_id', v_form, j - 'google_key', 'received', v_test)
  on conflict (source, idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;

  begin
    if not exists (select 1 from b2b.lead_forms where platform = 'google' and form_ref = v_form) then
      insert into b2b.lead_forms (platform, form_ref, name) values ('google', v_form, 'Google form ' || v_form) on conflict do nothing;
      perform b2b.log_event('alert.intake_new_form', null, null, null, jsonb_build_object('platform', 'google', 'form_id', v_form));
    end if;
    m := b2b.form_answers_to_lead('google', v_form,
           (select coalesce(jsonb_agg(jsonb_build_object('key', coalesce(x ->> 'column_id', x ->> 'column_name'), 'value', x ->> 'string_value')), '[]')
              from jsonb_array_elements(coalesce(j -> 'user_column_data', '[]')) x));
    f := m -> 'form';
    v_res := b2b.intake_lead(m -> 'lead', jsonb_build_object(
      'source_system', 'google', 'lead_source', 'google_lead_form', 'channel', 'google_lead_forms', 'campaign', f ->> 'campaign',
      'utm', jsonb_build_object('source', 'google', 'medium', 'cpc'),
      'click_ids', jsonb_strip_nulls(jsonb_build_object('google_lead_id', j ->> 'lead_id', 'gclid', j ->> 'gcl_id', 'form_id', v_form,
                                                        'campaign_id', j ->> 'campaign_id', 'adgroup_id', j ->> 'adgroup_id', 'creative_id', j ->> 'creative_id')),
      'consent', jsonb_build_object('sales_at', now(),
                                    'partner_share_at', case when 'partner_share' = any (array(select jsonb_array_elements_text(coalesce(f -> 'consent_purposes', '[]')))) then now() end,
                                    'marketing_at', case when 'marketing' = any (array(select jsonb_array_elements_text(coalesce(f -> 'consent_purposes', '[]')))) then now() end,
                                    'text_version', coalesce(f ->> 'consent_version', 'google_form:' || v_form)),
      'idempotency_key', 'google:' || (j ->> 'lead_id'), 'is_test', v_test,
      'attribution', jsonb_build_object('platform', 'google', 'form_id', v_form, 'campaign_id', j ->> 'campaign_id', 'gclid', j ->> 'gcl_id', 'unmapped', m -> 'unmapped')));
    update b2b.intake_requests set status = 'done', result = v_res, lead_id = (v_res ->> 'lead_id')::bigint, done_at = now() where id = v_id;
    return jsonb_build_object('ok', true, 'status', 200, 'result', 'stored');
  exception when others then
    update b2b.intake_requests set status = 'error', error = left(sqlerrm, 300) where id = v_id;
    return jsonb_build_object('ok', true, 'status', 200, 'result', 'stored for review');
  end;
end $fn$;

-- create or replace keeps each function's grants; restated: the public key reaches the four (their routes use it)
revoke execute on function b2b.b2ccrm_event_ingest(text, text, text), b2b.partner_event_ingest(text, text, text, text),
                           b2b.meta_webhook_ingest(text, text), b2b.google_leadform_ingest(text) from public;
grant execute on function b2b.b2ccrm_event_ingest(text, text, text), b2b.partner_event_ingest(text, text, text, text),
                          b2b.meta_webhook_ingest(text, text), b2b.google_leadform_ingest(text) to anon, authenticated, service_role;

-- rollback: re-run the create or replace function of b2b.b2ccrm_event_ingest (m32b_a4_b2c_events_reads.sql),
-- b2b.partner_event_ingest (20261006221943_m15c_mapping_runtime.sql), b2b.meta_webhook_ingest and
-- b2b.google_leadform_ingest (20261007005350_m17e_intake_api_webhooks.sql); b2b.log_auth_failure can stay (unused) or be
-- dropped from pending/ (this folder keeps DROP out of migrations).
