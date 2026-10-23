-- 0004 one.events: incremental copy of the apps' event logs into one shape (spec §7).
-- Each source is one SELECT that returns rows newer than its watermark ($1 last id, $2 last time) with the columns
-- source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id, wm_at. $3 is the batch size, $4 the
-- PII column names removed from payloads. Rows already copied are skipped by the unique (app, source_table,
-- source_id). Sources that change state rather than append (outbox, advisor sessions, cron runs) re-scan a
-- 10-minute overlap by time. A missing source is recorded as source_missing (staging lacks several, D-009).

create or replace function one.events_copy(p_source text, p_app text, p_sql text) returns integer
language plpgsql set search_path = '' as $$
declare
  v_wm one.event_watermarks;
  v_batch integer := coalesce((one.setting('events') ->> 'batch')::int, 5000);
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(one.setting('events') -> 'pii_columns')), '{}');
  v_inserted integer;
  v_max_id bigint;
  v_max_at timestamptz;
begin
  insert into one.event_watermarks (source) values (p_source) on conflict do nothing;
  select * into v_wm from one.event_watermarks where source = p_source for update;
  execute format($q$
    with src (source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id, wm_at) as (%s),
    ins as (
      insert into one.events (app, source_table, source_id, occurred_at, type, lead_id, actor_type, actor_id, payload)
      select %L, %L, s.source_id, s.occurred_at, s.type, s.lead_id, s.actor_type, s.actor_id, coalesce(s.payload, '{}')
        from src s where s.occurred_at is not null
      on conflict (app, source_table, source_id) do nothing
      returning 1)
    select (select count(*) from ins)::int, (select max(wm_id) from src), (select max(wm_at) from src)$q$, p_sql, p_app, p_source)
    into v_inserted, v_max_id, v_max_at
    using coalesce(v_wm.last_id, 0), coalesce(v_wm.last_at, '-infinity'::timestamptz), v_batch, v_pii;
  update one.event_watermarks
     set last_id = greatest(last_id, v_max_id), last_at = greatest(last_at, v_max_at), last_status = 'ok', last_error = null,
         rows_copied = rows_copied + v_inserted, updated_at = now()
   where source = p_source;
  return v_inserted;
exception
  when undefined_table or undefined_function or undefined_column or invalid_schema_name then
    -- The body's writes were rolled back with the error, including the watermark row, so upsert it.
    insert into one.event_watermarks (source, last_status, last_error) values (p_source, 'source_missing', left(sqlerrm, 300))
    on conflict (source) do update set last_status = 'source_missing', last_error = excluded.last_error, updated_at = now();
    return -1;
end $$;

