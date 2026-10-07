-- M21b: CAPI for paid leads only, campaign by campaign (follows m21a).
--   capi_lead_sync     records the lead's campaign; events only for the platform whose paid ad brought the lead, tagged with the campaign
--   capi_lead_check    shows the campaign and only the events that would go
--   capi_settings_save accepts the new signals and their values
--   capi_campaigns     lead quality per paid campaign: qualified, interested, applied, enrolled, verified, commission

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
  v_camp jsonb;
  v_status text;
  v_reason text;
  v_event_id text;
  n int := 0;
  k int;
begin
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null or l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null then return 0; end if;
  -- the campaign is recorded for every lead; conversions go only to the platform whose paid ad brought the lead
  v_camp := b2b.lead_campaign_sync(l);
  if not coalesce((v_camp ->> 'paid')::boolean, false) or not coalesce((v_camp ->> 'matchable')::boolean, false) then return 0; end if;
  v_ids := b2b.capi_ids(l);
  if v_ids = '{}' then return 0; end if;
  v_test := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_consent := not coalesce(l.is_opted_out, false)
               and case coalesce(s ->> 'consent', 'marketing') when 'sales' then l.consent_sales_at is not null else l.consent_marketing_at is not null end;
  for ms in select * from b2b.capi_milestones(l) loop
    continue when ms.stage = 'disqualified' and not v_junk;
    foreach pf in array array['meta', 'google'] loop
      continue when pf <> v_camp ->> 'platform';
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
                                         match_keys, payload, next_attempt_at, campaign_id, campaign_name)
      values (l.id, pf, ms.stage, ev ->> 'name', v_event_id, coalesce(l.cycle_no, 1), ms.at, ms.value_inr, v_test, v_status, v_reason,
              array(select jsonb_array_elements_text(ev -> 'match_keys')), ev -> 'payload', case when v_status = 'pending' then now() end,
              left(v_camp ->> 'campaign_id', 60), left(coalesce(v_camp ->> 'campaign_name', v_camp -> 'utm' ->> 'campaign'), 200))
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

create or replace function b2b.capi_lead_check(p_lead_id bigint, p_write boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  l public.student_leads;
  v_ids jsonb;
  v_written int;
  v_camp jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  v_ids := b2b.capi_ids(l);
  v_camp := b2b.lead_campaign_detect(l);
  if p_write then v_written := b2b.capi_lead_sync(l.id); end if;
  return jsonb_build_object(
    'lead', jsonb_build_object('id', l.id, 'name', l.student_name, 'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
                               'cycle_no', coalesce(l.cycle_no, 1), 'has_email', l.email_id is not null, 'deleted', l.deleted_at is not null),
    'ids', v_ids,
    'campaign', v_camp - 'ck',
    'consent', jsonb_build_object('rule', coalesce(s ->> 'consent', 'marketing'), 'sales_at', l.consent_sales_at, 'marketing_at', l.consent_marketing_at,
                                  'opted_out', coalesce(l.is_opted_out, false)),
    'milestones', coalesce((select jsonb_agg(jsonb_build_object('stage', m.stage, 'at', m.at, 'value_inr', m.value_inr,
                              'meta', case when v_camp ->> 'platform' = 'meta' and (v_camp ->> 'matchable')::boolean
                                           then b2b.capi_build(l, v_ids, 'meta', m.stage, m.at, m.value_inr, l.id || ':' || m.stage || ':' || coalesce(l.cycle_no, 1)) end,
                              'google', case when v_camp ->> 'platform' = 'google' and (v_camp ->> 'matchable')::boolean
                                             then b2b.capi_build(l, v_ids, 'google', m.stage, m.at, m.value_inr, l.id || ':' || m.stage || ':' || coalesce(l.cycle_no, 1)) end))
                            from b2b.capi_milestones(l) m), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'platform', platform, 'stage', stage, 'status', status, 'reason', reason, 'error', error,
                                                            'sent_at', sent_at) order by id) from b2b.conversion_events where lead_id = l.id), '[]'),
    'written', v_written);
end $fn$;

