-- M22a: the B2C CRM link, part 1 (Vikas, 7 Oct): the B2C CRM no longer touches public.student_leads. It keeps its
-- own copy of the leads it works, synced in real time through the B2B CRM, and writes back only through the B2B API.
--   b2c_fields        the field catalogue: every lead field the B2C CRM sees, its group, type and whether B2C may write it
--   b2c_record        one lead as the B2C CRM sees it (grouped, standard field names, its allocation and campaign)
--   b2c_sync          one row per lead ever shared: per-lead version, a global change sequence (the feed cursor), the hash
--   b2c_sync_lead     recomputes a lead's record; when it changed, bumps the version and queues one signed webhook
--                     (b2c.lead_upserted, or b2c.lead_released when the lead leaves B2C) to the B2C endpoint
--   b2c_sync_tick     every 5 seconds: leads, allocations and campaigns changed since the last run
--   outbox_kick       outbox_tick under a lock, so the sync can deliver at once without racing the 15-second job
-- Settings b2c_link: enabled, scope ('held': leads B2C holds; 'all': every lead, read-only unless held), writable fields.

create index if not exists student_leads_updated_at_idx on public.student_leads (updated_at);

alter table b2b.api_keys drop constraint if exists api_keys_scopes_check;
alter table b2b.api_keys add constraint api_keys_scopes_check
  check (cardinality(scopes) > 0 and scopes <@ array['intake', 'referrals', 'events', 'b2c']::text[]);

create sequence if not exists b2b.b2c_sync_seq;

create table if not exists b2b.b2c_sync (
  lead_id     bigint primary key,
  seq         bigint not null unique,
  version     int not null,
  hash        text not null,
  in_scope    boolean not null,
  origin      text,
  changed_at  timestamptz not null default now()
);

create table if not exists b2b.b2c_writes (
  id              bigint generated always as identity primary key,
  api_key_id      bigint,
  request_id      text not null check (length(request_id) between 1 and 100),
  lead_id         bigint,
  kind            text not null check (kind in ('update', 'activity')),
  actor           jsonb not null default '{}',
  changes         jsonb not null default '{}',
  status          text not null check (status in ('applied', 'unchanged', 'conflict', 'rejected')),
  http_status     int not null,
  error           text,
  version_before  int,
  version_after   int,
  response        jsonb,
  created_at      timestamptz not null default now()
);
create unique index if not exists b2c_writes_request_uq on b2b.b2c_writes (coalesce(api_key_id, 0), kind, request_id);
create index if not exists b2c_writes_lead_idx on b2b.b2c_writes (lead_id, created_at desc);
create index if not exists b2c_writes_created_idx on b2b.b2c_writes (created_at desc);

create table if not exists b2b.b2c_link_state (
  key         text primary key,
  value       jsonb not null default '{}',
  updated_at  timestamptz not null default now()
);
insert into b2b.b2c_link_state (key, value) values ('cursor', jsonb_build_object('at', now())) on conflict (key) do nothing;

