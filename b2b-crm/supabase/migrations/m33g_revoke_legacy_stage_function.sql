-- M33g (30 Oct): the legacy CRM's internal stage writer runs only for its two internal callers, not through the API
--   (estate audit, 30 Oct 2026). Those callers, public.crm_set_stage (which checks crm_require first) and
--   public.crm_partner_event, are SECURITY DEFINER owned by postgres, so they keep working.
-- Re-appliable. Rollback (restores the previous grant; do not run it unless a caller is found that needs it):
--   grant execute on function public.crm_apply_stage_system(bigint, text, text, text, jsonb, text, boolean) to authenticated;
revoke all on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean)
  from public, anon, authenticated;
grant execute on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean)
  to service_role;
