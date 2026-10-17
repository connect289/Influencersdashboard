-- Phase 7: the ledger, Eduwit commission receipts, payouts, GST invoices and TDS (spec 11, 6.3; ERD §7; D-06;
-- INTEGRATION_CONTRACTS.md §3).
--
-- The ledger is append-only: amounts, types, directions and keys never change (a trigger refuses it), corrections are
-- reversal entries, and the status moves only through inf.ledger_transition(), which derives it from the entry's
-- facts exactly as lib/ledger/lifecycle.ts does (supabase/tests/020_ledger_status_matrix.sql is generated from the
-- TypeScript cases). The compensation engine runs in the app (lib/ledger/plan.ts): inf.ledger_facts() gathers a deal's
-- facts read-only, inf.ledger_apply() writes the outcome. No money moves automatically: payouts are prepared,
-- exported for the bank and marked paid by Finance.
--
-- Shared tables are only read (b2b.earnings, b2b.invoices, public.enrollments, public.b2c_enrollment_money_v,
-- public.catalog_programs), from security definer functions; nothing outside schema inf is created or changed.

-- ---------------------------------------------------------------------------------------------------------------
-- Calendar helpers (IST dates, Indian financial year 1 Apr – 31 Mar)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.ist_date(p timestamptz) returns date
language sql immutable set search_path = '' as $$ select (p at time zone 'Asia/Kolkata')::date $$;

create or replace function inf.fy_of(p date) returns text
language sql immutable set search_path = '' as $$
  select case when extract(month from p) >= 4
              then extract(year from p)::int::text || '-' || lpad(((extract(year from p)::int + 1) % 100)::text, 2, '0')
              else (extract(year from p)::int - 1)::text || '-' || lpad((extract(year from p)::int % 100)::text, 2, '0') end
$$;

create or replace function inf.fy_quarter_of(p date) returns text
language sql immutable set search_path = '' as $$
  select case when extract(month from p) between 4 and 6 then 'Q1' when extract(month from p) between 7 and 9 then 'Q2'
              when extract(month from p) between 10 and 12 then 'Q3' else 'Q4' end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Ledger
-- ---------------------------------------------------------------------------------------------------------------
create table inf.ledger_entries (
  id               bigint generated always as identity primary key,
  creator_id       uuid not null references inf.creators (id) on delete restrict,
  deal_id          uuid references inf.deals (id) on delete restrict,
  deal_version_id  uuid references inf.deal_versions (id) on delete restrict,
  type             text not null check (type in ('fixed_fee', 'milestone', 'commission', 'bonus', 'usage_fee', 'exclusivity_fee',
                                                 'reimbursement', 'penalty', 'clawback', 'adjustment', 'reversal', 'tds', 'gst', 'payout')),
  direction        text not null check (direction in ('credit', 'debit')),
  amount_paise     bigint not null check (amount_paise >= 0),
  confirmed_paise  bigint not null default 0 check (confirmed_paise >= 0 and confirmed_paise <= amount_paise),
  paid_paise       bigint not null default 0 check (paid_paise >= 0),
  status           text not null check (status in ('accrued', 'confirmed', 'payable', 'in_batch', 'paid', 'on_hold', 'reversed', 'clawed_back')),
  source           text not null check (source in ('engine', 'penalty', 'revision_fee', 'adjustment', 'reversal', 'payout')),
  event_key        text not null unique check (char_length(event_key) <= 400),
  rule_id          text,
  subject          text,
  -- The credited lead the entry is about (commission, per-lead and per-enrolment lines).
  attribution_id   uuid references inf.lead_attributions (id) on delete set null,
  tds_component    text check (tds_component in ('commission', 'fixed_fee', 'milestone', 'bonus', 'usage_fee', 'exclusivity_fee',
                                                 'reimbursement', 'non_cash')),
  period           text not null check (period ~ '^\d{4}-\d{2}$'),
  due_on           date not null,
  reverses_id      bigint unique references inf.ledger_entries (id) on delete restrict,
  reversed_by_id   bigint references inf.ledger_entries (id) on delete restrict,
  payout_id        uuid,
  held             boolean not null default false,
  hold_reason      text check (char_length(hold_reason) <= 500),
  note             text check (char_length(note) <= 500),
  posted_at        timestamptz not null default now(),
  posted_by        uuid default auth.uid(),
  updated_at       timestamptz not null default now(),
  check ((type in ('tds', 'gst', 'payout', 'reversal')) = (tds_component is null) or type = 'reversal'),
  check ((type = 'reversal') = (reverses_id is not null)),
  check (type <> 'reversal' or paid_paise <= confirmed_paise)
);
create index ledger_entries_creator_idx on inf.ledger_entries (creator_id, posted_at desc);
create index ledger_entries_deal_idx on inf.ledger_entries (deal_id, posted_at desc);
create index ledger_entries_status_idx on inf.ledger_entries (status, due_on);
create index ledger_entries_attribution_idx on inf.ledger_entries (attribution_id) where attribution_id is not null;
create index ledger_entries_payout_idx on inf.ledger_entries (payout_id) where payout_id is not null;

create table inf.ledger_status_events (
  id           bigint generated always as identity primary key,
  entry_id     bigint not null references inf.ledger_entries (id) on delete restrict,
  from_status  text,
  to_status    text not null,
  actor_id     uuid default auth.uid(),
  reason       text check (char_length(reason) <= 500),
  at           timestamptz not null default now()
);
create index ledger_status_events_entry_idx on inf.ledger_status_events (entry_id, at);
create trigger ledger_status_events_append_only before update or delete on inf.ledger_status_events
  for each row execute function inf.forbid_mutation();

-- Amounts and identity never change; status, confirmation, payment and holds change only inside the ledger
-- functions, which switch the flag inf.ledger_writer on and back to its previous value before they return
-- (inf.ledger_writer_on / inf.ledger_writer_restore; nested calls keep it on, a failed call rolls it back).
-- Entries are never deleted.
create or replace function inf.ledger_writer_on() returns text
language plpgsql set search_path = '' as $$
declare v_prev text := coalesce(current_setting('inf.ledger_writer', true), '');
begin
  perform set_config('inf.ledger_writer', 'on', true);
  return v_prev;
end $$;

create or replace function inf.ledger_writer_restore(p_prev text) returns void
language sql set search_path = '' as $$ select set_config('inf.ledger_writer', coalesce(p_prev, ''), true); $$;

create or replace function inf.ledger_entries_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'ledger entries are never deleted' using errcode = '42501'; end if;
  if new.creator_id is distinct from old.creator_id or new.deal_id is distinct from old.deal_id
     or new.deal_version_id is distinct from old.deal_version_id or new.type is distinct from old.type
     or new.direction is distinct from old.direction or new.amount_paise is distinct from old.amount_paise
     or new.source is distinct from old.source or new.event_key is distinct from old.event_key
     or new.rule_id is distinct from old.rule_id or new.subject is distinct from old.subject
     or new.tds_component is distinct from old.tds_component or new.period is distinct from old.period
     or new.due_on is distinct from old.due_on or new.reverses_id is distinct from old.reverses_id
     or new.posted_at is distinct from old.posted_at or new.posted_by is distinct from old.posted_by
     or new.payout_id is distinct from old.payout_id or new.attribution_id is distinct from old.attribution_id then
    raise exception 'ledger amounts are immutable: post a reversal instead' using errcode = '42501';
  end if;
  if coalesce(current_setting('inf.ledger_writer', true), '') <> 'on' then
    raise exception 'ledger entries change only through the ledger functions' using errcode = '42501';
  end if;
  if new.confirmed_paise < old.confirmed_paise then
    raise exception 'confirmation never goes backwards' using errcode = '23514';
  end if;
  if old.reversed_by_id is not null and new.reversed_by_id is distinct from old.reversed_by_id then
    raise exception 'an entry is reversed once' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger ledger_entries_guard before update or delete on inf.ledger_entries
  for each row execute function inf.ledger_entries_guard();
create trigger ledger_entries_audit after insert or update on inf.ledger_entries
  for each row execute function inf.audit_row('ledger_entry');

-- Mirror of statusOf() in lib/ledger/lifecycle.ts.
create or replace function inf.ledger_status_of(p_amount bigint, p_confirmed bigint, p_paid bigint, p_in_open_batch boolean,
                                                p_held boolean, p_reversed boolean, p_is_reversal boolean, p_due_on date, p_today date)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_is_reversal then
      case when p_confirmed = 0 then 'reversed' when p_paid >= p_confirmed then 'paid' when p_in_open_batch then 'in_batch'
           when p_held then 'on_hold' else 'payable' end
    when p_reversed then case when p_paid > 0 then 'clawed_back' else 'reversed' end
    when p_amount > 0 and p_paid >= p_amount then 'paid'
    when p_in_open_batch then 'in_batch'
    when p_held then 'on_hold'
    when p_confirmed > p_paid and p_due_on <= p_today then 'payable'
    when p_confirmed >= p_amount then 'confirmed'
    else 'accrued' end
$$;

-- Mirror of ALLOWED_TRANSITIONS.
create or replace function inf.ledger_can_transition(p_from text, p_to text) returns boolean
language sql immutable set search_path = '' as $$
  select p_from = p_to or p_to = any (case p_from
    when 'accrued' then array['confirmed', 'payable', 'on_hold', 'reversed', 'clawed_back']
    when 'confirmed' then array['payable', 'on_hold', 'reversed', 'clawed_back']
    when 'payable' then array['in_batch', 'on_hold', 'reversed', 'clawed_back']
    when 'in_batch' then array['paid', 'accrued', 'confirmed', 'payable', 'on_hold']
    when 'paid' then array['clawed_back', 'payable']
    when 'on_hold' then array['accrued', 'confirmed', 'payable', 'reversed', 'clawed_back']
    else array[]::text[] end)
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Payouts (declared before the lifecycle functions that read them)
-- ---------------------------------------------------------------------------------------------------------------
create sequence inf.payout_batch_ref_seq;
create sequence inf.payout_ref_seq;
create sequence inf.payout_statement_ref_seq;

create table inf.payout_batches (
  id                  uuid primary key default gen_random_uuid(),
  ref                 text not null unique,
  status              text not null default 'draft' check (status in ('draft', 'approved', 'processing', 'paid', 'cancelled')),
  filters             jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  note                text check (char_length(note) <= 500),
  created_by          uuid not null default auth.uid(),
  created_at          timestamptz not null default now(),
  approved_by         uuid,
  approved_at         timestamptz,
  second_approved_by  uuid,
  second_approved_at  timestamptz,
  exported_by         uuid,
  exported_at         timestamptz,
  export_count        int not null default 0,
  cancelled_reason    text check (char_length(cancelled_reason) <= 500),
  updated_at          timestamptz not null default now(),
  check (second_approved_by is null or second_approved_by <> approved_by)
);
create trigger payout_batches_touch before update on inf.payout_batches for each row execute function inf.touch_updated_at();
create trigger payout_batches_audit after insert or update on inf.payout_batches for each row execute function inf.audit_row('payout_batch');

