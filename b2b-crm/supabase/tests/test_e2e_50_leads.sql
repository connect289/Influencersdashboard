-- Phase 1 end-to-end scenarios (spec B20) on STAGING, 50 throwaway leads in one transaction, rolled back.
-- The routing engine runs for real (b2b.route_decide). Partner answers are applied with the same functions the push
-- engine calls on an HTTP answer (apply_created, apply_duplicate, apply_rejection, accept_allocation), so no request
-- leaves the database; the HTTP path itself was covered by the seven mock-partner runs on 6 Oct.
-- Staging fixtures used: partners e2e-down (25%, MBA, MCA), e2e-sync (20%, MBA, BBA, sync dedupe), e2e-async
-- (18%, MBA, BBA, async with a hold window). Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table l50 (k text, n int, lead_id bigint, phone text);

-- exploration on for the BBA group only (set before routing it); everything else commission-first
do $t$
declare
  i int; g int := 0; v_phone text; v_id bigint;
  spec record;
begin
  perform set_config('b2b.actor', 'engine', true);
  for spec in select * from (values
      ('mba', 10, 'MBA', 'PG', true),        -- highest commission wins
      ('bba', 10, 'BBA', 'UG', true),        -- exploration lane
      ('noconsent', 5, 'MBA', 'PG', false),  -- no consent → B2C
      ('nooffer', 5, 'MCA', 'UG', true),     -- no partner offers this programme (MCA is only offered at PG)
      ('dup2', 5, 'BBA', 'UG', true),        -- sync duplicate, then async duplicate → B2C
      ('reject', 5, 'MBA', 'PG', true),      -- rejected by the winner → next partner
      ('hold', 5, 'BBA', 'UG', true),        -- Goa (rule: never Sync) → async partner: no message in its hold window, once after
      ('test', 5, 'MBA', 'PG', true)) s(k, n, course, lvl, consent)
  loop
    for i in 1..spec.n loop
      g := g + 1;
      v_phone := case when spec.k = 'test' then '91900000009' || i else '91987001' || lpad(g::text, 4, '0') end;
      perform public.lead_intake(jsonb_build_object('phone', v_phone, 'source_system', 'crm', 'event_type', 'lead.created',
        'lead', jsonb_strip_nulls(jsonb_build_object('full_name', 'E50 ' || spec.k || ' ' || i, 'email', 'e50.' || spec.k || i || '@example.com',
          'interested_course', spec.course, 'programme_level', spec.lvl, 'study_mode_preference', 'online',
          'state', case when spec.k = 'hold' then 'Goa' else 'Delhi' end,
          'source', 'whatsapp_direct', 'classification', 'WARM',
          'consent_partner_share_at', case when spec.consent then now() end))));
      select id into v_id from public.student_leads where whatsapp_number = v_phone;
      insert into l50 values (spec.k, i, v_id, v_phone);
    end loop;
  end loop;
end $t$;

-- route: exploration share 0.5 while the BBA group is decided, 0 otherwise
do $t$
declare x record;
begin
  perform set_config('b2b.actor', 'engine', true);
  for x in select * from l50 order by k, n loop
    update b2b.settings set value = jsonb_set(value, '{exploration_share}', case when x.k = 'bba' then '0.5' else '0' end::jsonb) where key = 'engine';
    perform b2b.route_decide(x.lead_id, true, 'e2e-50', 'auto');
  end loop;
end $t$;

create temp view cur as
  select x.k, x.n, x.lead_id, a.id alloc_id, a.status, a.destination_type, a.mode, a.reason, a.b2c_lane, a.partner_id, p.slug, a.is_test, a.selection_probability
    from l50 x left join b2b.allocations a on a.id = (select max(id) from b2b.allocations y where y.lead_id = x.lead_id)
    left join b2b.partners p on p.id = a.partner_id;

-- 1. highest commission wins (MBA: e2e-down 25% beats 20% and 18%)
insert into r select 'highest_commission_wins', bool_and(destination_type = 'partner' and slug = 'e2e-down' and mode = 'commission_first'),
  string_agg(distinct coalesce(slug, destination_type) || '/' || mode, ' ') from cur where k = 'mba';
insert into r select 'decision_explained', bool_and(jsonb_array_length(d.candidates) >= 1 and d.mode is not null), count(*)::text
  from b2b.engine_decisions d join l50 x on x.lead_id = d.lead_id where x.k in ('mba', 'bba');
-- 2. exploration lane: some BBA leads explore the lower-commission partner, each with its selection probability
insert into r select 'exploration_lane', count(*) filter (where mode = 'exploration') between 1 and 9
    and bool_and(selection_probability is not null) and bool_and(slug in ('e2e-sync', 'e2e-async')),
  string_agg(slug || '/' || mode, ' ' order by n) from cur where k = 'bba';
-- 3. no consent → B2C with the reason
insert into r select 'no_consent_to_b2c', bool_and(destination_type = 'in_house' and reason = 'no_partner_consent'), string_agg(distinct reason, ' ') from cur where k = 'noconsent';
-- 4. no partner offers the programme → never a partner
insert into r select 'no_offer_not_to_partner', bool_and(coalesce(destination_type, 'none') <> 'partner'),
  string_agg(distinct coalesce(destination_type, 'none') || ':' || coalesce(reason, (select np.reason from b2b.not_passed np where np.lead_id = cur.lead_id), '-'), ' ')
  from cur where k = 'nooffer';

