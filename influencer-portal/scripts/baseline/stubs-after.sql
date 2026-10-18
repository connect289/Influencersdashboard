-- Part 3 of the shared baseline (hand-written, LOCAL ONLY): objects that need the exact tables to exist.

-- Catalogue contract views: exact production definitions (catalog.programmes_v reads the B2B stubs above).
create schema if not exists catalog;

create or replace view catalog.universities_v as
 select id, name, short_name, institution_type, recognitions, accreditation_text, updated_at
   from public.catalog_universities u;

create or replace view catalog.programmes_v as
 select c.id, c.university_id, u.name as university_name, c.program_name as programme_name, c.course, c.course_key,
        c.specialization, c.level, c.mode, nullif((c.fee_other ->> 'duration'), '') as duration, c.min_qualification,
        c.min_pct_general as min_pct, c.min_pct_reserved, c.eligibility_text,
        coalesce(c.fee_yearly, o.fee_yearly) as fee_per_year, coalesce(c.fee_semester, o.fee_semester) as fee_per_semester,
        coalesce(c.fee_total, o.fee_total) as fee_total, coalesce(c.fee_exam, o.fee_exam) as fee_exam,
        coalesce(c.fee_registration, o.fee_registration) as fee_registration,
        case when (c.fee_other ? 'emi_available') then ((c.fee_other ->> 'emi_available') = any (array['true', 'yes', '1'])) else null::boolean end as emi_available,
        nullif((c.fee_other ->> 'typical_emi'), '') as typical_emi, nullif((c.fee_other ->> 'scholarship'), '') as scholarship_notes,
        o.intakes, o.deadlines, u.accreditation_text as accreditation, u.recognitions, c.brochure_url,
        (coalesce(o.partners, 0::bigint))::integer as offered_by_partner_count,
        greatest(c.updated_at, u.updated_at, o.updated_at) as updated_at
   from public.catalog_programs c
   join public.catalog_universities u on u.id = c.university_id
   left join lateral (
     select count(distinct pp.partner_id) as partners,
            min((nullif((pp.fees ->> 'yearly'), ''))::numeric) as fee_yearly,
            min((nullif((pp.fees ->> 'semester'), ''))::numeric) as fee_semester,
            min((nullif((pp.fees ->> 'total'), ''))::numeric) as fee_total,
            min((nullif((pp.fees ->> 'exam'), ''))::numeric) as fee_exam,
            min((nullif((pp.fees ->> 'registration'), ''))::numeric) as fee_registration,
            array_remove(array_agg(distinct pp.intake), null::text) as intakes,
            array_remove(array_agg(distinct pp.season_to), null::date) as deadlines,
            max(pp.valid_from) as updated_at
       from b2b.partner_programmes pp join b2b.partners p on p.id = pp.partner_id
      where pp.programme_id = c.id and pp.active and pp.valid_to is null and p.status <> 'closed'
        and (pp.season_to is null or pp.season_to >= current_date)) o on true
  where c.active;

-- Commission per programme and partner (a view over B2B rate tables in production; a table here).
create table if not exists catalog.partner_rates_v (
  partner_id bigint, partner_name text, university_id bigint, university_name text, programme_id bigint,
  programme_name text, rate_id bigint, rate_scope text, rate_type text, value numeric, fee_base text,
  tier_table jsonb, current_tier_pct numeric, tier_conversion_pct numeric, gst_inclusive boolean, valid_from date,
  valid_to date, fee_base_inr numeric, effective_pct numeric, effective_inr numeric,
  is_highest_for_programme boolean, is_highest_for_university boolean
);

-- Old CRM role helpers and the auth trigger (exact production bodies). Every new auth user becomes an inactive
-- crm_users viewer in production (risk RK-3); reproduced here so local tests see the same side effect.
create or replace function public.crm_role() returns text language sql stable security definer set search_path to 'public' as $$
  select role from crm_users where id = auth.uid() and is_active;
$$;

create or replace function public.crm_can_see(p_owner uuid, p_is_test boolean, p_ready boolean) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select case coalesce(crm_role(), '')
           when '' then false
           when 'sales_manager' then (p_owner = auth.uid() or (p_owner is null and coalesce(p_ready, false))) and not coalesce(p_is_test, false)
           when 'admin' then true
           else not coalesce(p_is_test, false) end;
$$;

create or replace function public.current_referral_code() returns text language sql stable security definer set search_path to 'public' as $$
  select referral_code from public.influencers where auth_uid = auth.uid() and status = 'active'
$$;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'connect@eduwit.in'
$$;

create or replace function public.crm_handle_new_auth_user() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  insert into crm_users (id, email, full_name)
  values (new.id, coalesce(new.email, new.id::text), coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists crm_on_auth_user_created on auth.users;
create trigger crm_on_auth_user_created after insert on auth.users for each row execute function public.crm_handle_new_auth_user();

-- Production policies on the master table (exact).
create policy crm_staff_select on public.student_leads for select to authenticated
  using (crm_can_see(owner_user_id, is_test, is_sales_ready));
create policy "Influencers can only view their own student leads" on public.student_leads for select to authenticated
  using ((referral_code = current_referral_code()) or is_admin());
create policy "Influencers can view their own profile" on public.influencers for select to authenticated
  using ((auth_uid = auth.uid()) or is_admin());

-- Production grants that matter: anon has no data privileges on student_leads, touchpoints, enrollments; Witty's
-- tables are reached only through Witty's functions (RLS on, no policies).
revoke all on public.student_leads, public.touchpoints, public.enrollments, public.influencers, public.crm_users from anon;
revoke execute on function public.lead_intake(jsonb) from public, anon, authenticated;
revoke execute on function public.current_referral_code(), public.is_admin(), public.crm_handle_new_auth_user() from anon;
