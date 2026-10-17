-- web9: admin back end — allow-listed saves with audit, role checks, content rules, settings, dashboards. Runs on the replica too.
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;
\set actor '''00000000-0000-0000-0000-0000000000a1'''

insert into r select (public.web_admin_save('testimonials', '{"name":"Asha","quote":"Helpful counsellor","published":true}', :actor, 'ed@eduwit.in', 'content_editor')->>'error') like 'Testimonials can be published only after%', 'testimonial needs consent before publishing';
insert into v select 't', public.web_admin_save('testimonials', '{"name":"Asha","quote":"Helpful counsellor","published":true,"consent_confirmed":true,"sort":1}', :actor, 'ed@eduwit.in', 'content_editor');
insert into r select (select (val->>'ok')::boolean and val->'tags' ? 'content' from v where k = 't'), 'testimonial created; content tag to revalidate';
insert into r select exists (select 1 from public.web_audit_log where entity = 'testimonials' and action = 'create' and actor_email = 'ed@eduwit.in'), 'create audited';
insert into r select (public.web_admin_save('testimonials', jsonb_build_object('id', (select val->'row'->>'id' from v where k = 't'), 'quote', 'Very helpful', 'consent_confirmed', true, 'published', true), :actor, 'ed@eduwit.in', 'content_editor')->'row'->>'quote') = 'Very helpful', 'update keeps the same row';
insert into r select (select before->>'quote' = 'Helpful counsellor' and after->>'quote' = 'Very helpful' from public.web_audit_log where entity = 'testimonials' and action = 'update' order by id desc limit 1), 'update audited with before and after';
insert into r select (public.web_admin_save('testimonials', '{"name":"X","quote":"y"}', :actor, 'v@eduwit.in', 'viewer')->>'error') = 'forbidden', 'viewers cannot edit';
insert into r select (public.web_admin_save('legal_pages', '{"slug":"privacy-policy","title":"x"}', :actor, 'ed@eduwit.in', 'content_editor')->>'error') = 'forbidden', 'legal pages need a super admin';
insert into r select (public.web_admin_save('testimonials', '{"name":"X","quote":"y","id":1,"created_at":"2000-01-01"}', :actor, 'ed@eduwit.in', 'content_editor')->>'ok') is not null, 'unknown/non-editable columns are ignored';
insert into r select (public.web_admin_save('consent_texts', '{"version":"web-form-2026-10-v1","body":"changed"}', :actor, 'sa@eduwit.in', 'super_admin')->>'error') like 'Accepted consent texts cannot be reworded%', 'consent texts are versioned, never reworded';
insert into r select (public.web_admin_save('resources', '{"slug":"how-to-choose","title":"How to choose","status":"published"}', :actor, 'ed@eduwit.in', 'content_editor')->>'error') like 'Every guide needs%', 'guides need author and reviewer to publish';
insert into r select (public.web_admin_save('curated_views', '{"slug":"online-mba-hr","title":"Online MBA in HR","filters":{"programme":["mba"],"spec":["hr"]},"status":"draft"}', :actor, 'ed@eduwit.in', 'content_editor')->>'ok')::boolean, 'curated view draft created';
insert into r select (public.web_admin_get('curated_views', '{"slug":"online-mba-hr"}')->'filters'->'spec'->>0) = 'hr', 'get returns the row';
insert into r select jsonb_array_length(public.web_admin_list('curated_views', 'HR')->'rows') >= 1, 'list with search';
insert into r select (public.web_admin_delete('curated_views', '{"slug":"online-mba-hr"}', :actor, 'ed@eduwit.in', 'content_editor')->>'ok')::boolean, 'delete';
insert into r select exists (select 1 from public.web_audit_log where entity = 'curated_views' and action = 'delete'), 'delete audited';
insert into r select (public.web_admin_delete('authors', '{"id":1}', :actor, 'ed@eduwit.in', 'super_admin')->>'error') = 'not_deletable', 'authors cannot be deleted (bylines)';
insert into r select (public.web_admin_setting('web_advisor_enabled', 'true', :actor, 'ed@eduwit.in', 'content_editor')->>'error') = 'forbidden', 'only a super admin switches Witty on';
insert into r select (public.web_admin_setting('announcement', '{"text":"Admissions open","tone":"info"}', :actor, 'ed@eduwit.in', 'content_editor')->>'ok')::boolean, 'editors manage the announcement bar';
insert into r select (select value->>'text' from public.web_settings where key = 'announcement') = 'Admissions open', 'announcement saved';
insert into r select exists (select 1 from public.web_audit_log where entity = 'web_settings' and entity_id = 'announcement' and actor_email = 'ed@eduwit.in'), 'setting change audited';
insert into r select jsonb_typeof(public.web_admin_overview()) = 'object' and public.web_admin_overview() ? 'outbox_dead', 'overview';
insert into r select jsonb_array_length(public.web_admin_funnels(30)->'gate') = 7 and jsonb_array_length(public.web_admin_funnels(30)->'form') = 7, 'gate and form funnels';
insert into r select public.web_admin_advisor_insights(30) ? 'thumbs_down', 'advisor insights';
insert into r select public.web_admin_outbox(null, 10) ? 'counts', 'outbox monitor';
insert into r select jsonb_array_length(public.web_admin_audit(null, 5)) > 0, 'audit log readable';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
