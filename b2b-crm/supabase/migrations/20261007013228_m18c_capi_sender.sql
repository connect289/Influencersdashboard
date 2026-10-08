-- M18c: conversion feedback, part 3: sending (pg_net), reading the answers, retries, and the pg_cron tick.
--   Meta    POST graph.facebook.com/<version>/<dataset>/events, up to 100 events per call (Bearer: system-user token)
--   Google  POST googleads.googleapis.com/<version>/customers/<id>/conversionUploads:uploadClickConversions, up to 200
--           per call with partialFailure; the access token comes from the OAuth refresh token and is kept in Vault
-- Nothing goes out while a platform's live switch (capi_meta, capi_google) is off or its settings are incomplete: due
-- events wait as held and go once the platform is live (if still inside its window). Retries after 1, 5 and 30 minutes,
-- 2 and 6 hours; then dead with an alert. Events the platform refuses are rejected (not retried).

create or replace function b2b.capi_backoff(p_attempts int)
returns interval language sql immutable set search_path = '' as $fn$
  select case least(greatest(p_attempts, 1), 5) when 1 then interval '1 minute' when 2 then interval '5 minutes' when 3 then interval '30 minutes'
                                                when 4 then interval '2 hours' else interval '6 hours' end;
$fn$;

/* A failed attempt: retry later, or give up after 6 attempts. */
create or replace function b2b.capi_fail(p_ids bigint[], p_error text, p_response jsonb)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare n int;
begin
  update b2b.conversion_events
     set status = case when attempts >= 6 then 'dead' else 'failed' end, error = left(p_error, 500), response = p_response, request_id = null,
         next_attempt_at = case when attempts >= 6 then null else now() + b2b.capi_backoff(attempts) end
   where id = any (p_ids);
  select count(*) into n from b2b.conversion_events where id = any (p_ids) and status = 'dead';
  return n;
end $fn$;

/* Reads the answers to earlier calls. */
create or replace function b2b.capi_collect()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  h record;
  j jsonb;
  v_err text;
  v_dead int := 0;
  v_rejected int := 0;
  v_sent int := 0;
  v_auth text;
  t jsonb := (select value from b2b.capi_state where key = 'google_token');
  v_secret uuid;
  i int;
