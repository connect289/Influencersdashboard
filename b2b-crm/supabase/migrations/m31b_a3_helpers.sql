-- M31b: Addendum 3 helpers (docs/B2B_CRM_ADDENDUM_3.md) for the engine, consent, re-decisions and reads, plus the
-- published-event wiring for the new B2C event types. New functions only, except:
--   lead_interest        (m6a)  same keys, plus course_text, university_ids, segment_exact, rank and source
--   published_events     (m14a) the four new b2c.* types 1:1; contract_version 3 on every b2c.* and b2b.* envelope;
--                               b2b.lead_routed_to_partner also for leads accepted after a requalification
--   events_fanout        (m14a) trigger: the WHEN list gains the four new types
--   api_b2c_handoffs     (m14d) the four new types (the next_after cursor fix is kept)
--   webhook_endpoint_save (m23a) the four new types are accepted
-- New: phone_digits, lead_family, partner_bar, partner_bar_set, lead_other_providers, dup_history, b2c_hold, b2c_handling,
-- consent_text_covers, partner_consent, lead_attribution, interest_level, interest_mode, university_ids, lead_interest_list,
-- interest_offers, interest_offered, course_known, tier_middle, cpe_detail, lead_geo, qualification_level,
-- qualification_rank, criteria_check, offer_eligible, witty_blocked, student_last_inbound, is_witty_lead, chat_gate,
-- episode, np_fingerprint, handoff_payload, setting_for_update.
-- Witty data (public.w2_inbox, w2_messages, w2_blocks) is read only, with fully qualified names, inside SECURITY DEFINER
-- functions. public.w2_is_blocked, w2_is_test and crm_find_lead are never called: they have no search_path and fail
-- when called from a function with search_path ''.
-- Nothing here writes student_leads, Witty or the catalogue. Of the new functions only partner_bar_set writes
-- (b2b.partner_bars, b2b.events); setting_for_update only takes a row lock.

-- ---------- small pure helpers ----------
/* Digits of a phone number: '+91 98765-43210' -> '919876543210'. */
create or replace function b2b.phone_digits(p text)
returns text language sql immutable parallel safe set search_path = '' as $fn$
  select regexp_replace(coalesce(p, ''), '\D', '', 'g');
$fn$;

/* The Not passed fingerprint (as in m7b1..m24b): a lead is re-decided by the sweep only when it changes. */
create or replace function b2b.np_fingerprint(l public.student_leads)
returns text language sql immutable set search_path = '' as $fn$
  select md5(concat_ws('|', upper(coalesce(l.lead_status, '')), coalesce(nullif(l.interested_course, ''), l.field_of_interest, ''), l.whatsapp_number));
$fn$;

/* Programme level and study mode in catalogue terms (as m6a's lead_interest). */
create or replace function b2b.interest_level(p text)
returns text language sql immutable set search_path = '' as $fn$
  select case when lower(coalesce(p, '')) ~ '^(pg|post ?grad|master|postgraduate)' then 'PG'
              when lower(coalesce(p, '')) ~ '^(ug|under ?grad|bachelor|graduat)' then 'UG'
              when lower(coalesce(p, '')) ~ 'diploma' then 'DIPLOMA'
              when lower(coalesce(p, '')) ~ 'cert' then 'CERTIFICATE' end;
$fn$;

create or replace function b2b.interest_mode(p text)
returns text language sql immutable set search_path = '' as $fn$
  select case when lower(coalesce(p, '')) ~ 'online' then 'Online'
              when lower(coalesce(p, '')) ~ '(distance|odl|correspond)' then 'ODL'
              when lower(coalesce(p, '')) ~ '(regular|campus|offline|full)' then 'Regular' end;
$fn$;

/* Highest qualification as a level: '10th', '12th', 'diploma', 'ug', 'pg', 'doctorate', or null when not recognised. */
create or replace function b2b.qualification_level(p text)
returns text language sql immutable set search_path = '' as $fn$
  select case
    when t = '' then null
    when t ~ '(phd|ph\.d|doctorate|doctoral)' then 'doctorate'
    when t ~ '(post ?grad|postgrad|master|\mmba\M|\mpgdm\M|\mpgd\M|\mm\.? ?(tech|sc|com|a|ca|e|ed|phil|pharm|des|arch)\M|\mmca\M|\mpg\M|\mllm\M|\mmd\M)' then 'pg'
    when t ~ '(grad|bachelor|degree|\mb\.? ?(tech|sc|com|a|ca|e|ed|pharm|des|arch|voc|ba)\M|\mbba\M|\mbca\M|\mllb\M|\mmbbs\M|\mbds\M|\mug\M)' then 'ug'
    when t ~ '(diploma|polytechnic|\miti\M)' then 'diploma'
    when t ~ '(12|xii|hsc|intermediate|senior secondary|higher secondary|plus two|\+ ?2|\mpuc\M|pre.?university)' then '12th'
    when t ~ '(10|\mx\M|ssc|matric|secondary)' then '10th'
  end from (select lower(trim(coalesce(p, ''))) t) x;
$fn$;

create or replace function b2b.qualification_rank(p_level text)
returns int language sql immutable set search_path = '' as $fn$
  select case p_level when '10th' then 1 when '12th' then 2 when 'diploma' then 2 when 'ug' then 3 when 'pg' then 4 when 'doctorate' then 5 end;
$fn$;

/* The middle tier of a tiered rate (Stage A cold start): the median tier %, the mean of the two middle ones for an even
   count. 22.42 / 20.42 / 18.42 -> 20.42. */
create or replace function b2b.tier_middle(p_tiers jsonb)
returns numeric language sql immutable set search_path = '' as $fn$
  select round((percentile_cont(0.5) within group (order by (t ->> 'pct')::numeric))::numeric, 6)
    from jsonb_array_elements(case when jsonb_typeof(p_tiers) = 'array' then p_tiers else '[]'::jsonb end) t
   where (t ->> 'pct') ~ '^-?[0-9]+(\.[0-9]+)?$';
$fn$;

/* Reads a setting and locks its row until the transaction ends, for read-modify-write saves (critic F187). Under READ
   COMMITTED a waiting FOR UPDATE returns the newest committed value. Lock order: 'engine' before 'engine_policy'. */
create or replace function b2b.setting_for_update(p_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb;
begin
  select s.value into v from b2b.settings s where s.key = p_key for update;
  return coalesce(v, '{}');
end $fn$;

-- ---------- the student and the partner bar ----------
/* The student's leads: the lead, the leads merged into it, and (for a real phone) the other non-test leads with the same
   stored phone number (a soft-deleted and re-created lead). Used for duplicate history and the providers list. */
create or replace function b2b.lead_family(p_lead_id bigint)
returns table (lead_id bigint) language sql stable security definer set search_path = '' as $fn$
  with me as (
    select x.id, x.whatsapp_number,
           coalesce(x.is_test, false) or b2b.is_test_phone(x.whatsapp_number) or length(regexp_replace(coalesce(x.whatsapp_number, ''), '\D', '', 'g')) < 10 as no_phone
      from public.student_leads x where x.id = p_lead_id)
  select p_lead_id
  union
  select m.id from public.student_leads m where m.merged_into_id = p_lead_id
  union
  select s.id from me join public.student_leads s on s.whatsapp_number = me.whatsapp_number
   where not me.no_phone and not coalesce(s.is_test, false);
$fn$;

/* PART 3 R2: the lead's permanent partner bar, or null. A bar on the lead itself, on a lead merged into it, or on any
   non-test lead with the same phone digits (b2b.partner_bars keeps the digits, so a lead soft-removed and created again
   stays barred). The first bar wins. Never raises. Cost note: the merged-lead branch reads partner_bars by primary key of
   student_leads; for long lists prefer a set-based join on partner_bars. */
create or replace function b2b.partner_bar(l public.student_leads)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object('reason', x.reason, 'barred_at', x.barred_at, 'lead_id', x.lead_id, 'allocation_id', x.allocation_id,
                            'providers', x.providers, 'set_by', x.set_by, 'via', x.via)
    from (select b.*, 'lead'::text via from b2b.partner_bars b where b.lead_id = l.id
          union all
          select b.*, 'merged'::text from b2b.partner_bars b join public.student_leads m on m.id = b.lead_id
           where m.merged_into_id = l.id and b.lead_id <> l.id
          union all
          select b.*, 'phone'::text from b2b.partner_bars b
           where b.phone_digits = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g')
             and length(b.phone_digits) >= 10 and b.lead_id <> l.id
             and not coalesce(l.is_test, false) and not b2b.is_test_phone(l.whatsapp_number)) x
   order by x.barred_at, x.lead_id
   limit 1;
$fn$;

/* PART 5.4: the partners that proved the student was already their lead (proof-backed duplicate allocations of the lead,
   its merged leads and same-phone leads, all cycles), one entry per partner:
   {partner_id, partner_name, first_had_at (the partner's created date; null = 'date not given'), existing_record_id,
   claimed_at}, oldest claim first. */
create or replace function b2b.lead_other_providers(p_lead_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('partner_id', x.partner_id, 'partner_name', x.partner_name, 'first_had_at', x.first_had_at,
                                               'existing_record_id', x.existing_record_id, 'claimed_at', x.claimed_at)
                            order by x.claimed_at, x.partner_id), '[]'::jsonb)
    from (select a.partner_id, coalesce(min(p.display_name), min(p.name)) partner_name,
                 min(a.claim_existing_created_at) first_had_at,
                 (array_agg(a.claim_existing_record_id order by coalesce(a.outcome_at, a.updated_at), a.id)
                    filter (where a.claim_existing_record_id is not null))[1] existing_record_id,
                 min(coalesce(a.outcome_at, a.updated_at)) claimed_at
            from b2b.allocations a join b2b.partners p on p.id = a.partner_id
           where a.lead_id in (select f.lead_id from b2b.lead_family(p_lead_id) f)
             and a.destination_type = 'partner' and a.status = 'duplicate' and coalesce(a.claim_proof_ok, false) and not a.returning_lead
           group by a.partner_id) x;
