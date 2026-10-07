-- M20g: money screen reads (B12). Settings and exports are in m20h.
--   money_overview         totals, ageing, tier watch per partner, months closed, what invoicing still needs
--   money_enrollments      enrollments with their lines (filters: status, partner, text)
--   money_invoices, invoice_detail, money_receipts, money_statements

create or replace function b2b.money_setup_missing()
returns text[] language sql stable set search_path = '' as $fn$
  select array_remove(array[
    case when nullif(c -> 'eduwit' ->> 'legal_name', '') is null then 'Eduwit legal name' end,
    case when nullif(c -> 'eduwit' ->> 'gstin', '') is null then 'Eduwit GSTIN' end,
    case when nullif(c -> 'eduwit' ->> 'address', '') is null then 'Eduwit address' end,
    case when nullif(c ->> 'sac_code', '') is null then 'SAC code' end,
    case when not coalesce((c ->> 'confirmed_by_ca')::boolean, false) then 'confirmation by Eduwit''s CA' end], null)
  from (select b2b.money_cfg() c) x;
$fn$;

create or replace function b2b.money_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month text := b2b.period_of((now() at time zone 'Asia/Kolkata')::date);
  v_fy_start date := make_date(extract(year from v_today)::int - case when extract(month from v_today) < 4 then 1 else 0 end, 4, 1);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'month', v_month,
    'totals', (select jsonb_build_object(
        'expected_net', coalesce(sum(net_inr) filter (where status = 'expected'), 0),
        'realised_uninvoiced_net', coalesce(sum(net_inr) filter (where status = 'realised' and invoice_id is null), 0),
        'realised_fy_net', coalesce(sum(net_inr) filter (where status = 'realised' and realised_at >= v_fy_start), 0))
        from b2b.earnings),
    'invoices', (select jsonb_build_object(
        'drafts', count(*) filter (where status = 'draft'),
        'draft_total', coalesce(sum(total_inr) filter (where status = 'draft'), 0),
        'outstanding', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid')), 0),
        'overdue', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid') and due_date < v_today), 0),
        'ageing', jsonb_build_object(
          '0_30', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid') and v_today - issue_date <= 30), 0),
          '31_60', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid') and v_today - issue_date between 31 and 60), 0),
          '61_90', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid') and v_today - issue_date between 61 and 90), 0),
          '90_plus', coalesce(sum(total_inr - received_inr - tds_inr) filter (where status in ('approved', 'sent', 'partly_paid') and v_today - issue_date > 90), 0)))
        from b2b.invoices),
    'received_fy', (select jsonb_build_object('amount', coalesce(sum(amount_inr), 0), 'tds', coalesce(sum(tds_inr), 0))
                      from b2b.receipts where status = 'active' and received_on >= v_fy_start),
    'enrollments', (select jsonb_build_object(
        'to_verify', count(*) filter (where status = 'reported'),
        'oldest_to_verify', min(enrolled_on) filter (where status = 'reported'),
        'verified_month', count(*) filter (where status = 'verified' and b2b.period_of(enrolled_on) = v_month),
        'reported_month', count(*) filter (where status in ('reported', 'verified') and b2b.period_of(enrolled_on) = v_month),
        'no_line', count(*) filter (where status = 'reported' and not exists (select 1 from b2b.earnings x where x.enrollment_id = e.id and x.status = 'expected')))
        from public.enrollments e where source_product = 'b2b'),
    'partners', (select coalesce(jsonb_agg(pr order by pr ->> 'name'), '[]') from (
        select jsonb_build_object(
          'id', p.id, 'name', coalesce(p.display_name, p.name), 'billing_ready', p.legal_name is not null and p.billing_address is not null
                                                                         and coalesce(p.billing_state_code, left(p.gstin, 2)) is not null,
          'expected_net', (select coalesce(sum(net_inr), 0) from b2b.earnings where partner_id = p.id and status = 'expected'),
          'realised_uninvoiced_net', (select coalesce(sum(net_inr), 0) from b2b.earnings where partner_id = p.id and status = 'realised' and invoice_id is null),
          'outstanding', (select coalesce(sum(total_inr - received_inr - tds_inr), 0) from b2b.invoices where partner_id = p.id and status in ('approved', 'sent', 'partly_paid')),
          'to_verify', (select count(*) from public.enrollments where partner_id = p.id and source_product = 'b2b' and status = 'reported'),
          'conversion', b2b.partner_conversion(p.id, v_month),
          'tier', (select jsonb_build_object('rate_id', r.id, 'tiers', r.tiers, 'now', b2b.tier_pct(r.tiers, p.id, v_month))
                     from b2b.rates r where r.partner_id = p.id and r.rate_type = 'tiered' and r.valid_from <= v_today and (r.valid_to is null or r.valid_to >= v_today)
                    order by (r.scope = 'partner') desc, r.id desc limit 1)) pr
          from b2b.partners p
         where p.status <> 'closed' or exists (select 1 from b2b.earnings x where x.partner_id = p.id)) t),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('period', m.period,
                 'closed', exists (select 1 from b2b.events e where e.type = 'money.period_closed' and e.payload ->> 'period' = m.period and e.partner_id is null),
                 'partners_settled', (select count(*) from b2b.money_periods mp where mp.period = m.period)) order by m.period desc), '[]')
                 from (select b2b.period_of((date_trunc('month', v_today) - make_interval(months => g))::date) period from generate_series(1, 6) g) m),
    'setup_missing', to_jsonb(b2b.money_setup_missing()),
    'settings', b2b.money_cfg());
