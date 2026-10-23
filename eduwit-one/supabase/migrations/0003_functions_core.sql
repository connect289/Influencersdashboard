-- 0003 (core) settings, secrets, heartbeats, the app call, and the incident lifecycle (spec §5, §9).
-- Every function sets search_path = '' and is SECURITY DEFINER only where it reads Vault.

-- Settings ---------------------------------------------------------------------------------------------------------

create or replace function one.setting(p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select value from one.settings where key = p_key
$$;

create or replace function one.threshold(p_key text) returns numeric
language sql stable set search_path = '' as $$
  select (value ->> p_key)::numeric from one.settings where key = 'thresholds'
$$;

-- Versioned write. A seed never overwrites a value a person changed (spec §16.8). Returns the version in force.
create or replace function one.settings_put(p_key text, p_value jsonb, p_actor text, p_reason text default null) returns integer
language plpgsql set search_path = '' as $$
declare
  v_row one.settings;
begin
  select * into v_row from one.settings where key = p_key for update;
  if found and p_actor = 'seed' and v_row.actor <> 'seed' then
    return v_row.version;
  end if;
  if found and v_row.value = p_value then
    return v_row.version;
  end if;
  insert into one.settings (key, value, version, actor, updated_at)
  values (p_key, p_value, coalesce(v_row.version, 0) + 1, p_actor, now())
  on conflict (key) do update set value = excluded.value, version = excluded.version, actor = excluded.actor, updated_at = now();
  insert into one.settings_versions (key, version, value, reason, actor)
  values (p_key, coalesce(v_row.version, 0) + 1, p_value, p_reason, p_actor);
  return coalesce(v_row.version, 0) + 1;
end $$;

-- Secrets ----------------------------------------------------------------------------------------------------------

-- Only Eduwit One's own secrets plus the two app keys PLAT-05 and job calls need (spec §5).
create or replace function one.secret(p_name text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_value text;
begin
  if p_name !~ '^one_[a-z0-9_]+$' and p_name not in ('b2c_internal_key', 'web_internal_key') then
    raise exception 'one.secret: % is not readable by Eduwit One', p_name using errcode = '42501';
  end if;
  select decrypted_secret into v_value from vault.decrypted_secrets where name = p_name;
  return v_value;
end $$;

-- Names only, never values: lets checks and the Setup page see which secrets exist.
create or replace function one.vault_names() returns setof text
language sql stable security definer set search_path = '' as $$
  select name from vault.secrets where name ~ '^(one_[a-z0-9_]+|b2c_internal_key|web_internal_key|inf_[a-z0-9_]+)$' order by name
$$;

-- Heartbeats -------------------------------------------------------------------------------------------------------

create or replace function one.heartbeat(p_component text, p_ok boolean, p_detail jsonb default '{}',
                                         p_error text default null, p_expected_interval_s integer default null) returns void
language sql set search_path = '' as $$
  insert into one.heartbeats (component, last_ok_at, last_error_at, last_error, detail, expected_interval_s)
  values (p_component, case when p_ok then now() end, case when not p_ok then now() end,
          case when not p_ok then left(p_error, 500) end, coalesce(p_detail, '{}'), coalesce(p_expected_interval_s, 300))
  on conflict (component) do update set
    last_ok_at = case when p_ok then now() else one.heartbeats.last_ok_at end,
    last_error_at = case when not p_ok then now() else one.heartbeats.last_error_at end,
    last_error = case when not p_ok then left(p_error, 500) else one.heartbeats.last_error end,
    detail = coalesce(p_detail, one.heartbeats.detail),
    expected_interval_s = coalesce(p_expected_interval_s, one.heartbeats.expected_interval_s)
$$;

-- The database calls the app, exactly like b2c.job_call and web_job_call. A missing base URL or key means
-- "not configured": nothing is sent and null is returned.
create or replace function one.job_call(p_path text, p_timeout_ms integer default 55000) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_base text := one.setting('app') ->> 'base_url';
  v_key text;
begin
  if p_path !~ '^/api/internal/[a-z0-9/-]+$' then
    raise exception 'one.job_call: bad path %', p_path using errcode = '22023';
  end if;
  if v_base is null or v_base !~ '^https?://[^/\s]+$' then
    return null;
  end if;
  v_key := one.secret('one_internal_key');
  if v_key is null then
    return null;
  end if;
  return net.http_post(
    url := v_base || p_path,
    body := '{}'::jsonb,
    headers := jsonb_build_object('content-type', 'application/json', 'authorization', 'Bearer ' || v_key),
    timeout_milliseconds := greatest(1000, least(p_timeout_ms, 300000)));
end $$;

-- Mutes ------------------------------------------------------------------------------------------------------------

create or replace function one.is_muted(p_check_id text, p_app text) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from one.mutes m
     where now() between m.starts_at and m.ends_at
       and ((m.target_type = 'check' and m.target = p_check_id) or (m.target_type = 'app' and m.target = p_app)))
    or exists (select 1 from one.checks c where c.id = p_check_id and c.muted_until > now())
$$;

-- Alerts and AI tasks ----------------------------------------------------------------------------------------------

-- Queues one email per P1 recipient for an incident at an escalation level. Idempotent by key.
create or replace function one.enqueue_alert(p_incident_id bigint, p_level integer default 0) returns integer
language plpgsql set search_path = '' as $$
declare
  v_recipients jsonb := coalesce(one.setting('alerts') -> 'p1' -> 'email', '[]');
  v_count integer := 0;
  v_to text;
begin
  for v_to in select jsonb_array_elements_text(v_recipients) loop
    insert into one.deliveries (incident_id, channel, recipient, kind, escalation_level, idempotency_key)
    values (p_incident_id, 'email', v_to, case when p_level = 0 then 'alert' else 'escalation' end, p_level,
            format('alert:%s:%s:email:%s', p_incident_id, p_level, lower(v_to)))
    on conflict (idempotency_key) do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function one.enqueue_ai(p_kind text, p_input jsonb, p_model_hint text default null,
                                          p_idempotency_key text default null, p_incident_id bigint default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into one.ai_tasks (kind, input, model_hint, idempotency_key, incident_id)
  values (p_kind, coalesce(p_input, '{}'), p_model_hint, p_idempotency_key, p_incident_id)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  return v_id;
end $$;

-- Incident lifecycle (spec §9) ---------------------------------------------------------------------------------------

-- Routes a newly opened or reopened incident: P1 alerts now, P2 waits for the brief, P3 is dashboard only;
-- a muted check or app records but does not deliver. Every opening gets an AI triage task.
create or replace function one.route_incident(p_incident one.incidents) returns void
language plpgsql set search_path = '' as $$
declare
  v_state text;
begin
  v_state := case
    when one.is_muted(p_incident.check_id, p_incident.app) then 'muted'
    when p_incident.severity = 'P1' then 'pending'
    when p_incident.severity = 'P2' then 'digest'
    else 'none' end;
  update one.incidents set alert_state = v_state where id = p_incident.id;
  if v_state = 'pending' then
    perform one.enqueue_alert(p_incident.id, 0);
  end if;
  perform one.enqueue_ai('triage', jsonb_build_object('incident_id', p_incident.id, 'check_id', p_incident.check_id),
                         null, format('triage:%s:%s', p_incident.id, p_incident.reopened_count), p_incident.id);
end $$;

create or replace function one.open_or_touch_incident(p_check_id text, p_severity one.severity, p_evidence jsonb) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_inc one.incidents;
begin
  select * into strict v_check from one.checks where id = p_check_id;
  select * into v_inc from one.incidents where check_id = p_check_id and resolved_at is null for update;
  if found then
    update one.incidents
       set occurrences = occurrences + 1, last_seen_at = now(), evidence = p_evidence,
           severity = least(severity, p_severity)::one.severity
     where id = v_inc.id;
    return v_inc.id;
  end if;
  -- Reopen, not duplicate, when the same check fails again within 24 h of recovering.
  select * into v_inc from one.incidents
   where check_id = p_check_id and resolved_at > now() - interval '24 hours' and resolution = 'recovered'
   order by resolved_at desc limit 1 for update;
  if found then
    update one.incidents
       set resolved_at = null, resolved_by = null, resolution = null, resolution_note = null,
           reopened_count = reopened_count + 1, occurrences = occurrences + 1, last_seen_at = now(),
           evidence = p_evidence, severity = p_severity, acknowledged_at = null, acknowledged_by = null
     where id = v_inc.id
     returning * into v_inc;
  else
    insert into one.incidents (check_id, app, severity, title, evidence, first_evidence, tags)
    values (p_check_id, v_check.app, p_severity, v_check.title, p_evidence, p_evidence, v_check.tags)
    returning * into v_inc;
  end if;
  perform one.route_incident(v_inc);
  return v_inc.id;
end $$;

create or replace function one.resolve_incident(p_incident_id bigint, p_by text, p_resolution text, p_note text default null) returns void
language sql set search_path = '' as $$
  update one.incidents
     set resolved_at = now(), resolved_by = p_by, resolution = p_resolution, resolution_note = p_note
   where id = p_incident_id and resolved_at is null
$$;

create or replace function one.acknowledge_incident(p_incident_id bigint, p_by text) returns void
language sql set search_path = '' as $$
  update one.incidents set acknowledged_at = now(), acknowledged_by = p_by
   where id = p_incident_id and acknowledged_at is null and resolved_at is null
$$;

-- Actions ----------------------------------------------------------------------------------------------------------

create or replace function one.record_action(p_fix_id text, p_incident_id bigint, p_app text, p_target jsonb,
                                             p_dry_run boolean, p_status text, p_result jsonb, p_by text,
                                             p_idempotency_key text default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into one.actions (fix_id, incident_id, app, target, dry_run, status, result, ran_by, idempotency_key)
  values (p_fix_id, p_incident_id, p_app, coalesce(p_target, '{}'), p_dry_run, p_status, coalesce(p_result, '{}'), p_by, p_idempotency_key)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  return v_id;
end $$;

call one.apply_grants();
grant execute on function one.setting(text), one.threshold(text), one.vault_names() to eduwit_one_reader, service_role;
grant execute on function one.settings_put(text, jsonb, text, text), one.heartbeat(text, boolean, jsonb, text, integer),
  one.resolve_incident(bigint, text, text, text), one.acknowledge_incident(bigint, text),
  one.record_action(text, bigint, text, jsonb, boolean, text, jsonb, text, text),
  one.enqueue_ai(text, jsonb, text, text, bigint), one.is_muted(text, text) to service_role;
