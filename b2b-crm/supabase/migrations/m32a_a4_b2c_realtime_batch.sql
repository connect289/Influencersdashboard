-- M32a Addendum 4 (14 Oct, Vikas): the B2C CRM link, final shape, part 1: delivery, the 15-minute batch, new fields.
--   (1) b2c_fields          REPLACED (m22a): nine B2C-writable fields: marketing (active_journey_id, last_campaign_id,
--                           last_marketing_message_at, email_bounced_at), enrollment_verified_at, and the Eduwit stage
--                           b2c_stage / b2c_sub_stage / b2c_stage_comment / owner_name, kept in custom_fields.b2c (no new
--                           columns; a dotted column is a path inside a jsonb column).
--   (2) b2c_link_cfg        REPLACED (m22a): delivery is always 'realtime' (§1).
--   (3) log_event_at        NEW: b2b.log_event with the time the change was made (events are append-only).
--   (4) b2c_record          REPLACED (m31j): contract_version 4, the dotted fields, custom_fields without its b2c key,
--                           consent.marketing_consent (per channel) and consent.opted_out_channels.
--   (5) b2c_sync_lead       REPLACED (m31j): no batched branch; echo suppression for versions whose origin is 'b2c:…'.
--   (6) published_events    REPLACED (m31b): contract_version 4 on every b2c.* / b2b.* envelope and in stored records.
--   (7) b2c_batch_send      REPLACED (m23a): b2c.leads_batch never goes to the B2C CRM's endpoint.
--   (8) b2c_link_settings_save REPLACED (m23b): refuses batched delivery.
--   (9) api_b2c_lead_update REPLACED (m31h): occurred_at (stage_changed_at, the timeline), the custom_fields.b2c fields
--                           and their guard, contact roll-ups that never move backwards, someone else's pending change
--                           synced first, one delivery kick per batch.
--  (10) api_b2c_activity    REPLACED (m22b): the same pre-sync and kick; the event carries the activity's own time.
--  (11) api_b2c_batch       REPLACED (m23b): items in the order given, one kick at the end, contract_version 4.
-- Settings: b2c_link.delivery is set to 'realtime' and the nine new fields join an explicit writable list (b2b.set_setting,
-- as the system). No triggers, no columns, nothing dropped. Every function is created or replaced: re-appliable.

