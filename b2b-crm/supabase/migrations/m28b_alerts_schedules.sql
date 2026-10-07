-- M28b: messages to the Admin (spec B13.3 metric alerts and scheduled delivery; B7.4 "alerts the Admin on WhatsApp and
-- email"). Sent from the database through the e-mail provider already set up for students (Resend or Brevo, key in Vault)
-- and, when a Meta-approved template is named, WhatsApp. Students never receive these.
--   admin_messages        the queue and log: kind (alert digest, metric alert, scheduled report), channel, recipients,
--                         subject, body, attachments, status, provider answer
--   metric_alerts         a threshold on any metric (with filters and a window), checked every 5 minutes, with a cooldown
--   report_schedules      a dashboard (or a report, M29) by e-mail: daily, weekly or monthly at an hour (IST); every
--                         widget's numbers in the e-mail, tables and breakdowns attached as CSV
--   settings 'admin_alerts': recipients (e-mails, WhatsApp numbers), the WhatsApp template, which alert types go out
--                         immediately, and the digest interval
--   admin_alerts_tick()   every minute: queues a digest of new alert.* events, checks metric alerts, runs due schedules,
--                         sends what is queued and collects provider answers

insert into b2b.settings (key, value) values ('admin_alerts', jsonb_build_object(
  'enabled', false, 'emails', '[]'::jsonb, 'whatsapp_numbers', '[]'::jsonb, 'whatsapp_template', null, 'whatsapp_language', 'en',
  'digest_minutes', 15,
  'types', jsonb_build_array('alert.partner_auto_paused', 'alert.ncpl_drop', 'alert.model_fallback', 'alert.sla_breach', 'alert.reconciliation_items',
                             'alert.partner_bad_signature', 'alert.notification_failed', 'alert.ai_budget', 'alert.ai_run_failed', 'routing.error')))
on conflict (key) do nothing;

create table if not exists b2b.admin_messages (
  id              bigint generated always as identity primary key,
  kind            text not null check (kind in ('alert_digest', 'metric_alert', 'report', 'test')),
  channel         text not null check (channel in ('email', 'whatsapp')),
  recipients      text[] not null,
  subject         text not null,
  body_text       text not null,
  body_html       text,
  attachments     jsonb not null default '[]',      -- [{filename, content_base64}]
  ref             jsonb not null default '{}',
  status          text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'skipped')),
  attempts        int not null default 0,
  net_request_id  bigint,
  provider        text,
  error           text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);
create index if not exists admin_messages_open_idx on b2b.admin_messages (status, created_at) where status in ('queued', 'sending');

create table if not exists b2b.metric_alerts (
  id            bigint generated always as identity primary key,
  name          text not null,
  metric        text not null references b2b.metric_definitions (key),
  filters       jsonb not null default '{}',
  window_hours  int not null default 24 check (window_hours between 1 and 2160),
  op            text not null check (op in ('>', '>=', '<', '<=')),
  threshold     numeric not null,
  min_volume    int not null default 0,            -- for rates: skip while the window has fewer rows than this (checked with the matching count metric when given)
  volume_metric text references b2b.metric_definitions (key),
  channels      text[] not null default '{email}',
  cooldown_hours int not null default 24 check (cooldown_hours between 1 and 720),
  active        boolean not null default true,
  last_value    numeric,
  last_checked_at timestamptz,
  last_fired_at timestamptz,
  created_by    text,
  created_at    timestamptz not null default now(),
  check (channels <@ array['email', 'whatsapp']::text[] and cardinality(channels) > 0)
);

create table if not exists b2b.report_schedules (
  id            bigint generated always as identity primary key,
  name          text not null,
  dashboard_id  bigint references b2b.dashboards (id),
  report_id     bigint,                              -- M29
  frequency     text not null check (frequency in ('daily', 'weekly', 'monthly')),
  hour_ist      int not null default 9 check (hour_ist between 0 and 23),
  weekday       int check (weekday between 1 and 7),  -- weekly: ISO day
  monthday      int check (monthday between 1 and 28),
  recipients    text[] not null,
  active        boolean not null default true,
  last_sent_at  timestamptz,
  next_due_at   timestamptz,
  created_by    text,
  created_at    timestamptz not null default now(),
  check (dashboard_id is not null or report_id is not null),
  check (cardinality(recipients) between 1 and 20)
);

