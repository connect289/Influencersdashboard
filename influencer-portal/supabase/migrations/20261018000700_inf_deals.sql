-- Phase 3.4: deals, immutable deal versions, presets, the TDS section table and the compensation config check
-- (spec 5 "Deals and compensation", 6, 11; ERD §3; D-05).
--
--   * A deal belongs to a creator and optionally a campaign. Staff build its terms in `draft_config` (validated);
--     proposing snapshots them into an immutable `deal_versions` row that the creator (or their negotiating agency)
--     accepts or declines. Accepted versions are the deal's terms, in force from their `effective_from`; a change
--     after agreement is an amendment (a new proposed version), never an edit.
--   * Every stored config passes `inf.comp_config_valid()`: the JSON Schema generated from the zod schema
--     (`inf.comp_config_schema()`) plus the cross-field rules zod checks in superRefine.
--   * A deal is created automatically when a campaign offer is accepted: offer_accept() enqueues
--     `deal.from_application`; the app builds the config from the campaign preset and the agreed terms and calls
--     `deal_from_application()` (service role, idempotent per application).

-- ---------------------------------------------------------------------------------------------------------------
-- Compensation config validation
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.comp_config_errors(p jsonb) returns text[]
language plpgsql immutable set search_path = '' as $$
declare
  v_errs  text[] := inf.json_schema_errors(p, inf.comp_config_schema());
  f       jsonb;
  r       jsonb;
  t       jsonb;
  v_kinds text[];
  v_sum   numeric;
  v_prev  int;
  v_flat  boolean;
  v_x     text;
  v_i     int;