begin
  -- the Google access token
  if (t ->> 'request_id') is not null then
    select x.status_code, x.content, x.timed_out, x.error_msg into h from net._http_response x where x.id = (t ->> 'request_id')::bigint;
    if found then
      begin j := h.content::jsonb; exception when others then j := null; end;
      if h.status_code = 200 and j ->> 'access_token' is not null then
        v_secret := coalesce(nullif(t ->> 'secret_id', '')::uuid, (select vs.id from vault.secrets vs where vs.name = 'b2b_capi_google_access_token'));
        if v_secret is null then v_secret := vault.create_secret(j ->> 'access_token', 'b2b_capi_google_access_token', 'Google Ads access token (renewed hourly)');
        else perform vault.update_secret(v_secret, j ->> 'access_token'); end if;
        t := jsonb_build_object('secret_id', v_secret, 'expires_at', now() + make_interval(secs => coalesce((j ->> 'expires_in')::int, 3600) - 120));
      else
        v_auth := 'Google sign-in failed: ' || coalesce(j ->> 'error_description', j ->> 'error', h.error_msg, 'HTTP ' || h.status_code);
        t := (t - 'request_id') || jsonb_build_object('failed_at', now(), 'error', left(v_auth, 300));
      end if;
      update b2b.capi_state set value = t, updated_at = now() where key = 'google_token';
    elsif (t ->> 'requested_at')::timestamptz < now() - interval '10 minutes' then
      update b2b.capi_state set value = t - 'request_id', updated_at = now() where key = 'google_token';
    end if;
  end if;

  for r in select c.request_id, c.platform, array_agg(c.id order by c.id) ids, max(c.next_attempt_at) sent_at
             from b2b.conversion_events c where c.status = 'sending' and c.request_id is not null group by 1, 2 loop
    select x.status_code, x.content, x.timed_out, x.error_msg into h from net._http_response x where x.id = r.request_id;
    if not found then
      if r.sent_at < now() - interval '10 minutes' then v_dead := v_dead + b2b.capi_fail(r.ids, 'no answer from the platform', null); end if;
      continue;
    end if;
    begin j := h.content::jsonb; exception when others then j := jsonb_build_object('text', left(h.content, 500)); end;
    if h.status_code between 200 and 299 and r.platform = 'meta' then
      update b2b.conversion_events set status = 'sent', sent_at = now(), response = j, error = null, request_id = null where id = any (r.ids);
      v_sent := v_sent + cardinality(r.ids);
    elsif h.status_code between 200 and 299 then
      -- Google: results line up with the conversions sent (ordered by id); an empty result failed (partialFailureError says why)
      for i in 1 .. cardinality(r.ids) loop
        if coalesce(j -> 'results' -> (i - 1), '{}') = '{}' then
          update b2b.conversion_events set status = 'rejected', error = left(coalesce(j -> 'partialFailureError' ->> 'message', 'refused by Google'), 500),
                 response = j -> 'partialFailureError', request_id = null where id = r.ids[i];
          v_rejected := v_rejected + 1;
        else
          update b2b.conversion_events set status = 'sent', sent_at = now(), response = j -> 'results' -> (i - 1), error = null, request_id = null where id = r.ids[i];
          v_sent := v_sent + 1;
        end if;
      end loop;
    else
      v_err := coalesce(j -> 'error' ->> 'message', j ->> 'text', h.error_msg, case when h.timed_out then 'timed out' end, 'HTTP ' || h.status_code);
      if h.status_code in (401, 403) or (j -> 'error' ->> 'code') = '190' then
        v_auth := initcap(r.platform) || ' refused the credentials: ' || v_err;
        if r.platform = 'google' then update b2b.capi_state set value = value - 'expires_at', updated_at = now() where key = 'google_token'; end if;
        v_dead := v_dead + b2b.capi_fail(r.ids, v_err, j);
      elsif h.status_code = 400 and r.platform = 'meta' and cardinality(r.ids) > 1 then
        -- one bad event fails Meta's whole batch: send these one by one to find it
        update b2b.conversion_events set status = 'pending', reason = 'solo', request_id = null, next_attempt_at = now(), error = left(v_err, 500)
         where id = any (r.ids);
      elsif h.status_code between 400 and 499 and h.status_code <> 429 then
        update b2b.conversion_events set status = 'rejected', error = left(v_err, 500), response = j, request_id = null where id = any (r.ids);
        v_rejected := v_rejected + cardinality(r.ids);
      else
        v_dead := v_dead + b2b.capi_fail(r.ids, v_err, j);
      end if;
    end if;
  end loop;

  if v_dead + v_rejected > 0 then
    perform b2b.log_event('alert.capi_failed', null, null, null, jsonb_build_object('dead', v_dead, 'rejected', v_rejected));
  end if;
  if v_auth is not null then perform b2b.log_event('alert.capi_auth', null, null, null, jsonb_build_object('error', left(v_auth, 300))); end if;
  return jsonb_build_object('sent', v_sent, 'rejected', v_rejected, 'dead', v_dead);
end $fn$;

