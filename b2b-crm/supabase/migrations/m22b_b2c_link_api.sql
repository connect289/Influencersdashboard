-- M22b: the B2C CRM link, part 2 (follows m22a): the API the B2C CRM uses instead of reading or writing
-- public.student_leads. Every call takes an API key with the 'b2c' scope (checked here).
--   api_b2c_schema        the field catalogue, which fields B2C may write now, and the stage list
--   api_b2c_lead_get      one lead's current record and version
--   api_b2c_leads_feed    every change in order (the feed cursor is the sync sequence): rebuild or catch up a local copy
--   api_b2c_lead_lookup   find leads by phone or email
--   api_b2c_lead_update   writes B2C's fields on a lead it holds: validated, idempotent (request_id), optionally guarded
--                         by if_version, audited with the B2C user who made the change
--   api_b2c_activity      logs a call, message, meeting or note; contact fields follow

/* One value for a catalogue field, checked and converted. Returns {"value": …} or {"error": "…"}. */
create or replace function b2b.b2c_coerce(f jsonb, v jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  k text := f ->> 'kind';
  m numeric := nullif(f ->> 'max', '')::numeric;
  t text := case when jsonb_typeof(v) in ('string', 'number', 'boolean') then trim(v #>> '{}') end;
  n numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' or (t = '' and k <> 'json') then
    return case when f ->> 'field' in ('name') then jsonb_build_object('error', 'cannot be empty') else jsonb_build_object('value', null) end;
  end if;
  if k = 'json' then
    if jsonb_typeof(v) <> 'object' then return jsonb_build_object('error', 'must be an object'); end if;
    if length(v::text) > coalesce(m, 20000) then return jsonb_build_object('error', 'is too large'); end if;
    return jsonb_build_object('value', v);
  end if;
  if t is null then return jsonb_build_object('error', 'must be a text, number or true/false value'); end if;
  case k
    when 'text' then
      if length(t) > coalesce(m, 300)::int then return jsonb_build_object('error', 'is longer than ' || coalesce(m, 300)::int || ' characters'); end if;
      return jsonb_build_object('value', t);
    when 'email' then
      if lower(t) !~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$' or length(t) > 200 then return jsonb_build_object('error', 'is not an email address'); end if;
      return jsonb_build_object('value', lower(t));
    when 'phone' then
      t := regexp_replace(t, '\D', '', 'g');
      if length(t) = 10 then t := '91' || t; end if;
      if length(t) not between 11 and 15 then return jsonb_build_object('error', 'is not a phone number'); end if;
      return jsonb_build_object('value', t);
    when 'int', 'numeric', 'pct' then
      if t !~ '^-?\d+(\.\d+)?$' then return jsonb_build_object('error', 'must be a number'); end if;
      n := t::numeric;
      if k = 'int' and n <> trunc(n) then return jsonb_build_object('error', 'must be a whole number'); end if;
      if n < 0 or n > (case when k = 'pct' then 100 else coalesce(m, 1000000000) end) then
        return jsonb_build_object('error', 'must be between 0 and ' || case when k = 'pct' then 100 else coalesce(m, 1000000000) end);
      end if;
      return jsonb_build_object('value', n);
    when 'ts' then
      if b2b.try_timestamptz(t) is null then return jsonb_build_object('error', 'must be an ISO 8601 date and time'); end if;
      return jsonb_build_object('value', b2b.try_timestamptz(t));
    when 'date' then
      if t !~ '^\d{4}-\d{2}-\d{2}$' or b2b.try_timestamptz(t || 'T00:00:00Z') is null then return jsonb_build_object('error', 'must be a date (YYYY-MM-DD)'); end if;
      return jsonb_build_object('value', t);
    when 'uuid' then
      if lower(t) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return jsonb_build_object('error', 'must be a UUID'); end if;
      return jsonb_build_object('value', lower(t));
    when 'stage' then
      -- checked against the stage list by the caller
      if length(t) > 60 then return jsonb_build_object('error', 'is not a known stage'); end if;
      return jsonb_build_object('value', lower(t));
    when 'temperature' then
      if lower(t) not in ('hot', 'warm', 'cold') then return jsonb_build_object('error', 'must be hot, warm or cold'); end if;
      return jsonb_build_object('value', lower(t));
    else return jsonb_build_object('error', 'cannot be written');
  end case;
end $fn$;

create or replace function b2b.b2c_stage_keys()
returns text[] language sql stable set search_path = '' as $fn$
  select coalesce(array_agg(e ->> 'key'), '{}') from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null;
$fn$;

create or replace function b2b.b2c_key(p_key text)
returns jsonb language sql volatile security definer set search_path = '' as $fn$
  select b2b.api_key_check(p_key, 'b2c');
$fn$;

create or replace function b2b.b2c_version(p_lead_id bigint)
returns int language sql stable set search_path = '' as $fn$
  select coalesce((select version from b2b.b2c_sync where lead_id = p_lead_id), 0);
$fn$;

create or replace function b2b.api_b2c_schema(p_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'scope', cfg ->> 'scope', 'enabled', coalesce((cfg ->> 'enabled')::boolean, true),
    'fields', (select jsonb_agg(jsonb_build_object('field', f ->> 'field', 'group', f ->> 'group', 'kind', f ->> 'kind', 'max', f -> 'max',
                                                   'writable', f ->> 'write' = 'b2c' and (cfg -> 'writable') ? (f ->> 'field')))
                 from jsonb_array_elements(b2b.b2c_fields()) f),
    'stages', (select jsonb_agg(jsonb_build_object('key', e ->> 'key', 'rank', e -> 'rank', 'group', e ->> 'group'))
                 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null),
    'activity_kinds', jsonb_build_array('call', 'whatsapp', 'sms', 'email', 'meeting', 'note')));
end $fn$;

create or replace function b2b.api_b2c_lead_get(p_key text, p_lead_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  l public.student_leads;
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null or not (b2b.b2c_holds(l) or (cfg ->> 'scope' = 'all' and l.deleted_at is null and l.merged_into_id is null)
                          or exists (select 1 from b2b.b2c_sync s where s.lead_id = l.id and s.in_scope)) then
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead shared with the B2C CRM');
  end if;
  -- make sure the version answered is current
  perform b2b.b2c_sync_lead(l.id);
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('version', b2b.b2c_version(l.id), 'record', b2b.b2c_record(l)));
end $fn$;

create or replace function b2b.api_b2c_leads_feed(p_key text, p_after bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_rows jsonb;
  v_last bigint;
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  with page as (
    select s.* from b2b.b2c_sync s where s.seq > coalesce(p_after, 0) order by s.seq limit least(greatest(coalesce(p_limit, 100), 1), 500))
  select coalesce(jsonb_agg(jsonb_build_object(
           'type', case when p.in_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end, 'lead_id', p.lead_id, 'version', p.version, 'seq', p.seq,
           'changed_at', p.changed_at,
           'record', case when p.in_scope then (select b2b.b2c_record(l) from public.student_leads l where l.id = p.lead_id) end) order by p.seq), '[]'),
         max(p.seq)
    into v_rows, v_last from page p;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('leads', v_rows, 'next_after', coalesce(v_last, p_after, 0)));
end $fn$;

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
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('leads', coalesce((
    select jsonb_agg(jsonb_build_object('lead_id', l.id, 'version', b2b.b2c_version(l.id), 'held_by_b2c', b2b.b2c_holds(l),
                                        'record', case when b2b.b2c_holds(l) or cfg ->> 'scope' = 'all' then b2b.b2c_record(l) end) order by l.id desc)
      from public.student_leads l
     where l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null
       and ((length(v_phone) >= 11 and regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = v_phone)
            or (v_email <> '' and lower(l.email_id) = v_email))), '[]')));
