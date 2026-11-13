-- M34i (13 Nov 2026, audit hardening, approved by Vikas). Seven verified findings; every function below is its current
-- definition (the file named next to it) with only the change described there. Re-appliable (create or replace, if not
-- exists); no DROP. Checked by supabase/tests/test_m34i_hardening.sql (local: supabase/local-test.sh; staging: SQL editor).
--   0  http_maybe_delivered (new)      one rule for "the request may have reached the provider": no answer, a timeout, a 5xx,
--                                      or a transport error other than a failed DNS lookup or a refused connection
--   1  apply_duplicate (m31i)          a retried push answered "already exists" is not a duplicate when the claim names this
--                                      allocation's own reference or record, or an earlier attempt of this allocation may have
--                                      reached the partner (rule 0) and the partner's record is not more than 5 minutes older
--                                      than that attempt: the lead counts as created (the record id kept when given), the
--                                      allocation is flagged for a spot check and alert.push_retry_duplicate tells the Admin;
--                                      never re-routed
--   2  sign_in_locked(email, ip, step) the lock counts failures per email and client IP; the code step (after a correct
--      record_sign_in (m2b)            password) counts only failed codes, so strangers' wrong passwords never block it;
--                                      'locked' is logged at most once a minute per email; a malformed IP is stored as null
--   3  partner_event_ingest (m34c)     a partner's retry of an event that arrived before its record id was saved (stored as an
--                                      error with no allocation) is matched again and applied, instead of "already received"
--   4  receipt_record, receipt_apply (m20e), enrollment_verify, enrollment_refund, earning_manual (m20c), enrollment_record
--      (m31i)                          "today" is the date in India, not in UTC (00:00 to 05:30 IST was yesterday)
--   5  receipt_apply (m20e)            refuses a receipt that is not active once its row is locked (a void meanwhile)
--   6  notify_tick (m34e)              an answer that may mean "sent" (rule 0) is not sent again automatically, except by
--                                      Resend, which receives Idempotency-Key notify-<id> (notify_request, m9b) and so never
--                                      sends twice: failed, alerted with maybe_sent, "Send again" by hand
--   7  team_invite_accept (m33a)       the identity's email address must be confirmed
-- Deploy order: this migration before the web release that calls sign_in_locked(email, ip, step).
-- Rollback: re-run each function's create or replace from the file named above; b2b.sign_in_locked(text, text, text) and
-- b2b.http_maybe_delivered can stay (the old one-argument sign_in_locked is unchanged and the previous web release calls it).

-- ---------- (0) may the request have reached the provider? ----------
/* p_answered: a response row exists (pg_net wrote one). A failed DNS lookup or a refused connection never reached anyone;
   every other transport error (a reset or cut connection, an empty reply, a receive failure) may have. */
create or replace function b2b.http_maybe_delivered(p_answered boolean, p_timed_out boolean, p_status int, p_error text)
returns boolean language sql immutable set search_path = '' as $fn$
  select not coalesce(p_answered, false) or coalesce(p_timed_out, false) or coalesce(p_status, 0) >= 500
      or (p_status is null and p_error is not null
          and p_error !~* '(resolve|couldn''t connect|could not connect|failed to connect|connection refused)')
$fn$;
revoke execute on function b2b.http_maybe_delivered(boolean, boolean, int, text) from public, anon, authenticated;
grant execute on function b2b.http_maybe_delivered(boolean, boolean, int, text) to service_role;

-- ---------- (1) a retried push answered "duplicate" ----------
/* As m31i, plus the own-record rule before the duplicate rule. The idempotency key and X-Eduwit-Reference of every attempt is
   the allocation's reference, so a partner whose first attempt timed out after it created the lead answers the retry with
   "already exists": that existing record is this allocation's own, not an earlier student. It is our own when the claim names
   this allocation's reference (existing_reference) or the record id this allocation already has, or when an earlier attempt of
   this allocation may have reached the partner (http_maybe_delivered: a timeout, a 5xx, a cut connection) and the claim does not
   prove an older record (existing_created_at more than 5 minutes before the first such attempt). Then the lead counts as created
   (apply_created during the push; the hold window as usual), the claim is kept, spot_check is set and alert.push_retry_duplicate
   goes to the Admin. */
