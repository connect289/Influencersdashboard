-- B2C CRM b43: completing money, analytics, connectors, templates and platform (docs/completion-gaps.md D5-D12, D14, A12).
-- Staging first. Idempotent.
--   connectors         each connector's last success and last error; one overview (B2B, WhatsApp, Gmail, Claude, telephony) (B17)
--   user_connections   each person's own Gmail by OAuth; tokens sealed by the app, readable only by the service role (B16, B18)
--   metrics            Eduwit stage conversion and time per stage, B2C-created leads, duplicate cascades, suppression by cause,
--                      margin, receivables (B13.2)
--   alerts             metric alerts also by WhatsApp to one's own number (B13.3)
--   commission         the Admin's dashboard by counsellor, status and month, and the run calendar (B11.3)
--   emails             invoices to the university with the PDF; run statements to each counsellor (B11.1, B11.2)
--   guides             screenshots on guide articles (B15)
--   rate limits        counters the public /v1 endpoints check (B18)
--   templates          media headers, import from the WhatsApp account, version history, preview on a test lead,
--                      performance, a block editor for marketing email (B9.2, B9.2a)

-- ---------- connectors (D5) ----------
create table if not exists b2c.connector_status (
  key text primary key,                    -- b2b, whatsapp, gmail_system, gmail_marketing, claude, telephony, directory, calendar
  last_ok_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  detail jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table b2c.connector_status enable row level security;

/* The app's jobs report each call's outcome; detail carries figures such as WhatsApp's quality rating. */
create or replace function b2c.connector_report(p_key text, p_ok boolean, p_detail jsonb default null, p_error text default null) returns void
language sql security definer set search_path = '' as $f$
  insert into b2c.connector_status (key, last_ok_at, last_error_at, last_error, detail, updated_at)
  values (p_key, case when p_ok then now() end, case when not p_ok then now() end, case when not p_ok then left(p_error, 500) end, coalesce(p_detail, '{}'), now())
  on conflict (key) do update set
    last_ok_at = case when p_ok then now() else b2c.connector_status.last_ok_at end,
    last_error_at = case when not p_ok then now() else b2c.connector_status.last_error_at end,
    last_error = case when not p_ok then left(p_error, 500) else b2c.connector_status.last_error end,
    detail = b2c.connector_status.detail || coalesce(p_detail, '{}'), updated_at = now()
$f$;

create or replace function b2c.connectors_overview() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  perform b2c.require('settings');
  return jsonb_build_object(
    'status', (select coalesce(jsonb_object_agg(c.key, to_jsonb(c) - 'key'), '{}') from b2c.connector_status c),
    'b2b', jsonb_build_object(
       'queued', (select count(*) from b2c.outbox where status in ('queued', 'sending')),
       'refused_7d', (select count(*) from b2c.outbox where status in ('refused', 'conflict', 'failed') and done_at > now() - interval '7 days'),
       'last_applied_at', (select max(done_at) from b2c.outbox where status = 'applied')),
    'whatsapp', jsonb_build_object(
       'sent_today', (select count(*) from b2c.wa_messages where direction = 'out' and created_at >= d0 and status in ('sent', 'delivered', 'read')),
       'failed_today', (select count(*) from b2c.wa_messages where direction = 'out' and created_at >= d0 and status = 'failed'),
       'templates', (select jsonb_object_agg(status, n) from (select status, count(*) n from b2c.wa_templates where archived_at is null group by 1) t),
       'last_synced_at', (select max(synced_at) from b2c.wa_templates),
       'staff_template', exists (select 1 from b2c.wa_templates where name = b2c.setting('staff_alerts') ->> 'template' and status = 'approved' and archived_at is null)),
    'gmail', jsonb_build_object(
       'sent_today', (select count(*) from b2c.emails where direction = 'out' and created_at >= d0 and status in ('sent', 'delivered')),
       'marketing_today', (select count(*) from b2c.emails where direction = 'out' and created_at >= d0 and (purpose = 'marketing' or campaign_id is not null or journey_run_id is not null)),
       'allowance', coalesce((b2c.setting('messaging') ->> 'gmail_daily_allowance')::int, 2000),
       'by_user', (select coalesce(jsonb_agg(jsonb_build_object('name', u.full_name, 'sent_today', x.n)), '[]')
                     from (select user_id, count(*) n from b2c.emails where direction = 'out' and created_at >= d0 and user_id is not null group by 1) x
                     join b2c.users u on u.user_id = x.user_id),
       'connections', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from b2c.user_connections where provider = 'gmail' group by 1) c)),
    'claude', jsonb_build_object('spent_today', b2c.ai_spent_today(), 'budget', b2c.setting('ai')));
end $f$;

-- ---------- each person's own Gmail (D6) ----------
create table if not exists b2c.user_connections (
  user_id uuid not null references b2c.users (user_id),
  provider text not null check (provider in ('gmail')),
  account_email text not null,
  scopes text[] not null default '{}',
  token_sealed text,                       -- the refresh token, encrypted by the app (AES-GCM, key in the environment)
  status text not null default 'connected' check (status in ('connected', 'revoked', 'error', 'disconnected')),
  last_ok_at timestamptz,
  last_error text,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);
