-- M33d referral outcomes, rolled back: the masked view and GET /v1/referrals/{code}/outcomes. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
grant all on r to authenticated, anon;
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m33d referrals', '{referrals}', 'eb2b_m33dtest', encode(extensions.digest('eb2b_m33dtest_key_0001', 'sha256'), 'hex'));
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m33d other', '{intake}', 'eb2b_m33dothr', encode(extensions.digest('eb2b_m33dtest_key_0002', 'sha256'), 'hex'));
insert into public.student_leads (whatsapp_number, student_name, email_id, interested_course, referral_code, stage, lead_source)
values ('919876533201', 'Ref One', 'one@example.com', 'MBA', 'INF001', 'contacted', 'influencer'),
       ('919876533202', 'Ref Two', 'two@example.com', 'BBA', 'inf001', 'enrolled', 'influencer'),
       ('919876533203', 'Ref Three', 'three@example.com', 'MCA', 'INF002', 'new', 'influencer');
insert into r select 'view_masked', count(*) = 2 and bool_and(v.referral_code in ('INF001', 'inf001')) and not exists (
    select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'b2b_referral_outcomes' and c.column_name in ('whatsapp_number', 'student_name', 'email_id', 'id')),
  count(*)::text
  from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001';
insert into r select 'view_enrolled_flag', bool_or(v.enrolled and v.programme = 'BBA') and bool_or(not v.enrolled and v.stage = 'contacted'), (select jsonb_agg(to_jsonb(v))::text from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001') from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001';
insert into r select 'api_outcomes', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'outcomes') = 2 and x -> 'result' ->> 'referral_code' = 'INF001'
  and (select bool_and(length(o ->> 'lead_ref') = 12 and not (o ? 'name') and not (o ? 'phone')) from jsonb_array_elements(x -> 'result' -> 'outcomes') o)
  and (x -> 'result' ->> 'next_after')::bigint > 0, left(x::text, 400)
  from (select b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'inf001') x) y;
insert into r select 'api_paged', jsonb_array_length(x -> 'result' -> 'outcomes') = 1 and (x -> 'result' -> 'outcomes' -> 0 ->> 'programme') = 'BBA', x::text
  from (select b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'INF001', (select id from public.student_leads where whatsapp_number = '919876533201'), 10) x) y;
insert into r select 'api_wrong_scope', (b2b.api_referral_outcomes('eb2b_m33dtest_key_0002', 'INF001') ->> 'status')::int = 401, null;
insert into r select 'api_no_code', (b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', ' ') ->> 'status')::int = 400, null;
insert into r select 'api_unknown_code_empty', jsonb_array_length(b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'NOPE') -> 'result' -> 'outcomes') = 0, null;
select name, ok, detail from r order by ok, name;
rollback;
