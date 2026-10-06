-- M11a lead editing and paged export, on STAGING, rolled back. Adds 250 throwaway leads plus one Witty lead, edits it
-- (only real changes are kept; validation refuses a bad email, emptying, a system field, a score above 100 and a
-- missing reason), lets Witty write the name again (the history shows the correction as overwritten), then exports
-- everything 100 rows a page and checks every lead arrives once, masking, the export log and that a finished export
-- cannot be read again. Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (lead_id bigint, expect int);
grant all on r, t to authenticated;
select public.lead_intake(jsonb_build_object('phone', '91987650' || lpad(g::text, 4, '0'), 'source_system', 'api', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Export ' || g, 'source', 'website_form', 'email', 'x' || g || '@example.com'))) from generate_series(1, 250) g;
select public.lead_intake(jsonb_build_object('phone', '919876509999', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Edit Me', 'source', 'whatsapp_direct', 'interested_course', 'MBA', 'academic_score_pct', 60)));
insert into t select (select id from public.student_leads where whatsapp_number = '919876509999'),
                     (select count(*) from public.student_leads l where l.deleted_at is null and l.merged_into_id is null);
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'edit-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'edit-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"edit-admin@test.local"}', true);
do $t$
declare v_id bigint := (select lead_id from t); j jsonb;
begin
  j := b2b.lead_edit(v_id, '{"student_name":"Edit Me Correct","email_id":"Edit.Me@Example.com","academic_score_pct":"60.0","interested_course":"MBA","lead_status":"warm"}', 'name and email from the call');
  insert into r values ('edit_changes_only_real', jsonb_array_length(j -> 'changed') = 3, j::text);
  begin perform b2b.lead_edit(v_id, '{"email_id":"nope"}', 'test'); insert into r values ('bad_email', false, 'ran');
  exception when others then insert into r values ('bad_email', sqlerrm like '%not valid%', sqlerrm); end;
  begin perform b2b.lead_edit(v_id, '{"student_name":""}', 'test'); insert into r values ('no_clearing', false, 'ran');
  exception when others then insert into r values ('no_clearing', sqlerrm like '%cannot be emptied%', sqlerrm); end;
  begin perform b2b.lead_edit(v_id, '{"destination_type":"partner"}', 'test'); insert into r values ('field_refused', false, 'ran');
  exception when others then insert into r values ('field_refused', sqlerrm like '%cannot be edited%', sqlerrm); end;
  begin perform b2b.lead_edit(v_id, '{"academic_score_pct":"140"}', 'test'); insert into r values ('score_range', false, 'ran');
  exception when others then insert into r values ('score_range', sqlerrm like '%percentage%', sqlerrm); end;
  begin perform b2b.lead_edit(v_id, '{"student_name":"X Y"}', ''); insert into r values ('reason_needed', false, 'ran');
  exception when others then insert into r values ('reason_needed', sqlerrm like '%say why%', sqlerrm); end;
end $t$;
reset role;
insert into r select 'edit_applied', l.student_name = 'Edit Me Correct' and l.email_id = 'edit.me@example.com' and l.lead_status = 'WARM' and l.updated_by = 'crm', l.updated_by
  from public.student_leads l where l.id = (select lead_id from t);
insert into r select 'history_rows', count(*) = 3, string_agg(field || ':' || coalesce(old_value, '-') || '>' || new_value, ' ') from b2b.lead_edits where lead_id = (select lead_id from t);
insert into r select 'event_logged', count(*) = 1, null from b2b.events where type = 'lead.edited' and lead_id = (select lead_id from t);
select public.lead_intake(jsonb_build_object('phone', '919876509999', 'source_system', 'witty', 'event_type', 'chat.turn', 'lead', jsonb_build_object('full_name', 'Edit Me')));
set local role authenticated;
do $t$
declare v_id bigint := (select lead_id from t); expect int := (select t.expect from t); h jsonb; ex bigint; nxt jsonb; pages int := 0; ids bigint[] := '{}'; pg jsonb;
begin
  h := b2b.lead_edit_history(v_id);
  insert into r select 'overwrite_shown', bool_or((e ->> 'field') = 'student_name' and (e ->> 'overwritten')::boolean and e ->> 'updated_by' = 'witty')
     and not bool_or((e ->> 'field') = 'email_id' and (e ->> 'overwritten')::boolean), h::text from jsonb_array_elements(h) e;
  ex := b2b.leads_export_start('{"include_test": true, "masked": true}');
  loop
    pg := b2b.leads_export_page(ex, nxt, 100);
    pages := pages + 1;
    ids := ids || array(select (x ->> 'id')::bigint from jsonb_array_elements(pg -> 'rows') x);
    nxt := pg -> 'next';
    exit when nxt is null or jsonb_typeof(nxt) = 'null' or pages > 50;
  end loop;
  insert into r values ('export_all_rows', cardinality(ids) = expect and (select count(distinct u) from unnest(ids) u) = expect,
                        format('%s rows, %s pages, expected %s', cardinality(ids), pages, expect));
  insert into r select 'export_masked', bool_and(x ->> 'phone' like '******%' and x ->> 'email' like '_***@%'), min(x ->> 'email')
    from jsonb_array_elements(b2b.leads_export_page(b2b.leads_export_start('{"q":"Export 1", "masked": true}'), null, 100) -> 'rows') x;
  insert into r select 'export_logged', status = 'done' and row_count = expect, status || ' ' || row_count from b2b.lead_exports where id = ex;
  begin perform b2b.leads_export_page(ex, null, 100); insert into r values ('closed_export_refused', false, 'ran');
  exception when others then insert into r values ('closed_export_refused', sqlerrm like '%closed%', sqlerrm); end;
end $t$;
reset role;
select name, ok, left(detail, 250) detail from r order by ok, name;
rollback;
