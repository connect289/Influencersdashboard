-- B2C CRM b4: the lead allocation engine (spec B7). Staging first.
--   calendars    work_patterns (per weekday), shift_overrides (a roster day), holidays, leaves, away_until (users)
--   rules        allocation_rules (ordered: condition, logic, pool, fallbacks), pools, pool_members (weights)
--   decisions    allocation_decisions (every candidate, every skip reason), assignments
--   functions    working_window / working_now / next_working_at / add_working_minutes (also the SLA clock),
--                rule_matches, eligibility, decide (pure), allocate (decide + assign), assign, reengage, reassign,
--                hand_back, allocation_tick, simulate
-- Test leads go only to test users (users.is_test_user) or an Admin; real leads never to a test user.

create table if not exists b2c.work_patterns (
  user_id uuid not null references b2c.users (user_id),
  isodow smallint not null check (isodow between 1 and 7),
  start_t time not null,
  end_t time not null check (end_t > start_t),
  primary key (user_id, isodow)
);
create table if not exists b2c.shift_overrides (
  user_id uuid not null references b2c.users (user_id),
  day date not null,
  start_t time,
  end_t time,
  off boolean not null default false,
  label text,
  primary key (user_id, day)
);
create table if not exists b2c.holidays (
  day date primary key,
  name text not null,
  kind text not null default 'company' check (kind in ('national', 'company'))
);
create table if not exists b2c.leaves (
  id bigint generated always as identity primary key,
  user_id uuid not null references b2c.users (user_id),
  from_day date not null,
  to_day date not null check (to_day >= from_day),
  mode text not null default 'hold' check (mode in ('hold', 'reassign')),
  reassign_after_hours int check (reassign_after_hours is null or reassign_after_hours >= 0),
  reason text,
  created_by uuid,
  created_at timestamptz not null default now(),
  reassigned_at timestamptz
);
create table if not exists b2c.pools (
  id bigint generated always as identity primary key,
  name text not null unique,
  description text
);
create table if not exists b2c.pool_members (
  pool_id bigint not null references b2c.pools (id),
  user_id uuid not null references b2c.users (user_id),
  weight int not null default 1 check (weight between 1 and 10),
  position int not null default 0,
  primary key (pool_id, user_id)
);
create table if not exists b2c.allocation_rules (
  id bigint generated always as identity primary key,
  position int not null,
  name text not null,
  enabled boolean not null default true,
  condition jsonb not null default '{}'::jsonb,
  logic text not null default 'round_robin' check (logic in ('round_robin', 'weighted_round_robin', 'least_loaded', 'capacity',
                      'performance', 'skill_match', 'territory', 'pinning', 'returning', 'manual')),
  params jsonb not null default '{}'::jsonb,       -- skill_match: {"match": ["language","programme","university","level"]}
  pool_id bigint references b2c.pools (id),        -- null = everyone
  fallbacks jsonb not null default '["next_rule"]'::jsonb,  -- next_rule | on_call | admin | unassigned
  applies_from timestamptz not null default now(),
  turn int not null default -1,
  is_catch_all boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  actor_id uuid
);
create table if not exists b2c.allocation_decisions (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  at timestamptz not null default now(),
  trigger text not null,
  hot boolean not null default false,
  facts jsonb not null default '{}'::jsonb,
  rule_id bigint,
  rule_name text,
  logic text,
  pool text,
  eligible jsonb not null default '[]'::jsonb,
  skipped jsonb not null default '[]'::jsonb,
  chosen uuid,
  turn int,
  outcome text not null check (outcome in ('assigned', 'kept', 'unassigned', 'waiting_hours', 'manual_queue', 'skipped')),
  why text,
  simulated boolean not null default false
);
create index if not exists allocation_decisions_lead on b2c.allocation_decisions (lead_id, at desc);
create table if not exists b2c.assignments (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  user_id uuid not null references b2c.users (user_id),
  decision_id bigint references b2c.allocation_decisions (id),
  trigger text not null,
  reason text,
  by_user uuid,
  at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason text
);
create index if not exists assignments_user_at on b2c.assignments (user_id, at desc);
create index if not exists assignments_lead on b2c.assignments (lead_id, at desc);
create unique index if not exists assignments_one_open on b2c.assignments (lead_id) where ended_at is null;

do $d$
declare t text;
begin
  foreach t in array array['work_patterns', 'shift_overrides', 'holidays', 'leaves', 'pools', 'pool_members', 'allocation_rules', 'allocation_decisions', 'assignments'] loop
    execute format('alter table b2c.%I enable row level security', t);
    execute format('grant select on b2c.%I to authenticated', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = t and policyname = 'staff read') then
      execute format('create policy "staff read" on b2c.%I for select to authenticated using ((select b2c.is_staff()))', t);
    end if;
  end loop;
end $d$;

insert into b2c.allocation_rules (position, name, condition, logic, fallbacks, is_catch_all)
select 1000, 'Everyone else (catch-all)', '{}'::jsonb, 'round_robin', '["unassigned"]'::jsonb, true
where not exists (select 1 from b2c.allocation_rules where is_catch_all);

