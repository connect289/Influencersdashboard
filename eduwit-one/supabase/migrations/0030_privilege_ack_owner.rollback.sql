-- Rollback of 0030 privilege acknowledgement: restores 0011's one.ui_privilege_ack() verbatim (an engineer may
-- acknowledge again). Acknowledgements made meanwhile stay, as rows of one.privilege_baseline and of the audit.

create or replace function one.ui_privilege_ack(p_fn text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
begin
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = p_fn and not acknowledged;
  perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(p_fn, 180), null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

call one.apply_grants();
