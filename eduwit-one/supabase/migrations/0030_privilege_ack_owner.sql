-- 0030 acknowledging a privilege is the owner's (D-110). PLAT-07 (tagged security) fails while a SECURITY DEFINER
-- function that the API roles can execute is outside the acknowledged baseline, and Settings → Privileges acknowledges
-- one (one.ui_privilege_ack, 0011). Switching PLAT-07 off or down is already the owner's (security review S7, D-065),
-- and so is accepting an integrity baseline (one.ui_baseline_accept); acknowledging a function now is too. The body is
-- 0011's with the owner's gate. Found by the independent audit of 30 Oct. Numbered 0030: 0029 is the coordinator's.

create or replace function one.ui_privilege_ack(p_fn text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
begin
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = p_fn and not acknowledged;
  perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(p_fn, 180), null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

call one.apply_grants();