do $rls$
declare t text;
begin
  foreach t in array array['admin_messages', 'metric_alerts', 'report_schedules'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- formatting ----------
create or replace function b2b.fmt_metric(p_value numeric, p_unit text)
returns text language sql immutable set search_path = '' as $fn$
  select case when p_value is null then '—'
              when p_unit = 'pct' then round(p_value * 100, 1)::text || '%'
              when p_unit = 'inr' then '₹' || to_char(round(p_value), 'FM99,99,99,99,999')
              when p_unit = 'usd' then '$' || round(p_value, 2)::text
              when p_unit = 'hours' then round(p_value, 1)::text || ' h'
              when p_unit = 'days' then round(p_value, 1)::text || ' days'
              when p_unit = 'minutes' then round(p_value, 1)::text || ' min'
              when p_unit = 'count' then to_char(round(p_value), 'FM999,999,999')
              else round(p_value, 2)::text end;
$fn$;

/* The period a dashboard or widget period names, ending now (IST calendar for month/quarter/year/today). */
create or replace function b2b.period_range(p_period text, p_at timestamptz default now())
returns tstzrange language sql stable set search_path = '' as $fn$
  select case p_period
    when 'today' then tstzrange(date_trunc('day', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata', p_at)
    when '7d' then tstzrange(p_at - interval '7 days', p_at)
    when '90d' then tstzrange(p_at - interval '90 days', p_at)
    when 'month' then tstzrange(date_trunc('month', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata', p_at)
    when 'quarter' then tstzrange(date_trunc('quarter', p_at at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata', p_at)
    when 'year' then tstzrange(p_at - interval '365 days', p_at)
    else tstzrange(p_at - interval '30 days', p_at) end;
$fn$;

/* A widget's data: the metric layer for chart widgets, the special lists for the rest. */
create or replace function b2b.widget_data(w jsonb, p_period text, p_filters jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  r tstzrange := b2b.period_range(coalesce(w ->> 'period', p_period));
  f jsonb := coalesce(p_filters, '{}') || coalesce(w -> 'filters', '{}');
  v_ok jsonb;
  k text;
  m text;
  v_out jsonb := '[]';
  i int;
begin
  if w ->> 'type' = 'text' then return '{}'; end if;
  if w ->> 'type' = 'sla_timers' then
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'lead_id', c.lead_id, 'sla', c.sla, 'due_at', c.due_at,
                                                                                     'partner', coalesce(p.display_name, p.name)) order by c.due_at)
                                                  from (select * from b2b.sla_checks c where c.status = 'pending' and not c.is_test
                                                          and (f -> 'partner' is null or c.partner_id::text in (select jsonb_array_elements_text(f -> 'partner')))
                                                        order by c.due_at limit 15) c join b2b.partners p on p.id = c.partner_id), '[]'));
  end if;
  if w ->> 'type' = 'alerts' then
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('type', e.type, 'at', e.occurred_at, 'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
                                                                                     'payload', e.payload - 'phone' - 'email' - 'name') order by e.occurred_at desc)
                                                  from (select * from b2b.events e where (e.type like 'alert.%' or e.type = 'routing.error') order by e.occurred_at desc limit 12) e), '[]'));
  end if;
  -- dashboard filters apply only where the metric has that dimension
  for m in select coalesce(w ->> 'metric', x) from (select null::text x union all select jsonb_array_elements_text(coalesce(w -> 'metrics', '[]'))) z
            where coalesce(w ->> 'metric', x) is not null loop
    v_ok := (select coalesce(jsonb_object_agg(fk, fv), '{}') from jsonb_each(f) e(fk, fv)
              where b2b.metric_dim_expr((select coalesce(d.fact, (select d2.fact from b2b.metric_definitions d2 where d2.key = (b2b.metric_bases(d))[1]))
                                           from b2b.metric_definitions d where d.key = m), 'created_at', fk) is not null);
    if w ->> 'type' = 'sankey' then
      for i in 1 .. jsonb_array_length(w -> 'steps') - 1 loop
        v_out := v_out || jsonb_build_array(b2b.metric_run(jsonb_build_object('metric', m, 'dims', jsonb_build_array(w -> 'steps' ->> (i - 1), w -> 'steps' ->> i),
                                                                              'filters', v_ok, 'from', lower(r), 'to', upper(r), 'compare', 'none', 'limit', 200)));
      end loop;
    else
      v_out := v_out || jsonb_build_array(b2b.metric_run(jsonb_build_object('metric', m, 'dims', coalesce(w -> 'dims', '[]'), 'filters', v_ok,
                                                                            'from', lower(r), 'to', upper(r), 'compare', case when w ->> 'type' in ('kpi', 'gauge', 'table', 'leaderboard') then 'previous' else 'none' end,
                                                                            'limit', case when w ->> 'type' in ('kpi', 'gauge') then 1 else 200 end)));
    end if;
  end loop;
  return jsonb_build_object('series', v_out, 'from', lower(r), 'to', upper(r));
end $fn$;