-- ---------- calendars ----------
/* The person's working window on a local day, or nothing (holiday, leave, off, no pattern that weekday). */
create or replace function b2c.working_window(p_user uuid, p_day date, out w_start timestamptz, out w_end timestamptz)
language plpgsql stable security definer set search_path = '' as $f$
declare v_tz text; o b2c.shift_overrides; p b2c.work_patterns; d jsonb := b2c.setting('working_defaults'); v_has boolean;
begin
  select coalesce(u.tz, 'Asia/Kolkata') into v_tz from b2c.users u where u.user_id = p_user;
  v_tz := coalesce(v_tz, d ->> 'tz', 'Asia/Kolkata');
  if exists (select 1 from b2c.holidays h where h.day = p_day) then return; end if;
  if p_user is not null and exists (select 1 from b2c.leaves l where l.user_id = p_user and p_day between l.from_day and l.to_day) then return; end if;
  select * into o from b2c.shift_overrides s where s.user_id = p_user and s.day = p_day;
  if o.user_id is not null then
    if o.off or o.start_t is null then return; end if;
    w_start := (p_day + o.start_t) at time zone v_tz; w_end := (p_day + o.end_t) at time zone v_tz; return;
  end if;
  select exists (select 1 from b2c.work_patterns x where x.user_id = p_user) into v_has;
  if v_has then
    select * into p from b2c.work_patterns x where x.user_id = p_user and x.isodow = extract(isodow from p_day);
    if p.user_id is null then return; end if;
    w_start := (p_day + p.start_t) at time zone v_tz; w_end := (p_day + p.end_t) at time zone v_tz; return;
  end if;
  if not (d -> 'days') @> to_jsonb(extract(isodow from p_day)::int) then return; end if;
  w_start := (p_day + (d ->> 'start')::time) at time zone v_tz; w_end := (p_day + (d ->> 'end')::time) at time zone v_tz;
end $f$;

create or replace function b2c.local_day(p_user uuid, p_at timestamptz) returns date language sql stable security definer set search_path = '' as $f$
  select (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))::date
$f$;

/* Working now: inside today's window and not away. */
create or replace function b2c.working_now(p_user uuid, p_at timestamptz default now()) returns boolean
language plpgsql stable security definer set search_path = '' as $f$
declare w record;
begin
  if exists (select 1 from b2c.users u where u.user_id = p_user and u.away_until > p_at) then return false; end if;
  select * into w from b2c.working_window(p_user, b2c.local_day(p_user, p_at));
  return w.w_start is not null and p_at >= w.w_start and p_at < w.w_end;
end $f$;

/* The next moment the person (or the default calendar, p_user null) is working, from p_at. */
create or replace function b2c.next_working_at(p_user uuid, p_at timestamptz default now()) returns timestamptz
language plpgsql stable security definer set search_path = '' as $f$
declare w record; i int; v_day date := b2c.local_day(p_user, p_at);
begin
  for i in 0 .. 30 loop
    select * into w from b2c.working_window(p_user, v_day + i);
    if w.w_start is not null and p_at < w.w_end then return greatest(p_at, w.w_start); end if;
  end loop;
  return null;
end $f$;

/* p_at plus p_minutes of the person's working time (the SLA clock pauses outside their hours, B7.1). */
create or replace function b2c.add_working_minutes(p_user uuid, p_at timestamptz, p_minutes int) returns timestamptz
language plpgsql stable security definer set search_path = '' as $f$
declare v_left numeric := p_minutes; v_t timestamptz := p_at; w record; i int; v_room numeric;
begin
  for i in 0 .. 60 loop
    v_t := b2c.next_working_at(p_user, v_t);
    if v_t is null then return null; end if;
    select * into w from b2c.working_window(p_user, b2c.local_day(p_user, v_t));
    v_room := extract(epoch from (w.w_end - v_t)) / 60;
    if v_room >= v_left then return v_t + make_interval(secs => v_left * 60); end if;
    v_left := v_left - v_room; v_t := w.w_end;
  end loop;
  return null;
end $f$;

-- ---------- rules ----------
/* condition = {"all": [c…], "any": [c…]}; c = {field, op, value}. Empty = matches. ops: eq, neq, in, not_in, contains,
   gte, lte, is_true, is_false, is_null, not_null. Text comparisons ignore case. */
create or replace function b2c.rule_matches(p_cond jsonb, p_facts jsonb) returns boolean
language plpgsql immutable set search_path = '' as $f$
declare c jsonb; ok boolean;
begin
  if p_cond is null or p_cond = '{}'::jsonb then return true; end if;
  for c in select * from jsonb_array_elements(coalesce(p_cond -> 'all', '[]')) loop
    if not b2c.cond_true(c, p_facts) then return false; end if;
  end loop;
  if jsonb_array_length(coalesce(p_cond -> 'any', '[]')) > 0 then
    ok := false;
    for c in select * from jsonb_array_elements(p_cond -> 'any') loop
      if b2c.cond_true(c, p_facts) then ok := true; exit; end if;
    end loop;
    return ok;
  end if;
  return true;
end $f$;

