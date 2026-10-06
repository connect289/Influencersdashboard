-- M8c: partner events (B8.2, phase 1 subset), commission disputes and the Admin's push views.
-- Events arrive at POST /v1/partners/{slug}/events (the app passes the raw body through); this function checks the
-- HMAC signature, stores the event raw (idempotent by the partner's event id) and applies what phase 1 understands:
-- duplicate, rejected, lost, contacted, stage. Everything else is kept for the mapping layer (phase 2).

create or replace function b2b.partner_event_ingest(p_slug text, p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  p b2b.partners;
  j jsonb;
  a b2b.allocations;
  v_expected text;
  v_type text;
  v_event_id text;
  v_id bigint;
  v_result text;
  v_ts bigint;
begin
  perform set_config('b2b.actor', 'partner', true);
  select * into p from b2b.partners where slug = lower(trim(p_slug));
  if p.id is null or p.inbound_secret_id is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'unknown partner'); end if;
  if length(coalesce(p_body, '')) > 200000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  v_expected := 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                    convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex');
  if p_signature is distinct from v_expected then
    perform b2b.log_event('alert.partner_bad_signature', null, null, p.id, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  -- find the allocation by our reference (EDW-<id>), else by the partner's record id
  select * into a from b2b.allocations x
   where x.partner_id = p.id and (x.reference = j ->> 'reference' or (j ->> 'record_id' is not null and x.partner_record_id = j ->> 'record_id'))
   order by x.created_at desc limit 1;

  insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
  values (p.id, v_event_id, v_type, j ->> 'reference', j ->> 'record_id', a.id, a.lead_id, j)
  on conflict (partner_id, event_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no lead matches this reference');
  end if;

  begin
    v_result := case v_type
      when 'duplicate' then b2b.apply_partner_duplicate(a.id, j -> 'data')
      when 'rejected' then case when a.status in ('pushing', 'pushed') then b2b.apply_rejection(a.id, coalesce(j -> 'data' ->> 'reason', 'rejected'))
                                else 'ignored: rejection after acceptance' end
      when 'lost' then case when a.status in ('pushed', 'accepted')
                            then (b2b.apply_partner_lost(a.id, coalesce(j -> 'data', '{}') || jsonb_build_object('lost_reason', j -> 'data' ->> 'reason'))) ->> 'reference'
                            else 'ignored: allocation is ' || a.status end
      when 'contacted' then b2b.apply_contacted(a.id, j)
      when 'stage' then b2b.apply_partner_stage(a.id, j)
      else null end;
    update b2b.partner_events set status = case when v_result is null then 'held_unmapped' when v_result like 'ignored%' then 'ignored' else 'applied' end,
           result = coalesce(v_result, 'kept for the mapping layer'), applied_at = case when v_result is not null then now() end
     where id = v_id;
  exception when others then
    update b2b.partner_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
    return jsonb_build_object('ok', false, 'status', 500, 'error', 'could not apply the event; it is stored and will be reviewed');
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', coalesce(v_result, 'stored'));
end $$;

/* Duplicate claims: inside the hold window they cascade; after acceptance they become a commission dispute (24 h). */
create or replace function b2b.apply_partner_duplicate(p_allocation_id bigint, p_data jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  p b2b.partners;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  select * into p from b2b.partners where id = a.partner_id;
  if a.status in ('pushing', 'pushed') then
    return b2b.apply_duplicate(a.id, coalesce(p_data, '{}') || jsonb_build_object('source', 'partner_event'));
  end if;
  if a.status = 'accepted' and a.accepted_at > now() - make_interval(hours => coalesce(p.duplicate_window_hours, 24)) then
    insert into b2b.commission_disputes (allocation_id, lead_id, partner_id, existing_record_id, existing_created_at, proof)
    values (a.id, a.lead_id, a.partner_id, coalesce(p_data ->> 'existing_record_id', p_data ->> 'existing_id'), p_data ->> 'created_at', coalesce(p_data, '{}'))
    on conflict do nothing;
    perform b2b.log_event('alert.commission_dispute', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', p_data, 'reference', a.reference));
    return 'dispute opened: lead stays with the partner';
  end if;
  perform b2b.log_event('partner.late_duplicate_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', p_data, 'status', a.status));
  return 'ignored: duplicate claim outside the window';
end $$;

/* Contact attempts roll up onto the lead (phase 1 subset of B8.2). */
create or replace function b2b.apply_contacted(p_allocation_id bigint, j jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  v_at timestamptz;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.status not in ('pushed', 'accepted') then return 'ignored: allocation is ' || a.status; end if;
  begin v_at := least(coalesce((j ->> 'occurred_at')::timestamptz, now()), now()); exception when others then v_at := now(); end;
  update public.student_leads
     set first_contacted_at = least(coalesce(first_contacted_at, v_at), v_at), last_contacted_at = greatest(coalesce(last_contacted_at, v_at), v_at),
         contact_attempts = coalesce(contact_attempts, 0) + 1, partner_synced_at = now(),
         stage = case when stage in ('allocated', 'sent_to_partner') and coalesce((j -> 'data' ->> 'connected')::boolean, false) then 'contacted' else stage end,
         updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  return 'contact recorded';
end $$;

/* The partner's own stage, stored raw until the mapping layer (phase 2) maps it to Eduwit's stages. */
create or replace function b2b.apply_partner_stage(p_allocation_id bigint, j jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare a b2b.allocations;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.status not in ('pushed', 'accepted') then return 'ignored: allocation is ' || a.status; end if;
  update public.student_leads set partner_stage_raw = left(j -> 'data' ->> 'stage', 200), partner_sub_stage_raw = left(j -> 'data' ->> 'sub_stage', 200),
         partner_synced_at = now(), updated_by = 'b2b'
   where id = a.lead_id and allocation_id = a.id;
  return 'stage stored (mapping in phase 2)';
end $$;

-- ---------- partner lost: one internal function, two gated entry points ----------
create or replace function b2b.apply_partner_lost(p_allocation_id bigint, p_detail jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a b2b.allocations;
  l public.student_leads;
  v_dec bigint;
  v_new bigint;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.status not in ('queued', 'pushing', 'pushed', 'accepted') then
    raise exception 'only an open partner allocation can be marked lost' using errcode = '22023';
  end if;
  select * into l from public.student_leads where id = a.lead_id for update;

  update b2b.allocations set status = 'closed', outcome = 'lost', outcome_at = now(), updated_at = now() where id = a.id;
  insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, reason, settings_version, is_test, actor_type, actor_id, b2c_lane)
  values (a.lead_id, a.cycle_no, a.segment, b2b.lead_interest(l), 'fallback', 'in_house', 'partner_lost',
          (select version from b2b.settings where key = 'engine'), a.is_test, b2b.actor() ->> 'type', b2b.actor() ->> 'id', 'nurture')
  returning id into v_dec;
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, status, mode, attempt_no, reason, engine_decision_id, is_test, b2c_lane)
  values (a.lead_id, a.cycle_no, a.segment, 'in_house', 'handed_off', 'fallback', a.attempt_no + 1, 'partner_lost', v_dec, a.is_test, 'nurture')
  returning id into v_new;
  update b2b.allocations set reference = 'EDW-' || v_new where id = v_new;
  -- the partner-sync columns (partner_record_id, partner_stage_raw…) stay as history
  update public.student_leads set destination_type = 'in_house', partner_id = null, allocation_id = v_new, allocated_at = now(),
         allocation_reason = 'partner_lost', updated_by = 'b2b' where id = a.lead_id;
  perform b2b.log_event('b2c.lead_handed_off', a.lead_id, v_new, a.partner_id, jsonb_build_object(
    'lead_id', a.lead_id, 'b2c_lane', 'nurture', 'reason', 'partner_lost', 'decision_id', v_dec, 'reference', 'EDW-' || v_new,
    'partner_id', a.partner_id, 'partner_record_id', coalesce(a.partner_record_id, l.partner_record_id),
    'lost_reason', p_detail ->> 'lost_reason', 'partner_status', coalesce(p_detail ->> 'status', l.partner_stage_raw),
    'partner_sub_status', coalesce(p_detail ->> 'sub_status', l.partner_sub_stage_raw), 'partner_last_activity', p_detail ->> 'last_activity_at',
    'partners_tried', (select coalesce(jsonb_agg(jsonb_build_object('partner_id', x.partner_id, 'status', x.status, 'outcome', x.outcome) order by x.created_at), '[]')
                         from b2b.allocations x where x.lead_id = a.lead_id and x.destination_type = 'partner')));
  return jsonb_build_object('allocation_id', v_new, 'reference', 'EDW-' || v_new);
end $$;

/* The Admin's (or a service's) entry point; partner events call b2b.apply_partner_lost directly after their signature check. */
create or replace function b2b.allocation_partner_lost(p_allocation_id bigint, p_detail jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.apply_partner_lost(p_allocation_id, p_detail);
end $$;


-- ---------- Admin ----------
create or replace function b2b.dispute_resolve(p_id bigint, p_uphold boolean, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare d b2b.commission_disputes;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required' using errcode = '22023'; end if;
  update b2b.commission_disputes set status = case when p_uphold then 'upheld' else 'rejected' end, note = left(trim(p_note), 300),
         resolved_at = now(), resolved_by = auth.uid()::text
   where id = p_id and status = 'open' returning * into d;
  if d.id is null then raise exception 'dispute not found or already resolved' using errcode = 'P0002'; end if;
  -- upheld: no commission on this lead and it is left out of conversion stats
  if p_uphold then update b2b.allocations set outcome = 'duplicate_upheld', outcome_at = now() where id = d.allocation_id; end if;
  perform b2b.log_event('dispute.resolved', d.lead_id, d.allocation_id, d.partner_id, jsonb_build_object('upheld', p_uphold, 'note', left(trim(p_note), 300)));
end $$;

/* Push health for the Routing overview and the partner page. */
create or replace function b2b.push_overview(p_partner_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from b2b.allocations
                            where destination_type = 'partner' and (p_partner_id is null or partner_id = p_partner_id)
                              and created_at > now() - interval '30 days' group by 1) x), '{}'),
    'retrying', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'reference', a.reference, 'lead_id', a.lead_id, 'partner_id', a.partner_id,
                            'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id),
                            'attempts', a.push_attempts, 'next_push_at', a.next_push_at, 'last_error', a.last_error) order by a.next_push_at)
                          from b2b.allocations a where a.status = 'pushing' and a.push_attempts > 0 and a.last_error is not null
                            and (p_partner_id is null or a.partner_id = p_partner_id)), '[]'),
    'requests', coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object('reference', a.reference) order by q.sent_at desc)
                          from (select * from b2b.push_requests q where p_partner_id is null or q.allocation_id in (select id from b2b.allocations where partner_id = p_partner_id)
                                 order by sent_at desc limit 20) q join b2b.allocations a on a.id = q.allocation_id), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'partner_id', e.partner_id, 'event_type', e.event_type, 'reference', e.reference,
                            'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.received_at desc)
                        from (select * from b2b.partner_events where p_partner_id is null or partner_id = p_partner_id order by received_at desc limit 20) e), '[]'),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'lead_id', d.lead_id, 'lead_name', l.student_name, 'reference', a.reference,
                            'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.partner_id),
                            'existing_record_id', d.existing_record_id, 'existing_created_at', d.existing_created_at, 'created_at', d.created_at) order by d.created_at desc)
                          from b2b.commission_disputes d join b2b.allocations a on a.id = d.allocation_id left join public.student_leads l on l.id = d.lead_id
                         where d.status = 'open' and (p_partner_id is null or d.partner_id = p_partner_id)), '[]'),
    'duplicate_rate_7d', (select round(count(*) filter (where status = 'duplicate')::numeric / nullif(count(*) filter (where status in ('duplicate', 'pushed', 'accepted', 'rejected', 'closed')), 0), 3)
                            from b2b.allocations where destination_type = 'partner' and not is_test and created_at > now() - interval '7 days'
                              and (p_partner_id is null or partner_id = p_partner_id)));
