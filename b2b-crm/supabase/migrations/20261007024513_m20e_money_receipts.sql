-- M20e: receipts, reminders and the money jobs (B12.5).
--   receipt_apply       puts part of a receipt (cash + TDS, TDS in the receipt's proportion) on one invoice
--   receipt_record      a payment with TDS and bank reference, matched to the exact invoice or else oldest first
--   receipt_allocate, receipt_void
--   money_tick          every 5 minutes: enrollments for partner leads that reached "enrolled"
--   money_daily         overdue reminders and the automatic close of last month

/* Splits up to p_credit (cash + TDS) of a receipt onto one invoice, TDS in the receipt's proportion. Returns the credit used. */
create or replace function b2b.receipt_apply(p_receipt_id bigint, p_invoice_id bigint, p_credit numeric, p_method text)
returns numeric language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r b2b.receipts;
  i b2b.invoices;
  v_left numeric;
  v_open numeric;
  v_use numeric;
  v_tds numeric;
begin
  select * into r from b2b.receipts where id = p_receipt_id for update;
  select * into i from b2b.invoices where id = p_invoice_id for update;
  if i.partner_id <> r.partner_id then raise exception 'the invoice is another partner''s' using errcode = '22023'; end if;
  if i.status not in ('approved', 'sent', 'partly_paid') then raise exception 'invoice % is not open', coalesce(i.number, i.id::text) using errcode = '22023'; end if;
  select r.amount_inr + r.tds_inr - coalesce(sum(a.amount_inr + a.tds_inr), 0) into v_left
    from b2b.receipt_allocations a where a.receipt_id = r.id and a.reversed_at is null;
  v_open := i.total_inr - i.received_inr - i.tds_inr;
  v_use := least(v_left, v_open, coalesce(p_credit, v_left));
  if v_use <= 0 then return 0; end if;
  v_tds := round(v_use * r.tds_inr / (r.amount_inr + r.tds_inr), 2);
  insert into b2b.receipt_allocations (receipt_id, invoice_id, amount_inr, tds_inr, method) values (r.id, i.id, v_use - v_tds, v_tds, p_method);
  perform b2b.invoice_settle(i.id);
  return v_use;
end $fn$;

/* p: partner_id, received_on, amount_inr, tds_inr, bank_ref, note, invoice_id (optional: apply there first). */
create or replace function b2b.receipt_record(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_amt numeric := round(nullif(p ->> 'amount_inr', '')::numeric, 2);
  v_tds numeric := round(coalesce(nullif(p ->> 'tds_inr', '')::numeric, 0), 2);
  v_on date := coalesce(nullif(p ->> 'received_on', '')::date, current_date);
  v_id bigint;
  v_inv bigint;
  v_used numeric := 0;
  i record;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_amt is null or v_amt <= 0 or v_amt > 100000000 then raise exception 'enter the amount received' using errcode = '22023'; end if;
  if v_tds < 0 or v_tds > v_amt then raise exception 'TDS cannot be negative or more than the amount' using errcode = '22023'; end if;
  if v_on > current_date then raise exception 'the date is in the future' using errcode = '22023'; end if;
  if nullif(trim(p ->> 'bank_ref'), '') is not null and exists (select 1 from b2b.receipts where partner_id = v_partner and status = 'active'
                                                                  and lower(bank_ref) = lower(trim(p ->> 'bank_ref'))) then
    raise exception 'a receipt with this bank reference is already recorded' using errcode = '22023';
  end if;
  insert into b2b.receipts (partner_id, received_on, amount_inr, tds_inr, bank_ref, note, created_by)
  values (v_partner, v_on, v_amt, v_tds, nullif(left(trim(p ->> 'bank_ref'), 80), ''), nullif(left(trim(p ->> 'note'), 300), ''), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  v_inv := nullif(p ->> 'invoice_id', '')::bigint;
  if v_inv is not null then
    v_used := b2b.receipt_apply(v_id, v_inv, null, 'manual');
  else
    select x.id into v_inv from b2b.invoices x
     where x.partner_id = v_partner and x.status in ('approved', 'sent', 'partly_paid')
       and abs((x.total_inr - x.received_inr - x.tds_inr) - (v_amt + v_tds)) < 1
     order by x.issue_date, x.id limit 1;
    if v_inv is not null then
      v_used := b2b.receipt_apply(v_id, v_inv, null, 'auto_exact');
    else
      for i in select x.id from b2b.invoices x where x.partner_id = v_partner and x.status in ('approved', 'sent', 'partly_paid')
                order by x.issue_date, x.id loop
        exit when v_used >= v_amt + v_tds;
        v_used := v_used + b2b.receipt_apply(v_id, i.id, null, 'auto_oldest');
      end loop;
    end if;
  end if;
  perform b2b.log_event('money.receipt_recorded', null, null, v_partner,
                        jsonb_build_object('receipt_id', v_id, 'amount_inr', v_amt, 'tds_inr', v_tds, 'applied_inr', v_used));
  return jsonb_build_object('id', v_id, 'applied_inr', v_used, 'unapplied_inr', v_amt + v_tds - v_used);
end $fn$;

create or replace function b2b.receipt_allocate(p_receipt_id bigint, p_invoice_id bigint)
returns numeric language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.receipts where id = p_receipt_id and status = 'active') then raise exception 'receipt not found' using errcode = 'P0002'; end if;
  v := b2b.receipt_apply(p_receipt_id, p_invoice_id, null, 'manual');
  if v = 0 then raise exception 'nothing left to apply' using errcode = '22023'; end if;
  perform b2b.log_event('money.receipt_applied', null, null, (select partner_id from b2b.receipts where id = p_receipt_id),
                        jsonb_build_object('receipt_id', p_receipt_id, 'invoice_id', p_invoice_id, 'credit_inr', v));
  return v;
end $fn$;

create or replace function b2b.receipt_void(p_id bigint, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_inv bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'give a reason' using errcode = '22023'; end if;
  update b2b.receipts set status = 'void', void_reason = left(trim(p_reason), 300) where id = p_id and status = 'active';
  if not found then raise exception 'receipt not found or already void' using errcode = 'P0002'; end if;
  for v_inv in update b2b.receipt_allocations set reversed_at = now() where receipt_id = p_id and reversed_at is null returning invoice_id loop
    perform b2b.invoice_settle(v_inv);
  end loop;
  perform b2b.log_event('money.receipt_voided', null, null, (select partner_id from b2b.receipts where id = p_id), jsonb_build_object('receipt_id', p_id, 'reason', p_reason));
end $fn$;

create or replace function b2b.money_tick()
returns jsonb language sql volatile security definer set search_path = '' as $fn$
  select b2b.money_scan(200);
$fn$;

/* Daily: overdue reminders (on the due date, then at each reminder_days past it) and the automatic close of last month
   from close_day on (default the 7th, so proof for the month's enrollments can arrive first). */
create or replace function b2b.money_daily()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.money_cfg();
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_prev text := b2b.period_of(((now() at time zone 'Asia/Kolkata')::date - interval '1 month')::date);
  i record;
  v_bucket text;
  v_n int := 0;
  v_close jsonb;
begin
  for i in select x.*, v_today - x.due_date as overdue from b2b.invoices x
            where x.status in ('approved', 'sent', 'partly_paid') and x.due_date < v_today loop
    v_bucket := coalesce((select max(d::int)::text from jsonb_array_elements_text(coalesce(cfg -> 'reminder_days', '[30,60,90]')) d where d::int <= i.overdue), 'due');
    if i.reminded_bucket is distinct from v_bucket then
      perform b2b.log_event('alert.invoice_overdue', null, null, i.partner_id,
                            jsonb_build_object('invoice_id', i.id, 'number', i.number, 'days_overdue', i.overdue,
                                               'outstanding_inr', i.total_inr - i.received_inr - i.tds_inr));
      update b2b.invoices set reminded_bucket = v_bucket where id = i.id;
      v_n := v_n + 1;
    end if;
  end loop;
  if coalesce((cfg ->> 'auto_close')::boolean, true) and extract(day from v_today) >= coalesce((cfg ->> 'close_day')::int, 7)
     and not exists (select 1 from b2b.events e where e.type = 'money.period_closed' and e.payload ->> 'period' = v_prev and e.partner_id is null) then
    v_close := b2b.period_close(v_prev, null);
  end if;
  return jsonb_build_object('reminders', v_n, 'closed', v_close);
end $fn$;

do $do$ begin
  if not exists (select 1 from cron.job where jobname = 'b2b-money-tick') then
    perform cron.schedule('b2b-money-tick', '*/5 * * * *', 'select b2b.money_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2b-money-daily') then
    perform cron.schedule('b2b-money-daily', '35 3 * * *', 'select b2b.money_daily()');
  end if;
end $do$;

revoke execute on function b2b.receipt_apply(bigint, bigint, numeric, text), b2b.money_tick(), b2b.money_daily() from public, anon, authenticated;
grant execute on function b2b.receipt_apply(bigint, bigint, numeric, text), b2b.money_tick(), b2b.money_daily() to service_role;
revoke execute on function b2b.receipt_record(jsonb), b2b.receipt_allocate(bigint, bigint), b2b.receipt_void(bigint, text) from public, anon;
grant execute on function b2b.receipt_record(jsonb), b2b.receipt_allocate(bigint, bigint), b2b.receipt_void(bigint, text) to authenticated, service_role;