create or replace function b2c.cond_true(c jsonb, f jsonb) returns boolean language plpgsql immutable set search_path = '' as $f$
declare v jsonb := f -> (c ->> 'field'); t text := lower(f ->> (c ->> 'field')); x text := lower(c ->> 'value'); op text := c ->> 'op';
begin
  return case op
    when 'eq' then t = x
    when 'neq' then t is distinct from x
    when 'in' then t in (select lower(e) from jsonb_array_elements_text(c -> 'value') e)
    when 'not_in' then t is null or t not in (select lower(e) from jsonb_array_elements_text(c -> 'value') e)
    when 'contains' then t like '%' || x || '%'
    when 'gte' then (v #>> '{}')::numeric >= (c ->> 'value')::numeric
    when 'lte' then (v #>> '{}')::numeric <= (c ->> 'value')::numeric
    when 'is_true' then coalesce((v #>> '{}')::boolean, false)
    when 'is_false' then not coalesce((v #>> '{}')::boolean, false)
    when 'is_null' then v is null or v = 'null'::jsonb or t = ''
    when 'not_null' then not (v is null or v = 'null'::jsonb or t = '')
    else false end;
exception when others then return false;
end $f$;

/* What the rules see about a lead. */
create or replace function b2c.lead_facts(p_lead bigint, p_trigger text, p_at timestamptz default now()) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
    'lane', s.lane, 'reason', s.handoff_reason, 'cause', s.cause, 'trigger', p_trigger,
    'assignment_hint', s.handling ->> 'assignment', 'script', s.handling ->> 'first_contact_script',
    'source', r.record -> 'source' ->> 'lead_source', 'campaign', r.record -> 'source' ->> 'campaign',
    'paid', coalesce((r.record -> 'campaign' ->> 'paid')::boolean, false),
    'course', r.record -> 'interest' ->> 'course', 'university', r.record -> 'interest' ->> 'university',
    'level', r.record -> 'interest' ->> 'programme_level', 'mode', r.record -> 'interest' ->> 'study_mode',
    'city', r.record -> 'student' ->> 'city', 'state', r.record -> 'student' ->> 'state',
    'language', r.record -> 'student' ->> 'preferred_language',
    'temperature', coalesce(s.temperature, case when s.hot then 'hot' end), 'score', s.score, 'hot', s.hot,
    'lost_by', s.lost_by, 'partner_barred', s.partner_bar_reason is not null,
    'is_test', s.is_test or coalesce(r.is_test, false),
    'hour', extract(hour from p_at at time zone 'Asia/Kolkata')::int)
  from b2c.leads_state s left join b2c.lead_records r on r.lead_id = s.lead_id where s.lead_id = p_lead
$f$;

-- ---------- load counters (live, or a simulation's own) ----------
create or replace function b2c.load_of(p_user uuid, p_at timestamptz, p_sim boolean) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_month int; v_open int; v_day int; v_m date := date_trunc('month', p_at at time zone 'Asia/Kolkata')::date; v_d date := (p_at at time zone 'Asia/Kolkata')::date;
begin
  if p_sim then
    select coalesce(sum(n) filter (where m = v_m), 0), coalesce(sum(n) filter (where d = v_d), 0) into v_month, v_day from pg_temp.sim_load where user_id = p_user;
    return jsonb_build_object('month', v_month, 'open', 0, 'day', v_day);
  end if;
  select count(*) filter (where (a.at at time zone 'Asia/Kolkata')::date >= v_m),
         count(*) filter (where (a.at at time zone 'Asia/Kolkata')::date = v_d)
    into v_month, v_day from b2c.assignments a where a.user_id = p_user and a.at >= (v_m - 1);
  select count(*) into v_open from b2c.leads_state s where s.owner_id = p_user and s.status = 'active' and s.deleted_at is null;
  return jsonb_build_object('month', v_month, 'open', v_open, 'day', v_day);
end $f$;

/* Why this person cannot take this lead now (null = eligible). 'waits' = eligible, outside hours, non-hot. */
create or replace function b2c.ineligible(u b2c.users, p_facts jsonb, p_at timestamptz, p_hot boolean, p_sim boolean) returns text
language plpgsql stable security definer set search_path = '' as $f$
declare l jsonb; v_test boolean := coalesce((p_facts ->> 'is_test')::boolean, false); a jsonb := b2c.setting('allocation');
begin
  if not u.is_active then return 'inactive'; end if;
  if u.role = 'marketing' then return 'marketing'; end if;
  if u.role = 'admin' and not (u.takes_leads and coalesce((a ->> 'admin_takes_leads')::boolean, true)) then return 'admin does not take leads'; end if;
  if v_test and not (u.is_test_user or u.role = 'admin') then return 'test lead'; end if;
  if not v_test and u.is_test_user then return 'test user'; end if;
  if exists (select 1 from b2c.leaves lv where lv.user_id = u.user_id and b2c.local_day(u.user_id, p_at) between lv.from_day and lv.to_day) then return 'on leave'; end if;
  if u.away_until > p_at then return 'away'; end if;
  l := b2c.load_of(u.user_id, p_at, p_sim);
  if (l ->> 'month')::int >= u.monthly_cap then return 'monthly cap'; end if;
  if u.open_cap is not null and (l ->> 'open')::int >= u.open_cap then return 'open-lead cap'; end if;
  if u.daily_cap is not null and (l ->> 'day')::int >= u.daily_cap then return 'daily cap'; end if;
  if not b2c.working_now(u.user_id, p_at) then
    if p_hot then return 'off hours'; end if;
    if not coalesce((a ->> 'allow_outside_hours_non_hot')::boolean, true) then return 'off hours'; end if;
  end if;
  return null;
end $f$;

/* Pure decision: which rule, which person, and why. Writes nothing (except a simulation's own turn counters). */
create or replace function b2c.decide(p_lead bigint, p_trigger text, p_at timestamptz default now(), p_exclude uuid default null, p_sim boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  f jsonb := b2c.lead_facts(p_lead, p_trigger, p_at);
  s b2c.leads_state; r b2c.allocation_rules; u b2c.users;
  v_hot boolean; v_why text; v_cands jsonb; v_skip jsonb; v_chosen uuid; v_turn int; v_n int; v_i int; v_fb text;
  v_ids uuid[]; v_ok uuid[]; v_match text[]; v_pool text; v_tried jsonb := '[]'::jsonb;
begin
  if f is null then return jsonb_build_object('outcome', 'skipped', 'why', 'unknown lead'); end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_hot := coalesce(s.hot, false) or p_trigger in ('reengaged', 're_enquiry_hot');
  for r in select * from b2c.allocation_rules where enabled and applies_from <= p_at order by position, id loop
    continue when not b2c.rule_matches(r.condition, f);
    v_pool := coalesce((select p.name from b2c.pools p where p.id = r.pool_id), 'Everyone');
    -- the pool, in a stable order
    select array_agg(x.user_id order by x.pos, x.email) into v_ids from (
      select u2.user_id, coalesce(pm.position, 0) pos, u2.email from b2c.users u2
        left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = u2.user_id
       where (r.pool_id is null or pm.user_id is not null) and u2.user_id is distinct from p_exclude) x;
    v_cands := '[]'; v_skip := '[]'; v_ok := '{}';
    foreach v_chosen in array coalesce(v_ids, '{}') loop
      select * into u from b2c.users where user_id = v_chosen;
      v_why := b2c.ineligible(u, f, p_at, v_hot, p_sim);
      -- skill and territory logics narrow the pool
      if v_why is null and r.logic = 'skill_match' then
        v_match := array(select jsonb_array_elements_text(coalesce(r.params -> 'match', '["language"]')));
        if 'language' = any (v_match) and f ->> 'language' is not null and not exists (select 1 from unnest(u.languages) g where lower(g) = lower(f ->> 'language')) then v_why := 'language'; end if;
        if v_why is null and 'programme' = any (v_match) and f ->> 'course' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'programmes', '[]')) g where lower(f ->> 'course') like '%' || lower(g) || '%') then v_why := 'programme skill'; end if;
        if v_why is null and 'university' = any (v_match) and f ->> 'university' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'universities', '[]')) g where lower(g) = lower(f ->> 'university')) then v_why := 'university skill'; end if;
        if v_why is null and 'level' = any (v_match) and f ->> 'level' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'levels', '[]')) g where lower(g) = lower(f ->> 'level')) then v_why := 'level skill'; end if;
      elsif v_why is null and r.logic = 'territory' then
        if not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'territories', '[]')) g where lower(g) in (lower(f ->> 'city'), lower(f ->> 'state'))) then v_why := 'territory'; end if;
      end if;
      if v_why is null then v_ok := v_ok || v_chosen; v_cands := v_cands || jsonb_build_object('user_id', v_chosen, 'name', u.full_name);
      else v_skip := v_skip || jsonb_build_object('user_id', v_chosen, 'name', u.full_name, 'why', v_why); end if;
    end loop;

    v_chosen := null; v_turn := null;
    if r.logic = 'manual' then
      return jsonb_build_object('outcome', 'manual_queue', 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'manual queue');
    elsif r.logic = 'returning' then
      if coalesce(s.previous_owner_id, s.lost_by_user) = any (v_ok) then v_chosen := coalesce(s.previous_owner_id, s.lost_by_user); end if;
      if v_chosen is null then v_tried := v_tried || jsonb_build_object('rule', r.name, 'why', 'previous counsellor not eligible'); continue; end if;
    elsif cardinality(v_ok) > 0 then
      if r.logic in ('round_robin', 'pinning', 'skill_match', 'territory') then
        v_turn := r.turn;
        if p_sim then
          execute 'select turn from pg_temp.sim_turns where rule_id = $1' into v_turn using r.id;
          v_turn := coalesce(v_turn, r.turn);
        end if;
        v_n := cardinality(v_ids);
        for v_i in 1 .. v_n loop
          if v_ids[((v_turn + v_i) % v_n) + 1] = any (v_ok) then v_chosen := v_ids[((v_turn + v_i) % v_n) + 1]; v_turn := (v_turn + v_i) % v_n; exit; end if;
        end loop;
      elsif r.logic in ('weighted_round_robin', 'performance') then
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce(pm.weight, uu.weight, 1), 1) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = c.uid) x
         order by x.score, x.email limit 1;
      elsif r.logic = 'least_loaded' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> case when p_sim then 'month' else 'open' end)::int n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      elsif r.logic = 'capacity' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(uu.monthly_cap, 1) n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      end if;
    end if;

    if v_chosen is not null then
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'turn', v_turn, 'hot', v_hot, 'facts', f, 'tried', v_tried);
    end if;
    -- nobody eligible under this rule: its fallbacks, in order
    v_tried := v_tried || jsonb_build_object('rule', r.name, 'skipped', v_skip);
    for v_fb in select jsonb_array_elements_text(r.fallbacks) loop
      if v_fb = 'next_rule' then exit;
      elsif v_fb = 'on_call' then
        select uu.user_id into v_chosen from b2c.users uu
         where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
           and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
           and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
         order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'on-call fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'admin' then
        select uu.user_id into v_chosen from b2c.users uu where uu.role = 'admin' and uu.is_active and uu.takes_leads and uu.user_id is distinct from p_exclude order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'admin',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'Admin fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'unassigned' then
        return b2c.decide_none(f, v_hot, v_tried, r, v_pool, v_cands, v_skip, p_exclude, p_at);
      end if;
    end loop;
  end loop;
  return b2c.decide_none(f, v_hot, v_tried, null, null, '[]', '[]', p_exclude, p_at);
