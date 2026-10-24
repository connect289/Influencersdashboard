-- 0016 the seams the synthetic tests read and act through (spec §10). A journey never touches an app table itself:
-- each fact it waits for and each action it takes here is one named kind, run with Eduwit One's rights after two
-- checks that hold for every kind: the run is in flight, and its test may use the kind (D-069). Facts about a lead
-- answer only for a test lead on one of the run's own phones, and return no contact field. Actions write into an app
-- only through the app's own test function (Witty's reset); everything else a journey does in an app goes through the
-- app's API or the test runner login (D-070). The purge is the last section. Service role only. App tables are read
-- from PL/pgSQL bodies, so a missing app table fails the step that needs it, not this migration (staging lacks some).

-- Which test may use which kind. A kind not listed for a test is refused, so one test can never act through another's
-- seam.
create or replace function one.test_kinds(p_test text) returns text[]
language sql immutable set search_path = '' as $$
  select case p_test
    when 'T-ALERT' then array['alert.open', 'alert.delivery', 'alert.close']
    when 'T-WITTY-QUALIFY' then array['witty.harness_run', 'witty.qualified']
    when 'T-WITTY-TURN' then array['witty.trusted', 'witty.turn']
    when 'T-B2B-INTAKE' then array['phone.allocate', 'lead', 'b2b.routing', 'b2b.real_leads_today']
    when 'T-B2B-PUSH' then array['phone.allocate', 'lead', 'b2b.routing', 'b2b.sandbox_partners', 'b2b.push', 'b2b.activity']
    when 'T-HANDOFF' then array['phone.allocate', 'lead', 'b2b.routing', 'b2b.delivered', 'b2c.record', 'b2c.writeback', 'b2c.real_handoffs']
    when 'T-B2C-NURTURE' then array['phone.allocate', 'lead', 'b2b.routing', 'b2b.delivered', 'b2c.record', 'b2c.journey']
    else '{}'::text[]
  end
$$;

-- The run's test, when the run is in flight and the test may use the kind; otherwise a refusal.
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