create table inf.payouts (
  id               uuid primary key default gen_random_uuid(),
  ref              text not null unique check (ref ~ '^PO-\d{4}-\d{2}-\d{5}$'),
  batch_id         uuid not null references inf.payout_batches (id) on delete restrict,
  creator_id       uuid not null references inf.creators (id) on delete restrict,
  payee            text not null default 'creator' check (payee in ('creator')),
  gross_paise      bigint not null check (gross_paise > 0),
  gst_base_paise   bigint not null default 0 check (gst_base_paise >= 0),
  gst_paise        bigint not null default 0 check (gst_paise >= 0),
  tds_paise        bigint not null default 0 check (tds_paise >= 0),
  eduwit_tds_paise bigint not null default 0 check (eduwit_tds_paise >= 0),
  net_paise        bigint not null check (net_paise > 0),
  sections         jsonb not null default '[]'::jsonb check (jsonb_typeof(sections) = 'array'),
  needs_invoice    boolean not null default false,
  status           text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'removed', 'cancelled')),
  utr              text check (utr ~ '^[A-Z0-9]{12,22}$'),
  paid_on          date,
  status_reason    text check (char_length(status_reason) <= 500),
  advice_path      text check (advice_path ~ '^advice/[0-9a-f-]{36}/PO-\d{4}-\d{2}-\d{5}\.pdf$'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (net_paise = gross_paise + gst_paise - tds_paise),
  check ((status = 'paid') = (utr is not null and paid_on is not null)),
  unique (batch_id, creator_id)
);
create index payouts_creator_idx on inf.payouts (creator_id, created_at desc);
create trigger payouts_touch before update on inf.payouts for each row execute function inf.touch_updated_at();
create trigger payouts_audit after insert or update on inf.payouts for each row execute function inf.audit_row('payout');
alter table inf.ledger_entries add constraint ledger_entries_payout_fk foreign key (payout_id) references inf.payouts (id) on delete restrict;

create table inf.payout_items (
  payout_id     uuid not null references inf.payouts (id) on delete restrict,
  entry_id      bigint not null references inf.ledger_entries (id) on delete restrict,
  -- Signed: credits positive, debits (penalties, clawbacks, recoveries) negative.
  amount_paise  bigint not null check (amount_paise <> 0),
  primary key (payout_id, entry_id)
);
create index payout_items_entry_idx on inf.payout_items (entry_id);
create trigger payout_items_append_only before update or delete on inf.payout_items for each row execute function inf.forbid_mutation();

