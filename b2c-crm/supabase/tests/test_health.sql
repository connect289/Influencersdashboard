-- b53 checks (the machine health report and messages that stopped mid-send), rolled back. Every row of the final select
-- must say ok = true. Writes only test users and test leads (phones 9100009993xx); safe on staging (SQL editor) and on a
-- local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e531', 'asha.hl@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e534', 'admin.hl@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, languages) values
  ('aaaaaaaa-0000-0000-0000-00000000e531', 'asha.hl@eduwit.in', 'Asha HL', 'counsellor', true, true, false, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e534', 'admin.hl@eduwit.in', 'Admin HL', 'admin', true, true, false, '{English}');
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.hl@eduwit.in' on conflict do nothing;
update b2c.settings set value = value || '{"quiet_start": "00:00", "quiet_end": "23:59"}' where key = 'messaging';

/* A test lead with an owner: the record and the hand-off, then the owner set directly (the test needs no allocation). */
create function pg_temp.lead(p_id bigint) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'hl-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'HL Student ' || p_id, 'phone', '9100009993' || right(p_id::text, 2), 'email', 'hl' || p_id || '@example.com'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'hl-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', '{"b2c_lane": "sales", "reason": "qualified"}'::jsonb), 'test');
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000e531' where lead_id = p_id;
end $f$;

do $t$
declare j jsonb; v jsonb; q b2c.send_queue; v_id1 bigint; v_id2 bigint; v_id3 bigint; v_id4 bigint; v_wa bigint; n int; e text;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(993101);
  delete from b2c.send_queue where to_address like '9100009993%' or lead_id = 993101;

  -- ---------- send_take stamps taken_at ----------
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, not_before)
  values ('whatsapp', 993101, '910000999301', '{"type": "text", "text": "hl take"}', 'sales', now() - interval '1 minute') returning id into v_id1;
  v := b2c.send_take(200);
  select * into q from b2c.send_queue where id = v_id1;
  insert into r (name, ok, detail) values ('take_stamps_taken_at',
    exists (select 1 from jsonb_array_elements(v) x where (x ->> 'id')::bigint = v_id1) and q.status = 'sending' and q.attempts = 1
    and q.taken_at between now() - interval '5 seconds' and now(), row_to_json(q)::text);

  -- ---------- send_release hands back what the app did not start ----------
  n := b2c.send_release(array[v_id1, -1]);
  select * into q from b2c.send_queue where id = v_id1;
  insert into r (name, ok, detail) values ('release_back_to_queued', n = 1 and q.status = 'queued' and q.attempts = 0 and q.taken_at is null, row_to_json(q)::text);
  n := b2c.send_release(array[v_id1]);
  insert into r (name, ok, detail) values ('release_touches_only_sending', n = 0, n::text);
  n := b2c.send_release(null);
  insert into r (name, ok, detail) values ('release_null_is_nothing', n = 0, n::text);

  -- ---------- send_unstick: stuck rows failed, never resent; fresh ones untouched ----------
  begin
    perform b2c.send_unstick(4);
    insert into r (name, ok, detail) values ('unstick_refuses_under_5_min', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('unstick_refuses_under_5_min', sqlstate = '22023', sqlerrm);
  end;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, purpose)
  values ('910000999301', 993101, 'out', 'template', 'Your counsellor is Asha', 'queued', 'assignment') returning id into v_wa;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose, status, attempts, taken_at, not_before)
  values ('whatsapp', 993101, '910000999301', v_wa, '{"type": "text", "text": "hl stuck assignment"}', 'assignment', 'sending', 1, now() - interval '20 minutes', now() - interval '21 minutes')
  returning id into v_id2;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, status, attempts, taken_at, not_before)
  values ('email', 993101, 'hl993101@example.com', '{"subject": "hl", "text": "x"}', 'sales', 'sending', 1, now() - interval '2 minutes', now() - interval '3 minutes')
  returning id into v_id3;
  -- a row taken before b53 has no taken_at: its not_before stands in
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, status, attempts, not_before)
  values ('whatsapp', 993101, '910000999301', '{"type": "text", "text": "hl legacy"}', 'sales', 'sending', 1, now() - interval '2 hours')
  returning id into v_id4;

  -- health and the admin page see them before the fix
  j := b2c.health();
  insert into r (name, ok, detail) values ('health_counts_stuck', (j #>> '{checks,sending,stuck_sending}')::int = 2 and j #>> '{checks,sending,level}' = 'bad', j -> 'checks' ->> 'sending');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e534');
  j := b2c.system_health();
  select c into v from jsonb_array_elements(j -> 'checks') c where c ->> 'key' = 'sending';
  insert into r (name, ok, detail) values ('system_health_shows_stuck', v ->> 'level' = 'bad' and v ->> 'detail' like '%2 stopped mid-send%', v::text);
  perform pg_temp.as_system();

  n := b2c.send_unstick(15);
  insert into r (name, ok, detail) values ('unstick_marks_two', n = 2, n::text);
  select * into q from b2c.send_queue where id = v_id2;
  insert into r (name, ok, detail) values ('unstick_failed_not_requeued', q.status = 'failed' and q.error like 'stopped mid-send%' and q.attempts = 1 and q.sent_at is null, row_to_json(q)::text);
  insert into r (name, ok, detail) values ('unstick_mirrors_wa_message', (select status = 'failed' and error like 'stopped mid-send%' from b2c.wa_messages where id = v_wa), null);
  insert into r (name, ok, detail) values ('unstick_legacy_row_by_not_before', (select status from b2c.send_queue where id = v_id4) = 'failed', null);
  insert into r (name, ok, detail) values ('unstick_leaves_fresh_row', (select status from b2c.send_queue where id = v_id3) = 'sending', null);
  insert into r (name, ok, detail) values ('unstick_assignment_falls_back_to_email',
    exists (select 1 from b2c.send_queue where lead_id = 993101 and channel = 'email' and purpose = 'assignment' and status = 'queued'), null);
  insert into r (name, ok, detail) values ('unstick_one_admin_notice',
    (select count(*) from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000e534' and kind = 'send_failed' and title = 'Messages stopped mid-send') = 1, null);
  n := b2c.send_unstick(15);
  insert into r (name, ok, detail) values ('unstick_again_is_nothing', n = 0, n::text);

  -- ---------- health(): shape, levels, no personal data ----------
  j := b2c.health();
  insert into r (name, ok, detail) values ('health_shape',
    j ? 'ok' and j ->> 'status' in ('ok', 'degraded', 'down') and (select count(*) from jsonb_object_keys(j -> 'checks')) = 9
    and (select bool_and(c.value ->> 'level' in ('ok', 'warn', 'bad')) from jsonb_each(j -> 'checks') c), left(j::text, 600));
  insert into r (name, ok, detail) values ('health_no_personal_data',
    j::text !~ '9100009993|@example\.com|HL Student|993101|aaaaaaaa-', null);
  insert into r (name, ok, detail) values ('health_stuck_cleared_failed_counted',
    (j #>> '{checks,sending,stuck_sending}')::int = 0 and (j #>> '{checks,sending,failed_24h}')::int >= 2, j -> 'checks' ->> 'sending');
  -- the timers not pointed at the site: the app part is bad, so Spark is down
  update b2c.settings set value = value || '{"base_url": null}' where key = 'app';
  j := b2c.health();
  insert into r (name, ok, detail) values ('health_down_when_not_pointed',
    not (j ->> 'ok')::boolean and j ->> 'status' = 'down' and j #>> '{checks,app,level}' = 'bad' and not (j #>> '{checks,app,pointed}')::boolean, j -> 'checks' ->> 'app');
  update b2c.settings set value = value || '{"base_url": "https://spark.example.test"}' where key = 'app';
  insert into vault.secrets_store (name, decrypted_secret) values ('b2c_internal_key', 'k-test-health') on conflict (name) do update set decrypted_secret = excluded.decrypted_secret;
  j := b2c.health();
  insert into r (name, ok, detail) values ('health_pointed', (j #>> '{checks,app,pointed}')::boolean and j #>> '{checks,app,level}' <> 'bad', j -> 'checks' ->> 'app');
  insert into r (name, ok, detail) values ('health_never_shows_the_key', j::text !~ 'k-test-health', null);
  -- a connector whose last answer was an error is named by its key
  insert into b2c.connector_status (key, last_ok_at, last_error_at, last_error) values ('whatsapp', now() - interval '1 hour', now(), 'HTTP 401 for 910000999301')
  on conflict (key) do update set last_ok_at = excluded.last_ok_at, last_error_at = excluded.last_error_at, last_error = excluded.last_error;
  j := b2c.health();
  insert into r (name, ok, detail) values ('health_connector_key_only',
    j #> '{checks,connectors,erroring}' @> '["whatsapp"]' and j #>> '{checks,connectors,level}' = 'warn' and j::text !~ 'HTTP 401', j -> 'checks' ->> 'connectors');

  -- ---------- who may call them ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e534');
  begin
    execute 'set local role authenticated';
    perform b2c.health();
    insert into r (name, ok, detail) values ('health_not_for_staff', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('health_not_for_staff', sqlstate = '42501', sqlerrm);
  end;
  execute 'reset role';
  perform pg_temp.as_system();
end $t$;

insert into r (name, ok, detail)
select 'grants', bool_and(ok), string_agg(detail, '; ') filter (where not ok)
  from (select has_function_privilege('service_role', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
               and not has_function_privilege('anon', f, 'execute') as ok, f as detail
          from unnest(array['b2c.health()', 'b2c.send_release(bigint[])', 'b2c.send_unstick(integer)', 'b2c.send_take(integer)']) f) x;
insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
