-- b37 (17 Oct 2026): more for every role.
--   Sales:     saved WhatsApp snippets (own and shared), bulk tag / follow-ups / template send over the ticked leads of a view,
--              "Suggest a correction" on the Programme page (a support ticket to the Admin).
--   Marketing: the campaign calendar (one month of campaigns and automated sends).
--   Admin:     system health (timers, queues, feeds, the app, Claude's spend), the audit-log and sign-in viewers,
--              duplicate suspects (leads sharing a phone or email).
-- Idempotent; every function is SECURITY DEFINER with an empty search_path and checks its caller.

-- ---------- snippets (B8.5: "quick replies and saved snippets" in the free-text window) ----------
create table if not exists b2c.snippets (
  id bigint generated always as identity primary key,
  owner_id uuid not null references b2c.users (user_id),
  title text not null check (length(title) between 1 and 60),
  body text not null check (length(body) between 1 and 1000),
  shared boolean not null default false,          -- visible to every counsellor; the author's text never changes for others
  uses int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table b2c.snippets enable row level security;
create index if not exists ix_snippets_owner_id on b2c.snippets (owner_id);
do $d$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'snippets' and policyname = 'snippets_read') then
    create policy snippets_read on b2c.snippets for select to authenticated
      using (deleted_at is null and (owner_id = b2c.uid() or (shared and b2c.is_staff())));
  end if;
end $d$;
revoke all on b2c.snippets from anon;
grant select on b2c.snippets to authenticated;

/* Own snippets first, then the ones others share, with the author's name. */
create or replace function b2c.snippets_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'title', s.title, 'body', s.body, 'shared', s.shared, 'uses', s.uses,
                                               'mine', s.owner_id = b2c.uid(), 'author', u.full_name, 'updated_at', s.updated_at)
                            order by (s.owner_id = b2c.uid()) desc, s.uses desc, s.title), '[]'::jsonb)
    from b2c.snippets s join b2c.users u on u.user_id = s.owner_id
   where s.deleted_at is null and b2c.is_staff() and (s.owner_id = b2c.uid() or s.shared)
$f$;

create or replace function b2c.snippet_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint;
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(coalesce(trim(p ->> 'title'), '')) = 0 then raise exception 'name the snippet'; end if;
  if length(coalesce(trim(p ->> 'body'), '')) = 0 then raise exception 'write the text'; end if;
  if v is null then
    if (select count(*) from b2c.snippets where owner_id = me and deleted_at is null) >= 100 then raise exception 'at most 100 snippets'; end if;
    insert into b2c.snippets (owner_id, title, body, shared) values (me, left(trim(p ->> 'title'), 60), left(trim(p ->> 'body'), 1000), coalesce((p ->> 'shared')::boolean, false))
    returning id into v;
  else
    update b2c.snippets set title = left(trim(p ->> 'title'), 60), body = left(trim(p ->> 'body'), 1000), shared = coalesce((p ->> 'shared')::boolean, shared), updated_at = now()
     where id = v and deleted_at is null and (owner_id = me or b2c.my_role() = 'admin');
    if not found then raise exception 'not your snippet' using errcode = '42501'; end if;
  end if;
  return v;
end $f$;

