-- M33d and M34d referral outcomes, rolled back: the masked view, and GET /v1/referrals/{code}/outcomes, which answers only
-- for the codes its key is linked to, with keyed lead references and opaque cursors (m34d). Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
-- keys: linked to INF001, to the prefix INF*, to nothing, and one without the referrals scope
insert into b2b.api_keys (name, scopes, key_prefix, key_hash, referral_codes) values
  ('m33d referrals', '{referrals}', 'eb2b_m33dtest', encode(extensions.digest('eb2b_m33dtest_key_0001', 'sha256'), 'hex'), '{INF001}'),
  ('m33d other', '{intake}', 'eb2b_m33dothr', encode(extensions.digest('eb2b_m33dtest_key_0002', 'sha256'), 'hex'), '{}'),
  ('m34d prefix', '{referrals}', 'eb2b_m34dpref', encode(extensions.digest('eb2b_m34dtest_key_0003', 'sha256'), 'hex'), '{INF*}'),
  ('m34d unlinked', '{referrals}', 'eb2b_m34dnone', encode(extensions.digest('eb2b_m34dtest_key_0004', 'sha256'), 'hex'), '{}');
insert into public.student_leads (whatsapp_number, student_name, email_id, interested_course, referral_code, stage, lead_source)
values ('919876533201', 'Ref One', 'one@example.com', 'MBA', 'INF001', 'contacted', 'influencer'),
       ('919876533202', 'Ref Two', 'two@example.com', 'BBA', 'inf001', 'enrolled', 'influencer'),
       ('919876533203', 'Ref Three', 'three@example.com', 'MCA', 'INF002', 'new', 'influencer');
insert into t select 'L1', id::text from public.student_leads where whatsapp_number = '919876533201';
insert into t select 'L2', id::text from public.student_leads where whatsapp_number = '919876533202';

-- ---------- the view (unchanged) ----------
insert into r select 'view_masked', count(*) = 2 and bool_and(v.referral_code in ('INF001', 'inf001')) and not exists (
    select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'b2b_referral_outcomes' and c.column_name in ('whatsapp_number', 'student_name', 'email_id', 'id')),
  count(*)::text
  from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001';
insert into r select 'view_enrolled_flag', bool_or(v.enrolled and v.programme = 'BBA') and bool_or(not v.enrolled and v.stage = 'contacted'), (select jsonb_agg(to_jsonb(v))::text from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001') from public.b2b_referral_outcomes v where upper(v.referral_code) = 'INF001';

-- ---------- the API: the key's own codes, keyed references, opaque cursors ----------
insert into t select 'P1', b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'inf001')::text;
insert into r select 'api_outcomes', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'outcomes') = 2 and x -> 'result' ->> 'referral_code' = 'INF001'
  and (select bool_and((o ->> 'lead_ref') ~ '^[0-9a-f]{12}$' and not (o ? 'name') and not (o ? 'phone')) from jsonb_array_elements(x -> 'result' -> 'outcomes') o),
  left(x::text, 400)
  from (select pg_temp.v('P1')::jsonb x) y;
insert into r select 'api_ref_keyed', bool_and(o ->> 'lead_ref' not in (left(encode(extensions.digest('b2b-ref-' || pg_temp.v('L1'), 'sha256'), 'hex'), 12),
                                                                      left(encode(extensions.digest('b2b-ref-' || pg_temp.v('L2'), 'sha256'), 'hex'), 12))),
  string_agg(o ->> 'lead_ref', ',')
  from jsonb_array_elements(pg_temp.v('P1')::jsonb -> 'result' -> 'outcomes') o;
-- a token, not the id or a plain encoding of it; only the database reads the id back
insert into r select 'api_cursor_opaque', bool_and((o ->> 'cursor') ~ '^c1\.[A-Za-z0-9_-]{16,64}$'
                                                   and o ->> 'cursor' not in (pg_temp.v('L1'), pg_temp.v('L2'))
                                                   and translate(substr(o ->> 'cursor', 4), '-_', '+/') not in (rtrim(encode(convert_to(pg_temp.v('L1'), 'UTF8'), 'base64'), '='),
                                                                                                         rtrim(encode(convert_to(pg_temp.v('L2'), 'UTF8'), 'base64'), '='))
                                                   and b2b.referral_cursor_id(o ->> 'cursor') in (pg_temp.v('L1')::bigint, pg_temp.v('L2')::bigint))
  and (pg_temp.v('P1')::jsonb -> 'result' ->> 'next_after') ~ '^c1\.', string_agg(o ->> 'cursor', ',')
  from jsonb_array_elements(pg_temp.v('P1')::jsonb -> 'result' -> 'outcomes') o;
insert into r select 'api_paged', jsonb_array_length(x -> 'result' -> 'outcomes') = 1 and (x -> 'result' -> 'outcomes' -> 0 ->> 'programme') = 'BBA', x::text
  from (select b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'INF001', pg_temp.v('P1')::jsonb -> 'result' -> 'outcomes' -> 0 ->> 'cursor', 10) x) y;