$fn$;

/* PART 4 Step 1 'not previously reported this student as a duplicate': partners with a duplicate allocation on the
   student's leads in any cycle, plus partners whose after-acceptance duplicate claim was upheld. */
create or replace function b2b.dup_history(p_lead_id bigint)
returns bigint[] language sql stable security definer set search_path = '' as $fn$
  select coalesce(array_agg(distinct x.partner_id order by x.partner_id), '{}'::bigint[])
    from (select a.partner_id from b2b.allocations a
           where a.lead_id in (select f.lead_id from b2b.lead_family(p_lead_id) f)
             and a.status = 'duplicate' and not a.returning_lead and a.partner_id is not null
          union all
          select d.partner_id from b2b.commission_disputes d
           where d.lead_id in (select f.lead_id from b2b.lead_family(p_lead_id) f)
             and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance') x;
$fn$;

/* Bars a lead from partners for ever (PART 5.4 duplicate, PART 6.1 lost). Idempotent: an existing bar is returned as it is.
   providers: the proven duplicate claims (duplicate), or the partner that lost the lead (lost). p_allocation_id is the
   allocation that set the bar (usually the B2C hand-off). Logs lead.partner_barred once. */
create or replace function b2b.partner_bar_set(p_lead_id bigint, p_reason text, p_allocation_id bigint, p_set_by text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  a b2b.allocations;
  lp b2b.allocations;
  b b2b.partner_bars;
  v_prov jsonb;
  v_test boolean;
begin
  if p_reason is null or p_reason not in ('duplicate', 'lost') then raise exception 'a partner bar is for a duplicate or a lost lead' using errcode = '22023'; end if;
  if p_set_by is null or p_set_by not in ('engine', 'grace', 'manual_route', 'backfill') then raise exception 'unknown bar source' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  select * into b from b2b.partner_bars where lead_id = p_lead_id;
  if b.lead_id is not null then return to_jsonb(b) - 'phone_digits' || jsonb_build_object('created', false); end if;

  v_test := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  if p_allocation_id is not null then select * into a from b2b.allocations where id = p_allocation_id; end if;
  if p_reason = 'duplicate' then
    v_prov := b2b.lead_other_providers(p_lead_id);
  else
    -- the partner allocation that lost the lead: the given one when it is a partner allocation, else the latest one
    -- of the lead marked lost
    if a.destination_type = 'partner' then
      lp := a;
    else
      select x.* into lp from b2b.allocations x
       where x.lead_id = p_lead_id and x.destination_type = 'partner' and (x.lost_at is not null or x.outcome = 'lost')
       order by x.id desc limit 1;
    end if;
    v_prov := case when lp.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
                'partner_id', lp.partner_id, 'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = lp.partner_id),
                'allocation_id', lp.id, 'partner_record_id', lp.partner_record_id, 'lost_at', coalesce(lp.lost_at, lp.outcome_at),
                'lost_reason', lp.lost_detail ->> 'lost_reason')) end;
  end if;

  insert into b2b.partner_bars (lead_id, phone_digits, reason, allocation_id, cycle_no, providers, set_by, source_lead_id)
  values (p_lead_id, case when v_test then null else nullif(b2b.phone_digits(l.whatsapp_number), '') end, p_reason, a.id,
          coalesce(a.cycle_no, l.cycle_no), v_prov, p_set_by, case when a.lead_id is distinct from p_lead_id then a.lead_id end)
  on conflict (lead_id) do nothing
  returning * into b;
  if b.lead_id is null then   -- barred by a concurrent transaction
    select * into b from b2b.partner_bars where lead_id = p_lead_id;
    return to_jsonb(b) - 'phone_digits' || jsonb_build_object('created', false);
  end if;
  perform b2b.log_event('lead.partner_barred', p_lead_id, a.id, case when p_reason = 'lost' then lp.partner_id end,
                        jsonb_build_object('reason', p_reason, 'set_by', p_set_by, 'barred_at', b.barred_at, 'providers', v_prov, 'cycle_no', b.cycle_no));
  return to_jsonb(b) - 'phone_digits' || jsonb_build_object('created', true);
end $fn$;

-- ---------- B2C holds ----------
/* What B2C holds the lead as, from its latest in_house allocation L (any cycle), or null when B2C does not hold it:
     barred                 a partner bar and (L is the lead's open hand-off, or the lead is with B2C)
     null                   no L; or a partner allocation with origin to_partners, requalify or reroute came after L;
                            or L's outcome is requalified or routed_to_partners
     qualification_nurture  L.reason not_qualified or consent_no_answer (returns to routing when qualified, R7)
     selling                any other hand-off: an R4 hold until a manual route
   {kind, open, allocation_id, lane, reason, owner_assigned}; open = L is the lead's current, still handed_off allocation. */