end $f$;

/* Nobody eligible anywhere: "Admin takes leads" → the Admin; hot and everyone off hours → wait for working hours;
   otherwise the Unassigned queue. */
create or replace function b2c.decide_none(f jsonb, p_hot boolean, p_tried jsonb, r b2c.allocation_rules, p_pool text, p_cands jsonb, p_skip jsonb,
                                           p_exclude uuid, p_at timestamptz) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_admin uuid; v_offhours boolean;
begin
  if coalesce((b2c.setting('allocation') ->> 'admin_takes_leads')::boolean, true) then
    select u.user_id into v_admin from b2c.users u where u.role = 'admin' and u.is_active and u.takes_leads and u.user_id is distinct from p_exclude order by u.email limit 1;
    if v_admin is not null then
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_admin, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'admin_takes_leads',
                                'pool', p_pool, 'eligible', p_cands, 'skipped', p_skip, 'hot', p_hot, 'facts', f, 'why', 'Admin takes leads', 'tried', p_tried);
    end if;
  end if;
  select bool_and(x ->> 'why' = 'off hours') into v_offhours from jsonb_array_elements(p_skip) x where x ->> 'why' not in ('test user', 'test lead', 'marketing');
  return jsonb_build_object('outcome', case when p_hot and coalesce(v_offhours, false) then 'waiting_hours' else 'unassigned' end,
                            'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', p_pool, 'eligible', p_cands, 'skipped', p_skip,
                            'hot', p_hot, 'facts', f, 'why', 'nobody eligible', 'tried', p_tried);
