-- M34i audit hardening, rolled back (local: supabase/local-test.sh; staging: SQL editor after m34i). Builds its own fixtures
-- (ZZ M34i partners, leads and allocations). Every row must say ok = true.
--   0  http_maybe_delivered: no answer, a timeout, a 5xx or a cut connection may have reached the provider; DNS / refused never
--   1  a push that timed out and was retried, answered "already exists" (409), counts as created with the partner's record id,
--      spot check and alert.push_retry_duplicate, never re-routed; the same for the allocation's own reference, an earlier 5xx,
--      and in the hold window; a real earlier record (older than the timed-out attempt), or an earlier clear 4xx / DNS
--      failure, is still a duplicate and re-routed
--   2  sign_in_locked(email, ip, step): per email and IP; the code step counts only failed codes; 'locked' at most once a
--      minute; a malformed IP is stored as null; service role only
--   3  partner_event_ingest: an event that arrived before the record id was saved is applied when the partner retries it
--   4  the money functions take "today" in India
--   5  receipt_apply refuses a void receipt
--   6  notify_tick: an unclear answer from WhatsApp is failed (maybe sent), never re-sent; Resend (idempotency key) and a
--      clear 4xx are retried; the provider-address guard of m34e is kept
--   7  team_invite_accept refuses an unconfirmed address
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon, service_role;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$ insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
create function pg_temp.partner(p_slug text) returns bigint language plpgsql as $f$
declare v_id bigint;
begin
  insert into b2b.partners (slug, name, display_name, status, api_base_url, inbound_secret_id)
  values (p_slug, 'ZZ ' || p_slug, 'ZZ ' || p_slug, 'active', 'https://' || p_slug || '.zz-m34i.example.invalid/leads',
          vault.create_secret('m34i-inbound-' || p_slug, 'zz_m34i_' || p_slug))
  returning id into v_id;
  return v_id;
end $f$;
-- a lead and its partner allocation in the given status (the lead points at it, as route_decide leaves it)
create function pg_temp.alloc(p_phone text, p_partner bigint, p_status text) returns bigint language plpgsql as $f$
declare v_lead bigint; v_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'M34i ' || p_phone, 'interested_course', 'ZZM34i', 'programme_level', 'PG', 'source', 'website',
                               'classification', 'WARM')));
  select id into v_lead from public.student_leads where whatsapp_number = p_phone;
  insert into b2b.allocations (lead_id, destination_type, partner_id, status, mode, push_attempts)
  values (v_lead, 'partner', p_partner, 'queued', 'manual', 0) returning id into v_id;
  update b2b.allocations set reference = 'EDW-' || v_id where id = v_id;
  if p_status <> 'queued' then update b2b.allocations set status = 'pushing' where id = v_id; end if;
  update public.student_leads set allocation_id = v_id, destination_type = 'partner' where id = v_lead;
  return v_id;
end $f$;
-- one finished push attempt, as push_dispatch inserts and push_collect completes it
create function pg_temp.attempt(p_alloc bigint, p_no int, p_outcome text, p_status int, p_error text, p_ago interval) returns void language sql as $f$
  insert into b2b.push_requests (allocation_id, attempt, url, outcome, status_code, error, sent_at, completed_at)
  values (p_alloc, p_no, 'https://zz-m34i.example.invalid/leads', p_outcome, p_status, p_error, now() - p_ago, now() - p_ago + interval '2 minutes');
  update b2b.allocations set push_attempts = greatest(push_attempts, p_no) where id = p_alloc;
$f$;
create function pg_temp.events(p_alloc bigint, p_type text) returns int language sql as $f$
  select count(*)::int from b2b.events where allocation_id = p_alloc and type = p_type $f$;