alter table b2c.user_connections enable row level security;
revoke all on b2c.user_connections from anon, authenticated;

/* After the OAuth callback (service role): the account must be the person's own @eduwit.in mailbox. */
create or replace function b2c.connection_save(p_user uuid, p_provider text, p_email text, p_scopes text[], p_token_sealed text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if lower(trim(p_email)) is distinct from (select lower(email) from b2c.users where user_id = p_user) then raise exception 'connect your own @eduwit.in mailbox'; end if;
  if not ('https://www.googleapis.com/auth/gmail.send' = any (coalesce(p_scopes, '{}'))) then raise exception 'Spark needs permission to send from Gmail'; end if;
  insert into b2c.user_connections (user_id, provider, account_email, scopes, token_sealed, status, last_ok_at, last_error, connected_at, updated_at)
  values (p_user, p_provider, lower(trim(p_email)), p_scopes, p_token_sealed, 'connected', now(), null, now(), now())
  on conflict (user_id, provider) do update set account_email = excluded.account_email, scopes = excluded.scopes, token_sealed = excluded.token_sealed,
         status = 'connected', last_ok_at = now(), last_error = null, connected_at = now(), updated_at = now();
  insert into b2c.audit_log (actor_id, action, detail) values (p_user, 'connection_saved', jsonb_build_object('provider', p_provider, 'scopes', p_scopes));
end $f$;

/* A send or a refresh failed; invalid_grant means the person revoked access in Google: they are told and asked to reconnect. */
create or replace function b2c.connection_mark(p_user uuid, p_provider text, p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare v_revoked boolean := not p_ok and coalesce(p_error, '') ~* '(invalid_grant|revoked|unauthorized_client)';
begin
  update b2c.user_connections set status = case when p_ok then 'connected' when v_revoked then 'revoked' else 'error' end,
         last_ok_at = case when p_ok then now() else last_ok_at end, last_error = case when p_ok then null else left(p_error, 300) end, updated_at = now()
   where user_id = p_user and provider = p_provider;
  if v_revoked then
    perform b2c.notify(p_user, 'connection', 'Reconnect your Gmail', 'Spark can no longer send from your mailbox.', '/s/me#connections', null,
                       'conn:' || p_user || ':' || to_char(now(), 'YYYYMMDD'));
  end if;
end $f$;

create or replace function b2c.my_connections() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('provider', c.provider, 'account_email', c.account_email, 'status', c.status, 'scopes', c.scopes,
            'last_ok_at', c.last_ok_at, 'last_error', c.last_error, 'connected_at', c.connected_at)), '[]')
            from b2c.user_connections c where c.user_id = b2c.uid());
end $f$;