end $fn$;

/* B2C writes its fields on a lead it holds. p: {request_id, if_version?, actor: {id, email, name}, set: {field: value}}. */
create or replace function b2b.api_b2c_lead_update(p_key text, p_lead_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.b2c_key(p_key);
  cfg jsonb := b2b.b2c_link_cfg();
  v_req text := left(trim(coalesce(p ->> 'request_id', '')), 100);
  v_actor jsonb := coalesce(p -> 'actor', '{}');
  l public.student_leads;
  w b2b.b2c_writes;
  f jsonb;
  c jsonb;
  v_key text;
  v_val jsonb;
  v_ver int;
  v_errors jsonb := '{}';
  v_cols jsonb := '{}';
  v_diff jsonb := '{}';
  v_row jsonb;
  v_sql text;
  v_res jsonb;
  v_status int;
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_req = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'request_id is required (unique per change, reused on retries)'); end if;
  select * into w from b2b.b2c_writes where coalesce(api_key_id, 0) = coalesce((k ->> 'api_key_id')::bigint, 0) and kind = 'update' and request_id = v_req;
  if w.id is not null then return w.response || jsonb_build_object('replayed', true); end if;
  if jsonb_typeof(p -> 'set') is distinct from 'object' or (select count(*) from jsonb_object_keys(p -> 'set')) = 0 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'set must be an object of field: value');
  end if;
  if jsonb_typeof(v_actor) <> 'object' or length(v_actor::text) > 1000 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'actor must be a small object'); end if;

  select * into l from public.student_leads where id = p_lead_id for update;
  v_ver := b2b.b2c_version(p_lead_id);
  v_res := case
    when l.id is null then jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead')
    when l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null
      then jsonb_build_object('ok', false, 'status', 410, 'error', 'the lead was deleted or merged', 'merged_into_id', l.merged_into_id)
    when not b2b.b2c_holds(l) then jsonb_build_object('ok', false, 'status', 409, 'error', 'the B2C CRM does not hold this lead', 'destination', l.destination_type)
    when p ? 'if_version' and nullif(p ->> 'if_version', '')::int is distinct from v_ver
      then jsonb_build_object('ok', false, 'status', 409, 'error', 'version conflict: the lead changed since your copy', 'version', v_ver,
                              'record', b2b.b2c_record(l))
  end;
  if v_res is null then
    for v_key, v_val in select key, value from jsonb_each(p -> 'set') loop
      select x into f from jsonb_array_elements(b2b.b2c_fields()) x where x ->> 'field' = v_key;
      if f is null then v_errors := v_errors || jsonb_build_object(v_key, 'unknown field'); continue; end if;
      if f ->> 'write' <> 'b2c' or not (cfg -> 'writable') ? v_key then v_errors := v_errors || jsonb_build_object(v_key, 'is read-only for the B2C CRM'); continue; end if;
      c := b2b.b2c_coerce(f, v_val);
      if c ? 'error' then v_errors := v_errors || jsonb_build_object(v_key, c ->> 'error'); continue; end if;
      if f ->> 'kind' = 'stage' and c ->> 'value' is not null and not (c ->> 'value') = any (b2b.b2c_stage_keys()) then
        v_errors := v_errors || jsonb_build_object(v_key, 'is not a known stage'); continue;
      end if;
      if v_key = 'custom_fields' then
        c := jsonb_build_object('value', jsonb_strip_nulls(coalesce(l.custom_fields, '{}') || coalesce(c -> 'value', '{}')));
      end if;
      if (to_jsonb(l) -> (f ->> 'column')) is distinct from (c -> 'value') then
        v_cols := v_cols || jsonb_build_object(f ->> 'column', c -> 'value');
        v_diff := v_diff || jsonb_build_object(v_key, jsonb_build_object('from', to_jsonb(l) -> (f ->> 'column'), 'to', c -> 'value'));
      end if;
    end loop;
    if v_errors <> '{}' then
      v_res := jsonb_build_object('ok', false, 'status', 422, 'error', 'some fields were refused', 'fields', v_errors);
    end if;
  end if;

  if v_res is null and v_diff = '{}' then
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('lead_id', l.id, 'version', v_ver, 'changed', '[]'::jsonb));
  elsif v_res is null then
    -- a new stage stamps stage_changed_at unless the caller gave it
    if v_cols ? 'stage' and not v_cols ? 'stage_changed_at' then v_cols := v_cols || jsonb_build_object('stage_changed_at', now()); end if;
    v_row := to_jsonb(l) || v_cols;
    select string_agg(format('%I = r.%I', x, x), ', ') into v_sql from jsonb_object_keys(v_cols) x;
    perform set_config('b2b.actor', 'b2c_crm', true);
    execute format('update public.student_leads t set %s, updated_by = $3 from jsonb_populate_record(null::public.student_leads, $1) r where t.id = $2', v_sql)
      using v_row, l.id, left('b2c_crm:' || coalesce(v_actor ->> 'email', v_actor ->> 'id', 'api'), 120);
    perform b2b.log_event('b2c.lead_updated', l.id, l.allocation_id, null,
                          jsonb_build_object('changes', v_diff, 'actor', v_actor, 'request_id', v_req, 'api_key', k ->> 'name'));
    perform b2b.b2c_sync_lead(l.id, false, 'b2c:' || v_req);
    perform b2b.outbox_kick();
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
      'lead_id', l.id, 'version', b2b.b2c_version(l.id), 'changed', (select jsonb_agg(x) from jsonb_object_keys(v_diff) x),
      'record', (select b2b.b2c_record(n) from public.student_leads n where n.id = l.id)));
  end if;

  v_status := (v_res ->> 'status')::int;
  insert into b2b.b2c_writes (api_key_id, request_id, lead_id, kind, actor, changes, status, http_status, error, version_before, version_after, response)
  values ((k ->> 'api_key_id')::bigint, v_req, p_lead_id, 'update', v_actor, coalesce(nullif(v_diff, '{}'), p -> 'set'),
          case when v_status = 200 and v_diff = '{}' then 'unchanged' when v_status = 200 then 'applied' when v_status = 409 and v_res ? 'version' then 'conflict' else 'rejected' end,
          v_status, v_res ->> 'error', v_ver, case when v_status = 200 then b2b.b2c_version(p_lead_id) end,
          v_res - 'record' || case when v_res -> 'result' ? 'record' then jsonb_build_object('result', (v_res -> 'result') - 'record') else '{}' end)
  on conflict do nothing;
  return v_res;
