-- 0004 one.events: incremental copy of the apps' event logs into one shape (spec §7).
-- Each source is one SELECT returning source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id,
-- wm_at, with $1 the id to scan from, $2 the start of the time window, $3 the batch size. Two kinds of source:
--   append logs (ids only grow): read from the watermark minus events.id_overlap ids, so a row whose transaction
--   committed after a higher id was copied is still picked up (D-045);
--   state rows (outbox, advisor sessions, cron runs): every row touched in the last events.window_hours hours is read
--   again each time, and each state it is seen in becomes one event (source_id "<id>:<state>"), so a status change
--   is never missed and no watermark can freeze (D-045).
-- Rows already copied are skipped by the unique (app, source_table, source_id). Every payload goes through one.redact()
-- before it is stored (B1, D-046). A missing source is recorded as source_missing.

-- Removes personal data from a JSON value at any depth: keys matching events.pii_columns (case-insensitive; "*" is a
-- wildcard) are dropped with everything under them; any remaining string that holds an email address or is
-- phone-shaped, and any number shaped like an Indian mobile, is replaced by "[email]" or "[phone]". Spec §2: never a
-- raw name, phone or email outside the apps.
create or replace function one.redact(p_value jsonb, p_keys text[]) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_out jsonb;
  v_text text;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select coalesce(jsonb_object_agg(e.key, one.redact(e.value, p_keys)), '{}'::jsonb) into v_out
        from jsonb_each(p_value) e
       where not exists (select 1 from unnest(p_keys) k
                          where lower(e.key) like replace(replace(lower(k), '_', '\_'), '*', '%'));
      return v_out;
    when 'array' then
      select coalesce(jsonb_agg(one.redact(a.value, p_keys) order by a.ord), '[]'::jsonb) into v_out
        from jsonb_array_elements(p_value) with ordinality a(value, ord);
      return v_out;
    when 'string' then
      v_text := p_value #>> '{}';
      if v_text ~* '[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}' then
        return '"[email]"'::jsonb;
      end if;
      if v_text ~ '^\+?[0-9][0-9 ().-]{8,20}$' and length(regexp_replace(v_text, '\D', '', 'g')) between 10 and 15 then
        return '"[phone]"'::jsonb;
      end if;
      return p_value;
    when 'number' then
      -- An Indian mobile stored as a number (10 digits from 6, optionally 91 first). Epoch times and ids do not match.
      if p_value::text ~ '^(91)?[6-9][0-9]{9}$' then
        return '"[phone]"'::jsonb;
      end if;
      return p_value;
    else
      return p_value;
  end case;
end $$;

create or replace function one.events_copy(p_source text, p_app text, p_sql text) returns integer
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('events'), '{}');
  v_wm one.event_watermarks;
  v_batch integer := coalesce((v_cfg ->> 'batch')::int, 5000);
  v_overlap bigint := coalesce((v_cfg ->> 'id_overlap')::bigint, 1000);
  v_window interval := make_interval(hours => coalesce((v_cfg ->> 'window_hours')::int, 48));
  v_pii text[] := coalesce(array(select jsonb_array_elements_text(v_cfg -> 'pii_columns')), '{}');
  v_inserted integer;
  v_max_id bigint;
  v_max_at timestamptz;