create or replace function b2c.connection_disconnect(p_provider text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2c.user_connections set status = 'disconnected', token_sealed = null, updated_at = now() where user_id = b2c.uid() and provider = p_provider;
  insert into b2c.audit_log (actor_id, action, detail) values (b2c.uid(), 'connection_removed', jsonb_build_object('provider', p_provider));
end $f$;

/* The sealed token for a send (service role only). */
create or replace function b2c.connection_token(p_user uuid, p_provider text) returns text language sql stable security definer set search_path = '' as $f$
  select token_sealed from b2c.user_connections where user_id = p_user and provider = p_provider and status in ('connected', 'error')
$f$;

-- ---------- more metrics (D7) ----------
insert into b2c.an_sources (key, from_sql, actor_sql, lead_based) values
  ('suppressions', '(select s.*, null::bigint as lead_id from b2c.suppressions s) x', 'x.actor_id', false),
  ('invoices', '(select i.*, (i.issue_date::timestamp at time zone ''Asia/Kolkata'') as issued_at, u.name as university_name, null::bigint as lead_id from b2c.invoices i left join public.catalog_universities u on u.id = i.university_id where i.status not in (''draft'', ''discarded'')) x', 'null::uuid', false)
on conflict (key) do update set from_sql = excluded.from_sql, actor_sql = excluded.actor_sql, lead_based = excluded.lead_based;

insert into b2c.dim_defs (key, label, expr, sources, money, sort) values
  ('suppression_cause', 'Suppression cause', 'x.reason', '{suppressions}', false, 300),
  ('invoice_university', 'University (invoice)', 'x.university_name', '{invoices}', true, 301),
  ('invoice_status', 'Invoice status', 'x.status', '{invoices}', true, 302)
on conflict (key) do update set label = excluded.label, expr = excluded.expr, sources = excluded.sources, money = excluded.money;

insert into b2c.metric_defs (key, label, area, source, agg, date_sql, where_sql, fmt, roles, counts_leads, higher_is_better, description, sort) values
  ('b2c_created', 'Leads created by B2C', 'Intake', 'leads', 'count(*)', 'x.handed_off_at', 'x.source in (''b2c_created'', ''b2c_whatsapp'')', 'count', '{admin,marketing,sales}', true, true,
   'Leads the B2C team created itself (new lead form, WhatsApp from an unknown number)', 200),
  ('duplicate_cascades', 'Duplicate cascades', 'Intake', 'leads', 'count(*)', 'x.handed_off_at', 'x.handoff_reason like ''duplicate%''', 'count', '{admin,marketing}', true, false,
   'Leads handed over because they were already with partners; split by partner', 201),
  ('contact_rate', 'Assigned to contacted', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.contacted_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.assigned_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of assigned leads that were contacted', 202),
  ('counsel_rate', 'Contacted to counselled', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.counselled_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.contacted_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of contacted leads that were counselled', 203),
  ('apply_rate', 'Counselled to applied', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.applied_at is not null) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.counselled_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of counselled leads that applied', 204),
  ('enrol_rate_applied', 'Applied to enrolled', 'Sales funnel', 'leads', 'round(100.0 * count(*) filter (where x.enrolled_on is not null and not x.refunded) / nullif(count(*), 0), 1)', 'x.assigned_at', 'x.applied_at is not null', 'pct', '{admin,marketing,sales}', false, true,
   'Share of applicants that enrolled', 205),
  ('days_to_contact', 'Days assigned to contacted', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.contacted_at - x.assigned_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.contacted_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time spent before the first contact', 206),
  ('days_to_counsel', 'Days contacted to counselled', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.counselled_at - x.contacted_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.counselled_at is not null and x.contacted_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from first contact to counselling', 207),
  ('days_to_apply', 'Days counselled to applied', 'Sales funnel', 'leads', 'round(avg(extract(epoch from x.applied_at - x.counselled_at) / 86400)::numeric, 1)', 'x.assigned_at', 'x.applied_at is not null and x.counselled_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from counselling to application', 208),
  ('days_applied_to_enrol', 'Days applied to enrolled', 'Sales funnel', 'leads', 'round(avg(x.enrolled_on - (x.applied_at at time zone ''Asia/Kolkata'')::date)::numeric, 1)', 'x.assigned_at', 'x.enrolled_on is not null and x.applied_at is not null', 'days', '{admin,marketing,sales}', false, false,
   'Time from application to enrolment', 209),
  ('suppressions', 'Suppressions', 'Nurture', 'suppressions', 'count(*)', 'x.at', 'x.lifted_at is null', 'count', '{admin,marketing}', false, false,
   'Numbers and emails that may not be messaged, by cause', 210),
  ('margin', 'Margin after counsellor commission', 'Money', 'leads', 'coalesce(sum(coalesce(x.university_net, 0) - coalesce(x.counsellor_commission, 0)) filter (where x.enrolled_on is not null and not x.refunded), 0)', 'x.enrolled_at', null, 'money', '{admin,marketing}', false, true,
   'University commission net of GST, less the counsellor commission; split by university', 211),
  ('receivables', 'Receivables', 'Money', 'invoices', 'coalesce(sum(x.gross) filter (where x.status in (''approved'', ''sent'', ''part_paid'') and x.kind = ''invoice''), 0)', 'x.issued_at', null, 'money', '{admin,marketing}', false, false,
   'Invoiced to universities and not yet paid', 212),
  ('overdue_receivables', 'Overdue receivables', 'Money', 'invoices', 'coalesce(sum(x.gross) filter (where x.status in (''approved'', ''sent'', ''part_paid'') and x.kind = ''invoice'' and x.due_on < current_date), 0)', 'x.issued_at', null, 'money', '{admin,marketing}', false, false,
   'Invoices past their due date', 213)
on conflict (key) do update set label = excluded.label, area = excluded.area, source = excluded.source, agg = excluded.agg, date_sql = excluded.date_sql,
  where_sql = excluded.where_sql, fmt = excluded.fmt, roles = excluded.roles, counts_leads = excluded.counts_leads, higher_is_better = excluded.higher_is_better,
  description = excluded.description, sort = excluded.sort;

-- ---------- metric alerts by WhatsApp (D9) ----------
update b2c.settings set value = jsonb_set(value, '{kinds}', (select coalesce(jsonb_agg(distinct k), '[]') from jsonb_array_elements_text(value -> 'kinds' || '["alert"]') k))
 where key = 'staff_alerts' and not (value -> 'kinds') ? 'alert';

create or replace function b2c.alert_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v bigint := nullif(p ->> 'id', '')::bigint; me uuid := b2c.uid(); v_channels text[];
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_channels := coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'channels') x where x in ('push', 'email', 'whatsapp')), '{push}');
  if 'whatsapp' = any (v_channels) then
    if coalesce(b2c.norm_phone((select phone from b2c.users where user_id = me)), '') = '' then raise exception 'add your mobile number in Teams first'; end if;
    update b2c.users set wa_alerts = (select array_agg(distinct k) from unnest(wa_alerts || array['alert']) k) where user_id = me;
  end if;
  if v is null then
    perform b2c.analytics_run(jsonb_build_object('metrics', jsonb_build_array(p ->> 'metric'), 'filters', coalesce(p -> 'filters', '[]')));
    insert into b2c.metric_alerts (user_id, name, metric, filters, kind, op, threshold, win, channels)
    values (me, coalesce(nullif(trim(p ->> 'name'), ''), (select label from b2c.metric_defs where key = p ->> 'metric')), p ->> 'metric', coalesce(p -> 'filters', '[]'),
            coalesce(p ->> 'kind', 'threshold'), p ->> 'op', nullif(p ->> 'threshold', '')::numeric, coalesce(p ->> 'win', 'today'), v_channels)
    returning id into v;
  else
    update b2c.metric_alerts set active = coalesce((p ->> 'active')::boolean, active), channels = case when p ? 'channels' then v_channels else channels end
     where id = v and user_id = me;
    if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v;
end $f$;

-- ---------- the Admin's commission dashboard (D10) ----------
create or replace function b2c.commission_dashboard(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_from date := coalesce((p ->> 'from')::date, (date_trunc('month', now() at time zone 'Asia/Kolkata') - interval '11 months')::date);
        v_to date := coalesce((p ->> 'to')::date, (now() at time zone 'Asia/Kolkata')::date); v_test boolean := coalesce((p ->> 'test')::boolean, false);
begin
  if not b2c.can('read_money') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (with l as (
      select l.*, e.enrolled_on, e.university, e.programme, u.full_name counsellor
        from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id left join b2c.users u on u.user_id = l.counsellor_id
       where l.status <> 'void' and l.is_test = v_test and e.enrolled_on between v_from and v_to
         and (p ->> 'counsellor' is null or l.counsellor_id::text = p ->> 'counsellor') and (p ->> 'status' is null or l.status = p ->> 'status'))
    select jsonb_build_object(
      'totals', (select jsonb_build_object('amount', coalesce(sum(amount), 0), 'lines', count(*), 'enrollments', count(distinct enrollment_id)) from l),
      'by_counsellor', (select coalesce(jsonb_agg(jsonb_build_object('counsellor_id', counsellor_id, 'name', counsellor, 'amount', amount, 'lines', n, 'by_status', st, 'enrollment_ids', ids) order by amount desc), '[]')
                          from (select counsellor_id, counsellor, sum(amount) amount, count(*) n, jsonb_object_agg(status, s) st, array_agg(distinct enrollment_id) ids
                                  from (select counsellor_id, counsellor, status, enrollment_id, amount, sum(amount) over (partition by counsellor_id, status) s from l) q
                                 group by 1, 2) c),
      'by_status', (select coalesce(jsonb_object_agg(status, jsonb_build_object('amount', a, 'lines', n)), '{}') from (select status, sum(amount) a, count(*) n from l group by 1) s),
      'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'amount', a, 'lines', n, 'enrollment_ids', ids) order by m), '[]')
                     from (select to_char(enrolled_on, 'YYYY-MM') m, sum(amount) a, count(*) n, array_agg(distinct enrollment_id) ids from l group by 1) s),
      'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'period', r.period, 'status', r.status, 'totals', r.totals, 'approved_at', r.approved_at,
                       'pay_on', (r.period + interval '1 month' + make_interval(days => coalesce((b2c.setting('money') ->> 'commission_pay_day')::int, 10) - 1))::date) order by r.period desc), '[]')
                 from b2c.commission_runs r where r.is_test = v_test and r.period >= v_from - 31),
      'next_run', (date_trunc('month', now() at time zone 'Asia/Kolkata') + interval '1 month' - interval '1 day')::date));
