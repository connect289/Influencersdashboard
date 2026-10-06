-- M4b: Partners (spec B5.1, B8.3.8, B8.5).
-- public.partners is empty and only the old CRM's partner/engine functions use it. It moves to b2b; those functions
-- keep working because their search_path is widened to (public, b2b). Nothing is removed.
-- The partner's live state is b2b.live_switches scope 'partner:<id>' (one source of truth for every live switch).

do $mv$
begin
  if to_regclass('public.partners') is not null and to_regclass('b2b.partners') is null then
    execute 'alter table public.partners set schema b2b';
  end if;
end $mv$;

-- Old CRM functions that name `partners` unqualified.
alter function public.crm_allocate_lead(bigint, bigint[], text)                              set search_path = public, b2b;
alter function public.crm_dest_stats(text, bigint, text, jsonb)                              set search_path = public, b2b;
alter function public.crm_engine_flow__impl(integer)                                         set search_path = public, b2b;
alter function public.crm_partner_duplicate(bigint, text, timestamp with time zone, text)    set search_path = public, b2b;
alter function public.crm_partner_event(bigint, jsonb)                                       set search_path = public, b2b;
alter function public.crm_partner_health_check()                                             set search_path = public, b2b;
alter function public.crm_partner_rotate_secret(bigint)                                      set search_path = public, b2b;
alter function public.crm_partner_verify(bigint, text, text)                                 set search_path = public, b2b;
alter function public.crm_reallocate(bigint, text, bigint, uuid, text)                       set search_path = public, b2b;
alter function public.crm_scorecards__impl(text, integer)                                    set search_path = public, b2b;
alter function public.crm_sync_claim(integer)                                                set search_path = public, b2b;
alter function public.crm_upsert_partner(jsonb)                                              set search_path = public, b2b;

-- B5.1 fields.
alter table b2b.partners
  add column if not exists display_name           text,
  add column if not exists logo_url               text,
  add column if not exists brand_color            text,
  add column if not exists dedupe_mode            text    not null default 'async',
  add column if not exists hold_minutes           int     not null default 30,
  add column if not exists duplicate_window_hours int     not null default 24,
  add column if not exists notify_enabled         boolean not null default false,
  add column if not exists test_endpoint          text,
  add column if not exists working_hours          jsonb   not null default
    '{"mon":{"open":"10:00","close":"19:00"},"tue":{"open":"10:00","close":"19:00"},"wed":{"open":"10:00","close":"19:00"},"thu":{"open":"10:00","close":"19:00"},"fri":{"open":"10:00","close":"19:00"},"sat":{"open":"10:00","close":"17:00"},"sun":null}',
  add column if not exists holidays               date[]  not null default '{}',
  add column if not exists outbound_secret_id     uuid,
  add column if not exists inbound_secret_id      uuid,
  add column if not exists updated_by             text;

alter table b2b.partners alter column sla set default
  '{"first_contact_hours":2,"first_connect_days":1,"status_update_days":7,"outcome_days":5,"proof_days":7,"duplicate_hours":24}';

do $c$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'b2b.partners'::regclass and conname = 'partners_b2b_fields_check') then
    alter table b2b.partners add constraint partners_b2b_fields_check check (
          slug ~ '^[a-z0-9][a-z0-9-]{1,39}$'
      and length(trim(name)) between 1 and 120
      and dedupe_mode in ('sync', 'async', 'none')
      and hold_minutes between 0 and 1440
      and (dedupe_mode <> 'sync' or hold_minutes = 0)
      and duplicate_window_hours between 1 and 720
      and (brand_color is null or brand_color ~ '^#[0-9a-fA-F]{6}$')
      and (logo_url is null or logo_url ~ '^https://')
      and (api_base_url is null or api_base_url ~ '^https://')
      and (test_endpoint is null or test_endpoint ~ '^https://')
      and (daily_cap is null or daily_cap >= 0)
      and (monthly_cap is null or monthly_cap >= 0)
      and (contract_min_monthly is null or contract_min_monthly >= 0)
      and jsonb_typeof(lead_criteria) = 'object'
      and jsonb_typeof(sla) = 'object'
      and jsonb_typeof(working_hours) = 'object'
    );
  end if;
