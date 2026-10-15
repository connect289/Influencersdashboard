-- M33b lead workspace, rolled back: tags (save, bulk tag / untag, filter, facet, column), notes (add, pin, update,
-- remove), duplicate candidates (same email, recorded number, name and city; dismissal) and the merge (fills, contacts,
-- notes, tags, secondary interest, merged_into_id, B2C release, the refusals). Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f1","role":"authenticated","aal":"aal2","email":"m33b-admin@test.local"}', true) $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
create function pg_temp.lead(p_phone text, p_name text, p_email text, p_city text, p_course text default 'MBA') returns bigint language sql as $f$
  select (b2b.intake_lead(jsonb_strip_nulls(jsonb_build_object('full_name', p_name, 'phone', p_phone, 'email', p_email, 'city', p_city, 'course', p_course)),
                          jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id')::bigint $f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'm33b-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'm33b-admin@test.local');

select pg_temp.set('A', pg_temp.lead('919876533001', 'Aarav Mehta', 'aarav@example.com', 'Pune')::text);
select pg_temp.set('B', pg_temp.lead('919876533002', 'Aarav Mehta', 'aarav@example.com', 'Pune', 'MCA')::text);
select pg_temp.set('C', pg_temp.lead('919876533003', 'Diya Shah', null, 'Surat')::text);
select pg_temp.set('D', pg_temp.lead('919876533004', 'Diya Shah', null, 'Surat')::text);
select pg_temp.set('E', pg_temp.lead('919876533005', 'Kabir Rao', 'kabir@example.com', 'Delhi')::text);
update public.student_leads set alternate_phone = '919876533005' where id = pg_temp.v('C')::bigint;

set local role authenticated;
select pg_temp.admin();
-- ---------- tags ----------
do $x$ declare x jsonb; e text; begin
  x := b2b.tag_save('{"name": "Priority", "color": "red"}');
  insert into r values ('tag_saved', x ->> 'name' = 'Priority' and x ->> 'color' = 'red', x::text);
  e := pg_temp.err($q$select b2b.tag_save('{"name": "priority"}')$q$);
  insert into r values ('tag_name_unique_ci', e like '22023 a tag with this name exists%', e);
  x := b2b.leads_tag(array[pg_temp.v('A')::bigint, pg_temp.v('B')::bigint, pg_temp.v('C')::bigint], 'priority');
  insert into r values ('bulk_tag_existing_name', (x ->> 'changed')::int = 3 and x ->> 'tag' = 'priority', x::text);
  x := b2b.leads_tag(array[pg_temp.v('A')::bigint, pg_temp.v('A')::bigint], 'Call back');
  insert into r values ('bulk_tag_creates', (x ->> 'changed')::int = 1 and exists (select 1 from b2b.tags where name = 'Call back'), x::text);
  x := b2b.leads_tag(array[pg_temp.v('C')::bigint], 'Priority', false);
  insert into r values ('bulk_untag', (x ->> 'changed')::int = 1, x::text);
  insert into r values ('tags_of', (select jsonb_array_length(b2b.lead_tags_of(pg_temp.v('A')::bigint))) = 2, b2b.lead_tags_of(pg_temp.v('A')::bigint)::text);
  insert into r values ('tag_events', (select count(*) from b2b.events where type = 'lead.tagged') = 4 and (select count(*) from b2b.events where type = 'lead.untagged') = 1, null);
  x := b2b.leads_list('{"tags": ["priority"]}');
  insert into r values ('tag_filter', (x ->> 'total')::int = 2 and (select bool_and(z -> 'tags' ? 'Priority') from jsonb_array_elements(x -> 'rows') z), left(x::text, 200));
  x := b2b.leads_facets('{}');
  insert into r values ('tag_facet', (x -> 'tags' ->> 'Priority')::int = 2 and (x -> 'tags' ->> 'Call back')::int = 1, (x -> 'tags')::text);
  insert into r values ('tags_list', (select bool_or((z ->> 'name') = 'Priority' and (z ->> 'leads')::int = 2) from jsonb_array_elements(b2b.tags_list()) z), b2b.tags_list()::text);
  insert into r values ('tag_retire', b2b.tag_retire((select id from b2b.tags where name = 'Call back')), null);
  insert into r values ('tag_retired_lists', jsonb_array_length(b2b.tags_list()) = 1 and jsonb_array_length(b2b.tags_list(true)) = 2, null);
  insert into r values ('retired_tag_hidden_from_lead', jsonb_array_length(b2b.lead_tags_of(pg_temp.v('A')::bigint)) = 1, null);
end $x$;

-- ---------- notes ----------
do $x$ declare x jsonb; n1 bigint; n2 bigint; e text; begin
  n1 := (b2b.lead_note_add(pg_temp.v('A')::bigint, '  Called twice, wants EMI details  ') ->> 'id')::bigint;
  n2 := (b2b.lead_note_add(pg_temp.v('A')::bigint, 'Father decides; call after 7 pm', true) ->> 'id')::bigint;
  e := pg_temp.err(format($q$select b2b.lead_note_add(%s, '   ')$q$, pg_temp.v('A')));
  insert into r values ('note_needs_text', e like '22023 write something%', e);
  x := b2b.lead_notes_list(pg_temp.v('A')::bigint);
  insert into r values ('notes_pinned_first', jsonb_array_length(x) = 2 and (x -> 0 ->> 'id')::bigint = n2 and (x -> 0 ->> 'pinned')::boolean
                        and x -> 1 ->> 'body' = 'Called twice, wants EMI details' and x -> 0 ->> 'author' = 'm33b-admin@test.local' and (x -> 0 ->> 'mine')::boolean, x::text);
  x := b2b.lead_note_update(n1, '{"pinned": true, "body": "Called twice; wants EMI details (updated)"}');
  insert into r values ('note_updated', (select body = 'Called twice; wants EMI details (updated)' and pinned from b2b.lead_notes where id = n1), null);
  insert into r values ('note_removed', b2b.lead_note_remove(n2), null);
  insert into r values ('note_removed_once', jsonb_array_length(b2b.lead_notes_list(pg_temp.v('A')::bigint)) = 1, null);
  insert into r values ('note_remove_twice_false', not b2b.lead_note_remove(n2), null);
  insert into r values ('note_events', (select count(*) from b2b.events where type in ('lead.note_added', 'lead.note_updated', 'lead.note_removed') and lead_id = pg_temp.v('A')::bigint) = 4, null);
end $x$;

-- ---------- duplicates ----------
do $x$ declare x jsonb; begin
  x := b2b.lead_duplicates();
  insert into r values ('dup_same_email', exists (select 1 from jsonb_array_elements(x) p where (p -> 'a' ->> 'id')::bigint = pg_temp.v('A')::bigint and (p -> 'b' ->> 'id')::bigint = pg_temp.v('B')::bigint
                                                    and p ->> 'why' = 'same email, same name and city'), x::text);
  insert into r values ('dup_name_city', exists (select 1 from jsonb_array_elements(x) p where (p -> 'a' ->> 'id')::bigint = pg_temp.v('C')::bigint and (p -> 'b' ->> 'id')::bigint = pg_temp.v('D')::bigint
                                                    and p ->> 'why' = 'same name and city'), null);
  insert into r values ('dup_recorded_number', exists (select 1 from jsonb_array_elements(x) p where (p -> 'a' ->> 'id')::bigint = pg_temp.v('C')::bigint and (p -> 'b' ->> 'id')::bigint = pg_temp.v('E')::bigint
                                                    and p ->> 'why' = 'same phone number'), null);
  insert into r values ('dup_count', jsonb_array_length(x) = 3, jsonb_array_length(x)::text);
  perform b2b.lead_duplicate_dismiss(pg_temp.v('E')::bigint, pg_temp.v('C')::bigint, 'father and son');
  insert into r values ('dup_dismissed', jsonb_array_length(b2b.lead_duplicates()) = 2
                        and exists (select 1 from b2b.duplicate_dismissals where lead_a = pg_temp.v('C')::bigint and lead_b = pg_temp.v('E')::bigint), null);
end $x$;

-- ---------- merge ----------
reset role;
update public.student_leads set state = null, email_id = null where id = pg_temp.v('A')::bigint;
update public.student_leads set state = 'Maharashtra', interested_specialization = 'Data Science' where id = pg_temp.v('B')::bigint;
set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; e text; a bigint := pg_temp.v('A')::bigint; b bigint := pg_temp.v('B')::bigint; l public.student_leads; begin
  e := pg_temp.err(format($q$select b2b.lead_merge(%s, %s, 'x')$q$, a, b));
  insert into r values ('merge_needs_reason', e like '22023 a reason is required%', e);
  e := pg_temp.err(format($q$select b2b.lead_merge(%s, %s, 'same person')$q$, a, a));
  insert into r values ('merge_two_leads', e like '22023 choose two different leads%', e);
end $x$;
-- with a partner: refused (the allocation is written as the engine would, outside the Admin role)
reset role;
insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, reason) values (pg_temp.v('B')::bigint, 1, 'partner', 20, 'accepted', 'commission_first', null);
update public.student_leads set allocation_id = (select max(id) from b2b.allocations where lead_id = pg_temp.v('B')::bigint), destination_type = 'partner', partner_id = 20 where id = pg_temp.v('B')::bigint;
set local role authenticated;
select pg_temp.admin();
insert into r select 'merge_refused_with_partner', e like '22023 the lead to merge is with a partner%', e
  from (select pg_temp.err(format($q$select b2b.lead_merge(%s, %s, 'same person')$q$, pg_temp.v('A'), pg_temp.v('B'))) e) y;
