-- 0011 what the pages write (spec §12, phase 4). Every write is to schema one, except the Setup page's secrets, which
-- go to Vault under Eduwit One's own one_* names (spec §15: "secrets entered here are written to Vault, never to the
-- table"; D-059). Each function checks the caller's role with one.ui_require(), takes the actor from the JWT, and
-- writes one audit row with the request id (spec §13). Nothing here edits an app's data: the write paths into the
-- apps are their own deep links and, later, approved proposals run through the apps' own functions (spec §12).

create or replace function one.ui_audit_write(p_actor text, p_action text, p_target text, p_before jsonb, p_after jsonb, p_request_id text) returns void
language sql set search_path = '' as $$
  insert into one.audit (actor, action, target, before, after, request_id)
  values (left(p_actor, 120), p_action, left(p_target, 200), p_before, p_after, left(p_request_id, 80))
$$;

create or replace function one.ui_reason(p_text text) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if length(trim(coalesce(p_text, ''))) < 3 then
    raise exception 'give a reason' using errcode = '22023';
  end if;
  return left(trim(p_text), 500);
end $$;

-- Incidents ---------------------------------------------------------------------------------------------------------

create or replace function one.ui_ack(p_id bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
begin
  if not exists (select 1 from one.incidents where id = p_id and resolved_at is null) then
    raise exception 'no open incident %', p_id using errcode = 'P0002';
  end if;
  perform one.acknowledge_incident(p_id, v_actor);
  perform one.ui_audit_write(v_actor, 'incident.acknowledge', 'incident:' || p_id, null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.ui_resolve(p_id bigint, p_resolution text, p_note text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_note text := one.ui_reason(p_note);
begin
  if p_resolution not in ('fixed', 'false_positive', 'accepted', 'manual') then
    raise exception 'resolution must be fixed, false_positive, accepted or manual' using errcode = '22023';
  end if;
  if not exists (select 1 from one.incidents where id = p_id and resolved_at is null) then
    raise exception 'no open incident %', p_id using errcode = 'P0002';
  end if;
  perform one.resolve_incident(p_id, v_actor, p_resolution, v_note);
  perform one.ui_audit_write(v_actor, 'incident.resolve', 'incident:' || p_id, null,
                             jsonb_build_object('resolution', p_resolution, 'note', v_note), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor);
begin
  update one.audit set request_id = left(p_request_id, 80) where id = (select max(id) from one.audit where action = 'mute' and actor = v_actor);
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

create or replace function one.ui_unmute(p_id bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
begin
  perform one.unmute(p_id, v_actor);
  return jsonb_build_object('ok', true);
end $$;

-- "Re-run on deep model" (spec §12): a fresh triage task on the deep tier.
create or replace function one.ui_rerun_deep(p_id bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_inc one.incidents;
  v_task bigint;
begin
  select * into v_inc from one.incidents where id = p_id;
  if not found then
    raise exception 'no incident %', p_id using errcode = 'P0002';
  end if;
  v_task := one.enqueue_ai('triage', jsonb_build_object('incident_id', v_inc.id, 'check_id', v_inc.check_id, 'subjects', to_jsonb(v_inc.subjects),
                                                        'requested_by', v_actor),
                           'deep', format('triage:deep:%s:%s', v_inc.id, extract(epoch from date_trunc('minute', now()))::bigint), v_inc.id);
  perform one.ui_audit_write(v_actor, 'incident.rerun_deep', 'incident:' || p_id, null, jsonb_build_object('task_id', v_task), p_request_id);
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;

-- Proposals ---------------------------------------------------------------------------------------------------------

create or replace function one.ui_proposal_create(p_kind text, p_app text, p_title text, p_rationale text, p_change jsonb, p_risk text,
                                                  p_incident_id bigint default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  if length(trim(coalesce(p_title, ''))) < 5 or length(trim(coalesce(p_rationale, ''))) < 10 then
    raise exception 'a proposal needs a title and a rationale' using errcode = '22023';
  end if;
  insert into one.proposals (kind, app, title, rationale, change, risk, source, incident_id, expires_at)
  values (p_kind, p_app, left(trim(p_title), 200), left(trim(p_rationale), 4000), coalesce(p_change, '{}'), p_risk, 'person', p_incident_id,
          now() + make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14)))
  returning id into v_id;
  perform one.ui_audit_write(v_actor, 'proposal.create', 'proposal:' || v_id, null,
                             jsonb_build_object('kind', p_kind, 'app', p_app, 'title', p_title, 'risk', p_risk), p_request_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Approve (the owner, when the proposal touches money, allocation, live switches, partner mappings, prompts or
-- versioned settings, or when a fix or config proposal does not say what it touches), reject with a note, or snooze.
-- Approving with edited arguments keeps both versions in the audit. Approval records the decision; running an approved
-- change through the owning app's own function arrives with the fixes (phase 7).
create or replace function one.ui_proposal_decide(p_id bigint, p_decision text, p_note text default null, p_change jsonb default null,
                                                  p_snooze_days integer default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_p one.proposals;
  v_change jsonb;
begin
  select * into v_p from one.proposals where id = p_id for update;
  if not found or v_p.status not in ('open', 'snoozed') then
    raise exception 'proposal % is not open', p_id using errcode = 'P0002';
  end if;
  case p_decision
    when 'approve' then
      v_change := coalesce(p_change, v_p.change);
      if one.proposal_sensitive(v_p.kind, v_p.change) or one.proposal_sensitive(v_p.kind, v_change) then
        perform one.ui_require('owner');
      end if;
      update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000),
                               change = v_change, check_due_at = now() + interval '1 day'
       where id = p_id;
    when 'reject' then
      update one.proposals set status = 'rejected', decided_by = v_actor, decided_at = now(), decision_note = one.ui_reason(p_note) where id = p_id;
    when 'snooze' then
      if coalesce(p_snooze_days, 0) not between 1 and 30 then
        raise exception 'snooze for 1 to 30 days' using errcode = '22023';
      end if;
      update one.proposals set status = 'snoozed', decision_note = left(p_note, 1000), expires_at = now() + make_interval(days => p_snooze_days)
       where id = p_id;
    else
      raise exception 'decision must be approve, reject or snooze' using errcode = '22023';
  end case;
  perform one.ui_audit_write(v_actor, 'proposal.' || p_decision, 'proposal:' || p_id,
                             jsonb_build_object('status', v_p.status, 'change', v_p.change),
                             jsonb_build_object('note', p_note, 'change', v_change, 'snooze_days', p_snooze_days), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Settings, checks and tests ------------------------------------------------------------------------------------------

-- A versioned settings change with a reason (spec §12). Owner-only keys need the owner; in alerts, so do recipients.
create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_version integer;
begin
  select value into v_before from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  v_version := one.settings_put(p_key, p_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, p_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

-- A check's operational fields (switch, severity, cadence, threshold, open/resolve counts), versioned. A check that
-- cannot observe its signal (blocked:*) cannot be switched on here.
create or replace function one.ui_check_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_c one.checks;
  v_enabled boolean;
begin
  select * into v_c from one.checks where id = p_id for update;
  if not found then
    raise exception 'no check %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_c.enabled);
  if v_enabled and not v_c.enabled and v_c.disabled_reason like 'blocked:%' then
    raise exception 'check % cannot run: %', p_id, v_c.disabled_reason using errcode = '22023';
  end if;
  update one.checks set
    enabled = v_enabled,
    disabled_reason = case when v_enabled then null
                           when v_c.enabled then 'owner:' || trim(both '-' from regexp_replace(lower(left(v_reason, 40)), '[^a-z0-9_.:-]+', '-', 'g'))
                           else disabled_reason end,
    severity = coalesce((p_patch ->> 'severity')::one.severity, severity),
    cadence_s = coalesce((p_patch ->> 'cadence_s')::int, cadence_s),
    threshold = case when jsonb_typeof(p_patch -> 'threshold') = 'object' then p_patch -> 'threshold' else threshold end,
    open_after = coalesce((p_patch ->> 'open_after')::int, open_after),
    resolve_after = coalesce((p_patch ->> 'resolve_after')::int, resolve_after),
    updated_by = v_actor, updated_at = now(), version = version + 1
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'check.update', 'check:' || p_id,
    jsonb_build_object('enabled', v_c.enabled, 'severity', v_c.severity, 'cadence_s', v_c.cadence_s, 'threshold', v_c.threshold,
                       'open_after', v_c.open_after, 'resolve_after', v_c.resolve_after),
    p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function one.ui_test_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_t one.tests;
  v_enabled boolean;
  v_item text;
begin
  select * into v_t from one.tests where id = p_id for update;
  if not found then
    raise exception 'no test %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_t.enabled);
  v_item := substring(v_t.disabled_reason from '^setup:(.*)$');
  if v_enabled and not v_t.enabled and v_item is not null
     and not coalesce((one.setting('setup') #>> array['items', v_item, 'validated'])::boolean, false) then
    raise exception 'test % waits for Setup item %', p_id, v_item using errcode = '22023';
  end if;
  if p_patch ? 'schedule' and p_patch ->> 'schedule' !~ '^(\S+\s+){4}\S+$' then
    raise exception 'a schedule is a 5-field cron expression' using errcode = '22023';
  end if;
  update one.tests set enabled = v_enabled,
         disabled_reason = case when v_enabled then null when v_t.enabled then 'owner:' || left(v_reason, 60) else disabled_reason end,
         schedule = coalesce(p_patch ->> 'schedule', schedule), updated_by = v_actor
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'test.update', 'test:' || p_id, jsonb_build_object('enabled', v_t.enabled, 'schedule', v_t.schedule),
                             p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- "Run now": the test runner (phase 5) takes the request on its next tick.
create or replace function one.ui_test_run(p_id text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
begin
  update one.tests set run_requested_at = now(), run_requested_by = v_actor where id = p_id and enabled;
  if not found then
    raise exception 'test % is not enabled', p_id using errcode = '22023';
  end if;
  perform one.ui_audit_write(v_actor, 'test.run_now', 'test:' || p_id, null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Privileges and baselines ----------------------------------------------------------------------------------------------

create or replace function one.ui_privilege_ack(p_fn text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
begin
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = p_fn and not acknowledged;
  perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(p_fn, 180), null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Accept the current state as the new baseline of an integrity check (PLAT-06 views, PLAT-08 lead_intake, INT-06).
create or replace function one.ui_baseline_accept(p_key text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_before jsonb;
begin
  if p_key not in ('lead_intake_md5', 'student_leads_columns', 'security_definer_views') then
    raise exception 'no baseline %', p_key using errcode = '22023';
  end if;
  delete from one.baselines where key = p_key returning value into v_before;
  perform one.capture_baselines();
  update one.baselines set acknowledged_by = v_actor where key = p_key;
  perform one.ui_audit_write(v_actor, 'baseline.accept', 'baseline:' || p_key, v_before,
                             (select value from one.baselines where key = p_key), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Users (owner only) -------------------------------------------------------------------------------------------------

-- Adds or changes an Eduwit One user. The Supabase user must already exist: creating one fires the CRM's new-user
-- trigger (website runbook S-21), so it is agreed with the CRM owner first. At least one active owner always remains,
-- and the caller cannot take away their own owner access.
create or replace function one.ui_user_put(p_email text, p_role text, p_active boolean, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_email text := lower(trim(p_email));
  v_uid uuid;
  v_before jsonb;
begin
  if v_email !~ ('^[^@\s]+@' || replace(coalesce(one.setting('access') ->> 'allowed_domain', 'eduwit.in'), '.', '\.') || '$') then
    raise exception 'only @% addresses', coalesce(one.setting('access') ->> 'allowed_domain', 'eduwit.in') using errcode = '22023';
  end if;
  if p_role not in ('owner', 'engineer') then
    raise exception 'role must be owner or engineer' using errcode = '22023';
  end if;
  select id into v_uid from auth.users where lower(email) = v_email;
  if v_uid is null then
    raise exception 'no Supabase user has this address yet: ask the CRM owner to create it first (S-21)' using errcode = 'P0002';
  end if;
  if v_uid = one.uid() and (p_role <> 'owner' or not p_active) then
    raise exception 'you cannot remove your own owner access' using errcode = '22023';
  end if;
  select to_jsonb(o) into v_before from one.users o where o.user_id = v_uid;
  insert into one.users (user_id, email, role, is_active) values (v_uid, v_email, p_role, p_active)
  on conflict (user_id) do update set email = excluded.email, role = excluded.role, is_active = excluded.is_active;
  if not exists (select 1 from one.users where role = 'owner' and is_active) then
    raise exception 'at least one active owner must remain' using errcode = '22023';
  end if;
  if not p_active then
    update one.trusted_devices set revoked_at = now() where user_id = v_uid and revoked_at is null;
    delete from one.session_checks where user_id = v_uid;
  end if;
  perform one.ui_audit_write(v_actor, 'user.put', 'user:' || v_email, v_before,
                             jsonb_build_object('role', p_role, 'is_active', p_active), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Forget a person's trusted browsers: their own, or anyone's for the owner.
create or replace function one.ui_devices_revoke(p_user uuid, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require(case when p_user = one.uid() then 'read' else 'owner' end);
  v_n integer;
begin
  update one.trusted_devices set revoked_at = now() where user_id = p_user and revoked_at is null;
  get diagnostics v_n = row_count;
  perform one.ui_audit_write(v_actor, 'devices.revoke', 'user:' || p_user, null, jsonb_build_object('revoked', v_n), p_request_id);
  return jsonb_build_object('ok', true, 'revoked', v_n);
end $$;

-- Setup (spec §15) -----------------------------------------------------------------------------------------------------

-- The result of a validate button, recorded on the item. A pass switches on the checks waiting for it (their
-- disabled_reason is setup:<item>), as the specification says filling and validating does.
create or replace function one.ui_setup_validated(p_item text, p_ok boolean, p_detail text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_setup jsonb := coalesce(one.setting('setup'), '{"items": {}}');
  v_on integer := 0;
begin
  if not exists (select 1 from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) i where i ->> 'id' = p_item) then
    raise exception 'no Setup item %', p_item using errcode = 'P0002';
  end if;
  v_setup := jsonb_set(v_setup, array['items', p_item], coalesce(v_setup -> 'items' -> p_item, '{}') || jsonb_build_object(
    'status', case when p_ok then 'verified' else 'refused' end, 'validated', p_ok, 'validated_at', now(),
    'ran', 'Setup page: validate, by ' || v_actor, 'detail', left(p_detail, 500), 'source', 'app'), true);
  perform one.settings_put('setup', v_setup, v_actor, 'validate ' || p_item);
  if p_ok then
    update one.checks set enabled = true, disabled_reason = null, updated_by = v_actor, updated_at = now(), version = version + 1
     where disabled_reason = 'setup:' || p_item;
    get diagnostics v_on = row_count;
  end if;
  perform one.ui_audit_write(v_actor, 'setup.validate', 'setup:' || p_item, null,
                             jsonb_build_object('ok', p_ok, 'detail', left(p_detail, 500), 'checks_on', v_on), p_request_id);
  return jsonb_build_object('ok', true, 'checks_on', v_on);
end $$;

-- A secret entered on the Setup page goes to Vault under its one_* name, and only names the Setup checklist lists. The
-- value is never returned, logged or audited.
create or replace function one.ui_secret_put(p_name text, p_value text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_id uuid;
begin
  if p_name !~ '^one_[a-z0-9_]+$' or p_name = 'one_internal_key'
     or not exists (select 1 from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) i
                     where i ->> 'stores' ~ ('(^|[^a-z0-9_])vault:' || p_name || '([^a-z0-9_]|$)')) then
    raise exception 'secret % is not one the Setup checklist names', p_name using errcode = '22023';
  end if;
  if length(coalesce(p_value, '')) not between 8 and 8192 or p_value ~ '\s' then
    raise exception 'the value looks wrong: 8 to 8192 characters, no spaces' using errcode = '22023';
  end if;
  select id into v_id from vault.secrets where name = p_name;
  if v_id is null then
    perform vault.create_secret(p_value, p_name, 'Eduwit One: set from the Setup page');
  else
    perform vault.update_secret(v_id, p_value);
  end if;
  perform one.ui_audit_write(v_actor, 'secret.put', 'vault:' || p_name, null, jsonb_build_object('replaced', v_id is not null), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- The app's credentials (service role), so a secret saved on the Setup page takes effect without a deploy (spec
-- standard 3). Only the one_* names the checklist lists; never the internal key, which the app holds from deploy.
create or replace function one.app_secrets() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(s.name, s.decrypted_secret), '{}')
    from vault.decrypted_secrets s
   where s.name ~ '^one_[a-z0-9_]+$' and s.name <> 'one_internal_key'
     and exists (select 1 from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) i
                  where i ->> 'stores' ~ ('(^|[^a-z0-9_])vault:' || s.name || '([^a-z0-9_]|$)'))
$$;

-- Ask, the brief, saved views ------------------------------------------------------------------------------------------

create or replace function one.ui_ask(p_question text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task bigint;
begin
  if length(trim(coalesce(p_question, ''))) not between 3 and 2000 then
    raise exception 'ask a question of 3 to 2000 characters' using errcode = '22023';
  end if;
  v_task := one.enqueue_ai('ask', jsonb_build_object('question', trim(p_question), 'asked_by', v_actor), null, 'ask:' || gen_random_uuid(), null);
  perform one.ui_audit_write(v_actor, 'ask', 'ai_task:' || v_task, null, null, p_request_id);
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;

-- Pins an answer to the next brief: today's if the nightly run (02:30 IST) has not built it yet, else tomorrow's.
create or replace function one.ui_ask_pin(p_task_id bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_local timestamp := now() at time zone 'Asia/Kolkata';
  v_date date := v_local::date + case when v_local::time >= time '02:30' then 1 else 0 end;
begin
  if not exists (select 1 from one.ai_tasks where id = p_task_id and kind = 'ask' and status = 'done') then
    raise exception 'only an answered question can be pinned' using errcode = '22023';
  end if;
  insert into one.brief_pins (task_id, for_date, pinned_by) values (p_task_id, v_date, v_actor) on conflict do nothing;
  perform one.ui_audit_write(v_actor, 'ask.pin', 'ai_task:' || p_task_id, null, jsonb_build_object('for_date', v_date), p_request_id);
  return jsonb_build_object('ok', true, 'for_date', v_date);
end $$;

create or replace function one.ui_brief_regenerate(p_for_date date, p_tier text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task bigint;
begin
  if p_tier not in ('quick', 'regular', 'deep') then
    raise exception 'tier must be quick, regular or deep' using errcode = '22023';
  end if;
  v_task := one.enqueue_ai('brief', jsonb_build_object('for_date', p_for_date, 'tier', p_tier, 'requested_by', v_actor), p_tier,
                           format('brief:%s:%s:%s', p_for_date, p_tier, extract(epoch from date_trunc('minute', now()))::bigint), null);
  perform one.ui_audit_write(v_actor, 'brief.regenerate', 'brief:' || p_for_date, null, jsonb_build_object('tier', p_tier, 'task_id', v_task), p_request_id);
  return jsonb_build_object('ok', true, 'task_id', v_task);
end $$;

create or replace function one.ui_view_save(p_page text, p_name text, p_params jsonb, p_schedule text default null,
                                            p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  insert into one.saved_views (page, name, params, schedule, created_by) values (p_page, trim(p_name), coalesce(p_params, '{}'), p_schedule, v_actor)
  on conflict (page, name) do update set params = excluded.params, schedule = excluded.schedule
  returning id into v_id;
  perform one.ui_audit_write(v_actor, 'view.save', 'view:' || v_id, null, jsonb_build_object('page', p_page, 'name', p_name, 'schedule', p_schedule), p_request_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

insert into one.api_grants (fn, role, why)
select f, 'authenticated', 'page write (0011)' from unnest(array[
  'one.ui_ack(bigint,text)', 'one.ui_resolve(bigint,text,text,text)', 'one.ui_mute(text,text,integer,text,text)', 'one.ui_unmute(bigint,text)',
  'one.ui_rerun_deep(bigint,text)', 'one.ui_proposal_create(text,text,text,text,jsonb,text,bigint,text)',
  'one.ui_proposal_decide(bigint,text,text,jsonb,integer,text)', 'one.ui_settings_put(text,jsonb,text,text)',
  'one.ui_check_update(text,jsonb,text,text)', 'one.ui_test_update(text,jsonb,text,text)', 'one.ui_test_run(text,text)',
  'one.ui_privilege_ack(text,text)', 'one.ui_baseline_accept(text,text)', 'one.ui_user_put(text,text,boolean,text)',
  'one.ui_devices_revoke(uuid,text)', 'one.ui_setup_validated(text,boolean,text,text)', 'one.ui_secret_put(text,text,text)',
  'one.ui_ask(text,text)', 'one.ui_ask_pin(bigint,text)', 'one.ui_brief_regenerate(date,text,text)',
  'one.ui_view_save(text,text,jsonb,text,text)']) f
on conflict do nothing;
insert into one.api_grants (fn, role, why) values ('one.app_secrets()', 'service_role', 'credentials saved on the Setup page, without a deploy')
on conflict do nothing;
call one.apply_grants();