/* What stops a platform from sending, or an empty array. */
create or replace function b2b.capi_blockers(p_platform text)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with s as (select coalesce((select value from b2b.settings where key = 'capi'), '{}') -> p_platform v)
  select coalesce(jsonb_agg(x), '[]') from s, lateral (
    select 'switched off' x where not b2b.is_live('capi_' || p_platform)
    union all select 'no dataset ID' where p_platform = 'meta' and nullif(s.v ->> 'dataset_id', '') is null
    union all select 'no access token' where p_platform = 'meta' and b2b.capi_secret('meta.token_id') is null
    union all select 'no customer ID' where p_platform = 'google' and nullif(s.v ->> 'customer_id', '') is null
    union all select 'no developer token' where p_platform = 'google' and b2b.capi_secret('google.developer_token_id') is null
    union all select 'no OAuth client or refresh token' where p_platform = 'google'
                and (nullif(s.v ->> 'client_id', '') is null or b2b.capi_secret('google.client_secret_id') is null or b2b.capi_secret('google.refresh_token_id') is null)) y;
$fn$;

/* Sends due events. Holds them while a platform cannot send. */
create or replace function b2b.capi_send()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
  t jsonb;
  pf text;
  v_block jsonb;
  ids bigint[];
  v_body jsonb;
  v_net bigint;
  v_token text;
  n_sent int := 0;
  r record;
