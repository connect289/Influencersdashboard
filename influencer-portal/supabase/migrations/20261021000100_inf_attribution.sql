-- Phase 6: tracking links, attribution and the creator lead pipeline (spec 9; ERD §6; approved SHARED_CHANGES S-3,
-- S-6, S-7, S-8, S-9, S-12; STAGE_MAPPING.md; INTEGRATION_CONTRACTS.md §1).
--
-- No trigger on student_leads, no new column on any shared table, no change to lead_intake(). Attribution and stage
-- sync are sweeps: inf.lead_sync_candidates() reads the shared tables (read-only, as the function owner) and returns
-- each lead's facts; the app applies the pure rules in lib/attribution and writes the outcome back with
-- inf.lead_sync_apply(). Creators read leads only from inf.creator_lead_feed, which holds whitelisted values already
-- masked here in the database (phone and email are always masked; nothing can unmask them for a creator).

-- ---------------------------------------------------------------------------------------------------------------
-- Keys and masking
-- ---------------------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'inf_lead_ref_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'inf_lead_ref_key',
                                'Influencer portal: key for creator-facing lead references (L-XXXXXXXXXX)');
  end if;
end $$;

-- The lead reference creators see instead of the internal id: a keyed hash, not reversible or enumerable.
create or replace function inf.lead_ref(p_lead bigint) returns text
language sql stable security definer set search_path = '' as $$
  select 'L-' || upper(left(encode(extensions.hmac(p_lead::text, (select decrypted_secret from vault.decrypted_secrets
                                                                    where name = 'inf_lead_ref_key'), 'sha256'), 'hex'), 10));
$$;

-- 98XXXXXX21: the national number's first two and last two digits; anything that isn't a 10-digit Indian number is
-- fully masked.
create or replace function inf.mask_phone(p text) returns text
language sql immutable set search_path = '' as $$
  select case when n ~ '^\d{10}$' then left(n, 2) || 'XXXXXX' || right(n, 2) else 'XXXXXXXXXX' end
    from (select case when d ~ '^91\d{10}$' then substr(d, 3) when d ~ '^0\d{10}$' then substr(d, 2) else d end as n
            from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x) y;
$$;

-- r****@gmail.com for common public mailboxes; any other domain is masked too (r****@****.in).
create or replace function inf.mask_email(p text, p_public text[]) returns text
language sql immutable set search_path = '' as $$
  select case
    when p is null or position('@' in p) < 2 then null
    when lower(split_part(p, '@', 2)) = any (p_public) then left(p, 1) || '****@' || lower(split_part(p, '@', 2))
    else left(p, 1) || '****@****.' || coalesce(nullif(substring(lower(split_part(p, '@', 2)) from '\.([a-z]{2,})$'), ''), 'com')
  end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Tracking links and clicks
-- ---------------------------------------------------------------------------------------------------------------
create table inf.tracking_links (
  id              uuid primary key default gen_random_uuid(),
  code            text not null check (code ~ '^[A-Z0-9]{2,12}(-[A-Z0-9]{1,8}){1,3}$' and char_length(code) between 5 and 32),
  creator_id      uuid not null references inf.creators (id) on delete restrict,
  deal_id         uuid references inf.deals (id) on delete set null,
  deliverable_id  uuid references inf.deliverables (id) on delete set null,
  campaign_id     uuid references inf.campaigns (id) on delete set null,
  programme_id    bigint,
  destination     text not null check (destination in ('whatsapp_witty', 'website_landing', 'custom_url')),
  custom_url      text check (custom_url is null or (custom_url ~ '^https://' and char_length(custom_url) <= 1000)),
  platform        text check (platform in ('instagram', 'youtube', 'facebook', 'linkedin', 'x', 'telegram', 'moj_josh', 'other')),
  label           text check (char_length(label) <= 120),
  active          boolean not null default true,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (destination <> 'custom_url' or custom_url is not null)
);
-- Codes are unique forever, whatever their case (never reused, even after deactivation).
create unique index tracking_links_code_idx on inf.tracking_links (upper(code));
create index tracking_links_creator_idx on inf.tracking_links (creator_id, created_at desc);
create trigger tracking_links_touch before update on inf.tracking_links for each row execute function inf.touch_updated_at();
create trigger tracking_links_audit after insert or update on inf.tracking_links for each row execute function inf.audit_row('tracking_link');
create or replace function inf.tracking_links_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.code is distinct from old.code or new.creator_id is distinct from old.creator_id then
    raise exception 'inf.tracking_links: a code and its creator never change' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger tracking_links_guard before update on inf.tracking_links for each row execute function inf.tracking_links_guard();

create table inf.link_clicks (
  id              bigint generated always as identity primary key,
  link_id         uuid not null references inf.tracking_links (id) on delete restrict,
  clicked_at      timestamptz not null default now(),
  ip_hash         text,
  user_agent      text check (char_length(user_agent) <= 300),
  referrer        text check (char_length(referrer) <= 300),
  device          text check (device in ('mobile', 'tablet', 'desktop')),
  in_app          text check (char_length(in_app) <= 20),
  is_bot          boolean not null default false,
  w2_access_code  text check (w2_access_code ~ '^[A-Z0-9]{6}$'),
  w2_click_id     bigint,
  issue_failed    boolean not null default false
);
create index link_clicks_link_idx on inf.link_clicks (link_id, clicked_at desc);
create index link_clicks_code_idx on inf.link_clicks (w2_access_code) where w2_access_code is not null;
create trigger link_clicks_append_only before update or delete on inf.link_clicks for each row execute function inf.forbid_mutation();

-- ---------------------------------------------------------------------------------------------------------------
-- Attributions, decisions, fraud flags
-- ---------------------------------------------------------------------------------------------------------------
create table inf.lead_attributions (
  id               uuid primary key default gen_random_uuid(),
  -- public.student_leads.id: a soft reference (no foreign key into the shared table).
  student_lead_id  bigint not null,
  creator_id       uuid not null references inf.creators (id) on delete restrict,
  link_id          uuid references inf.tracking_links (id) on delete set null,
  deal_id          uuid references inf.deals (id) on delete set null,
  deliverable_id   uuid references inf.deliverables (id) on delete set null,
  campaign_id      uuid references inf.campaigns (id) on delete set null,
  code             text not null,
  touch            text not null check (touch in ('first', 'last', 'assisted', 'none')),
  status           text not null check (status in ('credited', 'duplicate', 'outside_window', 'self_referral', 'fraud_suspected',
                                                   'manually_rejected', 'manually_credited')),
  reason           text check (reason in ('existing_lead', 'another_creator', 'outside_window', 'self_referral')),
  evidence_source  text not null check (evidence_source in ('click', 'referral_code', 'touchpoint', 'access_code', 'manual')),
  touch_at         timestamptz not null,
  lead_created_at  timestamptz not null,
  is_test          boolean not null default false,
  decided_by       uuid,
  decided_at       timestamptz,
  decision_note    text check (char_length(decision_note) <= 1000),
  creator_stage    text,
  stage_reason     text,
  stage_flags      text[] not null default '{}',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (student_lead_id, creator_id)
);
-- At most one creator earns a lead.
create unique index lead_attributions_one_credit_idx on inf.lead_attributions (student_lead_id)
  where status in ('credited', 'manually_credited', 'fraud_suspected') and touch in ('first', 'last');
create index lead_attributions_creator_idx on inf.lead_attributions (creator_id, lead_created_at desc);
create index lead_attributions_status_idx on inf.lead_attributions (status) where status in ('fraud_suspected');
create trigger lead_attributions_touch before update on inf.lead_attributions for each row execute function inf.touch_updated_at();

create table inf.attribution_decisions (
  id              bigint generated always as identity primary key,
  attribution_id  uuid not null references inf.lead_attributions (id) on delete restrict,
  from_status     text,
  to_status       text not null,
  reason          text check (char_length(reason) <= 1000),
  actor_id        uuid,
  actor           text not null check (actor in ('system', 'staff')),
  at              timestamptz not null default now()
);
create index attribution_decisions_idx on inf.attribution_decisions (attribution_id, at);
create trigger attribution_decisions_append_only before update or delete on inf.attribution_decisions for each row execute function inf.forbid_mutation();
create trigger attribution_decisions_audit after insert on inf.attribution_decisions for each row execute function inf.audit_row('attribution_decision');

