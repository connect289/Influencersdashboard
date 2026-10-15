-- B2C CRM b30: the phone numbers the Admin allocates to counsellors and sales managers.
--   users.phone       the person's work mobile: the number they dial from today, and the one Exotel rings first
--   users.caller_id   optional: a number allocated to the person that students see (an Exotel virtual number); when it is
--                     empty the company caller ID in Settings → telephony is used
--   phone_set()       the Admin allocates, changes or moves a number. A number held by someone else is moved only when
--                     the Admin says so ("move"), and the other person is told. Counsellors cannot change their own
--                     numbers (they raise a support ticket).
--   phone_history     every change, whoever made it and however (Teams, phone_set, directory sync), with the reason

alter table b2c.users add column if not exists caller_id text;

create table if not exists b2c.phone_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references b2c.users (user_id),
  kind text not null check (kind in ('mobile', 'caller_id')),
  old_number text,
  new_number text,
  reason text,
  actor_id uuid,
  at timestamptz not null default now()
);
create index if not exists phone_history_user on b2c.phone_history (user_id, at desc);
alter table b2c.phone_history enable row level security;

create or replace function b2c.users_phone_history() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if new.phone is distinct from old.phone then
    insert into b2c.phone_history (user_id, kind, old_number, new_number, reason, actor_id)
    values (new.user_id, 'mobile', old.phone, new.phone, nullif(current_setting('b2c.phone_reason', true), ''), b2c.uid());
  end if;
  if new.caller_id is distinct from old.caller_id then
    insert into b2c.phone_history (user_id, kind, old_number, new_number, reason, actor_id)
    values (new.user_id, 'caller_id', old.caller_id, new.caller_id, nullif(current_setting('b2c.phone_reason', true), ''), b2c.uid());
  end if;
  return null;
end $f$;
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'users_phone_history' and tgrelid = 'b2c.users'::regclass) then
    create trigger users_phone_history after update of phone, caller_id on b2c.users for each row execute function b2c.users_phone_history();
  end if;
end $d$;

/* p: user_id, kind (mobile | caller_id), number (empty clears it), reason, move (take it from whoever holds it). */
create or replace function b2c.phone_set(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v_user uuid := (p ->> 'user_id')::uuid; v_kind text := p ->> 'kind';
        v_num text := nullif(trim(p ->> 'number'), ''); v_norm text; v_holder record; v_reason text := nullif(trim(p ->> 'reason'), ''); v_moved text;
begin
  if v_kind not in ('mobile', 'caller_id') then raise exception 'the number is a mobile or a caller ID'; end if;
  if not exists (select 1 from b2c.users where user_id = v_user) then raise exception 'unknown person'; end if;
  if v_reason is null or length(v_reason) < 3 then raise exception 'give a reason'; end if;
  if v_num is not null then
    v_norm := b2c.norm_phone(v_num);
    if length(v_norm) < 10 or length(v_norm) > 13 then raise exception 'that does not look like a phone number'; end if;
    v_num := '+' || case when length(v_norm) = 10 then '91' || v_norm else v_norm end;
    select user_id, full_name into v_holder from b2c.users
     where user_id <> v_user and b2c.norm_phone(case when v_kind = 'mobile' then phone else caller_id end) = b2c.norm_phone(v_num) limit 1;
    if v_holder.user_id is not null then
      if not coalesce((p ->> 'move')::boolean, false) then
        raise exception 'this number is allocated to %; choose "move it" to take it from them', coalesce(v_holder.full_name, 'someone else');
      end if;
      perform set_config('b2c.phone_reason', 'moved to another person: ' || v_reason, true);
      if v_kind = 'mobile' then update b2c.users set phone = null, updated_at = now() where user_id = v_holder.user_id;
      else update b2c.users set caller_id = null, updated_at = now() where user_id = v_holder.user_id; end if;
      perform b2c.notify(v_holder.user_id, 'phone_changed', case when v_kind = 'mobile' then 'Your work number was moved' else 'Your caller ID was moved' end,
                         v_num || ' is now allocated to someone else. Ask the Admin for your new number.', '/s/me', null, 'phone-moved:' || v_holder.user_id || ':' || v_norm);
      v_moved := v_holder.full_name;
    end if;
  end if;
  perform set_config('b2c.phone_reason', v_reason, true);
  if v_kind = 'mobile' then update b2c.users set phone = v_num, updated_at = now(), actor_id = me where user_id = v_user;
  else update b2c.users set caller_id = v_num, updated_at = now(), actor_id = me where user_id = v_user; end if;
  perform b2c.notify(v_user, 'phone_changed', case when v_kind = 'mobile' then 'Your work number changed' else 'Your caller ID changed' end,
                     coalesce(v_num, 'removed') || ' · ' || v_reason, '/s/me', null, null);
  perform b2c.log('team.phone_set', null, jsonb_build_object('user_id', v_user, 'kind', v_kind, 'number', v_num, 'moved_from', v_moved, 'reason', v_reason));
  return jsonb_build_object('number', v_num, 'moved_from', v_moved);
end $f$;

/* The Admin's phone directory: every active person with both numbers and the latest changes. */
create or replace function b2c.phone_directory() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return jsonb_build_object(
    'people', (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'email', u.email, 'role', u.role, 'active', u.is_active,
                 'mobile', u.phone, 'caller_id', u.caller_id) order by u.is_active desc, u.full_name), '[]') from b2c.users u),
    'company_caller_id', b2c.setting('telephony') ->> 'caller_id',
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'name', u.full_name, 'kind', h.kind, 'old', h.old_number, 'new', h.new_number, 'reason', h.reason,
                  'by', (select full_name from b2c.users a where a.user_id = h.actor_id)) order by h.at desc), '[]')
                  from (select * from b2c.phone_history order by at desc limit 100) h join b2c.users u on u.user_id = h.user_id));
