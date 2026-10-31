-- Rollback of 0031: gives the reader its table-wide SELECT back where 0031 narrowed it; restores 0020's one.mask_text,
-- 0021's one.ui_chat_action_propose and 3-argument one.ui_chat_action_decide, 0011's one.ui_user_put and 0018's
-- one.ai_calls_add verbatim; drops one.reader_without_credentials, one.is_credential_column,
-- one.credential_column_pattern, one.reader_excluded_columns, one.mask_normalise, one.mask_phones, one.ai_reserve,
-- one.ai_reserved and one.ai_reservations (reservations are transient: nothing is lost).

-- The reader reads each relation 0031 narrowed whole again (one.reader_excluded_columns, where it still exists), its
-- column grants there gone, as before 0031.
do $$
declare
  r record;
begin
  for r in
    select x.relation as rel,
           string_agg(pg_catalog.quote_ident(a.attname), ', ' order by a.attnum)
             filter (where exists (select 1 from pg_catalog.aclexplode(a.attacl) g
                                    where g.grantee = 'eduwit_one_reader'::regrole and g.privilege_type = 'SELECT')) as cols
      from (select distinct relation from one.reader_excluded_columns) x
      join pg_catalog.pg_attribute a on a.attrelid = pg_catalog.to_regclass(x.relation) and a.attnum > 0 and not a.attisdropped
     group by x.relation
  loop
    if r.cols is not null then
      execute format('revoke select (%s) on %s from eduwit_one_reader', r.cols, r.rel);
    end if;
    execute format('grant select on %s to eduwit_one_reader', r.rel);
  end loop;
end $$;
drop procedure if exists one.reader_without_credentials();
drop function if exists one.is_credential_column(regclass, name);
drop function if exists one.credential_column_pattern();
drop table if exists one.reader_excluded_columns;

delete from one.api_grants where fn = 'one.ai_reserve(bigint,text,numeric)';
drop function if exists one.ai_reserve(bigint, text, numeric);
drop function if exists one.ai_reserved(bigint);
drop table if exists one.ai_reservations;

create or replace function one.ai_calls_add(p_task bigint, p_holder text, p_calls jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_spent numeric;
begin
  perform one.ai_record_calls(v_t.id, p_calls);
  v_spent := one.ai_spent_today();
  return jsonb_build_object('spent_inr', v_spent, 'remaining_inr', greatest(v_cap - v_spent, 0));
end $$;

create or replace function one.ui_user_put(p_email text, p_role text, p_active boolean, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_email text := lower(trim(p_email));
  v_uid uuid;
  v_before jsonb;
begin
  if v_email !~ '^[^@\s]+@eduwit\.in$' then
    raise exception 'only @eduwit.in addresses' using errcode = '22023';
  end if;
  if p_role not in ('owner', 'engineer') then
    raise exception 'role must be owner or engineer' using errcode = '22023';
  end if;
  select id into v_uid from auth.users where lower(email) = v_email;
  if v_uid is null then
    raise exception 'no Supabase user has this address yet: ask the CRM owner to create it first (S-21)' using errcode = 'P0002';
  end if;
  if v_uid = one.uid() and (p_role <> 'owner' or not p_active) then
    raise exception 'you cannot remove your own owner access' using errcode = '22023';
  end if;
  select to_jsonb(o) into v_before from one.users o where o.user_id = v_uid;
  insert into one.users (user_id, email, role, is_active) values (v_uid, v_email, p_role, p_active)
  on conflict (user_id) do update set email = excluded.email, role = excluded.role, is_active = excluded.is_active;
  if not exists (select 1 from one.users where role = 'owner' and is_active) then
    raise exception 'at least one active owner must remain' using errcode = '22023';
  end if;
  if not p_active then
    update one.trusted_devices set revoked_at = now() where user_id = v_uid and revoked_at is null;
    delete from one.session_checks where user_id = v_uid;
  end if;
  perform one.ui_audit_write(v_actor, 'user.put', 'user:' || v_email, v_before,
                             jsonb_build_object('role', p_role, 'is_active', p_active), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

drop function if exists one.ui_chat_action_decide(bigint, text, text, jsonb);
create or replace function one.ui_chat_action_decide(p_id bigint, p_decision text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_a one.chat_actions;
  v_t one.chat_threads;
begin
  select * into v_a from one.chat_actions where id = p_id for update;
  if not found then
    raise exception 'no action %', p_id using errcode = 'P0002';
  end if;
  v_t := one.chat_own_thread(v_a.thread_id);
  if p_decision not in ('confirm', 'decline') then
    raise exception 'the decision is confirm or decline' using errcode = '22023';
  end if;
  if v_a.status <> 'proposed' then
    raise exception 'action % is not waiting for a decision (%)', p_id, v_a.status using errcode = 'P0002';
  end if;
  if v_a.proposed_at < now() - interval '2 hours' then
    update one.chat_actions set status = 'expired' where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'expired', 'summary', v_a.summary));
    return jsonb_build_object('ok', false, 'status', 'expired', 'error', 'this action expired two hours after it was proposed; ask for it again');
  end if;
  if p_decision = 'decline' then
    update one.chat_actions set status = 'declined', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'declined', 'summary', v_a.summary));
    perform one.ui_audit_write(v_actor, 'chat.action.decline', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool), p_request_id);
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  update one.chat_actions set status = 'confirmed', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
  perform one.ui_audit_write(v_actor, 'chat.action.confirm', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool, 'args', v_a.args), p_request_id);
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'id', p_id, 'tool', v_a.tool, 'args', v_a.args, 'summary', v_a.summary, 'risk', v_a.risk);
end $$;