create or replace function b2b.b2c_hold(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  h b2b.allocations;
  v_open boolean;
  v_kind text;
begin
  select a.* into h from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'in_house'
   order by a.created_at desc, a.id desc limit 1;
  v_open := h.id is not null and h.status = 'handed_off' and coalesce(l.allocation_id = h.id, false);
  if (v_open or l.destination_type = 'in_house') and b2b.partner_bar(l) is not null then
    v_kind := 'barred';
  elsif h.id is null or coalesce(h.outcome, '') in ('requalified', 'routed_to_partners') then
    return null;
  elsif exists (select 1 from b2b.allocations p
                 where p.lead_id = l.id and p.destination_type = 'partner' and p.origin in ('to_partners', 'requalify', 'reroute')
                   and (p.created_at > h.created_at or (p.created_at = h.created_at and p.id > h.id))) then
    return null;
  elsif h.reason in ('not_qualified', 'consent_no_answer') then
    v_kind := 'qualification_nurture';
  else
    v_kind := 'selling';
  end if;
  return jsonb_build_object('kind', v_kind, 'open', v_open, 'allocation_id', h.id, 'lane', h.b2c_lane, 'reason', h.reason,
                            'owner_assigned', l.owner_user_id is not null);
end $fn$;

/* How the B2C CRM should handle a hand-off (contract version 3):
   {job sell|qualify|nurture, assignment, first_contact_script, nurture_first_message_after_days}. */
create or replace function b2b.b2c_handling(p_reason text, p_lane text, p_bar jsonb, p_lost_reason text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  d jsonb;
  v_days numeric;
begin
  if p_reason = 'duplicate_cascade' or (p_reason = 'partner_barred' and p_bar ->> 'reason' = 'duplicate') then
    return jsonb_build_object('job', 'sell', 'assignment', 'round_robin_now', 'first_contact_script', 'neutral_adviser', 'nurture_first_message_after_days', null);
  elsif p_reason = 'partner_barred' then
    return jsonb_build_object('job', 'sell', 'assignment', 'round_robin_now', 'first_contact_script', 'standard', 'nurture_first_message_after_days', null);
  elsif p_reason = 'partner_lost' then
    -- PART 6.1: the lost reason sets the first nurture message, 3-90 days (per-reason values: lost_nurture_delays)
    d := coalesce((select s.value from b2b.settings s where s.key = 'lost_nurture_delays'), '{}');
    select (r.value #>> '{}') into v_days from jsonb_each(case when jsonb_typeof(d -> 'reasons') = 'object' then d -> 'reasons' else '{}'::jsonb end) r
     where lower(r.key) = lower(coalesce(p_lost_reason, '')) and (r.value #>> '{}') ~ '^[0-9]+(\.[0-9]+)?$'
     order by (r.key = p_lost_reason) desc limit 1;
    if v_days is null and (d ->> 'default') ~ '^[0-9]+(\.[0-9]+)?$' then v_days := (d ->> 'default')::numeric; end if;
    return jsonb_build_object('job', 'nurture', 'assignment', 'unassigned_until_interest', 'first_contact_script', 'standard',
                              'nurture_first_message_after_days', least(greatest(round(coalesce(v_days, 14)), 3), 90)::int);
  elsif p_reason in ('not_qualified', 'consent_no_answer') then
    return jsonb_build_object('job', 'qualify', 'assignment', 'unassigned', 'first_contact_script', 'standard', 'nurture_first_message_after_days', null);
  elsif p_reason = 'manual_route_failed' then
    return jsonb_build_object('job', 'sell', 'assignment', 'previous_counsellor', 'first_contact_script', 'standard', 'nurture_first_message_after_days', null);
  end if;
  return jsonb_build_object('job', case when p_lane = 'nurture' then 'nurture' else 'sell' end, 'assignment', 'counsellor_choice',
                            'first_contact_script', 'standard', 'nurture_first_message_after_days', null);
end $fn$;

-- ---------- consent (PART 7) ----------
/* Does a consent text version count as partner-sharing consent? Only an active registered text that names admission
   partners (edtech companies) and lists partner_share. */
create or replace function b2b.consent_text_covers(p_version text)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select coalesce(p_version is not null and exists (select 1 from b2b.consent_texts t
                                                      where t.version = p_version and t.active and t.covers_admission_partners
                                                        and 'partner_share' = any (t.purposes)), false);
$fn$;

/* The lead's partner-sharing consent (PART 7.1):
     given            a covering 'given' ledger row, or the student_leads stamp under a covering text version, with no
                      refusal or withdrawal at or after it
     at, version, source   of that grant (source 'stamp' for the column), only when given
     refused, refused_at   the latest refusal or withdrawal is at or after any grant
     last_state       the latest ledger state (given, refused, withdrawn), else 'stamp' or null
     stamp_uncovered  the column is stamped under a version that does not cover admission partners (R8 asks again)
     open_request, expired_request, last_request   this cycle's requests (JSON null when none; test with ->>)
*/
create or replace function b2b.partner_consent(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  g b2b.lead_consents;
  rf b2b.lead_consents;
  v_last text;
  v_stamp_ok boolean := l.consent_partner_share_at is not null and b2b.consent_text_covers(l.consent_text_version);
  v_given_at timestamptz;
  v_version text;
  v_source text;
  v_given boolean;
  v_refused boolean;
  o b2b.consent_requests;
  x b2b.consent_requests;
  q b2b.consent_requests;
  v_cycle int := coalesce(l.cycle_no, 1);
begin
  select c.* into g from b2b.lead_consents c
   where c.lead_id = l.id and c.purpose = 'partner_share' and c.state = 'given' and b2b.consent_text_covers(c.text_version)
   order by c.at desc, c.id desc limit 1;
  select c.* into rf from b2b.lead_consents c
   where c.lead_id = l.id and c.purpose = 'partner_share' and c.state in ('refused', 'withdrawn')
   order by c.at desc, c.id desc limit 1;
  select c.state into v_last from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'partner_share' order by c.at desc, c.id desc limit 1;

  if g.id is not null and (not v_stamp_ok or g.at >= l.consent_partner_share_at) then
    v_given_at := g.at; v_version := g.text_version; v_source := g.source;
  elsif v_stamp_ok then
    v_given_at := l.consent_partner_share_at; v_version := l.consent_text_version; v_source := 'stamp';
  end if;
  v_given := v_given_at is not null and (rf.id is null or rf.at < v_given_at);
  v_refused := rf.id is not null and (v_given_at is null or rf.at >= v_given_at);

  select r.* into o from b2b.consent_requests r
   where r.lead_id = l.id and r.cycle_no = v_cycle and r.status in ('queued', 'requested', 'sent', 'unsendable')
   order by r.created_at desc, r.id desc limit 1;
  select r.* into x from b2b.consent_requests r
   where r.lead_id = l.id and r.cycle_no = v_cycle and r.status = 'expired'
   order by coalesce(r.expires_at, r.created_at) desc, r.id desc limit 1;
  select r.* into q from b2b.consent_requests r
   where r.lead_id = l.id and r.cycle_no = v_cycle order by r.created_at desc, r.id desc limit 1;

  return jsonb_build_object(
    'given', v_given,
    'at', case when v_given then v_given_at end,
    'version', case when v_given then v_version end,
    'source', case when v_given then v_source end,
    'refused', v_refused,
    'refused_at', case when v_refused then rf.at end,
    'last_state', coalesce(v_last, case when l.consent_partner_share_at is not null then 'stamp' end),
    'stamp_uncovered', l.consent_partner_share_at is not null and not b2b.consent_text_covers(l.consent_text_version),
    'open_request', case when o.id is not null then jsonb_build_object('id', o.id, 'status', o.status, 'channel', o.channel, 'context', o.context,
                      'created_at', o.created_at, 'published_at', o.published_at, 'sent_at', o.sent_at, 'expires_at', o.expires_at,
                      'programme', o.programme) end,
    'expired_request', case when x.id is not null then jsonb_build_object('id', x.id, 'channel', x.channel, 'context', x.context,
                      'created_at', x.created_at, 'expires_at', x.expires_at, 'closed_at', x.closed_at, 'programme', x.programme) end,
    'last_request', case when q.id is not null then jsonb_build_object('id', q.id, 'status', q.status, 'answer', q.answer, 'answered_at', q.answered_at,
                      'created_at', q.created_at, 'expires_at', q.expires_at) end);
end $fn$;

-- ---------- attribution (Definitions: paid = Meta and Google only) ----------
/* The lead's paid label for its current enquiry cycle, used for labels, CAPI and analytics; it never changes routing.
   In order: (a) influencer or referral markers -> not paid; (b) an excluded campaign -> not paid; (c) Meta paid: a
   non-organic Meta lead form, a click-to-WhatsApp ad (ctwa_clid or Witty's ad referral), or fbclid/fbc together with a
   Meta ad parameter (attribution.meta_ad_params); (d) Google paid: gclid, gbraid, wbraid, a Google lead id or a Google
   lead form; (e) anything else (UTM-only, organic forms) -> not paid.
   Sources, as b2b.lead_campaign_detect: the cycle's Meta/Google intake requests and touchpoints, and the lead row.
   Returns {paid, platform meta|google|other|none, signal, label, campaign_id, origin}. */
create or replace function b2b.lead_attribution(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := coalesce((select s.value from b2b.settings s where s.key = 'attribution'), '{}');
  v_start timestamptz := coalesce(l.reopened_at - interval '1 hour', '-infinity'::timestamptz);
  v_mk_src text[] := array(select lower(trim(x)) from jsonb_array_elements_text(case when jsonb_typeof(cfg -> 'influencer_markers' -> 'lead_sources') = 'array'
                                                                                     then cfg -> 'influencer_markers' -> 'lead_sources' else '[]'::jsonb end) x);
  v_mk_utm text[] := array(select lower(trim(x)) from jsonb_array_elements_text(case when jsonb_typeof(cfg -> 'influencer_markers' -> 'utm_values') = 'array'
                                                                                     then cfg -> 'influencer_markers' -> 'utm_values' else '[]'::jsonb end) x);
  v_excl text[] := array(select lower(trim(x)) from jsonb_array_elements_text(case when jsonb_typeof(cfg -> 'exclude_campaigns') = 'array'
                                                                                   then cfg -> 'exclude_campaigns' else '[]'::jsonb end) x where trim(x) <> '');
  v_adp text[] := array(select trim(x) from jsonb_array_elements_text(case when jsonb_typeof(cfg -> 'meta_ad_params') = 'array'
                                                                           then cfg -> 'meta_ad_params' else '[]'::jsonb end) x where trim(x) ~ '^[A-Za-z0-9_]+$');
  v_rows jsonb[];
  r jsonb;
  ck jsonb;
  v_url text;
  v_src text;
  v_us text;
  v_um text;
  v_organic text[] := '{}';
  v_marker jsonb;
  v_excluded jsonb;
  v_meta jsonb;
  v_google jsonb;
  v_platform text;
  v_first_camp text;
  v_hit text;
begin
  select array_agg(to_jsonb(s) order by s.at nulls last, s.ord) into v_rows from (
    select q.received_at as at, 1 as ord, case q.source when 'meta' then 'intake_meta' else 'intake_google' end as origin, q.source as kind,
           case q.source when 'meta' then jsonb_strip_nulls(jsonb_build_object('leadgen_id', q.idempotency_key,
                                                             'organic', coalesce(q.raw -> 'graph' ->> 'is_organic', q.raw ->> 'is_organic')))
                         else jsonb_strip_nulls(jsonb_build_object('google_lead_id', q.idempotency_key, 'gclid', q.raw ->> 'gcl_id')) end as ck,
           coalesce(q.raw -> 'graph' ->> 'campaign_id', q.raw ->> 'campaign_id') as campaign_id,
           coalesce(q.raw -> 'graph' ->> 'campaign_name', q.raw ->> 'campaign_name') as campaign,
           null::text as utm_source, null::text as utm_medium, null::text as src, null::text as detail, null::text as url
      from b2b.intake_requests q
     where q.lead_id = l.id and q.source in ('meta', 'google') and q.status = 'done' and q.received_at >= v_start
    union all
    select t.occurred_at, 2, 'touchpoint:' || coalesce(t.source_system, '?'), 'touchpoint',
           (case when jsonb_typeof(t.attribution -> 'click_ids') = 'object' then t.attribution -> 'click_ids' else '{}'::jsonb end)
           || (case when jsonb_typeof(t.payload -> 'click_ids') = 'object' then t.payload -> 'click_ids' else '{}'::jsonb end)
           || jsonb_strip_nulls(jsonb_build_object('organic', t.attribution ->> 'organic', 'ctwa_clid', t.attribution ->> 'ctwa_clid',
                                                   'utm_id', coalesce(t.payload ->> 'utm_id', t.attribution ->> 'utm_id'))),
           coalesce(t.attribution ->> 'campaign_id', t.payload -> 'click_ids' ->> 'campaign_id', t.payload ->> 'utm_id', t.attribution ->> 'utm_id'),
           coalesce(nullif(t.campaign, ''), nullif(t.attribution ->> 'campaign', ''), t.payload ->> 'campaign', t.payload ->> 'utm_campaign', t.attribution ->> 'utm_campaign'),
           coalesce(t.payload ->> 'utm_source', t.payload -> 'utm' ->> 'source', t.attribution ->> 'utm_source'),
           coalesce(t.payload ->> 'utm_medium', t.payload -> 'utm' ->> 'medium', t.attribution ->> 'utm_medium'),
           t.source, coalesce(t.attribution ->> 'kind', t.payload ->> 'source_detail'), coalesce(t.payload ->> 'landing_url', t.attribution ->> 'landing_url')
      from public.touchpoints t
     where t.lead_id = l.id and t.occurred_at >= v_start
    union all
    select coalesce(l.first_touch_at, l.created_at), 3, 'lead', 'lead',
           case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids else '{}'::jsonb end,
           case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids ->> 'campaign_id' end,
           coalesce(nullif(l.campaign, ''), nullif(l.utm_campaign, '')), l.utm_source, l.utm_medium, l.lead_source, l.source_detail, l.landing_url) s;

  -- a Meta lead form marked organic stays organic in every copy of its leadgen id
  foreach r in array coalesce(v_rows, '{}'::jsonb[]) loop
    if (r -> 'ck') ? 'leadgen_id' and lower(coalesce(r -> 'ck' ->> 'organic', 'false')) in ('true', '1') then
      v_organic := array_append(v_organic, r -> 'ck' ->> 'leadgen_id');
    end if;
  end loop;

  foreach r in array coalesce(v_rows, '{}'::jsonb[]) loop
    ck := coalesce(r -> 'ck', '{}');
    v_url := coalesce(r ->> 'url', '');
    v_src := lower(trim(coalesce(r ->> 'src', '')));
    v_us := lower(trim(coalesce(r ->> 'utm_source', '')));
    v_um := lower(trim(coalesce(r ->> 'utm_medium', '')));
    v_first_camp := coalesce(v_first_camp, nullif(r ->> 'campaign_id', ''));
    if v_platform is null then
      v_platform := case when ck ?| array['leadgen_id', 'fbclid', 'fbc', 'ctwa_clid'] or r ->> 'kind' = 'meta'
                              or v_us in ('facebook', 'fb', 'instagram', 'ig', 'meta', 'messenger', 'an', 'audience_network') then 'meta'
                         when ck ?| array['gclid', 'gbraid', 'wbraid', 'google_lead_id'] or r ->> 'kind' = 'google'
                              or v_us in ('google', 'youtube', 'gdn', 'adwords', 'google_ads', 'googleads') then 'google'
                         when v_us <> '' or nullif(r ->> 'campaign', '') is not null then 'other' end;
    end if;
    -- (a) influencer or referral markers
    if v_marker is null and (v_src = any (v_mk_src) or v_us = any (v_mk_utm) or v_um = any (v_mk_utm)
                             or (r ->> 'origin' = 'lead' and (nullif(trim(l.referral_code), '') is not null))) then
      v_marker := r;
    end if;
    -- (b) an excluded campaign
    if v_excluded is null and nullif(r ->> 'campaign', '') is not null
       and exists (select 1 from unnest(v_excl) x where lower(r ->> 'campaign') like '%' || x || '%') then
      v_excluded := r;
    end if;
    -- (c) Meta
    if v_meta is null then
      v_hit := case
        when (r ->> 'kind' = 'meta' or ck ? 'leadgen_id') and not coalesce(ck ->> 'leadgen_id' = any (v_organic), false)
             and lower(coalesce(ck ->> 'organic', 'false')) not in ('true', '1') then 'meta_lead_form'
        when r ->> 'origin' = 'lead' and v_src in ('meta_lead_ad', 'meta_lead_ads') and cardinality(v_organic) = 0 then 'meta_lead_form'
        when ck ? 'ctwa_clid' or v_url ~* '[?&]ctwa_clid=' then 'ctwa_clid'
        when lower(coalesce(r ->> 'detail', '')) ~ '(ctwa|click.to.whatsapp)' then 'witty_ad_referral'
        when (ck ? 'fbclid' or ck ? 'fbc' or v_url ~* '[?&]fbclid=')
             and (ck ?| v_adp or (cardinality(v_adp) > 0 and v_url ~* ('[?&](' || array_to_string(v_adp, '|') || ')='))) then
          case when ck ? 'fbclid' or v_url ~* '[?&]fbclid=' then 'fbclid' else 'fbc' end
      end;
      if v_hit is not null then
        v_meta := r || jsonb_build_object('signal', v_hit,
                     'label', case v_hit when 'meta_lead_form' then 'Meta Lead Ads' when 'fbclid' then 'Meta ad click' when 'fbc' then 'Meta ad click'
                                         else 'Meta click-to-WhatsApp' end);
      end if;
    end if;
    -- (d) Google
    if v_google is null then
      v_hit := case
        when r ->> 'kind' = 'google' or ck ? 'google_lead_id' then 'google_lead_form'
        when r ->> 'origin' = 'lead' and v_src in ('google_lead_form', 'google_ads_lead_form') then 'google_lead_form'
        when ck ? 'gclid' or v_url ~* '[?&]gclid=' then 'gclid'
        when ck ? 'gbraid' or v_url ~* '[?&]gbraid=' then 'gbraid'
        when ck ? 'wbraid' or v_url ~* '[?&]wbraid=' then 'wbraid'
      end;
      if v_hit is not null then
        v_google := r || jsonb_build_object('signal', v_hit, 'label', case when v_hit = 'google_lead_form' then 'Google lead form' else 'Google ad click' end);
      end if;
    end if;
  end loop;

  if v_marker is not null then
    return jsonb_build_object('paid', false, 'platform', coalesce(v_platform, 'none'), 'signal', 'influencer_referral', 'label', null,
                              'campaign_id', coalesce(nullif(v_marker ->> 'campaign_id', ''), v_first_camp), 'origin', v_marker ->> 'origin');
  elsif v_excluded is not null then
    return jsonb_build_object('paid', false, 'platform', coalesce(v_platform, 'none'), 'signal', 'excluded_campaign', 'label', null,
                              'campaign_id', coalesce(nullif(v_excluded ->> 'campaign_id', ''), v_first_camp), 'origin', v_excluded ->> 'origin');
  elsif v_meta is not null then
    return jsonb_build_object('paid', true, 'platform', 'meta', 'signal', v_meta ->> 'signal', 'label', v_meta ->> 'label',
                              'campaign_id', coalesce(nullif(v_meta ->> 'campaign_id', ''), v_first_camp), 'origin', v_meta ->> 'origin');
  elsif v_google is not null then
    return jsonb_build_object('paid', true, 'platform', 'google', 'signal', v_google ->> 'signal', 'label', v_google ->> 'label',
                              'campaign_id', coalesce(nullif(v_google ->> 'campaign_id', ''), v_first_camp), 'origin', v_google ->> 'origin');
  end if;
  return jsonb_build_object('paid', false, 'platform', coalesce(v_platform, 'none'),
                            'signal', case when cardinality(v_organic) > 0 then 'organic_form' when v_platform is not null then 'utm_only' else 'none' end,
                            'label', null, 'campaign_id', v_first_camp, 'origin', null);
end $fn$;

-- ---------- interests (PART 4 'Several interests') ----------
/* Catalogue universities named in a preference: the whole text when it names one exactly, else each part split on
   , / & ; or ' or ', matched with match_university. In order of mention, without repeats. */
create or replace function b2b.university_ids(p_text text)
returns bigint[] language sql stable security definer set search_path = '' as $fn$
  with t as (select nullif(trim(p_text), '') v),
       whole as (select u.id from public.catalog_universities u, t
                  where t.v is not null and b2b.norm_key(t.v) <> ''
                    and (b2b.norm_key(u.name) = b2b.norm_key(t.v) or b2b.norm_key(u.short_name) = b2b.norm_key(t.v))
                  order by (b2b.norm_key(u.name) = b2b.norm_key(t.v)) desc, u.id limit 1),
       parts as (select p.part, p.n from t, regexp_split_to_table(t.v, '\s*(?:,|/|&|;|\s+or\s+)\s*', 'i') with ordinality p(part, n)
                  where t.v is not null and not exists (select 1 from whole) and b2b.norm_key(p.part) <> ''),
       m as (select b2b.match_university(parts.part) id, parts.n from parts)
  select coalesce((select array[whole.id] from whole),
                  (select array_agg(y.id order by y.first_n) from (select m.id, min(m.n) first_n from m where m.id is not null group by m.id) y),
                  '{}'::bigint[]);
$fn$;

/* The lead's primary interest in catalogue terms (replaces m6a; same keys plus course_text, university_ids,
   segment_exact, rank 1 and source 'lead'). university_id is set only when exactly one university is named;
   segment = course|level|mode, segment_exact = segment|u<university_id>. */
create or replace function b2b.lead_interest(l public.student_leads)
returns jsonb language sql stable set search_path = '' as $fn$
  with x as (
    select b2b.match_course_key(coalesce(nullif(l.interested_course, ''), l.field_of_interest)) as ck,
           coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), '')) as course_text,
           nullif(trim(l.interested_specialization), '') as spec,
           b2b.interest_level(l.program_level) as lvl,
           b2b.interest_mode(l.study_mode_preference) as mode,
           coalesce(nullif(trim(l.interested_university), ''), nullif(trim(l.university_preference), '')) as uni_text
  ), u as (select b2b.university_ids(x.uni_text) as ids from x),
     s as (select coalesce(x.ck, '?') || '|' || coalesce(x.lvl, '*') || '|' || coalesce(x.mode, '*') as seg from x)
  select jsonb_build_object(
    'course_key', x.ck,
    'course_text', x.course_text,
    'specialization', case when b2b.norm_key(x.spec) in ('', 'general', 'any', 'notsure', 'none', 'na') then null else x.spec end,
    'level', x.lvl,
    'mode', x.mode,
    'university_id', case when cardinality(u.ids) = 1 then u.ids[1] end,
    'university_ids', to_jsonb(u.ids),
    'university_text', x.uni_text,
    'segment', s.seg,
    'segment_exact', case when cardinality(u.ids) = 1 then s.seg || '|u' || u.ids[1] end,
    'rank', 1,
    'source', 'lead')
  from x, u, s;
$fn$;

/* Every interest in the order the engine tries them: the primary (b2b.lead_interest), then the live lead_interests rows
   by position, in the same shape (rank 2.., source, position, interest_id), without repeats of course + specialization,
   cut at engine.max_interests (default 5, 1-10). */
create or replace function b2b.lead_interest_list(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_max int := least(greatest(coalesce((select (s.value ->> 'max_interests')::int from b2b.settings s
                                          where s.key = 'engine' and (s.value ->> 'max_interests') ~ '^[0-9]+$'), 5), 1), 10);
  v_first jsonb := b2b.lead_interest(l);
  v_out jsonb;
  v_seen text[] := '{}';
  v_key text;
  v_ck text;
  v_spec text;
  v_lvl text;
  v_mode text;
  v_seg text;
  v_ids bigint[];
  r b2b.lead_interests;
begin
  v_out := jsonb_build_array(v_first);
  v_seen := array_append(v_seen, coalesce(v_first ->> 'course_key', 'txt:' || lower(coalesce(v_first ->> 'course_text', ''))) || '|'
                                 || b2b.norm_key(v_first ->> 'specialization'));
  for r in select i.* from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null order by i.position, i.id loop
    exit when jsonb_array_length(v_out) >= v_max;
    v_ck := coalesce(nullif(trim(r.course_key), ''), b2b.match_course_key(r.course_text));
    v_spec := case when b2b.norm_key(r.specialization) in ('', 'general', 'any', 'notsure', 'none', 'na') then null else trim(r.specialization) end;
    v_key := coalesce(v_ck, 'txt:' || lower(trim(r.course_text))) || '|' || b2b.norm_key(v_spec);
    continue when v_key = any (v_seen);
    v_seen := array_append(v_seen, v_key);
    v_ids := case when r.university_id is not null then array[r.university_id] else b2b.university_ids(r.university_text) end;
    v_lvl := b2b.interest_level(r.level);
    v_mode := b2b.interest_mode(r.mode);
    v_seg := coalesce(v_ck, '?') || '|' || coalesce(v_lvl, '*') || '|' || coalesce(v_mode, '*');
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'course_key', v_ck, 'course_text', r.course_text, 'specialization', v_spec, 'level', v_lvl, 'mode', v_mode,
      'university_id', case when cardinality(v_ids) = 1 then v_ids[1] end, 'university_ids', to_jsonb(coalesce(v_ids, '{}'::bigint[])),
      'university_text', r.university_text, 'segment', v_seg,
      'segment_exact', case when cardinality(v_ids) = 1 then v_seg || '|u' || v_ids[1] end,
      'rank', jsonb_array_length(v_out) + 1, 'source', r.source, 'position', r.position, 'interest_id', r.id));
  end loop;
  return v_out;
end $fn$;

/* The published offers matching one interest (PART 4 Step 1 'programme match'): live partner files (valid, active, in
   season), active catalogue programmes with the course key, plus level, mode and university when the student gave them,
   and the specialization exact (norm_key) or similar (trigram >= 0.5) when given, any when not; there is no 'General'
   fallback. Partners that are not closed and live (paused partners still offer), or with a test endpoint for the sandbox.
   spec_match: exact | similar | any. cat_min_qualification / cat_min_pct: the catalogue's minimums (b2b.offer_eligible). */
create or replace function b2b.interest_offers(p_int jsonb, p_sandbox boolean default false)
returns table (partner_id bigint, programme_id bigint, fees jsonb, eligibility jsonb, spec_match text, university_id bigint,
               cat_min_qualification text, cat_min_pct numeric)
language sql stable security definer set search_path = '' as $fn$
  with i as (
    select nullif(p_int ->> 'course_key', '') ck, nullif(p_int ->> 'level', '') lvl, nullif(p_int ->> 'mode', '') md,
           nullif(trim(p_int ->> 'specialization'), '') spec,
           coalesce((select array_agg(x::bigint) from jsonb_array_elements_text(case when jsonb_typeof(p_int -> 'university_ids') = 'array'
                                                                                    then p_int -> 'university_ids' else '[]'::jsonb end) x
                      where x ~ '^[0-9]+$'), '{}'::bigint[])
           || coalesce(case when (p_int ->> 'university_id') ~ '^[0-9]+$' then array[(p_int ->> 'university_id')::bigint] end, '{}'::bigint[]) unis)
  select o.partner_id, o.programme_id, o.fees, o.eligibility,
         case when i.spec is null then 'any' when b2b.norm_key(c.specialization) = b2b.norm_key(i.spec) then 'exact' else 'similar' end,
         c.university_id, c.min_qualification, c.min_pct_general
    from i
    join b2b.partner_programmes o on o.valid_to is null and o.active
    join public.catalog_programs c on c.id = o.programme_id and c.active
    join b2b.partners p on p.id = o.partner_id and p.status <> 'closed'
   where i.ck is not null
     and (o.season_from is null or o.season_from <= current_date) and (o.season_to is null or o.season_to >= current_date)
     and c.course_key = i.ck
     and (i.lvl is null or c.level = i.lvl)
     and (i.md is null or c.mode = i.md)
     and (cardinality(i.unis) = 0 or c.university_id = any (i.unis))
     and (i.spec is null or b2b.norm_key(c.specialization) = b2b.norm_key(i.spec)
          or public.similarity(lower(coalesce(c.specialization, '')), lower(i.spec)) >= 0.5)
     and case when coalesce(p_sandbox, false) then p.test_endpoint is not null else b2b.is_live('partner:' || p.id) end;
$fn$;

/* Does any live, non-closed partner offer this interest? Paused or full partners count (no_capacity, not the next
   interest; critic B4). */
create or replace function b2b.interest_offered(p_int jsonb)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select exists (select 1 from b2b.interest_offers(p_int, false));
$fn$;

/* R5: is any stated course (the primary or a live secondary interest) in Eduwit's catalogue? False when no course is
   stated (R7 decides that case). */
create or replace function b2b.course_known(l public.student_leads)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select coalesce(
    (coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), '')) is not null
     and b2b.course_in_catalogue(coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), ''))))
    or exists (select 1 from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null
                and b2b.course_in_catalogue(coalesce(nullif(trim(i.course_key), ''), i.course_text))), false);