create table inf.fraud_flags (
  id              uuid primary key default gen_random_uuid(),
  creator_id      uuid not null references inf.creators (id) on delete restrict,
  attribution_id  uuid references inf.lead_attributions (id) on delete restrict,
  signal          text not null check (signal in ('velocity', 'same_device', 'no_witty_reply', 'off_hours_burst', 'junk_rate')),
  detail          jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object'),
  status          text not null default 'open' check (status in ('open', 'cleared', 'confirmed')),
  opened_at       timestamptz not null default now(),
  decided_by      uuid,
  decided_at      timestamptz,
  note            text check (char_length(note) <= 1000)
);
create unique index fraud_flags_open_idx on inf.fraud_flags (creator_id, coalesce(attribution_id, '00000000-0000-0000-0000-000000000000'::uuid), signal)
  where status = 'open';
create index fraud_flags_status_idx on inf.fraud_flags (status, opened_at desc);
create trigger fraud_flags_audit after insert or update on inf.fraud_flags for each row execute function inf.audit_row('fraud_flag');

-- ---------------------------------------------------------------------------------------------------------------
-- Stage mappings, stage events, the creator-safe feed, sync state
-- ---------------------------------------------------------------------------------------------------------------
create table inf.stage_mappings (
  id               uuid primary key default gen_random_uuid(),
  priority         int not null unique check (priority between 1 and 9999),
  conditions       jsonb not null check (jsonb_typeof(conditions) = 'array' and jsonb_array_length(conditions) between 1 and 6),
  creator_stage    text check (creator_stage in ('new', 'qualifying', 'qualified', 'allocated', 'counselling', 'applied', 'enrolled', 'lost',
                                                  'duplicate', 'junk', 'not_attributed')),
  reason_category  text check (char_length(reason_category) <= 80),
  flag             text check (flag in ('cancelled', 'under_review')),
  active           boolean not null default true,
  updated_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (creator_stage is not null or flag is not null)
);
create trigger stage_mappings_touch before update on inf.stage_mappings for each row execute function inf.touch_updated_at();
create trigger stage_mappings_audit after insert or update or delete on inf.stage_mappings for each row execute function inf.audit_row('stage_mapping');

create table inf.lead_stage_events (
  id               bigint generated always as identity primary key,
  attribution_id   uuid not null references inf.lead_attributions (id) on delete restrict,
  student_lead_id  bigint not null,
  creator_stage    text not null,
  reason_category  text,
  flags            text[] not null default '{}',
  source           text not null check (source in ('sweep', 'backfill', 'override')),
  idem_key         text not null unique,
  occurred_at      timestamptz not null,
  created_at       timestamptz not null default now()
);
create index lead_stage_events_idx on inf.lead_stage_events (attribution_id, occurred_at);
create trigger lead_stage_events_append_only before update or delete on inf.lead_stage_events for each row execute function inf.forbid_mutation();

-- One row per attribution, holding only whitelisted values, masked here. The only lead-shaped object creators can
-- select, and the only one in the Realtime publication.
create table inf.creator_lead_feed (
  attribution_id      uuid primary key references inf.lead_attributions (id) on delete cascade,
  creator_id          uuid not null references inf.creators (id) on delete cascade,
  lead_ref            text not null,
  display_name        text,
  phone_masked        text not null,
  email_masked        text,
  fields              jsonb not null default '{}'::jsonb check (jsonb_typeof(fields) = 'object'),
  creator_stage       text not null,
  reason_category     text,
  flags               text[] not null default '{}',
  temperature         text,
  attribution_status  text not null,
  attribution_reason  text,
  touch               text not null,
  code                text not null,
  link_id             uuid,
  link_label          text,
  campaign_id         uuid,
  campaign_name       text,
  deal_id             uuid,
  deal_title          text,
  deliverable_id      uuid,
  deliverable_title   text,
  programme_id        bigint,
  programme_name      text,
  stage_timeline      jsonb not null default '[]'::jsonb check (jsonb_typeof(stage_timeline) = 'array'),
  earning_status      text not null default 'pending' check (earning_status in ('none', 'pending', 'accrued', 'confirmed', 'paid', 'clawed_back')),
  is_test             boolean not null default false,
  removed             boolean not null default false,
  lead_at             timestamptz not null,
  stage_changed_at    timestamptz,
  updated_at          timestamptz not null default now()
);
create index creator_lead_feed_creator_idx on inf.creator_lead_feed (creator_id, lead_at desc);

create table inf.sync_state (
  key         text primary key,
  watermark   timestamptz not null,
  detail      jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------------------------
-- Per-campaign attribution (spec 9.1 "message text configurable per campaign", 9.2 "optional overrides per campaign").
-- Null means the global setting. The message must keep {code} so Witty can read the creator code.
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.campaigns
  add column attribution_model text check (attribution_model in ('first_touch', 'last_touch', 'first_touch_with_assisted')),
  add column link_message text check (char_length(link_message) between 10 and 500 and position('{code}' in link_message) > 0);

create or replace function inf.campaign_attribution_save(p_campaign uuid, p_model text, p_message text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.campaigns set attribution_model = nullif(p_model, ''), link_message = nullif(trim(p_message), '')
   where id = p_campaign;
  if not found then raise exception 'no such campaign' using errcode = '22023'; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------------------------------------------
-- Staff (creator.write) create links for any creator; a creator (or their agency with the negotiate grant) for their
-- own agreed or active deals, and only for programmes of the deal's campaign. The app proposes the code.
create or replace function inf.link_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_creator uuid := (p ->> 'creator_id')::uuid;
  d inf.deals;
  v_deliverable uuid := nullif(p ->> 'deliverable_id', '')::uuid;
  v_prog bigint := nullif(p ->> 'programme_id', '')::bigint;
  v_staff boolean := inf.has_perm('creator.write');
  v_id uuid;
begin
  if not (v_staff or coalesce(v_creator = inf.current_creator_id(), false) or inf.agency_can(v_creator, 'negotiate')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  -- A custom address turns the short link into a redirect anywhere, so only staff set one (no open redirect).
  if p ->> 'destination' = 'custom_url' and not v_staff then
    raise exception 'custom addresses are set by Eduwit' using errcode = '42501';
  end if;
  if nullif(p ->> 'deal_id', '') is not null then
    select * into d from inf.deals where id = (p ->> 'deal_id')::uuid;
    if d.id is null or d.creator_id <> v_creator then raise exception 'invalid deal' using errcode = '22023'; end if;
    if not v_staff and d.status not in ('agreed', 'active') then raise exception 'links need an agreed deal' using errcode = '22023'; end if;
  elsif not v_staff then
    raise exception 'links need an agreed deal' using errcode = '22023';
  end if;
  if v_deliverable is not null and not exists (select 1 from inf.deliverables x where x.id = v_deliverable and x.deal_id = d.id) then
    raise exception 'invalid deliverable' using errcode = '22023';
  end if;
  if v_prog is not null and not exists (select 1 from public.catalog_programs cp where cp.id = v_prog) then
    raise exception 'invalid programme' using errcode = '22023';
  end if;
  if v_prog is not null and not v_staff and d.campaign_id is not null
     and not exists (select 1 from inf.campaign_programmes c where c.campaign_id = d.campaign_id and c.programme_id = v_prog) then
    raise exception 'programme not in this campaign' using errcode = '22023';
  end if;
  insert into inf.tracking_links (code, creator_id, deal_id, deliverable_id, campaign_id, programme_id, destination, custom_url, platform, label)
  values (upper(trim(p ->> 'code')), v_creator, d.id, v_deliverable, d.campaign_id, v_prog, p ->> 'destination',
          nullif(trim(p ->> 'custom_url'), ''), nullif(p ->> 'platform', ''), nullif(trim(p ->> 'label'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'this code is taken' using errcode = '23505';
end $$;

-- Every deliverable gets its own tracking link and code when it is created (spec 9.1: one per creator, deal and
-- deliverable), sending people to Witty. Codes follow lib/attribution/codes.ts (STEM-TAG-XXX, no-confusion alphabet).
create or replace function inf.link_code_suggest(p_handle text, p_tag text) returns text
language sql volatile set search_path = '' as $$
  select (select case when length(h) >= 2 then h else left(h || 'CR', 2) end
            from (select left(upper(regexp_replace(coalesce(p_handle, ''), '[^A-Za-z0-9]', '', 'g')), 12) as h) x)
         || '-' || case lower(p_tag) when 'instagram' then 'IG' when 'youtube' then 'YT' when 'facebook' then 'FB'
                     when 'linkedin' then 'LI' when 'x' then 'X' when 'telegram' then 'TG' when 'moj_josh' then 'MJ'
                     else 'GO' end
         || '-' || (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 32), 1), '' order by i)
                      from (select extensions.gen_random_bytes(3) as b) r, generate_series(0, 2) i);
$$;

create or replace function inf.deliverable_link_auto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  d inf.deals;
  v_handle text;
begin
  select * into d from inf.deals where id = new.deal_id;
  select c.handle into v_handle from inf.creators c where c.id = d.creator_id;
  for i in 1..20 loop
    begin
      insert into inf.tracking_links (code, creator_id, deal_id, deliverable_id, campaign_id, destination, platform, label)
      values (inf.link_code_suggest(v_handle, new.platform), d.creator_id, d.id, new.id, d.campaign_id, 'whatsapp_witty',
              new.platform, left(new.title, 120));
      return new;
    exception when unique_violation then
      null;  -- a taken code: try another suffix
    end;
  end loop;
  raise exception 'could not create a tracking code' using errcode = '23505';
end $$;
create trigger deliverables_link_auto after insert on inf.deliverables
  for each row execute function inf.deliverable_link_auto();

create or replace function inf.link_set_active(p_link uuid, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare l inf.tracking_links;
begin
  select * into l from inf.tracking_links where id = p_link;
  if l.id is null or not (inf.has_perm('creator.write') or coalesce(l.creator_id = inf.current_creator_id(), false)
                          or inf.agency_can(l.creator_id, 'negotiate')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update inf.tracking_links set active = p_active where id = p_link;
end $$;

-- A creator's links with click and lead counts (staff, the creator, or an agency with the view grant).
create or replace function inf.links_list(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'code', l.code, 'destination', l.destination, 'custom_url', l.custom_url, 'platform', l.platform,
           'label', l.label, 'active', l.active, 'created_at', l.created_at,
           'deal_id', l.deal_id, 'deal_title', d.title, 'deliverable_id', l.deliverable_id, 'deliverable_title', x.title,
           'campaign_id', l.campaign_id, 'campaign_name', cp.name, 'programme_id', l.programme_id,
           'programme_name', (select p.program_name from public.catalog_programs p where p.id = l.programme_id),
           'clicks', (select count(*) from inf.link_clicks c where c.link_id = l.id and not c.is_bot),
           'leads', (select count(*) from inf.lead_attributions a where a.link_id = l.id and a.status in ('credited', 'manually_credited')
                                                                     and a.touch in ('first', 'last')))
           order by l.created_at desc), '[]')
    from inf.tracking_links l
    left join inf.deals d on d.id = l.deal_id
    left join inf.deliverables x on x.id = l.deliverable_id
    left join inf.campaigns cp on cp.id = l.campaign_id
   where l.creator_id = p_creator
     and (inf.has_perm('creator.read') or coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'view'));
$$;

-- Deals a creator may make links for, with their deliverables and campaign programmes (the link builder).
create or replace function inf.link_options(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'deal_id', d.id, 'deal_title', d.title, 'campaign_id', d.campaign_id, 'campaign_name', cp.name,
           'deliverables', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'platform', x.platform) order by x.position)
                                       from inf.deliverables x where x.deal_id = d.id and x.status <> 'cancelled'), '[]'),
           'programmes', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', concat_ws(' · ', u.name, p.program_name, p.specialization))
                                                    order by c.position)
                                     from inf.campaign_programmes c join public.catalog_programs p on p.id = c.programme_id
                                     join public.catalog_universities u on u.id = p.university_id
                                    where c.campaign_id = d.campaign_id), '[]'))
           order by d.created_at desc), '[]')
    from inf.deals d left join inf.campaigns cp on cp.id = d.campaign_id
   where d.creator_id = p_creator and d.status in ('agreed', 'active')
     and (inf.has_perm('creator.write') or coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'negotiate'));