/* Every widget's data (internal: the Admin wrapper is dashboard_data, the e-mail renderer calls this directly). */
create or replace function b2b.dashboard_render(p_id bigint, p_period text default null, p_filters jsonb default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare d b2b.dashboards; w jsonb; v_out jsonb := '{}';
begin
  select * into d from b2b.dashboards where id = p_id and archived_at is null;
  if d.id is null then raise exception 'dashboard not found' using errcode = 'P0002'; end if;
  for w in select * from jsonb_array_elements(d.widgets) loop
    begin
      v_out := v_out || jsonb_build_object(w ->> 'id', b2b.widget_data(w, coalesce(p_period, d.period), coalesce(p_filters, d.filters)));
    exception when sqlstate '22023' then
      v_out := v_out || jsonb_build_object(w ->> 'id', jsonb_build_object('error', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('dashboard', to_jsonb(d), 'data', v_out, 'facts_at', (select value ->> 'refreshed_at' from b2b.ai_state where key = 'facts'));
end $fn$;

create or replace function b2b.dashboard_data(p_id bigint, p_period text default null, p_filters jsonb default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.dashboard_render(p_id, p_period, p_filters);
end $fn$;

-- ---------- sending ----------
/* The provider request for one admin message (e-mail through the student-notification provider settings). */
create or replace function b2b.admin_message_request(m b2b.admin_messages)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  e jsonb := coalesce(s -> 'email', '{}');
  w jsonb := coalesce(s -> 'whatsapp', '{}');
  v_key text;
begin
  if m.channel = 'whatsapp' then
    v_key := case when w ->> 'token_secret_id' is not null then b2b.partner_secret((w ->> 'token_secret_id')::uuid) end;
    if v_key is null or w ->> 'phone_number_id' is null or al ->> 'whatsapp_template' is null then return jsonb_build_object('error', 'WhatsApp for alerts is not configured (provider and an approved template)'); end if;
    return jsonb_build_object('provider', 'meta_cloud', 'many', true,
      'url', coalesce(w ->> 'base_url', 'https://graph.facebook.com') || '/' || coalesce(w ->> 'api_version', 'v21.0') || '/' || (w ->> 'phone_number_id') || '/messages',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      'bodies', (select jsonb_agg(jsonb_build_object('messaging_product', 'whatsapp', 'to', r, 'type', 'template',
                   'template', jsonb_build_object('name', al ->> 'whatsapp_template', 'language', jsonb_build_object('code', coalesce(al ->> 'whatsapp_language', 'en')),
                     'components', jsonb_build_array(jsonb_build_object('type', 'body', 'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', left(m.subject || ': ' || m.body_text, 900))))))))
                 from unnest(m.recipients) r));
  end if;
  v_key := case when e ->> 'api_key_secret_id' is not null then b2b.partner_secret((e ->> 'api_key_secret_id')::uuid) end;
  if v_key is null or e ->> 'from_email' is null then return jsonb_build_object('error', 'the e-mail provider is not configured (Notifications → Providers)'); end if;
  if coalesce(e ->> 'provider', 'resend') = 'brevo' then
    return jsonb_build_object('provider', 'brevo', 'url', coalesce(e ->> 'base_url', 'https://api.brevo.com') || '/v3/smtp/email',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'api-key', v_key),
      'body', jsonb_strip_nulls(jsonb_build_object('sender', jsonb_build_object('name', 'Eduwit B2B CRM', 'email', e ->> 'from_email'),
        'to', (select jsonb_agg(jsonb_build_object('email', r)) from unnest(m.recipients) r), 'subject', m.subject, 'textContent', m.body_text,
        'htmlContent', m.body_html,
        'attachment', case when jsonb_array_length(m.attachments) > 0 then (select jsonb_agg(jsonb_build_object('name', a ->> 'filename', 'content', a ->> 'content_base64')) from jsonb_array_elements(m.attachments) a) end)));
  end if;
  return jsonb_build_object('provider', 'resend', 'url', coalesce(e ->> 'base_url', 'https://api.resend.com') || '/emails',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'Idempotency-Key', 'admin-' || m.id),
    'body', jsonb_strip_nulls(jsonb_build_object('from', 'Eduwit B2B CRM <' || (e ->> 'from_email') || '>', 'to', to_jsonb(m.recipients), 'subject', m.subject,
      'text', m.body_text, 'html', m.body_html,
      'attachments', case when jsonb_array_length(m.attachments) > 0 then (select jsonb_agg(jsonb_build_object('filename', a ->> 'filename', 'content', a ->> 'content_base64')) from jsonb_array_elements(m.attachments) a) end)));
end $fn$;

