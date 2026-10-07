-- M20d: period close and GST invoices (B12.3–4).
--   period_close        settles tiers for a finished month (verified enrollments ÷ leads accepted) and builds draft invoices
--   invoice_build       adds a partner's realised, uninvoiced lines (through a month) to its one open draft
--   invoice_totals      taxable, CGST+SGST (same state) or IGST, total
--   invoice_approve     numbers it (prefix/FY/sequence, no gaps), snapshots both parties; leads → commission_booked
--   invoice_mark_sent, invoice_cancel (releases its lines)
--   invoice_settle      received and TDS from receipts; status follows (receipts are in m20e)

create or replace function b2b.fy_of(d date)
returns text language sql immutable set search_path = '' as $fn$
  select case when extract(month from d) >= 4 then to_char(d, 'YYYY') || '-' || to_char((d + interval '1 year')::date, 'YY')
              else to_char((d - interval '1 year')::date, 'YYYY') || '-' || to_char(d, 'YY') end;
$fn$;

create or replace function b2b.invoice_totals(p_invoice_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.invoices;
  p b2b.partners;
  cfg jsonb := b2b.money_cfg();
  v_from text;
  v_to text;
  v_tax numeric;
  v_gst numeric;
  v_type text;
begin
  select * into i from b2b.invoices where id = p_invoice_id;
  select * into p from b2b.partners where id = i.partner_id;
  v_from := coalesce(nullif(cfg -> 'eduwit' ->> 'state_code', ''), left(nullif(cfg -> 'eduwit' ->> 'gstin', ''), 2));
  v_to := coalesce(p.billing_state_code, left(p.gstin, 2));
  v_type := case when v_from is not null and v_from = v_to then 'cgst_sgst' else 'igst' end;
  select coalesce(sum(taxable_inr), 0), coalesce(sum(gst_inr), 0) into v_tax, v_gst from b2b.invoice_lines where invoice_id = i.id and released_at is null;
  update b2b.invoices
     set taxable_inr = v_tax, tax_type = v_type,
         cgst_inr = case when v_type = 'cgst_sgst' then round(v_gst / 2, 2) else 0 end,
         sgst_inr = case when v_type = 'cgst_sgst' then v_gst - round(v_gst / 2, 2) else 0 end,
         igst_inr = case when v_type = 'igst' then v_gst else 0 end,
         total_inr = v_tax + v_gst, place_of_supply = v_to, updated_at = now()
   where id = i.id;
end $fn$;

/* Adds realised, uninvoiced lines through p_through to the partner's draft (created when needed). Returns the draft id or null. */
create or replace function b2b.invoice_build(p_partner bigint, p_through text)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  v_n int;
begin
  if not exists (select 1 from b2b.earnings where partner_id = p_partner and status = 'realised' and invoice_id is null and period <= p_through) then
    return (select id from b2b.invoices where partner_id = p_partner and status = 'draft');
  end if;
  select id into v_id from b2b.invoices where partner_id = p_partner and status = 'draft' for update;
  if v_id is null then
    insert into b2b.invoices (partner_id, through_period, gst_rate, created_by)
    values (p_partner, p_through, coalesce((b2b.money_cfg() ->> 'gst_rate')::numeric, 0.18), coalesce(auth.uid()::text, 'system'))
    returning id into v_id;
  else
    update b2b.invoices set through_period = greatest(through_period, p_through) where id = v_id;
  end if;
  with picked as (
    select x.*, l.student_name, al.reference, e.programme_name, e.university_name, e.enrolled_on
      from b2b.earnings x
      left join public.enrollments e on e.id = x.enrollment_id
      left join public.student_leads l on l.id = x.lead_id
      left join b2b.allocations al on al.id = x.allocation_id
     where x.partner_id = p_partner and x.status = 'realised' and x.invoice_id is null and x.period <= p_through
     order by x.period, x.id
     for update of x),
  ins as (
    insert into b2b.invoice_lines (invoice_id, earning_id, lead_id, reference, description, taxable_inr, gst_inr, total_inr)
    select v_id, k.id, k.lead_id, k.reference,
           left(case k.kind when 'commission' then 'Commission' when 'tier_adjustment' then 'Tier settlement ' || k.period
                            when 'reversal' then 'Refund reversal' else 'Adjustment' end
                || coalesce(': ' || nullif(trim(k.student_name), ''), '')
                || coalesce(' · ' || nullif(concat_ws(', ', k.programme_name, k.university_name), ''), '')
                || coalesce(' · enrolled ' || to_char(k.enrolled_on, 'DD Mon YYYY'), '')
                || coalesce(' · ' || k.reference, '')
                || case when k.kind = 'manual_adjustment' then coalesce(' · ' || k.note, '') else '' end, 300),
           k.net_inr, k.gst_inr, k.gross_inr
      from picked k
    returning earning_id)
  update b2b.earnings set invoice_id = v_id where id in (select earning_id from ins);
  get diagnostics v_n = row_count;
  perform b2b.invoice_totals(v_id);
  perform b2b.log_event('money.invoice_drafted', null, null, p_partner, jsonb_build_object('invoice_id', v_id, 'lines_added', v_n, 'through', p_through));
  return v_id;
end $fn$;

/* Settles tiers for a finished month and builds draft invoices. Re-running is safe: settled months are not settled again. */
create or replace function b2b.period_close(p_period text, p_partner bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pt record;
  x b2b.earnings;
  c jsonb;
  v_pct numeric;
  v_cpe numeric;
  v_net numeric;
  v_gst numeric;
  v_settled int := 0;
  v_adj int := 0;
  v_inv int := 0;
begin
  if p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'the month must look like 2026-09' using errcode = '22023'; end if;
  if p_period >= b2b.period_of((now() at time zone 'Asia/Kolkata')::date) then
    raise exception 'only a finished month can be closed' using errcode = '22023';
  end if;
  for pt in
    select p.id from b2b.partners p
     where (p_partner is null or p.id = p_partner)
       and not exists (select 1 from b2b.money_periods m where m.partner_id = p.id and m.period = p_period)
       and (exists (select 1 from b2b.earnings e where e.partner_id = p.id and e.period = p_period)
            or exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.accepted_at is not null and not a.is_test
                         and b2b.period_of((a.accepted_at at time zone 'Asia/Kolkata')::date) = p_period))
  loop
    c := b2b.partner_conversion(pt.id, p_period, true);
    insert into b2b.money_periods (partner_id, period, accepted_leads, enrollments, conversion_pct, closed_by)
    values (pt.id, p_period, (c ->> 'accepted')::int, (c ->> 'enrollments')::int, (c ->> 'conversion_pct')::numeric, coalesce(auth.uid()::text, 'system'));
    v_settled := v_settled + 1;
    for x in select * from b2b.earnings where partner_id = pt.id and period = p_period and kind = 'commission' and tier_provisional and status <> 'void' loop
      if x.status = 'expected' then
        perform b2b.enrollment_expect(x.enrollment_id);
      else
        v_pct := b2b.tier_pick(x.rate_snapshot -> 'tiers', (c ->> 'conversion_pct')::numeric);
        v_cpe := v_pct / 100 * x.fee_base_inr;
        if coalesce((x.rate_snapshot ->> 'gst_inclusive')::boolean, false) then
          v_net := round(v_cpe / (1 + x.gst_rate), 2); v_gst := round(v_cpe, 2) - v_net;
        else
          v_net := round(v_cpe, 2); v_gst := round(v_net * x.gst_rate, 2);
        end if;
        if v_net is not null and v_net <> x.net_inr then
          insert into b2b.earnings (enrollment_id, allocation_id, partner_id, lead_id, period, kind, status, rate_id, rate_snapshot, fee_base_inr, pct,
                                    net_inr, gst_rate, gst_inr, gross_inr, adjusts_id, note, realised_at, created_by)
          values (x.enrollment_id, x.allocation_id, x.partner_id, x.lead_id, p_period, 'tier_adjustment', 'realised', x.rate_id, x.rate_snapshot,
                  x.fee_base_inr, v_pct, v_net - x.net_inr, x.gst_rate, v_gst - x.gst_inr, (v_net + v_gst) - x.gross_inr, x.id,
                  format('tier settled at %s%% (conversion %s%%; provisional %s%%)', v_pct, coalesce((c ->> 'conversion_pct'), '—'), x.pct),
                  now(), coalesce(auth.uid()::text, 'system'));
          v_adj := v_adj + 1;
        end if;
        update b2b.earnings set tier_provisional = false where id = x.id;
      end if;
    end loop;
  end loop;
  for pt in select distinct e.partner_id id from b2b.earnings e
             where e.status = 'realised' and e.invoice_id is null and e.period <= p_period and (p_partner is null or e.partner_id = p_partner) loop
    if b2b.invoice_build(pt.id, p_period) is not null then v_inv := v_inv + 1; end if;
  end loop;
  perform b2b.log_event('money.period_closed', null, null, p_partner,
                        jsonb_build_object('period', p_period, 'partners_settled', v_settled, 'tier_adjustments', v_adj, 'drafts', v_inv));
  return jsonb_build_object('period', p_period, 'partners_settled', v_settled, 'tier_adjustments', v_adj, 'drafts', v_inv);
end $fn$;

create or replace function b2b.money_period_close(p_period text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.period_close(p_period, null);
end $fn$;

/* The Admin's approval: checks the parties' details, assigns the next number in the financial year, snapshots both parties. */
create or replace function b2b.invoice_approve(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.invoices;
  p b2b.partners;
  cfg jsonb := b2b.money_cfg();
  ed jsonb := coalesce(cfg -> 'eduwit', '{}');
  v_missing text[] := '{}';
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_fy text := b2b.fy_of((now() at time zone 'Asia/Kolkata')::date);
  v_seq int;
  v_number text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.invoices where id = p_id for update;
  if i.id is null then raise exception 'invoice not found' using errcode = 'P0002'; end if;
  if i.status <> 'draft' then raise exception 'only a draft can be approved' using errcode = '22023'; end if;
  perform b2b.invoice_totals(i.id);
  select * into i from b2b.invoices where id = p_id;
  if i.total_inr <= 0 then raise exception 'the total is not positive; it carries over to the next invoice' using errcode = '22023'; end if;
  select * into p from b2b.partners where id = i.partner_id;
  if nullif(ed ->> 'legal_name', '') is null then v_missing := v_missing || 'Eduwit legal name'::text; end if;
  if nullif(ed ->> 'gstin', '') is null then v_missing := v_missing || 'Eduwit GSTIN'::text; end if;
  if nullif(ed ->> 'address', '') is null then v_missing := v_missing || 'Eduwit address'::text; end if;
  if nullif(cfg ->> 'sac_code', '') is null then v_missing := v_missing || 'SAC code'::text; end if;
  if nullif(p.legal_name, '') is null then v_missing := v_missing || 'partner legal name'::text; end if;
  if nullif(p.billing_address, '') is null then v_missing := v_missing || 'partner billing address'::text; end if;
  if coalesce(p.billing_state_code, left(p.gstin, 2)) is null then v_missing := v_missing || 'partner state (GSTIN or state code)'::text; end if;
  if cardinality(v_missing) > 0 then
    raise exception 'missing before an invoice can be issued: %', array_to_string(v_missing, ', ') using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('b2b.invoice_number'));
  select coalesce(max(seq), 0) + 1 into v_seq from b2b.invoices where fy = v_fy;
  v_number := coalesce(nullif(cfg ->> 'invoice_prefix', ''), 'EDW') || '/' || v_fy || '/' || lpad(v_seq::text, 4, '0');
  update b2b.invoices
     set status = 'approved', fy = v_fy, seq = v_seq, number = v_number, issue_date = v_today, due_date = v_today + p.payment_terms_days,
         sac_code = cfg ->> 'sac_code',
         supplier = jsonb_build_object('legal_name', ed ->> 'legal_name', 'gstin', ed ->> 'gstin', 'address', ed ->> 'address',
                                       'state_code', coalesce(nullif(ed ->> 'state_code', ''), left(ed ->> 'gstin', 2)), 'bank', ed ->> 'bank'),
         recipient = jsonb_build_object('legal_name', p.legal_name, 'gstin', p.gstin, 'address', p.billing_address,
                                        'state_code', coalesce(p.billing_state_code, left(p.gstin, 2)), 'email', p.billing_email, 'name', p.name),
         approved_at = now(), updated_at = now()
   where id = i.id;
  perform b2b.lead_stage_up(x.lead_id, 'commission_booked')
     from (select distinct lead_id from b2b.invoice_lines where invoice_id = i.id and released_at is null and lead_id is not null) x;
  perform b2b.log_event('money.invoice_approved', null, null, i.partner_id, jsonb_build_object('invoice_id', i.id, 'number', v_number, 'total_inr', i.total_inr));
  return jsonb_build_object('id', i.id, 'number', v_number);
end $fn$;

create or replace function b2b.invoice_mark_sent(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.invoices set status = 'sent', sent_at = now(), updated_at = now() where id = p_id and status = 'approved';
  if not found then raise exception 'only an approved invoice can be marked as sent' using errcode = '22023'; end if;
  perform b2b.log_event('money.invoice_sent', null, null, (select partner_id from b2b.invoices where id = p_id), jsonb_build_object('invoice_id', p_id));
end $fn$;

create or replace function b2b.invoice_cancel(p_id bigint, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.invoices;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into i from b2b.invoices where id = p_id for update;
  if i.id is null then raise exception 'invoice not found' using errcode = 'P0002'; end if;
  if i.status not in ('draft', 'approved', 'sent') then raise exception 'a paid or part-paid invoice cannot be cancelled; void its receipts first' using errcode = '22023'; end if;
  update b2b.invoices set status = 'cancelled', cancelled_at = now(), cancel_reason = left(trim(p_reason), 300), updated_at = now() where id = i.id;
  update b2b.invoice_lines set released_at = now() where invoice_id = i.id and released_at is null;
  update b2b.earnings set invoice_id = null where invoice_id = i.id;
  perform b2b.log_event('money.invoice_cancelled', null, null, i.partner_id, jsonb_build_object('invoice_id', i.id, 'number', i.number, 'reason', p_reason));
end $fn$;

/* Received and TDS from the active allocations; status follows. Paid invoices move their leads to "paid". */
create or replace function b2b.invoice_settle(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.invoices;
  v_rec numeric;
  v_tds numeric;
  v_status text;
begin
  select * into i from b2b.invoices where id = p_id for update;
  select coalesce(sum(amount_inr), 0), coalesce(sum(tds_inr), 0) into v_rec, v_tds
    from b2b.receipt_allocations where invoice_id = i.id and reversed_at is null;
  v_status := case when v_rec + v_tds >= i.total_inr - 0.5 then 'paid' when v_rec + v_tds > 0 then 'partly_paid'
                   when i.sent_at is not null then 'sent' else 'approved' end;
  update b2b.invoices set received_inr = v_rec, tds_inr = v_tds, status = v_status,
         paid_at = case when v_status = 'paid' then coalesce(paid_at, now()) end, updated_at = now()
   where id = i.id;
  if v_status = 'paid' and i.status <> 'paid' then
    perform b2b.lead_stage_up(x.lead_id, 'paid')
       from (select distinct lead_id from b2b.invoice_lines where invoice_id = i.id and released_at is null and lead_id is not null) x;
    perform b2b.log_event('money.invoice_paid', null, null, i.partner_id, jsonb_build_object('invoice_id', i.id, 'number', i.number));
  end if;
end $fn$;

revoke execute on function b2b.fy_of(date), b2b.invoice_totals(bigint), b2b.invoice_build(bigint, text), b2b.period_close(text, bigint), b2b.invoice_settle(bigint)
  from public, anon, authenticated;
grant execute on function b2b.fy_of(date), b2b.invoice_totals(bigint), b2b.invoice_build(bigint, text), b2b.period_close(text, bigint), b2b.invoice_settle(bigint)
  to service_role;
revoke execute on function b2b.money_period_close(text), b2b.invoice_approve(bigint), b2b.invoice_mark_sent(bigint), b2b.invoice_cancel(bigint, text)
  from public, anon;
grant execute on function b2b.money_period_close(text), b2b.invoice_approve(bigint), b2b.invoice_mark_sent(bigint), b2b.invoice_cancel(bigint, text)
  to authenticated, service_role;
