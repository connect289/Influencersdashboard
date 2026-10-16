-- B2C CRM b20 (Phase 3): counsellor commission owed to Eduwit (spec B11.2), the money dashboards (B11.3) and the
-- published view for the B2B CRM. Staging first. Idempotent.
--   partner_rates_for()     the partners that offer the enrollment's programme and each one's rate, read-only from the B2B
--                           CRM's tables (b2b.partner_programmes, b2b.rates) until catalog.partner_rates_v exists
--   commission_lines        the ledger: a rate snapshot on every line; corrections are new lines; status moves
--                           needs_rate / provisional -> confirmed -> due -> settled (or void when reversed before settling)
--   commission_fallbacks    the Admin's rate for a university no partner offers
--   commission_overrides    per counsellor or per programme, with a reason; one-off adjustments are lines
--   commission_runs         monthly: review, clawbacks, approve; the finance CSV and PDF statements come from the app
-- The CRM moves no money: how the amount is collected is Eduwit's decision (B21 #2d).

-- ---------- tables ----------
create table if not exists b2c.commission_fallbacks (
  university_id bigint primary key,
  rate_type text not null check (rate_type in ('percent', 'fixed')),
  fee_base text not null default 'first_year' check (fee_base in ('first_year', 'total', 'amount_paid')),
  value numeric(12, 4) not null check (value >= 0),
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now()
);

create table if not exists b2c.commission_overrides (
  id bigint generated always as identity primary key,
  counsellor_id uuid references b2c.users (user_id),
  programme_id bigint,
  rate_type text not null check (rate_type in ('percent', 'fixed')),
  fee_base text not null default 'first_year' check (fee_base in ('first_year', 'total', 'amount_paid')),
  value numeric(12, 4) not null check (value >= 0),
  valid_from date not null default current_date,
  valid_to date,
  reason text not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check (counsellor_id is not null or programme_id is not null)
);

create table if not exists b2c.commission_runs (
  id bigint generated always as identity primary key,
  period date not null,                       -- the month the run is for (lines due by its end)
  status text not null default 'draft' check (status in ('draft', 'approved', 'cancelled')),
  totals jsonb not null default '{}'::jsonb,
  note text,
  is_test boolean not null default false,     -- a run of test leads only (test mode)
  created_by uuid,
  created_at timestamptz not null default now(),
  approved_by uuid,
  approved_at timestamptz
);
create unique index if not exists commission_runs_one_open on b2c.commission_runs (period, is_test) where status <> 'cancelled';

