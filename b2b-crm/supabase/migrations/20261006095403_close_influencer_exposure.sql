-- D1 (approved 6 Oct 2026): close the anon read of students' contact data.
-- influencer_leads_dashboard runs with its owner's rights (not security_invoker), so anon
-- could read every referred student's name, phone, email and IP plus every influencer's
-- secret_password. Nothing in eduwit-crm or the n8n exports reads it.

revoke all on public.influencer_leads_dashboard from anon, authenticated;

-- RLS already blocked these writes; remove the grants so a future policy mistake can't open them.
revoke insert, update, delete, truncate on public.influencers     from anon;
revoke insert, update, delete, truncate on public.influencer_auth from anon;
revoke insert, update, delete, truncate on public.student_leads   from anon;

-- Replacement read path for the influencer dashboard: the password is checked on the
-- server and never returned; phone and email are masked; IP is not exposed.
create table if not exists public.influencer_login_attempts (
  id            bigserial primary key,
  referral_code text        not null,
  ok            boolean     not null,
  at            timestamptz not null default now()
);
create index if not exists influencer_login_attempts_code_idx
  on public.influencer_login_attempts (referral_code, at desc);
alter table public.influencer_login_attempts enable row level security;
revoke all on public.influencer_login_attempts from anon, authenticated;
revoke all on sequence public.influencer_login_attempts_id_seq from anon, authenticated;

create or replace function public.influencer_dashboard_leads(p_referral_code text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code  text := trim(coalesce(p_referral_code, ''));
  v_fails int;
  v_ok    boolean;
begin
  if v_code = '' or coalesce(p_password, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  -- 5 failed attempts per referral code in 15 minutes locks that code for the rest of the window.
  select count(*) into v_fails
    from influencer_login_attempts
   where referral_code = v_code and not ok and at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select exists (select 1 from influencer_auth a
                  where a.referral_code = v_code and a.secret_password = p_password)
    into v_ok;
  insert into influencer_login_attempts (referral_code, ok) values (v_code, v_ok);
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
      from student_leads l
     where l.referral_code = v_code
       and l.deleted_at is null and l.merged_into_id is null
       and not coalesce(l.is_test, false)), '[]'::jsonb));
end $$;

revoke all on function public.influencer_dashboard_leads(text, text) from public;
grant execute on function public.influencer_dashboard_leads(text, text) to anon, authenticated;
