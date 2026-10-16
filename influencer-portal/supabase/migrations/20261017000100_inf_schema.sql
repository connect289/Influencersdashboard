-- Influencer Portal: schema `inf`, grants, shared helpers, audit log.
-- Approved in SHARED_CHANGES.md S-1 (schema), S-2 (Data API exposure is a dashboard setting, not SQL).
-- Conventions: every function sets search_path = '' and qualifies every name; SECURITY DEFINER functions check the
-- caller themselves; nothing in `inf` is executable by PUBLIC unless granted explicitly.

create schema if not exists inf;
comment on schema inf is 'Eduwit Influencer Portal. Owned by the portal; other products must not write here.';

revoke all on schema inf from public;
grant usage on schema inf to anon, authenticated, service_role;

-- New functions are not executable by PUBLIC; new tables carry no privileges except for service_role.
alter default privileges in schema inf revoke execute on functions from public;
alter default privileges in schema inf grant all on tables to service_role;
alter default privileges in schema inf grant all on sequences to service_role;
alter default privileges in schema inf grant execute on functions to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Request metadata. The app server forwards the browser's IP and user agent in x-inf-client-ip / x-inf-user-agent
-- and a request id in x-request-id. PostgREST exposes request headers as the JSON GUC request.headers.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.request_header(p_name text) returns text
language sql stable set search_path = '' as $$
  select nullif(nullif(current_setting('request.headers', true), ''), 'null')::jsonb ->> lower(p_name);
$$;

create or replace function inf.request_ip() returns inet
language plpgsql stable set search_path = '' as $$
declare v text := coalesce(inf.request_header('x-inf-client-ip'), split_part(coalesce(inf.request_header('x-forwarded-for'), ''), ',', 1));
begin
  v := nullif(trim(v), '');
  if v is null or v !~ '^[0-9a-fA-F:.]{3,45}$' then return null; end if;
  return v::inet;
exception when others then return null;
end $$;

create or replace function inf.request_user_agent() returns text
language sql stable set search_path = '' as $$
  select left(coalesce(inf.request_header('x-inf-user-agent'), inf.request_header('user-agent')), 500);
$$;