do $rls$
declare t text;
begin
  foreach t in array array['b2c_sync', 'b2c_writes', 'b2c_link_state'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;
grant usage, select on sequence b2b.b2c_sync_seq to service_role;

/* The field catalogue. kind: text, email, phone, int, numeric, pct, ts, date, uuid, stage, temperature, bool, json.
   write: 'b2c' (the B2C CRM may write it while it holds the lead) or 'b2b' (read-only for B2C). */
create or replace function b2b.b2c_fields()
returns jsonb language sql immutable set search_path = '' as $fn$
  select jsonb_agg(jsonb_build_object('field', f, 'column', c, 'group', g, 'kind', k, 'write', w, 'max', m) order by o)
    from (values
      (1, 'student', 'name', 'student_name', 'text', 'b2c', 120),
      (2, 'student', 'phone', 'whatsapp_number', 'phone', 'b2b', null),
      (3, 'student', 'alternate_phone', 'alternate_phone', 'phone', 'b2c', null),
      (4, 'student', 'email', 'email_id', 'email', 'b2c', null),
      (5, 'student', 'city', 'city', 'text', 'b2c', 80),
      (6, 'student', 'state', 'state', 'text', 'b2c', 80),
      (7, 'student', 'country', 'country', 'text', 'b2c', 80),
      (8, 'student', 'preferred_language', 'preferred_language', 'text', 'b2c', 40),
      (9, 'student', 'enquirer_relation', 'enquirer_relation', 'text', 'b2c', 40),
      (10, 'student', 'guardian_name', 'guardian_name', 'text', 'b2c', 120),
      (11, 'student', 'guardian_phone', 'guardian_phone', 'phone', 'b2c', null),
      (20, 'education', 'highest_qualification', 'highest_qualification', 'text', 'b2c', 120),
      (21, 'education', 'current_study', 'current_study', 'text', 'b2c', 120),
      (22, 'education', 'academic_score_pct', 'academic_score_pct', 'pct', 'b2c', null),
      (23, 'education', 'work_experience_years', 'work_experience_years_num', 'numeric', 'b2c', 60),
      (24, 'education', 'current_job_role', 'current_job_role', 'text', 'b2c', 120),
      (30, 'interest', 'course', 'interested_course', 'text', 'b2c', 120),
      (31, 'interest', 'specialization', 'interested_specialization', 'text', 'b2c', 120),
      (32, 'interest', 'university', 'interested_university', 'text', 'b2c', 160),
      (33, 'interest', 'programme_level', 'program_level', 'text', 'b2c', 20),
      (34, 'interest', 'study_mode', 'study_mode_preference', 'text', 'b2c', 40),
      (35, 'interest', 'field_of_interest', 'field_of_interest', 'text', 'b2c', 120),
      (36, 'interest', 'enrollment_timeline', 'enrollment_timeline', 'text', 'b2c', 80),
      (37, 'interest', 'annual_budget_inr', 'annual_budget_inr', 'numeric', 'b2c', 100000000),
      (38, 'interest', 'preferred_counseling_time', 'preferred_counseling_time', 'text', 'b2c', 80),
      (40, 'consent', 'contact_consent_at', 'consent_sales_at', 'ts', 'b2b', null),
      (41, 'consent', 'marketing_consent_at', 'consent_marketing_at', 'ts', 'b2b', null),
      (42, 'consent', 'partner_share_consent_at', 'consent_partner_share_at', 'ts', 'b2b', null),
      (43, 'consent', 'consent_text_version', 'consent_text_version', 'text', 'b2b', null),
      (44, 'consent', 'opted_out', 'is_opted_out', 'bool', 'b2b', null),
      (45, 'consent', 'opted_out_at', 'opted_out_at', 'ts', 'b2b', null),
      (50, 'source', 'lead_source', 'lead_source', 'text', 'b2b', null),
      (51, 'source', 'channel', 'channel', 'text', 'b2b', null),
      (52, 'source', 'source_detail', 'source_detail', 'text', 'b2b', null),
      (53, 'source', 'campaign', 'campaign', 'text', 'b2b', null),
      (54, 'source', 'utm_source', 'utm_source', 'text', 'b2b', null),
      (55, 'source', 'utm_medium', 'utm_medium', 'text', 'b2b', null),
      (56, 'source', 'utm_campaign', 'utm_campaign', 'text', 'b2b', null),
      (57, 'source', 'utm_content', 'utm_content', 'text', 'b2b', null),
      (58, 'source', 'utm_term', 'utm_term', 'text', 'b2b', null),
      (59, 'source', 'click_ids', 'click_ids', 'json', 'b2b', null),
      (60, 'source', 'landing_url', 'landing_url', 'text', 'b2b', null),
      (61, 'source', 'referral_code', 'referral_code', 'text', 'b2b', null),
      (62, 'source', 'first_touch_at', 'first_touch_at', 'ts', 'b2b', null),
      (63, 'source', 'last_touch_at', 'last_touch_at', 'ts', 'b2b', null),
      (70, 'qualification', 'lead_status', 'lead_status', 'text', 'b2b', null),
      (71, 'qualification', 'classification', 'lead_classification', 'text', 'b2b', null),
      (72, 'qualification', 'admission_readiness', 'admission_readiness', 'text', 'b2b', null),
      (73, 'qualification', 'eligibility_status', 'eligibility_status', 'text', 'b2b', null),
      (74, 'qualification', 'is_sales_ready', 'is_sales_ready', 'bool', 'b2b', null),
      (75, 'qualification', 'lead_score', 'lead_score', 'int', 'b2c', 100),
      (76, 'qualification', 'temperature', 'temperature', 'temperature', 'b2c', null),
      (80, 'pipeline', 'owner_user_id', 'owner_user_id', 'uuid', 'b2c', null),
      (81, 'pipeline', 'team_id', 'team_id', 'int', 'b2c', 1000000000),
      (82, 'pipeline', 'assigned_at', 'assigned_at', 'ts', 'b2c', null),
      (83, 'pipeline', 'stage', 'stage', 'stage', 'b2c', null),
      (84, 'pipeline', 'sub_stage', 'sub_stage', 'text', 'b2c', 80),
      (85, 'pipeline', 'stage_changed_at', 'stage_changed_at', 'ts', 'b2c', null),
      (86, 'pipeline', 'first_contacted_at', 'first_contacted_at', 'ts', 'b2c', null),
      (87, 'pipeline', 'last_contacted_at', 'last_contacted_at', 'ts', 'b2c', null),
      (88, 'pipeline', 'last_activity_at', 'last_activity_at', 'ts', 'b2c', null),
      (89, 'pipeline', 'contact_attempts', 'contact_attempts', 'int', 'b2c', 10000),
      (90, 'pipeline', 'next_task_due_at', 'next_task_due_at', 'ts', 'b2c', null),
      (100, 'application', 'application_id', 'application_id', 'text', 'b2c', 80),
      (101, 'application', 'application_status', 'application_status', 'text', 'b2c', 60),
      (102, 'application', 'applied_at', 'applied_at', 'ts', 'b2c', null),
      (103, 'application', 'fee_amount_inr', 'fee_amount_inr', 'numeric', 'b2c', 100000000),
      (104, 'application', 'fee_paid_inr', 'fee_paid_inr', 'numeric', 'b2c', 100000000),
      (110, 'enrolment', 'enrollment_status', 'enrollment_status', 'text', 'b2c', 40),
      (111, 'enrolment', 'enrolled_program', 'enrolled_program', 'text', 'b2c', 200),
      (112, 'enrolment', 'enrolled_university', 'enrolled_university', 'text', 'b2c', 200),
      (113, 'enrolment', 'enrollment_date', 'enrollment_date', 'date', 'b2c', null),
      (114, 'enrolment', 'expected_net_revenue_inr', 'expected_net_revenue_inr', 'numeric', 'b2c', 100000000),
      (115, 'enrolment', 'realised_net_revenue_inr', 'realised_net_revenue_inr', 'numeric', 'b2c', 100000000),
      (120, 'lost', 'lost_reason', 'lost_reason', 'text', 'b2c', 200),
      (121, 'lost', 'lost_at', 'lost_at', 'ts', 'b2c', null),
      (130, 'other', 'custom_fields', 'custom_fields', 'json', 'b2c', 20000)
    ) v(o, g, f, c, k, w, m);
$fn$;

/* Does the B2C CRM hold this lead now? */
create or replace function b2b.b2c_holds(l public.student_leads)
returns boolean language sql stable set search_path = '' as $fn$
  select l.destination_type = 'in_house' and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null;
$fn$;

/* One lead as the B2C CRM sees it: standard field names grouped as in b2c_fields, the allocation (who holds it and why)
   and the ad campaign. No B2B internals (scores of partners, routing candidates, commission rates). */
create or replace function b2b.b2c_record(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v jsonb := to_jsonb(l);
  a b2b.allocations;
  c b2b.lead_campaigns;
  r jsonb;
begin
  select * into a from b2b.allocations where id = l.allocation_id;
  select * into c from b2b.lead_campaigns where lead_id = l.id and cycle_no = coalesce(l.cycle_no, 1);
  select coalesce(jsonb_object_agg(g, obj), '{}') into r
    from (select f ->> 'group' g, jsonb_object_agg(f ->> 'field', v -> (f ->> 'column')) obj
            from jsonb_array_elements(b2b.b2c_fields()) f group by 1) x;
  return r || jsonb_build_object(
    'id', l.id, 'cycle_no', coalesce(l.cycle_no, 1), 'created_at', l.created_at, 'updated_at', l.updated_at,
    'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
    'deleted', l.deleted_at is not null or l.anonymised_at is not null, 'merged_into_id', l.merged_into_id,
    'held_by_b2c', b2b.b2c_holds(l),
    'allocation', jsonb_build_object(
      'destination', l.destination_type, 'allocation_id', l.allocation_id, 'reference', a.reference, 'b2c_lane', a.b2c_lane,
      'reason', l.allocation_reason, 'allocated_at', l.allocated_at, 'status', a.status,
      'partner', case when l.partner_id is not null then (select jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name))
                                                            from b2b.partners p where p.id = l.partner_id) end),
    'campaign', case when c.lead_id is not null then jsonb_strip_nulls(jsonb_build_object(
      'platform', c.platform, 'paid', c.paid, 'campaign_id', c.campaign_id, 'campaign_name', c.campaign_name, 'adset_name', c.adset_name,
      'ad_name', c.ad_name, 'form_id', c.form_id, 'utm_source', c.utm_source, 'utm_medium', c.utm_medium, 'utm_campaign', c.utm_campaign)) end);