create table if not exists b2c.commission_lines (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references b2c.enrollments (id),
  lead_id bigint not null,
  counsellor_id uuid not null references b2c.users (user_id),
  kind text not null check (kind in ('booking', 'reversal', 'adjustment', 'clawback')),
  status text not null check (status in ('needs_rate', 'provisional', 'confirmed', 'due', 'settled', 'void')),
  amount numeric(12, 2),                      -- null while the line needs a rate
  tds numeric(12, 2) not null default 0,
  base_amount numeric(12, 2),
  rate_source text check (rate_source in ('partner', 'university_highest', 'fallback', 'override', 'adjustment', 'reversal', 'none')),
  flagged boolean not null default false,
  snapshot jsonb not null default '{}'::jsonb,
  override_id bigint references b2c.commission_overrides (id),
  reverses_id bigint references b2c.commission_lines (id),
  due_on date,
  run_id bigint references b2c.commission_runs (id),
  is_test boolean not null default false,
  reason text,
  actor_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists commission_lines_enrollment on b2c.commission_lines (enrollment_id);
create index if not exists commission_lines_counsellor on b2c.commission_lines (counsellor_id, created_at desc);
create index if not exists commission_lines_status on b2c.commission_lines (status) where status in ('needs_rate', 'confirmed', 'due');
do $d$
begin
  if not exists (select 1 from pg_trigger where tgname = 'commission_lines_ledger') then
    create trigger commission_lines_ledger before update on b2c.commission_lines for each row execute function b2c.ledger_guard('status,run_id,due_on');
  end if;
end $d$;

create table if not exists b2c.partner_rate_seen (
  key text primary key,                       -- 'rate:<id>' or 'pp:<id>'
  hash text not null,
  seen_at timestamptz not null default now()
);

-- ---------- partner rates (B11.2) ----------
/* One partner's rate for a programme on a date: the programme's own commission (partner_programmes.commission), then a
   partner_programme rate, then partner_university, then partner-wide. */
create or replace function b2c.partner_rate_pick(p_partner bigint, p_programme bigint, p_university bigint, p_on date, p_programme_scope boolean) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare j jsonb;
begin
  if p_programme_scope then
    select jsonb_build_object('scope', 'programme_commission', 'id', 'pp:' || pp.id, 'rate_type', coalesce(pp.commission ->> 'rate_type', pp.commission ->> 'type', 'percent'),
                              'value', coalesce(pp.commission ->> 'value', pp.commission ->> 'percent', pp.commission ->> 'amount')::numeric,
                              'fee_base', coalesce(pp.commission ->> 'fee_base', 'first_year'), 'tiers', pp.commission -> 'tiers')
      into j from b2b.partner_programmes pp
     where pp.partner_id = p_partner and pp.programme_id = p_programme and pp.active
       and (pp.valid_from is null or pp.valid_from::date <= p_on) and (pp.valid_to is null or pp.valid_to::date >= p_on)
       and coalesce(pp.commission ->> 'value', pp.commission ->> 'percent', pp.commission ->> 'amount', pp.commission ->> 'tiers') is not null
     order by pp.valid_from desc nulls last, pp.id desc limit 1;
    if j is not null then return j; end if;
  end if;
  select jsonb_build_object('scope', r.scope, 'id', 'rate:' || r.id, 'rate_type', r.rate_type, 'value', r.value, 'fee_base', r.fee_base, 'tiers', r.tiers,
                            'gst_inclusive', r.gst_inclusive, 'valid_from', r.valid_from)
    into j from b2b.rates r
   where r.partner_id = p_partner and r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and ((r.scope = 'partner_programme' and p_programme_scope and r.programme_id = p_programme)
          or (r.scope = 'partner_university' and r.university_id = p_university)
          or r.scope = 'partner')
   order by case r.scope when 'partner_programme' then 1 when 'partner_university' then 2 else 3 end, r.valid_from desc, r.id desc limit 1;
  return j;
end $f$;

/* The amount one rate gives for an enrollment. Tiers: the tier the catalogue marks as current, else the top tier
   (flagged), or always the top when Settings → money → partner_tier is 'top'. */
create or replace function b2c.rate_amount(p_enrollment bigint, p_rate jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_base numeric; v_pct numeric; v_tier jsonb; v_flag text;
begin
  if p_rate is null then return null; end if;
  v_base := b2c.fee_base_amount(p_enrollment, coalesce(p_rate ->> 'fee_base', 'first_year'));
  if p_rate ->> 'rate_type' = 'fixed' then
    return jsonb_build_object('base', v_base, 'amount', round((p_rate ->> 'value')::numeric, 2));
  elsif p_rate ->> 'rate_type' = 'tiered' then
    if coalesce(b2c.setting('money') ->> 'partner_tier', 'current') <> 'top' then
      select t into v_tier from jsonb_array_elements(p_rate -> 'tiers') t where coalesce((t ->> 'current')::boolean, false) limit 1;
    end if;
    if v_tier is null then v_tier := b2c.tier_pick(p_rate -> 'tiers', null, true); v_flag := 'top tier used'; end if;
    v_pct := (v_tier ->> 'value')::numeric;
  else
    v_pct := (p_rate ->> 'value')::numeric;
  end if;
  return jsonb_build_object('base', v_base, 'pct', v_pct, 'tier', v_tier, 'note', v_flag, 'amount', round(v_base * v_pct / 100, 2));
end $f$;

/* Who offers the enrollment's programme and at what rate; the highest is used. No partner offers the programme: the
   partners at its university (flagged university_highest). None at all: the Admin's fallback, or needs rate. */
create or replace function b2c.partner_rates_for(p_enrollment bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare e b2c.enrollments; v_src text; v_list jsonb := '[]'; p record; r jsonb; a jsonb; v_best jsonb; f b2c.commission_fallbacks; v_err text;
begin
  select * into e from b2c.enrollments where id = p_enrollment;
  begin
    for p in
      select pa.id, coalesce(pa.display_name, pa.name) as name,
             exists (select 1 from b2b.partner_programmes pp where pp.partner_id = pa.id and pp.programme_id = e.programme_id and pp.active
                      and (pp.valid_to is null or pp.valid_to::date >= e.enrolled_on)) as offers_programme,
             exists (select 1 from b2b.partner_programmes pp join public.catalog_programs cp on cp.id = pp.programme_id
                      where pp.partner_id = pa.id and cp.university_id = e.university_id and pp.active and (pp.valid_to is null or pp.valid_to::date >= e.enrolled_on)) as offers_university
        from b2b.partners pa where pa.status in ('active', 'paused')
    loop
      continue when not (p.offers_programme or p.offers_university);
      v_list := v_list || jsonb_build_object('partner_id', p.id, 'name', p.name, 'offers_programme', p.offers_programme);
    end loop;
  exception when undefined_table or undefined_column or invalid_schema_name then
    v_err := 'partner catalogue not readable: ' || sqlerrm;
    v_list := '[]';
  end;
  if e.programme_id is not null and exists (select 1 from jsonb_array_elements(v_list) x where (x ->> 'offers_programme')::boolean) then
    v_src := 'partner';
    v_list := (select jsonb_agg(x) from jsonb_array_elements(v_list) x where (x ->> 'offers_programme')::boolean);
  elsif jsonb_array_length(v_list) > 0 then
    v_src := 'university_highest';
  else
    v_src := 'none';
  end if;
  -- each partner's rate and amount
  if v_src <> 'none' then
    v_list := (select jsonb_agg(x || jsonb_build_object('rate', r1.r, 'computed', b2c.rate_amount(e.id, r1.r)))
                 from jsonb_array_elements(v_list) x,
                      lateral (select b2c.partner_rate_pick((x ->> 'partner_id')::bigint, e.programme_id, e.university_id, e.enrolled_on, v_src = 'partner') as r) r1);
    select x into v_best from jsonb_array_elements(v_list) x where x -> 'computed' ->> 'amount' is not null
     order by (x -> 'computed' ->> 'amount')::numeric desc, (x ->> 'partner_id')::bigint limit 1;
  end if;
  if v_best is null then
    select * into f from b2c.commission_fallbacks where university_id = e.university_id;
    if f.university_id is not null then
      r := jsonb_build_object('scope', 'fallback', 'rate_type', f.rate_type, 'value', f.value, 'fee_base', f.fee_base, 'reason', f.reason, 'set_at', f.set_at);
      a := b2c.rate_amount(e.id, r);
      return jsonb_build_object('source', 'fallback', 'partners', v_list, 'used', jsonb_build_object('rate', r, 'computed', a), 'read_at', now(), 'error', v_err,
                                'university_had_partners', v_src <> 'none');
    end if;
    return jsonb_build_object('source', 'none', 'partners', v_list, 'used', null, 'read_at', now(), 'error', v_err);
  end if;
  return jsonb_build_object('source', v_src, 'partners', v_list, 'used', v_best, 'read_at', now(), 'error', v_err);
end $f$;

/* The override in force for this counsellor and programme: both named first, then the counsellor's, then the programme's. */
create or replace function b2c.commission_override_for(p_counsellor uuid, p_programme bigint, p_on date) returns b2c.commission_overrides
language sql stable security definer set search_path = '' as $f$
  select o.* from b2c.commission_overrides o
   where o.retired_at is null and o.valid_from <= p_on and (o.valid_to is null or o.valid_to >= p_on)
     and (o.counsellor_id is null or o.counsellor_id = p_counsellor) and (o.programme_id is null or o.programme_id = p_programme)
   order by (o.counsellor_id is not null and o.programme_id is not null) desc, (o.counsellor_id is not null) desc, o.valid_from desc, o.id desc limit 1
$f$;

create or replace function b2c.commission_status_for(p_enrollment bigint) returns text language sql stable security definer set search_path = '' as $f$
  select case when e.status = 'verified' then case when e.enrolled_on + b2c.refund_days(e.university_id) <= current_date then 'due' else 'confirmed' end else 'provisional' end
    from b2c.enrollments e where e.id = p_enrollment
$f$;

-- ---------- booking ----------
/* Books what the counsellor owes for an enrollment, with the rate snapshot. Once per enrollment while a line is open. */
create or replace function b2c.commission_book(p_enrollment bigint, p_reason text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare e b2c.enrollments; pr jsonb; o b2c.commission_overrides; v_amount numeric; v_base numeric; v_source text; v_status text; c jsonb; v bigint;
        v_tds_pct numeric := coalesce((b2c.setting('money') ->> 'tds_counsellor_pct')::numeric, 0); v_test boolean;
begin
  select * into e from b2c.enrollments where id = p_enrollment;
  if e.id is null or e.counsellor_id is null or e.status in ('cancelled', 'refunded') then return null; end if;
  if exists (select 1 from b2c.commission_lines l where l.enrollment_id = e.id and l.kind = 'booking' and l.status <> 'void') then return null; end if;
  select coalesce(s.is_test, false) into v_test from b2c.leads_state s where s.lead_id = e.lead_id;
  pr := case when e.university_id is null then jsonb_build_object('source', 'none', 'partners', '[]'::jsonb, 'error', 'enrollment not linked to the catalogue', 'read_at', now())
             else b2c.partner_rates_for(e.id) end;
  o := b2c.commission_override_for(e.counsellor_id, e.programme_id, e.enrolled_on);
  if o.id is not null then
    c := b2c.rate_amount(e.id, jsonb_build_object('rate_type', o.rate_type, 'value', o.value, 'fee_base', o.fee_base));
    v_amount := (c ->> 'amount')::numeric; v_base := (c ->> 'base')::numeric; v_source := 'override';
  elsif pr ->> 'source' = 'none' then
    v_amount := null; v_source := 'none';
  else
    v_amount := (pr -> 'used' -> 'computed' ->> 'amount')::numeric; v_base := (pr -> 'used' -> 'computed' ->> 'base')::numeric; v_source := pr ->> 'source';
  end if;
  v_status := case when v_amount is null then 'needs_rate' else b2c.commission_status_for(e.id) end;
  insert into b2c.commission_lines (enrollment_id, lead_id, counsellor_id, kind, status, amount, tds, base_amount, rate_source, flagged, snapshot, override_id, due_on, is_test, reason, actor_id)
  values (e.id, e.lead_id, e.counsellor_id, 'booking', v_status, v_amount, case when v_amount is null then 0 else round(v_amount * v_tds_pct / 100, 2) end, v_base, v_source,
          v_source in ('university_highest', 'fallback') or (pr -> 'used' -> 'computed' ->> 'note') is not null,
          pr || jsonb_build_object('programme', e.programme, 'programme_id', e.programme_id, 'university', e.university, 'university_id', e.university_id,
                                   'enrolled_on', e.enrolled_on, 'fee', e.fee, 'override', case when o.id is not null then to_jsonb(o) end, 'computed', c),
          o.id, e.enrolled_on + b2c.refund_days(e.university_id), v_test, p_reason, b2c.uid())
  returning id into v;
  if v_amount is null then
    perform b2c.notify_admins('money', 'Commission needs a rate', coalesce(e.university, 'University') || ' · ' || e.programme || ': no partner offers it. Set a rate on Money → Counsellor commission.',
                              '/w/money?tab=commission', e.lead_id, 'needs-rate:' || coalesce(e.university_id::text, e.university));
  end if;
  return v;
end $f$;

/* Reverses an enrollment's open lines: unsettled ones are voided by a matching line; settled ones get a clawback that
   joins the next run. */
create or replace function b2c.commission_reverse(p_enrollment bigint, p_reason text) returns int language plpgsql security definer set search_path = '' as $f$
declare l b2c.commission_lines; n int := 0;
begin
  for l in select * from b2c.commission_lines x where x.enrollment_id = p_enrollment and x.kind in ('booking', 'adjustment') and x.status <> 'void'
            and not exists (select 1 from b2c.commission_lines y where y.reverses_id = x.id) order by x.id loop
    if l.status = 'settled' then
      insert into b2c.commission_lines (enrollment_id, lead_id, counsellor_id, kind, status, amount, tds, base_amount, rate_source, snapshot, reverses_id, due_on, is_test, reason, actor_id)
      values (l.enrollment_id, l.lead_id, l.counsellor_id, 'clawback', 'due', -l.amount, -l.tds, l.base_amount, 'reversal', jsonb_build_object('reverses', l.id, 'settled_in_run', l.run_id),
              l.id, current_date, l.is_test, p_reason, b2c.uid());
    else
      update b2c.commission_lines set status = 'void', run_id = null where id = l.id;
      if l.amount is not null then
        insert into b2c.commission_lines (enrollment_id, lead_id, counsellor_id, kind, status, amount, tds, base_amount, rate_source, snapshot, reverses_id, due_on, is_test, reason, actor_id)
        values (l.enrollment_id, l.lead_id, l.counsellor_id, 'reversal', 'void', -l.amount, -l.tds, l.base_amount, 'reversal', jsonb_build_object('reverses', l.id),
                l.id, l.due_on, l.is_test, p_reason, b2c.uid());
      end if;
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

/* Enrollment changes: a new enrollment books; verification confirms (or makes due); a cancellation reverses. */
create or replace function b2c.enrollments_commission() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if tg_op = 'INSERT' then
    perform b2c.commission_book(new.id);
  elsif new.status is distinct from old.status then
    if new.status = 'verified' then
      update b2c.commission_lines set status = b2c.commission_status_for(new.id)
       where enrollment_id = new.id and status = 'provisional';
    elsif new.status = 'cancelled' then
      perform b2c.commission_reverse(new.id, 'enrollment cancelled');
    end if;
  end if;
  return null;
end $f$;
do $d$
begin
  if not exists (select 1 from pg_trigger where tgname = 'enrollments_commission') then
    create trigger enrollments_commission after insert or update of status on b2c.enrollments for each row execute function b2c.enrollments_commission();
  end if;
end $d$;

-- ---------- Admin actions ----------
/* A refund: inside the university's refund window both commissions are reversed (the university's with a negative line,
   the counsellor's voided or clawed back); outside it nothing is reversed. */
create or replace function b2c.enrollment_refund(p_id bigint, p_on date, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); e b2c.enrollments; v_inside boolean; n1 int := 0; n2 int := 0;
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  select * into e from b2c.enrollments where id = p_id for update;
  if e.id is null or e.status not in ('reported', 'verified') then raise exception 'this enrollment cannot be refunded'; end if;
  v_inside := coalesce(p_on, current_date) <= e.enrolled_on + b2c.refund_days(e.university_id);
  update b2c.enrollments set status = 'refunded', refunded_on = coalesce(p_on, current_date), refund_reason = p_reason, updated_at = now() where id = p_id;
  if v_inside then
    n1 := b2c.earning_reverse(p_id, 'refund', 'refund: ' || p_reason);
    n2 := b2c.commission_reverse(p_id, 'refund: ' || p_reason);
  end if;
  update b2c.leads_state set sub_stage = 'Refunded', stage_changed_at = now() where lead_id = e.lead_id;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (e.lead_id, 'enrollment', 'Refund recorded' || case when v_inside then ' inside the refund window: commissions reversed' else ' after the refund window' end || ': ' || p_reason,
          jsonb_build_object('enrollment_id', p_id), me);
  perform b2c.queue_update(e.lead_id, jsonb_build_object('enrollment_status', 'refunded'), false);
  if e.counsellor_id is not null and v_inside then
    perform b2c.notify(e.counsellor_id, 'commission', 'Enrollment refunded', e.university || ' · ' || e.programme || ': the commission line is reversed', '/s/money', e.lead_id, 'refund:' || p_id);
  end if;
  return jsonb_build_object('inside_window', v_inside, 'university_lines', n1, 'counsellor_lines', n2);
end $f$;

create or replace function b2c.commission_fallback_save(p jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v_uni bigint := (p ->> 'university_id')::bigint; l record; n int := 0;
begin
  if length(coalesce(trim(p ->> 'reason'), '')) < 3 then raise exception 'say where the rate comes from'; end if;
  if p ->> 'rate_type' = 'percent' and (p ->> 'value')::numeric > 100 then raise exception 'a percent is between 0 and 100'; end if;
  insert into b2c.commission_fallbacks as f (university_id, rate_type, fee_base, value, reason, set_by)
  values (v_uni, p ->> 'rate_type', coalesce(p ->> 'fee_base', 'first_year'), (p ->> 'value')::numeric, p ->> 'reason', me)
  on conflict (university_id) do update set rate_type = excluded.rate_type, fee_base = excluded.fee_base, value = excluded.value, reason = excluded.reason, set_by = me, set_at = now();
  perform b2c.log('money.commission_fallback_saved', null, p);
  -- lines waiting for this university's rate are booked now
  for l in select x.id, x.enrollment_id from b2c.commission_lines x join b2c.enrollments e on e.id = x.enrollment_id
            where x.status = 'needs_rate' and e.university_id = v_uni loop
    update b2c.commission_lines set status = 'void' where id = l.id;
    perform b2c.commission_book(l.enrollment_id, 'rate set by the Admin');
    n := n + 1;
  end loop;
  return n;
end $f$;

create or replace function b2c.commission_override_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); v bigint;
begin
  if length(coalesce(trim(p ->> 'reason'), '')) < 3 then raise exception 'give the reason: the counsellor sees it on the line'; end if;
  if p ->> 'rate_type' = 'percent' and (p ->> 'value')::numeric > 100 then raise exception 'a percent is between 0 and 100'; end if;
  if nullif(p ->> 'counsellor_id', '') is null and nullif(p ->> 'programme_id', '') is null then raise exception 'pick a counsellor, a programme or both'; end if;
  insert into b2c.commission_overrides (counsellor_id, programme_id, rate_type, fee_base, value, valid_from, valid_to, reason, created_by)
  values (nullif(p ->> 'counsellor_id', '')::uuid, nullif(p ->> 'programme_id', '')::bigint, p ->> 'rate_type', coalesce(p ->> 'fee_base', 'first_year'),
          (p ->> 'value')::numeric, coalesce(nullif(p ->> 'valid_from', '')::date, current_date), nullif(p ->> 'valid_to', '')::date, p ->> 'reason', me)
  returning id into v;
  perform b2c.log('money.commission_override_saved', null, p || jsonb_build_object('override_id', v));
  return v;
end $f$;

create or replace function b2c.commission_override_retire(p_id bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  update b2c.commission_overrides set retired_at = now(), reason = reason || ' · retired: ' || p_reason where id = p_id and retired_at is null;
  perform b2c.log('money.commission_override_retired', null, jsonb_build_object('override_id', p_id, 'reason', p_reason));
end $f$;

/* A one-off adjustment on an enrollment (positive: owes more; negative: owes less), with a reason the counsellor sees. */
create or replace function b2c.commission_adjust(p_enrollment bigint, p_amount numeric, p_reason text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); e b2c.enrollments; v bigint; v_test boolean;
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give the reason: the counsellor sees it on the line'; end if;
  if coalesce(p_amount, 0) = 0 then raise exception 'enter the amount'; end if;
  select * into e from b2c.enrollments where id = p_enrollment;
  if e.id is null or e.counsellor_id is null or e.status not in ('reported', 'verified') then raise exception 'this enrollment has no open commission'; end if;
  select coalesce(s.is_test, false) into v_test from b2c.leads_state s where s.lead_id = e.lead_id;
  insert into b2c.commission_lines (enrollment_id, lead_id, counsellor_id, kind, status, amount, base_amount, rate_source, snapshot, due_on, is_test, reason, actor_id)
  values (e.id, e.lead_id, e.counsellor_id, 'adjustment', b2c.commission_status_for(e.id), round(p_amount, 2), null, 'adjustment',
          jsonb_build_object('programme', e.programme, 'university', e.university, 'adjustment', true), e.enrolled_on + b2c.refund_days(e.university_id), v_test, p_reason, me)
  returning id into v;
  perform b2c.log('money.commission_adjusted', e.lead_id, jsonb_build_object('line_id', v, 'amount', p_amount, 'reason', p_reason));
  return v;
end $f$;

/* Rebook both commissions of an enrollment at the rates in force for its date (after a catalogue link, an override, or a
   rate the partner corrected). A counsellor line already settled stays; use an adjustment for it. */
create or replace function b2c.money_rebook(p_id bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('money');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  perform b2c.earning_reverse(p_id, 'reversal', 'rebook: ' || p_reason);
  perform b2c.earning_book(p_id, 'rebook: ' || p_reason);
  if exists (select 1 from b2c.commission_lines where enrollment_id = p_id and kind = 'booking' and status = 'settled') then
    raise exception 'the counsellor''s line is already settled: add an adjustment instead';
  end if;
  perform b2c.commission_reverse(p_id, 'rebook: ' || p_reason);
  perform b2c.commission_book(p_id, 'rebook: ' || p_reason);
end $f$;

-- ---------- runs ----------
create or replace function b2c.run_totals(p_run bigint) returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('lines', count(*), 'counsellors', count(distinct counsellor_id), 'amount', coalesce(sum(amount), 0), 'tds', coalesce(sum(tds), 0),
                            'net', coalesce(sum(amount - tds), 0), 'clawbacks', coalesce(sum(amount) filter (where kind = 'clawback'), 0),
                            'adjustments', coalesce(sum(amount) filter (where kind = 'adjustment'), 0))
    from b2c.commission_lines where run_id = p_run
$f$;

/* A draft run for a month: every due line not yet in a run (clawbacks included). Real leads, or test leads only when
   p_test (test mode). */
create or replace function b2c.commission_run_prepare(p_period date, p_test boolean default false) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint; v_period date := date_trunc('month', p_period)::date;
begin
  if b2c.uid() is not null then perform b2c.require('money'); end if;
  if exists (select 1 from b2c.commission_runs where status = 'draft' and is_test = p_test) then raise exception 'finish or cancel the open draft run first'; end if;
  insert into b2c.commission_runs (period, is_test, created_by) values (v_period, p_test, b2c.uid()) returning id into v;
  update b2c.commission_lines set run_id = v
   where status = 'due' and run_id is null and is_test = p_test;
  update b2c.commission_runs set totals = b2c.run_totals(v) where id = v;
  perform b2c.notify_admins('money', 'Commission run ready to review', to_char(v_period, 'Mon YYYY'), '/w/money?tab=runs', null, 'run:' || v);
  return v;
end $f$;

create or replace function b2c.commission_run_release(p_run bigint, p_line bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  if not exists (select 1 from b2c.commission_runs where id = p_run and status = 'draft') then raise exception 'only a draft run can change'; end if;
  update b2c.commission_lines set run_id = null where id = p_line and run_id = p_run;
  update b2c.commission_runs set totals = b2c.run_totals(p_run) where id = p_run;
  perform b2c.log('money.run_line_released', null, jsonb_build_object('run_id', p_run, 'line_id', p_line, 'reason', p_reason));
end $f$;

create or replace function b2c.commission_run_approve(p_run bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); t jsonb; c record;
begin
  if not exists (select 1 from b2c.commission_runs where id = p_run and status = 'draft') then raise exception 'only a draft run can be approved'; end if;
  update b2c.commission_lines set status = 'settled' where run_id = p_run;
  t := b2c.run_totals(p_run);
  update b2c.commission_runs set status = 'approved', approved_by = me, approved_at = now(), totals = t where id = p_run;
  for c in select counsellor_id, sum(amount - tds) as owed from b2c.commission_lines where run_id = p_run group by counsellor_id loop
    perform b2c.notify(c.counsellor_id, 'commission', 'Commission statement ready', 'Settled in this run: ₹' || to_char(c.owed, 'FM99,99,99,990.00'), '/s/money', null, 'run-stmt:' || p_run);
  end loop;
  perform b2c.log('money.run_approved', null, jsonb_build_object('run_id', p_run) || t);
  return t;
end $f$;

create or replace function b2c.commission_run_cancel(p_run bigint, p_reason text) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money');
begin
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  if not exists (select 1 from b2c.commission_runs where id = p_run and status = 'draft') then raise exception 'only a draft run can be cancelled'; end if;
  update b2c.commission_lines set run_id = null where run_id = p_run;
  update b2c.commission_runs set status = 'cancelled', note = p_reason where id = p_run;
end $f$;

/* A run as the Admin reviews it and as finance gets it: per counsellor, every line with the enrollment and the rate. */
create or replace function b2c.commission_run_view(p_run bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return (select to_jsonb(r) || jsonb_build_object('counsellors', (
      select coalesce(jsonb_agg(x order by x ->> 'name'), '[]') from (
        select jsonb_build_object('counsellor_id', l.counsellor_id, 'name', u.full_name, 'email', u.email, 'amount', sum(l.amount), 'tds', sum(l.tds), 'net', sum(l.amount - l.tds),
                 'lines', jsonb_agg(b2c.commission_line_json(l.id) order by l.id)) x
          from b2c.commission_lines l join b2c.users u on u.user_id = l.counsellor_id where l.run_id = r.id group by l.counsellor_id, u.full_name, u.email) s))
    from b2c.commission_runs r where r.id = p_run);
end $f$;

/* One line as the screens show it: the enrollment, the rate used, the partners considered, any override. */
create or replace function b2c.commission_line_json(p_line bigint) returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('id', l.id, 'kind', l.kind, 'status', l.status, 'amount', l.amount, 'tds', l.tds, 'base', l.base_amount, 'rate_source', l.rate_source, 'flagged', l.flagged,
           'reason', l.reason, 'due_on', l.due_on, 'run_id', l.run_id, 'created_at', l.created_at, 'enrollment_id', l.enrollment_id, 'lead_id', l.lead_id,
           'counsellor_id', l.counsellor_id, 'student', r.record -> 'student' ->> 'name', 'university', e.university, 'programme', e.programme, 'enrolled_on', e.enrolled_on,
           'fee', e.fee, 'enrollment_status', e.status,
           'rate', case when l.rate_source = 'override' then l.snapshot -> 'computed' else l.snapshot -> 'used' -> 'computed' end,
           'rate_used', l.snapshot -> 'used', 'partners', coalesce(l.snapshot -> 'partners', '[]'), 'override', l.snapshot -> 'override',
           'expected_settlement', case when l.status in ('settled', 'void') then null
                                       else (date_trunc('month', greatest(coalesce(l.due_on, current_date), current_date)) + interval '1 month')::date
                                            + (coalesce((b2c.setting('money') ->> 'run_day')::int, 5) - 1) end)
    from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id left join b2c.lead_records r on r.lead_id = l.lead_id
   where l.id = p_line
$f$;

-- ---------- dashboards (B11.3) ----------
/* The counsellor's own commission (an Admin may pass a counsellor; Marketing reads). */
create or replace function b2c.my_commission(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_user uuid := coalesce(nullif(p ->> 'user_id', '')::uuid, b2c.uid());
        m0 date := date_trunc('month', (now() at time zone 'Asia/Kolkata')::date)::date; y0 date;
begin
  if v_user <> b2c.uid() and not b2c.can('read_money') then raise exception 'not allowed'; end if;
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  y0 := case when extract(month from m0) >= 4 then make_date(extract(year from m0)::int, 4, 1) else make_date(extract(year from m0)::int - 1, 4, 1) end;
  return jsonb_build_object(
    'user_id', v_user, 'name', (select full_name from b2c.users where user_id = v_user),
    'month', m0,
    'tiles', (select jsonb_build_object(
                'provisional', coalesce(sum(l.amount) filter (where l.status = 'provisional'), 0), 'confirmed', coalesce(sum(l.amount) filter (where l.status = 'confirmed'), 0),
                'due', coalesce(sum(l.amount) filter (where l.status = 'due'), 0), 'settled', coalesce(sum(l.amount) filter (where l.status = 'settled'), 0),
                'needs_rate', count(*) filter (where l.status = 'needs_rate'))
                from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id
               where l.counsellor_id = v_user and l.status <> 'void' and e.enrolled_on >= m0 and not l.is_test),
    'year_to_date', (select coalesce(sum(l.amount), 0) from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id
                      where l.counsellor_id = v_user and l.status <> 'void' and e.enrolled_on >= y0 and not l.is_test),
    'lines', (select coalesce(jsonb_agg(b2c.commission_line_json(l.id) order by l.created_at desc), '[]') from (
                select id, created_at from b2c.commission_lines where counsellor_id = v_user and status <> 'void' order by created_at desc limit 500) l),
    'by_university', (select coalesce(jsonb_agg(jsonb_build_object('university', u, 'amount', a, 'enrollments', n) order by a desc), '[]') from (
                       select e.university u, sum(l.amount) a, count(distinct e.id) n from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id
                        where l.counsellor_id = v_user and l.status <> 'void' and e.enrolled_on >= y0 and not l.is_test group by e.university) s),
    'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', mo, 'amount', coalesce(a, 0), 'settled', coalesce(st, 0)) order by mo), '[]') from (
                   select g.mo, sum(l.amount) a, sum(l.amount) filter (where l.status = 'settled') st
                     from generate_series(m0 - interval '11 months', m0, interval '1 month') g(mo)
                     left join b2c.enrollments e on date_trunc('month', e.enrolled_on) = g.mo
                     left join b2c.commission_lines l on l.enrollment_id = e.id and l.counsellor_id = v_user and l.status <> 'void' and not l.is_test
                    group by g.mo) s),
    'target', (select jsonb_build_object('commission', (u.monthly_target ->> 'commission')::numeric, 'enrollments', (u.monthly_target ->> 'enrollments')::int,
                 'enrollments_done', (select count(*) from b2c.enrollments e where e.counsellor_id = v_user and e.enrolled_on >= m0 and e.status in ('reported', 'verified')))
                 from b2c.users u where u.user_id = v_user),
    'statements', (select coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'period', r.period, 'approved_at', r.approved_at,
                     'amount', (select sum(amount - tds) from b2c.commission_lines x where x.run_id = r.id and x.counsellor_id = v_user)) order by r.period desc), '[]')
                     from b2c.commission_runs r where r.status = 'approved' and not r.is_test and exists (select 1 from b2c.commission_lines x where x.run_id = r.id and x.counsellor_id = v_user)));
end $f$;

/* A counsellor's statement for one run (their own; the Admin and Marketing any). */
create or replace function b2c.commission_statement(p_run bigint, p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_user uuid := coalesce(p_user, b2c.uid());
begin
  if not b2c.is_staff() or (v_user <> b2c.uid() and not b2c.can('read_money')) then raise exception 'not allowed'; end if;
  return (select jsonb_build_object('run_id', r.id, 'period', r.period, 'status', r.status, 'approved_at', r.approved_at,
            'counsellor', (select jsonb_build_object('name', full_name, 'email', email) from b2c.users where user_id = v_user),
            'lines', (select coalesce(jsonb_agg(b2c.commission_line_json(l.id) order by l.id), '[]') from b2c.commission_lines l where l.run_id = r.id and l.counsellor_id = v_user),
            'amount', (select coalesce(sum(amount), 0) from b2c.commission_lines where run_id = r.id and counsellor_id = v_user),
            'tds', (select coalesce(sum(tds), 0) from b2c.commission_lines where run_id = r.id and counsellor_id = v_user),
            'open', (select coalesce(sum(amount), 0) from b2c.commission_lines where counsellor_id = v_user and status in ('provisional', 'confirmed', 'due') and not is_test))
            from b2c.commission_runs r where r.id = p_run);
end $f$;

/* The partner-rate table per programme, highest marked (from the same reader the lines use). */
create or replace function b2c.partner_rate_table(p_university bigint default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  begin
    select coalesce(jsonb_agg(x order by x ->> 'university', x ->> 'programme'), '[]') into v from (
      select jsonb_build_object('programme_id', cp.id, 'programme', coalesce(cp.program_name, cp.course) || coalesce(' · ' || cp.specialization, ''), 'university', un.name,
               'university_id', un.id, 'fee_yearly', cp.fee_yearly, 'fee_total', cp.fee_total,
               'partners', (select jsonb_agg(jsonb_build_object('partner_id', pa.id, 'name', coalesce(pa.display_name, pa.name),
                                     'rate', b2c.partner_rate_pick(pa.id, cp.id, cp.university_id, current_date, true)) order by pa.id)
                              from b2b.partners pa where pa.status in ('active', 'paused')
                               and exists (select 1 from b2b.partner_programmes pp where pp.partner_id = pa.id and pp.programme_id = cp.id and pp.active))) x
        from public.catalog_programs cp join public.catalog_universities un on un.id = cp.university_id
       where cp.active and (p_university is null or cp.university_id = p_university)
         and exists (select 1 from b2b.partner_programmes pp where pp.programme_id = cp.id and pp.active)
       limit 1000) s;
  exception when undefined_table or undefined_column or invalid_schema_name then
    return jsonb_build_object('error', 'the partner catalogue is not readable', 'rows', '[]'::jsonb);
  end;
  return jsonb_build_object('rows', v, 'changes', (select coalesce(jsonb_agg(jsonb_build_object('at', ev.at, 'detail', ev.payload) order by ev.at desc), '[]')
                                                     from (select * from b2c.events where type = 'money.partner_rate_changed' order by at desc limit 20) ev));
end $f$;

/* The Admin's money dashboard (Marketing reads it). Every figure carries what opens the enrollments behind it. */
create or replace function b2c.money_admin(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_from date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', current_date) - interval '11 months')::date);
        v_to date := coalesce(nullif(p ->> 'to', '')::date, current_date);
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'from', v_from, 'to', v_to,
    'university', (select coalesce(jsonb_agg(jsonb_build_object('month', mo, 'university_id', uid, 'university', un.name, 'expected_gross', eg, 'realised_gross', rg,
                       'gross', g, 'gst', t, 'net', n) order by mo, un.name), '[]')
                     from (select e.period mo, e.university_id uid, sum(e.gross) filter (where e.realised_at is null) eg, sum(e.gross) filter (where e.realised_at is not null) rg,
                                  sum(e.gross) g, sum(e.gst) t, sum(e.net) n
                             from b2c.earnings e where e.period between date_trunc('month', v_from) and v_to and not e.is_test
                            group by e.period, e.university_id) s left join public.catalog_universities un on un.id = s.uid),
    'counsellor', (select coalesce(jsonb_agg(jsonb_build_object('counsellor_id', cid, 'name', u.full_name, 'month', mo, 'status', st, 'amount', a, 'lines', n)
                       order by u.full_name, mo, st), '[]')
                     from (select l.counsellor_id cid, date_trunc('month', en.enrolled_on)::date mo, l.status st, sum(l.amount) a, count(*) n
                             from b2c.commission_lines l join b2c.enrollments en on en.id = l.enrollment_id
                            where l.status <> 'void' and not l.is_test and en.enrolled_on between v_from and v_to group by 1, 2, 3) s join b2c.users u on u.user_id = s.cid),
    'side_by_side', (select coalesce(jsonb_agg(jsonb_build_object('university_id', uid, 'university', un.name, 'enrollments', n, 'university_net', un_net,
                         'university_gross', un_gross, 'counsellor_owed', co) order by un.name), '[]')
                       from (select en.university_id uid, count(*) n,
                                    (select sum(x.net) from b2c.earnings x join b2c.enrollments y on y.id = x.enrollment_id where y.university_id = en.university_id and y.enrolled_on between v_from and v_to) un_net,
                                    (select sum(x.gross) from b2c.earnings x join b2c.enrollments y on y.id = x.enrollment_id where y.university_id = en.university_id and y.enrolled_on between v_from and v_to) un_gross,
                                    (select sum(l.amount) from b2c.commission_lines l join b2c.enrollments y on y.id = l.enrollment_id
                                      where y.university_id = en.university_id and y.enrolled_on between v_from and v_to and l.status <> 'void' and not l.is_test) co
                               from b2c.enrollments en join b2c.leads_state s on s.lead_id = en.lead_id and not s.is_test
                              where en.enrolled_on between v_from and v_to and en.status in ('reported', 'verified') group by en.university_id) q
                       left join public.catalog_universities un on un.id = q.uid),
    'enrollments', (select coalesce(jsonb_agg(x order by x ->> 'enrolled_on' desc), '[]') from (
                      select jsonb_build_object('enrollment_id', en.id, 'lead_id', en.lead_id, 'student', r.record -> 'student' ->> 'name', 'university', en.university,
                               'university_id', en.university_id, 'programme_id', en.programme_id, 'programme', en.programme, 'enrolled_on', en.enrolled_on, 'status', en.status, 'fee', en.fee,
                               'counsellor', u.full_name,
                               'university_gross', (select sum(gross) from b2c.earnings where enrollment_id = en.id),
                               'university_net', (select sum(net) from b2c.earnings where enrollment_id = en.id),
                               'counsellor_owed', (select sum(amount) from b2c.commission_lines where enrollment_id = en.id and status <> 'void'),
                               'commission_status', (select string_agg(distinct status, ', ') from b2c.commission_lines where enrollment_id = en.id and status <> 'void')) x
                        from b2c.enrollments en join b2c.leads_state s on s.lead_id = en.lead_id and not s.is_test
                        left join b2c.lead_records r on r.lead_id = en.lead_id left join b2c.users u on u.user_id = en.counsellor_id
                       where en.enrolled_on between v_from and v_to order by en.enrolled_on desc limit 500) s),
    'needs_rate', (select coalesce(jsonb_agg(b2c.commission_line_json(l.id) order by l.created_at), '[]') from b2c.commission_lines l where l.status = 'needs_rate' and not l.is_test),
    'unlinked', (select coalesce(jsonb_agg(jsonb_build_object('enrollment_id', en.id, 'lead_id', en.lead_id, 'university', en.university, 'programme', en.programme,
                     'enrolled_on', en.enrolled_on) order by en.enrolled_on), '[]')
                   from b2c.enrollments en where (en.university_id is null or en.programme_id is null) and en.status in ('reported', 'verified')),
    'no_university_rate', (select coalesce(jsonb_agg(jsonb_build_object('enrollment_id', en.id, 'university', en.university, 'university_id', en.university_id, 'enrolled_on', en.enrolled_on)), '[]')
                             from b2c.enrollments en where en.university_id is not null and en.status in ('reported', 'verified')
                              and not exists (select 1 from b2c.earnings x where x.enrollment_id = en.id)),
    'receivables', b2c.receivables(null),
    'tier_watch', (select coalesce(jsonb_agg(jsonb_build_object('university_id', r.university_id, 'university', un.name, 'rate_id', r.id, 'tiers', r.tiers,
                       'now', b2c.period_conversion(r.university_id, date_trunc('month', current_date)::date),
                       'tier', b2c.tier_pick(r.tiers, (b2c.period_conversion(r.university_id, date_trunc('month', current_date)::date) ->> 'conversion')::numeric))), '[]')
                     from b2c.university_rates r left join public.catalog_universities un on un.id = r.university_id
                    where r.rate_type = 'tiered' and r.retired_at is null and r.valid_from <= current_date and (r.valid_to is null or r.valid_to >= current_date)),
    'statements', (select coalesce(jsonb_agg(jsonb_build_object('import_id', i.id, 'university', un.name, 'from', i.period_from, 'to', i.period_to, 'file', i.file_name, 'summary', i.summary,
                       'at', i.created_at) order by i.created_at desc), '[]')
                     from (select * from b2c.statement_imports order by created_at desc limit 20) i left join public.catalog_universities un on un.id = i.university_id),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'period', r.period, 'status', r.status, 'totals', r.totals, 'approved_at', r.approved_at) order by r.period desc), '[]')
               from b2c.commission_runs r where r.status <> 'cancelled' and not r.is_test),
    'next_run', (date_trunc('month', current_date + case when extract(day from current_date) > coalesce((b2c.setting('money') ->> 'run_day')::int, 5) then 31 else 0 end)::date
                 + (coalesce((b2c.setting('money') ->> 'run_day')::int, 5) - 1)),
    'settings', b2c.setting('money'));
