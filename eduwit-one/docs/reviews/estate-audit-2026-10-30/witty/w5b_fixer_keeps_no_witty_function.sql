-- w5b_fixer_keeps_no_witty_function (applied 1 Nov 2026, D-126): Eduwit One's fixer keeps no Witty function. It amends
-- w5_revoke_api_grants, whose 31 Oct apply granted the fixer four Witty functions it never calls; smoke.sql refused them
-- after 0029 to 0031. One statement, atomic, checked before and after. Rollback: not needed (the fixer calls none of them).
do $w5b$
declare v_bad text;
begin
  -- pre: the four explicit grants w5 gave the fixer are there, and no fixer-owned function calls a w2 function
  if (select count(*) from pg_proc p where p.oid in ('public.w2_health_alerts()'::regprocedure, 'public.w2_health_digest(integer)'::regprocedure,
        'public.w2_stale_inbox(integer)'::regprocedure, 'public.w2_is_test(text)'::regprocedure)
        and p.proacl::text like '%eduwit_one_fixer=X/%') <> 4 then
    raise exception 'pre check failed: the fixer does not hold the four grants w5 gave it';
  end if;
  if exists (select 1 from pg_proc p where p.proowner = 'eduwit_one_fixer'::regrole and p.prosrc ~ 'w2_') then
    raise exception 'pre check failed: a fixer function calls a w2 function';
  end if;
  revoke execute on function public.w2_health_alerts(), public.w2_health_digest(integer),
                             public.w2_stale_inbox(integer), public.w2_is_test(text) from eduwit_one_fixer;
  -- post: smoke.sql's rule (the fixer executes only the catalogue outside schema one), the reader and service_role unchanged
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname <> 'one' and p.proacl::text like '%eduwit_one_fixer=%'
     and p.oid::regprocedure::text not in ('b2b.b2c_sync_tick(integer)', 'b2b.outbox_kick()', 'b2b.outbox_retry(bigint)', 'b2c.inbox_retry(integer)',
                                           'b2c.outbox_unstick()', 'b2c.job_call(text)', 'b2c.programme_cache_refresh(boolean)',
                                           'web_outbox_retry(bigint,uuid)', 'web_job_call(text,integer)', 'web_catalog_poll()',
                                           'public.web_outbox_retry(bigint,uuid)', 'public.web_job_call(text,integer)', 'public.web_catalog_poll()');
  if v_bad is not null then raise exception 'post check failed: the fixer still executes %', v_bad; end if;
  if has_function_privilege('eduwit_one_fixer', 'public.w2_health_alerts()', 'EXECUTE') then
    raise exception 'post check failed: the fixer still executes w2_health_alerts()';
  end if;
  if not (has_function_privilege('eduwit_one_reader', 'public.w2_health_alerts()', 'EXECUTE')
          and has_function_privilege('eduwit_one_reader', 'public.w2_health_digest(integer)', 'EXECUTE')
          and has_function_privilege('eduwit_one_reader', 'public.w2_stale_inbox(integer)', 'EXECUTE')
          and has_function_privilege('eduwit_one_reader', 'public.w2_is_test(text)', 'EXECUTE')
          and has_function_privilege('service_role', 'public.w2_health_alerts()', 'EXECUTE')
          and has_function_privilege('service_role', 'public.w2_health_digest(integer)', 'EXECUTE')) then
    raise exception 'post check failed: the reader or service_role lost a Witty function';
  end if;
  if has_function_privilege('anon', 'public.w2_health_alerts()', 'EXECUTE') or has_function_privilege('authenticated', 'public.w2_health_alerts()', 'EXECUTE') then
    raise exception 'post check failed: a client role executes w2_health_alerts()';
  end if;
end $w5b$;
select 'w5b applied' as result;