create or replace function b2b.b2c_fields()
returns jsonb language sql immutable set search_path = '' as $fn$
  select jsonb_agg(jsonb_build_object('field', f, 'column', c, 'group', g, 'kind', k, 'write', w, 'max', m) order by o)
    from (values
      (1, 'student', 'name', 'student_name', 'text', 'b2c', 120),
      (2, 'student', 'phone', 'whatsapp_number', 'phone', 'b2b', null),
      (3, 'student', 'alternate_phone', 'alternate_phone', 'phone', 'b2c', null),
      (4, 'student', 'email', 'email_id', 'email', 'b2c', null),
      (5, 'student', 'city', 'city', 'text', 'b2c', 80),
      (6, 'student', 'state', 'state', 'text', 'b2c', 80),
      (7, 'student', 'country', 'country', 'text', 'b2c', 80),
      (8, 'student', 'preferred_language', 'preferred_language', 'text', 'b2c', 40),
      (9, 'student', 'enquirer_relation', 'enquirer_relation', 'text', 'b2c', 40),
      (10, 'student', 'guardian_name', 'guardian_name', 'text', 'b2c', 120),
      (11, 'student', 'guardian_phone', 'guardian_phone', 'phone', 'b2c', null),
      (20, 'education', 'highest_qualification', 'highest_qualification', 'text', 'b2c', 120),
      (21, 'education', 'current_study', 'current_study', 'text', 'b2c', 120),
      (22, 'education', 'academic_score_pct', 'academic_score_pct', 'pct', 'b2c', null),
      (23, 'education', 'work_experience_years', 'work_experience_years_num', 'numeric', 'b2c', 60),
      (24, 'education', 'current_job_role', 'current_job_role', 'text', 'b2c', 120),
      (30, 'interest', 'course', 'interested_course', 'text', 'b2c', 120),
      (31, 'interest', 'specialization', 'interested_specialization', 'text', 'b2c', 120),
      (32, 'interest', 'university', 'interested_university', 'text', 'b2c', 160),
      (33, 'interest', 'programme_level', 'program_level', 'text', 'b2c', 20),
      (34, 'interest', 'study_mode', 'study_mode_preference', 'text', 'b2c', 40),
      (35, 'interest', 'field_of_interest', 'field_of_interest', 'text', 'b2c', 120),
      (36, 'interest', 'enrollment_timeline', 'enrollment_timeline', 'text', 'b2c', 80),
      (37, 'interest', 'annual_budget_inr', 'annual_budget_inr', 'numeric', 'b2c', 100000000),
      (38, 'interest', 'preferred_counseling_time', 'preferred_counseling_time', 'text', 'b2c', 80),
      (40, 'consent', 'contact_consent_at', 'consent_sales_at', 'ts', 'b2b', null),
      (41, 'consent', 'marketing_consent_at', 'consent_marketing_at', 'ts', 'b2b', null),
      (42, 'consent', 'partner_share_consent_at', 'consent_partner_share_at', 'ts', 'b2b', null),
      (43, 'consent', 'consent_text_version', 'consent_text_version', 'text', 'b2b', null),
      (44, 'consent', 'opted_out', 'is_opted_out', 'bool', 'b2b', null),
      (45, 'consent', 'opted_out_at', 'opted_out_at', 'ts', 'b2b', null),
      (50, 'source', 'lead_source', 'lead_source', 'text', 'b2b', null),
      (51, 'source', 'channel', 'channel', 'text', 'b2b', null),
      (52, 'source', 'source_detail', 'source_detail', 'text', 'b2b', null),
      (53, 'source', 'campaign', 'campaign', 'text', 'b2b', null),
      (54, 'source', 'utm_source', 'utm_source', 'text', 'b2b', null),
      (55, 'source', 'utm_medium', 'utm_medium', 'text', 'b2b', null),
      (56, 'source', 'utm_campaign', 'utm_campaign', 'text', 'b2b', null),
      (57, 'source', 'utm_content', 'utm_content', 'text', 'b2b', null),
      (58, 'source', 'utm_term', 'utm_term', 'text', 'b2b', null),
      (59, 'source', 'click_ids', 'click_ids', 'json', 'b2b', null),
      (60, 'source', 'landing_url', 'landing_url', 'text', 'b2b', null),
      (61, 'source', 'referral_code', 'referral_code', 'text', 'b2b', null),
      (62, 'source', 'first_touch_at', 'first_touch_at', 'ts', 'b2b', null),
      (63, 'source', 'last_touch_at', 'last_touch_at', 'ts', 'b2b', null),
      (70, 'qualification', 'lead_status', 'lead_status', 'text', 'b2b', null),
      (71, 'qualification', 'classification', 'lead_classification', 'text', 'b2b', null),
      (72, 'qualification', 'admission_readiness', 'admission_readiness', 'text', 'b2b', null),
      (73, 'qualification', 'eligibility_status', 'eligibility_status', 'text', 'b2b', null),
      (74, 'qualification', 'is_sales_ready', 'is_sales_ready', 'bool', 'b2b', null),
      (75, 'qualification', 'lead_score', 'lead_score', 'int', 'b2c', 100),
      (76, 'qualification', 'temperature', 'temperature', 'temperature', 'b2c', null),
      (80, 'pipeline', 'owner_user_id', 'owner_user_id', 'uuid', 'b2c', null),
      (81, 'pipeline', 'team_id', 'team_id', 'int', 'b2c', 1000000000),
      (82, 'pipeline', 'assigned_at', 'assigned_at', 'ts', 'b2c', null),
      (83, 'pipeline', 'stage', 'stage', 'stage', 'b2c', null),
      (84, 'pipeline', 'sub_stage', 'sub_stage', 'text', 'b2c', 80),
      (85, 'pipeline', 'stage_changed_at', 'stage_changed_at', 'ts', 'b2c', null),
      (86, 'pipeline', 'first_contacted_at', 'first_contacted_at', 'ts', 'b2c', null),
      (87, 'pipeline', 'last_contacted_at', 'last_contacted_at', 'ts', 'b2c', null),
      (88, 'pipeline', 'last_activity_at', 'last_activity_at', 'ts', 'b2c', null),
      (89, 'pipeline', 'contact_attempts', 'contact_attempts', 'int', 'b2c', 10000),
      (90, 'pipeline', 'next_task_due_at', 'next_task_due_at', 'ts', 'b2c', null),
      (100, 'application', 'application_id', 'application_id', 'text', 'b2c', 80),
      (101, 'application', 'application_status', 'application_status', 'text', 'b2c', 60),
      (102, 'application', 'applied_at', 'applied_at', 'ts', 'b2c', null),
      (103, 'application', 'fee_amount_inr', 'fee_amount_inr', 'numeric', 'b2c', 100000000),
      (104, 'application', 'fee_paid_inr', 'fee_paid_inr', 'numeric', 'b2c', 100000000),
      (110, 'enrolment', 'enrollment_status', 'enrollment_status', 'text', 'b2c', 40),
      (111, 'enrolment', 'enrolled_program', 'enrolled_program', 'text', 'b2c', 200),
      (112, 'enrolment', 'enrolled_university', 'enrolled_university', 'text', 'b2c', 200),
      (113, 'enrolment', 'enrollment_date', 'enrollment_date', 'date', 'b2c', null),
      (114, 'enrolment', 'expected_net_revenue_inr', 'expected_net_revenue_inr', 'numeric', 'b2c', 100000000),
      (115, 'enrolment', 'realised_net_revenue_inr', 'realised_net_revenue_inr', 'numeric', 'b2c', 100000000),
      (120, 'lost', 'lost_reason', 'lost_reason', 'text', 'b2c', 200),
      (121, 'lost', 'lost_at', 'lost_at', 'ts', 'b2c', null),
      (91, 'pipeline', 'b2c_stage', 'custom_fields.b2c.stage', 'text', 'b2c', 60),
      (92, 'pipeline', 'b2c_sub_stage', 'custom_fields.b2c.sub_stage', 'text', 'b2c', 120),
      (93, 'pipeline', 'b2c_stage_comment', 'custom_fields.b2c.stage_comment', 'text', 'b2c', 1000),
      (94, 'pipeline', 'owner_name', 'custom_fields.b2c.owner_name', 'text', 'b2c', 120),
      (116, 'enrolment', 'enrollment_verified_at', 'enrollment_verified_at', 'ts', 'b2c', null),
      (125, 'marketing', 'active_journey_id', 'active_journey_id', 'int', 'b2c', 9000000000000000),
      (126, 'marketing', 'last_campaign_id', 'last_campaign_id', 'int', 'b2c', 9000000000000000),
      (127, 'marketing', 'last_marketing_message_at', 'last_marketing_message_at', 'ts', 'b2c', null),
      (128, 'marketing', 'email_bounced_at', 'email_bounced_at', 'ts', 'b2c', null),
      (130, 'other', 'custom_fields', 'custom_fields', 'json', 'b2c', 20000)
    ) v(o, g, f, c, k, w, m);
