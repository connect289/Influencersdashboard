-- Phase 10: scorecards, tiers and recommendations (spec 15), the contract compliance tracker, DPDP workflows (data
-- export, deletion requests, consent records for communications) and retention (spec 16, 19). Scores, tier decisions
-- and compliance status are computed by the pure modules in lib/scorecards and lib/compliance; the database supplies the
-- facts, stores the results with their inputs, and applies tier changes. Phase 9 follow-up: digest defaults and hour
-- come from the notifications.delivery setting.

-- ---------------------------------------------------------------------------------------------------------------
-- Tiers: configuration (rules and benefits validated in lib/scorecards/tiers.ts and here)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.tier_json_ok(p_rules jsonb, p_benefits jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_rules) = 'object' and jsonb_typeof(p_benefits) = 'object'
     and not exists (select 1 from jsonb_object_keys(p_rules) k
                      where k not in ('min_score', 'min_enrollments_90d', 'min_months_active', 'min_compliance', 'demote_after_months'))
     and not exists (select 1 from jsonb_each(p_rules) e where jsonb_typeof(e.value) <> 'number' or (e.value)::numeric < 0)
     and not exists (select 1 from jsonb_object_keys(p_benefits) k
                      where k not in ('commission_uplift_pct', 'early_access_days', 'payout_cycle', 'note'))
     and coalesce((p_benefits ->> 'commission_uplift_pct')::numeric between 0 and 100, true)
     and coalesce((p_benefits ->> 'early_access_days')::numeric between 0 and 60, true)
     and coalesce(p_benefits ->> 'payout_cycle' in ('weekly', 'fortnightly', 'monthly'), true)
     and coalesce(char_length(p_benefits ->> 'note') <= 300, true)
$$;
alter table inf.tiers add constraint tiers_json_ok check (inf.tier_json_ok(entry_rules, benefits));
create unique index if not exists tiers_rank_uq on inf.tiers (rank) where active;