-- Claimed by a payout that is still pending in a batch that is not settled or cancelled.
create or replace function inf.ledger_in_open_batch(p_entry bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from inf.payout_items i join inf.payouts p on p.id = i.payout_id join inf.payout_batches b on b.id = p.batch_id
                  where i.entry_id = p_entry and p.status = 'pending' and b.status in ('draft', 'approved', 'processing'))
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Lifecycle: the only writer of ledger_entries.status
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.ledger_transition(p_entry bigint, p_reason text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  e inf.ledger_entries;
  v_to text;
  v_prev text;
begin
  select * into e from inf.ledger_entries where id = p_entry for update;
  if e.id is null then raise exception 'no such ledger entry' using errcode = '22023'; end if;
  v_to := inf.ledger_status_of(e.amount_paise, e.confirmed_paise, e.paid_paise, inf.ledger_in_open_batch(e.id), e.held,
                               e.reversed_by_id is not null, e.type = 'reversal', e.due_on, inf.ist_date(now()));
  if v_to = e.status then return v_to; end if;
  if not inf.ledger_can_transition(e.status, v_to) then
    raise exception 'ledger entry % cannot move from % to %', e.id, e.status, v_to using errcode = '23514';
  end if;
  v_prev := inf.ledger_writer_on();
  update inf.ledger_entries set status = v_to where id = e.id;
  perform inf.ledger_writer_restore(v_prev);
  insert into inf.ledger_status_events (entry_id, from_status, to_status, reason) values (e.id, e.status, v_to, left(p_reason, 500));
  return v_to;
end $$;

-- Inserts an entry with its derived status and logs the first status event.
create or replace function inf.ledger_post(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_status text;
begin
  v_status := inf.ledger_status_of((p ->> 'amount_paise')::bigint, coalesce((p ->> 'confirmed_paise')::bigint, 0),
                                   coalesce((p ->> 'paid_paise')::bigint, 0), false, false, false, p ->> 'type' = 'reversal',
                                   (p ->> 'due_on')::date, inf.ist_date(now()));
  insert into inf.ledger_entries (creator_id, deal_id, deal_version_id, type, direction, amount_paise, confirmed_paise, paid_paise, status,
                                  source, event_key, rule_id, subject, attribution_id, tds_component, period, due_on, reverses_id, payout_id, note)
  values ((p ->> 'creator_id')::uuid, nullif(p ->> 'deal_id', '')::uuid, nullif(p ->> 'deal_version_id', '')::uuid, p ->> 'type',
          p ->> 'direction', (p ->> 'amount_paise')::bigint, coalesce((p ->> 'confirmed_paise')::bigint, 0),
          coalesce((p ->> 'paid_paise')::bigint, 0), v_status, p ->> 'source', p ->> 'event_key', nullif(p ->> 'rule_id', ''),
          nullif(p ->> 'subject', ''), nullif(p ->> 'attribution_id', '')::uuid, nullif(p ->> 'tds_component', ''),
          coalesce(nullif(p ->> 'period', ''), to_char(inf.ist_date(now()), 'YYYY-MM')), (p ->> 'due_on')::date,
          nullif(p ->> 'reverses_id', '')::bigint, nullif(p ->> 'payout_id', '')::uuid, left(nullif(p ->> 'note', ''), 500))
  on conflict (event_key) do nothing
  returning id into v_id;
  if v_id is not null then
    insert into inf.ledger_status_events (entry_id, from_status, to_status, reason) values (v_id, null, v_status, 'posted');
  end if;
  return v_id;
end $$;

-- Daily: entries whose due date has come become payable (nightly job).
create or replace function inf.ledger_refresh_due() returns int
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_n int := 0;
begin
  for v_id in select id from inf.ledger_entries
               where status = 'confirmed' or (status = 'accrued' and confirmed_paise > paid_paise) loop
    if inf.ledger_transition(v_id, 'due') = 'payable' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Manual deal events: milestone releases and recorded breaches (they feed the engine)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.deal_manual_events (
  id          uuid primary key default gen_random_uuid(),
  deal_id     uuid not null references inf.deals (id) on delete restrict,
  kind        text not null check (kind in ('manual_release', 'breach')),
  ref         text check (ref ~ '^[a-z0-9_-]{1,40}\.[a-z0-9_-]{1,40}$'),
  reason      text not null check (char_length(reason) between 3 and 1000),
  at          timestamptz not null default now(),
  created_by  uuid not null default auth.uid(),
  check ((kind = 'manual_release') = (ref is not null))
);
create index deal_manual_events_deal_idx on inf.deal_manual_events (deal_id, at);
create unique index deal_manual_events_release_once_idx on inf.deal_manual_events (deal_id, ref) where kind = 'manual_release';
create trigger deal_manual_events_append_only before update or delete on inf.deal_manual_events for each row execute function inf.forbid_mutation();
create trigger deal_manual_events_audit after insert on inf.deal_manual_events for each row execute function inf.audit_row('deal_manual_event');

-- ---------------------------------------------------------------------------------------------------------------
-- Eduwit commission receipts (INTEGRATION_CONTRACTS §3): append-only history per enrolment
-- ---------------------------------------------------------------------------------------------------------------
create table inf.eduwit_commission_receipts (
  id                 bigint generated always as identity primary key,
  student_lead_id    bigint not null,
  enrollment_ref     text not null check (enrollment_ref ~ '^(b2b|b2c):\d+$'),
  gross_paise        bigint not null default 0,
  gst_paise          bigint not null default 0,
  net_paise          bigint not null default 0,
  received_paise     bigint not null default 0 check (received_paise >= 0),
  received_on        date,
  status             text not null check (status in ('expected', 'partly_received', 'received', 'reversed', 'withdrawn')),
  enrollment_status  text,
  source             text not null check (source in ('b2b', 'b2c', 'manual')),
  source_version     text not null,
  entered_by         uuid default auth.uid(),
  reason             text check (char_length(reason) <= 1000),
  created_at         timestamptz not null default now(),
  check (source <> 'manual' or char_length(reason) >= 3),
  unique (enrollment_ref, source, source_version)
);
create index eduwit_commission_receipts_ref_idx on inf.eduwit_commission_receipts (enrollment_ref, id desc);
create trigger eduwit_commission_receipts_append_only before update or delete on inf.eduwit_commission_receipts
  for each row execute function inf.forbid_mutation();
create trigger eduwit_commission_receipts_audit after insert on inf.eduwit_commission_receipts
  for each row execute function inf.audit_row('commission_receipt');

-- The receipt in force per enrolment: the latest manual entry (unless it was withdrawn), else the latest CRM row.
create or replace function inf.receipts_effective() returns setof inf.eduwit_commission_receipts
language sql stable security definer set search_path = '' as $$
  select distinct on (r.enrollment_ref) r.*
    from inf.eduwit_commission_receipts r
   where (r.source = 'manual' and r.status <> 'withdrawn'
          and r.id = (select max(m.id) from inf.eduwit_commission_receipts m where m.enrollment_ref = r.enrollment_ref and m.source = 'manual'))
      or (r.source <> 'manual' and not exists (
            select 1 from inf.eduwit_commission_receipts m where m.enrollment_ref = r.enrollment_ref and m.source = 'manual'
               and m.id = (select max(m2.id) from inf.eduwit_commission_receipts m2 where m2.enrollment_ref = r.enrollment_ref and m2.source = 'manual')
               and m.status <> 'withdrawn'))
   order by r.enrollment_ref, (r.source = 'manual') desc, r.id desc
$$;

-- Enqueues one ledger run per deal per minute (runs start after the minute closes, so a burst of events is one run).
create or replace function inf.ledger_enqueue(p_deal uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_at timestamptz := date_trunc('minute', now()) + interval '1 minute';
begin
  if p_deal is null or not exists (select 1 from inf.deal_versions v where v.deal_id = p_deal and v.state = 'accepted') then return; end if;
  perform inf.job_enqueue('ledger.run', jsonb_build_object('deal_id', p_deal, 'reason', left(p_reason, 80)), v_at,
                          'ledger:' || p_deal || ':' || to_char(v_at, 'YYYYMMDDHH24MI'));
end $$;

-- Copies commission received per enrolment from the CRMs for attributed leads (service role; called by the lead
-- sweep, so it only runs with LEAD_SYNC on). A new row is written only when something changed (source_version).
create or replace function inf.commission_receipts_sync() returns int
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_n int := 0;
  v_deal uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  for r in
    with leads as (
      select distinct a.student_lead_id from inf.lead_attributions a
       where a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last') and not a.is_test
    ),
    b2b as (
      select e.lead_id, 'b2b:' || e.id as ref, e.status as enrollment_status,
             round(coalesce(sum(x.gross_inr), 0) * 100)::bigint as gross,
             round(coalesce(sum(x.gst_inr), 0) * 100)::bigint as gst,
             round(coalesce(sum(x.net_inr), 0) * 100)::bigint as net,
             round(coalesce(sum(case when i.status = 'paid' then x.gross_inr
                                     when i.status = 'partly_paid' and coalesce(i.total_inr, 0) > 0
                                       then x.gross_inr * least(coalesce(i.received_inr, 0) / i.total_inr, 1)
                                     else 0 end), 0) * 100)::bigint as received,
             max(inf.ist_date(i.paid_at)) as received_on
        from public.enrollments e
        join leads l on l.student_lead_id = e.lead_id
        left join b2b.earnings x on x.enrollment_id = e.id and x.kind = 'commission'
        left join b2b.invoices i on i.id = x.invoice_id
       where e.source_product = 'b2b'
       group by e.id, e.lead_id, e.status
    ),
    b2c as (
      select m.lead_id, 'b2c:' || m.enrollment_id as ref, m.enrollment_status,
             round(coalesce(m.university_commission_gross, 0) * 100)::bigint as gross,
             round(coalesce(m.university_commission_gst, 0) * 100)::bigint as gst,
             round(coalesce(m.university_commission_net, 0) * 100)::bigint as net,
             case when m.university_commission_status = 'paid' then round(coalesce(m.university_commission_gross, 0) * 100)::bigint else 0 end as received,
             null::date as received_on
        from public.b2c_enrollment_money_v m
        join leads l on l.student_lead_id = m.lead_id
    ),
    src as (
      select *, 'b2b' as source from b2b union all select *, 'b2c' from b2c
    )
    select s.*,
           case when s.enrollment_status in ('refunded', 'cancelled') and s.received = 0 then 'reversed'
                when s.received > 0 and s.received >= s.gross then 'received'
                when s.received > 0 then 'partly_received'
                else 'expected' end as status,
           md5(concat_ws('|', s.gross, s.gst, s.net, s.received, s.received_on, s.enrollment_status)) as version
      from src s
  loop
    insert into inf.eduwit_commission_receipts (student_lead_id, enrollment_ref, gross_paise, gst_paise, net_paise, received_paise,
                                                received_on, status, enrollment_status, source, source_version, entered_by)
    values (r.lead_id, r.ref, r.gross, r.gst, r.net, r.received,
            case when r.received > 0 then coalesce(r.received_on, inf.ist_date(now())) end, r.status, r.enrollment_status,
            r.source, r.version, null)
    on conflict (enrollment_ref, source, source_version) do nothing;
    if found then
      v_n := v_n + 1;
      for v_deal in select distinct a.deal_id from inf.lead_attributions a where a.student_lead_id = r.lead_id and a.deal_id is not null loop
        perform inf.ledger_enqueue(v_deal, 'receipt');
      end loop;
    end if;
  end loop;
  return v_n;
end $$;

-- Finance records a receipt by hand, or withdraws its override so the CRM's data counts again.
create or replace function inf.receipt_record(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_ref text := p ->> 'enrollment_ref';
  v_lead bigint;
  v_id bigint;
  v_deal uuid;
begin
  if not inf.has_perm('commission_receipt.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p ->> 'reason')), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if v_ref !~ '^(b2b|b2c):\d+$' then raise exception 'invalid enrolment reference' using errcode = '22023'; end if;
  v_lead := coalesce((select r.student_lead_id from inf.eduwit_commission_receipts r where r.enrollment_ref = v_ref order by r.id desc limit 1),
                     nullif(p ->> 'student_lead_id', '')::bigint);
  if v_lead is null then raise exception 'no such lead' using errcode = '22023'; end if;
  insert into inf.eduwit_commission_receipts (student_lead_id, enrollment_ref, gross_paise, gst_paise, net_paise, received_paise, received_on,
                                              status, source, source_version, reason)
  values (v_lead, v_ref, coalesce((p ->> 'gross_paise')::bigint, 0), coalesce((p ->> 'gst_paise')::bigint, 0),
          coalesce((p ->> 'net_paise')::bigint, 0), coalesce((p ->> 'received_paise')::bigint, 0), nullif(p ->> 'received_on', '')::date,
          p ->> 'status', 'manual', gen_random_uuid()::text, trim(p ->> 'reason'))
  returning id into v_id;
  for v_deal in select distinct a.deal_id from inf.lead_attributions a where a.student_lead_id = v_lead and a.deal_id is not null loop
    perform inf.ledger_enqueue(v_deal, 'receipt');
  end loop;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- The runner: gather (read-only) and apply
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.ledger_facts(p_deal uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  d inf.deals;
  v_content jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal;
  if d.id is null then return null; end if;
  v_content := inf.deal_content_facts(p_deal);
  return v_content || jsonb_build_object(
    'deal', jsonb_build_object('id', d.id, 'creator_id', d.creator_id, 'starts_on', d.starts_on, 'ends_on', d.ends_on, 'status', d.status,
                               'campaign_ends_on', (select c.ends_on from inf.campaigns c where c.id = d.campaign_id)),
    'context', inf.comp_context(),
    'leads', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'at', a.lead_created_at, 'link_id', a.link_id,
               'deliverable_ref', (select coalesce(x.config_ref, x.id::text) from inf.deliverables x where x.id = a.deliverable_id),
               'programme_id', k.programme_id,
               'university_id', (select cp.university_id from public.catalog_programs cp where cp.id = k.programme_id),
               'level', (select cp.level from public.catalog_programs cp where cp.id = k.programme_id),
               'qualified_at', (select min(e.occurred_at) from inf.lead_stage_events e where e.attribution_id = a.id
                                 and e.creator_stage in ('qualified', 'allocated', 'counselling', 'applied', 'enrolled')),
               'applied_at', (select min(e.occurred_at) from inf.lead_stage_events e where e.attribution_id = a.id
                               and e.creator_stage in ('applied', 'enrolled')),
               'rejected_at', (select min(e.occurred_at) from inf.lead_stage_events e where e.attribution_id = a.id
                                and e.creator_stage in ('junk', 'duplicate', 'not_attributed')),
               'junk', coalesce(a.creator_stage = 'junk', false)) order by a.lead_created_at, a.id)
        from inf.lead_attributions a left join inf.tracking_links k on k.id = a.link_id
       where a.deal_id = d.id and a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last') and not a.is_test), '[]'),
    'enrollments', coalesce((
      select jsonb_agg(x order by x ->> 'at', x ->> 'ref') from (
        select jsonb_build_object(
                 'ref', 'b2b:' || e.id, 'lead_id', a.id,
                 'at', to_char((e.enrolled_on::timestamp at time zone 'Asia/Kolkata') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                 'programme_id', e.programme_id, 'university_id', e.university_id,
                 'level', (select cp.level from public.catalog_programs cp where cp.id = e.programme_id),
                 'fee_paise', case when e.fee_amount_inr is not null then round(e.fee_amount_inr * 100)::bigint end,
                 'expected_commission_gross_paise', (select nullif(round(sum(x.gross_inr) * 100)::bigint, 0) from b2b.earnings x
                                                      where x.enrollment_id = e.id and x.kind = 'commission'),
                 'cancelled_at', case when e.status in ('refunded', 'cancelled')
                                      then to_char(coalesce(e.refunded_at, e.updated_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end) as x
          from inf.lead_attributions a join public.enrollments e on e.lead_id = a.student_lead_id and e.source_product = 'b2b'
         where a.deal_id = d.id and a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last') and not a.is_test
        union all
        select jsonb_build_object(
                 'ref', 'b2c:' || m.enrollment_id, 'lead_id', a.id,
                 'at', to_char((m.enrolled_on::timestamp at time zone 'Asia/Kolkata') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                 'programme_id', null, 'university_id', null, 'level', null, 'fee_paise', null,
                 'expected_commission_gross_paise', nullif(round(coalesce(m.university_commission_gross, 0) * 100)::bigint, 0),
                 'cancelled_at', (select to_char(min(r.created_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                                    from inf.eduwit_commission_receipts r
                                   where r.enrollment_ref = 'b2c:' || m.enrollment_id and r.enrollment_status in ('refunded', 'cancelled'))) as x
          from inf.lead_attributions a join public.b2c_enrollment_money_v m on m.lead_id = a.student_lead_id
         where a.deal_id = d.id and a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last') and not a.is_test
           and m.enrolled_on is not null
      ) s), '[]'),
    'receipts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'enrollment_ref', r.enrollment_ref, 'received_paise', r.received_paise,
               'received_on', to_char((coalesce(r.received_on, inf.ist_date(r.created_at))::timestamp at time zone 'Asia/Kolkata') at time zone 'UTC',
                                      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
               'full', r.status = 'received'))
        from inf.receipts_effective() r
       where r.student_lead_id in (select a.student_lead_id from inf.lead_attributions a where a.deal_id = d.id)
         and r.status in ('received', 'partly_received')), '[]'),
    'manual', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'ref', m.ref, 'at', m.at) order by m.at)
                          from inf.deal_manual_events m where m.deal_id = d.id), '[]'),
    'campaign_ended_at', (select to_char(((c.ends_on + 1)::timestamp at time zone 'Asia/Kolkata') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                            from inf.campaigns c where c.id = d.campaign_id and c.ends_on is not null and c.ends_on < inf.ist_date(now())),
    'deal_completed_at', case when d.status = 'completed' then to_char(coalesce(d.closed_at, d.updated_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
    'posted', coalesce((
      select jsonb_agg(jsonb_build_object('key', le.event_key, 'type', le.type, 'direction', le.direction, 'amount_paise', le.amount_paise,
                                          'confirmed_paise', le.confirmed_paise, 'reversed', le.reversed_by_id is not null,
                                          'paid_paise', le.paid_paise, 'in_open_batch', inf.ledger_in_open_batch(le.id)) order by le.id)
        from inf.ledger_entries le where le.deal_id = d.id and le.source = 'engine'), '[]')
  );
end $$;

-- Writes a runner plan (service role). Idempotent: lines are keyed, confirmations only grow, a reversal of an entry
-- an open batch holds is skipped (the plan defers it too). Also posts approved penalties and extra revision fees,
-- syncs penalty proposals, refreshes the lead feed's earning status and logs the run.
create or replace function inf.ledger_apply(p_deal uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  d inf.deals;
  v jsonb;
  e inf.ledger_entries;
  v_today date := inf.ist_date(now());
  v_created int := 0;
  v_confirmed int := 0;
  v_reversed int := 0;
  v_other int := 0;
  v_id bigint;
  v_attr uuid;
  pp inf.penalty_proposals;
  rx record;
  v_prev text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_prev := inf.ledger_writer_on();
  select * into d from inf.deals where id = p_deal for update;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;

  for v in select * from jsonb_array_elements(coalesce(p -> 'create', '[]')) loop
    v_attr := case
      when v ->> 'subject' ~ '^(lead|qualified|applied):[0-9a-f-]{36}$' then split_part(v ->> 'subject', ':', 2)::uuid
      when v ->> 'subject' like 'enrol:%' then nullif(p -> 'enrolment_leads' ->> substr(v ->> 'subject', 7), '')::uuid
    end;
    v_id := inf.ledger_post(jsonb_build_object(
      'creator_id', d.creator_id, 'deal_id', d.id, 'deal_version_id', v ->> 'version_id', 'type', v ->> 'type',
      'direction', v ->> 'direction', 'amount_paise', v ->> 'amount_paise', 'confirmed_paise', v ->> 'confirmed_paise',
      'source', 'engine', 'event_key', v ->> 'key', 'rule_id', v ->> 'rule_id', 'subject', v ->> 'subject',
      'attribution_id', case when exists (select 1 from inf.lead_attributions a where a.id = v_attr) then v_attr end,
      'tds_component', v ->> 'tds_component', 'period', v ->> 'period', 'due_on', v ->> 'due_on', 'note', v ->> 'note'));
    if v_id is not null then v_created := v_created + 1; end if;
  end loop;

  for v in select * from jsonb_array_elements(coalesce(p -> 'confirm', '[]')) loop
    update inf.ledger_entries set confirmed_paise = least(greatest(confirmed_paise, (v ->> 'confirmed_paise')::bigint), amount_paise)
     where event_key = v ->> 'key' and deal_id = d.id and source = 'engine' and reversed_by_id is null
       and confirmed_paise < (v ->> 'confirmed_paise')::bigint
    returning id into v_id;
    if v_id is not null then
      perform inf.ledger_transition(v_id, 'confirmed by the engine');
      v_confirmed := v_confirmed + 1;
    end if;
  end loop;

  for v in select * from jsonb_array_elements(coalesce(p -> 'reverse', '[]')) loop
    select * into e from inf.ledger_entries
     where event_key = v ->> 'key' and deal_id = d.id and source = 'engine' and reversed_by_id is null for update;
    continue when e.id is null or inf.ledger_in_open_batch(e.id);
    v_id := inf.ledger_post(jsonb_build_object(
      'creator_id', e.creator_id, 'deal_id', e.deal_id, 'deal_version_id', e.deal_version_id, 'type', 'reversal',
      'direction', case e.direction when 'credit' then 'debit' else 'credit' end, 'amount_paise', e.amount_paise,
      'confirmed_paise', e.paid_paise, 'source', 'reversal', 'event_key', 'rev:' || e.event_key, 'rule_id', e.rule_id,
      'subject', e.subject, 'attribution_id', e.attribution_id, 'tds_component', e.tds_component,
      'period', to_char(v_today, 'YYYY-MM'), 'due_on', v_today, 'reverses_id', e.id,
      'note', case v ->> 'reason' when 'obsolete' then 'No longer earned' else 'Amount changed' end));
    if v_id is not null then
      update inf.ledger_entries set reversed_by_id = v_id where id = e.id;
      perform inf.ledger_transition(e.id, 'reversed');
      v_reversed := v_reversed + 1;
    end if;
  end loop;

  -- Approved penalties become debits against the deal's fees.
  for pp in select * from inf.penalty_proposals where deal_id = d.id and status = 'approved' loop
    v_id := inf.ledger_post(jsonb_build_object(
      'creator_id', d.creator_id, 'deal_id', d.id, 'deal_version_id', pp.version_id, 'type', 'penalty', 'direction', 'debit',
      'amount_paise', pp.amount_paise, 'confirmed_paise', pp.amount_paise, 'source', 'penalty', 'event_key', 'penalty:' || pp.key,
      'rule_id', pp.rule_id, 'subject', pp.subject, 'tds_component', 'fixed_fee',
      'period', to_char(inf.ist_date(coalesce(pp.decided_at, now())), 'YYYY-MM'), 'due_on', inf.ist_date(coalesce(pp.decided_at, now())),
      'note', pp.reason));
    if v_id is not null then v_other := v_other + 1; end if;
  end loop;

  -- Approved extra revision rounds with a fee are paid as fees.
  for rx in select r.id, r.fee_paise, r.decided_at, x.title from inf.revision_extensions r join inf.deliverables x on x.id = r.deliverable_id
             where x.deal_id = d.id and r.status = 'approved' and r.fee_paise > 0 loop
    v_id := inf.ledger_post(jsonb_build_object(
      'creator_id', d.creator_id, 'deal_id', d.id, 'type', 'fixed_fee', 'direction', 'credit', 'amount_paise', rx.fee_paise,
      'confirmed_paise', rx.fee_paise, 'source', 'revision_fee', 'event_key', 'revision_fee:' || rx.id, 'rule_id', 'extra_revision',
      'subject', rx.id::text, 'tds_component', 'fixed_fee', 'period', to_char(inf.ist_date(coalesce(rx.decided_at, now())), 'YYYY-MM'),
      'due_on', inf.ist_date(coalesce(rx.decided_at, now())), 'note', left('Extra revision round: ' || rx.title, 500)));
    if v_id is not null then v_other := v_other + 1; end if;
  end loop;

  if jsonb_typeof(p -> 'proposals') = 'array' then perform inf.penalty_proposals_sync(d.id, p -> 'proposals'); end if;
  perform inf.lead_feed_earnings(d.id);
  insert into inf.comp_runs (deal_id, deal_version_id, kind, as_of, summary, created_by)
  values (d.id, null, 'live', coalesce((p ->> 'as_of')::timestamptz, now()),
          jsonb_build_object('created', v_created, 'confirmed', v_confirmed, 'reversed', v_reversed, 'other', v_other,
                             'deferred', coalesce(jsonb_array_length(p -> 'deferred'), 0), 'unchanged', coalesce((p ->> 'unchanged')::int, 0)),
          null);
  perform inf.ledger_writer_restore(v_prev);
  return jsonb_build_object('created', v_created, 'confirmed', v_confirmed, 'reversed', v_reversed, 'other', v_other);
end $$;

-- Deals the nightly run replays: open deals, and closed ones with entries not yet settled.
create or replace function inf.ledger_deals_to_run() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select d.id from inf.deals d
   where coalesce(auth.role(), '') = 'service_role'
     and exists (select 1 from inf.deal_versions v where v.deal_id = d.id and v.state = 'accepted')
     and (d.status in ('agreed', 'active')
          or exists (select 1 from inf.ledger_entries e where e.deal_id = d.id and e.status in ('accrued', 'confirmed', 'on_hold'))
          or coalesce(d.closed_at, d.updated_at) > now() - interval '120 days')
$$;

-- Domain events that can change what a deal earns enqueue a run for that deal.
create or replace function inf.ledger_on_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_deal uuid;
begin
  v_deal := case new.subject_type
    when 'deal' then (select d.id from inf.deals d where d.id::text = new.subject_id)
    when 'contract' then (select c.deal_id from inf.contracts c where c.id::text = new.subject_id)
    when 'brief' then (select b.deal_id from inf.briefs b where b.id::text = new.subject_id)
    when 'deliverable' then (select x.deal_id from inf.deliverables x where x.id::text = new.subject_id)
    when 'penalty_proposal' then (select pp.deal_id from inf.penalty_proposals pp where pp.id::text = new.subject_id)
    when 'lead_attribution' then (select a.deal_id from inf.lead_attributions a where a.id::text = new.subject_id)
  end;
  if v_deal is not null then perform inf.ledger_enqueue(v_deal, new.type); end if;
  return null;
end $$;
create trigger domain_events_ledger after insert on inf.domain_events for each row execute function inf.ledger_on_event();

-- Staff record a milestone release or a breach; the deal is re-run.
create or replace function inf.deal_manual_event(p_deal uuid, p_kind text, p_ref text, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from inf.deals d where d.id = p_deal and d.status in ('agreed', 'active', 'completed', 'terminated')) then
    raise exception 'invalid deal' using errcode = '22023';
  end if;
  if p_kind = 'manual_release' and not exists (
       select 1 from inf.deals d join inf.deal_versions v on v.id = d.current_version_id,
                     jsonb_array_elements(v.comp_config -> 'fixed') f, jsonb_array_elements(f -> 'milestones') m
        where d.id = p_deal and (f ->> 'id') || '.' || (m ->> 'id') = p_ref and m -> 'trigger' ->> 'type' = 'manual_release') then
    raise exception 'no such manual milestone' using errcode = '22023';
  end if;
  insert into inf.deal_manual_events (deal_id, kind, ref, reason) values (p_deal, p_kind, nullif(p_ref, ''), trim(p_reason))
  returning id into v_id;
  perform inf.ledger_enqueue(p_deal, p_kind);
  return v_id;
exception when unique_violation then
  raise exception 'this milestone is already released' using errcode = '23505';
end $$;

-- The lead feed's earning status for a deal's leads (D-121 replaced): from the ledger entries about each lead.
create or replace function inf.lead_feed_earnings(p_deal uuid) returns void
language sql security definer set search_path = '' as $$
  update inf.creator_lead_feed f set earning_status = s.status, updated_at = now()
    from (select a.id,
                 case when a.status not in ('credited', 'manually_credited') or a.touch not in ('first', 'last') then 'none'
                      when not exists (select 1 from inf.ledger_entries e where e.attribution_id = a.id and e.type <> 'reversal') then 'pending'
                      when not exists (select 1 from inf.ledger_entries e where e.attribution_id = a.id and e.type not in ('reversal', 'clawback')
                                         and e.status not in ('reversed', 'clawed_back'))
                        or exists (select 1 from inf.ledger_entries e where e.attribution_id = a.id and e.type = 'clawback') then 'clawed_back'
                      when not exists (select 1 from inf.ledger_entries e where e.attribution_id = a.id and e.direction = 'credit'
                                         and e.type <> 'reversal' and e.status not in ('paid', 'reversed', 'clawed_back')) then 'paid'
                      when exists (select 1 from inf.ledger_entries e where e.attribution_id = a.id and e.direction = 'credit'
                                     and e.status in ('confirmed', 'payable', 'in_batch', 'paid')) then 'confirmed'
                      else 'accrued' end as status
            from inf.lead_attributions a where a.deal_id = p_deal) s
   where f.attribution_id = s.id and f.earning_status is distinct from s.status
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff ledger operations
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.ledger_adjust(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_today date := inf.ist_date(now());
begin
  if not inf.has_perm('ledger.adjust') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p ->> 'reason')), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if coalesce((p ->> 'amount_paise')::bigint, 0) <= 0 then raise exception 'amount must be positive' using errcode = '22023'; end if;
  if not exists (select 1 from inf.creators c where c.id = (p ->> 'creator_id')::uuid) then raise exception 'invalid creator' using errcode = '22023'; end if;
  if nullif(p ->> 'deal_id', '') is not null
     and not exists (select 1 from inf.deals d where d.id = (p ->> 'deal_id')::uuid and d.creator_id = (p ->> 'creator_id')::uuid) then
    raise exception 'invalid deal' using errcode = '22023';
  end if;
  v_id := inf.ledger_post(jsonb_build_object(
    'creator_id', p ->> 'creator_id', 'deal_id', nullif(p ->> 'deal_id', ''), 'type', 'adjustment', 'direction', p ->> 'direction',
    'amount_paise', p ->> 'amount_paise', 'confirmed_paise', p ->> 'amount_paise', 'source', 'adjustment',
    'event_key', 'adjustment:' || gen_random_uuid(), 'rule_id', 'manual', 'tds_component', coalesce(nullif(p ->> 'tds_component', ''), 'commission'),
    'period', to_char(v_today, 'YYYY-MM'), 'due_on', coalesce(nullif(p ->> 'due_on', '')::date, v_today), 'note', trim(p ->> 'reason')));
  perform inf.emit_event('ledger.adjusted', 'ledger_entry', v_id::text, jsonb_build_object('creator_id', p ->> 'creator_id'), 'ledger_adjusted:' || v_id);
  return v_id;
end $$;

create or replace function inf.ledger_hold(p_entry bigint, p_hold boolean, p_reason text) returns text
language plpgsql security definer set search_path = '' as $$
declare e inf.ledger_entries; v_prev text; v_status text;
begin
  if not inf.has_perm('ledger.adjust') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into e from inf.ledger_entries where id = p_entry for update;
  if e.id is null or e.type in ('tds', 'gst', 'payout') or e.status in ('paid', 'reversed', 'clawed_back') then
    raise exception 'this entry cannot be held' using errcode = '22023';
  end if;
  v_prev := inf.ledger_writer_on();
  update inf.ledger_entries set held = p_hold, hold_reason = case when p_hold then trim(p_reason) end where id = e.id;
  perform inf.ledger_writer_restore(v_prev);
  v_status := inf.ledger_transition(e.id, (case when p_hold then 'held: ' else 'released: ' end) || trim(p_reason));
  return v_status;
end $$;

-- Hold or release every open entry of a creator (for example while KYC or a dispute is resolved).
create or replace function inf.ledger_hold_creator(p_creator uuid, p_hold boolean, p_reason text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_n int := 0;
begin
  if not inf.has_perm('ledger.adjust') then raise exception 'not allowed' using errcode = '42501'; end if;
  for v_id in select id from inf.ledger_entries
               where creator_id = p_creator and held is distinct from p_hold and type not in ('tds', 'gst', 'payout')
                 and status not in ('paid', 'reversed', 'clawed_back', 'in_batch') loop
    perform inf.ledger_hold(v_id, p_hold, p_reason);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Payout batches
-- ---------------------------------------------------------------------------------------------------------------
-- Creators with payable entries and everything the payout builder needs (payout.manage). Entries of deals whose
-- signed contract names an agency as payee are flagged.
create or replace function inf.payout_candidates(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := inf.ist_date(now());
  v_fy text := inf.fy_of(inf.ist_date(now()));
  v_creators uuid[] := case when jsonb_typeof(p -> 'creator_ids') = 'array' and jsonb_array_length(p -> 'creator_ids') > 0
                            then array(select (x)::uuid from jsonb_array_elements_text(p -> 'creator_ids') x) end;
  v_campaign uuid := nullif(p ->> 'campaign_id', '')::uuid;
  v_due date := coalesce(nullif(p ->> 'due_by', '')::date, inf.ist_date(now()));
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'today', v_today,
    'rules', jsonb_build_object(
      'payouts', inf.setting('finance.payouts'), 'gst', inf.setting('finance.gst'),
      'sections', inf.tds_sections_list(),
      'sections_confirmed', not exists (select 1 from inf.tds_sections s where not s.confirmed_by_ca)),
    'creators', coalesce((
      select jsonb_agg(c order by c ->> 'name') from (
        select jsonb_build_object(
                 'creator_id', cr.id, 'name', cr.display_name, 'handle', cr.handle,
                 'kyc_verified', coalesce(k.status = 'verified' and k.bank_account_enc is not null, false),
                 'has_pan', coalesce(k.status = 'verified' and k.pan_enc is not null, false),
                 'charges_gst', coalesce(k.gst_status = 'registered' and k.gstin_verified, false),
                 'fy_prior', coalesce((select jsonb_object_agg(t.section, jsonb_build_object('base_paise', t.base, 'taxed', t.taxed))
                                         from (select r.section, sum(r.base_paise) as base, bool_or(r.amount_paise > 0) as taxed
                                                 from inf.tds_records r where r.creator_id = cr.id and r.fy = v_fy group by r.section) t), '{}'),
                 'entries', (select jsonb_agg(jsonb_build_object(
                                     'id', e.id, 'type', e.type, 'direction', e.direction,
                                     'remaining_paise', e.confirmed_paise - e.paid_paise,
                                     'tds_component', coalesce(e.tds_component, 'commission'), 'deal_id', e.deal_id,
                                     'deal_title', (select d.title from inf.deals d where d.id = e.deal_id), 'note', e.note,
                                     'agency_payee', exists (select 1 from inf.contracts ct where ct.deal_id = e.deal_id and ct.payee_agency_id is not null
                                                               and ct.status in ('active', 'completed'))) order by e.id)
                               from inf.ledger_entries e
                              where e.creator_id = cr.id and e.status = 'payable' and e.due_on <= v_due
                                and (v_campaign is null or exists (select 1 from inf.deals d where d.id = e.deal_id and d.campaign_id = v_campaign)))) as c
          from inf.creators cr left join inf.creator_kyc k on k.creator_id = cr.id
         where (v_creators is null or cr.id = any (v_creators))
           and exists (select 1 from inf.ledger_entries e where e.creator_id = cr.id and e.status = 'payable' and e.due_on <= v_due
                         and (v_campaign is null or exists (select 1 from inf.deals d where d.id = e.deal_id and d.campaign_id = v_campaign)))
      ) s), '[]'));
end $$;

-- Creates a draft batch from payouts the app built with lib/ledger/payout.ts. The database re-checks what it can:
-- every item is a payable entry of that creator taking exactly what is left, items add up to the gross, the net
-- adds up, and no entry is in another open batch.
create or replace function inf.payout_batch_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_batch uuid;
  v_fy text := inf.fy_of(inf.ist_date(now()));
  po jsonb;
  it jsonb;
  e inf.ledger_entries;
  v_payout uuid;
  v_sum bigint;
  v_kyc boolean := coalesce((inf.setting('finance.payouts') ->> 'kyc_required_for_payout')::boolean, true);
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(jsonb_array_length(p -> 'payouts'), 0) = 0 then raise exception 'nothing to pay' using errcode = '22023'; end if;
  insert into inf.payout_batches (ref, filters, note)
  values ('PB-' || v_fy || '-' || lpad(nextval('inf.payout_batch_ref_seq')::text, 4, '0'), coalesce(p -> 'filters', '{}'),
          nullif(trim(p ->> 'note'), ''))
  returning id into v_batch;
  for po in select * from jsonb_array_elements(p -> 'payouts') loop
    if v_kyc and not exists (select 1 from inf.creator_kyc k where k.creator_id = (po ->> 'creator_id')::uuid and k.status = 'verified'
                                                              and k.bank_account_enc is not null) then
      raise exception 'KYC is not verified for a creator in this batch' using errcode = '22023';
    end if;
    insert into inf.payouts (ref, batch_id, creator_id, gross_paise, gst_base_paise, gst_paise, tds_paise, eduwit_tds_paise, net_paise,
                             sections, needs_invoice)
    values ('PO-' || v_fy || '-' || lpad(nextval('inf.payout_ref_seq')::text, 5, '0'), v_batch, (po ->> 'creator_id')::uuid,
            (po ->> 'gross_paise')::bigint, coalesce((po ->> 'gst_base_paise')::bigint, 0), coalesce((po ->> 'gst_paise')::bigint, 0),
            coalesce((po ->> 'tds_paise')::bigint, 0), coalesce((po ->> 'eduwit_tds_paise')::bigint, 0), (po ->> 'net_paise')::bigint,
            coalesce(po -> 'sections', '[]'), coalesce((po ->> 'needs_invoice')::boolean, false))
    returning id into v_payout;
    v_sum := 0;
    for it in select * from jsonb_array_elements(po -> 'items') loop
      select * into e from inf.ledger_entries where id = (it ->> 'entry_id')::bigint for update;
      if e.id is null or e.creator_id <> (po ->> 'creator_id')::uuid or e.status <> 'payable' or inf.ledger_in_open_batch(e.id)
         or (it ->> 'amount_paise')::bigint <> (case e.direction when 'credit' then 1 else -1 end) * (e.confirmed_paise - e.paid_paise) then
        raise exception 'an entry changed since the payout was prepared; prepare the batch again' using errcode = '40001';
      end if;
      insert into inf.payout_items (payout_id, entry_id, amount_paise) values (v_payout, e.id, (it ->> 'amount_paise')::bigint);
      v_sum := v_sum + (it ->> 'amount_paise')::bigint;
    end loop;
    if v_sum <> (po ->> 'gross_paise')::bigint then raise exception 'payout items do not add up' using errcode = '22023'; end if;
    for it in select * from jsonb_array_elements(po -> 'items') loop
      perform inf.ledger_transition((it ->> 'entry_id')::bigint, 'in batch');
    end loop;
  end loop;
  perform inf.emit_event('payout.batch_created', 'payout_batch', v_batch::text, '{}'::jsonb, 'payout_batch_created:' || v_batch);
  return v_batch;
end $$;

-- Frees a payout's entries (after removal, cancellation or a failed payment).
create or replace function inf.payout_release_items(p_payout uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  for v_id in select entry_id from inf.payout_items where payout_id = p_payout loop
    perform inf.ledger_transition(v_id, p_reason);
  end loop;
end $$;

create or replace function inf.payout_remove(p_payout uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare po inf.payouts;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select p.* into po from inf.payouts p join inf.payout_batches b on b.id = p.batch_id
   where p.id = p_payout and p.status = 'pending' and b.status = 'draft' for update of p;
  if po.id is null then raise exception 'only payouts in a draft batch can be removed' using errcode = '22023'; end if;
  update inf.payouts set status = 'removed', status_reason = trim(p_reason) where id = po.id;
  -- Any change to the batch needs fresh approvals.
  update inf.payout_batches set approved_by = null, approved_at = null, second_approved_by = null, second_approved_at = null
   where id = po.batch_id;
  perform inf.payout_release_items(po.id, 'removed from batch: ' || trim(p_reason));
end $$;

-- Approves a draft batch; with two-person approval it needs two different approvers. Every payout that needs a GST
-- invoice must have an accepted one.
create or replace function inf.payout_batch_approve(p_batch uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  b inf.payout_batches;
  v_two boolean := coalesce((inf.setting('finance.payouts') ->> 'two_person_approval')::boolean, true);
begin
  if not inf.has_perm('payout.approve') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into b from inf.payout_batches where id = p_batch for update;
  if b.id is null or b.status <> 'draft' then raise exception 'only a draft batch can be approved' using errcode = '22023'; end if;
  if not exists (select 1 from inf.payouts p where p.batch_id = b.id and p.status = 'pending') then
    raise exception 'nothing to pay' using errcode = '22023';
  end if;
  if exists (select 1 from inf.payouts p where p.batch_id = b.id and p.status = 'pending' and p.needs_invoice
               and not exists (select 1 from inf.invoices i where i.payout_id = p.id and i.kind = 'creator_gst_invoice' and i.status = 'accepted')) then
    raise exception 'a payout is waiting for its GST invoice' using errcode = '22023';
  end if;
  if b.approved_by is null then
    update inf.payout_batches set approved_by = auth.uid(), approved_at = now(), status = case when v_two then 'draft' else 'approved' end
     where id = b.id;
  elsif b.approved_by = auth.uid() then
    raise exception 'a second approver is needed' using errcode = '22023';
  else
    update inf.payout_batches set second_approved_by = auth.uid(), second_approved_at = now(), status = 'approved' where id = b.id;
  end if;
  select * into b from inf.payout_batches where id = p_batch;
  if b.status = 'approved' then
    perform inf.emit_event('payout.batch_approved', 'payout_batch', b.id::text, '{}'::jsonb, 'payout_batch_approved:' || b.id);
  end if;
  return b.status;
end $$;

create or replace function inf.payout_batch_cancel(p_batch uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare b inf.payout_batches; v_po uuid;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into b from inf.payout_batches where id = p_batch for update;
  if b.id is null or b.status not in ('draft', 'approved') then
    raise exception 'only a batch that has not been sent to the bank can be cancelled' using errcode = '22023';
  end if;
  update inf.payout_batches set status = 'cancelled', cancelled_reason = trim(p_reason) where id = b.id;
  for v_po in select id from inf.payouts where batch_id = b.id and status = 'pending' loop
    update inf.payouts set status = 'cancelled', status_reason = trim(p_reason) where id = v_po;
    perform inf.payout_release_items(v_po, 'batch cancelled: ' || trim(p_reason));
  end loop;
end $$;

-- The bank file rows, with account numbers decrypted (payout.manage, approved or processing batches only). Every
-- call is audited; the first one moves the batch to processing.
create or replace function inf.payout_bank_rows(p_batch uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b inf.payout_batches; v_rows jsonb;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into b from inf.payout_batches where id = p_batch for update;
  if b.id is null or b.status not in ('approved', 'processing') then
    raise exception 'the batch must be approved first' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'beneficiary_name', k.account_holder, 'account_number', inf.pii_decrypt(k.bank_account_enc), 'ifsc', k.ifsc,
           'net_paise', p.net_paise, 'payout_ref', p.ref, 'email', c.email, 'creator_code', upper(c.handle)) order by p.ref), '[]')
    into v_rows
    from inf.payouts p join inf.creators c on c.id = p.creator_id join inf.creator_kyc k on k.creator_id = p.creator_id
   where p.batch_id = b.id and p.status = 'pending';
  update inf.payout_batches set status = 'processing', exported_by = coalesce(exported_by, auth.uid()),
         exported_at = coalesce(exported_at, now()), export_count = export_count + 1
   where id = b.id;
  perform inf.audit('payout_batch', b.id::text, 'bank_export', null,
                     jsonb_build_object('payouts', jsonb_array_length(v_rows), 'export', b.export_count + 1));
  return v_rows;
end $$;

-- Marks payouts paid from UTRs (one by one or a whole bank file). Settles the entries, posts the TDS, GST and payout
-- entries, records TDS per section, issues a payout statement to creators who do not charge GST, and tells the creator.
create or replace function inf.payouts_mark_paid(p jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  po inf.payouts;
  it record;
  s jsonb;
  v_n int := 0;
  v_uid uuid;
  v_fy text;
  v_charges_gst boolean;
  v_prev text;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  for r in select * from jsonb_array_elements(p) loop
    select p2.* into po from inf.payouts p2 join inf.payout_batches b on b.id = p2.batch_id
     where p2.ref = upper(r ->> 'payout_ref') for update of p2;
    if po.id is null then raise exception 'no such payout %', r ->> 'payout_ref' using errcode = '22023'; end if;
    if po.status <> 'pending' or (select b.status from inf.payout_batches b where b.id = po.batch_id) <> 'processing' then
      raise exception 'payout % is not waiting for payment', po.ref using errcode = '22023';
    end if;
    if (r ->> 'paid_on')::date > inf.ist_date(now()) then raise exception 'the payment date is in the future' using errcode = '22023'; end if;
    update inf.payouts set status = 'paid', utr = upper(r ->> 'utr'), paid_on = (r ->> 'paid_on')::date where id = po.id;
    for it in select i.entry_id, i.amount_paise from inf.payout_items i where i.payout_id = po.id loop
      v_prev := inf.ledger_writer_on();
      update inf.ledger_entries set paid_paise = paid_paise + abs(it.amount_paise) where id = it.entry_id;
      perform inf.ledger_writer_restore(v_prev);
      perform inf.ledger_transition(it.entry_id, 'paid in ' || po.ref);
    end loop;
    if po.tds_paise > 0 then
      perform inf.ledger_post(jsonb_build_object('creator_id', po.creator_id, 'type', 'tds', 'direction', 'debit', 'amount_paise', po.tds_paise,
        'confirmed_paise', po.tds_paise, 'paid_paise', po.tds_paise, 'source', 'payout', 'event_key', 'payout:' || po.id || ':tds',
        'period', to_char((r ->> 'paid_on')::date, 'YYYY-MM'), 'due_on', r ->> 'paid_on', 'payout_id', po.id, 'note', 'TDS withheld, ' || po.ref));
    end if;
    if po.gst_paise > 0 then
      perform inf.ledger_post(jsonb_build_object('creator_id', po.creator_id, 'type', 'gst', 'direction', 'credit', 'amount_paise', po.gst_paise,
        'confirmed_paise', po.gst_paise, 'paid_paise', po.gst_paise, 'source', 'payout', 'event_key', 'payout:' || po.id || ':gst',
        'period', to_char((r ->> 'paid_on')::date, 'YYYY-MM'), 'due_on', r ->> 'paid_on', 'payout_id', po.id, 'note', 'GST, ' || po.ref));
    end if;
    perform inf.ledger_post(jsonb_build_object('creator_id', po.creator_id, 'type', 'payout', 'direction', 'debit', 'amount_paise', po.net_paise,
      'confirmed_paise', po.net_paise, 'paid_paise', po.net_paise, 'source', 'payout', 'event_key', 'payout:' || po.id || ':net',
      'period', to_char((r ->> 'paid_on')::date, 'YYYY-MM'), 'due_on', r ->> 'paid_on', 'payout_id', po.id,
      'note', 'Paid ' || po.ref || ', UTR ' || upper(r ->> 'utr')));
    v_fy := inf.fy_of((r ->> 'paid_on')::date);
    for s in select * from jsonb_array_elements(po.sections) loop
      insert into inf.tds_records (creator_id, payout_id, section, rate_bps, base_paise, taxable_paise, amount_paise, borne_by, fy, quarter, paid_on)
      values (po.creator_id, po.id, s ->> 'code', (s ->> 'rate_bps')::int, (s ->> 'base_paise')::bigint, (s ->> 'taxable_paise')::bigint,
              (s ->> 'tds_paise')::bigint, coalesce(s ->> 'borne_by', 'creator'), v_fy, inf.fy_quarter_of((r ->> 'paid_on')::date),
              (r ->> 'paid_on')::date);
    end loop;
    select coalesce(k.gst_status = 'registered' and k.gstin_verified, false) into v_charges_gst from inf.creator_kyc k where k.creator_id = po.creator_id;
    if not coalesce(v_charges_gst, false) then
      insert into inf.invoices (creator_id, payout_id, kind, number, issued_on, taxable_paise, gst_paise, total_paise, status)
      values (po.creator_id, po.id, 'payout_statement', 'PS-' || v_fy || '-' || lpad(nextval('inf.payout_statement_ref_seq')::text, 5, '0'),
              (r ->> 'paid_on')::date, po.gross_paise, 0, po.gross_paise, 'accepted');
    end if;
    perform inf.emit_event('payout.paid', 'payout', po.id::text, jsonb_build_object('creator_id', po.creator_id, 'net_paise', po.net_paise),
                           'payout_paid:' || po.id);
    perform inf.job_enqueue('payout.advice', jsonb_build_object('payout_id', po.id), now(), 'payout_advice:' || po.id);
    select ca.user_id into v_uid from inf.creator_accounts ca where ca.creator_id = po.creator_id;
    if v_uid is not null then
      perform inf.notify(v_uid, 'payout.paid', 'Payment sent: ' || po.ref,
                         'Your payout ' || po.ref || ' has been paid (UTR ' || upper(r ->> 'utr') || '). The payment advice is in Earnings.',
                         '/creator/earnings', jsonb_build_object('payout_id', po.id), true, 'payout_paid:' || po.id);
    end if;
    v_n := v_n + 1;
  end loop;
  update inf.payout_batches b set status = 'paid'
   where b.status = 'processing' and not exists (select 1 from inf.payouts x where x.batch_id = b.id and x.status = 'pending')
     and exists (select 1 from inf.payouts x where x.batch_id = b.id and x.status = 'paid');
  return v_n;
end $$;

create or replace function inf.payout_mark_failed(p_payout uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare po inf.payouts;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select p.* into po from inf.payouts p join inf.payout_batches b on b.id = p.batch_id
   where p.id = p_payout and p.status = 'pending' and b.status = 'processing' for update of p;
  if po.id is null then raise exception 'payout is not waiting for payment' using errcode = '22023'; end if;
  update inf.payouts set status = 'failed', status_reason = trim(p_reason) where id = po.id;
  perform inf.payout_release_items(po.id, 'payment failed: ' || trim(p_reason));
  update inf.payout_batches b set status = 'paid'
   where b.id = po.batch_id and not exists (select 1 from inf.payouts x where x.batch_id = b.id and x.status = 'pending')
     and exists (select 1 from inf.payouts x where x.batch_id = b.id and x.status = 'paid');
  update inf.payout_batches b set status = 'cancelled', cancelled_reason = 'every payout failed'
   where b.id = po.batch_id and not exists (select 1 from inf.payouts x where x.batch_id = b.id and x.status in ('pending', 'paid'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Invoices, TDS records and Form 16A
-- ---------------------------------------------------------------------------------------------------------------
create table inf.invoices (
  id             uuid primary key default gen_random_uuid(),
  creator_id     uuid not null references inf.creators (id) on delete restrict,
  payout_id      uuid not null references inf.payouts (id) on delete restrict,
  kind           text not null check (kind in ('creator_gst_invoice', 'payout_statement')),
  number         text not null check (char_length(number) between 1 and 20),
  issued_on      date not null,
  gstin          text check (gstin is null or inf.valid_gstin(gstin)),
  taxable_paise  bigint not null check (taxable_paise >= 0),
  gst_paise      bigint not null default 0 check (gst_paise >= 0),
  total_paise    bigint not null check (total_paise = taxable_paise + gst_paise),
  file_path      text check (file_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  status         text not null default 'submitted' check (status in ('submitted', 'accepted', 'rejected')),
  review_note    text check (char_length(review_note) <= 1000),
  reviewed_by    uuid,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now(),
  check (kind <> 'creator_gst_invoice' or (gstin is not null and file_path is not null))
);
create unique index invoices_number_idx on inf.invoices (creator_id, kind, upper(number)) where status <> 'rejected';
create unique index invoices_one_live_idx on inf.invoices (payout_id, kind) where status <> 'rejected';
create trigger invoices_audit after insert or update on inf.invoices for each row execute function inf.audit_row('invoice');

create table inf.tds_records (
  id             uuid primary key default gen_random_uuid(),
  creator_id     uuid not null references inf.creators (id) on delete restrict,
  payout_id      uuid not null references inf.payouts (id) on delete restrict,
  section        text not null,
  rate_bps       int not null check (rate_bps between 0 and 10000),
  base_paise     bigint not null,
  taxable_paise  bigint not null check (taxable_paise >= 0),
  amount_paise   bigint not null check (amount_paise >= 0),
  borne_by       text not null check (borne_by in ('creator', 'eduwit')),
  fy             text not null check (fy ~ '^\d{4}-\d{2}$'),
  quarter        text not null check (quarter in ('Q1', 'Q2', 'Q3', 'Q4')),
  paid_on        date not null,
  created_at     timestamptz not null default now(),
  unique (payout_id, section)
);
create index tds_records_creator_idx on inf.tds_records (creator_id, fy, section);
create index tds_records_quarter_idx on inf.tds_records (fy, quarter);
create trigger tds_records_append_only before update or delete on inf.tds_records for each row execute function inf.forbid_mutation();

create table inf.tds_certificates (
  id           uuid primary key default gen_random_uuid(),
  creator_id   uuid not null references inf.creators (id) on delete restrict,
  fy           text not null check (fy ~ '^\d{4}-\d{2}$'),
  quarter      text not null check (quarter in ('Q1', 'Q2', 'Q3', 'Q4')),
  file_path    text not null check (file_path ~ '^form16a/[0-9a-f-]{36}/\d{4}-\d{2}-Q[1-4](-[0-9a-f]{8})?\.pdf$'),
  uploaded_by  uuid not null default auth.uid(),
  uploaded_at  timestamptz not null default now(),
  unique (creator_id, fy, quarter)
);
create trigger tds_certificates_audit after insert or update on inf.tds_certificates for each row execute function inf.audit_row('tds_certificate');

-- A creator's GST invoice for a pending payout that needs one. Mirrors lib/ledger/invoice.ts (₹1 tolerance).
create or replace function inf.invoice_submit(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  po inf.payouts;
  k inf.creator_kyc;
  v_id uuid;
begin
  select * into po from inf.payouts where id = (p ->> 'payout_id')::uuid;
  if po.id is null or not coalesce(po.creator_id = inf.current_creator_id(), false) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if po.status <> 'pending' or not po.needs_invoice then raise exception 'this payout does not need an invoice' using errcode = '22023'; end if;
  select * into k from inf.creator_kyc where creator_id = po.creator_id;
  if k.gstin is null or upper(trim(p ->> 'gstin')) <> k.gstin then raise exception 'the GSTIN must match your verified GSTIN' using errcode = '22023'; end if;
  if (p ->> 'number') !~ '^[A-Za-z0-9/-]{1,16}$' then raise exception 'invalid invoice number' using errcode = '22023'; end if;
  if (p ->> 'issued_on')::date > inf.ist_date(now()) or (p ->> 'issued_on')::date < inf.ist_date(po.created_at) then
    raise exception 'invalid invoice date' using errcode = '22023';
  end if;
  if abs((p ->> 'taxable_paise')::bigint - po.gst_base_paise) > 100 or abs((p ->> 'gst_paise')::bigint - po.gst_paise) > 100 then
    raise exception 'the invoice amounts must match the payout' using errcode = '22023';
  end if;
  if (p ->> 'file_path') !~ ('^' || po.creator_id || '/' || po.id || '/[A-Za-z0-9._-]{1,120}$') then
    raise exception 'invalid file' using errcode = '22023';
  end if;
  insert into inf.invoices (creator_id, payout_id, kind, number, issued_on, gstin, taxable_paise, gst_paise, total_paise, file_path)
  values (po.creator_id, po.id, 'creator_gst_invoice', trim(p ->> 'number'), (p ->> 'issued_on')::date, k.gstin,
          (p ->> 'taxable_paise')::bigint, (p ->> 'gst_paise')::bigint, (p ->> 'taxable_paise')::bigint + (p ->> 'gst_paise')::bigint,
          p ->> 'file_path')
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'an invoice is already submitted for this payout, or this number is used' using errcode = '23505';
end $$;

create or replace function inf.invoice_upload_allowed(p_payout uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from inf.payouts p where p.id = p_payout and p.status = 'pending' and p.needs_invoice
                   and coalesce(p.creator_id = inf.current_creator_id(), false)
                   and not exists (select 1 from inf.invoices i where i.payout_id = p.id and i.status <> 'rejected'))
$$;

create or replace function inf.invoice_review(p_invoice uuid, p_accept boolean, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare i inf.invoices; v_uid uuid;
begin
  if not inf.has_perm('tax.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not p_accept and coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.invoices set status = case when p_accept then 'accepted' else 'rejected' end, review_note = nullif(trim(p_note), ''),
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_invoice and status = 'submitted' and kind = 'creator_gst_invoice'
  returning * into i;
  if i.id is null then raise exception 'this has already been decided' using errcode = '22023'; end if;
  select ca.user_id into v_uid from inf.creator_accounts ca where ca.creator_id = i.creator_id;
  if v_uid is not null and not p_accept then
    perform inf.notify(v_uid, 'invoice.rejected', 'Please upload your invoice again',
                       'Your GST invoice ' || i.number || ' was not accepted: ' || trim(p_note), '/creator/earnings',
                       jsonb_build_object('invoice_id', i.id), true, 'invoice_rejected:' || i.id);
  end if;
end $$;

create or replace function inf.tds_certificate_record(p_creator uuid, p_fy text, p_quarter text, p_path text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid;
begin
  if not inf.has_perm('tax.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_path !~ ('^form16a/' || p_creator || '/' || p_fy || '-' || p_quarter || '(-[0-9a-f]{8})?\.pdf$') then
    raise exception 'invalid file' using errcode = '22023';
  end if;
  insert into inf.tds_certificates (creator_id, fy, quarter, file_path) values (p_creator, p_fy, p_quarter, p_path)
  on conflict (creator_id, fy, quarter) do update set file_path = excluded.file_path, uploaded_by = auth.uid(), uploaded_at = now()
  returning id into v_id;
  select ca.user_id into v_uid from inf.creator_accounts ca where ca.creator_id = p_creator;
  if v_uid is not null then
    perform inf.notify(v_uid, 'tds.certificate', 'Your TDS certificate is ready',
                       'Form 16A for ' || p_fy || ' ' || p_quarter || ' is ready to download in Earnings.', '/creator/earnings',
                       jsonb_build_object('fy', p_fy, 'quarter', p_quarter), false, 'tds_certificate:' || p_creator || ':' || p_fy || ':' || p_quarter);
  end if;
  return v_id;
end $$;

-- Quarterly TDS summary (tax.manage): per section and per creator, with the PAN's last four characters.
create or replace function inf.tds_summary(p_fy text, p_quarter text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sections', coalesce((select jsonb_agg(jsonb_build_object('section', t.section, 'borne_by', t.borne_by, 'base_paise', t.base,
                                                              'taxable_paise', t.taxable, 'amount_paise', t.amount, 'creators', t.creators) order by t.section)
                            from (select r.section, r.borne_by, sum(r.base_paise) base, sum(r.taxable_paise) taxable, sum(r.amount_paise) amount,
                                         count(distinct r.creator_id) creators
                                    from inf.tds_records r where r.fy = p_fy and (p_quarter = '' or r.quarter = p_quarter)
                                   group by r.section, r.borne_by) t), '[]'),
    'creators', coalesce((select jsonb_agg(jsonb_build_object('creator_id', t.creator_id, 'name', c.legal_name, 'display_name', c.display_name,
                                                              'pan_last4', k.pan_last4, 'base_paise', t.base, 'amount_paise', t.amount,
                                                              'certificate', (select tc.file_path is not null from inf.tds_certificates tc
                                                                               where tc.creator_id = t.creator_id and tc.fy = p_fy and tc.quarter = p_quarter))
                                           order by c.display_name)
                            from (select r.creator_id, sum(r.base_paise) base, sum(r.amount_paise) amount from inf.tds_records r
                                   where r.fy = p_fy and (p_quarter = '' or r.quarter = p_quarter) and r.borne_by = 'creator' group by r.creator_id) t
                            join inf.creators c on c.id = t.creator_id left join inf.creator_kyc k on k.creator_id = t.creator_id), '[]'))
   where inf.has_perm('tax.manage')
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Read models
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.can_view_earnings(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('ledger.read') or inf.agency_can(p_creator, 'earnings')
$$;

-- Everything the earnings pages show for one creator.
create or replace function inf.creator_earnings(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
                           'id', e.id, 'type', e.type, 'direction', e.direction, 'amount_paise', e.amount_paise,
                           'confirmed_paise', e.confirmed_paise, 'paid_paise', e.paid_paise, 'status', e.status, 'period', e.period,
                           'due_on', e.due_on, 'posted_at', e.posted_at, 'note', e.note, 'deal_id', e.deal_id,
                           'deal_title', (select d.title from inf.deals d where d.id = e.deal_id), 'attribution_id', e.attribution_id,
                           'lead_ref', (select f.lead_ref from inf.creator_lead_feed f where f.attribution_id = e.attribution_id),
                           'payout_id', e.payout_id) order by e.posted_at desc, e.id desc)
                          from inf.ledger_entries e where e.creator_id = p_creator), '[]'),
    'payouts', coalesce((select jsonb_agg(jsonb_build_object(
                           'id', p.id, 'ref', p.ref, 'status', p.status, 'gross_paise', p.gross_paise, 'gst_base_paise', p.gst_base_paise,
                           'gst_paise', p.gst_paise, 'tds_paise', p.tds_paise, 'net_paise', p.net_paise, 'utr', p.utr, 'paid_on', p.paid_on,
                           'created_at', p.created_at, 'needs_invoice', p.needs_invoice, 'advice', p.advice_path is not null,
                           'invoice', (select jsonb_build_object('id', i.id, 'kind', i.kind, 'number', i.number, 'status', i.status,
                                                                 'review_note', i.review_note)
                                         from inf.invoices i where i.payout_id = p.id order by i.created_at desc limit 1))
                           order by p.created_at desc)
                          from inf.payouts p join inf.payout_batches b on b.id = p.batch_id
                         where p.creator_id = p_creator and p.status in ('pending', 'paid') and b.status <> 'cancelled'), '[]'),
    'certificates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'fy', t.fy, 'quarter', t.quarter, 'uploaded_at', t.uploaded_at)
                                               order by t.fy desc, t.quarter desc)
                               from inf.tds_certificates t where t.creator_id = p_creator), '[]'),
    'tds', coalesce((select jsonb_agg(jsonb_build_object('fy', t.fy, 'quarter', t.quarter, 'section', t.section, 'amount_paise', t.amount))
                       from (select r.fy, r.quarter, r.section, sum(r.amount_paise) amount from inf.tds_records r
                              where r.creator_id = p_creator and r.borne_by = 'creator' group by r.fy, r.quarter, r.section) t), '[]'),
    'gst', (select jsonb_build_object('charges_gst', coalesce(k.gst_status = 'registered' and k.gstin_verified, false), 'gstin', k.gstin)
              from inf.creator_kyc k where k.creator_id = p_creator),
    'settings', jsonb_build_object('cycle', inf.setting('finance.payouts') ->> 'cycle',
                                   'payout_day_of_month', (inf.setting('finance.payouts') ->> 'payout_day_of_month')::int))
   where inf.can_view_earnings(p_creator)
$$;

-- A payout with its items and the creator's details, for the payment advice PDF (service role) and staff.
create or replace function inf.payout_detail(p_payout uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'ref', p.ref, 'status', p.status, 'batch_id', p.batch_id, 'batch_ref', b.ref, 'creator_id', p.creator_id,
    'creator_name', c.display_name, 'legal_name', c.legal_name, 'handle', c.handle, 'pan_last4', k.pan_last4, 'bank_last4', k.bank_last4,
    'ifsc', k.ifsc, 'gstin', k.gstin, 'gross_paise', p.gross_paise, 'gst_base_paise', p.gst_base_paise, 'gst_paise', p.gst_paise,
    'tds_paise', p.tds_paise, 'eduwit_tds_paise', p.eduwit_tds_paise, 'net_paise', p.net_paise, 'sections', p.sections,
    'needs_invoice', p.needs_invoice, 'utr', p.utr, 'paid_on', p.paid_on, 'status_reason', p.status_reason, 'advice_path', p.advice_path,
    'created_at', p.created_at,
    'items', coalesce((select jsonb_agg(jsonb_build_object('entry_id', i.entry_id, 'amount_paise', i.amount_paise, 'type', e.type,
                                                           'note', e.note, 'period', e.period,
                                                           'deal_title', (select d.title from inf.deals d where d.id = e.deal_id)) order by i.entry_id)
                         from inf.payout_items i join inf.ledger_entries e on e.id = i.entry_id where i.payout_id = p.id), '[]'),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'number', i.number, 'issued_on', i.issued_on,
                                                              'gstin', i.gstin, 'taxable_paise', i.taxable_paise, 'gst_paise', i.gst_paise,
                                                              'total_paise', i.total_paise, 'status', i.status, 'review_note', i.review_note,
                                                              'file_path', i.file_path, 'created_at', i.created_at) order by i.created_at)
                            from inf.invoices i where i.payout_id = p.id), '[]'),
    'organisation', inf.setting('organisation.profile'))
    from inf.payouts p join inf.payout_batches b on b.id = p.batch_id join inf.creators c on c.id = p.creator_id
    left join inf.creator_kyc k on k.creator_id = p.creator_id
   where p.id = p_payout and (coalesce(auth.role(), '') = 'service_role' or inf.has_perm('payout.read') or inf.can_view_earnings(p.creator_id))
$$;

create or replace function inf.payout_advice_saved(p_payout uuid, p_path text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.payouts set advice_path = p_path where id = p_payout and status = 'paid' and advice_path is null;
end $$;

-- Staff lists (one page at a time).
create or replace function inf.ledger_list(p jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  with f as (
    select e.*, c.display_name as creator_name, d.title as deal_title, count(*) over () as total
      from inf.ledger_entries e join inf.creators c on c.id = e.creator_id left join inf.deals d on d.id = e.deal_id
     where inf.has_perm('ledger.read')
       and (nullif(p ->> 'creator_id', '') is null or e.creator_id = (p ->> 'creator_id')::uuid)
       and (nullif(p ->> 'deal_id', '') is null or e.deal_id = (p ->> 'deal_id')::uuid)
       and (nullif(p ->> 'status', '') is null or e.status = p ->> 'status')
       and (nullif(p ->> 'type', '') is null or e.type = p ->> 'type')
       and (nullif(p ->> 'period', '') is null or e.period = p ->> 'period')
       and (nullif(p ->> 'q', '') is null or c.display_name ilike '%' || (p ->> 'q') || '%' or c.handle ilike '%' || (p ->> 'q') || '%')
     order by e.posted_at desc, e.id desc
     limit 100 offset greatest((coalesce((p ->> 'page')::int, 1) - 1) * 100, 0)
  )
  select jsonb_build_object('total', coalesce((select max(total) from f), 0),
                            'rows', coalesce((select jsonb_agg(jsonb_build_object(
                              'id', f.id, 'creator_id', f.creator_id, 'creator_name', f.creator_name, 'deal_id', f.deal_id, 'deal_title', f.deal_title,
                              'type', f.type, 'direction', f.direction, 'amount_paise', f.amount_paise, 'confirmed_paise', f.confirmed_paise,
                              'paid_paise', f.paid_paise, 'status', f.status, 'source', f.source, 'period', f.period, 'due_on', f.due_on,
                              'note', f.note, 'held', f.held, 'hold_reason', f.hold_reason, 'posted_at', f.posted_at,
                              'reverses_id', f.reverses_id, 'reversed_by_id', f.reversed_by_id)) from f), '[]'))
$$;

create or replace function inf.ledger_entry_events(p_entry bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('from', s.from_status, 'to', s.to_status, 'reason', s.reason, 'at', s.at,
                                               'actor', (select sp.full_name from inf.staff_profiles sp where sp.user_id = s.actor_id)) order by s.at, s.id), '[]')
    from inf.ledger_status_events s where s.entry_id = p_entry and inf.has_perm('ledger.read')
$$;

create or replace function inf.payout_batches_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'ref', b.ref, 'status', b.status, 'created_at', b.created_at, 'note', b.note,
           'approvals', (b.approved_by is not null)::int + (b.second_approved_by is not null)::int,
           'payouts', (select count(*) from inf.payouts p where p.batch_id = b.id and p.status in ('pending', 'paid', 'failed')),
           'net_paise', (select coalesce(sum(p.net_paise), 0) from inf.payouts p where p.batch_id = b.id and p.status in ('pending', 'paid')),
           'paid', (select count(*) from inf.payouts p where p.batch_id = b.id and p.status = 'paid')) order by b.created_at desc), '[]')
    from inf.payout_batches b where inf.has_perm('payout.read')
$$;

create or replace function inf.payout_batch_detail(p_batch uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', b.id, 'ref', b.ref, 'status', b.status, 'filters', b.filters, 'note', b.note, 'created_at', b.created_at,
    'created_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = b.created_by),
    'approved_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = b.approved_by), 'approved_at', b.approved_at,
    'approved_by_me', b.approved_by = auth.uid(),
    'second_approved_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = b.second_approved_by),
    'second_approved_at', b.second_approved_at, 'exported_at', b.exported_at, 'export_count', b.export_count,
    'cancelled_reason', b.cancelled_reason,
    'two_person', coalesce((inf.setting('finance.payouts') ->> 'two_person_approval')::boolean, true),
    'payouts', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', p.id, 'ref', p.ref, 'creator_id', p.creator_id, 'creator_name', c.display_name, 'status', p.status,
                  'gross_paise', p.gross_paise, 'gst_paise', p.gst_paise, 'tds_paise', p.tds_paise, 'net_paise', p.net_paise,
                  'needs_invoice', p.needs_invoice, 'utr', p.utr, 'paid_on', p.paid_on, 'status_reason', p.status_reason,
                  'items', (select count(*) from inf.payout_items i where i.payout_id = p.id),
                  'invoice_status', (select i.status from inf.invoices i where i.payout_id = p.id and i.kind = 'creator_gst_invoice'
                                      order by i.created_at desc limit 1)) order by c.display_name)
                   from inf.payouts p join inf.creators c on c.id = p.creator_id where p.batch_id = b.id), '[]'))
    from inf.payout_batches b where b.id = p_batch and inf.has_perm('payout.read')
