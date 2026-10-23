-- 0012 the Apps, Marketing and Analytics pages (spec §3 "Embedding the five apps' UIs", §12). Eduwit One redoes no
-- app screen: a panel calls the app's own read function, or reads its tables in aggregate, and the page links into
-- the app for every write. Each panel runs inside one.ui_embed() as the signed-in person: an app function that checks
-- its own roles (b2b.is_admin(), b2c.can()) sees that person's JWT, so a person without access in the app gets "needs
-- your access" instead of data. Every answer passes through one.redact() before it leaves the database, and the call's
-- time is measured and returned (phase 4: "every embed RPC call is listed with its latency"; D-062).

-- The PII key list, for the redaction of panel answers.
create or replace function one.pii_keys() returns text[]
language sql stable set search_path = '' as $$
  select coalesce(array(select jsonb_array_elements_text(one.setting('events') -> 'pii_columns')), '{}')
$$;

-- The panel itself: one statement per panel id. Unknown ids raise P0002. Runs inside one.ui_embed's error block.
create or replace function one.embed_data(p_panel text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v jsonb;
begin
  case p_panel
    -- Witty (public w2_* functions are invoker-rights with unqualified names, D-042)
    when 'witty.health_alerts' then
      perform set_config('search_path', 'public, pg_temp', true);
      v := public.w2_health_alerts();
    when 'witty.digest' then
      perform set_config('search_path', 'public, pg_temp', true);
      v := public.w2_health_digest(24);
    when 'witty.outbox' then
      select coalesce(jsonb_object_agg(status, n), '{}') into v from (select status, count(*) as n from public.w2_outbox group by status) s;
    when 'witty.replies' then
      select coalesce(jsonb_agg(jsonb_build_object('day', d, 'replies', n, 'p50_ms', p50, 'p95_ms', p95, 'by_source', src) order by d desc), '[]') into v
        from (select (m.created_at at time zone 'Asia/Kolkata')::date as d, count(*) as n,
                     round(percentile_cont(0.5) within group (order by m.latency_ms)) as p50,
                     round(percentile_cont(0.95) within group (order by m.latency_ms)) as p95,
                     (select jsonb_object_agg(coalesce(x.reply_source, '?'), x.c) from (
                        select m2.reply_source, count(*) as c from public.w2_messages m2
                         where m2.direction = 'out' and (m2.created_at at time zone 'Asia/Kolkata')::date = (m.created_at at time zone 'Asia/Kolkata')::date
                         group by 1) x) as src
                from public.w2_messages m
               where m.direction = 'out' and m.created_at > now() - interval '7 days'
               group by 1) t;
    when 'witty.learnings' then
      select jsonb_build_object('by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.w2_learnings group by 1) s), '{}'),
                                'pending', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'title', l.title, 'confidence', l.confidence, 'at', l.created_at) order by l.id desc)
                                                       from (select * from public.w2_learnings where status = 'pending' order by id desc limit 20) l), '[]'))
        into v;
    when 'witty.prompts' then
      select coalesce(jsonb_agg(jsonb_build_object('name', p.name, 'version', p.version, 'updated_at', p.updated_at) order by p.name), '[]') into v from public.w2_prompts p;
    when 'witty.n8n' then
      select coalesce(jsonb_agg(one.heartbeat_state(h.component) || jsonb_build_object('detail', h.detail) order by h.component), '[]') into v
        from one.heartbeats h where h.component like 'n8n:%' or h.component in ('chatwoot', 'gemini', 'whatsapp:witty');
    -- B2B CRM (admin functions: they check b2b.is_admin() against the caller's JWT)
    when 'b2b.command_center' then v := b2b.command_center();
    when 'b2b.alert_feed' then v := b2b.alert_feed(30);
    when 'b2b.b2c_link' then v := b2b.b2c_link_overview();
    when 'b2b.capi' then v := b2b.capi_overview(null, null);
    when 'b2b.ai' then v := b2b.ai_overview();
    when 'b2b.dashboards' then v := b2b.dashboards_list();
    when 'b2b.health' then v := b2b.health_check();
    when 'b2b.partners' then
      select coalesce(jsonb_agg(jsonb_build_object('slug', p.slug, 'name', coalesce(p.display_name, p.name), 'status', p.status, 'adapter', p.adapter_type,
                                                   'daily_cap', p.daily_cap,
                                                   'allocations_30d', (select coalesce(jsonb_object_agg(a.status, a.n), '{}') from (
                                                      select status, count(*) as n from b2b.allocations
                                                       where partner_id = p.id and not coalesce(is_test, false) and created_at > now() - interval '30 days' group by 1) a))
                                order by p.slug), '[]') into v
        from b2b.partners p;
    -- Spark (direct reads where the owner chose them, D-006; its own functions where they exist, under the caller's role)
    when 'b2c.timers' then
      select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'last', r.status, 'at', r.start_time) order by j.jobname), '[]') into v
        from cron.job j left join lateral (select d.status, d.start_time from cron.job_run_details d
                                            where d.jobid = j.jobid and d.status in ('succeeded', 'failed')
                                              and d.runid > (select coalesce(max(x.runid), 0) - 100000 from cron.job_run_details x)
                                            order by d.runid desc limit 1) r on true
       where j.jobname like 'b2c-%';
    when 'b2c.queues' then
      select jsonb_build_object(
        'inbox', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from b2c.inbox group by 1) s),
        'outbox', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from b2c.outbox group by 1) s),
        'send_queue', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from b2c.send_queue group by 1) s)) into v;
    when 'b2c.connectors' then v := b2c.connectors_overview();
    when 'b2c.nurture' then v := b2c.nurture_overview();
    when 'b2c.counsellors' then
      select coalesce(jsonb_agg(jsonb_build_object('counsellor', coalesce(u.full_name, 'unassigned'), 'leads_30d', t.n, 'contacted', t.contacted, 'applied', t.applied,
                                                   'enrolled', t.enrolled, 'sla_met_pct', t.sla_pct, 'open', t.open) order by t.n desc), '[]') into v
        from (select f.owner_id, count(*) as n, count(f.contacted_at) as contacted, count(f.applied_at) as applied, count(f.enrolled_at) as enrolled,
                     round(100.0 * count(*) filter (where f.sla_met) / nullif(count(f.sla_met), 0)) as sla_pct,
                     count(*) filter (where f.lost_at is null and f.enrolled_at is null) as open
                from b2c.fact_leads f
               where not coalesce(f.is_test, false) and not coalesce(f.deleted, false) and f.assigned_at > now() - interval '30 days'
               group by 1) t
        left join b2c.users u on u.user_id = t.owner_id;
    -- Website (its own admin functions, run as the owner)
    when 'web.health' then v := public.web_health();
    when 'web.overview' then v := public.web_admin_overview();
    when 'web.quality' then v := public.web_data_quality();
    when 'web.seo' then v := public.web_seo_dashboard(28);
    when 'web.funnel' then
      select coalesce(jsonb_object_agg(k, n), '{}') into v
        from (select funnel || '.' || step as k, count(*) as n from public.web_funnel_events where at > now() - interval '7 days' group by 1) s;
    -- Influencer portal (aggregates; no creator contact field is read)
    when 'influencer.health' then v := one.inf_health();
    when 'influencer.creators' then
      select jsonb_build_object('by_status', coalesce(jsonb_object_agg(k, n), '{}')) into v
        from (select coalesce(status, '?') || ' / ' || coalesce(pipeline_stage, '?') as k, count(*) as n from inf.creators where not coalesce(is_test, false) group by 1) s;
    when 'influencer.clicks' then
      select coalesce(jsonb_agg(jsonb_build_object('day', d, 'clicks', n, 'bots', b) order by d desc), '[]') into v
        from (select (clicked_at at time zone 'Asia/Kolkata')::date as d, count(*) filter (where not coalesce(is_bot, false)) as n,
                     count(*) filter (where is_bot) as b
                from inf.link_clicks where clicked_at > now() - interval '30 days' group by 1) s;
    when 'influencer.outcomes' then
      select coalesce(jsonb_agg(jsonb_build_object('code', referral_code, 'leads', n, 'enrolled', e, 'by_stage', st) order by n desc), '[]') into v
        from (select o.referral_code, count(*) as n, count(*) filter (where o.enrolled) as e,
                     (select jsonb_object_agg(coalesce(x.stage, '?'), x.c) from (select stage, count(*) c from public.b2b_referral_outcomes x2
                        where x2.referral_code = o.referral_code group by 1) x) as st
                from public.b2b_referral_outcomes o group by 1) s;
    -- Eduwit One itself and the platform
    when 'one.health' then v := one.health();
    when 'one.runs' then
      select coalesce(jsonb_agg(jsonb_build_object('at', r.started_at, 'finished_at', r.finished_at, 'checks', r.report -> 'checks', 'app', r.report ->> 'app',
                                                   'errors', (select coalesce(jsonb_agg(k), '[]') from jsonb_object_keys(r.report) k where k like '%\_error')) order by r.id desc), '[]') into v
        from (select * from one.runs where kind = 'tick' order by id desc limit 30) r;
    when 'one.events' then
      select coalesce(jsonb_agg(jsonb_build_object('source', w.source, 'status', w.last_status, 'rows', w.rows_copied, 'at', w.updated_at, 'error', w.last_error) order by w.source), '[]') into v
        from one.event_watermarks w;
    when 'platform.cron' then
      select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'last', r.status, 'at', r.start_time,
                                                   'message', left(r.return_message, 160)) order by (r.status = 'failed') desc nulls last, j.jobname), '[]') into v
        from cron.job j left join lateral (select d.status, d.start_time, d.return_message from cron.job_run_details d
                                            where d.jobid = j.jobid and d.status in ('succeeded', 'failed')
                                              and d.runid > (select coalesce(max(x.runid), 0) - 100000 from cron.job_run_details x)
                                            order by d.runid desc limit 1) r on true;
    else
      raise exception 'no panel %', p_panel using errcode = 'P0002';
  end case;
  return v;
