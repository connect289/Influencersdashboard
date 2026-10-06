-- M7b2: b2b.route_core now calls b2b.route_decide ('auto'); the every-minute sweep also fills the review queue.

create or replace function b2b.route_core(p_lead_id bigint, p_commit boolean, p_note text default null)
returns jsonb language sql volatile security definer set search_path = '' as $$
  select b2b.route_decide(p_lead_id, p_commit, p_note, 'auto');
$$;

/*
 * Automatic routing, every minute (pg_cron). Flags passed leads that Witty later classifies junk or mismatch (always),
 * then, only while the 'routing' switch is on and the engine enabled, decides every lead that reached its decision
 * point: not passed, B2C (sales or nurture) or a partner. A not-passed lead is decided again only when what the
 * decision saw (classification, course, phone) changes.
 */
create or replace function b2b.route_ready_leads(p_limit int default 50)
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  r record;
  n int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);

  for r in
    insert into b2b.review_flags (lead_id, allocation_id, lead_status, destination_type)
    select l.id, a.id, l.lead_status, a.destination_type
      from public.student_leads l join b2b.allocations a on a.id = l.allocation_id
     where l.destination_type is not null and l.deleted_at is null and upper(coalesce(l.lead_status, '')) in ('JUNK', 'PROGRAM_MISMATCH')
       and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off') and not a.override and not a.is_test
    on conflict (allocation_id, kind) do nothing
    returning lead_id, allocation_id, lead_status, destination_type
  loop
    perform b2b.log_event('lead.flagged', r.lead_id, r.allocation_id, null, jsonb_build_object('lead_status', r.lead_status, 'destination', r.destination_type));
    if r.destination_type = 'in_house' then
      perform b2b.log_event('b2c.lead_flagged', r.lead_id, r.allocation_id, null,
                            jsonb_build_object('lead_id', r.lead_id, 'classification', r.lead_status, 'allocation_id', r.allocation_id));
    end if;
  end loop;

  if not b2b.is_live('routing') or not coalesce((e ->> 'enabled')::boolean, true) or coalesce((e ->> 'kill_switch')::boolean, false) then
    return 0;
  end if;
  for r in
    select l.id from public.student_leads l
     where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
       and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
       and l.created_at > now() - interval '90 days'
       and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null
                         and np.fingerprint = md5(concat_ws('|', upper(coalesce(l.lead_status, '')), coalesce(nullif(l.interested_course, ''), l.field_of_interest, ''), l.whatsapp_number)))
     order by l.created_at
     limit 500
  loop
    exit when n >= least(greatest(p_limit, 1), 200);
    begin
      if (b2b.lead_readiness((select x from public.student_leads x where x.id = r.id)) ->> 'ready')::boolean then
        perform b2b.route_decide(r.id, true, null, 'auto');
        n := n + 1;
      end if;
    exception when others then
      perform b2b.log_event('routing.error', r.id, null, null, jsonb_build_object('error', left(sqlerrm, 300), 'code', sqlstate));
    end;
  end loop;
  return n;
end $$;

revoke execute on function b2b.route_core(bigint, boolean, text), b2b.route_ready_leads(int) from public, anon, authenticated;
grant execute on function b2b.route_core(bigint, boolean, text), b2b.route_ready_leads(int) to service_role;
