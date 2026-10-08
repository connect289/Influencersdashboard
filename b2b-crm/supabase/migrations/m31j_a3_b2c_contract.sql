-- M31j Addendum 3: the B2C CRM contract, version 3 (rulebook PART 5.4, PART 6.1, PART 7, Amendment 1.2, R2/R4/R7;
-- design D12, D45, D47 and section m31j; CONTRACT.md section 8 and 14).
--   (1) b2b.b2c_record       REPLACED (20261007041838_m22a_b2c_link_sync.sql): the record the B2C CRM keeps a copy of now
--                            carries the partner bar, the "Already with other providers" list, the hold, how to handle the
--                            lead (job, assignment, first-contact script), the cause, the first nurture message time, the
--                            welcome request (b2c_actions), qualification {class, missing}, the partner-sharing consent
--                            state and request, the other courses the student asked about, and contract_version 3.
--                            No commission data.
--   (2) b2b.b2c_in_scope     NEW: is a lead in the B2C CRM's sync scope? Held leads always; under scope 'all' every live
--                            lead except Not passed leads (R5: not passed to any CRM) and test leads without a test
--                            hand-off (R1: test leads are never counted) (critic B16, D45).
--   (3) b2b.b2c_sync_lead    REPLACED (20261007043436_m23a_sync_cadence.sql): uses b2c_in_scope; a lead that leaves the
--                            scope gets b2c.lead_released, as before.
--   (4) b2b.consent_state_of NEW: the one-word consent state of CONTRACT 1.3 from b2b.partner_consent(l).
--   (5) b2b.api_b2c_schema   REPLACED (20261007043511_m23b_sync_cadence_admin.sql): contract_version 3, the reason table
--                            by lane, the handling vocabulary, the published and inbound event types, the route-to-partners
--                            error codes, and interest.other_courses as a writable field.
-- Nothing on public.student_leads; no tables, columns, indexes, settings or cron jobs. Every function is created or
-- replaced, so the file can be re-applied. After the deploy the Admin runs b2c_link_resync (batched delivery) so every
-- shared lead is re-published at version 3.

-- ---------- (4) the consent state (CONTRACT 1.3) ----------
/* given | refused | withdrawn | requested | queued | expired | stamp_uncovered | none, from b2b.partner_consent(l).
   Pure: the same input always gives the same word. */
create or replace function b2b.consent_state_of(p_consent jsonb)
returns text language sql immutable set search_path = '' as $fn$
  select case
    when coalesce((p_consent ->> 'given')::boolean, false) then 'given'
    when coalesce((p_consent ->> 'refused')::boolean, false) and p_consent ->> 'last_state' = 'withdrawn' then 'withdrawn'
    when coalesce((p_consent ->> 'refused')::boolean, false) then 'refused'
    when p_consent -> 'open_request' ->> 'status' in ('requested', 'sent', 'unsendable') then 'requested'
    when p_consent -> 'open_request' ->> 'status' = 'queued' then 'queued'
    when (p_consent ->> 'expired_request') is not null then 'expired'
    when coalesce((p_consent ->> 'stamp_uncovered')::boolean, false) then 'stamp_uncovered'
    else 'none' end;
$fn$;

-- ---------- (2) the sync scope (D45) ----------
/* Held leads (b2c_holds) are always in scope. Under b2c_link.scope 'all' a lead is also in scope when it is live (not
   deleted, merged or anonymised), is not a test lead unless its current allocation is a test hand-off, and has no open
   Not passed row for its current fingerprint (a Not passed lead reaches no CRM). */
create or replace function b2b.b2c_in_scope(l public.student_leads)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if coalesce(b2b.b2c_holds(l), false) then return true; end if;
  if coalesce(cfg ->> 'scope', 'held') <> 'all' then return false; end if;
  if l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null then return false; end if;
  if (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
     and not exists (select 1 from b2b.allocations a where a.id = l.allocation_id and a.destination_type = 'in_house' and a.is_test) then
    return false;
  end if;
  if exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null and np.fingerprint = b2b.np_fingerprint(l)) then
    return false;
  end if;
  return true;
end $fn$;

-- ---------- (1) the record, contract version 3 ----------
/* One lead as the B2C CRM sees it: standard field names grouped as in b2c_fields, plus
     allocation   destination, allocation_id, reference, b2c_lane, reason, cause, allocated_at, status, partner,
                  partner_barred_at, partner_bar_reason (R2), already_with_providers (PART 5.4 badge), hold (b2c_hold),
                  job, assignment, first_contact_script (b2c_handling), nurture_first_message_at (PART 6.1),
                  b2c_actions (Amendment 1.2: ["welcome_explore_programmes"] for a not_qualified hand-off of a Witty lead,
                  or of every lead when engine.welcome_for_all_nurture is on)
     qualification + class ('junk' | 'mismatch' | 'qualified' | 'unqualified'), missing [codes]
     consent      + partner_share_given, partner_share_request (the latest request of the current cycle), state (1.3)
     interest     + other_courses [course names, the live secondary interests by position]
     campaign     as before (attribution only), contract_version 3.
   No B2B internals: no scores, candidates or commission rates. */