end $f$;

-- ---------- invoices and statements by email (D11) ----------
/* The approved invoice to the university's billing email with the PDF (the app renders it when it sends). */
create or replace function b2c.invoice_send(p_id bigint, p_note text default null) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); i b2c.invoices; b b2c.university_billing; v bigint; v_from text := coalesce(b2c.setting('system_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
begin
  select * into i from b2c.invoices where id = p_id;
  if i.id is null or i.status not in ('approved', 'sent', 'part_paid') then raise exception 'approve the invoice first'; end if;
  select * into b from b2c.university_billing where university_id = i.university_id;
  if coalesce(b.email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'add the university''s billing email first'; end if;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
  values ('email', null, lower(b.email), jsonb_build_object('from', v_from, 'subject', case when i.kind = 'credit_note' then 'Credit note ' else 'Invoice ' end || i.number || ' from Eduwit',
          'text', 'Dear ' || coalesce(b.legal_name, 'Accounts team') || ',' || E'\n\n' || 'Please find attached ' || case when i.kind = 'credit_note' then 'credit note ' else 'invoice ' end
                  || i.number || ' for Rs ' || to_char(i.gross, 'FM99,99,99,999') || coalesce(', due on ' || to_char(i.due_on, 'DD Mon YYYY'), '') || '.'
                  || coalesce(E'\n\n' || nullif(trim(p_note), ''), '') || E'\n\n' || 'Eduwit',
          'html', null, 'marketing', false, 'attachments', jsonb_build_array(jsonb_build_object('kind', 'invoice_pdf', 'invoice_id', i.id))),
          'invoice', 'invoice:' || i.id || ':' || to_char(now(), 'YYYYMMDDHH24MI'))
  returning id into v;
  perform b2c.invoice_mark_sent(p_id);
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'invoice_emailed', jsonb_build_object('invoice', p_id, 'to', b.email));
  return v;
end $f$;

/* Each counsellor's statement for an approved run, to their own mailbox, with the PDF. */
create or replace function b2c.run_statements_send(p_run bigint) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('money'); r b2c.commission_runs; x record; n int := 0; v_from text := coalesce(b2c.setting('system_email') ->> 'from', 'Eduwit <connect@eduwit.in>');
begin
  select * into r from b2c.commission_runs where id = p_run;
  if r.id is null or r.status not in ('approved', 'paid') then raise exception 'approve the run first'; end if;
  for x in select l.counsellor_id, u.email, u.full_name, sum(l.amount) amount from b2c.commission_lines l join b2c.users u on u.user_id = l.counsellor_id
            where l.run_id = p_run and l.status <> 'void' group by 1, 2, 3 loop
    insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
    values ('email', null, x.email, jsonb_build_object('from', v_from, 'subject', 'Your commission statement for ' || to_char(r.period, 'Mon YYYY'),
            'text', 'Hi ' || split_part(coalesce(x.full_name, ''), ' ', 1) || ',' || E'\n\n' || 'Your commission statement for ' || to_char(r.period, 'Mon YYYY')
                    || ' is attached: Rs ' || to_char(x.amount, 'FM99,99,99,999') || '. It is also on the Money page in Spark.' || E'\n\n' || 'Eduwit',
            'html', null, 'marketing', false, 'attachments', jsonb_build_array(jsonb_build_object('kind', 'statement_pdf', 'run_id', p_run, 'user_id', x.counsellor_id))),
            'statement', 'statement:' || p_run || ':' || x.counsellor_id)
    on conflict do nothing;
    n := n + 1;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'statements_emailed', jsonb_build_object('run', p_run, 'counsellors', n));
  return n;
end $f$;

-- ---------- guide screenshots (D12) ----------
alter table b2c.user_guides add column if not exists images jsonb not null default '[]'::jsonb;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2c-guides', 'b2c-guides', false, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

/* Screenshots for an article: [{path, caption}] under guides/; the body shows one with ![caption](image:N). */
create or replace function b2c.guide_images_set(p_id bigint, p_images jsonb) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  if jsonb_typeof(p_images) <> 'array' or jsonb_array_length(p_images) > 12 then raise exception 'at most 12 screenshots'; end if;
  if exists (select 1 from jsonb_array_elements(p_images) x where coalesce(x ->> 'path', '') !~ '^guides/[A-Za-z0-9/_.-]+$') then raise exception 'screenshots are stored under guides/'; end if;
  update b2c.user_guides set images = p_images, updated_at = now(), updated_by = b2c.uid() where id = p_id;
  if not found then raise exception 'unknown article'; end if;
end $f$;

-- ---------- rate limits on the public endpoints (D14) ----------
create table if not exists b2c.rate_hits (
  key text not null,
  bucket timestamptz not null,
  n int not null default 0,
  primary key (key, bucket)
);
alter table b2c.rate_hits enable row level security;

/* One hit for key (e.g. 'v1:handoffs:<ip>') in a fixed window; false when over the limit. Old windows are cleared. */
create or replace function b2c.rate_check(p_key text, p_limit int, p_seconds int default 60) returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_bucket timestamptz := to_timestamp(floor(extract(epoch from now()) / p_seconds) * p_seconds); v int;
begin
  insert into b2c.rate_hits (key, bucket, n) values (left(p_key, 200), v_bucket, 1)
  on conflict (key, bucket) do update set n = b2c.rate_hits.n + 1 returning n into v;
  if random() < 0.01 then
    delete from b2c.rate_hits where bucket < now() - interval '1 hour';
  end if;
  return v <= p_limit;
end $f$;

-- ---------- templates (A12) ----------
alter table b2c.email_templates add column if not exists blocks jsonb;

/* A WhatsApp template header: text, or an image, document or video with a sample link Meta reviews. */
create or replace function b2c.wa_header_ok(p jsonb) returns boolean language sql immutable set search_path = '' as $f$
  select p is null or p = 'null'::jsonb or (
    jsonb_typeof(p) = 'object' and p ->> 'type' in ('text', 'image', 'document', 'video')
    and case when p ->> 'type' = 'text' then coalesce(length(trim(p ->> 'text')), 0) between 1 and 60
             else coalesce(p ->> 'example_url', '') ~ '^https://' end)
$f$;

create or replace function b2c.guard_wa_header() returns trigger language plpgsql set search_path = '' as $f$
begin
  if not b2c.wa_header_ok(new.header) then
    raise exception 'a header is text (at most 60 characters) or an image, document or video with a sample https link';
  end if;
  return new;
end $f$;
drop trigger if exists guard_wa_header on b2c.wa_templates;
create trigger guard_wa_header before insert or update of header on b2c.wa_templates for each row execute function b2c.guard_wa_header();

/* Templates already on the WhatsApp account (the app fetches them from Meta): new ones are added as marketing templates,
   known ones get Meta's status and id. Each change is a new version. */
create or replace function b2c.wa_template_import(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x jsonb; c jsonb; v_body text; v_header jsonb; v_buttons jsonb; v_vars jsonb; t b2c.wa_templates; n_new int := 0; n_upd int := 0; me uuid := b2c.uid();
begin
  if me is not null then perform b2c.require('settings'); end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'a list of templates'; end if;
  for x in select * from jsonb_array_elements(p) loop
    continue when coalesce(x ->> 'name', '') !~ '^[a-z0-9_]+$';
    v_body := null; v_header := null; v_buttons := '[]';
    for c in select * from jsonb_array_elements(coalesce(x -> 'components', '[]')) loop
      if c ->> 'type' = 'BODY' then v_body := c ->> 'text';
      elsif c ->> 'type' = 'HEADER' then
        v_header := case when c ->> 'format' = 'TEXT' then jsonb_build_object('type', 'text', 'text', left(c ->> 'text', 60))
                         else jsonb_build_object('type', lower(c ->> 'format'), 'example_url', coalesce(c -> 'example' -> 'header_handle' ->> 0, 'https://example.com')) end;
      elsif c ->> 'type' = 'BUTTONS' then v_buttons := coalesce(c -> 'buttons', '[]');
      end if;
    end loop;
    continue when v_body is null;
    select coalesce(jsonb_agg('var_' || m[1] order by m[1]::int), '[]') into v_vars from (select distinct regexp_matches(v_body, '\{\{(\d+)\}\}', 'g') m) q;
    select * into t from b2c.wa_templates where name = x ->> 'name' and language = coalesce(x ->> 'language', 'en');
    if t.id is null then
      insert into b2c.wa_templates (name, language, category, audience, body, variables, buttons, header, status, meta_template_id, synced_at, created_by)
      values (x ->> 'name', coalesce(x ->> 'language', 'en'), lower(coalesce(x ->> 'category', 'marketing')), 'marketing', v_body, v_vars, v_buttons, v_header,
              case lower(coalesce(x ->> 'status', '')) when 'approved' then 'approved' when 'rejected' then 'rejected' when 'paused' then 'paused' when 'disabled' then 'disabled' else 'submitted' end, x ->> 'id', now(), me)
      returning * into t;
      n_new := n_new + 1;
    else
      update b2c.wa_templates set status = case lower(coalesce(x ->> 'status', '')) when 'approved' then 'approved' when 'rejected' then 'rejected' when 'paused' then 'paused' when 'disabled' then 'disabled' else 'submitted' end, meta_template_id = coalesce(x ->> 'id', meta_template_id), synced_at = now(),
             body = case when lower(x ->> 'status') = 'approved' then v_body else body end, header = case when lower(x ->> 'status') = 'approved' then v_header else header end,
             version = version + case when body is distinct from v_body and lower(x ->> 'status') = 'approved' then 1 else 0 end, updated_at = now()
       where id = t.id returning * into t;
      n_upd := n_upd + 1;
    end if;
    insert into b2c.template_versions (kind, template_id, version, content, actor_id)
    select 'whatsapp', t.id, t.version, to_jsonb(t), me
     where not exists (select 1 from b2c.template_versions v where v.kind = 'whatsapp' and v.template_id = t.id and v.version = t.version);
  end loop;
  return jsonb_build_object('added', n_new, 'updated', n_upd);
end $f$;

create or replace function b2c.template_history(p_kind text, p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'at', v.at, 'by', u.full_name, 'content', v.content) order by v.version desc, v.at desc), '[]')
            from b2c.template_versions v left join b2c.users u on u.user_id = v.actor_id where v.kind = p_kind and v.template_id = p_id);
