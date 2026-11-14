-- Rollback of public_search_path.sql: the 47 functions go back to having no search_path setting.
do $m5$
declare
  v_sig text;
  v_oid oid;
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
    if v_oid is not null then
      execute format('alter function %s reset search_path', v_oid::regprocedure);
    end if;
  end loop;
end
$m5$;
