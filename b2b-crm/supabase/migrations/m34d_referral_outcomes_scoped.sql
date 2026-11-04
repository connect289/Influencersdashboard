-- M34d (31 Oct 2026, audit B2B-R1): the referral API answers only for the calling key's own codes, with opaque
-- references and cursors.
--   b2b.api_keys.referral_codes   NEW: the referral codes a key may read (upper case), or prefixes such as INF* (at least
--                                 3 characters before the *). Set when the key is created or later (System health → API
--                                 keys); a referrals key without codes reads nothing. api_key_create and api_key_update
--                                 accept referral_codes; system_overview lists them.
--   b2b.api_referral_outcomes_v2  NEW, GET /v1/referrals/{code}/outcomes: a code the key is not linked to answers like an
--                                 unknown code (an empty list); lead_ref is a keyed hash (HMAC, Vault secret
--                                 b2b_referral_ref_key) and cursor / next_after are encrypted tokens ("c1.…"), never the
--                                 lead id. Everything else answers as before.
--   b2b.api_referral_outcomes     kept for a web deploy older than this file: the first page goes through v2; a numeric
--                                 cursor is refused. pending/drop_api_referral_outcomes_v1.sql drops it once the web app
--                                 calls v2.
-- Re-appliable. Checked by supabase/tests/test_m33d_referrals.sql.

alter table b2b.api_keys add column if not exists referral_codes text[] not null default '{}';
comment on column b2b.api_keys.referral_codes is
  'M34d: the referral codes (upper case) or prefixes ending in * (3+ characters before it) this key may read through the referral API';

do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'b2b_referral_ref_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'b2b_referral_ref_key',
                                'B2B CRM: key for the referral API''s lead references and cursors (m34d)');
  end if;
end $v$;

/* The referral API's key (Vault). Internal. */
create or replace function b2b.referral_secret()
returns text language sql stable security definer set search_path = '' as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'b2b_referral_ref_key';
$fn$;

/* A lead's reference in the referral API: 12 hex characters of an HMAC under the Vault key (not reversible). Internal. */
create or replace function b2b.referral_ref(p_lead bigint)
returns text language sql stable security definer set search_path = '' as $fn$
  select left(encode(extensions.hmac('lead:' || p_lead::text, b2b.referral_secret(), 'sha256'), 'hex'), 12);
$fn$;

/* A paging cursor for a lead: the id encrypted under a key derived from the Vault key, as "c1." + base64url. Internal. */
create or replace function b2b.referral_cursor(p_lead bigint)
returns text language sql stable security definer set search_path = '' as $fn$
  select 'c1.' || rtrim(translate(encode(extensions.encrypt(convert_to(p_lead::text, 'UTF8'),
                                                            extensions.hmac('cursor', b2b.referral_secret(), 'sha256'), 'aes'), 'base64'),
                                  '+/', '-_'), '=');
$fn$;

/* The lead id inside a cursor, or null for anything that is not one of ours. Internal. */
create or replace function b2b.referral_cursor_id(p_cursor text)
returns bigint language plpgsql stable security definer set search_path = '' as $fn$
declare b text; v text;
begin
  if p_cursor is null or p_cursor !~ '^c1\.[A-Za-z0-9_-]{16,64}$' then return null; end if;
  b := translate(substr(p_cursor, 4), '-_', '+/');
  b := b || repeat('=', (4 - length(b) % 4) % 4);
  v := convert_from(extensions.decrypt(decode(b, 'base64'), extensions.hmac('cursor', b2b.referral_secret(), 'sha256'), 'aes'), 'UTF8');
  if v !~ '^[0-9]{1,18}$' then return null; end if;
  return v::bigint;
exception when others then
  return null;
end $fn$;

/* Whether a key's codes cover a code: the code itself, or a prefix entry (ABC*). Pure. */
create or replace function b2b.referral_code_allowed(p_codes text[], p_code text)
returns boolean language sql immutable set search_path = '' as $fn$
  select coalesce(p_code, '') <> '' and exists (
    select 1 from unnest(coalesce(p_codes, '{}'::text[])) c
     where c = p_code or (right(c, 1) = '*' and length(c) >= 4 and left(p_code, length(c) - 1) = left(c, length(c) - 1)));
$fn$;