end $c$;

-- Access: the Admin reads (minus the old plain-secret columns); every write goes through the functions below.
alter table b2b.partners enable row level security;
do $p$
begin
  if exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'partners' and policyname = 'crm_select') then
    alter policy crm_select on b2b.partners rename to admin_read;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'partners' and policyname = 'admin_read') then
    create policy admin_read on b2b.partners for select to authenticated using ((select b2b.is_admin()));
  end if;
end $p$;
alter policy admin_read on b2b.partners to authenticated using ((select b2b.is_admin()));

revoke all on b2b.partners from public, anon, authenticated;
grant select (id, slug, name, status, adapter_type, api_base_url, daily_cap, monthly_cap, lead_criteria, sla,
              contract_min_monthly, paused_reason, auto_paused_at, notes, created_by, created_at, updated_at,
              display_name, logo_url, brand_color, dedupe_mode, hold_minutes, duplicate_window_hours, notify_enabled,
              test_endpoint, working_hours, holidays, updated_by)
  on b2b.partners to authenticated;
grant all on b2b.partners to service_role;
revoke all on sequence b2b.partners_id_seq from public, anon, authenticated;
grant usage, select on sequence b2b.partners_id_seq to service_role;
revoke all on public.partners_v from anon;
revoke insert, update, delete, truncate, references, trigger on public.partners_v from authenticated;

-- ---------- functions ----------

create or replace function b2b.partner_json(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $$
  select (to_jsonb(p) - 'outbound_auth' - 'inbound_secret' - 'outbound_secret_id' - 'inbound_secret_id')
         || jsonb_build_object(
              'live', b2b.is_live('partner:' || p.id),
              'has_outbound_credentials', p.outbound_secret_id is not null,
              'has_inbound_secret', p.inbound_secret_id is not null);
$$;

/* Go-live checklist (B8.3.8). Items whose screens are not built yet are reported with available = false. */
create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', false, 'available', false),
    jsonb_build_object('key', 'programmes',  'done', false, 'available', false),
    jsonb_build_object('key', 'credentials', 'done', p.outbound_secret_id is not null, 'available', false),
    jsonb_build_object('key', 'mapping',     'done', false, 'available', false),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', false, 'available', false)
  );
$$;

create or replace function b2b.partners_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(b2b.partner_json(p) || jsonb_build_object(
             'leads_today', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
             'leads_month', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
             'checklist_done', (select count(*) from jsonb_array_elements(b2b.partner_checklist(p)) c where (c ->> 'done')::boolean),
             'checklist_total', jsonb_array_length(b2b.partner_checklist(p)))
           order by (p.status = 'closed'), lower(coalesce(p.display_name, p.name)))
      from b2b.partners p), '[]'::jsonb);
end $$;

create or replace function b2b.partner_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  p b2b.partners;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_id;
  if p.id is null then return null; end if;
  return jsonb_build_object(
    'partner', b2b.partner_json(p),
    'checklist', b2b.partner_checklist(p),
    'leads_month', (select count(*) from public.student_leads l where l.partner_id = p.id and l.allocated_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'leads_total', (select count(*) from public.student_leads l where l.partner_id = p.id),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.occurred_at, 'type', e.type, 'actor', e.actor_type, 'payload', e.payload) order by e.occurred_at desc)
                          from (select * from b2b.events where partner_id = p.id order by occurred_at desc limit 30) e), '[]'));
end $$;