create or replace function one.events_sources() returns table (source text, app text, sql text)
language sql immutable set search_path = '' as $src$
  values
  ('public.w2_events', 'witty', $$select r.id::text as source_id, r.created_at as occurred_at, r.type,
      (select sl.id from public.student_leads sl where sl.whatsapp_number = public.crm_norm_phone(r.phone) limit 1) as lead_id,
      'run'::text as actor_type, r.run_id as actor_id, to_jsonb(r) - $4 as payload, r.id as wm_id, null::timestamptz as wm_at
    from public.w2_events r where r.id > $1 order by r.id limit $3$$),
  ('public.w2_messages', 'witty', $$select r.id::text, r.created_at, 'msg.' || coalesce(r.direction, '?') || '.' || coalesce(r.kind, '?'),
      (select sl.id from public.student_leads sl where sl.whatsapp_number = public.crm_norm_phone(r.phone) limit 1),
      'model'::text, r.model,
      jsonb_build_object('direction', r.direction, 'kind', r.kind, 'reply_source', r.reply_source, 'latency_ms', r.latency_ms,
                         'prompt_tokens', r.prompt_tokens, 'output_tokens', r.output_tokens, 'verify_errors', r.verify_errors),
      r.id, null::timestamptz
    from public.w2_messages r where r.id > $1 order by r.id limit $3$$),
  ('public.w2_outbox', 'witty', $$select r.id || ':' || r.status, coalesce(r.sent_at, r.created_at), 'outbox.' || r.status,
      case when r.crm_record_id ~ '^[0-9]+$' then r.crm_record_id::bigint end, 'outbox'::text, r.target,
      jsonb_build_object('status', r.status, 'attempts', r.attempts, 'target', r.target, 'event_type', r.event_type, 'last_error', left(r.last_error, 300)),
      null::bigint, coalesce(r.sent_at, r.created_at)
    from public.w2_outbox r where coalesce(r.sent_at, r.created_at) > $2 - interval '10 minutes'
    order by coalesce(r.sent_at, r.created_at) limit $3$$),
  ('b2b.events', 'b2b', $$select r.id::text, r.occurred_at, r.type, r.lead_id, r.actor_type, r.actor_id, to_jsonb(r) - $4, r.id, null::timestamptz
    from b2b.events r where r.id > $1 order by r.id limit $3$$),
  ('b2b.allocation_transitions', 'b2b', $$select r.id::text, r.at, 'allocation.' || r.to_status,
      (select a.lead_id from b2b.allocations a where a.id = r.allocation_id), r.actor_type, r.actor_id, to_jsonb(r), r.id, null::timestamptz
    from b2b.allocation_transitions r where r.id > $1 order by r.id limit $3$$),
  ('b2b.partner_events', 'b2b', $$select r.id::text, r.received_at, 'partner.' || coalesce(r.event_type, '?'), r.lead_id, 'partner'::text, r.partner_id::text,
      jsonb_build_object('status', r.status, 'result', left(r.result, 300), 'allocation_id', r.allocation_id, 'record_id', r.record_id), r.id, null::timestamptz
    from b2b.partner_events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.events', 'b2c', $$select r.id::text, r.at, r.type, r.lead_id, r.actor_type, r.actor_id::text, to_jsonb(r) - $4, r.id, null::timestamptz
    from b2c.events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.activities', 'b2c', $$select r.id::text, r.at, 'activity.' || coalesce(r.kind, '?'), r.lead_id, 'user'::text, r.actor_id::text,
      (to_jsonb(r) - $4) - 'body' - 'meta', r.id, null::timestamptz
    from b2c.activities r where r.id > $1 order by r.id limit $3$$),
  ('b2c.audit_log', 'b2c', $$select r.id::text, r.at, 'audit.' || r.action, r.lead_id, 'user'::text, r.actor_id::text, to_jsonb(r) - $4 - 'detail', r.id, null::timestamptz
    from b2c.audit_log r where r.id > $1 order by r.id limit $3$$),
  ('public.web_funnel_events', 'web', $$select r.id::text, r.at, 'funnel.' || r.funnel || '.' || r.step, null::bigint, 'anon'::text, r.anon_id,
      to_jsonb(r) - $4, r.id, null::timestamptz
    from public.web_funnel_events r where r.id > $1 order by r.id limit $3$$),
  ('public.web_audit_log', 'web', $$select r.id::text, r.at, 'audit.' || r.action, null::bigint, 'staff'::text, r.actor_email,
      jsonb_build_object('entity', r.entity, 'entity_id', r.entity_id, 'request_id', r.request_id), r.id, null::timestamptz
    from public.web_audit_log r where r.id > $1 order by r.id limit $3$$),
  ('public.web_advisor_sessions', 'web', $$select x.source_id, x.at, x.type, x.lead_id, 'session'::text, x.session, x.payload, null::bigint, x.at from (
      select r.id || ':open' as source_id, r.created_at as at, 'advisor.open' as type, r.lead_id, r.id::text as session,
             jsonb_build_object('phase', r.phase, 'is_test', r.is_test) as payload from public.web_advisor_sessions r
      union all select r.id || ':escalate', r.escalated_at, 'advisor.escalate', r.lead_id, r.id::text, jsonb_build_object('classification', r.classification)
        from public.web_advisor_sessions r where r.escalated_at is not null
      union all select r.id || ':end', r.ended_at, 'advisor.end', r.lead_id, r.id::text,
             jsonb_build_object('turns', r.turns, 'cost_usd', r.cost_usd, 'readiness', r.readiness) from public.web_advisor_sessions r where r.ended_at is not null) x
    where x.at > $2 - interval '10 minutes' order by x.at limit $3$$),
  ('public.touchpoints', 'integrity', $$select r.id::text, r.occurred_at, 'touch.' || coalesce(r.event_type, '?'), r.lead_id, 'system'::text, r.source_system,
      (to_jsonb(r) - $4) - 'payload', r.id, null::timestamptz
    from public.touchpoints r where r.id > $1 order by r.id limit $3$$),
  ('cron.job_run_details', 'platform', $$select d.runid::text, d.start_time, 'cron.failed', null::bigint, 'job'::text, j.jobname,
      jsonb_build_object('jobid', d.jobid, 'message', left(d.return_message, 300)), null::bigint, d.end_time
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
    where d.status = 'failed' and d.end_time > $2 - interval '10 minutes' order by d.end_time limit $3$$),
  ('inf.domain_events', 'influencer', $$select r.id::text, r.occurred_at, r.type, null::bigint, 'user'::text, r.actor_id::text,
      jsonb_build_object('subject_type', r.subject_type, 'subject_id', r.subject_id), r.id, null::timestamptz
    from inf.domain_events r where r.id > $1 order by r.id limit $3$$),
  ('one.incidents', 'one', $$select r.id::text, r.opened_at, 'one.incident.' || lower(r.severity), null::bigint, 'one'::text, r.check_id,
      jsonb_build_object('check_id', r.check_id, 'app', r.app, 'severity', r.severity), r.id, null::timestamptz
    from one.incidents r where r.id > $1 order by r.id limit $3$$),
  ('one.actions', 'one', $$select r.id::text, r.ran_at, 'one.action.' || r.status, null::bigint, 'one'::text, r.fix_id,
      jsonb_build_object('fix_id', r.fix_id, 'dry_run', r.dry_run, 'incident_id', r.incident_id), r.id, null::timestamptz
    from one.actions r where r.id > $1 order by r.id limit $3$$)
$src$;

-- Copies every source once; each source is isolated, so one broken source cannot stop the others.
create or replace function one.events_refresh() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_src record;
  v_out jsonb := '{}';
begin
  for v_src in select * from one.events_sources() loop
    begin
      v_out := v_out || jsonb_build_object(v_src.source, one.events_copy(v_src.source, v_src.app, v_src.sql));
    exception when others then
      v_out := v_out || jsonb_build_object(v_src.source || '_error', left(sqlerrm, 200));
      insert into one.event_watermarks (source, last_status, last_error) values (v_src.source, 'error', left(sqlerrm, 300))
      on conflict (source) do update set last_status = 'error', last_error = excluded.last_error, updated_at = now();
    end;
  end loop;
  return v_out;
end $$;

call one.apply_grants();
