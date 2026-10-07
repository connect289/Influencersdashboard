-- M30a: Autopilot, the 7-day review, "Ask the CRM" and the change simulator (spec B7.8.2, B14.3).
--   Autopilot (settings ai.mode = 'autopilot'): a setting change inside the bounds is applied without waiting for the
--     Admin when its simulation rests on enough decisions, shows at least autopilot.min_gain_pct (default 3%) more net
--     commission per lead, and the lower end of its 95% interval is above zero; at most autopilot.max_per_day (default 3)
--     a day. Drafts (rules, pauses) and anything else stay in the inbox. Every auto-applied change is versioned "by autopilot".
--     The Admin can switch it on only once AI-steered leads beat the holdout over 4 weeks of matured leads (ai_autopilot_gate).
--   7-day review (every applied setting change, Advisory or Autopilot): realised commission cannot exist 7 days after a
--     change (leads mature after 60), so the review compares, inside the change's scope, the AI-steered leads routed since
--     the change with the holdout leads routed in the same days, on expected net commission per lead from the stage each
--     lead has reached (the same leading indicators as P̂). Steered worse than holdout with z <= -1: an autopilot change is
--     rolled back automatically, an approved one raises an alert. Too few leads: the review moves a week (three times at most),
--     then the change is kept as inconclusive.
--   ai_ask_log / ai_ask_budget: "Ask the CRM" (answers from the metric layer, run by the app) is logged as an AI run.
--   simulate_change(change, days): the Admin's replay of a proposed change on logged decisions (Routing → Simulate).

alter table b2b.ai_runs drop constraint if exists ai_runs_kind_check;
alter table b2b.ai_runs add constraint ai_runs_kind_check check (kind in ('light_check', 'optimise', 'deep_review', 'weekly_report', 'ask'));
alter table b2b.ai_runs drop constraint if exists ai_runs_trigger_check;
alter table b2b.ai_runs add constraint ai_runs_trigger_check check (trigger in ('light', 'hourly', 'nightly', 'weekly', 'event', 'manual', 'ask'));

update b2b.settings set value = value || jsonb_build_object('autopilot', jsonb_build_object('min_gain_pct', 3, 'max_per_day', 3, 'min_decisions', 30))
 where key = 'ai' and not (value ? 'autopilot');

/* Writes one AI setting change into engine_policy and marks the recommendation applied (used by the Admin's approval
   and by Autopilot). */
create or replace function b2b.ai_apply_setting(p_rec_id bigint, p_change jsonb, p_who text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare rec b2b.ai_recommendations; pol jsonb; v_put jsonb; v_from jsonb; v_res jsonb; v_set jsonb; v_path text[];
begin
  select * into rec from b2b.ai_recommendations where id = p_rec_id for update;
  pol := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  v_put := b2b.ai_change_path(p_change, rec.id);
  v_path := (select array_agg(x) from jsonb_array_elements_text(v_put -> 'path') x);
  v_from := pol #> v_path;
  pol := b2b.jsonb_put(pol, v_path, v_put -> 'value');
  v_res := b2b.set_setting('engine_policy', pol, format('AI recommendation #%s (run #%s) applied by %s: %s', rec.id, rec.run_id, p_who, rec.title));
  v_set := jsonb_build_object('key', 'engine_policy', 'version', v_res -> 'version', 'path', v_put -> 'path', 'from', v_from, 'to', v_put -> 'value',
                              'change', p_change, 'edited', p_change is distinct from rec.change);
  update b2b.ai_recommendations set status = 'applied', decided_by = p_who, decided_at = now(), decision_note = left(trim(p_note), 500), applied = v_set,
         check_due_at = now() + interval '7 days'
   where id = rec.id;
  perform b2b.log_event('ai.recommendation_applied', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id, 'change', p_change, 'by', p_who));
  return v_set;
end $fn$;

