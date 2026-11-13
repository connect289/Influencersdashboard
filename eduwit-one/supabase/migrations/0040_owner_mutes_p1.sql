-- 0040 the audit of 13 Nov 2026, finding M13 (D-139): muting a top-priority alarm is the owner's.
-- Only schema one changes, and in it one function: one.ui_mute, the only door to one.mute (the one writer of
-- one.mutes besides one.unmute, which only ends a mute; one.checks.muted_until has no writer). No table, grant or
-- signature changes, so every caller (the incident page, Settings → Maintenance, the chat's mute card) works as before.
--   A mute holds every alert of its target: of one check, or of every check of an app. Switching a P1 off, lowering
--   it, running it less often and loosening the thresholds it reads are the owner's (D-065 (3), M2, D-137); a mute did
--   the same for up to 7 days at a time, and again when it ended, with the engineer's 'operate' permission. Now:
--     - a check whose severity is P1, and
--     - an app that has at least one P1 check, whether that check is switched on or off (a check that is off can be
--       switched on, by a person or by its Setup item being validated, while the app's mute is in force)
--   are muted only by the owner. The refusal is SQLSTATE 42501 with a message the app shows as it is:
--   "only the owner can mute a top-priority alarm: …". Everything else is 0037's: any other check or app is muted by
--   an engineer as before, 1 minute to 7 days with a reason, one audit row with the request id. Ending a mute
--   (one.ui_unmute) stays with engineers: it makes things louder, not quieter.
--   Mutes already in force are left as they are; they end at their time (Settings → Maintenance lists them, and the
--   owner or an engineer can end one now).
-- Rollback: 0040_owner_mutes_p1.rollback.sql.

create or replace function one.ui_mute(p_target_type text, p_target text, p_minutes integer, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_id bigint;
begin
  -- A P1 check, or an app with any P1 check: the owner's (D-139). The caller has passed 'operate', so a refusal
  -- of 'owner' here is about the role alone, and says so.
  if (p_target_type = 'check' and exists (select 1 from one.checks c where c.id = p_target and c.severity = 'P1'))
     or (p_target_type = 'app' and exists (select 1 from one.checks c where c.app = p_target and c.severity = 'P1')) then
    begin
      perform one.ui_require('owner');
    exception when insufficient_privilege then
      raise exception 'only the owner can mute a top-priority alarm: %', case p_target_type
          when 'check' then 'check ' || left(p_target, 60) || ' is P1'
          else 'app ' || left(p_target, 60) || ' has P1 checks' end
        using errcode = '42501';
    end;
  end if;
  v_id := one.mute(p_target_type, p_target, p_minutes, one.ui_reason(p_reason), v_actor, p_request_id);
  return jsonb_build_object('ok', true, 'mute_id', v_id);
end $$;

call one.apply_grants();