create or replace function b2c.snippet_delete(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.snippets set deleted_at = now() where id = p_id and deleted_at is null and (owner_id = b2c.uid() or b2c.my_role() = 'admin');
  if not found then raise exception 'not your snippet' using errcode = '42501'; end if;
end $f$;

/* Counted when a snippet is inserted into a message, so the useful ones rise. */
create or replace function b2c.snippet_used(p_id bigint) returns void language sql security definer set search_path = '' as $f$
  update b2c.snippets set uses = uses + 1 where id = p_id and deleted_at is null and b2c.is_staff() and (owner_id = b2c.uid() or shared)
$f$;

-- ---------- bulk actions for counsellors (B8.2: tag, follow-ups, a template to several leads) ----------
/* A tag on the ticked leads: Admin and Marketing on any lead (as b2c.tag), a counsellor on their own leads only. */
create or replace function b2c.tag_own(p_leads bigint[], p_tag text, p_add boolean) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid; n int;
begin
  if b2c.can('tags') then return b2c.tag(p_leads, p_tag, p_add); end if;
  me := b2c.require('work_leads');
  if coalesce(trim(p_tag), '') = '' then raise exception 'name the tag'; end if;
  if cardinality(p_leads) > 200 then raise exception 'at most 200 leads at a time'; end if;
  update b2c.leads_state set tags = case when p_add then array(select distinct unnest(tags || array[lower(trim(p_tag))])) else array_remove(tags, lower(trim(p_tag))) end,
         updated_at = now()
   where lead_id = any (p_leads) and deleted_at is null and (owner_id = me or b2c.my_role() = 'sales_head');
  get diagnostics n = row_count;
  return n;
end $f$;

/* The same follow-up on every ticked lead (own leads; others are skipped and named). */
create or replace function b2c.tasks_bulk(p_leads bigint[], p_kind text, p_title text, p_due timestamptz, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); l bigint; n int := 0; skipped jsonb := '[]'::jsonb;
begin
  if cardinality(p_leads) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 100 then raise exception 'at most 100 leads at a time'; end if;
  if p_due is null or p_due < now() - interval '1 minute' then raise exception 'pick a time in the future'; end if;
  foreach l in array p_leads loop
    begin
      perform b2c.task_add(l, p_kind, p_title, p_due, p_note);
      n := n + 1;
    exception when others then
      skipped := skipped || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('created', n, 'skipped', skipped);
end $f$;

/* One approved sales template to several leads, under the same rules as a single send (B8.5): own leads, not opted out,
   not during a Witty chat. Each refusal is named. At most 50 at a time so a slip never floods the number. */
create or replace function b2c.wa_bulk_template(p_leads bigint[], p_template bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); l bigint; n int := 0; refused jsonb := '[]'::jsonb;
begin
  if cardinality(p_leads) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 50 then raise exception 'at most 50 leads at a time'; end if;
  foreach l in array p_leads loop
    begin
      perform b2c.wa_queue_template(l, p_template);
      n := n + 1;
    exception when others then
      refused := refused || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'wa_bulk', jsonb_build_object('template', p_template, 'sent', n, 'refused', jsonb_array_length(refused)));
  return jsonb_build_object('sent', n, 'refused', refused);
end $f$;

-- ---------- "Suggest a correction" on the Programme page (B8.9) ----------
/* A support ticket of kind data, so the Admin sees it in Support with the programme named; the Admin is told at once. */
create or replace function b2c.catalogue_suggest(p_programme bigint, p_note text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_name text; r jsonb;
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(coalesce(trim(p_note), '')) < 5 then raise exception 'say what is wrong'; end if;
  select coalesce(p.program_name, p.course) || coalesce(' · ' || p.specialization, '') || coalesce(' · ' || u.name, '')
    into v_name from public.catalog_programs p left join public.catalog_universities u on u.id = p.university_id where p.id = p_programme;
  if v_name is null then raise exception 'programme not found'; end if;
  r := b2c.support_create(jsonb_build_object('kind', 'data', 'subject', left('Catalogue: ' || v_name, 150),
                                             'body', 'Programme #' || p_programme || ' (' || v_name || E')\n\n' || trim(p_note), 'page', '/s/programmes'));
  perform b2c.notify_admins('support', 'Catalogue correction suggested: ' || left(v_name, 80), (select full_name from b2c.users where user_id = b2c.uid()),
                            '/w/support?t=' || (r ->> 'ticket_id'), null, 'catalogue:' || (r ->> 'ticket_id'), false);
  return r;
end $f$;

-- ---------- the campaign calendar (B9.3) ----------
/* One month: campaigns by their scheduled or sent day, and the automated sends (journeys and campaigns) that went out each day. */
create or replace function b2c.campaign_calendar(p_month date default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kolkata')::date))::date; d1 date := d0 + interval '1 month';
begin
  perform b2c.require('marketing');
  return jsonb_build_object(
    'month', d0,
    'campaigns', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'channel', c.channel, 'status', c.status, 'recurring', c.recurring,
                                                              'day', ((coalesce(c.started_at, c.schedule_at)) at time zone 'Asia/Kolkata')::date,
                                                              'at', coalesce(c.started_at, c.schedule_at), 'segment', g.name, 'test_only', c.test_only)
                                             order by coalesce(c.started_at, c.schedule_at)), '[]'::jsonb)
                    from b2c.campaigns c left join b2c.segments g on g.id = c.segment_id
                   where coalesce(c.started_at, c.schedule_at) >= d0 and coalesce(c.started_at, c.schedule_at) < d1 and c.status <> 'cancelled'),
    'sent', (select coalesce(jsonb_object_agg(day, n), '{}'::jsonb) from (
               select day, sum(n) as n from (
                 select (m.created_at at time zone 'Asia/Kolkata')::date as day, count(*) as n from b2c.wa_messages m
                  where m.direction = 'out' and (m.campaign_id is not null or m.journey_run_id is not null) and m.created_at >= d0 and m.created_at < d1 group by 1
                 union all
                 select (e.created_at at time zone 'Asia/Kolkata')::date, count(*) from b2c.emails e
                  where e.direction = 'out' and (e.campaign_id is not null or e.journey_run_id is not null) and e.created_at >= d0 and e.created_at < d1 group by 1) x
               group by day) y));