end $f$;

create or replace function b2c.university_money(p_university bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'university', (select to_jsonb(un) - 'search_doc' from public.catalog_universities un where un.id = p_university),
    'billing', (select to_jsonb(b) from b2c.university_billing b where b.university_id = p_university),
    'rates', (select coalesce(jsonb_agg(to_jsonb(r) || jsonb_build_object('programme', coalesce(cp.program_name, cp.course)) order by r.valid_from desc, r.id desc), '[]')
                from b2c.university_rates r left join public.catalog_programs cp on cp.id = r.programme_id where r.university_id = p_university),
    'fallback', (select to_jsonb(f) from b2c.commission_fallbacks f where f.university_id = p_university),
    'closes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.period desc), '[]') from b2c.period_closes c where c.university_id = p_university),
    'invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'number', i.number, 'status', i.status, 'issue_date', i.issue_date, 'due_on', i.due_on,
                   'gross', i.gross, 'net', i.net, 'gst', i.gst, 'paid', b2c.invoice_paid(i.id)) order by i.id desc), '[]')
                   from b2c.invoices i where i.university_id = p_university and i.status <> 'discarded'),
    'uninvoiced', (select jsonb_build_object('lines', count(*), 'gross', coalesce(sum(gross), 0)) from b2c.earnings
                    where university_id = p_university and realised_at is not null and invoice_id is null and not is_test),
    'receipts', (select coalesce(jsonb_agg(to_jsonb(r) order by r.received_on desc), '[]') from b2c.receipts r where r.university_id = p_university),
    'programmes', (select coalesce(jsonb_agg(jsonb_build_object('id', cp.id, 'name', coalesce(cp.program_name, cp.course) || coalesce(' · ' || cp.specialization, '')) order by cp.course), '[]')
                     from public.catalog_programs cp where cp.university_id = p_university and cp.active));