end $f$;

-- ---------- assigning ----------
create or replace function b2c.assign(p_lead bigint, p_user uuid, p_decision bigint, p_trigger text, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare
  s b2c.leads_state; u b2c.users; v_sub text; v_sla int; v_due timestamptz; v_start timestamptz; v_in_hours boolean; v_name text;
  m jsonb := b2c.setting('sla_minutes');
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  select * into u from b2c.users where user_id = p_user;
  update b2c.assignments set ended_at = now(), end_reason = coalesce(p_reason, p_trigger) where lead_id = p_lead and ended_at is null;
  insert into b2c.assignments (lead_id, user_id, decision_id, trigger, reason, by_user) values (p_lead, p_user, p_decision, p_trigger, p_reason, b2c.uid());
  v_sub := case p_trigger when 'reengaged' then 'Re-engaged from nurture' when 're_enquiry' then 'Re-enquiry' when 'created' then 'Created by me'
                          when 'returned_from_partners' then 'Returned from partners' else 'Fresh assignment' end;
  v_sla := case when s.hot or p_trigger = 'reengaged' then (m ->> 'hot')::int
                when coalesce(s.temperature, '') = 'warm' then (m ->> 'warm')::int else coalesce((m ->> 'cold')::int, 1440) end;
  if s.temperature is null and not s.hot and p_trigger <> 'reengaged' then v_sla := (m ->> 'warm')::int; end if;
  v_in_hours := b2c.working_now(p_user, now());
  v_start := coalesce(b2c.next_working_at(p_user, now()), now());
  v_due := coalesce(b2c.add_working_minutes(p_user, now(), v_sla), now() + make_interval(mins => v_sla));
  update b2c.leads_state set
    owner_id = p_user, assigned_at = now(), status = 'active',
    previous_owner_id = case when s.owner_id is distinct from p_user then coalesce(s.owner_id, s.previous_owner_id) else s.previous_owner_id end,
    stage_id = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then 1 else s.stage_id end,
    sub_stage = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then v_sub else s.sub_stage end,
    stage_changed_at = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then now() else s.stage_changed_at end,
    hot = s.hot or p_trigger = 'reengaged',
    reengaged_at = case when p_trigger = 'reengaged' then now() else s.reengaged_at end,
    journey = null,
    sla_due_at = case when s.first_contacted_at is null or p_trigger = 'reengaged' then v_due else s.sla_due_at end,
    sla_met_at = case when p_trigger = 'reengaged' then null else s.sla_met_at end,
    sla_breached_at = case when p_trigger = 'reengaged' then null else s.sla_breached_at end,
    next_task_due_at = v_due, updated_at = now()
  where lead_id = p_lead;
  update b2c.tasks set owner_id = p_user where lead_id = p_lead and status = 'open';
  insert into b2c.tasks (lead_id, owner_id, kind, title, due_at, suggested, source)
  select p_lead, p_user, 'call', case when s.handling ->> 'first_contact_script' = 'neutral_adviser' then 'First call: neutral-adviser opening' else 'First call' end,
         v_due, false, 'assignment'
   where not exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.status = 'open' and t.kind = 'call');
  select st.name into v_name from b2c.stages st join b2c.leads_state x on x.stage_id = st.id where x.lead_id = p_lead;
  perform b2c.queue_update(p_lead, jsonb_build_object(
    'owner_user_id', p_user, 'owner_name', u.full_name, 'assigned_at', now(), 'stage', 'assigned', 'stage_changed_at', now(),
    'sub_stage', left(v_sub, 80), 'b2c_stage', v_name, 'b2c_sub_stage', v_sub, 'next_task_due_at', v_due), false);
  insert into b2c.activities (lead_id, kind, body, meta, actor_id, at)
  values (p_lead, 'assignment', 'Assigned to ' || coalesce(u.full_name, u.email) || coalesce(' (' || p_reason || ')', ''),
          jsonb_build_object('decision_id', p_decision, 'trigger', p_trigger), b2c.uid(), now());
  perform b2c.notify(p_user, case when p_trigger = 'reengaged' then 'reengaged' else 'assigned' end,
                     case when p_trigger = 'reengaged' then 'Hot: a nurtured lead re-engaged' else 'New lead assigned' end,
                     coalesce(s.reengage_trigger, s.handoff_reason), '/s/leads/' || p_lead, p_lead, 'assign:' || p_lead || ':' || coalesce(p_decision, 0));
  perform b2c.queue_assignment_message(p_lead, p_user, v_in_hours, v_start);
end $f$;

