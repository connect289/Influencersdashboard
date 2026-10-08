-- M16b: the runtime of status and activity sync and the SLAs.
--   activity_record        one partner_activities row per applied sales event (idempotent by event), rolled up onto the lead
--   partner_event_apply    as in m15c, plus the activity rows and clearing the lead's stale flag when the partner reports
--   sla_met_at / sla_tick  the SLA clocks (B8.5): open on push, met by the partner's activity, breached when due; every 5 minutes
--   partner_event_retry / partner_event_discard   the dead-letter list: retry a failed or held event, or discard it with a reason

/* Records a sales activity from a partner event and rolls it up onto the lead. Direction, duration and counsellor come from
   the event's data (direction, duration_sec or duration, counsellor_name, counsellor_id) or its mapped canonical fields. */
create or replace function b2b.activity_record(e b2b.partner_events, a b2b.allocations, p_kind text, p_outcome text, m jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  d jsonb := coalesce(e.raw -> 'data', '{}');
  f jsonb := coalesce(m -> 'fields', '{}');
  v_at timestamptz;
  v_dir text;
  v_dur int;
  v_id bigint;
begin
  begin v_at := least(coalesce((e.raw ->> 'occurred_at')::timestamptz, e.received_at, now()), now()); exception when others then v_at := coalesce(e.received_at, now()); end;
  v_dir := case when lower(coalesce(d ->> 'direction', '')) in ('inbound', 'incoming', 'in') then 'inbound'
                when lower(coalesce(d ->> 'direction', '')) in ('outbound', 'outgoing', 'out') then 'outbound'
                when p_kind in ('call', 'whatsapp', 'email', 'sms') then 'outbound' end;
  begin v_dur := round(coalesce(d ->> 'duration_sec', d ->> 'duration')::numeric)::int; exception when others then v_dur := null; end;
  if v_dur is not null and (v_dur < 0 or v_dur > 86400) then v_dur := null; end if;
  insert into b2b.partner_activities (allocation_id, lead_id, partner_id, partner_event_id, kind, direction, outcome, duration_sec,
                                      counsellor_name, counsellor_external_id, occurred_at, raw, mapped)
  values (a.id, a.lead_id, a.partner_id, e.id, p_kind, v_dir, left(p_outcome, 100), v_dur,
          left(coalesce(f ->> 'counsellor_name', d ->> 'counsellor_name', d ->> 'counsellor'), 200),
          left(coalesce(f ->> 'counsellor_id', d ->> 'counsellor_id'), 200), v_at, e.raw, m)
  on conflict (partner_event_id) where partner_event_id is not null do nothing
  returning id into v_id;
  if v_id is not null then
    update public.student_leads set last_activity_at = greatest(coalesce(last_activity_at, v_at), v_at), updated_by = 'b2b'
     where id = a.lead_id and allocation_id = a.id and (last_activity_at is null or last_activity_at < v_at);
  end if;
  return v_id;
end $fn$;

create or replace function b2b.partner_event_apply(p_event_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e b2b.partner_events;
  a b2b.allocations;
  pr b2b.mapping_profiles;
  j jsonb;
  d jsonb;
  m jsonb;
  v_kind text;
  v_status text := 'applied';
  v_result text;
  v_unmapped jsonb;
  v_at timestamptz;
  v_connected boolean;
begin
  select * into e from b2b.partner_events where id = p_event_id for update;
  if e.id is null then raise exception 'event not found' using errcode = 'P0002'; end if;
  select * into a from b2b.allocations where id = e.allocation_id;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = e.id;
    return jsonb_build_object('status', 'error', 'result', 'no allocation matches reference or record_id');
  end if;
  j := e.raw;
  d := coalesce(j -> 'data', '{}');
  select * into pr from b2b.mapping_profiles where partner_id = e.partner_id and status = 'active';

  begin
    case e.event_type
      when 'duplicate' then v_result := b2b.apply_partner_duplicate(a.id, d);
      when 'rejected' then v_result := case when a.status in ('pushing', 'pushed') then b2b.apply_rejection(a.id, coalesce(d ->> 'reason', 'rejected'))
                                            else 'ignored: rejection after acceptance' end;
      when 'lost' then
        v_result := case when a.status in ('pushed', 'accepted')
                         then (b2b.apply_partner_lost(a.id, d || jsonb_build_object('lost_reason', d ->> 'reason'))) ->> 'reference'
                         else 'ignored: allocation is ' || a.status end;
        if v_result not like 'ignored%' then perform b2b.activity_record(e, a, 'stage_change', 'lost', null); end if;
      when 'contacted' then
        v_result := b2b.apply_contacted(a.id, j);
        if v_result not like 'ignored%' then
          v_connected := coalesce((d ->> 'connected')::boolean, false);
          perform b2b.activity_record(e, a, 'call', case when v_connected then 'connected' else coalesce(nullif(lower(trim(d ->> 'outcome')), ''), 'not_connected') end, null);
        end if;
      when 'stage', 'update', 'activity' then
        -- the partner's own wording is always kept on the lead
        if e.event_type = 'stage' and a.status in ('pushed', 'accepted') then
          update public.student_leads set partner_stage_raw = left(d ->> 'stage', 200), partner_sub_stage_raw = left(d ->> 'sub_stage', 200),
                 partner_synced_at = now(), updated_by = 'b2b'
           where id = a.lead_id and allocation_id = a.id;
        end if;
        if pr.id is null then
          v_status := 'held_unmapped';
          v_result := 'stored: no mapping published for this partner yet';
        else
          v_kind := e.event_type;
          -- an activity's standard keys (direction, duration, counsellor) are read by activity_record, not mapped as fields
          m := b2b.mapping_in(pr.id, v_kind, case when v_kind = 'activity'
                                                  then d - array['direction', 'duration', 'duration_sec', 'counsellor', 'counsellor_name', 'counsellor_id']
                                                  else d end);
          v_unmapped := coalesce(m -> 'unmapped', '[]');
          perform b2b.mapping_queue_add(e.partner_id, v_unmapped, a.lead_id);
          if a.status in ('pushed', 'accepted', 'closed', 'duplicate') then perform b2b.apply_partner_fields(a.id, pr.id, m); end if;
          if v_kind = 'stage' then
            if not coalesce((m -> 'status' ->> 'matched')::boolean, false) then
              v_status := 'held_unmapped';
              v_result := 'stored: unmapped stage ' || (d ->> 'stage') || coalesce(' / ' || (d ->> 'sub_stage'), '');
            elsif (m -> 'status' ->> 'ignored')::boolean then
              v_status := 'ignored';
              v_result := 'ignored stage: ' || (m -> 'status' ->> 'ignore_reason');
            else
              v_result := b2b.apply_partner_mapped_stage(a.id, m -> 'status', d);
              if v_result like 'stage %' and v_result not like 'stage unchanged%' or v_result like 'lost:%' then
                perform b2b.activity_record(e, a, 'stage_change', m -> 'status' ->> 'stage', m);
              end if;
            end if;
          elsif v_kind = 'activity' then
            if m -> 'activity' is null then
              v_status := 'held_unmapped';
              v_result := 'stored: unmapped activity ' || coalesce(d ->> 'type', '?') || coalesce(' / ' || (d ->> 'outcome'), '');
            else
              begin v_at := least(coalesce((j ->> 'occurred_at')::timestamptz, now()), now()); exception when others then v_at := now(); end;
              perform b2b.log_event('partner.activity', a.lead_id, a.id, a.partner_id,
                                    (m -> 'activity') || jsonb_build_object('occurred_at', v_at, 'partner_type', d ->> 'type', 'partner_outcome', d ->> 'outcome'));
              if m -> 'activity' ->> 'kind' = 'call' then
                perform b2b.apply_contacted(a.id, jsonb_build_object('occurred_at', v_at, 'data', jsonb_build_object('connected', m -> 'activity' ->> 'outcome' = 'connected')));
              end if;
              perform b2b.activity_record(e, a, m -> 'activity' ->> 'kind', m -> 'activity' ->> 'outcome', m);
              v_result := 'activity ' || (m -> 'activity' ->> 'kind') || coalesce(' / ' || (m -> 'activity' ->> 'outcome'), '');
            end if;
          else
            v_result := 'fields updated';
          end if;
          if jsonb_array_length(v_unmapped) > 0 and v_status = 'applied' then
            v_result := v_result || '; ' || jsonb_array_length(v_unmapped) || ' unmapped item(s) queued';
          end if;
        end if;
      else
        v_status := 'held_unmapped';
        v_result := 'stored: unknown event type';
    end case;
    if v_status = 'applied' and v_result like 'ignored%' then v_status := 'ignored'; end if;
    -- any report from the partner ends a "no status update" stale flag
    update public.student_leads set partner_stale_at = null, updated_by = 'b2b'
     where id = a.lead_id and allocation_id = a.id and partner_stale_at is not null;
    update b2b.partner_events set status = v_status, result = left(v_result, 500), mapped = m, mapping_version = pr.version,
           applied_at = case when v_status in ('applied', 'ignored') then now() end
     where id = e.id;
  exception when others then
    update b2b.partner_events set status = 'error', result = left(sqlerrm, 300) where id = e.id;
    return jsonb_build_object('status', 'error', 'result', left(sqlerrm, 300));
  end;
  return jsonb_build_object('status', v_status, 'result', v_result);
end $fn$;

/* Held events are re-applied after a mapping is published, unless the Admin discarded them. */
create or replace function b2b.mapping_reprocess(p_partner_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r record; x jsonb; n int := 0; ok int := 0;
begin
  for r in select id from b2b.partner_events where partner_id = p_partner_id and status = 'held_unmapped' and allocation_id is not null
              and discarded_at is null order by id loop
    x := b2b.partner_event_apply(r.id);
    n := n + 1;
    if x ->> 'status' in ('applied', 'ignored') then ok := ok + 1; end if;
  end loop;
  return jsonb_build_object('reprocessed', n, 'applied', ok);
end $fn$;

-- ---------- SLAs ----------
/* When the partner met an SLA for an allocation, from its activity and reports since the clock started (null: not yet). */
create or replace function b2b.sla_met_at(p_sla text, a b2b.allocations, p_started timestamptz)
returns timestamptz language sql stable set search_path = '' as $fn$
  with st as (select e ->> 'key' k, (e ->> 'rank')::int r from jsonb_array_elements((select value from b2b.settings where key = 'stages')) e where e ->> 'rank' is not null),
       held as (select l.* from public.student_leads l where l.id = a.lead_id and l.allocation_id = a.id),
       held_rank as (select h.stage_changed_at, st.r from held h join st on st.k = h.stage where h.stage_changed_at >= a.pushed_at)
  select case p_sla
    when 'first_attempt' then least(
      (select min(x.occurred_at) from b2b.partner_activities x
        where x.allocation_id = a.id and (x.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting')
                                          or (x.kind = 'stage_change' and x.outcome in (select k from st where r >= 50)))),
      (select h.first_contacted_at from held h where h.first_contacted_at >= a.pushed_at),
      (select hr.stage_changed_at from held_rank hr where hr.r between 50 and 998))
    when 'first_connect' then least(
      (select min(x.occurred_at) from b2b.partner_activities x
        where x.allocation_id = a.id and ((x.kind = 'call' and x.outcome = 'connected') or x.kind = 'meeting'
                                          or (x.kind = 'stage_change' and x.outcome in (select k from st where r between 50 and 998)))),
      (select hr.stage_changed_at from held_rank hr where hr.r between 50 and 998))
    when 'counselling_outcome' then least(
      (select min(x.occurred_at) from b2b.partner_activities x
        where x.allocation_id = a.id and x.kind = 'stage_change' and x.outcome in (select k from st where r >= 60)),
      (select min(pe.received_at) from b2b.partner_events pe
        where pe.allocation_id = a.id and pe.mapped -> 'fields' ->> 'counselling_done' = 'true'),
      (select hr.stage_changed_at from held_rank hr where hr.r >= 60),
      case when a.outcome is not null then a.outcome_at end)
    when 'status_update' then
      (select min(pe.received_at) from b2b.partner_events pe where pe.allocation_id = a.id and pe.received_at > p_started)
    when 'enrollment_proof' then least(
      (select min(x.occurred_at) from b2b.partner_activities x
        where x.allocation_id = a.id and x.kind = 'stage_change' and x.outcome in (select k from st where r between 90 and 998)),
      (select min(pe.received_at) from b2b.partner_events pe
        where pe.allocation_id = a.id and pe.received_at >= p_started and pe.mapped -> 'fields' ? 'enrollment_id'))
  end;
$fn$;

/* Opens, meets and breaches the SLA clocks. Runs every 5 minutes. */
create or replace function b2b.sla_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  al b2b.allocations;
  v_met timestamptz;
  n_open int := 0;
  n_met int := 0;
  n_breach int := 0;
  n_void int := 0;
  v_n int;
begin
  perform set_config('b2b.actor', 'system', true);
  -- 1. clocks open when a lead reaches the partner (pushed in the last 60 days)
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
  select a.id, a.lead_id, a.partner_id, s.sla, a.pushed_at, s.due, a.is_test
    from (select * from b2b.allocations y
           where y.destination_type = 'partner' and y.pushed_at is not null and y.pushed_at > now() - interval '60 days'
             and y.status in ('pushed', 'accepted', 'closed')
             and not exists (select 1 from b2b.sla_checks c where c.allocation_id = y.id)) a
   cross join lateral (values
     ('first_attempt', b2b.working_deadline(a.partner_id, a.pushed_at, 60 * b2b.partner_sla(a.partner_id, 'first_contact_hours'))),
     ('first_connect', b2b.working_days_deadline(a.partner_id, a.pushed_at, b2b.partner_sla(a.partner_id, 'first_connect_days'))),
     ('counselling_outcome', b2b.working_days_deadline(a.partner_id, a.pushed_at, b2b.partner_sla(a.partner_id, 'outcome_days'))),
     ('status_update', a.pushed_at + make_interval(days => b2b.partner_sla(a.partner_id, 'status_update_days')))) s(sla, due)
  on conflict do nothing;
  get diagnostics v_n = row_count; n_open := n_open + v_n;

  -- enrollment proof: from the partner's "enrolled", proof due within proof_days calendar days
  insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
  select a.id, a.lead_id, a.partner_id, 'enrollment_proof', s.t0, s.t0 + make_interval(days => b2b.partner_sla(a.partner_id, 'proof_days')), a.is_test
    from b2b.allocations a
    cross join lateral (select coalesce(
             (select min(x.occurred_at) from b2b.partner_activities x where x.allocation_id = a.id and x.kind = 'stage_change' and x.outcome = 'enrolled'),
             (select l.stage_changed_at from public.student_leads l where l.id = a.lead_id and l.allocation_id = a.id and l.stage = 'enrolled')) as t0) s
   where a.destination_type = 'partner' and a.pushed_at > now() - interval '180 days' and s.t0 is not null
     and exists (select 1 from b2b.sla_checks c where c.allocation_id = a.id)
     and not exists (select 1 from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'enrollment_proof')
  on conflict do nothing;
  get diagnostics v_n = row_count; n_open := n_open + v_n;

  -- 2. a partner that never held the lead owes nothing; status updates stop once the lead leaves the partner or is enrolled
  update b2b.sla_checks c set status = 'void', updated_at = now()
    from b2b.allocations y
   where y.id = c.allocation_id and c.status = 'pending'
     and (y.status in ('duplicate', 'rejected', 'recalled', 'failed')
          or (c.sla = 'status_update' and (y.status not in ('pushed', 'accepted')
              or exists (select 1 from public.student_leads l where l.id = y.lead_id and l.allocation_id = y.id
                           and l.stage in ('enrolled', 'verified', 'commission_booked', 'paid', 'lost')))));
  get diagnostics n_void = row_count;
  update public.student_leads l set partner_stale_at = null, updated_by = 'b2b'
   where l.partner_stale_at is not null
     and not exists (select 1 from b2b.allocations y where y.id = l.allocation_id and y.status in ('pushed', 'accepted'));

  -- 3. met, or breached
  for r in select c.* from b2b.sla_checks c
            where c.status = 'pending' or (c.status = 'breached' and c.due_at > now() - interval '30 days')
            order by c.due_at limit 5000 loop
    select * into al from b2b.allocations where id = r.allocation_id;
    v_met := b2b.sla_met_at(r.sla, al, r.started_at);
    if v_met is not null then
      update b2b.sla_checks set met_at = v_met, status = case when v_met <= r.due_at then 'met' else 'met_late' end, updated_at = now() where id = r.id;
      n_met := n_met + 1;
      if r.sla = 'status_update' and al.status in ('pushed', 'accepted') then
        insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, is_test)
        values (al.id, al.lead_id, al.partner_id, 'status_update', v_met, v_met + make_interval(days => b2b.partner_sla(al.partner_id, 'status_update_days')), al.is_test)
        on conflict do nothing;
      end if;
    elsif r.status = 'pending' and r.due_at < now() then
      update b2b.sla_checks set status = 'breached', breached_at = now(), updated_at = now() where id = r.id;
      n_breach := n_breach + 1;
      if r.sla = 'first_attempt' then
        perform b2b.log_event('alert.sla_breach', r.lead_id, r.allocation_id, r.partner_id,
                              jsonb_build_object('sla', r.sla, 'due_at', r.due_at, 'is_test', r.is_test));
      elsif r.sla = 'status_update' then
        update public.student_leads set partner_stale_at = now(), updated_by = 'b2b'
         where id = r.lead_id and allocation_id = r.allocation_id and partner_stale_at is null;
        perform b2b.log_event('lead.stale', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('last_update_at', r.started_at, 'due_at', r.due_at));
      else
        perform b2b.log_event('partner.sla_breached', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('sla', r.sla, 'due_at', r.due_at));
      end if;
    end if;
  end loop;
  return jsonb_build_object('opened', n_open, 'met', n_met, 'breached', n_breach, 'voided', n_void);
end $fn$;

-- ---------- dead letters ----------
/* Retry an event that failed or is held: the allocation is looked up again (a reference may have arrived late). */
create or replace function b2b.partner_event_retry(p_event_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare e b2b.partner_events; a b2b.allocations; x jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into e from b2b.partner_events where id = p_event_id;
  if e.id is null then raise exception 'event not found' using errcode = 'P0002'; end if;
  if e.status not in ('error', 'held_unmapped') or e.discarded_at is not null then
    raise exception 'only a failed or held event that was not discarded can be retried' using errcode = '22023';
  end if;
  if e.allocation_id is null then
    select * into a from b2b.allocations y
     where y.partner_id = e.partner_id and (y.reference = e.reference or (e.record_id is not null and y.partner_record_id = e.record_id))
     order by y.created_at desc limit 1;
    if a.id is not null then update b2b.partner_events set allocation_id = a.id, lead_id = a.lead_id where id = e.id; end if;
  end if;
  x := b2b.partner_event_apply(e.id);
  perform b2b.log_event('partner.event_retried', coalesce(e.lead_id, a.lead_id), coalesce(e.allocation_id, a.id), e.partner_id,
                        jsonb_build_object('partner_event_id', e.id, 'event_id', e.event_id, 'status', x ->> 'status', 'result', x ->> 'result'));
  return x;
end $fn$;

/* Discard a failed or held event with a reason. The row is kept, with the reason, and leaves the dead-letter list. */
create or replace function b2b.partner_event_discard(p_event_id bigint, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare e b2b.partner_events;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update b2b.partner_events set discarded_at = now(), discard_reason = left(trim(p_reason), 300)
   where id = p_event_id and status in ('error', 'held_unmapped') and discarded_at is null returning * into e;
  if e.id is null then raise exception 'failed or held event not found' using errcode = 'P0002'; end if;
  perform b2b.log_event('partner.event_discarded', e.lead_id, e.allocation_id, e.partner_id,
                        jsonb_build_object('partner_event_id', e.id, 'event_id', e.event_id, 'event_type', e.event_type, 'reason', e.discard_reason));
end $fn$;

revoke execute on function b2b.activity_record(b2b.partner_events, b2b.allocations, text, text, jsonb), b2b.sla_met_at(text, b2b.allocations, timestamptz),
                           b2b.sla_tick(), b2b.partner_event_retry(bigint), b2b.partner_event_discard(bigint, text)
  from public, anon, authenticated;
grant execute on function b2b.activity_record(b2b.partner_events, b2b.allocations, text, text, jsonb), b2b.sla_met_at(text, b2b.allocations, timestamptz),
                          b2b.sla_tick()
  to service_role;
grant execute on function b2b.partner_event_retry(bigint), b2b.partner_event_discard(bigint, text) to authenticated, service_role;

select cron.schedule('b2b-sla-tick', '*/5 * * * *', 'select b2b.sla_tick()');