end $f$;

-- ---------- daily job ----------
/* Daily: confirmed lines past their refund window become due; on the run day a draft run is prepared for last month;
   overdue invoices remind the Admin weekly; a changed partner rate is noted and the Admin told. */
create or replace function b2c.money_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare n_due int; v_run bigint; v_day int := coalesce((b2c.setting('money') ->> 'run_day')::int, 5); n_rem int := 0; n_rates int := 0; i record; k record; v_seed boolean;
begin
  update b2c.commission_lines set status = 'due' where status = 'confirmed' and due_on <= current_date;
  get diagnostics n_due = row_count;
  if extract(day from (now() at time zone 'Asia/Kolkata')) = v_day
     and not exists (select 1 from b2c.commission_runs where period = (date_trunc('month', current_date) - interval '1 month')::date and status <> 'cancelled' and not is_test)
     and not exists (select 1 from b2c.commission_runs where status = 'draft' and not is_test) then
    v_run := b2c.commission_run_prepare((date_trunc('month', current_date) - interval '1 month')::date);
  end if;
  for i in select inv.id, inv.number, inv.university_id, inv.due_on from b2c.invoices inv
            where inv.kind = 'invoice' and not inv.is_test and inv.status in ('approved', 'sent', 'part_paid') and inv.due_on < current_date
              and (inv.reminded_at is null or inv.reminded_at < now() - interval '7 days') loop
    perform b2c.notify_admins('money', 'Invoice overdue: ' || i.number, (current_date - i.due_on) || ' days past due', '/w/money?tab=receivables', null, 'overdue:' || i.id || ':' || current_date);
    update b2c.invoices set reminded_at = now() where id = i.id;
    n_rem := n_rem + 1;
  end loop;
  begin
    v_seed := not exists (select 1 from b2c.partner_rate_seen);
    for k in select 'rate:' || r.id as key, md5(concat_ws('|', r.scope, r.partner_id, r.programme_id, r.university_id, r.rate_type, r.fee_base, r.value, r.tiers, r.valid_from, r.valid_to)) as h,
                    jsonb_build_object('partner_id', r.partner_id, 'scope', r.scope, 'programme_id', r.programme_id, 'university_id', r.university_id, 'rate_type', r.rate_type, 'value', r.value) as d
               from b2b.rates r
             union all
             select 'pp:' || pp.id, md5(coalesce(pp.commission::text, '') || pp.active::text), jsonb_build_object('partner_id', pp.partner_id, 'programme_id', pp.programme_id, 'commission', pp.commission)
               from b2b.partner_programmes pp loop
      if not exists (select 1 from b2c.partner_rate_seen s where s.key = k.key and s.hash = k.h) then
        insert into b2c.partner_rate_seen (key, hash) values (k.key, k.h) on conflict (key) do update set hash = excluded.hash, seen_at = now();
        if not v_seed then
          insert into b2c.events (type, actor_type, payload) values ('money.partner_rate_changed', 'system', k.d || jsonb_build_object('key', k.key));
          n_rates := n_rates + 1;
        end if;
      end if;
    end loop;
    if n_rates > 0 then
      perform b2c.notify_admins('money', 'Partner rates changed', n_rates || ' partner rate rows changed. Booked lines keep their rates; later enrollments use the new ones.',
                                '/w/money?tab=rates', null, 'rates-changed:' || current_date);
    end if;
  exception when undefined_table or undefined_column or invalid_schema_name then null;
  end;
  return jsonb_build_object('due', n_due, 'run', v_run, 'reminders', n_rem, 'rate_changes', n_rates);
