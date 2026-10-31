-- Audit of 30 Oct 2026 (b47, b48, b49, b50), rolled back. Every row of the final select must say ok = true.
-- Writes only test users, test leads (phones 9100009997xx) and their rows; capacity_tick's check turns takes_leads off
-- for everyone inside the transaction. Safe on staging (SQL editor) and on a local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000a701', 'admin.au@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000a702', 'asha.au@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000a703', 'bala.au@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000a704', 'head.au@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000a705', 'nocode.au@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000a799', 'stranger.au@example.com', 'authenticated', 'authenticated');  -- an account that is not a Spark user
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, team, languages) values
  ('aaaaaaaa-0000-0000-0000-00000000a701', 'admin.au@eduwit.in', 'Admin AU', 'admin', true, true, false, null, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000a702', 'asha.au@eduwit.in', 'Asha AU', 'counsellor', true, true, true, 'North AU', '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000a703', 'bala.au@eduwit.in', 'Bala AU', 'counsellor', true, true, true, 'South AU', '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000a704', 'head.au@eduwit.in', 'Head AU', 'sales_head', true, true, false, 'North AU', '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000a705', 'nocode.au@eduwit.in', 'Nocode AU', 'counsellor', true, true, true, 'North AU', '{English}');
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
-- every staff fixture has a checked session except Nocode; the stranger has no Spark user row
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users
 where email like '%.au@eduwit.in' and email <> 'nocode.au@eduwit.in' on conflict do nothing;

/* A test lead handed to Sales and given to p_owner. */
create function pg_temp.lead(p_id bigint, p_owner uuid) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'au-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'AU Student ' || p_id, 'phone', '9100009997' || right(p_id::text, 2), 'email', 'au' || p_id || '@example.com'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'au-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', '{"b2c_lane": "sales", "reason": "fallback"}'::jsonb), 'test');
  perform b2c.assign(p_id, p_owner, null, 'manual', 'audit check');
end $f$;

do $x$
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(997701, 'aaaaaaaa-0000-0000-0000-00000000a702');   -- Asha (North)
  perform pg_temp.lead(997702, 'aaaaaaaa-0000-0000-0000-00000000a703');   -- Bala (South)
  perform b2c.add_task(997701, 'aaaaaaaa-0000-0000-0000-00000000a702', 'call', 'AU call Asha', now() - interval '1 hour', null, false, 'manual');
  perform b2c.add_task(997702, 'aaaaaaaa-0000-0000-0000-00000000a703', 'call', 'AU call Bala', now() - interval '1 hour', null, false, 'manual');
  -- the To qualify task for lead 997701: Asha's, and one for Nocode on the same lead
  perform b2c.add_task(997701, 'aaaaaaaa-0000-0000-0000-00000000a702', 'qualify', 'Collect the missing details', now() + interval '1 day', null, false, 'qualify');
  perform b2c.add_task(997701, 'aaaaaaaa-0000-0000-0000-00000000a705', 'qualify', 'Collect the missing details', now() + interval '1 day', null, false, 'qualify');
end $x$;

-- ---------- b47: qualify_record ----------
do $x$
declare e text; n0 int; n1 int;
begin
  select count(*) into n0 from b2c.field_history where lead_id = 997701;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a799');
  insert into r (name, ok, detail) values ('stranger_has_no_role', b2c.my_role() is null and not b2c.is_staff(), null);
  begin perform b2c.qualify_record(997701, '{"name": "Changed by a stranger", "email": "x@example.com"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('qualify_record_refuses_stranger', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a705');
  begin perform b2c.qualify_record(997701, '{"course": "Online MBA"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('qualify_record_refuses_session_without_code', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a703');
  begin perform b2c.qualify_record(997701, '{"course": "Online MBA"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('qualify_record_refuses_other_counsellor', e = 'not allowed', e);
  perform pg_temp.as_system();
  select count(*) into n1 from b2c.field_history where lead_id = 997701;
  insert into r (name, ok, detail) values ('refused_calls_changed_nothing', n1 = n0
    and not exists (select 1 from b2c.outbox o where o.lead_id = 997701 and o.kind = 'event' and o.body ->> 'type' = 'b2ccrm.qualification_completed'), n0 || ' -> ' || n1);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a702');
  begin perform b2c.qualify_record(997701, '{"course": "Online MBA"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('qualify_record_task_owner_still_records', e = 'recorded'
    and exists (select 1 from b2c.outbox o where o.lead_id = 997701 and o.kind = 'event' and o.body ->> 'type' = 'b2ccrm.qualification_completed'), e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a701');
  begin perform b2c.qualify_record(997702, '{"enrollment_timeline": "Next month"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('qualify_record_admin_still_records', e = 'recorded', e);
  perform pg_temp.as_system();
end $x$;

-- ---------- b47: support tickets ----------
do $x$
declare j jsonb; v bigint; m bigint; e text; p text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a702');
  j := b2c.support_create('{"kind": "bug", "subject": "AU audit ticket", "body": "A ticket only Asha and the Admin may see."}');
  v := (j ->> 'ticket_id')::bigint; m := (j ->> 'message_id')::bigint;
  p := 'tickets/' || v || '/0f0f0f0f-0000-4000-8000-0000000000a7.png';
  perform b2c.support_attach(m, jsonb_build_array(jsonb_build_object('path', p, 'name', 'screen.png', 'type', 'image/png', 'size', 100)));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a799');
  insert into r (name, ok, detail) values ('support_may_see_refuses_stranger', b2c.support_may_see(v) is false, coalesce(b2c.support_may_see(v)::text, 'null'));
  begin perform b2c.support_get(v); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('support_get_refuses_stranger', e = 'not allowed', e);
  begin perform b2c.support_reply(v, 'Injected by a stranger', array['https://example.com/x']); e := 'replied'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('support_reply_refuses_stranger', e = 'not allowed', e);
  begin perform b2c.support_set_status(v, 'fixed', 'set by a stranger'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('support_set_status_refuses_stranger', e = 'not allowed', e);
  insert into r (name, ok, detail) values ('support_file_refuses_stranger', not b2c.support_file_ok(p), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a705');
  begin perform b2c.support_get(v); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('support_get_refuses_session_without_code', e = 'not allowed', e);
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('ticket_untouched', (select status from b2c.support_tickets where id = v) = 'open'
    and (select count(*) from b2c.support_messages where ticket_id = v) = 1, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a702');
  insert into r (name, ok, detail) values ('support_owner_still_reads', (b2c.support_get(v) ->> 'subject') = 'AU audit ticket' and b2c.support_file_ok(p), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a701');
  insert into r (name, ok, detail) values ('support_admin_still_reads', (b2c.support_get(v) ->> 'subject') = 'AU audit ticket', null);
  perform b2c.support_set_status(v, 'in_progress');
  insert into r (name, ok, detail) values ('support_admin_still_sets_any_status', (select status from b2c.support_tickets where id = v) = 'in_progress', null);
  perform pg_temp.as_system();
end $x$;

-- ---------- b47: saved views by link ----------
do $x$
declare v_shared bigint; v_std bigint; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a702');
  v_shared := b2c.view_save('{"name": "AU shared", "shared_with_role": "counsellor"}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a701');
  v_std := b2c.view_save('{"name": "AU standard", "role": "sales", "is_standard": true}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a799');
  begin perform b2c.view_get(v_shared); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('view_get_refuses_stranger_shared', e = 'this view is not shared with you', e);
  begin perform b2c.view_get(v_std); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('view_get_refuses_stranger_standard', e = 'this view is not shared with you', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a703');
  insert into r (name, ok, detail) values ('view_get_same_role_still_opens', (b2c.view_get(v_shared) ->> 'name') = 'AU shared' and (b2c.view_get(v_std) ->> 'name') = 'AU standard', null);
  perform pg_temp.as_system();
end $x$;

-- ---------- b47: insights candidates are for the job only ----------
insert into r (name, ok, detail) values ('insights_candidates_service_only',
  not has_function_privilege('authenticated', 'b2c.insights_candidates(uuid)', 'execute') and has_function_privilege('service_role', 'b2c.insights_candidates(uuid)', 'execute'), null);

-- ---------- b48: a sales head's follow-ups are the team's ----------
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a704');
  j := b2c.followups('overdue', null);
  insert into r (name, ok, detail) values ('head_sees_team_followups', exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997701)
    and not exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997702), left(j::text, 300));
  begin j := b2c.followups('overdue', 'aaaaaaaa-0000-0000-0000-00000000a703'); e := 'listed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('head_cannot_pick_another_team', e = 'choose someone in your team', e);
  j := b2c.followups('overdue', 'aaaaaaaa-0000-0000-0000-00000000a702');
  insert into r (name, ok, detail) values ('head_picks_team_member', exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997701), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a701');
  j := b2c.followups('overdue', null);
  insert into r (name, ok, detail) values ('admin_still_sees_everyone', exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997701)
    and exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997702), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a703');
  j := b2c.followups('overdue', 'aaaaaaaa-0000-0000-0000-00000000a702');
  insert into r (name, ok, detail) values ('counsellor_still_sees_only_own', not exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997701)
    and exists (select 1 from jsonb_array_elements(j) x where (x -> 'lead' ->> 'lead_id')::bigint = 997702), null);
  perform pg_temp.as_system();
end $x$;

-- ---------- b51: a person's own rows need the checked second step (read as the API does: role authenticated) ----------
create temp table own (k text primary key, id bigint);
grant all on own to authenticated, service_role;
do $x$
begin
  perform pg_temp.as_system();
  perform b2c.add_task(997701, 'aaaaaaaa-0000-0000-0000-00000000a705', 'call', 'AU own task Nocode', now() - interval '1 hour', null, false, 'manual');
  perform b2c.add_task(997702, 'aaaaaaaa-0000-0000-0000-00000000a702', 'call', 'AU own task Asha', now() - interval '1 hour', null, false, 'manual');
  perform b2c.notify('aaaaaaaa-0000-0000-0000-00000000a705', 'assignment', 'AU note for Nocode', null, '/s', null, null);
  perform b2c.notify('aaaaaaaa-0000-0000-0000-00000000a702', 'assignment', 'AU note for Asha', null, '/s', null, null);
  update b2c.users set phone = '+919000000075', leaderboard_visible = false, first_sign_in_at = null where user_id = 'aaaaaaaa-0000-0000-0000-00000000a705';
  with s as (insert into b2c.snippets (owner_id, title, body) values ('aaaaaaaa-0000-0000-0000-00000000a705', 'AU snippet', 'Hello') returning id)
  insert into own select 'snippet', id from s;
  with s as (insert into b2c.dashboards (name, owner_id, created_by)
             values ('AU own dashboard', 'aaaaaaaa-0000-0000-0000-00000000a705', 'aaaaaaaa-0000-0000-0000-00000000a705') returning id)
  insert into own select 'dashboard', id from s;
end $x$;
do $x$
declare j jsonb; e text; n int;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a705');   -- Nocode: password only, no checked session
  set local role authenticated;
  insert into r (name, ok, detail) values ('own_tasks_need_second_step', (select count(*) from b2c.tasks where title like 'AU own task%') = 0, null);
  insert into r (name, ok, detail) values ('own_notifications_need_second_step', (select count(*) from b2c.notifications where title like 'AU note%') = 0
    and (b2c.notifications_mine() ->> 'unread')::int = 0 and jsonb_array_length(b2c.notifications_mine() -> 'items') = 0, null);
  j := b2c.nav_counts();
  insert into r (name, ok, detail) values ('own_counts_need_second_step', (j ->> 'overdue')::int = 0 and (j ->> 'unread_alerts')::int = 0
    and (b2c.followup_counts('aaaaaaaa-0000-0000-0000-00000000a705') ->> 'overdue')::int = 0, j::text);
  insert into r (name, ok, detail) values ('own_user_row_needs_second_step', (select count(*) from b2c.users where user_id = 'aaaaaaaa-0000-0000-0000-00000000a705') = 0
    and b2c.phone_mine() is null and b2c.calendar_mine() is null, coalesce(b2c.phone_mine()::text, 'null'));
  insert into r (name, ok, detail) values ('own_snippets_need_second_step', (select count(*) from b2c.snippets where title = 'AU snippet') = 0, null);
  begin perform b2c.snippet_delete((select id from own where k = 'snippet')); e := 'deleted'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('own_snippet_delete_needs_second_step', e = 'not your snippet', e);
  begin perform b2c.dashboard_get((select id from own where k = 'dashboard')); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('own_dashboard_needs_second_step', e = 'not allowed', e);
  begin perform b2c.dashboard_archive((select id from own where k = 'dashboard')); e := 'archived'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('own_dashboard_archive_needs_second_step', e = 'not allowed', e);
  perform b2c.notifications_read(null);
  perform b2c.leaderboard_opt(true);
  perform b2c.session_note('AU browser', '192.0.2.10');
  reset role;
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('own_writes_need_second_step',
    (select count(*) from b2c.notifications where title = 'AU note for Nocode' and read_at is null) = 1
    and (select not leaderboard_visible and first_sign_in_at is null from b2c.users where user_id = 'aaaaaaaa-0000-0000-0000-00000000a705')
    and (select archived_at is null from b2c.dashboards where id = (select id from own where k = 'dashboard')), null);
  -- the same rows for a checked session (Asha)
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a702');
  set local role authenticated;
  insert into r (name, ok, detail) values ('own_rows_with_second_step', (select count(*) from b2c.tasks where title = 'AU own task Asha') = 1
    and exists (select 1 from jsonb_array_elements(b2c.notifications_mine() -> 'items') x where x ->> 'title' = 'AU note for Asha')
    and (b2c.nav_counts() ->> 'overdue')::int >= 1 and (select count(*) from b2c.users where user_id = 'aaaaaaaa-0000-0000-0000-00000000a702') = 1, null);
  reset role;
  perform pg_temp.as_system();
end $x$;

-- ---------- b50: the emailed code (after the checks above, which need Nocode without a checked session) ----------
do $x$
declare c text; j jsonb;
begin
  perform pg_temp.as_system();
  c := b2c.mfa_issue('aaaaaaaa-0000-0000-0000-00000000a705', 'bbbbbbbb-0000-0000-0000-00000000a705');
  insert into r (name, ok, detail) values ('mfa_code_six_digits', c ~ '^[0-9]{6}$', null);
  insert into r (name, ok, detail) values ('mfa_code_from_strong_random', pg_get_functiondef('b2c.mfa_issue(uuid,uuid)'::regprocedure) ~ 'gen_random_bytes'
    and pg_get_functiondef('b2c.mfa_issue(uuid,uuid)'::regprocedure) !~ '[^_]random\(\)', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000a705');
  j := b2c.mfa_verify(c, false, null);
  insert into r (name, ok, detail) values ('mfa_code_verifies_and_checks_session', (j ->> 'ok')::boolean and b2c.my_role() = 'counsellor', j::text);
  perform pg_temp.as_system();
end $x$;

-- ---------- b49: capacity_tick with nobody taking leads ----------
do $x$
declare n int; e text;
begin
  perform pg_temp.as_system();
  update b2c.users set takes_leads = false where takes_leads;
  begin n := b2c.capacity_tick(); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('capacity_tick_runs_with_nobody_taking_leads', e = 'ran' and n = 0, e || ' ' || coalesce(n::text, 'null'));
  update b2c.users set takes_leads = true, is_test_user = false, monthly_cap = 1 where user_id = 'aaaaaaaa-0000-0000-0000-00000000a702';
  n := b2c.capacity_tick();
  insert into r (name, ok, detail) values ('capacity_tick_still_alerts', n >= 1 and exists (select 1 from b2c.notifications x where x.kind = 'capacity' and x.title like 'Asha AU is at%'), n::text);
end $x$;

insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
