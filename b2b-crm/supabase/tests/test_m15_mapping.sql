-- M15 mapping layer on STAGING, rolled back. Partner e2e-down (generic REST) gets a mapping through the Admin
-- functions; signed partner events go through b2b.partner_event_ingest before and after publishing. Every row of the
-- final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;

create function pg_temp.send(body jsonb) returns jsonb language plpgsql as $f$
declare ts text := floor(extract(epoch from now()))::bigint::text; sec text;
begin
  sec := b2b.partner_secret((select inbound_secret_id from b2b.partners where slug = 'e2e-down'));
  return b2b.partner_event_ingest('e2e-down', body::text, ts,
    'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || body::text, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
end $f$;

-- a lead accepted by e2e-down (highest MBA commission on staging)
do $x$
declare v_id bigint; a b2b.allocations;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876503001', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Map One', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now())));
  select id into v_id from public.student_leads where whatsapp_number = '919876503001';
  update b2b.settings set value = jsonb_set(value, '{exploration_share}', '0') where key = 'engine';
  perform b2b.route_decide(v_id, true, 'm15', 'auto');
  select * into a from b2b.allocations where lead_id = v_id and destination_type = 'partner' order by id desc limit 1;
  update b2b.allocations set status = 'pushing' where id = a.id;
  perform b2b.apply_created(a.id, 'REC-M15');
  perform b2b.accept_allocation(a.id);
  insert into t values ('lead', v_id::text), ('alloc', a.id::text), ('ref', a.reference), ('partner', a.partner_id::text);
end $x$;
insert into r select 'lead_with_partner', (select v from t where k = 'partner') = '20' and a.status = 'accepted', a.status
  from b2b.allocations a where a.id = (select v::bigint from t where k = 'alloc');

-- an event before any mapping exists: stored and held
insert into t select 'ev1', pg_temp.send(jsonb_build_object('event_id', 'm15-1', 'type', 'stage', 'reference', (select v from t where k = 'ref'),
                                                          'data', jsonb_build_object('stage', 'Attempted', 'sub_stage', 'RNR')))::text;
insert into r select 'held_without_mapping', (select v::jsonb ->> 'result' from t where k = 'ev1') like 'stored: no mapping%'
    and (select status from b2b.partner_events where event_id = 'm15-1') = 'held_unmapped'
    and (select partner_stage_raw from public.student_leads where id = (select v::bigint from t where k = 'lead')) = 'Attempted',
  (select v from t where k = 'ev1');

-- the Admin builds version 1
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b5', 'map-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000b5', 'map-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b5","role":"authenticated","aal":"aal2","email":"map-admin@test.local"}', true);
do $x$
declare d bigint; e text;
begin
  d := b2b.mapping_draft_start(20);
  insert into t values ('draft1', d::text);
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Attempted', 'partner_sub_stage', 'RNR', 'stage', 'contacted', 'sub_stage', 'no answer'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Attempted', 'stage', 'contacted'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Follow-up', 'stage', 'counselled',
    'conditions', jsonb_build_array(jsonb_build_object('field', 'counselling_done', 'op', 'eq', 'value', 'Yes'))));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Follow-up', 'stage', 'contacted'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Dead', 'stage', 'lost', 'lost_reason', 'not interested'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Junk', 'ignore', true, 'ignore_reason', 'partner housekeeping'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Admission', 'stage', 'enrolled'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Counsellor', 'canonical_key', 'counsellor_name', 'direction', 'in'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Full Name', 'canonical_key', 'full_name', 'direction', 'both'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'mx_Highest_Education', 'canonical_key', 'highest_qualification', 'direction', 'both'));
  perform b2b.mapping_rule_save('value', jsonb_build_object('profile_id', d, 'canonical_key', 'highest_qualification', 'partner_value', 'Graduate', 'canonical_value', 'bachelors'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Fee Paid', 'canonical_key', 'fee_paid_inr', 'direction', 'in',
    'transforms', '[{"op":"amount"}]'::jsonb));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Next Call', 'canonical_key', 'next_follow_up_at', 'direction', 'in',
    'transforms', '[{"op":"datetime"}]'::jsonb));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'counselling_done', 'canonical_key', 'counselling_done', 'direction', 'in',
    'transforms', '[{"op":"boolean"}]'::jsonb));
  perform b2b.mapping_rule_save('activity', jsonb_build_object('profile_id', d, 'partner_type', 'Call Log', 'partner_outcome', 'Connected', 'kind', 'call', 'outcome', 'connected'));
  perform b2b.mapping_golden_save(20, 'RNR is contacted', '{"kind":"stage","data":{"stage":"Attempted","sub_stage":"RNR"}}',
                                  '{"status":{"stage":"contacted","sub_stage":"no answer"}}');
  -- refusals
  begin perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Paid', 'stage', 'paid')); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('refuses_money_stage', e = 'choose an Eduwit stage', e);
  begin perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'X', 'canonical_key', 'city', 'transforms', '[{"op":"explode"}]'::jsonb)); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('refuses_unknown_transform', e like 'unknown transform%', e);
  begin perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'B', 'canonical_key', 'annual_budget_inr', 'direction', 'both')); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('budget_never_sent', e like '%never sent to partners', e);
  begin perform b2b.mapping_rule_save('value', jsonb_build_object('profile_id', d, 'canonical_key', 'highest_qualification', 'partner_value', 'PG', 'canonical_value', 'Postgrad')); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('value_must_be_canonical', e like 'choose one of the Eduwit values%', e);
  -- a failing golden file blocks publishing
  perform b2b.mapping_golden_save(20, 'wrong on purpose', '{"kind":"stage","data":{"stage":"Attempted","sub_stage":"RNR"}}', '{"status":{"stage":"enrolled"}}');
  begin perform b2b.mapping_publish(d, 'first version'); e := 'published';
  exception when others then e := sqlerrm; end;
  insert into r values ('golden_blocks_publish', e like 'golden files fail: wrong on purpose%', e);
  perform b2b.mapping_golden_archive((select id from b2b.mapping_goldens where partner_id = 20 and name = 'wrong on purpose'));
  insert into t select 'pub1', b2b.mapping_publish(d, 'first version')::text;
