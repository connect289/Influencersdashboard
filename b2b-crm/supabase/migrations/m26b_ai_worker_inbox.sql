-- M26b: Claude as the allocation optimiser, part 2: the worker's API, the schedule, the Advisory inbox.
-- The worker (Next.js route /v1/ai/tick, server-side, ANTHROPIC_API_KEY in its environment) authenticates with an API key
-- of scope ai_worker and only ever: claims a queued run (budget permitting), calls ai_tool for data, and finishes the run
-- with its output and token usage. The database prices the run, checks every proposed change against the bounds
-- (ai_validate_change), attaches a deterministic simulation to each one and files it in the inbox. Nothing is applied until
-- the Admin approves it (Advisory). Never touched by any AI path: consent, duplicate and attempt rules, the B2C fallback,
-- capacity and contracts, commission rates, live switches, students and partners.
--   ai_schedule_tick()   every 5 minutes: queues light checks (new alerts), the hourly optimisation (when decisions or
--                        outcomes changed), the nightly deep review (01:00 IST), the weekly report (Monday 09:00 IST) and
--                        event runs; pings the worker when something is queued; queues nothing once the daily budget is
--                        spent (one alert a day)
--   ai_recommendation_decide(id, approve|reject, note, edited change)   applies through engine_policy (source 'ai', versioned
--                        with the run and the approver); rule drafts become inactive rules; pause drafts pause the partner
--   ai_recommendation_rollback(id, reason)   restores what the change replaced

