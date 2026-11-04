CREATE OR REPLACE FUNCTION public.w2_is_test(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(p_phone, '') similar to '910000[0-9]{6}' or exists (select 1 from w2_trusted t where t.phone = p_phone and t.is_test);
$function$
;
CREATE OR REPLACE FUNCTION public.w2_stale_inbox(p_older_than_seconds integer DEFAULT 40)
 RETURNS TABLE(phone text)
 LANGUAGE sql
 STABLE
AS $function$
select distinct i.phone
from w2_inbox i join w2_conversations c on c.phone = i.phone
where i.processed_at is null
and i.received_at < now() - make_interval(secs => p_older_than_seconds)
and (c.lock_until is null or c.lock_until < now())
and not c.opted_out
limit 50;
$function$
;
CREATE OR REPLACE FUNCTION public.w2_health_alerts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
select coalesce(jsonb_agg(x), '[]'::jsonb) from (
  select 'outbox_failed' as alert, count(*)::text as detail from w2_outbox where status = 'failed' having count(*) > 0
  union all
  select 'stale_inbox', count(*)::text from w2_stale_inbox(300) having count(*) > 0
  union all
  select 'send_failed_last_hour', count(*)::text from w2_events where type = 'send_failed' and created_at > now() - interval '1 hour' having count(*) > 0
  union all
  select 'extractor_error_rate', round(100.0 * count(*) filter (where coalesce(payload->>'extractor_error', '') <> '') / greatest(count(*), 1), 0)::text || '%'
    from w2_events where type = 'turn' and created_at > now() - interval '1 hour'
   having count(*) >= 5 and count(*) filter (where coalesce(payload->>'extractor_error', '') <> '') * 5 > count(*)
  union all
  select 'cache_expired', name from w2_gemini_caches where expire_at < now()
  union all
  select 'fallback_rate_last_hour', round(100.0 * count(*) filter (where reply_source = 'fallback') / greatest(count(*), 1), 0)::text || '%'
    from w2_messages where direction = 'out' and kind = 'reply' and created_at > now() - interval '1 hour' and not w2_is_test(phone)
   having count(*) >= 5 and count(*) filter (where reply_source = 'fallback') * 4 > count(*)
) x;
$function$
;
CREATE OR REPLACE FUNCTION public.w2_cache_plan(p_model text, p_refresh_minutes integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_out jsonb := '[]'::jsonb;
v_name text;
v_text text;
v_hash text;
c w2_gemini_caches;
begin
foreach v_name in array array['extractor', 'counselor'] loop
v_text := w2_build_prompt(v_name);
continue when v_text is null;
v_hash := md5(v_text);
insert into w2_gemini_caches (name) values (v_name) on conflict (name) do nothing;
select * into c from w2_gemini_caches where name = v_name;
update w2_gemini_caches set prompt_text = v_text, updated_at = now() where name = v_name;
if c.cache_name is null or c.prompt_hash is distinct from v_hash or c.model is distinct from p_model
or c.expire_at is null or c.expire_at < now() + make_interval(mins => p_refresh_minutes) then
v_out := v_out || jsonb_build_object('name', v_name, 'hash', v_hash, 'text', v_text, 'old_cache', c.cache_name, 'model', p_model);
end if;
end loop;
return v_out;
end $function$
;
CREATE OR REPLACE FUNCTION public.w2_build_prompt(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
v_base    text := (select body from w2_prompts where name = p_name);
v_lessons text;
v_kinds   text[] := case p_name when 'extractor' then array['extractor_rule', 'extractor_example', 'intent_phrase']
else array['counselor_guideline', 'counselor_example'] end;
begin
if v_base is null then return null; end if;
select string_agg('- ' || coalesce(payload->>'text', title), E'\n' order by id) into v_lessons
from (select id, payload, title from w2_learnings
where status in ('approved', 'applied') and kind = any(v_kinds)
order by id limit 40) l;
return v_base
|| case when p_name = 'extractor' then E'\n\n' || w2_catalog_index() else '' end
|| case when v_lessons is not null then E'\n\nLESSONS FROM REVIEWED CONVERSATIONS (follow them):\n' || v_lessons else '' end;
end $function$
;
CREATE OR REPLACE FUNCTION public.w2_catalog_index()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
select coalesce('CATALOG INDEX (course: common specializations | modes | levels). Use it only to recognise and spell course and specialization names; never add a course or specialization the student did not state.' || E'\n' ||
string_agg(line, E'\n' order by n desc, line), '')
from (
select count(*) as n,
min(p.course) || ': ' ||
coalesce((select string_agg(s.specialization, ', ') from (
select specialization from catalog_programs p2
where p2.active and p2.course_key = p.course_key and p2.specialization <> 'General'
group by specialization order by count(*) desc, specialization limit 6) s), 'general') ||
' | ' || string_agg(distinct p.mode, '/') || ' | ' || string_agg(distinct coalesce(p.level, '?'), '/') as line
from catalog_programs p
where p.active and p.course_key is not null and p.course_key <> ''
group by p.course_key
order by count(*) desc
limit 80
) x;
$function$
;
CREATE OR REPLACE FUNCTION public.w2_inbox_add(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_id text;
begin
insert into w2_inbox (message_id, phone, conversation_id, account_id, content, content_type, has_attachment, labels, referral)
values (p->>'message_id', p->>'phone', (p->>'conversation_id')::bigint, (p->>'account_id')::bigint, p->>'content',
p->>'content_type', coalesce((p->>'has_attachment')::boolean, false), p->'labels',
case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end)
on conflict (message_id) do nothing
returning message_id into v_id;
if v_id is not null then
insert into w2_messages (phone, direction, kind, message_id, content, meta)
values (p->>'phone', 'in', 'chat', v_id, p->>'content',
jsonb_build_object('conversation_id', p->>'conversation_id', 'content_type', p->>'content_type', 'has_attachment', coalesce((p->>'has_attachment')::boolean, false),
'referral', case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end))
on conflict do nothing;
end if;
return jsonb_build_object('inserted', v_id is not null, 'phone', p->>'phone');
end $function$
;
CREATE OR REPLACE FUNCTION public.w2_cache_saved(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
begin
if coalesce(p->>'cache_name', '') <> '' then
update w2_gemini_caches set cache_name = p->>'cache_name', model = p->>'model', prompt_hash = p->>'hash',
tokens = (p->>'tokens')::int, expire_at = (p->>'expire_at')::timestamptz, error = null, updated_at = now()
where name = p->>'name';
else
update w2_gemini_caches set error = left(p->>'error', 1000), updated_at = now() where name = p->>'name';
end if;
return jsonb_build_object('name', p->>'name', 'ok', coalesce(p->>'cache_name', '') <> '');
end $function$
;
CREATE OR REPLACE FUNCTION public.w2_turn_prompts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ select coalesce(jsonb_object_agg(name, jsonb_strip_nulls(jsonb_build_object('cache', case when cache_name is not null and expire_at > now() + interval '3 minutes' then cache_name end, 'model', case when cache_name is not null and expire_at > now() + interval '3 minutes' then model end, 'text', prompt_text))), '{}'::jsonb) from w2_gemini_caches; $function$
;
CREATE OR REPLACE FUNCTION public.w2_release(p_phone text, p_run text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare v_pending int;
begin
update w2_conversations set lock_id = null, lock_until = null where phone = p_phone and lock_id = p_run;
select count(*) into v_pending from w2_inbox where phone = p_phone and processed_at is null;
return v_pending;
end $function$
;
CREATE OR REPLACE FUNCTION public.w2_parse_rating(p_text text)
 RETURNS smallint
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare t text := lower(btrim(coalesce(p_text, '')));
begin
if length(t) = 0 or length(t) > 30 then return null; end if;
if t ~ '^(👍|🙂|😊|😀|❤|good|great|very good|helpful|very helpful|useful|nice|accha|achha|acha|badhiya|bahut accha|5|4)[\s.!]*$' or t ~ '^👍' then return 1; end if;
if t ~ '^(👎|🙁|😞|😠|bad|not good|not helpful|unhelpful|not useful|useless|bekar|bakwas|1|2)[\s.!]*$' or t ~ '^👎' then return -1; end if;
if t ~ '^(3|ok|okay|average|theek|thik)[\s.!]*$' then return 0; end if;
return null;
end $function$
;
-- stand-ins with the production signatures for functions whose bodies depend on other apps
create or replace function public.w2_health_digest(p_hours integer default 24) returns jsonb language sql stable as $$ select jsonb_build_object('stale', (select count(*) from w2_stale_inbox(300)), 'test', w2_is_test('910000000001')) $$;
create or replace function public.w2_crm_owned(p_phone text) returns boolean language sql stable as $$ select false $$;
revoke execute on function public.w2_crm_owned(text) from public, anon;
grant execute on function public.w2_health_alerts(), public.w2_health_digest(integer) to eduwit_one_reader;
create view public.w2_latency_daily as
 SELECT date_trunc('day'::text, created_at) AS day, count(*) AS replies, round(avg(latency_ms)) AS avg_ms,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision)) AS p50_ms,
    percentile_cont(0.95::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision)) AS p95_ms,
    round(sum(cached_tokens)::numeric / NULLIF(sum(prompt_tokens), 0)::numeric, 3) AS cached_share
   FROM w2_messages
  WHERE direction = 'out'::text AND kind = 'reply'::text AND latency_ms IS NOT NULL AND NOT w2_is_test(phone)
  GROUP BY (date_trunc('day'::text, created_at)) ORDER BY (date_trunc('day'::text, created_at)) DESC;
grant select on public.w2_latency_daily to eduwit_one_reader;