create or replace function b2b.admin_queue(p_kind text, p_subject text, p_text text, p_html text, p_attachments jsonb, p_ref jsonb, p_channels text[] default '{email}', p_to text[] default null)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}'); v_n int := 0; v_to text[];
begin
  if 'email' = any (p_channels) then
    v_to := coalesce(p_to, (select array_agg(x) from jsonb_array_elements_text(coalesce(al -> 'emails', '[]')) x));
    if coalesce(cardinality(v_to), 0) > 0 then
      insert into b2b.admin_messages (kind, channel, recipients, subject, body_text, body_html, attachments, ref)
      values (p_kind, 'email', v_to, left(p_subject, 200), p_text, p_html, coalesce(p_attachments, '[]'), coalesce(p_ref, '{}'));
      v_n := v_n + 1;
    end if;
  end if;
  if 'whatsapp' = any (p_channels) and jsonb_array_length(coalesce(al -> 'whatsapp_numbers', '[]')) > 0 then
    insert into b2b.admin_messages (kind, channel, recipients, subject, body_text, ref)
    values (p_kind, 'whatsapp', (select array_agg(x) from jsonb_array_elements_text(al -> 'whatsapp_numbers') x), left(p_subject, 200), left(p_text, 900), coalesce(p_ref, '{}'));
    v_n := v_n + 1;
  end if;
  return v_n;
end $fn$;

/* Sends queued admin messages and collects answers (like notify_tick). Nothing goes out while admin_alerts.enabled is off. */
create or replace function b2b.admin_send_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  m b2b.admin_messages;
  req jsonb;
  b jsonb;
  v_net bigint;
  r record;
  v_sent int := 0;
begin
  -- answers
  for r in select x.id, x.attempts, x.updated, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null done
             from (select id, attempts, net_request_id, coalesce(sent_at, created_at) updated from b2b.admin_messages where status = 'sending' limit 100) x
             left join net._http_response h on h.id = x.net_request_id
  loop
    if not r.done then
      if r.updated < now() - interval '10 minutes' then update b2b.admin_messages set status = 'failed', error = 'no answer from the provider' where id = r.id; end if;
      continue;
    end if;
    if not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.admin_messages set status = 'sent', sent_at = now(), error = null where id = r.id;
    elsif r.attempts < 3 then
      update b2b.admin_messages set status = 'queued', error = left(coalesce(r.error_msg, 'HTTP ' || r.status_code || ': ' || left(r.content, 200)), 300) where id = r.id;
    else
      update b2b.admin_messages set status = 'failed', error = left(coalesce(r.error_msg, 'HTTP ' || r.status_code || ': ' || left(r.content, 200)), 300) where id = r.id;
    end if;
  end loop;
  if not coalesce((al ->> 'enabled')::boolean, false) then return jsonb_build_object('sent', 0, 'why', 'admin alerts are off'); end if;
  for m in select * from b2b.admin_messages where status = 'queued' and created_at > now() - interval '2 days' order by id limit 20 for update skip locked loop
    req := b2b.admin_message_request(m);
    if req ? 'error' then
      update b2b.admin_messages set status = 'failed', error = req ->> 'error' where id = m.id;
      continue;
    end if;
    if coalesce((req ->> 'many')::boolean, false) then
      for b in select * from jsonb_array_elements(req -> 'bodies') loop
        v_net := net.http_post(url := req ->> 'url', body := b, headers := req -> 'headers', timeout_milliseconds := 15000);
      end loop;
    else
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 20000);
    end if;
    update b2b.admin_messages set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider', sent_at = now() where id = m.id;
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('sent', v_sent);
end $fn$;

-- ---------- alerts ----------
/* New alert events since the last digest, as one message (B7.4: auto-pause, drop alerts, SLA breaches …). */
create or replace function b2b.alert_digest_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  v_last timestamptz := coalesce((select max(created_at) from b2b.admin_messages where kind = 'alert_digest'), now() - interval '1 hour');
  v_text text;
  v_n int;
  v_html text;
begin
  if v_last > now() - make_interval(mins => coalesce((al ->> 'digest_minutes')::int, 15)) then return 0; end if;
  select count(*), string_agg(format('• %s%s%s', replace(replace(e.type, 'alert.', ''), '_', ' '),
                                    coalesce(' — ' || (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id), ''),
                                    coalesce(': ' || left(coalesce(e.payload ->> 'reason', e.payload ->> 'error', e.payload ->> 'segment', ''), 160), '')), E'\n' order by e.occurred_at)
    into v_n, v_text
    from (select * from b2b.events e where e.occurred_at > v_last
            and e.type in (select jsonb_array_elements_text(coalesce(al -> 'types', '[]'))) order by e.occurred_at limit 50) e;
  if v_n = 0 then return 0; end if;
  v_html := '<div style="font-family:Arial,sans-serif;font-size:14px"><p><b>' || v_n || ' new alert' || case when v_n > 1 then 's' else '' end
            || '</b> in the Eduwit B2B CRM:</p><pre style="font-family:Arial,sans-serif;white-space:pre-wrap">' || b2b.html_escape(v_text) || '</pre></div>';
  return b2b.admin_queue('alert_digest', v_n || ' new alert' || case when v_n > 1 then 's' else '' end || ' in the B2B CRM', v_text, v_html, '[]',
                         jsonb_build_object('since', v_last), '{email,whatsapp}');
end $fn$;