create table if not exists b2b.ai_state (
  key        text primary key,
  value      jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table b2b.ai_state enable row level security;
revoke all on b2b.ai_state from public, anon, authenticated;
grant all on b2b.ai_state to service_role;

create or replace function b2b.ai_cfg()
returns jsonb language sql stable set search_path = '' as $fn$
  select coalesce((select value from b2b.settings where key = 'ai'), '{}');
$fn$;

/* Spent today (IST) and this month, from the run log. */
create or replace function b2b.ai_spend()
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_object(
    'today_usd', coalesce((select round(sum(cost_usd), 4) from b2b.ai_runs where created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'), 0),
    'month_usd', coalesce((select round(sum(cost_usd), 4) from b2b.ai_runs where created_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'), 0));
$fn$;

/* The price of a model in dollars per million tokens {in, out, cache_read, cache_write}, from settings ai.prices_per_mtok. */
create or replace function b2b.ai_price(p_model text) returns jsonb language sql stable security definer set search_path = '' as $fn$
  with p as (select coalesce(b2b.ai_cfg() -> 'prices_per_mtok', '{}') t)
  select coalesce(
    (select t -> p_model from p where jsonb_typeof(t -> p_model) = 'object'),
    -- an unlisted model is priced at the dearest listed rates, so the budget is never under-counted
    (select jsonb_build_object('in', max((x ->> 'in')::numeric), 'out', max((x ->> 'out')::numeric),
                               'cache_read', max(coalesce((x ->> 'cache_read')::numeric, 0)), 'cache_write', max(coalesce((x ->> 'cache_write')::numeric, 0)))
       from p, jsonb_each(p.t) e(k, x) where jsonb_typeof(x) = 'object' having count(*) > 0),
    '{"in":4,"out":20,"cache_read":0.2,"cache_write":5}'::jsonb);
$fn$;
revoke execute on function b2b.ai_price(text) from public, anon, authenticated;
grant execute on function b2b.ai_price(text) to service_role;

/* A proposed change, checked against the levers and bounds of B7.8.2; returns it normalised or raises 22023. */
create or replace function b2b.ai_validate_change(p jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  v_lever text := p ->> 'lever';
  v_until timestamptz;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'no change given' using errcode = '22023'; end if;
  if v_lever in ('exploration_share', 'segment_pin', 'share_cap') and (p ->> 'segment' is null or p ->> 'segment' !~ '^[^|]+\|[^|]+\|[^|]+$') then
    raise exception 'the change needs a segment (course|level|mode)' using errcode = '22023';
  end if;
  -- a value of the wrong type (text for a number, a bad date or id) is a refusal like any other, not a server error
  begin
    case v_lever
    when 'exploration_share' then
      if not ((p ->> 'value')::numeric between 0 and 0.5) then raise exception 'exploration share is 0 to 50%%' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'segment', p ->> 'segment', 'value', round((p ->> 'value')::numeric, 3));
    when 'maturity_days' then
      if not ((p ->> 'value')::int between 30 and 90) then raise exception 'maturity is 30 to 90 days for the AI' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', (p ->> 'value')::int);
    when 'half_life_days' then
      if not ((p ->> 'value')::int between 14 and 60) then raise exception 'the half-life is 14 to 60 days for the AI' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', (p ->> 'value')::int);
    when 'prior_weight' then
      if not ((p ->> 'value')::numeric between 5 and 50) then raise exception 'prior strength is 5 to 50 leads for the AI' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', round((p ->> 'value')::numeric, 1));
    when 'segment_pin' then
      if p ->> 'value' not in ('commission_first', 'performance') then raise exception 'a pin is commission_first or performance' using errcode = '22023'; end if;
      v_until := coalesce(nullif(p ->> 'until', '')::timestamptz, now() + interval '30 days');
      if v_until <= now() or v_until > now() + interval '30 days 1 hour' then raise exception 'an AI pin expires within 30 days' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'segment', p ->> 'segment', 'value', p ->> 'value', 'until', v_until);
    when 'speed_factor', 'reliability_factor' then
      if jsonb_typeof(p -> 'value') <> 'boolean' then raise exception 'the factor is on or off' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', (p ->> 'value')::boolean);
    when 'partner_weight' then
      if not exists (select 1 from b2b.partners where id = (p ->> 'partner_id')::bigint and status = 'active') then raise exception 'unknown or inactive partner' using errcode = '22023'; end if;
      if not ((p ->> 'value')::numeric between 0.9 and 1.1) then raise exception 'a partner weight is 0.90 to 1.10' using errcode = '22023'; end if;
      v_until := coalesce(nullif(p ->> 'until', '')::timestamptz, now() + interval '7 days');
      if v_until <= now() or v_until > now() + interval '14 days 1 hour' then raise exception 'a partner weight ends within 14 days' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'partner_id', (p ->> 'partner_id')::bigint, 'value', round((p ->> 'value')::numeric, 3), 'until', v_until);
    when 'share_cap' then
      if p -> 'value' is not null and jsonb_typeof(p -> 'value') <> 'null' and not ((p ->> 'value')::numeric between 0.5 and 1) then
        raise exception 'a share cap is 50 to 100%%' using errcode = '22023';
      end if;
      return jsonb_build_object('lever', v_lever, 'segment', p ->> 'segment', 'value', case when jsonb_typeof(p -> 'value') = 'number' then round((p ->> 'value')::numeric, 3) end);
    when 'rule_draft' then
      if p -> 'rule' ->> 'action' not in ('fix_partner', 'narrow', 'exclude') then raise exception 'a drafted rule keeps, narrows to or excludes partners' using errcode = '22023'; end if;
      if coalesce(trim(p -> 'rule' ->> 'name'), '') = '' then raise exception 'a drafted rule needs a name' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'rule', jsonb_build_object('name', left(trim(p -> 'rule' ->> 'name'), 120), 'action', p -> 'rule' ->> 'action',
                                'partner_ids', coalesce(p -> 'rule' -> 'partner_ids', '[]'), 'conditions', coalesce(p -> 'rule' -> 'conditions', '{}'),
                                'priority', coalesce((p -> 'rule' ->> 'priority')::int, 100)));
    when 'pause_draft' then
      if not exists (select 1 from b2b.partners where id = (p ->> 'partner_id')::bigint and status = 'active') then raise exception 'unknown or inactive partner' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'partner_id', (p ->> 'partner_id')::bigint, 'reason', left(coalesce(p ->> 'reason', ''), 300));
    else
      raise exception 'outside the AI''s bounds: %', coalesce(v_lever, 'no lever') using errcode = '22023';
    end case;
  exception when data_exception then
    if sqlstate = '22023' then raise; end if;
    raise exception 'the change has a value of the wrong type (%)', sqlerrm using errcode = '22023';
  end;
end $fn$;

/* Where a change lives in engine_policy, and the value it would write. */
create or replace function b2b.ai_change_path(c jsonb, p_rec_id bigint)
returns jsonb language sql stable set search_path = '' as $fn$
  select case c ->> 'lever'
    when 'exploration_share' then jsonb_build_object('path', jsonb_build_array('segments', c ->> 'segment', 'exploration_share'),
                                                     'value', jsonb_build_object('value', (c ->> 'value')::numeric, 'source', 'ai', 'recommendation', p_rec_id, 'at', now()))
    when 'share_cap' then jsonb_build_object('path', jsonb_build_array('segments', c ->> 'segment', 'share_cap'),
                                             'value', case when c ->> 'value' is not null then jsonb_build_object('value', (c ->> 'value')::numeric, 'source', 'ai', 'recommendation', p_rec_id, 'at', now()) end)
    when 'segment_pin' then jsonb_build_object('path', jsonb_build_array('segments', c ->> 'segment', 'pin'),
                                               'value', jsonb_build_object('mode', c ->> 'value', 'until', c ->> 'until', 'source', 'ai', 'recommendation', p_rec_id, 'at', now()))
    when 'partner_weight' then jsonb_build_object('path', jsonb_build_array('partner_weights', c ->> 'partner_id'),
                                                  'value', jsonb_build_object('weight', (c ->> 'value')::numeric, 'until', c ->> 'until', 'source', 'ai', 'recommendation', p_rec_id))
    when 'maturity_days' then jsonb_build_object('path', jsonb_build_array('ai', 'maturity_days'), 'value', c -> 'value')
    when 'half_life_days' then jsonb_build_object('path', jsonb_build_array('ai', 'half_life_days'), 'value', c -> 'value')
    when 'prior_weight' then jsonb_build_object('path', jsonb_build_array('ai', 'prior_weight'), 'value', c -> 'value')
    when 'speed_factor' then jsonb_build_object('path', jsonb_build_array('ai', 'speed_factor'), 'value', c -> 'value')
    when 'reliability_factor' then jsonb_build_object('path', jsonb_build_array('ai', 'reliability_factor'), 'value', c -> 'value')
  end;
$fn$;

/* Writes (or removes, for a null value) one value of engine_policy, creating parent objects. */
create or replace function b2b.jsonb_put(p_doc jsonb, p_path text[], p_value jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare i int;
begin
  for i in 1 .. cardinality(p_path) - 1 loop
    if p_doc #> p_path[1:i] is null or jsonb_typeof(p_doc #> p_path[1:i]) <> 'object' then p_doc := jsonb_set(p_doc, p_path[1:i], '{}'); end if;
  end loop;
  if p_value is null or jsonb_typeof(p_value) = 'null' then return p_doc #- p_path; end if;
  return jsonb_set(p_doc, p_path, p_value);
end $fn$;

-- ---------- worker API (API key scope ai_worker) ----------
create or replace function b2b.api_ai_claim(p_key text, p_info jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  r b2b.ai_runs;
  v_spent numeric;
begin
  if not (b2b.api_key_check(p_key, 'ai_worker') ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  perform set_config('b2b.actor', 'engine', true);
  insert into b2b.ai_state (key, value, updated_at) values ('worker', coalesce(p_info, '{}') || jsonb_build_object('seen_at', now()), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  -- a run stuck for 15 minutes failed
  update b2b.ai_runs set status = 'failed', error = 'the worker stopped answering', finished_at = now()
   where status = 'running' and started_at < now() - interval '15 minutes';
  if not coalesce((cfg ->> 'enabled')::boolean, false) then return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('run', null, 'why', 'the optimiser is off')); end if;
  -- a worker without an Anthropic key only reports in; it must not take a run it cannot finish
  if p_info ->> 'has_anthropic_key' = 'false' then
    return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('run', null, 'why', 'the worker has no Anthropic key'));
  end if;
  select * into r from b2b.ai_runs where status = 'queued' order by created_at limit 1 for update skip locked;
  if r.id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('run', null)); end if;
  v_spent := (b2b.ai_spend() ->> 'today_usd')::numeric;
  if v_spent >= coalesce((cfg ->> 'daily_budget_usd')::numeric, 5) then
    update b2b.ai_runs set status = 'skipped', error = format('daily budget of $%s reached ($%s spent)', cfg ->> 'daily_budget_usd', v_spent), finished_at = now()
     where status = 'queued';
    -- one budget alert a day (IST), however many claims and ticks come after it
    if not exists (select 1 from b2b.events where type = 'alert.ai_budget'
                    and occurred_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') then
      perform b2b.log_event('alert.ai_budget', null, null, null, jsonb_build_object('spent_usd', v_spent, 'budget_usd', cfg ->> 'daily_budget_usd'));
    end if;
    return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('run', null, 'why', 'daily budget reached'));
  end if;
  update b2b.ai_runs set status = 'running', started_at = now() where id = r.id;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'run', jsonb_build_object('id', r.id, 'kind', r.kind, 'trigger', r.trigger, 'model', r.model, 'context', r.context),
    'limits', jsonb_build_object('max_turns', coalesce((cfg ->> 'max_turns')::int, 8), 'max_tokens', coalesce((cfg ->> 'max_tokens')::int, 12000),
                                 'budget_left_usd', round(coalesce((cfg ->> 'daily_budget_usd')::numeric, 5) - v_spent, 4)),
    'mode', coalesce(cfg ->> 'mode', 'advisory'),
    'price_per_mtok', b2b.ai_price(r.model)));
end $fn$;

create or replace function b2b.api_ai_tool(p_key text, p_run_id bigint, p_name text, p_input jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_out jsonb;
  v_no int;
  t0 timestamptz := clock_timestamp();
begin
  if not (b2b.api_key_check(p_key, 'ai_worker') ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if not exists (select 1 from b2b.ai_runs where id = p_run_id and status = 'running') then
    return jsonb_build_object('ok', false, 'status', 409, 'error', 'the run is not running');
  end if;
  -- the limit goes back to Claude as a tool result, so the run can still file its report
  if (select count(*) from b2b.ai_tool_outputs where run_id = p_run_id) >= 40 then
    return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('call_no', null,
      'output', jsonb_build_object('error', 'tool call limit (40) reached for this run; call submit_report now')));
  end if;
  -- a malformed input (text for a number, a fractional day count, a bad date) is answered, not a failed run
  begin
    v_out := b2b.ai_tool(p_name, coalesce(p_input, '{}'));
  exception when data_exception then
    v_out := jsonb_build_object('error', sqlerrm);
  end;
  select coalesce(max(call_no), 0) + 1 into v_no from b2b.ai_tool_outputs where run_id = p_run_id;
  insert into b2b.ai_tool_outputs (run_id, call_no, name, input, output) values (p_run_id, v_no, p_name, coalesce(p_input, '{}'), v_out);
  update b2b.ai_runs set tool_calls = tool_calls || jsonb_build_object('call_no', v_no, 'name', p_name, 'input', coalesce(p_input, '{}'),
                                                                       'output_hash', md5(v_out::text), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000), 'at', now())
   where id = p_run_id;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('call_no', v_no, 'output', v_out));
