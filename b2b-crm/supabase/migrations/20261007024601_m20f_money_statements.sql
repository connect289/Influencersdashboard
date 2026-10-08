-- M20f: partner statement reconciliation (B12.6) and the Admin's manual enrollment.
--   statement_import          rows the browser read from the partner's Excel/CSV, matched by Eduwit reference, partner record ID,
--                             phone, or name plus programme, into matched / partner only / amount mismatch
--   statement_detail          the three piles plus Eduwit only (enrollments in the period the statement does not list)
--   statement_resolve         verify the enrollment from the line, record a missing one, or dismiss with a note
--   statement_verify_matched  verifies every matched line whose enrollment is still reported
--   money_enrollment_add      the Admin records an enrollment for a partner lead by its reference

create or replace function b2b.statement_match_row(p_partner bigint, r jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_alloc bigint;
  v_method text;
  v_phone text := right(regexp_replace(coalesce(r ->> 'phone', ''), '\D', '', 'g'), 10);
  v_name text := lower(nullif(trim(r ->> 'name'), ''));
  v_prog text := lower(nullif(trim(r ->> 'programme'), ''));
  v_n int;
begin
  if nullif(trim(r ->> 'reference'), '') is not null then
    select a.id into v_alloc from b2b.allocations a where a.partner_id = p_partner and upper(a.reference) = upper(trim(r ->> 'reference')) limit 1;
    if v_alloc is not null then v_method := 'reference'; end if;
  end if;
  if v_alloc is null and nullif(trim(r ->> 'record_id'), '') is not null then
    select a.id into v_alloc from b2b.allocations a where a.partner_id = p_partner and a.partner_record_id = trim(r ->> 'record_id')
     order by a.created_at desc limit 1;
    if v_alloc is not null then v_method := 'record_id'; end if;
  end if;
  if v_alloc is null and length(v_phone) = 10 then
    select a.id into v_alloc from b2b.allocations a join public.student_leads l on l.id = a.lead_id
     where a.partner_id = p_partner and a.status in ('pushed', 'accepted', 'closed') and not a.is_test
       and right(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), 10) = v_phone
     order by a.created_at desc limit 1;
    if v_alloc is not null then v_method := 'phone'; end if;
  end if;
  if v_alloc is null and v_name is not null then
    select count(*), min(a.id) into v_n, v_alloc
      from b2b.allocations a join public.student_leads l on l.id = a.lead_id
      left join public.catalog_programs c on c.id = a.programme_id
     where a.partner_id = p_partner and a.status in ('pushed', 'accepted', 'closed') and not a.is_test
       and lower(trim(l.student_name)) = v_name
       and (v_prog is null or lower(coalesce(c.program_name, concat_ws(' ', c.course, c.specialization), l.enrolled_program, '')) like '%' || v_prog || '%'
            or v_prog like '%' || lower(c.course) || '%');
    if v_n = 1 then v_method := 'name_programme'; else v_alloc := null; end if;
  end if;
  return jsonb_build_object('allocation_id', v_alloc, 'method', v_method);
end $fn$;

