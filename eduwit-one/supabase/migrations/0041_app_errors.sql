-- 0041 the audit of 13 Nov 2026, finding M11 (D-141): the apps tell Eduwit One how many server errors they throw.
-- Only schema one changes.
--   Every app logs a server error as one line in its host's logs (Eduwit One: app.error, D-137), and nobody is told
--   when an app starts throwing. The owner declined a third-party error tracker. Each app now also counts its errors
--   and reports the counts here, and a plain SQL check per app raises an incident when there are too many.
--   1. one.app_errors: one row per app, 5-minute bucket, route template and error name, with a count, when it was
--      first and last seen, and one sample: the render kind, a masked message of at most 200 characters and Next's
--      digest. No personal data: no user, address, query string, header, cookie, body or stack.
--   2. one.app_error_report(p_app, p_items): the one writer, for the service role only (each app calls it with the
--      service key it already holds; one.api_grants). p_items is a JSON array of at most 50 objects
--      {route, name, n, message, digest, kind}. The database decides the bucket (its own clock), refuses an app that
--      is not in one.apps, masks every text as stored text is masked (one.mask_text) and replaces what still reads as
--      an email or a phone (one.has_contact, as one.redact does), cuts every field, and caps a count at 10 000. A
--      buggy app cannot fill the table: past 300 rows in an hour for one app, only that bucket's "(overflow)" row
--      grows, so the count stays true and only the detail is lost. No audit row per call: the rows are the record,
--      and no person acts.
--   3. one.retention(): the counts are kept app_errors_days (30; a key of the retention setting, read with that
--      default when the setting lacks it), pruned by the nightly job with the rest.
--   4. A check per app that reports, P2, every 5 minutes: B2B-ERR, B2C-ERR, INF-ERR, ONE-ERR and WEB-ERR (off until
--      the website carries the reporter), as 0006 now seeds them. Each fails when the errors of the buckets that
--      started in the last 15 minutes exceed thresholds.app_errors_15m (20) and resolves by itself after two readings
--      at or under it. The threshold is seeded while the thresholds row is still the seed's; changing it is the
--      owner's (0039, D-137). No model decides anything here.
--   5. one.ui_app_errors(p_app, p_hours): what an app's page shows (the last 24 hours, the five busiest route and
--      error pairs), for a signed-in person of Eduwit One (one.ui_require('read')).
-- Rollback: 0041_app_errors.rollback.sql.

-- 1. The counts -------------------------------------------------------------------------------------------------------
create table one.app_errors (
  app text not null references one.apps (key),
  bucket timestamptz not null,
  route text not null check (length(route) between 1 and 200),
  error_name text not null check (length(error_name) between 1 and 60),
  n bigint not null check (n > 0),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  sample_kind text check (length(sample_kind) <= 20),
  sample_message text check (length(sample_message) <= 200),
  sample_digest text check (length(sample_digest) <= 64),
  primary key (app, bucket, route, error_name)
);

