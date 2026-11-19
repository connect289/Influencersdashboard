-- Test creators, 20 Nov 2026 (schema inf only; D-200).
-- Eduwit One's end-to-end test of the portal needs a creator it can use without touching a real person (its Setup item
-- test_creator reads inf.creators where is_test). The column has existed since the identity migration and analytics,
-- the leaderboard and the creator counts already leave test creators out, but nothing could set it.
-- 1. inf.creator_set_test(creator, is_test, reason): staff with creator.write mark a creator as a test creator, or
--    back. A reason is required both ways and is written to the audit log. A creator with any ledger entry cannot be
--    marked as a test creator: money was recorded for them, so hiding them from the reports would hide real money.
--    Unmarking is always allowed. Blocked creators can be marked too (the flag does not change their status).
-- Idempotent. Inverse statements: see the rollback block at the end.

create or replace function inf.creator_set_test(p_creator uuid, p_test boolean, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_was boolean;
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_test is null then raise exception 'say whether the creator is a test creator' using errcode = '22023'; end if;
  if char_length(coalesce(trim(p_reason), '')) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select is_test into v_was from inf.creators where id = p_creator for update;
  if not found then raise exception 'no such creator' using errcode = '22023'; end if;
  if v_was = p_test then return; end if;
  if p_test and exists (select 1 from inf.ledger_entries l where l.creator_id = p_creator) then
    raise exception 'a creator with ledger entries cannot be a test creator' using errcode = '22023';
  end if;
  update inf.creators set is_test = p_test where id = p_creator;
  perform inf.audit('creator', p_creator::text, case when p_test then 'mark_test' else 'unmark_test' end,
                    jsonb_build_object('is_test', v_was), jsonb_build_object('is_test', p_test, 'reason', left(trim(p_reason), 500)));
end $$;

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.creator_set_test(uuid, boolean, text)', 'authenticated', 'execute')
on conflict do nothing;

call inf.apply_client_grants();

-- ---------------------------------------------------------------------------------------------------------------
-- Rollback (run by hand; test creators stay test creators, nothing else depended on the function)
-- ---------------------------------------------------------------------------------------------------------------
-- delete from inf.client_grants where object_name = 'inf.creator_set_test(uuid, boolean, text)';
-- drop function if exists inf.creator_set_test(uuid, boolean, text);
-- call inf.apply_client_grants();