end $x$;
reset role;

insert into r select 'publish_reprocesses_held', (x ->> 'version')::int = 1 and (x -> 'reprocess' ->> 'applied')::int >= 1
    and (select stage || '/' || sub_stage from public.student_leads where id = (select v::bigint from t where k = 'lead')) = 'contacted/no answer', x::text
  from (select v::jsonb x from t where k = 'pub1') y;

-- events after publishing
select pg_temp.send(jsonb_build_object('event_id', 'm15-2', 'type', 'stage', 'reference', (select v from t where k = 'ref'),
  'data', jsonb_build_object('stage', 'Follow-up', 'fields', jsonb_build_object('counselling_done', 'Yes', 'Counsellor', 'Priya', 'Fee Paid', '2.5 L',
                                                                                'Next Call', '07/10/2026 11:00', 'mx_Lead_Quality', 'A'))));
insert into r select 'conditional_stage_and_fields', l.stage = 'counselled' and l.fee_paid_inr = 250000 and l.next_task_due_at = '2026-10-07 11:00+05:30'
    and a.partner_fields ->> 'counsellor_name' = 'Priya' and a.partner_fields ->> 'counselling_done' = 'true' and a.partner_custom ->> 'mx_Lead_Quality' = 'A'
    and a.mapping_version = 1, l.stage || ' ' || l.fee_paid_inr || ' ' || a.partner_fields::text
  from public.student_leads l join b2b.allocations a on a.id = l.allocation_id where l.id = (select v::bigint from t where k = 'lead');
insert into r select 'custom_field_queued', count(*) = 1 and bool_and(q.status = 'open' and q.lead_ids @> array[(select v::bigint from t where k = 'lead')]), count(*)::text
  from b2b.mapping_queue q where q.partner_id = 20 and q.kind = 'field' and q.item = 'mx_Lead_Quality';

select pg_temp.send(jsonb_build_object('event_id', 'm15-3', 'type', 'stage', 'reference', (select v from t where k = 'ref'), 'data', jsonb_build_object('stage', 'Attempted')));
insert into r select 'never_backwards', l.stage = 'counselled' and e.result like 'stored: not moved back%', e.result
  from public.student_leads l, b2b.partner_events e where l.id = (select v::bigint from t where k = 'lead') and e.event_id = 'm15-3';