end $f$;

do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-money') then
    perform cron.schedule('b2c-money', '30 0 * * *', 'select b2c.money_tick()');   -- 06:00 IST
  end if;
end $d$;

-- ---------- the published view for the B2B CRM (B11.3, Phase 0 audit C15) ----------
create or replace view public.b2c_enrollment_money_v as
select 1 as view_version,
       en.lead_id, en.id as enrollment_id, en.enrolled_on, en.university, en.programme, en.status as enrollment_status,
       coalesce(sum(e.gross), 0)::numeric(12, 2) as university_commission_gross,
       coalesce(sum(e.gst), 0)::numeric(12, 2) as university_commission_gst,
       coalesce(sum(e.net), 0)::numeric(12, 2) as university_commission_net,
       case when count(e.id) = 0 then 'not_booked'
            when bool_and(e.invoice_id is not null) and bool_and(i.status = 'paid') then 'paid'
            when bool_or(e.invoice_id is not null) then 'invoiced'
            when bool_or(e.realised_at is not null) then 'realised'
            else 'expected' end as university_commission_status,
       (select string_agg(distinct i2.number, ', ') from b2c.earnings e2 join b2c.invoices i2 on i2.id = e2.invoice_id where e2.enrollment_id = en.id) as invoice,
       (select coalesce(sum(l.amount), 0) from b2c.commission_lines l where l.enrollment_id = en.id and l.status <> 'void')::numeric(12, 2) as counsellor_commission_total
  from b2c.enrollments en
  join b2c.leads_state s on s.lead_id = en.lead_id and not s.is_test
  left join b2c.earnings e on e.enrollment_id = en.id
  left join b2c.invoices i on i.id = e.invoice_id
 group by en.id;