end $fn$;

create or replace function b2b.b2c_link_cfg()
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_object('enabled', true, 'scope', 'held',
                            'writable', (select jsonb_agg(f -> 'field') from jsonb_array_elements(b2b.b2c_fields()) f where f ->> 'write' = 'b2c'))
         || coalesce((select value from b2b.settings where key = 'b2c_link'), '{}');
$fn$;

/* Recompute one lead for the B2C CRM. When its record changed (or p_force), bump its version, take the next feed
   sequence and queue the webhook for the B2C endpoint (an older undelivered version of the same lead is cancelled:
   only the newest matters). A lead that leaves B2C's scope gets one b2c.lead_released. */
create or replace function b2b.b2c_sync_lead(p_lead_id bigint, p_force boolean default false, p_origin text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  l public.student_leads;
  prev b2b.b2c_sync;
  v_scope boolean;
  rec jsonb;
  v_hash text;
  v_seq bigint;
  v_ver int;
  v_type text;
  env jsonb;
  w b2b.webhook_endpoints;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, true) then return jsonb_build_object('changed', false, 'why', 'link off'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  select * into prev from b2b.b2c_sync where lead_id = p_lead_id for update;
  if l.id is null then
    if prev.lead_id is null or not prev.in_scope then return jsonb_build_object('changed', false); end if;
    v_scope := false;
    rec := jsonb_build_object('id', p_lead_id, 'deleted', true, 'held_by_b2c', false);
  else
    v_scope := b2b.b2c_holds(l) or (cfg ->> 'scope' = 'all' and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null);
    if not v_scope and (prev.lead_id is null or (not prev.in_scope and not p_force)) then return jsonb_build_object('changed', false); end if;
    rec := case when v_scope then b2b.b2c_record(l)
                else jsonb_build_object('id', l.id, 'held_by_b2c', false, 'deleted', l.deleted_at is not null or l.anonymised_at is not null,
                                        'merged_into_id', l.merged_into_id,
                                        'allocation', jsonb_build_object('destination', l.destination_type, 'reason', l.allocation_reason,
                                                                         'allocated_at', l.allocated_at)) end;
  end if;
  v_hash := md5((rec - 'updated_at')::text);
  if prev.lead_id is not null and prev.hash = v_hash and prev.in_scope = v_scope and not p_force then
    return jsonb_build_object('changed', false, 'version', prev.version);
  end if;
  v_seq := nextval('b2b.b2c_sync_seq');
  v_ver := coalesce(prev.version, 0) + 1;
  insert into b2b.b2c_sync (lead_id, seq, version, hash, in_scope, origin, changed_at)
  values (p_lead_id, v_seq, v_ver, v_hash, v_scope, p_origin, now())
  on conflict (lead_id) do update set seq = excluded.seq, version = excluded.version, hash = excluded.hash, in_scope = excluded.in_scope,
                                      origin = excluded.origin, changed_at = excluded.changed_at;
  v_type := case when v_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end;
  env := jsonb_build_object('id', 'lead_' || p_lead_id || '_v' || v_ver, 'type', v_type, 'occurred_at', now(), 'lead_id', p_lead_id,
                            'test', coalesce((rec ->> 'is_test')::boolean, false),
                            'data', jsonb_build_object('version', v_ver, 'seq', v_seq, 'origin', p_origin, 'record', rec));
  for w in select * from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, v_type) loop
    update b2b.integration_outbox set status = 'cancelled', last_error = 'superseded by version ' || v_ver
     where endpoint_id = w.id and status in ('pending', 'failed') and event_type in ('b2c.lead_upserted', 'b2c.lead_released')
       and (payload ->> 'lead_id')::bigint = p_lead_id;
    insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
    values (v_type, w.consumer, env, w.id || ':' || (env ->> 'id'), w.id)
    on conflict (idempotency_key) do nothing;
  end loop;
  return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type);