end $fn$;

/* p: {narrative, output: {summary, findings[], recommendations[]}, usage: {in, out, cache_read, cache_write}, prompt_version,
   input_hash, validation: {ok, unverified[]}}. Recommendations: {kind?, title, rationale, evidence[], change, risk}. */
create or replace function b2b.api_ai_finish(p_key text, p_run_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  r b2b.ai_runs;
  pr jsonb;
  v_cost numeric;
  x jsonb;
  v_change jsonb;
  v_kind text;
  v_sim jsonb;
  v_rejected jsonb := '[]';
  v_ids bigint[] := '{}';
  v_id bigint;
  v_ok boolean := coalesce((p -> 'validation' ->> 'ok')::boolean, false);
begin
  if not (b2b.api_key_check(p_key, 'ai_worker') ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  select * into r from b2b.ai_runs where id = p_run_id for update;
  if r.id is null or r.status <> 'running' then return jsonb_build_object('ok', false, 'status', 409, 'error', 'the run is not running'); end if;
  perform set_config('b2b.actor', 'engine', true);
  pr := b2b.ai_price(r.model);
  v_cost := round((coalesce((p -> 'usage' ->> 'in')::numeric, 0) * (pr ->> 'in')::numeric + coalesce((p -> 'usage' ->> 'out')::numeric, 0) * (pr ->> 'out')::numeric
                   + coalesce((p -> 'usage' ->> 'cache_read')::numeric, 0) * coalesce((pr ->> 'cache_read')::numeric, 0)
                   + coalesce((p -> 'usage' ->> 'cache_write')::numeric, 0) * coalesce((pr ->> 'cache_write')::numeric, 0)) / 1000000, 4);

  if v_ok then
    for x in select * from jsonb_array_elements(coalesce(p -> 'output' -> 'recommendations', '[]')) limit 10 loop
      begin
        v_change := case when x -> 'change' is not null and jsonb_typeof(x -> 'change') = 'object' then b2b.ai_validate_change(x -> 'change') end;
        v_kind := case when v_change is null then 'insight' when v_change ->> 'lever' = 'rule_draft' then 'rule_draft'
                       when v_change ->> 'lever' = 'pause_draft' then 'pause_draft' else 'setting_change' end;
        v_sim := case when v_kind = 'setting_change' then b2b.ai_simulate(v_change, 90) end;
        if coalesce(trim(x ->> 'title'), '') = '' or coalesce(trim(x ->> 'rationale'), '') = '' then
          raise exception 'a recommendation needs a title and a rationale' using errcode = '22023';
        end if;
        insert into b2b.ai_recommendations (run_id, kind, title, rationale, evidence, change, simulation, risk, expires_at)
        values (r.id, v_kind, left(trim(x ->> 'title'), 200), left(trim(x ->> 'rationale'), 3000), coalesce(x -> 'evidence', '[]'), v_change, v_sim,
                left(x ->> 'risk', 1000), now() + make_interval(days => coalesce((cfg ->> 'recommendation_days')::int, 7)))
        returning id into v_id;
        -- an older open recommendation on the same lever and target is superseded; a rule draft only by a draft of the same rule (by name)
        if v_change is not null then
          update b2b.ai_recommendations o set status = 'superseded'
           where o.status = 'open' and o.id <> v_id and o.change ->> 'lever' = v_change ->> 'lever'
             and coalesce(o.change ->> 'segment', '') = coalesce(v_change ->> 'segment', '')
             and coalesce(o.change ->> 'partner_id', '') = coalesce(v_change ->> 'partner_id', '')
             and coalesce(lower(o.change -> 'rule' ->> 'name'), '') = coalesce(lower(v_change -> 'rule' ->> 'name'), '');
        end if;
        v_ids := v_ids || v_id;
      -- a malformed recommendation is listed as rejected with the reason; the others are filed
      exception when data_exception then
        v_rejected := v_rejected || jsonb_build_object('title', x ->> 'title', 'why', sqlerrm);
      end;
    end loop;
  end if;

  update b2b.ai_runs
     set status = case when v_ok then 'done' else 'rejected' end, finished_at = now(),
         narrative = left(p ->> 'narrative', 20000), output = p -> 'output', prompt_version = left(p ->> 'prompt_version', 40), input_hash = left(p ->> 'input_hash', 64),
         validation = coalesce(p -> 'validation', '{}') || jsonb_build_object('rejected_changes', v_rejected, 'recommendations', to_jsonb(v_ids)),
         tokens_in = coalesce((p -> 'usage' ->> 'in')::int, 0), tokens_out = coalesce((p -> 'usage' ->> 'out')::int, 0),
         cache_read = coalesce((p -> 'usage' ->> 'cache_read')::int, 0), cache_write = coalesce((p -> 'usage' ->> 'cache_write')::int, 0), cost_usd = v_cost,
         error = case when not v_ok then 'the validator found numbers that no tool returned: ' || left(coalesce(p -> 'validation' ->> 'unverified', ''), 400) end
   where id = r.id;
  perform b2b.log_event('ai.run_finished', null, null, null, jsonb_build_object('run_id', r.id, 'kind', r.kind, 'ok', v_ok, 'recommendations', cardinality(v_ids), 'cost_usd', v_cost));
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('recommendations', to_jsonb(v_ids), 'rejected', v_rejected, 'cost_usd', v_cost, 'status', case when v_ok then 'done' else 'rejected' end));
end $fn$;

create or replace function b2b.api_ai_fail(p_key text, p_run_id bigint, p_error text, p_usage jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r b2b.ai_runs; pr jsonb;
begin
  if not (b2b.api_key_check(p_key, 'ai_worker') ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  select * into r from b2b.ai_runs where id = p_run_id and status = 'running' for update;
  if r.id is null then return jsonb_build_object('ok', false, 'status', 409, 'error', 'the run is not running'); end if;
  pr := b2b.ai_price(r.model);
  -- a failed run is priced like a finished one, cache reads and writes included
  update b2b.ai_runs set status = 'failed', error = left(p_error, 1000), finished_at = now(),
         tokens_in = coalesce((p_usage ->> 'in')::int, 0), tokens_out = coalesce((p_usage ->> 'out')::int, 0),
         cache_read = coalesce((p_usage ->> 'cache_read')::int, 0), cache_write = coalesce((p_usage ->> 'cache_write')::int, 0),
         cost_usd = round((coalesce((p_usage ->> 'in')::numeric, 0) * (pr ->> 'in')::numeric
                         + coalesce((p_usage ->> 'out')::numeric, 0) * (pr ->> 'out')::numeric
                         + coalesce((p_usage ->> 'cache_read')::numeric, 0) * coalesce((pr ->> 'cache_read')::numeric, 0)
                         + coalesce((p_usage ->> 'cache_write')::numeric, 0) * coalesce((pr ->> 'cache_write')::numeric, 0)) / 1000000, 4)
   where id = r.id;
  perform b2b.log_event('alert.ai_run_failed', null, null, null, jsonb_build_object('run_id', r.id, 'error', left(p_error, 300)));
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('status', 'failed'));
end $fn$;

-- ---------- schedule ----------
create or replace function b2b.ai_queue(p_trigger text, p_kind text, p_context jsonb, p_by text default 'engine')
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  v_model text := case when p_kind in ('deep_review', 'weekly_report') then cfg -> 'models' ->> 'deep'
                       when p_kind = 'light_check' then cfg -> 'models' ->> 'quick' else cfg -> 'models' ->> 'regular' end;
  v_id bigint;
begin
  if exists (select 1 from b2b.ai_runs where kind = p_kind and status in ('queued', 'running')) then return null; end if;
  insert into b2b.ai_runs (trigger, kind, model, context, requested_by) values (p_trigger, p_kind, coalesce(v_model, 'claude-sonnet-5-5'), coalesce(p_context, '{}'), p_by)
  returning id into v_id;
  return v_id;
end $fn$;

/* The events that queue an event run: a partner auto-paused or its status changed, an NCPL alert, a model fallback or status
   change, a commission rate created, ended or changed from a file, a partner switched live. */
create or replace function b2b.ai_is_trigger_event(p_type text, p_payload jsonb)
returns boolean language sql immutable set search_path = '' as $fn$
  select p_type in ('alert.partner_auto_paused', 'alert.ncpl_drop', 'alert.model_fallback', 'ml.model_status', 'partner.status_changed',
                    'rate.created', 'rate.ended', 'rate.from_file')
      or (p_type = 'live_switch.changed' and coalesce(p_payload ->> 'scope', '') like 'partner:%'
          and coalesce((p_payload ->> 'live')::boolean, false));
$fn$;
revoke execute on function b2b.ai_is_trigger_event(text, jsonb) from public, anon, authenticated;
grant execute on function b2b.ai_is_trigger_event(text, jsonb) to service_role;

create or replace function b2b.ai_schedule_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  sch jsonb := coalesce(cfg -> 'schedules', '{}');
  v_now_ist timestamp := now() at time zone 'Asia/Kolkata';
  v_last timestamptz;
  v_n int;
  v_queued int := 0;
  v_spent numeric;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, false) then return '{"enabled":false}'; end if;
  if not pg_try_advisory_xact_lock(hashtext('b2b.ai_schedule_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  -- the daily budget is spent: queue nothing more today (each queued run would only be skipped), skip what still waits
  -- (as api_ai_claim does; otherwise it would wait past IST midnight and run on the next day's budget with stale
  -- context), alert once a day (IST)
  v_spent := (b2b.ai_spend() ->> 'today_usd')::numeric;
  if v_spent >= coalesce((cfg ->> 'daily_budget_usd')::numeric, 5) then
    update b2b.ai_recommendations set status = 'expired' where status = 'open' and expires_at < now();
    update b2b.ai_runs set status = 'skipped', error = format('daily budget of $%s reached ($%s spent)', cfg ->> 'daily_budget_usd', v_spent), finished_at = now()
     where status = 'queued';
    get diagnostics v_n = row_count;
    if not exists (select 1 from b2b.events where type = 'alert.ai_budget'
                    and occurred_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') then
      perform b2b.log_event('alert.ai_budget', null, null, null, jsonb_build_object('spent_usd', v_spent, 'budget_usd', cfg ->> 'daily_budget_usd'));
    end if;
    return jsonb_build_object('budget_reached', true, 'spent_usd', v_spent, 'skipped', v_n);
  end if;
  -- light check: only when new alerts arrived (no call at all on a quiet quarter hour)
  if coalesce((sch ->> 'light')::boolean, true) then
    select max(created_at) into v_last from b2b.ai_runs where kind = 'light_check';
    if v_last is null or v_last < now() - interval '15 minutes' then
      select count(*) into v_n from b2b.events where (type like 'alert.%' or type = 'routing.error') and type not in ('alert.ai_budget', 'alert.ai_run_failed')
                                               and occurred_at > coalesce(v_last, now() - interval '15 minutes');
      if v_n > 0 and b2b.ai_queue('light', 'light_check', jsonb_build_object('new_alerts', v_n)) is not null then v_queued := v_queued + 1; end if;
    end if;
  end if;
  -- hourly optimisation: only when decisions or outcomes changed since the last one
  if coalesce((sch ->> 'hourly')::boolean, true) then
    select max(created_at) into v_last from b2b.ai_runs where kind = 'optimise' and status <> 'skipped';
    if (v_last is null or v_last < now() - interval '55 minutes')
       and (exists (select 1 from b2b.engine_decisions where created_at > coalesce(v_last, '-infinity') and not is_test and destination_type = 'partner')
            or exists (select 1 from public.enrollments where updated_at > coalesce(v_last, '-infinity') and source_product = 'b2b')) then
      if b2b.ai_queue('hourly', 'optimise', '{}') is not null then v_queued := v_queued + 1; end if;
    end if;
  end if;
  -- nightly deep review after 01:00 IST, weekly report Monday after 09:00 IST: once per IST day / ISO week, counting only
  -- scheduled runs, so a manual run does not move the schedule (while one of the same kind waits, ai_queue returns null
  -- and the next tick retries)
  if coalesce((sch ->> 'nightly')::boolean, true) and extract(hour from v_now_ist) >= 1
     and not exists (select 1 from b2b.ai_runs where kind = 'deep_review' and trigger = 'nightly'
                       and (created_at at time zone 'Asia/Kolkata')::date = v_now_ist::date) then
    if b2b.ai_queue('nightly', 'deep_review', '{}') is not null then v_queued := v_queued + 1; end if;
  end if;
  if coalesce((sch ->> 'weekly')::boolean, true) and extract(isodow from v_now_ist) = 1 and extract(hour from v_now_ist) >= 9
     and not exists (select 1 from b2b.ai_runs where kind = 'weekly_report' and trigger = 'weekly'
                       and date_trunc('week', created_at at time zone 'Asia/Kolkata') = date_trunc('week', v_now_ist)) then
    if b2b.ai_queue('weekly', 'weekly_report', '{}') is not null then v_queued := v_queued + 1; end if;
  end if;
  -- events: a partner auto-paused or its status changed, an NCPL alert, a model fallback or promotion, a commission rate change, a partner going live
  select count(*) into v_n from b2b.events e
   where b2b.ai_is_trigger_event(e.type, e.payload)
     and e.occurred_at > coalesce((select max(created_at) from b2b.ai_runs where trigger = 'event'), now() - interval '5 minutes');
  if v_n > 0 and not exists (select 1 from b2b.ai_runs where trigger = 'event' and created_at > now() - interval '1 hour') then
    if b2b.ai_queue('event', 'optimise', jsonb_build_object('events', v_n)) is not null then v_queued := v_queued + 1; end if;
  end if;
  -- recommendations past their expiry
  update b2b.ai_recommendations set status = 'expired' where status = 'open' and expires_at < now();
  -- wake the worker when something waits
  if exists (select 1 from b2b.ai_runs where status = 'queued') and nullif(cfg ->> 'worker_url', '') is not null then
    perform net.http_post(url := rtrim(cfg ->> 'worker_url', '/') || '/v1/ai/tick', body := '{}'::jsonb,
                          headers := '{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds := 5000);
  end if;
  return jsonb_build_object('queued', v_queued);
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-ai-schedule';
  perform cron.schedule('b2b-ai-schedule', '*/5 * * * *', 'select b2b.ai_schedule_tick()');
end $cron$;

-- ---------- Admin ----------
create or replace function b2b.ai_run_now(p_kind text, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint; cfg jsonb := b2b.ai_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind not in ('light_check', 'optimise', 'deep_review', 'weekly_report') then raise exception 'unknown kind of run' using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not coalesce((cfg ->> 'enabled')::boolean, false) then raise exception 'turn the optimiser on first (AI settings)' using errcode = '22023'; end if;
  v_id := b2b.ai_queue('manual', p_kind, jsonb_build_object('reason', left(trim(p_reason), 300)), coalesce(auth.uid()::text, 'admin'));
  if v_id is null then raise exception 'a run of this kind is already waiting' using errcode = '22023'; end if;
  if nullif(cfg ->> 'worker_url', '') is not null then
    perform net.http_post(url := rtrim(cfg ->> 'worker_url', '/') || '/v1/ai/tick', body := '{}'::jsonb,
                          headers := '{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds := 5000);
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function b2b.ai_recommendation_decide(p_id bigint, p_decision text, p_note text, p_change jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  v_change jsonb;
  v_put jsonb;
  pol jsonb;
  v_from jsonb;
  v_set jsonb;
  v_who text := coalesce((select email from b2b.app_users where user_id = auth.uid()), auth.uid()::text, 'admin');
  v_res jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'approve or reject' using errcode = '22023'; end if;
  select * into rec from b2b.ai_recommendations where id = p_id for update;
  if rec.id is null then raise exception 'recommendation not found' using errcode = 'P0002'; end if;
  if rec.status <> 'open' then raise exception 'this recommendation is %', rec.status using errcode = '22023'; end if;
  if rec.expires_at < now() then
    update b2b.ai_recommendations set status = 'expired' where id = rec.id;
    raise exception 'this recommendation has expired' using errcode = '22023';
  end if;
  if p_decision = 'reject' then
    update b2b.ai_recommendations set status = 'rejected', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500) where id = rec.id;
    perform b2b.log_event('ai.recommendation_rejected', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id));
    return jsonb_build_object('status', 'rejected');
  end if;
  if rec.kind = 'insight' then
    update b2b.ai_recommendations set status = 'applied', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500) where id = rec.id;
    return jsonb_build_object('status', 'applied');
  end if;
  -- the Admin may edit the change before approving; it is re-checked against the bounds
  v_change := b2b.ai_validate_change(coalesce(p_change, rec.change));
  if v_change ->> 'lever' is distinct from rec.change ->> 'lever' then raise exception 'an edit keeps the same lever' using errcode = '22023'; end if;

  if v_change ->> 'lever' = 'rule_draft' then
    v_res := b2b.routing_rule_save((v_change -> 'rule') || '{"active":false}');
    v_set := jsonb_build_object('rule_id', v_res ->> 'id', 'active', false);
  elsif v_change ->> 'lever' = 'pause_draft' then
    perform b2b.partner_set_status((v_change ->> 'partner_id')::bigint, 'paused', 'AI recommendation #' || rec.id || ' approved by ' || v_who || ': ' || coalesce(nullif(v_change ->> 'reason', ''), rec.title));
    v_set := jsonb_build_object('partner_id', v_change ->> 'partner_id', 'paused', true);
  else
    pol := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
    v_put := b2b.ai_change_path(v_change, rec.id);
    v_from := pol #> (select array_agg(x) from jsonb_array_elements_text(v_put -> 'path') x);
    pol := b2b.jsonb_put(pol, (select array_agg(x) from jsonb_array_elements_text(v_put -> 'path') x), v_put -> 'value');
    v_res := b2b.set_setting('engine_policy', pol, format('AI recommendation #%s (run #%s) approved by %s: %s', rec.id, rec.run_id, v_who, rec.title));
    v_set := jsonb_build_object('key', 'engine_policy', 'version', v_res -> 'version', 'path', v_put -> 'path', 'from', v_from, 'to', v_put -> 'value');
  end if;
  update b2b.ai_recommendations
     set status = 'applied', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500),
         applied = v_set || jsonb_build_object('edited', p_change is not null and v_change is distinct from rec.change, 'change', v_change),
         check_due_at = now() + interval '7 days'
   where id = rec.id;
  perform b2b.log_event('ai.recommendation_applied', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id, 'change', v_change, 'by', v_who));
  return jsonb_build_object('status', 'applied', 'applied', v_set);
end $fn$;

create or replace function b2b.ai_recommendation_rollback(p_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  pol jsonb;
  v_path text[];
  v_who text := coalesce((select email from b2b.app_users where user_id = auth.uid()), auth.uid()::text, 'admin');
  v_res jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into rec from b2b.ai_recommendations where id = p_id for update;
  if rec.id is null then raise exception 'recommendation not found' using errcode = 'P0002'; end if;
  if rec.status <> 'applied' or rec.kind <> 'setting_change' then raise exception 'only an applied setting change can be rolled back here' using errcode = '22023'; end if;
  pol := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  v_path := (select array_agg(x) from jsonb_array_elements_text(rec.applied -> 'path') x);
  pol := b2b.jsonb_put(pol, v_path, rec.applied -> 'from');
  v_res := b2b.set_setting('engine_policy', pol, format('rollback of AI recommendation #%s by %s: %s', rec.id, v_who, trim(p_reason)));
  update b2b.ai_recommendations set status = 'rolled_back', check_result = coalesce(check_result, '{}') || jsonb_build_object('rolled_back_by', v_who, 'at', now(), 'reason', trim(p_reason), 'version', v_res -> 'version')
   where id = rec.id;
  perform b2b.log_event('ai.recommendation_rolled_back', null, null, null, jsonb_build_object('id', rec.id, 'by', v_who));
  return jsonb_build_object('status', 'rolled_back', 'version', v_res -> 'version');
end $fn$;

/* When Autopilot may be switched on: AI-steered leads beat the holdout on realised net commission per matured lead over the
   last 4 weeks of matured leads (allocations maturity_days to maturity_days + 28 days old, every week present in both
   groups), with at least 30 leads in each group. */
create or replace function b2b.ai_autopilot_gate()
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with prm as (select coalesce((b2b.engine_params(true) ->> 'maturity_days')::int, 60) md),
  x as (select coalesce(d.holdout, false) holdout,
               floor(extract(epoch from (now() - make_interval(days => prm.md)) - a.created_at) / 604800)::int wk,
               b2b.allocation_reward(a.id) r
          from b2b.engine_decisions d
          join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test, prm
         where d.destination_type = 'partner' and not d.is_test and d.scoring_mode is not null
           and a.created_at > now() - make_interval(days => prm.md + 28) and a.created_at <= now() - make_interval(days => prm.md)
           and a.status in ('pushed', 'accepted', 'closed')),
  s as (select count(*) filter (where not holdout) sn, count(*) filter (where holdout) hn,
               avg(r) filter (where not holdout) sm, avg(r) filter (where holdout) hm,
               count(distinct wk) filter (where not holdout) sw, count(distinct wk) filter (where holdout) hw from x)
  select jsonb_build_object('open', coalesce(s.sn >= 30 and s.hn >= 30 and s.sw = 4 and s.hw = 4 and s.sm > s.hm, false),
           'steered', jsonb_build_object('leads', s.sn, 'ncpl', round(coalesce(s.sm, 0), 2), 'weeks', s.sw),
           'holdout', jsonb_build_object('leads', s.hn, 'ncpl', round(coalesce(s.hm, 0), 2), 'weeks', s.hw),
           'weeks', 4, 'min_leads', 30, 'maturity_days', (select md from prm))
    from s;
$fn$;
revoke execute on function b2b.ai_autopilot_gate() from public, anon, authenticated;
grant execute on function b2b.ai_autopilot_gate() to service_role;

create or replace function b2b.ai_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare cfg jsonb := b2b.ai_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', cfg - 'salt', 'settings_version', (select version from b2b.settings where key = 'ai'),
    'worker', (select value || jsonb_build_object('updated_at', updated_at) from b2b.ai_state where key = 'worker'),
    'worker_key', exists (select 1 from b2b.api_keys where 'ai_worker' = any (scopes) and revoked_at is null),
    'spend', b2b.ai_spend(),
    'uplift', b2b.ai_uplift(180),
    'autopilot_gate', b2b.ai_autopilot_gate(),
    'holdout_share', (select value -> 'holdout_share' from b2b.settings where key = 'engine_policy'),
    'open', coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('run_kind', (select kind from b2b.ai_runs where id = x.run_id)) order by x.created_at desc)
                        from b2b.ai_recommendations x where x.status = 'open'), '[]'),
    'decided', coalesce((select jsonb_agg(to_jsonb(x) order by coalesce(x.decided_at, x.created_at) desc)
                           from (select * from b2b.ai_recommendations where status <> 'open' order by coalesce(decided_at, created_at) desc limit 40) x), '[]'),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'trigger', r.trigger, 'kind', r.kind, 'model', r.model, 'status', r.status,
                                                          'created_at', r.created_at, 'finished_at', r.finished_at, 'tools', jsonb_array_length(r.tool_calls),
                                                          'tokens_in', r.tokens_in, 'tokens_out', r.tokens_out, 'cost_usd', r.cost_usd, 'error', r.error,
                                                          'summary', left(coalesce(r.output ->> 'summary', r.narrative), 300),
                                                          'recommendations', r.validation -> 'recommendations') order by r.id desc)
                        from (select * from b2b.ai_runs order by id desc limit 30) r), '[]'));