create or replace function b2b.b2c_record(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v jsonb := to_jsonb(l);
  a b2b.allocations;
  c b2b.lead_campaigns;
  r jsonb;
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  v_bar jsonb;
  v_hold jsonb;
  v_class jsonb;
  v_pc jsonb;
  v_req b2b.consent_requests;
  v_handling jsonb;
  v_days int;
  v_lost_reason text;
  v_actions jsonb := '[]';
  v_other jsonb;
begin
  select * into a from b2b.allocations where id = l.allocation_id;
  select * into c from b2b.lead_campaigns where lead_id = l.id and cycle_no = coalesce(l.cycle_no, 1);
  select coalesce(jsonb_object_agg(g, obj), '{}') into r
    from (select f ->> 'group' g, jsonb_object_agg(f ->> 'field', v -> (f ->> 'column')) obj
            from jsonb_array_elements(b2b.b2c_fields()) f group by 1) x;

  v_bar := b2b.partner_bar(l);
  v_hold := b2b.b2c_hold(l);
  v_class := b2b.lead_class(l);
  v_pc := b2b.partner_consent(l);
  select q.* into v_req from b2b.consent_requests q
   where q.lead_id = l.id and q.cycle_no = coalesce(l.cycle_no, 1)
   order by q.created_at desc, q.id desc limit 1;

  -- how B2C should handle the lead it holds (the same rule as the hand-off event)
  if a.id is not null and a.destination_type = 'in_house' then
    if a.reason = 'partner_lost' then
      select coalesce(y.lost_detail ->> 'lost_reason', l.lost_reason) into v_lost_reason
        from b2b.allocations y
       where y.lead_id = a.lead_id and y.destination_type = 'partner' and y.id < a.id and (y.lost_at is not null or y.outcome = 'lost')
       order by y.id desc limit 1;
      v_lost_reason := coalesce(v_lost_reason, l.lost_reason);
    end if;
    v_handling := b2b.b2c_handling(a.reason, a.b2c_lane, v_bar, v_lost_reason);
    v_days := (v_handling ->> 'nurture_first_message_after_days')::int;
    if a.reason = 'not_qualified' and (b2b.is_witty_lead(l) or coalesce((e ->> 'welcome_for_all_nurture')::boolean, false)) then
      v_actions := '["welcome_explore_programmes"]'::jsonb;
    end if;
  end if;

  select coalesce(jsonb_agg(i.course_text order by i.position, i.id), '[]'::jsonb) into v_other
    from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null;

  r := jsonb_set(r, '{qualification}', coalesce(r -> 'qualification', '{}'::jsonb)
         || jsonb_build_object('class', v_class ->> 'class', 'missing', coalesce(v_class -> 'missing', '[]'::jsonb)));
  r := jsonb_set(r, '{consent}', coalesce(r -> 'consent', '{}'::jsonb)
         || jsonb_build_object(
              'partner_share_given', coalesce((v_pc ->> 'given')::boolean, false),
              'partner_share_request', case when v_req.id is not null then jsonb_build_object(
                  'id', v_req.id, 'status', v_req.status, 'channel', v_req.channel, 'context', v_req.context,
                  'created_at', v_req.created_at, 'expires_at', v_req.expires_at, 'answer', v_req.answer) end,
              'state', b2b.consent_state_of(v_pc)));
  r := jsonb_set(r, '{interest}', coalesce(r -> 'interest', '{}'::jsonb) || jsonb_build_object('other_courses', v_other));

  return r || jsonb_build_object(
    'id', l.id, 'cycle_no', coalesce(l.cycle_no, 1), 'created_at', l.created_at, 'updated_at', l.updated_at,
    'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
    'deleted', l.deleted_at is not null or l.anonymised_at is not null, 'merged_into_id', l.merged_into_id,
    'held_by_b2c', coalesce(b2b.b2c_holds(l), false),
    'contract_version', 3,
    'allocation', jsonb_build_object(
      'destination', l.destination_type, 'allocation_id', l.allocation_id, 'reference', a.reference, 'b2c_lane', a.b2c_lane,
      'reason', l.allocation_reason, 'cause', a.cause, 'allocated_at', l.allocated_at, 'status', a.status,
      'partner', case when l.partner_id is not null then (select jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name))
                                                            from b2b.partners p where p.id = l.partner_id) end,
      'partner_barred_at', v_bar -> 'barred_at', 'partner_bar_reason', v_bar -> 'reason',
      'already_with_providers', b2b.lead_other_providers(l.id),
      'hold', v_hold,
      'job', v_handling -> 'job', 'assignment', v_handling -> 'assignment', 'first_contact_script', v_handling -> 'first_contact_script',
      'nurture_first_message_at', case when v_days is not null then a.created_at + make_interval(days => v_days) end,
      'b2c_actions', v_actions),
    'campaign', case when c.lead_id is not null then jsonb_strip_nulls(jsonb_build_object(
      'platform', c.platform, 'paid', c.paid, 'campaign_id', c.campaign_id, 'campaign_name', c.campaign_name, 'adset_name', c.adset_name,
      'ad_name', c.ad_name, 'form_id', c.form_id, 'utm_source', c.utm_source, 'utm_medium', c.utm_medium, 'utm_campaign', c.utm_campaign)) end);