create or replace function inf.tier_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('tier.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p ->> 'name')), 0) not between 2 and 40 then raise exception 'invalid tier name' using errcode = '22023'; end if;
  if not inf.tier_json_ok(coalesce(p -> 'entry_rules', '{}'), coalesce(p -> 'benefits', '{}')) then
    raise exception 'invalid tier rules' using errcode = '22023';
  end if;
  if v_id is null then
    insert into inf.tiers (name, rank, entry_rules, benefits, active)
    values (trim(p ->> 'name'), (p ->> 'rank')::int, coalesce(p -> 'entry_rules', '{}'), coalesce(p -> 'benefits', '{}'),
            coalesce((p ->> 'active')::boolean, true))
    returning id into v_id;
  else
    update inf.tiers set name = trim(p ->> 'name'), rank = (p ->> 'rank')::int, entry_rules = coalesce(p -> 'entry_rules', '{}'),
           benefits = coalesce(p -> 'benefits', '{}'), active = coalesce((p ->> 'active')::boolean, active)
     where id = v_id;
    if not found then raise exception 'no such tier' using errcode = '22023'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'another active tier has this rank' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Early campaign access (tier benefit): a campaign opened at T reaches a creator after (longest early access of any
-- tier − their tier's early access) days; creators already invited or applied always see it.
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.campaigns add column opened_at timestamptz;
update inf.campaigns set opened_at = created_at where status in ('open', 'active');
create or replace function inf.campaigns_opened_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status in ('open', 'active') and new.opened_at is null then new.opened_at := now(); end if;
  return new;
end $$;
create trigger campaigns_opened_at before insert or update of status on inf.campaigns
  for each row execute function inf.campaigns_opened_at();

create or replace function inf.early_access_wait(p_creator uuid) returns interval
language sql stable security definer set search_path = '' as $$
  select make_interval(days => greatest(0,
           coalesce((select max((t.benefits ->> 'early_access_days')::int) from inf.tiers t where t.active), 0)
           - coalesce((select (t.benefits ->> 'early_access_days')::int from inf.creators c join inf.tiers t on t.id = c.tier_id
                        where c.id = p_creator and t.active), 0)))
$$;

create or replace function inf.marketplace(p_creator uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_creator uuid := coalesce(p_creator, inf.current_creator_id()); v_wait interval;
begin
  if v_creator is null or not inf.can_negotiate_for(v_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_wait := inf.early_access_wait(v_creator);
  return coalesce((
    select jsonb_agg(x order by (x ->> 'apply_by') nulls last, x ->> 'name')
      from (select inf.campaign_public(c, v_creator) as x
              from inf.campaigns c
             where c.visibility in ('open', 'both') and c.status in ('open', 'active')
               and (c.apply_by is null or c.apply_by >= (now() at time zone 'Asia/Kolkata')::date)
               and (c.opened_at is null or c.opened_at + v_wait <= now()
                    or exists (select 1 from inf.campaign_applications a where a.campaign_id = c.id and a.creator_id = v_creator)
                    or exists (select 1 from inf.campaign_invites i where i.campaign_id = c.id and i.creator_id = v_creator))) s
     where p_all or jsonb_array_length(x -> 'gaps') = 0 or x -> 'application' <> 'null'::jsonb), '[]');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Scorecards and tier history
-- ---------------------------------------------------------------------------------------------------------------
create table inf.scorecards (
  id           uuid primary key default gen_random_uuid(),
  creator_id   uuid not null references inf.creators (id) on delete cascade,
  kind         text not null check (kind in ('monthly', 'on_demand')),
  period       text not null check (period ~ '^\d{4}-\d{2}$'),
  period_from  date not null,
  period_to    date not null check (period_to >= period_from),
  facts        jsonb not null check (jsonb_typeof(facts) = 'object'),
  scores       jsonb not null check (jsonb_typeof(scores) = 'object'),
  figures      jsonb not null default '{}'::jsonb check (jsonb_typeof(figures) = 'object'),
  composite    numeric(5, 1) check (composite between 0 and 100),
  weights      jsonb not null check (jsonb_typeof(weights) = 'object'),
  tier_before  uuid references inf.tiers (id) on delete set null,
  tier_after   uuid references inf.tiers (id) on delete set null,
  created_by   uuid,
  created_at   timestamptz not null default now()
);
create unique index scorecards_monthly_uq on inf.scorecards (creator_id, period) where kind = 'monthly';
create index scorecards_creator_idx on inf.scorecards (creator_id, created_at desc);
create index scorecards_period_idx on inf.scorecards (period, composite desc nulls last) where kind = 'monthly';
create trigger scorecards_append_only before update or delete on inf.scorecards
  for each row execute function inf.forbid_mutation();

create table inf.creator_tier_state (
  creator_id      uuid primary key references inf.creators (id) on delete cascade,
  months_below    int not null default 0 check (months_below >= 0),
  manual_tier_id  uuid references inf.tiers (id) on delete set null,
  manual_until    date,
  manual_reason   text check (char_length(manual_reason) <= 500),
  updated_by      uuid,
  updated_at      timestamptz not null default now(),
  check ((manual_until is null) = (manual_reason is null))
);
create trigger creator_tier_state_audit after insert or update on inf.creator_tier_state
  for each row execute function inf.audit_row('creator_tier_state');

create table inf.tier_history (
  id            bigint generated always as identity primary key,
  creator_id    uuid not null references inf.creators (id) on delete cascade,
  from_tier     uuid references inf.tiers (id) on delete set null,
  to_tier       uuid references inf.tiers (id) on delete set null,
  reason        text not null check (reason in ('eligible', 'below_rules', 'manual', 'manual_ended')),
  note          text check (char_length(note) <= 500),
  scorecard_id  uuid references inf.scorecards (id) on delete set null,
  created_by    uuid,
  created_at    timestamptz not null default now()
);
create index tier_history_creator_idx on inf.tier_history (creator_id, created_at desc);
create trigger tier_history_append_only before update or delete on inf.tier_history
  for each row execute function inf.forbid_mutation();

-- Facts for one creator's scorecard over a period (service role for the monthly job; staff with creator.read for an
-- on-demand card). Counting follows METRICS.md: credited leads by enquiry date, stages cumulative, spend accrued by
-- posting date without settlement lines, revenue received net of GST.
create or replace function inf.scorecard_facts(p_creator uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
  v_base_from date := p_from - 180;
begin
  if not (coalesce(auth.role(), '') = 'service_role' or inf.has_perm('creator.read')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  with dl as (
    select x.*, (x.due_dates ->> 'live')::timestamptz as due_live
      from inf.deliverables x join inf.deals d on d.id = x.deal_id where d.creator_id = p_creator
  ),
  posts as (
    select pp.id, pp.deliverable_id, pp.verified_at,
           (select s.views from inf.post_metric_snapshots s where s.published_post_id = pp.id order by s.captured_at desc limit 1) as views,
           (select coalesce(s.likes, 0) + coalesce(s.comments, 0) + coalesce(s.shares, 0) + coalesce(s.saves, 0)
              from inf.post_metric_snapshots s where s.published_post_id = pp.id order by s.captured_at desc limit 1) as eng
      from inf.published_posts pp join dl on dl.id = pp.deliverable_id
     where pp.verification_status = 'verified'
  ),
  leads as (
    select * from inf.an_leads_live l where l.creator_id = p_creator and not l.is_test and l.day between p_from and p_to
  )
  select jsonb_build_object(
    'due', (select count(*) from dl where inf.ist_date(dl.due_live) between p_from and p_to and dl.cancelled_at is null),
    'on_time', (select count(*) from dl where inf.ist_date(dl.due_live) between p_from and p_to and dl.cancelled_at is null
                  and dl.live_at is not null and dl.live_at <= dl.due_live),
    'cancelled', (select count(*) from dl where inf.ist_date(dl.cancelled_at) between p_from and p_to),
    'revisions', (select count(*) from inf.deliverable_submissions s join dl on dl.id = s.deliverable_id
                   where s.status = 'changes_requested' and inf.ist_date(s.decided_at) between p_from and p_to),
    'reviewed', (select count(distinct s.deliverable_id) from inf.deliverable_submissions s join dl on dl.id = s.deliverable_id
                  where s.decided_at is not null and inf.ist_date(s.decided_at) between p_from and p_to),
    'posts', (select count(*) from posts where inf.ist_date(posts.verified_at) between p_from and p_to and posts.views is not null),
    'views', (select coalesce(sum(posts.views), 0) from posts where inf.ist_date(posts.verified_at) between p_from and p_to),
    'engagements', (select coalesce(sum(posts.eng), 0) from posts
                     where inf.ist_date(posts.verified_at) between p_from and p_to and posts.views is not null),
    'baseline_views_per_post', (select avg(posts.views) from posts
                                 where inf.ist_date(posts.verified_at) >= v_base_from and inf.ist_date(posts.verified_at) < p_from),
    'baseline_engagement_rate', (select sum(posts.eng)::numeric / nullif(sum(posts.views), 0) from posts
                                  where inf.ist_date(posts.verified_at) >= v_base_from and inf.ist_date(posts.verified_at) < p_from),
    'leads', (select count(*) from leads where leads.credited),
    'qualified', (select count(*) from leads where leads.credited and leads.qualified),
    'junk', (select count(*) from leads where leads.credited and leads.junk),
    'duplicates', (select count(*) from leads where leads.duplicate),
    'attributions', (select count(*) from leads where leads.credited or leads.duplicate),
    'enrolled', (select count(*) from leads where leads.credited and leads.enrolled),
    'cost_paise', (select coalesce(sum(case when e.direction = 'credit' then e.amount_paise else -e.amount_paise end), 0)
                     from inf.ledger_entries e
                    where e.creator_id = p_creator and e.type not in ('tds', 'gst', 'payout')
                      and inf.ist_date(e.posted_at) between p_from and p_to),
    'revenue_paise', (select coalesce(sum(r.received_net_paise), 0) from inf.an_revenue r
                       where r.creator_id = p_creator and not r.is_test and r.day between p_from and p_to),
    'disclosure_misses', (select count(*) from dl where inf.ist_date(dl.disclosure_failed_at) between p_from and p_to),
    'claim_violations', (select count(*) from inf.compliance_checks k join dl on dl.id = k.deliverable_id
                          where k.kind = 'banned_claims' and not k.passed and not k.overridden
                            and inf.ist_date(k.created_at) between p_from and p_to),
    'checked', (select count(distinct k.deliverable_id) from inf.compliance_checks k join dl on dl.id = k.deliverable_id
                 where inf.ist_date(k.created_at) between p_from and p_to),
    -- Tier facts
    'enrollments_90d', (select count(*) from inf.an_leads_live l where l.creator_id = p_creator and not l.is_test and l.credited
                          and l.enrolled and l.day between p_to - 89 and p_to),
    'months_active', (select coalesce((extract(year from age(p_to, inf.ist_date(c.approved_at))) * 12
                                       + extract(month from age(p_to, inf.ist_date(c.approved_at))))::int, 0)
                        from inf.creators c where c.id = p_creator),
    'tier_id', (select c.tier_id from inf.creators c where c.id = p_creator),
    'months_below', coalesce((select s.months_below from inf.creator_tier_state s where s.creator_id = p_creator), 0),
    'manual_tier_id', (select s.manual_tier_id from inf.creator_tier_state s where s.creator_id = p_creator and s.manual_until is not null),
    'manual_until', (select s.manual_until from inf.creator_tier_state s where s.creator_id = p_creator)
  ) into v;
  return v;
end $$;

-- Active tiers with their rules and benefits (for the job, the screens and the creator's progress).
create or replace function inf.tiers_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'rank', t.rank, 'rules', t.entry_rules,
                                               'benefits', t.benefits, 'active', t.active,
                                               'creators', (select count(*) from inf.creators c where c.tier_id = t.id))
                            order by t.rank), '[]')
    from inf.tiers t
   where (t.active or inf.has_perm('tier.manage'))
     and (coalesce(auth.role(), '') = 'service_role' or auth.uid() is not null)
$$;

-- Stores a scorecard. Monthly cards (service role) also apply the tier decision made by lib/scorecards/tiers.ts:
-- the creator's tier, the months-below counter, the history row and a notification. On-demand cards (staff with
-- creator.write) never change a tier.
create or replace function inf.scorecard_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_creator uuid := (p ->> 'creator_id')::uuid;
  v_kind text := p ->> 'kind';
  v_id uuid;
  v_before uuid;
  v_after uuid := nullif(p ->> 'tier_after', '')::uuid;
  v_change text := coalesce(p ->> 'change', 'none');
  v_user uuid;
  v_name text;
begin
  if v_kind = 'monthly' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_kind = 'on_demand' and not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_kind not in ('monthly', 'on_demand') then raise exception 'invalid scorecard' using errcode = '22023'; end if;
  select tier_id into v_before from inf.creators where id = v_creator;
  if not found then raise exception 'no such creator' using errcode = '22023'; end if;
  if v_after is not null and not exists (select 1 from inf.tiers t where t.id = v_after and t.active) then
    raise exception 'no such tier' using errcode = '22023';
  end if;
  insert into inf.scorecards (creator_id, kind, period, period_from, period_to, facts, scores, figures, composite, weights,
                              tier_before, tier_after, created_by)
  values (v_creator, v_kind, p ->> 'period', (p ->> 'period_from')::date, (p ->> 'period_to')::date, p -> 'facts', p -> 'scores',
          coalesce(p -> 'figures', '{}'), nullif(p ->> 'composite', '')::numeric, p -> 'weights', v_before,
          case when v_kind = 'monthly' then v_after else v_before end, auth.uid())
  on conflict (creator_id, period) where kind = 'monthly' do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from inf.scorecards where creator_id = v_creator and period = p ->> 'period' and kind = 'monthly';
    return v_id;
  end if;
  if v_kind = 'monthly' then
    insert into inf.creator_tier_state (creator_id, months_below) values (v_creator, coalesce((p ->> 'months_below')::int, 0))
    on conflict (creator_id) do update set months_below = excluded.months_below, updated_at = now(),
      manual_tier_id = case when inf.creator_tier_state.manual_until < inf.ist_date(now()) then null else inf.creator_tier_state.manual_tier_id end,
      manual_reason = case when inf.creator_tier_state.manual_until < inf.ist_date(now()) then null else inf.creator_tier_state.manual_reason end,
      manual_until = case when inf.creator_tier_state.manual_until < inf.ist_date(now()) then null else inf.creator_tier_state.manual_until end;
    if v_after is distinct from v_before and v_change in ('up', 'down') then
      update inf.creators set tier_id = v_after where id = v_creator;
      insert into inf.tier_history (creator_id, from_tier, to_tier, reason, scorecard_id)
      values (v_creator, v_before, v_after, case v_change when 'up' then 'eligible' else 'below_rules' end, v_id);
      select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = v_creator;
      select name into v_name from inf.tiers where id = v_after;
      if v_user is not null then
        perform inf.notify(v_user, 'tier.changed',
                           case when v_after is null then 'Your tier has ended'
                                when v_change = 'up' then 'You reached ' || v_name
                                else 'Your tier is now ' || v_name end,
                           'See your tier, its benefits and what the next one needs on your home page.', '/creator',
                           jsonb_build_object('tier', coalesce(v_name, '')), false, 'tier_changed:' || v_id);
      end if;
    end if;
  end if;
  return v_id;
end $$;

-- Creators due a monthly scorecard (service role): approved and not blocked, without a card for the period.
create or replace function inf.scorecards_due(p_period text) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select c.id from inf.creators c
   where coalesce(auth.role(), '') = 'service_role'
     and c.status = 'active' and not c.is_blocked and not c.is_test and c.approved_at is not null
     and not exists (select 1 from inf.scorecards s where s.creator_id = c.id and s.kind = 'monthly' and s.period = p_period)
   order by c.id
$$;

-- A manual tier (staff with tier.manage), holding until a date; null tier = no tier.
create or replace function inf.tier_set_manual(p_creator uuid, p_tier uuid, p_until date, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_before uuid;
begin
  if not inf.has_perm('tier.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'say why' using errcode = '22023'; end if;
  if p_until is null or p_until < inf.ist_date(now()) then raise exception 'choose an end date in the future' using errcode = '22023'; end if;
  if p_tier is not null and not exists (select 1 from inf.tiers t where t.id = p_tier and t.active) then
    raise exception 'no such tier' using errcode = '22023';
  end if;
  select tier_id into v_before from inf.creators where id = p_creator for update;
  if not found then raise exception 'no such creator' using errcode = '22023'; end if;
  insert into inf.creator_tier_state (creator_id, months_below, manual_tier_id, manual_until, manual_reason, updated_by)
  values (p_creator, 0, p_tier, p_until, trim(p_reason), auth.uid())
  on conflict (creator_id) do update set months_below = 0, manual_tier_id = excluded.manual_tier_id, manual_until = excluded.manual_until,
    manual_reason = excluded.manual_reason, updated_by = excluded.updated_by, updated_at = now();
  update inf.creators set tier_id = p_tier where id = p_creator;
  insert into inf.tier_history (creator_id, from_tier, to_tier, reason, note, created_by)
  values (p_creator, v_before, p_tier, 'manual', trim(p_reason), auth.uid());
end $$;

create or replace function inf.tier_clear_manual(p_creator uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('tier.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.creator_tier_state set manual_tier_id = null, manual_until = null, manual_reason = null, updated_by = auth.uid(), updated_at = now()
   where creator_id = p_creator and manual_until is not null;
  if found then
    insert into inf.tier_history (creator_id, from_tier, to_tier, reason, created_by)
    select p_creator, c.tier_id, c.tier_id, 'manual_ended', auth.uid() from inf.creators c where c.id = p_creator;
  end if;
end $$;

-- A creator's scorecards, tier history and state (staff with creator.read).
create or replace function inf.creator_scorecards(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'cards', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'kind', s.kind, 'period', s.period, 'period_from', s.period_from,
                                                           'period_to', s.period_to, 'scores', s.scores, 'figures', s.figures,
                                                           'composite', s.composite, 'facts', s.facts, 'created_at', s.created_at,
                                                           'tier_before', s.tier_before, 'tier_after', s.tier_after)
                                         order by s.period desc, s.created_at desc)
                         from (select * from inf.scorecards x where x.creator_id = p_creator order by x.period desc, x.created_at desc limit 24) s), '[]'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'from_tier', ft.name, 'to_tier', tt.name, 'reason', h.reason,
                                                             'note', h.note, 'created_at', h.created_at,
                                                             'by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = h.created_by))
                                           order by h.created_at desc)
                           from inf.tier_history h left join inf.tiers ft on ft.id = h.from_tier left join inf.tiers tt on tt.id = h.to_tier
                          where h.creator_id = p_creator), '[]'),
    'tier_id', (select c.tier_id from inf.creators c where c.id = p_creator),
    'state', (select jsonb_build_object('months_below', s.months_below, 'manual_tier_id', s.manual_tier_id, 'manual_until', s.manual_until,
                                        'manual_reason', s.manual_reason)
                from inf.creator_tier_state s where s.creator_id = p_creator))
   where inf.has_perm('creator.read')
