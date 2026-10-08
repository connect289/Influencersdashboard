-- M20h: money settings, partner billing details and accounting exports (B12, B12.8).
--   money_settings_save    GST, SAC, TDS, refund window, Eduwit's invoice details, prefix, tiers, closing; versioned with a reason
--   partner_billing_save   the partner's legal name, GSTIN, address, state, billing email, payment terms
--   money_export           rows for Tally / Zoho Books (invoices, receipts, earning lines) in a date range

create or replace function b2b.money_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.money_cfg();
  ed jsonb := coalesce(p -> 'eduwit', '{}');
  v jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if nullif(ed ->> 'gstin', '') is not null and upper(ed ->> 'gstin') !~ '^[0-9]{2}[A-Z0-9]{13}$' then raise exception 'the GSTIN must be 15 characters' using errcode = '22023'; end if;
  if nullif(ed ->> 'state_code', '') is not null and ed ->> 'state_code' !~ '^[0-9]{2}$' then raise exception 'the state code is two digits (07 for Delhi)' using errcode = '22023'; end if;
  if nullif(p ->> 'sac_code', '') is not null and p ->> 'sac_code' !~ '^[0-9]{4,8}$' then raise exception 'the SAC code is 4 to 8 digits' using errcode = '22023'; end if;
  if not ((p ->> 'gst_rate')::numeric between 0 and 0.28) then raise exception 'GST is between 0 and 28%%' using errcode = '22023'; end if;
  if nullif(p ->> 'tds_rate', '') is not null and not ((p ->> 'tds_rate')::numeric between 0 and 0.2) then raise exception 'TDS is between 0 and 20%%' using errcode = '22023'; end if;
  if not ((p ->> 'refund_window_days')::int between 0 and 365) then raise exception 'the refund window is 0 to 365 days' using errcode = '22023'; end if;
  if coalesce(p ->> 'invoice_prefix', '') !~ '^[A-Z0-9-]{1,10}$' then raise exception 'the invoice prefix is 1 to 10 capital letters, digits or dashes' using errcode = '22023'; end if;
  if not ((p ->> 'tier_min_leads')::int between 1 and 1000) then raise exception 'tier minimum leads is 1 to 1,000' using errcode = '22023'; end if;
  if not ((p ->> 'close_day')::int between 1 and 28) then raise exception 'the closing day is 1 to 28' using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'give a reason for the change' using errcode = '22023'; end if;
  v := cfg || jsonb_build_object(
    'gst_rate', (p ->> 'gst_rate')::numeric, 'sac_code', nullif(p ->> 'sac_code', ''), 'tds_rate', nullif(p ->> 'tds_rate', '')::numeric,
    'refund_window_days', (p ->> 'refund_window_days')::int, 'invoice_prefix', p ->> 'invoice_prefix', 'tier_min_leads', (p ->> 'tier_min_leads')::int,
    'close_day', (p ->> 'close_day')::int, 'auto_close', coalesce((p ->> 'auto_close')::boolean, true),
    'confirmed_by_ca', coalesce((p ->> 'confirmed_by_ca')::boolean, false),
    'eduwit', jsonb_build_object('legal_name', nullif(left(trim(ed ->> 'legal_name'), 200), ''), 'gstin', nullif(upper(trim(ed ->> 'gstin')), ''),
                                 'address', nullif(left(trim(ed ->> 'address'), 500), ''), 'state_code', nullif(trim(ed ->> 'state_code'), ''),
                                 'bank', nullif(left(trim(ed ->> 'bank'), 300), '')));
  perform b2b.set_setting('money', v, left(trim(p_reason), 300));
  return v;
end $fn$;

