-- Shared database: a fixed search_path on 47 older plpgsql functions of schema public (audit of 13 Nov 2026, M5).
-- Owner-approved. Only the functions' search_path setting changes: no body, signature, owner, grant, volatility or
-- security mode changes, and no table, trigger, cron job or n8n workflow is touched.
--
-- Why: Supabase's security advisor lists every function of schema public without a fixed search_path. None of them
-- is SECURITY DEFINER and no client role can create objects in schema public, so the exposure is small; fixing the
-- path removes the dependence on whatever path the caller happens to have.
--
-- The value "public, extensions" is what every caller already resolves to today: role postgres has
-- "$user", public, extensions (there is no schema named postgres), and the API roles have no setting of their own.
-- pg_temp and pg_catalog stay searched implicitly, as before. So name resolution inside these functions is unchanged.
--
-- Left out on purpose:
--   * catalog_load, catalog_commit, catalog_remove_source, catalog_stage_add, catalog_programs_fee_check: the legacy
--     catalogue is frozen until it is switched off (Scout O-6, O-16);
--   * the 35 SQL-language functions (crm_mask_*, crm_norm_phone, web_norm, w2_is_test, ...): a SET clause stops the
--     planner folding them into the calling query, which would slow lists and search. They stay as they are.
-- A function that does not exist on the target (staging lacks four) is skipped. Idempotent.
do $m5$
declare
  v_sig text;
  v_oid oid;
  v_done int := 0;
  v_skipped int := 0;
begin
  foreach v_sig in array array[
    'public.crm_require(text[])',
    'public.increment_workflow_version()',
    'public.match_documents(vector,integer,jsonb)',
    'public.match_eduwit_knowledge_base(vector,integer,jsonb)',
    'public.student_leads_bulk_delete_guard()',
    'public.student_leads_touch()',
    'public.w2_add_feedback(jsonb)',
    'public.w2_add_source(jsonb)',
    'public.w2_agent_pause(jsonb)',
    'public.w2_blocks_sweep()',
    'public.w2_bot_check(text)',
    'public.w2_build_prompt(text)',
    'public.w2_cache_plan(text,integer)',
    'public.w2_cache_saved(jsonb)',
    'public.w2_commit_turn(jsonb)',
    'public.w2_crm_payload(text,text,text,jsonb)',
    'public.w2_drive_done(jsonb)',
    'public.w2_drive_plan(jsonb)',
    'public.w2_fee_sanity(text,boolean,numeric,numeric,numeric)',
    'public.w2_inbox_add(jsonb)',
    'public.w2_issue_code(jsonb)',
    'public.w2_kb_commit(text,jsonb)',
    'public.w2_kb_remove(text)',
    'public.w2_kb_search(jsonb)',
    'public.w2_kb_set_embeddings(jsonb)',
    'public.w2_kb_stage_add(text,jsonb)',
    'public.w2_learning_apply()',
    'public.w2_learning_digest(integer,integer)',
    'public.w2_learning_save(jsonb)',
    'public.w2_nurture_done(jsonb)',
    'public.w2_nurture_due(integer)',
    'public.w2_outbox_claim(text,integer)',
    'public.w2_outbox_result(jsonb)',
    'public.w2_outbox_retry(integer)',
    'public.w2_parse_rating(text)',
    'public.w2_redeem_code(text,text)',
    'public.w2_register_lead(jsonb)',
    'public.w2_release(text,text)',
    'public.w2_search_programs(jsonb)',
    'public.w2_search_programs_cached(jsonb)',
    'public.w2_send_failed(text,text,text)',
    'public.w2_test_prepare(jsonb)',
    'public.w2_test_reset(text)',
    'public.w2_test_send(text,text,text)',
    'public.w2_test_step(jsonb)',
    'public.w2_try_claim(text,text,integer)',
    'public.w2_unblock(text,text,text)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    execute format('alter function %s set search_path = public, extensions', v_oid::regprocedure);
    v_done := v_done + 1;
  end loop;
  raise notice 'search_path fixed on % functions, % not present', v_done, v_skipped;
end
$m5$;
