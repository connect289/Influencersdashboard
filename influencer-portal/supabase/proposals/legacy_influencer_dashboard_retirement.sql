-- =====================================================================================================================
-- PROPOSAL, OWNER DECISION. Not a migration: nothing applies this folder (supabase db push/reset only run
-- supabase/migrations). Apply only after the owner approves, in one transaction, on the live project
-- (SQL Editor or the coordinator's apply script), after a rehearsal on staging.
-- =====================================================================================================================
-- Retires the legacy influencer dashboard objects in schema public (SHARED_CHANGES.md §E L-1 to L-3, RUNBOOK G-7,
-- Eduwit One check INF-06); the dashboard that used them is no longer deployed. Sections 1-4 are recommended
-- together; sections 5-6 are optional (commented out). Every statement is idempotent. Rollback statements are at
-- the end (stored passwords do not return to their old form, by design).
-- =====================================================================================================================

-- 1. Remove the legacy dashboard's read policy on student_leads (the CRM's policy crm_staff_select stays).
drop policy if exists "Influencers can only view their own student leads" on public.student_leads;

-- 2. Deactivate the legacy accounts (INF-06), without deleting them. On 30 Oct 2026 all 3 rows were 'active'.
update public.influencers set status = 'inactive' where status = 'active';

-- 3. Store the legacy dashboard passwords as bcrypt hashes (in place; existing passwords keep working), check them
--    with crypt(), and add a global failure limit beside the per-code one.
do $$
begin
  if to_regclass('public.influencer_auth') is not null then
    update public.influencer_auth
       set secret_password = extensions.crypt(secret_password, extensions.gen_salt('bf', 10))
     where secret_password !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$';
    comment on column public.influencer_auth.secret_password is
      'bcrypt hash (extensions.crypt with gen_salt(''bf'', 10)); never plain text';
  end if;
  if to_regclass('public.influencer_login_attempts') is not null then
    create index if not exists influencer_login_attempts_fail_at_idx on public.influencer_login_attempts (at) where not ok;
  end if;
end $$;