insert into r select 'api_page_end', jsonb_array_length(x -> 'result' -> 'outcomes') = 0
  and x -> 'result' ->> 'next_after' = pg_temp.v('P1')::jsonb -> 'result' ->> 'next_after', x::text
  from (select b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'INF001', pg_temp.v('P1')::jsonb -> 'result' ->> 'next_after', 10) x) y;
insert into r select 'api_lead_id_not_a_cursor', (b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'INF001', pg_temp.v('L1'), 10) ->> 'status')::int = 400
  and (b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'INF001', 'c1.AAAAAAAAAAAAAAAAAAAAAA', 10) ->> 'status')::int = 400, null;
insert into r select 'api_other_code_empty', jsonb_array_length(x -> 'result' -> 'outcomes') = 0 and (x ->> 'ok')::boolean, x::text
  from (select b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'INF002') x) y;
insert into r select 'api_prefix', jsonb_array_length(b2b.api_referral_outcomes_v2('eb2b_m34dtest_key_0003', 'INF002') -> 'result' -> 'outcomes') = 1
  and jsonb_array_length(b2b.api_referral_outcomes_v2('eb2b_m34dtest_key_0003', 'inf001') -> 'result' -> 'outcomes') = 2, null;
insert into r select 'api_unlinked_reads_nothing', jsonb_array_length(b2b.api_referral_outcomes_v2('eb2b_m34dtest_key_0004', 'INF001') -> 'result' -> 'outcomes') = 0, null;
insert into r select 'api_wrong_scope', (b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0002', 'INF001') ->> 'status')::int = 401, null;
insert into r select 'api_no_code', (b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', ' ') ->> 'status')::int = 400, null;
insert into r select 'api_unknown_code_empty', jsonb_array_length(b2b.api_referral_outcomes_v2('eb2b_m33dtest_key_0001', 'NOPE') -> 'result' -> 'outcomes') = 0, null;
-- the first function, kept for a web deploy older than m34d: the same first page, no numeric cursor
insert into r select 'v1_first_page_scoped', x -> 'result' -> 'outcomes' = pg_temp.v('P1')::jsonb -> 'result' -> 'outcomes'
  and jsonb_array_length(b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'INF002') -> 'result' -> 'outcomes') = 0, left(x::text, 200)
  from (select b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'INF001') x) y;
insert into r select 'v1_numeric_cursor_refused', (b2b.api_referral_outcomes('eb2b_m33dtest_key_0001', 'INF001', pg_temp.v('L1')::bigint, 10) ->> 'status')::int = 400, null;

-- ---------- the Admin links keys to codes ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d4', 'm34d-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000d4', 'm34d-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d4","role":"authenticated","aal":"aal2","email":"m34d-admin@test.local"}', true);
do $x$ declare e text; x jsonb; v_id bigint; begin
  e := pg_temp.err($q$select b2b.api_key_create('{"name":"m34d no codes","scopes":["referrals"]}')$q$);
  insert into r values ('create_needs_codes', e like '22023 link the key to at least one referral code%', e);
  e := pg_temp.err($q$select b2b.api_key_create('{"name":"m34d bad code","scopes":["referrals"],"referral_codes":["IN*"]}')$q$);
  insert into r values ('create_checks_codes', e like '22023 referral code IN*%', e);
  e := pg_temp.err($q$select b2b.api_key_create('{"name":"m34d wrong scope","scopes":["intake"],"referral_codes":["INF001"]}')$q$);
  insert into r values ('codes_need_scope', e like '22023 referral codes apply only%', e);
  x := b2b.api_key_create('{"name":"m34d platform","scopes":["referrals"],"referral_codes":[" inf003 ","INF*","inf003"]}');
  v_id := (x ->> 'id')::bigint;
  insert into t values ('K', v_id::text);
  insert into t values ('K_created', x::text);
  x := b2b.api_key_update(v_id, '{"referral_codes":["ABC001"]}');
  x := b2b.system_overview();
  insert into r select 'overview_lists_codes', exists (select 1 from jsonb_array_elements(x -> 'api_keys') a where (a ->> 'id')::bigint = v_id
                                                         and a -> 'referral_codes' = '["ABC001"]'::jsonb), null;
end $x$;
reset role;
insert into r select 'create_stores_codes', (select e.payload -> 'referral_codes' from b2b.events e where e.type = 'api_key.created'
                                              and (e.payload ->> 'api_key_id')::bigint = pg_temp.v('K')::bigint) = '["INF*", "INF003"]'::jsonb,
  pg_temp.v('K_created');
insert into r select 'update_replaces_codes', k.referral_codes = '{ABC001}', k.referral_codes::text from b2b.api_keys k where k.id = pg_temp.v('K')::bigint;
insert into r select 'helpers_internal', bool_and(not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')),
                     string_agg(f::text, ', ')
  from unnest(array['b2b.referral_secret()'::regprocedure, 'b2b.referral_ref(bigint)'::regprocedure, 'b2b.referral_cursor(bigint)'::regprocedure,
                    'b2b.referral_cursor_id(text)'::regprocedure]) f;
insert into r select 'v2_public', has_function_privilege('anon', 'b2b.api_referral_outcomes_v2(text, text, text, integer)', 'execute'), null;
select name, ok, detail from r order by ok, name;
rollback;
