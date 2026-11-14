-- Rollback of 0040: an engineer mutes any check or app again, a P1 included, as after 0039 (one.ui_mute as 0037 left
-- it, verbatim). Mutes made under 0040 stay, with their audit rows, and end at their time.

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor, p_request_id);
begin
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

call one.apply_grants();