create or replace function b2b.partner_billing_save(p_partner_id bigint, p jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_gstin text := nullif(upper(trim(p ->> 'gstin')), '');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_gstin is not null and v_gstin !~ '^[0-9]{2}[A-Z0-9]{13}$' then raise exception 'the GSTIN must be 15 characters' using errcode = '22023'; end if;
  if nullif(p ->> 'billing_state_code', '') is not null and p ->> 'billing_state_code' !~ '^[0-9]{2}$' then raise exception 'the state code is two digits' using errcode = '22023'; end if;
  if nullif(p ->> 'billing_email', '') is not null and p ->> 'billing_email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'the billing email looks wrong' using errcode = '22023'; end if;
  if not (coalesce(nullif(p ->> 'payment_terms_days', '')::int, 30) between 0 and 180) then raise exception 'payment terms are 0 to 180 days' using errcode = '22023'; end if;
  update b2b.partners
     set legal_name = nullif(left(trim(p ->> 'legal_name'), 200), ''), gstin = v_gstin, billing_address = nullif(left(trim(p ->> 'billing_address'), 500), ''),
         billing_state_code = nullif(trim(p ->> 'billing_state_code'), ''), billing_email = nullif(lower(trim(p ->> 'billing_email')), ''),
         payment_terms_days = coalesce(nullif(p ->> 'payment_terms_days', '')::int, 30), updated_at = now(), updated_by = coalesce(auth.uid()::text, 'system')
   where id = p_partner_id;
  if not found then raise exception 'partner not found' using errcode = 'P0002'; end if;
  perform b2b.log_event('partner.billing_changed', null, null, p_partner_id, jsonb_build_object('gstin', v_gstin, 'legal_name', p ->> 'legal_name'));
end $fn$;

/* kind: invoices | receipts | earnings, between p_from and p_to (issue, receipt and realisation dates). */
create or replace function b2b.money_export(p_kind text, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'choose up to a year' using errcode = '22023'; end if;
  if p_kind = 'invoices' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'Invoice No', i.number, 'Invoice Date', i.issue_date, 'Due Date', i.due_date, 'Party', i.recipient ->> 'legal_name', 'Party GSTIN', i.recipient ->> 'gstin',
        'Place of Supply', i.place_of_supply, 'SAC', i.sac_code, 'Taxable Value', i.taxable_inr, 'CGST', i.cgst_inr, 'SGST', i.sgst_inr, 'IGST', i.igst_inr,
        'Invoice Total', i.total_inr, 'Received', i.received_inr, 'TDS', i.tds_inr, 'Status', i.status) order by i.issue_date, i.seq), '[]')
      from b2b.invoices i where i.number is not null and i.issue_date between p_from and p_to);
  elsif p_kind = 'receipts' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'Date', r.received_on, 'Party', coalesce(p.legal_name, p.name), 'Amount', r.amount_inr, 'TDS', r.tds_inr, 'Bank Reference', r.bank_ref,
        'Against Invoices', (select string_agg(i.number, ' ') from b2b.receipt_allocations ra join b2b.invoices i on i.id = ra.invoice_id
                              where ra.receipt_id = r.id and ra.reversed_at is null),
        'Status', r.status, 'Note', r.note) order by r.received_on, r.id), '[]')
      from b2b.receipts r join b2b.partners p on p.id = r.partner_id where r.received_on between p_from and p_to);
  elsif p_kind = 'earnings' then
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'Line', x.id, 'Partner', coalesce(p.display_name, p.name), 'Reference', a.reference, 'Student', l.student_name, 'Kind', x.kind, 'Status', x.status,
        'Period', x.period, 'Fee Base', x.fee_base_inr, 'Percent', x.pct, 'Net', x.net_inr, 'GST', x.gst_inr, 'Gross', x.gross_inr,
        'Invoice', (select number from b2b.invoices i where i.id = x.invoice_id), 'Realised On', (x.realised_at at time zone 'Asia/Kolkata')::date, 'Note', x.note)
        order by x.realised_at, x.id), '[]')
      from b2b.earnings x join b2b.partners p on p.id = x.partner_id
      left join b2b.allocations a on a.id = x.allocation_id left join public.student_leads l on l.id = x.lead_id
     where x.status = 'realised' and (x.realised_at at time zone 'Asia/Kolkata')::date between p_from and p_to);
  end if;
  raise exception 'unknown export' using errcode = '22023';
end $fn$;

revoke execute on function b2b.money_settings_save(jsonb, text), b2b.partner_billing_save(bigint, jsonb), b2b.money_export(text, date, date) from public, anon;
grant execute on function b2b.money_settings_save(jsonb, text), b2b.partner_billing_save(bigint, jsonb), b2b.money_export(text, date, date)
  to authenticated, service_role;