begin
  if cardinality(v_errs) > 0 then return v_errs; end if;

  -- Percentages carry at most two decimals (basis points).
  if exists (select 1 from jsonb_path_query(p, 'lax $.**.pct') x
              where jsonb_typeof(x) = 'number' and (x #>> '{}')::numeric * 100 <> trunc((x #>> '{}')::numeric * 100)) then
    v_errs := array_append(v_errs, 'two_decimals');
  end if;

  -- Ids are unique across the document (milestones as "<component>.<milestone>").
  for v_x in
    select id from (
      select f2 ->> 'id' as id from jsonb_array_elements(p -> 'fixed') f2
      union all select (f2 ->> 'id') || '.' || (m ->> 'id') from jsonb_array_elements(p -> 'fixed') f2, jsonb_array_elements(f2 -> 'milestones') m
      union all select x ->> 'id' from jsonb_array_elements(p -> 'commission') x
      union all select x ->> 'id' from jsonb_array_elements(p -> 'floors') x
      union all select x ->> 'id' from jsonb_array_elements(p -> 'bonuses') x
      union all select x ->> 'id' from jsonb_array_elements(p -> 'penalties') x
      union all select x ->> 'id' from jsonb_array_elements(p -> 'fees') x
      union all select x ->> 'id' from jsonb_array_elements(p -> 'non_cash') x) ids
    group by id having count(*) > 1 order by id
  loop
    v_errs := array_append(v_errs, 'duplicate_id:' || v_x);
  end loop;

  -- Fixed components: retainers need their schedule; others need milestones of one kind adding up to the whole.
  for f in select * from jsonb_array_elements(p -> 'fixed') loop
    if f ->> 'basis' = 'retainer' then
      if not f ? 'retainer' then v_errs := array_append(v_errs, 'retainer_required'); end if;
      continue;
    end if;
    if jsonb_array_length(f -> 'milestones') = 0 then
      v_errs := array_append(v_errs, 'milestones_required');
      continue;
    end if;
    select array_agg(distinct m -> 'share' ->> 'type') into v_kinds from jsonb_array_elements(f -> 'milestones') m;
    if cardinality(v_kinds) > 1 then
      v_errs := array_append(v_errs, 'milestones_mixed');
    elsif v_kinds[1] = 'pct' then
      select sum(round((m -> 'share' ->> 'pct')::numeric * 100)) into v_sum from jsonb_array_elements(f -> 'milestones') m;
      if v_sum <> 10000 then v_errs := array_append(v_errs, 'milestones_not_100'); end if;
    else
      select sum((m -> 'share' ->> 'amount_paise')::numeric) into v_sum from jsonb_array_elements(f -> 'milestones') m;
      if v_sum <> (f ->> 'amount_paise')::numeric * (f ->> 'units')::numeric then
        v_errs := array_append(v_errs, 'milestones_not_total');
      end if;
    end if;
  end loop;

  -- Commission rules: tiers start at 1 and ascend, carry the right kind of rate; dates in order.
  for r in select * from jsonb_array_elements(p -> 'commission') loop
    v_flat := r -> 'basis' ->> 'type' in ('flat_per_enrollment', 'flat_per_qualified_lead', 'flat_per_lead', 'flat_per_application');
    if r ? 'slabs' then
      if (r -> 'slabs' -> 'tiers' -> 0 ->> 'from')::int <> 1 then v_errs := array_append(v_errs, 'tiers_start_at_1'); end if;
      v_prev := 0;
      for v_i in 0 .. jsonb_array_length(r -> 'slabs' -> 'tiers') - 1 loop
        t := r -> 'slabs' -> 'tiers' -> v_i;
        if v_i > 0 and (t ->> 'from')::int <= v_prev then v_errs := array_append(v_errs, 'tiers_ascending'); end if;
        v_prev := (t ->> 'from')::int;
        if v_flat and not t ? 'amount_paise' then v_errs := array_append(v_errs, 'tier_amount'); end if;
        if not v_flat and not t ? 'pct' then v_errs := array_append(v_errs, 'tier_pct'); end if;
      end loop;
    end if;
    if r ? 'effective_from' and r ? 'effective_to' and (r ->> 'effective_to')::date < (r ->> 'effective_from')::date then
      v_errs := array_append(v_errs, 'dates');
    end if;
  end loop;

  -- References.
  if p -> 'recoupment' ->> 'mode' <> 'none' then
    for v_x in select x from jsonb_array_elements_text(p -> 'recoupment' -> 'fixed') x
                where x not in (select f2 ->> 'id' from jsonb_array_elements(p -> 'fixed') f2) loop
      v_errs := array_append(v_errs, 'unknown_fixed:' || v_x);
    end loop;
    if jsonb_array_length(p -> 'commission') = 0 then v_errs := array_append(v_errs, 'recoupment_needs_commission'); end if;
  end if;
  for v_x in select x from jsonb_array_elements(p -> 'floors') fl, jsonb_array_elements_text(fl -> 'rules') x
              where x not in (select c ->> 'id' from jsonb_array_elements(p -> 'commission') c) loop
    v_errs := array_append(v_errs, 'unknown_rule:' || v_x);
  end loop;
  return v_errs[1:20];
end $$;

create or replace function inf.comp_config_valid(p jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select cardinality(inf.comp_config_errors(p)) = 0;
$$;

-- Mirrors dealModel() in lib/compensation/schema.ts.
create or replace function inf.deal_model(p jsonb) returns text
language sql immutable set search_path = '' as $$
  select case
    when jsonb_array_length(coalesce(p -> 'fixed', '[]')) > 0 and jsonb_array_length(coalesce(p -> 'commission', '[]')) > 0 then 'hybrid'
    when jsonb_array_length(coalesce(p -> 'fixed', '[]')) > 0 then 'fixed_only'
    when jsonb_array_length(coalesce(p -> 'commission', '[]')) > 0 then 'commission_only'
    when jsonb_array_length(coalesce(p -> 'non_cash', '[]')) > 0 and jsonb_array_length(coalesce(p -> 'fees', '[]')) = 0 then 'barter'
    else 'custom' end;
$$;

-- jsonb's text form is canonical (keys sorted), so equal configs hash equally.
create or replace function inf.config_hash(p jsonb) returns text
language sql immutable set search_path = '' as $$
  select encode(sha256(convert_to(p::text, 'UTF8')), 'hex');
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- TDS sections (spec 11). Finance edits; defaults are flagged "confirm with CA" until confirmed (D-19, D-68).
-- ---------------------------------------------------------------------------------------------------------------
create table inf.tds_sections (
  code                    text primary key check (code ~ '^[0-9A-Z]{3,8}$'),
  label                   text not null check (char_length(label) between 2 and 80),
  rate_bps                int not null check (rate_bps between 0 and 10000),
  no_pan_rate_bps         int not null check (no_pan_rate_bps between 0 and 10000),
  single_threshold_paise  bigint check (single_threshold_paise >= 0),
  fy_threshold_paise      bigint check (fy_threshold_paise >= 0),
  components              text[] not null check (components <@ array['commission', 'fixed_fee', 'milestone', 'bonus', 'usage_fee',
                                                                     'exclusivity_fee', 'reimbursement', 'non_cash']),
  borne_by                text not null default 'creator' check (borne_by in ('creator', 'eduwit')),
  position                int not null default 0,
  confirmed_by_ca         boolean not null default false,
  updated_by              uuid,
  updated_at              timestamptz not null default now()
);
create trigger tds_sections_touch before update on inf.tds_sections for each row execute function inf.touch_updated_at();
create trigger tds_sections_audit after insert or update or delete on inf.tds_sections for each row execute function inf.audit_row('tds_section');

insert into inf.tds_sections (code, label, rate_bps, no_pan_rate_bps, single_threshold_paise, fy_threshold_paise, components, borne_by, position) values
  ('194H', 'Commission or brokerage', 200, 2000, null, 2000000, array['commission'], 'creator', 1),
  ('194J', 'Fees for professional services', 1000, 2000, null, 5000000,
   array['fixed_fee', 'milestone', 'bonus', 'usage_fee', 'exclusivity_fee'], 'creator', 2),
  ('194R', 'Benefit or perquisite (barter)', 1000, 2000, null, 2000000, array['non_cash'], 'eduwit', 3);

-- The rates are public law, so every signed-in user (a creator's simulator, statements) may read the table.
create or replace function inf.tds_sections_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(s) - 'updated_by' order by s.position, s.code), '[]')
    from inf.tds_sections s
   where auth.uid() is not null or coalesce(auth.role(), '') = 'service_role';
$$;

create or replace function inf.tds_section_save(p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('tax.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.tds_sections (code, label, rate_bps, no_pan_rate_bps, single_threshold_paise, fy_threshold_paise, components,
                                borne_by, position, confirmed_by_ca, updated_by)
  values (upper(trim(p ->> 'code')), trim(p ->> 'label'), (p ->> 'rate_bps')::int, (p ->> 'no_pan_rate_bps')::int,
          nullif(p ->> 'single_threshold_paise', '')::bigint, nullif(p ->> 'fy_threshold_paise', '')::bigint,
          array(select jsonb_array_elements_text(p -> 'components')), coalesce(p ->> 'borne_by', 'creator'),
          coalesce((p ->> 'position')::int, 0), coalesce((p ->> 'confirmed_by_ca')::boolean, false), auth.uid())
  on conflict (code) do update set label = excluded.label, rate_bps = excluded.rate_bps, no_pan_rate_bps = excluded.no_pan_rate_bps,
    single_threshold_paise = excluded.single_threshold_paise, fy_threshold_paise = excluded.fy_threshold_paise,
    components = excluded.components, borne_by = excluded.borne_by, position = excluded.position,
    confirmed_by_ca = excluded.confirmed_by_ca, updated_by = excluded.updated_by;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Presets (spec 6.2). System presets are generated from lib/compensation/presets.ts; staff can save their own.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.deal_presets (
  id           uuid primary key default gen_random_uuid(),
  key          text unique check (key ~ '^[a-z][a-z0-9_]{2,39}$'),
  name         text not null check (char_length(name) between 2 and 80),
  description  text check (char_length(description) <= 500),
  comp_config  jsonb not null check (inf.comp_config_valid(comp_config)),
  is_system    boolean not null default false,
  archived_at  timestamptz,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index deal_presets_name_idx on inf.deal_presets (lower(name)) where archived_at is null;
create trigger deal_presets_touch before update on inf.deal_presets for each row execute function inf.touch_updated_at();
create trigger deal_presets_audit after insert or update or delete on inf.deal_presets for each row execute function inf.audit_row('deal_preset');

alter table inf.campaigns add column default_preset_id uuid references inf.deal_presets (id) on delete set null;

create or replace function inf.deal_presets_list(p_include_archived boolean default false) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'key', d.key, 'name', d.name, 'description', d.description,
                                               'comp_config', d.comp_config, 'is_system', d.is_system,
                                               'deal_model', inf.deal_model(d.comp_config), 'archived', d.archived_at is not null)
                            order by d.is_system desc, d.name), '[]')
    from inf.deal_presets d
   where inf.has_perm('deal.read') and (p_include_archived or d.archived_at is null);
$$;

create or replace function inf.deal_preset_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not inf.comp_config_valid(p -> 'comp_config') then raise exception 'invalid compensation config' using errcode = '22023'; end if;
  if v_id is null then
    insert into inf.deal_presets (name, description, comp_config)
    values (trim(p ->> 'name'), nullif(trim(p ->> 'description'), ''), p -> 'comp_config')
    returning id into v_id;
  else
    update inf.deal_presets set name = trim(p ->> 'name'), description = nullif(trim(p ->> 'description'), ''), comp_config = p -> 'comp_config'
     where id = v_id and not is_system;
    if not found then raise exception 'system presets cannot be edited' using errcode = '22023'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'a preset with this name exists' using errcode = '23505';
end $$;

create or replace function inf.deal_preset_archive(p_id uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.deal_presets set archived_at = case when p_archived then now() end where id = p_id and not is_system;
  if not found then raise exception 'system presets cannot be archived' using errcode = '22023'; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Deals and versions
-- ---------------------------------------------------------------------------------------------------------------
create sequence inf.deal_code_seq;

create table inf.deals (
  id                   uuid primary key default gen_random_uuid(),
  code                 text not null unique default 'DL-' || lpad(nextval('inf.deal_code_seq')::text, 5, '0'),
  creator_id           uuid not null references inf.creators (id) on delete restrict,
  campaign_id          uuid references inf.campaigns (id) on delete set null,
  application_id       uuid unique references inf.campaign_applications (id) on delete set null,
  title                text not null check (char_length(title) between 3 and 120),
  status               text not null default 'draft'
                         check (status in ('draft', 'proposed', 'negotiating', 'agreed', 'active', 'completed', 'terminated', 'expired')),
  starts_on            date not null,
  ends_on              date check (ends_on is null or ends_on >= starts_on),
  -- Working copy of the terms: the builder's draft before the first proposal, or an amendment being prepared.
  draft_config         jsonb check (draft_config is null or inf.comp_config_valid(draft_config)),
  preset_id            uuid references inf.deal_presets (id) on delete set null,
  current_version_id   uuid,
  deal_model           text not null default 'custom'
                         check (deal_model in ('commission_only', 'fixed_only', 'hybrid', 'barter', 'custom')),
  agreed_terms         jsonb,
  owner_id             uuid references inf.staff_profiles (user_id) on delete set null,
  internal_notes       text check (char_length(internal_notes) <= 4000),
  status_reason        text check (char_length(status_reason) <= 1000),
  agreed_at            timestamptz,
  activated_at         timestamptz,
  closed_at            timestamptz,
  created_by           uuid default auth.uid(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index deals_creator_idx on inf.deals (creator_id, status);
create index deals_campaign_idx on inf.deals (campaign_id) where campaign_id is not null;
create index deals_status_idx on inf.deals (status, updated_at desc);

create table inf.deal_versions (
  id               uuid primary key default gen_random_uuid(),
  deal_id          uuid not null references inf.deals (id) on delete cascade,
  version          int not null check (version >= 1),
  comp_config      jsonb not null check (inf.comp_config_valid(comp_config)),
  config_hash      text not null,
  origin           text not null check (origin in ('builder', 'application', 'amendment', 'renewal')),
  preset_id        uuid references inf.deal_presets (id) on delete set null,
  effective_from   timestamptz not null,
  note             text check (char_length(note) <= 1000),
  state            text not null default 'proposed' check (state in ('proposed', 'accepted', 'declined', 'withdrawn')),
  proposed_by      uuid default auth.uid(),
  proposed_at      timestamptz not null default now(),
  decided_by       uuid,
  decided_at       timestamptz,
  decision_reason  text check (char_length(decision_reason) <= 1000),
  -- Set when the governing contract (Phase 4) is signed for this version.
  is_signed        boolean not null default false,
  unique (deal_id, version)
);
create unique index deal_versions_one_open_idx on inf.deal_versions (deal_id) where state = 'proposed';
alter table inf.deals add constraint deals_current_version_fk foreign key (current_version_id) references inf.deal_versions (id);

-- Versions are immutable snapshots: only the decision (and the signed flag) can change, once.
create or replace function inf.deal_versions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'inf.deal_versions: rows are append-only (delete refused)' using errcode = 'insufficient_privilege';
  end if;
  if (new.deal_id, new.version, new.comp_config, new.config_hash, new.origin, new.effective_from, new.proposed_by, new.proposed_at)
     is distinct from (old.deal_id, old.version, old.comp_config, old.config_hash, old.origin, old.effective_from, old.proposed_by, old.proposed_at)
     or (old.state <> 'proposed' and new.state is distinct from old.state) then
    raise exception 'inf.deal_versions: a version is immutable' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger deal_versions_guard before update or delete on inf.deal_versions for each row execute function inf.deal_versions_guard();
create trigger deals_touch before update on inf.deals for each row execute function inf.touch_updated_at();
create trigger deals_audit after insert or update or delete on inf.deals for each row execute function inf.audit_row('deal');
create trigger deal_versions_audit after insert or update on inf.deal_versions for each row execute function inf.audit_row('deal_version');

-- Engine and dry-run history (spec 6.3). Dry runs record what an amendment would change.
create table inf.comp_runs (
  id               bigint generated always as identity primary key,
  deal_id          uuid not null references inf.deals (id) on delete cascade,
  deal_version_id  uuid references inf.deal_versions (id),
  kind             text not null check (kind in ('dry_run', 'live')),
  as_of            timestamptz not null,
  summary          jsonb not null default '{}'::jsonb,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now()
);
create index comp_runs_deal_idx on inf.comp_runs (deal_id, created_at desc);
create trigger comp_runs_append_only before update or delete on inf.comp_runs for each row execute function inf.forbid_mutation();

-- ---------------------------------------------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------------------------------------------
-- Staff with deal.read; the creator; an agency with the creator's "negotiate" or "view earnings" grant.
create or replace function inf.can_view_deal_of(p_creator uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select inf.has_perm('deal.read') or coalesce(p_creator = inf.current_creator_id(), false)
      or inf.agency_can(p_creator, 'negotiate') or inf.agency_can(p_creator, 'earnings');
$$;

create or replace function inf.deal_notify(p_deal uuid, p_to text, p_event text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_user uuid; v_key text := extract(epoch from clock_timestamp())::bigint::text;
begin
  select * into d from inf.deals where id = p_deal;
  if p_to = 'creator' then
    select user_id into v_user from inf.creator_accounts where creator_id = d.creator_id;
    if v_user is not null then
      perform inf.notify(v_user, p_event, p_title, p_body, '/creator/deals/' || p_deal, jsonb_build_object('deal_id', p_deal), true,
                         p_event || ':' || p_deal || ':' || v_key);
    end if;
  else
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/deals/' || p_deal, jsonb_build_object('deal_id', p_deal), false,
                       p_event || ':' || p_deal || ':' || sp.user_id || ':' || v_key)
      from inf.staff_profiles sp
     where sp.status = 'active' and (sp.user_id = d.owner_id or (d.owner_id is null and exists (
             select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
              where g.user_id = sp.user_id and rp.permission = 'deal.write')));
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Building and proposing
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.deal_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_creator uuid := (p ->> 'creator_id')::uuid; v_config jsonb := p -> 'comp_config';
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from inf.creators c where c.id = v_creator and not c.is_blocked and c.status not in ('blocked', 'archived')) then
    raise exception 'creator cannot take a deal' using errcode = '22023';
  end if;
  if v_config is null or not inf.comp_config_valid(v_config) then raise exception 'invalid compensation config' using errcode = '22023'; end if;
  insert into inf.deals (creator_id, campaign_id, title, starts_on, ends_on, draft_config, preset_id, deal_model, owner_id, internal_notes)
  values (v_creator, nullif(p ->> 'campaign_id', '')::uuid, trim(p ->> 'title'), (p ->> 'starts_on')::date,
          nullif(p ->> 'ends_on', '')::date, v_config, nullif(p ->> 'preset_id', '')::uuid, inf.deal_model(v_config),
          coalesce(nullif(p ->> 'owner_id', '')::uuid, auth.uid()), nullif(trim(p ->> 'internal_notes'), ''))
  returning id into v_id;
  return v_id;
end $$;

-- Edit the working copy and the deal's details. Dates change only before the terms are agreed (afterwards a change is
-- a renewal, Phase 4); the config changes in any open status (after agreement it is an amendment being prepared).
create or replace function inf.deal_update(p_deal uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare d inf.deals;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal for update;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;
  if d.status in ('completed', 'terminated', 'expired') then raise exception 'deal is closed' using errcode = '22023'; end if;
  if p ? 'comp_config' and p -> 'comp_config' <> 'null'::jsonb and not inf.comp_config_valid(p -> 'comp_config') then
    raise exception 'invalid compensation config' using errcode = '22023';
  end if;
  if (p ? 'starts_on' and (p ->> 'starts_on')::date is distinct from d.starts_on
      or p ? 'ends_on' and nullif(p ->> 'ends_on', '')::date is distinct from d.ends_on)
     and d.status not in ('draft', 'negotiating') then
    raise exception 'dates are fixed once the deal is proposed or agreed' using errcode = '22023';
  end if;
  update inf.deals set
    title = coalesce(nullif(trim(p ->> 'title'), ''), title),
    starts_on = coalesce((p ->> 'starts_on')::date, starts_on),
    ends_on = case when p ? 'ends_on' then nullif(p ->> 'ends_on', '')::date else ends_on end,
    draft_config = case when p ? 'comp_config' then nullif(p -> 'comp_config', 'null'::jsonb) else draft_config end,
    deal_model = case when current_version_id is null and p ? 'comp_config' and p -> 'comp_config' <> 'null'::jsonb
                      then inf.deal_model(p -> 'comp_config') else deal_model end,
    owner_id = case when p ? 'owner_id' then nullif(p ->> 'owner_id', '')::uuid else owner_id end,
    internal_notes = case when p ? 'internal_notes' then nullif(trim(p ->> 'internal_notes'), '') else internal_notes end
  where id = p_deal;
end $$;

-- Snapshot the working copy as a proposed version. The first version takes effect at the deal's start (midnight IST);
-- an amendment takes effect at p_effective_from, which must be after the version it replaces.
create or replace function inf.deal_propose(p_deal uuid, p_effective_from timestamptz default null, p_note text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_cur inf.deal_versions; v_id uuid; v_from timestamptz; v_amend boolean;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal for update;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;
  if d.status not in ('draft', 'negotiating', 'agreed', 'active') then raise exception 'deal cannot take a proposal now' using errcode = '22023'; end if;
  if d.draft_config is null then raise exception 'nothing to propose' using errcode = '22023'; end if;
  if exists (select 1 from inf.deal_versions where deal_id = p_deal and state = 'proposed') then
    raise exception 'a proposal is already open' using errcode = '22023';
  end if;
  select * into v_cur from inf.deal_versions where id = d.current_version_id;
  v_amend := v_cur.id is not null;
  if v_amend and inf.config_hash(d.draft_config) = v_cur.config_hash then
    raise exception 'the terms are unchanged' using errcode = '22023';
  end if;
  if v_amend then
    v_from := coalesce(p_effective_from, now());
    if v_from <= v_cur.effective_from then raise exception 'an amendment must take effect after the current terms' using errcode = '22023'; end if;
  else
    v_from := (d.starts_on::timestamp at time zone 'Asia/Kolkata');
  end if;
  insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, preset_id, effective_from, note)
  values (p_deal, coalesce((select max(version) from inf.deal_versions where deal_id = p_deal), 0) + 1, d.draft_config,
          inf.config_hash(d.draft_config), case when v_amend then 'amendment' else 'builder' end, d.preset_id, v_from,
          nullif(trim(p_note), ''))
  returning id into v_id;
  update inf.deals set draft_config = null, status = case when status in ('draft', 'negotiating') then 'proposed' else status end
   where id = p_deal;
  perform inf.deal_notify(p_deal, 'creator', case when v_amend then 'deal.amendment_proposed' else 'deal.proposed' end,
                          case when v_amend then 'Updated deal terms to review' else 'New deal terms to review' end,
                          d.title || ': please review the terms and accept or decline.');
  return v_id;
end $$;

-- The creator (or their negotiating agency) accepts or declines a proposed version. Declining needs a reason and puts
-- the terms back into the working copy for staff to revise.
create or replace function inf.deal_version_respond(p_version uuid, p_accept boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare v inf.deal_versions; d inf.deals;
begin
  select * into v from inf.deal_versions where id = p_version for update;
  if v.id is null or v.state <> 'proposed' then raise exception 'this proposal is no longer open' using errcode = '22023'; end if;
  select * into d from inf.deals where id = v.deal_id for update;
  if not inf.can_negotiate_for(d.creator_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_accept then
    update inf.deal_versions set state = 'accepted', decided_by = auth.uid(), decided_at = now() where id = p_version;
    update inf.deals set current_version_id = p_version, deal_model = inf.deal_model(v.comp_config),
           status = case when status = 'proposed' then 'agreed' else status end,
           agreed_at = coalesce(agreed_at, now())
     where id = d.id;
    perform inf.emit_event('deal.version_accepted', 'deal', d.id::text, jsonb_build_object('version_id', p_version, 'version', v.version),
                           'deal_version_accepted:' || p_version);
    perform inf.deal_notify(d.id, 'eduwit', 'deal.accepted', 'Terms accepted: ' || d.title,
                            'Version ' || v.version || ' was accepted.');
  else
    if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
    update inf.deal_versions set state = 'declined', decided_by = auth.uid(), decided_at = now(), decision_reason = trim(p_reason)
     where id = p_version;
    update inf.deals set draft_config = coalesce(draft_config, v.comp_config),
           status = case when status = 'proposed' then 'negotiating' else status end
     where id = d.id;
    perform inf.deal_notify(d.id, 'eduwit', 'deal.declined', 'Terms declined: ' || d.title, trim(p_reason));
  end if;
end $$;

create or replace function inf.deal_version_withdraw(p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v inf.deal_versions;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from inf.deal_versions where id = p_version for update;
  if v.id is null or v.state <> 'proposed' then raise exception 'this proposal is no longer open' using errcode = '22023'; end if;
  update inf.deal_versions set state = 'withdrawn', decided_by = auth.uid(), decided_at = now() where id = p_version;
  update inf.deals set draft_config = coalesce(draft_config, v.comp_config),
         status = case when status = 'proposed' then (case when exists (select 1 from inf.deal_versions x
                         where x.deal_id = v.deal_id and x.state = 'declined') then 'negotiating' else 'draft' end) else status end
   where id = v.deal_id;
  perform inf.deal_notify(v.deal_id, 'creator', 'deal.proposal_withdrawn', 'Proposal withdrawn',
                          'Eduwit withdrew the proposed terms. You will receive new terms soon.');
end $$;

-- Staff status moves. "agreed → active" is normally done by the countersigned contract (Phase 4); doing it here
-- needs a reason (for example a contract signed on paper) and is audited.
create or replace function inf.deal_set_status(p_deal uuid, p_status text, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_ok boolean;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal for update;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;
  v_ok := case d.status
    when 'draft' then p_status = 'terminated'
    when 'proposed' then p_status = 'terminated'
    when 'negotiating' then p_status = 'terminated'
    when 'agreed' then p_status in ('active', 'terminated')
    when 'active' then p_status in ('completed', 'terminated')
    else false end;
  if not v_ok then raise exception 'cannot move a % deal to %', d.status, p_status using errcode = '22023'; end if;
  if p_status in ('active', 'terminated') and coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  update inf.deal_versions set state = 'withdrawn', decided_by = auth.uid(), decided_at = now()
   where deal_id = p_deal and state = 'proposed' and p_status = 'terminated';
  update inf.deals set status = p_status, status_reason = nullif(trim(p_reason), ''),
         activated_at = case when p_status = 'active' then now() else activated_at end,
         closed_at = case when p_status in ('completed', 'terminated') then now() else closed_at end,
         draft_config = case when p_status in ('completed', 'terminated') then null else draft_config end
   where id = p_deal;
  perform inf.emit_event('deal.' || p_status, 'deal', p_deal::text, jsonb_build_object('reason', nullif(trim(p_reason), '')),
                         'deal_' || p_status || ':' || p_deal);
  perform inf.deal_notify(p_deal, 'creator', 'deal.' || p_status,
                          case p_status when 'active' then 'Your deal is active' when 'completed' then 'Deal completed'
                                        else 'Deal ended' end,
                          d.title || coalesce(': ' || nullif(trim(p_reason), ''), ''));
end $$;

create or replace function inf.deal_delete_draft(p_deal uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inf.deals d where d.id = p_deal and d.status = 'draft'
     and not exists (select 1 from inf.deal_versions v where v.deal_id = d.id);
  if not found then raise exception 'only unproposed drafts can be deleted' using errcode = '22023'; end if;
end $$;

-- Nightly: deals whose end date passed before they started become "expired".
create or replace function inf.deals_expire() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  with x as (
    update inf.deals set status = 'expired', closed_at = now(), draft_config = null
     where status in ('draft', 'proposed', 'negotiating', 'agreed') and ends_on < (now() at time zone 'Asia/Kolkata')::date
    returning id)
  select count(*) into v_n from x;
  update inf.deal_versions v set state = 'withdrawn', decided_at = now()
    from inf.deals d where d.id = v.deal_id and d.status = 'expired' and v.state = 'proposed';
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- From an accepted campaign offer (service role; called by the app with the config it built from the preset)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.deal_from_application(p_app uuid, p_config jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare a inf.campaign_applications; c inf.campaigns; v_id uuid; v_version uuid; v_start date;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select id into v_id from inf.deals where application_id = p_app;
  if v_id is not null then return v_id; end if;
  select * into a from inf.campaign_applications where id = p_app;
  if a.id is null or a.status <> 'accepted' then raise exception 'application is not accepted' using errcode = '22023'; end if;
  if not inf.comp_config_valid(p_config) then raise exception 'invalid compensation config' using errcode = '22023'; end if;
  select * into c from inf.campaigns where id = a.campaign_id;
  v_start := greatest(coalesce(c.starts_on, (a.decided_at at time zone 'Asia/Kolkata')::date), (a.decided_at at time zone 'Asia/Kolkata')::date);
  insert into inf.deals (creator_id, campaign_id, application_id, title, status, starts_on, ends_on, preset_id, deal_model,
                         agreed_terms, owner_id, agreed_at, created_by)
  values (a.creator_id, c.id, a.id, left(c.name, 120), 'agreed', v_start, case when c.ends_on >= v_start then c.ends_on end,
          c.default_preset_id, inf.deal_model(p_config), a.accepted_terms, c.owner_id, a.decided_at, a.decided_by)
  returning id into v_id;
  insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, preset_id, effective_from, note, state,
                                 proposed_by, proposed_at, decided_by, decided_at)
  values (v_id, 1, p_config, inf.config_hash(p_config), 'application', c.default_preset_id,
          (v_start::timestamp at time zone 'Asia/Kolkata'), 'Terms agreed on the campaign application', 'accepted',
          a.decided_by, a.decided_at, a.decided_by, a.decided_at)
  returning id into v_version;
  update inf.deals set current_version_id = v_version where id = v_id;
  perform inf.emit_event('deal.created', 'deal', v_id::text, jsonb_build_object('application_id', p_app, 'version_id', v_version),
                         'deal_created:' || p_app);
  perform inf.deal_notify(v_id, 'creator', 'deal.created', 'Your deal is ready', c.name || ': your agreed terms are in My deals.');
  return v_id;
end $$;

-- What the app needs to build that config: the agreed terms and the campaign's default preset.
create or replace function inf.application_deal_source(p_app uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('application_id', a.id, 'status', a.status, 'terms', a.accepted_terms,
                            'preset_config', p.comp_config, 'has_deal', exists (select 1 from inf.deals d where d.application_id = a.id))
    from inf.campaign_applications a
    join inf.campaigns c on c.id = a.campaign_id
    left join inf.deal_presets p on p.id = c.default_preset_id
   where a.id = p_app and coalesce(auth.role(), '') = 'service_role';
$$;

-- creator_rows: unchanged, plus the "deal type" filter of the creator CRM (deferred from Phase 2, D-49).
create or replace function inf.creator_rows(p jsonb) returns table (
  id uuid, display_name text, handle text, email text, status text, pipeline_stage text, is_blocked boolean,
  city text, state text, niches text[], languages text[], tags text[], owner_id uuid, tier_id uuid,
  updated_at timestamptz, last_activity_at timestamptz, last_contacted_at timestamptz, followers bigint,
  platforms text[], next_follow_up_at timestamptz, owner_name text, tier_name text, has_account boolean)
language sql stable security definer set search_path = '' as $$
  with stats as (
    select pl.creator_id, sum(coalesce(pl.followers, 0))::bigint as followers, array_agg(distinct pl.platform) as platforms
      from inf.creator_platforms pl group by pl.creator_id
  ), follow as (
    select o.creator_id, min(o.next_follow_up_at) as next_follow_up_at
      from inf.outreach_activities o where o.next_follow_up_at is not null and o.follow_up_done_at is null
     group by o.creator_id
  )
  select c.id, c.display_name, c.handle, c.email, c.status, c.pipeline_stage, c.is_blocked, c.city, c.state, c.niches,
         c.languages, c.tags, c.owner_id, c.tier_id, c.updated_at, c.last_activity_at, c.last_contacted_at,
         coalesce(s.followers, 0), coalesce(s.platforms, '{}'), f.next_follow_up_at, sp.full_name, t.name,
         exists (select 1 from inf.creator_accounts a where a.creator_id = c.id)
    from inf.creators c
    left join stats s on s.creator_id = c.id
    left join follow f on f.creator_id = c.id
    left join inf.staff_profiles sp on sp.user_id = c.owner_id
    left join inf.tiers t on t.id = c.tier_id
   where (coalesce((p ->> 'include_blocked')::boolean, false) or not c.is_blocked)
     and (nullif(trim(p ->> 'q'), '') is null
          or (c.display_name || ' ' || c.handle || ' ' || coalesce(c.email, '')) ilike '%' || replace(replace(replace(trim(p ->> 'q'), '\', '\\'), '%', '\%'), '_', '\_') || '%')
     and (coalesce(jsonb_array_length(p -> 'status'), 0) = 0 or c.status in (select jsonb_array_elements_text(p -> 'status')))
     and (coalesce(jsonb_array_length(p -> 'stage'), 0) = 0 or c.pipeline_stage in (select jsonb_array_elements_text(p -> 'stage')))
     and (nullif(p ->> 'platform', '') is null or (p ->> 'platform') = any(coalesce(s.platforms, '{}')))
     and (nullif(p ->> 'followers_min', '') is null or coalesce(s.followers, 0) >= (p ->> 'followers_min')::bigint)
     and (nullif(p ->> 'followers_max', '') is null or coalesce(s.followers, 0) <= (p ->> 'followers_max')::bigint)
     and (nullif(p ->> 'niche', '') is null or lower(p ->> 'niche') = any(c.niches))
     and (nullif(p ->> 'language', '') is null or exists (select 1 from unnest(c.languages) l where lower(l) = lower(p ->> 'language')))
     and (nullif(p ->> 'city', '') is null or lower(c.city) = lower(p ->> 'city'))
     and (nullif(p ->> 'state', '') is null or lower(c.state) = lower(p ->> 'state'))
     and (nullif(p ->> 'tier_id', '') is null or c.tier_id = (p ->> 'tier_id')::uuid)
     and (nullif(p ->> 'owner_id', '') is null
          or (p ->> 'owner_id' = 'me' and c.owner_id = auth.uid())
          or (p ->> 'owner_id' = 'none' and c.owner_id is null)
          or (p ->> 'owner_id' not in ('me', 'none') and c.owner_id::text = p ->> 'owner_id'))
     and (nullif(p ->> 'tag', '') is null or lower(p ->> 'tag') = any(c.tags))
     and (nullif(p ->> 'follow_up', '') is null
          or (p ->> 'follow_up' = 'overdue' and f.next_follow_up_at < now())
          or (p ->> 'follow_up' = 'today' and f.next_follow_up_at < (date_trunc('day', now() at time zone 'Asia/Kolkata') + interval '1 day') at time zone 'Asia/Kolkata'))
     and (nullif(p ->> 'deal_model', '') is null or exists (
          select 1 from inf.deals d where d.creator_id = c.id and d.deal_model = p ->> 'deal_model'
             and d.status in ('proposed', 'negotiating', 'agreed', 'active')));
$$;

-- campaign_save: unchanged, plus the campaign's default deal preset (spec 13 "deal preset(s) offered").
create or replace function inf.campaign_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_prog bigint; v_pos int := 0;
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.campaigns (name, objective, description, visibility, starts_on, ends_on, apply_by, budget_paise, slots,
                               eligibility, deliverables, compensation_summary, internal_notes, owner_id, default_preset_id)
    values (trim(p ->> 'name'), p ->> 'objective', nullif(trim(p ->> 'description'), ''), coalesce(nullif(p ->> 'visibility', ''), 'open'),
            nullif(p ->> 'starts_on', '')::date, nullif(p ->> 'ends_on', '')::date, nullif(p ->> 'apply_by', '')::date,
            nullif(p ->> 'budget_paise', '')::bigint, nullif(p ->> 'slots', '')::int, coalesce(p -> 'eligibility', '{}'),
            coalesce(p -> 'deliverables', '[]'), nullif(trim(p ->> 'compensation_summary'), ''), nullif(trim(p ->> 'internal_notes'), ''),
            coalesce(nullif(p ->> 'owner_id', '')::uuid, auth.uid()), nullif(p ->> 'default_preset_id', '')::uuid)
    returning id into v_id;
  else
    update inf.campaigns set name = trim(p ->> 'name'), objective = p ->> 'objective', description = nullif(trim(p ->> 'description'), ''),
           visibility = coalesce(nullif(p ->> 'visibility', ''), visibility), starts_on = nullif(p ->> 'starts_on', '')::date,
           ends_on = nullif(p ->> 'ends_on', '')::date, apply_by = nullif(p ->> 'apply_by', '')::date,
           budget_paise = nullif(p ->> 'budget_paise', '')::bigint, slots = nullif(p ->> 'slots', '')::int,
           eligibility = coalesce(p -> 'eligibility', '{}'), deliverables = coalesce(p -> 'deliverables', '[]'),
           compensation_summary = nullif(trim(p ->> 'compensation_summary'), ''), internal_notes = nullif(trim(p ->> 'internal_notes'), ''),
           owner_id = nullif(p ->> 'owner_id', '')::uuid,
           default_preset_id = case when p ? 'default_preset_id' then nullif(p ->> 'default_preset_id', '')::uuid else default_preset_id end
     where id = v_id;
    if not found then raise exception 'no such campaign' using errcode = '22023'; end if;
  end if;
  if p ? 'programme_ids' then
    delete from inf.campaign_programmes where campaign_id = v_id
      and programme_id not in (select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x);
    for v_prog in select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x loop
      if not exists (select 1 from public.catalog_programs where id = v_prog) then
        raise exception 'unknown programme %', v_prog using errcode = '22023';
      end if;
      insert into inf.campaign_programmes (campaign_id, programme_id, position) values (v_id, v_prog, v_pos)
      on conflict (campaign_id, programme_id) do update set position = excluded.position;
      v_pos := v_pos + 1;
    end loop;
  end if;
  return v_id;
end $$;

-- offer_accept: unchanged, plus the deal job.
create or replace function inf.offer_accept(p_offer uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare o inf.application_offers; a inf.campaign_applications; c inf.campaigns; v_side text; v_left int;
begin
  select * into o from inf.application_offers where id = p_offer for update;
  if o.id is null or o.status <> 'open' then raise exception 'offer is no longer open' using errcode = '22023'; end if;
  select * into a from inf.campaign_applications where id = o.application_id for update;
  select * into c from inf.campaigns where id = a.campaign_id for update;
  v_side := inf.application_side(a.creator_id);
  if v_side is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if (v_side = 'eduwit') = (o.from_side = 'eduwit') then raise exception 'the other side must accept this offer' using errcode = '22023'; end if;
  v_left := case when c.slots is null then 1 else c.slots - (select count(*) from inf.campaign_applications where campaign_id = c.id and status = 'accepted') end;
  if v_left <= 0 then raise exception 'no slots left' using errcode = '22023'; end if;
  update inf.application_offers set status = 'accepted' where id = p_offer;
  update inf.campaign_applications set status = 'accepted', accepted_terms = o.terms, decided_by = auth.uid(), decided_at = now()
   where id = a.id;
  perform inf.emit_event('application.accepted', 'campaign_application', a.id::text,
                         jsonb_build_object('campaign_id', c.id, 'creator_id', a.creator_id, 'offer_id', o.id, 'terms', o.terms),
                         'application_accepted:' || a.id);
  perform inf.job_enqueue('deal.from_application', jsonb_build_object('application_id', a.id), now(), 'deal_from_application:' || a.id);
  perform inf.application_notify(a.id, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'application.accepted',
                                 'Accepted: ' || c.name, 'The agreed terms are now final. Your deal and contract come next.');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.deal_version_json(v inf.deal_versions) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'comp_config', v.comp_config, 'origin', v.origin,
                            'effective_from', v.effective_from, 'note', v.note, 'state', v.state, 'proposed_at', v.proposed_at,
                            'decided_at', v.decided_at, 'decision_reason', v.decision_reason, 'is_signed', v.is_signed,
                            'deal_model', inf.deal_model(v.comp_config));
$$;

-- Staff see everything; the creator and their agency see the terms, never internal notes, owner or preset.
create or replace function inf.deal_detail(p_deal uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d inf.deals; v_staff boolean := inf.has_perm('deal.read'); v_out jsonb;
begin
  select * into d from inf.deals where id = p_deal;
  if d.id is null or not inf.can_view_deal_of(d.creator_id) then return null; end if;
  v_out := jsonb_build_object(
    'id', d.id, 'code', d.code, 'title', d.title, 'status', d.status, 'starts_on', d.starts_on, 'ends_on', d.ends_on,
    'deal_model', d.deal_model, 'creator_id', d.creator_id, 'campaign_id', d.campaign_id, 'agreed_at', d.agreed_at,
    'activated_at', d.activated_at, 'closed_at', d.closed_at, 'status_reason', d.status_reason, 'agreed_terms', d.agreed_terms,
    'current_version_id', d.current_version_id,
    'creator', (select jsonb_build_object('id', c.id, 'display_name', c.display_name, 'handle', c.handle) from inf.creators c where c.id = d.creator_id),
    'campaign', (select jsonb_build_object('id', c.id, 'name', c.name, 'starts_on', c.starts_on, 'ends_on', c.ends_on, 'status', c.status)
                   from inf.campaigns c where c.id = d.campaign_id),
    'versions', coalesce((select jsonb_agg(inf.deal_version_json(v) order by v.version)
                            from inf.deal_versions v where v.deal_id = d.id and (v_staff or v.state in ('proposed', 'accepted', 'declined'))), '[]'),
    'can_respond', inf.can_negotiate_for(d.creator_id));
  if v_staff then
    v_out := v_out || jsonb_build_object(
      'draft_config', d.draft_config, 'internal_notes', d.internal_notes, 'owner_id', d.owner_id, 'preset_id', d.preset_id,
      'application_id', d.application_id, 'can_write', inf.has_perm('deal.write'),
      'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'as_of', r.as_of, 'summary', r.summary,
                                                            'created_at', r.created_at) order by r.id desc)
                          from (select * from inf.comp_runs where deal_id = d.id order by id desc limit 10) r), '[]'));
  end if;
  return v_out;
end $$;

create or replace function inf.deals_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_page int := greatest(coalesce((p ->> 'page')::int, 1), 1);
  v_size int := least(greatest(coalesce((p ->> 'page_size')::int, 25), 1), 100);
  v_q text := nullif(trim(p ->> 'q'), '');
  v_status text[] := case when jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0
                          then array(select jsonb_array_elements_text(p -> 'status')) end;
  v_model text[] := case when jsonb_typeof(p -> 'model') = 'array' and jsonb_array_length(p -> 'model') > 0
                         then array(select jsonb_array_elements_text(p -> 'model')) end;
  v_total int; v_rows jsonb;
begin
  if not inf.has_perm('deal.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  with f as (
    select d.*, c.display_name, c.handle, cp.name as campaign_name
      from inf.deals d join inf.creators c on c.id = d.creator_id left join inf.campaigns cp on cp.id = d.campaign_id
     where (v_status is null or d.status = any (v_status))
       and (v_model is null or d.deal_model = any (v_model))
       and (nullif(p ->> 'creator_id', '') is null or d.creator_id = (p ->> 'creator_id')::uuid)
       and (nullif(p ->> 'campaign_id', '') is null or d.campaign_id = (p ->> 'campaign_id')::uuid)
       and (nullif(p ->> 'owner_id', '') is null or d.owner_id = (p ->> 'owner_id')::uuid)
       and (v_q is null or d.title ilike '%' || v_q || '%' or d.code ilike '%' || v_q || '%'
            or c.display_name ilike '%' || v_q || '%' or c.handle ilike '%' || v_q || '%'))
  select (select count(*) from f),
         coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'code', x.code, 'title', x.title, 'status', x.status,
                                                       'deal_model', x.deal_model, 'starts_on', x.starts_on, 'ends_on', x.ends_on,
                                                       'creator_id', x.creator_id, 'creator_name', x.display_name, 'handle', x.handle,
                                                       'campaign_name', x.campaign_name, 'owner_id', x.owner_id, 'updated_at', x.updated_at,
                                                       'pending', exists (select 1 from inf.deal_versions v where v.deal_id = x.id and v.state = 'proposed'))
                                    order by x.updated_at desc)
                     from (select * from f order by updated_at desc offset (v_page - 1) * v_size limit v_size) x), '[]')
    into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'page', v_page, 'page_size', v_size, 'rows', v_rows);
end $$;

-- The creator's (or agency's) deals.
create or replace function inf.my_deals(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status,
                                               'deal_model', d.deal_model, 'starts_on', d.starts_on, 'ends_on', d.ends_on,
                                               'campaign_name', c.name, 'application_id', d.application_id,
                                               'pending', exists (select 1 from inf.deal_versions v where v.deal_id = d.id and v.state = 'proposed'))
                            order by d.updated_at desc), '[]')
    from inf.deals d left join inf.campaigns c on c.id = d.campaign_id
   where d.creator_id = p_creator and d.status <> 'draft'
     and (coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'negotiate') or inf.agency_can(p_creator, 'earnings'));
$$;

-- Engine settings in one object (basis points), for the simulator and the dry-run.
create or replace function inf.comp_context() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'eduwit_gst_bps', round(coalesce((inf.setting('compensation.defaults') ->> 'eduwit_commission_gst_pct')::numeric, 18) * 100)::int,
    'hold_days', coalesce((inf.setting('compensation.defaults') ->> 'hold_days')::int, 30),
    'refund_window_days', coalesce((inf.setting('compensation.defaults') ->> 'refund_window_days')::int, 30),
    'penalty_cap_bps', round(coalesce((inf.setting('compensation.defaults') ->> 'penalty_cap_pct')::numeric, 20) * 100)::int,
    'confirm_partial_receipts', coalesce((inf.setting('compensation.defaults') ->> 'confirm_partial_receipts')::boolean, false),
    'gst_rate_bps', round(coalesce((inf.setting('finance.gst') ->> 'rate_pct')::numeric, 18) * 100)::int)
  where auth.uid() is not null or coalesce(auth.role(), '') = 'service_role';
$$;

-- Average Eduwit commission per enrolment (GST-inclusive paise) across a campaign's programmes, from the catalogue's
-- partner rates (S-11). Staff and the service role only: creators never see Eduwit's commission (their simulator runs
-- it server-side and returns only their own earnings).
create or replace function inf.commission_estimate(p_campaign uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select round(avg(case when r.gst_inclusive then r.effective_inr
                        else r.effective_inr * (1 + coalesce((inf.setting('compensation.defaults') ->> 'eduwit_commission_gst_pct')::numeric, 18) / 100)
                   end) * 100)::bigint
    from inf.campaign_programmes cp
    join lateral (select x.effective_inr, x.gst_inclusive from catalog.partner_rates_v x
                   where x.programme_id = cp.programme_id and x.effective_inr > 0
                   order by x.is_highest_for_programme desc nulls last, x.effective_inr desc limit 1) r on true
   where cp.campaign_id = p_campaign and (inf.has_perm('deal.read') or coalesce(auth.role(), '') = 'service_role');
$$;

create or replace function inf.comp_run_record(p_deal uuid, p_version uuid, p_kind text, p_as_of timestamptz, p_summary jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind <> 'dry_run' then raise exception 'only dry runs are recorded from the app' using errcode = '22023'; end if;
  insert into inf.comp_runs (deal_id, deal_version_id, kind, as_of, summary)
  values (p_deal, p_version, p_kind, p_as_of, coalesce(p_summary, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

-- Housekeeping: expire stale deals with the rest of the nightly work.
create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
  perform inf.creators_flag_dormant();
  perform inf.deals_expire();
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS: staff read directly; creators and agencies only through deal_detail() / my_deals().
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.tds_sections enable row level security;
alter table inf.deal_presets enable row level security;
alter table inf.deals enable row level security;
alter table inf.deal_versions enable row level security;
alter table inf.comp_runs enable row level security;

create policy tds_sections_staff_read on inf.tds_sections for select to authenticated
  using ((select inf.has_perm('deal.read')) or (select inf.has_perm('ledger.read')) or (select inf.has_perm('tax.manage')));
create policy deal_presets_staff_read on inf.deal_presets for select to authenticated using ((select inf.has_perm('deal.read')));
create policy deals_staff_read on inf.deals for select to authenticated using ((select inf.has_perm('deal.read')));
create policy deal_versions_staff_read on inf.deal_versions for select to authenticated using ((select inf.has_perm('deal.read')));
create policy comp_runs_staff_read on inf.comp_runs for select to authenticated using ((select inf.has_perm('deal.read')));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.tds_sections', 'authenticated', 'select'),
  ('table', 'inf.deal_presets', 'authenticated', 'select'),
  ('table', 'inf.deals', 'authenticated', 'select'),
  ('table', 'inf.deal_versions', 'authenticated', 'select'),
  ('table', 'inf.comp_runs', 'authenticated', 'select'),
  ('function', 'inf.comp_config_errors(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.comp_config_valid(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deal_model(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.tds_sections_list()', 'authenticated', 'execute'),
  ('function', 'inf.tds_section_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deal_presets_list(boolean)', 'authenticated', 'execute'),
  ('function', 'inf.deal_preset_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deal_preset_archive(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.deal_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deal_update(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deal_propose(uuid, timestamptz, text)', 'authenticated', 'execute'),
  ('function', 'inf.deal_version_respond(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.deal_version_withdraw(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deal_set_status(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.deal_delete_draft(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deal_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deals_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.my_deals(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.comp_context()', 'authenticated', 'execute'),
  ('function', 'inf.commission_estimate(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.comp_run_record(uuid, uuid, text, timestamptz, jsonb)', 'authenticated', 'execute');
call inf.apply_client_grants();
