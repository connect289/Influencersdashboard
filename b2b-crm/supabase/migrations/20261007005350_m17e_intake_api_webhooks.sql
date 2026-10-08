-- M17e: the other intake sources (spec B4, B17) and the Intake screen's reads.
--   intake_lead              the one core every source below uses: standard field names → lead_intake(), the source's
--                            routing directive, and the routing outlook returned to the caller
--   api_intake_lead          POST /v1/leads (API key with scope intake + Idempotency-Key; a replay returns the stored answer)
--   meta_webhook_verify / meta_webhook_ingest   Meta Lead Ads: verify token, X-Hub-Signature-256 over the raw body
--   google_leadform_ingest   Google Ads lead forms: google_key in the body
--   (the Meta fetch loop, manual entry, form and settings saves and the overview are in m17f)
-- Meta and Google secrets live in Vault; settings key 'intake' holds only their ids.

alter table b2b.lead_forms add column if not exists consent_purposes text[] not null default '{sales}';

-- Google lead-form leads are a trusted source like Meta's (the platform verified the form submission)
update b2b.settings set value = jsonb_set(value, '{trusted_sources}', coalesce(value -> 'trusted_sources', '[]') || '["google_lead_form"]'::jsonb)
 where key = 'engine' and not coalesce(value -> 'trusted_sources', '[]') ? 'google_lead_form';

