-- M20a: commission and money tables (spec B12, B5.3; design 5.7, D9). Receivables only: what partners owe Eduwit.
-- public.enrollments stays the shared outcome table (D9): two nullable columns are added (allocation_id, source_product);
-- the old CRM's inserts leave them null and keep working. Everything else is new in schema b2b.
-- Ledger rules: earning lines are never removed (a trigger refuses it); a realised line's amounts never change
-- (reversals and tier adjustments are new lines); expected lines are forecasts and are recomputed until verification.

-- ---------- shared enrollments (D9) ----------
alter table public.enrollments add column if not exists allocation_id bigint references b2b.allocations (id) on delete restrict;
alter table public.enrollments add column if not exists source_product text;
do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'enrollments_source_product_check') then
    alter table public.enrollments add constraint enrollments_source_product_check check (source_product is null or source_product in ('b2b', 'b2c'));
  end if;
end $do$;
create unique index if not exists enrollments_allocation_live_uq on public.enrollments (allocation_id)
  where allocation_id is not null and status <> 'cancelled';
create index if not exists enrollments_partner_idx on public.enrollments (partner_id, enrolled_on) where source_product = 'b2b';

-- ---------- partner billing details (invoice recipient) ----------
alter table b2b.partners add column if not exists legal_name text;
alter table b2b.partners add column if not exists gstin text;
alter table b2b.partners add column if not exists billing_address text;
alter table b2b.partners add column if not exists billing_state_code text;
alter table b2b.partners add column if not exists billing_email text;
alter table b2b.partners add column if not exists payment_terms_days int not null default 30;
do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'partners_gstin_check') then
    alter table b2b.partners add constraint partners_gstin_check check (gstin is null or gstin ~ '^[0-9]{2}[A-Z0-9]{13}$');
    alter table b2b.partners add constraint partners_terms_check check (payment_terms_days between 0 and 180);
    alter table b2b.partners add constraint partners_state_code_check check (billing_state_code is null or billing_state_code ~ '^[0-9]{2}$');
  end if;
end $do$;

