-- Phase 4 (Telephony and depth) checks, rolled back. Every row of the final select must say ok = true.
-- LOCAL COPY ONLY, like test_phase3: the ROAS check books university commission, which needs catalogue fixtures.
-- Test phones 9190000000NN only; no provider is ever called (the database only sees the events the adapter would send).
begin;
do $g$ begin
  if current_database() <> 'b2c_fresh' then raise exception 'test_phase4 writes catalogue fixtures: run it on a local copy, never on staging'; end if;
end $g$;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e001', 'admin.p4@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e002', 'priya.p4@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e003', 'rohan.p4@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e005', 'sneha.p4@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, languages, takes_leads, phone) values
  ('aaaaaaaa-0000-0000-0000-00000000e001', 'admin.p4@eduwit.in', 'P4 Admin', 'admin', true, false, '{English}', false, null),
  ('aaaaaaaa-0000-0000-0000-00000000e002', 'priya.p4@eduwit.in', 'Priya P4', 'counsellor', true, true, '{English}', true, null),
  ('aaaaaaaa-0000-0000-0000-00000000e003', 'rohan.p4@eduwit.in', 'Rohan P4', 'counsellor', true, true, '{English}', true, '+91 90000 00099'),
  ('aaaaaaaa-0000-0000-0000-00000000e005', 'sneha.p4@eduwit.in', 'Sneha P4', 'marketing', true, false, '{English}', false, null);
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.p4@eduwit.in' on conflict do nothing;
create function pg_temp.env(p_id text, p_type text, p_lead bigint, p_data jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('id', p_id, 'type', p_type, 'lead_id', p_lead, 'occurred_at', now(), 'test', true, 'contract_version', 3, 'data', p_data)
$f$;
create function pg_temp.lead(p_lead bigint, p_name text, p_owner uuid, p_extra jsonb default '{}') returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(pg_temp.env('p4-rec-' || p_lead, 'b2c.lead_upserted', p_lead, jsonb_build_object('version', 1, 'record',
    jsonb_build_object('id', p_lead, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', p_name, 'phone', '91900000' || right(p_lead::text, 4), 'email', lower(replace(p_name, ' ', '.')) || '@example.in', 'city', 'Pune'),
      'interest', jsonb_build_object('course', 'MBA', 'university', 'Amity University Online'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')) || p_extra)));
  perform b2c.handoff_receive(pg_temp.env('p4-ho-' || p_lead, 'b2c.lead_handed_off', p_lead, '{"b2c_lane":"sales","reason":"fallback"}'));
  perform b2c.assign(p_lead, p_owner, null, 'manual', 'phase 4 test');
end $f$;
create function pg_temp.tel(p jsonb) returns void language sql as $f$
  insert into b2c.settings as s (key, value) values ('telephony', p) on conflict (key) do update set value = s.value || excluded.value
$f$;

do $x$
begin
  perform pg_temp.lead(900061, 'Kiran Test', 'aaaaaaaa-0000-0000-0000-00000000e003');
  perform pg_temp.lead(900062, 'Lata Test', 'aaaaaaaa-0000-0000-0000-00000000e003');
  perform pg_temp.lead(900063, 'Mohan Test', 'aaaaaaaa-0000-0000-0000-00000000e003');
  perform pg_temp.lead(900064, 'Nisha Test', 'aaaaaaaa-0000-0000-0000-00000000e002');
end $x$;

-- ---------- telephony ----------
do $x$
declare j jsonb; v_call bigint; e text; n int; s b2c.leads_state;
begin
  -- provider none (today): the Call button is the old tel: flow with the log sheet
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  j := b2c.call_start(900061, null);
  insert into r (name, ok, detail) values ('none_is_manual', j ->> 'mode' = 'manual' and j ->> 'tel' like 'tel:+91%'
    and (select provider from b2c.calls where id = (j ->> 'call_id')::bigint) = 'manual', j::text);
  perform pg_temp.as_system();

  -- Exotel switched on: a test lead still never reaches it
  perform pg_temp.tel('{"provider": "exotel", "caller_id": "+911140000000"}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e002');
  begin perform b2c.call_start(900064, null); e := 'started'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('needs_counsellor_phone', e like 'add your mobile number%', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  j := b2c.call_start(900062, null);
  v_call := (j ->> 'call_id')::bigint;
  insert into r (name, ok, detail) values ('test_lead_goes_to_mock', j ->> 'mode' = 'bridge' and j ->> 'provider' = 'mock' and j ->> 'agent' = '+919000000099'
    and j ->> 'student' = '+919000000062' and j ->> 'number' is not null, j::text);
  begin perform b2c.call_log(v_call, 'connected', 60, 'x', now() + interval '1 day'); e := 'logged'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('no_manual_log_while_bridging', e like 'this call is still going on%', e);
  perform pg_temp.as_system();

  -- the provider's events log the call by themselves
  perform b2c.call_event(jsonb_build_object('provider', 'mock', 'call_id', v_call, 'provider_ref', 'MOCK-1', 'status', 'ringing'));
  perform b2c.call_event(jsonb_build_object('provider', 'mock', 'provider_ref', 'MOCK-1', 'status', 'answered'));
  j := b2c.call_event(jsonb_build_object('provider', 'mock', 'provider_ref', 'MOCK-1', 'status', 'completed', 'duration_s', 250, 'recording_url', 'https://mock.local/rec/MOCK-1.mp3'));
  select * into s from b2c.leads_state where lead_id = 900062;
  insert into r (name, ok, detail) values ('bridged_call_logs_itself',
    (select logged_at is not null and outcome = 'connected' and duration_s = 250 and auto_logged and bridged_at is not null and recording_status = 'pending' from b2c.calls where id = v_call)
    and s.contact_attempts = 1 and s.first_contacted_at is not null and s.stage_id = 3, j::text || ' stage ' || s.stage_id);
  insert into r (name, ok, detail) values ('timeline_without_manual_logging',
    exists (select 1 from b2c.activities where lead_id = 900062 and kind = 'call' and outcome = 'connected' and duration_s = 250 and (meta ->> 'bridged')::boolean and body like '%4 min 10 s%'),
    (select string_agg(body, ' | ') from b2c.activities where lead_id = 900062 and kind = 'call'));
  insert into r (name, ok, detail) values ('suggested_next_task', exists (select 1 from b2c.tasks where lead_id = 900062 and status = 'open' and suggested and source = 'call_auto'), null);
  j := b2c.call_event(jsonb_build_object('provider', 'mock', 'provider_ref', 'MOCK-1', 'status', 'completed', 'duration_s', 250));
  insert into r (name, ok, detail) values ('repeated_webhook_is_noop', (j ->> 'duplicate')::boolean
    and (select count(*) from b2c.activities where lead_id = 900062 and kind = 'call') = 1, j::text);
  update b2c.calls set tapped_at = now() - interval '1 hour' where id = v_call;
  perform b2c.reminder_tick();
  insert into r (name, ok, detail) values ('bridged_never_flagged_unlogged', (select unlogged_flagged_at is null from b2c.calls where id = v_call), null);

  -- no answer on a New Lead: Could Not Connect
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  v_call := (b2c.call_start(900063, null) ->> 'call_id')::bigint;
  perform pg_temp.as_system();
  perform b2c.call_event(jsonb_build_object('provider', 'mock', 'call_id', v_call, 'provider_ref', 'MOCK-2', 'status', 'no_answer'));
  select * into s from b2c.leads_state where lead_id = 900063;
  insert into r (name, ok, detail) values ('no_answer_moves_to_could_not_connect', s.stage_id = 2 and s.sub_stage = 'No answer'
    and (select outcome from b2c.calls where id = v_call) = 'no_answer', s.stage_id || ' ' || s.sub_stage);

  -- the mock, played by the counsellor on their own mock call only
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e002');
  begin perform b2c.call_mock_event(v_call, 'completed', 10); e := 'played'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('mock_only_for_who_may_see', e in ('not allowed', 'not your lead'), e);
  perform pg_temp.as_system();
  -- the provider refused to start: nothing dialled, nothing counted
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  v_call := (b2c.call_start(900061, null) ->> 'call_id')::bigint;
  perform pg_temp.as_system();
  n := (select contact_attempts from b2c.leads_state where lead_id = 900061);
  perform b2c.call_start_failed(v_call, 'LIVE_MODE is off');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  insert into r (name, ok, detail) values ('refused_start_not_an_attempt', (b2c.call_get(v_call) ->> 'logged')::boolean and (b2c.call_get(v_call) ->> 'status') = 'failed'
    and (select contact_attempts from b2c.leads_state where lead_id = 900061) = n, b2c.call_get(v_call)::text);
  perform pg_temp.as_system();
  -- the counsellor's own phone did not answer: no attempt counted
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  v_call := (b2c.call_start(900061, null) ->> 'call_id')::bigint;
  perform pg_temp.as_system();
  n := (select contact_attempts from b2c.leads_state where lead_id = 900061);
  perform b2c.call_event(jsonb_build_object('provider', 'mock', 'call_id', v_call, 'provider_ref', 'MOCK-3', 'status', 'agent_no_answer'));
  insert into r (name, ok, detail) values ('agent_missed_not_an_attempt', (select contact_attempts from b2c.leads_state where lead_id = 900061) = n
    and (select logged_at is not null and outcome is null from b2c.calls where id = v_call), null);

  -- a missed call from the student: call back
  j := b2c.call_event('{"provider": "mock", "provider_ref": "MOCK-IN-1", "status": "missed", "direction": "in", "from": "+91 90000 00063"}');
  insert into r (name, ok, detail) values ('missed_inbound_callback_task',
    exists (select 1 from b2c.tasks where lead_id = 900063 and status = 'open' and source = 'missed_call' and owner_id = 'aaaaaaaa-0000-0000-0000-00000000e003')
    and exists (select 1 from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000e003' and kind = 'missed_call'), j::text);
  j := b2c.call_event('{"provider": "mock", "provider_ref": "MOCK-IN-2", "status": "completed", "direction": "in", "from": "+91 90000 00063", "agent": "+919000000099", "duration_s": 90}');
  insert into r (name, ok, detail) values ('answered_inbound_logged', (select direction = 'in' and outcome = 'connected' and user_id = 'aaaaaaaa-0000-0000-0000-00000000e003'
                                                                          from b2c.calls where provider_ref = 'MOCK-IN-2'), j::text);
  j := b2c.call_event('{"provider": "mock", "provider_ref": "MOCK-IN-3", "status": "missed", "direction": "in", "from": "+91 98111 22233"}');
  insert into r (name, ok, detail) values ('unknown_number_waits_for_admin', (j ->> 'unknown_number')::boolean and exists (select 1 from b2c.unknown_calls where provider_ref = 'MOCK-IN-3'), j::text);
  begin perform b2c.call_event('{"provider": "mock", "provider_ref": "X", "status": "exploded"}'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('unknown_status_refused', e like 'unknown call status%', e);
end $x$;

-- ---------- recordings ----------
do $x$
declare j jsonb; v_call bigint := (select id from b2c.calls where provider_ref = 'MOCK-1'); e text; p text;
begin
  j := b2c.recordings_take(5);
  insert into r (name, ok, detail) values ('recording_queued', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::bigint = v_call and x ->> 'recording_url' like 'https://mock.local/%'), j::text);
  perform b2c.recording_saved(v_call, 'calls/900062/' || v_call || '.mp3');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  p := b2c.recording_open(v_call);
  insert into r (name, ok, detail) values ('owner_plays_recording_logged', p = 'calls/900062/' || v_call || '.mp3'
    and exists (select 1 from b2c.audit_log where action = 'recording_play' and lead_id = 900062), p);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e002');
  begin perform b2c.recording_open(v_call); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('other_counsellor_cannot_play', e = 'not allowed', e);
  perform pg_temp.as_system();
  update b2c.calls set recording_stored_at = now() - interval '200 days' where id = v_call;
  j := b2c.recordings_expired(50);
  insert into r (name, ok, detail) values ('recording_expires', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::bigint = v_call), j::text);
  perform b2c.recording_removed(v_call);
  insert into r (name, ok, detail) values ('recording_removed', (select recording_status = 'deleted' and recording_path is null and recording_url is null from b2c.calls where id = v_call), null);
  insert into r (name, ok, detail) values ('webhook_functions_service_only',
    not has_function_privilege('authenticated', 'b2c.call_event(jsonb)', 'execute') and not has_function_privilege('authenticated', 'b2c.recording_saved(bigint,text,text)', 'execute')
    and has_function_privilege('authenticated', 'b2c.call_start(bigint,bigint)', 'execute'), null);
  perform pg_temp.tel('{"provider": "none"}');
end $x$;

-- ---------- ad spend and ROAS ----------
update public.catalog_programs set fee_yearly = 90000 where id = 11;
do $x$
declare j jsonb; d0 date := (now() at time zone 'Asia/Kolkata')::date; v_rows jsonb; e text; v_net numeric; v_leads bigint[];
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e001');
  perform b2c.university_rate_save('{"university_id":1,"rate_type":"percent","fee_base":"first_year","value":20,"gst_inclusive":true,"valid_from":"2026-01-01","note":"test"}');
  perform pg_temp.as_system();
  perform pg_temp.lead(900065, 'Om Test', 'aaaaaaaa-0000-0000-0000-00000000e003', '{"source": {"lead_source": "meta_lead_ad", "campaign": "C1"}}');
  perform pg_temp.lead(900066, 'Pia Test', 'aaaaaaaa-0000-0000-0000-00000000e003', '{"source": {"lead_source": "meta_lead_ad", "campaign": "Admissions Oct"}}');
  perform pg_temp.lead(900067, 'Raj Test', 'aaaaaaaa-0000-0000-0000-00000000e002', '{"source": {"lead_source": "meta_lead_ad", "campaign": "c1"}}');
  perform pg_temp.lead(900068, 'Sia Test', 'aaaaaaaa-0000-0000-0000-00000000e002', '{"source": {"lead_source": "google_ads", "campaign": null}}');
  perform pg_temp.lead(900069, 'Tara Test', 'aaaaaaaa-0000-0000-0000-00000000e002', '{"source": {"lead_source": "website", "campaign": "C9"}}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  perform b2c.enrollment_record(jsonb_build_object('lead_id', 900065, 'university', 'Amity University Online', 'programme', 'Online MBA', 'fee', 179000, 'fee_paid', 179000,
                                                   'enrolled_on', d0, 'proof_path', 'leads/900065/receipt.pdf'));
  -- a counsellor cannot import spend
  begin perform b2c.ad_spend_import('{"platform":"meta","rows":[{"day":"2026-10-01","campaign_id":"1","spend":"1"}]}'); e := 'imported'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('counsellor_cannot_import_spend', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e005');
  j := jsonb_build_object('platform', 'meta', 'file_name', 'meta.csv', 'rows', jsonb_build_array(
         jsonb_build_object('day', d0 - 1, 'campaign_id', '120200', 'campaign', 'C1', 'spend', '1000.00', 'clicks', '50', 'impressions', '4000'),
         jsonb_build_object('day', d0, 'campaign_id', '120200', 'campaign', 'C1', 'spend', '500', 'clicks', '20'),
         jsonb_build_object('day', d0, 'campaign_id', '120300', 'campaign', 'Admissions Oct', 'spend', '700')));
  perform b2c.ad_spend_import(j);
  perform b2c.ad_spend_import(j);   -- the same file again
  perform b2c.ad_spend_import(jsonb_build_object('platform', 'google', 'file_name', 'google.csv', 'rows', jsonb_build_array(
         jsonb_build_object('day', d0, 'campaign_id', 'G1', 'campaign', 'Search brand', 'spend', '300'))));
  perform b2c.ad_campaign_map_save('{"platform": "google", "campaign_id": "G1", "lead_source": "google_ads"}');
  insert into r (name, ok, detail) values ('reimport_replaces', (select sum(spend) from b2c.ad_spend_daily) = 2500 and (select count(*) from b2c.ad_spend_daily) = 4,
    (select sum(spend)::text || ' / ' || count(*) from b2c.ad_spend_daily));
  perform pg_temp.as_system();
  perform b2c.facts_build(array[900065, 900066, 900067, 900068, 900069]::bigint[]);
  v_net := (select university_net from b2c.fact_leads where lead_id = 900065);
  insert into r (name, ok, detail) values ('lead_matched_to_campaigns',
    (select string_agg(lead_id || ':' || platform || ':' || campaign_id, ' ' order by lead_id) from b2c.ad_lead_campaign_v where lead_id between 900065 and 900069)
      = '900065:meta:120200 900066:meta:120300 900067:meta:120200 900068:google:G1',
    (select string_agg(lead_id || ':' || platform || ':' || campaign_id, ' ' order by lead_id) from b2c.ad_lead_campaign_v where lead_id between 900065 and 900069));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e005');
  j := b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array('ad_spend', 'ad_leads', 'ad_cpl', 'ad_enrolled', 'ad_cpe', 'ad_roas'), 'from', d0 - 1, 'to', d0, 'test', true));
  v_rows := j -> 'rows' -> 0;
  insert into r (name, ok, detail) values ('roas_matches_manual', (v_rows ->> 'ad_spend')::numeric = 2500 and (v_rows ->> 'ad_leads')::int = 4 and (v_rows ->> 'ad_cpl')::numeric = 625
    and (v_rows ->> 'ad_enrolled')::int = 1 and (v_rows ->> 'ad_cpe')::numeric = 2500 and v_net > 0 and (v_rows ->> 'ad_roas')::numeric = round(v_net / 2500, 2),
    v_rows::text || ' net ' || v_net);
  j := b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array('ad_spend', 'ad_leads'), 'dims', jsonb_build_array('ad_campaign'), 'from', d0 - 1, 'to', d0, 'test', true));
  insert into r (name, ok, detail) values ('by_campaign', exists (select 1 from jsonb_array_elements(j -> 'rows') x where x -> 'k' ->> 0 = 'C1' and (x ->> 'ad_spend')::numeric = 1500 and (x ->> 'ad_leads')::int = 2), (j -> 'rows')::text);
  j := b2c.analytics_drill(jsonb_build_object('metrics', jsonb_build_array('ad_leads'), 'from', d0 - 1, 'to', d0, 'test', true), 'ad_leads', '{}');
  insert into r (name, ok, detail) values ('ad_leads_drill_down', (j ->> 'count')::int = 4, j::text);
  j := b2c.ad_spend_overview(d0 - 1, d0);
  insert into r (name, ok, detail) values ('overview_campaigns', jsonb_array_length(j -> 'campaigns') = 3 and jsonb_array_length(j -> 'imports') = 3, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  begin perform b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array('ad_spend'))); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('sales_cannot_see_ad_spend', e like '%not available to your role%', e);
  perform pg_temp.as_system();
end $x$;

-- ---------- performance-weighted allocation ----------
do $x$
declare sh numeric[]; i int; cnt int[] := array[0, 0, 0, 0]; w numeric[]; best int; v numeric; bv numeric; j jsonb; v_rule bigint; d jsonb;
        floor_ok boolean := true; e text;
begin
  -- A converts 20%, B 5%, C 10%, D is new (5 leads): team 10%
  sh := b2c.perf_shares(array[100, 100, 100, 5], array[20, 5, 10, 0], 0.1, '{"floor": 0.5, "cap": 2, "prior": 20}');
  insert into r (name, ok, detail) values ('shares_sum_to_one', abs((select sum(x) from unnest(sh) x) - 1) < 0.0001, sh::text);
  insert into r (name, ok, detail) values ('better_converter_more_turns', sh[1] > sh[3] and sh[3] > sh[2] and abs(sh[4] - sh[3]) < 0.02, sh::text);
  insert into r (name, ok, detail) values ('shares_within_floor_and_cap', (select bool_and(x >= 0.5 / 4 - 0.0001 and x <= 2.0 / 4 + 0.0001) from unnest(sh) x), sh::text);
  sh := b2c.perf_shares(array[200, 200], array[100, 0], 0.25, '{"floor": 0.5, "cap": 2}');
  insert into r (name, ok, detail) values ('floor_protects_the_weakest', round(sh[2], 4) = 0.25 and round(sh[1], 4) = 0.75, sh::text);
  sh := b2c.perf_shares(array[0, 0, 0], array[0, 0, 0], 0, '{}');
  insert into r (name, ok, detail) values ('no_history_equal_shares', (select bool_and(round(x, 4) = round(1.0 / 3, 4)) from unnest(sh) x), sh::text);
  -- 200 leads by the decide() rule (lowest load ÷ weight next): each share lands within one lead of its target
  sh := b2c.perf_shares(array[100, 100, 100, 5], array[20, 5, 10, 0], 0.1, '{"floor": 0.5, "cap": 2, "prior": 20}');
  for i in 1 .. 200 loop
    best := 1; bv := null;
    for k in 1 .. 4 loop v := cnt[k] / (sh[k] * 4); if bv is null or v < bv then bv := v; best := k; end if; end loop;
    cnt[best] := cnt[best] + 1;
  end loop;
  for i in 1 .. 4 loop if abs(cnt[i] - sh[i] * 200) > 1 or cnt[i] < 0.5 / 4 * 200 - 1 or cnt[i] > 2.0 / 4 * 200 + 1 then floor_ok := false; end if; end loop;
  insert into r (name, ok, detail) values ('simulated_200_within_floor_and_cap', floor_ok, cnt::text || ' vs ' || sh::text);
  -- decide() with a performance rule records each counsellor's share
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e001');
  v_rule := b2c.rule_save('{"name": "P4 performance", "logic": "performance", "position": 1, "params": {"window_days": 90, "floor": 0.5, "cap": 2}}');
  j := b2c.perf_preview(v_rule);
  insert into r (name, ok, detail) values ('perf_preview', j ->> 'logic' = 'performance' and jsonb_typeof(j -> 'rows') = 'array' and (j ->> 'window_days')::int = 90, left(j::text, 300));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  begin perform b2c.perf_preview(v_rule); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('perf_preview_admin_only', e = 'not allowed', e);
  perform pg_temp.as_system();
  d := b2c.decide(900069, 'handoff', (date_trunc('week', now() at time zone 'Asia/Kolkata') + interval '9 days 12 hours') at time zone 'Asia/Kolkata', null, false);
  insert into r (name, ok, detail) values ('decision_explains_performance', d ->> 'logic' = 'performance' and d ->> 'outcome' = 'assigned' and d ->> 'why' like 'performance over 90 days%'
    and (select bool_and(x ? 'share' and x ? 'weight') from jsonb_array_elements(d -> 'eligible') x), left((d - 'facts')::text, 400));
end $x$;

-- ---------- Google Calendar ----------
do $x$
declare j jsonb; v_task bigint; ce b2c.calendar_events;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  j := b2c.calendar_set(true);
  v_task := b2c.task_add(900061, 'call', 'Discuss fees', now() + interval '1 day', 'parent asked about EMI; call +91 98765 43210');
  select * into ce from b2c.calendar_events where task_id = v_task;
  insert into r (name, ok, detail) values ('task_queued_for_calendar', ce.want = 'upsert' and ce.state = 'pending' and ce.user_id = 'aaaaaaaa-0000-0000-0000-00000000e003', j::text);
  perform pg_temp.as_system();
  j := b2c.calendar_take(50);
  insert into r (name, ok, detail) values ('event_has_no_phone_or_email',
    exists (select 1 from jsonb_array_elements(j) x where (x ->> 'task_id')::bigint = v_task and x ->> 'first_name' = 'Kiran' and x ->> 'email' = 'rohan.p4@eduwit.in')
    and (select (x - 'email' - 'old_email')::text from jsonb_array_elements(j) x where (x ->> 'task_id')::bigint = v_task) !~ '(9876543210|98765 43210|@)',
    (select (x - 'email')::text from jsonb_array_elements(j) x where (x ->> 'task_id')::bigint = v_task));
  perform b2c.calendar_done(v_task, 'gcal-1', 'etag-1');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  perform b2c.task_move(v_task, now() + interval '2 days');
  select * into ce from b2c.calendar_events where task_id = v_task;
  insert into r (name, ok, detail) values ('moved_task_updates_same_event', ce.state = 'pending' and ce.want = 'upsert' and ce.event_id = 'gcal-1', null);
  perform pg_temp.as_system();
  perform b2c.calendar_done(v_task, 'gcal-1', 'etag-2');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e001');
  perform b2c.reassign(array[900061]::bigint[], 'aaaaaaaa-0000-0000-0000-00000000e002', 'P4 calendar test');
  perform pg_temp.as_system();
  select * into ce from b2c.calendar_events where task_id = v_task;
  insert into r (name, ok, detail) values ('reassigned_task_leaves_old_calendar', ce.old_event_id = 'gcal-1' and ce.old_user_id = 'aaaaaaaa-0000-0000-0000-00000000e003'
    and ce.want = 'remove' and ce.event_id is null, row_to_json(ce)::text);
  perform b2c.calendar_done(v_task, null, null);
  update b2c.tasks set status = 'done', done_at = now() where id = v_task;
  insert into r (name, ok, detail) values ('done_task_without_event_stays_quiet', (select state from b2c.calendar_events where task_id = v_task) = 'pending'
    and (select want from b2c.calendar_events where task_id = v_task) = 'remove', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e003');
  j := b2c.calendar_mine();
  insert into r (name, ok, detail) values ('calendar_mine', (j ->> 'on')::boolean, j::text);
  perform pg_temp.as_system();
end $x$;

insert into r (name, ok, detail)
select 'nothing_for_anon', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
