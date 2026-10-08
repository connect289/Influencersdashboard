-- M20c: money engine, part 2 (B12.2, B12.7): verification with proof, cancel, refund with reversal lines, manual adjustments,
-- and the scan that records enrollments for partner leads that reached "enrolled". Part 1 is m20b.

/* Proof → verified. p: proof_type (statement_line | university_confirmation | fee_receipt), proof_ref, proof_url, and optionally corrected
   fee_amount_inr, fee_paid_inr, enrolled_on, programme_id. */
create or replace function b2b.enrollment_verify(p_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e public.enrollments;
  m jsonb;
  v_days int := coalesce((b2b.money_cfg() ->> 'refund_window_days')::int, 30);
  v_type text := p ->> 'proof_type';
  v_ref text := nullif(left(trim(p ->> 'proof_ref'), 300), '');
  v_on date := nullif(p ->> 'enrolled_on', '')::date;
  c public.catalog_programs;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into e from public.enrollments where id = p_id for update;
  if e.id is null or e.source_product is distinct from 'b2b' then raise exception 'enrollment not found' using errcode = 'P0002'; end if;
  if e.status <> 'reported' then raise exception 'only a reported enrollment can be verified (this one is %)', e.status using errcode = '22023'; end if;
  if v_type not in ('statement_line', 'university_confirmation', 'fee_receipt') then raise exception 'choose the kind of proof' using errcode = '22023'; end if;
  if v_ref is null then raise exception 'describe the proof (statement row, confirmation number or receipt number)' using errcode = '22023'; end if;
  if nullif(p ->> 'proof_url', '') is not null and p ->> 'proof_url' !~ '^https://' then raise exception 'the proof link must start with https://' using errcode = '22023'; end if;
  if v_on > current_date then raise exception 'the enrolment date is in the future' using errcode = '22023'; end if;
  if nullif(p ->> 'fee_amount_inr', '') is not null and not ((p ->> 'fee_amount_inr')::numeric between 1 and 100000000) then
    raise exception 'the fee looks wrong' using errcode = '22023';
  end if;
  if nullif(p ->> 'programme_id', '') is not null then
    select * into c from public.catalog_programs where id = (p ->> 'programme_id')::bigint;
    if c.id is null then raise exception 'choose a catalogue programme' using errcode = '22023'; end if;
  end if;

  update public.enrollments
     set fee_amount_inr = coalesce(nullif(p ->> 'fee_amount_inr', '')::numeric, fee_amount_inr),
         fee_paid_inr = coalesce(nullif(p ->> 'fee_paid_inr', '')::numeric, fee_paid_inr),
         enrolled_on = coalesce(v_on, enrolled_on),
         programme_id = coalesce(c.id, programme_id), programme_name = coalesce(c.program_name, programme_name),
         updated_at = now()
   where id = e.id;
  m := b2b.enrollment_expect(e.id);
  if m ->> 'error' = 'no_rate' then
    raise exception 'no commission rate in force for this partner and programme on the enrolment date; add one in Routing → Rates' using errcode = '22023';
  elsif m ->> 'error' = 'no_fee' then
    raise exception 'the fee is unknown: enter the fee the student pays' using errcode = '22023';
  end if;
  update b2b.earnings set status = 'realised', realised_at = now() where enrollment_id = e.id and kind = 'commission' and status = 'expected';
  select * into e from public.enrollments where id = e.id;
  update public.enrollments
     set status = 'verified', verified_at = now(), verified_by = auth.uid(), proof_ref = v_type || ': ' || v_ref,
         proof_url = coalesce(nullif(p ->> 'proof_url', ''), proof_url), refund_window_ends_on = e.enrolled_on + v_days,
         realised_net_revenue_inr = (m ->> 'net')::numeric, updated_at = now()
   where id = e.id;
  update public.student_leads
     set realised_net_revenue_inr = (m ->> 'net')::numeric, expected_net_revenue_inr = (m ->> 'net')::numeric, enrollment_verified_at = now(),
         enrollment_status = 'verified', enrollment_date = e.enrolled_on, fee_amount_inr = coalesce(e.fee_amount_inr, fee_amount_inr), updated_by = 'b2b'
   where id = e.lead_id and allocation_id is not distinct from e.allocation_id;
  perform b2b.lead_stage_up(e.lead_id, 'verified');
  perform b2b.log_event('money.enrollment_verified', e.lead_id, e.allocation_id, e.partner_id,
                        jsonb_build_object('enrollment_id', e.id, 'proof_type', v_type, 'net_inr', m -> 'net', 'gross_inr', m -> 'gross', 'provisional', m -> 'provisional'));
  return jsonb_build_object('id', e.id, 'amounts', m);
end $fn$;

create or replace function b2b.enrollment_cancel(p_id bigint, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e public.enrollments;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into e from public.enrollments where id = p_id for update;
  if e.id is null or e.source_product is distinct from 'b2b' then raise exception 'enrollment not found' using errcode = 'P0002'; end if;
  if e.status <> 'reported' then raise exception 'only a reported enrollment can be cancelled; refund a verified one' using errcode = '22023'; end if;
  update public.enrollments set status = 'cancelled', refund_reason = left(trim(p_reason), 300), expected_net_revenue_inr = null, updated_at = now() where id = e.id;
  update b2b.earnings set status = 'void', note = 'enrollment cancelled: ' || left(trim(p_reason), 200) where enrollment_id = e.id and status = 'expected';
  update public.student_leads set expected_net_revenue_inr = null, enrollment_status = 'cancelled', updated_by = 'b2b'
   where id = e.lead_id and allocation_id is not distinct from e.allocation_id;
  perform b2b.log_event('money.enrollment_cancelled', e.lead_id, e.allocation_id, e.partner_id, jsonb_build_object('enrollment_id', e.id, 'reason', p_reason));
end $fn$;

/* p: refunded_on, reason, outside_window (true records it even after the window, when both sides agreed). */
create or replace function b2b.enrollment_refund(p_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e public.enrollments;
  v_on date := coalesce(nullif(p ->> 'refunded_on', '')::date, current_date);
  v_reason text := nullif(left(trim(p ->> 'reason'), 300), '');
  x b2b.earnings;
  v_total numeric := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into e from public.enrollments where id = p_id for update;
  if e.id is null or e.source_product is distinct from 'b2b' then raise exception 'enrollment not found' using errcode = 'P0002'; end if;
  if e.status <> 'verified' then raise exception 'only a verified enrollment can be refunded' using errcode = '22023'; end if;
  if v_on > current_date or v_on < e.enrolled_on then raise exception 'the refund date must be between the enrolment date and today' using errcode = '22023'; end if;
  if v_on > e.refund_window_ends_on and not coalesce((p ->> 'outside_window')::boolean, false) then
    raise exception 'the refund window ended on %; confirm that Eduwit agreed to refund the commission anyway', to_char(e.refund_window_ends_on, 'DD Mon YYYY')
      using errcode = '22023';
  end if;
  for x in select o.* from b2b.earnings o where o.enrollment_id = e.id and o.status = 'realised' and o.kind in ('commission', 'tier_adjustment')
                                            and not exists (select 1 from b2b.earnings r where r.reverses_id = o.id) loop
    insert into b2b.earnings (enrollment_id, allocation_id, partner_id, lead_id, period, kind, status, rate_id, net_inr, gst_rate, gst_inr, gross_inr,
                              reverses_id, note, realised_at, created_by)
    values (e.id, e.allocation_id, e.partner_id, e.lead_id, b2b.period_of(v_on), 'reversal', 'realised', x.rate_id, -x.net_inr, x.gst_rate, -x.gst_inr,
            -x.gross_inr, x.id, 'refund: ' || v_reason, now(), coalesce(auth.uid()::text, 'system'));
    v_total := v_total + x.net_inr;
  end loop;
  update public.enrollments set status = 'refunded', refunded_at = v_on::timestamptz, refund_reason = v_reason, realised_net_revenue_inr = 0, updated_at = now()
   where id = e.id;
  update public.student_leads set realised_net_revenue_inr = 0, enrollment_status = 'refunded', updated_by = 'b2b'
   where id = e.lead_id and allocation_id is not distinct from e.allocation_id;
  perform b2b.log_event('money.enrollment_refunded', e.lead_id, e.allocation_id, e.partner_id,
                        jsonb_build_object('enrollment_id', e.id, 'reason', v_reason, 'reversed_net_inr', v_total, 'outside_window', v_on > e.refund_window_ends_on));
  return jsonb_build_object('reversed_net_inr', v_total);
end $fn$;

/* A signed adjustment the Admin records (agreed with the partner), realised at once. p: partner_id, enrollment_id?, net_inr, note. */
create or replace function b2b.earning_manual(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_enr public.enrollments;
  v_net numeric := round(nullif(p ->> 'net_inr', '')::numeric, 2);
  v_g numeric := coalesce((b2b.money_cfg() ->> 'gst_rate')::numeric, 0.18);
  v_note text := nullif(left(trim(p ->> 'note'), 300), '');
  v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_net is null or v_net = 0 or abs(v_net) > 10000000 then raise exception 'enter a non-zero amount' using errcode = '22023'; end if;
  if v_note is null then raise exception 'say what was agreed' using errcode = '22023'; end if;
  if nullif(p ->> 'enrollment_id', '') is not null then
    select * into v_enr from public.enrollments where id = (p ->> 'enrollment_id')::bigint and partner_id = v_partner and source_product = 'b2b';
    if v_enr.id is null then raise exception 'that enrollment is not this partner''s' using errcode = '22023'; end if;
  end if;
  insert into b2b.earnings (enrollment_id, allocation_id, partner_id, lead_id, period, kind, status, net_inr, gst_rate, gst_inr, gross_inr, note, realised_at, created_by)
  values (v_enr.id, v_enr.allocation_id, v_partner, v_enr.lead_id, b2b.period_of(current_date), 'manual_adjustment', 'realised', v_net, v_g,
          round(v_net * v_g, 2), v_net + round(v_net * v_g, 2), v_note, now(), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  perform b2b.log_event('money.adjustment', v_enr.lead_id, v_enr.allocation_id, v_partner, jsonb_build_object('earning_id', v_id, 'net_inr', v_net, 'note', v_note));
  return v_id;
end $fn$;

/* Partner leads that reached enrolled (or later) without an enrollment row get one; reported ones without a line are retried. */
create or replace function b2b.money_scan(p_limit int default 200)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  v_new int := 0;
  v_err int := 0;
  v_retry int := 0;
begin
  for r in
    select a.id, case when l.enrollment_date >= (a.created_at at time zone 'Asia/Kolkata')::date then l.enrollment_date end as enrollment_date
      from public.student_leads l
      join b2b.allocations a on a.id = l.allocation_id
     where l.stage in ('enrolled', 'verified', 'commission_booked', 'paid') and l.deleted_at is null
       and a.destination_type = 'partner' and not a.is_test and a.status in ('pushed', 'accepted', 'closed')
       and not exists (select 1 from public.enrollments e where e.allocation_id = a.id) -- a cancelled one is the Admin's decision
       and not exists (select 1 from b2b.events ev where ev.type = 'money.scan_error' and ev.allocation_id = a.id and ev.occurred_at > now() - interval '1 day')
     limit p_limit
  loop
    begin
      perform b2b.enrollment_record(r.id, jsonb_build_object('enrolled_on', r.enrollment_date), 'partner_stage');
      v_new := v_new + 1;
    exception when others then
      v_err := v_err + 1;
      perform b2b.log_event('money.scan_error', null, r.id, null, jsonb_build_object('error', sqlerrm));
    end;
  end loop;
  for r in
    select e.id from public.enrollments e
     where e.source_product = 'b2b' and e.status = 'reported'
       and not exists (select 1 from b2b.earnings x where x.enrollment_id = e.id and x.kind = 'commission' and x.status = 'expected')
     order by e.updated_at limit p_limit -- a retry touches updated_at, so every one gets its turn
  loop
    if not (b2b.enrollment_expect(r.id) ? 'error') then v_retry := v_retry + 1; end if;
  end loop;
  return jsonb_build_object('recorded', v_new, 'errors', v_err, 'lines_added', v_retry);
end $fn$;

revoke execute on function b2b.money_scan(int) from public, anon, authenticated;
grant execute on function b2b.money_scan(int) to service_role;
revoke execute on function b2b.enrollment_verify(bigint, jsonb), b2b.enrollment_cancel(bigint, text), b2b.enrollment_refund(bigint, jsonb),
                           b2b.earning_manual(jsonb) from public, anon;
grant execute on function b2b.enrollment_verify(bigint, jsonb), b2b.enrollment_cancel(bigint, text), b2b.enrollment_refund(bigint, jsonb),
                          b2b.earning_manual(jsonb) to authenticated, service_role;