update one.api_grants set fn = 'one.ui_chat_action_decide(bigint,text,text)'
 where fn = 'one.ui_chat_action_decide(bigint,text,text,jsonb)' and role = 'authenticated';

create or replace function one.ui_chat_action_propose(p_task bigint, p_holder text, p_tool text, p_args jsonb, p_summary text, p_risk text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task one.ai_tasks;
  v_t one.chat_threads;
  v_id bigint;
begin
  select * into v_task from one.ai_tasks where id = p_task and kind = 'chat' and status = 'claimed' and claimed_by = p_holder;
  if not found then
    raise exception 'turn % is not open for this holder', p_task using errcode = '55000';
  end if;
  v_t := one.chat_own_thread((v_task.input ->> 'thread_id')::bigint);
  if coalesce(p_tool, '') !~ '^[a-z_]{3,40}$' or coalesce(p_risk, '') not in ('low', 'medium', 'high')
     or length(trim(coalesce(p_summary, ''))) not between 3 and 500
     or jsonb_typeof(coalesce(p_args, '{}'::jsonb)) <> 'object' or pg_column_size(coalesce(p_args, '{}'::jsonb)) > 20000 then
    raise exception 'an action names a tool, a risk (low, medium, high), a summary of 3 to 500 characters and an object of arguments' using errcode = '22023';
  end if;
  if (select count(*) from one.chat_actions where thread_id = v_t.id and status = 'proposed') >= 5 then
    raise exception 'five actions already wait for a decision in this conversation' using errcode = '22023';
  end if;
  insert into one.chat_actions (thread_id, task_id, tool, args, summary, risk, proposed_by)
  values (v_t.id, p_task, p_tool, one.mask_json(coalesce(p_args, '{}'::jsonb)), trim(p_summary), p_risk, v_actor) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function one.mask_text(p text) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null when p !~ '[0-9@]' then p else
    regexp_replace(
      regexp_replace(
        regexp_replace(p, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
        '(\+?91[\s-]?)?[6-9][0-9]{4}[\s-]?[0-9]{5}(?![0-9])', '[phone]', 'g'),
      '(?<![0-9])[0-9]{11,15}(?![0-9])', '[phone]', 'g') end
$$;

drop function if exists one.mask_phones(text);
drop function if exists one.mask_normalise(text);

call one.apply_grants();