end $fn$;

create or replace function b2b.ai_run_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select to_jsonb(r) || jsonb_build_object(
            'tool_outputs', coalesce((select jsonb_agg(jsonb_build_object('call_no', t.call_no, 'name', t.name, 'input', t.input, 'output', t.output) order by t.call_no)
                                        from b2b.ai_tool_outputs t where t.run_id = r.id), '[]'),
            'recommendations_rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from b2b.ai_recommendations x where x.run_id = r.id), '[]'))
            from b2b.ai_runs r where r.id = p_id);
end $fn$;

create or replace function b2b.ai_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb := b2b.ai_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'enabled' and jsonb_typeof(p -> 'enabled') <> 'boolean' then raise exception 'the optimiser is on or off' using errcode = '22023'; end if;
  if p ? 'mode' and p ->> 'mode' <> 'advisory' then raise exception 'only Advisory mode is available until Autopilot is built' using errcode = '22023'; end if;
  if p ? 'daily_budget_usd' and not ((p ->> 'daily_budget_usd')::numeric between 0 and 200) then raise exception 'the daily budget is $0 to $200' using errcode = '22023'; end if;
  if p ? 'worker_url' and coalesce(p ->> 'worker_url', '') <> '' and p ->> 'worker_url' !~ '^https://[^\s/]+(/[^\s]*)?$' then
    raise exception 'the worker address starts with https://' using errcode = '22023';
  end if;
  if p ? 'models' and (jsonb_typeof(p -> 'models') <> 'object' or exists (select 1 from jsonb_each_text(p -> 'models') m(k, x)
                                                                          where k not in ('regular', 'deep', 'quick') or x !~ '^claude-[a-z0-9.-]{3,60}$')) then
    raise exception 'models are claude-… names for regular, deep and quick runs' using errcode = '22023';
  end if;
  if p ? 'schedules' and jsonb_typeof(p -> 'schedules') <> 'object' then raise exception 'schedules are on or off' using errcode = '22023'; end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('enabled', (p ->> 'enabled')::boolean, 'mode', p ->> 'mode',
                                                 'daily_budget_usd', round((p ->> 'daily_budget_usd')::numeric, 2),
                                                 'worker_url', case when p ? 'worker_url' then coalesce(nullif(rtrim(p ->> 'worker_url', '/'), ''), '') end))
       || case when p ? 'models' then jsonb_build_object('models', coalesce(v -> 'models', '{}') || (p -> 'models')) else '{}' end
       || case when p ? 'schedules' then jsonb_build_object('schedules', coalesce(v -> 'schedules', '{}')
                                                            || (select coalesce(jsonb_object_agg(k, x::boolean), '{}') from jsonb_each_text(p -> 'schedules') s(k, x)
                                                                 where k in ('light', 'hourly', 'nightly', 'weekly') and x in ('true', 'false'))) else '{}' end;
  return b2b.set_setting('ai', v, p_reason);