$fn$;

create or replace function b2b.b2c_link_cfg()
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_object('enabled', true, 'scope', 'held',
                            'writable', (select jsonb_agg(f -> 'field') from jsonb_array_elements(b2b.b2c_fields()) f where f ->> 'write' = 'b2c'))
         || coalesce((select value from b2b.settings where key = 'b2c_link'), '{}')
         -- Addendum 4 §1: the B2C CRM is always served in real time
         || jsonb_build_object('delivery', 'realtime');
$fn$;

/* b2b.log_event with the time the change was made (a B2C counsellor's occurred_at), for the timeline. */
create or replace function b2b.log_event_at(p_type text, p_lead bigint, p_allocation bigint, p_partner bigint, p_payload jsonb, p_at timestamptz)
returns bigint language sql volatile security definer set search_path = '' as $fn$
  insert into b2b.events (type, lead_id, allocation_id, partner_id, actor_type, actor_id, payload, occurred_at)
  select p_type, p_lead, p_allocation, p_partner, a ->> 'type', a ->> 'id', coalesce(p_payload, '{}'), coalesce(p_at, now())
    from (select b2b.actor() a) x
  returning id;
$fn$;


-- ---------- the record, contract version 4 ----------
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
    from (select f ->> 'group' g, jsonb_object_agg(f ->> 'field', v #> string_to_array(f ->> 'column', '.')) obj
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
  -- Addendum 4 §3: custom_fields.b2c is reached through the named fields only; §4: per-channel marketing consent
  r := jsonb_set(r, '{other,custom_fields}', coalesce(r -> 'other' -> 'custom_fields', '{}'::jsonb) - 'b2c');
  r := jsonb_set(r, '{consent}', coalesce(r -> 'consent', '{}'::jsonb)
         || jsonb_build_object('marketing_consent', coalesce(v #> '{custom_fields,b2c,marketing_consent}', '{}'::jsonb),
                               'opted_out_channels', coalesce(to_jsonb(l.opted_out_channels), '[]'::jsonb)));

  return r || jsonb_build_object(
    'id', l.id, 'cycle_no', coalesce(l.cycle_no, 1), 'created_at', l.created_at, 'updated_at', l.updated_at,
    'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
    'deleted', l.deleted_at is not null or l.anonymised_at is not null, 'merged_into_id', l.merged_into_id,
    'held_by_b2c', coalesce(b2b.b2c_holds(l), false),
    'contract_version', 4,
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

-- ---------- the sync: real time only, echo suppression ----------
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
                            'test', coalesce((rec ->> 'is_test')::boolean, false), 'contract_version', 4,
                            'data', jsonb_build_object('version', v_ver, 'seq', v_seq, 'origin', p_origin, 'record', rec));
  -- Addendum 4 §1: always real time. Echo suppression: a version whose only origin is the B2C CRM's own write is not sent
  -- back (it learns the version from its answer), unless an older version is still on its way to that endpoint (then the
  -- newest record must follow, or the B2C CRM would drop the older one as stale and lose someone else's change).
  for w in select * from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, v_type) loop
    if v_scope and coalesce(p_origin, '') like 'b2c:%' and not exists (
         select 1 from b2b.integration_outbox o
          where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')
            and o.event_type in ('b2c.lead_upserted', 'b2c.lead_released') and (o.payload ->> 'lead_id')::bigint = p_lead_id) then
      continue;
    end if;
    update b2b.integration_outbox set status = 'cancelled', last_error = 'superseded by version ' || v_ver
     where endpoint_id = w.id and status in ('pending', 'failed') and event_type in ('b2c.lead_upserted', 'b2c.lead_released')
       and (payload ->> 'lead_id')::bigint = p_lead_id;
    insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
    values (v_type, w.consumer, env, w.id || ':' || (env ->> 'id'), w.id)
    on conflict (idempotency_key) do nothing;
  end loop;
  return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type);
end $fn$;

-- ---------- published events at contract version 4 ----------
create or replace function b2b.published_events(e b2b.events)
returns table (event_type text, envelope jsonb) language plpgsql stable set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_test boolean;
  v_base jsonb;
  v_type text;
begin
  if e.allocation_id is not null then select * into a from b2b.allocations where id = e.allocation_id; end if;
  v_test := coalesce(a.is_test, (select coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) from public.student_leads l where l.id = e.lead_id), false);
  v_type := case e.type
    when 'lead.routed' then 'lead.allocated'
    when 'lead.accepted' then 'lead.accepted'
    when 'b2c.lead_handed_off' then 'b2c.lead_handed_off'
    when 'b2c.lead_reenquired' then 'b2c.lead_reenquired'
    when 'b2c.lead_flagged' then 'b2c.lead_flagged'
    when 'b2c.lead_close_agreed' then 'b2c.lead_close_agreed'
    when 'b2c.lead_requalified' then 'b2c.lead_requalified'
    when 'b2c.lead_reengaged' then 'b2c.lead_reengaged'
    when 'b2c.consent_requested' then 'b2c.consent_requested'
    when 'b2c.consent_closed' then 'b2c.consent_closed'
    when 'partner.stage_applied' then 'lead.status_changed'
    when 'lead.enrolled' then 'lead.enrolled'
  end;
  if v_type is null then return; end if;
  v_base := jsonb_build_object('occurred_at', e.occurred_at, 'lead_id', e.lead_id, 'test', v_test);
  event_type := v_type;
  envelope := v_base
    || case when v_type like 'b2c.%' then jsonb_build_object('contract_version', 4) else '{}'::jsonb end
    || jsonb_build_object('id', 'evt_' || e.id, 'type', v_type,
         'data', coalesce(e.payload, '{}') || jsonb_strip_nulls(jsonb_build_object('allocation_id', e.allocation_id, 'reference', a.reference,
                                                                                   'partner_id', e.partner_id, 'b2c_lane', a.b2c_lane))
                 -- Addendum 4: records stored at version 3 are published at version 4
                 || case when e.payload ? 'contract_version' then jsonb_build_object('contract_version', 4) else '{}'::jsonb end);
  return next;
  if e.type = 'lead.accepted' and (a.mode = 'manual' or a.origin in ('to_partners', 'requalify')) then
    event_type := 'b2b.lead_routed_to_partner';
    envelope := v_base || jsonb_build_object('contract_version', 4, 'id', 'evt_' || e.id || '_r', 'type', event_type,
      'data', jsonb_strip_nulls(jsonb_build_object('allocation_id', a.id, 'reference', a.reference, 'partner_id', a.partner_id, 'origin', a.origin)));
    return next;
  end if;
end $fn$;

-- ---------- b2c.leads_batch: other products only ----------
create or replace function b2b.b2c_batch_send(p_force boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  st jsonb := coalesce((select value from b2b.b2c_link_state where key = 'batch'), '{}');
  v_from bigint := coalesce((st ->> 'seq')::bigint, 0);
  v_to bigint;
  v_n int := 0;
  v_batches int := 0;
  v_items jsonb;
  env jsonb;
  w b2b.webhook_endpoints;
  r record;
begin
  if coalesce(cfg ->> 'batch_other_products', 'false') <> 'true' or not coalesce((cfg ->> 'enabled')::boolean, true) then
    return jsonb_build_object('batches', 0, 'why', 'real time (the B2C CRM needs real time: Addendum 4)');
  end if;
  if not p_force and coalesce((st ->> 'at')::timestamptz, '-infinity') > now() - make_interval(mins => b2b.sync_minutes()) then
    return jsonb_build_object('batches', 0, 'next_at', (st ->> 'at')::timestamptz + make_interval(mins => b2b.sync_minutes()));
  end if;
  select max(seq) into v_to from b2b.b2c_sync;
  v_to := coalesce(v_to, v_from);
  if v_to > v_from then
    -- Addendum 4 §1: b2c.leads_batch is kept for other products and never goes to the B2C CRM's endpoint
    select * into w from b2b.webhook_endpoints where consumer <> 'b2c_crm' and active and b2b.event_subscribed(events, 'b2c.leads_batch')
     order by id limit 1;
    if w.id is not null then
      for r in
        select (row_number() over (order by s.seq) - 1) / 100 grp,
               jsonb_build_object('type', case when s.in_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end, 'lead_id', s.lead_id,
                                  'version', s.version, 'seq', s.seq, 'changed_at', s.changed_at, 'origin', s.origin,
                                  'record', case when s.in_scope then (select b2b.b2c_record(l) from public.student_leads l where l.id = s.lead_id)
                                                 else jsonb_build_object('id', s.lead_id, 'held_by_b2c', false) end) item
          from b2b.b2c_sync s where s.seq > v_from and s.seq <= v_to order by s.seq
      loop
        v_n := v_n + 1;
        insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
        values ('b2c.leads_batch', w.consumer,
                jsonb_build_object('id', 'batch_' || v_from || '_' || v_to || '_' || r.grp, 'type', 'b2c.leads_batch', 'occurred_at', now(), 'lead_id', null, 'test', false,
                                   'data', jsonb_build_object('from_seq', v_from, 'to_seq', v_to, 'part', r.grp + 1, 'leads', jsonb_build_array(r.item))),
                w.id || ':batch_' || v_from || '_' || v_to || '_' || r.grp, w.id)
        on conflict (idempotency_key) do update
          set payload = jsonb_set(b2b.integration_outbox.payload, '{data,leads}', (b2b.integration_outbox.payload -> 'data' -> 'leads') || jsonb_build_array(r.item));
      end loop;
      select count(*) into v_batches from b2b.integration_outbox where endpoint_id = w.id and idempotency_key like w.id || ':batch_' || v_from || '_' || v_to || '_%';
    end if;
  end if;
  update b2b.b2c_link_state set value = jsonb_build_object('seq', v_to, 'at', now(), 'leads', v_n, 'batches', v_batches), updated_at = now() where key = 'batch';
  return jsonb_build_object('batches', v_batches, 'leads', v_n, 'from_seq', v_from, 'to_seq', v_to);
end $fn$;

-- ---------- B2C CRM link settings: real time only ----------
create or replace function b2b.b2c_link_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  v_scope text := coalesce(p ->> 'scope', cfg ->> 'scope', 'held');
  v_delivery text := coalesce(p ->> 'delivery', cfg ->> 'delivery', 'realtime');
  v_writable jsonb := coalesce(p -> 'writable', cfg -> 'writable', '[]');
  v_bad text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'give a reason (it goes in the settings history)' using errcode = '22023'; end if;
  if v_scope not in ('held', 'all') then raise exception 'scope is held or all' using errcode = '22023'; end if;
  if v_delivery <> 'realtime' then raise exception 'the B2C CRM needs real-time delivery (Addendum 4): delivery must be realtime' using errcode = '22023'; end if;
  if jsonb_typeof(v_writable) <> 'array' then raise exception 'writable must be a list of fields' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from jsonb_array_elements_text(v_writable) x
   where not exists (select 1 from jsonb_array_elements(b2b.b2c_fields()) f where f ->> 'field' = x and f ->> 'write' = 'b2c');
  if v_bad is not null then raise exception 'these fields cannot be written by the B2C CRM: %', v_bad using errcode = '22023'; end if;
  perform b2b.set_setting('b2c_link', jsonb_build_object('enabled', coalesce((p ->> 'enabled')::boolean, (cfg ->> 'enabled')::boolean, true), 'scope', v_scope,
                                                         'delivery', v_delivery,
                                                         'writable', (select coalesce(jsonb_agg(distinct x), '[]') from jsonb_array_elements_text(v_writable) x)),
                          trim(p_reason));
  return b2b.b2c_link_cfg();
end $fn$;

-- ---------- POST /v1/b2c/leads/{id} (also each batch update) ----------
create or replace function b2b.api_b2c_lead_update(p_key text, p_lead_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.b2c_key(p_key);
  cfg jsonb := b2b.b2c_link_cfg();
  v_req text := left(trim(coalesce(p ->> 'request_id', '')), 100);
  v_actor jsonb := coalesce(p -> 'actor', '{}');
  l public.student_leads;
  w b2b.b2c_writes;
  f jsonb;
  c jsonb;
  v_key text;
  v_val jsonb;
  v_ver int;
  v_errors jsonb := '{}';
  v_cols jsonb := '{}';
  v_diff jsonb := '{}';
  v_row jsonb;
  v_sql text;
  v_res jsonb;
  v_status int;
  v_oc text[];
  v_oc_cur text[];
  v_oc_set boolean := false;
  v_occ timestamptz := b2b.try_timestamptz(p ->> 'occurred_at');
  v_b2c jsonb := '{}';
  v_b2c_cur jsonb;
  v_path text[];
  v_cur jsonb;
  v_new jsonb;
  v_batch boolean := current_setting('b2b.b2c_in_batch', true) = 'on';
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_req = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'request_id is required (unique per change, reused on retries)'); end if;
  select * into w from b2b.b2c_writes where coalesce(api_key_id, 0) = coalesce((k ->> 'api_key_id')::bigint, 0) and kind = 'update' and request_id = v_req;
  if w.id is not null then return w.response || jsonb_build_object('replayed', true); end if;
  if jsonb_typeof(p -> 'set') is distinct from 'object' or (select count(*) from jsonb_object_keys(p -> 'set')) = 0 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'set must be an object of field: value');
  end if;
  if jsonb_typeof(v_actor) <> 'object' or length(v_actor::text) > 1000 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'actor must be a small object'); end if;
  -- Addendum 4 §2.1: the time the counsellor made the change
  if p ? 'occurred_at' and v_occ is null then return jsonb_build_object('ok', false, 'status', 400, 'error', 'occurred_at must be an ISO 8601 date and time'); end if;
  if v_occ > now() + interval '10 minutes' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'occurred_at is in the future'); end if;
  v_occ := least(coalesce(v_occ, now()), now());

  select * into l from public.student_leads where id = p_lead_id for update;
  -- Addendum 4 §1: someone else's pending change goes out first, so the echo suppression of this write never hides it
  if l.id is not null then perform b2b.b2c_sync_lead(l.id); end if;
  v_ver := b2b.b2c_version(p_lead_id);
  v_b2c_cur := coalesce(l.custom_fields -> 'b2c', '{}');
  v_res := case
    when l.id is null then jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead')
    when l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null
      then jsonb_build_object('ok', false, 'status', 410, 'error', 'the lead was deleted or merged', 'merged_into_id', l.merged_into_id)
    when not b2b.b2c_holds(l) then jsonb_build_object('ok', false, 'status', 409, 'error', 'the B2C CRM does not hold this lead', 'destination', l.destination_type)
    when p ? 'if_version' and nullif(p ->> 'if_version', '')::int is distinct from v_ver
      then jsonb_build_object('ok', false, 'status', 409, 'error', 'version conflict: the lead changed since your copy', 'version', v_ver,
                              'record', b2b.b2c_record(l))
  end;
  if v_res is null then
    for v_key, v_val in select key, value from jsonb_each(p -> 'set') loop
      if v_key = 'other_courses' then
        -- the secondary interests (D30): a list of course names, or comma text; null or [] clears them
        if jsonb_typeof(v_val) not in ('array', 'string', 'null') then v_errors := v_errors || jsonb_build_object(v_key, 'must be a list of course names'); continue; end if;
        if jsonb_typeof(v_val) = 'array' and exists (select 1 from jsonb_array_elements(v_val) e where jsonb_typeof(e) not in ('string', 'object')) then
          v_errors := v_errors || jsonb_build_object(v_key, 'must be a list of course names'); continue;
        end if;
        v_oc := b2b.other_courses_list(v_val);
        if cardinality(v_oc) > 9 then v_errors := v_errors || jsonb_build_object(v_key, 'at most 9 other courses'); continue; end if;
        v_oc_cur := array(select i.course_text from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null order by i.position, i.id);
        if (select array_agg(lower(y) order by lower(y)) from unnest(v_oc) y) is distinct from (select array_agg(lower(y) order by lower(y)) from unnest(v_oc_cur) y) then
          v_oc_set := true;
          v_diff := v_diff || jsonb_build_object('other_courses', jsonb_build_object('from', to_jsonb(v_oc_cur), 'to', to_jsonb(v_oc)));
        end if;
        continue;
      end if;
      select x into f from jsonb_array_elements(b2b.b2c_fields()) x where x ->> 'field' = v_key;
      if f is null then v_errors := v_errors || jsonb_build_object(v_key, 'unknown field'); continue; end if;
      if f ->> 'write' <> 'b2c' or not (cfg -> 'writable') ? v_key then v_errors := v_errors || jsonb_build_object(v_key, 'is read-only for the B2C CRM'); continue; end if;
      c := b2b.b2c_coerce(f, v_val);
      if c ? 'error' then v_errors := v_errors || jsonb_build_object(v_key, c ->> 'error'); continue; end if;
      if f ->> 'kind' = 'stage' and c ->> 'value' is not null and not (c ->> 'value') = any (b2b.b2c_stage_keys()) then
        v_errors := v_errors || jsonb_build_object(v_key, 'is not a known stage'); continue;
      end if;
      if v_key = 'custom_fields' then
        -- Addendum 4 §3: custom_fields.b2c is written through the named fields only, and a generic write keeps it
        if coalesce(c -> 'value', '{}') ? 'b2c' then v_errors := v_errors || jsonb_build_object(v_key, 'custom_fields.b2c is written through b2c_stage, b2c_sub_stage, b2c_stage_comment and owner_name'); continue; end if;
        c := jsonb_build_object('value', jsonb_strip_nulls(coalesce(l.custom_fields, '{}') - 'b2c' || coalesce(c -> 'value', '{}'))
                                         || case when v_b2c_cur <> '{}' then jsonb_build_object('b2c', v_b2c_cur) else '{}'::jsonb end);
      end if;
      -- Addendum 4 §3: the Eduwit stage, sub-stage, comment and counsellor name live in custom_fields.b2c
      if f ->> 'column' like 'custom_fields.b2c.%' then
        v_path := string_to_array(f ->> 'column', '.');
        v_cur := l.custom_fields #> v_path[2:3];
        if v_cur is distinct from (c -> 'value') then
          v_b2c := v_b2c || jsonb_build_object(v_path[3], c -> 'value');
          v_diff := v_diff || jsonb_build_object(v_key, jsonb_build_object('from', v_cur, 'to', c -> 'value'));
        end if;
        continue;
      end if;
      -- Addendum 4 §2.2: contact roll-ups never move backwards, whatever order the batches arrive in
      if v_key in ('first_contacted_at') and (to_jsonb(l) ->> (f ->> 'column')) is not null and c ->> 'value' is not null then
        c := jsonb_build_object('value', to_jsonb(least((to_jsonb(l) ->> (f ->> 'column'))::timestamptz, (c ->> 'value')::timestamptz)));
      elsif v_key in ('last_contacted_at', 'last_activity_at') and (to_jsonb(l) ->> (f ->> 'column')) is not null and c ->> 'value' is not null then
        c := jsonb_build_object('value', to_jsonb(greatest((to_jsonb(l) ->> (f ->> 'column'))::timestamptz, (c ->> 'value')::timestamptz)));
      elsif v_key = 'contact_attempts' and l.contact_attempts is not null and c ->> 'value' is not null then
        c := jsonb_build_object('value', greatest(l.contact_attempts, (c ->> 'value')::numeric));
      end if;
      if (to_jsonb(l) -> (f ->> 'column')) is distinct from (c -> 'value') then
        v_cols := v_cols || jsonb_build_object(f ->> 'column', c -> 'value');
        v_diff := v_diff || jsonb_build_object(v_key, jsonb_build_object('from', to_jsonb(l) -> (f ->> 'column'), 'to', c -> 'value'));
      end if;
    end loop;
    if v_errors <> '{}' then
      v_res := jsonb_build_object('ok', false, 'status', 422, 'error', 'some fields were refused', 'fields', v_errors);
    end if;
  end if;

  if v_res is null and v_diff = '{}' then
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('lead_id', l.id, 'version', v_ver, 'changed', '[]'::jsonb));
  elsif v_res is null then
    perform set_config('b2b.actor', 'b2c_crm', true);
    if v_b2c <> '{}' then
      v_new := jsonb_strip_nulls(v_b2c_cur || v_b2c);
      v_cols := v_cols || jsonb_build_object('custom_fields',
        (coalesce(v_cols -> 'custom_fields', l.custom_fields, '{}') - 'b2c') || case when v_new <> '{}' then jsonb_build_object('b2c', v_new) else '{}'::jsonb end);
    end if;
    if v_cols <> '{}' then
      -- a new stage stamps stage_changed_at unless the caller gave it
      if v_cols ? 'stage' and not v_cols ? 'stage_changed_at' then v_cols := v_cols || jsonb_build_object('stage_changed_at', v_occ); end if;
      v_row := to_jsonb(l) || v_cols;
      select string_agg(format('%I = r.%I', x, x), ', ') into v_sql from jsonb_object_keys(v_cols) x;
      execute format('update public.student_leads t set %s, updated_by = $3 from jsonb_populate_record(null::public.student_leads, $1) r where t.id = $2', v_sql)
        using v_row, l.id, left('b2c_crm:' || coalesce(v_actor ->> 'email', v_actor ->> 'id', 'api'), 120);
    end if;
    if v_oc_set then perform b2b.lead_interests_apply(l.id, to_jsonb(v_oc), 'b2c'); end if;
    perform b2b.log_event_at('b2c.lead_updated', l.id, l.allocation_id, null,
                             jsonb_build_object('changes', v_diff, 'actor', v_actor, 'request_id', v_req, 'api_key', k ->> 'name',
                                                'occurred_at', v_occ, 'received_at', now()), v_occ);
    perform b2b.b2c_sync_lead(l.id, false, 'b2c:' || v_req);
    if not v_batch then perform b2b.outbox_kick(); end if;
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
      'lead_id', l.id, 'version', b2b.b2c_version(l.id), 'changed', (select jsonb_agg(x) from jsonb_object_keys(v_diff) x),
      'record', (select b2b.b2c_record(n) from public.student_leads n where n.id = l.id)));
  end if;

  v_status := (v_res ->> 'status')::int;
  insert into b2b.b2c_writes (api_key_id, request_id, lead_id, kind, actor, changes, status, http_status, error, version_before, version_after, response)
  values ((k ->> 'api_key_id')::bigint, v_req, p_lead_id, 'update', v_actor, coalesce(nullif(v_diff, '{}'), p -> 'set'),
          case when v_status = 200 and v_diff = '{}' then 'unchanged' when v_status = 200 then 'applied' when v_status = 409 and v_res ? 'version' then 'conflict' else 'rejected' end,
          v_status, v_res ->> 'error', v_ver, case when v_status = 200 then b2b.b2c_version(p_lead_id) end,
          v_res - 'record' || case when v_res -> 'result' ? 'record' then jsonb_build_object('result', (v_res -> 'result') - 'record') else '{}' end)
  on conflict do nothing;
  return v_res;
