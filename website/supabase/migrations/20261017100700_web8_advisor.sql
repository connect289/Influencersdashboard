-- web8 · Witty on the website (internal name web_advisor) — spec 7, 3A Witty path, docs/AGENT_ARCHITECTURE.md.
-- Website-owned state and transcript. The transcript table has exactly the w2_messages columns plus channel and
-- session_id, so rows can move into the shared table once A-AGENT-2/3 are approved. Read-only wrappers around Witty's
-- shared prompt, catalogue and knowledge functions (never writes w2_* tables). Leads only through lead_intake.

create table if not exists public.web_advisor_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.web_students (id),
  attempt_id uuid references public.web_gate_attempts (id),
  lead_id bigint,
  agent_core_version text,                 -- prompt name:version:md5 pairs + engine contract version
  state jsonb not null default '{}',       -- Witty-shaped state (profile, asks, flags, pending question, language)
  classification text not null default 'UNQUALIFIED',
  readiness text not null default 'EXPLORING',
  eligibility text not null default 'INSUFFICIENT_DATA',
  phase text not null default 'EARN_IT',
  language text not null default 'english',
  turns integer not null default 0,
  prompt_tokens integer not null default 0,
  cached_tokens integer not null default 0,
  output_tokens integer not null default 0,
  cost_usd numeric(10, 5) not null default 0,
  escalated_at timestamptz,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  last_turn_at timestamptz,
  ended_at timestamptz
);
create index if not exists web_advisor_sessions_student_idx on public.web_advisor_sessions (student_id, created_at desc);

create table if not exists public.web_advisor_messages (
  id bigint generated always as identity primary key,
  phone text not null,                     -- E.164 digits without '+', as w2_messages
  direction text not null check (direction in ('in', 'out')),
  kind text not null default 'chat',
  message_id text,
  run_id text,
  content text,
  answer_mode text,
  reply_source text,
  model text,
  prompt_tokens integer,
  cached_tokens integer,
  output_tokens integer,
  latency_ms integer,
  verify_errors jsonb,
  sent boolean,
  meta jsonb,
  created_at timestamptz not null default now(),
  channel text not null default 'web' check (channel = 'web'),
  session_id uuid not null references public.web_advisor_sessions (id)
);
create index if not exists web_advisor_messages_session_idx on public.web_advisor_messages (session_id, id);
create unique index if not exists web_advisor_messages_in_uidx on public.web_advisor_messages (session_id, message_id) where direction = 'in';

create table if not exists public.web_advisor_feedback (
  message_id bigint primary key references public.web_advisor_messages (id),
  session_id uuid not null references public.web_advisor_sessions (id),
  rating smallint not null check (rating in (-1, 1)),
  comment text check (char_length(comment) <= 500),
  created_at timestamptz not null default now()
);

