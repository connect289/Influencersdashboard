-- Hardening after the November audit, 13 Nov 2026 (schema inf only; D-197).
-- 1. Payouts go to the bank account that was verified when the batch was made.
--    a. Each payout keeps a fingerprint of the creator's beneficiary (keyed hash of account number, IFSC and holder,
--       inf.pii_hash) and the account's last four digits, written by a trigger when the payout is inserted.
--       inf.payout_bank_rows refuses the whole file, naming each payout, while any pending payout's KYC is not
--       'verified' or its bank details differ from the fingerprint. Pending payouts in open batches whose KYC is
--       verified today get today's fingerprint once (they could be exported unchecked until now).
--    b. inf.kyc_save refuses a change of account number, IFSC or holder name ('bank_locked') while the creator has a
--       pending payout in a draft, approved or processing batch. Re-entering the stored number is not a change.
--    c. A new account holder name counts as a change and sends the KYC back for verification.
-- 2. Accepting or countering a compensation counter-offer is one locked step: inf.deal_version_from_counter locks the
--    contract and the request, refuses a request that is no longer pending (and terms that changed under the
--    decision), writes the deal version and marks the request decided. Any new contract version then closes decided
--    counter-offers it carries (resolved_in_version_id); until one does, the request shows "terms accepted, contract
--    not generated" and the contract cannot be marked ready to sign. Regenerating never writes another deal version.
-- 3. A job that dies while running on its last attempt is marked dead instead of being reclaimed forever (stale reclaim
--    needs attempts < max_attempts). Every dead job (inf.job_dead_record) emits system.job_dead, tells active staff
--    with system.read in the app (no email, so a broken mail provider cannot loop), and fails the queued deliveries of
--    a dead notify.deliver job when no other delivery job for that notification is still live.
-- 4. Contract reminders, deadline and expiry notices use a per-day idempotency key, so a nightly run that repeats on
--    the same day sends nothing twice.
-- Idempotent. Inverse statements: see the rollback block at the end.

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Bank details are fixed for the life of a payout
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.payouts add column if not exists bank_fingerprint text;
alter table inf.payouts add column if not exists bank_last4 text check (bank_last4 ~ '^\d{4}$');