/* Decide and act. Keeps a current owner who is still active (re-enquiry, a returned lead). */
create or replace function b2c.allocate(p_lead bigint, p_trigger text, p_exclude uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare s b2c.leads_state; d jsonb; v_id bigint; v_creator uuid;
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null or s.deleted_at is not null or s.status = 'closed' then return jsonb_build_object('outcome', 'skipped'); end if;
  if s.owner_id is not null and p_exclude is null and p_trigger not in ('reassign', 'hand_back')
     and exists (select 1 from b2c.users u where u.user_id = s.owner_id and u.is_active) then
    insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, s.owner_id, 'kept', 'already with an active counsellor')
    returning id into v_id;
    if p_trigger = 'returned_from_partners' then
      perform b2c.assign(p_lead, s.owner_id, v_id, p_trigger, 'no partner took it');
    else
      perform b2c.notify(s.owner_id, 'reenquiry', 'Your lead came back', p_trigger, '/s/leads/' || p_lead, p_lead, 'kept:' || v_id);
    end if;
    return jsonb_build_object('outcome', 'kept', 'chosen', s.owner_id, 'decision_id', v_id);
  end if;
  -- B4.3: a lead created in B2C goes to the person who created it (the Intake answer names the lead; wait up to 2 minutes for it)
  if s.handoff_reason = 'b2c_created' and p_exclude is null and p_trigger in ('handoff', 'retry') then
    select c.user_id into v_creator from b2c.created_leads c join b2c.users u on u.user_id = c.user_id and u.is_active
     where c.lead_id = p_lead order by c.created_at desc limit 1;
    if v_creator is not null then
      insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, v_creator, 'assigned', 'created by this counsellor')
      returning id into v_id;
      perform b2c.assign(p_lead, v_creator, v_id, 'created', 'created by them');
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_creator, 'decision_id', v_id, 'why', 'created by this counsellor');
    elsif s.handed_off_at > now() - interval '2 minutes' then
      return jsonb_build_object('outcome', 'skipped', 'why', 'waiting for the creating counsellor');
    end if;
  end if;
  d := b2c.decide(p_lead, p_trigger, now(), p_exclude, false);
  insert into b2c.allocation_decisions (lead_id, trigger, hot, facts, rule_id, rule_name, logic, pool, eligible, skipped, chosen, turn, outcome, why)
  values (p_lead, p_trigger, coalesce((d ->> 'hot')::boolean, false), coalesce(d -> 'facts', '{}'), (d ->> 'rule_id')::bigint, d ->> 'rule_name', d ->> 'logic',
          d ->> 'pool', coalesce(d -> 'eligible', '[]'), coalesce(d -> 'skipped', '[]'), (d ->> 'chosen')::uuid, (d ->> 'turn')::int, d ->> 'outcome',
          coalesce(d ->> 'why', (select string_agg(t ->> 'rule' || ': ' || coalesce(t ->> 'why', 'nobody eligible'), '; ') from jsonb_array_elements(d -> 'tried') t)))
  returning id into v_id;
  if d ->> 'outcome' = 'assigned' then
    if d ->> 'turn' is not null then update b2c.allocation_rules set turn = (d ->> 'turn')::int where id = (d ->> 'rule_id')::bigint; end if;
    perform b2c.assign(p_lead, (d ->> 'chosen')::uuid, v_id, p_trigger, d ->> 'rule_name');
  else
    update b2c.leads_state set owner_id = null, status = 'active', updated_at = now() where lead_id = p_lead and status <> 'closed';
  end if;
  return d - 'facts' || jsonb_build_object('decision_id', v_id);
end $f$;

