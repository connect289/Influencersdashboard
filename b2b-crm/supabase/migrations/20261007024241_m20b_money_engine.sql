-- M20b: money engine, part 1 (B12.1–3, B5.3; part 2 in m20c). Enrollment → expected earning; verification → realised;
-- tiers provisional until period close; refunds inside the window reverse with new negative lines.
--   money_cfg, period_of        settings and the YYYY-MM period of a date
--   partner_conversion          verified (or reported) enrollments ÷ leads accepted in a month, per partner
--   tier_pick, tier_pct         the tier for a conversion; settled for a closed month, projected otherwise
--   earning_amounts             commission for an enrollment: rate in force on the enrolment date, fee base, GST
--   lead_stage_up               moves a lead forward only (verified, commission_booked, paid)
--   enrollment_record           a partner enrollment (from the partner's stage, a statement or the Admin) + expected line
--   enrollment_verify           proof → verified; the line is recomputed and realised
--   enrollment_cancel, _refund  cancel a reported one; refund a verified one (reversal lines, window enforced)
--   earning_manual              a signed manual adjustment with a note
--   money_scan                  partner leads that reached "enrolled" without an enrollment row get one

create or replace function b2b.money_cfg()
returns jsonb language sql stable set search_path = '' as $fn$
  select coalesce((select value from b2b.settings where key = 'money'), '{}');
$fn$;

create or replace function b2b.period_of(d date)
returns text language sql immutable set search_path = '' as $fn$
  select to_char(d, 'YYYY-MM');
$fn$;

create or replace function b2b.partner_conversion(p_partner bigint, p_period text, p_verified_only boolean default false)
returns jsonb language sql stable set search_path = '' as $fn$
  with acc as (
    select count(*) n from b2b.allocations a
     where a.partner_id = p_partner and a.destination_type = 'partner' and not a.is_test and a.accepted_at is not null
       and b2b.period_of((a.accepted_at at time zone 'Asia/Kolkata')::date) = p_period),
  enr as (
    select count(*) n from public.enrollments e
     where e.partner_id = p_partner and e.source_product = 'b2b' and b2b.period_of(e.enrolled_on) = p_period
       and (e.status = 'verified' or (not p_verified_only and e.status = 'reported')))
  select jsonb_build_object('accepted', acc.n, 'enrollments', enr.n,
                            'conversion_pct', case when acc.n > 0 then round(enr.n * 100.0 / acc.n, 3) end)
    from acc, enr;
$fn$;

/* tiers: [{"from_pct": 0, "pct": 22.42}, {"from_pct": 7, "pct": 20.42}, ...]; the highest from_pct not above the conversion wins.
   Without a conversion, the lowest tier (from_pct smallest) applies. */
create or replace function b2b.tier_pick(p_tiers jsonb, p_conv numeric)
returns numeric language sql immutable set search_path = '' as $fn$
  select (t ->> 'pct')::numeric from jsonb_array_elements(coalesce(p_tiers, '[]')) t
   where p_conv is null or coalesce((t ->> 'from_pct')::numeric, 0) <= p_conv
   order by case when p_conv is null then -coalesce((t ->> 'from_pct')::numeric, 0) else coalesce((t ->> 'from_pct')::numeric, 0) end desc
   limit 1;
$fn$;

create or replace function b2b.tier_pct(p_tiers jsonb, p_partner bigint, p_period text)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  mp b2b.money_periods;
  c jsonb;
  v_conv numeric;
  v_basis text;
begin
  select * into mp from b2b.money_periods where partner_id = p_partner and period = p_period;
  if mp.partner_id is not null then
    return jsonb_build_object('pct', b2b.tier_pick(p_tiers, mp.conversion_pct), 'provisional', false, 'conversion_pct', mp.conversion_pct, 'basis', 'settled');
  end if;
  c := b2b.partner_conversion(p_partner, p_period);
  if (c ->> 'accepted')::int >= coalesce((b2b.money_cfg() ->> 'tier_min_leads')::int, 20) then
    v_conv := (c ->> 'conversion_pct')::numeric; v_basis := 'projected';
  else
    select m.conversion_pct into v_conv from b2b.money_periods m where m.partner_id = p_partner and m.period < p_period order by m.period desc limit 1;
    v_basis := case when v_conv is not null then 'last_settled' else 'first_tier' end;
  end if;
  return jsonb_build_object('pct', b2b.tier_pick(p_tiers, v_conv), 'provisional', true, 'conversion_pct', v_conv, 'basis', v_basis,
                            'accepted', c -> 'accepted', 'enrollments', c -> 'enrollments');
end $fn$;

/* The commission for one enrollment. {error: no_rate | no_fee} when it cannot be computed yet. */
create or replace function b2b.earning_amounts(p_partner bigint, p_programme bigint, p_on date, p_fee numeric)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  r b2b.rates;
  c public.catalog_programs;
  f jsonb;
  t jsonb;
  v_base numeric;
  v_pct numeric;
  v_cpe numeric;
  v_g numeric := coalesce((b2b.money_cfg() ->> 'gst_rate')::numeric, 0.18);
  v_net numeric;
  v_gst numeric;
  v_note text;
begin
  r := b2b.rate_for(p_partner, p_programme, p_on);
  if r.id is null then return jsonb_build_object('error', 'no_rate'); end if;
  select * into c from public.catalog_programs where id = p_programme;
  select pp.fees into f from b2b.partner_programmes pp
   where pp.partner_id = p_partner and pp.programme_id = p_programme order by (pp.valid_to is null) desc, pp.valid_from desc limit 1;
  if r.rate_type <> 'fixed' then
    if r.fee_base = 'total' then
      v_base := coalesce(p_fee, (f ->> 'total')::numeric, c.fee_total);
    else
      v_base := coalesce((f ->> 'yearly')::numeric, c.fee_yearly);
      if v_base is null then
        v_base := coalesce(p_fee, (f ->> 'total')::numeric, c.fee_total);
        if v_base is not null then v_note := 'first-year fee unknown: the total fee was used'; end if;
      end if;
    end if;
    if v_base is null then return jsonb_build_object('error', 'no_fee', 'rate_id', r.id); end if;
  end if;
  if r.rate_type = 'tiered' then
    t := b2b.tier_pct(r.tiers, p_partner, b2b.period_of(p_on));
    v_pct := (t ->> 'pct')::numeric;
    if v_pct is null then return jsonb_build_object('error', 'no_rate', 'rate_id', r.id); end if;
  elsif r.rate_type = 'percent' then v_pct := r.value;
  end if;
  v_cpe := case when r.rate_type = 'fixed' then r.value else v_pct / 100 * v_base end;
  if r.gst_inclusive then
    v_net := round(v_cpe / (1 + v_g), 2); v_gst := round(v_cpe, 2) - v_net;
  else
    v_net := round(v_cpe, 2); v_gst := round(v_net * v_g, 2);
  end if;
  return jsonb_build_object('rate_id', r.id, 'rate', to_jsonb(r) - 'created_by', 'fee_base_inr', round(v_base, 2), 'pct', v_pct,
                            'provisional', coalesce((t ->> 'provisional')::boolean, false), 'tier', t, 'gst_rate', v_g,
                            'net', v_net, 'gst', v_gst, 'gross', v_net + v_gst, 'note', v_note);
end $fn$;

create or replace function b2b.lead_stage_up(p_lead bigint, p_stage text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_stages jsonb := (select value from b2b.settings where key = 'stages');
  v_old text;
  v_new_rank int;
  v_old_rank int;
begin
  select stage into v_old from public.student_leads where id = p_lead for update;
  select (e ->> 'rank')::int into v_new_rank from jsonb_array_elements(v_stages) e where e ->> 'key' = p_stage;
  select (e ->> 'rank')::int into v_old_rank from jsonb_array_elements(v_stages) e where e ->> 'key' = v_old;
  if v_new_rank is null or coalesce(v_old_rank, 0) >= v_new_rank then return false; end if;
  update public.student_leads set stage = p_stage, sub_stage = null, stage_changed_at = now(), updated_by = 'b2b' where id = p_lead;
  perform b2b.log_event('lead.stage_changed', p_lead, null, null, jsonb_build_object('from', v_old, 'to', p_stage, 'source', 'money'));
  return true;
end $fn$;

/* Writes the expected commission line of a reported enrollment (insert, refresh, or void when no longer computable). */
create or replace function b2b.enrollment_expect(p_enrollment_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e public.enrollments;
  m jsonb;
  v_line bigint;
begin
  select * into e from public.enrollments where id = p_enrollment_id;
  if e.status <> 'reported' then return null; end if;
  m := b2b.earning_amounts(e.partner_id, e.programme_id, e.enrolled_on, e.fee_amount_inr);
  select id into v_line from b2b.earnings where enrollment_id = e.id and kind = 'commission' and status = 'expected';
  if m ? 'error' then
    update b2b.earnings set status = 'void', note = 'no longer computable: ' || (m ->> 'error') where id = v_line;
    update public.enrollments set expected_net_revenue_inr = null, updated_at = now() where id = e.id;
    return m;
  end if;
  if v_line is null then
    insert into b2b.earnings (enrollment_id, allocation_id, partner_id, lead_id, period, kind, status, rate_id, rate_snapshot, fee_base_inr, pct,
                              tier_provisional, net_inr, gst_rate, gst_inr, gross_inr, note, created_by)
    values (e.id, e.allocation_id, e.partner_id, e.lead_id, b2b.period_of(e.enrolled_on), 'commission', 'expected', (m ->> 'rate_id')::bigint,
            m -> 'rate', (m ->> 'fee_base_inr')::numeric, (m ->> 'pct')::numeric, (m ->> 'provisional')::boolean, (m ->> 'net')::numeric,
            (m ->> 'gst_rate')::numeric, (m ->> 'gst')::numeric, (m ->> 'gross')::numeric, m ->> 'note', coalesce(auth.uid()::text, 'system'));
  else
    update b2b.earnings set period = b2b.period_of(e.enrolled_on), rate_id = (m ->> 'rate_id')::bigint, rate_snapshot = m -> 'rate',
           fee_base_inr = (m ->> 'fee_base_inr')::numeric, pct = (m ->> 'pct')::numeric, tier_provisional = (m ->> 'provisional')::boolean,
           net_inr = (m ->> 'net')::numeric, gst_rate = (m ->> 'gst_rate')::numeric, gst_inr = (m ->> 'gst')::numeric, gross_inr = (m ->> 'gross')::numeric,
           note = m ->> 'note'
     where id = v_line;
  end if;
  update public.enrollments set expected_net_revenue_inr = (m ->> 'net')::numeric, updated_at = now() where id = e.id;
  return m;
end $fn$;

/* A partner enrollment. p: enrolled_on, fee_amount_inr, fee_paid_inr, programme_id, proof_ref. Idempotent per allocation. */
create or replace function b2b.enrollment_record(p_allocation_id bigint, p jsonb, p_source text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  c public.catalog_programs;
  v_uni text;
  v_id bigint;
  v_on date;
  v_prog bigint;
  m jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.partner_id is null then raise exception 'only partner allocations earn partner commission' using errcode = '22023'; end if;
  if a.is_test then raise exception 'test leads never earn commission' using errcode = '22023'; end if;
  if a.status not in ('pushed', 'accepted', 'closed') then raise exception 'the partner never held this lead (allocation is %)', a.status using errcode = '22023'; end if;
  select id into v_id from public.enrollments where allocation_id = a.id and status <> 'cancelled';
  if v_id is not null then return jsonb_build_object('id', v_id, 'existing', true); end if;

  select * into l from public.student_leads where id = a.lead_id;
  v_on := coalesce(nullif(p ->> 'enrolled_on', '')::date, l.enrollment_date, (l.stage_changed_at at time zone 'Asia/Kolkata')::date, current_date);
  if v_on > current_date then raise exception 'the enrolment date is in the future' using errcode = '22023'; end if;
  if v_on < (a.created_at at time zone 'Asia/Kolkata')::date then raise exception 'the enrolment date is before the lead was sent to the partner' using errcode = '22023'; end if;
  v_prog := coalesce(nullif(p ->> 'programme_id', '')::bigint, a.programme_id);
  select * into c from public.catalog_programs where id = v_prog;
  select name into v_uni from public.catalog_universities where id = c.university_id;

  insert into public.enrollments (lead_id, cycle_no, university_id, university_name, programme_id, programme_name, fee_amount_inr, fee_paid_inr,
                                  enrolled_on, destination_type, partner_id, status, proof_ref, reported_by, allocation_id, source_product)
  values (a.lead_id, a.cycle_no, c.university_id, v_uni, c.id, coalesce(c.program_name, nullif(trim(concat_ws(' ', c.course, c.specialization)), '')),
          coalesce(nullif(p ->> 'fee_amount_inr', '')::numeric, l.fee_amount_inr), coalesce(nullif(p ->> 'fee_paid_inr', '')::numeric, l.fee_paid_inr),
          v_on, 'partner', a.partner_id, 'reported', nullif(left(trim(p ->> 'proof_ref'), 300), ''), auth.uid(), a.id, 'b2b')
  returning id into v_id;
  m := b2b.enrollment_expect(v_id);

  if l.allocation_id is not distinct from a.id then
    update public.student_leads
       set expected_net_revenue_inr = case when m ? 'error' then expected_net_revenue_inr else (m ->> 'net')::numeric end,
           enrollment_date = coalesce(enrollment_date, v_on), enrolled_program = coalesce(enrolled_program, c.program_name),
           enrolled_university = coalesce(enrolled_university, v_uni), enrollment_status = 'reported', updated_by = 'b2b'
     where id = l.id;
    perform b2b.lead_stage_up(l.id, 'enrolled');
  end if;
  perform b2b.log_event('money.enrollment_reported', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('enrollment_id', v_id, 'source', p_source, 'enrolled_on', v_on, 'expected_net_inr', m -> 'net', 'problem', m -> 'error'));
  return jsonb_build_object('id', v_id, 'existing', false, 'amounts', m);
end $fn$;

revoke execute on function b2b.money_cfg(), b2b.period_of(date), b2b.partner_conversion(bigint, text, boolean), b2b.tier_pick(jsonb, numeric),
                           b2b.tier_pct(jsonb, bigint, text), b2b.earning_amounts(bigint, bigint, date, numeric), b2b.lead_stage_up(bigint, text),
                           b2b.enrollment_expect(bigint), b2b.enrollment_record(bigint, jsonb, text)
  from public, anon, authenticated;
grant execute on function b2b.money_cfg(), b2b.period_of(date), b2b.partner_conversion(bigint, text, boolean), b2b.tier_pick(jsonb, numeric),
                          b2b.tier_pct(jsonb, bigint, text), b2b.earning_amounts(bigint, bigint, date, numeric), b2b.lead_stage_up(bigint, text),
                          b2b.enrollment_expect(bigint), b2b.enrollment_record(bigint, jsonb, text)
  to service_role;