$$;

-- The creator's own tier, benefits and progress facts (the creator, their agency with view, staff with creator.read).
-- Never the sub-scores (economics would reveal revenue).
create or replace function inf.tier_status(p_creator uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_card inf.scorecards;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'view') or inf.has_perm('creator.read')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into v_card from inf.scorecards s where s.creator_id = p_creator and s.kind = 'monthly' order by s.period desc limit 1;
  return jsonb_build_object(
    'tier_id', (select c.tier_id from inf.creators c where c.id = p_creator),
    'score', v_card.composite,
    'compliance', v_card.scores -> 'compliance',
    'period', v_card.period,
    'enrollments_90d', (select count(*) from inf.an_leads_live l where l.creator_id = p_creator and not l.is_test and l.credited
                          and l.enrolled and l.day > inf.ist_date(now()) - 90),
    'months_active', (select coalesce((extract(year from age(inf.ist_date(now()), inf.ist_date(c.approved_at))) * 12
                                       + extract(month from age(inf.ist_date(now()), inf.ist_date(c.approved_at))))::int, 0)
                        from inf.creators c where c.id = p_creator),
    'manual_until', (select s.manual_until from inf.creator_tier_state s where s.creator_id = p_creator),
    'tiers', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'rank', t.rank, 'rules', t.entry_rules,
                                                           'benefits', t.benefits) order by t.rank)
                         from inf.tiers t where t.active), '[]'));