/* A pooled lead shows interest again (B6.3): journey stops, hot, allocated. */
create or replace function b2c.reengage(p_lead bigint, p_trigger text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.leads_state set status = 'active', hot = true, reengaged_at = now(), reengage_trigger = p_trigger, journey = null, updated_at = now()
   where lead_id = p_lead and status = 'pool';
  if not found then return jsonb_build_object('outcome', 'skipped', 'why', 'not in the pool'); end if;
  insert into b2c.activities (lead_id, kind, body, meta, at) values (p_lead, 'reengaged', 'Re-engaged: ' || p_trigger, jsonb_build_object('trigger', p_trigger), now());
  return b2c.allocate(p_lead, 'reengaged');
end $f$;

/* Admin or sales head: reassign leads to a person, or by the rules (p_user null). */
create or replace function b2c.reassign(p_leads bigint[], p_user uuid, p_reason text) returns int
language plpgsql security definer set search_path = '' as $f$
declare v bigint; n int := 0; v_d bigint;
begin
  perform b2c.require('reassign');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason'; end if;
  foreach v in array p_leads loop
    if p_user is null then perform b2c.allocate(v, 'reassign', (select owner_id from b2c.leads_state where lead_id = v));
    else
      if not exists (select 1 from b2c.users where user_id = p_user and is_active and role in ('counsellor', 'sales_head', 'admin')) then raise exception 'not an active counsellor'; end if;
      insert into b2c.allocation_decisions (lead_id, trigger, chosen, outcome, why) values (v, 'reassign', p_user, 'assigned', 'manual: ' || p_reason) returning id into v_d;
      perform b2c.assign(v, p_user, v_d, 'reassign', p_reason);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

/* A counsellor hands a lead back with a reason; the rules reassign it to someone else (B7.5). */
create or replace function b2c.hand_back(p_lead bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads');
begin
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead and owner_id = me) then raise exception 'not your lead'; end if;
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason'; end if;
  insert into b2c.activities (lead_id, kind, body, actor_id, at) values (p_lead, 'assignment', 'Handed back: ' || p_reason, me, now());
  return b2c.allocate(p_lead, 'hand_back', me);
end $f$;

/* Every minute: unassigned and waiting leads get another try; alert when a sales lead waits > N minutes in working
   hours; leave with "reassign after N hours" moves the person's open leads. */
create or replace function b2c.allocation_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0; v_alert int := coalesce((b2c.setting('allocation') ->> 'unassigned_alert_minutes')::int, 5);
begin
  for r in select lead_id, handed_off_at from b2c.leads_state where status = 'active' and owner_id is null and deleted_at is null order by handed_off_at limit 100 loop
    perform b2c.allocate(r.lead_id, 'retry'); n := n + 1;
    if not exists (select 1 from b2c.leads_state where lead_id = r.lead_id and owner_id is not null)
       and r.handed_off_at < now() - make_interval(mins => v_alert) and b2c.working_now(null, now()) then
      perform b2c.notify_admins('unassigned', 'A sales lead is waiting unassigned', 'Waiting since ' || to_char(r.handed_off_at at time zone 'Asia/Kolkata', 'HH24:MI'),
                                '/w/allocation', r.lead_id, 'unassigned:' || r.lead_id || ':' || to_char(now(), 'YYYYMMDDHH24'));
    end if;
  end loop;
  for r in select lv.id, lv.user_id from b2c.leaves lv
            where lv.mode = 'reassign' and lv.reassigned_at is null and current_date between lv.from_day and lv.to_day
              and (lv.from_day::timestamp at time zone 'Asia/Kolkata') + make_interval(hours => coalesce(lv.reassign_after_hours, 0)) <= now() loop
    perform b2c.allocate(s.lead_id, 'leave', r.user_id) from b2c.leads_state s where s.owner_id = r.user_id and s.status = 'active';
    update b2c.leaves set reassigned_at = now() where id = r.id;
  end loop;
  return jsonb_build_object('retried', n);
end $f$;

/* Replays the leads handed over (or re-engaged) in a date range through the current rules, without assigning anything,
   and compares with what really happened (B7.4). */
create or replace function b2c.simulate(p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; d jsonb; v_rows jsonb;
begin
  perform b2c.require('settings');
  create temp table if not exists sim_load (user_id uuid, m date, d date, n int) on commit drop;
  create temp table if not exists sim_turns (rule_id bigint primary key, turn int) on commit drop;
  create temp table if not exists sim_out (lead_id bigint, actual uuid, simulated uuid, outcome text, rule text) on commit drop;
  truncate pg_temp.sim_load, pg_temp.sim_turns, pg_temp.sim_out;
  for r in select s.lead_id, coalesce(a.at, s.handed_off_at) at, a.user_id actual, a.trigger
             from b2c.leads_state s
             left join lateral (select x.at, x.user_id, x.trigger from b2c.assignments x where x.lead_id = s.lead_id order by x.at limit 1) a on true
            where coalesce(a.at, s.handed_off_at) >= p_from and coalesce(a.at, s.handed_off_at) < p_to + 1 and not s.is_test
            order by 2 loop
    d := b2c.decide(r.lead_id, coalesce(r.trigger, 'handoff'), r.at, null, true);
    if d ->> 'outcome' = 'assigned' then
      insert into pg_temp.sim_load values ((d ->> 'chosen')::uuid, date_trunc('month', r.at at time zone 'Asia/Kolkata')::date, (r.at at time zone 'Asia/Kolkata')::date, 1);
      if d ->> 'turn' is not null then
        insert into pg_temp.sim_turns values ((d ->> 'rule_id')::bigint, (d ->> 'turn')::int) on conflict (rule_id) do update set turn = excluded.turn;
      end if;
    end if;
    insert into pg_temp.sim_out values (r.lead_id, r.actual, (d ->> 'chosen')::uuid, d ->> 'outcome', d ->> 'rule_name');
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('user_id', x.uid, 'name', u.full_name, 'actual', x.actual, 'simulated', x.simulated) order by u.full_name), '[]')
    into v_rows
    from (select coalesce(a.uid, s.uid) uid, coalesce(a.n, 0) actual, coalesce(s.n, 0) simulated
            from (select actual uid, count(*) n from pg_temp.sim_out where actual is not null group by 1) a
            full join (select simulated uid, count(*) n from pg_temp.sim_out where simulated is not null group by 1) s on s.uid = a.uid) x
    left join b2c.users u on u.user_id = x.uid;
  return jsonb_build_object('leads', (select count(*) from pg_temp.sim_out), 'unassigned', (select count(*) from pg_temp.sim_out where simulated is null),
                            'by_person', v_rows);
end $f$;

