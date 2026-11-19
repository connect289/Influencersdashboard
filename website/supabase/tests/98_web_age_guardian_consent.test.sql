-- web23: age and a parent's or guardian's consent for students under 18 (owner request, 19 Nov 2026). The age is
-- stored; under 18 needs the guardian consent text, recorded as its own consent row; refused without it, on the
-- signed-in path too; sign-in needs no age. The same checks as web23_age_guardian_consent.http.sql.
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table g (k text primary key, start jsonb, attempt uuid, student uuid) on commit drop;

create or replace function pg_temp.go(p_key text, p_surface text, p_phone text, p_age jsonb, p_guardian text, p_verify boolean)
returns jsonb language plpgsql as $$
declare s jsonb; v jsonb;
begin
  s := public.web_gate_start(jsonb_strip_nulls(jsonb_build_object('idempotency_key', p_key, 'surface', p_surface, 'name', 'Asha Test',
         'email', p_key || '@example.com', 'phone', p_phone,
         'consent_version', case p_surface when 'gate' then 'web-gate-2026-10-v1' else 'web-form-2026-10-v1' end,
         'age', p_age, 'guardian_consent_version', p_guardian, 'is_test', true, 'code_hash', 'k-' || p_key)));
  if p_verify and (s->>'ok')::boolean then
    v := public.web_gate_verify((s->>'attempt_id')::uuid, 'k-' || p_key);
  end if;
  insert into pg_temp.g values (p_key, s, (s->>'attempt_id')::uuid, (v->>'student_id')::uuid);
  return s;
end $$;
create or replace function pg_temp.a(p_key text) returns public.web_gate_attempts language sql as $$
  select a.* from public.web_gate_attempts a join pg_temp.g on g.attempt = a.id where g.k = p_key $$;
create or replace function pg_temp.consents(p_key text) returns text[] language sql as $$
  select coalesce(array_agg(c.version order by c.version), '{}') from public.web_consents c join pg_temp.g on g.student = c.student_id where g.k = p_key $$;

-- 1. An adult: the age is stored, no guardian consent, one consent row (the form's).
select pg_temp.go('w23-adult', 'enquiry', '+919876533601', '25', null, true);
insert into r select (pg_temp.a('w23-adult')).age = 25 and (pg_temp.a('w23-adult')).guardian_consent_version is null
  and pg_temp.consents('w23-adult') = array['web-form-2026-10-v1'], 'an adult: age stored, only the form consent recorded';

-- 2. A 16-year-old without the parent's consent is refused and nothing is stored.
insert into r select (pg_temp.go('w23-minor-no', 'enquiry', '+919876533602', '16', null, false))->>'reason' = 'guardian'
  and not exists (select 1 from public.web_gate_attempts where idempotency_key = 'w23-minor-no'), 'under 18 without consent: refused, no attempt';

-- 3. A wrong or unknown consent version is refused too.
insert into r select (pg_temp.go('w23-minor-bad', 'gate', '+919876533603', '17', 'web-form-2026-10-v1', false))->>'reason' = 'guardian',
  'under 18 with a version that is not a guardian text: refused';

-- 4. A 16-year-old with the parent's consent: stored, and the guardian consent is its own ledger row.
select pg_temp.go('w23-minor-ok', 'gate', '+919876533604', '16', 'web-guardian-2026-11-v1', true);
insert into r select (pg_temp.a('w23-minor-ok')).age = 16 and (pg_temp.a('w23-minor-ok')).guardian_consent_version = 'web-guardian-2026-11-v1'
  and pg_temp.consents('w23-minor-ok') = array['web-gate-2026-10-v1', 'web-guardian-2026-11-v1'], 'under 18 with consent: both consents recorded';

-- 5. An adult who also sends the guardian version: it is not stored (only minors give it).
select pg_temp.go('w23-adult-g', 'application', '+919876533605', '30', 'web-guardian-2026-11-v1', true);
insert into r select (pg_temp.a('w23-adult-g')).guardian_consent_version is null and pg_temp.consents('w23-adult-g') = array['web-form-2026-10-v1'],
  'an adult never gets a guardian consent row';

-- 6. An out-of-range age is stored as unknown instead of failing; an old page that sends no age still works.
select pg_temp.go('w23-odd', 'enquiry', '+919876533606', '150', null, false);
insert into r select (g.start->>'ok')::boolean and (pg_temp.a('w23-odd')).age is null, 'age 150: accepted, stored as unknown' from pg_temp.g g where g.k = 'w23-odd';
select pg_temp.go('w23-noage', 'enquiry', '+919876533607', null, null, false);
insert into r select (g.start->>'ok')::boolean and (pg_temp.a('w23-noage')).age is null, 'no age (old page): accepted' from pg_temp.g g where g.k = 'w23-noage';

-- 7. The signed-in path refuses a minor without consent as well.
insert into r select (public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 'w23-trusted', 'surface', 'enquiry', 'name', 'Asha Test',
         'email', 'w23-adult@example.com', 'phone', '+919876533601', 'consent_version', 'web-form-2026-10-v1', 'age', 15, 'is_test', true),
       (select student from pg_temp.g where k = 'w23-adult')))->>'reason' = 'guardian', 'signed-in path: under 18 without consent refused';

-- 8. Sign-in never needs an age.
insert into r select ((public.web_gate_start(jsonb_build_object('idempotency_key', 'w23-signin', 'surface', 'signin', 'email', 'w23-adult@example.com',
         'age', 12, 'is_test', true, 'code_hash', 'k-w23-signin')))->>'ok')::boolean, 'sign-in: no age rule';

do $$ begin
  if exists (select 1 from r where ok is not true) then
    raise exception 'FAILED (%): %', (select count(*) from r where ok is not true), (select string_agg(name, ' | ') from r where ok is not true);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