end $f$;

-- ---------- system health (B15 Settings: "system health") ----------
/* Everything the Admin needs to know the machine is running: each timer's last run, the queues, the feeds, the app's answers
   to the timers, Claude's spend, and what waits for a person. Each check carries a level: ok, warn or bad. */
create or replace function b2c.system_health() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_jobs jsonb := '[]'::jsonb; v_calls jsonb := null; v_ai jsonb; v_checks jsonb := '[]'::jsonb; v_live boolean;
        n_out_q int; n_out_bad int; t_out_old timestamptz; n_sq_q int; n_sq_held int; n_sq_bad int; t_sq_old timestamptz;
        n_in_err int; n_in_stale int; n_unassigned int; n_replies int; n_unlogged int; n_wa_fail int; t_batch timestamptz; t_event timestamptz;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  -- timers
  if to_regclass('cron.job') is not null then
    if to_regclass('cron.job_run_details') is not null then
      -- cron.job_run_details has no index but its primary key and can hold hundreds of thousands of rows: read only the newest 20,000 runs, once.
      execute $q$with recent as materialized (
                   select distinct on (r.jobid) r.jobid, r.status, r.start_time, r.end_time, r.return_message from cron.job_run_details r
                    where r.runid > coalesce((select max(x.runid) from cron.job_run_details x), 0) - 20000 order by r.jobid, r.start_time desc)
                 select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'last_status', d.status, 'last_start', d.start_time,
                                                              'last_end', d.end_time, 'message', left(d.return_message, 200)) order by j.jobname), '[]'::jsonb)
                   from cron.job j left join recent d on d.jobid = j.jobid
                  where j.jobname like 'b2c-%'$q$ into v_jobs;
    else
      execute $q$select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule) order by j.jobname), '[]'::jsonb) from cron.job j where j.jobname like 'b2c-%'$q$ into v_jobs;
    end if;
  end if;
  -- the app's answers to the timers (pg_net keeps the last responses)
  if to_regclass('net._http_response') is not null then
    execute $q$select jsonb_build_object('last_at', max(created), 'failed_last_hour', count(*) filter (where created > now() - interval '1 hour' and (status_code is null or status_code >= 400)),
                                         'ok_last_hour', count(*) filter (where created > now() - interval '1 hour' and status_code < 400))
                 from net._http_response$q$ into v_calls;
  end if;
  -- queues and feeds
  select count(*) filter (where status = 'queued'), count(*) filter (where status in ('failed', 'refused', 'conflict') and created_at > now() - interval '7 days'),
         min(created_at) filter (where status = 'queued') into n_out_q, n_out_bad, t_out_old from b2c.outbox;
  select count(*) filter (where status = 'queued'), count(*) filter (where status = 'held'), count(*) filter (where status = 'failed' and created_at > now() - interval '24 hours'),
         min(not_before) filter (where status = 'queued') into n_sq_q, n_sq_held, n_sq_bad, t_sq_old from b2c.send_queue;
  select count(*) filter (where status = 'error'), count(*) filter (where status = 'stored' and received_at < now() - interval '10 minutes') into n_in_err, n_in_stale from b2c.inbox;
  select max(sent_at) into t_batch from b2c.outbox where status = 'applied';
  select max(received_at) into t_event from b2c.inbox;
  select count(*) into n_wa_fail from b2c.wa_messages where direction = 'out' and status = 'failed' and created_at > now() - interval '24 hours';
  -- waiting for a person
  select count(*) into n_unassigned from b2c.leads_state where status = 'active' and owner_id is null and lane = 'sales' and deleted_at is null and not is_test;
  select count(*) into n_replies from b2c.replies where status = 'inbox';
  select count(*) into n_unlogged from b2c.calls where logged_at is null and unlogged_flagged_at is not null and tapped_at > now() - interval '24 hours';
  v_ai := jsonb_build_object('spent_today', b2c.ai_spent_today(), 'cap', (b2c.setting('ai') ->> 'daily_cap_inr')::numeric,
                             'failed_today', (select count(*) from b2c.ai_calls where not ok and at > now() - interval '24 hours'));
  v_live := coalesce((b2c.setting('live_mode') ->> 'whatsapp')::boolean, false) or coalesce((b2c.setting('live_mode') ->> 'email')::boolean, false);
  -- the checks, each with a level
  v_checks := v_checks
    || jsonb_build_object('key', 'timers', 'label', 'Database timers', 'level', case when jsonb_array_length(v_jobs) = 0 then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'last_status' = 'failed') then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute' and coalesce((j ->> 'last_start')::timestamptz, now() - interval '1 day') < now() - interval '10 minutes') then 'warn'
                            else 'ok' end,
                          'detail', jsonb_array_length(v_jobs) || ' timers' || coalesce('; last minute tick ' || (select j ->> 'last_start' from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute'), ''))
    || jsonb_build_object('key', 'app', 'label', 'The app answering the timers', 'level', case when v_calls is null then 'warn' when (v_calls ->> 'failed_last_hour')::int > 0 then 'bad' when v_calls ->> 'last_at' is null then 'warn' else 'ok' end,
                          'detail', case when v_calls is null then 'no record of calls' else coalesce((v_calls ->> 'ok_last_hour'), '0') || ' ok and ' || coalesce((v_calls ->> 'failed_last_hour'), '0') || ' failed in the last hour' end)
    || jsonb_build_object('key', 'outbox', 'label', 'Changes to the master lead table', 'level', case when n_out_bad > 0 then 'bad' when t_out_old < now() - interval '30 minutes' then 'warn' else 'ok' end,
                          'detail', n_out_q || ' waiting, ' || n_out_bad || ' failed or refused this week' || coalesce(', last batch ' || t_batch::text, ''))
    || jsonb_build_object('key', 'inbox', 'label', 'Events from the master lead table', 'level', case when n_in_err > 0 then 'bad' when n_in_stale > 0 then 'warn' else 'ok' end,
                          'detail', n_in_err || ' with errors, ' || n_in_stale || ' not yet applied' || coalesce(', last event ' || t_event::text, ''))
    || jsonb_build_object('key', 'sending', 'label', 'WhatsApp and email sending', 'level', case when n_sq_bad > 0 or n_wa_fail > 0 then 'bad' when t_sq_old < now() - interval '15 minutes' then 'warn' else 'ok' end,
                          'detail', n_sq_q || ' queued, ' || n_sq_held || ' held, ' || n_sq_bad || ' failed in 24 h; live mode ' || case when v_live then 'on' else 'off' end)
    || jsonb_build_object('key', 'ai', 'label', 'Claude', 'level', case when (v_ai ->> 'failed_today')::int > 0 then 'warn' when (v_ai ->> 'spent_today')::numeric >= coalesce((v_ai ->> 'cap')::numeric, 0) and coalesce((v_ai ->> 'cap')::numeric, 0) > 0 then 'warn' else 'ok' end,
                          'detail', '₹' || round((v_ai ->> 'spent_today')::numeric) || ' of ₹' || coalesce(v_ai ->> 'cap', '0') || ' today, ' || (v_ai ->> 'failed_today') || ' failed calls')
    || jsonb_build_object('key', 'people', 'label', 'Waiting for a person', 'level', case when n_unassigned > 0 then 'bad' when n_replies > 0 or n_unlogged > 0 then 'warn' else 'ok' end,
                          'detail', n_unassigned || ' unassigned sales leads, ' || n_replies || ' replies to answer, ' || n_unlogged || ' calls not logged in 24 h');
  return jsonb_build_object('at', now(), 'checks', v_checks, 'jobs', v_jobs, 'calls', v_calls, 'ai', v_ai,
                            'overall', case when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'bad') then 'bad'
                                            when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'warn') then 'warn' else 'ok' end);