/* referral_codes from an Admin payload: a JSON array of codes or prefixes, trimmed, upper-cased, de-duplicated. */
create or replace function b2b.referral_codes_parse(p jsonb)
returns text[] language plpgsql immutable set search_path = '' as $fn$
declare v text[]; bad text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'; end if;
  if jsonb_typeof(p) <> 'array' or exists (select 1 from jsonb_array_elements(p) x where jsonb_typeof(x) <> 'string') then
    raise exception 'referral codes are a list of codes' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct c order by c), '{}') into v
    from (select upper(trim(x)) c from jsonb_array_elements_text(p) x) y where c <> '';
  select c into bad from unnest(v) c where c !~ '^[A-Z0-9_-]{1,60}$' and c !~ '^[A-Z0-9_-]{3,59}\*$' limit 1;
  if bad is not null then
    raise exception 'referral code %: letters, digits, _ and -, at most 60 (a prefix ends in * after 3 or more characters)', left(bad, 70) using errcode = '22023';
  end if;
  if cardinality(v) > 200 then raise exception 'at most 200 referral codes per key' using errcode = '22023'; end if;
  return v;
end $fn$;

create or replace function b2b.api_referral_outcomes_v2(p_key text, p_code text, p_after text default null, p_limit integer default 100)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.api_key_check(p_key, 'referrals');
  v_code text := upper(trim(coalesce(p_code, '')));
  v_after bigint;
  v_rows jsonb;
  v_last bigint;
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_code = '' or length(v_code) > 60 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'give a referral code'); end if;
  if nullif(p_after, '') is not null then
    v_after := b2b.referral_cursor_id(p_after);
    if v_after is null then return jsonb_build_object('ok', false, 'status', 400, 'error', 'after must be the next_after of the previous page'); end if;
  end if;
  -- only the codes this key is linked to; any other code answers like an unknown one
  if not b2b.referral_code_allowed((select a.referral_codes from b2b.api_keys a where a.id = (k ->> 'api_key_id')::bigint), v_code) then
    return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('referral_code', v_code, 'outcomes', '[]'::jsonb,
                              'next_after', nullif(p_after, '')));
  end if;
  with page as (
    select l.id, l.created_at, l.stage, l.enrollment_status, l.interested_course, l.enrolled_program, l.updated_at, l.stage_changed_at, l.destination_type
      from public.student_leads l
     where upper(l.referral_code) = v_code and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null
       and (v_after is null or l.id > v_after)
     order by l.id limit least(greatest(coalesce(p_limit, 100), 1), 500))
  select coalesce(jsonb_agg(jsonb_build_object(
           'lead_ref', b2b.referral_ref(x.id),
           'enquired_on', x.created_at::date,
           'stage', coalesce(case when x.destination_type = 'in_house' then b2b.b2c_status_of(x.id) ->> 'stage' end, x.stage, 'new'),
           'enrolled', x.stage = 'enrolled' or coalesce(x.enrollment_status in ('verified', 'reported'), false) or exists (select 1 from public.enrollments e where e.lead_id = x.id and e.status in ('reported', 'verified')),
           'programme', x.interested_course, 'enrolled_program', x.enrolled_program,
           'updated_on', greatest(coalesce(x.updated_at, x.created_at), coalesce(x.stage_changed_at, x.created_at))::date,
           'cursor', b2b.referral_cursor(x.id)) order by x.id), '[]'), max(x.id)
    into v_rows, v_last from page x;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('referral_code', v_code, 'outcomes', v_rows,
                            'next_after', coalesce(b2b.referral_cursor(v_last), nullif(p_after, ''))));
end $fn$;

/* The first referral API: kept for a web deploy older than m34d. The first page answers through v2; lead ids are no
   longer cursors. Dropped by pending/drop_api_referral_outcomes_v1.sql once the web app calls v2. */
create or replace function b2b.api_referral_outcomes(p_key text, p_code text, p_after bigint default null, p_limit integer default 100)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if p_after is not null then
    if not (b2b.api_key_check(p_key, 'referrals') ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'after must be the next_after of the previous page');
  end if;
  return b2b.api_referral_outcomes_v2(p_key, p_code, null, p_limit);
end $fn$;

