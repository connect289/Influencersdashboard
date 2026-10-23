-- 0016 the seams the synthetic tests read and act through (spec §10). The app's journeys never touch an app table: each
-- fact they wait for and each action they take is one named kind here, run with Eduwit One's rights after two checks
-- that hold for every kind: the run is in flight, and its test is one that may use this kind. An action that writes
-- into an app does it through the app's own test function, only on a test identity, and records what it created on
-- the run so the purge can remove it (one.purge_test_rows). Service role only.

-- Which test may use which kind. A kind not listed for a test is refused, so one test can never act through another's
-- seam.
create or replace function one.test_kinds(p_test text) returns text[]
language sql immutable set search_path = '' as $$
  select case p_test
    when 'T-ALERT' then array['alert.open', 'alert.delivery', 'alert.close']
    else '{}'::text[]
  end
$$;

-- The run's test, when the run is in flight and the test may use the kind; otherwise a refusal (42501).
create or replace function one.test_run_allows(p_run bigint, p_kind text) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_test text;
begin
  select test_id into v_test from one.test_runs where id = p_run and finished_at is null;
  if v_test is null then
    raise exception 'run % is not in flight', p_run using errcode = '22023';
  end if;
  if not (p_kind = any (one.test_kinds(v_test))) then
    raise exception 'test % may not use %', v_test, p_kind using errcode = '42501';
  end if;
  return v_test;
end $$;

-- Facts: what a step waits to see. Read-only.
create or replace function one.test_fact(p_run bigint, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_test text := one.test_run_allows(p_run, p_kind);
  v jsonb;
begin
  case p_kind
    -- T-ALERT: the test delivery of this run (only that one: kind test, keyed by the run).
    when 'alert.delivery' then
      select jsonb_build_object('status', d.status, 'provider_id', d.provider_id, 'attempts', d.attempts, 'error', left(d.error, 200),
                                'sent_at', d.sent_at)
        into v from one.deliveries d where d.idempotency_key = 'test:' || p_run and d.kind = 'test';
    else
      raise exception 'no fact %', p_kind using errcode = '22023';
  end case;
  return coalesce(v, '{}');
end $$;

-- Actions: what a step does. Each records its artefacts on the run.
create or replace function one.test_act(p_run bigint, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_test text := one.test_run_allows(p_run, p_kind);
  v_ids jsonb := coalesce(one.setting('test_identities'), '{}');
  v jsonb;
  v_incident bigint;
  v_delivery bigint;
  v_to text;
begin
  case p_kind
    -- T-ALERT: a synthetic P2 incident and a delivery to the test recipient: the test mailbox, or Resend's test address
    -- (delivered@resend.dev accepts and reports "delivered") while none is set (D-069). Never to a real inbox.
    when 'alert.open' then
      v_to := coalesce(nullif(lower(v_ids ->> 'mailbox'), ''), 'delivered@resend.dev');
      v_incident := one.open_or_touch_incident('ONE-SYNTH', 'P2', jsonb_build_object('value', jsonb_build_object('synthetic', true, 'run', p_run, 'test', v_test)));
      update one.incidents set tags = array(select distinct unnest(tags || array['synthetic'])) where id = v_incident;
      insert into one.deliveries (incident_id, channel, recipient, kind, idempotency_key)
      values (v_incident, 'email', v_to, 'test', 'test:' || p_run)
      on conflict (idempotency_key) do nothing
      returning id into v_delivery;
      v := jsonb_build_object('incident_id', v_incident, 'delivery_id', v_delivery,
                              'recipient', case when v_to = 'delivered@resend.dev' then 'resend_test_address' else 'test_mailbox' end);
    -- T-ALERT: acknowledge and resolve the synthetic incident of this run, as the test.
    when 'alert.close' then
      update one.incidents
         set acknowledged_at = coalesce(acknowledged_at, now()), acknowledged_by = coalesce(acknowledged_by, 'test:' || v_test),
             resolved_at = now(), resolved_by = 'test:' || v_test, resolution = 'accepted',
             resolution_note = 'synthetic incident of ' || v_test || ' run ' || p_run
       where id = (p_args ->> 'incident_id')::bigint and check_id = 'ONE-SYNTH' and resolved_at is null;
      v := jsonb_build_object('closed', found);
    else
      raise exception 'no action %', p_kind using errcode = '22023';
  end case;
  update one.test_runs set artefacts = artefacts || jsonb_build_object(p_kind, v) where id = p_run;
  return v;
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.test_fact(bigint,text,jsonb)', 'service_role', 'test runner (0016): what a step waits to see'),
  ('one.test_act(bigint,text,jsonb)', 'service_role', 'test runner (0016): what a step does, on test identities only')
on conflict do nothing;
call one.apply_grants();
