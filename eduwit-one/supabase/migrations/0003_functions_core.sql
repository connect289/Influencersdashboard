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

-- The shapes the database relies on, checked on every write: a malformed value would otherwise surface as an error
-- inside a tick, where it erases the very result it should report (m1 of the second review), or, for events, copy
-- rows with no PII list (M4). Raises 22023 with what is wrong; never returns the value.
create or replace function one.settings_check(p_key text, p_value jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare
  v_email text := '^[^@\s]+@[^@\s]+\.[a-z]{2,}$';
  v_bad text;
begin
  if jsonb_typeof(p_value) is distinct from 'object' then
    raise exception 'setting %: the value must be a JSON object', p_key using errcode = '22023';
  end if;
  case p_key
    when 'events' then
      if jsonb_typeof(p_value -> 'pii_columns') is distinct from 'array' or jsonb_array_length(p_value -> 'pii_columns') = 0
         or exists (select 1 from jsonb_array_elements(p_value -> 'pii_columns') e where jsonb_typeof(e) <> 'string') then
        raise exception 'setting events: pii_columns must be a non-empty list of key patterns' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'batch')::int, 5000) not between 100 and 50000
         or coalesce((p_value ->> 'id_overlap')::int, 0) not between 0 and 10000
         or coalesce((p_value ->> 'window_hours')::int, 48) not between 1 and 720 then
        raise exception 'setting events: batch 100–50000, id_overlap 0–10000, window_hours 1–720' using errcode = '22023';
      end if;
    when 'alerts' then
      if jsonb_typeof(p_value #> '{p1,email}') is distinct from 'array' or jsonb_array_length(p_value #> '{p1,email}') = 0 then
        raise exception 'setting alerts: p1.email must be a non-empty list of addresses' using errcode = '22023';
      end if;
      select string_agg(x, ', ') into v_bad
        from (select jsonb_array_elements_text(p_value #> '{p1,email}') x
              union all select jsonb_array_elements_text(coalesce(p_value #> '{escalation,second_contact}', '[]'))
              union all select p_value ->> 'developer_email' where p_value ->> 'developer_email' is not null) a
       where lower(x) !~ v_email;
      if v_bad is not null then
        raise exception 'setting alerts: not an email address: %', left(v_bad, 200) using errcode = '22023';
      end if;
      if coalesce((p_value #>> '{escalation,resend_min}')::numeric, 30) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,second_contact_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,repeat_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value ->> 'p2_digest_hour_ist')::numeric, 18) not between 0 and 23
         or coalesce((p_value ->> 'p2_digest_min_count')::numeric, 5) not between 0 and 1000
         or coalesce((p_value #>> '{storm,p1_count}')::numeric, 10) not between 2 and 1000
         or coalesce((p_value #>> '{storm,window_min}')::numeric, 5) not between 1 and 120
         or coalesce((p_value #>> '{storm,suppress_min}')::numeric, 15) not between 1 and 240 then
        raise exception 'setting alerts: an escalation, digest or storm number is out of range' using errcode = '22023';
      end if;
    when 'thresholds' then
      select string_agg(key, ', ') into v_bad from jsonb_each(p_value) where jsonb_typeof(value) <> 'number';
      if v_bad is not null then
        raise exception 'setting thresholds: not a number: %', left(v_bad, 200) using errcode = '22023';
      end if;
    when 'checks' then
      if coalesce(p_value ->> 'lock_timeout', '2s') !~ '^[0-9]{1,5}(ms|s)$'
         or coalesce(p_value ->> 'transaction_timeout', '30s') !~ '^[0-9]{1,5}(ms|s|min)$'
         or jsonb_typeof(coalesce(p_value -> 'source_missing_opens_incident', 'true')) <> 'boolean'
         or coalesce((p_value ->> 'slow_ms')::int, 5000) not between 100 and 600000 then
        raise exception 'setting checks: lock_timeout like "2s", transaction_timeout like "30s", a boolean source_missing_opens_incident, slow_ms 100–600000'
          using errcode = '22023';
      end if;
    when 'app' then
      if p_value ->> 'base_url' is not null and p_value ->> 'base_url' !~ '^https://[a-z0-9.-]+(:[0-9]+)?$' then
        raise exception 'setting app: base_url must be https://host with no path' using errcode = '22023';
      end if;
    else
      null;
  end case;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'setting %: a number field holds something else', p_key using errcode = '22023';
end $$;

-- Versioned write. A seed never overwrites a value a person changed (spec §16.8). Returns the version in force.
create or replace function one.settings_put(p_key text, p_value jsonb, p_actor text, p_reason text default null) returns integer
language plpgsql set search_path = '' as $$
declare
  v_row one.settings;
begin
  perform one.settings_check(p_key, p_value);
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
  -- https only: the bearer key must never travel in clear text (m15). A bad value is "not configured", and PLAT-05
  -- reports it.
  if v_base is null or v_base !~ '^https://[^/\s]+$' then
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

-- Queues one email per recipient for an incident at an escalation level: the P1 inbox at every level, plus the second
-- contact from level 2 (60 min, spec §9). The key carries the incident's alert_seq, so a reopen, an escalation or a
-- new subject alerts again while a retry of the same routing does not (D-043). Returns the deliveries actually queued.
create or replace function one.enqueue_alert(p_incident_id bigint, p_level integer default 0) returns integer
language plpgsql set search_path = '' as $$
declare
  v_alerts jsonb := coalesce(one.setting('alerts'), '{}');
  v_seq integer := (select alert_seq from one.incidents where id = p_incident_id);
  v_count integer := 0;
  v_to text;
begin
  for v_to in
    select distinct lower(x) from (
      select jsonb_array_elements_text(coalesce(v_alerts -> 'p1' -> 'email', '[]')) as x
      union all
      select jsonb_array_elements_text(coalesce(v_alerts -> 'escalation' -> 'second_contact', '[]')) where p_level >= 2) r
     where x ~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'
  loop
    insert into one.deliveries (incident_id, channel, recipient, kind, escalation_level, idempotency_key)
    values (p_incident_id, 'email', v_to, case when p_level = 0 then 'alert' else 'escalation' end, p_level,
            format('alert:%s:%s:%s:email:%s', p_incident_id, v_seq, p_level, v_to))
    on conflict (idempotency_key) do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end $$;

-- A copy to the developer for incidents tagged "code" (spec §9: failing function, migration drift, privilege audit,
-- build failed), when alerts.developer_email is set.
create or replace function one.enqueue_developer(p_incident_id bigint) returns integer
language plpgsql set search_path = '' as $$
declare
  v_to text := lower(nullif(one.setting('alerts') ->> 'developer_email', ''));
  v_seq integer := (select alert_seq from one.incidents where id = p_incident_id);
begin
  if v_to is null or v_to !~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    return 0;
  end if;
  insert into one.deliveries (incident_id, channel, recipient, kind, idempotency_key)
  values (p_incident_id, 'email', v_to, 'alert', format('dev:%s:%s:email:%s', p_incident_id, v_seq, v_to))
  on conflict (idempotency_key) do nothing;
  return case when found then 1 else 0 end;
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

-- Routes an incident each time it needs a person's attention again: opened, reopened, made more severe, or joined by
-- a new subject. P1 alerts now, P2 waits for the digest, P3 is dashboard only; a muted check or app records but does
-- not deliver. While an alert storm is open (ONE-STORM, routed in the last storm.suppress_min minutes), other P1s are
-- suppressed and filed under it; the storm itself alerts once and suppresses the P1s that opened with it (spec §9).
-- Each routing bumps alert_seq and gets one AI triage task, on the deep model for a storm.
create or replace function one.route_incident(p_incident_id bigint) returns void
language plpgsql set search_path = '' as $$
declare
  v_inc one.incidents;
  v_storm jsonb := coalesce(one.setting('alerts') -> 'storm', '{}');
  v_storm_id bigint;
  v_state text;
begin
  update one.incidents set alert_seq = alert_seq + 1, routed_at = now() where id = p_incident_id returning * into v_inc;
  select id into v_storm_id from one.incidents
   where check_id = 'ONE-STORM' and resolved_at is null and id <> v_inc.id
     and routed_at > now() - make_interval(mins => coalesce((v_storm ->> 'suppress_min')::int, 15));
  v_state := case
    when one.is_muted(v_inc.check_id, v_inc.app) then 'muted'
    when v_inc.severity = 'P1' and v_storm_id is not null then 'suppressed'
    when v_inc.severity = 'P1' then 'pending'
    when v_inc.severity = 'P2' then 'digest'
    else 'none' end;
  update one.incidents set alert_state = v_state, parent_id = coalesce(case when v_state = 'suppressed' then v_storm_id end, parent_id)
   where id = v_inc.id;
  if v_inc.check_id = 'ONE-STORM' then
    update one.incidents set alert_state = 'suppressed', parent_id = v_inc.id
     where severity = 'P1' and resolved_at is null and id <> v_inc.id and alert_state = 'pending'
       and routed_at > now() - make_interval(mins => coalesce((v_storm ->> 'window_min')::int, 5));
  end if;
  if v_state = 'pending' then
    perform one.enqueue_alert(v_inc.id, 0);
  end if;
  if v_state not in ('muted', 'suppressed') and 'code' = any (v_inc.tags) then
    perform one.enqueue_developer(v_inc.id);
  end if;
  perform one.enqueue_ai('triage', jsonb_build_object('incident_id', v_inc.id, 'check_id', v_inc.check_id, 'subjects', to_jsonb(v_inc.subjects)),
                         case when v_inc.check_id = 'ONE-STORM' then 'deep' end, format('triage:%s:%s', v_inc.id, v_inc.alert_seq), v_inc.id);
end $$;

-- Each minute (spec §9): an unacknowledged P1 is re-sent at resend_min (30), reaches the second contact at
-- second_contact_min (60), and repeats every repeat_min (60) until acknowledged, counted from its last routing. A
-- muted incident whose mute has ended, or one held by a storm that has passed, is routed again.
create or replace function one.escalate() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('alerts'), '{}');
  v_resend integer := coalesce((v_cfg #>> '{escalation,resend_min}')::int, 30);
  v_second integer := coalesce((v_cfg #>> '{escalation,second_contact_min}')::int, 60);
  v_repeat integer := greatest(coalesce((v_cfg #>> '{escalation,repeat_min}')::int, 60), 5);
  v_suppress integer := coalesce((v_cfg #>> '{storm,suppress_min}')::int, 15);
  v_row record;
  v_level integer;
  v_mins numeric;
  v_queued integer := 0;
  v_rerouted integer := 0;
begin
  for v_row in
    select i.id from one.incidents i
     where i.resolved_at is null
       and ((i.alert_state = 'muted' and not one.is_muted(i.check_id, i.app))
            or (i.alert_state = 'suppressed' and not exists (
                  select 1 from one.incidents s where s.check_id = 'ONE-STORM' and s.resolved_at is null
                     and s.routed_at > now() - make_interval(mins => v_suppress))))
  loop
    perform one.route_incident(v_row.id);
    v_rerouted := v_rerouted + 1;
  end loop;
  for v_row in
    select i.id, i.routed_at, i.alert_state from one.incidents i
     where i.resolved_at is null and i.acknowledged_at is null and i.severity = 'P1' and i.routed_at is not null
       and i.alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2')
  loop
    v_mins := extract(epoch from now() - v_row.routed_at) / 60;
    v_level := case when v_mins < v_resend then 0 when v_mins < v_second then 1
                    else 2 + floor((v_mins - v_second) / v_repeat)::int end;
    if v_level >= 1 then
      v_queued := v_queued + one.enqueue_alert(v_row.id, v_level);
      update one.incidents set alert_state = case when v_level = 1 then 'escalated_1' else 'escalated_2' end
       where id = v_row.id and alert_state is distinct from case when v_level = 1 then 'escalated_1' else 'escalated_2' end;
    end if;
  end loop;
  return jsonb_build_object('queued', v_queued, 'rerouted', v_rerouted);
end $$;

-- The P2 digest (spec §9): from p2_digest_hour_ist (18:00), once a day, to the P1 inbox, when more than
-- p2_digest_min_count P2 incidents opened that day (IST).
create or replace function one.digest() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('alerts'), '{}');
  v_local timestamp := now() at time zone 'Asia/Kolkata';
  v_count integer;
  v_to text;
  v_queued integer := 0;
begin
  if extract(hour from v_local) < coalesce((v_cfg ->> 'p2_digest_hour_ist')::numeric, 18) then
    return jsonb_build_object('due', false);
  end if;
  select count(*) into v_count from one.incidents
   where severity = 'P2' and (opened_at at time zone 'Asia/Kolkata')::date = v_local::date;
  if v_count <= coalesce((v_cfg ->> 'p2_digest_min_count')::int, 5) then
    return jsonb_build_object('due', true, 'p2_today', v_count, 'queued', 0);
  end if;
  for v_to in select distinct lower(x) from jsonb_array_elements_text(coalesce(v_cfg -> 'p1' -> 'email', '[]')) x loop
    insert into one.deliveries (channel, recipient, kind, idempotency_key)
    values ('email', v_to, 'digest', format('digest:%s:email:%s', v_local::date, v_to))
    on conflict (idempotency_key) do nothing;
    if found then v_queued := v_queued + 1; end if;
  end loop;
  return jsonb_build_object('due', true, 'p2_today', v_count, 'queued', v_queued);
end $$;

-- An incident whose check was switched off can never recover (the tick no longer runs the check), so it is closed as
-- accepted, naming the reason (m6 of the second review).
create or replace function one.close_disabled() returns integer
language plpgsql set search_path = '' as $$
declare
  v_n integer;
begin
  update one.incidents i
     set resolved_at = now(), resolved_by = 'one', resolution = 'accepted',
         resolution_note = left('check switched off: ' || coalesce(c.disabled_reason, 'no reason'), 300)
    from one.checks c
   where c.id = i.check_id and i.resolved_at is null and not c.enabled;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- The tick's alert step, isolated like the others: escalation, the digest and closing switched-off checks' incidents,
-- or alerts_error.
create or replace function one.alerts_step() returns jsonb
language plpgsql set search_path = '' as $$
begin
  return jsonb_build_object('alerts', one.escalate() || jsonb_build_object('digest', one.digest(), 'closed_disabled', one.close_disabled()));
exception when others then
  return jsonb_build_object('alerts_error', left(sqlerrm, 200));
end $$;

-- Opens, touches or reopens the check's incident. A touch only records the occurrence, unless the severity rose or a
-- subject entered the failing set: then the acknowledgement is cleared and it is routed again. subjects holds the
-- current failing set, so a subject that recovered and fails again alerts again (m5 of the second review). A run
-- that names no subjects keeps the set it had.
create or replace function one.open_or_touch_incident(p_check_id text, p_severity one.severity, p_evidence jsonb,
                                                      p_subjects text[] default '{}') returns bigint
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_inc one.incidents;
  v_new text[];
  v_escalated boolean;
begin
  select * into strict v_check from one.checks where id = p_check_id;
  select * into v_inc from one.incidents where check_id = p_check_id and resolved_at is null for update;
  if found then
    v_new := array(select x from unnest(coalesce(p_subjects, '{}')) x where not x = any (v_inc.subjects));
    v_escalated := p_severity < v_inc.severity;
    update one.incidents
       set occurrences = occurrences + 1, last_seen_at = now(), evidence = p_evidence,
           severity = least(severity, p_severity)::one.severity,
           subjects = case when cardinality(coalesce(p_subjects, '{}')) > 0 then p_subjects else subjects end,
           acknowledged_at = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_at end,
           acknowledged_by = case when v_escalated or cardinality(v_new) > 0 then null else acknowledged_by end
     where id = v_inc.id;
    if v_escalated or cardinality(v_new) > 0 then
      perform one.route_incident(v_inc.id);
    end if;
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
           evidence = p_evidence, severity = p_severity, acknowledged_at = null, acknowledged_by = null,
           subjects = coalesce(p_subjects, '{}')
     where id = v_inc.id
     returning * into v_inc;
  else
    insert into one.incidents (check_id, app, severity, title, evidence, first_evidence, tags, subjects)
    values (p_check_id, v_check.app, p_severity, v_check.title, p_evidence, p_evidence, v_check.tags, coalesce(p_subjects, '{}'))
    returning * into v_inc;
  end if;
  perform one.route_incident(v_inc.id);
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

insert into one.api_grants (fn, role, why) values
  ('one.setting(text)', 'eduwit_one_reader', 'read settings'),
  ('one.threshold(text)', 'eduwit_one_reader', 'read thresholds'),
  ('one.vault_names()', 'eduwit_one_reader', 'secret names, never values')
on conflict do nothing;
call one.apply_grants();
