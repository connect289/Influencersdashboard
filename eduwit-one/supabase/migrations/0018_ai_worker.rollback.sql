-- Rollback of 0018: the AI worker's API, schedule, context builders and Ask tools. The tick's app call, the delivery
-- claim and verdict, and the Marketing and Analytics reads go back to their earlier versions (copied verbatim from
-- 0003, 0008 and 0012). Tasks, calls, briefs and proposals stay; the three new columns go.

delete from one.api_grants where why like 'AI worker (0018):%';

create or replace function one.tick_app_call() returns jsonb
language plpgsql set search_path = '' as $$
begin
  return jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
exception when others then
  return jsonb_build_object('app_error', sqlerrm);
end $$;

create or replace function one.claim_deliveries(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_out jsonb := '[]';
  v_row record;
begin
  update one.deliveries d set status = case when i.alert_state = 'muted' then 'muted' else 'suppressed' end
    from one.incidents i
   where d.incident_id = i.id and d.status = 'pending' and d.channel = 'email'
     and (i.resolved_at is not null or i.alert_state in ('muted', 'suppressed')
          or (d.kind = 'escalation' and i.acknowledged_at is not null));
  for v_row in
    with c as (
      select d.id from one.deliveries d
       where d.channel = 'email'
         and ((d.status = 'pending' and d.next_attempt_at <= now()) or (d.status = 'sending' and d.claimed_at < now() - interval '5 minutes'))
       order by d.created_at limit least(greatest(p_limit, 1), 100) for update skip locked)
    update one.deliveries d set status = 'sending', claimed_at = now() from c where d.id = c.id
    returning d.id, d.incident_id, d.recipient, d.kind, d.escalation_level, d.attempts, d.idempotency_key
  loop
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row.id, 'recipient', v_row.recipient, 'kind', v_row.kind, 'escalation_level', v_row.escalation_level,
      'attempts', v_row.attempts, 'idempotency_key', v_row.idempotency_key,
      'incident', (select jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'severity', i.severity, 'title', i.title,
                                             'opened_at', i.opened_at, 'occurrences', i.occurrences, 'reopened_count', i.reopened_count,
                                             'subjects', to_jsonb(i.subjects), 'summary', i.summary, 'value', i.evidence -> 'value',
                                             'status', i.evidence ->> 'status', 'error', i.evidence ->> 'error')
                     from one.incidents i where i.id = v_row.incident_id),
      'digest', case when v_row.kind = 'digest' then (
        select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                     'resolved', i.resolved_at is not null) order by i.opened_at), '[]')
          from one.incidents i
         where i.severity = 'P2' and (i.opened_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
           and i.check_id <> 'ONE-SYNTH') end));
  end loop;
  return v_out;
end $$;

