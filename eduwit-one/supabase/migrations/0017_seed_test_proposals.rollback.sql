-- Rollback of 0017: removes the test proposals nobody has decided. A decided one is history (spec §13) and stays.

delete from one.proposals where source = 'builder' and source_key like 'builder:p5-%' and status = 'open' and decided_by is null;
