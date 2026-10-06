-- M2 part d of 5 (see 20261006103851_m2a_extensions_and_schema.sql for the overview).

-- ---------- API keys (intake, referrals, product webhooks, partners) ----------
create table if not exists b2b.api_keys (
  id           bigint generated always as identity primary key,
  name         text not null,
  scopes       text[] not null check (cardinality(scopes) > 0 and scopes <@ array['intake', 'referrals', 'events']::text[]),
  key_prefix   text not null,
  key_hash     text not null unique,     -- sha256 hex of the full key; the key itself is shown once and never stored
  created_at   timestamptz not null default now(),
  created_by   uuid,
  last_used_at timestamptz,
  revoked_at   timestamptz
);

create or replace function b2b.create_api_key(p_name text, p_scopes text[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_key text := 'eb2b_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_id  bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2b.api_keys (name, scopes, key_prefix, key_hash, created_by)
  values (p_name, p_scopes, left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), auth.uid())
  returning id into v_id;
  perform b2b.log_event('api_key.created', null, null, null, jsonb_build_object('api_key_id', v_id, 'name', p_name, 'scopes', p_scopes));
  return jsonb_build_object('id', v_id, 'key', v_key);   -- shown once
end $$;

create or replace function b2b.revoke_api_key(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.api_keys set revoked_at = now() where id = p_id and revoked_at is null;
  if found then perform b2b.log_event('api_key.revoked', null, null, null, jsonb_build_object('api_key_id', p_id)); end if;
  return found;
end $$;

-- Server-side check for public endpoints (service role only).
create or replace function b2b.api_key_check(p_key text, p_scope text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k b2b.api_keys;
begin
  select * into k from b2b.api_keys
   where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') and revoked_at is null;
  if k.id is null or not (p_scope = any (k.scopes)) then
    return jsonb_build_object('ok', false);
  end if;
  update b2b.api_keys set last_used_at = now() where id = k.id and (last_used_at is null or last_used_at < now() - interval '1 minute');
  return jsonb_build_object('ok', true, 'api_key_id', k.id, 'name', k.name);
end $$;

-- ---------- integration outbox (events to the B2C CRM and other products) ----------
create table if not exists b2b.integration_outbox (
  id              bigint generated always as identity primary key,
  event_type      text not null,
  target          text not null,
  payload         jsonb not null,
  idempotency_key text not null unique,
  status          text not null default 'pending'
                  check (status in ('pending', 'sending', 'delivered', 'failed', 'dead', 'cancelled')),
  attempts        int not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error      text,
  created_at      timestamptz not null default now(),
  delivered_at    timestamptz
);
create index if not exists integration_outbox_due_idx on b2b.integration_outbox (next_attempt_at)
  where status in ('pending', 'failed');

-- ---------- live switches (everything starts off) ----------
create table if not exists b2b.live_switches (
  scope       text primary key,     -- 'whatsapp' | 'email' | 'capi_meta' | 'capi_google' | 'partner:<id>'
  live        boolean not null default false,
  reason      text,
  switched_by uuid,
  switched_at timestamptz
);
insert into b2b.live_switches (scope) values ('whatsapp'), ('email'), ('capi_meta'), ('capi_google')
on conflict (scope) do nothing;

create or replace function b2b.set_live_switch(p_scope text, p_live boolean, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  insert into b2b.live_switches (scope, live, reason, switched_by, switched_at)
  values (p_scope, p_live, p_reason, auth.uid(), now())
  on conflict (scope) do update set live = excluded.live, reason = excluded.reason,
                                    switched_by = excluded.switched_by, switched_at = excluded.switched_at;
  perform b2b.log_event('live_switch.changed', null, null, null, jsonb_build_object('scope', p_scope, 'live', p_live, 'reason', p_reason));
  return jsonb_build_object('scope', p_scope, 'live', p_live);
end $$;

create or replace function b2b.is_live(p_scope text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select live from b2b.live_switches where scope = p_scope), false);
$$;