create or replace function b2b.capi_settings_save(p jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  m jsonb := coalesce(s -> 'meta', '{}');
  g jsonb := coalesce(s -> 'google', '{}');
  v_stages text[] := array['lead', 'ready_to_route', 'qualified', 'partner_accepted', 'contacted', 'interested', 'applied', 'enrolled', 'verified', 'disqualified'];
  v_values jsonb := coalesce(s -> 'values', '{}');
  v_id uuid;
  r record;
  k text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'consent', s ->> 'consent', 'marketing') not in ('marketing', 'sales') then raise exception 'consent must be marketing or sales' using errcode = '22023'; end if;
  if nullif(p -> 'meta' ->> 'dataset_id', '') is not null and p -> 'meta' ->> 'dataset_id' !~ '^\d{5,25}$' then
    raise exception 'the Meta dataset (pixel) ID is a number' using errcode = '22023';
  end if;
  if nullif(p -> 'meta' ->> 'api_version', '') is not null and p -> 'meta' ->> 'api_version' !~ '^v\d{1,2}\.\d$' then
    raise exception 'the Graph API version looks like v21.0' using errcode = '22023';
  end if;
  if nullif(p -> 'google' ->> 'api_version', '') is not null and p -> 'google' ->> 'api_version' !~ '^v\d{1,3}$' then
    raise exception 'the Google Ads API version looks like v21' using errcode = '22023';
  end if;
  foreach k in array array['customer_id', 'login_customer_id'] loop
    if nullif(p -> 'google' ->> k, '') is not null and regexp_replace(p -> 'google' ->> k, '\D', '', 'g') !~ '^\d{10}$' then
      raise exception 'a Google Ads customer ID has 10 digits (123-456-7890)' using errcode = '22023';
    end if;
  end loop;
  if p -> 'meta' -> 'map' is not null then
    for k in select jsonb_object_keys(p -> 'meta' -> 'map') loop
      if not k = any (v_stages) then raise exception 'unknown stage: %', k using errcode = '22023'; end if;
      if length(trim(coalesce(p -> 'meta' -> 'map' -> k ->> 'event', ''))) not between 1 and 50 then raise exception 'each Meta stage needs an event name (up to 50 characters)' using errcode = '22023'; end if;
    end loop;
    m := m || jsonb_build_object('map', (select jsonb_object_agg(key, jsonb_build_object('event', trim(value ->> 'event'), 'enabled', coalesce((value ->> 'enabled')::boolean, false)))
                                           from jsonb_each(p -> 'meta' -> 'map')));
  end if;
  if p -> 'google' -> 'map' is not null then
    for k in select jsonb_object_keys(p -> 'google' -> 'map') loop
      if not k = any (v_stages) then raise exception 'unknown stage: %', k using errcode = '22023'; end if;
      if nullif(p -> 'google' -> 'map' -> k ->> 'action', '') is not null and p -> 'google' -> 'map' -> k ->> 'action' !~ '^customers/\d{10}/conversionActions/\d{1,20}$' then
        raise exception 'a conversion action looks like customers/1234567890/conversionActions/987654321' using errcode = '22023';
      end if;
    end loop;
    g := g || jsonb_build_object('map', (select jsonb_object_agg(key, jsonb_build_object('action', nullif(trim(value ->> 'action'), ''), 'enabled', coalesce((value ->> 'enabled')::boolean, false)))
                                           from jsonb_each(p -> 'google' -> 'map')));
  end if;
  m := m || jsonb_strip_nulls(jsonb_build_object('dataset_id', nullif(trim(p -> 'meta' ->> 'dataset_id'), ''), 'api_version', nullif(p -> 'meta' ->> 'api_version', '')));
  if p -> 'meta' ? 'test_event_code' then m := m || jsonb_build_object('test_event_code', nullif(trim(p -> 'meta' ->> 'test_event_code'), '')); end if;
  g := g || jsonb_strip_nulls(jsonb_build_object('customer_id', nullif(regexp_replace(coalesce(p -> 'google' ->> 'customer_id', ''), '\D', '', 'g'), ''),
                                                 'api_version', nullif(p -> 'google' ->> 'api_version', ''), 'client_id', nullif(trim(p -> 'google' ->> 'client_id'), '')));
  if p -> 'google' ? 'login_customer_id' then
    g := g || jsonb_build_object('login_customer_id', nullif(regexp_replace(coalesce(p -> 'google' ->> 'login_customer_id', ''), '\D', '', 'g'), ''));
  end if;
  for r in select * from (values ('meta', 'token', 'token_id', 'Meta Conversions API access token'),
                                 ('google', 'developer_token', 'developer_token_id', 'Google Ads developer token'),
                                 ('google', 'client_secret', 'client_secret_id', 'Google OAuth client secret'),
                                 ('google', 'refresh_token', 'refresh_token_id', 'Google Ads OAuth refresh token')) x(grp, field, id_key, label) loop
    continue when coalesce(p -> r.grp ->> r.field, '') = '';
    if length(p -> r.grp ->> r.field) < 10 then raise exception '% is too short', r.label using errcode = '22023'; end if;
    v_id := (case r.grp when 'meta' then m else g end ->> r.id_key)::uuid;
    if v_id is null then v_id := vault.create_secret(p -> r.grp ->> r.field, 'b2b_capi_' || r.grp || '_' || r.field, r.label);
    else perform vault.update_secret(v_id, p -> r.grp ->> r.field); end if;
    if r.grp = 'meta' then m := m || jsonb_build_object(r.id_key, v_id); else g := g || jsonb_build_object(r.id_key, v_id); end if;
    if r.grp = 'google' then update b2b.capi_state set value = value - 'expires_at' - 'failed_at' - 'error', updated_at = now() where key = 'google_token'; end if;
  end loop;
  -- values of the earlier signals, as a share of the lead's expected commission (enrolled uses the commission itself)
  if p -> 'values' is not null then
    for k in select jsonb_object_keys(p -> 'values') loop
      if k not in ('qualified', 'interested', 'applied') then raise exception 'values are set for qualified, interested and applied' using errcode = '22023'; end if;
      if not coalesce((p -> 'values' ->> k)::numeric between 0 and 1, false) then raise exception 'a signal value is a share between 0 and 100%%' using errcode = '22023'; end if;
    end loop;
    v_values := v_values || (p -> 'values');
  end if;
  if nullif(p ->> 'base_value_inr', '') is not null and not ((p ->> 'base_value_inr')::numeric between 0 and 10000000) then
    raise exception 'the default commission is between 0 and 1,00,00,000' using errcode = '22023';
  end if;
  perform b2b.set_setting('capi', s || jsonb_build_object('consent', coalesce(nullif(p ->> 'consent', ''), s ->> 'consent', 'marketing'), 'meta', m, 'google', g,
                                                       'values', v_values, 'base_value_inr', coalesce(nullif(p ->> 'base_value_inr', '')::numeric, (s ->> 'base_value_inr')::numeric, 15000)),
                          'conversions (CAPI) settings saved');