end $fn$;

/* p: status (reported | verified | refunded | cancelled | all), partner_id, q (name, reference, phone digits), limit, offset. */
create or replace function b2b.money_enrollments(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_status text := coalesce(nullif(p ->> 'status', ''), 'reported');
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_q text := nullif(trim(p ->> 'q'), '');
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 50), 1), 200);
  v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('rows', (select coalesce(jsonb_agg(r order by (r ->> 'enrolled_on') desc, (r ->> 'id')::bigint desc), '[]') from (
      select jsonb_build_object(
        'id', e.id, 'lead_id', e.lead_id, 'allocation_id', e.allocation_id, 'reference', a.reference, 'record_id', a.partner_record_id,
        'name', l.student_name, 'partner_id', e.partner_id, 'partner_name', coalesce(pt.display_name, pt.name),
        'programme', e.programme_name, 'university', e.university_name, 'programme_id', e.programme_id, 'enrolled_on', e.enrolled_on,
        'fee_amount_inr', e.fee_amount_inr, 'fee_paid_inr', e.fee_paid_inr, 'status', e.status, 'proof_ref', e.proof_ref, 'proof_url', e.proof_url,
        'verified_at', e.verified_at, 'refund_window_ends_on', e.refund_window_ends_on, 'refunded_at', e.refunded_at, 'refund_reason', e.refund_reason,
        'expected_net_inr', e.expected_net_revenue_inr, 'realised_net_inr', e.realised_net_revenue_inr, 'created_at', e.created_at,
        'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'status', x.status, 'period', x.period, 'pct', x.pct,
                    'fee_base_inr', x.fee_base_inr, 'net_inr', x.net_inr, 'gst_inr', x.gst_inr, 'gross_inr', x.gross_inr, 'provisional', x.tier_provisional,
                    'invoice_id', x.invoice_id, 'invoice_number', (select number from b2b.invoices i where i.id = x.invoice_id), 'note', x.note,
                    'rate_type', x.rate_snapshot ->> 'rate_type', 'gst_inclusive', (x.rate_snapshot ->> 'gst_inclusive')::boolean) order by x.id), '[]')
                    from b2b.earnings x where x.enrollment_id = e.id)) r
        from public.enrollments e
        join b2b.partners pt on pt.id = e.partner_id
        left join b2b.allocations a on a.id = e.allocation_id
        left join public.student_leads l on l.id = e.lead_id
       where e.source_product = 'b2b' and (v_status = 'all' or e.status = v_status) and (v_partner is null or e.partner_id = v_partner)
         and (v_q is null or l.student_name ilike '%' || v_q || '%' or a.reference ilike '%' || v_q || '%'
              or (length(regexp_replace(v_q, '\D', '', 'g')) >= 6 and l.whatsapp_number like '%' || regexp_replace(v_q, '\D', '', 'g') || '%'))
       order by e.enrolled_on desc, e.id desc limit v_limit offset v_offset) t),
    'total', (select count(*) from public.enrollments e left join b2b.allocations a on a.id = e.allocation_id left join public.student_leads l on l.id = e.lead_id
               where e.source_product = 'b2b' and (v_status = 'all' or e.status = v_status) and (v_partner is null or e.partner_id = v_partner)
                 and (v_q is null or l.student_name ilike '%' || v_q || '%' or a.reference ilike '%' || v_q || '%'
                      or (length(regexp_replace(v_q, '\D', '', 'g')) >= 6 and l.whatsapp_number like '%' || regexp_replace(v_q, '\D', '', 'g') || '%'))));