$$;

-- What the redirect needs for a code (service role).
create or replace function inf.link_resolve(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'id', l.id, 'code', l.code, 'active', l.active and c.status not in ('blocked', 'archived'), 'destination', l.destination,
           'custom_url', l.custom_url, 'platform', l.platform, 'creator_name', c.display_name, 'handle', c.handle,
           'campaign_slug', cp.name, 'message', cp.link_message,
           'programme', (select p.program_name from public.catalog_programs p where p.id = l.programme_id))
    from inf.tracking_links l join inf.creators c on c.id = l.creator_id left join inf.campaigns cp on cp.id = l.campaign_id
   where upper(l.code) = upper(trim(p_code)) and coalesce(auth.role(), '') = 'service_role';
$$;

create or replace function inf.click_log(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.link_clicks (link_id, ip_hash, user_agent, referrer, device, in_app, is_bot, w2_access_code, w2_click_id, issue_failed)
  values ((p ->> 'link_id')::uuid, nullif(p ->> 'ip_hash', ''), left(p ->> 'user_agent', 300), left(p ->> 'referrer', 300),
          nullif(p ->> 'device', ''), nullif(p ->> 'in_app', ''), coalesce((p ->> 'is_bot')::boolean, false),
          nullif(upper(p ->> 'w2_access_code'), ''), nullif(p ->> 'w2_click_id', '')::bigint, coalesce((p ->> 'issue_failed')::boolean, false))
  returning id into v_id;
  return v_id;
end $$;

-- S-12: the redirect asks Witty for an access code through Witty's own public function, exactly as the website does
-- (the portal's only write path into another product's tables). Service role only.
create or replace function inf.witty_issue_code(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  -- Witty's function has no search_path of its own and names its tables unqualified, so it needs public for this call
  -- (transaction-local; the function's empty search_path is restored on return). It is called exactly as Witty calls it.
  perform set_config('search_path', 'public', true);
  return public.w2_issue_code(p);
end $$;

-- R-1: Witty validates a typed creator code (service role only; no personal data in or out).
create or replace function inf.witty_resolve_code(p_code text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_build_object('valid', true, 'code', l.code, 'campaign', cp.name,
                                             'programme_key', l.programme_id::text, 'message', null)
                     from inf.tracking_links l join inf.creators c on c.id = l.creator_id left join inf.campaigns cp on cp.id = l.campaign_id
                    where upper(l.code) = upper(trim(p_code)) and l.active and coalesce(auth.role(), '') = 'service_role'),
                  jsonb_build_object('valid', false));
$$;

-- The public landing data for the website (INTEGRATION_CONTRACTS §4): active creators with a public page only.
create or replace function inf.public_creator(p_handle text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'handle', c.handle, 'display_name', c.display_name, 'bio', c.bio, 'avatar_path', c.avatar_path,
           'code', (select l.code from inf.tracking_links l where l.creator_id = c.id and l.active and l.destination in ('whatsapp_witty', 'website_landing')
                     order by (l.destination = 'website_landing') desc, l.created_at desc limit 1),
           'featured_programmes', coalesce((select jsonb_agg(distinct jsonb_build_object('programme_id', p.id, 'name', p.program_name,
                                                     'university', u.name, 'level', p.level, 'mode', p.mode, 'fee_total_inr', p.fee_total))
                                              from inf.tracking_links l join public.catalog_programs p on p.id = l.programme_id
                                              join public.catalog_universities u on u.id = p.university_id
                                             where l.creator_id = c.id and l.active and p.active), '[]'))
    from inf.creators c
   where lower(c.handle) = lower(trim(p_handle)) and c.status = 'active' and c.public_page_enabled
     and coalesce(auth.role(), '') = 'service_role';
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- The sweep: gather facts (read-only on shared tables) …
-- ---------------------------------------------------------------------------------------------------------------
-- Facts for leads changed since a watermark (p: {since, limit}), created in a date range (p: {from, to}), or a list
-- (p: {lead_ids}). Only leads with creator evidence or an existing attribution are returned. Service role.
create or replace function inf.lead_sync_candidates(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_limit int := least(coalesce((p ->> 'limit')::int, 500), 2000);
  v_rules jsonb := inf.setting('attribution.rules');
  v_utm text := lower(coalesce(inf.setting('attribution.links') ->> 'utm_source', 'influencer'));
  v_ids bigint[];
  v_out jsonb;
  v_max timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'lead_ids' then
    v_ids := array(select (x)::bigint from jsonb_array_elements_text(p -> 'lead_ids') x);
  elsif p ? 'from' then
    v_ids := array(select l.id from public.student_leads l
                    where l.created_at >= (p ->> 'from')::timestamptz and l.created_at < (p ->> 'to')::timestamptz and l.deleted_at is null
                      and l.id > coalesce((p ->> 'after')::bigint, 0)
                    order by l.id limit v_limit);
  else
    -- Leads changed since the watermark, plus attributed leads whose B2C status changed.
    v_ids := array(select id from (
                     select l.id, l.updated_at from public.student_leads l
                      where l.updated_at > (p ->> 'since')::timestamptz and l.deleted_at is null
                     union
                     select a.student_lead_id, v.updated_at from public.b2c_lead_status_v v
                       join inf.lead_attributions a on a.student_lead_id = v.lead_id
                      where v.updated_at > (p ->> 'since')::timestamptz
                     order by 2 limit v_limit) s);
  end if;
  select max(greatest(l.updated_at, coalesce(v.updated_at, l.updated_at))) into v_max
    from public.student_leads l left join public.b2c_lead_status_v v on v.lead_id = l.id where l.id = any (v_ids);

  with leads as (
    select l.* from public.student_leads l where l.id = any (v_ids)
  ),
  -- Every place a creator code can appear for a lead (INTEGRATION_CONTRACTS §1.4), resolved to a link.
  evidence as (
    select l.id as lead_id, upper(l.referral_code) as code,
           coalesce((select min(t.occurred_at) from public.touchpoints t where t.lead_id = l.id
                      and (upper(t.attribution ->> 'creator_code') = upper(l.referral_code) or upper(t.payload ->> 'referral_code') = upper(l.referral_code))),
                    l.created_at) as at, 'referral_code' as source
      from leads l where l.referral_code is not null
    union all
    select t.lead_id, upper(coalesce(t.attribution ->> 'creator_code', t.attribution ->> 'utm_content')),
           coalesce((t.attribution ->> 'first_click_at')::timestamptz, t.occurred_at),
           case when t.attribution ? 'first_click_at' then 'click' else 'touchpoint' end
      from public.touchpoints t join leads l on l.id = t.lead_id
     where t.attribution ->> 'creator_code' is not null
        or (lower(t.attribution ->> 'utm_source') = v_utm and t.attribution ->> 'utm_content' is not null)
    union all
    select l.id, upper(coalesce(ac.attribution ->> 'creator_code', ac.attribution ->> 'utm_content')),
           coalesce((ac.attribution ->> 'first_click_at')::timestamptz, ac.created_at), 'access_code'
      from leads l join public.w2_access_codes ac on ac.code = upper(l.activation_code)
     where ac.attribution ->> 'creator_code' is not null
        or (lower(ac.attribution ->> 'utm_source') = v_utm and ac.attribution ->> 'utm_content' is not null)
    union all
    select l.id, k.code, c.clicked_at, 'click'
      from leads l join inf.link_clicks c on c.w2_access_code = upper(l.activation_code) and not c.is_bot
      join inf.tracking_links k on k.id = c.link_id
  ),
  touches as (
    select e.lead_id, jsonb_agg(distinct jsonb_build_object(
             'code', k.code, 'link_id', k.id, 'creator_id', k.creator_id, 'deal_id', k.deal_id, 'deliverable_id', k.deliverable_id,
             'campaign_id', k.campaign_id, 'at', to_char(e.at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), 'source', e.source)) as list
      from evidence e join inf.tracking_links k on upper(k.code) = e.code
     group by e.lead_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id,
           'created_at', to_char(l.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'reopened_at', to_char(l.reopened_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'is_test', coalesce(l.is_test, false),
           'touches', coalesce(t.list, '[]'),
           'self_referral_creators', coalesce((
              select jsonb_agg(distinct cr.id) from inf.creators cr
               where cr.id in (select (x ->> 'creator_id')::uuid from jsonb_array_elements(coalesce(t.list, '[]')) x)
                 and ((coalesce((v_rules ->> 'self_referral_match_phone')::boolean, true)
                       and (inf.norm_phone(cr.phone_e164) = l.whatsapp_number
                            or exists (select 1 from inf.creator_contacts cc where cc.creator_id = cr.id and cc.kind = 'self'
                                         and cc.phone_hash = inf.pii_hash(l.whatsapp_number))))
                   or (coalesce((v_rules ->> 'self_referral_match_email')::boolean, true) and l.email_id is not null
                       and (lower(cr.email) = lower(l.email_id)
                            or exists (select 1 from inf.creator_contacts cc where cc.creator_id = cr.id and cc.kind in ('self', 'family')
                                         and cc.email_hash = inf.pii_hash(l.email_id))))
                   or (coalesce((v_rules ->> 'self_referral_match_family')::boolean, true)
                       and exists (select 1 from inf.creator_contacts cc where cc.creator_id = cr.id and cc.kind = 'family'
                                     and cc.phone_hash = inf.pii_hash(l.whatsapp_number))))), '[]'),
           'existing', coalesce((select jsonb_agg(jsonb_build_object('creator_id', a.creator_id, 'status', a.status, 'id', a.id,
                                                                     'stage', a.creator_stage, 'reason', a.stage_reason,
                                                                     'link_id', a.link_id, 'code', a.code, 'deal_id', a.deal_id,
                                                                     'deliverable_id', a.deliverable_id, 'campaign_id', a.campaign_id,
                                                                     'touch', a.touch, 'attribution_reason', a.reason,
                                                                     'touch_at', to_char(a.touch_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                                                                     'evidence_source', a.evidence_source))
                                  from inf.lead_attributions a where a.student_lead_id = l.id), '[]'),
           'stage', jsonb_build_object('stage', l.stage, 'lost_reason', l.lost_reason, 'enrollment_status', l.enrollment_status,
                                       'applied_at', l.applied_at, 'is_sales_ready', coalesce(l.is_sales_ready, false),
                                       'b2c_stage', b.canonical_stage, 'b2c_closed_reason', b.closed_reason),
           'stage_changed_at', to_char(greatest(l.stage_changed_at, b.stage_changed_at, l.updated_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
         ) order by l.id), '[]')
    into v_out
    from leads l
    left join touches t on t.lead_id = l.id
    left join public.b2c_lead_status_v b on b.lead_id = l.id and b.view_version = 1
   where t.list is not null or exists (select 1 from inf.lead_attributions a where a.student_lead_id = l.id);

  return jsonb_build_object('leads', v_out, 'scanned', coalesce(array_length(v_ids, 1), 0),
                            'last_id', (select max(x) from unnest(v_ids) x),
                            'watermark', to_char(v_max at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
                            'rules', v_rules,
                            'campaign_models', coalesce((select jsonb_object_agg(cp.id, cp.attribution_model) from inf.campaigns cp
                                                          where cp.attribution_model is not null), '{}'),
                            'stage_rules', coalesce((select jsonb_agg(jsonb_build_object('priority', m.priority, 'conditions', m.conditions,
                                                                                         'creator_stage', m.creator_stage, 'reason_category', m.reason_category,
                                                                                         'flag', m.flag) order by m.priority)
                                                       from inf.stage_mappings m where m.active), '[]'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- … and apply the outcome
-- ---------------------------------------------------------------------------------------------------------------
-- Rebuilds the creator-safe rows of one lead from the shared table and the portal's attributions. Values are masked
-- and filtered by the lead_visibility.creator setting before they are stored.
create or replace function inf.lead_feed_refresh(p_lead bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  l public.student_leads;
  v_set jsonb := inf.setting('lead_visibility.creator');
  v_fields text[] := array(select jsonb_array_elements_text(coalesce(v_set -> 'fields', '[]')));
  v_domains text[] := array(select jsonb_array_elements_text(coalesce(v_set -> 'public_mail_domains', '[]')));
  v_name text;
  v_all jsonb;
  v_vis jsonb;
  v_removed boolean;
begin
  select * into l from public.student_leads where id = p_lead;
  if l.id is null then
    delete from inf.creator_lead_feed f using inf.lead_attributions a where a.id = f.attribution_id and a.student_lead_id = p_lead;
    return;
  end if;
  v_removed := l.anonymised_at is not null or l.deleted_at is not null;
  v_name := case coalesce(v_set ->> 'name_format', 'first_initial')
              when 'hidden' then null
              when 'full' then nullif(trim(l.student_name), '')
              when 'first_name' then nullif(split_part(trim(l.student_name), ' ', 1), '')
              else nullif(trim(split_part(trim(l.student_name), ' ', 1) ||
                               case when position(' ' in trim(coalesce(l.student_name, ''))) > 0
                                    then ' ' || left(regexp_replace(trim(l.student_name), '^.*\s', ''), 1) || '.' else '' end), '')
            end;
  v_all := jsonb_build_object(
    'city', l.city, 'state', l.state, 'country', l.country, 'preferred_language', l.preferred_language,
    'enquirer_relation', l.enquirer_relation, 'interested_course', l.interested_course,
    'interested_specialization', l.interested_specialization, 'field_of_interest', l.field_of_interest,
    'interested_university', l.interested_university, 'university_preference', l.university_preference,
    'program_level', l.program_level, 'programme_segment', l.programme_segment, 'study_mode_preference', l.study_mode_preference,
    'highest_qualification', l.highest_qualification, 'current_study', l.current_study, 'enrollment_timeline', l.enrollment_timeline,
    'eligibility_status', l.eligibility_status, 'admission_readiness', l.admission_readiness, 'lead_status', upper(l.lead_status),
    'experience_band', case when l.work_experience_years_num is null then null
                            when l.work_experience_years_num < 1 then '0'
                            when l.work_experience_years_num < 3 then '1–3'
                            when l.work_experience_years_num < 5 then '3–5'
                            when l.work_experience_years_num < 10 then '5–10' else '10+' end,
    'first_touch_at', l.first_touch_at, 'applied_at', l.applied_at, 'enrolled_program', l.enrolled_program,
    'enrolled_university', l.enrolled_university, 'enrollment_date', l.enrollment_date);
  select coalesce(jsonb_object_agg(k, v), '{}') into v_vis
    from jsonb_each(v_all) e(k, v) where k = any (v_fields) and v <> 'null'::jsonb;

  insert into inf.creator_lead_feed (attribution_id, creator_id, lead_ref, display_name, phone_masked, email_masked, fields, creator_stage,
                                     reason_category, flags, temperature, attribution_status, attribution_reason, touch, code, link_id,
                                     link_label, campaign_id, campaign_name, deal_id, deal_title, deliverable_id, deliverable_title,
                                     programme_id, programme_name, stage_timeline, is_test, removed, lead_at, stage_changed_at, updated_at)
  select a.id, a.creator_id, inf.lead_ref(l.id),
         case when v_removed then null when 'display_name' = any (v_fields) then v_name end,
         case when v_removed then 'XXXXXXXXXX' else inf.mask_phone(l.whatsapp_number) end,
         case when v_removed then null else inf.mask_email(l.email_id, v_domains) end,
         case when v_removed then '{}'::jsonb else v_vis end,
         coalesce(a.creator_stage, 'new'), a.stage_reason, a.stage_flags,
         case when v_removed then null when upper(l.lead_status) in ('HOT', 'WARM', 'COLD') then upper(l.lead_status) end,
         a.status, a.reason, a.touch, a.code, a.link_id, k.label, a.campaign_id, cp.name, a.deal_id, d.title, a.deliverable_id, x.title,
         k.programme_id, (select pr.program_name from public.catalog_programs pr where pr.id = k.programme_id),
         coalesce((select jsonb_agg(jsonb_build_object('stage', e.creator_stage, 'reason', e.reason_category, 'flags', to_jsonb(e.flags),
                                                       'at', e.occurred_at) order by e.occurred_at, e.id)
                     from inf.lead_stage_events e where e.attribution_id = a.id), '[]'),
         a.is_test, v_removed, a.lead_created_at,
         (select max(e.occurred_at) from inf.lead_stage_events e where e.attribution_id = a.id), now()
    from inf.lead_attributions a
    left join inf.tracking_links k on k.id = a.link_id
    left join inf.campaigns cp on cp.id = a.campaign_id
    left join inf.deals d on d.id = a.deal_id
    left join inf.deliverables x on x.id = a.deliverable_id
   where a.student_lead_id = l.id
  on conflict (attribution_id) do update set
    lead_ref = excluded.lead_ref, display_name = excluded.display_name, phone_masked = excluded.phone_masked,
    email_masked = excluded.email_masked, fields = excluded.fields, creator_stage = excluded.creator_stage,
    reason_category = excluded.reason_category, flags = excluded.flags, temperature = excluded.temperature,
    attribution_status = excluded.attribution_status, attribution_reason = excluded.attribution_reason, touch = excluded.touch,
    code = excluded.code, link_id = excluded.link_id, link_label = excluded.link_label, campaign_id = excluded.campaign_id,
    campaign_name = excluded.campaign_name, deal_id = excluded.deal_id, deal_title = excluded.deal_title,
    deliverable_id = excluded.deliverable_id, deliverable_title = excluded.deliverable_title,
    programme_id = excluded.programme_id, programme_name = excluded.programme_name, stage_timeline = excluded.stage_timeline,
    is_test = excluded.is_test, removed = excluded.removed, lead_at = excluded.lead_at, stage_changed_at = excluded.stage_changed_at,
    updated_at = now();
end $$;

-- Writes the sweep's decisions (service role). p: {source, watermark, leads: [{id, created_at, is_test, occurred_at,
-- decisions: [{creator_id, link_id, code, deal_id, deliverable_id, campaign_id, touch, status, reason, touch_at,
-- evidence_source, stage: {stage, reason, flags, unmapped}}]}]}. Staff decisions (sticky statuses) are never changed.
create or replace function inf.lead_sync_apply(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_lead jsonb; v_d jsonb; a inf.lead_attributions; v_id uuid; v_new boolean; v_status text; v_stage jsonb;
  v_source text := coalesce(p ->> 'source', 'sweep'); v_n int := 0; v_changed int := 0; v_user uuid;
  v_occurred timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  for v_lead in select * from jsonb_array_elements(coalesce(p -> 'leads', '[]')) loop
    v_occurred := coalesce((v_lead ->> 'occurred_at')::timestamptz, now());
    -- Release a credit that moved to another creator before claiming it (one credit per lead).
    update inf.lead_attributions la set touch = 'none'
     where la.student_lead_id = (v_lead ->> 'id')::bigint and la.touch in ('first', 'last')
       and la.status in ('credited')
       and not exists (select 1 from jsonb_array_elements(v_lead -> 'decisions') d
                        where (d ->> 'creator_id')::uuid = la.creator_id and d ->> 'touch' in ('first', 'last')
                          and d ->> 'status' in ('credited', 'manually_credited', 'fraud_suspected'));
    for v_d in select * from jsonb_array_elements(coalesce(v_lead -> 'decisions', '[]')) loop
      select * into a from inf.lead_attributions
       where student_lead_id = (v_lead ->> 'id')::bigint and creator_id = (v_d ->> 'creator_id')::uuid for update;
      v_new := a.id is null;
      v_status := case when not v_new and a.status in ('fraud_suspected', 'manually_rejected', 'manually_credited') then a.status
                       else v_d ->> 'status' end;
      v_stage := v_d -> 'stage';
      if v_new then
        insert into inf.lead_attributions (student_lead_id, creator_id, link_id, deal_id, deliverable_id, campaign_id, code, touch, status,
                                           reason, evidence_source, touch_at, lead_created_at, is_test, creator_stage, stage_reason, stage_flags)
        values ((v_lead ->> 'id')::bigint, (v_d ->> 'creator_id')::uuid, nullif(v_d ->> 'link_id', '')::uuid,
                nullif(v_d ->> 'deal_id', '')::uuid, nullif(v_d ->> 'deliverable_id', '')::uuid, nullif(v_d ->> 'campaign_id', '')::uuid,
                v_d ->> 'code', v_d ->> 'touch', v_status, nullif(v_d ->> 'reason', ''), v_d ->> 'evidence_source',
                (v_d ->> 'touch_at')::timestamptz, (v_lead ->> 'created_at')::timestamptz, coalesce((v_lead ->> 'is_test')::boolean, false),
                v_stage ->> 'stage', nullif(v_stage ->> 'reason', ''),
                coalesce(array(select jsonb_array_elements_text(v_stage -> 'flags')), '{}'))
        returning id into v_id;
        insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor) values (v_id, null, v_status, v_d ->> 'reason', 'system');
      else
        v_id := a.id;
        update inf.lead_attributions set
          link_id = nullif(v_d ->> 'link_id', '')::uuid, deal_id = nullif(v_d ->> 'deal_id', '')::uuid,
          deliverable_id = nullif(v_d ->> 'deliverable_id', '')::uuid, campaign_id = nullif(v_d ->> 'campaign_id', '')::uuid,
          code = v_d ->> 'code', touch = v_d ->> 'touch', status = v_status,
          reason = case when v_status = a.status and a.status in ('fraud_suspected', 'manually_rejected', 'manually_credited') then a.reason
                        else nullif(v_d ->> 'reason', '') end,
          evidence_source = v_d ->> 'evidence_source', touch_at = (v_d ->> 'touch_at')::timestamptz,
          is_test = coalesce((v_lead ->> 'is_test')::boolean, false),
          creator_stage = v_stage ->> 'stage', stage_reason = nullif(v_stage ->> 'reason', ''),
          stage_flags = coalesce(array(select jsonb_array_elements_text(v_stage -> 'flags')), '{}')
         where id = a.id;
        if a.status is distinct from v_status then
          insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor) values (v_id, a.status, v_status, v_d ->> 'reason', 'system');
          v_changed := v_changed + 1;
        end if;
      end if;
      -- Stage history: one event per change of stage, reason or flags.
      if v_new or a.creator_stage is distinct from v_stage ->> 'stage' or a.stage_reason is distinct from nullif(v_stage ->> 'reason', '')
         or a.stage_flags is distinct from coalesce(array(select jsonb_array_elements_text(v_stage -> 'flags')), '{}') then
        insert into inf.lead_stage_events (attribution_id, student_lead_id, creator_stage, reason_category, flags, source, idem_key, occurred_at)
        values (v_id, (v_lead ->> 'id')::bigint, v_stage ->> 'stage', nullif(v_stage ->> 'reason', ''),
                coalesce(array(select jsonb_array_elements_text(v_stage -> 'flags')), '{}'), v_source,
                v_id || ':' || (v_stage ->> 'stage') || ':' || coalesce(v_stage ->> 'reason', '') || ':' || coalesce((v_stage -> 'flags')::text, '[]')
                  || ':' || extract(epoch from v_occurred)::bigint, v_occurred)
        on conflict (idem_key) do nothing;
        perform inf.emit_event('lead.stage_changed', 'lead_attribution', v_id::text,
                               jsonb_build_object('creator_id', v_d ->> 'creator_id', 'stage', v_stage ->> 'stage', 'status', v_status),
                               'lead_stage:' || v_id || ':' || (v_stage ->> 'stage') || ':' || coalesce((v_stage -> 'flags')::text, ''));
        if v_stage ->> 'stage' = 'enrolled' and v_status in ('credited', 'manually_credited') and v_d ->> 'touch' in ('first', 'last') then
          perform inf.emit_event('lead.enrolled', 'lead_attribution', v_id::text, jsonb_build_object('creator_id', v_d ->> 'creator_id'),
                                 'lead_enrolled:' || v_id);
        end if;
      end if;
      -- A new credited lead: an event for the compensation runner and a note for the creator.
      if v_status = 'credited' and v_d ->> 'touch' in ('first', 'last') and (v_new or a.status <> 'credited' or a.touch not in ('first', 'last')) then
        perform inf.emit_event('lead.attributed', 'lead_attribution', v_id::text,
                               jsonb_build_object('creator_id', v_d ->> 'creator_id', 'deal_id', v_d ->> 'deal_id', 'link_id', v_d ->> 'link_id'),
                               'lead_attributed:' || v_id);
        select user_id into v_user from inf.creator_accounts where creator_id = (v_d ->> 'creator_id')::uuid;
        if v_user is not null and not coalesce((v_lead ->> 'is_test')::boolean, false) then
          perform inf.notify(v_user, 'lead.new', 'New lead from your link', 'Someone enquired through ' || (v_d ->> 'code') || '.',
                             '/creator/leads?lead=' || v_id, jsonb_build_object('attribution_id', v_id), false, 'lead_new:' || v_id);
        end if;
      end if;
      v_n := v_n + 1;
    end loop;
    perform inf.lead_feed_refresh((v_lead ->> 'id')::bigint);
  end loop;
  if p ? 'watermark' and nullif(p ->> 'watermark', '') is not null then
    insert into inf.sync_state (key, watermark, detail) values ('lead_sync', (p ->> 'watermark')::timestamptz, jsonb_build_object('applied', v_n))
    on conflict (key) do update set watermark = greatest(inf.sync_state.watermark, excluded.watermark), detail = excluded.detail, updated_at = now();
  end if;
  return jsonb_build_object('decisions', v_n, 'status_changes', v_changed);
end $$;

-- The watermark the next sweep starts from (2-minute overlap; processing is idempotent).
create or replace function inf.lead_sync_since() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce((select watermark - interval '2 minutes' from inf.sync_state where key = 'lead_sync'), '-infinity'::timestamptz)
   where coalesce(auth.role(), '') = 'service_role';
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Fraud signals (facts → pure rules in the app → flags)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.fraud_facts(p_creators uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_set jsonb := inf.setting('attribution.fraud');
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('settings', v_set, 'creators', coalesce((
    select jsonb_agg(jsonb_build_object(
      'creator_id', c.id,
      'leads_last_hour', (select count(*) from inf.lead_attributions a where a.creator_id = c.id and not a.is_test
                             and a.lead_created_at > now() - interval '1 hour' and a.touch in ('first', 'last')),
      'recent', coalesce((select jsonb_agg(a.lead_created_at) from inf.lead_attributions a where a.creator_id = c.id and not a.is_test
                            and a.lead_created_at > now() - interval '24 hours' and a.touch in ('first', 'last')), '[]'),
      'closed_30d', (select count(*) from inf.lead_attributions a where a.creator_id = c.id and not a.is_test
                        and a.lead_created_at > now() - interval '30 days' and a.creator_stage in ('lost', 'junk', 'duplicate', 'enrolled')),
      'junk_30d', (select count(*) from inf.lead_attributions a where a.creator_id = c.id and not a.is_test
                      and a.lead_created_at > now() - interval '30 days' and a.creator_stage = 'junk'),
      'leads', coalesce((select jsonb_agg(jsonb_build_object(
                  'attribution_id', a.id,
                  'age_hours', extract(epoch from (now() - a.lead_created_at)) / 3600,
                  'student_replied', (select wc.last_student_at is not null from public.w2_conversations wc where wc.phone = l.whatsapp_number limit 1),
                  'same_device_leads', greatest(
                     (select count(distinct a2.student_lead_id) from inf.lead_attributions a2 join public.student_leads l2 on l2.id = a2.student_lead_id
                       where a2.creator_id = c.id and l.fingerprint is not null and l2.fingerprint = l.fingerprint),
                     (select count(distinct a2.student_lead_id) from inf.lead_attributions a2 join public.student_leads l2 on l2.id = a2.student_lead_id
                       where a2.creator_id = c.id and l.ip_address is not null and l2.ip_address = l.ip_address))))
                  from inf.lead_attributions a join public.student_leads l on l.id = a.student_lead_id
                 where a.creator_id = c.id and not a.is_test and a.status = 'credited' and a.touch in ('first', 'last')
                   and a.lead_created_at > now() - interval '30 days'), '[]')))
      from inf.creators c where c.id = any (p_creators)), '[]'));
end $$;

-- Opens flags the app computed (service role). Lead signals put a credited attribution on hold (fraud_suspected).
create or replace function inf.fraud_apply(p jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare v_f jsonb; v_n int := 0; v_attr uuid; a inf.lead_attributions;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  for v_f in select * from jsonb_array_elements(coalesce(p -> 'flags', '[]')) loop
    v_attr := nullif(v_f ->> 'attribution_id', '')::uuid;
    -- A signal staff already cleared for this lead does not come back.
    if exists (select 1 from inf.fraud_flags f where f.creator_id = (v_f ->> 'creator_id')::uuid and f.signal = v_f ->> 'signal'
                 and f.attribution_id is not distinct from v_attr and f.status = 'cleared' and (v_attr is not null or f.decided_at > now() - interval '24 hours')) then
      continue;
    end if;
    insert into inf.fraud_flags (creator_id, attribution_id, signal, detail)
    values ((v_f ->> 'creator_id')::uuid, v_attr, v_f ->> 'signal', coalesce(v_f -> 'detail', '{}'))
    on conflict do nothing;
    if found then
      v_n := v_n + 1;
      if v_attr is not null then
        select * into a from inf.lead_attributions where id = v_attr for update;
        if a.status = 'credited' then
          update inf.lead_attributions set status = 'fraud_suspected' where id = a.id;
          insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor)
          values (a.id, a.status, 'fraud_suspected', 'signal: ' || (v_f ->> 'signal'), 'system');
          perform inf.lead_feed_refresh(a.student_lead_id);
        end if;
      end if;
    end if;
  end loop;
  return v_n;
end $$;

-- Staff close a flag: cleared (the credit is restored) or confirmed (the attribution is rejected).
create or replace function inf.fraud_decide(p_flag uuid, p_confirm boolean, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare f inf.fraud_flags; a inf.lead_attributions;
begin
  if not inf.has_perm('fraud.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.fraud_flags set status = case when p_confirm then 'confirmed' else 'cleared' end, decided_by = auth.uid(), decided_at = now(),
         note = trim(p_note)
   where id = p_flag and status = 'open' returning * into f;
  if f.id is null then raise exception 'this flag has already been decided' using errcode = '22023'; end if;
  if f.attribution_id is not null then
    select * into a from inf.lead_attributions where id = f.attribution_id for update;
    if p_confirm and a.status not in ('manually_rejected', 'manually_credited') then
      update inf.lead_attributions set status = 'manually_rejected', touch = 'none', decided_by = auth.uid(), decided_at = now(),
             decision_note = trim(p_note) where id = a.id;
      insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor_id, actor)
      values (a.id, a.status, 'manually_rejected', trim(p_note), auth.uid(), 'staff');
    elsif not p_confirm and a.status = 'fraud_suspected'
          and not exists (select 1 from inf.fraud_flags x where x.attribution_id = a.id and x.status = 'open') then
      update inf.lead_attributions set status = 'credited' where id = a.id;
      insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor_id, actor)
      values (a.id, a.status, 'credited', trim(p_note), auth.uid(), 'staff');
    end if;
    perform inf.job_enqueue('leads.rerun', jsonb_build_object('lead_ids', jsonb_build_array(a.student_lead_id)), now(),
                            'leads_rerun:' || a.student_lead_id || ':' || extract(epoch from clock_timestamp())::text);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff overrides and backfill
-- ---------------------------------------------------------------------------------------------------------------
-- Credit a creator for a lead (creating the attribution if their link wasn't recorded), or reject an attribution.
-- Mandatory reason; audited; the rest of the lead is recomputed by the next run.
create or replace function inf.attribution_override(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_lead bigint := (p ->> 'student_lead_id')::bigint;
  v_creator uuid := (p ->> 'creator_id')::uuid;
  v_status text := p ->> 'status';
  v_reason text := trim(p ->> 'reason');
  a inf.lead_attributions;
  l public.student_leads;
  v_id uuid;
begin
  if not inf.has_perm('attribution.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_status not in ('manually_credited', 'manually_rejected') then raise exception 'invalid status' using errcode = '22023'; end if;
  if coalesce(char_length(v_reason), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = v_lead;
  if l.id is null then raise exception 'no such lead' using errcode = '22023'; end if;
  select * into a from inf.lead_attributions where student_lead_id = v_lead and creator_id = v_creator for update;
  if v_status = 'manually_credited' then
    -- Only one creator earns a lead: anyone else holding the credit drops to "another creator".
    update inf.lead_attributions set touch = 'none', status = case when status = 'credited' then 'duplicate' else status end,
           reason = case when status = 'credited' then 'another_creator' else reason end
     where student_lead_id = v_lead and creator_id <> v_creator and touch in ('first', 'last');
  end if;
  if a.id is null then
    if v_status = 'manually_rejected' then raise exception 'no attribution to reject' using errcode = '22023'; end if;
    insert into inf.lead_attributions (student_lead_id, creator_id, link_id, deal_id, campaign_id, code, touch, status, evidence_source,
                                       touch_at, lead_created_at, is_test, decided_by, decided_at, decision_note, creator_stage)
    select v_lead, v_creator, k.id, k.deal_id, k.campaign_id, coalesce(k.code, 'MANUAL-' || upper(left(v_creator::text, 4))), 'first', v_status,
           'manual', now(), l.created_at, coalesce(l.is_test, false), auth.uid(), now(), v_reason, 'new'
      from (select null) x left join inf.tracking_links k on k.id = nullif(p ->> 'link_id', '')::uuid and k.creator_id = v_creator
    returning id into v_id;
    insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor_id, actor) values (v_id, null, v_status, v_reason, auth.uid(), 'staff');
  else
    v_id := a.id;
    update inf.lead_attributions set status = v_status, touch = case when v_status = 'manually_credited' then 'first' else 'none' end,
           decided_by = auth.uid(), decided_at = now(), decision_note = v_reason where id = a.id;
    insert into inf.attribution_decisions (attribution_id, from_status, to_status, reason, actor_id, actor) values (a.id, a.status, v_status, v_reason, auth.uid(), 'staff');
  end if;
  update inf.fraud_flags set status = case when v_status = 'manually_rejected' then 'confirmed' else 'cleared' end, decided_by = auth.uid(),
         decided_at = now(), note = v_reason
   where attribution_id = v_id and status = 'open';
  perform inf.emit_event('attribution.overridden', 'lead_attribution', v_id::text, jsonb_build_object('status', v_status, 'creator_id', v_creator),
                         'attribution_override:' || v_id || ':' || extract(epoch from clock_timestamp())::text);
  perform inf.job_enqueue('leads.rerun', jsonb_build_object('lead_ids', jsonb_build_array(v_lead)), now(),
                          'leads_rerun:' || v_lead || ':' || extract(epoch from clock_timestamp())::text);
  perform inf.lead_feed_refresh(v_lead);
  return v_id;
end $$;

-- Re-run attribution for leads created in a date range (staff); the job pages through the range.
create or replace function inf.lead_backfill(p_from date, p_to date) returns bigint
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('attribution.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'choose a range of up to 400 days' using errcode = '22023'; end if;
  return inf.job_enqueue('leads.backfill', jsonb_build_object('from', (p_from::timestamp at time zone 'Asia/Kolkata'),
                                                              'to', ((p_to + 1)::timestamp at time zone 'Asia/Kolkata'), 'after', 0),
                         now(), 'leads_backfill:' || p_from || ':' || p_to || ':' || extract(epoch from clock_timestamp())::text);
end $$;

create or replace function inf.stage_mapping_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('settings.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.stage_mappings (priority, conditions, creator_stage, reason_category, flag, active)
    values ((p ->> 'priority')::int, p -> 'conditions', nullif(p ->> 'creator_stage', ''), nullif(trim(p ->> 'reason_category'), ''),
            nullif(p ->> 'flag', ''), coalesce((p ->> 'active')::boolean, true))
    returning id into v_id;
  else
    update inf.stage_mappings set priority = (p ->> 'priority')::int, conditions = p -> 'conditions',
           creator_stage = nullif(p ->> 'creator_stage', ''), reason_category = nullif(trim(p ->> 'reason_category'), ''),
           flag = nullif(p ->> 'flag', ''), active = coalesce((p ->> 'active')::boolean, true), updated_by = auth.uid()
     where id = v_id;
    if not found then raise exception 'no such rule' using errcode = '22023'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'another rule has this priority' using errcode = '23505';
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff reads
-- ---------------------------------------------------------------------------------------------------------------
-- The staff lead pipeline: every attribution with the creator-safe row, plus contact details for lead.contacts.
create or replace function inf.leads_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_contacts boolean := inf.has_perm('lead.contacts');
  v_status text[] := case when jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0
                          then array(select jsonb_array_elements_text(p -> 'status')) end;
  v_stage text := nullif(p ->> 'stage', '');
  v_q text := nullif(trim(p ->> 'q'), '');
  v_creator uuid := nullif(p ->> 'creator_id', '')::uuid;
  v_page int := greatest(coalesce((p ->> 'page')::int, 1), 1);
  v_size int := least(greatest(coalesce((p ->> 'page_size')::int, 50), 1), 200);
begin
  if not inf.has_perm('lead.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with rows as (
      select f.*, a.student_lead_id, a.decision_note, c.display_name as creator_name, c.handle,
             case when v_contacts then l.whatsapp_number end as phone, case when v_contacts then l.email_id end as email,
             case when v_contacts then l.student_name end as student_name
        from inf.creator_lead_feed f join inf.lead_attributions a on a.id = f.attribution_id
        join inf.creators c on c.id = f.creator_id
        left join public.student_leads l on l.id = a.student_lead_id
       where (v_status is null or f.attribution_status = any (v_status))
         and (v_stage is null or f.creator_stage = v_stage)
         and (v_creator is null or f.creator_id = v_creator)
         and (v_q is null or f.lead_ref ilike '%' || v_q || '%' or f.code ilike '%' || v_q || '%' or c.display_name ilike '%' || v_q || '%')
         and (coalesce((p ->> 'include_test')::boolean, false) or not f.is_test)
    )
    select jsonb_build_object('total', (select count(*) from rows), 'rows', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.lead_at desc) from (select * from rows order by lead_at desc offset (v_page - 1) * v_size limit v_size) r), '[]'))
  );
end $$;

create or replace function inf.lead_detail(p_attribution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f inf.creator_lead_feed; a inf.lead_attributions; v_staff boolean := inf.has_perm('lead.read');
begin
  select * into f from inf.creator_lead_feed where attribution_id = p_attribution;
  if f.attribution_id is null then return null; end if;
  if not (v_staff or coalesce(f.creator_id = inf.current_creator_id(), false) or inf.agency_can(f.creator_id, 'view')) then return null; end if;
  select * into a from inf.lead_attributions where id = p_attribution;
  return to_jsonb(f) || jsonb_build_object(
    'staff', v_staff,
    'decisions', case when v_staff then coalesce((select jsonb_agg(jsonb_build_object('from', d.from_status, 'to', d.to_status, 'reason', d.reason,
                                                                                      'actor', d.actor, 'at', d.at) order by d.at)
                                                    from inf.attribution_decisions d where d.attribution_id = a.id), '[]') end,
    'other_creators', case when v_staff then coalesce((select jsonb_agg(jsonb_build_object('attribution_id', x.id, 'creator_id', x.creator_id,
                                                                                           'creator_name', c.display_name, 'status', x.status, 'touch', x.touch,
                                                                                           'code', x.code, 'touch_at', x.touch_at) order by x.touch_at)
                                                         from inf.lead_attributions x join inf.creators c on c.id = x.creator_id
                                                        where x.student_lead_id = a.student_lead_id and x.id <> a.id), '[]') end,
    'student_lead_id', case when v_staff then a.student_lead_id end,
    'contact', case when v_staff and inf.has_perm('lead.contacts') then (select jsonb_build_object('phone', l.whatsapp_number, 'email', l.email_id,
                                                                                                   'name', l.student_name)
                                                                             from public.student_leads l where l.id = a.student_lead_id) end,
    'flags_open', case when v_staff then coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'signal', x.signal, 'detail', x.detail, 'opened_at', x.opened_at))
                                                     from inf.fraud_flags x where x.attribution_id = a.id and x.status = 'open'), '[]') end,
    'touch_at', a.touch_at, 'evidence_source', a.evidence_source);
end $$;

create or replace function inf.fraud_queue(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_status text := coalesce(nullif(p ->> 'status', ''), 'open');
begin
  if not inf.has_perm('fraud.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
           'id', f.id, 'creator_id', f.creator_id, 'creator_name', c.display_name, 'handle', c.handle, 'attribution_id', f.attribution_id,
           'lead_ref', (select x.lead_ref from inf.creator_lead_feed x where x.attribution_id = f.attribution_id),
           'signal', f.signal, 'detail', f.detail, 'status', f.status, 'opened_at', f.opened_at, 'decided_at', f.decided_at, 'note', f.note)
           order by f.opened_at desc)
      from inf.fraud_flags f join inf.creators c on c.id = f.creator_id
     where v_status = 'all' or f.status = v_status), '[]');
end $$;

create or replace function inf.attribution_overview() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from inf.lead_attributions where not is_test group by status) s), '{}'),
    'open_flags', (select count(*) from inf.fraud_flags where status = 'open'),
    'last_sync', (select jsonb_build_object('watermark', watermark, 'updated_at', updated_at, 'detail', detail) from inf.sync_state where key = 'lead_sync'),
    'unmapped', (select count(*) from inf.lead_attributions where 'unmapped' = any (stage_flags)))
   where inf.has_perm('lead.read');
