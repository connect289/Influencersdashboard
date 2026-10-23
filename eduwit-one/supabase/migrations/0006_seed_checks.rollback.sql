-- Rollback of 0006: removes the seeded checks with their state and results, the baselines it captured, the seed
-- function and the apps rows. Incidents, proposals, actions and deliveries are history that spec §13 keeps forever:
-- while any exists, this rollback refuses, unless the session sets one.rollback_discards_history = on (the local test
-- and the staging rehearsal do; on production, export first and decide; m8 of the second review).

do $$
begin
  if coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on'
     and (exists (select 1 from one.incidents) or exists (select 1 from one.proposals) or exists (select 1 from one.actions)) then
    raise exception '0006 rollback refused: schema one holds incidents, proposals or actions, which are kept forever. Export them, then run this rollback with one.rollback_discards_history = on'
      using errcode = '55000';
  end if;
end $$;

delete from one.deliveries;
delete from one.ai_tasks;
delete from one.proposals;
delete from one.actions;
delete from one.incidents;
delete from one.results;
delete from one.check_state;
delete from one.checks;
delete from one.baselines where key in ('lead_intake_md5', 'student_leads_columns', 'security_definer_views');
drop function if exists one.seed_check(jsonb);
delete from one.apps;