create or replace function b2b.intake_secret(p_name text)
returns text language sql stable security definer set search_path = '' as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
   where s.id = nullif((select value #>> string_to_array(p_name, '.') from b2b.settings where key = 'intake'), '')::uuid;
$fn$;

/* p_lead: standard intake field names (import_fields), plus phone. p_opts: source_system, lead_source, campaign,
   click_ids, utm, consent {sales_at, partner_share_at, marketing_at, text_version}, is_test, idempotency_key,
   occurred_at, directive {directive, b2c_lane, phone_trusted}, directive_source. */
create or replace function b2b.intake_lead(p_lead jsonb, p_opts jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_fields jsonb := b2b.import_fields();
  v_lead jsonb := '{}';
  c jsonb := coalesce(p_opts -> 'consent', '{}');
  d jsonb := p_opts -> 'directive';
  v_res jsonb;
  v_id bigint;
  l public.student_leads;
  r jsonb;
  k text;
  v text;
  v_phone text := public.crm_norm_phone(p_lead ->> 'phone');
begin
  if v_phone is null or length(v_phone) < 10 then raise exception 'phone is missing or too short' using errcode = '22023'; end if;
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
    'consent_marketing_at', b2b.try_timestamptz(c ->> 'marketing_at'), 'consent_text_version', c ->> 'text_version'));

  v_res := public.lead_intake(jsonb_strip_nulls(jsonb_build_object(
    'phone', v_phone, 'source_system', coalesce(p_opts ->> 'source_system', 'api'), 'event_type', coalesce(p_opts ->> 'event_type', 'lead.created'),
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

  r := b2b.lead_readiness(l);
  return jsonb_build_object('lead_id', v_id, 'action', v_res ->> 'action', 'is_test', (v_res ->> 'is_test')::boolean,
    'routing', jsonb_build_object(
      'status', case when l.destination_type is not null then 'already_routed'
                     when (r ->> 'ready')::boolean then 'queued' else 'waiting' end,
      'destination', l.destination_type,
      'outlook', (b2b.pool_lead(l, true) ->> 'outlook'),
      'waiting_for', r -> 'missing', 'missing', r -> 'not_qualified'));
end $fn$;

-- ---------- Intake API ----------
create or replace function b2b.api_intake_lead(p_key text, p_idempotency_key text, p_body jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb;
  v_req b2b.intake_requests;
  v_id bigint;
  v_res jsonb;
  v_lead jsonb;
  v_unknown text[];
  v_fields jsonb := b2b.import_fields();
  v_allowed text[] := array['lead', 'source', 'channel', 'campaign', 'utm', 'click_ids', 'landing_url', 'consent', 'phone_verified', 'occurred_at', 'route', 'b2c_lane'];
begin
  perform set_config('b2b.actor', 'api', true);
  k := b2b.api_key_check(p_key, 'intake');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid API key'); end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) not between 1 and 200 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'send an Idempotency-Key header (1 to 200 characters)');
  end if;
  if (select count(*) from b2b.intake_requests where api_key_id = (k ->> 'api_key_id')::bigint and received_at > now() - interval '1 minute') >= 600 then
    return jsonb_build_object('ok', false, 'status', 429, 'error', 'too many requests; at most 600 a minute per key');
  end if;

  select * into v_req from b2b.intake_requests where source = 'api' and idempotency_key = trim(p_idempotency_key);
  if v_req.id is not null then
    if v_req.raw is distinct from p_body then
      return jsonb_build_object('ok', false, 'status', 409, 'error', 'this Idempotency-Key was used with a different body');
    end if;
    if v_req.status = 'done' then return jsonb_build_object('ok', true, 'status', 200, 'replayed', true, 'result', v_req.result); end if;
    if v_req.status = 'error' then return jsonb_build_object('ok', false, 'status', 422, 'replayed', true, 'error', v_req.error); end if;
  end if;

  if jsonb_typeof(p_body) <> 'object' or jsonb_typeof(p_body -> 'lead') <> 'object' then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'the body must be an object with a "lead" object');
  end if;
  select array_agg(x) into v_unknown from jsonb_object_keys(p_body) x where not (x = any (v_allowed));
  if v_unknown is not null then return jsonb_build_object('ok', false, 'status', 400, 'error', 'unknown keys: ' || array_to_string(v_unknown, ', ')); end if;
  v_lead := p_body -> 'lead';
  select array_agg(x) into v_unknown from jsonb_object_keys(v_lead) x where not (v_fields ? x);
  if v_unknown is not null then return jsonb_build_object('ok', false, 'status', 400, 'error', 'unknown lead fields: ' || array_to_string(v_unknown, ', ')); end if;
  if coalesce(p_body ->> 'route', 'auto') not in ('auto', 'hold', 'b2c') then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'route must be auto, hold or b2c');
  end if;

  insert into b2b.intake_requests (source, idempotency_key, api_key_id, raw, status)
  values ('api', trim(p_idempotency_key), (k ->> 'api_key_id')::bigint, p_body, 'received')
  on conflict (source, idempotency_key) do update set attempts = b2b.intake_requests.attempts + 1
  returning id into v_id;
  begin
    v_res := b2b.intake_lead(v_lead, jsonb_build_object(
      'source_system', 'api', 'lead_source', coalesce(nullif(trim(p_body ->> 'source'), ''), 'api'), 'channel', p_body ->> 'channel',
      'campaign', p_body ->> 'campaign', 'utm', p_body -> 'utm', 'click_ids', p_body -> 'click_ids', 'landing_url', p_body ->> 'landing_url',
      'consent', p_body -> 'consent', 'occurred_at', p_body ->> 'occurred_at', 'idempotency_key', 'api:' || trim(p_idempotency_key),
      'attribution', jsonb_build_object('api_key', k ->> 'name', 'click_ids', p_body -> 'click_ids', 'utm', p_body -> 'utm'),
      'directive_source', 'api',
      'directive', case when coalesce(p_body ->> 'route', 'auto') <> 'auto' or coalesce((p_body ->> 'phone_verified')::boolean, false)
                        then jsonb_build_object('directive', case p_body ->> 'route' when 'hold' then 'hold' when 'b2c' then 'b2c' else 'route' end,
                                                'b2c_lane', case when p_body ->> 'route' = 'b2c' then coalesce(p_body ->> 'b2c_lane', 'sales') end,
                                                'phone_trusted', coalesce((p_body ->> 'phone_verified')::boolean, false)) end));
    update b2b.intake_requests set status = 'done', result = v_res, lead_id = (v_res ->> 'lead_id')::bigint, done_at = now(),
                                   is_test = coalesce((v_res ->> 'is_test')::boolean, false), error = null where id = v_id;
    return jsonb_build_object('ok', true, 'status', case when v_res ->> 'action' = 'created' then 201 else 200 end, 'result', v_res);
  exception when others then
    update b2b.intake_requests set status = 'error', error = left(sqlerrm, 300) where id = v_id;
    return jsonb_build_object('ok', false, 'status', case when sqlstate = '22023' then 422 else 500 end,
                              'error', case when sqlstate = '22023' then sqlerrm else 'could not store the lead; it was logged' end);
  end;
end $fn$;

-- ---------- Meta Lead Ads ----------
create or replace function b2b.meta_webhook_verify(p_mode text, p_token text, p_challenge text)
returns text language plpgsql stable security definer set search_path = '' as $fn$
declare v_token text := b2b.intake_secret('meta.verify_token_id');
begin
  if p_mode = 'subscribe' and v_token is not null and p_token = v_token and length(coalesce(p_challenge, '')) between 1 and 200 then return p_challenge; end if;
  return null;
end $fn$;

/* The webhook body, raw. Each leadgen change is stored once (by leadgen id); intake_tick fetches the lead. */
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
    perform b2b.log_event('alert.intake_bad_signature', null, null, null, jsonb_build_object('source', 'meta'));
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

/* A Meta or Google answer list [{key, value}] as standard intake fields, through the form's mapping. */
create or replace function b2b.form_answers_to_lead(p_platform text, p_form_ref text, p_answers jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  f b2b.lead_forms;
  v_std jsonb := case when p_platform = 'meta' then
      '{"full_name":"full_name","first_name":"first_name","last_name":"last_name","phone_number":"phone","phone":"phone","email":"email",
        "city":"city","state":"state","province":"state","country":"country"}'::jsonb
    else
      '{"FULL_NAME":"full_name","FIRST_NAME":"first_name","LAST_NAME":"last_name","PHONE_NUMBER":"phone","EMAIL":"email","CITY":"city",
        "REGION":"state","COUNTRY":"country"}'::jsonb end;
  o jsonb := '{}';
  other jsonb := '{}';
  a record;
  t text;
begin
  select * into f from b2b.lead_forms where platform = p_platform and form_ref = p_form_ref;
  for a in select x ->> 'key' k, x ->> 'value' v from jsonb_array_elements(coalesce(p_answers, '[]')) x loop
    continue when a.v is null or trim(a.v) = '';
    t := coalesce(f.field_map ->> a.k, v_std ->> a.k);
    if t is not null and t <> 'ignore' then o := o || jsonb_build_object(t, left(trim(a.v), 500));
    elsif t is null then other := other || jsonb_build_object(a.k, left(trim(a.v), 500)); end if;
  end loop;
  o := coalesce(f.defaults, '{}') || o;
  if other <> '{}' then o := o || jsonb_build_object('notes', left(coalesce(o ->> 'notes' || E'\n', '') ||
                                    (select string_agg(key || ': ' || (value #>> '{}'), E'\n') from jsonb_each(other)), 2000)); end if;
  return jsonb_build_object('lead', o, 'form', to_jsonb(f), 'unmapped', other);
end $fn$;

/* Writes one fetched Meta lead (the Graph API answer) through intake_lead. */
create or replace function b2b.meta_lead_apply(p_req_id bigint, g jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  q b2b.intake_requests;
  m jsonb;
  f jsonb;
  v_res jsonb;
  v_form text := coalesce(g ->> 'form_id', (select form_ref from b2b.intake_requests where id = p_req_id));
begin
  select * into q from b2b.intake_requests where id = p_req_id;
  if not exists (select 1 from b2b.lead_forms where platform = 'meta' and form_ref = v_form) then
    insert into b2b.lead_forms (platform, form_ref, name, page_ref) values ('meta', v_form, 'Meta form ' || v_form, q.raw ->> 'page_id')
    on conflict do nothing;
    perform b2b.log_event('alert.intake_new_form', null, null, null, jsonb_build_object('platform', 'meta', 'form_id', v_form));
  end if;
  m := b2b.form_answers_to_lead('meta', v_form,
         (select coalesce(jsonb_agg(jsonb_build_object('key', x ->> 'name', 'value', array_to_string(array(select jsonb_array_elements_text(x -> 'values')), ', '))), '[]')
            from jsonb_array_elements(coalesce(g -> 'field_data', '[]')) x));
  f := m -> 'form';
  v_res := b2b.intake_lead(m -> 'lead', jsonb_build_object(
    'source_system', 'meta', 'lead_source', 'meta_lead_ad', 'channel', 'meta_lead_ads',
    'campaign', coalesce(f ->> 'campaign', g ->> 'campaign_name'),
    'utm', jsonb_build_object('source', case lower(coalesce(g ->> 'platform', '')) when 'ig' then 'instagram' else 'facebook' end, 'medium', 'paid_social',
                              'campaign', g ->> 'campaign_name'),
    'click_ids', jsonb_strip_nulls(jsonb_build_object('leadgen_id', q.idempotency_key, 'form_id', v_form, 'ad_id', coalesce(g ->> 'ad_id', q.raw ->> 'ad_id'),
                                                      'adset_id', coalesce(g ->> 'adset_id', q.raw ->> 'adgroup_id'), 'campaign_id', g ->> 'campaign_id',
                                                      'page_id', q.raw ->> 'page_id', 'platform', g ->> 'platform')),
    'consent', jsonb_build_object('sales_at', case when 'sales' = any (array(select jsonb_array_elements_text(coalesce(f -> 'consent_purposes', '["sales"]')))) then g ->> 'created_time' end,
                                  'partner_share_at', case when 'partner_share' = any (array(select jsonb_array_elements_text(coalesce(f -> 'consent_purposes', '[]')))) then g ->> 'created_time' end,
                                  'marketing_at', case when 'marketing' = any (array(select jsonb_array_elements_text(coalesce(f -> 'consent_purposes', '[]')))) then g ->> 'created_time' end,
                                  'text_version', coalesce(f ->> 'consent_version', 'meta_form:' || v_form)),
    'occurred_at', g ->> 'created_time', 'idempotency_key', 'meta:' || q.idempotency_key,
    'attribution', jsonb_build_object('platform', 'meta', 'form_id', v_form, 'ad_id', g ->> 'ad_id', 'campaign_id', g ->> 'campaign_id',
                                      'organic', g ->> 'is_organic', 'unmapped', m -> 'unmapped')));
  update b2b.intake_requests set status = 'done', result = v_res, lead_id = (v_res ->> 'lead_id')::bigint, done_at = now(), error = null,
                                 raw = q.raw || jsonb_build_object('graph', g) where id = q.id;
  return v_res;
end $fn$;

-- ---------- Google Ads lead forms ----------
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
    perform b2b.log_event('alert.intake_bad_signature', null, null, null, jsonb_build_object('source', 'google'));
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

revoke execute on function b2b.intake_secret(text), b2b.intake_lead(jsonb, jsonb), b2b.api_intake_lead(text, text, jsonb), b2b.meta_webhook_verify(text, text, text),
                           b2b.meta_webhook_ingest(text, text), b2b.form_answers_to_lead(text, text, jsonb), b2b.meta_lead_apply(bigint, jsonb),
                           b2b.google_leadform_ingest(text)
  from public, anon, authenticated;
grant execute on function b2b.intake_secret(text), b2b.intake_lead(jsonb, jsonb), b2b.form_answers_to_lead(text, text, jsonb), b2b.meta_lead_apply(bigint, jsonb)
  to service_role;
-- machine endpoints: the functions are the only gate (API key, signature, google_key)
grant execute on function b2b.api_intake_lead(text, text, jsonb), b2b.meta_webhook_verify(text, text, text), b2b.meta_webhook_ingest(text, text),
                          b2b.google_leadform_ingest(text)
  to anon, authenticated, service_role;