/* Expected net commission per lead of allocations, from the stage each reached (enrolled counts as 1). */
create or replace function b2b.expected_ncpl_rows(p_from timestamptz, p_to timestamptz, p_scope jsonb)
returns table (holdout boolean, n bigint, mean numeric, var numeric) language sql stable security definer set search_path = '' as $fn$
  with rates as (select coalesce(jsonb_object_agg(stage, rate), '{}') r from b2b.stage_rates),
  x as (select coalesce(d.holdout, false) holdout,
               coalesce(a.cpe_net_inr, 0) * case when o.enrolled then 1 else coalesce((rates.r ->> o.stage)::numeric, 0.05) end ev
          from b2b.allocation_outcomes() o
          join b2b.allocations a on a.id = o.allocation_id
          join b2b.engine_decisions d on d.id = a.engine_decision_id and d.scoring_mode is not null
          cross join rates
         where a.created_at >= p_from and a.created_at < p_to
           and (p_scope ->> 'segment' is null or a.segment = p_scope ->> 'segment')
           and (p_scope ->> 'partner_id' is null or d.candidates @> jsonb_build_array(jsonb_build_object('partner_id', (p_scope ->> 'partner_id')::bigint))))
  select x.holdout, count(*), avg(x.ev), coalesce(var_samp(x.ev), 0) from x group by x.holdout;
$fn$;

create or replace function b2b.ai_review_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  st record; ho record;
  v_scope jsonb;
  v_z numeric;
  v_verdict text;
  v_tries int;
  v_n int := 0;
  pol jsonb;
  v_res jsonb;
begin
  for rec in select * from b2b.ai_recommendations where status = 'applied' and kind = 'setting_change' and check_due_at <= now()
                                                     and coalesce(check_result ->> 'final', 'false') <> 'true' for update skip locked loop
    v_scope := jsonb_strip_nulls(jsonb_build_object('segment', rec.applied -> 'change' ->> 'segment', 'partner_id', rec.applied -> 'change' ->> 'partner_id'));
    select * into st from b2b.expected_ncpl_rows(rec.decided_at, now(), v_scope) where not holdout;
    select * into ho from b2b.expected_ncpl_rows(rec.decided_at, now(), v_scope) where holdout;
    v_tries := coalesce((rec.check_result ->> 'tries')::int, 0) + 1;
    if coalesce(st.n, 0) < 20 or coalesce(ho.n, 0) < 10 then
      v_verdict := case when v_tries >= 3 then 'inconclusive' else 'waiting' end;
      v_z := null;
    else
      v_z := round((st.mean - ho.mean) / nullif(sqrt(st.var / st.n + ho.var / ho.n), 0), 2);
      v_verdict := case when st.mean < ho.mean and coalesce(v_z, -9) <= -1 then 'worse' else 'kept' end;
    end if;
    update b2b.ai_recommendations
       set check_result = coalesce(check_result, '{}') || jsonb_build_object('tries', v_tries, 'at', now(), 'verdict', v_verdict,
                            'steered', jsonb_build_object('leads', coalesce(st.n, 0), 'expected_ncpl', round(st.mean, 2)),
                            'holdout', jsonb_build_object('leads', coalesce(ho.n, 0), 'expected_ncpl', round(ho.mean, 2)), 'z', v_z,
                            'final', v_verdict <> 'waiting'),
           check_due_at = case when v_verdict = 'waiting' then now() + interval '7 days' else check_due_at end
     where id = rec.id;
    if v_verdict = 'worse' then
      if rec.decided_by = 'autopilot' then
        pol := b2b.jsonb_put(coalesce((select value from b2b.settings where key = 'engine_policy'), '{}'),
                             (select array_agg(x) from jsonb_array_elements_text(rec.applied -> 'path') x), rec.applied -> 'from');
        v_res := b2b.set_setting('engine_policy', pol, format('autopilot rollback of AI recommendation #%s after its 7-day review', rec.id));
        update b2b.ai_recommendations set status = 'rolled_back', check_result = check_result || jsonb_build_object('auto_rolled_back', true, 'version', v_res -> 'version')
         where id = rec.id;
        perform b2b.log_event('alert.ai_rollback', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z));
      else
        perform b2b.log_event('alert.ai_review_worse', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z));
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $fn$;