/* p: partner_id, period_from, period_to, file_name, rows [{reference, record_id, phone, name, programme, enrolled_on, amount_inr, raw}] (≤ 5,000). */
create or replace function b2b.statement_import(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_from date := nullif(p ->> 'period_from', '')::date;
  v_to date := nullif(p ->> 'period_to', '')::date;
  v_id bigint;
  r jsonb;
  m jsonb;
  e public.enrollments;
  v_row int := 0;
  v_amt numeric;
  v_edu numeric;
  v_gross numeric;
  v_status text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 400 then raise exception 'give the period the statement covers (up to a year)' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') = 0 then raise exception 'the file has no rows' using errcode = '22023'; end if;
  if jsonb_array_length(p -> 'rows') > 5000 then raise exception 'at most 5,000 rows per statement' using errcode = '22023'; end if;
  insert into b2b.partner_statements (partner_id, period_from, period_to, file_name, row_count, created_by)
  values (v_partner, v_from, v_to, nullif(left(p ->> 'file_name', 200), ''), jsonb_array_length(p -> 'rows'), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  for r in select value from jsonb_array_elements(p -> 'rows') loop
    v_row := v_row + 1;
    m := b2b.statement_match_row(v_partner, r);
    e := null;
    v_edu := null; v_gross := null;
    if m ->> 'allocation_id' is not null then
      select * into e from public.enrollments where allocation_id = (m ->> 'allocation_id')::bigint and status <> 'cancelled';
    end if;
    v_amt := round(nullif(regexp_replace(coalesce(r ->> 'amount_inr', ''), '[^0-9.\-]', '', 'g'), '')::numeric, 2);
    if e.id is null then
      v_status := 'partner_only';
    else
      select sum(net_inr), sum(gross_inr) into v_edu, v_gross from b2b.earnings where enrollment_id = e.id and status <> 'void';
      v_status := case when v_amt is null or v_edu is null or abs(v_amt - v_edu) < 1 or abs(v_amt - v_gross) < 1 then 'matched' else 'amount_mismatch' end;
    end if;
    insert into b2b.statement_lines (statement_id, row_no, reference, record_id, phone, name, programme, enrolled_on, amount_inr, raw,
                                     match_status, match_method, allocation_id, enrollment_id, eduwit_amount_inr, diff_inr)
    values (v_id, v_row, nullif(left(trim(r ->> 'reference'), 60), ''), nullif(left(trim(r ->> 'record_id'), 80), ''),
            nullif(left(trim(r ->> 'phone'), 20), ''), nullif(left(trim(r ->> 'name'), 120), ''), nullif(left(trim(r ->> 'programme'), 200), ''),
            case when coalesce(r ->> 'enrolled_on', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'enrolled_on')::date end, v_amt,
            coalesce(r -> 'raw', '{}'), v_status, m ->> 'method', (m ->> 'allocation_id')::bigint, e.id, v_edu,
            case when v_status = 'amount_mismatch' then v_amt - v_edu end);
  end loop;
  perform b2b.log_event('money.statement_imported', null, null, v_partner, jsonb_build_object('statement_id', v_id, 'rows', v_row));
  return b2b.statement_detail(v_id);
end $fn$;

create or replace function b2b.statement_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  s b2b.partner_statements;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from b2b.partner_statements where id = p_id;
  if s.id is null then raise exception 'statement not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'statement', to_jsonb(s) || jsonb_build_object('partner_name', (select coalesce(display_name, name) from b2b.partners where id = s.partner_id)),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', sl.id, 'row_no', sl.row_no, 'reference', coalesce(sl.reference, a.reference), 'record_id', sl.record_id, 'phone', sl.phone,
                'name', coalesce(sl.name, l.student_name), 'programme', sl.programme, 'enrolled_on', sl.enrolled_on, 'amount_inr', sl.amount_inr,
                'match_status', sl.match_status, 'match_method', sl.match_method, 'lead_id', a.lead_id, 'allocation_id', sl.allocation_id,
                'enrollment_id', sl.enrollment_id, 'enrollment_status', e.status, 'eduwit_amount_inr', sl.eduwit_amount_inr, 'diff_inr', sl.diff_inr,
                'resolution', sl.resolution, 'resolution_note', sl.resolution_note) order by sl.row_no), '[]')
                from b2b.statement_lines sl
                left join b2b.allocations a on a.id = sl.allocation_id
                left join public.student_leads l on l.id = a.lead_id
                left join public.enrollments e on e.id = sl.enrollment_id
               where sl.statement_id = s.id),
    'eduwit_only', (select coalesce(jsonb_agg(jsonb_build_object(
                'enrollment_id', e.id, 'lead_id', e.lead_id, 'reference', a.reference, 'name', l.student_name, 'programme', e.programme_name,
                'enrolled_on', e.enrolled_on, 'status', e.status, 'record_id', a.partner_record_id,
                'eduwit_amount_inr', (select sum(x.net_inr) from b2b.earnings x where x.enrollment_id = e.id and x.status <> 'void')) order by e.enrolled_on), '[]')
                from public.enrollments e
                join b2b.allocations a on a.id = e.allocation_id
                left join public.student_leads l on l.id = e.lead_id
               where e.partner_id = s.partner_id and e.source_product = 'b2b' and e.status in ('reported', 'verified')
                 and e.enrolled_on between s.period_from and s.period_to
                 and not exists (select 1 from b2b.statement_lines sl where sl.statement_id = s.id and sl.enrollment_id = e.id)),
    'counts', (select jsonb_build_object(
                'matched', count(*) filter (where match_status = 'matched'),
                'partner_only', count(*) filter (where match_status = 'partner_only'),
                'amount_mismatch', count(*) filter (where match_status = 'amount_mismatch'),
                'resolved', count(*) filter (where resolution is not null),
                'to_verify', count(*) filter (where match_status = 'matched' and resolution is null
                                                and exists (select 1 from public.enrollments e where e.id = sl.enrollment_id and e.status = 'reported')))
                from b2b.statement_lines sl where sl.statement_id = s.id));
