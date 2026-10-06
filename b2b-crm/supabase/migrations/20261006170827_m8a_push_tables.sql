-- M8a: partner push (spec B7.5, B8.1, B8.2): the allocation state machine, push bookkeeping, partner events,
-- commission disputes and partner credentials in Vault. The HTTP work runs in Postgres (pg_net + pg_cron, m8b),
-- so no worker, service key or paid infrastructure is needed (design D14).

-- ---------- allocations: push bookkeeping ----------
alter table b2b.allocations
  add column if not exists programme_id      bigint,
  add column if not exists push_attempts     int not null default 0,
  add column if not exists next_push_at      timestamptz,
  add column if not exists push_request_id   bigint,
  add column if not exists pushed_at         timestamptz,
  add column if not exists last_error        text,
  add column if not exists returning_lead    boolean not null default false,
  add column if not exists spot_check        boolean not null default false,
  add column if not exists claim_proof       jsonb;
create index if not exists allocations_push_due_idx on b2b.allocations (next_push_at) where status in ('queued', 'pushing');
create index if not exists allocations_hold_idx on b2b.allocations (hold_until) where status = 'pushed';

-- ---------- state machine: every writer goes through these rules (B7.5) ----------
create table if not exists b2b.allocation_transitions (
  id             bigint generated always as identity primary key,
  allocation_id  bigint not null references b2b.allocations (id) on delete restrict,
  from_status    text,
  to_status      text not null,
  actor_type     text,
  actor_id       text,
  at             timestamptz not null default now()
);
create index if not exists allocation_transitions_alloc_idx on b2b.allocation_transitions (allocation_id, at);

create or replace function b2b.allocation_status_guard()
returns trigger language plpgsql set search_path = '' as $$
declare
  ok boolean;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    ok := case old.status
      when 'queued'     then new.status in ('pushing', 'failed', 'recalled', 'closed')
      when 'pushing'    then new.status in ('pushed', 'accepted', 'duplicate', 'rejected', 'failed', 'recalled', 'closed')
      when 'pushed'     then new.status in ('accepted', 'duplicate', 'rejected', 'recalled', 'closed')
      when 'accepted'   then new.status in ('closed', 'recalled')
      when 'handed_off' then new.status in ('closed')
      else false end;
    if not ok then
      raise exception 'allocation % cannot move from % to %', old.id, old.status, new.status using errcode = '22023';
    end if;
    new.updated_at := now();
  end if;
  return new;
end $$;

create or replace function b2b.allocation_status_log()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into b2b.allocation_transitions (allocation_id, from_status, to_status, actor_type, actor_id)
    select new.id, case when tg_op = 'UPDATE' then old.status end, new.status, a ->> 'type', a ->> 'id' from (select b2b.actor() a) x;
  end if;
  return null;
end $$;

create or replace trigger allocation_status_guard before update of status on b2b.allocations
  for each row execute function b2b.allocation_status_guard();
create or replace trigger allocation_status_log after insert or update of status on b2b.allocations
  for each row execute function b2b.allocation_status_log();

-- ---------- push requests: one row per HTTP call, for audit and debugging ----------
create table if not exists b2b.push_requests (
  id             bigint generated always as identity primary key,
  allocation_id  bigint not null references b2b.allocations (id) on delete restrict,
  attempt        int not null,
  net_request_id bigint,
  url            text not null,
  sandbox        boolean not null default false,
  status_code    int,
  response       text,
  outcome        text check (outcome in ('created', 'duplicate', 'rejected', 'error', 'timeout')),
  error          text,
  sent_at        timestamptz not null default now(),
  completed_at   timestamptz
);
create index if not exists push_requests_alloc_idx on b2b.push_requests (allocation_id, sent_at desc);

-- ---------- partner events: stored raw before anything is applied (B8.2) ----------
create table if not exists b2b.partner_events (
  id             bigint generated always as identity primary key,
  partner_id     bigint not null references b2b.partners (id) on delete restrict,
  event_id       text not null,
  event_type     text not null,
  reference      text,
  record_id      text,
  allocation_id  bigint references b2b.allocations (id) on delete restrict,
  lead_id        bigint,
  raw            jsonb not null,
  status         text not null default 'received' check (status in ('received', 'applied', 'ignored', 'held_unmapped', 'error')),
  result         text,
  received_at    timestamptz not null default now(),
  applied_at     timestamptz,
  unique (partner_id, event_id)
);
create index if not exists partner_events_alloc_idx on b2b.partner_events (allocation_id, received_at);