end $f$;

/* My own numbers (Me page): read only. */
create or replace function b2c.phone_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('mobile', phone, 'caller_id', coalesce(caller_id, b2c.setting('telephony') ->> 'caller_id'), 'own_caller_id', caller_id is not null)
    from b2c.users where user_id = b2c.uid()
$f$;

/* A bridged call shows the counsellor's own caller ID when they have one (b25 used the company's only). */
create or replace function b2c.call_start(p_lead bigint, p_contact bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_provider text := b2c.telephony_provider(p_lead); v_num text; v_agent text; v_caller text; v_id bigint; r jsonb;
begin
  if v_provider = 'manual' then
    return b2c.call_tap(p_lead, p_contact) || jsonb_build_object('mode', 'manual');
  end if;
  select value into v_num from b2c.lead_contacts
   where lead_id = p_lead and kind = 'phone' and removed_at is null and (id = p_contact or (p_contact is null and primary_call))
   order by (id = p_contact) desc nulls last limit 1;
  if v_num is null then raise exception 'this lead has no phone number'; end if;
  select phone, caller_id into v_agent, v_caller from b2c.users where user_id = me;
  if coalesce(b2c.norm_phone(v_agent), '') = '' then raise exception 'you have no work mobile in Teams yet: ask the Admin (the call rings your phone, then the student)'; end if;
  insert into b2c.calls (lead_id, user_id, number, provider, direction, status, from_number)
  values (p_lead, me, v_num, v_provider, 'out', 'initiated', v_agent) returning id into v_id;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'call_tap', p_lead, jsonb_build_object('call_id', v_id, 'provider', v_provider));
  r := jsonb_build_object('mode', 'bridge', 'provider', v_provider, 'call_id', v_id, 'agent', '+' || b2c.norm_phone(v_agent), 'student', '+' || b2c.norm_phone(v_num),
                          'caller_id', coalesce(v_caller, b2c.setting('telephony') ->> 'caller_id'), 'number', v_num, 'tel', 'tel:+' || b2c.norm_phone(v_num));
  return r;
end $f$;

grant execute on function b2c.phone_set(jsonb), b2c.phone_directory(), b2c.phone_mine() to authenticated;
revoke execute on function b2c.users_phone_history() from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