-- 2. The writer -------------------------------------------------------------------------------------------------------
-- A text an app sent, as it may be stored: one line, masked as stored text is (one.mask_text keeps the sentence and
-- replaces the contact), cut to p_max, and replaced whole when the contact check still finds an email or a phone in
-- it (as one.redact does with a string). Null for nothing.
create or replace function one.app_error_text(p_text text, p_max integer) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v text := left(btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g')), 1000);
  v_contact text;
begin
  if v = '' then
    return null;
  end if;
  v := left(one.mask_text(v), p_max);
  v_contact := one.has_contact(v);
  if v_contact is not null then
    return '[' || v_contact || ']';
  end if;
  return v;
end $$;

create or replace function one.app_error_report(p_app text, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c_max_items constant integer := 50;
  c_max_count constant integer := 10000;
  c_max_rows_hour constant integer := 300;
  c_overflow constant text := '(overflow)';
  v_bucket timestamptz := date_bin(interval '5 minutes', now(), timestamptz '2000-01-01 00:00:00+00');
  v_item jsonb;
  v_text text;
  v_route text;
  v_name text;
  v_kind text;
  v_message text;
  v_digest text;
  v_n bigint;
  v_rows integer;
  v_items integer := 0;
  v_total bigint := 0;
  v_overflow bigint := 0;
begin
  if p_app is null or not exists (select 1 from one.apps a where a.key = p_app) then
    raise exception 'one.app_error_report: unknown app' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > c_max_items then
    raise exception 'one.app_error_report: the items are a JSON array of at most % objects', c_max_items using errcode = '22023';
  end if;
  -- One report of an app at a time: the hourly cap is counted once and holds, and two reports never wait on each
  -- other's rows.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('one.app_errors:' || p_app));
  select count(*) into v_rows from one.app_errors e where e.app = p_app and e.bucket > now() - interval '1 hour';
  for v_item in select i.value from jsonb_array_elements(p_items) i loop
    if jsonb_typeof(v_item) is distinct from 'object' then
      continue;
    end if;
    v_items := v_items + 1;
    -- The route as its file names it; anything after ? or # is never kept.
    v_route := coalesce(one.app_error_text(split_part(split_part(coalesce(v_item ->> 'route', ''), '?', 1), '#', 1), 200), '(unknown)');
    v_text := v_item ->> 'name';
    v_name := case when v_text ~ '^[A-Za-z_$][A-Za-z0-9_$]{0,59}$' and one.has_contact(v_text) is null then v_text else 'Error' end;
    -- What an app's own buffer could not hold apart arrives as one "(overflow)" pair and joins the bucket's overflow row.
    if v_route = c_overflow then
      v_name := c_overflow;
    end if;
    v_text := v_item ->> 'kind';
    v_kind := case when v_text ~ '^[a-z][a-z_-]{0,19}$' then v_text end;
    v_text := v_item ->> 'digest';
    v_digest := case when v_text ~ '^[A-Za-z0-9_.:;-]{1,64}$' and one.has_contact(v_text) is null then v_text end;
    v_message := one.app_error_text(v_item ->> 'message', 200);
    v_n := case when jsonb_typeof(v_item -> 'n') = 'number'
                then least(greatest(floor((v_item ->> 'n')::numeric), 1), c_max_count)::bigint else 1 end;
    update one.app_errors e
       set n = e.n + v_n, last_seen = now(), sample_kind = coalesce(e.sample_kind, v_kind),
           sample_message = coalesce(e.sample_message, v_message), sample_digest = coalesce(e.sample_digest, v_digest)
     where e.app = p_app and e.bucket = v_bucket and e.route = v_route and e.error_name = v_name;
    if found then
      v_total := v_total + v_n;
    elsif v_rows >= c_max_rows_hour then
      v_overflow := v_overflow + v_n;
    else
      insert into one.app_errors (app, bucket, route, error_name, n, sample_kind, sample_message, sample_digest)
      values (p_app, v_bucket, v_route, v_name, v_n, v_kind, v_message, v_digest);
      v_rows := v_rows + 1;
      v_total := v_total + v_n;
    end if;
  end loop;
  if v_overflow > 0 then
    insert into one.app_errors as e (app, bucket, route, error_name, n)
    values (p_app, v_bucket, c_overflow, c_overflow, v_overflow)
    on conflict (app, bucket, route, error_name) do update set n = e.n + excluded.n, last_seen = now();
  end if;
  return jsonb_build_object('ok', true, 'items', v_items, 'errors', v_total + v_overflow, 'overflow', v_overflow);
end $$;

-- 3. Retention --------------------------------------------------------------------------------------------------------
-- 0029's function with one more step: the apps' error counts older than app_errors_days (30).
create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
  v_chat integer;
  v_app_errors integer;
begin
  -- The histories are append-only (D-085); this is the one step that may prune them.
  perform set_config('one.history_writer', 'on', true);
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (2 since 0029; 14 before); failures
  -- and errors stay results_days (14 since 0029; 90 before) for the incident pages and the comparisons (efficiency
  -- review 10; D-103: the Free plan's 500 MB database limit).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 2)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 14));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept app_report_days (7; 30 before 0029); a person's
  -- audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'app_report_days')::int, 7)));
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 30));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  -- The tick and nightly reports are kept runs_days (7; 30 before 0029): the checks read 26 hours of them at most.
  delete from one.runs where started_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'runs_days')::int, 7)));
  -- Conversations with the command centre (0021) and their actions go with their thread.
  delete from one.chat_threads where updated_at < now() - make_interval(days => coalesce((v_cfg ->> 'chat_days')::int, 90));
  get diagnostics v_chat = row_count;
  -- The apps' server-error counts (0041, D-141) are kept app_errors_days (30). They are counters, not a history.
  delete from one.app_errors where bucket < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'app_errors_days')::int, 30)));
  get diagnostics v_app_errors = row_count;
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit, 'chat_threads', v_chat,
                            'app_errors', v_app_errors);