create or replace function b2b.metric_alerts_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare a b2b.metric_alerts; v numeric; vol numeric; md b2b.metric_definitions; v_fire boolean; v_n int := 0; v_text text;
begin
  for a in select * from b2b.metric_alerts where active and (last_checked_at is null or last_checked_at < now() - interval '5 minutes') loop
    begin
      v := (b2b.metric_run(jsonb_build_object('metric', a.metric, 'filters', a.filters, 'from', now() - make_interval(hours => a.window_hours), 'to', now(), 'compare', 'none')) -> 'total' ->> 'value')::numeric;
      vol := case when a.volume_metric is not null then (b2b.metric_run(jsonb_build_object('metric', a.volume_metric, 'filters', a.filters, 'from', now() - make_interval(hours => a.window_hours), 'to', now(), 'compare', 'none')) -> 'total' ->> 'value')::numeric end;
      v_fire := v is not null and coalesce(vol, a.min_volume) >= a.min_volume
                and case a.op when '>' then v > a.threshold when '>=' then v >= a.threshold when '<' then v < a.threshold else v <= a.threshold end
                and (a.last_fired_at is null or a.last_fired_at < now() - make_interval(hours => a.cooldown_hours));
      update b2b.metric_alerts set last_value = v, last_checked_at = now(), last_fired_at = case when v_fire then now() else last_fired_at end where id = a.id;
      if v_fire then
        select * into md from b2b.metric_definitions where key = a.metric;
        v_text := format('%s: %s is %s (threshold %s %s) over the last %s hours%s.', a.name, md.label, b2b.fmt_metric(v, md.unit), a.op, b2b.fmt_metric(a.threshold, md.unit),
                         a.window_hours, case when a.filters <> '{}' then ', filters ' || a.filters::text else '' end);
        perform b2b.log_event('alert.metric', null, null, null, jsonb_build_object('alert_id', a.id, 'name', a.name, 'metric', a.metric, 'value', v, 'threshold', a.threshold, 'op', a.op));
        perform b2b.admin_queue('metric_alert', 'Alert: ' || a.name, v_text, '<p style="font-family:Arial,sans-serif;font-size:14px">' || b2b.html_escape(v_text) || '</p>',
                                '[]', jsonb_build_object('alert_id', a.id), a.channels);
        v_n := v_n + 1;
      end if;
    exception when sqlstate '22023' then
      update b2b.metric_alerts set last_checked_at = now(), active = false where id = a.id;
      perform b2b.log_event('alert.metric_invalid', null, null, null, jsonb_build_object('alert_id', a.id, 'error', sqlerrm));
    end;
  end loop;
  return v_n;
end $fn$;

-- ---------- scheduled delivery ----------
create or replace function b2b.schedule_next(s b2b.report_schedules, p_after timestamptz)
returns timestamptz language plpgsql stable set search_path = '' as $fn$
declare d date := (p_after at time zone 'Asia/Kolkata')::date; t timestamptz; i int;
begin
  for i in 0 .. 62 loop
    t := ((d + i)::timestamp + make_interval(hours => s.hour_ist)) at time zone 'Asia/Kolkata';
    if t > p_after and (s.frequency = 'daily'
                        or (s.frequency = 'weekly' and extract(isodow from d + i) = coalesce(s.weekday, 1))
                        or (s.frequency = 'monthly' and extract(day from d + i) = coalesce(s.monthday, 1))) then
      return t;
    end if;
  end loop;
  return p_after + interval '1 day';
end $fn$;

