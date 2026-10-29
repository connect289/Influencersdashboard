-- Rollback of 0023: restores 0012's one.embed_data verbatim (without the Catalogue Engine's panels).

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
      -- Test traffic (harness phones, Witty's trusted test numbers) is not a metric (spec §10, D-073).
      with m as (select (w.created_at at time zone 'Asia/Kolkata')::date as d, coalesce(w.reply_source, '?') as src, w.latency_ms
                   from public.w2_messages w
                  where w.direction = 'out' and w.created_at > now() - interval '7 days'
                    and regexp_replace(coalesce(w.phone, ''), '\D', '', 'g') !~ '^910000[0-9]{6}$'
                    and not exists (select 1 from public.w2_trusted t where t.phone = w.phone and t.is_test)),
           by_day as (select d, count(*) as n, round(percentile_cont(0.5) within group (order by latency_ms)) as p50,
                             round(percentile_cont(0.95) within group (order by latency_ms)) as p95 from m group by d),
           by_src as (select d, jsonb_object_agg(src, c) as src from (select d, src, count(*) as c from m group by 1, 2) x group by d)
      select coalesce(jsonb_agg(jsonb_build_object('day', b.d, 'replies', b.n, 'p50_ms', b.p50, 'p95_ms', b.p95, 'by_source', s.src) order by b.d desc), '[]')
        into v from by_day b left join by_src s on s.d = b.d;
    when 'witty.learnings' then
      select jsonb_build_object('by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.w2_learnings group by 1) s), '{}'),
                                'waiting', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'title', l.title, 'confidence', l.confidence, 'at', l.created_at) order by l.id desc)
                                                       from (select * from public.w2_learnings where status = 'proposed' order by id desc limit 20) l), '[]'))
        into v;
    when 'witty.prompts' then
      select coalesce(jsonb_agg(jsonb_build_object('prompt', p.name, 'version', p.version, 'updated_at', p.updated_at) order by p.name), '[]') into v from public.w2_prompts p;
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
      select coalesce(jsonb_agg(jsonb_build_object('slug', p.slug, 'partner', coalesce(p.display_name, p.name), 'status', p.status, 'adapter', p.adapter_type,
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
                                                   'error', case when r.status = 'failed' then left(r.return_message, 160) end)
                                order by (r.status = 'failed') desc nulls last, j.jobname), '[]') into v
        from cron.job j left join lateral (select d.status, d.start_time, d.return_message from cron.job_run_details d
                                            where d.jobid = j.jobid and d.status in ('succeeded', 'failed')
                                              and d.runid > (select coalesce(max(x.runid), 0) - 100000 from cron.job_run_details x)
                                            order by d.runid desc limit 1) r on true;
    else
      raise exception 'no panel %', p_panel using errcode = 'P0002';
  end case;
  return v;
end $$;
