-- M16c: health and reconciliation (spec B8.4) and the reads for the screens.
--   reconcile_core          compares B2B's view of a partner's leads with what the partner reported, and optionally with the
--                           partner's own export; each mismatch is an open item (a task for the Admin) until it is gone
--   reconcile_all           nightly, every partner with recent traffic (02:37 India time)
--   reconcile_partner_run   the Admin runs it now, optionally with an uploaded export
--   reconciliation_resolve  the Admin closes an item as resolved or dismissed, with a note
--   partner_sync            the partner's Sync & SLAs tab: health, SLA scorecard, dead letters, reconciliation
--   lead_partner_sync       the lead drawer's Partner sync tab: activities, raw events with their mapping, SLA clocks

/* A timestamp from a partner's text, or null when it is not one. */
create or replace function b2b.try_timestamptz(p_text text)
returns timestamptz language plpgsql stable set search_path = '' as $fn$
begin
  return p_text::timestamptz;
exception when others then
  return null;
end $fn$;

/* p_export: [{reference?, record_id?, stage?, sub_stage?}], the partner's own list of the leads it holds (optional). */
create or replace function b2b.reconcile_core(p_partner_id bigint, p_source text, p_export jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  pr b2b.mapping_profiles;
  v_run bigint;
  v_kinds text[] := array['no_record_id', 'unknown_record', 'stale', 'held_events'];
  v_found jsonb := '[]';
  v_exp jsonb := '[]';
  v_summary jsonb;
  v_new int;
begin
  select * into p from b2b.partners where id = p_partner_id;
  if p.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if p_export is not null and (jsonb_typeof(p_export) <> 'array' or jsonb_array_length(p_export) > 20000) then
    raise exception 'the export must be a list of at most 20,000 rows' using errcode = '22023';
  end if;
  select * into pr from b2b.mapping_profiles where partner_id = p.id and status = 'active';
  insert into b2b.reconciliation_runs (partner_id, source, created_by) values (p.id, p_source, b2b.actor() ->> 'id') returning id into v_run;

  -- the partner never returned its record id (every CRM adapter does; a plain webhook may not)
  v_found := v_found || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'no_record_id', 'item_key', a.id::text, 'allocation_id', a.id, 'lead_id', a.lead_id,
                                        'detail', jsonb_build_object('reference', a.reference, 'pushed_at', a.pushed_at)))
      from b2b.allocations a
     where a.partner_id = p.id and a.status in ('pushed', 'accepted') and a.partner_record_id is null
       and a.pushed_at < now() - interval '1 hour' and p.adapter_type <> 'webhook'), '[]');
  -- events that name no lead we sent
  v_found := v_found || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'unknown_record', 'item_key', e.id::text,
                                        'detail', jsonb_build_object('event_id', e.event_id, 'event_type', e.event_type, 'reference', e.reference,
                                                                     'record_id', e.record_id, 'received_at', e.received_at)))
      from b2b.partner_events e
     where e.partner_id = p.id and e.allocation_id is null and e.discarded_at is null and e.received_at > now() - interval '30 days'), '[]');
  -- leads with no status update for longer than the SLA
  v_found := v_found || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'stale', 'item_key', a.id::text, 'allocation_id', a.id, 'lead_id', a.lead_id,
                                        'detail', jsonb_build_object('reference', a.reference, 'stale_since', l.partner_stale_at, 'stage', l.stage,
                                                                     'partner_stage', l.partner_stage_raw, 'last_synced_at', l.partner_synced_at)))
      from b2b.allocations a join public.student_leads l on l.id = a.lead_id and l.allocation_id = a.id
     where a.partner_id = p.id and a.status in ('pushed', 'accepted') and l.partner_stale_at is not null), '[]');
  -- events that failed or are held for more than an hour
  v_found := v_found || coalesce((
    select jsonb_agg(jsonb_build_object('kind', 'held_events', 'item_key', e.id::text, 'allocation_id', e.allocation_id, 'lead_id', e.lead_id,
                                        'detail', jsonb_build_object('event_id', e.event_id, 'event_type', e.event_type, 'status', e.status,
                                                                     'result', e.result, 'received_at', e.received_at)))
      from b2b.partner_events e
     where e.partner_id = p.id and e.allocation_id is not null and e.status in ('error', 'held_unmapped') and e.discarded_at is null
       and e.received_at < now() - interval '1 hour'), '[]');

  if p_export is not null then
    v_kinds := v_kinds || array['missing_at_partner', 'missing_at_eduwit', 'status_mismatch'];
    select coalesce(jsonb_agg(jsonb_build_object('reference', x0.reference, 'record_id', x0.record_id, 'stage', x0.stage, 'sub_stage', x0.sub_stage,
             'allocation_id', (select a.id from b2b.allocations a
                                where a.partner_id = p.id and (a.reference = x0.reference or (x0.record_id is not null and a.partner_record_id = x0.record_id))
                                order by a.created_at desc limit 1))), '[]')
      into v_exp
      from (select nullif(trim(r ->> 'reference'), '') reference, nullif(trim(r ->> 'record_id'), '') record_id,
                   nullif(trim(r ->> 'stage'), '') stage, nullif(trim(r ->> 'sub_stage'), '') sub_stage
              from jsonb_array_elements(p_export) r where jsonb_typeof(r) = 'object') x0
     where coalesce(x0.reference, x0.record_id) is not null;

    v_found := v_found || coalesce((
      select jsonb_agg(jsonb_build_object('kind', 'missing_at_eduwit', 'item_key', coalesce(x.record_id, x.reference),
                                          'detail', jsonb_build_object('reference', x.reference, 'record_id', x.record_id, 'stage', x.stage)))
        from jsonb_to_recordset(v_exp) x (reference text, record_id text, stage text, sub_stage text, allocation_id bigint)
       where x.allocation_id is null), '[]');
    v_found := v_found || coalesce((
      select jsonb_agg(jsonb_build_object('kind', 'missing_at_partner', 'item_key', a.id::text, 'allocation_id', a.id, 'lead_id', a.lead_id,
                                          'detail', jsonb_build_object('reference', a.reference, 'record_id', a.partner_record_id, 'pushed_at', a.pushed_at)))
        from b2b.allocations a
       where a.partner_id = p.id and a.status in ('pushed', 'accepted') and a.pushed_at < now() - interval '1 day'
         and not exists (select 1 from jsonb_to_recordset(v_exp) x (allocation_id bigint) where x.allocation_id = a.id)), '[]');
    v_found := v_found || coalesce((
      select jsonb_agg(jsonb_build_object('kind', 'status_mismatch', 'item_key', a.id::text, 'allocation_id', a.id, 'lead_id', a.lead_id,
               'detail', jsonb_build_object('reference', a.reference, 'export_stage', x.stage, 'export_sub_stage', x.sub_stage,
                                            'partner_stage', l.partner_stage_raw, 'partner_sub_stage', l.partner_sub_stage_raw, 'stage', l.stage,
                                            'export_maps_to', case when pr.id is not null then
                                              b2b.mapping_in(pr.id, 'stage', jsonb_build_object('stage', x.stage, 'sub_stage', x.sub_stage)) -> 'status' ->> 'stage' end)))
        from jsonb_to_recordset(v_exp) x (reference text, record_id text, stage text, sub_stage text, allocation_id bigint)
        join b2b.allocations a on a.id = x.allocation_id and a.status in ('pushed', 'accepted')
        join public.student_leads l on l.id = a.lead_id and l.allocation_id = a.id
       where x.stage is not null
         and (lower(x.stage) is distinct from lower(trim(l.partner_stage_raw))
              or (x.sub_stage is not null and lower(x.sub_stage) is distinct from lower(trim(l.partner_sub_stage_raw))))), '[]');
  end if;

  with ins as (
    insert into b2b.reconciliation_items (partner_id, run_id, kind, item_key, allocation_id, lead_id, detail)
    select distinct on (f.kind, f.item_key) p.id, v_run, f.kind, f.item_key, f.allocation_id, f.lead_id, coalesce(f.detail, '{}')
      from jsonb_to_recordset(v_found) f (kind text, item_key text, allocation_id bigint, lead_id bigint, detail jsonb)
     where f.item_key is not null
     order by f.kind, f.item_key
    on conflict (partner_id, kind, item_key) where status = 'open'
    do update set run_id = excluded.run_id, detail = excluded.detail, last_seen = now()
    returning (xmax = 0) inserted)
  select count(*) filter (where inserted) into v_new from ins;
  -- whatever this run checked and no longer found is resolved
  update b2b.reconciliation_items set status = 'resolved', resolved_at = now(), note = 'no longer found by run ' || v_run
   where partner_id = p.id and status = 'open' and kind = any (v_kinds) and run_id is distinct from v_run;

  select jsonb_build_object('run_id', v_run, 'new', v_new,
           'open', (select count(*) from b2b.reconciliation_items where partner_id = p.id and status = 'open'),
           'by_kind', coalesce((select jsonb_object_agg(k, n) from (select f ->> 'kind' k, count(*) n from jsonb_array_elements(v_found) f group by 1) z), '{}'),
           'export_rows', case when p_export is not null then jsonb_array_length(v_exp) end)
    into v_summary;
  update b2b.reconciliation_runs set finished_at = clock_timestamp(), summary = v_summary where id = v_run;
  if v_new > 0 then
    perform b2b.log_event('alert.reconciliation_items', null, null, p.id, jsonb_build_object('run_id', v_run, 'new', v_new, 'source', p_source));
  end if;
  return v_summary;
