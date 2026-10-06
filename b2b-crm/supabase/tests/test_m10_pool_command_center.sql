-- M10a pre-routing pool and Command Center, on STAGING, rolled back. Three throwaway leads: one still chatting with
-- Witty, one form lead without a course (waits for automatic routing), one test phone. Expect total 3; groups chatting,
-- routing_off (or due when routing is on) and test; outlook b2c_nurture 2 (test leads are left out); the Command
-- Center's pool counts 2.
begin;
select public.lead_intake(jsonb_build_object('phone', '919876543281', 'source_system', 'witty', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Pool Chat', 'source', 'whatsapp_direct', 'interested_course', 'MBA')));
update public.student_leads set last_agent_message_at = now() where whatsapp_number = '919876543281';
select public.lead_intake(jsonb_build_object('phone', '919876543282', 'source_system', 'api', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Pool Form', 'source', 'website_form')));
select public.lead_intake(jsonb_build_object('phone', '919000000082', 'source_system', 'api', 'event_type', 'lead.created',
  'lead', jsonb_build_object('full_name', 'Pool Test', 'source', 'website_form', 'interested_course', 'MBA')));
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'pool-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'pool-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"pool-admin@test.local"}', true);
select b2b.pool_overview() - 'rows' as pool,
  (select jsonb_agg(jsonb_build_object('name', r ->> 'name', 'group', r ->> 'group', 'outlook', r ->> 'outlook', 'missing', r -> 'not_qualified'))
     from jsonb_array_elements(b2b.pool_overview() -> 'rows') r) rows,
  jsonb_array_length(b2b.pool_overview('chatting') -> 'rows') chatting_rows, b2b.command_center() -> 'pool' cc_pool;
rollback;
