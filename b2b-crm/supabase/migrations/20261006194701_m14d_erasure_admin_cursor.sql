-- M14d: erasure requests from the B2C CRM (b2ccrm.erasure_requested, m14b) are listed on the System screen and closed by
-- the Admin as done or rejected, with a note. The erasure itself (removing the student's personal data across Witty,
-- B2B and partner copies) is a manual, audited step until a data-retention job exists; this only tracks the request.
-- Also: GET /v1/handoffs returned next_after = null when nothing new had happened, so a client storing the cursor would
-- start again from the beginning. It now echoes the caller's cursor in that case.

create or replace function b2b.erasure_request_close(p_id bigint, p_status text, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare r b2b.erasure_requests;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status is null or p_status not in ('done', 'rejected') then raise exception 'status must be done or rejected' using errcode = '22023'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required' using errcode = '22023'; end if;
  update b2b.erasure_requests set status = p_status, note = left(trim(p_note), 300), closed_at = now()
   where id = p_id and status = 'open' returning * into r;
  if r.id is null then raise exception 'open request not found' using errcode = 'P0002'; end if;
  perform b2b.log_event('erasure.' || p_status, r.lead_id, null, null, jsonb_build_object('erasure_request_id', r.id, 'note', r.note));
end $fn$;

/* Open erasure requests for the System screen, oldest first. */
create or replace function b2b.erasure_requests_open()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'lead_id', e.lead_id, 'source', e.source, 'requested_at', e.requested_at,
                                                       'note', e.note, 'name', l.student_name) order by e.requested_at)
                     from b2b.erasure_requests e left join public.student_leads l on l.id = e.lead_id where e.status = 'open'), '[]');
end $fn$;

create or replace function b2b.api_b2c_handoffs(p_key text, p_since timestamptz, p_after bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare k jsonb; v_rows jsonb; v_last bigint;
begin
  k := b2b.api_key_check(p_key, 'events');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  -- the cursor advances past every scanned event, including ones that publish nothing to B2C
  with scanned as (
    select ev from b2b.events ev
     where ev.type in ('b2c.lead_handed_off', 'b2c.lead_reenquired', 'b2c.lead_flagged', 'b2c.lead_close_agreed', 'lead.accepted')
       and ev.id > coalesce(p_after, 0) and ev.occurred_at >= coalesce(p_since, '-infinity')
     order by ev.id limit least(greatest(coalesce(p_limit, 200), 1), 500))
  select coalesce((select jsonb_agg(p.envelope order by (s.ev).id, p.envelope ->> 'id')
                     from scanned s cross join lateral b2b.published_events(s.ev) p
                    where p.event_type like 'b2c.%' or p.event_type = 'b2b.lead_routed_to_partner'), '[]'),
         (select max((s.ev).id) from scanned s)
    into v_rows, v_last;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('events', v_rows, 'next_after', coalesce(v_last, p_after)));
end $fn$;

revoke execute on function b2b.erasure_request_close(bigint, text, text), b2b.erasure_requests_open() from public, anon;
grant execute on function b2b.erasure_request_close(bigint, text, text), b2b.erasure_requests_open() to authenticated, service_role;