end $fn$;

-- ---------- POST /v1/b2c/leads/{id}/activities (also each batch activity) ----------
create or replace function b2b.api_b2c_activity(p_key text, p_lead_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.b2c_key(p_key);
  v_req text := left(trim(coalesce(p ->> 'request_id', '')), 100);
  v_kind text := lower(coalesce(p ->> 'kind', ''));
  v_at timestamptz := coalesce(b2b.try_timestamptz(p ->> 'at'), now());
  v_actor jsonb := coalesce(p -> 'actor', '{}');
  v_act jsonb;
  l public.student_leads;
  w b2b.b2c_writes;
  v_res jsonb;
  v_contact boolean;
  v_batch boolean := current_setting('b2b.b2c_in_batch', true) = 'on';
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_req = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'request_id is required'); end if;
  select * into w from b2b.b2c_writes where coalesce(api_key_id, 0) = coalesce((k ->> 'api_key_id')::bigint, 0) and kind = 'activity' and request_id = v_req;
  if w.id is not null then return w.response || jsonb_build_object('replayed', true); end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is not null then perform b2b.b2c_sync_lead(l.id); end if;
  v_res := case
    when v_kind not in ('call', 'whatsapp', 'sms', 'email', 'meeting', 'note') then jsonb_build_object('ok', false, 'status', 400, 'error', 'kind must be call, whatsapp, sms, email, meeting or note')
    when v_at > now() + interval '10 minutes' then jsonb_build_object('ok', false, 'status', 400, 'error', 'at is in the future')
    when length(coalesce(p ->> 'note', '')) > 2000 or length(coalesce(p ->> 'outcome', '')) > 80 then jsonb_build_object('ok', false, 'status', 400, 'error', 'note up to 2,000 characters, outcome up to 80')
    when jsonb_typeof(v_actor) <> 'object' or length(v_actor::text) > 1000 then jsonb_build_object('ok', false, 'status', 400, 'error', 'actor must be a small object')
    when l.id is null then jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead')
    when not b2b.b2c_holds(l) then jsonb_build_object('ok', false, 'status', 409, 'error', 'the B2C CRM does not hold this lead')
  end;
  if v_res is null then
    v_act := jsonb_strip_nulls(jsonb_build_object('kind', v_kind, 'at', v_at, 'outcome', nullif(trim(p ->> 'outcome'), ''),
                                                  'duration_seconds', case when (p ->> 'duration_seconds') ~ '^\d{1,6}$' then (p ->> 'duration_seconds')::int end,
                                                  'note', nullif(trim(p ->> 'note'), ''), 'actor', v_actor, 'request_id', v_req));
    perform set_config('b2b.actor', 'b2c_crm', true);
    -- Addendum 4 §2.2: roll-ups from the activity's own time (min / max), each request_id counted once (replays are answered above)
    v_contact := v_kind <> 'note';
    update public.student_leads
       set last_activity_at = greatest(coalesce(last_activity_at, v_at), v_at),
           first_contacted_at = case when v_kind <> 'note' then least(coalesce(first_contacted_at, v_at), v_at) else first_contacted_at end,
           last_contacted_at = case when v_kind <> 'note' then greatest(coalesce(last_contacted_at, v_at), v_at) else last_contacted_at end,
           contact_attempts = coalesce(contact_attempts, 0) + case when v_kind <> 'note' then 1 else 0 end,
           updated_by = left('b2c_crm:' || coalesce(v_actor ->> 'email', v_actor ->> 'id', 'api'), 120)
     where id = l.id;
    perform b2b.log_event_at('b2c.activity', l.id, l.allocation_id, null, v_act || jsonb_build_object('received_at', now()), least(v_at, now()));
    perform b2b.b2c_sync_lead(l.id, false, 'b2c:' || v_req);
    if not v_batch then perform b2b.outbox_kick(); end if;
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('lead_id', l.id, 'version', b2b.b2c_version(l.id)));
  end if;
  insert into b2b.b2c_writes (api_key_id, request_id, lead_id, kind, actor, changes, status, http_status, error, version_after, response)
  values ((k ->> 'api_key_id')::bigint, v_req, p_lead_id, 'activity', v_actor, coalesce(v_act, p), case when (v_res ->> 'ok')::boolean then 'applied' else 'rejected' end,
          (v_res ->> 'status')::int, v_res ->> 'error', case when (v_res ->> 'ok')::boolean then b2b.b2c_version(p_lead_id) end, v_res)
  on conflict do nothing;
  return v_res;