$$;

create or replace function inf.invoices_queue(p_status text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'payout_id', i.payout_id, 'payout_ref', p.ref, 'creator_id', i.creator_id, 'creator_name', c.display_name,
           'number', i.number, 'issued_on', i.issued_on, 'gstin', i.gstin, 'taxable_paise', i.taxable_paise, 'gst_paise', i.gst_paise,
           'total_paise', i.total_paise, 'payout_gst_base_paise', p.gst_base_paise, 'payout_gst_paise', p.gst_paise,
           'status', i.status, 'review_note', i.review_note, 'file_path', i.file_path, 'created_at', i.created_at) order by i.created_at), '[]')
    from inf.invoices i join inf.payouts p on p.id = i.payout_id join inf.creators c on c.id = i.creator_id
   where i.kind = 'creator_gst_invoice' and (p_status = '' or i.status = p_status) and inf.has_perm('tax.manage')
$$;

-- Receipts and the creator commission on each enrolment (ledger.read), for reconciliation.
create or replace function inf.recon_data() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'flag_after_days', coalesce((inf.setting('finance.reconciliation') ->> 'flag_after_days')::int, 90),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('subject', e.subject, 'direction', e.direction, 'amount_paise', e.amount_paise,
                                                             'confirmed_paise', e.confirmed_paise, 'reversed', e.reversed_by_id is not null,
                                                             'at', e.posted_at, 'creator_name', c.display_name, 'deal_title', d.title))
                           from inf.ledger_entries e join inf.creators c on c.id = e.creator_id left join inf.deals d on d.id = e.deal_id
                          where e.type in ('commission', 'clawback') and e.subject like 'enrol:%'), '[]'),
    'receipts', coalesce((select jsonb_agg(jsonb_build_object('enrollment_ref', r.enrollment_ref, 'expected_paise', nullif(r.gross_paise, 0),
                                                              'received_paise', r.received_paise, 'received_on', r.received_on,
                                                              'status', r.status, 'source', r.source, 'reason', r.reason,
                                                              'student_lead_id', r.student_lead_id, 'recorded_at', r.created_at))
                            from inf.receipts_effective() r), '[]'))
   where inf.has_perm('ledger.read') or inf.has_perm('commission_receipt.write')