create or replace function one.finish_delivery(p_id bigint, p_ok boolean, p_error text default null, p_provider_id text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_d one.deliveries;
begin
  select * into v_d from one.deliveries where id = p_id and status = 'sending' for update;
  if not found then
    return 'not_claimed';
  end if;
  if p_ok then
    update one.deliveries set status = 'sent', sent_at = now(), provider_id = left(p_provider_id, 120), error = null, attempts = attempts + 1 where id = p_id;
    update one.incidents set alert_state = 'sent' where id = v_d.incident_id and alert_state = 'pending';
    return 'sent';
  end if;
  update one.deliveries
     set attempts = attempts + 1, error = left(p_error, 500),
         status = case when attempts + 1 >= 2 then 'failed' else 'pending' end,
         next_attempt_at = now() + interval '2 minutes'
   where id = p_id;
  return case when v_d.attempts + 1 >= 2 then 'failed' else 'retry' end;
end $$;

create or replace function one.ui_marketing(p_days integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 180);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_out jsonb := jsonb_build_object('days', v_days);
  v_ms jsonb := '{}';
  v_t timestamptz;
begin
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('leads', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'platform', p, 'campaign', c, 'leads', n) order by d desc, n desc), '[]')
      from (select (touched_at at time zone 'Asia/Kolkata')::date as d, coalesce(platform, 'organic') as p, coalesce(campaign_name, utm_campaign, '—') as c, count(*) as n
              from b2b.lead_campaigns lc
             where lc.touched_at > v_from
               and not exists (select 1 from public.student_leads l where l.id = lc.lead_id and coalesce(l.is_test, false))
             group by 1, 2, 3) s));
  exception when others then v_out := v_out || jsonb_build_object('leads_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('leads', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('touchpoints', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'source', s, 'event', e, 'n', n) order by d desc), '[]')
      from (select (occurred_at at time zone 'Asia/Kolkata')::date as d, coalesce(source_system, '?') as s, event_type as e, count(*) as n
              from public.touchpoints tp
             where tp.occurred_at > v_from and regexp_replace(coalesce(tp.phone, ''), '\D', '', 'g') !~ '^910000[0-9]{6}$'
               and not exists (select 1 from public.student_leads l where l.id = tp.lead_id and coalesce(l.is_test, false))
             group by 1, 2, 3) t));
  exception when others then v_out := v_out || jsonb_build_object('touchpoints_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('touchpoints', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('spend', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'b2b_inr', b, 'b2c_inr', c) order by d desc), '[]')
      from (select coalesce(x.day, y.day) as d, x.b, y.c
              from (select day, sum(spend_inr) as b from b2b.ad_spend_daily where day > v_from::date group by 1) x
              full join (select day, sum(spend) as c from b2c.ad_spend_daily where day > v_from::date group by 1) y on y.day = x.day) s));
  exception when others then v_out := v_out || jsonb_build_object('spend_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('spend', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('nurture', b2c.nurture_overview());
  exception
    when insufficient_privilege then v_out := v_out || jsonb_build_object('nurture_error', 'needs your Spark marketing access');
    when others then v_out := v_out || jsonb_build_object('nurture_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('nurture', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_out := v_out || jsonb_build_object('numbers', (select coalesce(jsonb_agg(one.heartbeat_state(h.component) || jsonb_build_object('detail', h.detail) order by h.component), '[]')
                                                     from one.heartbeats h where h.component like 'whatsapp:%'));
  return one.redact(v_out, one.pii_keys()) || jsonb_build_object('ms', v_ms);
end $$;