create or replace function public.influencer_dashboard_leads(p_referral_code text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code  text := trim(coalesce(p_referral_code, ''));
  v_fails int;
  v_hash  text;
  v_ok    boolean;
begin
  if v_code = '' or coalesce(p_password, '') = '' or length(v_code) > 64 or length(p_password) > 128 then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  -- Global limit first (spraying many codes), then the per-code lockout.
  select count(*) into v_fails
    from public.influencer_login_attempts
   where not ok and at > now() - interval '15 minutes';
  if v_fails >= 50 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;
  select count(*) into v_fails
    from public.influencer_login_attempts
   where referral_code = v_code and not ok and at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select a.secret_password into v_hash from public.influencer_auth a where a.referral_code = v_code;
  if v_hash is null then
    perform extensions.crypt(p_password, extensions.gen_salt('bf', 10));  -- same cost for unknown codes
    v_ok := false;
  else
    v_ok := extensions.crypt(p_password, v_hash) = v_hash;
  end if;
  insert into public.influencer_login_attempts (referral_code, ok) values (v_code, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  return jsonb_build_object('ok', true, 'leads', coalesce((
    select jsonb_agg(jsonb_build_object(
             'student_name',        l.student_name,
             'phone_masked',        case when l.whatsapp_number is null then null
                                         else '••••••' || right(regexp_replace(l.whatsapp_number, '\D', '', 'g'), 4) end,
             'email_masked',        case when l.email_id is null or position('@' in l.email_id) = 0 then null
                                         else left(l.email_id, 1) || '•••@' || split_part(l.email_id, '@', 2) end,
             'lead_status',         l.lead_status,
             'interested_course',   l.interested_course,
             'lead_stage',          l.lead_stage,
             'enrolled_program',    l.enrolled_program,
             'enrolled_university', l.enrolled_university,
             'enrollment_date',     l.enrollment_date,
             'created_at',          l.created_at)
           order by l.created_at desc)
      from public.student_leads l
     where l.referral_code = v_code
       and l.deleted_at is null and l.merged_into_id is null
       and not coalesce(l.is_test, false)), '[]'::jsonb));
end $$;

-- 4. Close the legacy function to clients (nothing calls it); it stays callable by service_role.
revoke all on function public.influencer_dashboard_leads(text, text) from public, anon, authenticated;
grant execute on function public.influencer_dashboard_leads(text, text) to service_role;

-- 5. Optional: drop the legacy view public.influencer_leads_dashboard (nothing reads it).
-- drop view if exists public.influencer_leads_dashboard;

-- 6. Optional: drop the legacy profile policy on public.influencers once nothing needs the legacy admin page.
-- drop policy if exists "Influencers can view their own profile" on public.influencers;

-- =====================================================================================================================
-- rollback: (inverse statements, one transaction)
-- create policy "Influencers can only view their own student leads" on public.student_leads for select to authenticated
--   using ((referral_code = current_referral_code()) or is_admin());
-- update public.influencers set status = 'active' where status = 'inactive';   -- check first: 3 rows
-- drop index if exists public.influencer_login_attempts_fail_at_idx;
-- comment on column public.influencer_auth.secret_password is null;
-- The previous function, verbatim (it would not match the hashed passwords: give each account a new password with
-- the section 3 function instead of rolling this part back):
-- create or replace function public.influencer_dashboard_leads(p_referral_code text, p_password text)
--  returns jsonb
--  language plpgsql
--  security definer
--  set search_path to 'public'
-- as $function$
-- declare
--   v_code  text := trim(coalesce(p_referral_code, ''));
--   v_fails int;
--   v_ok    boolean;
-- begin
--   if v_code = '' or coalesce(p_password, '') = '' or length(v_code) > 64 or length(p_password) > 128 then
--     return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
--   end if;
--
--   select count(*) into v_fails
--     from influencer_login_attempts
--    where referral_code = v_code and not ok and at > now() - interval '15 minutes';
--   if v_fails >= 5 then
--     return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
--   end if;
--
--   select exists (select 1 from influencer_auth a
--                   where a.referral_code = v_code and a.secret_password = p_password)
--     into v_ok;
--   insert into influencer_login_attempts (referral_code, ok) values (v_code, v_ok);
--   if not v_ok then
--     return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
--   end if;
--
--   return jsonb_build_object('ok', true, 'leads', coalesce((
--     select jsonb_agg(jsonb_build_object(
--              'student_name',        l.student_name,
--              'phone_masked',        case when l.whatsapp_number is null then null
--                                          else '••••••' || right(regexp_replace(l.whatsapp_number, '\D', '', 'g'), 4) end,
--              'email_masked',        case when l.email_id is null or position('@' in l.email_id) = 0 then null
--                                          else left(l.email_id, 1) || '•••@' || split_part(l.email_id, '@', 2) end,
--              'lead_status',         l.lead_status,
--              'interested_course',   l.interested_course,
--              'lead_stage',          l.lead_stage,
--              'enrolled_program',    l.enrolled_program,
--              'enrolled_university', l.enrolled_university,
--              'enrollment_date',     l.enrollment_date,
--              'created_at',          l.created_at)
--            order by l.created_at desc)
--       from student_leads l
--      where l.referral_code = v_code
--        and l.deleted_at is null and l.merged_into_id is null
--        and not coalesce(l.is_test, false)), '[]'::jsonb));
-- end $function$;
-- grant execute on function public.influencer_dashboard_leads(text, text) to anon, authenticated;
-- (sections 5-6, if applied: recreate the view from its production definition, and
--  create policy "Influencers can view their own profile" on public.influencers for select to authenticated
--    using ((auth_uid = auth.uid()) or is_admin());)
