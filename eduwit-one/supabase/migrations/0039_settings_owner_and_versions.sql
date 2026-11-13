-- 0039 the audit of 13 Nov 2026 (D-137): who may loosen a check's limits, and saving a setting someone else changed.
-- Only schema one changes.
--   1. The thresholds are the owner's. Sixteen P1 checks read one.settings.thresholds (B2B-02/03/04/05/07,
--      B2C-01/02/04, HB-one:tick, ONE-02, PLAT-01/01W/02/10, WEB-03, WITTY-03), so an engineer who raised a limit could
--      silence a P1 without the owner, while switching off or downgrading the same P1 is the owner's (D-065 (3), the
--      review rule M2 kept). one.setting_owner_only now leaves only checks, tests, witty and analytics to engineers;
--      ui_settings_put asks for the owner on every other key, and ui_settings_restore saves through it, so a restore
--      is the owner's too; the Settings page marks the key owner-only (ui_settings reads the same function). Reading is
--      unchanged: engineers still see the values and their versions.
--   2. A lost update: ui_settings_put locked the row but saved whatever value the page sent, so two people editing the
--      same key from the same version kept only the second save, silently. It takes p_expected_version (the version
--      the page loaded): when given and the stored version differs, nothing is saved and the call is refused with
--      SQLSTATE 40001, which the app shows as "Someone else changed this setting — reload and try again". Left out
--      (null), it saves as before (the chat's put_setting card, a restore).
--   3. Acknowledging a schema's functions in one step compared only how many there were: a list where one function
--      was swapped for another of the same count passed. one.ui_privilege_ack_schema also takes p_hash, the md5 of the
--      functions the page showed, sorted bytewise and joined with commas, and refuses when it differs from the list
--      now. The three-argument form is dropped (as 0031 did for a confirmation), so no call can skip the comparison.
-- Rollback: 0039_settings_owner_and_versions.rollback.sql.

-- 1. The thresholds become the owner's -----------------------------------------------------------------------------------
-- Keys only the owner may change: everything but how the check runner, the tests, Witty's expectations and the analytics
-- funnel run (0010; thresholds moved to the owner by 0039, D-137): a threshold decides whether a P1 can fire at all.
create or replace function one.setting_owner_only(p_key text) returns boolean
language sql immutable set search_path = '' as $$
  select p_key not in ('checks', 'tests', 'witty', 'analytics')
$$;

-- 2. Saving a setting compares the version the page loaded ---------------------------------------------------------------
drop function if exists one.ui_settings_put(text, jsonb, text, text);
create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null,
                                               p_expected_version integer default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_current integer;
  v_version integer;
  v_value jsonb := p_value;
begin
  select value, version into v_before, v_current from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  -- The row is locked, so the comparison holds until this transaction ends (D-137).
  if p_expected_version is not null and p_expected_version is distinct from v_current then
    raise exception 'setting % changed since the page loaded it (version % now, % on the page); reload and try again',
      p_key, v_current, p_expected_version using errcode = '40001';
  end if;
  -- The observation window's start is the first tick's to write, never a page's (security review m1): the stored
  -- value is kept whatever the form sends, so the window cannot be backdated before it starts.
  if p_key = 'fixes' then
    v_value := v_value || jsonb_build_object('observation_started_at', v_before -> 'observation_started_at');
  end if;
  if v_value = v_before then
    raise exception 'nothing changed: the value is the current version' using errcode = '22023';
  end if;
  v_version := one.settings_put(p_key, v_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, v_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

delete from one.api_grants where fn = 'one.ui_settings_put(text,jsonb,text,text)';
insert into one.api_grants (fn, role, why)
values ('one.ui_settings_put(text,jsonb,text,text,integer)', 'authenticated',
        'page write (0039): a setting saved as a new version, refused when the version the page loaded is no longer current')
on conflict do nothing;

-- 3. A schema's functions are acknowledged only as the list the page showed ----------------------------------------------
drop function if exists one.ui_privilege_ack_schema(text, integer, text);
create or replace function one.ui_privilege_ack_schema(p_schema text, p_expected integer, p_hash text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_fns text[];
  f text;
begin
  -- Sorted bytewise (collation C), as the page sorts them before hashing.
  select coalesce(array_agg(b.fn order by b.fn collate "C"), '{}') into v_fns
    from one.privilege_baseline b where b.schema = p_schema and not b.acknowledged;
  if cardinality(v_fns) = 0 then
    raise exception 'nothing to acknowledge in schema %', left(coalesce(p_schema, ''), 60) using errcode = '22023';
  end if;
  if cardinality(v_fns) is distinct from p_expected then
    raise exception 'the list changed: % function(s) to acknowledge in %, not %; reload the page and read it again',
      cardinality(v_fns), left(p_schema, 60), coalesce(p_expected::text, 'none') using errcode = '22023';
  end if;
  if p_hash is null or md5(array_to_string(v_fns, ',')) is distinct from lower(p_hash) then
    raise exception 'the list changed: the functions to acknowledge in % are not the ones the page showed; reload the page and read it again',
      left(p_schema, 60) using errcode = '22023';
  end if;
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = any (v_fns) and not acknowledged;
  foreach f in array v_fns loop
    perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(f, 180), null, null, p_request_id);
  end loop;
  return jsonb_build_object('ok', true, 'acknowledged', cardinality(v_fns));
end $$;

delete from one.api_grants where fn = 'one.ui_privilege_ack_schema(text,integer,text)';
insert into one.api_grants (fn, role, why)
values ('one.ui_privilege_ack_schema(text,integer,text,text)', 'authenticated',
        'page write (0039): the owner acknowledges a schema''s new functions, exactly the list the page showed')
on conflict do nothing;

call one.apply_grants();
