-- M33g (30 Oct): the legacy CRM's internal stage writer is no longer callable through the API (estate audit, 30 Oct 2026).
--   public.crm_apply_stage_system(...) is SECURITY DEFINER and checks no caller: it moves any lead to any stage, writes
--   its application, fee and enrolment fields, and for 'lost' closes its partner allocations. The baseline granted it to
--   authenticated, and Supabase sign-ups are open, so any stranger who signed up could call it through /rest/v1/rpc.
--   Its only callers are public.crm_set_stage (which checks crm_require first) and public.crm_partner_event (not callable
--   by anon or authenticated), both SECURITY DEFINER owned by postgres, so they keep working.
-- Re-appliable. Rollback (restores the old, unsafe grant; do not run it unless a caller is found that needs it):
--   grant execute on function public.crm_apply_stage_system(bigint, text, text, text, jsonb, text, boolean) to authenticated;
revoke all on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean)
  from public, anon, authenticated;
grant execute on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean)
  to service_role;
