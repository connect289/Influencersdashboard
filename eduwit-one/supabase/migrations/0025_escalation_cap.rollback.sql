-- Rollback of 0025 escalation cap: restores 0003's one.escalate() verbatim (the unbounded level, and with it the failing
-- alerts step on a database with a P1 unacknowledged for more than ten hours).

create or replace function one.escalate() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('alerts'), '{}');
  v_resend integer := coalesce((v_cfg #>> '{escalation,resend_min}')::int, 30);
  v_second integer := coalesce((v_cfg #>> '{escalation,second_contact_min}')::int, 60);
  v_repeat integer := greatest(coalesce((v_cfg #>> '{escalation,repeat_min}')::int, 60), 5);
  v_suppress integer := coalesce((v_cfg #>> '{storm,suppress_min}')::int, 15);
  v_row record;
  v_level integer;
  v_mins numeric;
  v_queued integer := 0;
  v_rerouted integer := 0;
begin
  for v_row in
    select i.id from one.incidents i
     where i.resolved_at is null
       and ((i.alert_state = 'muted' and not one.is_muted(i.check_id, i.app))
            or (i.alert_state = 'suppressed' and not exists (
                  select 1 from one.incidents s where s.check_id = 'ONE-STORM' and s.resolved_at is null
                     and s.routed_at > now() - make_interval(mins => v_suppress))))
  loop
    perform one.route_incident(v_row.id);
    v_rerouted := v_rerouted + 1;
  end loop;
  for v_row in
    select i.id, i.routed_at, i.alert_state from one.incidents i
     where i.resolved_at is null and i.acknowledged_at is null and i.severity = 'P1' and i.routed_at is not null
       and i.alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2')
  loop
    v_mins := extract(epoch from now() - v_row.routed_at) / 60;
    v_level := case when v_mins < v_resend then 0 when v_mins < v_second then 1
                    else 2 + floor((v_mins - v_second) / v_repeat)::int end;
    if v_level >= 1 then
      v_queued := v_queued + one.enqueue_alert(v_row.id, v_level);
      update one.incidents set alert_state = case when v_level = 1 then 'escalated_1' else 'escalated_2' end
       where id = v_row.id and alert_state is distinct from case when v_level = 1 then 'escalated_1' else 'escalated_2' end;
    end if;
  end loop;
  return jsonb_build_object('queued', v_queued, 'rerouted', v_rerouted);
end $$;

call one.apply_grants();