select pg_temp.send(jsonb_build_object('event_id', 'm15-4', 'type', 'stage', 'reference', (select v from t where k = 'ref'), 'data', jsonb_build_object('stage', 'Brand New Stage')));
insert into r select 'unknown_stage_held', e.status = 'held_unmapped' and l.stage = 'counselled'
    and exists (select 1 from b2b.mapping_queue q where q.partner_id = 20 and q.kind = 'stage' and q.item = 'Brand New Stage')
    and exists (select 1 from b2b.events v where v.type = 'alert.mapping_unmapped' and v.partner_id = 20), e.status
  from b2b.partner_events e, public.student_leads l where e.event_id = 'm15-4' and l.id = (select v::bigint from t where k = 'lead');

select pg_temp.send(jsonb_build_object('event_id', 'm15-5', 'type', 'update', 'reference', (select v from t where k = 'ref'),
  'data', jsonb_build_object('fields', jsonb_build_object('mx_Highest_Education', 'Graduate'))));
select pg_temp.send(jsonb_build_object('event_id', 'm15-6', 'type', 'update', 'reference', (select v from t where k = 'ref'),
  'data', jsonb_build_object('fields', jsonb_build_object('mx_Highest_Education', 'Doctor of Something'))));
insert into r select 'value_map_and_unmapped_value', a.partner_fields ->> 'highest_qualification' = 'Bachelors'
    and exists (select 1 from b2b.mapping_queue q where q.partner_id = 20 and q.kind = 'value' and q.item = 'highest_qualification = Doctor of Something')
    and (select highest_qualification from public.student_leads where id = a.lead_id) is distinct from 'Bachelors',   -- not trusted: Witty's field untouched
  a.partner_fields ->> 'highest_qualification'
  from b2b.allocations a where a.id = (select v::bigint from t where k = 'alloc');

select pg_temp.send(jsonb_build_object('event_id', 'm15-7', 'type', 'activity', 'reference', (select v from t where k = 'ref'), 'occurred_at', now(),
  'data', jsonb_build_object('type', 'Call Log', 'outcome', 'Connected')));
select pg_temp.send(jsonb_build_object('event_id', 'm15-8', 'type', 'activity', 'reference', (select v from t where k = 'ref'), 'data', jsonb_build_object('type', 'SMS')));
insert into r select 'activity_mapped_and_held', l.contact_attempts >= 1
    and exists (select 1 from b2b.events v where v.type = 'partner.activity' and v.lead_id = l.id and v.payload ->> 'kind' = 'call' and v.payload ->> 'outcome' = 'connected')
    and (select status from b2b.partner_events where event_id = 'm15-8') = 'held_unmapped', coalesce(l.contact_attempts, 0)::text
  from public.student_leads l where l.id = (select v::bigint from t where k = 'lead');

select pg_temp.send(jsonb_build_object('event_id', 'm15-9', 'type', 'stage', 'reference', (select v from t where k = 'ref'), 'data', jsonb_build_object('stage', 'Junk')));
insert into r select 'ignored_stage', status = 'ignored' and result like 'ignored stage: partner housekeeping', result from b2b.partner_events where event_id = 'm15-9';
insert into r select 'stage_event_published', count(*) >= 2, count(*)::text from b2b.events
 where type = 'partner.stage_applied' and lead_id = (select v::bigint from t where k = 'lead');

-- outbound: the push carries the partner's field names and the version
insert into r select 'push_carries_fields', p -> 'fields' ->> 'Full Name' = 'Map One' and (p ->> 'mapping_version')::int = 1 and p ? 'student', (p -> 'fields')::text
  from (select b2b.push_payload(a) p from b2b.allocations a where a.id = (select v::bigint from t where k = 'alloc')) y;

