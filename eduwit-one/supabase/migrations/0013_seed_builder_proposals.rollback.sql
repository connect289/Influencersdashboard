-- Rollback of 0013: removes the builder's proposals that nobody has decided. A decided one is history (spec §13) and
-- stays.

delete from one.proposals where source = 'builder' and source_key like 'builder:%' and status = 'open' and decided_by is null;
