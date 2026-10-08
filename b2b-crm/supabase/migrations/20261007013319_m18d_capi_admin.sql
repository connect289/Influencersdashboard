-- M18d: conversion feedback, part 4: the Admin's CAPI screen.
--   capi_overview        switches and blockers, settings (secrets as set / not set), maps, volumes, match quality, log
--   capi_settings_save   settings and maps; secrets go to Vault and are never read back
--   capi_retry           sends a failed, dead, rejected or held event again
--   capi_lead_check      one lead: its identifiers, consent, milestones and the events they make (writes them if asked)

create or replace function b2b.capi_overview(p_status text default null, p_platform text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', jsonb_build_object(
      'consent', coalesce(s ->> 'consent', 'marketing'),
      'junk_signal', coalesce((select (value ->> 'junk_capi_signal')::boolean from b2b.settings where key = 'engine'), false),
      'meta', jsonb_build_object('dataset_id', s -> 'meta' ->> 'dataset_id', 'api_version', s -> 'meta' ->> 'api_version',
                                 'test_event_code', s -> 'meta' ->> 'test_event_code', 'window_days', s -> 'meta' -> 'window_days',
                                 'token', b2b.capi_secret('meta.token_id') is not null, 'map', s -> 'meta' -> 'map'),
      'google', jsonb_build_object('customer_id', s -> 'google' ->> 'customer_id', 'login_customer_id', s -> 'google' ->> 'login_customer_id',
                                   'api_version', s -> 'google' ->> 'api_version', 'client_id', s -> 'google' ->> 'client_id', 'window_days', s -> 'google' -> 'window_days',
                                   'developer_token', b2b.capi_secret('google.developer_token_id') is not null,
                                   'client_secret', b2b.capi_secret('google.client_secret_id') is not null,
                                   'refresh_token', b2b.capi_secret('google.refresh_token_id') is not null,
                                   'token_error', (select value ->> 'error' from b2b.capi_state where key = 'google_token'),
                                   'map', s -> 'google' -> 'map')),
    'switches', jsonb_build_object(
      'meta', jsonb_build_object('live', b2b.is_live('capi_meta'), 'blockers', b2b.capi_blockers('meta') - 'switched off',
                                 'switched_at', (select switched_at from b2b.live_switches where scope = 'capi_meta')),
      'google', jsonb_build_object('live', b2b.is_live('capi_google'), 'blockers', b2b.capi_blockers('google') - 'switched off',
                                   'switched_at', (select switched_at from b2b.live_switches where scope = 'capi_google'))),
    'status', coalesce((select jsonb_object_agg(platform || '.' || status, n) from (
                          select platform, status, count(*) n from b2b.conversion_events where created_at > now() - interval '30 days' group by 1, 2) x), '{}'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('platform', platform, 'stage', stage, 'event_name', event_name, 'sent', sent, 'sent_7d', sent_7d,
                                                            'waiting', waiting, 'failed', failed, 'value_inr', value_inr) order by platform, ord)
                          from (select platform, stage, max(event_name) event_name,
                                       count(*) filter (where status = 'sent') sent,
                                       count(*) filter (where status = 'sent' and sent_at > now() - interval '7 days') sent_7d,
                                       count(*) filter (where status in ('pending', 'sending', 'held')) waiting,
                                       count(*) filter (where status in ('failed', 'dead', 'rejected')) failed,
                                       sum(value_inr) filter (where status = 'sent') value_inr,
                                       array_position(array['lead', 'ready_to_route', 'partner_accepted', 'contacted', 'applied', 'enrolled', 'verified', 'disqualified'], stage) ord
                                  from b2b.conversion_events where created_at > now() - interval '30 days' group by platform, stage) x), '[]'),
    'match', coalesce((select jsonb_object_agg(platform, keys) from (
                         select platform, jsonb_build_object('events', count(*),
                                  'keys', (select coalesce(jsonb_object_agg(k, n), '{}') from (
                                             select k, count(*) n from b2b.conversion_events c2, unnest(c2.match_keys) k
                                              where c2.platform = c.platform and c2.created_at > now() - interval '30 days' and c2.status in ('sent', 'dry_run', 'pending', 'held')
                                              group by k) y)) keys
                           from b2b.conversion_events c where created_at > now() - interval '30 days' and status in ('sent', 'dry_run', 'pending', 'held')
                          group by platform) x), '{}'),
    'log', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'lead_id', c.lead_id, 'name', l.student_name, 'platform', c.platform, 'stage', c.stage,
                                                         'event_name', c.event_name, 'event_id', c.event_id, 'occurred_at', c.occurred_at, 'value_inr', c.value_inr,
                                                         'is_test', c.is_test, 'status', c.status, 'reason', c.reason, 'error', c.error, 'attempts', c.attempts,
                                                         'match_keys', c.match_keys, 'created_at', c.created_at, 'sent_at', c.sent_at) order by c.id desc)
                       from (select * from b2b.conversion_events
                              where (p_status is null or status = p_status or (p_status = 'problems' and status in ('failed', 'dead', 'rejected')))
                                and (p_platform is null or platform = p_platform)
                              order by id desc limit 150) c left join public.student_leads l on l.id = c.lead_id), '[]'));