-- partner answers, as the push engine applies them
do $t$
declare x record; a b2b.allocations;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- dup2: first partner says duplicate, the next one too → B2C
  for x in select * from cur where k = 'dup2' loop
    update b2b.allocations set status = 'pushing' where id = x.alloc_id;
    perform b2b.apply_duplicate(x.alloc_id, '{"existing_id": "D1", "created_at": "2026-09-01"}');
    select * into a from b2b.allocations where lead_id = x.lead_id order by id desc limit 1;
    if a.destination_type = 'partner' and a.status = 'queued' then
      update b2b.allocations set status = 'pushing' where id = a.id;
      perform b2b.apply_duplicate(a.id, '{"existing_id": "D2", "created_at": "2026-09-02"}');
    end if;
  end loop;
  -- reject: winner refuses → the lead moves on
  for x in select * from cur where k = 'reject' loop
    update b2b.allocations set status = 'pushing' where id = x.alloc_id;
    perform b2b.apply_rejection(x.alloc_id, 'outside our criteria');
  end loop;
  -- hold: created at the partner, still inside its hold window
  for x in select * from cur where k = 'hold' and destination_type = 'partner' loop
    update b2b.allocations set status = 'pushing' where id = x.alloc_id;
    perform b2b.apply_created(x.alloc_id, 'REC-' || x.n);
  end loop;
end $t$;

-- 5. second duplicate → B2C (duplicate cascade)
insert into r select 'second_duplicate_to_b2c', bool_and(destination_type = 'in_house' and reason = 'duplicate_cascade'),
  string_agg(distinct coalesce(destination_type, '-') || ':' || coalesce(reason, '-'), ' ') from cur where k = 'dup2';
-- 6. rejection → another partner (never the one that refused), with a contract alert
insert into r select 'rejection_moves_on', bool_and(c.destination_type = 'partner' and c.slug <> 'e2e-down' and c.status = 'queued')
    and (select count(*) from b2b.events e join l50 x on x.lead_id = e.lead_id where x.k = 'reject' and e.type = 'alert.partner_rejected') = 5,
  string_agg(distinct coalesce(c.slug, c.destination_type), ' ') from cur c where k = 'reject';
-- 7. no message during the hold window (async partner)
insert into r select 'no_message_in_hold', count(*) filter (where c.status = 'pushed') >= 1
    and not exists (select 1 from b2b.student_notifications n join l50 x on x.lead_id = n.lead_id where x.k = 'hold'),
  string_agg(c.slug || ':' || c.status, ' ') from cur c where k = 'hold';

do $t$
declare x record;
begin
  perform set_config('b2b.actor', 'engine', true);
  for x in select * from cur where k = 'hold' and status = 'pushed' loop perform b2b.accept_allocation(x.alloc_id); end loop;
  for x in select * from cur where k = 'hold' and status = 'pushed' loop perform b2b.accept_allocation(x.alloc_id); end loop; -- twice: still once
  -- a sync acceptance for comparison, and the test leads
  for x in select * from cur where k in ('mba', 'test') and destination_type = 'partner' and status = 'queued' and n <= 2 loop
    update b2b.allocations set status = 'pushing' where id = x.alloc_id;
    perform b2b.apply_created(x.alloc_id, 'REC-' || x.k || x.n);
    perform b2b.accept_allocation(x.alloc_id);
  end loop;
end $t$;

-- 8. once per accepted lead and channel, only after the hold window, never for duplicate or rejecting partners
insert into r select 'message_once_after_hold', bool_and(cnt = 2), string_agg(k || n || ':' || cnt, ' ')
  from (select x.k, x.n, (select count(*) from b2b.student_notifications s where s.allocation_id = c.alloc_id) cnt
          from l50 x join cur c on c.lead_id = x.lead_id where x.k = 'hold' and c.status = 'accepted') z;
insert into r select 'no_message_for_refusing_partner', count(*) = 0, count(*)::text
  from b2b.student_notifications s join b2b.allocations a on a.id = s.allocation_id where a.status in ('duplicate', 'rejected');
-- 9. no message to any real number: test leads never reach a live partner or a message, and nothing is sent
-- (no staging partner has a sandbox endpoint, so test leads go to B2C; with one they would go only to that sandbox)
insert into r select 'test_leads_never_live', bool_and(c.is_test and (c.destination_type = 'in_house' or (select p.test_endpoint is not null from b2b.partners p where p.id = c.partner_id)))
    and not exists (select 1 from b2b.student_notifications s join l50 x on x.lead_id = s.lead_id where x.k = 'test' and s.status <> 'skipped'),
  string_agg(distinct c.destination_type || ':' || coalesce(c.reason, '-'), ' ') from cur c where k = 'test';
insert into r select 'nothing_sent', count(*) = 0, string_agg(distinct s.status, ' ')
  from b2b.student_notifications s join l50 x on x.lead_id = s.lead_id where s.status in ('sending', 'sent', 'delivered', 'read');
-- 10. every lead has an outcome
insert into r select 'fifty_leads_decided', count(*) = 50 and count(*) filter (where c.alloc_id is not null
    or exists (select 1 from b2b.not_passed np where np.lead_id = c.lead_id)) = 50, count(*)::text from cur c;

select name, ok, left(detail, 250) detail from r order by ok, name;
rollback;