end $fn$;

-- ---------- (3) the sync, with the version-3 scope ----------
/* Recomputes a lead's record; when it changed, bumps the version and queues one signed webhook (b2c.lead_upserted, or
   b2c.lead_released when the lead leaves the scope) to the B2C endpoint. Same body as m23a except the scope line. */
create or replace function b2b.b2c_sync_lead(p_lead_id bigint, p_force boolean default false, p_origin text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  l public.student_leads;
  prev b2b.b2c_sync;
  v_scope boolean;
  rec jsonb;
  v_hash text;
  v_seq bigint;
  v_ver int;
  v_type text;
  env jsonb;
  w b2b.webhook_endpoints;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, true) then return jsonb_build_object('changed', false, 'why', 'link off'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  select * into prev from b2b.b2c_sync where lead_id = p_lead_id for update;
  if l.id is null then
    if prev.lead_id is null or not prev.in_scope then return jsonb_build_object('changed', false); end if;
    v_scope := false;
    rec := jsonb_build_object('id', p_lead_id, 'deleted', true, 'held_by_b2c', false);
  else
    -- Addendum 3 (D45): held leads; under scope 'all' every live lead except Not passed and test leads without a test hand-off
    v_scope := b2b.b2c_in_scope(l);
    if not v_scope and (prev.lead_id is null or (not prev.in_scope and not p_force)) then return jsonb_build_object('changed', false); end if;
    rec := case when v_scope then b2b.b2c_record(l)
                else jsonb_build_object('id', l.id, 'held_by_b2c', false, 'deleted', l.deleted_at is not null or l.anonymised_at is not null,
                                        'merged_into_id', l.merged_into_id,
                                        'allocation', jsonb_build_object('destination', l.destination_type, 'reason', l.allocation_reason,
                                                                         'allocated_at', l.allocated_at)) end;
  end if;
  v_hash := md5((rec - 'updated_at')::text);
  if prev.lead_id is not null and prev.hash = v_hash and prev.in_scope = v_scope and not p_force then
    return jsonb_build_object('changed', false, 'version', prev.version);
  end if;
  v_seq := nextval('b2b.b2c_sync_seq');
  v_ver := coalesce(prev.version, 0) + 1;
  insert into b2b.b2c_sync (lead_id, seq, version, hash, in_scope, origin, changed_at)
  values (p_lead_id, v_seq, v_ver, v_hash, v_scope, p_origin, now())
  on conflict (lead_id) do update set seq = excluded.seq, version = excluded.version, hash = excluded.hash, in_scope = excluded.in_scope,
                                      origin = excluded.origin, changed_at = excluded.changed_at;
  v_type := case when v_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end;
  env := jsonb_build_object('id', 'lead_' || p_lead_id || '_v' || v_ver, 'type', v_type, 'occurred_at', now(), 'lead_id', p_lead_id,
                            'test', coalesce((rec ->> 'is_test')::boolean, false),
                            'data', jsonb_build_object('version', v_ver, 'seq', v_seq, 'origin', p_origin, 'record', rec));
  -- production cadence: real students go out in the next batch (b2c_batch_send); test leads stay real time for testing
  if cfg ->> 'delivery' = 'batched' and not coalesce((rec ->> 'is_test')::boolean, false) then
    return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type, 'batched', true);
  end if;
  for w in select * from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, v_type) loop
    update b2b.integration_outbox set status = 'cancelled', last_error = 'superseded by version ' || v_ver
     where endpoint_id = w.id and status in ('pending', 'failed') and event_type in ('b2c.lead_upserted', 'b2c.lead_released')
       and (payload ->> 'lead_id')::bigint = p_lead_id;
    insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
    values (v_type, w.consumer, env, w.id || ':' || (env ->> 'id'), w.id)
    on conflict (idempotency_key) do nothing;
  end loop;
  return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type);