end $$;

-- One panel for the signed-in person: the data, redacted; whether it worked; how long it took.
create or replace function one.ui_embed(p_panel text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_started timestamptz := clock_timestamp();
  v_data jsonb;
  v_error text;
  v_kind text;
begin
  begin
    perform set_config('lock_timeout', '2s', true);
    v_data := one.embed_data(p_panel);
  exception
    when insufficient_privilege then
      v_kind := 'needs_access';
      v_error := 'needs your access in the app itself';
    when undefined_function or undefined_table or undefined_column or invalid_schema_name then
      v_kind := 'missing';
      v_error := 'not available on this database';
    when lock_not_available then
      v_kind := 'busy';
      v_error := 'the app''s table was locked; try again';
    when sqlstate 'P0002' then
      raise;
    when others then
      v_kind := 'error';
      v_error := left(sqlerrm, 200);
  end;
  perform set_config('search_path', '', true);
  return jsonb_build_object('panel', p_panel, 'ok', v_error is null, 'kind', v_kind, 'error', v_error,
                            'ms', round(extract(epoch from clock_timestamp() - v_started) * 1000),
                            'data', one.redact(v_data, one.pii_keys()));
end $$;

-- Marketing (spec §12): leads by platform and campaign per day, ad spend against leads, nurture, WhatsApp numbers.
create or replace function one.ui_marketing(p_days integer default 30) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 180);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_out jsonb := jsonb_build_object('days', v_days);
begin
  begin
    v_out := v_out || jsonb_build_object('leads', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'platform', p, 'campaign', c, 'leads', n) order by d desc, n desc), '[]')
      from (select (touched_at at time zone 'Asia/Kolkata')::date as d, coalesce(platform, 'organic') as p, coalesce(campaign_name, utm_campaign, '—') as c, count(*) as n
              from b2b.lead_campaigns where touched_at > v_from group by 1, 2, 3) s));
  exception when others then v_out := v_out || jsonb_build_object('leads_error', left(sqlerrm, 160));
  end;
  begin
    v_out := v_out || jsonb_build_object('touchpoints', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'source', s, 'event', e, 'n', n) order by d desc), '[]')
      from (select (occurred_at at time zone 'Asia/Kolkata')::date as d, coalesce(source_system, '?') as s, event_type as e, count(*) as n
              from public.touchpoints where occurred_at > v_from group by 1, 2, 3) t));
  exception when others then v_out := v_out || jsonb_build_object('touchpoints_error', left(sqlerrm, 160));
  end;
  begin
    v_out := v_out || jsonb_build_object('spend', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'b2b_inr', b, 'b2c_inr', c) order by d desc), '[]')
      from (select coalesce(x.day, y.day) as d, x.b, y.c
              from (select day, sum(spend_inr) as b from b2b.ad_spend_daily where day > v_from::date group by 1) x
              full join (select day, sum(spend) as c from b2c.ad_spend_daily where day > v_from::date group by 1) y on y.day = x.day) s));
  exception when others then v_out := v_out || jsonb_build_object('spend_error', left(sqlerrm, 160));
  end;
  begin
    v_out := v_out || jsonb_build_object('nurture', b2c.nurture_overview());
  exception
    when insufficient_privilege then v_out := v_out || jsonb_build_object('nurture_error', 'needs your Spark marketing access');
    when others then v_out := v_out || jsonb_build_object('nurture_error', left(sqlerrm, 160));
  end;
  v_out := v_out || jsonb_build_object('whatsapp', (select coalesce(jsonb_agg(one.heartbeat_state(h.component) || jsonb_build_object('detail', h.detail) order by h.component), '[]')
                                                      from one.heartbeats h where h.component like 'whatsapp:%'));
  return one.redact(v_out, one.pii_keys());