end $fn$;

/* Lead quality per paid campaign: how far its leads got, strongest signal first. What the ad platforms are told, campaign
   by campaign. p_days: leads whose paid touch is in the last p_days days. Test, deleted and merged leads are left out. */
create or replace function b2b.capi_campaigns(p_days int default 90, p_platform text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with lc as (
      select c.*, l
        from b2b.lead_campaigns c join public.student_leads l on l.id = c.lead_id and coalesce(l.cycle_no, 1) = c.cycle_no
       where c.paid and c.touched_at >= now() - make_interval(days => least(greatest(coalesce(p_days, 90), 1), 730))
         and (p_platform is null or c.platform = p_platform)
         and l.deleted_at is null and l.merged_into_id is null and not coalesce(l.is_test, false) and not b2b.is_test_phone(l.whatsapp_number)),
    ms as (select lc.lead_id, ms.stage, ms.value_inr from lc, lateral b2b.capi_milestones(lc.l) ms),
    per as (
      select lc.platform, coalesce(lc.campaign_id, lc.utm_campaign, lc.campaign_name, '(no campaign)') campaign_key,
             max(lc.campaign_id) campaign_id, max(coalesce(lc.campaign_name, lc.utm_campaign)) campaign_name,
             count(*) leads, count(*) filter (where lc.matchable) matchable, max(lc.touched_at) last_lead_at,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'qualified')) qualified,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'interested')) interested,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'applied')) applied,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'enrolled')) enrolled,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'verified')) verified,
             count(*) filter (where exists (select 1 from ms where ms.lead_id = lc.lead_id and ms.stage = 'disqualified')) junk,
             coalesce(sum((select coalesce(max(ms.value_inr) filter (where ms.stage = 'verified'), max(ms.value_inr) filter (where ms.stage = 'enrolled'))
                             from ms where ms.lead_id = lc.lead_id)), 0) commission,
             (select count(*) from b2b.conversion_events ce where ce.platform = lc.platform and ce.status = 'sent'
                and ce.lead_id = any (array_agg(lc.lead_id))) events_sent
        from lc group by lc.platform, coalesce(lc.campaign_id, lc.utm_campaign, lc.campaign_name, '(no campaign)'))
    select jsonb_build_object(
      'days', p_days,
      'campaigns', coalesce((select jsonb_agg(to_jsonb(per) order by per.enrolled desc, per.applied desc, per.leads desc) from per), '[]'),
      'unpaid', (select count(*) from b2b.lead_campaigns c join public.student_leads l on l.id = c.lead_id
                  where not c.paid and c.touched_at >= now() - make_interval(days => least(greatest(coalesce(p_days, 90), 1), 730))
                    and l.deleted_at is null and not coalesce(l.is_test, false)))
  );
end $fn$;

revoke execute on function b2b.capi_lead_sync(bigint) from public, anon, authenticated;
grant execute on function b2b.capi_lead_sync(bigint) to service_role;
revoke execute on function b2b.capi_lead_check(bigint, boolean), b2b.capi_settings_save(jsonb), b2b.capi_campaigns(int, text) from public, anon;
grant execute on function b2b.capi_lead_check(bigint, boolean), b2b.capi_settings_save(jsonb), b2b.capi_campaigns(int, text) to authenticated, service_role;