end $fn$;

/* action: verify (the line is the proof), record (a partner-only line for a lead Eduwit sent), dismiss (note required). */
create or replace function b2b.statement_resolve(p_line_id bigint, p_action text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  sl b2b.statement_lines;
  v_ref text;
  r jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into sl from b2b.statement_lines where id = p_line_id for update;
  if sl.id is null then raise exception 'line not found' using errcode = 'P0002'; end if;
  if sl.resolution is not null then raise exception 'this line is already %', sl.resolution using errcode = '22023'; end if;
  v_ref := format('statement %s row %s%s', sl.statement_id, sl.row_no, coalesce(' (' || nullif(trim(p_note), '') || ')', ''));
  if p_action = 'verify' then
    if sl.enrollment_id is null then raise exception 'no Eduwit enrollment matches this line; record it first' using errcode = '22023'; end if;
    r := b2b.enrollment_verify(sl.enrollment_id, jsonb_build_object('proof_type', 'statement_line', 'proof_ref', v_ref,
                                                                    'enrolled_on', sl.enrolled_on));
    update b2b.statement_lines set resolution = 'verified', resolution_note = nullif(trim(p_note), ''), resolved_at = now() where id = sl.id;
  elsif p_action = 'record' then
    if sl.allocation_id is null then raise exception 'this student was not sent by Eduwit to this partner, so there is nothing to record' using errcode = '22023'; end if;
    if sl.enrollment_id is not null then raise exception 'an enrollment already exists for this line' using errcode = '22023'; end if;
    r := b2b.enrollment_record(sl.allocation_id, jsonb_build_object('enrolled_on', sl.enrolled_on, 'proof_ref', v_ref), 'statement');
    update b2b.statement_lines set resolution = 'recorded', enrollment_id = (r ->> 'id')::bigint, resolution_note = nullif(trim(p_note), ''), resolved_at = now()
     where id = sl.id;
  elsif p_action = 'dismiss' then
    if coalesce(trim(p_note), '') = '' then raise exception 'say why it is dismissed' using errcode = '22023'; end if;
    update b2b.statement_lines set resolution = 'dismissed', resolution_note = left(trim(p_note), 300), resolved_at = now() where id = sl.id;
  else
    raise exception 'unknown action' using errcode = '22023';
  end if;
  perform b2b.log_event('money.statement_line_resolved', null, sl.allocation_id, (select partner_id from b2b.partner_statements where id = sl.statement_id),
                        jsonb_build_object('line_id', sl.id, 'action', p_action, 'note', p_note));
  return jsonb_build_object('line_id', sl.id, 'action', p_action, 'result', r);
end $fn$;

create or replace function b2b.statement_verify_matched(p_statement_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  v_ok int := 0;
  v_err jsonb := '[]';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  for v_id in select sl.id from b2b.statement_lines sl join public.enrollments e on e.id = sl.enrollment_id
               where sl.statement_id = p_statement_id and sl.match_status = 'matched' and sl.resolution is null and e.status = 'reported'
               order by sl.row_no loop
    begin
      perform b2b.statement_resolve(v_id, 'verify', null);
      v_ok := v_ok + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('line_id', v_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('verified', v_ok, 'errors', v_err);
end $fn$;

/* p: reference (EDW-…), enrolled_on, fee_amount_inr, fee_paid_inr, programme_id, proof_ref. */
create or replace function b2b.money_enrollment_add(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_alloc bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select a.id into v_alloc from b2b.allocations a
   where upper(a.reference) = upper(trim(p ->> 'reference')) and a.destination_type = 'partner' limit 1;
  if v_alloc is null then raise exception 'no partner lead has that reference' using errcode = 'P0002'; end if;
  return b2b.enrollment_record(v_alloc, p, 'admin');
end $fn$;

revoke execute on function b2b.statement_match_row(bigint, jsonb) from public, anon, authenticated;
grant execute on function b2b.statement_match_row(bigint, jsonb) to service_role;
revoke execute on function b2b.statement_import(jsonb), b2b.statement_detail(bigint), b2b.statement_resolve(bigint, text, text),
                           b2b.statement_verify_matched(bigint), b2b.money_enrollment_add(jsonb) from public, anon;
grant execute on function b2b.statement_import(jsonb), b2b.statement_detail(bigint), b2b.statement_resolve(bigint, text, text),
                          b2b.statement_verify_matched(bigint), b2b.money_enrollment_add(jsonb) to authenticated, service_role;
