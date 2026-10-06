-- M2 part c of 5 (see 20261006103851_m2a_extensions_and_schema.sql for the overview).

-- ---------- actor: who is acting (Admin user, or a named system component) ----------
-- System components set it per transaction: select set_config('b2b.actor', 'engine', true);
create or replace function b2b.actor()
returns jsonb language sql stable set search_path = '' as $$
  select case when auth.uid() is not null
              then jsonb_build_object('type', 'admin', 'id', auth.uid()::text)
              else jsonb_build_object('type', coalesce(nullif(current_setting('b2b.actor', true), ''), 'system'), 'id', null) end;
$$;

-- ---------- append-only event log (timelines, analytics, audit) ----------
create table if not exists b2b.events (
  id            bigint generated always as identity primary key,
  occurred_at   timestamptz not null default now(),
  type          text not null,
  lead_id       bigint,          -- no foreign key: the log keeps ids even after erasure or a test-lead purge
  allocation_id bigint,
  partner_id    bigint,
  actor_type    text not null,
  actor_id      text,
  payload       jsonb not null default '{}'
);
create index if not exists events_lead_idx on b2b.events (lead_id, occurred_at desc) where lead_id is not null;
create index if not exists events_type_idx on b2b.events (type, occurred_at desc);
create index if not exists events_at_idx on b2b.events (occurred_at desc);

create or replace function b2b.events_append_only()
returns trigger language plpgsql as $$
begin
  raise exception 'b2b.events is append-only (% blocked)', tg_op using errcode = '42501';
end $$;
create or replace trigger events_append_only before update or delete on b2b.events
  for each row execute function b2b.events_append_only();
create or replace trigger events_no_truncate before truncate on b2b.events
  for each statement execute function b2b.events_append_only();

create or replace function b2b.log_event(p_type text, p_lead bigint default null, p_allocation bigint default null,
                                         p_partner bigint default null, p_payload jsonb default '{}')
returns bigint language sql volatile security definer set search_path = '' as $$
  insert into b2b.events (type, lead_id, allocation_id, partner_id, actor_type, actor_id, payload)
  select p_type, p_lead, p_allocation, p_partner, a ->> 'type', a ->> 'id', coalesce(p_payload, '{}')
    from (select b2b.actor() a) x
  returning id;
$$;

-- ---------- versioned settings ----------
create table if not exists b2b.settings (
  key        text primary key,
  value      jsonb not null,
  version    int not null default 1,
  updated_at timestamptz not null default now(),
  actor_type text not null default 'system',
  actor_id   text
);

create table if not exists b2b.settings_versions (
  id         bigint generated always as identity primary key,
  key        text not null references b2b.settings (key),
  version    int not null,
  value      jsonb not null,
  reason     text,
  actor_type text not null,
  actor_id   text,
  ai_run_id  bigint,
  created_at timestamptz not null default now(),
  unique (key, version)
);

