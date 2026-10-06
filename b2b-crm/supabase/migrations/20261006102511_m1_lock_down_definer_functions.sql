-- M1 (approved 6 Oct 2026, D2): stop signed-in accounts that are not CRM staff, and anonymous callers,
-- from running internal SECURITY DEFINER functions through /rest/v1/rpc.
--
-- Supabase Auth is shared with the influencer dashboard, so any sign-up gets the `authenticated` role.
-- Who still calls what after this migration:
--   * n8n / Witty: the privileged "Postgres account" credential (unaffected by grants to anon/authenticated).
--   * Old CRM server routes (service role client): lead_intake, crm_api_key_check, crm_partner_*, ticks. Unaffected.
--   * Old CRM UI (user session): the role-checked crm_* functions (unchanged), plus the ten unchecked
--     functions in part 2, which now refuse a signed-in user who is not active CRM staff.
--   * Trigger functions run without an EXECUTE check, so revoking them breaks no trigger.
-- Idempotent.

-- 1. Unchecked functions that no signed-in user needs to call directly.
do $m$
declare
  f text;
begin
  foreach f in array array[
    'crm_api_key_check(text)',
    'crm_auto_assign_trg()',
    'crm_compute_earning(enrollments, earning_rates, text)',
    'crm_compute_payout(enrollments, payout_rates, numeric, text)',
    'crm_conversion(text, bigint)',
    'crm_dest_stats(text, bigint, text, jsonb)',
    'crm_earning_rate(bigint, bigint, bigint, date)',
    'crm_handle_new_auth_user()',
    'crm_marketing_allowed(bigint, text)',
    'crm_money_setting(text)',
    'crm_partner_duplicate(bigint, text, timestamp with time zone, text)',
    'crm_partner_event(bigint, jsonb)',
    'crm_partner_health_check()',
    'crm_partner_verify(bigint, text, text)',
    'crm_payout_rate(bigint, bigint, uuid, date)',
    'crm_rules_match(jsonb, bigint)',
    'crm_rules_where(jsonb)',
    'crm_segment_leads(jsonb, integer)',
    'crm_segment_resolve(bigint)',
    'crm_send_job(bigint, bigint, text, jsonb)',
    'crm_sla_minutes(text)',
    'crm_sync_claim(integer)',
    'crm_sync_result(jsonb)',
    'crm_unsubscribe(bigint, text, text)',
    'crm_unsubscribe_token(bigint)',
    'lead_intake(jsonb)',
    'rls_auto_enable()'
  ] loop
    if to_regprocedure('public.' || f) is not null then
      execute format('revoke execute on function public.%s from public, anon, authenticated', f);
      execute format('grant execute on function public.%s to service_role', f);
    end if;
  end loop;
end $m$;

-- RLS helpers: only signed-in policies use them, so anon loses access; authenticated keeps it.
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.current_referral_code() from public, anon;

-- 2. Unchecked functions the old CRM's UI calls with the user's session. Their bodies stay as they are:
--    each is renamed to <name>__impl (callable only by the service role) and a wrapper with the same
--    name and signature refuses a signed-in user who is not active CRM staff. Calls without a user
--    (service role, n8n, jobs) and calls nested inside other definer functions pass through.
do $m$
declare
  r      record;
  v_impl text;
  v_call text;
begin
  for r in
    select p.oid, p.proname, p.pronargs,
           pg_get_function_arguments(p.oid)          as fargs,
           oidvectortypes(p.proargtypes)             as iargs,
           pg_get_function_result(p.oid)             as res
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('crm_duplicate_candidates', 'crm_engine_flow', 'crm_marketing_stats', 'crm_programme_fit',
                         'crm_render_template', 'crm_scorecards', 'crm_score_lead', 'crm_segment_count',
                         'crm_timeline', 'crm_whatsapp_window')
  loop
    v_impl := r.proname || '__impl';
    if to_regprocedure(format('public.%I(%s)', v_impl, r.iargs)) is not null then
      continue;  -- already wrapped
    end if;
    if r.res like 'SETOF %' or r.res like 'TABLE(%' then
      raise exception 'M1: % returns a set; wrapper not supported', r.proname;
    end if;
    execute format('alter function public.%I(%s) rename to %I', r.proname, r.iargs, v_impl);
    execute format('revoke execute on function public.%I(%s) from public, anon, authenticated', v_impl, r.iargs);
    execute format('grant execute on function public.%I(%s) to service_role', v_impl, r.iargs);
    v_call := coalesce((select string_agg('$' || i, ', ' order by i) from generate_series(1, r.pronargs) i), '');
    execute format($f$
      create function public.%1$I(%2$s) returns %3$s
      language plpgsql security definer set search_path = public as $w$
      begin
        if auth.uid() is not null and crm_role() is null then
          raise exception 'not allowed' using errcode = '42501';
        end if;
        return public.%4$I(%5$s);
      end $w$$f$, r.proname, r.fargs, r.res, v_impl, v_call);
    execute format('comment on function public.%I(%s) is %L', r.proname, r.iargs,
                   'M1 guard: refuses signed-in users who are not active CRM staff; body in ' || v_impl);
    execute format('revoke execute on function public.%I(%s) from public, anon', r.proname, r.iargs);
    execute format('grant execute on function public.%I(%s) to authenticated, service_role', r.proname, r.iargs);
  end loop;
end $m$;