create or replace function b2b.ai_autopilot_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  ap jsonb := coalesce(cfg -> 'autopilot', '{}');
  rec b2b.ai_recommendations;
  v_today int;
  v_applied int := 0;
  v_change jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.ai_autopilot_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  if coalesce((cfg ->> 'enabled')::boolean, false) and cfg ->> 'mode' = 'autopilot' then
    select count(*) into v_today from b2b.ai_recommendations
     where decided_by = 'autopilot' and decided_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
    for rec in select * from b2b.ai_recommendations where status = 'open' and kind = 'setting_change' and expires_at > now() order by created_at, id for update skip locked loop
      exit when v_today + v_applied >= coalesce((ap ->> 'max_per_day')::int, 3);
      continue when not coalesce((rec.simulation ->> 'simulated')::boolean, false)
                 or coalesce((rec.simulation ->> 'decisions')::int, 0) < coalesce((ap ->> 'min_decisions')::int, 30)
                 or coalesce((rec.simulation ->> 'gain_pct')::numeric, -100) < coalesce((ap ->> 'min_gain_pct')::numeric, 3)
                 or coalesce((rec.simulation -> 'ci95' ->> 0)::numeric, -1) <= 0;
      begin
        v_change := b2b.ai_validate_change(rec.change);
        perform b2b.ai_apply_setting(rec.id, v_change, 'autopilot',
                                     format('simulated +%s%% (95%%: %s to %s) on %s decisions', rec.simulation ->> 'gain_pct', rec.simulation -> 'ci95' ->> 0,
                                            rec.simulation -> 'ci95' ->> 1, rec.simulation ->> 'decisions'));
        v_applied := v_applied + 1;
      exception when sqlstate '22023' then
        update b2b.ai_recommendations set decision_note = 'autopilot skipped: ' || left(sqlerrm, 200) where id = rec.id;
      end;
    end loop;
  end if;
  return jsonb_build_object('applied', v_applied, 'reviewed', b2b.ai_review_tick());
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-ai-autopilot';
  perform cron.schedule('b2b-ai-autopilot', '*/5 * * * *', 'select b2b.ai_autopilot_tick()');
end $cron$;

/* As in M26b, plus Autopilot (locked until AI-steered leads beat the holdout, ai_autopilot_gate) and its bounds, and the
   prices per million tokens (every model in use needs one). */