create or replace function b2b.set_setting(p_key text, p_value jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  a jsonb := b2b.actor();
  v int;
begin
  if a ->> 'type' = 'admin' and not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required for every settings change'; end if;
  insert into b2b.settings (key, value, actor_type, actor_id) values (p_key, p_value, a ->> 'type', a ->> 'id')
  on conflict (key) do update set value = excluded.value, version = b2b.settings.version + 1, updated_at = now(),
                                  actor_type = excluded.actor_type, actor_id = excluded.actor_id
  returning version into v;
  insert into b2b.settings_versions (key, version, value, reason, actor_type, actor_id)
  values (p_key, v, p_value, p_reason, a ->> 'type', a ->> 'id');
  perform b2b.log_event('settings.changed', null, null, null, jsonb_build_object('key', p_key, 'version', v, 'reason', p_reason));
  return jsonb_build_object('key', p_key, 'version', v);
end $$;

-- Defaults (B21 and the design doc). Seeded once; later changes go through b2b.set_setting().
do $seed$
declare
  s record;
begin
  for s in select * from (values
    ('engine', jsonb_build_object(
        'enabled', true, 'kill_switch', false, 'fixed_split', '{}'::jsonb,
        'exploration_share', 0.20, 'min_learning_leads', 30, 'share_cap', null,
        'maturity_days', 60, 'half_life_days', 30, 'prior_weight', 20, 'default_p_enroll', 0.05, 'min_matured_leads', 30,
        'require_partner_consent', true, 'attempt_limit', 2, 'partner_limit', 3, 'witty_idle_minutes', 30,
        'cpe_aggregate', 'median', 'returning_same_partner_days', 90,
        'speed_factor', jsonb_build_object('enabled', false, 'bounds', jsonb_build_array(0.85, 1.15)),
        'reliability_factor', jsonb_build_object('enabled', false, 'bounds', jsonb_build_array(0.7, 1.0)))),
    ('stages', '[
        {"key":"new","rank":10,"group":"before_routing"},
        {"key":"qualifying","rank":20,"group":"before_routing"},
        {"key":"allocated","rank":30,"group":"routing"},
        {"key":"sent_to_partner","rank":40,"group":"routing"},
        {"key":"contacted","rank":50,"group":"partner_pipeline"},
        {"key":"counselled","rank":60,"group":"partner_pipeline"},
        {"key":"applied","rank":70,"group":"partner_pipeline"},
        {"key":"enrolled","rank":80,"group":"partner_pipeline"},
        {"key":"verified","rank":90,"group":"money"},
        {"key":"commission_booked","rank":100,"group":"money"},
        {"key":"paid","rank":110,"group":"money"},
        {"key":"duplicate_at_partner","rank":45,"group":"exit"},
        {"key":"lost","rank":999,"group":"exit"}]'::jsonb),
    ('sub_stages', '{"contacted":["no answer","busy","switched off","call-back scheduled","connected, interested","connected, not now"],
                     "counselled":["considering","comparing options","parent to decide","documents pending"],
                     "applied":["application fee pending","documents submitted","under university review"],
                     "enrolled":["fee paid","seat confirmed"]}'::jsonb),
    ('lost_reasons', '["not reachable","not interested","not eligible","over budget","chose another provider","enrolled elsewhere","duplicate","junk or test","wrong number","cannot be served"]'::jsonb),
    ('money', '{"gst_rate":0.18,"refund_window_days":30,"sac_code":null,"tds_rate":null,"invoice_period":"monthly","confirmed_by_ca":false}'::jsonb),
    ('notifications', '{"timezone":"Asia/Kolkata","quiet_start":"08:00","quiet_end":"21:00","retry_after_minutes":5,"b2c_sends_own_notification":false,"support_contact":null}'::jsonb),
    ('sla_defaults', '{"first_attempt_working_hours":2,"first_connect_working_days":1,"status_update_days":7,"counselling_working_days":5,"enrollment_proof_days":7,"duplicate_window_hours":24,"hold_minutes_async":30}'::jsonb),
    ('security', '{"session_idle_hours":12,"lockout_attempts":5,"lockout_minutes":15,"require_totp_for_google":true,"min_password_length":12}'::jsonb),
    ('leads', '{"recycle_bin_days":30,"export_link_hours":24,"background_export_rows":10000,"admin_bulk_delete_confirm_rows":500}'::jsonb),
    ('test_phones', '{"digit_prefixes":["910000"],"digit_patterns":["9190000000__"]}'::jsonb)
  ) v(key, value) loop
    if not exists (select 1 from b2b.settings where key = s.key) then
      insert into b2b.settings (key, value) values (s.key, s.value);
      insert into b2b.settings_versions (key, version, value, reason, actor_type)
      values (s.key, 1, s.value, 'initial defaults (M2)', 'system');
    end if;
  end loop;
end $seed$;