$fn$;

-- ---------- commission per enrolment (Stage A) ----------
/* CPE of one partner offer, net of GST, with its basis (PART 4 Stage A):
   rate_for precedence (m21e); percent rates on the partner file's fee in the rate's basis, else the catalogue fee (a
   first-year basis falls back to totals); fixed rates as they are; tiered rates at the middle tier (p_basis 'middle'),
   or at the projected tier via tier_pick at p_conv (p_basis 'projected' with a conversion); GST-inclusive rates divided
   by 1 + money.gst_rate. Returns {cpe (null without a rate or fee), has_rate, rate_id, rate_scope, rate_type, pct,
   fee_base_inr, fee_basis yearly|total, fee_source partner_file|catalogue, gst_inclusive, tier_basis middle|projected}. */
create or replace function b2b.cpe_detail(p_partner bigint, p_programme bigint, p_fees jsonb, p_basis text default 'middle', p_conv numeric default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  r b2b.rates;
  c public.catalog_programs;
  f jsonb := case when jsonb_typeof(p_fees) = 'object' then p_fees else '{}'::jsonb end;
  v_gst numeric := coalesce((select (s.value ->> 'gst_rate')::numeric from b2b.settings s where s.key = 'money' and (s.value ->> 'gst_rate') ~ '^[0-9]+(\.[0-9]+)?$'), 0.18);
  v_fee numeric;
  v_basis text;
  v_src text;
  v_pct numeric;
  v_tier text;
  v_cpe numeric;
  v_py numeric := case when (f ->> 'yearly') ~ '^[0-9]+(\.[0-9]+)?$' then (f ->> 'yearly')::numeric end;
  v_pt numeric := case when (f ->> 'total') ~ '^[0-9]+(\.[0-9]+)?$' then (f ->> 'total')::numeric end;
begin
  r := b2b.rate_for(p_partner, p_programme);
  if r.id is null then
    return jsonb_build_object('cpe', null, 'has_rate', false, 'rate_id', null, 'rate_scope', null, 'rate_type', null, 'pct', null,
                              'fee_base_inr', null, 'fee_basis', null, 'fee_source', null, 'gst_inclusive', null, 'tier_basis', null);
  end if;
  select * into c from public.catalog_programs where id = p_programme;
  if r.fee_base = 'total' then
    v_basis := 'total';
    if v_pt is not null then v_fee := v_pt; v_src := 'partner_file'; elsif c.fee_total is not null then v_fee := c.fee_total; v_src := 'catalogue'; end if;
  else
    if v_py is not null then v_fee := v_py; v_basis := 'yearly'; v_src := 'partner_file';
    elsif c.fee_yearly is not null then v_fee := c.fee_yearly; v_basis := 'yearly'; v_src := 'catalogue';
    elsif v_pt is not null then v_fee := v_pt; v_basis := 'total'; v_src := 'partner_file';
    elsif c.fee_total is not null then v_fee := c.fee_total; v_basis := 'total'; v_src := 'catalogue';
    end if;
  end if;
  if r.rate_type = 'fixed' then
    v_cpe := r.value;
  elsif r.rate_type = 'percent' then
    v_pct := r.value;
    v_cpe := v_pct / 100 * v_fee;
  else
    if p_basis = 'projected' and p_conv is not null then
      v_pct := b2b.tier_pick(r.tiers, p_conv); v_tier := 'projected';
    else
      v_pct := b2b.tier_middle(r.tiers); v_tier := 'middle';
    end if;
    v_cpe := v_pct / 100 * v_fee;
  end if;
  if v_cpe is not null and r.gst_inclusive then v_cpe := v_cpe / (1 + v_gst); end if;
  return jsonb_build_object('cpe', round(v_cpe, 2), 'has_rate', true, 'rate_id', r.id, 'rate_scope', r.scope, 'rate_type', r.rate_type,
                            'pct', v_pct, 'fee_base_inr', case when r.rate_type = 'fixed' then null else v_fee end,
                            'fee_basis', case when r.rate_type = 'fixed' then null else v_basis end,
                            'fee_source', case when r.rate_type = 'fixed' then null else v_src end,
                            'gst_inclusive', r.gst_inclusive, 'tier_basis', v_tier);
end $fn$;

-- ---------- partner criteria (PART 4 Step 1) ----------
/* The lead's state and city for geography criteria, computed at decision time and never written: state, then the city
   through b2b.geo_places, then current_city_country (each part, as a city or a state name). {state, city, source}. */
create or replace function b2b.lead_geo(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_state text := nullif(trim(l.state), '');
  v_city text := nullif(trim(l.city), '');
  v_src text;
  g b2b.geo_places;
  v_part text;
  v_st text;
begin
  if v_city is not null then
    select * into g from b2b.geo_places where alias = b2b.norm_key(v_city);
    if g.alias is not null then v_city := g.city; end if;
  end if;
  if v_state is not null then
    v_src := 'state';
  elsif g.alias is not null then
    v_state := g.state; v_src := 'city';
  end if;
  if v_state is null or v_city is null then
    for v_part in select trim(x) from regexp_split_to_table(coalesce(l.current_city_country, ''), '[,;/|]') x where trim(x) <> '' loop
      select * into g from b2b.geo_places where alias = b2b.norm_key(v_part);
      if g.alias is not null then
        v_city := coalesce(v_city, g.city);
        if v_state is null then v_state := g.state; v_src := 'current_city_country'; end if;
        exit;
      end if;
      select distinct p.state into v_st from b2b.geo_places p where b2b.norm_key(p.state) = b2b.norm_key(v_part) limit 1;
      if v_st is not null and v_state is null then v_state := v_st; v_src := 'current_city_country'; end if;
    end loop;
  end if;
  return jsonb_build_object('state', v_state, 'city', v_city, 'source', coalesce(v_src, case when v_city is not null then 'city' end));
end $fn$;

/* Does the lead meet the partner's agreed criteria (partners.lead_criteria)? Checks, in order: states_include,
   states_exclude, cities_include, cities_exclude (cities through geo_places aliases), sources_exclude,
   qualifications_include (levels from b2b.qualification_level), min_academic_pct, min_work_experience_years.
   A value the lead does not have follows p_criteria.unknown ('pass' | 'fail'), else p_unknown, else 'fail' (D32);
   this applies to exclusion lists too. Returns {ok, cause 'criteria' (null when ok), why, unknown_passed[]}. */
create or replace function b2b.criteria_check(p_criteria jsonb, l public.student_leads, p_geo jsonb, p_unknown text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  c jsonb := case when jsonb_typeof(p_criteria) = 'object' then p_criteria else '{}'::jsonb end;
  u text := case when lower(c ->> 'unknown') in ('pass', 'fail') then lower(c ->> 'unknown')
                 when lower(p_unknown) in ('pass', 'fail') then lower(p_unknown) else 'fail' end;
  v_state text := nullif(trim(p_geo ->> 'state'), '');
  v_city text := nullif(trim(p_geo ->> 'city'), '');
  v_src text := nullif(lower(trim(l.lead_source)), '');
  v_q text := b2b.qualification_level(l.highest_qualification);
  v_pct numeric := l.academic_score_pct;
  v_exp numeric := l.work_experience_years_num;
  v_min numeric;
  v_passed text[] := '{}';
  si jsonb := case when jsonb_typeof(c -> 'states_include') = 'array' then c -> 'states_include' else '[]'::jsonb end;
  se jsonb := case when jsonb_typeof(c -> 'states_exclude') = 'array' then c -> 'states_exclude' else '[]'::jsonb end;
  ci jsonb := case when jsonb_typeof(c -> 'cities_include') = 'array' then c -> 'cities_include' else '[]'::jsonb end;
  ce jsonb := case when jsonb_typeof(c -> 'cities_exclude') = 'array' then c -> 'cities_exclude' else '[]'::jsonb end;
  so jsonb := case when jsonb_typeof(c -> 'sources_exclude') = 'array' then c -> 'sources_exclude' else '[]'::jsonb end;
  qi jsonb := case when jsonb_typeof(c -> 'qualifications_include') = 'array' then c -> 'qualifications_include' else '[]'::jsonb end;
begin
  if v_pct is null and l.academic_percentage_gpa ~ '^\s*[0-9]{1,3}(\.[0-9]+)?\s*%?\s*$' then
    v_pct := (regexp_replace(l.academic_percentage_gpa, '[^0-9.]', '', 'g'))::numeric;
    if v_pct <= 10 or v_pct > 100 then v_pct := null; end if;   -- a CGPA or nonsense is not a percentage
  end if;
  if v_exp is null then
    if lower(coalesce(l.work_experience_years, '')) ~ '(fresher|no experience|^\s*(none|nil|no)\s*$)' then v_exp := 0;
    elsif l.work_experience_years ~ '[0-9]' then
      v_exp := nullif(substring(l.work_experience_years from '([0-9]+(\.[0-9]+)?)'), '')::numeric;
    end if;
  end if;

  -- geography
  if jsonb_array_length(si) > 0 then
    if v_state is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s state is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'state');
    elsif not exists (select 1 from jsonb_array_elements_text(si) s where b2b.norm_key(s) = b2b.norm_key(v_state)) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'outside the partner''s states', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  if jsonb_array_length(se) > 0 then
    if v_state is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s state is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      if not ('state' = any (v_passed)) then v_passed := array_append(v_passed, 'state'); end if;
    elsif exists (select 1 from jsonb_array_elements_text(se) s where b2b.norm_key(s) = b2b.norm_key(v_state)) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'state excluded by the partner', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  if jsonb_array_length(ci) > 0 then
    if v_city is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s city is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'city');
    elsif not exists (select 1 from jsonb_array_elements_text(ci) s
                       where b2b.norm_key(coalesce((select g.city from b2b.geo_places g where g.alias = b2b.norm_key(s)), s)) = b2b.norm_key(v_city)) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'outside the partner''s cities', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  if jsonb_array_length(ce) > 0 then
    if v_city is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s city is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      if not ('city' = any (v_passed)) then v_passed := array_append(v_passed, 'city'); end if;
    elsif exists (select 1 from jsonb_array_elements_text(ce) s
                   where b2b.norm_key(coalesce((select g.city from b2b.geo_places g where g.alias = b2b.norm_key(s)), s)) = b2b.norm_key(v_city)) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'city excluded by the partner', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  -- source
  if jsonb_array_length(so) > 0 then
    if v_src is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the lead''s source is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'source');
    elsif exists (select 1 from jsonb_array_elements_text(so) s where lower(trim(s)) = v_src) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'source excluded by the partner', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  -- qualification
  if jsonb_array_length(qi) > 0 then
    if v_q is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s qualification is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'qualification');
    elsif not exists (select 1 from jsonb_array_elements_text(qi) s
                       where coalesce(b2b.qualification_level(s), lower(trim(s))) = v_q) then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'qualification not accepted by the partner', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  if (c ->> 'min_academic_pct') ~ '^[0-9]+(\.[0-9]+)?$' and (c ->> 'min_academic_pct')::numeric > 0 then
    v_min := (c ->> 'min_academic_pct')::numeric;
    if v_pct is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s academic score is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'academic_pct');
    elsif v_pct < v_min then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'below the partner''s minimum academic score', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  if (c ->> 'min_work_experience_years') ~ '^[0-9]+(\.[0-9]+)?$' and (c ->> 'min_work_experience_years')::numeric > 0 then
    v_min := (c ->> 'min_work_experience_years')::numeric;
    if v_exp is null then
      if u = 'fail' then return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'the student''s work experience is not known', 'unknown_passed', to_jsonb(v_passed)); end if;
      v_passed := array_append(v_passed, 'work_experience');
    elsif v_exp < v_min then
      return jsonb_build_object('ok', false, 'cause', 'criteria', 'why', 'below the partner''s minimum work experience', 'unknown_passed', to_jsonb(v_passed));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'cause', null, 'why', null, 'unknown_passed', to_jsonb(v_passed));