revoke all on public.b2c_enrollment_money_v from public, anon, authenticated;
grant select on public.b2c_enrollment_money_v to service_role;

-- ---------- grants ----------
do $d$
declare t text;
begin
  foreach t in array array['commission_fallbacks', 'commission_overrides', 'commission_runs', 'partner_rate_seen'] loop
    execute format('alter table b2c.%I enable row level security', t);
    execute format('grant select on b2c.%I to authenticated', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = t and policyname = 'money read') then
      execute format('create policy "money read" on b2c.%I for select to authenticated using ((select b2c.can(''read_money'')))', t);
    end if;
  end loop;
  alter table b2c.commission_lines enable row level security;
  grant select on b2c.commission_lines to authenticated;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'commission_lines' and policyname = 'own or money read') then
    create policy "own or money read" on b2c.commission_lines for select to authenticated using ((select b2c.can('read_money')) or counsellor_id = (select b2c.uid()));
  end if;
end $d$;
grant execute on function b2c.enrollment_refund(bigint, date, text), b2c.commission_fallback_save(jsonb), b2c.commission_override_save(jsonb),
  b2c.commission_override_retire(bigint, text), b2c.commission_adjust(bigint, numeric, text), b2c.money_rebook(bigint, text), b2c.commission_run_prepare(date, boolean),
  b2c.commission_run_release(bigint, bigint, text), b2c.commission_run_approve(bigint), b2c.commission_run_cancel(bigint, text), b2c.commission_run_view(bigint),
  b2c.my_commission(jsonb), b2c.commission_statement(bigint, uuid), b2c.partner_rate_table(bigint), b2c.money_admin(jsonb), b2c.university_money(bigint) to authenticated;
revoke execute on function b2c.partner_rate_pick(bigint, bigint, bigint, date, boolean), b2c.rate_amount(bigint, jsonb), b2c.partner_rates_for(bigint),
  b2c.commission_override_for(uuid, bigint, date), b2c.commission_status_for(bigint), b2c.commission_book(bigint, text), b2c.commission_reverse(bigint, text),
  b2c.enrollments_commission(), b2c.run_totals(bigint), b2c.commission_line_json(bigint), b2c.money_tick() from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
