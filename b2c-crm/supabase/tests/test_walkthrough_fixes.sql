-- The b32 fixes (Step 1 walkthrough), rolled back. Every row of the final select must say ok = true.
-- Writes only test users and test leads (phones 9100009998xx); safe on staging (SQL editor) and on a local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e301', 'tina.wt@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e302', 'raj.wt@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e303', 'mona.wt@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads) values
  ('aaaaaaaa-0000-0000-0000-00000000e301', 'tina.wt@eduwit.in', 'Tina WT', 'counsellor', true, true, false),
  ('aaaaaaaa-0000-0000-0000-00000000e302', 'raj.wt@eduwit.in', 'Raj WT', 'counsellor', true, false, false),
  ('aaaaaaaa-0000-0000-0000-00000000e303', 'mona.wt@eduwit.in', 'Mona WT', 'marketing', true, true, false);
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.wt@eduwit.in' on conflict do nothing;

create function pg_temp.lead(p_id bigint, p_lane jsonb) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'wt-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'WT Student ' || p_id, 'phone', '9100009998' || right(p_id::text, 2)), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'wt-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', p_lane), 'test');
end $f$;

do $x$
declare j jsonb; v_mine int;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(998801, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}');
  perform pg_temp.lead(998802, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["no_course"]}');
  perform pg_temp.lead(998803, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["no_course"]}');
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000e301', status = 'active' where lead_id = 998801;

  -- a test counsellor sees her test lead without asking for test leads; a real counsellor never sees test leads
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e301');
  j := b2c.lead_list('{"limit": 500}');
  insert into r (name, ok, detail) values ('test_user_sees_own_test_lead', j -> 'rows' @> '[{"lead_id": 998801}]', left(j::text, 300));
  select count(*) into v_mine from b2c.leads_state where owner_id = 'aaaaaaaa-0000-0000-0000-00000000e301';
  insert into r (name, ok, detail) values ('test_user_sees_only_own', (j ->> 'total')::int = v_mine, (j ->> 'total') || ' vs ' || v_mine);
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000e302' where lead_id = 998801;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e302');
  j := b2c.lead_list('{"limit": 500}');
  insert into r (name, ok, detail) values ('real_user_does_not_see_test_leads', not (j -> 'rows' @> '[{"lead_id": 998801}]'), left(j::text, 300));

  -- pool_list counts the matching leads, not the one aggregated row
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e303');
  j := b2c.pool_list('{"test": true, "limit": 1}');
  insert into r (name, ok, detail) values ('pool_total_counts_leads', (j ->> 'total')::int >= 2 and jsonb_array_length(j -> 'rows') = 1, left(j::text, 300));
  j := b2c.pool_list('{"test": true, "q": "no such student zz"}');
  insert into r (name, ok, detail) values ('pool_total_zero_when_empty', (j ->> 'total')::int = 0 and jsonb_array_length(j -> 'rows') = 0, j::text);

  -- a search with no digits never matches every chat
  j := b2c.inbox_list('{"search": "no such student zz"}');
  insert into r (name, ok, detail) values ('inbox_search_without_digits', jsonb_array_length(j) = 0, left(j::text, 300));

  -- programme_search: total is the number of programmes shown
  j := b2c.programme_search('{"limit": 300}');
  insert into r (name, ok, detail) values ('programme_total_matches_rows', (j ->> 'total')::int = jsonb_array_length(j -> 'rows'), (j ->> 'total') || ' vs ' || jsonb_array_length(j -> 'rows'));
  j := b2c.programme_search('{"q": "no such programme zz"}');
  insert into r (name, ok, detail) values ('programme_total_zero_when_empty', (j ->> 'total')::int = 0, j::text);
end $x$;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
