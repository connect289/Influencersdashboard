-- M32b Addendum 4 (14 Oct, Vikas): the B2C CRM link, final shape, part 2: inbound events, contacts, reads.
--   (1) b2b.lead_contacts      NEW: other numbers and emails of a student, recorded by the B2C CRM (b2ccrm.contact_added).
--                              They count in duplicate detection (intake) and in the B2C lookup. whatsapp_number and
--                              email_id never change.
--   (2) b2ccrm_event_ingest    REPLACED (m31e): b2ccrm.marketing_consent (per channel, consent_marketing_at, the consent
--                              ledger), b2ccrm.opted_out with optional channels (is_opted_out only when every channel is
--                              out), b2ccrm.contact_added, and b2ccrm.lead_updated / b2ccrm.commission_booked (timeline).
--                              b2ccrm.stage_changed keeps its whole data (b2c_stage, b2c_sub_stage, comment,
--                              canonical_stage) on the timeline.
--   (3) intake_lead            REPLACED (m31h): a phone recorded in lead_contacts for a known student is that student.
--   (4) api_b2c_lead_lookup    REPLACED (m22b): matches lead_contacts too; a lead the B2C CRM does not hold answers
--                              holder {destination partner|unrouted|not_passed, partner_name, since}, no personal data.
--   (5) api_b2c_partner_history NEW: GET /v1/b2c/leads/{id}/partner-history, for leads the B2C CRM holds.
--   (6) api_b2c_schema         REPLACED (m31j): contract_version 4, the batch rules, groups, the registered consent
--                              texts, the new inbound types; b2c.leads_batch is no longer offered to the B2C CRM.
-- No triggers on student_leads; nothing dropped. Re-appliable.

create table if not exists b2b.lead_contacts (
  id           bigint generated always as identity primary key,
  lead_id      bigint not null,
  kind         text not null check (kind in ('phone', 'email')),
  value        text not null check (length(value) between 3 and 200),
  label        text not null default 'alternate' check (label in ('alternate', 'parent', 'office', 'whatsapp_only')),
  primary_for  text[] not null default '{}',
  origin       text not null default 'b2c' check (origin in ('b2c', 'admin')),
  actor        jsonb not null default '{}',
  event_id     text,
  added_at     timestamptz not null default now(),
  removed_at   timestamptz,
  unique (lead_id, kind, value)
);
create index if not exists lead_contacts_value_idx on b2b.lead_contacts (kind, value) where removed_at is null;
alter table b2b.lead_contacts enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'lead_contacts' and policyname = 'admin_read') then
    create policy admin_read on b2b.lead_contacts for select to authenticated using ((select b2b.is_admin()));
  end if;
end $p$;
revoke all on b2b.lead_contacts from public, anon, authenticated;
grant select on b2b.lead_contacts to authenticated;
grant all on b2b.lead_contacts to service_role;

-- ---------- (2) inbound events ----------
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
    perform b2b.log_event('alert.b2c_bad_signature', null, null, null, '{}');
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