end $fn$;

/* Is the lead eligible for one offer? The partner file's minimums (eligibility.min_qualification, min_pct), else the
   catalogue's (min_qualification, min_pct_general). A minimum that cannot be read as a level is no requirement; a value
   the lead does not have follows p_unknown ('pass' | 'fail', default 'fail'). */
create or replace function b2b.offer_eligible(p_elig jsonb, p_cat_min_qual text, p_cat_min_pct numeric, l public.student_leads, p_unknown text default 'fail')
returns boolean language plpgsql stable set search_path = '' as $fn$
declare
  u text := case when lower(p_unknown) = 'pass' then 'pass' else 'fail' end;
  v_req_q text := b2b.qualification_level(coalesce(nullif(trim(p_elig ->> 'min_qualification'), ''), p_cat_min_qual));
  v_req_pct numeric := coalesce(case when (p_elig ->> 'min_pct') ~ '^[0-9]+(\.[0-9]+)?$' then (p_elig ->> 'min_pct')::numeric end, p_cat_min_pct);
  v_q text := b2b.qualification_level(l.highest_qualification);
  v_pct numeric := l.academic_score_pct;
begin
  if v_pct is null and l.academic_percentage_gpa ~ '^\s*[0-9]{1,3}(\.[0-9]+)?\s*%?\s*$' then
    v_pct := (regexp_replace(l.academic_percentage_gpa, '[^0-9.]', '', 'g'))::numeric;
    if v_pct <= 10 or v_pct > 100 then v_pct := null; end if;
  end if;
  if v_req_q is not null then
    if v_q is null then
      if u = 'fail' then return false; end if;
    elsif b2b.qualification_rank(v_q) < b2b.qualification_rank(v_req_q) then
      return false;
    end if;
  end if;
  if v_req_pct is not null and v_req_pct > 0 then
    if v_pct is null then
      if u = 'fail' then return false; end if;
    elsif v_pct < v_req_pct then
      return false;
    end if;
  end if;
  return true;