end $fn$;

-- ---------- POST /v1/b2c/leads/batch ----------
create or replace function b2b.api_b2c_batch(p_key text, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  it jsonb;
  res jsonb;
  v_out jsonb := '[]';
  v_ok int := 0;
  v_lead bigint;
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') not between 1 and 200 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'items must be a list of 1 to 200 updates or activities');
  end if;
  -- Addendum 4 §2: applied in the order given (the B2C CRM orders by occurred_at); delivery is kicked once at the end
  perform set_config('b2b.b2c_in_batch', 'on', true);
  for it in select t.x from jsonb_array_elements(p -> 'items') with ordinality t(x, n) order by t.n loop
    v_lead := case when (it ->> 'lead_id') ~ '^\d{1,18}$' then (it ->> 'lead_id')::bigint end;
    res := case
      when jsonb_typeof(it) <> 'object' or v_lead is null then jsonb_build_object('ok', false, 'status', 400, 'error', 'each item needs op and lead_id')
      when it ->> 'op' = 'update' then b2b.api_b2c_lead_update(p_key, v_lead, it - 'op' - 'lead_id')
      when it ->> 'op' = 'activity' then b2b.api_b2c_activity(p_key, v_lead, it - 'op' - 'lead_id')
      else jsonb_build_object('ok', false, 'status', 400, 'error', 'op must be update or activity') end;
    if (res ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', v_lead, 'request_id', it ->> 'request_id', 'op', it ->> 'op') || (res - 'result')
                                        || case when res ? 'result' then jsonb_build_object('version', res -> 'result' -> 'version', 'changed', res -> 'result' -> 'changed') else '{}' end);
  end loop;
  perform set_config('b2b.b2c_in_batch', 'off', true);
  perform b2b.outbox_kick();
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('applied', v_ok, 'items', v_out, 'contract_version', 4));
end $fn$;