-- ---------- (3) intake ----------
create or replace function b2b.intake_lead(p_lead jsonb, p_opts jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_fields jsonb := b2b.import_fields();
  v_lead jsonb := '{}';
  c jsonb := case when jsonb_typeof(p_opts -> 'consent') = 'object' then p_opts -> 'consent' else '{}'::jsonb end;
  d jsonb := p_opts -> 'directive';
  v_res jsonb;
  v_id bigint;
  l public.student_leads;
  r jsonb;
  o jsonb;
  k text;
  v text;
  x text;
  v_phone text := public.crm_norm_phone(p_lead ->> 'phone');
  v_sys text := coalesce(p_opts ->> 'source_system', 'api');
  v_isrc text := case v_sys when 'meta' then 'meta' when 'google' then 'google' when 'manual' then 'manual' when 'import' then 'import'
                            when 'witty' then 'witty' when 'web_agent' then 'web_agent' when 'b2c' then 'b2c' when 'b2c_crm' then 'b2c' else 'api' end;
  v_csrc text := case v_sys when 'meta' then 'meta_form' when 'google' then 'google_form' when 'manual' then 'manual' when 'import' then 'import'
                            when 'witty' then 'witty' when 'b2c_crm' then 'b2c_crm' else 'api' end;
  v_ver text := nullif(trim(coalesce(c ->> 'text_version', '')), '');
  v_warn text[] := '{}';
  v_course text;
  v_prim jsonb;
  v_added int := 0;
begin
  if v_phone is null or length(v_phone) < 10 then raise exception 'phone is missing or too short' using errcode = '22023'; end if;
  -- Addendum 4 §4: a number the B2C CRM recorded for a known student (b2b.lead_contacts) is that student
  if not exists (select 1 from public.student_leads s where s.whatsapp_number = v_phone and s.deleted_at is null and s.merged_into_id is null) then
    select s.whatsapp_number into x
      from b2b.lead_contacts lc join public.student_leads s on s.id = lc.lead_id
     where lc.kind = 'phone' and lc.value = v_phone and lc.removed_at is null
       and s.deleted_at is null and s.merged_into_id is null and s.anonymised_at is null
     order by lc.added_at desc limit 1;
    if x is not null then
      v_warn := array_append(v_warn, 'matched a number recorded for an existing student');
      v_phone := x;
      x := null;
    end if;
  end if;
  for k, v in select key, value #>> '{}' from jsonb_each(p_lead) loop
    continue when k = 'phone' or v is null or trim(v) = '' or not (v_fields ? k) or v_fields ->> k is null;
    v_lead := v_lead || jsonb_build_object(v_fields ->> k, left(trim(v), 500));
  end loop;
  if p_lead ->> 'full_name' is null and coalesce(p_lead ->> 'first_name', p_lead ->> 'last_name') is not null then
    v_lead := v_lead || jsonb_build_object('full_name', trim(concat_ws(' ', p_lead ->> 'first_name', p_lead ->> 'last_name')));
  end if;
  if v_lead ? 'email' then
    if lower(v_lead ->> 'email') ~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$' then v_lead := jsonb_set(v_lead, '{email}', to_jsonb(lower(v_lead ->> 'email')));
    else v_lead := v_lead - 'email'; end if;
  end if;
  v_lead := v_lead || jsonb_strip_nulls(jsonb_build_object(
    'source', p_opts ->> 'lead_source', 'channel', p_opts ->> 'channel', 'campaign', coalesce(p_opts ->> 'campaign', v_lead ->> 'campaign'),
    'click_ids', p_opts -> 'click_ids',
    'utm_source', coalesce(p_opts -> 'utm' ->> 'source', v_lead ->> 'utm_source'), 'utm_medium', coalesce(p_opts -> 'utm' ->> 'medium', v_lead ->> 'utm_medium'),
    'utm_campaign', coalesce(p_opts -> 'utm' ->> 'campaign', v_lead ->> 'utm_campaign'),
    'landing_url', p_opts ->> 'landing_url',
    'consent_sales_at', b2b.try_timestamptz(c ->> 'sales_at'), 'consent_partner_share_at', b2b.try_timestamptz(c ->> 'partner_share_at'),
    'consent_marketing_at', b2b.try_timestamptz(c ->> 'marketing_at'), 'consent_text_version', v_ver));

  v_res := public.lead_intake(jsonb_strip_nulls(jsonb_build_object(
    'phone', v_phone, 'source_system', v_sys, 'event_type', coalesce(p_opts ->> 'event_type', 'lead.created'),
    'lead', v_lead, 'idempotency_key', p_opts ->> 'idempotency_key', 'occurred_at', b2b.try_timestamptz(p_opts ->> 'occurred_at'),
    'attribution', coalesce(p_opts -> 'attribution', '{}'), 'is_test', case when coalesce((p_opts ->> 'is_test')::boolean, false) then true end)));
  v_id := (v_res ->> 'lead_id')::bigint;

  select * into l from public.student_leads where id = v_id;
  if d is not null and l.destination_type is null then
    insert into b2b.intake_directives (lead_id, source, directive, b2c_lane, phone_trusted)
    values (v_id, coalesce(p_opts ->> 'directive_source', 'api'), coalesce(d ->> 'directive', 'route'), d ->> 'b2c_lane', coalesce((d ->> 'phone_trusted')::boolean, false))
    on conflict (lead_id) do update set source = excluded.source, import_id = null, directive = excluded.directive, b2c_lane = excluded.b2c_lane,
                                        phone_trusted = b2b.intake_directives.phone_trusted or excluded.phone_trusted,
                                        created_at = now(), released_at = null, released_by = null;
  end if;

  -- secondary interests (D30): a different course on an existing lead (lead_intake keeps the stored course for these
  -- sources), then other_courses; lead_interest_add skips the primary interest and repeats
  v_course := nullif(trim(coalesce(v_lead ->> 'interested_course', '')), '');
  if v_course is not null and coalesce(v_res ->> 'action', '') <> 'created' then
    v_prim := b2b.lead_interest(l);
    if coalesce(v_prim ->> 'course_key', lower(coalesce(v_prim ->> 'course_text', ''))) is distinct from coalesce(b2b.match_course_key(v_course), lower(v_course)) then
      if b2b.lead_interest_add(v_id, jsonb_strip_nulls(jsonb_build_object('course', v_course, 'specialization', v_lead ->> 'interested_specialization',
                                 'level', v_lead ->> 'programme_level', 'mode', v_lead ->> 'study_mode_preference', 'university', v_lead ->> 'interested_university')), v_isrc) then
        v_added := v_added + 1;
      end if;
    end if;
  end if;
  foreach x in array b2b.other_courses_list(p_lead -> 'other_courses') loop
    if b2b.lead_interest_add(v_id, to_jsonb(x), v_isrc) then v_added := v_added + 1; end if;
  end loop;

  -- the consent ledger (D8) and the wording warnings (PART 7.1)
  if coalesce(c ->> 'sales_at', c ->> 'partner_share_at', c ->> 'marketing_at') is not null then
    perform b2b.consent_ledger_record(v_id, c, v_csrc,
              jsonb_strip_nulls(jsonb_build_object('source_system', v_sys, 'lead_source', p_opts ->> 'lead_source', 'channel', p_opts ->> 'channel',
                                                   'idempotency_key', p_opts ->> 'idempotency_key'))
              || case when jsonb_typeof(c -> 'evidence') = 'object' then c -> 'evidence' else '{}'::jsonb end);
    if v_ver is null or not exists (select 1 from b2b.consent_texts t where t.version = v_ver) then
      v_warn := array_append(v_warn, 'consent text version not registered');
    end if;
    if c ->> 'partner_share_at' is not null and not b2b.consent_text_covers(v_ver) then
      v_warn := array_append(v_warn, 'consent text does not cover admission partners');
    end if;
  end if;

  r := b2b.lead_readiness(l);
  o := b2b.route_outlook(l);
  return jsonb_build_object('lead_id', v_id, 'action', v_res ->> 'action', 'is_test', (v_res ->> 'is_test')::boolean,
    'warnings', to_jsonb(v_warn), 'outlook', o ->> 'outlook', 'interests_added', v_added,
    'routing', jsonb_build_object(
      'status', case when l.destination_type is not null then 'already_routed'
                     when (r ->> 'ready')::boolean then 'queued' else 'waiting' end,
      'destination', l.destination_type,
      'outlook', o ->> 'outlook', 'outlook_reason', o ->> 'reason', 'outlook_lane', o ->> 'lane',
      'waiting_for', r -> 'missing', 'missing', r -> 'not_qualified'));
end $fn$;

/* GET /v1/b2c/leads?phone= | ?email=: the student's leads by their own number or email, or one the B2C CRM recorded
   (lead_contacts). A lead the B2C CRM holds (or every live lead under scope 'all') comes with its record; any other
   answers only holder {destination, partner_name, since}, so a counsellor sees "Already with {partner} since {date}". */
create or replace function b2b.api_b2c_lead_lookup(p_key text, p_phone text, p_email text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if length(v_phone) = 10 then v_phone := '91' || v_phone; end if;
  if length(v_phone) < 11 and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'give a phone number or an email address');
  end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('contract_version', 4, 'leads', coalesce((
    select jsonb_agg(jsonb_build_object('lead_id', l.id, 'version', b2b.b2c_version(l.id), 'held_by_b2c', coalesce(b2b.b2c_holds(l), false),
                                        'matched_on', m.how,
                                        'record', case when b2b.b2c_holds(l) or cfg ->> 'scope' = 'all' then b2b.b2c_record(l) end,
                                        'holder', case when not coalesce(b2b.b2c_holds(l), false) then jsonb_build_object(
                                            'destination', case when l.destination_type = 'partner' then 'partner'
                                                                when exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null) then 'not_passed'
                                                                when l.destination_type is null then 'unrouted'
                                                                else l.destination_type end,
                                            'partner_name', case when l.destination_type = 'partner' then
                                                (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = l.partner_id) end,
                                            'since', case when l.destination_type is not null then l.allocated_at else l.created_at end) end)
                     order by l.id desc)
      from public.student_leads l
      join lateral (
        select string_agg(distinct w, ',') how from (
          select 'phone' w where length(v_phone) >= 11 and regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = v_phone
          union all select 'email' where v_email <> '' and lower(l.email_id) = v_email
          union all select 'contact' where exists (select 1 from b2b.lead_contacts lc where lc.lead_id = l.id and lc.removed_at is null
                                                     and ((lc.kind = 'phone' and length(v_phone) >= 11 and lc.value = v_phone)
                                                          or (lc.kind = 'email' and v_email <> '' and lc.value = v_email)))) z) m on m.how is not null
     where l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null
       and (   (length(v_phone) >= 11 and regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = v_phone)
            or (v_email <> '' and lower(l.email_id) = v_email)
            or l.id in (select lc.lead_id from b2b.lead_contacts lc
                         where lc.removed_at is null and ((lc.kind = 'phone' and length(v_phone) >= 11 and lc.value = v_phone)
                                                          or (lc.kind = 'email' and v_email <> '' and lc.value = v_email))))), '[]')));