-- ---------- commission disputes: duplicate claims after acceptance (B7.5) ----------
create table if not exists b2b.commission_disputes (
  id                  bigint generated always as identity primary key,
  allocation_id       bigint not null references b2b.allocations (id) on delete restrict,
  lead_id             bigint not null,
  partner_id          bigint not null references b2b.partners (id) on delete restrict,
  existing_record_id  text,
  existing_created_at text,
  proof               jsonb not null default '{}',
  status              text not null default 'open' check (status in ('open', 'upheld', 'rejected')),
  note                text,
  created_at          timestamptz not null default now(),
  resolved_at         timestamptz,
  resolved_by         text
);
create unique index if not exists commission_disputes_one_open on b2b.commission_disputes (allocation_id) where status = 'open';

do $rls$
declare t text;
begin
  foreach t in array array['allocation_transitions', 'push_requests', 'partner_events', 'commission_disputes'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- Push defaults (engine settings): retry schedule (B7.5), HTTP timeout, duplicate spot-check share.
update b2b.settings
   set value = jsonb_build_object('push_retry_seconds', jsonb_build_array(10, 60, 300, 900, 3600), 'push_timeout_ms', 10000,
                                  'duplicate_spot_check', 0.05) || value
 where key = 'engine';

-- ---------- partner credentials (Vault): outbound token and inbound webhook secret ----------
/*
 * Outbound: how the B2B CRM authenticates to the partner. outbound_auth holds only the non-secret shape
 * ({type: bearer | header | basic | none, header?}); the token itself is a Vault secret.
 * Inbound: the HMAC secret partners sign their events with; generated here and shown to the Admin once.
 */
create or replace function b2b.partner_set_credentials(p_partner_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v b2b.partners;
  v_type text := coalesce(p ->> 'type', 'bearer');
  v_header text := nullif(trim(p ->> 'header'), '');
  v_token text := p ->> 'token';
  v_id uuid;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from b2b.partners where id = p_partner_id for update;
  if v.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if v_type not in ('bearer', 'header', 'basic', 'none') then raise exception 'unknown authentication type' using errcode = '22023'; end if;
  if v_type = 'header' and (v_header is null or v_header !~ '^[A-Za-z0-9-]{1,60}$') then raise exception 'give the header name (letters, digits, dashes)' using errcode = '22023'; end if;
  if v_type <> 'none' and v.outbound_secret_id is null and coalesce(v_token, '') = '' then raise exception 'the token is required' using errcode = '22023'; end if;
  if v_token is not null and length(v_token) > 4000 then raise exception 'the token is too long' using errcode = '22023'; end if;

  if coalesce(v_token, '') <> '' then
    if v.outbound_secret_id is null then
      v_id := vault.create_secret(v_token, 'b2b_partner_' || v.id || '_outbound', 'Outbound credential for partner ' || v.slug);
    else
      perform vault.update_secret(v.outbound_secret_id, v_token);
      v_id := v.outbound_secret_id;
    end if;
  else
    v_id := v.outbound_secret_id;
  end if;
  update b2b.partners set outbound_auth = jsonb_build_object('type', v_type, 'header', v_header),
         outbound_secret_id = v_id, updated_at = now(), updated_by = auth.uid()::text
   where id = v.id;
  perform b2b.log_event('partner.credentials_set', null, null, v.id, jsonb_build_object('type', v_type, 'token_changed', coalesce(v_token, '') <> ''));
  return jsonb_build_object('type', v_type, 'header', v_header, 'has_token', v_id is not null);
end $$;

/* A new inbound signing secret; the only time it is shown. Partners sign events with it (HMAC-SHA256). */
create or replace function b2b.partner_rotate_inbound_secret(p_partner_id bigint)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v b2b.partners;
  v_secret text := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from b2b.partners where id = p_partner_id for update;
  if v.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if v.inbound_secret_id is null then
    update b2b.partners set inbound_secret_id = vault.create_secret(v_secret, 'b2b_partner_' || v.id || '_inbound', 'Inbound event secret for partner ' || v.slug),
           updated_at = now() where id = v.id;
  else
    perform vault.update_secret(v.inbound_secret_id, v_secret);
  end if;
  perform b2b.log_event('partner.inbound_secret_rotated', null, null, v.id, '{}');
  return v_secret;
end $$;

/* Secret values for the push and event functions only (never granted to the Admin or the API). */
create or replace function b2b.partner_secret(p_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select s.decrypted_secret from vault.decrypted_secrets s where s.id = p_id;
$$;

revoke execute on function b2b.allocation_status_guard(), b2b.allocation_status_log(), b2b.partner_secret(uuid) from public, anon, authenticated;
grant execute on function b2b.partner_secret(uuid) to service_role;
revoke execute on function b2b.partner_set_credentials(bigint, jsonb), b2b.partner_rotate_inbound_secret(bigint) from public, anon;
grant execute on function b2b.partner_set_credentials(bigint, jsonb), b2b.partner_rotate_inbound_secret(bigint) to authenticated, service_role;