-- ---------- settings: real time, and the new fields writable where an explicit list exists ----------
do $s$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'b2c_link'), '{}');
  v_new jsonb := v;
begin
  perform set_config('b2b.actor', 'system', true);
  v_new := v_new || jsonb_build_object('delivery', 'realtime');
  if jsonb_typeof(v -> 'writable') = 'array' then
    v_new := jsonb_set(v_new, '{writable}', (select jsonb_agg(distinct x) from (
               select jsonb_array_elements_text(v -> 'writable') x
               union select unnest(array['b2c_stage', 'b2c_sub_stage', 'b2c_stage_comment', 'owner_name', 'enrollment_verified_at',
                                         'active_journey_id', 'last_campaign_id', 'last_marketing_message_at', 'email_bounced_at'])) y));
  end if;
  if v_new is distinct from v then
    perform b2b.set_setting('b2c_link', v_new, 'Addendum 4: the B2C CRM is served in real time; nine new B2C-writable fields');
  end if;
end $s$;

-- ---------- grants ----------
revoke execute on function b2b.b2c_fields(), b2b.b2c_link_cfg(), b2b.b2c_record(public.student_leads), b2b.b2c_sync_lead(bigint, boolean, text),
                           b2b.b2c_batch_send(boolean), b2b.log_event_at(text, bigint, bigint, bigint, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function b2b.b2c_fields(), b2b.b2c_link_cfg(), b2b.b2c_record(public.student_leads), b2b.b2c_sync_lead(bigint, boolean, text),
                          b2b.b2c_batch_send(boolean), b2b.log_event_at(text, bigint, bigint, bigint, jsonb, timestamptz) to service_role;