end $fn$;

/* outbox_tick under a transaction lock: the B2C sync calls it to deliver at once; the 15-second job uses it too. */
create or replace function b2b.outbox_kick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.outbox_tick')) then return jsonb_build_object('skipped', 'busy'); end if;
  return b2b.outbox_tick();
end $fn$;

/* Every 5 seconds: leads changed since the last run (their own row, their allocation, their campaign), oldest first. */
create or replace function b2b.b2c_sync_tick(p_limit int default 1000)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_start timestamptz := clock_timestamp();
  v_since timestamptz;
  v_last timestamptz;
  v_n int := 0;
  v_changed int := 0;
  r record;
  x jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.b2c_sync_tick')) then return jsonb_build_object('skipped', 'busy'); end if;
  perform set_config('b2b.actor', 'engine', true);
  select (value ->> 'at')::timestamptz into v_since from b2b.b2c_link_state where key = 'cursor';
  v_since := coalesce(v_since, now() - interval '1 day') - interval '10 seconds';
  for r in
    select lead_id, max(changed) changed from (
      select l.id lead_id, l.updated_at changed from public.student_leads l where l.updated_at > v_since
      union all select a.lead_id, greatest(a.created_at, a.updated_at) from b2b.allocations a where greatest(a.created_at, a.updated_at) > v_since
      union all select c.lead_id, c.updated_at from b2b.lead_campaigns c where c.updated_at > v_since) y
     group by lead_id order by 2 limit greatest(p_limit, 1)
  loop
    begin
      x := b2b.b2c_sync_lead(r.lead_id);
      if (x ->> 'changed')::boolean then v_changed := v_changed + 1; end if;
    exception when others then
      raise warning 'b2c_sync_lead(%) failed: %', r.lead_id, sqlerrm;
    end;
    v_n := v_n + 1;
    v_last := r.changed;
  end loop;
  update b2b.b2c_link_state set value = jsonb_build_object('at', case when v_n >= greatest(p_limit, 1) then v_last else v_start end,
                                                           'last_run', v_start, 'scanned', v_n, 'changed', v_changed), updated_at = now()
   where key = 'cursor';
  if v_changed > 0 then perform b2b.outbox_kick(); end if;
  return jsonb_build_object('scanned', v_n, 'changed', v_changed);
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('b2b-b2c-sync-tick', 'b2b-outbox-tick');
  perform cron.schedule('b2b-b2c-sync-tick', '5 seconds', 'select b2b.b2c_sync_tick()');
  perform cron.schedule('b2b-outbox-tick', '15 seconds', 'select b2b.outbox_kick()');
end $cron$;

revoke execute on function b2b.b2c_fields(), b2b.b2c_holds(public.student_leads), b2b.b2c_record(public.student_leads), b2b.b2c_link_cfg(),
                           b2b.b2c_sync_lead(bigint, boolean, text), b2b.outbox_kick(), b2b.b2c_sync_tick(int) from public, anon, authenticated;
grant execute on function b2b.b2c_fields(), b2b.b2c_holds(public.student_leads), b2b.b2c_record(public.student_leads), b2b.b2c_link_cfg(),
                          b2b.b2c_sync_lead(bigint, boolean, text), b2b.outbox_kick(), b2b.b2c_sync_tick(int) to service_role;
