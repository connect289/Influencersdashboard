-- M33d (15 Oct): referral outcomes for the influencer dashboard (design A5, B2B_CRM_PROMPT table 'b2b_referral_outcomes').
--   public.b2b_referral_outcomes   a masked, read-only view (security_invoker): referral code, an opaque lead reference, the
--                                  enquiry date, the canonical stage (the B2C CRM's own stage for leads it holds, once it
--                                  publishes b2c_lead_status_v), enrolled yes / no, the programme. Never a name, phone or
--                                  email. Row access follows student_leads' own policies, so an influencer sees only their code.
--   b2b.api_referral_outcomes      GET /v1/referrals/{code}/outcomes (API key scope 'referrals'), keyset-paged.
create or replace view public.b2b_referral_outcomes with (security_invoker = true) as
  select l.referral_code,
         left(encode(extensions.digest('b2b-ref-' || l.id::text, 'sha256'), 'hex'), 12) as lead_ref,
         l.created_at::date as enquired_on,
         coalesce(l.stage, 'new') as stage,
         (l.stage = 'enrolled' or coalesce(l.enrollment_status in ('verified', 'reported'), false) or exists (select 1 from public.enrollments e where e.lead_id = l.id and e.status in ('reported', 'verified'))) as enrolled,
         l.interested_course as programme,
         l.enrolled_program,
         greatest(coalesce(l.updated_at, l.created_at), coalesce(l.stage_changed_at, l.created_at))::date as updated_on
    from public.student_leads l
   where l.referral_code is not null and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null;
revoke all on public.b2b_referral_outcomes from public, anon;
grant select on public.b2b_referral_outcomes to authenticated, service_role;

create or replace function b2b.api_referral_outcomes(p_key text, p_code text, p_after bigint default null, p_limit int default 100)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.api_key_check(p_key, 'referrals');
  v_code text := upper(trim(coalesce(p_code, '')));
  v_rows jsonb;
  v_last bigint;
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_code = '' or length(v_code) > 60 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'give a referral code'); end if;
  with page as (
    select l.id, l.created_at, l.stage, l.enrollment_status, l.interested_course, l.enrolled_program, l.updated_at, l.stage_changed_at, l.destination_type
      from public.student_leads l
     where upper(l.referral_code) = v_code and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null
       and (p_after is null or l.id > p_after)
     order by l.id limit least(greatest(coalesce(p_limit, 100), 1), 500))
  select coalesce(jsonb_agg(jsonb_build_object(
           'lead_ref', left(encode(extensions.digest('b2b-ref-' || x.id::text, 'sha256'), 'hex'), 12),
           'enquired_on', x.created_at::date,
           'stage', coalesce(case when x.destination_type = 'in_house' then b2b.b2c_status_of(x.id) ->> 'stage' end, x.stage, 'new'),
           'enrolled', x.stage = 'enrolled' or coalesce(x.enrollment_status in ('verified', 'reported'), false) or exists (select 1 from public.enrollments e where e.lead_id = x.id and e.status in ('reported', 'verified')),
           'programme', x.interested_course, 'enrolled_program', x.enrolled_program,
           'updated_on', greatest(coalesce(x.updated_at, x.created_at), coalesce(x.stage_changed_at, x.created_at))::date,
           'cursor', x.id) order by x.id), '[]'), max(x.id)
    into v_rows, v_last from page x;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('referral_code', v_code, 'outcomes', v_rows, 'next_after', coalesce(v_last, p_after, 0)));
end $fn$;
revoke execute on function b2b.api_referral_outcomes(text, text, bigint, int) from public;
grant execute on function b2b.api_referral_outcomes(text, text, bigint, int) to anon, authenticated, service_role;