-- A harness phone: 910000 and six digits, a test phone in every app (w2_is_test, b2b.is_test_phone, Spark's prefixes).
create or replace function one.is_harness_phone(p text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(p, '') ~ '^910000[0-9]{6}$'
$$;

-- The phones the database handed to a run (artefacts.phones, written only by phone.allocate; 0014 keeps the runner
-- from changing it).
create or replace function one.test_run_phones(p_run bigint) returns text[]
language sql stable set search_path = '' as $$
  select coalesce((select array(select x from jsonb_array_elements_text(coalesce(r.artefacts -> 'phones', '[]')) x where one.is_harness_phone(x))
                     from one.test_runs r where r.id = p_run), '{}')
$$;

-- Witty's own reset of one harness phone: its conversation, messages, events and outbox, and the phone's test leads
-- (a hard delete that cascades to B2B's allocations and decisions). w2_test_reset names its tables without a schema,
-- so it runs with search_path public, as WITTY-01 does (D-042), and only for a harness phone.
create or replace function one.witty_test_reset(p_phone text) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
begin
  if not one.is_harness_phone(p_phone) then
    raise exception 'not a harness phone' using errcode = '22023';
  end if;
  return public.w2_test_reset(p_phone);
end $$;

-- A lead the run may read: a test lead on one of its phones, returned as the fields the facts use. Anything else is
-- refused, so no fact reads a real lead.
create or replace function one.test_run_lead(p_run bigint, p_lead bigint) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v jsonb;
begin
  select jsonb_build_object('id', s.id, 'phone', s.whatsapp_number, 'is_test', s.is_test, 'lead_source', s.lead_source,
                            'lead_status', s.lead_status, 'destination_type', s.destination_type, 'deleted', s.deleted_at is not null,
                            'first_contacted_at', s.first_contacted_at, 'contact_attempts', s.contact_attempts)
    into v from public.student_leads s
   where s.id = p_lead and coalesce(s.is_test, false) and s.whatsapp_number = any (one.test_run_phones(p_run));
  if v is null then
    raise exception 'lead % is not a test lead of run %', p_lead, p_run using errcode = '42501';
  end if;
  return v;
end $$;

-- Facts: what a step waits to see. Read-only.
create or replace function one.test_fact(p_run bigint, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_test text := one.test_run_allows(p_run, p_kind);
  v_ids jsonb := coalesce(one.setting('test_identities'), '{}');
  v_lead bigint := nullif(p_args ->> 'lead_id', '')::bigint;
  v_since timestamptz := coalesce(nullif(p_args ->> 'since', '')::timestamptz, now() - interval '1 hour');
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_phones text[];
  v_phone text;
  l jsonb;
  v jsonb;
begin
  if v_lead is not null then
    l := one.test_run_lead(p_run, v_lead);
  elsif p_kind in ('lead', 'b2b.routing', 'b2b.push', 'b2b.activity', 'b2b.delivered', 'b2c.record', 'b2c.writeback', 'b2c.journey') then
    raise exception 'fact % needs lead_id', p_kind using errcode = '22023';
  end if;
  case p_kind
    -- T-ALERT: the test delivery of this run (only that one: kind test, keyed by the run).
    when 'alert.delivery' then
      select jsonb_build_object('status', d.status, 'provider_id', d.provider_id, 'attempts', d.attempts, 'error', left(d.error, 200), 'sent_at', d.sent_at)
        into v from one.deliveries d where d.idempotency_key = 'test:' || p_run and d.kind = 'test';

    -- T-WITTY-QUALIFY: the harness run Witty recorded under this run's tag.
    when 'witty.harness_run' then
      select jsonb_build_object('found', true, 'summary', w.summary) into v
        from public.w2_test_runs w where w.run_tag = 'one-' || p_run order by w.id desc limit 1;
      v := coalesce(v, jsonb_build_object('found', false));
    -- T-WITTY-QUALIFY: for the harness phones of that run, how many Witty marked HOT, their sent outbox rows and their
    -- leads. The phones come from Witty's own record of the run, never from the caller.
    when 'witty.qualified' then
      select array(select distinct e ->> 'phone' from jsonb_array_elements(case when jsonb_typeof(w.results) = 'array' then w.results else '[]' end) e
                    where one.is_harness_phone(e ->> 'phone'))
        into v_phones from public.w2_test_runs w where w.run_tag = 'one-' || p_run order by w.id desc limit 1;
      v_phones := coalesce(v_phones, '{}');
      v := jsonb_build_object(
        'phones', cardinality(v_phones),
        'hot', (select count(*) from public.w2_conversations c where c.phone = any (v_phones) and c.classification = 'HOT'),
        'outbox_sent', (select count(*) from public.w2_outbox o where o.phone = any (v_phones) and o.status = 'sent' and o.created_at >= v_since),
        'leads', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'is_test', coalesce(s.is_test, false), 'lead_source', s.lead_source) order by s.id), '[]')
                    from public.student_leads s where s.whatsapp_number = any (v_phones) and s.deleted_at is null and s.created_at >= v_since));

    -- T-WITTY-TURN: the test number must be one of Witty's trusted test numbers; then what Witty did with the message.
    when 'witty.trusted' then
      v_phone := nullif(v_ids ->> 'whatsapp_number', '');
      v := jsonb_build_object('trusted_test', coalesce((select t.is_test from public.w2_trusted t where t.phone = v_phone), false));
    when 'witty.turn' then
      v_phone := nullif(v_ids ->> 'whatsapp_number', '');
      if not coalesce((select t.is_test from public.w2_trusted t where t.phone = v_phone), false) then
        raise exception 'the test number is not a trusted test number in Witty' using errcode = '42501';
      end if;
      v := jsonb_build_object(
        'inbox', (select count(*) from public.w2_inbox i where i.phone = v_phone and i.received_at >= v_since),
        'conversation_id', (select c.conversation_id from public.w2_conversations c where c.phone = v_phone),
        'replies', (select coalesce(jsonb_agg(jsonb_build_object(
                                     'reply_source', m.reply_source, 'sent', m.sent, 'latency_ms', m.latency_ms, 'at', m.created_at,
                                     'verify_errors', case when jsonb_typeof(m.verify_errors) = 'array' then jsonb_array_length(m.verify_errors) else 0 end)
                                   order by m.created_at), '[]')
                      from public.w2_messages m where m.phone = v_phone and m.direction = 'out' and m.created_at >= v_since));

    -- The lead itself (each lead-creating test).
    when 'lead' then
      v := l - 'phone';
    -- B2B: its routing decisions and allocations for the lead, with the partner's slug.
    when 'b2b.routing' then
      v := jsonb_build_object(
        'decisions', (select count(*) from b2b.engine_decisions d where d.lead_id = v_lead),
        'allocations', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'status', a.status, 'destination_type', a.destination_type,
                                                                     'b2c_lane', a.b2c_lane, 'partner', p.slug, 'is_test', a.is_test, 'origin', a.origin,
                                                                     'reference', a.reference) order by a.id), '[]')
                          from b2b.allocations a left join b2b.partners p on p.id = a.partner_id where a.lead_id = v_lead));
    -- B2B: the partners a sandbox push could reach (not closed, with a test endpoint). T-B2B-PUSH runs only while the
    -- test partner is the only one.
    when 'b2b.sandbox_partners' then
      v := jsonb_build_object('slugs', (select coalesce(jsonb_agg(p.slug order by p.slug), '[]') from b2b.partners p
                                          where p.test_endpoint is not null and p.status <> 'closed'));
    -- B2B: the last push of an allocation of the lead, and whether it went to the partner's test endpoint.
    when 'b2b.push' then
      select jsonb_build_object('status_code', q.status_code, 'sandbox', q.sandbox, 'outcome', q.outcome,
                                'to_test_endpoint', coalesce(q.url = p.test_endpoint, false))
        into v from b2b.push_requests q join b2b.allocations a on a.id = q.allocation_id left join b2b.partners p on p.id = a.partner_id
       where a.lead_id = v_lead order by q.id desc limit 1;
    -- B2B: the partner's calls on the lead (the contacted event applied) and the lead's first contact.
    when 'b2b.activity' then
      v := jsonb_build_object('calls', (select count(*) from b2b.partner_activities x where x.lead_id = v_lead and x.kind = 'call'),
                              'first_contacted_at', l -> 'first_contacted_at');
    -- B2B: the sync to Spark (the outbox rows for the b2c consumer carrying this lead).
    when 'b2b.delivered' then
      v := jsonb_build_object('statuses', (select coalesce(jsonb_agg(o.status order by o.id), '[]') from b2b.integration_outbox o
                                             where o.target = 'b2c_crm' and o.payload ->> 'lead_id' = v_lead::text));
    -- B2B: real leads created today, counted as B2B's command centre counts them, for the leak check.
    when 'b2b.real_leads_today' then
      v := jsonb_build_object('leads_today', (select count(*) from public.student_leads s
                                                where s.created_at >= v_today and s.deleted_at is null and s.merged_into_id is null
                                                  and not (coalesce(s.is_test, false) or b2b.is_test_phone(s.whatsapp_number))));

    -- Spark: whether it holds the lead, and whether it took it as a test lead.
    when 'b2c.record' then
      select jsonb_build_object('found', true, 'held_by_b2c', r.held_by_b2c, 'is_test', coalesce(r.is_test, false),
                                'state_is_test', (select s.is_test from b2c.leads_state s where s.lead_id = v_lead))
        into v from b2c.lead_records r where r.lead_id = v_lead;
      v := coalesce(v, jsonb_build_object('found', false));
    -- Spark → B2B: the activity in Spark's outbox and B2B's record of the write, since the step began.
    when 'b2c.writeback' then
      v := jsonb_build_object(
        'outbox', (select coalesce(jsonb_agg(o.status order by o.id), '[]') from b2c.outbox o where o.lead_id = v_lead and o.kind = 'activity' and o.created_at >= v_since),
        'writes', (select coalesce(jsonb_agg(jsonb_build_object('status', w.status, 'http_status', w.http_status) order by w.id), '[]')
                     from b2b.b2c_writes w where w.lead_id = v_lead and w.kind = 'activity' and w.created_at >= v_since));
    -- Spark: real hand-offs today in its fact table, as its "handoffs" metric counts them, for the leak check against
    -- its analytics; and whether the run's lead has reached the fact table yet (the check means nothing before).
    when 'b2c.real_handoffs' then
      v := jsonb_build_object('real', (select count(*) from b2c.fact_leads f where not coalesce(f.is_test, false) and not coalesce(f.deleted, false)
                                          and (f.handed_off_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date));
      if v_lead is not null then
        v := v || jsonb_build_object('lead_in_facts', exists (select 1 from b2c.fact_leads f where f.lead_id = v_lead),
                                     'lead_fact_is_test', (select f.is_test from b2c.fact_leads f where f.lead_id = v_lead));
      end if;
    -- Spark: the lead's journey run and the sends it queued, checked against the lead's own phone (no address is
    -- returned).
    when 'b2c.journey' then
      v := jsonb_build_object(
        'run', (select jsonb_build_object('journey_id', j.journey_id, 'step_idx', j.step_idx, 'status', j.status, 'is_test', j.is_test)
                  from b2c.journey_runs j where j.lead_id = v_lead order by j.id desc limit 1),
        'sends', (select count(*) from b2c.send_queue q where q.lead_id = v_lead),
        'sends_to_lead_phone', (select count(*) from b2c.send_queue q where q.lead_id = v_lead and q.channel = 'whatsapp'
                                  and regexp_replace(coalesce(q.to_address, ''), '\D', '', 'g') = l ->> 'phone'),
        'sends_live', (select count(*) from b2c.send_queue q where q.lead_id = v_lead and q.status in ('sending', 'sent')));
    else
      raise exception 'no fact %', p_kind using errcode = '22023';
  end case;
  return coalesce(v, '{}');
end $$;

-- Actions: what a step does inside the database. Each records its result on the run.
create or replace function one.test_act(p_run bigint, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_test text := one.test_run_allows(p_run, p_kind);
  v_ids jsonb := coalesce(one.setting('test_identities'), '{}');
  v jsonb;
  v_incident bigint;
  v_delivery bigint;
  v_to text;
  v_phone text;
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
    -- A fresh harness phone for this run, from Eduwit One's slice of the harness range (test_identities.run_phone_prefix,
    -- 9100009 and five digits from the run id), cleared with Witty's own reset so the run starts from nothing. A phone
    -- still holding a partner-routed test lead (which the purge keeps) is refused rather than reset.
    when 'phone.allocate' then
      v_phone := coalesce(nullif(v_ids ->> 'run_phone_prefix', ''), '9100009');
      if v_phone !~ '^9100009[0-9]{0,4}$' then
        raise exception 'test_identities.run_phone_prefix must start with 9100009 and leave digits for the run' using errcode = '22023';
      end if;
      v_phone := v_phone || lpad((p_run % power(10, 12 - length(v_phone))::bigint)::text, 12 - length(v_phone), '0');
      if exists (select 1 from public.student_leads s join b2b.allocations a on a.lead_id = s.id
                  where s.whatsapp_number = v_phone and a.destination_type = 'partner') then
        raise exception 'harness phone % still holds a partner-routed test lead', v_phone using errcode = '55000';
      end if;
      v := jsonb_build_object('phone', v_phone, 'reset', one.witty_test_reset(v_phone));
      update one.test_runs set artefacts = jsonb_set(artefacts, '{phones}', coalesce(artefacts -> 'phones', '[]') || to_jsonb(v_phone)) where id = p_run;
    else
      raise exception 'no action %', p_kind using errcode = '22023';
  end case;
  update one.test_runs set artefacts = artefacts || jsonb_build_object(p_kind, v) where id = p_run;
  return v;
end $$;

-- The purge (spec §10: after tests.purge_after_days, through each app's own delete path) -------------------------------
-- The runner deletes each lead in Spark and then in B2B as the test runner login, with reason "test"; then
-- test_run_purge resets the run's phones in Witty. Leads that went to a partner are kept: B2B refuses "test" for them,
-- and Witty's reset would remove their allocations behind B2B's back (D-071).

-- Finished runs whose purge is due, oldest first, with each test lead on their phones.
create or replace function one.test_purge_due(p_limit integer default 20) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'run', r.id, 'test', r.test_id, 'finished_at', r.finished_at, 'phones', cardinality(one.test_run_phones(r.id)),
           'leads', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'id', s.id, 'deleted', s.deleted_at is not null,
                                       'with_partner', coalesce(s.destination_type = 'partner', false)
                                                       or exists (select 1 from b2b.allocations a where a.lead_id = s.id and a.destination_type = 'partner'),
                                       'in_spark', exists (select 1 from b2c.leads_state b where b.lead_id = s.id and b.deleted_at is null))
                                     order by s.id), '[]')
                       from public.student_leads s where coalesce(s.is_test, false) and s.whatsapp_number = any (one.test_run_phones(r.id))))
         order by r.finished_at), '[]')
    into v
    from (select * from one.test_runs
           where purged_at is null and finished_at < now() - make_interval(days => coalesce((one.setting('tests') ->> 'purge_after_days')::int, 2))
           order by finished_at limit least(greatest(coalesce(p_limit, 20), 1), 100)) r;
  return v;
