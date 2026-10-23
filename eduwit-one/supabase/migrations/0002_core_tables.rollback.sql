-- Rollback of 0002: drops every table, the grants procedure and the severity domain. Data in schema one is lost;
-- schema one holds only Eduwit One's own records, nothing of the five apps.

drop procedure if exists one.apply_grants();
drop table if exists
  one.runs, one.mutes, one.baselines, one.privilege_baseline, one.audit, one.users, one.settings_versions,
  one.settings, one.ai_calls, one.ai_tasks, one.test_runs, one.tests, one.deliveries, one.heartbeats,
  one.event_watermarks, one.events, one.briefs, one.proposals, one.actions, one.incidents, one.results,
  one.check_state, one.checks, one.apps
  cascade;
drop domain if exists one.severity;