/* Validates a working-hours object: keys mon..sun, each null (closed) or {"open":"HH:MM","close":"HH:MM"} with open < close. */
create or replace function b2b.valid_working_hours(w jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(w) = 'object'
     and not exists (select 1 from jsonb_object_keys(w) k where k not in ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'))
     and not exists (
       select 1 from jsonb_each(w) d
        where not (jsonb_typeof(d.value) = 'null'
               or (jsonb_typeof(d.value) = 'object'
                   and d.value ->> 'open' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                   and d.value ->> 'close' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                   and d.value ->> 'open' < d.value ->> 'close')));
$$;

/*
 * Creates (no id) or updates a partner. Status, the live switch and credentials have their own functions.
 * The slug is fixed once the partner has left onboarding: partners' systems call /v1/partners/{slug}/events.
 */
create or replace function b2b.partner_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id    bigint := nullif(p ->> 'id', '')::bigint;
  v_old   b2b.partners;
  v_new   b2b.partners;
  v_slug  text := lower(trim(p ->> 'slug'));
  v_dedupe text := coalesce(p ->> 'dedupe_mode', 'async');
  v_wh    jsonb := coalesce(p -> 'working_hours', 'null'::jsonb);
  v_changed text[];
  v_who   text := coalesce(auth.uid()::text, 'system');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_slug is null or v_slug !~ '^[a-z0-9][a-z0-9-]{1,39}$' then
    raise exception 'slug: 2 to 40 lowercase letters, digits or hyphens' using errcode = '22023';
  end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  if jsonb_typeof(v_wh) = 'object' and not b2b.valid_working_hours(v_wh) then
    raise exception 'working hours: each day closed or open < close (HH:MM)' using errcode = '22023';
  end if;
  if p ? 'sla' and jsonb_typeof(p -> 'sla') <> 'object' then raise exception 'sla must be an object' using errcode = '22023'; end if;
  if p ? 'lead_criteria' and jsonb_typeof(p -> 'lead_criteria') <> 'object' then raise exception 'lead criteria must be an object' using errcode = '22023'; end if;

  if v_id is not null then
    select * into v_old from b2b.partners where id = v_id for update;
    if v_old.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
    if v_slug <> v_old.slug and (v_old.status <> 'onboarding' or b2b.is_live('partner:' || v_id)) then
      raise exception 'the slug is fixed once a partner leaves onboarding' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from b2b.partners where slug = v_slug and id is distinct from v_id) then
    raise exception 'slug already used by another partner' using errcode = '23505';
  end if;

  if v_id is null then
    insert into b2b.partners (slug, name, created_by, updated_by) values (v_slug, trim(p ->> 'name'), auth.uid(), v_who)
    returning * into v_old;
    v_id := v_old.id;
  end if;

  update b2b.partners t set
    slug                   = v_slug,
    name                   = trim(p ->> 'name'),
    display_name           = nullif(trim(p ->> 'display_name'), ''),
    logo_url               = nullif(trim(p ->> 'logo_url'), ''),
    brand_color            = nullif(trim(p ->> 'brand_color'), ''),
    adapter_type           = coalesce(nullif(p ->> 'adapter_type', ''), t.adapter_type),
    api_base_url           = nullif(trim(p ->> 'api_base_url'), ''),
    test_endpoint          = nullif(trim(p ->> 'test_endpoint'), ''),
    dedupe_mode            = v_dedupe,
    hold_minutes           = case when v_dedupe = 'sync' then 0 else coalesce((p ->> 'hold_minutes')::int, 30) end,
    duplicate_window_hours = coalesce((p ->> 'duplicate_window_hours')::int, 24),
    notify_enabled         = coalesce((p ->> 'notify_enabled')::boolean, false),
    daily_cap              = (p ->> 'daily_cap')::int,
    monthly_cap            = (p ->> 'monthly_cap')::int,
    contract_min_monthly   = (p ->> 'contract_min_monthly')::int,
    working_hours          = case when jsonb_typeof(v_wh) = 'object' then v_wh else t.working_hours end,
    holidays               = coalesce((select array_agg(distinct d::date order by d::date) from jsonb_array_elements_text(p -> 'holidays') d), '{}'),
    sla                    = case when p ? 'sla' then t.sla || (p -> 'sla') else t.sla end,
    lead_criteria          = case when p ? 'lead_criteria' then p -> 'lead_criteria' else t.lead_criteria end,
    notes                  = nullif(trim(p ->> 'notes'), ''),
    updated_at             = now(),
    updated_by             = v_who
  where t.id = v_id
  returning * into v_new;

  select coalesce(array_agg(n.key order by n.key), '{}') into v_changed
    from jsonb_each(to_jsonb(v_new)) n
   where n.key not in ('updated_at', 'updated_by', 'created_at', 'created_by')
     and n.value is distinct from (to_jsonb(v_old) -> n.key);

  if p ->> 'id' is null or p ->> 'id' = '' then
    perform b2b.log_event('partner.created', null, null, v_id, jsonb_build_object('slug', v_slug));
  elsif cardinality(v_changed) > 0 then
    perform b2b.log_event('partner.updated', null, null, v_id, jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;
  return jsonb_build_object('id', v_id, 'changed', to_jsonb(v_changed));
end $$;

/* onboarding → active ↔ paused → closed. Pausing needs a reason; closing also switches the partner off. */
create or replace function b2b.partner_set_status(p_id bigint, p_status text, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_old text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('onboarding', 'active', 'paused', 'closed') then raise exception 'unknown status' using errcode = '22023'; end if;
  if p_status in ('paused', 'closed') and coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select status into v_old from b2b.partners where id = p_id for update;
  if v_old is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if v_old = p_status then return jsonb_build_object('status', p_status); end if;
  if v_old = 'closed' then raise exception 'a closed partner cannot be reopened here' using errcode = '22023'; end if;

  update b2b.partners
     set status = p_status,
         paused_reason = case when p_status = 'paused' then trim(p_reason) else null end,
         auto_paused_at = null,
         updated_at = now(), updated_by = coalesce(auth.uid()::text, 'system')
   where id = p_id;
  if p_status = 'closed' and b2b.is_live('partner:' || p_id) then
    perform b2b.set_live_switch('partner:' || p_id, false, 'partner closed: ' || trim(p_reason));
  end if;
  perform b2b.log_event('partner.status_changed', null, null, p_id, jsonb_build_object('from', v_old, 'to', p_status, 'reason', nullif(trim(p_reason), '')));
  return jsonb_build_object('status', p_status);
end $$;

/* The partner's live switch. Off is always allowed; on needs an active partner and the whole go-live checklist. */
create or replace function b2b.partner_set_live(p_id bigint, p_live boolean, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  p b2b.partners;
  v_missing jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_id for update;
  if p.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if p_live then
    if p.status <> 'active' then raise exception 'only an active partner can go live' using errcode = '22023'; end if;
    select jsonb_agg(c -> 'key') into v_missing from jsonb_array_elements(b2b.partner_checklist(p)) c where not (c ->> 'done')::boolean;
    if v_missing is not null then
      raise exception 'go-live checklist incomplete: %', (select string_agg(x, ', ') from jsonb_array_elements_text(v_missing) x) using errcode = '22023';
    end if;
  end if;
  perform b2b.set_live_switch('partner:' || p_id, p_live, p_reason);
  return jsonb_build_object('live', p_live);
end $$;

revoke execute on function b2b.partner_json(b2b.partners), b2b.partner_checklist(b2b.partners), b2b.valid_working_hours(jsonb)
  from public, anon, authenticated;
grant execute on function b2b.partner_json(b2b.partners), b2b.partner_checklist(b2b.partners), b2b.valid_working_hours(jsonb)
  to service_role;
revoke execute on function b2b.partners_list(), b2b.partner_detail(bigint), b2b.partner_save(jsonb),
                           b2b.partner_set_status(bigint, text, text), b2b.partner_set_live(bigint, boolean, text)
  from public, anon;
grant execute on function b2b.partners_list(), b2b.partner_detail(bigint), b2b.partner_save(jsonb),
                          b2b.partner_set_status(bigint, text, text), b2b.partner_set_live(bigint, boolean, text)
  to authenticated, service_role;