end $$;

-- The programme's latest monthly scorecards (staff with creator.read), best first.
create or replace function inf.programme_scorecards(p_period text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('creator_id', c.id, 'display_name', c.display_name, 'handle', c.handle,
                                               'tier', t.name, 'composite', s.composite, 'scores', s.scores, 'period', s.period,
                                               'changed', s.tier_before is distinct from s.tier_after)
                            order by s.composite desc nulls last, c.display_name), '[]')
    from inf.scorecards s join inf.creators c on c.id = s.creator_id left join inf.tiers t on t.id = c.tier_id
   where inf.has_perm('creator.read') and s.kind = 'monthly' and s.period = p_period
$$;

-- Periods that have monthly scorecards, newest first (staff).
create or replace function inf.scorecard_periods() returns setof text
language sql stable security definer set search_path = '' as $$
  select distinct s.period from inf.scorecards s where inf.has_perm('creator.read') and s.kind = 'monthly' order by 1 desc limit 36
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Contract compliance tracker: per-deliverable facts for lib/compliance/obligations.ts
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.compliance_facts(p_creator uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_first_h int; v_grace_h int;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'deliverables')
          or inf.has_perm('creator.read') or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce((select min((x)::int) from jsonb_array_elements_text(inf.setting('content.review') -> 'metric_checkpoints_hours') x), 24),
         coalesce((inf.setting('content.schedule') ->> 'metrics_grace_hours')::int, 48)
    into v_first_h, v_grace_h;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id, 'title', x.title, 'deal_id', x.deal_id, 'deal_title', d.title, 'status', x.status,
             'due_live', (x.due_dates ->> 'live')::timestamptz, 'live_at', x.live_at, 'cancelled_at', x.cancelled_at,
             'disclosure_failed_at', x.disclosure_failed_at,
             'disclosure_ok', (select pp.disclosure_ok from inf.published_posts pp where pp.deliverable_id = x.id
                                  and pp.verification_status = 'verified' order by pp.verified_at desc limit 1),
             'metrics_submitted_at', (select min(m.captured_at) from inf.post_metric_snapshots m where m.deliverable_id = x.id),
             'metrics_due_days', ceil((v_first_h + v_grace_h) / 24.0)::int,
             'brief_acknowledged_at', (select min(a.acknowledged_at) from inf.brief_acknowledgements a where a.brief_id = x.brief_id),
             'first_submission_at', (select min(s.created_at) from inf.deliverable_submissions s where s.deliverable_id = x.id))
           order by (x.due_dates ->> 'live') nulls last, x.code)
      from inf.deliverables x join inf.deals d on d.id = x.deal_id
     where d.creator_id = p_creator and d.status <> 'draft'), '[]');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Consent records for communications (DPDP): every change a person makes to what they receive is recorded, append-only