$$;

-- Files: invoices in inf-invoices under <creator>/<payout>/, advice PDFs and Form 16A in inf-documents.
create or replace function inf.finance_file_allowed(p_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when p_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$' then
      inf.has_perm('tax.manage') or inf.has_perm('payout.read')
      or coalesce(split_part(p_path, '/', 1)::uuid = inf.current_creator_id(), false)
    when p_path ~ '^(advice|form16a)/[0-9a-f-]{36}/' then inf.can_view_earnings(split_part(p_path, '/', 2)::uuid)
    else false end
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Nightly: entries that fall due become payable; deals with time-based rules are re-run
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.ledger_nightly() returns void
language plpgsql security definer set search_path = '' as $$
declare v_deal uuid;
begin
  perform inf.ledger_refresh_due();
  for v_deal in select d.id from inf.deals d
                 where exists (select 1 from inf.deal_versions v where v.deal_id = d.id and v.state = 'accepted')
                   and (d.status in ('agreed', 'active')
                        or exists (select 1 from inf.ledger_entries e where e.deal_id = d.id and e.status in ('accrued', 'confirmed', 'on_hold'))) loop
    perform inf.job_enqueue('ledger.run', jsonb_build_object('deal_id', v_deal, 'reason', 'nightly'), now(),
                            'ledger:' || v_deal || ':nightly:' || to_char(inf.ist_date(now()), 'YYYYMMDD'));
  end loop;
end $$;

create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.contract_sign_codes where created_at < now() - interval '30 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
  perform inf.creators_flag_dormant();
  perform inf.deals_expire();
  perform inf.contracts_remind();
  perform inf.content_remind();
  perform inf.ledger_nightly();
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.ledger_entries enable row level security;
alter table inf.ledger_status_events enable row level security;
alter table inf.deal_manual_events enable row level security;
alter table inf.eduwit_commission_receipts enable row level security;
alter table inf.payout_batches enable row level security;
alter table inf.payouts enable row level security;
alter table inf.payout_items enable row level security;
alter table inf.invoices enable row level security;
alter table inf.tds_records enable row level security;
alter table inf.tds_certificates enable row level security;

create policy ledger_entries_read on inf.ledger_entries for select to authenticated using ((select inf.can_view_earnings(creator_id)));
create policy ledger_status_events_read on inf.ledger_status_events for select to authenticated using ((select inf.has_perm('ledger.read')));
create policy deal_manual_events_read on inf.deal_manual_events for select to authenticated using ((select inf.has_perm('deal.read')));
create policy eduwit_commission_receipts_read on inf.eduwit_commission_receipts for select to authenticated
  using ((select inf.has_perm('ledger.read')) or (select inf.has_perm('commission_receipt.write')));
create policy payout_batches_read on inf.payout_batches for select to authenticated using ((select inf.has_perm('payout.read')));
create policy payouts_read on inf.payouts for select to authenticated
  using ((select inf.has_perm('payout.read')) or (select inf.can_view_earnings(creator_id)));
create policy payout_items_read on inf.payout_items for select to authenticated using ((select inf.has_perm('payout.read')));
create policy invoices_read on inf.invoices for select to authenticated
  using ((select inf.has_perm('tax.manage')) or (select inf.has_perm('payout.read')) or (select inf.can_view_earnings(creator_id)));
create policy tds_records_read on inf.tds_records for select to authenticated
  using ((select inf.has_perm('tax.manage')) or (select inf.can_view_earnings(creator_id)));
create policy tds_certificates_read on inf.tds_certificates for select to authenticated
  using ((select inf.has_perm('tax.manage')) or (select inf.can_view_earnings(creator_id)));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.ledger_entries', 'authenticated', 'select'),
  ('table', 'inf.ledger_status_events', 'authenticated', 'select'),
  ('table', 'inf.deal_manual_events', 'authenticated', 'select'),
  ('table', 'inf.eduwit_commission_receipts', 'authenticated', 'select'),
  ('table', 'inf.payout_batches', 'authenticated', 'select'),
  ('table', 'inf.payouts', 'authenticated', 'select'),
  ('table', 'inf.payout_items', 'authenticated', 'select'),
  ('table', 'inf.invoices', 'authenticated', 'select'),
  ('table', 'inf.tds_records', 'authenticated', 'select'),
  ('table', 'inf.tds_certificates', 'authenticated', 'select'),
  ('function', 'inf.fy_of(date)', 'authenticated', 'execute'),
  ('function', 'inf.fy_quarter_of(date)', 'authenticated', 'execute'),
  ('function', 'inf.ledger_adjust(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.ledger_hold(bigint, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.ledger_hold_creator(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.ledger_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.ledger_entry_events(bigint)', 'authenticated', 'execute'),
  ('function', 'inf.deal_manual_event(uuid, text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.receipt_record(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.recon_data()', 'authenticated', 'execute'),
  ('function', 'inf.payout_candidates(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.payout_batch_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.payout_remove(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.payout_batch_approve(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.payout_batch_cancel(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.payout_bank_rows(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.payouts_mark_paid(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.payout_mark_failed(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.payout_batches_list()', 'authenticated', 'execute'),
  ('function', 'inf.payout_batch_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.payout_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.invoice_submit(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.invoice_upload_allowed(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.invoice_review(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.invoices_queue(text)', 'authenticated', 'execute'),
  ('function', 'inf.tds_certificate_record(uuid, text, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.tds_summary(text, text)', 'authenticated', 'execute'),
  ('function', 'inf.can_view_earnings(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creator_earnings(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.finance_file_allowed(text)', 'authenticated', 'execute');
call inf.apply_client_grants();