end $fn$;

create or replace function b2b.money_invoices(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_status text := nullif(p ->> 'status', '');
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', i.id, 'number', i.number, 'status', i.status, 'partner_id', i.partner_id, 'partner_name', coalesce(p2.display_name, p2.name),
      'through_period', i.through_period, 'issue_date', i.issue_date, 'due_date', i.due_date, 'taxable_inr', i.taxable_inr,
      'gst_inr', i.cgst_inr + i.sgst_inr + i.igst_inr, 'total_inr', i.total_inr, 'received_inr', i.received_inr, 'tds_inr', i.tds_inr,
      'outstanding_inr', case when i.status in ('approved', 'sent', 'partly_paid') then i.total_inr - i.received_inr - i.tds_inr else 0 end,
      'lines', (select count(*) from b2b.invoice_lines il where il.invoice_id = i.id and il.released_at is null),
      'days_overdue', case when i.status in ('approved', 'sent', 'partly_paid') and i.due_date < current_date then current_date - i.due_date end,
      'created_at', i.created_at) order by (i.status = 'draft') desc, i.issue_date desc nulls last, i.id desc), '[]')
    from b2b.invoices i join b2b.partners p2 on p2.id = i.partner_id
   where (v_status is null or i.status = v_status or (v_status = 'open' and i.status in ('approved', 'sent', 'partly_paid')))
     and (v_partner is null or i.partner_id = v_partner));
end $fn$;

create or replace function b2b.invoice_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  i b2b.invoices;
  pt b2b.partners;
  cfg jsonb := b2b.money_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.invoices where id = p_id;
  if i.id is null then raise exception 'invoice not found' using errcode = 'P0002'; end if;
  select * into pt from b2b.partners where id = i.partner_id;
  return to_jsonb(i) || jsonb_build_object(
    'partner_name', coalesce(pt.display_name, pt.name),
    -- a draft shows today's details; an approved invoice its snapshots
    'supplier', coalesce(i.supplier, jsonb_build_object('legal_name', cfg -> 'eduwit' ->> 'legal_name', 'gstin', cfg -> 'eduwit' ->> 'gstin',
                          'address', cfg -> 'eduwit' ->> 'address', 'state_code', coalesce(cfg -> 'eduwit' ->> 'state_code', left(cfg -> 'eduwit' ->> 'gstin', 2)),
                          'bank', cfg -> 'eduwit' ->> 'bank')),
    'recipient', coalesce(i.recipient, jsonb_build_object('legal_name', pt.legal_name, 'gstin', pt.gstin, 'address', pt.billing_address,
                          'state_code', coalesce(pt.billing_state_code, left(pt.gstin, 2)), 'email', pt.billing_email, 'name', pt.name)),
    'sac_code', coalesce(i.sac_code, cfg ->> 'sac_code'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', il.id, 'earning_id', il.earning_id, 'lead_id', il.lead_id, 'reference', il.reference,
                'description', il.description, 'taxable_inr', il.taxable_inr, 'gst_inr', il.gst_inr, 'total_inr', il.total_inr, 'released', il.released_at is not null)
                order by il.id), '[]') from b2b.invoice_lines il where il.invoice_id = i.id),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('receipt_id', r.id, 'received_on', r.received_on, 'bank_ref', r.bank_ref,
                'amount_inr', ra.amount_inr, 'tds_inr', ra.tds_inr, 'method', ra.method, 'reversed', ra.reversed_at is not null) order by r.received_on), '[]')
                from b2b.receipt_allocations ra join b2b.receipts r on r.id = ra.receipt_id where ra.invoice_id = i.id),
    'setup_missing', to_jsonb(b2b.money_setup_missing()));