end $fn$;

/* Nightly: every partner with leads pushed in the last 90 days or events in the last 30. */
create or replace function b2b.reconcile_all()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r record; n int := 0; v_new int := 0; x jsonb;
begin
  perform set_config('b2b.actor', 'system', true);
  for r in select p.id from b2b.partners p
            where exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.pushed_at > now() - interval '90 days')
               or exists (select 1 from b2b.partner_events e where e.partner_id = p.id and e.received_at > now() - interval '30 days')
            order by p.id loop
    begin
      x := b2b.reconcile_core(r.id, 'nightly', null);
      n := n + 1;
      v_new := v_new + coalesce((x ->> 'new')::int, 0);
    exception when others then
      perform b2b.log_event('routing.error', null, null, r.id, jsonb_build_object('where', 'reconcile_all', 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return jsonb_build_object('partners', n, 'new_items', v_new);
end $fn$;

create or replace function b2b.reconcile_partner_run(p_partner_id bigint, p_export jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.reconcile_core(p_partner_id, case when p_export is null then 'manual' else 'export' end, p_export);
end $fn$;

create or replace function b2b.reconciliation_resolve(p_id bigint, p_status text, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare r b2b.reconciliation_items;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status is null or p_status not in ('resolved', 'dismissed') then raise exception 'status must be resolved or dismissed' using errcode = '22023'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required' using errcode = '22023'; end if;
  update b2b.reconciliation_items set status = p_status, note = left(trim(p_note), 300), resolved_at = now()
   where id = p_id and status = 'open' returning * into r;
  if r.id is null then raise exception 'open item not found' using errcode = 'P0002'; end if;
  perform b2b.log_event('partner.reconciliation_' || p_status, r.lead_id, r.allocation_id, r.partner_id,
                        jsonb_build_object('item_id', r.id, 'kind', r.kind, 'note', r.note));
end $fn$;

/* The partner's Sync & SLAs tab. Test leads are left out of the scorecard. */
create or replace function b2b.partner_sync(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare p b2b.partners; v_health jsonb; v_score jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_partner_id;
  if p.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;

  with ev as (select e.*, extract(epoch from e.received_at - b2b.try_timestamptz(e.raw ->> 'occurred_at')) lag_s
                from b2b.partner_events e where e.partner_id = p.id and e.received_at > now() - interval '7 days'),
       pu as (select r.* from b2b.push_requests r join b2b.allocations a on a.id = r.allocation_id
               where a.partner_id = p.id and r.sent_at > now() - interval '7 days')
  select jsonb_build_object(
           'last_event_at', (select max(received_at) from b2b.partner_events where partner_id = p.id),
           'events_24h', (select count(*) from ev where received_at > now() - interval '24 hours'),
           'events_7d', (select count(*) from ev),
           'lag_p50_s', (select round(percentile_cont(0.5) within group (order by greatest(lag_s, 0)))::int from ev where lag_s is not null),
           'lag_p95_s', (select round(percentile_cont(0.95) within group (order by greatest(lag_s, 0)))::int from ev where lag_s is not null),
           'errors_7d', (select count(*) from ev where status = 'error'),
           'held', (select count(*) from b2b.partner_events where partner_id = p.id and status = 'held_unmapped' and discarded_at is null),
           'dead_letters', (select count(*) from b2b.partner_events where partner_id = p.id and status in ('error', 'held_unmapped') and discarded_at is null),
           'bad_signatures_7d', (select count(*) from b2b.events where type = 'alert.partner_bad_signature' and partner_id = p.id and occurred_at > now() - interval '7 days'),
           'pushes_7d', (select count(*) from pu),
           'push_failures_7d', (select count(*) from pu where outcome in ('error', 'timeout')),
           'push_backlog', (select count(*) from b2b.allocations where partner_id = p.id and status in ('queued', 'pushing')),
           'last_push_at', (select max(pushed_at) from b2b.allocations where partner_id = p.id),
           'stale_leads', (select count(*) from b2b.allocations a join public.student_leads l on l.id = a.lead_id and l.allocation_id = a.id
                            where a.partner_id = p.id and a.status in ('pushed', 'accepted') and l.partner_stale_at is not null),
           'open_items', (select count(*) from b2b.reconciliation_items where partner_id = p.id and status = 'open'),
           'daily', coalesce((select jsonb_agg(jsonb_build_object('day', d::date, 'events', (select count(*) from ev where (ev.received_at at time zone 'Asia/Kolkata')::date = d::date),
                                                              'errors', (select count(*) from ev where (ev.received_at at time zone 'Asia/Kolkata')::date = d::date and ev.status = 'error')) order by d)
                                from generate_series((now() at time zone 'Asia/Kolkata')::date - 6, (now() at time zone 'Asia/Kolkata')::date, interval '1 day') d), '[]'))
    into v_health;

  select coalesce(jsonb_agg(jsonb_build_object('sla', s.sla, 'met', s.met, 'met_late', s.met_late, 'breached', s.breached, 'pending', s.pending,
                                               'median_working_min', s.med) order by array_position(array['first_attempt', 'first_connect', 'counselling_outcome', 'status_update', 'enrollment_proof'], s.sla)), '[]')
    into v_score
    from (select c.sla,
                 count(*) filter (where c.status = 'met') met, count(*) filter (where c.status = 'met_late') met_late,
                 count(*) filter (where c.status = 'breached') breached, count(*) filter (where c.status = 'pending') pending,
                 case when c.sla in ('first_attempt', 'first_connect', 'counselling_outcome') then
                   (select round(percentile_cont(0.5) within group (order by b2b.working_minutes_between(p.id, c2.started_at, c2.met_at)))::int
                      from (select * from b2b.sla_checks c2 where c2.partner_id = p.id and c2.sla = c.sla and c2.met_at is not null and not c2.is_test
                              and c2.started_at > now() - interval '30 days' order by c2.started_at desc limit 300) c2) end med
            from b2b.sla_checks c
           where c.partner_id = p.id and not c.is_test and c.status <> 'void' and c.started_at > now() - interval '30 days'
           group by c.sla) s;

  return jsonb_build_object(
    'partner', jsonb_build_object('id', p.id, 'name', p.name, 'adapter_type', p.adapter_type, 'status', p.status, 'working_hours', b2b.partner_hours(p.id),
                                  'holidays', coalesce(to_jsonb(p.holidays), '[]'),
                                  'sla', jsonb_build_object('first_contact_hours', b2b.partner_sla(p.id, 'first_contact_hours'), 'first_connect_days', b2b.partner_sla(p.id, 'first_connect_days'),
                                                            'outcome_days', b2b.partner_sla(p.id, 'outcome_days'), 'status_update_days', b2b.partner_sla(p.id, 'status_update_days'),
                                                            'proof_days', b2b.partner_sla(p.id, 'proof_days'))),
    'health', v_health,
    'scorecard', v_score,
    'breaches', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'sla', c.sla, 'lead_id', c.lead_id, 'allocation_id', c.allocation_id, 'due_at', c.due_at,
                                                              'status', c.status, 'met_at', c.met_at, 'name', l.student_name, 'reference', a.reference) order by c.due_at desc)
                            from (select * from b2b.sla_checks c where c.partner_id = p.id and c.status in ('breached', 'met_late') and not c.is_test
                                   order by c.due_at desc limit 50) c
                            join b2b.allocations a on a.id = c.allocation_id left join public.student_leads l on l.id = c.lead_id), '[]'),
    'dead_letters', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'event_id', e.event_id, 'event_type', e.event_type, 'reference', e.reference,
                                                                  'record_id', e.record_id, 'status', e.status, 'result', e.result, 'received_at', e.received_at,
                                                                  'lead_id', e.lead_id, 'raw', e.raw) order by e.id desc)
                                from (select * from b2b.partner_events e where e.partner_id = p.id and e.status in ('error', 'held_unmapped') and e.discarded_at is null
                                       order by e.id desc limit 100) e), '[]'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'lead_id', i.lead_id, 'allocation_id', i.allocation_id, 'detail', i.detail,
                                                           'first_seen', i.first_seen, 'last_seen', i.last_seen, 'name', l.student_name) order by i.last_seen desc, i.id desc)
                         from (select * from b2b.reconciliation_items i where i.partner_id = p.id and i.status = 'open' order by i.last_seen desc limit 200) i
                         left join public.student_leads l on l.id = i.lead_id), '[]'),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'source', r.source, 'started_at', r.started_at, 'finished_at', r.finished_at, 'summary', r.summary) order by r.id desc)
                        from (select * from b2b.reconciliation_runs r where r.partner_id = p.id order by r.id desc limit 5) r), '[]'));
