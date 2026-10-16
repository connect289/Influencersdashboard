-- Creators and agency users can never read the shared master tables, even with production's own policies in place
-- (spec 2.2, HARD STOP 3). The legacy influencer policy is reproduced in the baseline, and a portal creator is never in
-- public.influencers, so it can't apply to them.
begin;
\ir _helpers.psql
select plan(9);

select tests.make_creator('alice');
insert into public.student_leads (whatsapp_number, student_name, email_id, referral_code, stage)
values ('919812345621', 'Riya Sharma', 'riya@gmail.com', 'ALICE-IG-01', 'new');
insert into public.touchpoints (lead_id, phone, source_system, event_type, attribution)
select id, '919812345621', 'witty', 'lead.created', '{"utm_content":"ALICE-IG-01"}' from public.student_leads;

select tests.as_person('alice');
select is((select count(*)::int from public.student_leads), 0, 'creator: no rows from student_leads');
select is((select count(*)::int from public.touchpoints), 0, 'creator: no rows from touchpoints');
select throws_ok($$ select inf.setting('lead_visibility.creator') $$, '42501', null, 'creator: internal settings reader is not callable');
select throws_ok($$ select public.lead_intake('{"phone":"9812345622"}'::jsonb) $$, '42501', null, 'creator: cannot write leads through lead_intake');
select throws_ok($$ select count(*) from public.b2c_lead_status_v $$, '42501', null, 'creator: B2C status view is service-role only');
select is((select count(*)::int from public.influencers), 0, 'creator: not a legacy influencer');

-- The old CRM trigger made the creator an inactive crm_users viewer (production behaviour, risk RK-3): no access.
select tests.reset();
select is((select is_active from public.crm_users where id = (select user_id from tests.people where label = 'alice')), false,
          'creator exists in crm_users only as an inactive viewer');
select tests.as_person('alice');
select is(public.crm_role(), null, 'and has no old-CRM role');

select tests.act_as_anon();
select throws_ok($$ select count(*) from public.student_leads $$, '42501', null, 'anon: no access to student_leads');

select tests.reset();
select * from finish();
rollback;