end $f$;

-- ---------- the audit log and sign-ins (B18: "every phone reveal and Call tap is logged"; "every sign-in is logged") ----------
create or replace function b2c.audit_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
        v_action text := nullif(p ->> 'action', ''); v_actor uuid := nullif(p ->> 'actor', '')::uuid; v_lead bigint := nullif(p ->> 'lead', '')::bigint;
        v_from timestamptz := nullif(p ->> 'from', '')::timestamptz; v_to timestamptz := nullif(p ->> 'to', '')::timestamptz;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at, 'actor', u.full_name, 'actor_id', a.actor_id, 'action', a.action, 'lead_id', a.lead_id, 'detail', a.detail) order by a.at desc), '[]'::jsonb)
               from (select * from b2c.audit_log a
                      where (v_action is null or a.action = v_action) and (v_actor is null or a.actor_id = v_actor) and (v_lead is null or a.lead_id = v_lead)
                        and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to)
                      order by a.at desc limit v_limit offset v_offset) a
               left join b2c.users u on u.user_id = a.actor_id),
    'total', (select count(*) from b2c.audit_log a
               where (v_action is null or a.action = v_action) and (v_actor is null or a.actor_id = v_actor) and (v_lead is null or a.lead_id = v_lead)
                 and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to)),
    'actions', (select coalesce(jsonb_agg(x.action order by x.action), '[]'::jsonb) from (select distinct action from b2c.audit_log) x),
    'people', (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name) order by u.full_name), '[]'::jsonb) from b2c.users u where u.is_active));
