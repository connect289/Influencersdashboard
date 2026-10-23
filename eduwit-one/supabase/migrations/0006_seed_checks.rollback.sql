-- Rollback of 0006: removes the seeded checks with their state, results and incidents, the baselines it captured,
-- the seed function and the apps rows. Eduwit One's own records only.

delete from one.proposals where incident_id in (select id from one.incidents);
delete from one.ai_tasks where incident_id in (select id from one.incidents);
delete from one.deliveries where incident_id in (select id from one.incidents);
delete from one.actions where incident_id in (select id from one.incidents);
delete from one.incidents;
delete from one.results;
delete from one.check_state;
delete from one.checks;
delete from one.baselines where key in ('lead_intake_md5', 'student_leads_columns');
drop function if exists one.seed_check(jsonb);
delete from one.apps;