create or replace function b2b.ai_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb := b2b.ai_cfg(); v_model text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'enabled' and jsonb_typeof(p -> 'enabled') <> 'boolean' then raise exception 'the optimiser is on or off' using errcode = '22023'; end if;
  if p ? 'mode' and p ->> 'mode' not in ('advisory', 'autopilot') then raise exception 'advisory or autopilot' using errcode = '22023'; end if;
  -- only switching into Autopilot is checked, so other settings can still be saved while in Autopilot
  if p ->> 'mode' = 'autopilot' and coalesce(v ->> 'mode', 'advisory') <> 'autopilot'
     and not coalesce((b2b.ai_autopilot_gate() ->> 'open')::boolean, false) then
    raise exception 'Autopilot unlocks once AI-steered leads beat the holdout over 4 weeks of matured leads (see AI vs holdout)' using errcode = '22023';
  end if;
  if p ? 'daily_budget_usd' and not ((p ->> 'daily_budget_usd')::numeric between 0 and 200) then raise exception 'the daily budget is $0 to $200' using errcode = '22023'; end if;
  if p ? 'worker_url' and coalesce(p ->> 'worker_url', '') <> '' and p ->> 'worker_url' !~ '^https://[^\s/]+(/[^\s]*)?$' then
    raise exception 'the worker address starts with https://' using errcode = '22023';
  end if;
  if p ? 'models' and (jsonb_typeof(p -> 'models') <> 'object' or exists (select 1 from jsonb_each_text(p -> 'models') m(k, x)
                                                                          where k not in ('regular', 'deep', 'quick') or x !~ '^claude-[a-z0-9.-]{3,60}$')) then
    raise exception 'models are claude-… names for regular, deep and quick runs' using errcode = '22023';
  end if;
  if p ? 'schedules' and jsonb_typeof(p -> 'schedules') <> 'object' then raise exception 'schedules are on or off' using errcode = '22023'; end if;
  if p ? 'prices_per_mtok' and (jsonb_typeof(p -> 'prices_per_mtok') <> 'object'
       or exists (select 1 from jsonb_each(p -> 'prices_per_mtok') m(k, x)
                   where k !~ '^claude-[a-z0-9.-]{3,60}$'
                      or case when jsonb_typeof(x) <> 'object' or not (x ? 'in' and x ? 'out') then true
                              else exists (select 1 from jsonb_each(x) f(fk, fx)
                                            where fk not in ('in', 'out', 'cache_read', 'cache_write')
                                               or case when jsonb_typeof(fx) = 'number' then not ((fx #>> '{}')::numeric between 0 and 1000) else true end) end)) then
    raise exception 'prices are dollars per million tokens (in, out, cache_read, cache_write) for claude-… models' using errcode = '22023';
  end if;
  if p ? 'autopilot' then
    if not ((p -> 'autopilot' ->> 'min_gain_pct')::numeric between 1 and 50) then raise exception 'Autopilot needs a simulated gain of 1 to 50%%' using errcode = '22023'; end if;
    if not ((p -> 'autopilot' ->> 'max_per_day')::int between 1 and 10) then raise exception 'Autopilot applies 1 to 10 changes a day' using errcode = '22023'; end if;
  end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('enabled', (p ->> 'enabled')::boolean, 'mode', p ->> 'mode',
                                                 'daily_budget_usd', round((p ->> 'daily_budget_usd')::numeric, 2),
                                                 'worker_url', case when p ? 'worker_url' then coalesce(nullif(rtrim(p ->> 'worker_url', '/'), ''), '') end))
       || case when p ? 'models' then jsonb_build_object('models', coalesce(v -> 'models', '{}') || (p -> 'models')) else '{}' end
       || case when p ? 'schedules' then jsonb_build_object('schedules', coalesce(v -> 'schedules', '{}')
                                                            || (select coalesce(jsonb_object_agg(k, x::boolean), '{}') from jsonb_each_text(p -> 'schedules') s(k, x)
                                                                 where k in ('light', 'hourly', 'nightly', 'weekly') and x in ('true', 'false'))) else '{}' end
       || case when p ? 'autopilot' then jsonb_build_object('autopilot', coalesce(v -> 'autopilot', '{}')
                                                            || jsonb_build_object('min_gain_pct', round((p -> 'autopilot' ->> 'min_gain_pct')::numeric, 1),
                                                                                  'max_per_day', (p -> 'autopilot' ->> 'max_per_day')::int)) else '{}' end
       || case when p ? 'prices_per_mtok' then jsonb_build_object('prices_per_mtok', coalesce(v -> 'prices_per_mtok', '{}') || (p -> 'prices_per_mtok')) else '{}' end;
  -- every model in use is priced, so the cost log and the daily budget never guess
  select m.x into v_model from jsonb_each_text(coalesce(v -> 'models', '{}')) m(k, x)
   where jsonb_typeof(v -> 'prices_per_mtok' -> m.x) is distinct from 'object' order by m.k limit 1;
  if v_model is not null then raise exception 'add a price for % first', v_model using errcode = '22023'; end if;
  return b2b.set_setting('ai', v, p_reason);
end $fn$;

-- ---------- Ask the CRM ----------
create or replace function b2b.ai_ask_budget()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare cfg jsonb := b2b.ai_cfg(); v_spent numeric := (b2b.ai_spend() ->> 'today_usd')::numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('ok', v_spent < coalesce((cfg ->> 'daily_budget_usd')::numeric, 5), 'left_usd', round(coalesce((cfg ->> 'daily_budget_usd')::numeric, 5) - v_spent, 4),
                            'model', coalesce(cfg -> 'models' ->> 'regular', 'claude-sonnet-5-5'),
                            'price_per_mtok', b2b.ai_price(coalesce(cfg -> 'models' ->> 'regular', 'claude-sonnet-5-5')));
end $fn$;

/* p: {question, answer, sources [{metric, dims, filters, from, to}], tool_calls, usage {in, out, cache_read, cache_write}, model, validation, error} */
create or replace function b2b.ai_ask_log(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare cfg jsonb := b2b.ai_cfg(); pr jsonb; v_id bigint; v_cost numeric; v_ok boolean := coalesce((p -> 'validation' ->> 'ok')::boolean, false);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  pr := b2b.ai_price(p ->> 'model');
  v_cost := round((coalesce((p -> 'usage' ->> 'in')::numeric, 0) * (pr ->> 'in')::numeric + coalesce((p -> 'usage' ->> 'out')::numeric, 0) * (pr ->> 'out')::numeric
                   + coalesce((p -> 'usage' ->> 'cache_read')::numeric, 0) * coalesce((pr ->> 'cache_read')::numeric, 0)
                   + coalesce((p -> 'usage' ->> 'cache_write')::numeric, 0) * coalesce((pr ->> 'cache_write')::numeric, 0)) / 1000000, 4);
  insert into b2b.ai_runs (trigger, kind, model, prompt_version, status, context, tool_calls, output, narrative, validation, tokens_in, tokens_out, cache_read, cache_write,
                           cost_usd, error, requested_by, started_at, finished_at)
  values ('ask', 'ask', coalesce(p ->> 'model', 'unknown'), left(p ->> 'prompt_version', 40),
          case when p ->> 'error' is not null then 'failed' when v_ok then 'done' else 'rejected' end,
          jsonb_build_object('question', left(p ->> 'question', 1000)), coalesce(p -> 'tool_calls', '[]'),
          jsonb_build_object('question', left(p ->> 'question', 1000), 'answer', left(p ->> 'answer', 8000), 'sources', coalesce(p -> 'sources', '[]')),
          left(p ->> 'answer', 8000), p -> 'validation', coalesce((p -> 'usage' ->> 'in')::int, 0), coalesce((p -> 'usage' ->> 'out')::int, 0),
          coalesce((p -> 'usage' ->> 'cache_read')::int, 0), coalesce((p -> 'usage' ->> 'cache_write')::int, 0), v_cost, left(p ->> 'error', 500),
          coalesce(auth.uid()::text, 'admin'), now(), now())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'cost_usd', v_cost);
end $fn$;

create or replace function b2b.ai_ask_history(p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'at', r.created_at, 'status', r.status, 'question', r.output ->> 'question', 'answer', r.output ->> 'answer',
                                                       'sources', r.output -> 'sources', 'cost_usd', r.cost_usd, 'unverified', r.validation -> 'unverified', 'error', r.error) order by r.id desc)
                     from (select * from b2b.ai_runs where kind = 'ask' order by id desc limit least(greatest(p_limit, 1), 100)) r), '[]');
end $fn$;

-- ---------- the change simulator (Routing → Simulate) ----------
create or replace function b2b.simulate_change(p_change jsonb, p_days int default 90)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.ai_simulate(b2b.ai_validate_change(p_change), p_days);
end $fn$;

revoke execute on function b2b.ai_apply_setting(bigint, jsonb, text, text), b2b.expected_ncpl_rows(timestamptz, timestamptz, jsonb), b2b.ai_review_tick(), b2b.ai_autopilot_tick()
  from public, anon, authenticated;
grant execute on function b2b.ai_apply_setting(bigint, jsonb, text, text), b2b.expected_ncpl_rows(timestamptz, timestamptz, jsonb), b2b.ai_review_tick(), b2b.ai_autopilot_tick()
  to service_role;
revoke execute on function b2b.ai_ask_budget(), b2b.ai_ask_log(jsonb), b2b.ai_ask_history(int), b2b.simulate_change(jsonb, int) from public, anon;
grant execute on function b2b.ai_ask_budget(), b2b.ai_ask_log(jsonb), b2b.ai_ask_history(int), b2b.simulate_change(jsonb, int) to authenticated, service_role;