-- coverage before completion, then version 2 and the go-live gate
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b5","role":"authenticated","aal":"aal2","email":"map-admin@test.local"}', true);
do $x$
declare c jsonb; d bigint; d2 bigint; x jsonb; o jsonb; n1 int; n2 int; e text;
begin
  c := b2b.mapping_studio(20) -> 'editing' -> 'coverage';   -- no draft yet: the active version
  insert into r values ('coverage_incomplete', (c ->> 'required_done')::int < (c ->> 'required_total')::int and not b2b.mapping_ready(20)
    and exists (select 1 from jsonb_array_elements(c -> 'items') i where i ->> 'item' = 'Brand New Stage' and not (i ->> 'done')::boolean),
    (c ->> 'required_done') || '/' || (c ->> 'required_total'));
  o := b2b.mapping_test_out((select id from b2b.mapping_profiles where partner_id = 20 and status = 'active'), (select v::bigint from t where k = 'lead'));
  insert into r values ('roundtrip', exists (select 1 from jsonb_array_elements(o -> 'roundtrip' -> 'checks') k where k ->> 'key' = 'full_name' and (k ->> 'pass')::boolean),
    (o -> 'roundtrip' -> 'checks')::text);
  x := b2b.mapping_test((select id from b2b.mapping_profiles where partner_id = 20 and status = 'active'), 'stage', '{"stage":"attempted","sub_stage":"rnr"}');
  insert into r values ('test_panel_case_insensitive', x -> 'status' ->> 'sub_stage' = 'no answer', x::text);

  d := b2b.mapping_draft_start(20);
  insert into r values ('draft_copies_active', (select count(*) from b2b.status_rules where profile_id = d) = 7, d::text);
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Brand New Stage', 'stage', 'counselled'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'canonical_key', k, 'direction', 'in', 'not_available', true))
     from unnest(array['call_outcome', 'application_status', 'enrollment_date']) k;
  -- removing a rule makes a new draft without it (the Junk rule)
  n1 := (select count(*) from b2b.status_rules where profile_id = d);
  d2 := b2b.mapping_rule_remove('status', (select id from b2b.status_rules where profile_id = d and partner_stage = 'Junk'));
  n2 := (select count(*) from b2b.status_rules where profile_id = d2);
  insert into r values ('rule_remove_makes_new_draft', n2 = n1 - 1 and (select status from b2b.mapping_profiles where id = d) = 'retired'
    and (select status from b2b.mapping_profiles where id = d2) = 'draft', n1 || ' → ' || n2);
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d2, 'partner_stage', 'Junk', 'ignore', true, 'ignore_reason', 'partner housekeeping'));
  x := b2b.mapping_publish(d2, 'new stage and N/A sales fields');
  insert into t values ('pub2', x::text);
  insert into r values ('v2_resolves_queue', (x ->> 'version')::int = 2 and (x ->> 'queue_resolved')::int >= 1
    and (select status from b2b.mapping_queue where partner_id = 20 and kind = 'stage' and item = 'Brand New Stage') = 'mapped'
    and (select status from b2b.partner_events where event_id = 'm15-4') = 'applied', x::text);
  c := b2b.mapping_studio(20) -> 'editing' -> 'coverage';
  insert into r values ('go_live_gate', b2b.mapping_ready(20), (c ->> 'required_done') || '/' || (c ->> 'required_total'));
end $x$;
reset role;
-- the partner page's checklist (read through partner_json, which signed-in users cannot query directly)
insert into r select 'checklist_mapping_done', (i ->> 'done')::boolean and (i ->> 'available')::boolean, i::text
  from jsonb_array_elements(b2b.partner_checklist((select p from b2b.partners p where id = 20))) i where i ->> 'key' = 'mapping';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b5","role":"authenticated","aal":"aal2","email":"map-admin@test.local"}', true);