create function pg_temp.ingest(p_slug text, p_body jsonb) returns jsonb language plpgsql as $f$
declare ts text := extract(epoch from now())::bigint::text; sec text;
begin
  sec := b2b.partner_secret((select inbound_secret_id from b2b.partners where slug = p_slug));
  return b2b.partner_event_ingest(p_slug, p_body::text, ts,
    'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || p_body::text, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
end $f$;

insert into b2b.live_switches (scope, live, reason) values ('routing', false, 'm34i test: no re-route reaches a real partner')
  on conflict (scope) do update set live = false;
select pg_temp.set('P', pg_temp.partner('zz-m34i-a')::text);

-- ---------- (0) the shared rule ----------
insert into r select 'maybe_delivered_rule',
  b2b.http_maybe_delivered(false, null, null, null)                         -- no answer yet
  and b2b.http_maybe_delivered(true, true, null, 'Timeout was reached')     -- timed out
  and b2b.http_maybe_delivered(true, false, 502, null)                      -- 5xx
  and b2b.http_maybe_delivered(true, false, null, 'Recv failure: Connection reset by peer')
  and b2b.http_maybe_delivered(true, false, null, 'Server returned nothing (no headers, no status code)')
  and not b2b.http_maybe_delivered(true, false, 200, null)
  and not b2b.http_maybe_delivered(true, false, 400, 'HTTP 400: bad phone')
  and not b2b.http_maybe_delivered(true, false, null, 'Could not resolve host: zz.example.invalid')
  and not b2b.http_maybe_delivered(true, false, null, 'Couldn''t connect to server')
  and not b2b.http_maybe_delivered(true, false, null, 'Failed to connect to zz port 443: Connection refused'), null;
insert into r select 'maybe_delivered_internal', not has_function_privilege('anon', 'b2b.http_maybe_delivered(boolean, boolean, integer, text)', 'execute')
  and not has_function_privilege('authenticated', 'b2b.http_maybe_delivered(boolean, boolean, integer, text)', 'execute')
  and has_function_privilege('service_role', 'b2b.http_maybe_delivered(boolean, boolean, integer, text)', 'execute'), null;

-- ---------- (1) timeout -> retry -> "already exists" ----------
do $x$ declare v_a bigint; a b2b.allocations; v_res text; v_lead bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  v_a := pg_temp.alloc('919811034901', pg_temp.v('P')::bigint, 'pushing');
  -- attempt 1: no answer within 2 minutes (push_collect marks it timeout); attempt 2: the partner says it already has the lead
  perform pg_temp.attempt(v_a, 1, 'timeout', null, 'no response within 2 minutes', interval '4 minutes');
  perform pg_temp.attempt(v_a, 2, 'duplicate', 409, null, interval '10 seconds');
  v_res := b2b.apply_duplicate(v_a, jsonb_build_object('duplicate', true, 'existing_id', 'ZZP-901', 'created_at', now() - interval '4 minutes',
                                                       'status_code', 409, 'source', 'push_response'));
  select * into a from b2b.allocations where id = v_a;
  select lead_id into v_lead from b2b.allocations where id = v_a;
  insert into r values ('retry_dup_created', v_res like 'created: own record%' and a.status = 'pushed' and a.partner_record_id = 'ZZP-901'
                          and a.outcome is null and a.hold_until is not null, v_res || ' / ' || a.status || ' / ' || coalesce(a.partner_record_id, '-'));
  insert into r values ('retry_dup_flagged', a.spot_check and a.claim_existing_record_id = 'ZZP-901' and pg_temp.events(v_a, 'alert.push_retry_duplicate') = 1
                          and pg_temp.events(v_a, 'lead.pushed') = 1,
                        (select payload::text from b2b.events where allocation_id = v_a and type = 'alert.push_retry_duplicate'));
  insert into r values ('retry_dup_not_rerouted', pg_temp.events(v_a, 'lead.duplicate') = 0 and pg_temp.events(v_a, 'alert.partner_rejected') = 0
                          and (select count(*) from b2b.allocations where lead_id = v_lead) = 1
                          and (select allocation_id = v_a and stage = 'sent_to_partner' and partner_record_id = 'ZZP-901' from public.student_leads where id = v_lead)
                          and coalesce((select duplicate_claim_count from public.student_leads where id = v_lead), 0) = 0, null);
end $x$;

-- the claim names this allocation's own reference (no earlier failure needed)
do $x$ declare v_a bigint; a b2b.allocations; v_res text;
begin
  v_a := pg_temp.alloc('919811034902', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_a, 1, 'duplicate', 409, null, interval '5 seconds');
  v_res := b2b.apply_duplicate(v_a, jsonb_build_object('duplicate', true, 'existing_reference', 'EDW-' || v_a, 'existing_id', 'ZZP-902'));
  select * into a from b2b.allocations where id = v_a;
  insert into r values ('own_reference_created', v_res like 'created: own record (the claim names this allocation''s own reference)'
                          and a.status = 'pushed' and a.partner_record_id = 'ZZP-902' and a.spot_check, v_res);
end $x$;

-- an earlier 5xx (may have been created), and the record id only in "record_id"
do $x$ declare v_a bigint; a b2b.allocations; v_res text;
begin
  v_a := pg_temp.alloc('919811034903', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_a, 1, 'error', 503, 'HTTP 503: unavailable', interval '90 seconds');
  perform pg_temp.attempt(v_a, 2, 'duplicate', 409, null, interval '5 seconds');
  v_res := b2b.apply_duplicate(v_a, jsonb_build_object('duplicate', true, 'record_id', 'ZZP-903'));
  select * into a from b2b.allocations where id = v_a;
  insert into r values ('earlier_5xx_created', v_res like 'created: own record%' and a.status = 'pushed' and a.partner_record_id = 'ZZP-903' and a.spot_check, v_res);
end $x$;

-- in the hold window (a partner event after the push): kept, flagged, never re-routed
do $x$ declare v_a bigint; a b2b.allocations; v_res text;
begin
  v_a := pg_temp.alloc('919811034904', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_a, 1, 'timeout', null, 'no response within 2 minutes', interval '6 minutes');
  perform pg_temp.attempt(v_a, 2, 'created', 201, null, interval '3 minutes');
  perform b2b.apply_created(v_a, 'ZZP-904');
  v_res := b2b.apply_duplicate(v_a, jsonb_build_object('duplicate', true, 'existing_id', 'ZZP-904-dup', 'created_at', now() - interval '5 minutes'));
  select * into a from b2b.allocations where id = v_a;
  insert into r values ('hold_window_kept', v_res like 'created: own record%' and a.status = 'pushed' and a.partner_record_id = 'ZZP-904'
                          and a.spot_check and pg_temp.events(v_a, 'alert.push_retry_duplicate') = 1, v_res || ' / ' || a.status);
end $x$;

-- controls: a record older than the timed-out attempt, an earlier clear 4xx, an earlier DNS failure: still duplicates
do $x$ declare v_a bigint; v_b bigint; v_c bigint; v_ra text; v_rb text; v_rc text;
begin
  v_a := pg_temp.alloc('919811034905', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_a, 1, 'timeout', null, 'no response within 2 minutes', interval '4 minutes');
  v_ra := b2b.apply_duplicate(v_a, jsonb_build_object('duplicate', true, 'existing_id', 'ZZP-OLD', 'created_at', now() - interval '40 days'));
  v_b := pg_temp.alloc('919811034906', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_b, 1, 'error', 400, 'HTTP 400: bad phone', interval '4 minutes');
  v_rb := b2b.apply_duplicate(v_b, jsonb_build_object('duplicate', true, 'existing_id', 'ZZP-B'));
  v_c := pg_temp.alloc('919811034907', pg_temp.v('P')::bigint, 'pushing');
  perform pg_temp.attempt(v_c, 1, 'error', null, 'Could not resolve host: zz-m34i.example.invalid', interval '4 minutes');
  v_rc := b2b.apply_duplicate(v_c, jsonb_build_object('duplicate', true, 'existing_id', 'ZZP-C'));
  insert into r values ('older_record_is_duplicate', v_ra = 'duplicate: re-routed' and (select status from b2b.allocations where id = v_a) = 'duplicate'
                          and pg_temp.events(v_a, 'alert.push_retry_duplicate') = 0, v_ra);
  insert into r values ('clear_4xx_is_duplicate', v_rb = 'duplicate: re-routed' and (select status from b2b.allocations where id = v_b) = 'duplicate', v_rb);
  insert into r values ('dns_failure_is_duplicate', v_rc = 'duplicate: re-routed' and (select status from b2b.allocations where id = v_c) = 'duplicate', v_rc);
end $x$;

-- ---------- (2) sign-in lockout per email and IP ----------
insert into b2b.sign_in_log (email, method, outcome, ip, at)
select 'zz-m34i-admin@test.local', 'password', 'failed_password', '198.51.100.9', now() - make_interval(secs => g) from generate_series(1, 5) g;
insert into r select 'lock_same_ip', b2b.sign_in_locked('ZZ-M34i-Admin@test.local', '198.51.100.9', 'password'), null;
insert into r select 'no_lock_other_ip', not b2b.sign_in_locked('zz-m34i-admin@test.local', '203.0.113.20', 'password')
                     and not b2b.sign_in_locked('zz-m34i-admin@test.local', null, 'password')
                     and not b2b.sign_in_locked('zz-m34i-admin@test.local', 'not-an-ip', 'password'), null;
insert into r select 'totp_not_blocked_by_passwords', not b2b.sign_in_locked('zz-m34i-admin@test.local', '198.51.100.9', 'totp'), null;
insert into b2b.sign_in_log (email, method, outcome, ip, at)
select 'zz-m34i-admin@test.local', 'totp', 'failed_totp', ('203.0.113.' || g)::inet, now() - make_interval(secs => g) from generate_series(1, 5) g;
insert into r select 'totp_locks_on_failed_codes', b2b.sign_in_locked('zz-m34i-admin@test.local', '192.0.2.1', 'totp'), null;
insert into b2b.sign_in_log (email, method, outcome, ip) values ('zz-m34i-admin@test.local', 'totp', 'success', '198.51.100.9');
insert into r select 'success_resets', not b2b.sign_in_locked('zz-m34i-admin@test.local', '198.51.100.9', 'password')
                     and not b2b.sign_in_locked('zz-m34i-admin@test.local', '192.0.2.1', 'totp'), null;
insert into r select 'old_one_argument_unchanged', to_regprocedure('b2b.sign_in_locked(text)') is not null, null;
do $x$ declare a bigint; b bigint; c bigint; n int; v_ip inet;
begin
  a := b2b.record_sign_in(jsonb_build_object('email', 'ZZ-M34i-Other@test.local', 'method', 'password', 'outcome', 'locked', 'ip', '198.51.100.10'));
  b := b2b.record_sign_in(jsonb_build_object('email', 'zz-m34i-other@test.local', 'method', 'password', 'outcome', 'locked', 'ip', '198.51.100.11'));
  select count(*) into n from b2b.sign_in_log where email = 'zz-m34i-other@test.local' and outcome = 'locked';
  insert into r values ('locked_logged_once_a_minute', a is not null and b is null and n = 1, a || ' / ' || coalesce(b::text, 'null') || ' / ' || n);
  c := b2b.record_sign_in(jsonb_build_object('email', 'zz-m34i-other@test.local', 'method', 'password', 'outcome', 'failed_password', 'ip', 'garbage'));
  select ip into v_ip from b2b.sign_in_log where id = c;
  insert into r values ('malformed_ip_stored_null', c is not null and v_ip is null, c::text);
end $x$;
insert into r select 'lock_check_service_role_only',
  not has_function_privilege('anon', 'b2b.sign_in_locked(text, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'b2b.sign_in_locked(text, text, text)', 'execute')
  and has_function_privilege('service_role', 'b2b.sign_in_locked(text, text, text)', 'execute')
  and not has_function_privilege('anon', 'b2b.record_sign_in(jsonb)', 'execute')
  and has_function_privilege('service_role', 'b2b.record_sign_in(jsonb)', 'execute'), null;

-- ---------- (3) a partner's retry of an event that arrived before its record id was saved ----------
do $x$ declare v_a bigint; x1 jsonb; x2 jsonb; x3 jsonb; e b2b.partner_events; v_body jsonb;
begin
  v_a := pg_temp.alloc('919811034908', pg_temp.v('P')::bigint, 'pushing');
  v_body := jsonb_build_object('event_id', 'zz-m34i-ev-1', 'type', 'contacted', 'record_id', 'ZZP-908', 'occurred_at', now());
  -- the partner's webhook arrives before its push answer: no allocation has record ZZP-908 yet
  x1 := pg_temp.ingest('zz-m34i-a', v_body);
  select * into e from b2b.partner_events where event_id = 'zz-m34i-ev-1';
  insert into r values ('early_event_stored_as_error', x1 ->> 'status' = '404' and e.status = 'error' and e.allocation_id is null, x1::text);
  perform b2b.apply_created(v_a, 'ZZP-908');
  x2 := pg_temp.ingest('zz-m34i-a', v_body);
  select * into e from b2b.partner_events where event_id = 'zz-m34i-ev-1';
  insert into r values ('retry_applied', (x2 ->> 'ok')::boolean and x2 ->> 'result' is distinct from 'already received'
                          and e.allocation_id = v_a and e.status <> 'error'
                          and (select count(*) from b2b.partner_events where event_id = 'zz-m34i-ev-1') = 1
                          and pg_temp.events(v_a, 'partner.event_retried') = 1, x2::text || ' / ' || e.status);
  x3 := pg_temp.ingest('zz-m34i-a', v_body);
  insert into r values ('second_retry_already_received', x3 ->> 'result' = 'already received' and pg_temp.events(v_a, 'partner.event_retried') = 1, x3::text);
end $x$;

-- ---------- (4) "today" in India ----------
insert into r select 'money_dates_india', bool_and(prosrc !~* 'current_date' and prosrc ~ 'Asia/Kolkata'),
                     coalesce(string_agg(proname, ', ') filter (where prosrc ~* 'current_date' or prosrc !~ 'Asia/Kolkata'), 'all')
  from pg_proc where pronamespace = 'b2b'::regnamespace
   and proname in ('receipt_record', 'enrollment_verify', 'enrollment_refund', 'earning_manual', 'enrollment_record');
insert into auth.users (id, email, aud, role, email_confirmed_at)
values ('aaaaaaaa-0000-0000-0000-0000000034a1', 'zz-m34i-admin@test.local', 'authenticated', 'authenticated', now());
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000034a1', 'zz-m34i-admin@test.local');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000034a1","role":"authenticated","aal":"aal2","email":"zz-m34i-admin@test.local"}', true);
do $x$ declare j jsonb; e text;
begin
  j := b2b.receipt_record(jsonb_build_object('partner_id', pg_temp.v('P'), 'amount_inr', 1000, 'received_on', (now() at time zone 'Asia/Kolkata')::date));
  insert into r values ('receipt_today_in_india', (select received_on from b2b.receipts where id = (j ->> 'id')::bigint) = (now() at time zone 'Asia/Kolkata')::date, j::text);
  e := pg_temp.err(format($q$select b2b.receipt_record(jsonb_build_object('partner_id', %s, 'amount_inr', 1000, 'received_on', %L))$q$,
                          pg_temp.v('P'), ((now() at time zone 'Asia/Kolkata')::date + 1)::text));
  insert into r values ('receipt_tomorrow_refused', e like '22023%future%', e);
  j := b2b.receipt_record(jsonb_build_object('partner_id', pg_temp.v('P'), 'amount_inr', 500));
  insert into r values ('receipt_default_date_india', (select received_on from b2b.receipts where id = (j ->> 'id')::bigint) = (now() at time zone 'Asia/Kolkata')::date, j::text);
end $x$;

-- ---------- (5) a void receipt never settles ----------
do $x$ declare v_r bigint; e text;
begin
  insert into b2b.receipts (partner_id, received_on, amount_inr, status, void_reason) values (pg_temp.v('P')::bigint, current_date, 100, 'void', 'm34i test')
  returning id into v_r;
  e := pg_temp.err(format('select b2b.receipt_apply(%s, -1, null, %L)', v_r, 'manual'));
  insert into r values ('void_receipt_refused', e like 'P0002%void%' and not exists (select 1 from b2b.receipt_allocations where receipt_id = v_r), e);
end $x$;

-- ---------- (6) student messages that may have been sent ----------
do $x$ declare v_a bigint; v_lead bigint; n1 bigint; n2 bigint; n3 bigint; x jsonb; s1 b2b.student_notifications; s2 b2b.student_notifications; s3 b2b.student_notifications;
begin
  v_a := pg_temp.alloc('919811034909', pg_temp.v('P')::bigint, 'pushing');
  select lead_id into v_lead from b2b.allocations where id = v_a;
  insert into net._http_response (id, status_code, content, timed_out, error_msg) values
    (934001, null, null, true, 'Timeout was reached'), (934002, null, null, true, 'Timeout was reached'), (934003, 400, '{"error":{"message":"bad number"}}', false, null);
  insert into b2b.student_notifications (lead_id, allocation_id, partner_id, kind, channel, status, attempts, net_request_id, provider, updated_at) values
    (v_lead, v_a, pg_temp.v('P')::bigint, 'm34i_wa', 'whatsapp', 'sending', 1, 934001, 'meta_cloud', now() - interval '20 seconds'),
    (v_lead, v_a, pg_temp.v('P')::bigint, 'm34i_mail', 'email', 'sending', 1, 934002, 'resend', now() - interval '20 seconds'),
    (v_lead, v_a, pg_temp.v('P')::bigint, 'm34i_wa_4xx', 'whatsapp', 'sending', 1, 934003, 'meta_cloud', now() - interval '20 seconds');
  select id into n1 from b2b.student_notifications where allocation_id = v_a and kind = 'm34i_wa';
  select id into n2 from b2b.student_notifications where allocation_id = v_a and kind = 'm34i_mail';
  select id into n3 from b2b.student_notifications where allocation_id = v_a and kind = 'm34i_wa_4xx';
  x := b2b.notify_tick();
  select * into s1 from b2b.student_notifications where id = n1;
  select * into s2 from b2b.student_notifications where id = n2;
  select * into s3 from b2b.student_notifications where id = n3;
  insert into r values ('whatsapp_timeout_not_resent', s1.status = 'failed' and s1.error like 'may have been sent (%' and s1.net_request_id is null
                          and exists (select 1 from b2b.events where type = 'alert.notification_failed' and allocation_id = v_a
                                        and (payload ->> 'maybe_sent')::boolean), s1.status || ' / ' || coalesce(s1.error, '-'));
  insert into r values ('resend_timeout_retried', s2.status = 'scheduled' and s2.scheduled_for > now(), s2.status);
  insert into r values ('clear_4xx_retried', s3.status = 'scheduled' and s3.error like 'HTTP 400%', s3.status || ' / ' || coalesce(s3.error, '-'));
end $x$;
insert into r select 'notify_tick_keeps_url_guard', prosrc ~ 'b2b.url_allowed' and prosrc ~ 'http_maybe_delivered', null
  from pg_proc where oid = 'b2b.notify_tick()'::regprocedure;
insert into r select 'resend_idempotency_key', prosrc ~ $q$'Idempotency-Key', 'notify-' \|\| n.id$q$, null
  from pg_proc where oid = 'b2b.notify_request(b2b.student_notifications)'::regprocedure;

-- ---------- (7) a team invitation needs a confirmed address ----------
do $x$ declare ok1 boolean; ok2 boolean;
begin
  insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000034a2', 'zz-m34i-new@test.local', 'authenticated', 'authenticated');
  insert into b2b.team_invites (email, role, invited_by) values ('zz-m34i-new@test.local', 'viewer', 'aaaaaaaa-0000-0000-0000-0000000034a1');
  ok1 := b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000034a2', 'zz-m34i-new@test.local');
  insert into r values ('invite_unconfirmed_refused', not ok1 and not exists (select 1 from b2b.app_users where user_id = 'aaaaaaaa-0000-0000-0000-0000000034a2')
                          and (select accepted_at is null from b2b.team_invites where email = 'zz-m34i-new@test.local'), null);
  update auth.users set email_confirmed_at = now() where id = 'aaaaaaaa-0000-0000-0000-0000000034a2';
  ok2 := b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000034a2', 'zz-m34i-new@test.local');
  insert into r values ('invite_confirmed_accepted', ok2 and (select role from b2b.app_users where user_id = 'aaaaaaaa-0000-0000-0000-0000000034a2') = 'viewer', null);
end $x$;

select name, ok, detail from r order by name;
rollback;