/* A dashboard rendered for e-mail: every widget's total (with the previous period) and its breakdown as CSV. */
create or replace function b2b.dashboard_email(p_dashboard_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  d jsonb;
  w jsonb;
  s jsonb;
  md jsonb;
  v_html text := '';
  v_text text := '';
  v_att jsonb := '[]';
  v_csv text;
  r jsonb;
begin
  d := b2b.dashboard_render(p_dashboard_id);
  for w in select * from jsonb_array_elements(d -> 'dashboard' -> 'widgets') loop
    continue when w ->> 'type' in ('text', 'alerts', 'sla_timers');
    for s in select * from jsonb_array_elements(coalesce(d -> 'data' -> (w ->> 'id') -> 'series', '[]')) loop
      md := s -> 'metric';
      v_html := v_html || format('<tr><td style="padding:4px 12px 4px 0">%s%s</td><td style="padding:4px 12px;text-align:right"><b>%s</b></td><td style="padding:4px 0;color:#666;text-align:right">%s</td></tr>',
                                 b2b.html_escape(coalesce(nullif(w ->> 'title', ''), md ->> 'label')),
                                 case when jsonb_array_length(coalesce(w -> 'metrics', '[]')) > 1 then ' · ' || b2b.html_escape(md ->> 'label') else '' end,
                                 b2b.fmt_metric((s -> 'total' ->> 'value')::numeric, md ->> 'unit'),
                                 case when s -> 'total' ->> 'prev' is not null then 'before: ' || b2b.fmt_metric((s -> 'total' ->> 'prev')::numeric, md ->> 'unit') else '' end);
      v_text := v_text || format('%s: %s', coalesce(nullif(w ->> 'title', ''), md ->> 'label'), b2b.fmt_metric((s -> 'total' ->> 'value')::numeric, md ->> 'unit')) || E'\n';
      if jsonb_array_length(coalesce(s -> 'rows', '[]')) > 0 and jsonb_array_length(coalesce(s -> 'dims', '[]')) > 0 then
        v_csv := (select string_agg(x, E'\n') from (
                    select (select string_agg(dd, ',') from jsonb_array_elements_text(s -> 'dims') dd) || ',value' x
                    union all
                    select (select string_agg('"' || replace(coalesce(case when s -> 'dims' ->> (o - 1)::int = 'partner' then coalesce(s -> 'labels' -> 'partner' ->> v, v) else v end, ''), '"', '""') || '"', ',' order by o)
                              from jsonb_array_elements_text(rw -> 'd') with ordinality q(v, o)) || ',' || coalesce(rw ->> 'value', '')
                      from jsonb_array_elements(s -> 'rows') rw) z);
        v_att := v_att || jsonb_build_object('filename', regexp_replace(lower(coalesce(nullif(w ->> 'title', ''), md ->> 'key')), '[^a-z0-9]+', '-', 'g') || '-' || (md ->> 'key') || '.csv',
                                             'content_base64', translate(encode(convert_to(v_csv, 'UTF8'), 'base64'), E'\n', ''));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('name', d -> 'dashboard' ->> 'name', 'text', v_text,
    'html', format('<div style="font-family:Arial,sans-serif;font-size:14px"><h2 style="font-size:18px">%s</h2><p style="color:#666">%s to %s (IST). Breakdowns are attached as CSV.</p><table>%s</table></div>',
                   b2b.html_escape(d -> 'dashboard' ->> 'name'),
                   to_char(((d -> 'data' -> (d -> 'dashboard' -> 'widgets' -> 0 ->> 'id') ->> 'from')::timestamptz) at time zone 'Asia/Kolkata', 'DD Mon YYYY'),
                   to_char(now() at time zone 'Asia/Kolkata', 'DD Mon YYYY HH24:MI'), v_html),
    'attachments', v_att);
end $fn$;

create or replace function b2b.schedules_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare s b2b.report_schedules; e jsonb; v_n int := 0;
begin
  for s in select * from b2b.report_schedules where active and coalesce(next_due_at, now()) <= now() for update skip locked loop
    begin
      if s.dashboard_id is not null then
        e := b2b.dashboard_email(s.dashboard_id);
      else
        e := b2b.report_email(s.report_id);
      end if;
      perform b2b.admin_queue('report', s.name || ': ' || (e ->> 'name'), e ->> 'text', e ->> 'html', e -> 'attachments', jsonb_build_object('schedule_id', s.id), '{email}', s.recipients);
      update b2b.report_schedules set last_sent_at = now(), next_due_at = b2b.schedule_next(s, now()) where id = s.id;
      v_n := v_n + 1;
    exception when others then
      update b2b.report_schedules set next_due_at = now() + interval '1 hour' where id = s.id;
      perform b2b.log_event('alert.schedule_failed', null, null, null, jsonb_build_object('schedule_id', s.id, 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return v_n;
end $fn$;

create or replace function b2b.admin_alerts_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_d int; v_m int; v_s int;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.admin_alerts_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  if coalesce((select (value ->> 'enabled')::boolean from b2b.settings where key = 'admin_alerts'), false) then
    v_d := b2b.alert_digest_tick();
  end if;
  v_m := b2b.metric_alerts_tick();
  v_s := b2b.schedules_tick();
  return jsonb_build_object('digest', coalesce(v_d, 0), 'metric_alerts', v_m, 'schedules', v_s, 'send', b2b.admin_send_tick());
end $fn$;

-- M29 replaces this with the report renderer
create or replace function b2b.report_email(p_report_id bigint)
returns jsonb language plpgsql stable set search_path = '' as $fn$
begin
  raise exception 'reports are not available yet' using errcode = '22023';
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-admin-alerts';
  perform cron.schedule('b2b-admin-alerts', '* * * * *', 'select b2b.admin_alerts_tick()');
end $cron$;

-- ---------- Admin ----------
create or replace function b2b.admin_alerts_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', (select value from b2b.settings where key = 'admin_alerts'), 'settings_version', (select version from b2b.settings where key = 'admin_alerts'),
    'email_ready', (select (value -> 'email' ->> 'api_key_secret_id') is not null and (value -> 'email' ->> 'from_email') is not null from b2b.settings where key = 'notifications'),
    'alerts', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('metric_label', (select label from b2b.metric_definitions where key = a.metric),
                                                                           'unit', (select unit from b2b.metric_definitions where key = a.metric)) order by a.id desc) from b2b.metric_alerts a), '[]'),
    'schedules', coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object('dashboard', (select name from b2b.dashboards where id = s.dashboard_id)) order by s.id desc) from b2b.report_schedules s), '[]'),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'channel', m.channel, 'recipients', cardinality(m.recipients), 'subject', m.subject,
                                                              'status', m.status, 'error', m.error, 'created_at', m.created_at, 'sent_at', m.sent_at,
                                                              'attachments', jsonb_array_length(m.attachments)) order by m.id desc)
                            from (select * from b2b.admin_messages order by id desc limit 30) m), '[]'));