do $x$
declare v_d bigint; x jsonb; e text;
begin
  -- discard a draft; restore version 1 as version 3
  v_d := b2b.mapping_draft_start(20);
  perform b2b.mapping_draft_discard(v_d);
  insert into r values ('discard_draft', not exists (select 1 from b2b.mapping_profiles where partner_id = 20 and status = 'draft')
    and (select jsonb_array_length(b2b.mapping_studio(20) -> 'profiles')) = 2, null);
  x := b2b.mapping_restore((select id from b2b.mapping_profiles where partner_id = 20 and version = 1), 'v2 was wrong');
  insert into r values ('restore_as_new_version', (x ->> 'version')::int = 3
    and (select count(*) from b2b.status_rules s join b2b.mapping_profiles p on p.id = s.profile_id where p.partner_id = 20 and p.status = 'active') = 7, x::text);
  begin perform b2b.mapping_restore((select id from b2b.mapping_profiles where partner_id = 20 and status = 'active'), 'nope'); e := 'restored';
  exception when others then e := sqlerrm; end;
  insert into r values ('restore_only_earlier', e = 'only an earlier version can be restored', e);

  -- schema snapshots and drift
  perform b2b.mapping_snapshot_save(20, 'upload', '{"fields":[{"name":"Counsellor","type":"text"},{"name":"Full Name","type":"text"},{"name":"mx_Highest_Education","type":"picklist","values":["Graduate","Post Graduate"]}],"stages":[{"stage":"Attempted","sub_stages":["RNR"]}]}');
  x := b2b.mapping_snapshot_save(20, 'upload', '{"fields":[{"name":"Counsellor","type":"number"},{"name":"mx_Highest_Education","type":"picklist","values":["Graduate"]}],"stages":[{"stage":"Attempted"},{"stage":"Hot"}]}');
  insert into r values ('drift_detected',
    exists (select 1 from jsonb_array_elements(x -> 'drift') d where d ->> 'what' = 'removed_field' and d ->> 'item' = 'Full Name' and (d ->> 'required')::boolean)
    and exists (select 1 from jsonb_array_elements(x -> 'drift') d where d ->> 'what' = 'new_stage' and d ->> 'item' = 'Hot')
    and exists (select 1 from jsonb_array_elements(x -> 'drift') d where d ->> 'what' = 'type_changed' and d ->> 'item' = 'Counsellor')
    and exists (select 1 from jsonb_array_elements(x -> 'drift') d where d ->> 'what' = 'removed_value' and d ->> 'detail' = 'Post Graduate')
    and exists (select 1 from b2b.events v where v.type = 'alert.mapping_drift' and v.partner_id = 20), jsonb_array_length(x -> 'drift')::text);
  x := b2b.mapping_discover(20);
  insert into r values ('discover_from_events', exists (select 1 from jsonb_array_elements(x -> 'stages') s where s ->> 'stage' = 'Follow-up')
    and exists (select 1 from jsonb_array_elements(x -> 'fields') f where f ->> 'name' = 'Fee Paid'), left(x::text, 200));
  x := b2b.mapping_studio(20);
  insert into r values ('studio_read', x -> 'editing' ->> 'status' = 'active' and jsonb_array_length(x -> 'queue') >= 3 and jsonb_array_length(x -> 'canonical') > 40
    and (x -> 'editing' -> 'goldens' -> 0 ->> 'pass')::boolean, null);
  x := b2b.mapping_overview();
  insert into r values ('overview', exists (select 1 from jsonb_array_elements(x) p where (p ->> 'id')::int = 20 and (p ->> 'active_version')::int = 3), null);
end $x$;
reset role;

-- backfill after a correction: the lead's stored partner stage maps to a different Eduwit stage
update public.student_leads set stage = 'contacted', partner_stage_raw = 'Admission', partner_sub_stage_raw = null where id = (select v::bigint from t where k = 'lead');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b5","role":"authenticated","aal":"aal2","email":"map-admin@test.local"}', true);
do $x$
declare x jsonb; n int;
begin
  x := b2b.mapping_backfill_preview(20);
  n := b2b.mapping_backfill(20, 'corrected Admission mapping');
  insert into r values ('backfill', (x ->> 'count')::int >= 1 and n = (x ->> 'count')::int
    and exists (select 1 from jsonb_array_elements(x -> 'sample') s where (s ->> 'lead_id')::bigint = (select v::bigint from t where k = 'lead') and s ->> 'new_stage' = 'enrolled'),
    left(x::text, 200));
end $x$;
reset role;
insert into r select 'backfill_applied', stage = 'enrolled', stage from public.student_leads where id = (select v::bigint from t where k = 'lead');

-- a mapped lost stage hands the lead to B2C nurture
update public.student_leads set stage = 'counselled' where id = (select v::bigint from t where k = 'lead');
select pg_temp.send(jsonb_build_object('event_id', 'm15-10', 'type', 'stage', 'reference', (select v from t where k = 'ref'), 'data', jsonb_build_object('stage', 'Dead')));
insert into r select 'lost_to_b2c_nurture', l.destination_type = 'in_house' and n.b2c_lane = 'nurture' and n.reason = 'partner_lost'
    and (select outcome from b2b.allocations where id = (select v::bigint from t where k = 'alloc')) = 'lost', n.reason
  from public.student_leads l join b2b.allocations n on n.id = l.allocation_id where l.id = (select v::bigint from t where k = 'lead');

-- engine functions are not callable by signed-in users or anon
insert into r select 'engine_locked', not has_function_privilege('authenticated', 'b2b.mapping_in(bigint, text, jsonb)', 'execute')
    and not has_function_privilege('anon', 'b2b.partner_event_apply(bigint)', 'execute')
    and not has_function_privilege('anon', 'b2b.mapping_studio(bigint)', 'execute'), null;

select name, ok, left(detail, 220) detail from r order by ok, name;
rollback;