end $f$;

/* A template filled from a real test lead (test leads only, so no student's data is shown in the editor). */
create or replace function b2c.template_preview(p_kind text, p_id bigint, p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare t b2c.wa_templates; e b2c.email_templates; v_params jsonb;
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead and is_test) then raise exception 'preview with a test lead'; end if;
  if p_kind = 'whatsapp' then
    select * into t from b2c.wa_templates where id = p_id;
    if t.id is null then raise exception 'unknown template'; end if;
    v_params := b2c.template_params(t, p_lead, b2c.uid(), '{}');
    return jsonb_build_object('header', case when t.header ->> 'type' = 'text' then jsonb_build_object('type', 'text', 'text', b2c.render(t.header ->> 'text', v_params)) else t.header end,
                              'body', b2c.render(t.body, v_params), 'params', v_params, 'buttons', t.buttons);
  end if;
  select * into e from b2c.email_templates where id = p_id;
  if e.id is null then raise exception 'unknown template'; end if;
  return jsonb_build_object('subject', b2c.merge(e.subject, p_lead), 'body', b2c.merge(e.body, p_lead));
end $f$;

/* How each template does: sent, delivered, read or opened, clicked, replied, failed, cost. */
create or replace function b2c.template_performance(p_kind text, p_days int default 90) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('templates_marketing') or b2c.can('settings')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind = 'whatsapp' then
    return (select coalesce(jsonb_object_agg(template_id, jsonb_build_object('sent', sent, 'delivered', delivered, 'read', rd, 'failed', failed, 'replied', replied, 'cost', cost)), '{}')
      from (select m.template_id, count(*) filter (where m.status in ('sent', 'delivered', 'read')) sent, count(*) filter (where m.status in ('delivered', 'read')) delivered,
                   count(*) filter (where m.status = 'read') rd, count(*) filter (where m.status = 'failed') failed, coalesce(sum(m.cost_estimate), 0) cost,
                   count(*) filter (where exists (select 1 from b2c.wa_messages i where i.phone = m.phone and i.direction = 'in' and i.created_at > m.created_at
                                                   and i.created_at < m.created_at + interval '7 days')) replied
              from b2c.wa_messages m where m.direction = 'out' and m.template_id is not null and m.created_at > now() - make_interval(days => p_days) group by 1) s);
  end if;
  return (select coalesce(jsonb_object_agg(marketing_template_id, jsonb_build_object('sent', sent, 'opened', opened, 'clicked', clicked, 'bounced', bounced, 'replied', replied)), '{}')
    from (select e.marketing_template_id, count(*) sent, count(*) filter (where e.opened_at is not null) opened, count(*) filter (where e.clicked_at is not null) clicked,
                 count(*) filter (where e.bounced_at is not null) bounced,
                 count(*) filter (where exists (select 1 from b2c.emails i where i.direction = 'in' and i.lead_id = e.lead_id and i.created_at > e.created_at
                                                 and i.created_at < e.created_at + interval '14 days')) replied
            from b2c.emails e where e.direction = 'out' and e.marketing_template_id is not null and e.created_at > now() - make_interval(days => p_days) group by 1) s);