CREATE OR REPLACE FUNCTION b2b.api_key_create(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := 'eb2b_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_id bigint;
  v_scopes text[];
  v_exp timestamptz := b2b.try_timestamptz(p ->> 'expires_at');
  v_rate int := case when (p ->> 'rate_per_minute') ~ '^[0-9]{1,6}$' then (p ->> 'rate_per_minute')::int end;
  v_codes text[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'give the key a name' using errcode = '22023'; end if;
  select array_agg(x) into v_scopes from jsonb_array_elements_text(case when jsonb_typeof(p -> 'scopes') = 'array' then p -> 'scopes' else '[]'::jsonb end) x;
  if v_scopes is null or cardinality(v_scopes) = 0 then raise exception 'choose at least one scope' using errcode = '22023'; end if;
  if p ? 'expires_at' and nullif(p ->> 'expires_at', '') is not null and v_exp is null then raise exception 'expires_at must be a date and time' using errcode = '22023'; end if;
  if v_exp is not null and (v_exp <= now() or v_exp > now() + interval '2 years') then raise exception 'expiry must be in the future and within 2 years' using errcode = '22023'; end if;
  if p ? 'rate_per_minute' and nullif(p ->> 'rate_per_minute', '') is not null and (v_rate is null or v_rate not between 1 and 100000) then
    raise exception 'the limit is 1 to 100,000 requests per minute' using errcode = '22023';
  end if;
  -- M34d: a referrals key reads only the codes it is linked to
  v_codes := b2b.referral_codes_parse(p -> 'referral_codes');
  if 'referrals' = any (v_scopes) and cardinality(v_codes) = 0 then
    raise exception 'link the key to at least one referral code (or a prefix such as INF*)' using errcode = '22023';
  end if;
  if not ('referrals' = any (v_scopes)) and cardinality(v_codes) > 0 then
    raise exception 'referral codes apply only to a key with the referrals scope' using errcode = '22023';
  end if;
  insert into b2b.api_keys (name, scopes, key_prefix, key_hash, created_by, expires_at, rate_per_minute, note, referral_codes)
  values (left(trim(p ->> 'name'), 80), v_scopes, left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), auth.uid(), v_exp, v_rate, left(nullif(trim(p ->> 'note'), ''), 300), v_codes)
  returning id into v_id;
  perform b2b.log_event('api_key.created', null, null, null, jsonb_build_object('api_key_id', v_id, 'name', p ->> 'name', 'scopes', to_jsonb(v_scopes),
                        'expires_at', v_exp, 'rate_per_minute', v_rate, 'referral_codes', to_jsonb(v_codes)));
  return jsonb_build_object('id', v_id, 'key', v_key);
end $function$;

CREATE OR REPLACE FUNCTION b2b.api_key_update(p_id bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  k b2b.api_keys;
  v_exp timestamptz;
  v_rate int;
  v_codes text[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into k from b2b.api_keys where id = p_id and revoked_at is null for update;
  if k.id is null then raise exception 'key not found' using errcode = 'P0002'; end if;
  v_exp := case when p ? 'expires_at' then b2b.try_timestamptz(p ->> 'expires_at') else k.expires_at end;
  if p ? 'expires_at' and nullif(p ->> 'expires_at', '') is not null and v_exp is null then raise exception 'expires_at must be a date and time' using errcode = '22023'; end if;
  if v_exp is not null and v_exp > now() + interval '2 years' then raise exception 'expiry must be within 2 years' using errcode = '22023'; end if;
  v_rate := case when p ? 'rate_per_minute' then case when (p ->> 'rate_per_minute') ~ '^[0-9]{1,6}$' then (p ->> 'rate_per_minute')::int end else k.rate_per_minute end;
  if p ? 'rate_per_minute' and nullif(p ->> 'rate_per_minute', '') is not null and (v_rate is null or v_rate not between 1 and 100000) then
    raise exception 'the limit is 1 to 100,000 requests per minute' using errcode = '22023';
  end if;
  -- M34d: the referral codes a referrals key may read (the whole list is replaced)
  v_codes := case when p ? 'referral_codes' then b2b.referral_codes_parse(p -> 'referral_codes') else k.referral_codes end;
  if p ? 'referral_codes' and not ('referrals' = any (k.scopes)) and cardinality(v_codes) > 0 then
    raise exception 'referral codes apply only to a key with the referrals scope' using errcode = '22023';
  end if;
  update b2b.api_keys
     set name = coalesce(nullif(left(trim(p ->> 'name'), 80), ''), name), expires_at = v_exp, rate_per_minute = v_rate, referral_codes = v_codes,
         note = case when p ? 'note' then left(nullif(trim(p ->> 'note'), ''), 300) else note end
   where id = k.id;
  perform b2b.log_event('api_key.updated', null, null, null, jsonb_build_object('api_key_id', k.id, 'changes', p));
  return jsonb_build_object('id', k.id, 'expires_at', v_exp, 'rate_per_minute', v_rate, 'referral_codes', to_jsonb(v_codes));
end $function$;

CREATE OR REPLACE FUNCTION b2b.system_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_jobs jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- the jobs card, from the newest 75,000 runs (about 30 hours)
  with recent as materialized (
    select d.jobid, d.runid, d.start_time, d.status, d.return_message
      from cron.job_run_details d where d.runid > (select max(x.runid) - 75000 from cron.job_run_details x)),
  last_run as (select distinct on (r.jobid) r.jobid, r.start_time, r.status from recent r order by r.jobid, r.runid desc),
  failed as (select r.jobid, count(*) as n from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' group by r.jobid),
  last_err as (
    select distinct on (r.jobid) r.jobid, left(r.return_message, 200) as msg
      from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' order by r.jobid, r.runid desc)
  select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active,
                             'last_status', r.status, 'last_run', r.start_time, 'last_error', e.msg, 'failed_24h', coalesce(f.n, 0)) order by j.jobname), '[]')
    into v_jobs
    from cron.job j
    left join last_run r on r.jobid = j.jobid
    left join failed f on f.jobid = j.jobid
    left join last_err e on e.jobid = j.jobid
   where j.jobname like 'b2b-%';
  return jsonb_build_object(
    'api_keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'scopes', k.scopes, 'prefix', k.key_prefix, 'created_at', k.created_at,
                                                              'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at,
                                                              'expires_at', k.expires_at, 'rate_per_minute', k.rate_per_minute, 'note', k.note, 'referral_codes', k.referral_codes,
                                                              'requests_1h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '1 hour'),
                                                              'requests_24h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '24 hours'))
                                                   order by k.revoked_at nulls first, k.created_at desc)
                          from b2b.api_keys k), '[]'),
    'api_limits', coalesce((select value from b2b.settings where key = 'api_limits'), '{}'),
    'endpoints', coalesce((select jsonb_agg(to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null,
                             'pending', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
                             'dead', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'dead'),
                             'delivered_24h', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'delivered' and o.delivered_at > now() - interval '1 day'))
                           order by w.id) from b2b.webhook_endpoints w), '[]'),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'event_type', o.event_type, 'endpoint_id', o.endpoint_id,
                              'endpoint', (select w.name from b2b.webhook_endpoints w where w.id = o.endpoint_id), 'status', o.status, 'attempts', o.attempts,
                              'response_status', o.response_status, 'last_error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at,
                              'next_attempt_at', o.next_attempt_at, 'lead_id', (o.payload ->> 'lead_id')::bigint) order by o.id desc)
                            from (select * from b2b.integration_outbox where endpoint_id is not null order by id desc limit 100) o), '[]'),
    'product_events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'event_type', e.event_type, 'lead_id', e.lead_id,
                                  'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.id desc)
                                from (select * from b2b.product_events order by id desc limit 50) e), '[]'),
    'erasure_open', (select count(*) from b2b.erasure_requests where status = 'open'),
    'jobs', v_jobs);
