-- Rollback of 0037: B2C-11, FIX-SENDQ-B2C, B2C-07's stuck_sending and the per-fix switch-on rule go; 0019's plan and
-- act and 0020's settings_check come back verbatim. Incidents, proposals and actions are history kept forever: while any
-- exists for B2C-11 or FIX-SENDQ-B2C, this rollback refuses, unless the session sets one.rollback_discards_history = on
-- (the local test and the staging rehearsal do; on production, export first and decide). A fix switched on stays
-- switched on: only the new key is taken out of "fixes".

do $$
begin
  if coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on'
     and (exists (select 1 from one.incidents where check_id = 'B2C-11')
          or exists (select 1 from one.actions where fix_id = 'FIX-SENDQ-B2C')
          or exists (select 1 from one.proposals p where p.source_key like 'fix:FIX-SENDQ-B2C:%')) then
    raise exception '0037 rollback refused: schema one holds B2C-11 incidents or FIX-SENDQ-B2C actions or proposals, which are kept forever. Export them, then run this rollback with one.rollback_discards_history = on'
      using errcode = '55000';
  end if;
end $$;

select set_config('one.history_writer', 'on', true);
delete from one.deliveries where incident_id in (select id from one.incidents where check_id = 'B2C-11');
update one.ai_tasks set incident_id = null, status = case when status in ('pending', 'claimed', 'deferred') then 'cancelled' else status end
 where incident_id in (select id from one.incidents where check_id = 'B2C-11');
delete from one.actions where fix_id = 'FIX-SENDQ-B2C' or incident_id in (select id from one.incidents where check_id = 'B2C-11');
delete from one.proposals where source_key like 'fix:FIX-SENDQ-B2C:%' or incident_id in (select id from one.incidents where check_id = 'B2C-11');
delete from one.incidents where check_id = 'B2C-11';
delete from one.results where check_id = 'B2C-11';
delete from one.check_state where check_id = 'B2C-11';
delete from one.checks where id = 'B2C-11';
select set_config('one.history_writer', 'off', true);

update one.checks c
   set sql = $sql$with mk as (
  select lead_id, created_at from b2c.wa_messages
   where direction = 'out' and status in ('sent', 'delivered', 'read') and (campaign_id is not null or journey_run_id is not null or coalesce(purpose, '') ~* 'market|campaign')
     and created_at > now() - interval '30 days'),
today as (select (now() at time zone 'Asia/Kolkata')::date as d),
v as (
  select (select count(*) from b2c.send_queue where status = 'queued' and not_before < now() - interval '15 minutes') as queue_stuck,
         (select count(*) from mk, today where (created_at at time zone 'Asia/Kolkata')::date = today.d
            and (created_at at time zone 'Asia/Kolkata')::time not between time '09:00' and time '20:00') as marketing_off_hours_today,
         (select count(*) from (select lead_id from mk, today where (created_at at time zone 'Asia/Kolkata')::date = today.d group by lead_id having count(*) > 1) x) as leads_over_1_today,
         (select count(*) from (select lead_id from mk group by lead_id having count(*) > 6) x) as leads_over_6_30d,
         (select count(*) from (select e.lead_id from b2c.emails e, today where e.direction = 'out' and (e.created_at at time zone 'Asia/Kolkata')::date = today.d
                                  group by e.lead_id having count(*) > 2) x) as leads_over_2_emails_today)
select queue_stuck + marketing_off_hours_today + leads_over_1_today + leads_over_6_30d + leads_over_2_emails_today = 0 as ok, to_jsonb(v) as value
  from v$sql$, description = $d$b2c.send_queue queued past not_before by more than 15 min; a marketing WhatsApp (campaign or journey) sent today outside 09:00 to 20:00 IST; a lead with more than 1 marketing WhatsApp today or more than 6 in 30 days; a lead with more than 2 emails today.$d$, auto_fix_id = null,
       version = c.version + 1, updated_at = now()
 where c.id = 'B2C-07';
update one.checks c set description = $d$Spark's /api/health, written by the app's health probe; expected every 300 s (D-133).$d$, version = c.version + 1, updated_at = now()
 where c.id = 'HB-spark' and c.description is distinct from $d$Spark's /api/health, written by the app's health probe; expected every 300 s (D-133).$d$;

create or replace function one.fix_plan(p_fix text, p_inc one.incidents) returns jsonb
language plpgsql set search_path = '' as $$
declare
  e jsonb := coalesce(p_inc.evidence -> 'value', '{}');
  v_rows jsonb := '[]';
  v_n integer := 0;
  v_test integer := 0;
  v_status text;
  v_url text;
  v_old boolean;