end $fn$;

/* A counsellor's activity on a lead B2C holds. p: {request_id, kind, at?, outcome?, duration_seconds?, note?, actor}. A call,
   message or meeting counts as a contact attempt and stamps first / last contacted; a note only last activity. */
create or replace function b2b.api_b2c_activity(p_key text, p_lead_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.b2c_key(p_key);
  v_req text := left(trim(coalesce(p ->> 'request_id', '')), 100);
  v_kind text := lower(coalesce(p ->> 'kind', ''));
  v_at timestamptz := coalesce(b2b.try_timestamptz(p ->> 'at'), now());
  v_actor jsonb := coalesce(p -> 'actor', '{}');
  v_act jsonb;
  l public.student_leads;
  w b2b.b2c_writes;
  v_res jsonb;
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_req = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'request_id is required'); end if;
  select * into w from b2b.b2c_writes where coalesce(api_key_id, 0) = coalesce((k ->> 'api_key_id')::bigint, 0) and kind = 'activity' and request_id = v_req;
  if w.id is not null then return w.response || jsonb_build_object('replayed', true); end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  v_res := case
    when v_kind not in ('call', 'whatsapp', 'sms', 'email', 'meeting', 'note') then jsonb_build_object('ok', false, 'status', 400, 'error', 'kind must be call, whatsapp, sms, email, meeting or note')
    when v_at > now() + interval '10 minutes' then jsonb_build_object('ok', false, 'status', 400, 'error', 'at is in the future')
    when length(coalesce(p ->> 'note', '')) > 2000 or length(coalesce(p ->> 'outcome', '')) > 80 then jsonb_build_object('ok', false, 'status', 400, 'error', 'note up to 2,000 characters, outcome up to 80')
    when jsonb_typeof(v_actor) <> 'object' or length(v_actor::text) > 1000 then jsonb_build_object('ok', false, 'status', 400, 'error', 'actor must be a small object')
    when l.id is null then jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead')
    when not b2b.b2c_holds(l) then jsonb_build_object('ok', false, 'status', 409, 'error', 'the B2C CRM does not hold this lead')
  end;
  if v_res is null then
    v_act := jsonb_strip_nulls(jsonb_build_object('kind', v_kind, 'at', v_at, 'outcome', nullif(trim(p ->> 'outcome'), ''),
                                                  'duration_seconds', case when (p ->> 'duration_seconds') ~ '^\d{1,6}$' then (p ->> 'duration_seconds')::int end,
                                                  'note', nullif(trim(p ->> 'note'), ''), 'actor', v_actor, 'request_id', v_req));
    perform set_config('b2b.actor', 'b2c_crm', true);
    update public.student_leads
       set last_activity_at = greatest(coalesce(last_activity_at, v_at), v_at),
           first_contacted_at = case when v_kind <> 'note' then least(coalesce(first_contacted_at, v_at), v_at) else first_contacted_at end,
           last_contacted_at = case when v_kind <> 'note' then greatest(coalesce(last_contacted_at, v_at), v_at) else last_contacted_at end,
           contact_attempts = coalesce(contact_attempts, 0) + case when v_kind <> 'note' then 1 else 0 end,
           updated_by = left('b2c_crm:' || coalesce(v_actor ->> 'email', v_actor ->> 'id', 'api'), 120)
     where id = l.id;
    perform b2b.log_event('b2c.activity', l.id, l.allocation_id, null, v_act);
    perform b2b.b2c_sync_lead(l.id, false, 'b2c:' || v_req);
    perform b2b.outbox_kick();
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('lead_id', l.id, 'version', b2b.b2c_version(l.id)));
  end if;
  insert into b2b.b2c_writes (api_key_id, request_id, lead_id, kind, actor, changes, status, http_status, error, version_after, response)
  values ((k ->> 'api_key_id')::bigint, v_req, p_lead_id, 'activity', v_actor, coalesce(v_act, p), case when (v_res ->> 'ok')::boolean then 'applied' else 'rejected' end,
          (v_res ->> 'status')::int, v_res ->> 'error', case when (v_res ->> 'ok')::boolean then b2b.b2c_version(p_lead_id) end, v_res)
  on conflict do nothing;
  return v_res;
end $fn$;

revoke execute on function b2b.b2c_coerce(jsonb, jsonb), b2b.b2c_stage_keys(), b2b.b2c_key(text), b2b.b2c_version(bigint) from public, anon, authenticated;
grant execute on function b2b.b2c_coerce(jsonb, jsonb), b2b.b2c_stage_keys(), b2b.b2c_key(text), b2b.b2c_version(bigint) to service_role;
revoke execute on function b2b.api_b2c_schema(text), b2b.api_b2c_lead_get(text, bigint), b2b.api_b2c_leads_feed(text, bigint, int),
                           b2b.api_b2c_lead_lookup(text, text, text), b2b.api_b2c_lead_update(text, bigint, jsonb), b2b.api_b2c_activity(text, bigint, jsonb)
  from public;
grant execute on function b2b.api_b2c_schema(text), b2b.api_b2c_lead_get(text, bigint), b2b.api_b2c_leads_feed(text, bigint, int),
                          b2b.api_b2c_lead_lookup(text, text, text), b2b.api_b2c_lead_update(text, bigint, jsonb), b2b.api_b2c_activity(text, bigint, jsonb)
  to anon, authenticated, service_role;
