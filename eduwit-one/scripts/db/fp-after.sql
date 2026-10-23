-- Wraps a migration file, after it, in the same transaction (see app-fingerprint.sql). Raises, and so rolls the whole
-- file back, when the catalogue outside schema one changed.
\set fp_phase after
\ir app-fingerprint.sql
do $$
begin
  if current_setting('one.fp_before') is distinct from current_setting('one.fp_after') then
    raise exception 'refused: this migration changed an object outside schema one (an ACL, policy, trigger, function, column, role, publication, default privilege or cron job); nothing was applied';
  end if;
end $$;