end $$;

-- Analytics (spec §12): the cross-app funnel from one.events (steps and their event types in settings.analytics), with
-- the median time between steps per lead; per-partner and per-counsellor views from the apps' own fact tables. Counts
-- only: no contact field is read, so an export of this page has none to include.
create or replace function one.ui_analytics(p_days integer default 30) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_steps jsonb := coalesce(one.setting('analytics') -> 'funnel', '[]');
  v_out jsonb := jsonb_build_object('days', v_days);
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
  begin
    v_out := v_out || jsonb_build_object('partners', (select coalesce(jsonb_agg(jsonb_build_object('partner', coalesce(p.display_name, p.name, a.partner_id::text), 'allocated', a.n,
                                                                                                  'accepted', a.acc, 'enrolled', a.enr, 'lost', a.lost) order by a.n desc), '[]')
      from (select partner_id, count(*) as n, count(accepted_at) as acc, count(*) filter (where outcome = 'enrolled' or stage = 'enrolled') as enr, count(lost_at) as lost
              from b2b.allocations where not coalesce(is_test, false) and created_at > v_from group by 1) a
      left join b2b.partners p on p.id = a.partner_id));
  exception when others then v_out := v_out || jsonb_build_object('partners_error', left(sqlerrm, 160));
  end;
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
  v_out := v_out || jsonb_build_object('views', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'params', v.params, 'schedule', v.schedule,
                                                                                           'created_by', v.created_by) order by v.name), '[]')
                                                   from one.saved_views v where v.page = 'analytics'));
  return v_out;
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.ui_embed(text)', 'authenticated', 'page read (0012): an app panel, as the signed-in person'),
  ('one.ui_marketing(integer)', 'authenticated', 'page read (0012): Marketing'),
  ('one.ui_analytics(integer)', 'authenticated', 'page read (0012): Analytics')
on conflict do nothing;
call one.apply_grants();