begin
  foreach pf in array array['meta', 'google'] loop
    -- too old for the platform
    update b2b.conversion_events set status = 'skipped', reason = 'older than the platform accepts', next_attempt_at = null
     where platform = pf and status in ('pending', 'failed', 'held')
       and occurred_at < now() - make_interval(days => coalesce((s -> pf ->> 'window_days')::int, case pf when 'meta' then 7 else 90 end));
    v_block := b2b.capi_blockers(pf);
    if jsonb_array_length(v_block) > 0 then
      update b2b.conversion_events set status = 'held', reason = v_block ->> 0
       where platform = pf and status in ('pending', 'failed') and coalesce(next_attempt_at, now()) <= now();
      continue;
    end if;
    update b2b.conversion_events set status = 'pending', reason = null, next_attempt_at = now() where platform = pf and status = 'held';

    if pf = 'meta' then
      -- singles first (a batch Meta refused), then batches of 100
      for r in select id, payload from b2b.conversion_events where platform = 'meta' and status in ('pending', 'failed') and reason = 'solo'
                  and coalesce(next_attempt_at, now()) <= now() order by id limit 20 for update skip locked loop
        v_net := net.http_post(
          url := 'https://graph.facebook.com/' || coalesce(s -> 'meta' ->> 'api_version', 'v21.0') || '/' || (s -> 'meta' ->> 'dataset_id') || '/events',
          body := jsonb_strip_nulls(jsonb_build_object('data', jsonb_build_array(r.payload), 'test_event_code', nullif(s -> 'meta' ->> 'test_event_code', ''))),
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || b2b.capi_secret('meta.token_id')),
          timeout_milliseconds := 15000);
        update b2b.conversion_events set status = 'sending', reason = null, request_id = v_net, attempts = attempts + 1, next_attempt_at = now() where id = r.id;
        n_sent := n_sent + 1;
      end loop;
      select array_agg(id order by id), jsonb_agg(payload order by id) into ids, v_body from (
        select id, payload from b2b.conversion_events where platform = 'meta' and status in ('pending', 'failed') and reason is distinct from 'solo'
           and coalesce(next_attempt_at, now()) <= now() order by id limit 100 for update skip locked) x;
      if ids is not null then
        v_net := net.http_post(
          url := 'https://graph.facebook.com/' || coalesce(s -> 'meta' ->> 'api_version', 'v21.0') || '/' || (s -> 'meta' ->> 'dataset_id') || '/events',
          body := jsonb_strip_nulls(jsonb_build_object('data', v_body, 'test_event_code', nullif(s -> 'meta' ->> 'test_event_code', ''))),
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || b2b.capi_secret('meta.token_id')),
          timeout_milliseconds := 15000);
        update b2b.conversion_events set status = 'sending', request_id = v_net, attempts = attempts + 1, next_attempt_at = now() where id = any (ids);
        n_sent := n_sent + cardinality(ids);
      end if;
      continue;
    end if;

    -- google: events whose stage has no conversion action wait
    update b2b.conversion_events c set status = 'held', reason = 'no conversion action for this stage'
     where c.platform = 'google' and c.status in ('pending', 'failed') and nullif(s -> 'google' -> 'map' -> c.stage ->> 'action', '') is null;
    if not exists (select 1 from b2b.conversion_events where platform = 'google' and status in ('pending', 'failed') and coalesce(next_attempt_at, now()) <= now()) then
      continue;
    end if;
    t := (select value from b2b.capi_state where key = 'google_token');
    v_token := case when (t ->> 'expires_at')::timestamptz > now() then (select ds.decrypted_secret from vault.decrypted_secrets ds where ds.id = nullif(t ->> 'secret_id', '')::uuid) end;
    if v_token is null then
      if (t ->> 'request_id') is null and coalesce((t ->> 'failed_at')::timestamptz, '-infinity') < now() - interval '15 minutes' then
        v_net := net.http_post(url := 'https://oauth2.googleapis.com/token',
          body := jsonb_build_object('client_id', s -> 'google' ->> 'client_id', 'client_secret', b2b.capi_secret('google.client_secret_id'),
                                     'refresh_token', b2b.capi_secret('google.refresh_token_id'), 'grant_type', 'refresh_token'),
          headers := jsonb_build_object('Content-Type', 'application/json'), timeout_milliseconds := 10000);
        update b2b.capi_state set value = coalesce(t, '{}') - 'failed_at' || jsonb_build_object('request_id', v_net, 'requested_at', now()), updated_at = now()
         where key = 'google_token';
      end if;
      continue;
    end if;
    select array_agg(id order by id), jsonb_agg(payload || jsonb_build_object('conversionAction', s -> 'google' -> 'map' -> stage ->> 'action') order by id)
      into ids, v_body from (
      select id, stage, payload from b2b.conversion_events where platform = 'google' and status in ('pending', 'failed')
         and coalesce(next_attempt_at, now()) <= now() order by id limit 200 for update skip locked) x;
    if ids is not null then
      v_net := net.http_post(
        url := 'https://googleads.googleapis.com/' || coalesce(s -> 'google' ->> 'api_version', 'v21') || '/customers/'
               || regexp_replace(s -> 'google' ->> 'customer_id', '\D', '', 'g') || '/conversionUploads:uploadClickConversions',
        body := jsonb_build_object('conversions', v_body, 'partialFailure', true),
        headers := jsonb_strip_nulls(jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token,
                     'developer-token', b2b.capi_secret('google.developer_token_id'),
                     'login-customer-id', nullif(regexp_replace(coalesce(s -> 'google' ->> 'login_customer_id', ''), '\D', '', 'g'), ''))),
        timeout_milliseconds := 20000);
      update b2b.conversion_events set status = 'sending', request_id = v_net, attempts = attempts + 1, next_attempt_at = now() where id = any (ids);
      n_sent := n_sent + cardinality(ids);
    end if;
  end loop;
  return jsonb_build_object('sending', n_sent);
end $fn$;

/* pg_cron, every minute. */
create or replace function b2b.capi_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare a jsonb; b jsonb; c jsonb;
begin
  perform set_config('b2b.actor', 'system', true);
  a := b2b.capi_collect();
  b := b2b.capi_scan(2000);
  c := b2b.capi_send();
  return a || b || c;
end $fn$;

revoke execute on function b2b.capi_backoff(int), b2b.capi_fail(bigint[], text, jsonb), b2b.capi_collect(), b2b.capi_blockers(text), b2b.capi_send(), b2b.capi_tick()
  from public, anon, authenticated;
grant execute on function b2b.capi_backoff(int), b2b.capi_fail(bigint[], text, jsonb), b2b.capi_collect(), b2b.capi_blockers(text), b2b.capi_send(), b2b.capi_tick()
  to service_role;

select cron.schedule('b2b-capi-tick', '* * * * *', 'select b2b.capi_tick()');