end $$;

-- 4. The threshold and the checks -------------------------------------------------------------------------------------
-- As 0029 did for PLAT-10: a seed version while the row is still the seed's. Otherwise it is left as it is and the
-- checks read their default (20) until the owner adds app_errors_15m on Settings.
do $$
declare
  v_row one.settings;
begin
  select * into v_row from one.settings where key = 'thresholds';
  if not found then
    raise exception '0041: no thresholds setting; 0007 must be applied first';
  end if;
  if v_row.value ? 'app_errors_15m' then
    null;
  elsif v_row.actor <> 'seed' then
    raise notice '0041: the thresholds setting was changed by % (version %), so it is left as it is; the server-error checks use their default (20 in 15 minutes) until app_errors_15m is set', v_row.actor, v_row.version;
  else
    perform one.settings_put('thresholds', '{"app_errors_15m": 20}' || v_row.value,
                             'seed', 'D-141 (0041): server errors an app may report in 15 minutes before its check fails');
  end if;
end $$;

-- The five checks, as 0006 now seeds them.
select one.seed_check(jsonb_build_object(
  'id', 'B2B-ERR',
  'app', 'b2b',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'The B2B CRM is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key).',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'b2b' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
$sql$));

select one.seed_check(jsonb_build_object(
  'id', 'B2C-ERR',
  'app', 'b2c',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'Spark is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key).',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'b2c' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
$sql$));

select one.seed_check(jsonb_build_object(
  'id', 'INF-ERR',
  'app', 'influencer',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'The influencer portal is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key).',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'influencer' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
$sql$));

select one.seed_check(jsonb_build_object(
  'id', 'ONE-ERR',
  'app', 'one',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'Eduwit One''s own app is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key).',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'one' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
$sql$));

select one.seed_check(jsonb_build_object(
  'id', 'WEB-ERR',
  'app', 'web',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'The website is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key). Off until the website carries the reporter (it lives in another repository branch): until then the website reports nothing, and a check that reads nothing must not read as passing.',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', false,
  'disabled_reason', 'blocked:web_error_reporter_not_ported',
  'search_path', '',
  'sql', $sql$
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'web' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
$sql$));

-- 5. What an app's page shows -----------------------------------------------------------------------------------------
create or replace function one.ui_app_errors(p_app text, p_hours integer default 24) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_hours integer := least(greatest(coalesce(p_hours, 24), 1), 168);
  v_from timestamptz := now() - make_interval(hours => v_hours);
begin
  if p_app is null or not exists (select 1 from one.apps a where a.key = p_app) then
    raise exception 'unknown app' using errcode = 'P0002';
  end if;
  return (
    with e as (
      select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen,
             (array_agg(x.sample_message order by x.last_seen desc) filter (where x.sample_message is not null))[1] as message,
             (array_agg(x.sample_digest order by x.last_seen desc) filter (where x.sample_digest is not null))[1] as digest,
             (array_agg(x.sample_kind order by x.last_seen desc) filter (where x.sample_kind is not null))[1] as kind
        from one.app_errors x
       where x.app = p_app and x.bucket > v_from
       group by x.route, x.error_name)
    select jsonb_build_object(
      'app', p_app, 'hours', v_hours,
      'total', (select coalesce(sum(e.n), 0) from e),
      'pairs', (select count(*) from e),
      'last_seen', (select max(e.last_seen) from e),
      'last_15m', (select coalesce(sum(x.n), 0) from one.app_errors x where x.app = p_app and x.bucket > now() - interval '15 minutes'),
      'limit_15m', coalesce(one.threshold('app_errors_15m'), 20),
      'top', (select coalesce(jsonb_agg(jsonb_build_object('route', t.route, 'error', t.error_name, 'n', t.n, 'last_seen', t.last_seen,
                                                           'message', t.message, 'digest', t.digest, 'kind', t.kind)
                                        order by t.n desc, t.route, t.error_name), '[]')
                from (select * from e order by e.n desc, e.route, e.error_name limit 5) t)));
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.app_error_report(text,jsonb)', 'service_role', 'each app reports its server-error counts (0041, D-141)'),
  ('one.ui_app_errors(text,integer)', 'authenticated', 'page read (0041): an app''s server errors, as the signed-in person')
on conflict do nothing;

call one.apply_grants();