end $$;

-- Witty's part, last: its reset on each of the run's phones that holds no partner-routed lead (the reset also hard
-- deletes the phone's test leads). Then the run is marked purged with the runner's report and Witty's.
create or replace function one.test_run_purge(p_run bigint, p_report jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_phone text;
  v_witty jsonb := '{}';
begin
  perform 1 from one.test_runs where id = p_run and finished_at is not null and purged_at is null for update;
  if not found then
    raise exception 'run % is not waiting for its purge', p_run using errcode = '22023';
  end if;
  foreach v_phone in array one.test_run_phones(p_run) loop
    if exists (select 1 from public.student_leads s
                where s.whatsapp_number = v_phone
                  and (s.destination_type = 'partner' or exists (select 1 from b2b.allocations a where a.lead_id = s.id and a.destination_type = 'partner'))) then
      v_witty := v_witty || jsonb_build_object(v_phone, jsonb_build_object('kept', 'partner-routed test lead'));
      continue;
    end if;
    begin
      v_witty := v_witty || jsonb_build_object(v_phone, one.witty_test_reset(v_phone));
    exception when others then
      v_witty := v_witty || jsonb_build_object(v_phone, jsonb_build_object('error', left(sqlerrm, 200)));
    end;
  end loop;
  update one.test_runs set purged_at = now(), purge_report = coalesce(p_report, '{}') || jsonb_build_object('witty', v_witty) where id = p_run;
  return jsonb_build_object('run', p_run, 'witty', v_witty);
end $$;

-- The Setup page's validators for the test items (service role): the test identities, and the Spark journey that
-- test_identities.spark_test_journey_id names, with whether it is in test mode and published.
create or replace function one.setup_test_facts() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ids jsonb := coalesce(one.setting('test_identities'), '{}');
  v jsonb;
begin
  if coalesce(v_ids ->> 'spark_test_journey_id', '') ~ '^[0-9]{1,18}$' then
    select jsonb_build_object('found', true, 'test_mode', coalesce(j.test_mode, false), 'status', j.status,
                              'published', j.current_version is not null,
                              'steps', case when jsonb_typeof(jv.steps) = 'array' then jsonb_array_length(jv.steps) else 0 end)
      into v
      from b2c.journeys j left join b2c.journey_versions jv on jv.journey_id = j.id and jv.version = j.current_version
     where j.id = (v_ids ->> 'spark_test_journey_id')::bigint;
  end if;
  return jsonb_build_object('identities', v_ids, 'spark_journey', coalesce(v, jsonb_build_object('found', false)));
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.setup_test_facts()', 'service_role', 'test runner (0016): what the Setup validators of the test items read'),
  ('one.test_fact(bigint,text,jsonb)', 'service_role', 'test runner (0016): what a step waits to see'),
  ('one.test_act(bigint,text,jsonb)', 'service_role', 'test runner (0016): what a step does, on test identities only'),
  ('one.test_purge_due(integer)', 'service_role', 'test runner (0016): runs whose purge is due, with their test leads'),
  ('one.test_run_purge(bigint,jsonb)', 'service_role', 'test runner (0016): Witty''s reset, then the run marked purged')
on conflict do nothing;
call one.apply_grants();
