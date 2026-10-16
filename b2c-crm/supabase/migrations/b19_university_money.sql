-- B2C CRM b19 (Phase 3): Eduwit's university commission (spec B11.1). Staging first. Idempotent.
--   university_billing, university_rates   who the university is for invoices; rates by date (percent, fixed, tiered; GST flag)
--   earnings                               the ledger: one booking per enrollment, never edited; corrections are new lines
--   period_closes                          tiers settled at period close from verified enrollments / leads
--   invoices, invoice_lines                GST invoices with gapless numbers per financial year; credit notes, never edits
--   receipts, receipt_allocations          payments with TDS, matched to invoices; ageing
--   statement_imports, statement_rows      a university's statement reconciled into four piles
-- The CRM moves no money. Rates, GST, SAC and refund windows are settings to be confirmed by Eduwit's CA.

insert into b2c.settings (key, value) values
  ('money', '{"gst_pct": 18, "sac": "to confirm", "eduwit_legal_name": "Eduwit Learning Services", "eduwit_gstin": null, "eduwit_address": null,
              "eduwit_state_code": null, "invoice_prefix": "EDW", "credit_prefix": "EDW-CN", "payment_terms_days": 30, "default_refund_days": 30,
              "tier_denominator": "university_leads", "tds_counsellor_pct": 0, "run_day": 5, "statement_tolerance": 1, "ca_confirmed": false}')
on conflict (key) do nothing;

-- ---------- enrollments: the catalogue ids the rates need ----------
alter table b2c.enrollments add column if not exists university_id bigint;
alter table b2c.enrollments add column if not exists programme_id bigint;
alter table b2c.enrollments add column if not exists fee_first_year numeric(12, 2);
alter table b2c.enrollments add column if not exists refunded_on date;
alter table b2c.enrollments add column if not exists refund_reason text;

/* The catalogue ids for an enrollment typed as text: the university by name or short name, the programme by name or
   course within it. Unresolved ids stay null; the Admin links them on the Money page. */
create or replace function b2c.catalog_ids(p_university text, p_programme text) returns jsonb language sql stable security definer set search_path = '' as $f$
  with u as (
    select un.id from public.catalog_universities un
     where lower(un.name) = lower(trim(p_university)) or lower(un.short_name) = lower(trim(p_university))
     order by (lower(un.name) = lower(trim(p_university))) desc, un.id limit 1)
  select jsonb_build_object('university_id', (select id from u),
    'programme_id', (select pr.id from public.catalog_programs pr, u
                      where pr.university_id = u.id
                        and (lower(coalesce(pr.program_name, '')) = lower(trim(p_programme)) or lower(pr.course) = lower(trim(p_programme))
                             or lower(pr.course || ' ' || coalesce(pr.specialization, '')) = lower(trim(p_programme))
                             or lower(coalesce(pr.program_name, pr.course) || ' ' || coalesce(pr.specialization, '')) = lower(trim(p_programme)))
                      order by pr.active desc, (lower(coalesce(pr.program_name, '')) = lower(trim(p_programme))) desc, pr.id limit 1))
$f$;

create or replace function b2c.enrollments_catalog() returns trigger language plpgsql security definer set search_path = '' as $f$
declare j jsonb;
begin
  if new.university_id is null or new.programme_id is null then
    j := b2c.catalog_ids(new.university, new.programme);
    new.university_id := coalesce(new.university_id, (j ->> 'university_id')::bigint);
    new.programme_id := coalesce(new.programme_id, (j ->> 'programme_id')::bigint);
  end if;
  return new;
end $f$;
do $d$
begin
  if not exists (select 1 from pg_trigger where tgname = 'enrollments_catalog') then
    create trigger enrollments_catalog before insert on b2c.enrollments for each row execute function b2c.enrollments_catalog();
  end if;
end $d$;