end $fn$;

-- ---------- Witty (read-only) and the PART 2 hand-off points ----------
/* Is the phone blocked by Witty now? The same predicate as public.w2_is_blocked, read directly (critic A1). */
create or replace function b2b.witty_blocked(p_digits text)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select coalesce(p_digits, '') <> ''
     and exists (select 1 from public.w2_blocks b
                  where b.phone = p_digits and b.unblocked_at is null and (b.blocked_until is null or b.blocked_until > now()));
$fn$;

/* The student's last own message to Witty (Amendment 1): the later of the newest w2_inbox row and the newest inbound
   w2_messages row for the phone. Witty's replies and nurture sends do not count. Null when there is none. */
create or replace function b2b.student_last_inbound(p_digits text)
returns timestamptz language sql stable security definer set search_path = '' as $fn$
  select greatest((select i.received_at from public.w2_inbox i where i.phone = p_digits order by i.received_at desc limit 1),
                  (select m.created_at from public.w2_messages m where m.phone = p_digits and m.direction = 'in' order by m.created_at desc limit 1));
$fn$;

/* A lead that came through Witty (R9 qualification by Witty's label; critic B15). Never a B2C-created lead. */
create or replace function b2b.is_witty_lead(l public.student_leads)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select case
    when lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(coalesce(
           (select s.value -> 'b2c_sources' from b2b.settings s where s.key = 'engine' and jsonb_typeof(s.value -> 'b2c_sources') = 'array'),
           '["b2c_created","b2c_whatsapp"]'::jsonb)) x) then false
    else lower(coalesce(l.first_agent_channel, '')) = 'whatsapp'
         or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.source_system = 'witty') end;