begin
  perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
  insert into one.event_watermarks (source) values (p_source) on conflict do nothing;
  select * into v_wm from one.event_watermarks where source = p_source for update;
  execute format($q$
    with src (source_id, occurred_at, type, lead_id, actor_type, actor_id, payload, wm_id, wm_at) as (%s),
    ins as (
      insert into one.events (app, source_table, source_id, occurred_at, type, lead_id, actor_type, actor_id, payload)
      select %L, %L, s.source_id, s.occurred_at, s.type, s.lead_id, s.actor_type, s.actor_id, one.redact(coalesce(s.payload, '{}'), $4)
        from src s where s.occurred_at is not null
      on conflict (app, source_table, source_id) do nothing
      returning 1)
    select (select count(*) from ins)::int, (select max(wm_id) from src), (select max(wm_at) from src)$q$, p_sql, p_app, p_source)
    into v_inserted, v_max_id, v_max_at
    using greatest(coalesce(v_wm.last_id, 0) - v_overlap, 0), now() - v_window, v_batch, v_pii;
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
      'run'::text as actor_type, r.run_id as actor_id, to_jsonb(r) as payload, r.id as wm_id, null::timestamptz as wm_at
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
    from public.w2_outbox r where r.created_at > $2 order by r.id desc limit $3$$),
  ('b2b.events', 'b2b', $$select r.id::text, r.occurred_at, r.type, r.lead_id, r.actor_type, r.actor_id, to_jsonb(r), r.id, null::timestamptz
    from b2b.events r where r.id > $1 order by r.id limit $3$$),
  ('b2b.allocation_transitions', 'b2b', $$select r.id::text, r.at, 'allocation.' || r.to_status,
      (select a.lead_id from b2b.allocations a where a.id = r.allocation_id), r.actor_type, r.actor_id, to_jsonb(r), r.id, null::timestamptz
    from b2b.allocation_transitions r where r.id > $1 order by r.id limit $3$$),
  ('b2b.partner_events', 'b2b', $$select r.id::text, r.received_at, 'partner.' || coalesce(r.event_type, '?'), r.lead_id, 'partner'::text, r.partner_id::text,
      jsonb_build_object('status', r.status, 'result', left(r.result, 300), 'allocation_id', r.allocation_id, 'record_id', r.record_id), r.id, null::timestamptz
    from b2b.partner_events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.events', 'b2c', $$select r.id::text, r.at, r.type, r.lead_id, r.actor_type, r.actor_id::text, to_jsonb(r), r.id, null::timestamptz
    from b2c.events r where r.id > $1 order by r.id limit $3$$),
  ('b2c.activities', 'b2c', $$select r.id::text, r.at, 'activity.' || coalesce(r.kind, '?'), r.lead_id, 'user'::text, r.actor_id::text,
      to_jsonb(r) - 'body' - 'meta', r.id, null::timestamptz
    from b2c.activities r where r.id > $1 order by r.id limit $3$$),
  ('b2c.audit_log', 'b2c', $$select r.id::text, r.at, 'audit.' || r.action, r.lead_id, 'user'::text, r.actor_id::text, to_jsonb(r) - 'detail', r.id, null::timestamptz
    from b2c.audit_log r where r.id > $1 order by r.id limit $3$$),
  ('public.web_funnel_events', 'web', $$select r.id::text, r.at, 'funnel.' || r.funnel || '.' || r.step, null::bigint, 'anon'::text, r.anon_id,
      to_jsonb(r), r.id, null::timestamptz
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
    where x.at > $2 order by x.at desc limit $3$$),
  ('public.touchpoints', 'integrity', $$select r.id::text, r.occurred_at, 'touch.' || coalesce(r.event_type, '?'), r.lead_id, 'system'::text, r.source_system,
      to_jsonb(r) - 'payload', r.id, null::timestamptz
    from public.touchpoints r where r.id > $1 order by r.id limit $3$$),
  ('cron.job_run_details', 'platform', $$select d.runid::text, d.start_time, 'cron.failed', null::bigint, 'job'::text, j.jobname,
      jsonb_build_object('jobid', d.jobid, 'message', left(d.return_message, 300)), null::bigint, d.end_time
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
    where d.status = 'failed' and d.runid > (select max(x.runid) from cron.job_run_details x) - 20000 and d.start_time > $2
    order by d.runid desc limit $3$$),
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

-- One source, isolated: its copy count, or "<source>_error" when it failed for any reason but a missing source.
create or replace function one.events_copy_safe(p_source text, p_app text, p_sql text) returns jsonb
language plpgsql set search_path = '' as $$
begin
  return jsonb_build_object(p_source, one.events_copy(p_source, p_app, p_sql));
exception when others then
  insert into one.event_watermarks (source, last_status, last_error) values (p_source, 'error', left(sqlerrm, 300))
  on conflict (source) do update set last_status = 'error', last_error = excluded.last_error, updated_at = now();
  return jsonb_build_object(p_source || '_error', left(sqlerrm, 200));
end $$;

-- Copies every source once in the caller's transaction (one.tick(); the cron job commits per source instead).
create or replace function one.events_refresh() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_src record;
  v_out jsonb := '{}';
begin
  for v_src in select * from one.events_sources() loop
    v_out := v_out || one.events_copy_safe(v_src.source, v_src.app, v_src.sql);
  end loop;
  return v_out;
end $$;

call one.apply_grants();