create table if not exists public.web_callback_requests (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.web_students (id),
  session_id uuid references public.web_advisor_sessions (id),
  lead_id bigint,
  slot_date date not null,
  slot text not null check (slot in ('morning', 'afternoon', 'evening')),
  created_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['web_advisor_sessions', 'web_advisor_messages', 'web_advisor_feedback', 'web_callback_requests'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

insert into public.web_settings (key, value) values
  ('web_advisor_channel_overlay', jsonb_build_object('version', 1, 'body',
    'CHANNEL: website chat (not WhatsApp). The student is on eduwit.in. Keep every HARD RULE. You may use short markdown bullets ("- ") instead of "•" and **bold** at most once. Programme rows you list with {{Pn.*}} placeholders are also shown as cards under your reply, so keep each bullet to one line. Never ask for the student''s name, email or phone: the website already has them. Instead of "reply STOP", say they can stop any time and manage their data in their account.'))
on conflict (key) do nothing;

-- Prompts by reference (docs/AGENT_ARCHITECTURE.md §3.2): Witty's own assembled prompts, their versions and hashes,
-- and the web overlay. Read-only.
-- The three wrappers of Witty's shared functions pin search_path = public (not ''): Witty's w2_* functions are
-- SECURITY INVOKER with unqualified table names and run with the caller's search_path (D-055).
create or replace function public.web_agent_core_prompts()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'extractor', (select jsonb_build_object('version', p.version, 'updated_at', p.updated_at, 'md5', md5(p.body), 'text', public.w2_build_prompt('extractor'))
                  from public.w2_prompts p where p.name = 'extractor'),
    'counselor', (select jsonb_build_object('version', p.version, 'updated_at', p.updated_at, 'md5', md5(p.body), 'text', public.w2_build_prompt('counselor'))
                  from public.w2_prompts p where p.name = 'counselor'),
    'overlay', (select value from public.web_settings where key = 'web_advisor_channel_overlay'))
$$;

-- search_programmes (spec 7.3): Witty's own catalogue function (the STABLE variant, so the website never writes Witty's
-- cache), restricted to rows the website shows (web_offering_search), so Witty and the finder always agree.
-- w2_search_programs resolves the course through catalog_synonyms by exact alias (lower case, letters and digits only),
-- so the course is normalised the same way first; "MA English" style courses fall back to course "ma" + specialization.
create or replace function public.web_advisor_search(q jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_course text := nullif(regexp_replace(lower(coalesce(q->>'course', '')), '[^a-z0-9]', '', 'g'), '');
  v_words text[] := regexp_split_to_array(btrim(coalesce(q->>'course', '')), '\s+');
  v jsonb;
  v_rows jsonb;
begin
  if v_course is not null then q := q || jsonb_build_object('course', v_course); end if;
  v := public.w2_search_programs(q);
  if v_course is not null and coalesce((v->>'total_for_course')::int, 0) = 0 and cardinality(v_words) > 1 and not (q ? 'specialization') then
    q := q || jsonb_build_object('course', regexp_replace(lower(v_words[1]), '[^a-z0-9]', '', 'g'), 'specialization', array_to_string(v_words[2:], ' '));
    v := public.w2_search_programs(q);
  end if;
  select coalesce(jsonb_agg(r order by ord), '[]') into v_rows
  from jsonb_array_elements(coalesce(v->'rows', '[]')) with ordinality as e(r, ord)
  where exists (select 1 from public.web_offering_search s where s.id = (r->>'id')::bigint);
  return v || jsonb_build_object('rows', v_rows, 'visible_total', jsonb_array_length(v_rows));
end $$;

create or replace function public.web_advisor_kb(p_text text, p_limit int default 3)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(public.w2_kb_search(jsonb_build_object('text', left(p_text, 500), 'limit', least(coalesce(p_limit, 3), 6))), '[]')
$$;

-- Start or resume the student's latest open session (spec 7.2 "restore chat history").
create or replace function public.web_advisor_session_open(p_student uuid, p_new boolean default false, p_is_test boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.web_advisor_sessions; st public.web_students;
begin
  select * into st from public.web_students where id = p_student and deleted_at is null;
  if st.id is null then return null; end if;
  if p_new then
    update public.web_advisor_sessions set ended_at = now() where student_id = p_student and ended_at is null;
  else
    select * into s from public.web_advisor_sessions where student_id = p_student and ended_at is null order by created_at desc limit 1;
  end if;
  if s.id is null then
    insert into public.web_advisor_sessions (student_id, lead_id, is_test,
      state) values (p_student, st.lead_id, p_is_test,
      jsonb_build_object('profile', jsonb_strip_nulls(jsonb_build_object(
        'student_name', case when st.full_name is not null then jsonb_build_object('value', st.full_name, 'confirmed', true) end,
        'email_id', jsonb_build_object('value', st.email_norm, 'confirmed', true)))))
    returning * into s;
  end if;
  return jsonb_build_object('session', to_jsonb(s) - 'state', 'state', s.state, 'phone', st.phone_e164, 'student_name', st.full_name,
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'content', m.content,
      'answer_mode', m.answer_mode, 'meta', m.meta, 'created_at', m.created_at,
      'rating', (select f.rating from public.web_advisor_feedback f where f.message_id = m.id)) order by m.id)
      from public.web_advisor_messages m where m.session_id = s.id and m.kind in ('chat', 'reply')), '[]'));
end $$;

-- Commits one turn: both messages, the new state and usage, and the lead write through lead_intake (trusted web_agent,
-- Witty's payload keys and event types; idempotent per session turn). All in one transaction.
create or replace function public.web_advisor_turn_commit(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.web_advisor_sessions; st public.web_students; v_turn int; v_in bigint; v_out bigint; v_res jsonb; v_key text;
  v_phone text; v_lead jsonb := case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end;
  u jsonb := coalesce(p->'usage', '{}');
begin
  select * into s from public.web_advisor_sessions where id = (p->>'session_id')::uuid for update;
  if s.id is null or s.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  select * into st from public.web_students where id = s.student_id;
  v_turn := s.turns + 1;
  v_phone := ltrim(coalesce(st.phone_e164, ''), '+');

  insert into public.web_advisor_messages (phone, direction, kind, message_id, run_id, content, sent, meta, session_id)
  values (v_phone, 'in', 'chat', p->>'message_id', p->>'run_id', left(p->>'student_message', 4000), true,
          jsonb_build_object('client_id', p->>'message_id'), s.id)
  on conflict (session_id, message_id) where direction = 'in' do nothing
  returning id into v_in;
  if v_in is null then
    return jsonb_build_object('ok', true, 'status', 'duplicate');
  end if;
  insert into public.web_advisor_messages (phone, direction, kind, run_id, content, answer_mode, reply_source, model, prompt_tokens,
    cached_tokens, output_tokens, latency_ms, verify_errors, sent, meta, session_id)
  values (v_phone, 'out', 'reply', p->>'run_id', p->>'reply', p->>'answer_mode', p->>'reply_source', p->>'model',
    (u->>'prompt_tokens')::int, (u->>'cached_tokens')::int, (u->>'output_tokens')::int, (p->>'latency_ms')::int,
    p->'verify_errors', true, coalesce(p->'meta', '{}'), s.id)
  returning id into v_out;

  update public.web_advisor_sessions set
    state = coalesce(p->'state', state), turns = v_turn, last_turn_at = now(),
    classification = coalesce(p->>'classification', classification), readiness = coalesce(p->>'readiness', readiness),
    eligibility = coalesce(p->>'eligibility', eligibility), phase = coalesce(p->>'phase', phase),
    language = coalesce(p->>'language', language), agent_core_version = coalesce(p->>'agent_core_version', agent_core_version),
    prompt_tokens = prompt_tokens + coalesce((u->>'prompt_tokens')::int, 0),
    cached_tokens = cached_tokens + coalesce((u->>'cached_tokens')::int, 0),
    output_tokens = output_tokens + coalesce((u->>'output_tokens')::int, 0),
    cost_usd = cost_usd + coalesce((u->>'cost_usd')::numeric, 0),
    escalated_at = case when (p->>'escalate')::boolean then coalesce(escalated_at, now()) else escalated_at end
  where id = s.id;

  -- Lead: same key set as w2_crm_payload, source_system web_agent (D-009), web channel stamps (first-touch).
  if st.phone_e164 is not null and coalesce(p->>'event_type', '') <> '' then
    v_key := 'web:' || s.id::text || ':' || v_turn;
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, s.student_id, 'advisor.' || (p->>'event_type'))
    on conflict do nothing;
    if found then
      v_res := public.lead_intake(jsonb_build_object('phone', st.phone_e164, 'source_system', 'web_agent', 'event_type', p->>'event_type',
        'idempotency_key', v_key, 'is_test', s.is_test, 'occurred_at', now(),
        'lead', jsonb_strip_nulls(v_lead || jsonb_build_object('web_session_id', s.id::text, 'channel', 'web', 'first_agent_channel', 'web',
          'source', 'website_agent', 'last_agent_message_at', now()))));
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_advisor_sessions set lead_id = coalesce(lead_id, (v_res->>'lead_id')::bigint) where id = s.id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'turn', v_turn, 'in_id', v_in, 'out_id', v_out, 'lead', v_res);
end $$;

