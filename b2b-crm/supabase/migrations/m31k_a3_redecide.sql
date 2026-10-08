-- M31k (Addendum 3, PART 2 re-decisions, R2 / R3 / R4 re-enquiries, PART 7 answers from Witty): re-decisions and re-enquiries.
--   requalify_lead     a lead in B2C qualification nurture (R7 not_qualified, R8 consent_no_answer) that is qualified again goes
--                      back through the rules: the nurture hand-off is closed (outcome 'requalified'), the lead's columns are
--                      cleared and route_decide runs in the 'requalify' context (R7 is not re-checked there: it is checked here
--                      first); b2c.lead_requalified is published. A qualified lead without recorded consent is asked first
--                      (consent_request_create, context 'nurture') and waits (PART 7.2: the request repeats in nurture)
--   requalify_tick     every minute while routing is live: candidates from an updated_at cursor with a 10-minute overlap and a
--                      1-minute safe horizon, due rechecks (nurture_watch.recheck_at), consent answers since the cursor and a
--                      6-hour catch-up; a fingerprint of the qualification fields skips unchanged leads; Witty leads wait for the
--                      PART 2 chat gate (escalation, final programme, 30 minutes idle) when engine.requalify.wait_for_chat_gate
--   reenquiry_apply    a new enquiry on a routed lead: recorded in lead_reenquiries and shown to the Admin; partner-held leads
--                      (lost-in-grace included) get the internal lead.reenquired and are never re-routed (R3); B2C-held and
--                      barred leads get b2c.lead_reenquired with the hold, the bar, an interest flag and a reactivation hint (R2,
--                      R4); still-unqualified nurture leads get b2c.lead_reengaged at most once a day
--   reenquiry_tick     every minute whatever the routing switch: public.touchpoints after the cursor (by created_at, never Witty's
--                      occurred_at, 2-minute safe horizon) and inbound public.w2_messages after reenquiry_quiet_hours of silence;
--                      Witty's consent.partner_* touchpoints go to consent_from_witty (m31e) and are not re-enquiries;
--                      touchpoints from b2b / b2c_crm / crm are never re-enquiries (the consent stamp lead_intake writes is 'b2b')
--   reenquiry_catchup  hourly: the same filters over the last 26 hours with id <= cursor (idempotent through the unique
--                      touchpoint_id / message_id and the consent engine's own idempotency)
--   reenquiry_ack      Admin: acknowledges 1-500 re-enquiries
-- Depends on m31a (lead_reenquiries, nurture_watch, scan_cursors, consent_requests, engine.requalify / reenquiry_quiet_hours),
-- m31b (b2c_hold, partner_bar, partner_consent, lead_attribution, chat_gate, stats_num via m31c), m31d (lead_class, is_chat_lead),
-- m31e (consent_request_create, consent_from_witty), m31f (route_decide with p_how 'requalify'). Witty's tables are read only,
-- fully qualified; nothing here touches public.student_leads' shape (B2B writes only the pointer columns it already wrote).
-- Replaces: none (new functions and cron jobs only). Every tick is time-boxed (2 s), sets lock_timeout 2 s and runs one row per
-- exception block, so Witty's lead_intake never waits long on a B2B row lock.

-- ---------- (0) scanner cursors (m31a seeds them; kept here so a fresh database has them before the first tick) ----------
insert into b2b.scan_cursors (key, last_id, last_at, updated_at) values
  ('touchpoints', (select coalesce(max(t.id), 0) from public.touchpoints t), now(), now()),
  ('w2_messages', (select coalesce(max(m.id), 0) from public.w2_messages m), now(), now()),
  ('requalify', null, now() - interval '1 day', now())
on conflict (key) do nothing;

-- ---------- (1) the qualification fingerprint ----------
/* What a nurture re-decision depends on: the label, the course fields, the identity fields, the contact, the consent state,
   the number of live secondary interests and the last field-completing event (b2c.lead_updated / lead.edited, which
   lead_class's 'completed_by_b2c' basis reads). requalify_tick skips a lead whose fingerprint is unchanged. */
create or replace function b2b.nurture_fingerprint(l public.student_leads)
returns text language plpgsql stable security definer set search_path = '' as $fn$
declare
  c jsonb := b2b.partner_consent(l);
begin
  return md5(concat_ws('|',
    upper(coalesce(l.lead_status, '')), coalesce(l.lead_stage, ''), coalesce(l.is_bot_paused::text, ''),
    coalesce(l.interested_course, ''), coalesce(l.field_of_interest, ''), coalesce(l.interested_specialization, ''),
    coalesce(l.program_level, ''), coalesce(l.study_mode_preference, ''), coalesce(l.interested_university, ''),
    coalesce(l.university_preference, ''),
    coalesce(l.student_name, ''), coalesce(l.email_id, ''), coalesce(l.whatsapp_number, ''), coalesce(l.phone_verified_at::text, ''),
    coalesce(c ->> 'given', ''), coalesce(c ->> 'refused', ''), coalesce(c ->> 'last_state', ''),
    coalesce(c -> 'open_request' ->> 'id', ''), coalesce(c -> 'open_request' ->> 'status', ''),
    coalesce(c -> 'expired_request' ->> 'id', ''), coalesce(c -> 'last_request' ->> 'answer', ''),
    (select count(*) from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null)::text,
    coalesce((select max(e.id) from b2b.events e where e.lead_id = l.id and e.type in ('b2c.lead_updated', 'lead.edited'))::text, '')));
end $fn$;

-- ---------- (2) requalify_lead ----------
/* R7 -> R9 (PART 2 'Re-decisions', Changes table rows 2 and 3). Locks the lead. Refuses (requalified false + why) when the
   lead is not in an open B2C qualification-nurture hold, is partner-barred, is a test lead, is not qualified, or routing is
   off. A qualified lead whose partner-sharing consent is neither given nor refused is asked (consent_request_create, context
   'nurture'; the request id and a recheck at its expiry go to nurture_watch) and the result is {requalified false, waiting
   'consent'}. Otherwise, in the caller's transaction: the nurture allocation is closed (outcome 'requalified'), the lead's
   allocation columns are cleared, lead.requalified is logged, route_decide(lead, true, p_why, 'requalify') decides, and
   b2c.lead_requalified is published whatever the B2C link scope. Callers: requalify_tick, m31e consent_answer ('consent yes'
   / 'consent no' on a nurture hold). Result: {requalified, waiting 'consent'|null, why, closed_allocation_id, decision_id,
   allocation_id, reference, destination, reason, b2c_lane, route (route_decide's result)} + consent_request when asked. */
create or replace function b2b.requalify_lead(p_lead_id bigint, p_why text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_policy text := coalesce(e ->> 'consent_policy', 'ask');
  v_why text := left(coalesce(nullif(trim(p_why), ''), 'requalified'), 300);
  v_hold jsonb;
  v_bar jsonb;
  v_class jsonb;
  v_cons jsonb;
  v_req jsonb;
  v jsonb;
  v_missing text;
  v_no jsonb := jsonb_build_object('requalified', false, 'waiting', null, 'why', null, 'closed_allocation_id', null, 'decision_id', null,
                                   'allocation_id', null, 'reference', null, 'destination', null, 'reason', null, 'b2c_lane', null, 'route', null);
begin
  select * into l from public.student_leads x where x.id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if l.deleted_at is not null or l.merged_into_id is not null then
    return v_no || jsonb_build_object('why', 'deleted or merged lead');
  end if;
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then
    return v_no || jsonb_build_object('why', 'test lead');
  end if;
  v_hold := b2b.b2c_hold(l);
  if v_hold is null or coalesce(v_hold ->> 'kind', '') <> 'qualification_nurture' or not coalesce((v_hold ->> 'open')::boolean, false) then
    return v_no || jsonb_build_object('why', 'not in B2C qualification nurture' ||
      case when v_hold is null then '' else ' (' || coalesce(v_hold ->> 'kind', '?') || case when coalesce((v_hold ->> 'open')::boolean, false) then '' else ', closed' end || ')' end);
  end if;
  v_bar := b2b.partner_bar(l);
  if v_bar is not null then
    return v_no || jsonb_build_object('why', 'partner-barred (' || coalesce(v_bar ->> 'reason', '?') || '): B2C only');
  end if;
  if not b2b.is_live('routing') then return v_no || jsonb_build_object('why', 'routing is off'); end if;
  if not coalesce((e ->> 'enabled')::boolean, true) then return v_no || jsonb_build_object('why', 'the routing engine is disabled'); end if;

  v_class := b2b.lead_class(l);
  if coalesce(v_class ->> 'class', '') <> 'qualified' then
    select string_agg(x, ', ') into v_missing from jsonb_array_elements_text(case when jsonb_typeof(v_class -> 'missing') = 'array' then v_class -> 'missing' else '[]'::jsonb end) x;
    return v_no || jsonb_build_object('why', 'not qualified: ' || coalesce(v_missing, v_class ->> 'reason', v_class ->> 'class', '?'));
  end if;

  -- R8 inside nurture: ask first, route on an answer (PART 7.2: the request repeats in nurture)
  v_cons := b2b.partner_consent(l);
  if not coalesce((v_cons ->> 'given')::boolean, false) and not coalesce((v_cons ->> 'refused')::boolean, false) and v_policy = 'ask' then
    v_req := b2b.consent_request_create(l.id, 'nurture', null);
    insert into b2b.nurture_watch (lead_id, allocation_id, class, missing, qualified_at, consent_request_id, recheck_at, checked_at, times)
    values (l.id, (v_hold ->> 'allocation_id')::bigint, v_class ->> 'class', coalesce(v_class -> 'missing', '[]'::jsonb), now(),
            (v_req ->> 'request_id')::bigint, coalesce((v_req ->> 'expires_at')::timestamptz, now() + interval '15 minutes') + interval '1 minute', now(), 1)
    on conflict (lead_id) do update
      set allocation_id = excluded.allocation_id, class = excluded.class, missing = excluded.missing,
          qualified_at = coalesce(b2b.nurture_watch.qualified_at, now()),
          consent_request_id = coalesce(excluded.consent_request_id, b2b.nurture_watch.consent_request_id),
          recheck_at = excluded.recheck_at, checked_at = now(), times = b2b.nurture_watch.times + 1;
    return v_no || jsonb_build_object('waiting', 'consent',
                                      'why', coalesce(nullif(v_req ->> 'why', ''), 'awaiting partner-sharing consent'),
                                      'consent_request', v_req);
  end if;

  -- close the nurture hand-off and decide again
  select * into a from b2b.allocations x where x.id = (v_hold ->> 'allocation_id')::bigint for update;
  if a.id is null or a.status <> 'handed_off' then
    return v_no || jsonb_build_object('why', 'the nurture hand-off is no longer open');
  end if;
  update b2b.allocations set status = 'closed', outcome = 'requalified', outcome_at = now(), updated_at = now() where id = a.id;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null,
         allocation_reason = null, updated_by = 'b2b'
   where id = l.id and allocation_id = a.id;
  perform b2b.log_event('lead.requalified', l.id, a.id, null, jsonb_build_object(
    'why', v_why, 'closed_allocation_id', a.id, 'reference', a.reference, 'basis', v_class ->> 'basis', 'hold_reason', a.reason));

  v := b2b.route_decide(l.id, true, v_why, 'requalify');

  perform b2b.log_event('b2c.lead_requalified', l.id, (v ->> 'allocation_id')::bigint, (v ->> 'partner_id')::bigint, jsonb_build_object(
    'lead_id', l.id, 'closed_allocation_id', a.id, 'closed_reference', a.reference, 'reference', v ->> 'reference',
    'decision_id', (v ->> 'decision_id')::bigint, 'destination', v ->> 'destination', 'reason', v ->> 'reason',
    'b2c_lane', v ->> 'b2c_lane', 'partner_id', (v ->> 'partner_id')::bigint, 'why', v_why, 'contract_version', 3));

  insert into b2b.nurture_watch (lead_id, allocation_id, class, missing, qualified_at, recheck_at, checked_at, times)
  values (l.id, a.id, v_class ->> 'class', coalesce(v_class -> 'missing', '[]'::jsonb), now(), null, now(), 1)
  on conflict (lead_id) do update
    set class = excluded.class, missing = excluded.missing, qualified_at = coalesce(b2b.nurture_watch.qualified_at, now()),
        recheck_at = null, checked_at = now(), times = b2b.nurture_watch.times + 1;

  return jsonb_build_object('requalified', true, 'waiting', null, 'why', v_why, 'closed_allocation_id', a.id,
                            'decision_id', (v ->> 'decision_id')::bigint, 'allocation_id', (v ->> 'allocation_id')::bigint,
                            'reference', v ->> 'reference', 'destination', v ->> 'destination', 'reason', v ->> 'reason',
                            'b2c_lane', v ->> 'b2c_lane', 'route', v);
end $fn$;

-- ---------- (3) requalify_tick ----------
/* Re-decides qualification-nurture leads without a trigger (D15). Runs only while routing is live, engine.enabled and
   engine.requalify.enabled; one tick at a time; lock_timeout 2 s; 2 s time box; p_limit null = engine.requalify.max_per_run
   (25), clamped 1-100. Candidates, in this order: (a) leads with updated_at in (cursor - 10 min, now() - 1 min) whose open
   allocation is an in_house hand-off with reason not_qualified or consent_no_answer; (b) nurture_watch rows with recheck_at
   due; (c) leads with a consent request answered since the cursor; (d) catch-up: open nurture leads not checked for 6 hours,
   oldest first, 10 per run. A lead whose fingerprint is unchanged and has nothing due is only marked checked. A qualified chat
   lead waits for the PART 2 gate (chat_gate since the hand-off) when requalify.wait_for_chat_gate; otherwise requalify_lead
   runs in its own exception block (a lock timeout rechecks in 1 minute, another error in 15 minutes + routing.error). The
   cursor advances to now() - 1 min when every (a) candidate was seen, else to the last updated_at processed. */
create or replace function b2b.requalify_tick(p_limit int default 25)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  rq jsonb;
  v_limit int;
  v_wait_gate boolean;
  v_prev_lt text := current_setting('lock_timeout', true);
  t0 timestamptz := clock_timestamp();
  v_cursor timestamptz;
  v_new_cursor timestamptz;
  v_horizon timestamptz := now() - interval '1 minute';
  v_max_seen timestamptz;
  v_complete boolean := true;
  r record;
  l public.student_leads;
  nw b2b.nurture_watch;
  v_fp text;
  v_class jsonb;
  v_gate jsonb;
  v_res jsonb;
  n_scanned int := 0;
  n_req int := 0;
  n_wait int := 0;
  n_recheck int := 0;
  n_err int := 0;
  v_zero jsonb := jsonb_build_object('ran', false, 'scanned', 0, 'requalified', 0, 'waiting_consent', 0, 'rechecks', 0, 'errors', 0, 'cursor_at', null);
begin
  perform set_config('b2b.actor', 'engine', true);
  rq := case when jsonb_typeof(e -> 'requalify') = 'object' then e -> 'requalify' else '{}'::jsonb end;
  v_wait_gate := coalesce((rq ->> 'wait_for_chat_gate')::boolean, true);
  v_limit := greatest(1, least(100, coalesce(p_limit, (b2b.stats_num(rq -> 'max_per_run'))::int, 25)));
  if not b2b.is_live('routing') then return v_zero || jsonb_build_object('why', 'routing is off'); end if;
  if not coalesce((e ->> 'enabled')::boolean, true) then return v_zero || jsonb_build_object('why', 'the routing engine is disabled'); end if;
  if not coalesce((rq ->> 'enabled')::boolean, true) then return v_zero || jsonb_build_object('why', 'requalification is disabled (engine.requalify.enabled)'); end if;
  if not pg_try_advisory_xact_lock(hashtext('b2b.requalify_tick')) then return v_zero || jsonb_build_object('why', 'another tick is running'); end if;

  insert into b2b.scan_cursors (key, last_id, last_at, updated_at) values ('requalify', null, now() - interval '1 day', now()) on conflict (key) do nothing;
  select c.last_at into v_cursor from b2b.scan_cursors c where c.key = 'requalify' for update;
  v_cursor := coalesce(v_cursor, now() - interval '1 day');
  perform set_config('lock_timeout', '2000', true);

  for r in
    with holds as (
      select sl.id as lead_id, sl.updated_at, a.id as allocation_id, a.created_at as hold_since
        from public.student_leads sl
        join b2b.allocations a on a.id = sl.allocation_id
       where sl.destination_type = 'in_house' and a.destination_type = 'in_house' and a.status = 'handed_off'
         and a.reason in ('not_qualified', 'consent_no_answer')
         and sl.deleted_at is null and sl.merged_into_id is null
         and not coalesce(sl.is_test, false) and not b2b.is_test_phone(sl.whatsapp_number)
    ),
    cand as (
      select h.lead_id, h.updated_at, h.allocation_id, h.hold_since, 1 as prio, false as due
        from holds h where h.updated_at > v_cursor - interval '10 minutes' and h.updated_at < v_horizon
      union all
      select h.lead_id, h.updated_at, h.allocation_id, h.hold_since, 2, true
        from holds h join b2b.nurture_watch w on w.lead_id = h.lead_id where w.recheck_at is not null and w.recheck_at <= now()
      union all
      select h.lead_id, h.updated_at, h.allocation_id, h.hold_since, 3, false
        from holds h where exists (select 1 from b2b.consent_requests q where q.lead_id = h.lead_id and q.answered_at > v_cursor - interval '10 minutes')
      union all
      (select h.lead_id, h.updated_at, h.allocation_id, h.hold_since, 4, true
         from holds h left join b2b.nurture_watch w on w.lead_id = h.lead_id
        where w.checked_at is null or w.checked_at < now() - interval '6 hours'
        order by w.checked_at nulls first, h.updated_at, h.lead_id limit 10)
    )
    select c.lead_id, c.allocation_id, c.hold_since, c.updated_at, min(c.prio) as prio, bool_or(c.due) as due
      from cand c
     group by c.lead_id, c.allocation_id, c.hold_since, c.updated_at
     order by min(c.prio), c.updated_at, c.lead_id
  loop
    if n_scanned >= v_limit or clock_timestamp() - t0 > interval '2 seconds' then
      if r.prio = 1 then v_complete := false; end if;   -- (a) rows come first: an unprocessed one keeps the cursor behind
      exit;
    end if;
    n_scanned := n_scanned + 1;
    if r.prio = 1 then v_max_seen := greatest(coalesce(v_max_seen, r.updated_at), r.updated_at); end if;
    begin
      select x.* into l from public.student_leads x where x.id = r.lead_id;
      if l.id is null or l.allocation_id is distinct from r.allocation_id or coalesce(l.destination_type, '') <> 'in_house' then
        continue;
      end if;
      select w.* into nw from b2b.nurture_watch w where w.lead_id = l.id;
      v_fp := b2b.nurture_fingerprint(l);
      if nw.lead_id is not null and nw.fingerprint = v_fp and not r.due then
        update b2b.nurture_watch set checked_at = now() where lead_id = l.id;
        continue;
      end if;
      v_class := b2b.lead_class(l);
      insert into b2b.nurture_watch (lead_id, allocation_id, fingerprint, class, missing, qualified_at, recheck_at, checked_at, times)
      values (l.id, r.allocation_id, v_fp, v_class ->> 'class', coalesce(v_class -> 'missing', '[]'::jsonb),
              case when v_class ->> 'class' = 'qualified' then now() end, null, now(), 1)
      on conflict (lead_id) do update
        set allocation_id = excluded.allocation_id, fingerprint = excluded.fingerprint, class = excluded.class, missing = excluded.missing,
            qualified_at = case when excluded.class = 'qualified' then coalesce(b2b.nurture_watch.qualified_at, now()) else null end,
            recheck_at = null, checked_at = now(), times = b2b.nurture_watch.times + 1;
      if coalesce(v_class ->> 'class', '') <> 'qualified' then
        continue;
      end if;
      if v_wait_gate and b2b.is_chat_lead(l) then
        v_gate := b2b.chat_gate(l, r.hold_since);
        if not coalesce((v_gate ->> 'open')::boolean, false) then
          update b2b.nurture_watch set recheck_at = coalesce((v_gate ->> 'decide_after')::timestamptz, now() + interval '5 minutes') where lead_id = l.id;
          n_recheck := n_recheck + 1;
          continue;
        end if;
      end if;
      v_res := b2b.requalify_lead(l.id, 'qualified in B2C nurture (' || coalesce(v_class ->> 'basis', 'fields') || ')');
      if coalesce((v_res ->> 'requalified')::boolean, false) then
        n_req := n_req + 1;
      elsif v_res ->> 'waiting' = 'consent' then
        n_wait := n_wait + 1;
        -- the request just created is part of the consent state: store the fingerprint it leaves behind
        update b2b.nurture_watch w set fingerprint = b2b.nurture_fingerprint(x) from public.student_leads x where x.id = l.id and w.lead_id = l.id;
      end if;
    exception
      when lock_not_available or deadlock_detected then
        n_err := n_err + 1;
        begin
          insert into b2b.nurture_watch (lead_id, allocation_id, recheck_at, checked_at) values (r.lead_id, r.allocation_id, now() + interval '1 minute', now())
          on conflict (lead_id) do update set recheck_at = excluded.recheck_at;
        exception when others then null;
        end;
      when others then
        n_err := n_err + 1;
        begin
          perform b2b.log_event('routing.error', r.lead_id, r.allocation_id, null,
                                jsonb_build_object('where', 'requalify_tick', 'error', left(sqlerrm, 300), 'code', sqlstate));
        exception when others then null;
        end;
        begin
          insert into b2b.nurture_watch (lead_id, allocation_id, recheck_at, checked_at) values (r.lead_id, r.allocation_id, now() + interval '15 minutes', now())
          on conflict (lead_id) do update set recheck_at = excluded.recheck_at;
        exception when others then null;
        end;
    end;
  end loop;

  v_new_cursor := greatest(v_cursor, case when v_complete then v_horizon else coalesce(v_max_seen, v_cursor) end);
  update b2b.scan_cursors set last_at = v_new_cursor, updated_at = now() where key = 'requalify';
  perform set_config('lock_timeout', coalesce(nullif(v_prev_lt, ''), '0'), true);
  return jsonb_build_object('ran', true, 'scanned', n_scanned, 'requalified', n_req, 'waiting_consent', n_wait, 'rechecks', n_recheck,
                            'errors', n_err, 'cursor_at', v_new_cursor);
end $fn$;

-- ---------- (4) reenquiry_apply ----------
/* One new enquiry on a routed lead (D18, critic B28). p_kind touchpoint | witty_message; p_ref = public.touchpoints.id or
   public.w2_messages.id; p_meta {source_system, source, event_type, campaign, at, interest}. Holder: 'partner' when the lead's
   allocation is an open partner allocation (queued/pushing/pushed/accepted, lost-in-grace included), else from b2c_hold:
   barred | qualification_nurture | selling (-> b2c_selling). Counted: non-Witty touchpoints and Witty messages for every
   holder; Witty touchpoints only lead.interest (all holders) and lead.escalated (B2C holders). Debounce: a Witty message
   within reenquiry_quiet_hours of a recorded Witty message is skipped; a lead.interest within the quiet hours of a recorded
   row sets interest = true on that row (merged) and B2C holders get one b2c.lead_reenquired with interest true. Events:
   partner -> lead.reenquired (internal); barred / b2c_selling -> b2c.lead_reenquired; qualification_nurture (still
   unqualified) -> b2c.lead_reengaged at most once in 24 h (nurture_watch.reengaged_at); a qualified nurture lead is left to
   requalify_tick. Never writes allocations or student_leads. Returns {recorded, id, holder, event, merged, why}. */
create or replace function b2b.reenquiry_apply(p_lead_id bigint, p_kind text, p_ref bigint, p_meta jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  nw b2b.nurture_watch;
  x b2b.lead_reenquiries;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_quiet numeric := least(greatest(coalesce(b2b.stats_num(e -> 'reenquiry_quiet_hours'), 24), 1), 168);
  v_window interval;
  v_hold jsonb;
  v_bar jsonb;
  v_class jsonb;
  v_attr jsonb;
  v_holder text;
  v_at timestamptz;
  v_src text := p_meta ->> 'source_system';
  v_evt text := p_meta ->> 'event_type';
  v_witty boolean;
  v_interest boolean;
  v_lane text;
  v_reason text;
  v_id bigint;
  v_ev bigint;
  v_event text;
  v_no jsonb := jsonb_build_object('recorded', false, 'id', null, 'holder', null, 'event', null, 'merged', false, 'why', null);
begin
  if p_kind not in ('touchpoint', 'witty_message') then
    raise exception 'unknown re-enquiry kind: %', coalesce(p_kind, '?') using errcode = '22023';
  end if;
  if p_ref is null then raise exception 'a touchpoint or message id is required' using errcode = '22023'; end if;
  v_window := make_interval(mins => round(v_quiet * 60)::int);
  begin v_at := (p_meta ->> 'at')::timestamptz; exception when others then v_at := null; end;
  v_at := coalesce(v_at, now());

  select * into l from public.student_leads z where z.id = p_lead_id;
  if l.id is null then return v_no || jsonb_build_object('why', 'lead not found'); end if;
  if l.deleted_at is not null or l.merged_into_id is not null then return v_no || jsonb_build_object('why', 'deleted or merged lead'); end if;
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then return v_no || jsonb_build_object('why', 'test lead'); end if;
  if l.destination_type is null then return v_no || jsonb_build_object('why', 'not routed yet: the sweep decides'); end if;

  v_witty := p_kind = 'witty_message' or lower(coalesce(v_src, '')) = 'witty';
  v_interest := coalesce((p_meta ->> 'interest')::boolean, false) or (v_witty and v_evt = 'lead.interest');

  -- the holder (R3 first: an open partner allocation, lost-in-grace included)
  select * into a from b2b.allocations z where z.id = l.allocation_id;
  if a.id is not null and a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted') then
    v_holder := 'partner';
  else
    v_hold := b2b.b2c_hold(l);
    v_bar := b2b.partner_bar(l);
    v_holder := case v_hold ->> 'kind' when 'barred' then 'barred' when 'qualification_nurture' then 'qualification_nurture' when 'selling' then 'b2c_selling' end;
    if v_holder is null then
      if v_bar is not null then v_holder := 'barred';
      elsif l.destination_type = 'in_house' then v_holder := 'b2c_selling';
      else return v_no || jsonb_build_object('why', 'no open hold on the lead');
      end if;
    end if;
    v_lane := coalesce(v_hold ->> 'lane', a.b2c_lane);
    v_reason := coalesce(v_hold ->> 'reason', a.reason);
  end if;

  -- what counts (critic B28): Witty's classification noise is not a new enquiry
  if v_witty and p_kind = 'touchpoint' then
    if v_evt = 'lead.interest' then
      null;
    elsif v_evt = 'lead.escalated' and v_holder <> 'partner' then
      null;
    else
      return v_no || jsonb_build_object('holder', v_holder, 'why', 'not a re-enquiry signal (' || coalesce(v_evt, '?') || ')');
    end if;
  end if;
  if v_holder = 'qualification_nurture' then
    v_class := b2b.lead_class(l);
    if coalesce(v_class ->> 'class', '') = 'qualified' then
      return v_no || jsonb_build_object('holder', v_holder, 'why', 'qualified: requalify_tick decides');
    end if;
  end if;

  -- debounce inside the quiet hours
  if p_kind = 'witty_message' then
    if exists (select 1 from b2b.lead_reenquiries q
                where q.lead_id = l.id and q.kind = 'witty_message' and q.message_id is distinct from p_ref
                  and q.occurred_at > v_at - v_window and q.occurred_at <= v_at) then
      return v_no || jsonb_build_object('holder', v_holder, 'why', 'a Witty message inside the quiet hours is already recorded');
    end if;
  elsif v_witty and v_evt = 'lead.interest' then
    select q.* into x from b2b.lead_reenquiries q
     where q.lead_id = l.id and q.touchpoint_id is distinct from p_ref and q.occurred_at > v_at - v_window and q.occurred_at <= v_at
     order by q.occurred_at desc, q.id desc limit 1;
    if x.id is not null then
      if x.interest then
        return v_no || jsonb_build_object('id', x.id, 'holder', v_holder, 'why', 'interest already recorded inside the quiet hours');
      end if;
      update b2b.lead_reenquiries set interest = true where id = x.id;
      if v_holder in ('barred', 'b2c_selling') then
        v_attr := b2b.lead_attribution(l);
        v_ev := b2b.log_event('b2c.lead_reenquired', l.id, l.allocation_id, null, jsonb_build_object(
          'lead_id', l.id, 'b2c_lane', v_lane, 'reason', v_reason, 'hold', v_hold, 'partner_bar', v_bar, 'cycle_no', l.cycle_no,
          'what', jsonb_build_object('source_system', v_src, 'source', p_meta ->> 'source', 'event_type', v_evt, 'campaign', p_meta ->> 'campaign',
                                     'attribution', v_attr, 'at', v_at, 'ref', p_ref, 'kind', p_kind),
          'interest', true, 'reactivation', coalesce(v_reason = 'partner_lost', false), 'merged_into', x.id, 'contract_version', 3));
        v_event := 'b2c.lead_reenquired';
      end if;
      return jsonb_build_object('recorded', false, 'id', x.id, 'holder', v_holder, 'event', v_event, 'merged', true, 'why', null);
    end if;
  end if;

  -- the row (idempotent through the unique touchpoint_id / message_id)
  v_attr := b2b.lead_attribution(l);
  insert into b2b.lead_reenquiries (lead_id, cycle_no, allocation_id, holder, partner_id, kind, touchpoint_id, message_id, source_system,
                                    event_type, campaign, paid_label, interest, occurred_at)
  values (l.id, l.cycle_no, l.allocation_id, v_holder, case when v_holder = 'partner' then a.partner_id end, p_kind,
          case when p_kind = 'touchpoint' then p_ref end, case when p_kind = 'witty_message' then p_ref end, v_src, v_evt,
          p_meta ->> 'campaign', case when coalesce((v_attr ->> 'paid')::boolean, false) then v_attr ->> 'label' end, v_interest, v_at)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then return v_no || jsonb_build_object('holder', v_holder, 'why', 'already recorded'); end if;

  if v_holder = 'partner' then
    v_ev := b2b.log_event('lead.reenquired', l.id, a.id, a.partner_id, jsonb_build_object(
      'holder', v_holder, 'partner_id', a.partner_id, 'source_system', v_src, 'event_type', v_evt, 'campaign', p_meta ->> 'campaign',
      'paid_label', case when coalesce((v_attr ->> 'paid')::boolean, false) then v_attr ->> 'label' end, 'ref', p_ref, 'kind', p_kind,
      'interest', v_interest, 'at', v_at, 'lost_in_grace', a.lost_at is not null and a.lost_revived_at is null, 'reference', a.reference));
    v_event := 'lead.reenquired';
  elsif v_holder in ('barred', 'b2c_selling') then
    v_ev := b2b.log_event('b2c.lead_reenquired', l.id, l.allocation_id, null, jsonb_build_object(
      'lead_id', l.id, 'b2c_lane', v_lane, 'reason', v_reason, 'hold', v_hold, 'partner_bar', v_bar, 'cycle_no', l.cycle_no,
      'what', jsonb_build_object('source_system', v_src, 'source', p_meta ->> 'source', 'event_type', v_evt, 'campaign', p_meta ->> 'campaign',
                                 'attribution', v_attr, 'at', v_at, 'ref', p_ref, 'kind', p_kind),
      'interest', v_interest, 'reactivation', coalesce(v_reason = 'partner_lost' and (v_interest or coalesce(l.lead_score, 0) >= 60), false),
      'contract_version', 3));
    v_event := 'b2c.lead_reenquired';
  else
    select w.* into nw from b2b.nurture_watch w where w.lead_id = l.id;
    if nw.reengaged_at is null or nw.reengaged_at < now() - interval '24 hours' then
      v_ev := b2b.log_event('b2c.lead_reengaged', l.id, l.allocation_id, null, jsonb_build_object(
        'lead_id', l.id, 'allocation_id', l.allocation_id, 'engaged_at', v_at, 'source', coalesce(p_meta ->> 'source', v_src),
        'event_type', v_evt, 'missing', coalesce(v_class -> 'missing', '[]'::jsonb), 'interest', v_interest, 'contract_version', 3));
      v_event := 'b2c.lead_reengaged';
      insert into b2b.nurture_watch (lead_id, allocation_id, reengaged_at) values (l.id, l.allocation_id, now())
      on conflict (lead_id) do update set reengaged_at = now();
    end if;
  end if;
  if v_ev is not null then update b2b.lead_reenquiries set event_id = v_ev where id = v_id; end if;
  return jsonb_build_object('recorded', true, 'id', v_id, 'holder', v_holder, 'event', v_event, 'merged', false, 'why', null);
end $fn$;

-- ---------- (5) the scanner shared by reenquiry_tick and reenquiry_catchup ----------
/* p_catchup false: public.touchpoints with id > cursor and inbound public.w2_messages with id > cursor, both created before
   now() - 2 min (the safe horizon), by id, p_limit rows each; the cursors advance past every scanned row. p_catchup true: the
   same filters over rows created in the last 26 hours with id <= cursor; the cursors are left alone. Witty consent.partner_*
   touchpoints go to consent_from_witty; touchpoints of source_system b2b / b2c_crm / crm are skipped; the others count when
   the lead is routed (destination_type set), not deleted or merged, and the row was created after the lead's allocated_at.
   A Witty message counts only when no earlier inbound message of the phone falls inside reenquiry_quiet_hours before it; the
   lead is the latest non-deleted routed lead with the same digits. One row per exception block (routing.error). */
create or replace function b2b.reenquiry_scan(p_catchup boolean, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_quiet numeric := least(greatest(coalesce(b2b.stats_num(e -> 'reenquiry_quiet_hours'), 24), 1), 168);
  v_window interval;
  v_tc bigint;
  v_mc bigint;
  v_tmax bigint;
  v_mmax bigint;
  v_lead bigint;
  v_res jsonb;
  t record;
  m record;
  n_t int := 0;
  n_m int := 0;
  n_c int := 0;
  n_r int := 0;
  n_e int := 0;
  v_horizon timestamptz := now() - interval '2 minutes';
  v_since timestamptz := now() - interval '26 hours';
  t0 timestamptz := clock_timestamp();
  v_box interval := case when p_catchup then interval '20 seconds' else interval '2 seconds' end;
  v_limit int := greatest(1, least(coalesce(p_limit, 1000), 10000));
begin
  v_window := make_interval(mins => round(v_quiet * 60)::int);
  insert into b2b.scan_cursors (key, last_id, last_at, updated_at) values
    ('touchpoints', (select coalesce(max(z.id), 0) from public.touchpoints z), now(), now()),
    ('w2_messages', (select coalesce(max(z.id), 0) from public.w2_messages z), now(), now())
  on conflict (key) do nothing;
  select coalesce(c.last_id, 0) into v_tc from b2b.scan_cursors c where c.key = 'touchpoints' for update;
  select coalesce(c.last_id, 0) into v_mc from b2b.scan_cursors c where c.key = 'w2_messages' for update;

  -- (a) touchpoints, compared on created_at (Witty's occurred_at is the conversation start)
  for t in
    select z.id, z.lead_id, z.source_system, z.event_type, z.source, z.campaign, z.created_at
      from public.touchpoints z
     where (case when p_catchup then z.id <= v_tc and z.created_at >= v_since else z.id > v_tc end)
       and z.created_at < v_horizon
     order by z.id
     limit v_limit
  loop
    exit when clock_timestamp() - t0 > v_box;
    n_t := n_t + 1;
    if not p_catchup then v_tmax := t.id; end if;
    begin
      if t.source_system = 'witty' and t.event_type like 'consent.partner\_%' then
        v_res := b2b.consent_from_witty(t.id);
        n_c := n_c + 1;
      elsif lower(coalesce(t.source_system, '')) in ('b2b', 'b2c_crm', 'crm') then
        null;
      else
        select l.id into v_lead from public.student_leads l
         where l.id = t.lead_id and l.destination_type is not null and l.deleted_at is null and l.merged_into_id is null
           and l.allocated_at is not null and t.created_at > l.allocated_at;
        if v_lead is not null then
          v_res := b2b.reenquiry_apply(v_lead, 'touchpoint', t.id, jsonb_build_object(
            'source_system', t.source_system, 'source', t.source, 'event_type', t.event_type, 'campaign', t.campaign,
            'at', t.created_at, 'interest', t.event_type = 'lead.interest'));
          if coalesce((v_res ->> 'recorded')::boolean, false) or coalesce((v_res ->> 'merged')::boolean, false) then n_r := n_r + 1; end if;
        end if;
      end if;
    exception when others then
      n_e := n_e + 1;
      begin
        perform b2b.log_event('routing.error', t.lead_id, null, null, jsonb_build_object(
          'where', 'reenquiry_tick', 'error', left(sqlerrm, 300), 'code', sqlstate, 'touchpoint_id', t.id, 'catchup', p_catchup));
      exception when others then null;
      end;
    end;
  end loop;

  -- (b) inbound Witty messages after the quiet hours
  for m in
    select z.id, z.phone, z.created_at
      from public.w2_messages z
     where z.direction = 'in'
       and (case when p_catchup then z.id <= v_mc and z.created_at >= v_since else z.id > v_mc end)
       and z.created_at < v_horizon
     order by z.id
     limit v_limit
  loop
    exit when clock_timestamp() - t0 > v_box;
    n_m := n_m + 1;
    if not p_catchup then v_mmax := m.id; end if;
    begin
      if exists (select 1 from public.w2_messages p
                  where p.phone = m.phone and p.direction = 'in' and p.id <> m.id
                    and p.created_at >= m.created_at - v_window and p.created_at < m.created_at) then
        continue;
      end if;
      select l.id into v_lead from public.student_leads l
       where regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = regexp_replace(coalesce(m.phone, ''), '\D', '', 'g')
         and l.deleted_at is null and l.merged_into_id is null and l.destination_type is not null
       order by l.created_at desc, l.id desc
       limit 1;
      if v_lead is not null and exists (select 1 from public.student_leads l where l.id = v_lead and l.allocated_at is not null and m.created_at > l.allocated_at) then
        v_res := b2b.reenquiry_apply(v_lead, 'witty_message', m.id, jsonb_build_object(
          'source_system', 'witty', 'source', 'whatsapp', 'event_type', 'message.inbound', 'campaign', null, 'at', m.created_at, 'interest', false));
        if coalesce((v_res ->> 'recorded')::boolean, false) or coalesce((v_res ->> 'merged')::boolean, false) then n_r := n_r + 1; end if;
      end if;
    exception when others then
      n_e := n_e + 1;
      begin
        perform b2b.log_event('routing.error', v_lead, null, null, jsonb_build_object(
          'where', 'reenquiry_tick', 'error', left(sqlerrm, 300), 'code', sqlstate, 'message_id', m.id, 'catchup', p_catchup));
      exception when others then null;
      end;
    end;
  end loop;

  if not p_catchup then
    if v_tmax is not null then
      update b2b.scan_cursors set last_id = greatest(coalesce(last_id, 0), v_tmax), last_at = now(), updated_at = now() where key = 'touchpoints';
    end if;
    if v_mmax is not null then
      update b2b.scan_cursors set last_id = greatest(coalesce(last_id, 0), v_mmax), last_at = now(), updated_at = now() where key = 'w2_messages';
    end if;
  end if;
  return jsonb_build_object('touchpoints', n_t, 'messages', n_m, 'consent', n_c, 'reenquiries', n_r, 'errors', n_e);
end $fn$;

-- ---------- (6) reenquiry_tick / reenquiry_catchup ----------
/* Every minute, whatever the routing switch (re-enquiries are recorded even while routing is off). One scan at a time
   (the catch-up shares the lock). */
create or replace function b2b.reenquiry_tick(p_limit int default 1000)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev_lt text := current_setting('lock_timeout', true);
  v jsonb;
begin
  perform set_config('b2b.actor', 'engine', true);
  if not pg_try_advisory_xact_lock(hashtext('b2b.reenquiry_tick')) then
    return jsonb_build_object('touchpoints', 0, 'messages', 0, 'consent', 0, 'reenquiries', 0, 'errors', 0, 'skipped', 'another scan is running');
  end if;
  perform set_config('lock_timeout', '2000', true);
  v := b2b.reenquiry_scan(false, p_limit);
  perform set_config('lock_timeout', coalesce(nullif(v_prev_lt, ''), '0'), true);
  return v;
end $fn$;

/* Hourly: the last 26 hours up to the cursors, for rows that committed late (critic B26). Idempotent. */
create or replace function b2b.reenquiry_catchup()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev_lt text := current_setting('lock_timeout', true);
  v jsonb;
begin
  perform set_config('b2b.actor', 'engine', true);
  if not pg_try_advisory_xact_lock(hashtext('b2b.reenquiry_tick')) then
    return jsonb_build_object('touchpoints', 0, 'messages', 0, 'consent', 0, 'reenquiries', 0, 'errors', 0, 'skipped', 'another scan is running');
  end if;
  perform set_config('lock_timeout', '2000', true);
  v := b2b.reenquiry_scan(true, 5000);
  perform set_config('lock_timeout', coalesce(nullif(v_prev_lt, ''), '0'), true);
  return v || jsonb_build_object('catchup', true);
end $fn$;

-- ---------- (7) reenquiry_ack (Admin) ----------
create or replace function b2b.reenquiry_ack(p_ids bigint[], p_note text default null)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  n int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_ids is null or cardinality(p_ids) < 1 or cardinality(p_ids) > 500 then
    raise exception 'choose 1 to 500 re-enquiries' using errcode = '22023';
  end if;
  update b2b.lead_reenquiries
     set acknowledged_at = now(), acknowledged_by = coalesce(b2b.actor() ->> 'id', b2b.actor() ->> 'type'), note = left(nullif(trim(p_note), ''), 300)
   where id = any (p_ids) and acknowledged_at is null;
  get diagnostics n = row_count;
  return n;
end $fn$;

-- ---------- grants ----------
-- internal functions: the engine only; reenquiry_ack is an Admin RPC (it checks b2b.is_admin())
revoke execute on function b2b.nurture_fingerprint(public.student_leads), b2b.requalify_lead(bigint, text), b2b.requalify_tick(int),
                           b2b.reenquiry_apply(bigint, text, bigint, jsonb), b2b.reenquiry_scan(boolean, int), b2b.reenquiry_tick(int),
                           b2b.reenquiry_catchup()
  from public, anon, authenticated;
grant execute on function b2b.nurture_fingerprint(public.student_leads), b2b.requalify_lead(bigint, text), b2b.requalify_tick(int),
                          b2b.reenquiry_apply(bigint, text, bigint, jsonb), b2b.reenquiry_scan(boolean, int), b2b.reenquiry_tick(int),
                          b2b.reenquiry_catchup()
  to service_role;
revoke execute on function b2b.reenquiry_ack(bigint[], text) from public, anon;
grant execute on function b2b.reenquiry_ack(bigint[], text) to authenticated, service_role;

-- ---------- cron ----------
-- An existing job is changed in place (a job paused for the promotion window stays paused); a new one follows the push tick's
-- state. requalify_tick(null) reads its batch size from engine.requalify.max_per_run.
do $cron$
declare
  j record;
  v_id bigint;
  v_active boolean;
begin
  select x.active into v_active from cron.job x where x.jobname = 'b2b-push-tick' order by x.jobid limit 1;
  for j in
    select * from (values ('b2b-requalify-tick', '* * * * *', 'select b2b.requalify_tick(null)'),
                          ('b2b-reenquiry-tick', '* * * * *', 'select b2b.reenquiry_tick(1000)'),
                          ('b2b-reenquiry-catchup', '17 * * * *', 'select b2b.reenquiry_catchup()')) v (name, sched, cmd)
  loop
    select x.jobid into v_id from cron.job x where x.jobname = j.name order by x.jobid limit 1;
    if v_id is null then
      perform cron.schedule(j.name, j.sched, j.cmd);
      if v_active is false then
        perform cron.alter_job(x.jobid, active := false) from cron.job x where x.jobname = j.name;
      end if;
    else
      perform cron.alter_job(v_id, schedule := j.sched, command := j.cmd);
    end if;
  end loop;
end $cron$;