end $fn$;

/* The lead drawer's Partner sync tab. */
create or replace function b2b.lead_partner_sync(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'stale_since', (select partner_stale_at from public.student_leads where id = p_lead_id),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'direction', x.direction, 'outcome', x.outcome, 'duration_sec', x.duration_sec,
                                                                'counsellor', x.counsellor_name, 'occurred_at', x.occurred_at, 'partner', p.name, 'allocation_id', x.allocation_id) order by x.occurred_at desc, x.id desc)
                              from (select * from b2b.partner_activities x where x.lead_id = p_lead_id order by x.occurred_at desc limit 200) x
                              join b2b.partners p on p.id = x.partner_id), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'event_id', e.event_id, 'event_type', e.event_type, 'status', e.status, 'result', e.result,
                                                            'received_at', e.received_at, 'partner', p.name, 'raw', e.raw, 'mapped', e.mapped, 'mapping_version', e.mapping_version,
                                                            'discarded', e.discarded_at is not null, 'discard_reason', e.discard_reason) order by e.id desc)
                          from (select * from b2b.partner_events e where e.lead_id = p_lead_id order by e.id desc limit 100) e
                          join b2b.partners p on p.id = e.partner_id), '[]'),
    'slas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'sla', c.sla, 'started_at', c.started_at, 'due_at', c.due_at, 'met_at', c.met_at,
                                                          'status', c.status, 'partner', p.name, 'allocation_id', c.allocation_id) order by c.started_at desc, c.id)
                        from b2b.sla_checks c join b2b.partners p on p.id = c.partner_id where c.lead_id = p_lead_id), '[]'));
end $fn$;

revoke execute on function b2b.reconcile_core(bigint, text, jsonb), b2b.reconcile_all(), b2b.reconcile_partner_run(bigint, jsonb),
                           b2b.reconciliation_resolve(bigint, text, text), b2b.partner_sync(bigint), b2b.lead_partner_sync(bigint)
  from public, anon, authenticated;
grant execute on function b2b.reconcile_core(bigint, text, jsonb), b2b.reconcile_all() to service_role;
revoke execute on function b2b.try_timestamptz(text) from public, anon, authenticated;
grant execute on function b2b.try_timestamptz(text) to service_role;
grant execute on function b2b.reconcile_partner_run(bigint, jsonb), b2b.reconciliation_resolve(bigint, text, text), b2b.partner_sync(bigint),
                          b2b.lead_partner_sync(bigint)
  to authenticated, service_role;

select cron.schedule('b2b-reconcile-nightly', '7 21 * * *', 'select b2b.reconcile_all()');