end $fn$;

-- ---------- (5) GET /v1/b2c/schema, contract version 3 ----------
/* The field catalogue (now with interest.other_courses, always writable while the lead is held), the stage keys, the
   activity kinds, and the version-3 vocabulary: reasons by lane (CONTRACT 1.2), causes, handling values, hold kinds,
   consent states, b2c_actions, the events we publish, the inbound event types we accept and the route-to-partners
   error codes. */
create or replace function b2b.api_b2c_schema(p_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'contract_version', 3,
    'scope', cfg ->> 'scope', 'enabled', coalesce((cfg ->> 'enabled')::boolean, true),
    'delivery', coalesce(cfg ->> 'delivery', 'realtime'), 'interval_minutes', b2b.sync_minutes(),
    'fields', (select jsonb_agg(jsonb_build_object('field', f ->> 'field', 'group', f ->> 'group', 'kind', f ->> 'kind', 'max', f -> 'max',
                                                   'writable', f ->> 'write' = 'b2c' and (cfg -> 'writable') ? (f ->> 'field')))
                 from jsonb_array_elements(b2b.b2c_fields()) f)
              || jsonb_build_array(jsonb_build_object('field', 'other_courses', 'group', 'interest', 'kind', 'list', 'max', 9::int, 'writable', true)),
    'stages', (select jsonb_agg(jsonb_build_object('key', e ->> 'key', 'rank', e -> 'rank', 'group', e ->> 'group'))
                 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null),
    'activity_kinds', jsonb_build_array('call', 'whatsapp', 'sms', 'email', 'meeting', 'note'),
    'reasons', jsonb_build_object(
      'sales', jsonb_build_array('b2c_created', 'import_choice', 'rule', 'manual', 'manual_route_failed', 'no_partner_offers_programme', 'no_capacity',
                                 'partners_unreachable', 'partner_attempts_exhausted', 'duplicate_cascade', 'no_partner_consent', 'partner_barred', 'b2c_held'),
      'nurture', jsonb_build_array('not_qualified', 'consent_no_answer', 'partner_lost'),
      'test', jsonb_build_array('test_handoff'),
      'retired', jsonb_build_array('paid_campaign')),
    'causes', jsonb_build_array('caps', 'paused', 'criteria', 'rule', 'duplicate_history', 'tried', 'duplicate_cascade', 'partner_attempts_exhausted',
                                'partners_unreachable', 'no_partner_offers_programme', 'no_capacity', 'no_partner_consent'),
    'handling', jsonb_build_object(
      'job', jsonb_build_array('sell', 'qualify', 'nurture'),
      'assignment', jsonb_build_array('round_robin_now', 'unassigned_until_interest', 'previous_counsellor', 'counsellor_choice', 'unassigned'),
      'first_contact_script', jsonb_build_array('neutral_adviser', 'standard')),
    'hold_kinds', jsonb_build_array('barred', 'qualification_nurture', 'selling'),
    'partner_bar_reasons', jsonb_build_array('duplicate', 'lost'),
    'consent_states', jsonb_build_array('given', 'refused', 'withdrawn', 'requested', 'queued', 'expired', 'stamp_uncovered', 'none'),
    'b2c_actions', jsonb_build_array('welcome_explore_programmes'),
    'events', jsonb_build_array('b2c.lead_upserted', 'b2c.lead_released', 'b2c.leads_batch', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                                'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_requalified', 'b2c.lead_reengaged',
                                'b2c.consent_requested', 'b2c.consent_closed', 'b2b.lead_routed_to_partner', 'ping'),
    'inbound', jsonb_build_array('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested',
                                 'b2ccrm.partner_consent', 'b2ccrm.consent_request_sent'),
    'route_to_partners_error_codes', jsonb_build_array('partner_barred', 'no_consent', 'not_held', 'invalid')));
end $fn$;

-- ---------- grants ----------
revoke execute on function b2b.consent_state_of(jsonb), b2b.b2c_in_scope(public.student_leads), b2b.b2c_record(public.student_leads),
                           b2b.b2c_sync_lead(bigint, boolean, text) from public, anon, authenticated;
grant execute on function b2b.consent_state_of(jsonb), b2b.b2c_in_scope(public.student_leads), b2b.b2c_record(public.student_leads),
                          b2b.b2c_sync_lead(bigint, boolean, text) to service_role;
revoke execute on function b2b.api_b2c_schema(text) from public;
grant execute on function b2b.api_b2c_schema(text) to anon, authenticated, service_role;