end $f$;

/* Marketing email templates may carry the block editor's layout; body stays the HTML that is sent. */
create or replace function b2c.email_template_m_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_marketing'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.email_templates;
begin
  if coalesce(trim(p ->> 'name'), '') = '' or coalesce(trim(p ->> 'subject'), '') = '' or coalesce(trim(p ->> 'body'), '') = '' then
    raise exception 'a template needs a name, a subject and a text';
  end if;
  if p ? 'blocks' and p -> 'blocks' <> 'null'::jsonb and (jsonb_typeof(p -> 'blocks') <> 'array' or jsonb_array_length(p -> 'blocks') > 60
       or exists (select 1 from jsonb_array_elements(p -> 'blocks') b where b ->> 'type' not in ('heading', 'text', 'image', 'button', 'divider', 'spacer', 'programme'))) then
    raise exception 'unknown block';
  end if;
  if v is null then
    insert into b2c.email_templates (name, language, subject, body, blocks, tags, created_by)
    values (trim(p ->> 'name'), coalesce(p ->> 'language', 'en'), left(p ->> 'subject', 300), left(p ->> 'body', 50000), p -> 'blocks',
            coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'), me)
    returning * into t;
  else
    update b2c.email_templates set name = trim(p ->> 'name'), language = coalesce(p ->> 'language', language), subject = left(p ->> 'subject', 300),
           body = left(p ->> 'body', 50000), blocks = case when p ? 'blocks' then p -> 'blocks' else blocks end,
           tags = case when p ? 'tags' then coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}') else tags end,
           archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
           version = version + 1, updated_at = now()
     where id = v returning * into t;
    if t.id is null then raise exception 'unknown template'; end if;
  end if;
  insert into b2c.template_versions (kind, template_id, version, content, actor_id) values ('email', t.id, t.version, to_jsonb(t), me);
  return t.id;