$$;

-- Saved views for the lead pipeline (creators, agencies and staff each keep their own; staff may share theirs).
alter table inf.saved_views drop constraint saved_views_scope_check;
alter table inf.saved_views add constraint saved_views_scope_check check (scope in ('creators', 'leads'));

create or replace function inf.lead_view_save(p_name text, p_filters jsonb, p_shared boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_staff boolean := inf.has_perm('lead.read');
begin
  if auth.uid() is null or not (v_staff or inf.current_creator_id() is not null
                                or exists (select 1 from inf.agency_members m where m.user_id = auth.uid() and m.status = 'active')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into inf.saved_views (scope, name, filters, is_shared) values ('leads', trim(p_name), p_filters, v_staff and coalesce(p_shared, false))
  on conflict (owner_id, scope, name) do update set filters = excluded.filters, is_shared = excluded.is_shared
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.lead_view_delete(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.saved_views where id = p_id and owner_id = auth.uid() and scope = 'leads';
end $$;

create or replace function inf.lead_views() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'filters', v.filters, 'shared', v.is_shared,
                                               'mine', v.owner_id = auth.uid()) order by v.name), '[]')
    from inf.saved_views v
   where v.scope = 'leads' and (v.owner_id = auth.uid() or (v.is_shared and inf.has_perm('lead.read')));