-- ---------------------------------------------------------------------------------------------------------------
create table inf.communication_consents (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  purpose     text not null check (purpose ~ '^[a-z_]+(\.[a-z_]+)?$' or purpose = 'digest'),
  channel     text not null check (channel in ('email', 'whatsapp')),
  granted     boolean not null,
  detail      text check (char_length(detail) <= 100),
  created_at  timestamptz not null default now()
);
create index communication_consents_user_idx on inf.communication_consents (user_id, created_at desc);
create trigger communication_consents_append_only before update or delete on inf.communication_consents
  for each row execute function inf.forbid_mutation();

create or replace function inf.consent_from_preference() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.enabled is not distinct from new.enabled then return null; end if;
  if new.channel in ('email', 'whatsapp') then
    insert into inf.communication_consents (user_id, purpose, channel, granted) values (new.user_id, new.event, new.channel, new.enabled);
  end if;
  return null;
end $$;
create trigger notification_preferences_consent after insert or update on inf.notification_preferences
  for each row execute function inf.consent_from_preference();

create or replace function inf.consent_from_digest() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.frequency is not distinct from new.frequency and old.channel is not distinct from new.channel then return null; end if;
  insert into inf.communication_consents (user_id, purpose, channel, granted, detail)
  values (new.user_id, 'digest', new.channel, new.frequency <> 'off', new.frequency);
  return null;
end $$;
create trigger digest_preferences_consent after insert or update on inf.digest_preferences
  for each row execute function inf.consent_from_digest();

create or replace function inf.my_consents() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('purpose', c.purpose, 'channel', c.channel, 'granted', c.granted, 'detail', c.detail,
                                               'created_at', c.created_at) order by c.created_at desc), '[]')
    from (select * from inf.communication_consents x where x.user_id = auth.uid() order by x.created_at desc limit 200) c
   where inf.session_ok()
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Data export and deletion requests (DPDP)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.privacy_requests (
  id             uuid primary key default gen_random_uuid(),
  creator_id     uuid not null references inf.creators (id) on delete cascade,
  kind           text not null check (kind in ('export', 'deletion')),
  status         text not null default 'requested'
                   check (status in ('requested', 'ready', 'completed', 'rejected', 'expired', 'purged')),
  reason         text check (char_length(reason) <= 1000),
  requested_by   uuid not null default auth.uid(),
  requested_at   timestamptz not null default now(),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text check (char_length(decision_note) <= 1000),
  -- Exports are built on each download (never stored) while the request is ready, for 7 days.
  file_expires_at timestamptz,
  plan           jsonb,
  purge_on       date,
  updated_at     timestamptz not null default now()
);
create unique index privacy_requests_open_uq on inf.privacy_requests (creator_id, kind) where status in ('requested', 'ready') and kind = 'deletion';
create index privacy_requests_status_idx on inf.privacy_requests (status, requested_at);
create trigger privacy_requests_touch before update on inf.privacy_requests for each row execute function inf.touch_updated_at();
create trigger privacy_requests_audit after insert or update on inf.privacy_requests
  for each row execute function inf.audit_row('privacy_request');

-- The creator asks for an export (ready at once, downloadable for 7 days, at most one a day) or for deletion (decided
-- by staff with privacy.manage).
create or replace function inf.privacy_request_create(p_kind text, p_reason text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_creator uuid := inf.current_creator_id(); v_id uuid;
begin
  if v_creator is null or not inf.session_ok() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind not in ('export', 'deletion') then raise exception 'invalid request' using errcode = '22023'; end if;
  if p_kind = 'export' and exists (select 1 from inf.privacy_requests r where r.creator_id = v_creator and r.kind = 'export'
                                    and r.requested_at > now() - interval '1 day') then
    raise exception 'one export a day' using errcode = '22023';
  end if;
  insert into inf.privacy_requests (creator_id, kind, reason, status, file_expires_at, decided_at)
  values (v_creator, p_kind, left(nullif(trim(p_reason), ''), 1000), case p_kind when 'export' then 'ready' else 'requested' end,
          case p_kind when 'export' then now() + interval '7 days' end, case p_kind when 'export' then now() end)
  returning id into v_id;
  if p_kind = 'export' then
    perform inf.notify(auth.uid(), 'privacy.export_ready', 'Your data export is ready',
                       'Download it from Account → Privacy within 7 days.', '/creator/account/privacy', jsonb_build_object('request_id', v_id),
                       true, 'privacy_export_ready:' || v_id);
  else
    perform inf.notify(sp.user_id, 'staff.privacy_request', 'Deletion request: ' || c.display_name,
                       'Review it in Privacy requests.', '/admin/privacy', jsonb_build_object('request_id', v_id), false,
                       'privacy_request:' || v_id || ':' || sp.user_id)
      from inf.staff_profiles sp, inf.creators c
     where c.id = v_creator and sp.status = 'active'
       and exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                    where g.user_id = sp.user_id and rp.permission = 'privacy.manage');
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'a deletion request is already open' using errcode = '22023';
end $$;