create or replace function b2b.apply_duplicate(p_allocation_id bigint, p_proof jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_existing text := coalesce(p_proof ->> 'existing_record_id', p_proof ->> 'existing_id');
  v_ref text := p_proof ->> 'existing_reference';
  pf jsonb;
  v_rid text;
  v_first timestamptz;
  v_why text;
  v_res text;
begin
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then return 'ignored: allocation not found'; end if;
  if a.status not in ('pushing', 'pushed') then return 'ignored: allocation is ' || a.status; end if;
  if exists (select 1 from b2b.allocations p where p.lead_id = a.lead_id and p.partner_id = a.partner_id and p.id <> a.id
               and ((v_existing is not null and p.partner_record_id = v_existing) or (v_ref is not null and p.reference = v_ref))) then
    update b2b.allocations set status = 'pushed', returning_lead = true, partner_record_id = coalesce(partner_record_id, v_existing),
           claim_proof = p_proof, pushed_at = coalesce(pushed_at, now()), push_request_id = null, hold_until = now() where id = a.id;
    update public.student_leads set stage = 'sent_to_partner', partner_record_id = coalesce(v_existing, partner_record_id), updated_by = 'b2b'
     where id = a.lead_id and allocation_id = a.id;
    perform b2b.accept_allocation(a.id);
    return 'accepted: returning Eduwit lead';
  end if;

  pf := b2b.claim_proof_normalize(coalesce(p_proof, '{}'), a.partner_id);
  -- M34i: this allocation's own record (see the comment above)
  v_rid := left(coalesce(v_existing, pf ->> 'existing_record_id'), 200);
  v_why := case
    when v_ref is not null and v_ref = a.reference then 'the claim names this allocation''s own reference'
    when v_rid is not null and v_rid = a.partner_record_id then 'the claim names the record this allocation already has'
  end;
  if v_why is null then
    select min(q.sent_at) into v_first
      from b2b.push_requests q
     where q.allocation_id = a.id and q.outcome in ('timeout', 'error')
       and b2b.http_maybe_delivered(q.outcome <> 'timeout', q.outcome = 'timeout', q.status_code, q.error);
    if v_first is not null and not coalesce((pf ->> 'existing_created_at')::timestamptz < v_first - interval '5 minutes', false) then
      v_why := 'an earlier attempt got no answer, so the partner may have created the lead then';
    end if;
  end if;
  if v_why is not null then
    if a.status = 'pushing' then
      v_res := b2b.apply_created(a.id, v_rid);
    else
      v_res := 'kept: still in the hold window';
      update b2b.allocations set partner_record_id = coalesce(partner_record_id, v_rid) where id = a.id;
    end if;
    update b2b.allocations set spot_check = true, claim_proof = p_proof,
           claim_existing_record_id = pf ->> 'existing_record_id', claim_existing_created_at = (pf ->> 'existing_created_at')::timestamptz
     where id = a.id;
    perform b2b.log_event('alert.push_retry_duplicate', a.lead_id, a.id, a.partner_id,
                          jsonb_build_object('why', v_why, 'reference', a.reference, 'record_id', v_rid, 'proof', p_proof, 'result', v_res,
                                             'check', 'confirm with the partner that this record is Eduwit''s lead ' || a.reference));
    return 'created: own record (' || v_why || ')';
  end if;

  if coalesce((pf ->> 'proof_ok')::boolean, false) then
    update b2b.allocations set status = 'duplicate', outcome = 'duplicate', outcome_at = now(), claim_proof = p_proof,
           claim_existing_record_id = pf ->> 'existing_record_id', claim_existing_created_at = (pf ->> 'existing_created_at')::timestamptz,
           claim_proof_ok = true, spot_check = random() < coalesce((e ->> 'duplicate_spot_check')::numeric, 0.05)
     where id = a.id;
    update public.student_leads set duplicate_claim_count = coalesce(duplicate_claim_count, 0) + 1 where id = a.lead_id;
    perform b2b.log_event('lead.duplicate', a.lead_id, a.id, a.partner_id, jsonb_build_object('proof', p_proof, 'reference', a.reference, 'proof_ok', true,
                          'existing_record_id', pf ->> 'existing_record_id', 'existing_created_at', pf -> 'existing_created_at'));
    perform b2b.reroute_after(a.id, 'duplicate at partner');
    return 'duplicate: re-routed';
  end if;

  -- PART 5.3 requires proof: an unproven claim is handled as a rejection (contract alert, excluded, an attempt, no bar)
  update b2b.allocations set status = 'rejected', outcome = 'rejected', outcome_at = now(), claim_proof = p_proof, claim_proof_ok = false,
         last_error = 'duplicate claim without proof' where id = a.id;
  perform b2b.log_event('alert.partner_rejected', a.lead_id, a.id, a.partner_id, jsonb_build_object('reason', 'duplicate claim without proof',
                        'contract_breach', true, 'why', 'duplicate claim without proof', 'reference', a.reference, 'claim', p_proof));
  perform b2b.reroute_after(a.id, 'duplicate claim without proof');
  return 'rejected: duplicate claim without proof';
end $fn$;

-- ---------- (2) sign-in lockout per email and client IP ----------
/* Replaces the app's use of sign_in_locked(email) (m2b), which a stranger could keep tripping for the Admin's address.
   p_step 'password': 5 failed passwords or codes in 15 minutes from this IP (a null IP is its own bucket), since the email's
   last success. p_step 'totp': 5 failed codes for the email from any IP in 15 minutes since its last success; only someone who
   passed the first factor can fail a code, so others' wrong passwords never block it. */
create or replace function b2b.sign_in_locked(p_email text, p_ip text, p_step text)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_ip inet;
  v_since timestamptz;
begin
  begin v_ip := nullif(trim(coalesce(p_ip, '')), '')::inet; exception when others then v_ip := null; end;
  select greatest(now() - interval '15 minutes', coalesce(max(s.at), '-infinity'::timestamptz)) into v_since
    from b2b.sign_in_log s where lower(s.email) = lower(p_email) and s.outcome = 'success';
  return (select count(*) >= 5
            from b2b.sign_in_log l
           where lower(l.email) = lower(p_email) and l.at > v_since
             and case when p_step = 'totp' then l.outcome = 'failed_totp'
                      else l.outcome in ('failed_password', 'failed_totp') and l.ip is not distinct from v_ip end);
end $fn$;

/* As m2b, plus: 'locked' is stored at most once a minute per email (returns null otherwise), and an IP that is not a valid
   address is stored as null instead of failing the write (a failure that is not logged would not count toward the lock). */
create or replace function b2b.record_sign_in(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_ip inet;
  v_id bigint;
begin
  if p ->> 'outcome' = 'locked'
     and exists (select 1 from b2b.sign_in_log l where lower(l.email) = lower(p ->> 'email') and l.outcome = 'locked'
                    and l.at > now() - interval '1 minute') then
    return null;
  end if;
  begin v_ip := nullif(p ->> 'ip', '')::inet; exception when others then v_ip := null; end;
  insert into b2b.sign_in_log (user_id, email, method, outcome, ip, user_agent, detail)
  values ((p ->> 'user_id')::uuid, lower(p ->> 'email'), p ->> 'method', p ->> 'outcome',
          v_ip, left(p ->> 'user_agent', 500), coalesce(p -> 'detail', '{}'))
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function b2b.sign_in_locked(text, text, text), b2b.record_sign_in(jsonb) from public, anon, authenticated;
grant execute on function b2b.sign_in_locked(text, text, text), b2b.record_sign_in(jsonb) to service_role;

-- ---------- (3) a partner's retry of an event that arrived too early ----------
/* As m34c, with the event_id conflict handled as described in the header. */
create or replace function b2b.partner_event_ingest(p_slug text, p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  j jsonb;
  a b2b.allocations;
  v_expected text;
  v_type text;
  v_event_id text;
  v_id bigint;
  v_ts bigint;
  x jsonb;
  v_retry boolean := false;
begin
  perform set_config('b2b.actor', 'partner', true);
  select * into p from b2b.partners where slug = lower(trim(p_slug));
  if p.id is null or p.inbound_secret_id is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'unknown partner'); end if;
  if length(coalesce(p_body, '')) > 200000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  v_expected := 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                    convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex');
  if p_signature is distinct from v_expected then
    perform b2b.log_auth_failure('alert.partner_bad_signature', p.id, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  -- find the allocation by our reference (EDW-<id>), else by the partner's record id
  select * into a from b2b.allocations x
   where x.partner_id = p.id and (x.reference = j ->> 'reference' or (j ->> 'record_id' is not null and x.partner_record_id = j ->> 'record_id'))
   order by x.created_at desc limit 1;

  insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
  values (p.id, v_event_id, v_type, j ->> 'reference', j ->> 'record_id', a.id, a.lead_id, j)
  on conflict (partner_id, event_id) do nothing
  returning id into v_id;
  if v_id is null then
    -- M34i: an event that arrived before its record id was saved is stored as an error with no allocation. The partner's
    -- retry (same event_id) is matched again and applied, as partner_event_retry does, instead of "already received".
    select x.id into v_id from b2b.partner_events x
     where x.partner_id = p.id and x.event_id = v_event_id and x.status = 'error' and x.allocation_id is null and x.discarded_at is null
     for update;
    if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;
    if a.id is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'no lead matches this reference'); end if;
    update b2b.partner_events set allocation_id = a.id, lead_id = a.lead_id, event_type = v_type, reference = j ->> 'reference',
           record_id = j ->> 'record_id', raw = j, result = null
     where id = v_id;
    v_retry := true;
  end if;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no lead matches this reference');
  end if;

  x := b2b.partner_event_apply(v_id);
  if v_retry then
    perform b2b.log_event('partner.event_retried', a.lead_id, a.id, p.id,
                          jsonb_build_object('partner_event_id', v_id, 'event_id', v_event_id, 'source', 'partner_retry',
                                             'status', x ->> 'status', 'result', x ->> 'result'));
  end if;
  if x ->> 'status' = 'error' then
    return jsonb_build_object('ok', false, 'status', 500, 'error', 'could not apply the event; it is stored and will be reviewed');
  end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', coalesce(x ->> 'result', 'stored'));
end $fn$;

-- ---------- (4) and (5) money dates in India's time zone; a voided receipt never settles ----------
/* Each as its file (m20e, m20c, m31i) with current_date replaced by (now() at time zone 'Asia/Kolkata')::date; receipt_apply also
   checks the receipt's status once it holds the row lock (receipt_allocate checked it before taking the lock). */
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
  -- M34i: checked after the row lock, so a receipt voided meanwhile can never settle an invoice
  if r.id is null or r.status is distinct from 'active' then raise exception 'receipt not found or void' using errcode = 'P0002'; end if;
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

create or replace function b2b.receipt_record(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_amt numeric := round(nullif(p ->> 'amount_inr', '')::numeric, 2);
  v_tds numeric := round(coalesce(nullif(p ->> 'tds_inr', '')::numeric, 0), 2);
  v_on date := coalesce(nullif(p ->> 'received_on', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  v_id bigint;
  v_inv bigint;
  v_used numeric := 0;
  i record;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_amt is null or v_amt <= 0 or v_amt > 100000000 then raise exception 'enter the amount received' using errcode = '22023'; end if;
  if v_tds < 0 or v_tds > v_amt then raise exception 'TDS cannot be negative or more than the amount' using errcode = '22023'; end if;
  if v_on > (now() at time zone 'Asia/Kolkata')::date then raise exception 'the date is in the future' using errcode = '22023'; end if;
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
  if v_on > (now() at time zone 'Asia/Kolkata')::date then raise exception 'the enrolment date is in the future' using errcode = '22023'; end if;
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

create or replace function b2b.enrollment_refund(p_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e public.enrollments;
  v_on date := coalesce(nullif(p ->> 'refunded_on', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  v_reason text := nullif(left(trim(p ->> 'reason'), 300), '');
  x b2b.earnings;
  v_total numeric := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into e from public.enrollments where id = p_id for update;
  if e.id is null or e.source_product is distinct from 'b2b' then raise exception 'enrollment not found' using errcode = 'P0002'; end if;
  if e.status <> 'verified' then raise exception 'only a verified enrollment can be refunded' using errcode = '22023'; end if;
  if v_on > (now() at time zone 'Asia/Kolkata')::date or v_on < e.enrolled_on then raise exception 'the refund date must be between the enrolment date and today' using errcode = '22023'; end if;
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
  values (v_enr.id, v_enr.allocation_id, v_partner, v_enr.lead_id, b2b.period_of((now() at time zone 'Asia/Kolkata')::date), 'manual_adjustment', 'realised', v_net, v_g,
          round(v_net * v_g, 2), v_net + round(v_net * v_g, 2), v_note, now(), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  perform b2b.log_event('money.adjustment', v_enr.lead_id, v_enr.allocation_id, v_partner, jsonb_build_object('earning_id', v_id, 'net_inr', v_net, 'note', v_note));
  return v_id;
end $fn$;

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
  x jsonb;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.partner_id is null then raise exception 'only partner allocations earn partner commission' using errcode = '22023'; end if;
  if a.is_test then raise exception 'test leads never earn commission' using errcode = '22023'; end if;
  if a.status not in ('pushed', 'accepted', 'closed') then raise exception 'the partner never held this lead (allocation is %)', a.status using errcode = '22023'; end if;
  select id into v_id from public.enrollments where allocation_id = a.id and status <> 'cancelled';
  if v_id is not null then return jsonb_build_object('id', v_id, 'existing', true); end if;

  -- PART 5.8: an upheld duplicate claim after acceptance leaves no commission on this lead
  if a.outcome = 'duplicate_upheld'
     or exists (select 1 from b2b.commission_disputes d where d.allocation_id = a.id and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance') then
    perform b2b.log_event('money.enrollment_not_booked', a.lead_id, a.id, a.partner_id, jsonb_build_object('source', p_source, 'why', 'duplicate_upheld', 'enrollment', p));
    return jsonb_build_object('status', 'no_earnings', 'why', 'duplicate_upheld');
  end if;
  -- PART 6.1: an enrolment after the lead moved to B2C is a commission dispute first; it earns once the Admin upholds it
  if a.status = 'closed' and a.outcome = 'lost'
     and not exists (select 1 from b2b.commission_disputes d where d.allocation_id = a.id and d.status = 'upheld' and d.kind = 'late_activity_after_lost') then
    x := b2b.late_activity_dispute(a.id, null, jsonb_build_object('source', p_source, 'enrollment', coalesce(p, '{}'), 'at', now()));
    return jsonb_build_object('status', 'disputed', 'dispute_id', (x ->> 'dispute_id')::bigint, 'why', 'enrolment reported after the lead moved to B2C');
  end if;
  -- PART 6.1: an enrolment inside the grace brings the lead back to the partner (never followed by a bar)
  if a.lost_at is not null and a.lost_revived_at is null and a.status in ('pushed', 'accepted') then
    perform b2b.partner_lost_revive(a.id, null, 'enrolment reported (' || coalesce(p_source, '?') || ')');
    select * into a from b2b.allocations where id = a.id;
  end if;

  select * into l from public.student_leads where id = a.lead_id;
  v_on := coalesce(nullif(p ->> 'enrolled_on', '')::date, l.enrollment_date, (l.stage_changed_at at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date);
  if v_on > (now() at time zone 'Asia/Kolkata')::date then raise exception 'the enrolment date is in the future' using errcode = '22023'; end if;
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

-- ---------- (6) a student message that may have been sent ----------
/* As m34e (the provider-address guard kept), with the answer handling described in the header. */
create or replace function b2b.notify_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_retry int := coalesce((s ->> 'retry_after_minutes')::int, 5);
  r record;
  n b2b.student_notifications;
  j jsonb;
  req jsonb;
  v_net bigint;
  v_sent int := 0;
  v_done int := 0;
  v_why text;
  v_maybe boolean;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    select x.id, x.attempts, x.lead_id, x.allocation_id, x.partner_id, x.channel, x.provider, x.updated_at, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null as done
      from b2b.student_notifications x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 200
  loop
    if not r.done and r.updated_at > now() - interval '2 minutes' then continue; end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.student_notifications set status = 'sent', sent_at = now(), updated_at = now(), net_request_id = null, error = null,
             provider_message_id = left(coalesce(j -> 'messages' -> 0 ->> 'id', j ->> 'id', j ->> 'messageId'), 200)
       where id = r.id;
      perform b2b.log_event('notification.sent', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'notification_id', r.id));
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer from the provider' end,
                             'HTTP ' || r.status_code || ': ' || coalesce(j -> 'error' ->> 'message', j ->> 'message', left(r.content, 200))), 300);
      -- M34i: no answer, a timeout, a 5xx or a cut connection may mean the provider sent it. Only Resend, which received the
      -- notification's Idempotency-Key (notify_request), is asked again automatically; Meta and Brevo would send it twice.
      v_maybe := b2b.http_maybe_delivered(r.done, r.timed_out, r.status_code, r.error_msg);
      if r.attempts < 2 and (not v_maybe or r.provider = 'resend') then
        update b2b.student_notifications set status = 'scheduled', scheduled_for = now() + make_interval(mins => v_retry), net_request_id = null,
               error = v_why, updated_at = now() where id = r.id;
      else
        if v_maybe and r.provider is distinct from 'resend' then
          v_why := left('may have been sent (' || v_why || '), so it is not sent again automatically: check with the student before Send again', 300);
        end if;
        update b2b.student_notifications set status = 'failed', net_request_id = null, error = v_why, updated_at = now() where id = r.id;
        perform b2b.log_event('alert.notification_failed', r.lead_id, r.allocation_id, r.partner_id,
                              jsonb_build_object('channel', r.channel, 'error', v_why, 'maybe_sent', v_maybe and r.provider is distinct from 'resend'));
      end if;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due messages
  for n in
    select * from b2b.student_notifications where status = 'scheduled' and scheduled_for <= now()
     order by scheduled_for limit 50 for update skip locked
  loop
    begin
      v_why := case
        when not exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.status = 'accepted') then 'the allocation is no longer accepted'
        when exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.lost_at is not null and a.lost_revived_at is null) then 'lost, in grace'
        when exists (select 1 from b2b.commission_disputes d where d.allocation_id = n.allocation_id and d.kind = 'duplicate_after_acceptance'
                        and d.status in ('open', 'upheld')) then 'duplicate claimed after acceptance'
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and (coalesce(l.is_opted_out, false) or coalesce(l.is_test, false)
                                                                                       or b2b.is_test_phone(l.whatsapp_number))) then 'student opted out or is a test lead'
        when not b2b.is_live(n.channel) then n.channel || ' is switched off'
      end;
      if v_why is not null then
        update b2b.student_notifications set status = 'cancelled', error = v_why, updated_at = now() where id = n.id;
        continue;
      end if;
      req := b2b.notify_request(n);
      if req ? 'error' then
        update b2b.student_notifications set status = 'failed', error = req ->> 'error', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', req ->> 'error'));
        continue;
      end if;
      -- M34e: the provider must be on the public internet
      if not b2b.url_allowed(req ->> 'url') then
        update b2b.student_notifications set status = 'failed', error = 'the provider address is not allowed (a private, loopback, link-local or metadata address)', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id,
                              jsonb_build_object('channel', n.channel, 'error', 'the provider address is not allowed'));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 15000);
      update b2b.student_notifications set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider',
             updated_at = now() where id = n.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.student_notifications set status = 'failed', error = left(sqlerrm, 300), updated_at = now() where id = n.id;
      perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $fn$;

-- ---------- (7) a team invitation needs a confirmed address ----------
/* As m33a, plus the email_confirmed_at check. */
create or replace function b2b.team_invite_accept(p_user_id uuid, p_email text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.team_invites;
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if p_user_id is null or v_email = '' then return false; end if;
  if exists (select 1 from b2b.app_users u where u.user_id = p_user_id) then return false; end if;
  -- M34i: only an identity whose address is confirmed (Supabase Auth sets email_confirmed_at; Google sign-ins have it)
  if not exists (select 1 from auth.users a where a.id = p_user_id and lower(a.email) = v_email and a.email_confirmed_at is not null) then
    return false;
  end if;
  select * into i from b2b.team_invites t where t.email = v_email and t.accepted_at is null and t.revoked_at is null and t.expires_at > now()
   order by t.id desc limit 1 for update;
  if i.id is null then return false; end if;
  insert into b2b.app_users (user_id, email, role, is_active, require_totp, invited_by, note)
  values (p_user_id, v_email, i.role, true, true, i.invited_by, i.note)
  on conflict (user_id) do nothing;
  update b2b.team_invites set accepted_at = now(), accepted_user_id = p_user_id where id = i.id;
  perform set_config('b2b.actor', 'system', true);
  perform b2b.log_event('team.joined', null, null, null, jsonb_build_object('invite_id', i.id, 'email', v_email, 'role', i.role, 'user_id', p_user_id));
  return true;
end $fn$;

-- create or replace keeps each replaced function's grants; the new sign_in_locked overload's are set in (2).
