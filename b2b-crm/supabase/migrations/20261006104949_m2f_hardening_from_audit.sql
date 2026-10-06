-- M2f (6 Oct 2026): fixes from the audit of the hotfixes, M1 and M2. No DROP statements (the connector holds those).
--
-- 1. RLS cost: `using (b2b.is_admin())` ran the function once per row (2,000 calls on a 2,000-row table on staging).
--    `(select b2b.is_admin())` makes Postgres evaluate it once per query.
-- 2. b2b.events_append_only() had no fixed search_path (advisor warning).
-- 3. b2b.set_setting() accepted any key and any JSON; now only known keys and object/array values.
-- 4. influencer_dashboard_leads(): cap input lengths so the attempt log cannot be flooded with long junk, and
--    purge attempts older than two days nightly (pg_cron is available since M2).
-- 5. anon never needs to read student_leads, influencers or influencer_auth (influencers sign in; the dashboard's
--    read path is the password-checked function). Revoke the SELECT grants so RLS is not the only line of defence.
-- 6. The auth.users trigger function: grant EXECUTE to supabase_auth_admin explicitly. Trigger firing does not
--    check EXECUTE (verified on staging), so this is belt and braces after M1's revokes.
-- 7. Index for listing failed and dead outbox items.

-- 1. RLS: evaluate is_admin() once per statement
do $rls$
declare t text;
begin
  foreach t in array array['app_users', 'sign_in_log', 'events', 'settings', 'settings_versions', 'api_keys',
                           'integration_outbox', 'live_switches'] loop
    execute format('alter policy admin_read on b2b.%I using ((select b2b.is_admin()))', t);
  end loop;
end $rls$;

-- 2. search_path on the trigger function
alter function b2b.events_append_only() set search_path = '';

-- 3. settings: known keys and sane values only
create or replace function b2b.set_setting(p_key text, p_value jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a jsonb := b2b.actor();
  v int;
begin
  if a ->> 'type' = 'admin' and not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required for every settings change'; end if;
  if p_value is null or jsonb_typeof(p_value) not in ('object', 'array') then
    raise exception 'setting % must be a JSON object or array', p_key;
  end if;
  -- Only a system migration may introduce a key; the Admin and the AI optimiser change existing ones.
  if a ->> 'type' <> 'system' and not exists (select 1 from b2b.settings s where s.key = p_key) then
    raise exception 'unknown setting %', p_key;
  end if;
  insert into b2b.settings (key, value, actor_type, actor_id) values (p_key, p_value, a ->> 'type', a ->> 'id')
  on conflict (key) do update set value = excluded.value, version = b2b.settings.version + 1, updated_at = now(),
                                  actor_type = excluded.actor_type, actor_id = excluded.actor_id
  returning version into v;
  insert into b2b.settings_versions (key, version, value, reason, actor_type, actor_id)
  values (p_key, v, p_value, p_reason, a ->> 'type', a ->> 'id');
  perform b2b.log_event('settings.changed', null, null, null, jsonb_build_object('key', p_key, 'version', v, 'reason', p_reason));
  return jsonb_build_object('key', p_key, 'version', v);
end $$;

-- 4. influencer read path: input caps and nightly purge of the attempt log
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
  if v_code = '' or coalesce(p_password, '') = '' or length(v_code) > 64 or length(p_password) > 128 then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  -- 5 failed attempts per referral code in 15 minutes lock that code for the rest of the window.
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

do $cron$
begin
  if not exists (select 1 from cron.job where jobname = 'influencer_login_attempts_purge') then
    perform cron.schedule('influencer_login_attempts_purge', '17 21 * * *',   -- 02:47 IST
      $job$delete from public.influencer_login_attempts where at < now() - interval '2 days'$job$);
  end if;
end $cron$;

-- 5. anon reads of the shared tables
revoke select on public.student_leads   from anon;
revoke select on public.influencers     from anon;
revoke select on public.influencer_auth from anon;

-- 6. auth trigger function: explicit EXECUTE for the auth service role
grant execute on function public.crm_handle_new_auth_user() to supabase_auth_admin;

-- 7. outbox listing index
create index if not exists integration_outbox_status_idx on b2b.integration_outbox (status, created_at desc);