end $fn$;

/* GET /v1/b2c/leads/{id}/partner-history: what partners did with a lead the B2C CRM now holds (a partner-lost lead):
   each partner's activities and outcomes [{partner_name, kind, outcome, at, note?}], newest first, without the partner's
   counsellor names, and the partner's last raw status and sub-status. 404 for a lead the B2C CRM does not hold. */
create or replace function b2b.api_b2c_partner_history(p_key text, p_lead_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  v_last b2b.allocations;
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null or not coalesce(b2b.b2c_holds(l), false) then
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead held by the B2C CRM');
  end if;
  select * into v_last from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner' order by a.id desc limit 1;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'lead_id', l.id, 'contract_version', 4,
    'last_partner_status', coalesce(v_last.lost_detail ->> 'status', l.partner_stage_raw),
    'last_partner_sub_status', coalesce(v_last.lost_detail ->> 'sub_status', l.partner_sub_stage_raw),
    'history', coalesce((
      select jsonb_agg(h.item order by h.at desc, h.ord desc) from (
        select pa.occurred_at at, pa.id ord,
               jsonb_strip_nulls(jsonb_build_object('partner_name', coalesce(p.display_name, p.name), 'kind', pa.kind,
                                                    'outcome', pa.outcome, 'at', pa.occurred_at,
                                                    'note', left(nullif(trim(coalesce(pa.mapped ->> 'note', '')), ''), 1000))) item
          from b2b.partner_activities pa join b2b.partners p on p.id = pa.partner_id
         where pa.lead_id = l.id
        union all
        select coalesce(a.outcome_at, a.lost_at, a.updated_at), a.id,
               jsonb_strip_nulls(jsonb_build_object('partner_name', coalesce(p.display_name, p.name), 'kind', 'outcome',
                                                    'outcome', coalesce(a.outcome, a.status), 'at', coalesce(a.outcome_at, a.lost_at, a.updated_at),
                                                    'note', left(nullif(trim(coalesce(a.lost_detail ->> 'lost_reason', '')), ''), 300)))
          from b2b.allocations a join b2b.partners p on p.id = a.partner_id
         where a.lead_id = l.id and a.destination_type = 'partner' and (a.outcome is not null or a.status in ('duplicate', 'rejected', 'closed'))) h), '[]'::jsonb)));