end $fn$;

create or replace function b2b.money_receipts(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'receipts', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'partner_id', r.partner_id, 'partner_name', coalesce(p2.display_name, p2.name), 'received_on', r.received_on,
        'amount_inr', r.amount_inr, 'tds_inr', r.tds_inr, 'bank_ref', r.bank_ref, 'note', r.note, 'status', r.status, 'void_reason', r.void_reason,
        'unapplied_inr', case when r.status = 'active' then r.amount_inr + r.tds_inr - coalesce((select sum(ra.amount_inr + ra.tds_inr) from b2b.receipt_allocations ra
                          where ra.receipt_id = r.id and ra.reversed_at is null), 0) else 0 end,
        'applied', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', ra.invoice_id, 'number', i.number, 'amount_inr', ra.amount_inr,
                      'tds_inr', ra.tds_inr, 'method', ra.method)), '[]')
                      from b2b.receipt_allocations ra join b2b.invoices i on i.id = ra.invoice_id where ra.receipt_id = r.id and ra.reversed_at is null))
        order by r.received_on desc, r.id desc), '[]')
        from b2b.receipts r join b2b.partners p2 on p2.id = r.partner_id where v_partner is null or r.partner_id = v_partner),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'number', i.number, 'partner_id', i.partner_id,
        'outstanding_inr', i.total_inr - i.received_inr - i.tds_inr, 'issue_date', i.issue_date) order by i.issue_date), '[]')
        from b2b.invoices i where i.status in ('approved', 'sent', 'partly_paid') and (v_partner is null or i.partner_id = v_partner)));
end $fn$;

create or replace function b2b.money_statements()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'partner_id', s.partner_id, 'partner_name', coalesce(p.display_name, p.name), 'period_from', s.period_from, 'period_to', s.period_to,
      'file_name', s.file_name, 'row_count', s.row_count, 'created_at', s.created_at,
      'matched', (select count(*) from b2b.statement_lines l where l.statement_id = s.id and l.match_status = 'matched'),
      'partner_only', (select count(*) from b2b.statement_lines l where l.statement_id = s.id and l.match_status = 'partner_only'),
      'amount_mismatch', (select count(*) from b2b.statement_lines l where l.statement_id = s.id and l.match_status = 'amount_mismatch'),
      'open', (select count(*) from b2b.statement_lines l where l.statement_id = s.id and l.match_status <> 'matched' and l.resolution is null))
      order by s.created_at desc), '[]')
    from b2b.partner_statements s join b2b.partners p on p.id = s.partner_id);
end $fn$;

revoke execute on function b2b.money_setup_missing() from public, anon, authenticated;
grant execute on function b2b.money_setup_missing() to service_role;
revoke execute on function b2b.money_overview(), b2b.money_enrollments(jsonb), b2b.money_invoices(jsonb), b2b.invoice_detail(bigint), b2b.money_receipts(jsonb),
                           b2b.money_statements() from public, anon;
grant execute on function b2b.money_overview(), b2b.money_enrollments(jsonb), b2b.money_invoices(jsonb), b2b.invoice_detail(bigint), b2b.money_receipts(jsonb),
                          b2b.money_statements() to authenticated, service_role;