$fn$;

/* PART 2 hand-off point of a qualified chat lead, whichever comes first:
     escalated        lead_stage ESCALATION, a paused bot, or a lead.escalated touchpoint created at or after p_since
                      (created_at, never Witty's occurred_at; critic A2)
     final_programme  interested_university is set
     idle             the later of the student's last message, Witty's last reply and p_since is older than
                      a3_fixed.witty_idle_minutes (30)
   {open, gate escalated|final_programme|idle|chatting, last_inbound, decide_after}. */
create or replace function b2b.chat_gate(l public.student_leads, p_since timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_idle int := coalesce((select (s.value -> 'a3_fixed' ->> 'witty_idle_minutes')::int from b2b.settings s
                           where s.key = 'engine' and (s.value -> 'a3_fixed' ->> 'witty_idle_minutes') ~ '^[0-9]+$'), 30);
  v_since timestamptz := coalesce(p_since, l.created_at);
  v_in timestamptz := b2b.student_last_inbound(b2b.phone_digits(l.whatsapp_number));
  v_last timestamptz;
begin
  if upper(coalesce(l.lead_stage, '')) = 'ESCALATION' or coalesce(l.is_bot_paused, false)
     or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.event_type = 'lead.escalated' and t.created_at >= v_since) then
    return jsonb_build_object('open', true, 'gate', 'escalated', 'last_inbound', v_in, 'decide_after', null);
  end if;
  if nullif(trim(l.interested_university), '') is not null then
    return jsonb_build_object('open', true, 'gate', 'final_programme', 'last_inbound', v_in, 'decide_after', null);
  end if;
  v_last := greatest(coalesce(v_in, l.created_at), coalesce(l.last_agent_message_at, l.created_at), v_since);
  return jsonb_build_object('open', v_last < now() - make_interval(mins => v_idle), 'gate', case when v_last < now() - make_interval(mins => v_idle) then 'idle' else 'chatting' end,
                            'last_inbound', v_in, 'decide_after', v_last + make_interval(mins => v_idle));
end $fn$;

/* The lead's current routing episode (PART 5.5-5.7, D3): partner allocations of the current cycle created after the
   cycle's latest in_house allocation or recalled allocation. origin = the origin of the episode's first partner
   allocation (what a cascade continues: auto, pass, to_partners, requalify, reroute or sandbox), else 'auto'.
   {start_at (-infinity when none), origin, in_house_allocation_id, boundary in_house|recall|null, boundary_allocation_id,
   partner_allocation_ids[]}. Allocation ids order creation, so the same-transaction case is exact. */