end $fn$;

-- ---------- (6) GET /v1/b2c/schema, contract version 4 ----------
create or replace function b2b.api_b2c_schema(p_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'contract_version', 4,
    'scope', cfg ->> 'scope', 'enabled', coalesce((cfg ->> 'enabled')::boolean, true),
    'delivery', 'realtime', 'interval_minutes', b2b.sync_minutes(),
    -- Addendum 4 §2: B2C -> B2B every 15 minutes through the batch (at most one update per lead per batch), these at once
    'batch', jsonb_build_object('every_minutes', 15, 'max_items', 200, 'max_bytes', 1048576, 'min_calls_per_minute', 20,
                                'item_fields', jsonb_build_array('op', 'lead_id', 'request_id', 'occurred_at', 'if_version', 'actor', 'set'),
                                'immediate', jsonb_build_array('b2ccrm.consent_request_sent', 'b2ccrm.partner_consent', 'b2ccrm.opted_out',
                                                               'b2ccrm.erasure_requested', 'POST /v1/leads/{id}/route-to-partners', 'POST /v1/leads')),
    'groups', (select jsonb_agg(distinct f ->> 'group') from jsonb_array_elements(b2b.b2c_fields()) f),
    -- Addendum 4 §5.3: the registered consent wording, so the B2C CRM sends only an exact sentence
    'consent_texts', coalesce((select jsonb_agg(jsonb_build_object('text_version', t.version, 'text', t.body, 'channel', t.channel, 'purposes', to_jsonb(t.purposes),
                                                                   'covers_admission_partners', t.covers_admission_partners,
                                                                   'lawyer_approved', t.lawyer_approved_at is not null) order by t.version)
                                 from b2b.consent_texts t where t.active), '[]'::jsonb),
    'contact_labels', jsonb_build_array('alternate', 'parent', 'office', 'whatsapp_only'),
    'fields', (select jsonb_agg(jsonb_build_object('field', f ->> 'field', 'group', f ->> 'group', 'kind', f ->> 'kind', 'max', f -> 'max',
                                                   'writable', f ->> 'write' = 'b2c' and (cfg -> 'writable') ? (f ->> 'field')))
                 from jsonb_array_elements(b2b.b2c_fields()) f)
              || jsonb_build_array(jsonb_build_object('field', 'other_courses', 'group', 'interest', 'kind', 'list', 'max', 9::int, 'writable', true)),
    'stages', (select jsonb_agg(jsonb_build_object('key', e ->> 'key', 'rank', e -> 'rank', 'group', e ->> 'group'))
                 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null),
    'activity_kinds', jsonb_build_array('call', 'whatsapp', 'sms', 'email', 'meeting', 'note'),
    'reasons', jsonb_build_object(
      'sales', jsonb_build_array('b2c_created', 'import_choice', 'rule', 'manual', 'manual_route_failed', 'no_partner_offers_programme', 'no_capacity',
                                 'partners_unreachable', 'partner_attempts_exhausted', 'duplicate_cascade', 'no_partner_consent', 'partner_barred', 'b2c_held'),
      'nurture', jsonb_build_array('not_qualified', 'consent_no_answer', 'partner_lost'),
      'test', jsonb_build_array('test_handoff'),
      'retired', jsonb_build_array('paid_campaign')),
    'causes', jsonb_build_array('caps', 'paused', 'criteria', 'rule', 'duplicate_history', 'tried', 'duplicate_cascade', 'partner_attempts_exhausted',
                                'partners_unreachable', 'no_partner_offers_programme', 'no_capacity', 'no_partner_consent'),
    'handling', jsonb_build_object(
      'job', jsonb_build_array('sell', 'qualify', 'nurture'),
      'assignment', jsonb_build_array('round_robin_now', 'unassigned_until_interest', 'previous_counsellor', 'counsellor_choice', 'unassigned'),
      'first_contact_script', jsonb_build_array('neutral_adviser', 'standard')),
    'hold_kinds', jsonb_build_array('barred', 'qualification_nurture', 'selling'),
    'partner_bar_reasons', jsonb_build_array('duplicate', 'lost'),
    'consent_states', jsonb_build_array('given', 'refused', 'withdrawn', 'requested', 'queued', 'expired', 'stamp_uncovered', 'none'),
    'b2c_actions', jsonb_build_array('welcome_explore_programmes'),
    'events', jsonb_build_array('b2c.lead_upserted', 'b2c.lead_released', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                                'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_requalified', 'b2c.lead_reengaged',
                                'b2c.consent_requested', 'b2c.consent_closed', 'b2b.lead_routed_to_partner', 'ping'),
    'inbound', jsonb_build_array('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested',
                                 'b2ccrm.partner_consent', 'b2ccrm.consent_request_sent', 'b2ccrm.marketing_consent', 'b2ccrm.contact_added',
                                 'b2ccrm.lead_updated', 'b2ccrm.commission_booked'),
    'route_to_partners_error_codes', jsonb_build_array('partner_barred', 'no_consent', 'not_held', 'invalid')));
end $fn$;

revoke execute on function b2b.api_b2c_lead_lookup(text, text, text), b2b.api_b2c_partner_history(text, bigint), b2b.api_b2c_schema(text) from public;
grant execute on function b2b.api_b2c_lead_lookup(text, text, text), b2b.api_b2c_partner_history(text, bigint), b2b.api_b2c_schema(text) to anon, authenticated, service_role;