reset role;
update b2b.allocations set status = 'closed', outcome = 'lost' where lead_id = pg_temp.v('B')::bigint;
update public.student_leads set destination_type = null, partner_id = null, allocation_id = null where id = pg_temp.v('B')::bigint;
set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; begin
  x := b2b.lead_merge(pg_temp.v('A')::bigint, pg_temp.v('B')::bigint, 'same student, two numbers');
  perform pg_temp.set('MX', x::text);
end $x$;
insert into r select 'merge_once', e like '22023 the lead to merge is deleted, merged or erased%', e
  from (select pg_temp.err(format($q$select b2b.lead_merge(%s, %s, 'again')$q$, pg_temp.v('A'), pg_temp.v('B'))) e) y;
insert into r select 'merge_hidden_from_list', not exists (select 1 from jsonb_array_elements(b2b.leads_list('{"q": "919876533002"}') -> 'rows') z where (z ->> 'id')::bigint = pg_temp.v('B')::bigint), null;
insert into r select 'merge_duplicates_cleared', not exists (select 1 from jsonb_array_elements(b2b.lead_duplicates()) p where (p -> 'b' ->> 'id')::bigint = pg_temp.v('B')::bigint), null;
reset role;
insert into r select 'merge_filled', (x ->> 'kept')::bigint = l.id and (x ->> 'merged')::bigint = pg_temp.v('B')::bigint and (x -> 'filled') @> '["email_id", "state"]'
                     and l.email_id = 'aarav@example.com' and l.state = 'Maharashtra' and l.interested_course = 'MBA' and l.city = 'Pune', x::text
  from (select pg_temp.v('MX')::jsonb x) y, public.student_leads l where l.id = pg_temp.v('A')::bigint;