end $fn$;

/* p: {consent, meta: {dataset_id, api_version, test_event_code, token, map}, google: {customer_id, login_customer_id,
   api_version, client_id, client_secret, refresh_token, developer_token, map}}. Empty secrets leave a secret unchanged. */
create or replace function b2b.capi_settings_save(p jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  m jsonb := coalesce(s -> 'meta', '{}');
  g jsonb := coalesce(s -> 'google', '{}');
  v_stages text[] := array['lead', 'ready_to_route', 'partner_accepted', 'contacted', 'applied', 'enrolled', 'verified', 'disqualified'];
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
  perform b2b.set_setting('capi', s || jsonb_build_object('consent', coalesce(nullif(p ->> 'consent', ''), s ->> 'consent', 'marketing'), 'meta', m, 'google', g),
                          'conversions (CAPI) settings saved');
end $fn$;

create or replace function b2b.capi_retry(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.conversion_events set status = 'pending', reason = null, error = null, attempts = 0, next_attempt_at = now()
   where id = p_id and status in ('failed', 'dead', 'rejected', 'held') and not is_test;
  if not found then raise exception 'only a failed, rejected or held event can be sent again' using errcode = '22023'; end if;
  perform b2b.log_event('capi.retried', (select lead_id from b2b.conversion_events where id = p_id), null, null, jsonb_build_object('event', p_id));
end $fn$;

/* One lead, for checking a setup with a test lead: what Eduwit knows and what it would send. p_write also logs the
   events (test leads as dry runs). */
create or replace function b2b.capi_lead_check(p_lead_id bigint, p_write boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  l public.student_leads;
  v_ids jsonb;
  v_written int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  v_ids := b2b.capi_ids(l);
  if p_write then v_written := b2b.capi_lead_sync(l.id); end if;
  return jsonb_build_object(
    'lead', jsonb_build_object('id', l.id, 'name', l.student_name, 'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
                               'cycle_no', coalesce(l.cycle_no, 1), 'has_email', l.email_id is not null, 'deleted', l.deleted_at is not null),
    'ids', v_ids,
    'consent', jsonb_build_object('rule', coalesce(s ->> 'consent', 'marketing'), 'sales_at', l.consent_sales_at, 'marketing_at', l.consent_marketing_at,
                                  'opted_out', coalesce(l.is_opted_out, false)),
    'milestones', coalesce((select jsonb_agg(jsonb_build_object('stage', m.stage, 'at', m.at, 'value_inr', m.value_inr,
                              'meta', b2b.capi_build(l, v_ids, 'meta', m.stage, m.at, m.value_inr, l.id || ':' || m.stage || ':' || coalesce(l.cycle_no, 1)),
                              'google', b2b.capi_build(l, v_ids, 'google', m.stage, m.at, m.value_inr, l.id || ':' || m.stage || ':' || coalesce(l.cycle_no, 1))))
                            from b2b.capi_milestones(l) m), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'platform', platform, 'stage', stage, 'status', status, 'reason', reason, 'error', error,
                                                            'sent_at', sent_at) order by id) from b2b.conversion_events where lead_id = l.id), '[]'),
    'written', v_written);
end $fn$;

revoke execute on function b2b.capi_overview(text, text), b2b.capi_settings_save(jsonb), b2b.capi_retry(bigint), b2b.capi_lead_check(bigint, boolean)
  from public, anon, authenticated;
grant execute on function b2b.capi_overview(text, text), b2b.capi_settings_save(jsonb), b2b.capi_retry(bigint), b2b.capi_lead_check(bigint, boolean)
  to authenticated, service_role;
