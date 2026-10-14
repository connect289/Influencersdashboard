-- B2C CRM b23 (Phase 3): "Brief before you call" (spec B8.3, B18). Staging first. Idempotent.
--   scrub_pii()        removes email addresses, phone numbers (8 or more digits, however written) and the lead's own
--                      known numbers and addresses from any text
--   brief_input()      what Claude may see for a brief: profile fields (first name only), interest, stage, partner history,
--                      the Witty conversation and recent activity, every item scrubbed and tagged with its source
--   lead_briefs        3-5 lines, each with its source; stale when a key fact changes (programme, stage, a new Witty turn,
--                      a partner event, a new call outcome)
--   brief_get()        the lead screen; brief_due_take() the leads with a call due within the hour, for the job

create table if not exists b2c.lead_briefs (
  lead_id bigint primary key,
  lines jsonb not null default '[]'::jsonb,     -- [{text, source}] source: field:<path> | witty:<id> | activity:<id> | partner
  facts_hash text,
  model text,
  written_at timestamptz,
  attempted_at timestamptz,
  error text
);

/* Every email address and phone number out of a text, plus the given known values (the lead's own). */
create or replace function b2c.scrub_pii(p_text text, p_known text[] default '{}') returns text language plpgsql immutable set search_path = '' as $f$
declare t text := p_text; k text;
begin
  if t is null then return null; end if;
  foreach k in array coalesce(p_known, '{}') loop
    if length(coalesce(k, '')) >= 5 then t := replace(t, k, '[removed]'); end if;
  end loop;
  t := regexp_replace(t, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g');
  t := regexp_replace(t, '[A-Za-z0-9._%+-]+\s*(\(at\)|\[at\]| at )\s*[A-Za-z0-9-]+\s*(\(dot\)|\[dot\]| dot |\.)\s*[A-Za-z]{2,}', '[email]', 'gi');
  t := regexp_replace(t, '(\+?\d[\s().-]{0,2}){8,}', '[phone]', 'g');
  return t;
end $f$;

/* Every string inside a JSON value scrubbed (numbers and keys are left alone). */
create or replace function b2c.scrub_jsonb(p jsonb, p_known text[] default '{}') returns jsonb language plpgsql immutable set search_path = '' as $f$
begin
  return case jsonb_typeof(p)
    when 'string' then to_jsonb(b2c.scrub_pii(p #>> '{}', p_known))
    when 'object' then coalesce((select jsonb_object_agg(e.key, b2c.scrub_jsonb(e.value, p_known)) from jsonb_each(p) e), '{}'::jsonb)
    when 'array' then coalesce((select jsonb_agg(b2c.scrub_jsonb(e.value, p_known) order by e.ord) from jsonb_array_elements(p) with ordinality e(value, ord)), '[]'::jsonb)
    else p end;
end $f$;

/* The lead's known phone numbers and email addresses (every form), to scrub exactly. */
create or replace function b2c.lead_pii(p_lead bigint) returns text[] language sql stable security definer set search_path = '' as $f$
  select coalesce(array_agg(distinct v) filter (where v is not null and length(v) >= 5), '{}') from (
    select c.value as v from b2c.lead_contacts c where c.lead_id = p_lead
    union all select c.value_norm from b2c.lead_contacts c where c.lead_id = p_lead
    union all select right(c.value_norm, 10) from b2c.lead_contacts c where c.lead_id = p_lead and c.kind = 'phone'
    union all select r.record -> 'student' ->> 'phone' from b2c.lead_records r where r.lead_id = p_lead
    union all select right(regexp_replace(r.record -> 'student' ->> 'phone', '\D', '', 'g'), 10) from b2c.lead_records r where r.lead_id = p_lead
    union all select r.record -> 'student' ->> 'email' from b2c.lead_records r where r.lead_id = p_lead) s
$f$;

/* Witty's messages for a lead (read-only from w2_messages, as witty_transcript in b11, without the screen's permission
   check: internal). */
create or replace function b2c.witty_messages(p_lead bigint, p_limit int default 40) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_phones text[]; v jsonb;
begin
  if to_regclass('public.w2_messages') is null then return '[]'::jsonb; end if;
  select array_agg(distinct x) into v_phones from (
    select c.value_norm as x from b2c.lead_contacts c where c.lead_id = p_lead and c.kind = 'phone' and c.removed_at is null
    union select b2c.norm_phone(r.record -> 'student' ->> 'phone') from b2c.lead_records r where r.lead_id = p_lead) p where x is not null;
  if v_phones is null then return '[]'::jsonb; end if;
  v_phones := v_phones || array(select '+' || x from unnest(v_phones) x);
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'content', m.content, 'at', m.created_at) order by m.created_at, m.id), '[]') into v
    from (select w.id, w.direction, w.content, w.created_at from public.w2_messages w
           where w.phone = any (v_phones) and coalesce(w.content, '') <> '' order by w.created_at desc, w.id desc limit p_limit) m;
  return v;