create or replace function inf.my_privacy_requests() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'status', r.status, 'requested_at', r.requested_at,
                                               'decided_at', r.decided_at, 'decision_note', r.decision_note,
                                               'file_ready', r.kind = 'export' and r.status = 'ready' and r.file_expires_at > now(),
                                               'file_expires_at', r.file_expires_at, 'purge_on', r.purge_on)
                            order by r.requested_at desc), '[]')
    from inf.privacy_requests r
   where r.creator_id = inf.current_creator_id() and inf.session_ok()
$$;

-- Everything the export contains, by section (service role, for the download route after inf.privacy_export_allowed). Contact details of students are never in it:
-- leads come from the masked creator feed.
create or replace function inf.privacy_export_data(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r inf.privacy_requests; c uuid; v_user uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into r from inf.privacy_requests where id = p_request and kind = 'export';
  if r.id is null then return null; end if;
  c := r.creator_id;
  select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = c;
  return jsonb_build_object(
    'creator_id', c,
    'generated_at', now(),
    'profile', (select to_jsonb(x) - 'internal_notes' - 'owner_id' - 'created_by' - 'approved_by' - 'blocked_reason' - 'tags'
                                   - 'pipeline_stage' - 'source' from inf.creators x where x.id = c),
    'platforms', coalesce((select jsonb_agg(to_jsonb(p)) from inf.creator_platforms p where p.creator_id = c), '[]'),
    'agency_links', coalesce((select jsonb_agg(jsonb_build_object('agency', a.name, 'status', l.status, 'can_view', l.can_view,
                                                                  'can_act_deliverables', l.can_act_deliverables,
                                                                  'can_negotiate_sign', l.can_negotiate_sign,
                                                                  'can_view_earnings', l.can_view_earnings, 'requested_at', l.requested_at))
                               from inf.agency_creator_links l join inf.agencies a on a.id = l.agency_id where l.creator_id = c), '[]'),
    'consents', coalesce((select jsonb_agg(to_jsonb(k) - 'user_id') from inf.communication_consents k where k.user_id = v_user), '[]'),
    'terms', coalesce((select jsonb_agg(jsonb_build_object('title', v.title, 'version', v.version, 'accepted_at', t.accepted_at))
                         from inf.terms_acceptances t join inf.terms_versions v on v.id = t.terms_version_id where t.user_id = v_user), '[]'),
    'applications', coalesce((select jsonb_agg(jsonb_build_object('campaign', cp.name, 'status', a.status, 'pitch', a.pitch,
                                                                  'created_at', a.created_at))
                               from inf.campaign_applications a join inf.campaigns cp on cp.id = a.campaign_id where a.creator_id = c), '[]'),
    'deals', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'status', d.status, 'starts_on', d.starts_on,
                                                           'ends_on', d.ends_on)) from inf.deals d where d.creator_id = c and d.status <> 'draft'), '[]'),
    'contracts', coalesce((select jsonb_agg(jsonb_build_object('number', k.number, 'status', k.status, 'created_at', k.created_at))
                            from inf.contracts k join inf.deals d on d.id = k.deal_id where d.creator_id = c), '[]'),
    'deliverables', coalesce((select jsonb_agg(jsonb_build_object('title', x.title, 'platform', x.platform, 'format', x.format,
                                                                  'status', x.status, 'live_at', x.live_at))
                               from inf.deliverables x join inf.deals d on d.id = x.deal_id where d.creator_id = c), '[]'),
    'links', coalesce((select jsonb_agg(jsonb_build_object('code', l.code, 'platform', l.platform, 'created_at', l.created_at))
                        from inf.tracking_links l where l.creator_id = c), '[]'),
    'leads', coalesce((select jsonb_agg(jsonb_build_object('lead_ref', f.lead_ref, 'stage', f.creator_stage, 'status', f.attribution_status,
                                                           'enquired_on', f.lead_at))
                        from inf.creator_lead_feed f where f.creator_id = c), '[]'),
    'earnings', coalesce((select jsonb_agg(jsonb_build_object('type', e.type, 'direction', e.direction, 'amount_paise', e.amount_paise,
                                                              'status', e.status, 'posted_at', e.posted_at, 'note', e.note)
                                           order by e.posted_at)
                           from inf.ledger_entries e where e.creator_id = c), '[]'),
    'payouts', coalesce((select jsonb_agg(jsonb_build_object('ref', p.ref, 'gross_paise', p.gross_paise, 'tds_paise', p.tds_paise,
                                                             'gst_paise', p.gst_paise, 'net_paise', p.net_paise, 'status', p.status,
                                                             'utr', p.utr, 'paid_on', p.paid_on))
                          from inf.payouts p where p.creator_id = c), '[]'),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('thread', t.entity_type, 'side', m.author_side, 'body', m.body,
                                                              'created_at', m.created_at) order by m.created_at)
                           from inf.messages m join inf.threads t on t.id = m.thread_id
                          where t.creator_id = c and not t.staff_only), '[]'),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('event', n.event, 'title', n.title, 'created_at', n.created_at)
                                                order by n.created_at)
                                from inf.notifications n where n.user_id = v_user), '[]'));
end $$;

-- Whether the caller may download an export (the creator who asked, while it is ready).
create or replace function inf.privacy_export_allowed(p_request uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from inf.privacy_requests r
                  where r.id = p_request and r.kind = 'export' and r.creator_id = inf.current_creator_id() and r.status = 'ready'
                    and r.file_expires_at > now() and inf.session_ok())
$$;