create or replace function inf.request_id() returns text
language sql stable set search_path = '' as $$
  select left(inf.request_header('x-request-id'), 64);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Generic triggers
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Append-only tables: signatures, contract versions, ledger entries, audit log, stage events, deliveries…
create or replace function inf.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'inf.%: rows are append-only (% refused)', tg_table_name, lower(tg_op)
    using errcode = 'insufficient_privilege';
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- JSON Schema validation (subset of draft 2020-12, the subset zod's toJSONSchema emits): type, enum, const,
-- string length and pattern, numeric bounds, multipleOf, object properties / required / additionalProperties,
-- min/maxProperties, array items / prefixItems / min/maxItems / uniqueItems, anyOf / oneOf / allOf / not.
-- Unknown annotation keywords ($schema, title, description, default, format…) are ignored; $ref is refused so a
-- schema we can't fully check never passes silently. Returns at most 20 errors as "path: message".
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.json_schema_errors(p_value jsonb, p_schema jsonb, p_path text default '$')
returns text[]
language plpgsql immutable set search_path = '' as $$
declare
  v_errs   text[] := '{}';
  v_type   text := jsonb_typeof(p_value);
  v_types  jsonb;
  v_ok     boolean;
  v_key    text;
  v_val    jsonb;
  v_sub    text[];
  v_count  int;
  v_num    numeric;
  v_len    int;
  v_idx    int;
begin
  if p_schema is null or p_schema = 'true'::jsonb or p_schema = '{}'::jsonb then return v_errs; end if;
  if p_schema = 'false'::jsonb then return array[p_path || ': value not allowed']; end if;
  if jsonb_typeof(p_schema) <> 'object' then return array[p_path || ': invalid schema']; end if;
  if p_schema ? '$ref' then return array[p_path || ': $ref is not supported by the validator']; end if;

  if p_schema ? 'type' then
    v_types := case when jsonb_typeof(p_schema -> 'type') = 'array' then p_schema -> 'type' else jsonb_build_array(p_schema -> 'type') end;
    select coalesce(bool_or(case
             when t = 'integer' then (case when v_type = 'number' then (p_value #>> '{}')::numeric = trunc((p_value #>> '{}')::numeric) else false end)
             else t = v_type end), false)
      into v_ok from jsonb_array_elements_text(v_types) t;
    if not v_ok then return array[format('%s: expected %s, got %s', p_path, v_types #>> '{}', v_type)]; end if;
  end if;

  if p_schema ? 'const' and p_value is distinct from (p_schema -> 'const') then
    v_errs := v_errs || format('%s: must equal %s', p_path, p_schema -> 'const');
  end if;
  if p_schema ? 'enum' and not exists (select 1 from jsonb_array_elements(p_schema -> 'enum') e where e = p_value) then
    v_errs := v_errs || format('%s: must be one of %s', p_path, p_schema -> 'enum');
  end if;

  if v_type = 'string' then
    v_len := char_length(p_value #>> '{}');
    if p_schema ? 'minLength' and v_len < (p_schema ->> 'minLength')::int then
      v_errs := v_errs || format('%s: at least %s characters', p_path, p_schema ->> 'minLength');
    end if;
    if p_schema ? 'maxLength' and v_len > (p_schema ->> 'maxLength')::int then
      v_errs := v_errs || format('%s: at most %s characters', p_path, p_schema ->> 'maxLength');
    end if;
    if p_schema ? 'pattern' then
      begin
        if (p_value #>> '{}') !~ (p_schema ->> 'pattern') then
          v_errs := v_errs || format('%s: does not match the required format', p_path);
        end if;
      exception when others then
        v_errs := v_errs || format('%s: pattern cannot be evaluated', p_path);
      end;
    end if;
  elsif v_type = 'number' then
    v_num := (p_value #>> '{}')::numeric;
    if p_schema ? 'minimum' and v_num < (p_schema ->> 'minimum')::numeric then
      v_errs := v_errs || format('%s: must be ≥ %s', p_path, p_schema ->> 'minimum');
    end if;
    if p_schema ? 'maximum' and v_num > (p_schema ->> 'maximum')::numeric then
      v_errs := v_errs || format('%s: must be ≤ %s', p_path, p_schema ->> 'maximum');
    end if;
    if jsonb_typeof(p_schema -> 'exclusiveMinimum') = 'number' and v_num <= (p_schema ->> 'exclusiveMinimum')::numeric then
      v_errs := v_errs || format('%s: must be > %s', p_path, p_schema ->> 'exclusiveMinimum');
    end if;
    if jsonb_typeof(p_schema -> 'exclusiveMaximum') = 'number' and v_num >= (p_schema ->> 'exclusiveMaximum')::numeric then
      v_errs := v_errs || format('%s: must be < %s', p_path, p_schema ->> 'exclusiveMaximum');
    end if;
    if p_schema ? 'multipleOf' and (p_schema ->> 'multipleOf')::numeric <> 0
       and mod(v_num, (p_schema ->> 'multipleOf')::numeric) <> 0 then
      v_errs := v_errs || format('%s: must be a multiple of %s', p_path, p_schema ->> 'multipleOf');
    end if;
  elsif v_type = 'object' then
    if p_schema ? 'required' then
      for v_key in select jsonb_array_elements_text(p_schema -> 'required') loop
        if not p_value ? v_key then v_errs := v_errs || format('%s.%s: required', p_path, v_key); end if;
      end loop;
    end if;
    select count(*) into v_count from jsonb_object_keys(p_value);
    if p_schema ? 'minProperties' and v_count < (p_schema ->> 'minProperties')::int then
      v_errs := v_errs || format('%s: at least %s properties', p_path, p_schema ->> 'minProperties');
    end if;
    if p_schema ? 'maxProperties' and v_count > (p_schema ->> 'maxProperties')::int then
      v_errs := v_errs || format('%s: at most %s properties', p_path, p_schema ->> 'maxProperties');
    end if;
    for v_key, v_val in select key, value from jsonb_each(p_value) loop
      if p_schema -> 'properties' ? v_key then
        v_errs := v_errs || inf.json_schema_errors(v_val, p_schema -> 'properties' -> v_key, p_path || '.' || v_key);
      elsif p_schema ? 'additionalProperties' then
        if p_schema -> 'additionalProperties' = 'false'::jsonb then
          v_errs := v_errs || format('%s.%s: unknown property', p_path, v_key);
        elsif jsonb_typeof(p_schema -> 'additionalProperties') = 'object' then
          v_errs := v_errs || inf.json_schema_errors(v_val, p_schema -> 'additionalProperties', p_path || '.' || v_key);
        end if;
      end if;
      exit when cardinality(v_errs) >= 20;
    end loop;
  elsif v_type = 'array' then
    v_count := jsonb_array_length(p_value);
    if p_schema ? 'minItems' and v_count < (p_schema ->> 'minItems')::int then
      v_errs := v_errs || format('%s: at least %s items', p_path, p_schema ->> 'minItems');
    end if;
    if p_schema ? 'maxItems' and v_count > (p_schema ->> 'maxItems')::int then
      v_errs := v_errs || format('%s: at most %s items', p_path, p_schema ->> 'maxItems');
    end if;
    if coalesce((p_schema ->> 'uniqueItems')::boolean, false)
       and (select count(distinct e) from jsonb_array_elements(p_value) e) <> v_count then
      v_errs := v_errs || format('%s: items must be unique', p_path);
    end if;
    for v_idx in 0 .. v_count - 1 loop
      if p_schema ? 'prefixItems' and v_idx < jsonb_array_length(p_schema -> 'prefixItems') then
        v_errs := v_errs || inf.json_schema_errors(p_value -> v_idx, p_schema -> 'prefixItems' -> v_idx, format('%s[%s]', p_path, v_idx));
      elsif p_schema ? 'items' and jsonb_typeof(p_schema -> 'items') in ('object', 'boolean') then
        v_errs := v_errs || inf.json_schema_errors(p_value -> v_idx, p_schema -> 'items', format('%s[%s]', p_path, v_idx));
      end if;
      exit when cardinality(v_errs) >= 20;
    end loop;
  end if;

  if p_schema ? 'allOf' then
    for v_val in select jsonb_array_elements(p_schema -> 'allOf') loop
      v_errs := v_errs || inf.json_schema_errors(p_value, v_val, p_path);
    end loop;
  end if;
  if p_schema ? 'anyOf' then
    v_ok := false;
    for v_val in select jsonb_array_elements(p_schema -> 'anyOf') loop
      if cardinality(inf.json_schema_errors(p_value, v_val, p_path)) = 0 then v_ok := true; exit; end if;
    end loop;
    if not v_ok then v_errs := v_errs || format('%s: does not match any allowed shape', p_path); end if;
  end if;
  if p_schema ? 'oneOf' then
    v_count := 0;
    for v_val in select jsonb_array_elements(p_schema -> 'oneOf') loop
      if cardinality(inf.json_schema_errors(p_value, v_val, p_path)) = 0 then v_count := v_count + 1; end if;
    end loop;
    if v_count <> 1 then v_errs := v_errs || format('%s: must match exactly one allowed shape (matched %s)', p_path, v_count); end if;
  end if;
  if p_schema ? 'not' and cardinality(inf.json_schema_errors(p_value, p_schema -> 'not', p_path)) = 0 then
    v_errs := v_errs || format('%s: matches a forbidden shape', p_path);
  end if;

  return v_errs[1:20];
end $$;

create or replace function inf.json_matches_schema(p_value jsonb, p_schema jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select cardinality(inf.json_schema_errors(p_value, p_schema)) = 0;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Audit log (spec 2.7): every create, update or delete on business entities and every status transition.
-- Append-only. Written by inf.audit_row() (table trigger) and inf.audit() (explicit events).
-- ---------------------------------------------------------------------------------------------------------------
create table if not exists inf.audit_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_id    uuid,
  actor_role  text,
  entity_type text not null,
  entity_id   text,
  action      text not null,
  before      jsonb,
  after       jsonb,
  ip          inet,
  user_agent  text,
  request_id  text
);
create index if not exists audit_log_entity_idx on inf.audit_log (entity_type, entity_id, at desc);
create index if not exists audit_log_actor_idx on inf.audit_log (actor_id, at desc);
create index if not exists audit_log_at_idx on inf.audit_log (at desc);
alter table inf.audit_log enable row level security;

create trigger audit_log_append_only before update or delete on inf.audit_log
  for each row execute function inf.forbid_mutation();
create trigger audit_log_no_truncate before truncate on inf.audit_log
  for each statement execute function inf.forbid_mutation();

-- Who is acting, as a short label. Defined here as a stub and replaced in the identity migration once roles exist.
create or replace function inf.actor_role() returns text
language sql stable set search_path = '' as $$
  select case when auth.role() = 'service_role' then 'service' else coalesce(auth.role(), 'system') end;
$$;

create or replace function inf.audit(p_entity_type text, p_entity_id text, p_action text, p_before jsonb default null, p_after jsonb default null)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into inf.audit_log (actor_id, actor_role, entity_type, entity_id, action, before, after, ip, user_agent, request_id)
  values (auth.uid(), inf.actor_role(), p_entity_type, p_entity_id, p_action, p_before, p_after,
          inf.request_ip(), inf.request_user_agent(), inf.request_id());
end $$;

-- Table trigger. TG_ARGV: [0] entity type label (defaults to the table name), [1..] columns to redact (e.g. encrypted
-- PAN). On UPDATE only the changed keys are stored; an update that changes nothing but updated_at is not logged.
create or replace function inf.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_old    jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_entity text := coalesce(nullif(tg_argv[0], ''), tg_table_name);
  v_redact text[] := coalesce(tg_argv[1:], '{}');
  v_before jsonb;
  v_after  jsonb;
  v_col    text;
begin
  foreach v_col in array v_redact loop
    if v_old ? v_col and v_old -> v_col <> 'null'::jsonb then v_old := jsonb_set(v_old, array[v_col], '"[redacted]"'); end if;
    if v_new ? v_col and v_new -> v_col <> 'null'::jsonb then v_new := jsonb_set(v_new, array[v_col], '"[redacted]"'); end if;
  end loop;
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(o.key, o.value), jsonb_object_agg(o.key, v_new -> o.key)
      into v_before, v_after
      from jsonb_each(v_old) o
     where o.key <> 'updated_at' and (v_new -> o.key) is distinct from o.value;
    if v_before is null then return new; end if;
  else
    v_before := v_old;
    v_after := v_new;
  end if;
  insert into inf.audit_log (actor_id, actor_role, entity_type, entity_id, action, before, after, ip, user_agent, request_id)
  values (auth.uid(), inf.actor_role(), v_entity, coalesce(v_new, v_old) ->> 'id', lower(tg_op), v_before, v_after,
          inf.request_ip(), inf.request_user_agent(), inf.request_id());
  return coalesce(new, old);
end $$;

revoke execute on function inf.audit(text, text, text, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function inf.audit_row() from public, anon, authenticated;
grant execute on function inf.json_schema_errors(jsonb, jsonb, text), inf.json_matches_schema(jsonb, jsonb) to authenticated;
