-- Run once in the Supabase SQL editor of the project, signed in as the project owner: staging (mplbspysxmtohnlwpbti,
-- done) and PRODUCTION (xlseqwgyjuqhktrguhyc, still to do on 15 Oct 2026: the connector cancelled it).
-- These two functions are part of b4_allocation.sql. The automated apply path refuses any SQL that contains DELETE,
-- so they were left for a person to run. Both delete only the one pool's members / one person's weekly pattern before
-- re-inserting the saved list. Safe to run more than once. Until they exist, saving a pool's members or a person's
-- weekly hours under Lead Allocation fails with "function b2c.pool_save does not exist".

create or replace function b2c.pool_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; m jsonb; i int := 0;
begin
  perform b2c.require('settings');
  if v_id is null then insert into b2c.pools (name, description) values (p ->> 'name', p ->> 'description') returning id into v_id;
  else update b2c.pools set name = coalesce(p ->> 'name', name), description = p ->> 'description' where id = v_id; end if;
  if p ? 'members' then
    delete from b2c.pool_members where pool_id = v_id;
    for m in select * from jsonb_array_elements(p -> 'members') loop
      insert into b2c.pool_members (pool_id, user_id, weight, position) values (v_id, (m ->> 'user_id')::uuid, coalesce((m ->> 'weight')::int, 1), i);
      i := i + 1;
    end loop;
  end if;
  return v_id;
end $f$;

create or replace function b2c.calendar_save(p_user uuid, p_patterns jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare x jsonb;
begin
  perform b2c.require('settings');
  delete from b2c.work_patterns where user_id = p_user;
  for x in select * from jsonb_array_elements(coalesce(p_patterns, '[]')) loop
    insert into b2c.work_patterns (user_id, isodow, start_t, end_t) values (p_user, (x ->> 'isodow')::smallint, (x ->> 'start')::time, (x ->> 'end')::time);
  end loop;
end $f$;

grant execute on function b2c.pool_save(jsonb), b2c.calendar_save(uuid, jsonb) to authenticated;
revoke execute on function b2c.pool_save(jsonb), b2c.calendar_save(uuid, jsonb) from public, anon;