end $fn$;

create or replace function b2b.admin_alerts_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'emails' and (jsonb_typeof(p -> 'emails') <> 'array' or jsonb_array_length(p -> 'emails') > 10
                       or exists (select 1 from jsonb_array_elements_text(p -> 'emails') x where x !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$')) then
    raise exception 'up to 10 e-mail addresses' using errcode = '22023';
  end if;
  if p ? 'whatsapp_numbers' and (jsonb_typeof(p -> 'whatsapp_numbers') <> 'array' or jsonb_array_length(p -> 'whatsapp_numbers') > 5
                                 or exists (select 1 from jsonb_array_elements_text(p -> 'whatsapp_numbers') x where x !~ '^[0-9]{10,15}$')) then
    raise exception 'up to 5 WhatsApp numbers, digits with the country code' using errcode = '22023';
  end if;
  if p ? 'digest_minutes' and not ((p ->> 'digest_minutes')::int between 5 and 1440) then raise exception 'the digest interval is 5 to 1440 minutes' using errcode = '22023'; end if;
  if p ? 'enabled' and jsonb_typeof(p -> 'enabled') <> 'boolean' then raise exception 'on or off' using errcode = '22023'; end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('enabled', p -> 'enabled', 'emails', p -> 'emails', 'whatsapp_numbers', p -> 'whatsapp_numbers',
                                                 'digest_minutes', (p ->> 'digest_minutes')::int, 'whatsapp_language', p ->> 'whatsapp_language'))
       || case when p ? 'whatsapp_template' then jsonb_build_object('whatsapp_template', nullif(trim(p ->> 'whatsapp_template'), '')) else '{}' end;
  return b2b.set_setting('admin_alerts', v, p_reason);
end $fn$;

create or replace function b2b.metric_alert_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; v_ch text[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'give the alert a name' using errcode = '22023'; end if;
  if not exists (select 1 from b2b.metric_definitions where key = p ->> 'metric') then raise exception 'unknown metric' using errcode = '22023'; end if;
  if p ->> 'op' not in ('>', '>=', '<', '<=') then raise exception 'choose above or below' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'threshold') <> 'number' then raise exception 'the threshold is a number' using errcode = '22023'; end if;
  select coalesce(array_agg(x), '{email}') into v_ch from jsonb_array_elements_text(coalesce(p -> 'channels', '["email"]')) x;
  -- the filters must be valid for the metric (raises 22023 otherwise)
  perform b2b.metric_run(jsonb_build_object('metric', p ->> 'metric', 'filters', coalesce(p -> 'filters', '{}'), 'from', now() - interval '1 hour', 'to', now(), 'compare', 'none'));
  if v_id is null then
    insert into b2b.metric_alerts (name, metric, filters, window_hours, op, threshold, min_volume, volume_metric, channels, cooldown_hours, created_by)
    values (left(trim(p ->> 'name'), 80), p ->> 'metric', coalesce(p -> 'filters', '{}'), coalesce((p ->> 'window_hours')::int, 24), p ->> 'op', (p ->> 'threshold')::numeric,
            coalesce((p ->> 'min_volume')::int, 0), nullif(p ->> 'volume_metric', ''), v_ch, coalesce((p ->> 'cooldown_hours')::int, 24), coalesce(auth.uid()::text, 'admin'))
    returning id into v_id;
  else
    update b2b.metric_alerts set name = left(trim(p ->> 'name'), 80), metric = p ->> 'metric', filters = coalesce(p -> 'filters', '{}'),
           window_hours = coalesce((p ->> 'window_hours')::int, 24), op = p ->> 'op', threshold = (p ->> 'threshold')::numeric, min_volume = coalesce((p ->> 'min_volume')::int, 0),
           volume_metric = nullif(p ->> 'volume_metric', ''), channels = v_ch, cooldown_hours = coalesce((p ->> 'cooldown_hours')::int, 24),
           active = coalesce((p ->> 'active')::boolean, active)
     where id = v_id;
    if not found then raise exception 'alert not found' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function b2b.schedule_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; v_to text[]; s b2b.report_schedules;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'give the schedule a name' using errcode = '22023'; end if;
  if p ->> 'frequency' not in ('daily', 'weekly', 'monthly') then raise exception 'daily, weekly or monthly' using errcode = '22023'; end if;
  select array_agg(lower(trim(x))) into v_to from jsonb_array_elements_text(coalesce(p -> 'recipients', '[]')) x;
  if coalesce(cardinality(v_to), 0) = 0 or cardinality(v_to) > 20 or exists (select 1 from unnest(v_to) x where x !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$') then
    raise exception '1 to 20 e-mail addresses' using errcode = '22023';
  end if;
  if (p ->> 'dashboard_id') is null and (p ->> 'report_id') is null then raise exception 'choose a dashboard or a report' using errcode = '22023'; end if;
  if (p ->> 'dashboard_id') is not null and not exists (select 1 from b2b.dashboards where id = (p ->> 'dashboard_id')::bigint and archived_at is null) then
    raise exception 'dashboard not found' using errcode = 'P0002';
  end if;
  if v_id is null then
    insert into b2b.report_schedules (name, dashboard_id, report_id, frequency, hour_ist, weekday, monthday, recipients, created_by)
    values (left(trim(p ->> 'name'), 80), (p ->> 'dashboard_id')::bigint, (p ->> 'report_id')::bigint, p ->> 'frequency', coalesce((p ->> 'hour_ist')::int, 9),
            (p ->> 'weekday')::int, (p ->> 'monthday')::int, v_to, coalesce(auth.uid()::text, 'admin'))
    returning id into v_id;
  else
    update b2b.report_schedules set name = left(trim(p ->> 'name'), 80), dashboard_id = (p ->> 'dashboard_id')::bigint, report_id = (p ->> 'report_id')::bigint,
           frequency = p ->> 'frequency', hour_ist = coalesce((p ->> 'hour_ist')::int, 9), weekday = (p ->> 'weekday')::int, monthday = (p ->> 'monthday')::int,
           recipients = v_to, active = coalesce((p ->> 'active')::boolean, active)
     where id = v_id;
    if not found then raise exception 'schedule not found' using errcode = 'P0002'; end if;
  end if;
  select * into s from b2b.report_schedules where id = v_id;
  update b2b.report_schedules set next_due_at = b2b.schedule_next(s, now()) where id = v_id;
  return jsonb_build_object('id', v_id, 'next_due_at', (select next_due_at from b2b.report_schedules where id = v_id));
end $fn$;

/* A test message to the configured recipients (queued; sent by the tick when alerts are on). */
create or replace function b2b.admin_alerts_test()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('queued', b2b.admin_queue('test', 'Test alert from the Eduwit B2B CRM', 'This is a test. Alerts reach you here.',
                                                      '<p>This is a test. Alerts reach you here.</p>', '[]', '{}', '{email,whatsapp}'));
end $fn$;

revoke execute on function b2b.fmt_metric(numeric, text), b2b.period_range(text, timestamptz), b2b.widget_data(jsonb, text, jsonb), b2b.admin_message_request(b2b.admin_messages),
                           b2b.admin_queue(text, text, text, text, jsonb, jsonb, text[], text[]), b2b.admin_send_tick(), b2b.alert_digest_tick(), b2b.metric_alerts_tick(),
                           b2b.schedule_next(b2b.report_schedules, timestamptz), b2b.dashboard_email(bigint), b2b.schedules_tick(), b2b.admin_alerts_tick(), b2b.report_email(bigint),
                           b2b.dashboard_render(bigint, text, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.fmt_metric(numeric, text), b2b.period_range(text, timestamptz), b2b.widget_data(jsonb, text, jsonb), b2b.admin_message_request(b2b.admin_messages),
                          b2b.admin_queue(text, text, text, text, jsonb, jsonb, text[], text[]), b2b.admin_send_tick(), b2b.alert_digest_tick(), b2b.metric_alerts_tick(),
                          b2b.schedule_next(b2b.report_schedules, timestamptz), b2b.dashboard_email(bigint), b2b.schedules_tick(), b2b.admin_alerts_tick(), b2b.report_email(bigint),
                          b2b.dashboard_render(bigint, text, jsonb)
  to service_role;
revoke execute on function b2b.dashboard_data(bigint, text, jsonb), b2b.admin_alerts_overview(), b2b.admin_alerts_settings_save(jsonb, text), b2b.metric_alert_save(jsonb),
                           b2b.schedule_save(jsonb), b2b.admin_alerts_test() from public, anon;
grant execute on function b2b.dashboard_data(bigint, text, jsonb), b2b.admin_alerts_overview(), b2b.admin_alerts_settings_save(jsonb, text), b2b.metric_alert_save(jsonb),
                          b2b.schedule_save(jsonb), b2b.admin_alerts_test() to authenticated, service_role;