end $f$;

/* The facts a brief depends on; a different hash means the brief is stale. */
create or replace function b2c.brief_facts_hash(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select md5(concat_ws('|',
    (select (r.record -> 'interest')::text || (r.record -> 'education')::text from b2c.lead_records r where r.lead_id = p_lead),
    (select concat_ws(',', s.stage_id, s.sub_stage, s.partner_lost::text, s.handoff_reason, s.status) from b2c.leads_state s where s.lead_id = p_lead),
    (select max(a.id) from b2c.activities a where a.lead_id = p_lead and a.kind in ('call', 'stage', 'note', 'application', 'enrollment', 'correction', 'reenquiry', 'reengaged')),
    (select max((x ->> 'id')::bigint) from jsonb_array_elements(b2c.witty_messages(p_lead, 1)) x)))
$f$;

/* Service role: the model's input. Nothing here is a phone number or an email address (b2c.scrub_pii on every text). */
create or replace function b2c.brief_input(p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare r b2c.lead_records; s b2c.leads_state; k text[] := b2c.lead_pii(p_lead); v jsonb;
begin
  select * into r from b2c.lead_records where lead_id = p_lead;
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.lead_id is null then raise exception 'unknown lead'; end if;
  v := jsonb_build_object(
    'lead_id', p_lead,
    'facts', jsonb_strip_nulls(jsonb_build_object(
      'first_name', split_part(trim(coalesce(r.record -> 'student' ->> 'name', '')), ' ', 1),
      'city', r.record -> 'student' ->> 'city', 'state', r.record -> 'student' ->> 'state', 'language', r.record -> 'student' ->> 'preferred_language',
      'interest', r.record -> 'interest', 'education', r.record -> 'education', 'experience', r.record -> 'experience', 'qualification', r.record -> 'qualification',
      'source', r.record -> 'source' ->> 'lead_source', 'handoff_reason', s.handoff_reason, 'lane', s.lane,
      'stage', (select name from b2c.stages where id = s.stage_id), 'sub_stage', s.sub_stage, 'stage_comment', s.stage_comment,
      'temperature', coalesce(s.temperature, case when s.hot then 'hot' end), 'score', s.score, 'contact_attempts', s.contact_attempts,
      'partner_history', case when s.partner_lost is not null or s.lost_by = 'partner' then jsonb_build_object('lost', s.partner_lost, 'providers', s.providers) end,
      'reengaged', case when s.reengaged_at is not null then jsonb_build_object('at', s.reengaged_at, 'trigger', s.reengage_trigger) end)),
    'witty', (select coalesce(jsonb_agg(jsonb_build_object('source', 'witty:' || (x ->> 'id'), 'from', case when x ->> 'direction' in ('in', 'inbound') then 'student' else 'witty' end,
                                                         'text', left(b2c.scrub_pii(x ->> 'content', k), 600))), '[]')
                from jsonb_array_elements(b2c.witty_messages(p_lead, 40)) x),
    'activity', (select coalesce(jsonb_agg(jsonb_build_object('source', 'activity:' || a.id, 'kind', a.kind, 'at', a.at, 'outcome', a.outcome,
                                                            'text', left(b2c.scrub_pii(a.body, k), 400)) order by a.at), '[]')
                   from (select * from b2c.activities a where a.lead_id = p_lead and not a.internal
                           and a.kind in ('call', 'stage', 'note', 'application', 'enrollment', 'correction', 'reenquiry', 'reengaged', 'programme_shared', 'handoff')
                         order by a.at desc limit 20) a));
  -- belt and braces: the facts object is scrubbed as text too (a phone typed into a free-text field)
  v := jsonb_set(v, '{facts}', b2c.scrub_jsonb(v -> 'facts', k));
  return v || jsonb_build_object('facts_hash', b2c.brief_facts_hash(p_lead));
end $f$;

create or replace function b2c.brief_get(p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare b b2c.lead_briefs; h text;
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into b from b2c.lead_briefs where lead_id = p_lead;
  h := b2c.brief_facts_hash(p_lead);
  return jsonb_build_object('lines', coalesce(b.lines, '[]'), 'written_at', b.written_at, 'model', b.model, 'error', b.error,
                            'stale', b.lead_id is null or b.facts_hash is distinct from h, 'facts_hash', h);
end $f$;

/* Service role: store a brief. 3-5 lines of at most 300 characters, each naming a source from the input. */
create or replace function b2c.brief_save(p jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := jsonb_array_length(coalesce(p -> 'lines', '[]'));
begin
  if p ->> 'error' is not null then
    insert into b2c.lead_briefs as b (lead_id, attempted_at, error) values ((p ->> 'lead_id')::bigint, now(), left(p ->> 'error', 300))
    on conflict (lead_id) do update set attempted_at = now(), error = excluded.error;
    return;
  end if;
  if n < 1 or n > 5 then raise exception 'a brief has 1 to 5 lines'; end if;
  for x in select * from jsonb_array_elements(p -> 'lines') loop
    if length(coalesce(x ->> 'text', '')) not between 3 and 300 then raise exception 'each line has 3 to 300 characters'; end if;
    if coalesce(x ->> 'source', '') !~ '^(field:[a-z_.]+|witty:[0-9]+|activity:[0-9]+|partner)$' then raise exception 'unknown source %', x ->> 'source'; end if;
  end loop;
  insert into b2c.lead_briefs as b (lead_id, lines, facts_hash, model, written_at, attempted_at, error)
  values ((p ->> 'lead_id')::bigint, p -> 'lines', p ->> 'facts_hash', p ->> 'model', now(), now(), null)
  on conflict (lead_id) do update set lines = excluded.lines, facts_hash = excluded.facts_hash, model = excluded.model, written_at = now(), attempted_at = now(), error = null;
end $f$;

/* Service role: leads with a call due within the hour (or overdue) whose brief is missing or stale, not tried in the
   last 30 minutes. Real leads only: test leads get a brief only when someone opens them. */
create or replace function b2c.brief_due_take(p_limit int default 5) returns bigint[] language plpgsql security definer set search_path = '' as $f$
declare v bigint[];
begin
  select array_agg(lead_id) into v from (
    select distinct t.lead_id from b2c.tasks t join b2c.leads_state s on s.lead_id = t.lead_id and s.status = 'active' and not s.is_test and s.deleted_at is null
      left join b2c.lead_briefs b on b.lead_id = t.lead_id
     where t.status = 'open' and t.kind = 'call' and t.due_at < now() + interval '60 minutes' and t.due_at > now() - interval '1 day'
       and (b.attempted_at is null or b.attempted_at < now() - interval '30 minutes')
       and (b.lead_id is null or b.facts_hash is distinct from b2c.brief_facts_hash(t.lead_id))
     limit p_limit) q;
  if v is not null then
    insert into b2c.lead_briefs (lead_id, attempted_at) select x, now() from unnest(v) x
    on conflict (lead_id) do update set attempted_at = now();
  end if;
  return coalesce(v, '{}');
end $f$;

alter table b2c.lead_briefs enable row level security;
grant select on b2c.lead_briefs to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'lead_briefs' and policyname = 'who may see') then
    create policy "who may see" on b2c.lead_briefs for select to authenticated using ((select b2c.can_see(lead_id)));
  end if;
end $p$;
grant execute on function b2c.brief_get(bigint) to authenticated;
grant execute on function b2c.brief_input(bigint), b2c.brief_save(jsonb), b2c.brief_due_take(integer), b2c.brief_get(bigint) to service_role;
revoke execute on function b2c.scrub_pii(text, text[]), b2c.scrub_jsonb(jsonb, text[]), b2c.lead_pii(bigint), b2c.witty_messages(bigint, integer), b2c.brief_facts_hash(bigint),
  b2c.brief_input(bigint), b2c.brief_save(jsonb), b2c.brief_due_take(integer) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