end $f$;

-- ---------- fixes found while building the screens ----------
-- yes/no filters also work on text fields (flagged is a reason, not a boolean), so older saved views keep working
CREATE OR REPLACE FUNCTION b2c.filter_sql(c jsonb, allowed text[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $f$
declare fld text := c ->> 'field'; op text := c ->> 'op'; val jsonb := c -> 'value'; d0 text := '(date_trunc(''day'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata'')';
begin
  if not fld = any (allowed) then raise exception 'cannot filter on %', fld; end if;
  return case op
    when 'eq' then format('%I::text = %L', fld, val #>> '{}')
    when 'neq' then format('%I::text is distinct from %L', fld, val #>> '{}')
    when 'in' then format('%I::text = any (%L::text[])', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'not_in' then format('not coalesce(%I::text = any (%L::text[]), false)', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'contains' then format('%I::text ilike %L', fld, '%' || (val #>> '{}') || '%')
    when 'gte' then format('%I >= %L', fld, val #>> '{}')
    when 'lte' then format('%I <= %L', fld, val #>> '{}')
    when 'gt' then format('%I > %L', fld, val #>> '{}')
    when 'lt' then format('%I < %L', fld, val #>> '{}')
    when 'between' then format('%I between %L and %L', fld, val ->> 0, val ->> 1)
    when 'is_null' then format('%I is null', fld)
    when 'not_null' then format('%I is not null', fld)
    when 'is_true' then format('coalesce(%I::text, '''') not in ('''', ''false'')', fld)
    when 'is_false' then format('coalesce(%I::text, '''') in ('''', ''false'')', fld)
    when 'lte_now' then format('%I <= now()', fld)
    when 'older_than_days' then format('%I < now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'within_days' then format('%I >= now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'next_days' then format('%I >= now() and %I < now() + make_interval(days => %s)', fld, fld, (val #>> '{}')::int)
    when 'today' then format('%I >= %s and %I < %s + interval ''1 day''', fld, d0, fld, d0)
    when 'this_week' then format('%I >= date_trunc(''week'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'this_month' then format('%I >= date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'last_month' then format('%I >= (date_trunc(''month'', now() at time zone ''Asia/Kolkata'') - interval ''1 month'') at time zone ''Asia/Kolkata'' and %I < date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld, fld)
    when 'has_tag' then format('%L = any (tags)', val #>> '{}')
    when 'not_tag' then format('not (%L = any (coalesce(tags, ''{}'')))', val #>> '{}')
    else 'false' end;
end $f$;

-- an export whose job died part-way is queued again
CREATE OR REPLACE FUNCTION b2c.export_take(p_limit integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  update b2c.exports set status = 'expired', path = null where status = 'ready' and expires_at < now();
  -- a job that died part-way is tried again (at most 3 times)
  update b2c.exports set status = case when attempts >= 3 then 'failed' else 'queued' end, error = coalesce(error, 'the export job stopped part-way')
   where status = 'running' and coalesce(done_at, created_at) < now() - interval '15 minutes' and created_at < now() - interval '15 minutes';
  with t as (select id from b2c.exports where status = 'queued' and attempts < 3 order by id limit p_limit for update skip locked),
       m as (update b2c.exports e set status = 'running', attempts = e.attempts + 1 from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id, 'params', m.params, 'format', m.format)), '[]') into v from m;
  return v;
end $f$;

-- an Analytics drill-down can be exported
CREATE OR REPLACE FUNCTION b2c.export_request(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare me uuid := b2c.require('settings'); v_n int; v bigint; v_fmt text := coalesce(p ->> 'format', 'csv');
begin
  if v_fmt not in ('csv', 'xlsx') then raise exception 'CSV or Excel'; end if;
  v_n := (b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'search', p ->> 'search', 'ids', p -> 'ids', 'drill', p ->> 'drill',
                                           'include_test', p -> 'include_test', 'limit', 1)) ->> 'total')::int;
  if v_n <= 10000 then return jsonb_build_object('inline', true, 'rows', v_n); end if;
  insert into b2c.exports (user_id, params, format) values (me, p - 'format', v_fmt) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'export', jsonb_build_object('job', v, 'rows', v_n, 'format', v_fmt, 'filters', p -> 'filters', 'columns', p -> 'columns'));
  return jsonb_build_object('inline', false, 'job_id', v, 'rows', v_n);
end $f$;

/* The replies that followed a campaign (within 7 days of the send), for the campaign's results. */
create or replace function b2c.campaign_replies(p_campaign bigint, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return (select coalesce(jsonb_agg(x order by x ->> 'at' desc), '[]') from (
    select distinct on (r.id) jsonb_build_object('reply_id', r.id, 'lead_id', r.lead_id, 'name', v.name, 'channel', r.channel, 'text', left(coalesce(r.text, r.button), 300),
             'class', coalesce(r.corrected_class, r.class), 'status', r.status, 'at', r.created_at, 'variant', s.variant) x
      from b2c.campaign_sends s join b2c.replies r on r.lead_id = s.lead_id and r.created_at > s.done_at and r.created_at < s.done_at + interval '7 days'
      left join b2c.leads_v v on v.lead_id = r.lead_id
     where s.campaign_id = p_campaign and s.done_at is not null
     order by r.id, s.done_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q);
end $f$;

-- ---------- grants ----------
grant execute on function b2c.connectors_overview(), b2c.my_connections(), b2c.connection_disconnect(text), b2c.alert_save(jsonb), b2c.commission_dashboard(jsonb),
  b2c.invoice_send(bigint, text), b2c.run_statements_send(bigint), b2c.guide_images_set(bigint, jsonb), b2c.wa_template_import(jsonb), b2c.template_history(text, bigint),
  b2c.template_preview(text, bigint, bigint), b2c.template_performance(text, integer), b2c.email_template_m_save(jsonb), b2c.campaign_replies(bigint, integer) to authenticated;
grant execute on function b2c.connector_report(text, boolean, jsonb, text), b2c.connection_save(uuid, text, text, text[], text), b2c.connection_mark(uuid, text, boolean, text),
  b2c.connection_token(uuid, text), b2c.rate_check(text, integer, integer), b2c.wa_template_import(jsonb) to service_role;
revoke execute on function b2c.connector_report(text, boolean, jsonb, text), b2c.connection_save(uuid, text, text, text[], text), b2c.connection_mark(uuid, text, boolean, text),
  b2c.connection_token(uuid, text), b2c.rate_check(text, integer, integer), b2c.wa_header_ok(jsonb), b2c.guard_wa_header() from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