begin
  if not exists (select 1 from one.fixes f where f.id = p_fix and p_inc.check_id = any (f.checks)) then
    return jsonb_build_object('applies', false, 'why_not', 'not one of this fix''s checks');
  end if;
  if coalesce(p_inc.evidence ->> 'status', '') <> 'fail' then
    return jsonb_build_object('applies', false,
                              'why_not', format('%s could not run (%s): it observed nothing to fix', p_inc.check_id, coalesce(p_inc.evidence ->> 'status', 'no reading')));
  end if;
  case p_fix
    when 'FIX-OUTBOX-W2' then
      if not 'outbox_failed' = any (p_inc.subjects) then
        return jsonb_build_object('applies', false, 'why_not', 'WITTY-01 does not name outbox_failed');
      end if;
      -- A test phone as Witty's own w2_is_test() decides (910000 and six digits, or a trusted test phone).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     (coalesce(o.phone, '') similar to '910000[0-9]{6}'
                      or exists (select 1 from public.w2_trusted t where t.phone = o.phone and t.is_test)) as t
                from public.w2_outbox o
               where o.status = 'failed' and o.attempts < 8
                 and coalesce(o.last_error, '') !~ '(INVALID_DATA|MANDATORY_NOT_FOUND|DUPLICATE_DATA)') x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no failed row with a retryable error' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test,
                                'would', 'open a proposal to Witty: these rows cannot be sent again from Eduwit One');
    when 'FIX-CACHE-W2' then
      if not 'cache_expired' = any (p_inc.subjects) then
        return jsonb_build_object('applies', false, 'why_not', 'WITTY-01 does not name cache_expired');
      end if;
      select coalesce(jsonb_agg(c.name order by c.name), '[]'), count(*) into v_rows, v_n
        from public.w2_gemini_caches c where c.expire_at < now();
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no cache has expired' end,
                                'count', v_n, 'target', jsonb_build_object('caches', v_rows),
                                'would', 'open a proposal: the n8n API cannot start Witty''s Cache Manager');
    when 'FIX-N8N-RETRY' then
      -- Each execution once, never a retry of a retry: left out are the probe's retries_15m and any id an earlier run
      -- named, unless that run's report says the app never sent it (skipped: out of time, not configured, not this
      -- workflow's, no longer in error). An unreported run counts as sent (phase 7 review M9, M10).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where x.n <= 500), '[]'), count(*) into v_rows, v_n
        from (select x.id, row_number() over (order by x.id) as n
                from jsonb_array_elements_text(coalesce(e -> 'failed_15m', '[]')) as x(id)
               where not coalesce(e -> 'retries_15m', '[]') ? x.id
                 and not exists (
                   select 1 from one.actions b
                    where b.fix_id = 'FIX-N8N-RETRY' and b.step = 'before' and not b.dry_run and coalesce(b.target -> 'rows', '[]') ? x.id
                      and not exists (select 1 from one.actions a2
                                       where a2.run_key = b.run_key and a2.step = 'after'
                                         and exists (select 1 from jsonb_array_elements(coalesce(a2.result -> 'skipped', '[]')) k where k ->> 'id' = x.id)))) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no failed execution that was not retried already' end,
                                'rows', v_rows, 'count', v_n,
                                'target', jsonb_build_object('workflow_id', one.setting('n8n') ->> 'witty_workflow_id'),
                                'would', 'retry each execution once through the n8n API');
    when 'FIX-OUTBOX-B2B' then
      if coalesce((e #>> '{deliveries,dead_7d}')::int, 0) + coalesce((e #>> '{deliveries,waiting_over_1h}')::int, 0) = 0 then
        return jsonb_build_object('applies', false, 'why_not', 'B2B-01 reports no dead or waiting delivery');
      end if;
      -- As B2B-01 counts them: dead, or failed and waiting over an hour (a younger failed one is still in B2B's own
      -- backoff). A test lead's handoff carries test true at the top of its payload or in its data (as Spark reads it).
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     coalesce(o.payload @> '{"test": true}' or o.payload -> 'data' @> '{"test": true}', false) as t
                from b2b.integration_outbox o
               where (o.status = 'dead' or (o.status = 'failed' and o.created_at < now() - interval '1 hour'))
                 and o.created_at > now() - interval '7 days' and o.endpoint_id is not null
                 and not exists (select 1 from one.actions a where a.fix_id = 'FIX-OUTBOX-B2B' and a.step = 'after' and not a.dry_run
                                    and coalesce(a.result -> 'done', '[]') @> to_jsonb(o.id))) x;
      return jsonb_build_object('applies', v_n > 0, 'why_not', case when v_n = 0 then 'no dead or long-failed delivery that was not sent again already' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test,
                                'would', 'open a proposal; approving it runs b2b.outbox_retry(id) for each under the owner''s session');
    when 'FIX-CURSOR-B2C' then
      if coalesce((e #>> '{b2c_sync,cursor_age_seconds}')::numeric, 0) <= 600 then
        return jsonb_build_object('applies', false, 'why_not', 'the B2C sync cursor is not over 600 s');
      end if;
      select d.status into v_status from cron.job_run_details d join cron.job j on j.jobid = d.jobid
       where j.jobname = 'b2b-b2c-sync-tick' order by d.runid desc limit 1;
      if v_status = 'failed' then
        return jsonb_build_object('applies', false, 'why_not', 'b2b-b2c-sync-tick failed on its last run: a person looks first');
      end if;
      return jsonb_build_object('applies', true, 'count', 1,
                                'target', jsonb_build_object('cursor_age_seconds', e #> '{b2c_sync,cursor_age_seconds}', 'job_last_status', v_status),
                                'would', 'run b2b.b2c_sync_tick(200) once');
    when 'FIX-WEBHOOK-REKICK' then
      v_url := rtrim(one.setting('hosts') ->> 'spark', '/') || '/v1/handoffs';
      if v_url is null then
        return jsonb_build_object('applies', false, 'why_not', 'hosts.spark is not set');
      end if;
      return jsonb_build_object('applies', true, 'count', 1,
                                'target', jsonb_build_object('url', v_url,
                                          'endpoints', (select coalesce(jsonb_agg(x -> 'id'), '[]') from jsonb_array_elements(coalesce(e -> 'endpoints', '[]')) x)),
                                'would', 'check that ' || v_url || ' answers, then run b2b.outbox_kick()');
    when 'FIX-INBOX-RETRY' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('error', e -> 'error', 'stuck', e -> 'stuck'),
                                'would', 'run b2c.inbox_retry(50)');
    when 'FIX-OUTBOX-B2C' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('count', e -> 'count', 'by_status', e -> 'by_status'),
                                'would', 'run b2c.outbox_unstick(), then b2c.job_call(''/api/internal/sync?mode=urgent'')');
    when 'FIX-OUTBOX-WEB' then
      v_old := coalesce((e ->> 'outbox_oldest_pending_seconds')::numeric, 0) > 900;
      if coalesce((e ->> 'outbox_dead')::int, 0) = 0 and not v_old then
        return jsonb_build_object('applies', false, 'why_not', 'WEB-01 reports no dead row and no old pending row');
      end if;
      select coalesce(jsonb_agg(x.id order by x.id) filter (where not x.t and x.n <= 500), '[]'), count(*) filter (where not x.t),
             count(*) filter (where x.t)
        into v_rows, v_n, v_test
        from (select o.id, row_number() over (order by o.id) as n,
                     coalesce(o.payload @> '{"is_test": true}' or o.payload @> '{"test": true}', false) as t
                from public.web_outbox o
               where o.status = 'dead' and o.attempts < o.max_attempts
                 and not exists (select 1 from one.actions b join one.actions a on a.run_key = b.run_key and a.step = 'after' and a.status = 'done'
                                  where b.fix_id = 'FIX-OUTBOX-WEB' and b.step = 'before' and not b.dry_run
                                    and coalesce(b.target -> 'rows', '[]') @> to_jsonb(o.id))) x;
      return jsonb_build_object('applies', v_n > 0 or v_old,
                                'why_not', case when v_n = 0 and not v_old then 'no dead row with attempts left that was not sent again already: a person decides' end,
                                'rows', v_rows, 'count', v_n, 'test_rows', v_test, 'target', jsonb_build_object('oldest_pending_old', v_old),
                                'would', format('send %s dead rows again (public.web_outbox_retry), then run the website''s outbox worker', v_n));
    when 'FIX-CATALOG-POLL' then
      if p_inc.check_id = 'WEB-01' and coalesce((e ->> 'catalog_checked_seconds_ago')::numeric, 0) <= 600 then
        return jsonb_build_object('applies', false, 'why_not', 'the catalogue poll is not older than 600 s');
      end if;
      return jsonb_build_object('applies', true, 'count', 1, 'target', jsonb_build_object('check', p_inc.check_id),
                                'would', 'run public.web_catalog_poll()');
    when 'FIX-CACHE-B2C' then
      return jsonb_build_object('applies', true, 'count', 1, 'target', e, 'would', 'run b2c.programme_cache_refresh(true)');
    else
      raise exception 'no fix %', p_fix using errcode = 'P0002';
  end case;
end $$;

create or replace function one.fix_act(p_fix text, p_plan jsonb, p_actor uuid default null) returns jsonb
language plpgsql set search_path = '' as $$
begin
  case p_fix
    when 'FIX-CURSOR-B2C' then return jsonb_build_object('sync', one.fixer_b2c_sync());
    when 'FIX-WEBHOOK-REKICK' then return jsonb_build_object('kick', one.fixer_outbox_kick());
    when 'FIX-INBOX-RETRY' then return jsonb_build_object('applied', one.fixer_inbox_retry());
    when 'FIX-OUTBOX-B2C' then return one.fixer_b2c_outbox();
    when 'FIX-OUTBOX-WEB' then
      return one.fixer_web_outbox(array(select x::bigint from jsonb_array_elements_text(coalesce(p_plan -> 'rows', '[]')) x), p_actor);
    when 'FIX-CATALOG-POLL' then return jsonb_build_object('poll', one.fixer_catalog_poll());
    when 'FIX-CACHE-B2C' then return jsonb_build_object('refreshed', one.fixer_programme_cache());
    else raise exception '% does not act in the database', p_fix using errcode = '22023';
  end case;
end $$;

create or replace function one.settings_check(p_key text, p_value jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare
  v_email text := '^[^@\s]+@[^@\s]+\.[a-z]{2,}$';
  v_bad text;
begin
  if jsonb_typeof(p_value) is distinct from 'object' then
    raise exception 'setting %: the value must be a JSON object', p_key using errcode = '22023';
  end if;
  case p_key
    when 'events' then
      if jsonb_typeof(p_value -> 'pii_columns') is distinct from 'array' or jsonb_array_length(p_value -> 'pii_columns') = 0
         or exists (select 1 from jsonb_array_elements(p_value -> 'pii_columns') e where jsonb_typeof(e) <> 'string') then
        raise exception 'setting events: pii_columns must be a non-empty list of key patterns' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'batch')::int, 5000) not between 100 and 50000
         or coalesce((p_value ->> 'id_overlap')::int, 0) not between 0 and 10000
         or coalesce((p_value ->> 'window_hours')::int, 48) not between 1 and 720 then
        raise exception 'setting events: batch 100–50000, id_overlap 0–10000, window_hours 1–720' using errcode = '22023';
      end if;
    when 'alerts' then
      if jsonb_typeof(p_value #> '{p1,email}') is distinct from 'array' or jsonb_array_length(p_value #> '{p1,email}') = 0 then
        raise exception 'setting alerts: p1.email must be a non-empty list of addresses' using errcode = '22023';
      end if;
      select string_agg(x, ', ') into v_bad
        from (select jsonb_array_elements_text(p_value #> '{p1,email}') x
              union all select jsonb_array_elements_text(coalesce(p_value #> '{escalation,second_contact}', '[]'))
              union all select p_value ->> 'developer_email' where p_value ->> 'developer_email' is not null) a
       where lower(x) !~ v_email;
      if v_bad is not null then
        raise exception 'setting alerts: not an email address: %', left(v_bad, 200) using errcode = '22023';
      end if;
      if coalesce((p_value #>> '{escalation,resend_min}')::numeric, 30) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,second_contact_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value #>> '{escalation,repeat_min}')::numeric, 60) not between 5 and 1440
         or coalesce((p_value ->> 'p2_digest_hour_ist')::numeric, 18) not between 0 and 23
         or coalesce((p_value ->> 'p2_digest_min_count')::numeric, 5) not between 0 and 1000
         or coalesce((p_value #>> '{storm,p1_count}')::numeric, 10) not between 2 and 1000
         or coalesce((p_value #>> '{storm,window_min}')::numeric, 5) not between 1 and 120
         or coalesce((p_value #>> '{storm,suppress_min}')::numeric, 15) not between 1 and 240 then
        raise exception 'setting alerts: an escalation, digest or storm number is out of range' using errcode = '22023';
      end if;
    when 'thresholds' then
      select string_agg(key, ', ') into v_bad from jsonb_each(p_value) where jsonb_typeof(value) <> 'number';
      if v_bad is not null then
        raise exception 'setting thresholds: not a number: %', left(v_bad, 200) using errcode = '22023';
      end if;
    when 'checks' then
      if coalesce(p_value ->> 'lock_timeout', '2s') !~ '^[0-9]{1,5}(ms|s)$'
         or coalesce(p_value ->> 'transaction_timeout', '30s') !~ '^[0-9]{1,5}(s|min)$'
         or (coalesce(p_value ->> 'transaction_timeout', '30s') ~ '^[0-9]+s$' and regexp_replace(coalesce(p_value ->> 'transaction_timeout', '30s'), 's$', '')::int < 5)
         or jsonb_typeof(coalesce(p_value -> 'source_missing_opens_incident', 'true')) <> 'boolean'
         or coalesce((p_value ->> 'slow_ms')::int, 5000) not between 100 and 600000 then
        raise exception 'setting checks: lock_timeout like "2s", transaction_timeout like "30s" (5s or more), a boolean source_missing_opens_incident, slow_ms 100–600000'
          using errcode = '22023';
      end if;
    when 'access' then
      if jsonb_typeof(p_value -> 'owners') is distinct from 'array'
         or exists (select 1 from jsonb_array_elements_text(p_value -> 'owners') x where lower(x) !~ '^[^@\s]+@eduwit\.in$') then
        raise exception 'setting access: owners must be a list of @eduwit.in addresses' using errcode = '22023';
      end if;
      if coalesce((p_value ->> 'trusted_days')::int, 30) not between 0 and 90
         or coalesce((p_value ->> 'idle_hours')::int, 12) not between 1 and 72
         or coalesce((p_value ->> 'code_minutes')::int, 10) not between 2 and 30 then
        raise exception 'setting access: trusted_days 0–90, idle_hours 1–72, code_minutes 2–30' using errcode = '22023';
      end if;
    when 'app' then
      if p_value ->> 'base_url' is not null and p_value ->> 'base_url' !~ '^https://[a-z0-9.-]+(:[0-9]+)?$' then
        raise exception 'setting app: base_url must be https://host with no path' using errcode = '22023';
      end if;
    -- The shapes the pages cast or parse (phase review m12): a bad edit must be refused here, not break a page.
    when 'analytics' then
      if jsonb_typeof(p_value -> 'funnel') is distinct from 'array' or jsonb_array_length(p_value -> 'funnel') not between 1 and 20
         or exists (select 1 from jsonb_array_elements(p_value -> 'funnel') s
                     where jsonb_typeof(s) <> 'object' or coalesce(s ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,30}$'
                        or jsonb_typeof(s -> 'label') is distinct from 'string' or length(s ->> 'label') not between 1 and 80
                        or jsonb_typeof(s -> 'match') is distinct from 'array' or jsonb_array_length(s -> 'match') = 0
                        or exists (select 1 from jsonb_array_elements(s -> 'match') m
                                    where jsonb_typeof(m) <> 'object' or jsonb_typeof(m -> 'type') is distinct from 'string'
                                       or (m ? 'app' and jsonb_typeof(m -> 'app') is distinct from 'string')))
         or (select count(distinct s ->> 'key') from jsonb_array_elements(p_value -> 'funnel') s) <> jsonb_array_length(p_value -> 'funnel') then
        raise exception 'setting analytics: funnel is 1 to 20 steps, each {key (a-z_), label, match: [{type, app?}]}, keys unique' using errcode = '22023';
      end if;
    when 'ai' then
      if exists (select 1 from unnest(array['daily_cap_inr', 'per_task_cap_inr', 'queue_non_triage_at_pct', 'usd_inr']) k
                  where p_value ? k and (jsonb_typeof(p_value -> k) <> 'number' or (p_value ->> k)::numeric < 0)) then
        raise exception 'setting ai: daily_cap_inr, per_task_cap_inr, queue_non_triage_at_pct and usd_inr are numbers, 0 or more' using errcode = '22023';
      end if;
      -- The worker reads these on every task (phase 6, D-075): a bad edit is refused here, not found by a failing task.
      -- Claude only (owner, 24 Oct; D-004): there is no provider to choose.
      if p_value ? 'provider'
         or (p_value ? 'effort' and (jsonb_typeof(p_value -> 'effort') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'effort') e where e.key not in ('quick', 'regular', 'deep')
                                                                         or e.value not in ('null', '"low"', '"medium"', '"high"', '"xhigh"', '"max"'))))
         or (p_value ? 'prices' and (jsonb_typeof(p_value -> 'prices') <> 'object'
            or exists (select 1 from jsonb_each(p_value -> 'prices') e
                        where jsonb_typeof(e.value) not in ('null', 'object')
                           or (jsonb_typeof(e.value) = 'object'
                               and (not (e.value ? 'input' and e.value ? 'output')
                                    or exists (select 1 from jsonb_each(e.value) f
                                                where f.key not in ('input', 'output', 'cache_read', 'cache_write')
                                                   or jsonb_typeof(f.value) <> 'number' or (f.value #>> '{}')::numeric < 0))))))
         or (p_value ? 'queue_non_triage_at_pct' and (p_value ->> 'queue_non_triage_at_pct')::numeric > 100)
         or (p_value ? 'allow_message_excerpts' and jsonb_typeof(p_value -> 'allow_message_excerpts') <> 'boolean')
         or coalesce((p_value ->> 'max_parallel')::numeric, 2) not between 1 and 5
         or coalesce((p_value ->> 'task_max_age_h')::numeric, 48) not between 1 and 720
         or coalesce(p_value #>> '{schedule,brief_mail_at_ist}', '08:00') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         or coalesce((p_value #>> '{schedule,propose_feature_weekday}')::numeric, 1) not between 1 and 7
         or coalesce((p_value #>> '{schedule,explain_after_min}')::numeric, 15) not between 1 and 1440
         or coalesce((p_value #>> '{schedule,propose_fix_after_min}')::numeric, 60) not between 1 and 10080
         -- Routing and models are read by the schedule and every claim (phase 6 review m1).
         or (p_value ? 'usd_inr' and (p_value ->> 'usd_inr')::numeric <= 0)
         or (p_value ? 'routing' and (jsonb_typeof(p_value -> 'routing') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'routing') e where e.value not in ('"quick"', '"regular"', '"deep"'))))
         or (p_value ? 'fallback_when_model_missing' and p_value -> 'fallback_when_model_missing' not in ('null', '"quick"', '"regular"', '"deep"'))
         or (p_value ? 'models' and (jsonb_typeof(p_value -> 'models') <> 'object'
             or exists (select 1 from jsonb_each(p_value -> 'models') m
                         where m.key not in ('quick', 'regular', 'deep')
                            or (jsonb_typeof(m.value) <> 'null'
                                and (jsonb_typeof(m.value) <> 'string' or (m.value #>> '{}') !~ '^claude-[a-z0-9.-]{1,80}$')))))
         or (p_value ? 'refusal_fallback' and jsonb_typeof(p_value -> 'refusal_fallback') <> 'null'
             and (jsonb_typeof(p_value -> 'refusal_fallback') <> 'string' or (p_value ->> 'refusal_fallback') !~ '^claude-[a-z0-9.-]{1,80}$')) then
        raise exception 'setting ai: Claude only, so no provider; effort per tier null, low, medium, high, xhigh or max; prices per model null or {input, output, cache_read?, cache_write?} in USD per million tokens, 0 or more; queue_non_triage_at_pct at most 100; allow_message_excerpts a boolean; max_parallel 1–5; task_max_age_h 1–720; schedule: brief_mail_at_ist HH:MM, propose_feature_weekday 1–7, explain_after_min 1–1440, propose_fix_after_min 1–10080; usd_inr above 0; routing values quick, regular or deep; fallback_when_model_missing null or a tier; models {tier: a claude-… model or null}; refusal_fallback null or a claude-… model'
          using errcode = '22023';
      end if;
    when 'fixes' then
      if (p_value ? 'observation_days' and (jsonb_typeof(p_value -> 'observation_days') <> 'number' or (p_value ->> 'observation_days')::numeric not between 14 and 90))
         or (jsonb_typeof(p_value -> 'observation_started_at') not in ('null') and coalesce(p_value ->> 'observation_started_at', '')
             !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)?)?$') then
        raise exception 'setting fixes: observation_days 14–90 (spec §8: two weeks at least), observation_started_at null or an ISO time' using errcode = '22023';
      end if;
      -- The window's start is set once, by the first tick that runs the fixes; nobody moves it afterwards (phase 7 review m8).
      if (select s.value ->> 'observation_started_at' from one.settings s where s.key = 'fixes') is not null
         and ((p_value ->> 'observation_started_at') is null
              or (p_value ->> 'observation_started_at')::timestamptz <> (select (s.value ->> 'observation_started_at')::timestamptz from one.settings s where s.key = 'fixes')) then
        raise exception 'setting fixes: the observation window started at its first tick and its start cannot change' using errcode = '22023';
      end if;
      -- Each fix: {enabled, per_tick 1–500, cooldown_min 1–1440}. A fix is switched on only on evidence (spec §8):
      -- after the observation window, and once it has at least one dry run.
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key not in ('observation_days', 'observation_started_at')
                    and (f.key !~ '^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$' or jsonb_typeof(f.value) <> 'object'
                         or exists (select 1 from jsonb_object_keys(f.value) k where k not in ('enabled', 'per_tick', 'cooldown_min'))
                         or jsonb_typeof(f.value -> 'enabled') is distinct from 'boolean'
                         or jsonb_typeof(f.value -> 'per_tick') is distinct from 'number' or (f.value ->> 'per_tick')::numeric not between 1 and 500
                         or (f.value ->> 'per_tick')::numeric <> trunc((f.value ->> 'per_tick')::numeric)
                         or jsonb_typeof(f.value -> 'cooldown_min') is distinct from 'number' or (f.value ->> 'cooldown_min')::numeric not between 1 and 1440
                         or (f.value ->> 'cooldown_min')::numeric <> trunc((f.value ->> 'cooldown_min')::numeric))) then
        raise exception 'setting fixes: each FIX-… is {enabled: boolean, per_tick: 1–500, cooldown_min: 1–1440}' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean)
         and (p_value ->> 'observation_started_at' is null
              or (p_value ->> 'observation_started_at')::timestamptz + make_interval(days => coalesce((p_value ->> 'observation_days')::int, 14)) > now()) then
        raise exception 'setting fixes: a fix is switched on only after the observation window ends' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(p_value) f
                  where f.key ~ '^FIX-' and (f.value ->> 'enabled')::boolean
                    and not exists (select 1 from one.actions a where a.fix_id = f.key and a.dry_run)) then
        raise exception 'setting fixes: a fix is switched on only once it has a dry run to judge it by' using errcode = '22023';
      end if;
    -- The keys the app parses each minute and the engineer-editable ones have a shape too (hardening F6, m2): a typo
    -- is refused here instead of making every tick route fail.
    when 'tests' then
      if coalesce((p_value ->> 'purge_after_days')::int, 2) not between 1 and 30
         or jsonb_typeof(coalesce(p_value -> 'schedules', '{}')) <> 'object'
         or exists (select 1 from jsonb_each_text(coalesce(p_value -> 'schedules', '{}')) sc where sc.value !~ '^(\S+\s+){4}\S+$') then
        raise exception 'setting tests: purge_after_days 1–30, schedules {T-…: a 5-field cron expression}' using errcode = '22023';
      end if;
    when 'witty' then
      if exists (select 1 from jsonb_each(p_value) w where w.key in ('expect_nurture', 'expect_learning') and jsonb_typeof(w.value) <> 'boolean') then
        raise exception 'setting witty: expect_nurture and expect_learning are booleans' using errcode = '22023';
      end if;
    when 'hosts' then
      if exists (select 1 from unnest(array['website', 'spark', 'b2b_app', 'influencer', 'chatwoot', 'n8n', 'one']) h where coalesce(p_value ->> h, '') !~ '^https://[a-z0-9.-]+$')
         or exists (select 1 from jsonb_each(p_value) h where jsonb_typeof(h.value) <> 'string' or (h.value #>> '{}') !~ '^https://[a-z0-9.-]+$') then
        raise exception 'setting hosts: website, spark, b2b_app, influencer, chatwoot, n8n and one are https://host values with no path' using errcode = '22023';
      end if;
    when 'vendors' then
      if exists (select 1 from jsonb_each(p_value) v where jsonb_typeof(v.value) <> 'string' or (v.value #>> '{}') !~ '^https://[a-z0-9.-]+(/[A-Za-z0-9._/-]*)?$') then
        raise exception 'setting vendors: every value is an https URL' using errcode = '22023';
      end if;
    when 'vercel' then
      if jsonb_typeof(p_value -> 'team') <> 'string' or jsonb_typeof(coalesce(p_value -> 'projects', '{}')) <> 'object'
         or exists (select 1 from jsonb_each(coalesce(p_value -> 'projects', '{}')) pr where jsonb_typeof(pr.value) <> 'string') then
        raise exception 'setting vercel: team a string, projects {app: project name}' using errcode = '22023';
      end if;
    when 'chatwoot' then
      if coalesce(p_value ->> 'account_id', '') !~ '^[0-9]{1,10}$' then
        raise exception 'setting chatwoot: account_id is a number' using errcode = '22023';
      end if;
    when 'n8n' then
      if exists (select 1 from jsonb_each(p_value) n where n.key like '%workflow_id' and (jsonb_typeof(n.value) <> 'string' or (n.value #>> '{}') !~ '^[A-Za-z0-9_-]{1,64}$')) then
        raise exception 'setting n8n: each *_workflow_id is an n8n workflow id' using errcode = '22023';
      end if;
    when 'whatsapp' then
      if jsonb_typeof(coalesce(p_value -> 'waba_ids', '[]')) <> 'array'
         or exists (select 1 from jsonb_array_elements(coalesce(p_value -> 'waba_ids', '[]')) w where jsonb_typeof(w) <> 'string') then
        raise exception 'setting whatsapp: waba_ids is a list of ids' using errcode = '22023';
      end if;
    when 'health_paths' then
      if exists (select 1 from jsonb_each(p_value) h where jsonb_typeof(h.value) <> 'string' or (h.value #>> '{}') !~ '^/') then
        raise exception 'setting health_paths: every value is a path starting with /' using errcode = '22023';
      end if;
    when 'retention' then
      if exists (select 1 from jsonb_each(p_value) r where r.key like '%_days' and (jsonb_typeof(r.value) <> 'number' or (r.value #>> '{}')::numeric not between 1 and 3650))
         or coalesce((p_value ->> 'results_days')::int, 90) < 7 or coalesce((p_value ->> 'events_days')::int, 180) < 7
         or coalesce((p_value ->> 'ai_calls_days')::int, 365) < 7 then
        raise exception 'setting retention: *_days are numbers up to 3650; results, events and ai_calls at least 7, ok_results_days at least 1' using errcode = '22023';
      end if;
    else
      null;
  end case;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'setting %: a number field holds something else', p_key using errcode = '22023';
end $$;

create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_version integer;
  v_value jsonb := p_value;
begin
  select value into v_before from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  -- The observation window's start is the first tick's to write, never a page's (security review m1): the stored
  -- value is kept whatever the form sends, so the window cannot be backdated before it starts.
  if p_key = 'fixes' then
    v_value := v_value || jsonb_build_object('observation_started_at', v_before -> 'observation_started_at');
  end if;
  if v_value = v_before then
    raise exception 'nothing changed: the value is the current version' using errcode = '22023';
  end if;
  v_version := one.settings_put(p_key, v_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, v_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;

-- Restores an earlier version of a setting as a new version (D-065 promised it; review F14): the same checks and
-- rights as any write, the reason naming the version restored.
create or replace function one.ui_settings_restore(p_key text, p_version integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_value jsonb;
begin
  -- The gate first, as every UI function (80_ui_api §10); the key's own rule (owner or engineer) applies in ui_settings_put.
  perform one.ui_require('read');
  select v.value into v_value from one.settings_versions v where v.key = p_key and v.version = p_version;
  if v_value is null then
    raise exception 'no version % of setting %', p_version, p_key using errcode = 'P0002';
  end if;
  return one.ui_settings_put(p_key, v_value, format('restore version %s: %s', p_version, p_reason), p_request_id);
end $$;

create or replace function one.ui_view_save(p_page text, p_name text, p_params jsonb, p_schedule text default null,
                                            p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  -- A saved view's days must be a whole number of days: a bad one would make every brief email unreadable (security m3).
  if p_params ? 'days' and (jsonb_typeof(p_params -> 'days') <> 'number' or (p_params ->> 'days')::numeric not between 1 and 365
                            or (p_params ->> 'days')::numeric <> trunc((p_params ->> 'days')::numeric)) then
    raise exception 'a view''s days is a whole number from 1 to 365' using errcode = '22023';
  end if;
  insert into one.saved_views (page, name, params, schedule, created_by) values (p_page, trim(p_name), coalesce(p_params, '{}'), p_schedule, v_actor)
  on conflict (page, name) do update set params = excluded.params, schedule = excluded.schedule
  returning id into v_id;
  perform one.ui_audit_write(v_actor, 'view.save', 'view:' || v_id, null, jsonb_build_object('page', p_page, 'name', p_name, 'schedule', p_schedule), p_request_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- The request id travels with the mute so its audit row is written once (append-only histories, D-085).
drop function if exists one.mute(text, text, integer, text, text);
create or replace function one.mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_by text, p_request_id text default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  if p_target_type = 'check' and not exists (select 1 from one.checks where id = p_target)
     or p_target_type = 'app' and not exists (select 1 from one.apps where key = p_target) then
    raise exception 'one.mute: unknown % %', p_target_type, p_target using errcode = '22023';
  end if;
  if coalesce(p_minutes, 0) not between 1 and 10080 or nullif(trim(p_reason), '') is null then
    raise exception 'one.mute: a duration of 1 minute to 7 days and a reason are required' using errcode = '22023';
  end if;
  insert into one.mutes (target_type, target, ends_at, reason, created_by)
  values (p_target_type, p_target, now() + make_interval(mins => p_minutes), left(p_reason, 300), left(p_by, 120))
  returning id into v_id;
  update one.incidents set alert_state = 'muted'
   where resolved_at is null and alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2', 'digest')
     and ((p_target_type = 'check' and check_id = p_target) or (p_target_type = 'app' and app = p_target));
  insert into one.audit (actor, action, target, after, request_id) values (left(p_by, 120), 'mute', p_target_type || ':' || p_target,
    jsonb_build_object('mute_id', v_id, 'minutes', p_minutes, 'reason', left(p_reason, 300)), left(p_request_id, 80));
  return v_id;
end $$;

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor, p_request_id);
begin
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

-- Redaction compiled (efficiency review 8, D-088). The PII key list becomes one anchored pattern per call ("*" a
-- wildcard, everything else literal), tested once per key instead of a like per key per node, and one.has_contact runs
-- only on text that holds a digit or an @ (nothing else can be a phone or an email). one.redact(jsonb, text[]) keeps
-- its signature as a thin wrapper, so every caller and test is unchanged.
create or replace function one.redact_pattern(p_keys text[]) returns text
language sql immutable set search_path = '' as $$
  select case when p_keys is null or cardinality(p_keys) = 0 then null
              else '^(' || (select string_agg(replace(regexp_replace(lower(k), '([.+?^$(){}|\[\]\\])', '\\\1', 'g'), '*', '.*'), '|')
                              from unnest(p_keys) k) || ')$' end
$$;

select one.settings_put('fixes', s.value - 'FIX-SENDQ-B2C', s.actor, 'rollback of 0037') from one.settings s where s.key = 'fixes' and s.value ? 'FIX-SENDQ-B2C';
select one.settings_put('health_paths', one.setting('health_paths') || '{"spark": "/"}', 'seed', 'rollback of 0037')
 where one.setting('health_paths') ->> 'spark' = '/api/health';

drop function if exists one.fixer_b2c_sendq();
do $$
begin
  if to_regprocedure('b2c.send_unstick(integer)') is not null then
    revoke execute on function b2c.send_unstick(integer) from eduwit_one_fixer;
  end if;
end $$;
delete from one.fix_state where fix_id = 'FIX-SENDQ-B2C';
delete from one.fixes where id = 'FIX-SENDQ-B2C';

call one.apply_grants();