end $fn$;

revoke execute on function b2b.ai_cfg(), b2b.ai_spend(), b2b.ai_validate_change(jsonb), b2b.ai_change_path(jsonb, bigint), b2b.jsonb_put(jsonb, text[], jsonb),
                           b2b.ai_queue(text, text, jsonb, text), b2b.ai_schedule_tick() from public, anon, authenticated;
grant execute on function b2b.ai_cfg(), b2b.ai_spend(), b2b.ai_validate_change(jsonb), b2b.ai_change_path(jsonb, bigint), b2b.jsonb_put(jsonb, text[], jsonb),
                          b2b.ai_queue(text, text, jsonb, text), b2b.ai_schedule_tick() to service_role;
-- the worker API is called with the publishable key and checks its own API key (like the other /v1 functions)
revoke execute on function b2b.api_ai_claim(text, jsonb), b2b.api_ai_tool(text, bigint, text, jsonb), b2b.api_ai_finish(text, bigint, jsonb),
                           b2b.api_ai_fail(text, bigint, text, jsonb) from public;
grant execute on function b2b.api_ai_claim(text, jsonb), b2b.api_ai_tool(text, bigint, text, jsonb), b2b.api_ai_finish(text, bigint, jsonb),
                          b2b.api_ai_fail(text, bigint, text, jsonb) to anon, authenticated, service_role;
revoke execute on function b2b.ai_run_now(text, text), b2b.ai_recommendation_decide(bigint, text, text, jsonb), b2b.ai_recommendation_rollback(bigint, text),
                           b2b.ai_overview(), b2b.ai_run_detail(bigint), b2b.ai_settings_save(jsonb, text) from public, anon;
grant execute on function b2b.ai_run_now(text, text), b2b.ai_recommendation_decide(bigint, text, text, jsonb), b2b.ai_recommendation_rollback(bigint, text),
                          b2b.ai_overview(), b2b.ai_run_detail(bigint), b2b.ai_settings_save(jsonb, text) to authenticated, service_role;