-- Internal (no client grant): the keyed hash of a creator's current beneficiary, null without account or IFSC.
create or replace function inf.kyc_bank_fingerprint(p_creator uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when k.bank_account_enc is null or k.ifsc is null then null
              else inf.pii_hash(inf.pii_decrypt(k.bank_account_enc) || '|' || k.ifsc || '|' || coalesce(k.account_holder, '')) end
    from inf.creator_kyc k where k.creator_id = p_creator
$$;

create or replace function inf.payout_bank_snapshot() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.bank_fingerprint := inf.kyc_bank_fingerprint(new.creator_id);
  new.bank_last4 := (select k.bank_last4 from inf.creator_kyc k where k.creator_id = new.creator_id);
  return new;
end $$;
drop trigger if exists payouts_bank_snapshot on inf.payouts;
create trigger payouts_bank_snapshot before insert on inf.payouts for each row execute function inf.payout_bank_snapshot();

-- Open payouts made before this migration: today's verified details (once; later runs find none without a fingerprint).
update inf.payouts p set bank_fingerprint = inf.kyc_bank_fingerprint(p.creator_id), bank_last4 = k.bank_last4
  from inf.payout_batches b, inf.creator_kyc k
 where b.id = p.batch_id and k.creator_id = p.creator_id and p.bank_fingerprint is null and p.status = 'pending'
   and b.status in ('draft', 'approved', 'processing') and k.status = 'verified' and k.bank_account_enc is not null;

-- The bank file rows, with account numbers decrypted (payout.manage, approved or processing batches only). Every
-- call is audited; the first one moves the batch to processing. Refused while any pending payout's KYC is not
-- verified or its bank details changed since the batch was made.
create or replace function inf.payout_bank_rows(p_batch uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b inf.payout_batches; v_rows jsonb; v_refused text;
begin
  if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into b from inf.payout_batches where id = p_batch for update;
  if b.id is null or b.status not in ('approved', 'processing') then
    raise exception 'the batch must be approved first' using errcode = '22023';
  end if;
  select string_agg(x.ref || ' (' || x.reason || ')', ', ' order by x.ref) into v_refused
    from (select p.ref,
                 case when k.creator_id is null or k.status <> 'verified' then 'KYC not verified'
                      when p.bank_fingerprint is null then 'no verified bank details when the batch was made'
                      when p.bank_fingerprint is distinct from inf.kyc_bank_fingerprint(p.creator_id) then 'bank details changed after the batch was made'
                 end as reason
            from inf.payouts p left join inf.creator_kyc k on k.creator_id = p.creator_id
           where p.batch_id = b.id and p.status = 'pending') x
   where x.reason is not null;
  if v_refused is not null then
    raise exception 'bank file refused: %', v_refused using errcode = '22023',
      hint = 'Verify the KYC again, or take the payout out (remove it from a draft batch, cancel an approved batch, mark it failed once processing).';
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

-- KYC save (20261030000100 §4) plus: bank details locked while a payout is open; holder name counts as a change; the
-- stored account number re-entered is not a change.
create or replace function inf.kyc_save(p_creator uuid, p_pan text, p_name_on_pan text, p_gst_status text, p_gstin text,
                                        p_bank_account text, p_ifsc text, p_account_holder text, p_proof_path text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cur     inf.creator_kyc;
  v_pan     text := upper(nullif(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'), ''));
  v_acct    text := nullif(regexp_replace(coalesce(p_bank_account, ''), '\s', '', 'g'), '');
  v_ifsc    text := upper(nullif(trim(coalesce(p_ifsc, '')), ''));
  v_gstin   text := upper(nullif(trim(coalesce(p_gstin, '')), ''));
  v_holder  text := nullif(trim(coalesce(p_account_holder, '')), '');
  v_status  text := coalesce(nullif(p_gst_status, ''), 'unregistered');
  v_changed boolean;
  v_bank_changed boolean;
  v_complete boolean;
  v_pan_eff text;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write') or inf.has_perm('kyc.verify')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_pan is not null and not inf.valid_pan(v_pan) then return jsonb_build_object('ok', false, 'error', 'invalid_pan'); end if;
  if v_acct is not null and v_acct !~ '^\d{9,18}$' then return jsonb_build_object('ok', false, 'error', 'invalid_account'); end if;
  if v_ifsc is not null and not inf.valid_ifsc(v_ifsc) then return jsonb_build_object('ok', false, 'error', 'invalid_ifsc'); end if;
  if v_status not in ('unregistered', 'registered', 'composition') then return jsonb_build_object('ok', false, 'error', 'invalid_gst_status'); end if;
  if v_status <> 'unregistered' and (v_gstin is null or not inf.valid_gstin(v_gstin)) then return jsonb_build_object('ok', false, 'error', 'invalid_gstin'); end if;
  if v_status = 'unregistered' then v_gstin := null; end if;
  -- The proof must be in this creator's own folder of inf-kyc (<creator>/<file>), where the upload URL puts it.
  if nullif(p_proof_path, '') is not null and split_part(p_proof_path, '/', 1) <> p_creator::text then
    return jsonb_build_object('ok', false, 'error', 'invalid_proof');
  end if;

  select * into v_cur from inf.creator_kyc where creator_id = p_creator for update;
  v_pan_eff := coalesce(v_pan, case when v_cur.pan_enc is not null then inf.pii_decrypt(v_cur.pan_enc) end);
  -- GSTIN characters 3–12 are the PAN.
  if v_gstin is not null and v_pan_eff is not null and substr(v_gstin, 3, 10) <> v_pan_eff then
    return jsonb_build_object('ok', false, 'error', 'gstin_pan_mismatch');
  end if;
  -- Blank keeps the stored value, so only a value that differs from it is a change.
  v_bank_changed := v_cur.creator_id is not null and (
       (v_acct is not null and v_acct is distinct from case when v_cur.bank_account_enc is not null then inf.pii_decrypt(v_cur.bank_account_enc) end)
    or v_ifsc is distinct from v_cur.ifsc
    or (v_holder is not null and v_holder is distinct from v_cur.account_holder));
  -- The bank file pays the details fixed when the batch was made, so they cannot move under an open payout.
  if v_bank_changed and exists (select 1 from inf.payouts p join inf.payout_batches b on b.id = p.batch_id
                                 where p.creator_id = p_creator and p.status = 'pending'
                                   and b.status in ('draft', 'approved', 'processing')) then
    return jsonb_build_object('ok', false, 'error', 'bank_locked');
  end if;
  v_changed := v_cur.creator_id is not null and (v_pan is not null or v_bank_changed or v_gstin is distinct from v_cur.gstin);

  insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, gst_status, gstin, bank_account_enc, bank_last4, ifsc, account_holder, proof_path)
  values (p_creator, inf.pii_encrypt(v_pan), right(v_pan, 4), nullif(trim(p_name_on_pan), ''), v_status, v_gstin,
          inf.pii_encrypt(v_acct), right(v_acct, 4), v_ifsc, v_holder, nullif(p_proof_path, ''))
  on conflict (creator_id) do update set
    pan_enc = coalesce(excluded.pan_enc, inf.creator_kyc.pan_enc),
    pan_last4 = coalesce(excluded.pan_last4, inf.creator_kyc.pan_last4),
    name_on_pan = coalesce(excluded.name_on_pan, inf.creator_kyc.name_on_pan),
    gst_status = excluded.gst_status,
    gstin = excluded.gstin,
    gstin_verified = case when excluded.gstin is distinct from inf.creator_kyc.gstin then false else inf.creator_kyc.gstin_verified end,
    bank_account_enc = coalesce(excluded.bank_account_enc, inf.creator_kyc.bank_account_enc),
    bank_last4 = coalesce(excluded.bank_last4, inf.creator_kyc.bank_last4),
    ifsc = coalesce(excluded.ifsc, inf.creator_kyc.ifsc),
    account_holder = coalesce(excluded.account_holder, inf.creator_kyc.account_holder),
    proof_path = coalesce(excluded.proof_path, inf.creator_kyc.proof_path);

  select (pan_enc is not null and name_on_pan is not null and bank_account_enc is not null and ifsc is not null and account_holder is not null)
    into v_complete from inf.creator_kyc where creator_id = p_creator;
  update inf.creator_kyc set
    status = case when not v_complete then 'pending'
                  when status = 'verified' and not v_changed then 'verified'
                  else 'submitted' end,
    submitted_at = case when v_complete and (status <> 'verified' or v_changed) then now() else submitted_at end,
    verified_at = case when v_changed then null else verified_at end,
    verified_by = case when v_changed then null else verified_by end,
    rejection_reason = case when v_complete then null else rejection_reason end
  where creator_id = p_creator;
  update inf.creators set last_activity_at = now() where id = p_creator;
  return jsonb_build_object('ok', true, 'status', (select status from inf.creator_kyc where creator_id = p_creator), 'complete', v_complete);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Counter-offer decisions are one locked step; regeneration closes them
-- ---------------------------------------------------------------------------------------------------------------
drop function if exists inf.deal_version_from_counter(uuid, jsonb);
delete from inf.client_grants where object_type = 'function' and object_name = 'inf.deal_version_from_counter(uuid, jsonb)';

-- A structured compensation counter-offer accepted (or countered) by Eduwit: the deal's terms are replaced (before
-- signing) by a new accepted version and the request is marked decided, in one transaction under the contract's lock.
-- p_base_version is the deal version the app built p_config from; terms that moved since are refused.
create or replace function inf.deal_version_from_counter(p_request uuid, p_config jsonb, p_status text default 'accepted',
                                                         p_note text default null, p_base_version uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare r inf.contract_change_requests; c inf.contracts; d inf.deals; cur inf.deal_versions; v_id uuid;
begin
  if not (inf.has_perm('contract.write') and inf.has_perm('deal.write')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status is null or p_status not in ('accepted', 'countered') then raise exception 'invalid decision' using errcode = '22023'; end if;
  select * into c from inf.contracts where id = (select x.contract_id from inf.contract_change_requests x where x.id = p_request) for update;
  select * into r from inf.contract_change_requests where id = p_request and status = 'pending' and kind = 'compensation' for update;
  if r.id is null then raise exception 'change request is not pending' using errcode = '22023'; end if;
  if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'a signed or closed contract cannot change' using errcode = '22023'; end if;
  select * into d from inf.deals where id = c.deal_id for update;
  if p_base_version is not null and d.current_version_id is distinct from p_base_version then
    raise exception 'the deal terms changed while this was being decided; reload and decide again' using errcode = '40001';
  end if;
  select * into cur from inf.deal_versions where id = d.current_version_id;
  if not inf.comp_config_valid(p_config) then raise exception 'invalid compensation config' using errcode = '22023'; end if;
  insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, preset_id, effective_from, note, state, decided_by, decided_at)
  values (d.id, (select max(version) from inf.deal_versions where deal_id = d.id) + 1, p_config, inf.config_hash(p_config), 'counter_offer',
          cur.preset_id, cur.effective_from, 'Counter-offer agreed in contract ' || c.number, 'accepted', auth.uid(), now())
  returning id into v_id;
  update inf.deal_versions set state = 'superseded' where id = cur.id;
  update inf.deals set current_version_id = v_id, deal_model = inf.deal_model(p_config) where id = d.id;
  update inf.contract_change_requests set status = p_status, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(trim(p_note), '')
   where id = r.id;
  return v_id;
end $$;

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.deal_version_from_counter(uuid, jsonb, text, text, uuid)', 'authenticated', 'execute')
on conflict do nothing;

-- Adds a version (content and HTML assembled by the app). The database hashes the HTML. With p_resolve, the listed
-- change requests are closed as accepted or countered in this version (a compensation request already decided by
-- inf.deal_version_from_counter is accepted too). Every decided counter-offer still waiting for its version is
-- closed by this one, which is built from the deal's current terms.
create or replace function inf.contract_version_add(p_contract uuid, p_content jsonb, p_html text, p_overrides jsonb,
                                                    p_note text default null, p_resolve jsonb default '[]'::jsonb,
                                                    p_missing text[] default '{}')
returns uuid
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; d inf.deals; v_id uuid; v_item jsonb;
begin
  if not inf.contract_writer() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.id is null then raise exception 'no such contract' using errcode = '22023'; end if;
  if c.status not in ('draft', 'sent', 'in_negotiation', 'ready_to_sign') then
    raise exception 'a signed or closed contract cannot change' using errcode = '22023';
  end if;
  select * into d from inf.deals where id = c.deal_id;
  insert into inf.contract_versions (contract_id, version, deal_version_id, content, html, sha256, overrides, missing_fields, note)
  values (c.id, coalesce((select max(version) from inf.contract_versions where contract_id = c.id), 0) + 1, d.current_version_id,
          p_content, p_html, encode(sha256(convert_to(p_html, 'UTF8')), 'hex'), coalesce(p_overrides, '{}'::jsonb),
          coalesce(p_missing, '{}'), nullif(trim(p_note), ''))
  returning id into v_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_resolve, '[]'::jsonb)) loop
    update inf.contract_change_requests set status = v_item ->> 'status', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(trim(v_item ->> 'note'), ''), resolved_in_version_id = v_id
     where id = (v_item ->> 'id')::uuid and contract_id = c.id and status = 'pending' and v_item ->> 'status' in ('accepted', 'countered');
    if not found then
      update inf.contract_change_requests set resolved_in_version_id = v_id
       where id = (v_item ->> 'id')::uuid and contract_id = c.id and kind = 'compensation' and status = v_item ->> 'status'
         and resolved_in_version_id is null;
      if not found then raise exception 'change request is not pending' using errcode = '22023'; end if;
    end if;
  end loop;
  update inf.contract_change_requests set resolved_in_version_id = v_id
   where contract_id = c.id and kind = 'compensation' and status in ('accepted', 'countered') and resolved_in_version_id is null;
  update inf.contracts set current_version_id = v_id,
         status = case when status in ('sent', 'ready_to_sign') then 'in_negotiation' else status end
   where id = c.id;
  if c.status <> 'draft' then
    perform inf.contract_notify(c.id, 'creator', 'contract.updated', 'Contract updated: ' || c.number,
                                'A new version of your contract is ready to review.');
  end if;
  return v_id;
end $$;

create or replace function inf.contract_set_ready(p_contract uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.status not in ('sent', 'in_negotiation') then raise exception 'cannot mark this contract ready' using errcode = '22023'; end if;
  if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending') then
    raise exception 'answer every pending change request first' using errcode = '22023';
  end if;
  if exists (select 1 from inf.contract_change_requests where contract_id = c.id and kind = 'compensation'
              and status in ('accepted', 'countered') and resolved_in_version_id is null) then
    raise exception 'accepted counter-offer terms are not in the contract yet; regenerate the contract first' using errcode = '22023';
  end if;
  if exists (select 1 from inf.contract_versions v where v.id = c.current_version_id and cardinality(v.missing_fields) > 0) then
    raise exception 'details are missing' using errcode = '22023';
  end if;
  update inf.contracts set status = 'ready_to_sign' where id = c.id;
  perform inf.contract_notify(c.id, 'creator', 'contract.ready', 'Ready to sign: ' || c.number,
                              'Your contract is final and ready for your signature.');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Jobs that die while running stop; dead jobs reach the System page and its staff
-- ---------------------------------------------------------------------------------------------------------------
-- Internal (no client grant): everything that follows a job going dead.
create or replace function inf.job_dead_record(p_job_id bigint, p_error text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_job inf.jobs; v_notification uuid;
begin
  select * into v_job from inf.jobs where id = p_job_id;
  if v_job.id is null then return; end if;
  perform inf.emit_event('system.job_dead', 'job', v_job.id::text, jsonb_build_object('kind', v_job.kind, 'error', left(p_error, 500)),
                         'job_dead:' || v_job.id);
  if v_job.kind = 'notify.deliver' and v_job.payload ->> 'notification_id' ~ '^[0-9a-f-]{36}$' then
    v_notification := (v_job.payload ->> 'notification_id')::uuid;
    -- Another delivery job for the same notification (the after-quiet-hours run) still owns its queued rows.
    if not exists (select 1 from inf.jobs j where j.id <> v_job.id and j.kind = 'notify.deliver' and j.status in ('queued', 'running', 'failed')
                     and j.payload ->> 'notification_id' = v_notification::text) then
      update inf.notification_deliveries set status = 'failed', error = left('delivery job gave up: ' || coalesce(p_error, ''), 2000)
       where notification_id = v_notification and status = 'queued';
    end if;
    -- A dead delivery of a dead-job notice tells no one again.
    if exists (select 1 from inf.notifications n where n.id = v_notification and n.event = 'system.job_dead') then return; end if;
  end if;
  perform inf.notify(sp.user_id, 'system.job_dead', 'Background job stopped: ' || v_job.kind,
                     'Job #' || v_job.id || ' gave up after ' || v_job.attempts || ' attempts. Retry it from System status once the cause is fixed.',
                     '/admin/system', jsonb_build_object('job_id', v_job.id, 'kind', v_job.kind), false,
                     'job_dead:' || v_job.id || ':' || sp.user_id || ':' || extract(epoch from clock_timestamp())::bigint, '{}'::text[])
    from inf.staff_profiles sp
   where sp.status = 'active'
     and exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                  where g.user_id = sp.user_id and rp.permission = 'system.read');
end $$;

-- service_role (via job_claim): jobs that stopped while running on their last attempt (timed out, or the worker was
-- killed) are dead, not claimable again.
create or replace function inf.jobs_reap_stale() returns int
language plpgsql security definer set search_path = '' as $$
declare j inf.jobs; v_n int := 0; v_error text;
begin
  for j in select * from inf.jobs where status = 'running' and locked_at < now() - interval '10 minutes' and attempts >= max_attempts
            order by id for update skip locked loop
    v_error := 'stopped while running on attempt ' || j.attempts || ' of ' || j.max_attempts || ' (timed out or the worker stopped)';
    update inf.jobs set status = 'dead', finished_at = now(), locked_at = null, last_error = v_error where id = j.id
    returning * into j;
    perform inf.job_dead_record(j.id, v_error);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- service_role: claim up to p_limit due jobs. A job stuck in "running" for 10 minutes is claimable again while it has
-- attempts left; one on its last attempt is marked dead first.
create or replace function inf.job_claim(p_worker text, p_limit int default 20, p_kinds text[] default null)
returns setof inf.jobs language plpgsql security definer set search_path = '' as $$
begin
  perform inf.jobs_reap_stale();
  return query
  with due as (
    select j.id from inf.jobs j
     where ((j.status in ('queued', 'failed') and j.run_at <= now())
            or (j.status = 'running' and j.locked_at < now() - interval '10 minutes' and j.attempts < j.max_attempts))
       and (p_kinds is null or j.kind = any (p_kinds))
     order by j.run_at
     limit least(greatest(p_limit, 1), 100)
     for update skip locked)
  update inf.jobs j set status = 'running', attempts = j.attempts + 1, locked_at = now(), locked_by = left(p_worker, 80)
    from due where j.id = due.id
  returning j.*;
end $$;

-- service_role: finish a claimed job. Failures back off 1, 2, 4, 8… minutes (capped at 6 h), then go dead.
create or replace function inf.job_finish(p_id bigint, p_ok boolean, p_error text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_job inf.jobs; v_status text;
begin
  select * into v_job from inf.jobs where id = p_id for update;
  if v_job.id is null or v_job.status <> 'running' then return 'ignored'; end if;
  if p_ok then
    v_status := 'done';
    update inf.jobs set status = 'done', finished_at = now(), locked_at = null, last_error = null where id = p_id;
  elsif v_job.attempts >= v_job.max_attempts then
    v_status := 'dead';
    update inf.jobs set status = 'dead', finished_at = now(), locked_at = null, last_error = left(p_error, 2000) where id = p_id
    returning * into v_job;
    perform inf.job_dead_record(v_job.id, p_error);
  else
    v_status := 'failed';
    update inf.jobs set status = 'failed', locked_at = null, last_error = left(p_error, 2000),
           run_at = now() + least(interval '6 hours', make_interval(mins => power(2, v_job.attempts - 1)::int))
     where id = p_id;
  end if;
  return v_status;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Contract notices with a caller's idempotency key (internal, no client grant); nightly reminders keyed by the IST day
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.contract_notify_keyed(p_contract uuid, p_to text, p_event text, p_title text, p_body text, p_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; d inf.deals; v_user uuid; v_key text := coalesce(nullif(p_key, ''), extract(epoch from clock_timestamp())::bigint::text);
begin
  select * into c from inf.contracts where id = p_contract;
  select * into d from inf.deals where id = c.deal_id;
  if p_to in ('creator', 'all') then
    select user_id into v_user from inf.creator_accounts where creator_id = d.creator_id;
    if v_user is not null then
      perform inf.notify(v_user, p_event, p_title, p_body, '/creator/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
                         p_event || ':' || p_contract || ':c:' || v_key);
    end if;
    perform inf.notify(m.user_id, p_event, p_title, p_body, '/agency/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
                       p_event || ':' || p_contract || ':' || m.user_id || ':' || v_key)
      from inf.agency_creator_links l join inf.agency_members m on m.agency_id = l.agency_id and m.status = 'active' and m.user_id is not null
     where l.creator_id = d.creator_id and l.status = 'active' and l.can_negotiate_sign;
  end if;
  if p_to in ('eduwit', 'all') then
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
                       p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
      from inf.staff_profiles sp
     where sp.status = 'active' and (sp.user_id = d.owner_id or (d.owner_id is null and exists (
             select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
              where g.user_id = sp.user_id and rp.permission = 'contract.write')));
  end if;
  if p_to = 'signatory' then
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
                       p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
      from inf.staff_profiles sp where sp.status = 'active' and sp.is_signatory;
  end if;
end $$;

-- The original five-argument form: every event-driven notice stays unique to the second, as before.
create or replace function inf.contract_notify(p_contract uuid, p_to text, p_event text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform inf.contract_notify_keyed(p_contract, p_to, p_event, p_title, p_body, extract(epoch from clock_timestamp())::bigint::text);
end $$;

create or replace function inf.contracts_remind() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; v_set jsonb := inf.setting('contracts.signing'); v_n int := 0; v_days int; v_day text := 'day:' || inf.ist_date(now())::text;
begin
  for r in
    select c.id, c.number, c.negotiation_deadline, c.expires_on, c.status from inf.contracts c
     where c.status in ('sent', 'in_negotiation', 'ready_to_sign', 'signed_by_creator', 'active')
  loop
    if r.status <> 'active' and r.negotiation_deadline is not null then
      v_days := ceil(extract(epoch from (r.negotiation_deadline - now())) / 86400)::int;
      if v_days = -1 then
        -- The deadline passed yesterday: Eduwit decides whether to extend, chase or void.
        perform inf.contract_notify_keyed(r.id, 'eduwit', 'contract.deadline_passed', 'Deadline passed: ' || r.number,
                                    'The negotiation deadline has passed. Follow up, extend the conversation or void the contract.', v_day);
        v_n := v_n + 1;
      elsif v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'negotiation_reminder_days') x) or v_days = 0 then
        perform inf.contract_notify_keyed(r.id, case when r.status = 'signed_by_creator' then 'signatory' else 'all' end,
                                    'contract.reminder', 'Reminder: ' || r.number,
                                    case when r.status = 'signed_by_creator' then 'Waiting for the countersignature.'
                                         else 'This contract is still open. Please review or sign it.' end, v_day);
        v_n := v_n + 1;
      end if;
    elsif r.status = 'active' and r.expires_on is not null then
      v_days := r.expires_on - (now() at time zone 'Asia/Kolkata')::date;
      if v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'expiry_reminder_days') x) then
        perform inf.contract_notify_keyed(r.id, 'all', 'contract.expiring', r.number || ' expires in ' || v_days || ' days',
                                    'Renew the deal or let it end on its expiry date.', v_day);
        v_n := v_n + 1;
      elsif v_days < 0 then
        update inf.contracts set status = 'expired', closed_at = now(), status_reason = 'Expiry date passed' where id = r.id;
      end if;
    end if;
  end loop;
  return v_n;
end $$;

call inf.apply_client_grants();

-- ---------------------------------------------------------------------------------------------------------------
-- Rollback (inverse statements; the definitions as they stood before, from the migrations named)
-- ---------------------------------------------------------------------------------------------------------------
-- drop trigger if exists payouts_bank_snapshot on inf.payouts;
-- drop function if exists inf.payout_bank_snapshot();
-- drop function if exists inf.kyc_bank_fingerprint(uuid);
-- alter table inf.payouts drop column if exists bank_fingerprint, drop column if exists bank_last4;
-- drop function if exists inf.jobs_reap_stale();
-- drop function if exists inf.job_dead_record(bigint, text);
-- drop function if exists inf.contract_notify_keyed(uuid, text, text, text, text, text);
-- drop function if exists inf.deal_version_from_counter(uuid, jsonb, text, text, uuid);
-- delete from inf.client_grants where object_type = 'function' and object_name = 'inf.deal_version_from_counter(uuid, jsonb, text, text, uuid)';
-- insert into inf.client_grants (object_type, object_name, grantee, privilege) values
--   ('function', 'inf.deal_version_from_counter(uuid, jsonb)', 'authenticated', 'execute') on conflict do nothing;
-- -- from 20261022000100_inf_ledger.sql
-- create or replace function inf.payout_bank_rows(p_batch uuid) returns jsonb
-- language plpgsql security definer set search_path = '' as $$
-- declare b inf.payout_batches; v_rows jsonb;
-- begin
--   if not inf.has_perm('payout.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into b from inf.payout_batches where id = p_batch for update;
--   if b.id is null or b.status not in ('approved', 'processing') then
--     raise exception 'the batch must be approved first' using errcode = '22023';
--   end if;
--   select coalesce(jsonb_agg(jsonb_build_object(
--            'beneficiary_name', k.account_holder, 'account_number', inf.pii_decrypt(k.bank_account_enc), 'ifsc', k.ifsc,
--            'net_paise', p.net_paise, 'payout_ref', p.ref, 'email', c.email, 'creator_code', upper(c.handle)) order by p.ref), '[]')
--     into v_rows
--     from inf.payouts p join inf.creators c on c.id = p.creator_id join inf.creator_kyc k on k.creator_id = p.creator_id
--    where p.batch_id = b.id and p.status = 'pending';
--   update inf.payout_batches set status = 'processing', exported_by = coalesce(exported_by, auth.uid()),
--          exported_at = coalesce(exported_at, now()), export_count = export_count + 1
--    where id = b.id;
--   perform inf.audit('payout_batch', b.id::text, 'bank_export', null,
--                      jsonb_build_object('payouts', jsonb_array_length(v_rows), 'export', b.export_count + 1));
--   return v_rows;
-- end $$;
-- -- from 20261030000100_inf_audit_guards.sql
-- create or replace function inf.kyc_save(p_creator uuid, p_pan text, p_name_on_pan text, p_gst_status text, p_gstin text,
--                                         p_bank_account text, p_ifsc text, p_account_holder text, p_proof_path text default null)
-- returns jsonb language plpgsql security definer set search_path = '' as $$
-- declare
--   v_cur     inf.creator_kyc;
--   v_pan     text := upper(nullif(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'), ''));
--   v_acct    text := nullif(regexp_replace(coalesce(p_bank_account, ''), '\s', '', 'g'), '');
--   v_ifsc    text := upper(nullif(trim(coalesce(p_ifsc, '')), ''));
--   v_gstin   text := upper(nullif(trim(coalesce(p_gstin, '')), ''));
--   v_status  text := coalesce(nullif(p_gst_status, ''), 'unregistered');
--   v_changed boolean;
--   v_complete boolean;
--   v_pan_eff text;
-- begin
--   if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write') or inf.has_perm('kyc.verify')) then
--     raise exception 'not allowed' using errcode = '42501';
--   end if;
--   if v_pan is not null and not inf.valid_pan(v_pan) then return jsonb_build_object('ok', false, 'error', 'invalid_pan'); end if;
--   if v_acct is not null and v_acct !~ '^\d{9,18}$' then return jsonb_build_object('ok', false, 'error', 'invalid_account'); end if;
--   if v_ifsc is not null and not inf.valid_ifsc(v_ifsc) then return jsonb_build_object('ok', false, 'error', 'invalid_ifsc'); end if;
--   if v_status not in ('unregistered', 'registered', 'composition') then return jsonb_build_object('ok', false, 'error', 'invalid_gst_status'); end if;
--   if v_status <> 'unregistered' and (v_gstin is null or not inf.valid_gstin(v_gstin)) then return jsonb_build_object('ok', false, 'error', 'invalid_gstin'); end if;
--   if v_status = 'unregistered' then v_gstin := null; end if;
--   -- The proof must be in this creator's own folder of inf-kyc (<creator>/<file>), where the upload URL puts it.
--   if nullif(p_proof_path, '') is not null and split_part(p_proof_path, '/', 1) <> p_creator::text then
--     return jsonb_build_object('ok', false, 'error', 'invalid_proof');
--   end if;
--
--   select * into v_cur from inf.creator_kyc where creator_id = p_creator for update;
--   v_pan_eff := coalesce(v_pan, case when v_cur.pan_enc is not null then inf.pii_decrypt(v_cur.pan_enc) end);
--   -- GSTIN characters 3–12 are the PAN.
--   if v_gstin is not null and v_pan_eff is not null and substr(v_gstin, 3, 10) <> v_pan_eff then
--     return jsonb_build_object('ok', false, 'error', 'gstin_pan_mismatch');
--   end if;
--   v_changed := v_cur.creator_id is not null and (v_pan is not null or v_acct is not null
--                  or v_ifsc is distinct from v_cur.ifsc or v_gstin is distinct from v_cur.gstin);
--
--   insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, gst_status, gstin, bank_account_enc, bank_last4, ifsc, account_holder, proof_path)
--   values (p_creator, inf.pii_encrypt(v_pan), right(v_pan, 4), nullif(trim(p_name_on_pan), ''), v_status, v_gstin,
--           inf.pii_encrypt(v_acct), right(v_acct, 4), v_ifsc, nullif(trim(p_account_holder), ''), nullif(p_proof_path, ''))
--   on conflict (creator_id) do update set
--     pan_enc = coalesce(excluded.pan_enc, inf.creator_kyc.pan_enc),
--     pan_last4 = coalesce(excluded.pan_last4, inf.creator_kyc.pan_last4),
--     name_on_pan = coalesce(excluded.name_on_pan, inf.creator_kyc.name_on_pan),
--     gst_status = excluded.gst_status,
--     gstin = excluded.gstin,
--     gstin_verified = case when excluded.gstin is distinct from inf.creator_kyc.gstin then false else inf.creator_kyc.gstin_verified end,
--     bank_account_enc = coalesce(excluded.bank_account_enc, inf.creator_kyc.bank_account_enc),
--     bank_last4 = coalesce(excluded.bank_last4, inf.creator_kyc.bank_last4),
--     ifsc = coalesce(excluded.ifsc, inf.creator_kyc.ifsc),
--     account_holder = coalesce(excluded.account_holder, inf.creator_kyc.account_holder),
--     proof_path = coalesce(excluded.proof_path, inf.creator_kyc.proof_path);
--
--   select (pan_enc is not null and name_on_pan is not null and bank_account_enc is not null and ifsc is not null and account_holder is not null)
--     into v_complete from inf.creator_kyc where creator_id = p_creator;
--   update inf.creator_kyc set
--     status = case when not v_complete then 'pending'
--                   when status = 'verified' and not v_changed then 'verified'
--                   else 'submitted' end,
--     submitted_at = case when v_complete and (status <> 'verified' or v_changed) then now() else submitted_at end,
--     verified_at = case when v_changed then null else verified_at end,
--     verified_by = case when v_changed then null else verified_by end,
--     rejection_reason = case when v_complete then null else rejection_reason end
--   where creator_id = p_creator;
--   update inf.creators set last_activity_at = now() where id = p_creator;
--   return jsonb_build_object('ok', true, 'status', (select status from inf.creator_kyc where creator_id = p_creator), 'complete', v_complete);
-- end $$;
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.deal_version_from_counter(p_request uuid, p_config jsonb) returns uuid
-- language plpgsql security definer set search_path = '' as $$
-- declare r inf.contract_change_requests; c inf.contracts; d inf.deals; cur inf.deal_versions; v_id uuid;
-- begin
--   if not (inf.has_perm('contract.write') and inf.has_perm('deal.write')) then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into r from inf.contract_change_requests where id = p_request and status = 'pending' and kind = 'compensation';
--   if r.id is null then raise exception 'change request is not pending' using errcode = '22023'; end if;
--   select * into c from inf.contracts where id = r.contract_id;
--   if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'a signed or closed contract cannot change' using errcode = '22023'; end if;
--   select * into d from inf.deals where id = c.deal_id for update;
--   select * into cur from inf.deal_versions where id = d.current_version_id;
--   if not inf.comp_config_valid(p_config) then raise exception 'invalid compensation config' using errcode = '22023'; end if;
--   insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, preset_id, effective_from, note, state, decided_by, decided_at)
--   values (d.id, (select max(version) from inf.deal_versions where deal_id = d.id) + 1, p_config, inf.config_hash(p_config), 'counter_offer',
--           cur.preset_id, cur.effective_from, 'Counter-offer agreed in contract ' || c.number, 'accepted', auth.uid(), now())
--   returning id into v_id;
--   update inf.deal_versions set state = 'superseded' where id = cur.id;
--   update inf.deals set current_version_id = v_id, deal_model = inf.deal_model(p_config) where id = d.id;
--   return v_id;
-- end $$;
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.contract_version_add(p_contract uuid, p_content jsonb, p_html text, p_overrides jsonb,
--                                                     p_note text default null, p_resolve jsonb default '[]'::jsonb,
--                                                     p_missing text[] default '{}')
-- returns uuid
-- language plpgsql security definer set search_path = '' as $$
-- declare c inf.contracts; d inf.deals; v_id uuid; v_item jsonb;
-- begin
--   if not inf.contract_writer() then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into c from inf.contracts where id = p_contract for update;
--   if c.id is null then raise exception 'no such contract' using errcode = '22023'; end if;
--   if c.status not in ('draft', 'sent', 'in_negotiation', 'ready_to_sign') then
--     raise exception 'a signed or closed contract cannot change' using errcode = '22023';
--   end if;
--   select * into d from inf.deals where id = c.deal_id;
--   insert into inf.contract_versions (contract_id, version, deal_version_id, content, html, sha256, overrides, missing_fields, note)
--   values (c.id, coalesce((select max(version) from inf.contract_versions where contract_id = c.id), 0) + 1, d.current_version_id,
--           p_content, p_html, encode(sha256(convert_to(p_html, 'UTF8')), 'hex'), coalesce(p_overrides, '{}'::jsonb),
--           coalesce(p_missing, '{}'), nullif(trim(p_note), ''))
--   returning id into v_id;
--   for v_item in select * from jsonb_array_elements(coalesce(p_resolve, '[]'::jsonb)) loop
--     update inf.contract_change_requests set status = v_item ->> 'status', decided_by = auth.uid(), decided_at = now(),
--            decision_note = nullif(trim(v_item ->> 'note'), ''), resolved_in_version_id = v_id
--      where id = (v_item ->> 'id')::uuid and contract_id = c.id and status = 'pending' and v_item ->> 'status' in ('accepted', 'countered');
--     if not found then raise exception 'change request is not pending' using errcode = '22023'; end if;
--   end loop;
--   update inf.contracts set current_version_id = v_id,
--          status = case when status in ('sent', 'ready_to_sign') then 'in_negotiation' else status end
--    where id = c.id;
--   if c.status <> 'draft' then
--     perform inf.contract_notify(c.id, 'creator', 'contract.updated', 'Contract updated: ' || c.number,
--                                 'A new version of your contract is ready to review.');
--   end if;
--   return v_id;
-- end $$;
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.contract_set_ready(p_contract uuid) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare c inf.contracts;
-- begin
--   if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into c from inf.contracts where id = p_contract for update;
--   if c.status not in ('sent', 'in_negotiation') then raise exception 'cannot mark this contract ready' using errcode = '22023'; end if;
--   if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending') then
--     raise exception 'answer every pending change request first' using errcode = '22023';
--   end if;
--   if exists (select 1 from inf.contract_versions v where v.id = c.current_version_id and cardinality(v.missing_fields) > 0) then
--     raise exception 'details are missing' using errcode = '22023';
--   end if;
--   update inf.contracts set status = 'ready_to_sign' where id = c.id;
--   perform inf.contract_notify(c.id, 'creator', 'contract.ready', 'Ready to sign: ' || c.number,
--                               'Your contract is final and ready for your signature.');
-- end $$;
-- -- from 20261017000600_inf_ops.sql
-- create or replace function inf.job_claim(p_worker text, p_limit int default 20, p_kinds text[] default null)
-- returns setof inf.jobs language plpgsql security definer set search_path = '' as $$
-- begin
--   return query
--   with due as (
--     select j.id from inf.jobs j
--      where ((j.status in ('queued', 'failed') and j.run_at <= now())
--             or (j.status = 'running' and j.locked_at < now() - interval '10 minutes'))
--        and (p_kinds is null or j.kind = any (p_kinds))
--      order by j.run_at
--      limit least(greatest(p_limit, 1), 100)
--      for update skip locked)
--   update inf.jobs j set status = 'running', attempts = j.attempts + 1, locked_at = now(), locked_by = left(p_worker, 80)
--     from due where j.id = due.id
--   returning j.*;
-- end $$;
-- -- from 20261017000600_inf_ops.sql
-- create or replace function inf.job_finish(p_id bigint, p_ok boolean, p_error text default null)
-- returns text language plpgsql security definer set search_path = '' as $$
-- declare v_job inf.jobs; v_status text;
-- begin
--   select * into v_job from inf.jobs where id = p_id for update;
--   if v_job.id is null or v_job.status <> 'running' then return 'ignored'; end if;
--   if p_ok then
--     v_status := 'done';
--     update inf.jobs set status = 'done', finished_at = now(), locked_at = null, last_error = null where id = p_id;
--   elsif v_job.attempts >= v_job.max_attempts then
--     v_status := 'dead';
--     update inf.jobs set status = 'dead', finished_at = now(), locked_at = null, last_error = left(p_error, 2000) where id = p_id;
--     perform inf.emit_event('system.job_dead', 'job', p_id::text, jsonb_build_object('kind', v_job.kind, 'error', left(p_error, 500)), 'job_dead:' || p_id);
--   else
--     v_status := 'failed';
--     update inf.jobs set status = 'failed', locked_at = null, last_error = left(p_error, 2000),
--            run_at = now() + least(interval '6 hours', make_interval(mins => power(2, v_job.attempts - 1)::int))
--      where id = p_id;
--   end if;
--   return v_status;
-- end $$;
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.contract_notify(p_contract uuid, p_to text, p_event text, p_title text, p_body text) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare c inf.contracts; d inf.deals; v_user uuid; v_key text := extract(epoch from clock_timestamp())::bigint::text;
-- begin
--   select * into c from inf.contracts where id = p_contract;
--   select * into d from inf.deals where id = c.deal_id;
--   if p_to in ('creator', 'all') then
--     select user_id into v_user from inf.creator_accounts where creator_id = d.creator_id;
--     if v_user is not null then
--       perform inf.notify(v_user, p_event, p_title, p_body, '/creator/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
--                          p_event || ':' || p_contract || ':c:' || v_key);
--     end if;
--     perform inf.notify(m.user_id, p_event, p_title, p_body, '/agency/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
--                        p_event || ':' || p_contract || ':' || m.user_id || ':' || v_key)
--       from inf.agency_creator_links l join inf.agency_members m on m.agency_id = l.agency_id and m.status = 'active' and m.user_id is not null
--      where l.creator_id = d.creator_id and l.status = 'active' and l.can_negotiate_sign;
--   end if;
--   if p_to in ('eduwit', 'all') then
--     perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
--                        p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
--       from inf.staff_profiles sp
--      where sp.status = 'active' and (sp.user_id = d.owner_id or (d.owner_id is null and exists (
--              select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
--               where g.user_id = sp.user_id and rp.permission = 'contract.write')));
--   end if;
--   if p_to = 'signatory' then
--     perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
--                        p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
--       from inf.staff_profiles sp where sp.status = 'active' and sp.is_signatory;
--   end if;
-- end $$;
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.contracts_remind() returns int
-- language plpgsql security definer set search_path = '' as $$
-- declare r record; v_set jsonb := inf.setting('contracts.signing'); v_n int := 0; v_days int;
-- begin
--   for r in
--     select c.id, c.number, c.negotiation_deadline, c.expires_on, c.status from inf.contracts c
--      where c.status in ('sent', 'in_negotiation', 'ready_to_sign', 'signed_by_creator', 'active')
--   loop
--     if r.status <> 'active' and r.negotiation_deadline is not null then
--       v_days := ceil(extract(epoch from (r.negotiation_deadline - now())) / 86400)::int;
--       if v_days = -1 then
--         -- The deadline passed yesterday: Eduwit decides whether to extend, chase or void.
--         perform inf.contract_notify(r.id, 'eduwit', 'contract.deadline_passed', 'Deadline passed: ' || r.number,
--                                     'The negotiation deadline has passed. Follow up, extend the conversation or void the contract.');
--         v_n := v_n + 1;
--       elsif v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'negotiation_reminder_days') x) or v_days = 0 then
--         perform inf.contract_notify(r.id, case when r.status = 'signed_by_creator' then 'signatory' else 'all' end,
--                                     'contract.reminder', 'Reminder: ' || r.number,
--                                     case when r.status = 'signed_by_creator' then 'Waiting for the countersignature.'
--                                          else 'This contract is still open. Please review or sign it.' end);
--         v_n := v_n + 1;
--       end if;
--     elsif r.status = 'active' and r.expires_on is not null then
--       v_days := r.expires_on - (now() at time zone 'Asia/Kolkata')::date;
--       if v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'expiry_reminder_days') x) then
--         perform inf.contract_notify(r.id, 'all', 'contract.expiring', r.number || ' expires in ' || v_days || ' days',
--                                     'Renew the deal or let it end on its expiry date.');
--         v_n := v_n + 1;
--       elsif v_days < 0 then
--         update inf.contracts set status = 'expired', closed_at = now(), status_reason = 'Expiry date passed' where id = r.id;
--       end if;
--     end if;
--   end loop;
--   return v_n;
-- end $$;
-- call inf.apply_client_grants();
