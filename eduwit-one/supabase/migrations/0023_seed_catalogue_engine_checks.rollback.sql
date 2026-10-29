-- Rollback of 0023: removes the Catalogue Engine's checks with their state and results, and its app row, so 0022's
-- rollback can put back 0002's app keys. Incidents, proposals and actions are history that spec §13 keeps forever: while
-- any exists for the app, this rollback refuses, unless the session sets one.rollback_discards_history = on (as 0006's
-- rollback; the local test and the staging rehearsal do; on production, export first and decide). Check results are
-- append-only (D-085): this transaction says it rewrites them, as one.retention() does. AI tasks about its incidents
-- stay with their calls (the spend audit) and lose only the link; copied events, mutes and the audit stay.

do $$
begin
  if coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on'
     and (exists (select 1 from one.incidents where app = 'catalogue_engine')
          or exists (select 1 from one.proposals where app = 'catalogue_engine')
          or exists (select 1 from one.actions where app = 'catalogue_engine')) then
    raise exception '0023 rollback refused: schema one holds Catalogue Engine incidents, proposals or actions, which are kept forever. Export them, then run this rollback with one.rollback_discards_history = on'
      using errcode = '55000';
  end if;
end $$;

select set_config('one.history_writer', 'on', true);
delete from one.deliveries
 where incident_id in (select id from one.incidents where app = 'catalogue_engine');
update one.ai_tasks set incident_id = null, status = case when status in ('pending', 'claimed', 'deferred') then 'cancelled' else status end
 where incident_id in (select id from one.incidents where app = 'catalogue_engine');
delete from one.actions
 where app = 'catalogue_engine'
    or incident_id in (select id from one.incidents where app = 'catalogue_engine')
    or proposal_id in (select id from one.proposals where app = 'catalogue_engine'
                                                       or incident_id in (select id from one.incidents where app = 'catalogue_engine'));
delete from one.proposals
 where app = 'catalogue_engine' or incident_id in (select id from one.incidents where app = 'catalogue_engine');
delete from one.incidents where app = 'catalogue_engine';
delete from one.results where check_id in (select id from one.checks where app = 'catalogue_engine');
delete from one.check_state where check_id in (select id from one.checks where app = 'catalogue_engine');
delete from one.checks where app = 'catalogue_engine';
delete from one.apps where key = 'catalogue_engine';
select set_config('one.history_writer', 'off', true);