end $function$;

revoke execute on function b2b.referral_secret(), b2b.referral_ref(bigint), b2b.referral_cursor(bigint), b2b.referral_cursor_id(text),
                           b2b.referral_code_allowed(text[], text), b2b.referral_codes_parse(jsonb) from public, anon, authenticated;
grant execute on function b2b.referral_secret(), b2b.referral_ref(bigint), b2b.referral_cursor(bigint), b2b.referral_cursor_id(text),
                          b2b.referral_code_allowed(text[], text), b2b.referral_codes_parse(jsonb) to service_role;
revoke execute on function b2b.api_referral_outcomes_v2(text, text, text, integer), b2b.api_referral_outcomes(text, text, bigint, integer) from public;
grant execute on function b2b.api_referral_outcomes_v2(text, text, text, integer), b2b.api_referral_outcomes(text, text, bigint, integer)
  to anon, authenticated, service_role;
-- the replaced Admin functions keep their grants (create or replace); restated
revoke execute on function b2b.api_key_create(jsonb), b2b.api_key_update(bigint, jsonb), b2b.system_overview() from public, anon;
grant execute on function b2b.api_key_create(jsonb), b2b.api_key_update(bigint, jsonb), b2b.system_overview() to authenticated, service_role;

-- rollback: re-run b2b.api_referral_outcomes (m33d_referral_outcomes.sql), b2b.api_key_create and b2b.api_key_update
-- (m33a_access_api_hardening.sql) and b2b.system_overview (m33f_cron_history_performance.sql); then
--   revoke execute on function b2b.api_referral_outcomes_v2(text, text, text, integer) from anon, authenticated, service_role;
-- The column, the helpers and the Vault secret can stay (unused); dropping them belongs in pending/.