-- ---------- universities and their rates ----------
create table if not exists b2c.university_billing (
  university_id bigint primary key,
  legal_name text,
  gstin text check (gstin is null or gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  address text,
  state_code text check (state_code is null or state_code ~ '^[0-9]{2}$'),
  email text,
  refund_days int check (refund_days is null or refund_days between 0 and 365),
  payment_terms_days int check (payment_terms_days is null or payment_terms_days between 0 and 180),
  updated_at timestamptz not null default now(),
  actor_id uuid
);

create table if not exists b2c.university_rates (
  id bigint generated always as identity primary key,
  university_id bigint not null,
  programme_id bigint,                         -- null = the university's rate for every programme
  rate_type text not null check (rate_type in ('percent', 'fixed', 'tiered')),
  fee_base text not null default 'first_year' check (fee_base in ('first_year', 'total', 'amount_paid')),
  value numeric(12, 4),                        -- percent or rupees
  tiers jsonb,                                 -- [{"from": 0, "to": 7, "value": 22.42}, ...] conversion % (to exclusive; null = no limit)
  gst_inclusive boolean not null default true,
  valid_from date not null,
  valid_to date,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check ((rate_type = 'tiered') = (tiers is not null)),
  check (rate_type = 'tiered' or value is not null),
  check (valid_to is null or valid_to >= valid_from)
);
create index if not exists university_rates_uni on b2c.university_rates (university_id, valid_from desc) where retired_at is null;

-- ---------- the ledger ----------
create table if not exists b2c.earnings (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references b2c.enrollments (id),
  university_id bigint,
  kind text not null check (kind in ('booking', 'reversal', 'tier_adjust', 'refund')),
  period date not null,                        -- the month of the enrollment
  base_amount numeric(12, 2),
  rate_pct numeric(12, 4),                     -- the percent applied (null for a fixed rate)
  gross numeric(12, 2) not null,
  gst numeric(12, 2) not null,
  net numeric(12, 2) not null,
  gst_inclusive boolean not null,
  snapshot jsonb not null default '{}'::jsonb, -- rate id, type, fee base, tier and conversion, provisional, read at
  reverses_id bigint references b2c.earnings (id),
  realised_at timestamptz,                     -- the Admin verified the enrollment
  invoice_id bigint,
  is_test boolean not null default false,      -- a test lead's enrollment: test invoices only, never in reports
  reason text,
  actor_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists earnings_enrollment on b2c.earnings (enrollment_id);
create index if not exists earnings_uni_period on b2c.earnings (university_id, period);
create index if not exists earnings_uninvoiced on b2c.earnings (university_id) where invoice_id is null and realised_at is not null;

/* Amounts and the snapshot never change; only realised_at and invoice_id move. */
create or replace function b2c.ledger_guard() returns trigger language plpgsql set search_path = '' as $f$
declare k text; allowed text[] := string_to_array(tg_argv[0], ',');
begin
  if tg_op <> 'UPDATE' then raise exception '% is a ledger: add a reversing line instead', tg_table_name; end if;
  for k in select key from jsonb_each(to_jsonb(new)) loop
    if not (k = any (allowed)) and (to_jsonb(new) -> k) is distinct from (to_jsonb(old) -> k) then
      raise exception '% is a ledger: % cannot change (add a reversing line)', tg_table_name, k;
    end if;
  end loop;
  return new;
end $f$;
-- (the guard against removing rows is in supabase/manual/staging_phase3_ledger_guards.sql: the connector cannot apply it)
do $d$
begin
  if not exists (select 1 from pg_trigger where tgname = 'earnings_ledger') then
    create trigger earnings_ledger before update on b2c.earnings for each row execute function b2c.ledger_guard('realised_at,invoice_id');
  end if;
end $d$;

create table if not exists b2c.period_closes (
  university_id bigint not null,
  period date not null,
  leads int not null,
  verified int not null,
  conversion numeric(8, 4) not null,
  denominator text not null,
  adjustments int not null default 0,
  closed_by uuid,
  closed_at timestamptz not null default now(),
  primary key (university_id, period)
);

-- ---------- invoices ----------
create table if not exists b2c.invoice_counters (
  series text primary key,                     -- 'EDW/2026-27'
  last int not null default 0
);
create table if not exists b2c.invoices (
  id bigint generated always as identity primary key,
  kind text not null default 'invoice' check (kind in ('invoice', 'credit_note')),
  number text unique,                          -- given at approval, gapless per series
  university_id bigint not null,
  credit_of bigint references b2c.invoices (id),
  issue_date date,
  due_on date,
  billing jsonb not null default '{}'::jsonb,  -- Eduwit's and the university's details as on the invoice
  sac text,
  gst_pct numeric(6, 2) not null,
  supply text not null default 'inter' check (supply in ('intra', 'inter')),   -- CGST+SGST or IGST
  net numeric(12, 2) not null default 0,
  gst numeric(12, 2) not null default 0,
  gross numeric(12, 2) not null default 0,
  status text not null default 'draft' check (status in ('draft', 'approved', 'sent', 'part_paid', 'paid', 'cancelled', 'discarded')),
  approved_by uuid,
  approved_at timestamptz,
  sent_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  reminded_at timestamptz,
  is_test boolean not null default false,      -- an invoice of test leads: its own TEST- series, never sent
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists b2c.invoice_lines (
  id bigint generated always as identity primary key,
  invoice_id bigint not null references b2c.invoices (id),
  earning_id bigint references b2c.earnings (id),
  enrollment_id bigint,
  description text not null,
  net numeric(12, 2) not null,
  gst numeric(12, 2) not null,
  gross numeric(12, 2) not null
);
create index if not exists invoice_lines_invoice on b2c.invoice_lines (invoice_id);

-- ---------- receipts ----------
create table if not exists b2c.receipts (
  id bigint generated always as identity primary key,
  university_id bigint not null,
  received_on date not null,
  amount numeric(12, 2) not null check (amount >= 0),   -- what reached the bank
  tds numeric(12, 2) not null default 0 check (tds >= 0),
  reference text not null,
  note text,
  unallocated numeric(12, 2) not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (university_id, reference)
);
create table if not exists b2c.receipt_allocations (
  id bigint generated always as identity primary key,
  receipt_id bigint not null references b2c.receipts (id),
  invoice_id bigint not null references b2c.invoices (id),
  amount numeric(12, 2) not null check (amount > 0),     -- counts against the invoice gross (bank amount plus TDS share)
  created_at timestamptz not null default now()
);
create index if not exists receipt_allocations_invoice on b2c.receipt_allocations (invoice_id);

-- ---------- statements ----------
create table if not exists b2c.statement_imports (
  id bigint generated always as identity primary key,
  university_id bigint not null,
  period_from date not null,
  period_to date not null,
  file_name text,
  summary jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now()
);
create table if not exists b2c.statement_rows (
  id bigint generated always as identity primary key,
  import_id bigint not null references b2c.statement_imports (id),
  row_no int not null,
  ref text,
  student text,
  programme text,
  amount numeric(12, 2),
  enrollment_id bigint,
  expected numeric(12, 2),
  pile text not null check (pile in ('matched', 'university_only', 'mismatch')),
  raw jsonb not null default '{}'::jsonb
);
create index if not exists statement_rows_import on b2c.statement_rows (import_id);

-- ---------- helpers ----------
/* Rounded GST split. Inclusive: the amount is gross. Exclusive: the amount is net. */
create or replace function b2c.gst_split(p_amount numeric, p_inclusive boolean, p_pct numeric) returns jsonb language sql immutable set search_path = '' as $f$
  select case when p_inclusive
    then jsonb_build_object('gross', round(p_amount, 2), 'net', round(p_amount / (1 + p_pct / 100), 2), 'gst', round(p_amount, 2) - round(p_amount / (1 + p_pct / 100), 2))
    else jsonb_build_object('net', round(p_amount, 2), 'gst', round(p_amount * p_pct / 100, 2), 'gross', round(p_amount, 2) + round(p_amount * p_pct / 100, 2)) end
$f$;

/* The fee an enrollment's rate applies to. */
create or replace function b2c.fee_base_amount(p_enrollment bigint, p_base text) returns numeric language sql stable security definer set search_path = '' as $f$
  select case p_base
    when 'total' then e.fee
    when 'amount_paid' then e.fee_paid
    else coalesce(e.fee_first_year, pr.fee_yearly, e.fee) end
    from b2c.enrollments e left join public.catalog_programs pr on pr.id = e.programme_id
   where e.id = p_enrollment
$f$;

/* The tier for a conversion %, from [{"from","to","value"}]. p_top: the highest value regardless. */
create or replace function b2c.tier_pick(p_tiers jsonb, p_conversion numeric, p_top boolean default false) returns jsonb language sql immutable set search_path = '' as $f$
  select case when p_top then (select t from jsonb_array_elements(p_tiers) t order by (t ->> 'value')::numeric desc limit 1)
    else coalesce(
      (select t from jsonb_array_elements(p_tiers) t
        where coalesce(p_conversion, 0) >= coalesce((t ->> 'from')::numeric, 0) and (t ->> 'to' is null or coalesce(p_conversion, 0) < (t ->> 'to')::numeric)
        order by coalesce((t ->> 'from')::numeric, 0) desc limit 1),
      (select t from jsonb_array_elements(p_tiers) t order by coalesce((t ->> 'from')::numeric, 0) limit 1)) end
$f$;

create or replace function b2c.refund_days(p_university bigint) returns int language sql stable security definer set search_path = '' as $f$
  select coalesce((select refund_days from b2c.university_billing where university_id = p_university), (b2c.setting('money') ->> 'default_refund_days')::int, 30)
$f$;

/* The university rate in force on a date: the programme's own first, then the university's. */
create or replace function b2c.university_rate_for(p_university bigint, p_programme bigint, p_on date) returns b2c.university_rates
language sql stable security definer set search_path = '' as $f$
  select r.* from b2c.university_rates r
   where r.university_id = p_university and r.retired_at is null and r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and (r.programme_id is null or r.programme_id = p_programme)
   order by (r.programme_id is not null) desc, r.valid_from desc, r.id desc limit 1
$f$;

/* The tier denominator for a university and month: B2C leads handed off that month whose interest names the university
   (setting 'university_leads'), or every B2C lead that month ('all_leads'). */
create or replace function b2c.period_leads(p_university bigint, p_period date) returns int language sql stable security definer set search_path = '' as $f$
  select count(*)::int from b2c.leads_state s left join b2c.lead_records r on r.lead_id = s.lead_id
   where s.handed_off_at >= p_period and s.handed_off_at < (p_period + interval '1 month') and not s.is_test and s.deleted_at is null
     and (coalesce(b2c.setting('money') ->> 'tier_denominator', 'university_leads') = 'all_leads'
          or exists (select 1 from public.catalog_universities un where un.id = p_university
                      and (lower(r.record -> 'interest' ->> 'university') = lower(un.name) or lower(r.record -> 'interest' ->> 'university') = lower(un.short_name))))
$f$;

create or replace function b2c.period_conversion(p_university bigint, p_period date, p_leads int default null) returns jsonb
language sql stable security definer set search_path = '' as $f$
  with v as (select count(*)::int as n from b2c.enrollments e
              where e.university_id = p_university and e.status = 'verified' and date_trunc('month', e.enrolled_on)::date = p_period),
       l as (select coalesce(p_leads, b2c.period_leads(p_university, p_period)) as n)
  select jsonb_build_object('verified', v.n, 'leads', l.n, 'conversion', case when l.n > 0 then round(100.0 * v.n / l.n, 4) else 0 end) from v, l
$f$;

-- ---------- booking ----------
/* Books an enrollment's expected commission from the rate in force on its enrollment date. Once per enrollment (a
   rebook reverses first). No university or rate: nothing is booked and the Admin is told. */
create or replace function b2c.earning_book(p_enrollment bigint, p_reason text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare e b2c.enrollments; r b2c.university_rates; v_period date; v_base numeric; v_pct numeric; v_amt numeric; v_tier jsonb; v_conv jsonb;
        g jsonb; v_gst numeric := coalesce((b2c.setting('money') ->> 'gst_pct')::numeric, 18); v bigint; v_test boolean;
begin
  select * into e from b2c.enrollments where id = p_enrollment;
  if e.id is null or e.status in ('cancelled', 'refunded') then return null; end if;
  if exists (select 1 from b2c.earnings x where x.enrollment_id = e.id and x.kind = 'booking'
              and not exists (select 1 from b2c.earnings y where y.reverses_id = x.id)) then return null; end if;
  v_period := date_trunc('month', e.enrolled_on)::date;
  select coalesce(s.is_test, false) into v_test from b2c.leads_state s where s.lead_id = e.lead_id;
  if e.university_id is null then
    perform b2c.notify_admins('money', 'Enrollment needs its university', e.university || ' · ' || e.programme || ': link it to the catalogue on Money', '/w/money?tab=university', e.lead_id, 'uni-link:' || e.id);
    return null;
  end if;
  r := b2c.university_rate_for(e.university_id, e.programme_id, e.enrolled_on);
  if r.id is null then
    perform b2c.notify_admins('money', 'No university commission rate', e.university || ' has no rate on ' || e.enrolled_on || '. Add it on Money → University commission.',
                              '/w/money?tab=university', e.lead_id, 'uni-rate:' || e.university_id || ':' || v_period);
    return null;
  end if;
  v_base := b2c.fee_base_amount(e.id, r.fee_base);
  if r.rate_type = 'fixed' then
    v_amt := r.value;
  else
    if r.rate_type = 'tiered' then
      v_conv := b2c.period_conversion(e.university_id, v_period);
      v_tier := b2c.tier_pick(r.tiers, (v_conv ->> 'conversion')::numeric);
      v_pct := (v_tier ->> 'value')::numeric;
    else
      v_pct := r.value;
    end if;
    v_amt := v_base * v_pct / 100;
  end if;
  g := b2c.gst_split(v_amt, r.gst_inclusive, v_gst);
  insert into b2c.earnings (enrollment_id, university_id, kind, period, base_amount, rate_pct, gross, gst, net, gst_inclusive, snapshot, realised_at, is_test, reason, actor_id)
  values (e.id, e.university_id, 'booking', v_period, v_base, v_pct, (g ->> 'gross')::numeric, (g ->> 'gst')::numeric, (g ->> 'net')::numeric, r.gst_inclusive,
          jsonb_build_object('rate_id', r.id, 'rate_type', r.rate_type, 'fee_base', r.fee_base, 'value', r.value, 'tier', v_tier, 'conversion', v_conv,
                             'provisional', r.rate_type = 'tiered', 'gst_pct', v_gst, 'programme_rate', r.programme_id is not null, 'read_at', now()),
          case when e.status = 'verified' then now() end, coalesce(v_test, false), p_reason, b2c.uid())
  returning id into v;
  return v;
end $f$;

/* Reverses every open line of an enrollment (cancelled, refunded inside the window, or rebooked). */
create or replace function b2c.earning_reverse(p_enrollment bigint, p_kind text, p_reason text) returns int
language plpgsql security definer set search_path = '' as $f$
declare x b2c.earnings; n int := 0;
begin
  for x in select * from b2c.earnings e where e.enrollment_id = p_enrollment and e.kind in ('booking', 'tier_adjust')
            and not exists (select 1 from b2c.earnings y where y.reverses_id = e.id) loop
    insert into b2c.earnings (enrollment_id, university_id, kind, period, base_amount, rate_pct, gross, gst, net, gst_inclusive, snapshot, reverses_id, realised_at, is_test, reason, actor_id)
    values (x.enrollment_id, x.university_id, p_kind, x.period, x.base_amount, x.rate_pct, -x.gross, -x.gst, -x.net, x.gst_inclusive,
            jsonb_build_object('reverses', x.id), x.id, x.realised_at, x.is_test, p_reason, b2c.uid());
    n := n + 1;
  end loop;
  return n;
end $f$;

/* Enrollment changes drive the ledger: a new enrollment books; verification realises; a cancellation reverses. */
create or replace function b2c.enrollments_money() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if tg_op = 'INSERT' then
    perform b2c.earning_book(new.id);
  elsif new.status is distinct from old.status then
    if new.status = 'verified' then
      update b2c.earnings set realised_at = now() where enrollment_id = new.id and realised_at is null;
    elsif new.status = 'cancelled' then
      perform b2c.earning_reverse(new.id, 'reversal', 'enrollment cancelled');
    end if;
  end if;
  return null;
end $f$;
do $d$
begin
  if not exists (select 1 from pg_trigger where tgname = 'enrollments_money') then
    create trigger enrollments_money after insert or update of status on b2c.enrollments for each row execute function b2c.enrollments_money();
  end if;
end $d$;

-- ---------- Admin: rates, billing, linking ----------
create or replace function b2c.university_rate_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v bigint; v_from date := coalesce(nullif(p ->> 'valid_from', '')::date, current_date);
        v_uni bigint := (p ->> 'university_id')::bigint; v_prog bigint := nullif(p ->> 'programme_id', '')::bigint; t jsonb;
begin
  if not exists (select 1 from public.catalog_universities where id = v_uni) then raise exception 'pick a university from the catalogue'; end if;
  if p ->> 'rate_type' = 'tiered' then
    if jsonb_typeof(p -> 'tiers') <> 'array' or jsonb_array_length(p -> 'tiers') = 0 then raise exception 'a tiered rate needs its tiers'; end if;
    for t in select * from jsonb_array_elements(p -> 'tiers') loop
      if (t ->> 'value') is null or (t ->> 'value')::numeric < 0 or (t ->> 'value')::numeric > 100 then raise exception 'each tier needs a percent between 0 and 100'; end if;
    end loop;
  elsif p ->> 'rate_type' = 'percent' and ((p ->> 'value')::numeric not between 0 and 100) then raise exception 'a percent is between 0 and 100';
  elsif p ->> 'rate_type' = 'fixed' and ((p ->> 'value')::numeric < 0) then raise exception 'a fixed amount cannot be negative';
  end if;
  if length(coalesce(trim(p ->> 'note'), '')) < 3 then raise exception 'say where the rate comes from (agreement, email, date)'; end if;
  -- the rate it replaces ends the day before
  update b2c.university_rates set valid_to = v_from - 1
   where university_id = v_uni and programme_id is not distinct from v_prog and retired_at is null and valid_from < v_from and (valid_to is null or valid_to >= v_from);
  insert into b2c.university_rates (university_id, programme_id, rate_type, fee_base, value, tiers, gst_inclusive, valid_from, valid_to, note, created_by)
  values (v_uni, v_prog, p ->> 'rate_type', coalesce(p ->> 'fee_base', 'first_year'), nullif(p ->> 'value', '')::numeric,
          case when p ->> 'rate_type' = 'tiered' then p -> 'tiers' end, coalesce((p ->> 'gst_inclusive')::boolean, true), v_from,
          nullif(p ->> 'valid_to', '')::date, p ->> 'note', me)
  returning id into v;
  perform b2c.log('money.university_rate_saved', null, jsonb_build_object('rate_id', v, 'university_id', v_uni, 'programme_id', v_prog));
  -- enrollments waiting for a rate get booked now
  perform b2c.earning_book(e.id) from b2c.enrollments e
   where e.university_id = v_uni and e.status in ('reported', 'verified') and e.enrolled_on >= v_from
     and not exists (select 1 from b2c.earnings x where x.enrollment_id = e.id);
  return v;
end $f$;

create or replace function b2c.university_rate_retire(p_id bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  update b2c.university_rates set retired_at = now(), note = note || ' · retired: ' || p_reason where id = p_id and retired_at is null;
  perform b2c.log('money.university_rate_retired', null, jsonb_build_object('rate_id', p_id, 'reason', p_reason));
end $f$;

create or replace function b2c.university_billing_save(p jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  insert into b2c.university_billing as b (university_id, legal_name, gstin, address, state_code, email, refund_days, payment_terms_days, actor_id)
  values ((p ->> 'university_id')::bigint, p ->> 'legal_name', nullif(upper(trim(p ->> 'gstin')), ''), p ->> 'address', nullif(p ->> 'state_code', ''),
          nullif(lower(trim(p ->> 'email')), ''), nullif(p ->> 'refund_days', '')::int, nullif(p ->> 'payment_terms_days', '')::int, me)
  on conflict (university_id) do update set legal_name = excluded.legal_name, gstin = excluded.gstin, address = excluded.address, state_code = excluded.state_code,
     email = excluded.email, refund_days = excluded.refund_days, payment_terms_days = excluded.payment_terms_days, updated_at = now(), actor_id = me;
  perform b2c.log('money.university_billing_saved', null, p);
end $f$;

/* The Admin links an enrollment typed as text to the catalogue; open lines are rebooked. */
create or replace function b2c.enrollment_link(p_id bigint, p_university bigint, p_programme bigint default null, p_fee_first_year numeric default null)
returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if not exists (select 1 from public.catalog_universities where id = p_university) then raise exception 'pick a university from the catalogue'; end if;
  if p_programme is not null and not exists (select 1 from public.catalog_programs where id = p_programme and university_id = p_university) then
    raise exception 'that programme is not at this university';
  end if;
  update b2c.enrollments set university_id = p_university, programme_id = p_programme, fee_first_year = coalesce(p_fee_first_year, fee_first_year), updated_at = now() where id = p_id;
  perform b2c.money_rebook(p_id, 'linked to the catalogue');
end $f$;

/* Reverse the open university lines and book again at today's rate for the enrollment date (and, from b20, the
   counsellor's unsettled lines). Lines already invoiced keep their invoice; the reversal goes on the next one. */
create or replace function b2c.money_rebook(p_id bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('money');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  perform b2c.earning_reverse(p_id, 'reversal', 'rebook: ' || p_reason);
  perform b2c.earning_book(p_id, 'rebook: ' || p_reason);
end $f$;

-- ---------- period close (tiers) ----------
/* Settles tiered bookings of a university's month at the final conversion; the difference is a tier_adjust line. */
create or replace function b2c.period_close(p_university bigint, p_period date, p_leads int default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v_period date := date_trunc('month', p_period)::date; c jsonb; x record; r b2c.university_rates; t jsonb;
        v_pct numeric; v_amt numeric; g jsonb; n int := 0; v_gst numeric := coalesce((b2c.setting('money') ->> 'gst_pct')::numeric, 18);
begin
  if v_period >= date_trunc('month', current_date)::date then raise exception 'a month can be closed once it is over'; end if;
  if exists (select 1 from b2c.period_closes where university_id = p_university and period = v_period) then raise exception 'this month is already closed'; end if;
  if coalesce(b2c.setting('money') ->> 'tier_denominator', '') = 'manual' and p_leads is null then raise exception 'enter the number of leads for the month'; end if;
  c := b2c.period_conversion(p_university, v_period, p_leads);
  for x in
    select e.enrollment_id, (array_agg(e.snapshot order by e.id desc) filter (where e.kind = 'booking'))[1] as snap, sum(e.gross) as open_gross,
           max(e.base_amount) as base, bool_or(e.gst_inclusive) as incl, max(e.realised_at) as realised, bool_or(e.is_test) as test
      from b2c.earnings e
     where e.university_id = p_university and e.period = v_period
     group by e.enrollment_id
  loop
    continue when x.snap is null or x.snap ->> 'rate_type' <> 'tiered' or coalesce(x.open_gross, 0) = 0;
    select * into r from b2c.university_rates where id = (x.snap ->> 'rate_id')::bigint;
    t := b2c.tier_pick(r.tiers, (c ->> 'conversion')::numeric);
    v_pct := (t ->> 'value')::numeric;
    v_amt := x.base * v_pct / 100;
    g := b2c.gst_split(v_amt, x.incl, v_gst);
    if round((g ->> 'gross')::numeric - x.open_gross, 2) <> 0 then
      insert into b2c.earnings (enrollment_id, university_id, kind, period, base_amount, rate_pct, gross, gst, net, gst_inclusive, snapshot, realised_at, is_test, reason, actor_id)
      select x.enrollment_id, p_university, 'tier_adjust', v_period, x.base, v_pct,
             (g ->> 'gross')::numeric - x.open_gross,
             ((g ->> 'gross')::numeric - x.open_gross) - round(((g ->> 'gross')::numeric - x.open_gross) / (1 + v_gst / 100), 2),
             round(((g ->> 'gross')::numeric - x.open_gross) / (1 + v_gst / 100), 2),
             x.incl, jsonb_build_object('rate_id', r.id, 'tier', t, 'conversion', c, 'provisional', false, 'period_close', true), x.realised, x.test, 'period close', me;
      n := n + 1;
    end if;
  end loop;
  insert into b2c.period_closes (university_id, period, leads, verified, conversion, denominator, adjustments, closed_by)
  values (p_university, v_period, (c ->> 'leads')::int, (c ->> 'verified')::int, (c ->> 'conversion')::numeric,
          case when p_leads is not null then 'manual' else coalesce(b2c.setting('money') ->> 'tier_denominator', 'university_leads') end, n, me);
  perform b2c.log('money.period_closed', null, jsonb_build_object('university_id', p_university, 'period', v_period, 'conversion', c, 'adjustments', n));
  return c || jsonb_build_object('adjustments', n);
end $f$;

-- ---------- invoices ----------
create or replace function b2c.fin_year(p_on date) returns text language sql immutable set search_path = '' as $f$
  select case when extract(month from p_on) >= 4 then extract(year from p_on)::int || '-' || lpad(((extract(year from p_on)::int + 1) % 100)::text, 2, '0')
              else (extract(year from p_on)::int - 1) || '-' || lpad((extract(year from p_on)::int % 100)::text, 2, '0') end
$f$;

/* A draft invoice for a university: every realised line not yet invoiced (bookings, tier adjustments, reversals).
   p_test: an invoice of test leads only (test mode), numbered in its own TEST- series. */
create or replace function b2c.invoice_draft(p_university bigint, p_upto date default null, p_test boolean default false) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); m jsonb := b2c.setting('money'); b b2c.university_billing; v bigint; n int;
begin
  select * into b from b2c.university_billing where university_id = p_university;
  if exists (select 1 from b2c.invoices where university_id = p_university and status = 'draft' and is_test = p_test) then raise exception 'this university already has a draft invoice'; end if;
  insert into b2c.invoices (university_id, is_test, billing, sac, gst_pct, supply, created_by)
  values (p_university, p_test,
          jsonb_build_object('eduwit', jsonb_build_object('name', m ->> 'eduwit_legal_name', 'gstin', m ->> 'eduwit_gstin', 'address', m ->> 'eduwit_address', 'state_code', m ->> 'eduwit_state_code'),
                             'university', jsonb_build_object('name', coalesce(b.legal_name, (select name from public.catalog_universities where id = p_university)),
                                                              'gstin', b.gstin, 'address', b.address, 'state_code', b.state_code, 'email', b.email)),
          m ->> 'sac', coalesce((m ->> 'gst_pct')::numeric, 18),
          case when b.state_code is not null and b.state_code = m ->> 'eduwit_state_code' then 'intra' else 'inter' end, me)
  returning id into v;
  insert into b2c.invoice_lines (invoice_id, earning_id, enrollment_id, description, net, gst, gross)
  select v, e.id, e.enrollment_id,
         left(coalesce(r.record -> 'student' ->> 'name', 'Student') || ' · ' || en.programme || ' · enrolled ' || to_char(en.enrolled_on, 'DD Mon YYYY')
              || case e.kind when 'tier_adjust' then ' · tier adjustment' when 'reversal' then ' · reversal' when 'refund' then ' · refund' else '' end, 300),
         e.net, e.gst, e.gross
    from b2c.earnings e join b2c.enrollments en on en.id = e.enrollment_id left join b2c.lead_records r on r.lead_id = en.lead_id
   where e.university_id = p_university and e.realised_at is not null and e.invoice_id is null and (p_upto is null or e.period <= p_upto)
     and e.is_test = p_test;
  get diagnostics n = row_count;
  if n = 0 then
    update b2c.invoices set status = 'discarded', updated_at = now() where id = v;
    raise exception 'nothing to invoice: no verified, uninvoiced enrollments for this university';
  end if;
  update b2c.earnings e set invoice_id = v from b2c.invoice_lines l where l.invoice_id = v and l.earning_id = e.id;
  update b2c.invoices i set net = s.net, gst = s.gst, gross = s.gross, updated_at = now()
    from (select sum(net) net, sum(gst) gst, sum(gross) gross from b2c.invoice_lines where invoice_id = v) s where i.id = v;
  return v;
end $f$;

create or replace function b2c.invoice_discard(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if not exists (select 1 from b2c.invoices where id = p_id and status = 'draft') then raise exception 'only a draft can be discarded'; end if;
  update b2c.earnings set invoice_id = null where invoice_id = p_id;
  update b2c.invoices set status = 'discarded', updated_at = now() where id = p_id;
end $f$;

/* Approval gives the number: gapless within the series for the financial year of the issue date. */
create or replace function b2c.invoice_approve(p_id bigint, p_issue date default null) returns text language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); i b2c.invoices; m jsonb := b2c.setting('money'); v_issue date := coalesce(p_issue, current_date); v_series text; v_n int; v_num text;
begin
  select * into i from b2c.invoices where id = p_id for update;
  if i.id is null or i.status <> 'draft' then raise exception 'only a draft can be approved'; end if;
  if i.kind = 'invoice' and (coalesce(m ->> 'eduwit_gstin', '') = '' or coalesce(i.billing -> 'university' ->> 'name', '') = '') then
    raise exception 'set Eduwit''s GSTIN (Settings → money) and the university''s billing details first';
  end if;
  v_series := case when i.is_test then 'TEST-' else '' end || case when i.kind = 'credit_note' then coalesce(m ->> 'credit_prefix', 'EDW-CN') else coalesce(m ->> 'invoice_prefix', 'EDW') end || '/' || b2c.fin_year(v_issue);
  insert into b2c.invoice_counters (series, last) values (v_series, 1) on conflict (series) do update set last = b2c.invoice_counters.last + 1 returning last into v_n;
  v_num := v_series || '/' || lpad(v_n::text, 4, '0');
  update b2c.invoices set number = v_num, status = 'approved', issue_date = v_issue, approved_by = me, approved_at = now(),
         due_on = v_issue + coalesce((select payment_terms_days from b2c.university_billing where university_id = i.university_id), (m ->> 'payment_terms_days')::int, 30),
         updated_at = now()
   where id = p_id;
  perform b2c.log('money.invoice_approved', null, jsonb_build_object('invoice_id', p_id, 'number', v_num, 'gross', i.gross));
  return v_num;
end $f$;

create or replace function b2c.invoice_mark_sent(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  update b2c.invoices set status = case when status = 'approved' then 'sent' else status end, sent_at = coalesce(sent_at, now()), updated_at = now()
   where id = p_id and status in ('approved', 'sent', 'part_paid');
  if not found then raise exception 'approve the invoice first'; end if;
end $f$;

/* Cancelling an issued invoice raises a credit note for it; its lines can then be invoiced again. */
create or replace function b2c.invoice_cancel(p_id bigint, p_reason text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); i b2c.invoices; v bigint;
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  select * into i from b2c.invoices where id = p_id for update;
  if i.id is null or i.kind <> 'invoice' or i.status not in ('approved', 'sent') then raise exception 'only an approved or sent invoice with no payment can be cancelled'; end if;
  if exists (select 1 from b2c.receipt_allocations where invoice_id = p_id) then raise exception 'this invoice has payments: record a credit note against the balance instead'; end if;
  insert into b2c.invoices (kind, university_id, credit_of, is_test, billing, sac, gst_pct, supply, net, gst, gross, created_by)
  values ('credit_note', i.university_id, i.id, i.is_test, i.billing, i.sac, i.gst_pct, i.supply, -i.net, -i.gst, -i.gross, me) returning id into v;
  insert into b2c.invoice_lines (invoice_id, earning_id, enrollment_id, description, net, gst, gross)
  select v, null, l.enrollment_id, 'Credit: ' || l.description, -l.net, -l.gst, -l.gross from b2c.invoice_lines l where l.invoice_id = p_id;
  update b2c.invoices set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason, updated_at = now() where id = p_id;
  update b2c.earnings set invoice_id = null where invoice_id = p_id;
  perform b2c.invoice_approve(v);
  perform b2c.log('money.invoice_cancelled', null, jsonb_build_object('invoice_id', p_id, 'credit_note_id', v, 'reason', p_reason));
  return v;
end $f$;

create or replace function b2c.invoice_paid(p_id bigint) returns numeric language sql stable security definer set search_path = '' as $f$
  select coalesce(sum(amount), 0) from b2c.receipt_allocations where invoice_id = p_id
$f$;

create or replace function b2c.invoice_restatus(p_id bigint) returns void language sql security definer set search_path = '' as $f$
  update b2c.invoices i set status = case when b2c.invoice_paid(i.id) >= i.gross - 0.5 then 'paid' when b2c.invoice_paid(i.id) > 0 then 'part_paid'
                                          when i.sent_at is not null then 'sent' else 'approved' end, updated_at = now()
   where i.id = p_id and i.kind = 'invoice' and i.status in ('approved', 'sent', 'part_paid', 'paid')
$f$;

-- ---------- receipts ----------
/* A payment from a university: bank amount plus TDS settle invoices. An exact match to one invoice's balance first,
   else the oldest first. What is left stays unallocated on the receipt. */
create or replace function b2c.receipt_record(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v bigint; v_left numeric; v_uni bigint := (p ->> 'university_id')::bigint; inv record; v_take numeric; n int := 0;
        v_target bigint := nullif(p ->> 'invoice_id', '')::bigint;
begin
  if coalesce(trim(p ->> 'reference'), '') = '' then raise exception 'enter the bank reference'; end if;
  if coalesce((p ->> 'amount')::numeric, 0) <= 0 then raise exception 'enter the amount received'; end if;
  insert into b2c.receipts (university_id, received_on, amount, tds, reference, note, created_by)
  values (v_uni, coalesce(nullif(p ->> 'received_on', '')::date, current_date), (p ->> 'amount')::numeric, coalesce(nullif(p ->> 'tds', '')::numeric, 0),
          trim(p ->> 'reference'), p ->> 'note', me)
  returning id, amount + tds into v, v_left;
  if v_target is null then
    select i.id into v_target from b2c.invoices i
     where i.university_id = v_uni and i.kind = 'invoice' and i.status in ('approved', 'sent', 'part_paid')
       and abs((i.gross - b2c.invoice_paid(i.id)) - v_left) <= 1
     order by i.issue_date, i.id limit 1;
  end if;
  for inv in select i.id, i.gross - b2c.invoice_paid(i.id) as bal from b2c.invoices i
              where i.university_id = v_uni and i.kind = 'invoice' and i.status in ('approved', 'sent', 'part_paid')
              order by (i.id = v_target) desc, i.issue_date, i.id loop
    exit when v_left <= 0;
    continue when inv.bal <= 0;
    v_take := least(inv.bal, v_left);
    if abs(inv.bal - v_left) <= 1 then v_take := v_left; end if;
    insert into b2c.receipt_allocations (receipt_id, invoice_id, amount) values (v, inv.id, v_take);
    v_left := v_left - v_take;
    perform b2c.invoice_restatus(inv.id);
    n := n + 1;
  end loop;
  update b2c.receipts set unallocated = greatest(v_left, 0) where id = v;
  perform b2c.log('money.receipt_recorded', null, jsonb_build_object('receipt_id', v, 'university_id', v_uni, 'amount', p ->> 'amount', 'tds', p ->> 'tds', 'invoices', n));
  return jsonb_build_object('receipt_id', v, 'invoices', n, 'unallocated', greatest(v_left, 0));
end $f$;

/* Outstanding invoices by age past their due date. */
create or replace function b2c.receivables(p_university bigint default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return (with o as (
      select i.id, i.number, i.university_id, un.name as university, i.issue_date, i.due_on, i.gross, i.gross - b2c.invoice_paid(i.id) as balance,
             greatest(current_date - i.due_on, 0) as days_late, i.status, i.reminded_at
        from b2c.invoices i left join public.catalog_universities un on un.id = i.university_id
       where i.kind = 'invoice' and i.status in ('approved', 'sent', 'part_paid') and not i.is_test and (p_university is null or i.university_id = p_university))
    select jsonb_build_object(
      'total', coalesce(sum(balance), 0),
      'buckets', jsonb_build_object('current', coalesce(sum(balance) filter (where days_late = 0), 0), 'd1_30', coalesce(sum(balance) filter (where days_late between 1 and 30), 0),
                                    'd31_60', coalesce(sum(balance) filter (where days_late between 31 and 60), 0), 'd61_90', coalesce(sum(balance) filter (where days_late between 61 and 90), 0),
                                    'd90_plus', coalesce(sum(balance) filter (where days_late > 90), 0)),
      'invoices', coalesce(jsonb_agg(to_jsonb(o) order by o.days_late desc, o.issue_date), '[]'),
      'unallocated', (select coalesce(sum(unallocated), 0) from b2c.receipts r where p_university is null or r.university_id = p_university))
    from o);
end $f$;

-- ---------- statements ----------
/* A university's statement (rows parsed by the app from its CSV): each row is matched to an enrollment by reference
   (the enrollment number) or by student and programme, then compared with what Eduwit booked. Booked enrollments the
   statement does not list are the fourth pile. */
create or replace function b2c.statement_import(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v bigint; x jsonb; i int := 0; v_uni bigint := (p ->> 'university_id')::bigint;
        v_from date := (p ->> 'period_from')::date; v_to date := (p ->> 'period_to')::date; v_en bigint; v_exp numeric;
        v_tol numeric := coalesce((b2c.setting('money') ->> 'statement_tolerance')::numeric, 1); v_ref text;
begin
  if v_from is null or v_to is null or v_to < v_from then raise exception 'give the statement''s period'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') > 5000 then raise exception 'between 1 and 5,000 rows'; end if;
  insert into b2c.statement_imports (university_id, period_from, period_to, file_name, created_by) values (v_uni, v_from, v_to, left(p ->> 'file_name', 200), me) returning id into v;
  for x in select * from jsonb_array_elements(p -> 'rows') loop
    i := i + 1;
    v_ref := nullif(regexp_replace(coalesce(x ->> 'ref', ''), '[^0-9]', '', 'g'), '');
    v_en := null;
    if v_ref is not null and length(v_ref) < 12 then
      select e.id into v_en from b2c.enrollments e where e.id = v_ref::bigint and e.university_id = v_uni;
    end if;
    if v_en is null and coalesce(trim(x ->> 'student'), '') <> '' then
      select e.id into v_en from b2c.enrollments e left join b2c.lead_records r on r.lead_id = e.lead_id
       where e.university_id = v_uni and e.enrolled_on between v_from and v_to
         and lower(trim(r.record -> 'student' ->> 'name')) = lower(trim(x ->> 'student'))
         and (coalesce(trim(x ->> 'programme'), '') = '' or e.programme ilike '%' || trim(x ->> 'programme') || '%' or trim(x ->> 'programme') ilike '%' || e.programme || '%')
         and not exists (select 1 from b2c.statement_rows s where s.import_id = v and s.enrollment_id = e.id)
       order by e.enrolled_on limit 1;
    end if;
    v_exp := (select sum(gross) from b2c.earnings where enrollment_id = v_en);
    insert into b2c.statement_rows (import_id, row_no, ref, student, programme, amount, enrollment_id, expected, pile, raw)
    values (v, i, left(x ->> 'ref', 60), left(x ->> 'student', 200), left(x ->> 'programme', 200), nullif(x ->> 'amount', '')::numeric, v_en, v_exp,
            case when v_en is null then 'university_only' when abs(coalesce(nullif(x ->> 'amount', '')::numeric, 0) - coalesce(v_exp, 0)) <= v_tol then 'matched' else 'mismatch' end,
            x);
  end loop;
  update b2c.statement_imports set summary = b2c.statement_piles(v) - 'eduwit_only_rows' where id = v;
  return jsonb_build_object('import_id', v) || b2c.statement_piles(v);
end $f$;

create or replace function b2c.statement_piles(p_import bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare im b2c.statement_imports;
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  select * into im from b2c.statement_imports where id = p_import;
  return jsonb_build_object(
    'matched', (select count(*) from b2c.statement_rows where import_id = p_import and pile = 'matched'),
    'mismatch', (select count(*) from b2c.statement_rows where import_id = p_import and pile = 'mismatch'),
    'university_only', (select count(*) from b2c.statement_rows where import_id = p_import and pile = 'university_only'),
    'eduwit_only', (select count(*) from b2c.enrollments e where e.university_id = im.university_id and e.enrolled_on between im.period_from and im.period_to
                      and e.status = 'verified' and not exists (select 1 from b2c.statement_rows s where s.import_id = p_import and s.enrollment_id = e.id)),
    'rows', (select coalesce(jsonb_agg(to_jsonb(s) - 'raw' order by s.row_no), '[]') from b2c.statement_rows s where s.import_id = p_import),
    'eduwit_only_rows', (select coalesce(jsonb_agg(jsonb_build_object('enrollment_id', e.id, 'lead_id', e.lead_id, 'student', r.record -> 'student' ->> 'name', 'programme', e.programme,
                           'enrolled_on', e.enrolled_on, 'expected', (select sum(gross) from b2c.earnings x where x.enrollment_id = e.id)) order by e.enrolled_on), '[]')
                           from b2c.enrollments e left join b2c.lead_records r on r.lead_id = e.lead_id
                          where e.university_id = im.university_id and e.enrolled_on between im.period_from and im.period_to and e.status = 'verified'
                            and not exists (select 1 from b2c.statement_rows s where s.import_id = p_import and s.enrollment_id = e.id)));
end $f$;

-- ---------- read ----------
create or replace function b2c.invoice_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return (select to_jsonb(i) || jsonb_build_object('paid', b2c.invoice_paid(i.id), 'university', un.name,
            'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]') from b2c.invoice_lines l where l.invoice_id = i.id),
            'receipts', (select coalesce(jsonb_agg(jsonb_build_object('receipt_id', r.id, 'received_on', r.received_on, 'reference', r.reference, 'amount', a.amount) order by r.received_on), '[]')
                           from b2c.receipt_allocations a join b2c.receipts r on r.id = a.receipt_id where a.invoice_id = i.id))
            from b2c.invoices i left join public.catalog_universities un on un.id = i.university_id where i.id = p_id);
end $f$;

-- ---------- grants ----------
do $d$
declare t text;
begin
  foreach t in array array['university_billing', 'university_rates', 'earnings', 'period_closes', 'invoice_counters', 'invoices', 'invoice_lines', 'receipts',
                           'receipt_allocations', 'statement_imports', 'statement_rows'] loop
    execute format('alter table b2c.%I enable row level security', t);
    execute format('grant select on b2c.%I to authenticated', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = t and policyname = 'money read') then
      execute format('create policy "money read" on b2c.%I for select to authenticated using ((select b2c.can(''read_money'')))', t);
    end if;
  end loop;
end $d$;
grant execute on function b2c.university_rate_save(jsonb), b2c.university_rate_retire(bigint, text), b2c.university_billing_save(jsonb),
  b2c.enrollment_link(bigint, bigint, bigint, numeric), b2c.money_rebook(bigint, text), b2c.period_close(bigint, date, integer), b2c.invoice_draft(bigint, date, boolean),
  b2c.invoice_discard(bigint), b2c.invoice_approve(bigint, date), b2c.invoice_mark_sent(bigint), b2c.invoice_cancel(bigint, text), b2c.receipt_record(jsonb),
  b2c.receivables(bigint), b2c.statement_import(jsonb), b2c.statement_piles(bigint), b2c.invoice_get(bigint), b2c.period_conversion(bigint, date, integer) to authenticated;
revoke execute on function b2c.earning_book(bigint, text), b2c.earning_reverse(bigint, text, text), b2c.enrollments_money(), b2c.enrollments_catalog(),
  b2c.invoice_restatus(bigint), b2c.period_leads(bigint, date), b2c.catalog_ids(text, text), b2c.fee_base_amount(bigint, text) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