end $f$;

create or replace function b2c.sign_in_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 500); v_outcome text := nullif(p ->> 'outcome', ''); v_email text := nullif(lower(trim(p ->> 'email')), '');
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'at', s.at, 'email', s.email, 'method', s.method, 'outcome', s.outcome, 'ip', s.ip, 'user_agent', left(s.user_agent, 120)) order by s.at desc), '[]'::jsonb)
               from (select * from b2c.sign_in_log s where (v_outcome is null or s.outcome = v_outcome) and (v_email is null or lower(s.email) = v_email) order by s.at desc limit v_limit) s),
    'failed_24h', (select count(*) from b2c.sign_in_log where at > now() - interval '24 hours' and outcome not in ('ok', 'code_sent', 'trusted')),
    'outcomes', (select coalesce(jsonb_agg(x.outcome order by x.outcome), '[]'::jsonb) from (select distinct outcome from b2c.sign_in_log) x));
end $f$;

-- ---------- duplicate suspects (B13.2 Quality: "duplicate suspects") ----------
/* Groups of open leads that share a phone or an email (any of a lead's numbers and addresses). The Admin decides what to do
   through the B2B CRM (merging lives there); here it is a list to look at, newest first. */
create or replace function b2c.duplicate_suspects(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('read_all');
  return (
    select coalesce(jsonb_agg(jsonb_build_object('kind', g.kind, 'value', g.value, 'leads', g.leads, 'latest', g.latest) order by g.latest desc), '[]'::jsonb)
      from (select c.kind, max(c.value) as value, max(v.handed_off_at) as latest,
                   jsonb_agg(jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'stage', v.stage, 'owner', v.owner_name, 'lane', v.lane, 'status', v.status, 'created_at', v.handed_off_at) order by v.lead_id) as leads
              from b2c.lead_contacts c
              join b2c.leads_v v on v.lead_id = c.lead_id
             where c.removed_at is null and v.deleted_at is null and not v.is_test
             group by c.kind, c.value_norm
            having count(distinct c.lead_id) > 1
             order by max(v.handed_off_at) desc
             limit least(greatest(coalesce(p_limit, 100), 1), 500)) g);
end $f$;

-- ---------- grants: staff over the API; nothing for anon ----------
grant execute on function b2c.snippets_mine(), b2c.snippet_save(jsonb), b2c.snippet_delete(bigint), b2c.snippet_used(bigint),
  b2c.tag_own(bigint[], text, boolean), b2c.tasks_bulk(bigint[], text, text, timestamptz, text), b2c.wa_bulk_template(bigint[], bigint),
  b2c.catalogue_suggest(bigint, text), b2c.campaign_calendar(date), b2c.system_health(), b2c.audit_list(jsonb), b2c.sign_in_list(jsonb),
  b2c.duplicate_suspects(int) to authenticated, service_role;
revoke execute on function b2c.snippets_mine(), b2c.snippet_save(jsonb), b2c.snippet_delete(bigint), b2c.snippet_used(bigint),
  b2c.tag_own(bigint[], text, boolean), b2c.tasks_bulk(bigint[], text, text, timestamptz, text), b2c.wa_bulk_template(bigint[], bigint),
  b2c.catalogue_suggest(bigint, text), b2c.campaign_calendar(date), b2c.system_health(), b2c.audit_list(jsonb), b2c.sign_in_list(jsonb),
  b2c.duplicate_suspects(int) from public, anon;