$$;

-- Schedule the sweep (S-3).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('inf-lead-sync', '* * * * *', $c$select inf.cron_dispatch('/api/internal/lead-sync')$c$);
  end if;
end $$;

-- Realtime on the creator-safe projection only (S-6).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'inf' and tablename = 'creator_lead_feed') then
    alter publication supabase_realtime add table inf.creator_lead_feed;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.tracking_links enable row level security;
alter table inf.link_clicks enable row level security;
alter table inf.lead_attributions enable row level security;
alter table inf.attribution_decisions enable row level security;
alter table inf.fraud_flags enable row level security;
alter table inf.stage_mappings enable row level security;
alter table inf.lead_stage_events enable row level security;
alter table inf.creator_lead_feed enable row level security;
alter table inf.sync_state enable row level security;

create policy tracking_links_read on inf.tracking_links for select to authenticated
  using ((select inf.has_perm('creator.read')) or coalesce(creator_id = (select inf.current_creator_id()), false) or inf.agency_can(creator_id, 'view'));
create policy lead_attributions_staff_read on inf.lead_attributions for select to authenticated using ((select inf.has_perm('lead.read')));
create policy attribution_decisions_staff_read on inf.attribution_decisions for select to authenticated using ((select inf.has_perm('lead.read')));
create policy fraud_flags_staff_read on inf.fraud_flags for select to authenticated using ((select inf.has_perm('fraud.review')));
create policy stage_mappings_staff_read on inf.stage_mappings for select to authenticated using ((select inf.has_perm('lead.read')));
create policy lead_stage_events_staff_read on inf.lead_stage_events for select to authenticated using ((select inf.has_perm('lead.read')));
-- Creators see their own rows; agencies with the view grant see their creators' rows; staff with lead.read see all.
create policy creator_lead_feed_read on inf.creator_lead_feed for select to authenticated
  using ((select inf.has_perm('lead.read'))
         or coalesce(creator_id = (select inf.current_creator_id()), false)
         or inf.agency_can(creator_id, 'view'));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.tracking_links', 'authenticated', 'select'),
  ('table', 'inf.lead_attributions', 'authenticated', 'select'),
  ('table', 'inf.attribution_decisions', 'authenticated', 'select'),
  ('table', 'inf.fraud_flags', 'authenticated', 'select'),
  ('table', 'inf.stage_mappings', 'authenticated', 'select'),
  ('table', 'inf.lead_stage_events', 'authenticated', 'select'),
  ('table', 'inf.creator_lead_feed', 'authenticated', 'select'),
  ('function', 'inf.link_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.link_set_active(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.links_list(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.link_options(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.fraud_decide(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.attribution_override(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.lead_backfill(date, date)', 'authenticated', 'execute'),
  ('function', 'inf.stage_mapping_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.leads_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.lead_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.fraud_queue(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.attribution_overview()', 'authenticated', 'execute'),
  ('function', 'inf.lead_view_save(text, jsonb, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.lead_view_delete(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.lead_views()', 'authenticated', 'execute'),
  ('function', 'inf.campaign_attribution_save(uuid, text, text)', 'authenticated', 'execute');
call inf.apply_client_grants();