create or replace function b2b.episode(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_cycle int := coalesce(l.cycle_no, 1);
  ih b2b.allocations;
  rc b2b.allocations;
  v_at timestamptz;
  v_bid bigint;
  v_kind text;
  v_origin text;
  v_ids jsonb;
begin
  select a.* into ih from b2b.allocations a where a.lead_id = l.id and a.cycle_no = v_cycle and a.destination_type = 'in_house'
   order by a.id desc limit 1;
  select a.* into rc from b2b.allocations a where a.lead_id = l.id and a.cycle_no = v_cycle and a.status = 'recalled'
   order by coalesce(a.outcome_at, a.updated_at) desc, a.id desc limit 1;
  if rc.id is not null and (ih.id is null or coalesce(rc.outcome_at, rc.updated_at) >= ih.created_at) then
    v_at := coalesce(rc.outcome_at, rc.updated_at); v_bid := rc.id; v_kind := 'recall';
  elsif ih.id is not null then
    v_at := ih.created_at; v_bid := ih.id; v_kind := 'in_house';
  end if;
  select a.origin into v_origin from b2b.allocations a
   where a.lead_id = l.id and a.cycle_no = v_cycle and a.destination_type = 'partner' and a.id > coalesce(v_bid, 0)
   order by a.id limit 1;
  select coalesce(jsonb_agg(a.id order by a.id), '[]'::jsonb) into v_ids from b2b.allocations a
   where a.lead_id = l.id and a.cycle_no = v_cycle and a.destination_type = 'partner' and a.id > coalesce(v_bid, 0);
  return jsonb_build_object('start_at', coalesce(v_at, '-infinity'::timestamptz), 'origin', coalesce(v_origin, 'auto'),
                            'in_house_allocation_id', ih.id, 'boundary', v_kind, 'boundary_allocation_id', v_bid,
                            'partner_allocation_ids', v_ids);
end $fn$;

-- ---------- the B2C hand-off payload (contract version 3) ----------
/* The data of b2c.lead_handed_off for an in_house allocation (D47):
   {lead_id, allocation_id, reference, decision_id, b2c_lane, reason, cause, contract_version 3, hold, handling
    {job, assignment, first_contact_script, nurture_first_message_after_days, previous_owner}, partner_bar,
    already_with_providers, partners_tried [{partner_id, partner_name, status, outcome, at}], missing, b2c_actions,
    welcome {template_hint, last_inbound_at}, consent {request_id, status, requested_at, expires_at, refused_at},
    lost {partner_id, partner_name, partner_record_id, lost_reason, lost_at, grace_ended_at, partner_status,
          partner_sub_status, partner_last_activity}, nurture_first_message_after_days, nurture_first_message_at,
    interests_tried, attribution, paid (legacy label), test}.
   p_extra: 'previous_owner' goes into handling (lost_handoff passes the owner it cleared); 'b2c_actions' replaces the
   computed list; any other key is added at the top level. Null when the allocation does not exist. */
create or replace function b2b.handoff_payload(p_allocation_id bigint, p_extra jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  d b2b.engine_decisions;
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  x jsonb := case when jsonb_typeof(p_extra) = 'object' then p_extra else '{}'::jsonb end;
  v_bar jsonb;
  v_lost b2b.allocations;
  v_lost_reason text;
  v_handling jsonb;
  v_days int;
  v_actions jsonb;
  v_welcome jsonb;
  v_req b2b.consent_requests;
  v_pc jsonb;
  v_consent jsonb;
  v_attr jsonb;
  v_missing jsonb;
  v_tried jsonb;
  v_lost_block jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then return null; end if;
  select * into l from public.student_leads where id = a.lead_id;
  if a.engine_decision_id is not null then select * into d from b2b.engine_decisions where id = a.engine_decision_id; end if;
  v_bar := b2b.partner_bar(l);

  if a.reason = 'partner_lost' then
    select y.* into v_lost from b2b.allocations y
     where y.lead_id = a.lead_id and y.destination_type = 'partner' and y.id < a.id and (y.lost_at is not null or y.outcome = 'lost')
     order by y.id desc limit 1;
    v_lost_reason := coalesce(v_lost.lost_detail ->> 'lost_reason', l.lost_reason);
    if v_lost.id is not null then
      v_lost_block := jsonb_build_object(
        'partner_id', v_lost.partner_id,
        'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = v_lost.partner_id),
        'partner_record_id', coalesce(v_lost.partner_record_id, l.partner_record_id),
        'lost_reason', v_lost_reason,
        'lost_at', coalesce(v_lost.lost_at, v_lost.outcome_at),
        'grace_ended_at', case when v_lost.lost_at is not null then v_lost.lost_grace_until end,
        'partner_status', coalesce(v_lost.lost_detail ->> 'status', l.partner_stage_raw),
        'partner_sub_status', coalesce(v_lost.lost_detail ->> 'sub_status', l.partner_sub_stage_raw),
        'partner_last_activity', v_lost.lost_detail ->> 'last_activity_at');
    end if;
  end if;

  v_handling := b2b.b2c_handling(a.reason, a.b2c_lane, v_bar, v_lost_reason)
                || jsonb_build_object('previous_owner', case when x ? 'previous_owner' then x -> 'previous_owner'
                                                             when a.reason = 'manual_route_failed' then to_jsonb(l.owner_user_id) end);
  v_days := (v_handling ->> 'nurture_first_message_after_days')::int;

  v_actions := case when jsonb_typeof(x -> 'b2c_actions') = 'array' then x -> 'b2c_actions'
                    when a.reason = 'not_qualified' and (b2b.is_witty_lead(l) or coalesce((e ->> 'welcome_for_all_nurture')::boolean, false))
                      then '["welcome_explore_programmes"]'::jsonb
                    else '[]'::jsonb end;
  if v_actions ? 'welcome_explore_programmes' then
    v_welcome := jsonb_build_object('template_hint', 'explore_programmes', 'last_inbound_at', b2b.student_last_inbound(b2b.phone_digits(l.whatsapp_number)));
  end if;

  select r.* into v_req from b2b.consent_requests r where r.lead_id = a.lead_id and r.cycle_no = a.cycle_no
   order by r.created_at desc, r.id desc limit 1;
  v_pc := b2b.partner_consent(l);
  if v_req.id is not null or coalesce((v_pc ->> 'refused')::boolean, false) then
    v_consent := jsonb_build_object('request_id', v_req.id, 'status', v_req.status, 'requested_at', coalesce(v_req.published_at, v_req.created_at),
                                    'expires_at', v_req.expires_at, 'refused_at', v_pc -> 'refused_at');
  end if;

  v_missing := case a.reason when 'not_qualified' then coalesce(b2b.lead_class(l) -> 'missing', '[]'::jsonb)
                             when 'consent_no_answer' then '["partner_consent"]'::jsonb else '[]'::jsonb end;

  select coalesce(jsonb_agg(jsonb_build_object('partner_id', y.partner_id, 'partner_name', coalesce(p.display_name, p.name), 'status', y.status,
                                               'outcome', y.outcome, 'at', coalesce(y.outcome_at, y.pushed_at, y.created_at)) order by y.id), '[]'::jsonb)
    into v_tried
    from b2b.allocations y join b2b.partners p on p.id = y.partner_id
   where y.lead_id = a.lead_id and y.cycle_no = a.cycle_no and y.destination_type = 'partner' and y.id < a.id and y.is_test = a.is_test;

  v_attr := b2b.lead_attribution(l);

  return jsonb_build_object(
    'lead_id', a.lead_id, 'allocation_id', a.id, 'reference', a.reference, 'decision_id', a.engine_decision_id,
    'b2c_lane', a.b2c_lane, 'reason', a.reason, 'cause', a.cause, 'contract_version', 3,
    'hold', b2b.b2c_hold(l), 'handling', v_handling, 'partner_bar', v_bar,
    'already_with_providers', b2b.lead_other_providers(a.lead_id), 'partners_tried', v_tried,
    'missing', v_missing, 'b2c_actions', v_actions, 'welcome', v_welcome, 'consent', v_consent, 'lost', v_lost_block,
    'nurture_first_message_after_days', v_days,
    'nurture_first_message_at', case when v_days is not null then a.created_at + make_interval(days => v_days) end,
    'interests_tried', coalesce(d.interests, '[]'::jsonb), 'attribution', v_attr,
    'paid', case when coalesce((v_attr ->> 'paid')::boolean, false) then v_attr ->> 'label' end,
    'test', a.is_test)
    || (x - 'previous_owner' - 'b2c_actions');
end $fn$;

-- ---------- published events (m14a), now with the Addendum 3 B2C types ----------
/* The published form of an internal event: zero, one or two envelopes. Test leads are flagged, never hidden.
   b2c.* and b2b.* envelopes carry contract_version 3. b2b.lead_routed_to_partner follows the acceptance of a lead that
   reached a partner by a manual route to partners or by a requalification (Addendum 1 §1, Addendum 3 R7). */
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
    || case when v_type like 'b2c.%' then jsonb_build_object('contract_version', 3) else '{}'::jsonb end
    || jsonb_build_object('id', 'evt_' || e.id, 'type', v_type,
         'data', coalesce(e.payload, '{}') || jsonb_strip_nulls(jsonb_build_object('allocation_id', e.allocation_id, 'reference', a.reference,
                                                                                   'partner_id', e.partner_id, 'b2c_lane', a.b2c_lane)));
  return next;
  if e.type = 'lead.accepted' and (a.mode = 'manual' or a.origin in ('to_partners', 'requalify')) then
    event_type := 'b2b.lead_routed_to_partner';
    envelope := v_base || jsonb_build_object('contract_version', 3, 'id', 'evt_' || e.id || '_r', 'type', event_type,
      'data', jsonb_strip_nulls(jsonb_build_object('allocation_id', a.id, 'reference', a.reference, 'partner_id', a.partner_id, 'origin', a.origin)));
    return next;
  end if;
end $fn$;

create or replace trigger events_fanout after insert on b2b.events for each row
  when (new.type in ('lead.routed', 'lead.accepted', 'b2c.lead_handed_off', 'b2c.lead_reenquired', 'b2c.lead_flagged',
                     'b2c.lead_close_agreed', 'b2c.lead_requalified', 'b2c.lead_reengaged', 'b2c.consent_requested',
                     'b2c.consent_closed', 'partner.stage_applied', 'lead.enrolled'))
  execute function b2b.events_fanout();

/* GET /v1/handoffs (m14d), plus the Addendum 3 types. The cursor advances past every scanned event, including ones that
   publish nothing to B2C, and echoes the caller's cursor when nothing new happened. */
create or replace function b2b.api_b2c_handoffs(p_key text, p_since timestamptz, p_after bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare k jsonb; v_rows jsonb; v_last bigint;
begin
  k := b2b.api_key_check(p_key, 'events');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  with scanned as (
    select ev from b2b.events ev
     where ev.type in ('b2c.lead_handed_off', 'b2c.lead_reenquired', 'b2c.lead_flagged', 'b2c.lead_close_agreed', 'lead.accepted',
                       'b2c.lead_requalified', 'b2c.lead_reengaged', 'b2c.consent_requested', 'b2c.consent_closed')
       and ev.id > coalesce(p_after, 0) and ev.occurred_at >= coalesce(p_since, '-infinity')
     order by ev.id limit least(greatest(coalesce(p_limit, 200), 1), 500))
  select coalesce((select jsonb_agg(p.envelope order by (s.ev).id, p.envelope ->> 'id')
                     from scanned s cross join lateral b2b.published_events(s.ev) p
                    where p.event_type like 'b2c.%' or p.event_type = 'b2b.lead_routed_to_partner'), '[]'),
         (select max((s.ev).id) from scanned s)
    into v_rows, v_last;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('events', v_rows, 'next_after', coalesce(v_last, p_after)));
end $fn$;

/* Webhook endpoints (m23a), plus the Addendum 3 event types. */
create or replace function b2b.webhook_endpoint_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_events text[];
  v_bad text;
  w b2b.webhook_endpoints;
  v_known text[] := array['lead.allocated', 'lead.accepted', 'lead.status_changed', 'lead.enrolled', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                          'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_upserted', 'b2c.lead_released', 'b2c.leads_batch',
                          'b2c.lead_requalified', 'b2c.lead_reengaged', 'b2c.consent_requested', 'b2c.consent_closed',
                          'b2b.lead_routed_to_partner', 'lead.*', 'b2c.*', 'b2b.*', '*'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(distinct trim(x)) into v_events from jsonb_array_elements_text(coalesce(p -> 'events', '[]')) x where trim(x) <> '';
  if coalesce(cardinality(v_events), 0) = 0 then raise exception 'choose at least one event' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from unnest(v_events) x where not x = any (v_known);
  if v_bad is not null then raise exception 'unknown event: %', v_bad using errcode = '22023'; end if;
  if coalesce(p ->> 'url', '') !~ '^https://[^\s]+$' then raise exception 'the URL must start with https://' using errcode = '22023'; end if;
  if v_id is null then
    insert into b2b.webhook_endpoints (name, consumer, url, events)
    values (trim(p ->> 'name'), coalesce(p ->> 'consumer', 'other'), trim(p ->> 'url'), v_events) returning * into w;
  else
    update b2b.webhook_endpoints set name = trim(p ->> 'name'), url = trim(p ->> 'url'), events = v_events, updated_at = now()
     where id = v_id returning * into w;
    if w.id is null then raise exception 'endpoint not found' using errcode = 'P0002'; end if;
  end if;
  perform b2b.log_event('webhook.saved', null, null, null, jsonb_build_object('endpoint_id', w.id, 'consumer', w.consumer, 'events', v_events));
  return to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null);
exception when unique_violation then
  raise exception 'there is already a B2C CRM endpoint; edit it instead' using errcode = '22023';
end $fn$;

-- ---------- grants: internal helpers, service_role only ----------
revoke execute on function
  b2b.phone_digits(text), b2b.np_fingerprint(public.student_leads), b2b.interest_level(text), b2b.interest_mode(text),
  b2b.qualification_level(text), b2b.qualification_rank(text), b2b.tier_middle(jsonb), b2b.setting_for_update(text),
  b2b.lead_family(bigint), b2b.partner_bar(public.student_leads), b2b.lead_other_providers(bigint), b2b.dup_history(bigint),
  b2b.partner_bar_set(bigint, text, bigint, text), b2b.b2c_hold(public.student_leads), b2b.b2c_handling(text, text, jsonb, text),
  b2b.consent_text_covers(text), b2b.partner_consent(public.student_leads), b2b.lead_attribution(public.student_leads),
  b2b.university_ids(text), b2b.lead_interest_list(public.student_leads), b2b.interest_offers(jsonb, boolean),
  b2b.interest_offered(jsonb), b2b.course_known(public.student_leads), b2b.cpe_detail(bigint, bigint, jsonb, text, numeric),
  b2b.lead_geo(public.student_leads), b2b.criteria_check(jsonb, public.student_leads, jsonb, text),
  b2b.offer_eligible(jsonb, text, numeric, public.student_leads, text), b2b.witty_blocked(text), b2b.student_last_inbound(text),
  b2b.is_witty_lead(public.student_leads), b2b.chat_gate(public.student_leads, timestamptz), b2b.episode(public.student_leads),
  b2b.handoff_payload(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function
  b2b.phone_digits(text), b2b.np_fingerprint(public.student_leads), b2b.interest_level(text), b2b.interest_mode(text),
  b2b.qualification_level(text), b2b.qualification_rank(text), b2b.tier_middle(jsonb), b2b.setting_for_update(text),
  b2b.lead_family(bigint), b2b.partner_bar(public.student_leads), b2b.lead_other_providers(bigint), b2b.dup_history(bigint),
  b2b.partner_bar_set(bigint, text, bigint, text), b2b.b2c_hold(public.student_leads), b2b.b2c_handling(text, text, jsonb, text),
  b2b.consent_text_covers(text), b2b.partner_consent(public.student_leads), b2b.lead_attribution(public.student_leads),
  b2b.university_ids(text), b2b.lead_interest_list(public.student_leads), b2b.interest_offers(jsonb, boolean),
  b2b.interest_offered(jsonb), b2b.course_known(public.student_leads), b2b.cpe_detail(bigint, bigint, jsonb, text, numeric),
  b2b.lead_geo(public.student_leads), b2b.criteria_check(jsonb, public.student_leads, jsonb, text),
  b2b.offer_eligible(jsonb, text, numeric, public.student_leads, text), b2b.witty_blocked(text), b2b.student_last_inbound(text),
  b2b.is_witty_lead(public.student_leads), b2b.chat_gate(public.student_leads, timestamptz), b2b.episode(public.student_leads),
  b2b.handoff_payload(bigint, jsonb)
  to service_role;