insert into r select 'merge_contacts', exists (select 1 from b2b.lead_contacts c where c.lead_id = l.id and c.kind = 'phone' and c.value = '919876533002' and c.origin = 'admin')
                     and l.alternate_phone = '919876533002', coalesce(l.alternate_phone, '-')
  from public.student_leads l where l.id = pg_temp.v('A')::bigint;
insert into r select 'merge_tags_moved', (select count(*) from b2b.lead_tags where lead_id = pg_temp.v('A')::bigint) = 2, null;
insert into r select 'merge_interest', exists (select 1 from b2b.lead_interests i where i.lead_id = pg_temp.v('A')::bigint and lower(i.course_text) = 'mca' and i.removed_at is null), null;
insert into r select 'merge_marked', (select merged_into_id = pg_temp.v('A')::bigint and deleted_at is not null from public.student_leads where id = pg_temp.v('B')::bigint), null;
insert into r select 'merge_events', exists (select 1 from b2b.events where type = 'lead.merged' and lead_id = pg_temp.v('A')::bigint) and exists (select 1 from b2b.events where type = 'lead.merged_into' and lead_id = pg_temp.v('B')::bigint), null;
reset role;
-- a new enquiry on the merged number joins the kept lead (m32b contact matching)
insert into r select 'merged_number_rejoins', (x ->> 'lead_id')::bigint = pg_temp.v('A')::bigint, x::text
  from (select b2b.intake_lead('{"full_name":"Aarav Mehta","phone":"919876533002","course":"MBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) x) y;

select name, ok, detail from r order by ok, name;
rollback;
