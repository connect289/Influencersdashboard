-- M18b: conversion feedback, part 2: building events and finding new milestones.
--   capi_state        small key/value state for the sender (scan watermark, Google access token id and expiry)
--   capi_build        one milestone as a Meta Conversions API event or a Google Ads click conversion (hashed data only)
--   capi_lead_sync    writes the events a lead's milestones call for (idempotent: event_id = <lead id>:<stage>:<cycle>)
--   capi_scan         finds leads whose milestones may have changed since the last scan (leads, allocations, enrollments, not-passed)
-- Test leads are logged as dry runs and never sent. Without the consent the settings ask for, events are logged as skipped
-- and are written again as pending if the consent arrives later.

create table if not exists b2b.capi_state (
  key        text primary key,
  value      jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table b2b.capi_state enable row level security;
revoke all on b2b.capi_state from public, anon, authenticated;
grant all on b2b.capi_state to service_role;
insert into b2b.capi_state (key) values ('scan'), ('google_token') on conflict (key) do nothing;

/* One event for one platform, or null when the platform has nothing to match it with or the stage is switched off.
   Returns {name, payload, match_keys}. Google's conversion action is added when it is sent, so events logged before
   the action was configured can still go. */
create or replace function b2b.capi_build(l public.student_leads, p_ids jsonb, p_platform text, p_stage text, p_at timestamptz,
                                          p_value numeric, p_event_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  m jsonb := s -> p_platform -> 'map' -> p_stage;
  v_em text := b2b.capi_hash_email(l.email_id, p_platform);
  v_ph text := b2b.capi_hash_phone(l.whatsapp_number, p_platform);
  v_fbc text;
  v_keys text[] := '{}';
  v_user jsonb;
  v_lead_id bigint;
  g jsonb;
begin
  if m is null or not coalesce((m ->> 'enabled')::boolean, false) then return null; end if;
  if p_platform = 'meta' then
    if not (p_ids ?| array['leadgen_id', 'fbclid', 'fbc', 'fbp']) then return null; end if;
    v_fbc := coalesce(p_ids ->> 'fbc', case when p_ids ? 'fbclid' then 'fb.1.' || (extract(epoch from l.created_at) * 1000)::bigint || '.' || (p_ids ->> 'fbclid') end);
    if p_ids ->> 'leadgen_id' ~ '^\d{1,19}$' then v_lead_id := (p_ids ->> 'leadgen_id')::bigint; end if;
    v_user := jsonb_strip_nulls(jsonb_build_object(
      'lead_id', v_lead_id, 'em', case when v_em is not null then jsonb_build_array(v_em) end, 'ph', case when v_ph is not null then jsonb_build_array(v_ph) end,
      'fbc', v_fbc, 'fbp', p_ids ->> 'fbp', 'external_id', jsonb_build_array(encode(extensions.digest('eduwit:' || l.id, 'sha256'), 'hex'))));
    v_keys := array_remove(array[case when v_lead_id is not null then 'lead_id' end, case when v_em is not null then 'email' end,
                                 case when v_ph is not null then 'phone' end, case when v_fbc is not null then 'fbc' end,
                                 case when p_ids ? 'fbp' then 'fbp' end], null);
    return jsonb_build_object('name', m ->> 'event', 'match_keys', to_jsonb(v_keys), 'payload', jsonb_strip_nulls(jsonb_build_object(
      'event_name', m ->> 'event', 'event_time', floor(extract(epoch from p_at))::bigint, 'event_id', p_event_id,
      'action_source', case when v_lead_id is not null then 'system_generated' else 'website' end,
      'event_source_url', case when v_lead_id is null then l.landing_url end,
      'user_data', v_user,
      'custom_data', jsonb_strip_nulls(jsonb_build_object('event_source', 'crm', 'lead_event_source', 'Eduwit CRM',
                                                          'value', p_value, 'currency', case when p_value is not null then 'INR' end)))));
  end if;

  -- google: a click ID, or (enhanced conversions for leads) a Google lead with a hashed email or phone
  if not (p_ids ?| array['gclid', 'gbraid', 'wbraid']) and not (p_ids ? 'google_lead_id' and coalesce(v_em, v_ph) is not null) then return null; end if;
  g := jsonb_strip_nulls(jsonb_build_object(
    'conversionDateTime', to_char(p_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD HH24:MI:SS') || '+05:30',
    'conversionValue', p_value, 'currencyCode', case when p_value is not null then 'INR' end, 'orderId', p_event_id,
    'gclid', p_ids ->> 'gclid',
    'gbraid', case when not p_ids ? 'gclid' then p_ids ->> 'gbraid' end,
    'wbraid', case when not (p_ids ?| array['gclid', 'gbraid']) then p_ids ->> 'wbraid' end,
    'consent', jsonb_build_object('adUserData', 'GRANTED')));
  if coalesce(v_em, v_ph) is not null then
    g := g || jsonb_build_object('userIdentifiers', (select jsonb_agg(x) from (
           select jsonb_build_object('hashedEmail', v_em) x where v_em is not null
           union all select jsonb_build_object('hashedPhoneNumber', v_ph) where v_ph is not null) y));
  end if;
  v_keys := array_remove(array[case when p_ids ? 'gclid' then 'gclid' when p_ids ? 'gbraid' then 'gbraid' when p_ids ? 'wbraid' then 'wbraid' end,
                               case when v_em is not null then 'email' end, case when v_ph is not null then 'phone' end], null);
  return jsonb_build_object('name', coalesce(m ->> 'label', p_stage), 'match_keys', to_jsonb(v_keys), 'payload', g);
end $fn$;

/* Writes the events a lead's milestones call for. Returns the number of rows written or revived. */
create or replace function b2b.capi_lead_sync(p_lead_id bigint)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  v_junk boolean := coalesce((select (value ->> 'junk_capi_signal')::boolean from b2b.settings where key = 'engine'), false);
  l public.student_leads;
  v_ids jsonb;
  v_test boolean;
  v_consent boolean;
  ms record;
  pf text;
  ev jsonb;
  v_status text;
  v_reason text;
  v_event_id text;
  n int := 0;
  k int;
begin
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null or l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null then return 0; end if;
  v_ids := b2b.capi_ids(l);
  if v_ids = '{}' then return 0; end if;
  v_test := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_consent := not coalesce(l.is_opted_out, false)
               and case coalesce(s ->> 'consent', 'marketing') when 'sales' then l.consent_sales_at is not null else l.consent_marketing_at is not null end;
  for ms in select * from b2b.capi_milestones(l) loop
    continue when ms.stage = 'disqualified' and not v_junk;
    foreach pf in array array['meta', 'google'] loop
      v_event_id := l.id || ':' || ms.stage || ':' || coalesce(l.cycle_no, 1);
      ev := b2b.capi_build(l, v_ids, pf, ms.stage, ms.at, ms.value_inr, v_event_id);
      continue when ev is null;
      v_status := case when v_test then 'dry_run'
                       when not v_consent then 'skipped'
                       when ms.at < now() - make_interval(days => coalesce((s -> pf ->> 'window_days')::int, case pf when 'meta' then 7 else 90 end)) then 'skipped'
                       else 'pending' end;
      v_reason := case when v_test then 'test lead: never sent'
                       when not v_consent then 'no consent'
                       when v_status = 'skipped' then 'older than the platform accepts' end;
      insert into b2b.conversion_events (lead_id, platform, stage, event_name, event_id, cycle_no, occurred_at, value_inr, is_test, status, reason,
                                         match_keys, payload, next_attempt_at)
      values (l.id, pf, ms.stage, ev ->> 'name', v_event_id, coalesce(l.cycle_no, 1), ms.at, ms.value_inr, v_test, v_status, v_reason,
              array(select jsonb_array_elements_text(ev -> 'match_keys')), ev -> 'payload', case when v_status = 'pending' then now() end)
      on conflict (platform, event_id) do update
        set status = excluded.status, reason = excluded.reason, payload = excluded.payload, match_keys = excluded.match_keys,
            value_inr = excluded.value_inr, occurred_at = excluded.occurred_at, next_attempt_at = excluded.next_attempt_at
        where b2b.conversion_events.status = 'skipped' and b2b.conversion_events.reason = 'no consent' and excluded.status <> 'skipped';
      get diagnostics k = row_count;
      n := n + k;
    end loop;
  end loop;
  return n;
end $fn$;

/* Leads whose milestones may have changed since the last scan, oldest change first, at most p_limit per run. The
   first run looks back 30 days. */
create or replace function b2b.capi_scan(p_limit int default 2000)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_start timestamptz := now();
  v_since timestamptz := coalesce((select (value ->> 'at')::timestamptz from b2b.capi_state where key = 'scan'), now() - interval '30 days');
  v_last timestamptz;
  v_leads int := 0;
  v_rows int := 0;
  r record;
begin
  for r in
    select lead_id, max(changed) changed from (
      select l.id lead_id, l.updated_at changed from public.student_leads l where l.updated_at > v_since - interval '5 minutes'
      union all select a.lead_id, greatest(a.created_at, a.updated_at, a.accepted_at) from b2b.allocations a
                 where greatest(a.created_at, a.updated_at, a.accepted_at) > v_since - interval '5 minutes'
      union all select e.lead_id, greatest(e.created_at, e.updated_at, e.verified_at) from public.enrollments e
                 where greatest(e.created_at, e.updated_at, e.verified_at) > v_since - interval '5 minutes' and e.lead_id is not null
      union all select n.lead_id, n.decided_at from b2b.not_passed n where n.decided_at > v_since - interval '5 minutes') x
     group by lead_id order by 2 limit greatest(p_limit, 1)
  loop
    begin
      v_rows := v_rows + b2b.capi_lead_sync(r.lead_id);
    exception when others then
      raise warning 'capi_lead_sync(%) failed: %', r.lead_id, sqlerrm;
    end;
    v_leads := v_leads + 1;
    v_last := r.changed;
  end loop;
  update b2b.capi_state set value = jsonb_build_object('at', case when v_leads >= greatest(p_limit, 1) then v_last else v_start end), updated_at = now()
   where key = 'scan';
  return jsonb_build_object('leads', v_leads, 'events', v_rows);
end $fn$;

revoke execute on function b2b.capi_build(public.student_leads, jsonb, text, text, timestamptz, numeric, text), b2b.capi_lead_sync(bigint), b2b.capi_scan(int)
  from public, anon, authenticated;
grant execute on function b2b.capi_build(public.student_leads, jsonb, text, text, timestamptz, numeric, text), b2b.capi_lead_sync(bigint), b2b.capi_scan(int)
  to service_role;