-- What a deletion would do now (staff with privacy.manage): the facts for lib/privacy/plan.ts.
create or replace function inf.privacy_deletion_facts(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r inf.privacy_requests;
begin
  if not inf.has_perm('privacy.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into r from inf.privacy_requests where id = p_request and kind = 'deletion';
  if r.id is null then raise exception 'no such request' using errcode = '22023'; end if;
  return jsonb_build_object(
    'last_record_on', greatest(
      (select max(inf.ist_date(e.posted_at)) from inf.ledger_entries e where e.creator_id = r.creator_id),
      (select max(p.paid_on) from inf.payouts p where p.creator_id = r.creator_id),
      (select max(inf.ist_date(k.updated_at)) from inf.contracts k join inf.deals d on d.id = k.deal_id
        where d.creator_id = r.creator_id and k.status in ('active', 'completed', 'terminated', 'expired'))),
    'open_deals', (select count(*) from inf.deals d where d.creator_id = r.creator_id and d.status in ('proposed', 'negotiating', 'agreed', 'active')),
    'balance_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                               else -(e.confirmed_paise - e.paid_paise) end), 0)
                        from inf.ledger_entries e where e.creator_id = r.creator_id and e.status in ('payable', 'in_batch', 'confirmed')),
    'retention_years', coalesce((inf.setting('retention.privacy') ->> 'financial_records_years')::int, 8),
    'today', inf.ist_date(now()));
end $$;

-- Messages are append-only; erasure may blank the creator's own message text inside a privacy erasure only.
create or replace function inf.messages_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and current_setting('inf.privacy_erase', true) = 'on'
     and new.thread_id = old.thread_id and new.author_id = old.author_id and new.author_side = old.author_side
     and new.created_at = old.created_at then
    return new;
  end if;
  raise exception 'inf.messages: rows are append-only (% refused)', lower(tg_op) using errcode = 'insufficient_privilege';
end $$;
drop trigger messages_append_only on inf.messages;
create trigger messages_append_only before update or delete on inf.messages for each row execute function inf.messages_guard();

-- Carries out a deletion request (staff with privacy.manage) after the screen showed its plan: erases the profile,
-- platforms, media kit, preferences and the creator's message text, blocks the account and ends its sessions; keeps
-- financial and contract records (with the KYC they need) until purge_on, when the nightly job purges the KYC. The
-- server action then removes the sign-in account.
create or replace function inf.privacy_deletion_decide(p_request uuid, p_approve boolean, p_note text, p_purge_on date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare r inf.privacy_requests; v_user uuid; f jsonb;
begin
  if not inf.has_perm('privacy.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into r from inf.privacy_requests where id = p_request and kind = 'deletion' for update;
  if r.id is null or r.status <> 'requested' then raise exception 'this request is already decided' using errcode = '22023'; end if;
  if coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'say why' using errcode = '22023'; end if;
  select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = r.creator_id;
  if not p_approve then
    update inf.privacy_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = trim(p_note) where id = r.id;
  else
    f := inf.privacy_deletion_facts(p_request);
    if (f ->> 'open_deals')::int > 0 then raise exception 'the creator still has open deals' using errcode = '22023'; end if;
    if (f ->> 'balance_paise')::bigint <> 0 then raise exception 'money is still owed' using errcode = '22023'; end if;
    perform set_config('inf.privacy_erase', 'on', true);
    update inf.messages m set body = '[removed at the creator''s request]'
      from inf.threads t where t.id = m.thread_id and t.creator_id = r.creator_id and m.author_side = 'creator';
    perform set_config('inf.privacy_erase', 'off', true);
    delete from inf.creator_platforms where creator_id = r.creator_id;
    delete from inf.notification_preferences where user_id = v_user;
    delete from inf.digest_preferences where user_id = v_user;
    update inf.creators set legal_name = null, display_name = 'Deleted creator', handle = 'deleted.' || left(replace(id::text, '-', ''), 12),
           email = null, phone_e164 = null, city = null, state = null, bio = null, avatar_path = null, niches = '{}', languages = '{}',
           public_page_enabled = false, leaderboard_opt_in = false, status = 'archived', is_blocked = true,
           blocked_reason = 'Deleted at the creator''s request'
     where id = r.creator_id;
    update inf.user_sessions set revoked_at = now(), revoke_reason = 'deleted' where user_id = v_user and revoked_at is null;
    update inf.privacy_requests set status = 'completed', decided_by = auth.uid(), decided_at = now(), decision_note = trim(p_note),
           plan = f, purge_on = p_purge_on
     where id = r.id;
  end if;
  if v_user is not null then
    perform inf.notify(v_user, 'privacy.request_update',
                       case when p_approve then 'Your account has been deleted' else 'Your deletion request was not carried out' end,
                       case when p_approve then 'Financial and contract records are kept as the law requires, then removed.'
                            else trim(p_note) end, null, jsonb_build_object('request_id', r.id), true, 'privacy_decided:' || r.id);
  end if;
  return v_user;
end $$;

create or replace function inf.privacy_requests_list(p_status text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'status', r.status, 'reason', r.reason,
                                               'requested_at', r.requested_at, 'decided_at', r.decided_at, 'decision_note', r.decision_note,
                                               'purge_on', r.purge_on, 'creator_id', r.creator_id, 'creator', c.display_name,
                                               'handle', c.handle,
                                               'decided_by', (select sp.full_name from inf.staff_profiles sp where sp.user_id = r.decided_by))
                            order by r.requested_at desc), '[]')
    from inf.privacy_requests r join inf.creators c on c.id = r.creator_id
   where inf.has_perm('privacy.manage') and (p_status is null or r.status = p_status)
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Retention (setting retention.privacy), run nightly
-- ---------------------------------------------------------------------------------------------------------------
-- The audit and sign-in logs are append-only; only the retention run (transaction flag inf.retention_purge) may delete
-- rows older than their retention period.
create or replace function inf.retention_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' and current_setting('inf.retention_purge', true) = 'on' then return old; end if;
  raise exception 'inf.%: rows are append-only (% refused)', tg_table_name, lower(tg_op) using errcode = 'insufficient_privilege';
end $$;
drop trigger audit_log_append_only on inf.audit_log;
create trigger audit_log_append_only before update or delete on inf.audit_log for each row execute function inf.retention_guard();
drop trigger sign_in_log_append_only on inf.sign_in_log;
create trigger sign_in_log_append_only before update or delete on inf.sign_in_log for each row execute function inf.retention_guard();

create or replace function inf.retention_run() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s jsonb := inf.setting('retention.privacy'); v_clicks int; v_signins int; v_audit int; v_kyc int; v_exports int;
begin
  update inf.link_clicks set ip_hash = null, user_agent = null, referrer = null
   where clicked_at < now() - make_interval(days => coalesce((s ->> 'click_anonymise_days')::int, 90))
     and (ip_hash is not null or user_agent is not null or referrer is not null);
  get diagnostics v_clicks = row_count;
  perform set_config('inf.retention_purge', 'on', true);
  delete from inf.sign_in_log where at < now() - make_interval(days => coalesce((s ->> 'sign_in_log_days')::int, 365));
  get diagnostics v_signins = row_count;
  delete from inf.audit_log where at < now() - make_interval(years => greatest(coalesce((s ->> 'audit_log_years')::int, 8), 1));
  get diagnostics v_audit = row_count;
  perform set_config('inf.retention_purge', 'off', true);
  -- Deleted creators: KYC kept for the retention period goes when it ends.
  with due as (update inf.privacy_requests set status = 'purged'
                where kind = 'deletion' and status = 'completed' and purge_on <= inf.ist_date(now()) returning creator_id)
  delete from inf.creator_kyc k using due where k.creator_id = due.creator_id;
  get diagnostics v_kyc = row_count;
  update inf.privacy_requests set status = 'expired' where kind = 'export' and status = 'ready' and file_expires_at <= now();
  get diagnostics v_exports = row_count;
  return jsonb_build_object('clicks_anonymised', v_clicks, 'sign_ins_deleted', v_signins, 'audit_deleted', v_audit,
                            'kyc_purged', v_kyc, 'exports_expired', v_exports);
end $$;

create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.contract_sign_codes where created_at < now() - interval '30 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
  perform inf.creators_flag_dormant();
  perform inf.deals_expire();
  perform inf.contracts_remind();
  perform inf.content_remind();
  perform inf.ledger_nightly();
  perform inf.retention_run();
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Phase 9 follow-up: digest defaults and hour from notifications.delivery
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.digest_recipients(p_today date) returns table (user_id uuid, kind text, frequency text, channel text, creator_id uuid)
language sql stable security definer set search_path = '' as $$
  with s as (select inf.setting('notifications.delivery') as v),
  people as (
    select ca.user_id, 'creator' as kind, ca.creator_id from inf.creator_accounts ca join inf.creators c on c.id = ca.creator_id
     where c.status = 'active' and not c.is_blocked
    union all
    select sp.user_id, 'staff', null from inf.staff_profiles sp where sp.status = 'active'),
  chosen as (
    select p.user_id, p.kind, p.creator_id, coalesce(d.channel, 'email') as channel,
           coalesce(d.frequency, case p.kind when 'creator' then coalesce(s.v ->> 'creator_digest', 'weekly')
                                             else coalesce(s.v ->> 'staff_digest', 'off') end) as frequency
      from people p cross join s left join inf.digest_preferences d on d.user_id = p.user_id)
  select c.user_id, c.kind, c.frequency, c.channel, c.creator_id from chosen c
   where coalesce(auth.role(), '') = 'service_role'
     and (c.frequency = 'daily' or (c.frequency = 'weekly' and extract(isodow from p_today) = 1))
$$;

create or replace function inf.digests_enqueue() returns void
language plpgsql security definer set search_path = '' as $$
declare v_hour int := coalesce((inf.setting('notifications.delivery') ->> 'digest_hour_ist')::int, 8);
begin
  if extract(hour from now() at time zone 'Asia/Kolkata')::int = v_hour then
    perform inf.job_enqueue('digest.run', jsonb_build_object('date', inf.ist_date(now())), now(), 'digest:' || inf.ist_date(now()));
  end if;
end $$;

-- Scorecards: the monthly job runs on the 1st at 06:00 IST for the month just ended.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('inf-digests') where exists (select 1 from cron.job where jobname = 'inf-digests');
    perform cron.schedule('inf-digests', '30 * * * *', $c$select inf.digests_enqueue()$c$);
    perform cron.schedule('inf-scorecards', '30 0 1 * *',
      $c$select inf.job_enqueue('scorecards.run', jsonb_build_object('period', to_char(inf.ist_date(now()) - 1, 'YYYY-MM')), now(),
                                'scorecards:' || to_char(inf.ist_date(now()) - 1, 'YYYY-MM'))$c$);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS and grants (tables are read through the functions above)
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.scorecards enable row level security;
alter table inf.creator_tier_state enable row level security;
alter table inf.tier_history enable row level security;
alter table inf.communication_consents enable row level security;
alter table inf.privacy_requests enable row level security;

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.tier_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.tiers_list()', 'authenticated', 'execute'),
  ('function', 'inf.scorecard_facts(uuid, date, date)', 'authenticated', 'execute'),
  ('function', 'inf.scorecard_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.tier_set_manual(uuid, uuid, date, text)', 'authenticated', 'execute'),
  ('function', 'inf.tier_clear_manual(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creator_scorecards(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.tier_status(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.programme_scorecards(text)', 'authenticated', 'execute'),
  ('function', 'inf.scorecard_periods()', 'authenticated', 'execute'),
  ('function', 'inf.compliance_facts(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.my_consents()', 'authenticated', 'execute'),
  ('function', 'inf.privacy_request_create(text, text)', 'authenticated', 'execute'),
  ('function', 'inf.my_privacy_requests()', 'authenticated', 'execute'),
  ('function', 'inf.privacy_export_allowed(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.privacy_deletion_facts(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.privacy_deletion_decide(uuid, boolean, text, date)', 'authenticated', 'execute'),
  ('function', 'inf.privacy_requests_list(text)', 'authenticated', 'execute');
call inf.apply_client_grants();
