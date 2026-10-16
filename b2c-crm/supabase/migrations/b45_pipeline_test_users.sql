-- B2C CRM b45: a test user's pipeline shows their test leads without asking (as the lead list does). Staging first. Idempotent.
CREATE OR REPLACE FUNCTION b2c.pipeline_board(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
        v_test_user boolean := coalesce((select u.is_test_user from b2c.users u where u.user_id = b2c.uid()), false);
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me) and b2c.in_my_team(v.owner_id)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_test_user) or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;
grant execute on function b2c.pipeline_board(jsonb) to authenticated;
revoke execute on all functions in schema b2c from public, anon;