end $$;

/* What the Admin sees about a partner's connection (never the secrets). */
create or replace function b2b.partner_connection(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare p b2b.partners;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_partner_id;
  if p.id is null then return null; end if;
  return jsonb_build_object('adapter_type', p.adapter_type, 'api_base_url', p.api_base_url, 'test_endpoint', p.test_endpoint,
    'auth_type', coalesce(p.outbound_auth ->> 'type', case when p.outbound_secret_id is null then null else 'bearer' end), 'auth_header', p.outbound_auth ->> 'header',
    'has_token', p.outbound_secret_id is not null, 'has_inbound_secret', p.inbound_secret_id is not null,
    'events_url_path', '/v1/partners/' || p.slug || '/events',
    'test_accepted', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')),
    'push', b2b.push_overview(p.id));
end $$;

-- go-live checklist: credentials and test leads are real now (a test lead accepted by the partner's sandbox)
create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', false, 'available', false),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    jsonb_build_object('key', 'credentials', 'done', p.api_base_url is not null and (p.outbound_secret_id is not null or p.outbound_auth ->> 'type' = 'none')
                                                     and p.inbound_secret_id is not null, 'available', true),
    jsonb_build_object('key', 'mapping',     'done', false, 'available', false),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')), 'available', true)
  );
$$;

revoke execute on function b2b.apply_partner_duplicate(bigint, jsonb), b2b.apply_contacted(bigint, jsonb), b2b.apply_partner_stage(bigint, jsonb), b2b.apply_partner_lost(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.apply_partner_duplicate(bigint, jsonb), b2b.apply_contacted(bigint, jsonb), b2b.apply_partner_stage(bigint, jsonb), b2b.apply_partner_lost(bigint, jsonb) to service_role;
-- the event endpoint is public by design: the function itself checks the partner's HMAC signature
revoke execute on function b2b.partner_event_ingest(text, text, text, text) from public;
grant execute on function b2b.partner_event_ingest(text, text, text, text) to anon, authenticated, service_role;
revoke execute on function b2b.dispute_resolve(bigint, boolean, text), b2b.push_overview(bigint), b2b.partner_connection(bigint) from public, anon;
grant execute on function b2b.dispute_resolve(bigint, boolean, text), b2b.push_overview(bigint), b2b.partner_connection(bigint) to authenticated, service_role;