create or replace function one.ui_analytics(p_days integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_steps jsonb := coalesce(one.setting('analytics') -> 'funnel', '[]');
  v_out jsonb := jsonb_build_object('days', v_days);
  v_ms jsonb := '{}';
  v_t timestamptz := clock_timestamp();
begin
  with steps as (
    select s.ord, s.step ->> 'key' as key, s.step ->> 'label' as label, s.step -> 'match' as match
      from jsonb_array_elements(v_steps) with ordinality s(step, ord)),
  hits as (
    select st.ord, e.lead_id, min(e.occurred_at) as at, count(*) as n
      from steps st join one.events e on e.occurred_at > v_from
       and exists (select 1 from jsonb_array_elements(st.match) m
                    where (m ->> 'app' is null or e.app = m ->> 'app') and e.type like (m ->> 'type'))
     group by st.ord, e.lead_id),
  per_step as (
    select st.ord, st.key, st.label,
           coalesce((select sum(h.n) from hits h where h.ord = st.ord), 0) as events,
           (select count(distinct h.lead_id) from hits h where h.ord = st.ord and h.lead_id is not null) as leads,
           (select round(percentile_cont(0.5) within group (order by extract(epoch from h.at - p.at) / 60)::numeric, 1)
              from hits h join hits p on p.lead_id = h.lead_id and p.ord = st.ord - 1 and h.at >= p.at where h.ord = st.ord) as median_min_from_previous
      from steps st)
  select v_out || jsonb_build_object('funnel', coalesce(jsonb_agg(to_jsonb(p) order by p.ord), '[]')) into v_out from per_step p;
  v_out := v_out || jsonb_build_object('events_by_app', (select coalesce(jsonb_object_agg(app, n), '{}') from (
             select app, count(*) as n from one.events where occurred_at > v_from group by 1) s));
  v_ms := v_ms || jsonb_build_object('funnel', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('partners', (select coalesce(jsonb_agg(jsonb_build_object('partner', coalesce(p.display_name, p.name, a.partner_id::text), 'allocated', a.n,
                                                                                                  'accepted', a.acc, 'enrolled', a.enr, 'lost', a.lost) order by a.n desc), '[]')
      from (select partner_id, count(*) as n, count(accepted_at) as acc, count(*) filter (where outcome = 'enrolled' or stage = 'enrolled') as enr, count(lost_at) as lost
              from b2b.allocations where not coalesce(is_test, false) and created_at > v_from group by 1) a
      left join b2b.partners p on p.id = a.partner_id));
  exception when others then v_out := v_out || jsonb_build_object('partners_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('partners', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_t := clock_timestamp();
  begin
    v_out := v_out || jsonb_build_object('counsellors', (select coalesce(jsonb_agg(jsonb_build_object('counsellor', coalesce(u.full_name, 'unassigned'), 'leads', t.n,
                                                                                                     'contacted', t.c, 'applied', t.a, 'enrolled', t.e,
                                                                                                     'median_first_contact_min', t.m) order by t.n desc), '[]')
      from (select owner_id, count(*) as n, count(contacted_at) as c, count(applied_at) as a, count(enrolled_at) as e,
                   round(percentile_cont(0.5) within group (order by first_contact_minutes)::numeric, 1) as m
              from b2c.fact_leads where not coalesce(is_test, false) and not coalesce(deleted, false) and assigned_at > v_from group by 1) t
      left join b2c.users u on u.user_id = t.owner_id));
  exception when others then v_out := v_out || jsonb_build_object('counsellors_error', left(sqlerrm, 160));
  end;
  v_ms := v_ms || jsonb_build_object('counsellors', round(extract(epoch from clock_timestamp() - v_t) * 1000));
  v_out := v_out || jsonb_build_object('ms', v_ms, 'views', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'params', v.params, 'schedule', v.schedule,
                                                                                           'created_by', v.created_by) order by v.name), '[]')
                                                   from one.saved_views v where v.page = 'analytics'));
  return v_out;
end $$;

drop function if exists one.app_ai_settings();
drop function if exists one.ai_tool(bigint, text, text, jsonb);
drop function if exists one.ai_tool_data(text, jsonb);
drop function if exists one.ai_defer(bigint, text, text, integer);
drop function if exists one.ai_fail(bigint, text, text, jsonb, boolean);
drop function if exists one.ai_finish(bigint, text, jsonb, jsonb);
drop function if exists one.ai_held(bigint, text);
drop function if exists one.ai_record_calls(bigint, jsonb);
drop function if exists one.ai_claim(text);
drop function if exists one.ai_step();
drop function if exists one.ai_schedule();
drop function if exists one.ai_context(one.ai_tasks);
drop function if exists one.ai_week_context();
drop function if exists one.ai_brief_stats(date);
drop function if exists one.ai_incident_context(bigint, text);
drop function if exists one.ai_witty_excerpts(timestamptz);
drop function if exists one.analytics_data(integer);
drop function if exists one.marketing_data(integer);
drop function if exists one.ai_risk(text, text);
drop function if exists one.ai_high_risk(one.incidents);
drop function if exists one.ai_priority(text);
drop function if exists one.ai_spent_today();

alter table one.deliveries drop column if exists brief_id;
alter table one.briefs drop column if exists task_id;
drop index if exists one.ai_tasks_open_idx;
alter table one.ai_tasks drop column if exists not_before;
alter table one.ai_tasks drop column if exists deferred_reason;

call one.apply_grants();