-- ---------- tier settlement per partner and month ----------
create table if not exists b2b.money_periods (
  partner_id      bigint not null references b2b.partners (id) on delete restrict,
  period          text not null check (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  accepted_leads  int not null,
  enrollments     int not null,
  conversion_pct  numeric(7, 3),
  closed_at       timestamptz not null default now(),
  closed_by       text,
  primary key (partner_id, period)
);

-- ---------- invoices (before earnings: lines point at them) ----------
create table if not exists b2b.invoices (
  id              bigint generated always as identity primary key,
  partner_id      bigint not null references b2b.partners (id) on delete restrict,
  through_period  text not null check (through_period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  status          text not null default 'draft' check (status in ('draft', 'approved', 'sent', 'partly_paid', 'paid', 'cancelled')),
  fy              text,
  seq             int,
  number          text unique,
  issue_date      date,
  due_date        date,
  supplier        jsonb,
  recipient       jsonb,
  sac_code        text,
  place_of_supply text,
  tax_type        text check (tax_type in ('igst', 'cgst_sgst')),
  gst_rate        numeric(5, 4) not null,
  taxable_inr     numeric(12, 2) not null default 0,
  cgst_inr        numeric(12, 2) not null default 0,
  sgst_inr        numeric(12, 2) not null default 0,
  igst_inr        numeric(12, 2) not null default 0,
  total_inr       numeric(12, 2) not null default 0,
  received_inr    numeric(12, 2) not null default 0,
  tds_inr         numeric(12, 2) not null default 0,
  reminded_bucket text,
  notes           text,
  approved_at     timestamptz,
  sent_at         timestamptz,
  paid_at         timestamptz,
  cancelled_at    timestamptz,
  cancel_reason   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      text,
  unique (fy, seq),
  check ((status = 'draft') or (status = 'cancelled' and number is null) or (number is not null and issue_date is not null))
);
create index if not exists invoices_partner_idx on b2b.invoices (partner_id, status);
create unique index if not exists invoices_one_draft_uq on b2b.invoices (partner_id) where status = 'draft';

-- ---------- earning lines ----------
create table if not exists b2b.earnings (
  id                bigint generated always as identity primary key,
  enrollment_id     bigint references public.enrollments (id) on delete restrict,
  allocation_id     bigint references b2b.allocations (id) on delete restrict,
  partner_id        bigint not null references b2b.partners (id) on delete restrict,
  lead_id           bigint,
  period            text not null check (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  kind              text not null check (kind in ('commission', 'tier_adjustment', 'reversal', 'manual_adjustment')),
  status            text not null default 'expected' check (status in ('expected', 'realised', 'void')),
  rate_id           bigint references b2b.rates (id) on delete restrict,
  rate_snapshot     jsonb,
  fee_base_inr      numeric(12, 2),
  pct               numeric(7, 4),
  tier_provisional  boolean not null default false,
  net_inr           numeric(12, 2) not null,
  gst_rate          numeric(5, 4) not null,
  gst_inr           numeric(12, 2) not null,
  gross_inr         numeric(12, 2) not null,
  reverses_id       bigint references b2b.earnings (id) on delete restrict,
  adjusts_id        bigint references b2b.earnings (id) on delete restrict,
  invoice_id        bigint references b2b.invoices (id) on delete restrict,
  note              text,
  realised_at       timestamptz,
  created_at        timestamptz not null default now(),
  created_by        text,
  check (gross_inr = net_inr + gst_inr),
  check (kind <> 'commission' or enrollment_id is not null),
  check (invoice_id is null or status = 'realised')
);
create index if not exists earnings_enrollment_idx on b2b.earnings (enrollment_id);
create index if not exists earnings_open_idx on b2b.earnings (partner_id, period) where status = 'realised' and invoice_id is null;
create index if not exists earnings_invoice_idx on b2b.earnings (invoice_id) where invoice_id is not null;
create unique index if not exists earnings_one_commission_uq on b2b.earnings (enrollment_id) where kind = 'commission' and status <> 'void';
create unique index if not exists earnings_one_reversal_uq on b2b.earnings (reverses_id) where reverses_id is not null;

create table if not exists b2b.invoice_lines (
  id           bigint generated always as identity primary key,
  invoice_id   bigint not null references b2b.invoices (id) on delete restrict,
  earning_id   bigint not null references b2b.earnings (id) on delete restrict,
  lead_id      bigint,
  reference    text,
  description  text not null,
  taxable_inr  numeric(12, 2) not null,
  gst_inr      numeric(12, 2) not null,
  total_inr    numeric(12, 2) not null,
  released_at  timestamptz,
  unique (invoice_id, earning_id)
);

-- ---------- receipts ----------
create table if not exists b2b.receipts (
  id            bigint generated always as identity primary key,
  partner_id    bigint not null references b2b.partners (id) on delete restrict,
  received_on   date not null,
  amount_inr    numeric(12, 2) not null check (amount_inr > 0),
  tds_inr       numeric(12, 2) not null default 0 check (tds_inr >= 0),
  bank_ref      text,
  note          text,
  status        text not null default 'active' check (status in ('active', 'void')),
  void_reason   text,
  created_at    timestamptz not null default now(),
  created_by    text
);
create index if not exists receipts_partner_idx on b2b.receipts (partner_id, received_on desc);
create unique index if not exists receipts_bank_ref_uq on b2b.receipts (partner_id, lower(bank_ref)) where bank_ref is not null and status = 'active';

create table if not exists b2b.receipt_allocations (
  id           bigint generated always as identity primary key,
  receipt_id   bigint not null references b2b.receipts (id) on delete restrict,
  invoice_id   bigint not null references b2b.invoices (id) on delete restrict,
  amount_inr   numeric(12, 2) not null check (amount_inr >= 0),
  tds_inr      numeric(12, 2) not null default 0 check (tds_inr >= 0),
  method       text not null check (method in ('auto_exact', 'auto_oldest', 'manual')),
  reversed_at  timestamptz,
  created_at   timestamptz not null default now(),
  check (amount_inr + tds_inr > 0)
);
create index if not exists receipt_allocations_invoice_idx on b2b.receipt_allocations (invoice_id) where reversed_at is null;

-- ---------- partner statements (B12.6) ----------
create table if not exists b2b.partner_statements (
  id            bigint generated always as identity primary key,
  partner_id    bigint not null references b2b.partners (id) on delete restrict,
  period_from   date not null,
  period_to     date not null,
  file_name     text,
  row_count     int not null default 0,
  created_at    timestamptz not null default now(),
  created_by    text,
  check (period_to >= period_from)
);

create table if not exists b2b.statement_lines (
  id                 bigint generated always as identity primary key,
  statement_id       bigint not null references b2b.partner_statements (id) on delete cascade,
  row_no             int not null,
  reference          text,
  record_id          text,
  phone              text,
  name               text,
  programme          text,
  enrolled_on        date,
  amount_inr         numeric(12, 2),
  raw                jsonb not null default '{}',
  match_status       text not null check (match_status in ('matched', 'partner_only', 'amount_mismatch')),
  match_method       text check (match_method in ('reference', 'record_id', 'phone', 'name_programme')),
  allocation_id      bigint references b2b.allocations (id) on delete restrict,
  enrollment_id      bigint references public.enrollments (id) on delete restrict,
  eduwit_amount_inr  numeric(12, 2),
  diff_inr           numeric(12, 2),
  resolution         text check (resolution in ('verified', 'recorded', 'dismissed')),
  resolution_note    text,
  resolved_at        timestamptz,
  unique (statement_id, row_no)
);
create index if not exists statement_lines_enrollment_idx on b2b.statement_lines (enrollment_id) where enrollment_id is not null;

-- ---------- ledger guards ----------
create or replace function b2b.money_line_guard()
returns trigger language plpgsql set search_path = '' as $fn$
begin
  raise exception 'money lines are never removed; record a reversal or cancel instead' using errcode = '42501';
end $fn$;

create or replace function b2b.earning_update_guard()
returns trigger language plpgsql set search_path = '' as $fn$
begin
  if old.status = 'realised' and (new.net_inr, new.gst_inr, new.gross_inr, new.period, new.kind, new.enrollment_id, new.partner_id, new.status)
     is distinct from (old.net_inr, old.gst_inr, old.gross_inr, old.period, old.kind, old.enrollment_id, old.partner_id, old.status) then
    raise exception 'a realised earning never changes; record a reversal or adjustment' using errcode = '42501';
  end if;
  if old.status = 'void' and new.status is distinct from 'void' then raise exception 'a void earning stays void' using errcode = '42501'; end if;
  return new;
end $fn$;

do $do$ begin
  if not exists (select 1 from pg_trigger where tgname = 'earnings_no_removal') then
    create trigger earnings_no_removal before delete on b2b.earnings for each row execute function b2b.money_line_guard();
    create trigger earnings_update_guard before update on b2b.earnings for each row execute function b2b.earning_update_guard();
    create trigger invoices_no_removal before delete on b2b.invoices for each row execute function b2b.money_line_guard();
    create trigger invoice_lines_no_removal before delete on b2b.invoice_lines for each row execute function b2b.money_line_guard();
    create trigger receipts_no_removal before delete on b2b.receipts for each row execute function b2b.money_line_guard();
    create trigger receipt_allocations_no_removal before delete on b2b.receipt_allocations for each row execute function b2b.money_line_guard();
  end if;
end $do$;

-- ---------- RLS: reads through definer functions only ----------
alter table b2b.money_periods enable row level security;
alter table b2b.invoices enable row level security;
alter table b2b.earnings enable row level security;
alter table b2b.invoice_lines enable row level security;
alter table b2b.receipts enable row level security;
alter table b2b.receipt_allocations enable row level security;
alter table b2b.partner_statements enable row level security;
alter table b2b.statement_lines enable row level security;
do $do$
declare t text;
begin
  foreach t in array array['money_periods', 'invoices', 'earnings', 'invoice_lines', 'receipts', 'receipt_allocations', 'partner_statements', 'statement_lines'] loop
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
  end loop;
end $do$;
revoke all on b2b.money_periods, b2b.invoices, b2b.earnings, b2b.invoice_lines, b2b.receipts, b2b.receipt_allocations,
              b2b.partner_statements, b2b.statement_lines from anon, authenticated;
grant select on b2b.money_periods, b2b.invoices, b2b.earnings, b2b.invoice_lines, b2b.receipts, b2b.receipt_allocations,
                b2b.partner_statements, b2b.statement_lines to authenticated;
revoke execute on function b2b.money_line_guard(), b2b.earning_update_guard() from public, anon, authenticated;

-- ---------- settings: money (keys kept; new ones added with defaults) ----------
select b2b.set_setting('money',
  jsonb_build_object(
    'gst_rate', 0.18, 'sac_code', null, 'tds_rate', null, 'invoice_period', 'monthly', 'refund_window_days', 30, 'confirmed_by_ca', false,
    'invoice_prefix', 'EDW', 'eduwit', jsonb_build_object('legal_name', null, 'gstin', null, 'address', null, 'state_code', null, 'bank', null),
    'tier_min_leads', 20, 'auto_close', true, 'close_day', 7, 'reminder_days', jsonb_build_array(30, 60, 90))
  || coalesce((select value from b2b.settings where key = 'money'), '{}'),
  'm20a: money settings for invoicing (Eduwit details, prefix, tiers, auto close, reminders)')
 where not ((select value from b2b.settings where key = 'money') ? 'invoice_prefix');