create or replace function public.web_advisor_feedback_add(p_student uuid, p_message bigint, p_rating smallint, p_comment text default null)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_session uuid;
begin
  select m.session_id into v_session from public.web_advisor_messages m join public.web_advisor_sessions s on s.id = m.session_id
   where m.id = p_message and m.direction = 'out' and s.student_id = p_student;
  if v_session is null then return false; end if;
  insert into public.web_advisor_feedback (message_id, session_id, rating, comment) values (p_message, v_session, p_rating, left(p_comment, 500))
  on conflict (message_id) do update set rating = excluded.rating, comment = coalesce(excluded.comment, public.web_advisor_feedback.comment), created_at = now();
  return true;
end $$;

-- "Book a callback" (spec 7.4): a time slot written to the lead through the approved path.
create or replace function public.web_callback_request(p_student uuid, p_session uuid, p_date date, p_slot text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st public.web_students; v_id bigint; v_res jsonb; v_label text;
begin
  select * into st from public.web_students where id = p_student and deleted_at is null;
  if st.id is null or st.phone_e164 is null then return jsonb_build_object('ok', false, 'reason', 'no_phone'); end if;
  if p_date < (now() at time zone 'Asia/Kolkata')::date or p_date > (now() at time zone 'Asia/Kolkata')::date + 14 then
    return jsonb_build_object('ok', false, 'reason', 'bad_date');
  end if;
  insert into public.web_callback_requests (student_id, session_id, lead_id, slot_date, slot)
  values (p_student, p_session, st.lead_id, p_date, p_slot) returning id into v_id;
  v_label := 'Callback ' || to_char(p_date, 'Dy DD Mon') || ', ' || case p_slot when 'morning' then 'morning (9am–12pm)' when 'afternoon' then 'afternoon (12–4pm)' else 'evening (4–8pm)' end;
  v_res := public.lead_intake(jsonb_build_object('phone', st.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.updated',
    'idempotency_key', 'web:callback:' || v_id, 'lead', jsonb_build_object('preferred_call_time', v_label, 'last_intent', 'asks_human')));
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'lead', v_res);
end $$;

-- Account: past conversations (spec 7.4 "conversation history in the account").
create or replace function public.web_advisor_history(p_student uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'created_at', s.created_at, 'last_turn_at', s.last_turn_at, 'turns', s.turns,
    'open', s.ended_at is null,
    'messages', coalesce((select jsonb_agg(jsonb_build_object('direction', m.direction, 'content', m.content, 'created_at', m.created_at) order by m.id)
                 from public.web_advisor_messages m where m.session_id = s.id and m.kind in ('chat', 'reply')), '[]'))
    order by s.created_at desc), '[]')
  from public.web_advisor_sessions s where s.student_id = p_student and s.turns > 0
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_agent_core_prompts()', 'public.web_advisor_search(jsonb)', 'public.web_advisor_kb(text, integer)',
    'public.web_advisor_session_open(uuid, boolean, boolean)', 'public.web_advisor_turn_commit(jsonb)',
    'public.web_advisor_feedback_add(uuid, bigint, smallint, text)', 'public.web_callback_request(uuid, uuid, date, text)',
    'public.web_advisor_history(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