-- ---------- Admin edits of rules, pools and calendars ----------
create or replace function b2c.rule_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; me uuid := b2c.require('settings');
begin
  if coalesce(p ->> 'name', '') = '' then raise exception 'name the rule'; end if;
  if p ? 'condition' and jsonb_typeof(p -> 'condition') <> 'object' then raise exception 'a rule condition is an object: {"all": […], "any": […]}'; end if;
  if p ? 'fallbacks' and jsonb_typeof(p -> 'fallbacks') <> 'array' then raise exception 'fallbacks are a list'; end if;
  if v_id is null then
    insert into b2c.allocation_rules (position, name, enabled, condition, logic, params, pool_id, fallbacks, applies_from, actor_id)
    values (coalesce((p ->> 'position')::int, (select coalesce(max(position), 0) + 10 from b2c.allocation_rules where not is_catch_all)),
            p ->> 'name', coalesce((p ->> 'enabled')::boolean, true), coalesce(p -> 'condition', '{}'), coalesce(p ->> 'logic', 'round_robin'),
            coalesce(p -> 'params', '{}'), nullif(p ->> 'pool_id', '')::bigint, coalesce(p -> 'fallbacks', '["next_rule"]'),
            coalesce(nullif(p ->> 'applies_from', '')::timestamptz, now()), me)
    returning id into v_id;
  else
    update b2c.allocation_rules set name = p ->> 'name', enabled = coalesce((p ->> 'enabled')::boolean, enabled),
           condition = coalesce(p -> 'condition', condition), logic = coalesce(p ->> 'logic', logic), params = coalesce(p -> 'params', params),
           pool_id = case when p ? 'pool_id' then nullif(p ->> 'pool_id', '')::bigint else pool_id end,
           fallbacks = coalesce(p -> 'fallbacks', fallbacks), applies_from = coalesce(nullif(p ->> 'applies_from', '')::timestamptz, applies_from),
           position = coalesce((p ->> 'position')::int, position), updated_at = now(), actor_id = me
     where id = v_id;
  end if;
  perform b2c.log('allocation.rule_saved', null, p);
  return v_id;
end $f$;

create or replace function b2c.rules_reorder(p_ids bigint[]) returns void language plpgsql security definer set search_path = '' as $f$
declare i int;
begin
  perform b2c.require('settings');
  for i in 1 .. cardinality(p_ids) loop
    update b2c.allocation_rules set position = i * 10, updated_at = now() where id = p_ids[i] and not is_catch_all;
  end loop;
end $f$;

create or replace function b2c.pool_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; m jsonb; i int := 0;
begin
  perform b2c.require('settings');
  if v_id is null then insert into b2c.pools (name, description) values (p ->> 'name', p ->> 'description') returning id into v_id;
  else update b2c.pools set name = coalesce(p ->> 'name', name), description = p ->> 'description' where id = v_id; end if;
  if p ? 'members' then
    delete from b2c.pool_members where pool_id = v_id;
    for m in select * from jsonb_array_elements(p -> 'members') loop
      insert into b2c.pool_members (pool_id, user_id, weight, position) values (v_id, (m ->> 'user_id')::uuid, coalesce((m ->> 'weight')::int, 1), i);
      i := i + 1;
    end loop;
  end if;
  return v_id;
end $f$;

create or replace function b2c.calendar_save(p_user uuid, p_patterns jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare x jsonb;
begin
  perform b2c.require('settings');
  delete from b2c.work_patterns where user_id = p_user;
  for x in select * from jsonb_array_elements(coalesce(p_patterns, '[]')) loop
    insert into b2c.work_patterns (user_id, isodow, start_t, end_t) values (p_user, (x ->> 'isodow')::smallint, (x ->> 'start')::time, (x ->> 'end')::time);
  end loop;
end $f$;

create or replace function b2c.leave_add(p_user uuid, p_from date, p_to date, p_mode text, p_after int, p_reason text) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v bigint;
begin
  perform b2c.require('settings');
  insert into b2c.leaves (user_id, from_day, to_day, mode, reassign_after_hours, reason, created_by)
  values (p_user, p_from, p_to, coalesce(p_mode, 'hold'), p_after, p_reason, b2c.uid()) returning id into v;
  return v;
end $f$;

create or replace function b2c.holiday_save(p_day date, p_name text, p_kind text default 'company') returns void
language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  insert into b2c.holidays (day, name, kind) values (p_day, p_name, coalesce(p_kind, 'company')) on conflict (day) do update set name = excluded.name, kind = excluded.kind;
end $f$;

/* A counsellor's own availability toggle (B7.1). */
create or replace function b2c.set_away(p_minutes int) returns timestamptz language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); v timestamptz;
begin
  v := case when p_minutes is null or p_minutes <= 0 then null when p_minutes >= 1440 then (date_trunc('day', now() at time zone 'Asia/Kolkata') + interval '1 day') at time zone 'Asia/Kolkata'
            else now() + make_interval(mins => p_minutes) end;
  update b2c.users set away_until = v, updated_at = now() where user_id = me;
  return v;
end $f$;

-- Indian national holidays (gazetted, 2026–27) as a starting list; the Admin edits it.
insert into b2c.holidays (day, name, kind) values
  ('2026-10-02', 'Gandhi Jayanti', 'national'), ('2026-10-20', 'Dussehra', 'national'), ('2026-11-08', 'Diwali', 'national'),
  ('2026-12-25', 'Christmas', 'national'), ('2027-01-26', 'Republic Day', 'national'), ('2027-08-15', 'Independence Day', 'national')
on conflict (day) do nothing;

-- ---------- grants ----------
grant execute on function b2c.working_now(uuid, timestamptz), b2c.next_working_at(uuid, timestamptz), b2c.reassign(bigint[], uuid, text),
  b2c.hand_back(bigint, text), b2c.simulate(date, date), b2c.rule_save(jsonb), b2c.rules_reorder(bigint[]), b2c.pool_save(jsonb),
  b2c.calendar_save(uuid, jsonb), b2c.leave_add(uuid, date, date, text, int, text), b2c.holiday_save(date, text, text), b2c.set_away(int) to authenticated;
revoke execute on function b2c.allocate(bigint, text, uuid), b2c.assign(bigint, uuid, bigint, text, text), b2c.decide(bigint, text, timestamptz, uuid, boolean),
  b2c.reengage(bigint, text), b2c.allocation_tick() from public, authenticated;
grant execute on function b2c.allocation_tick() to service_role;
grant all on all tables in schema b2c to service_role;
