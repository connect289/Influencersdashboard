-- Rollback of 0007: removes seeded settings and their seed history. Values a person changed (actor <> 'seed') stay.

delete from one.settings_versions where actor = 'seed' and key in (select key from one.settings where actor = 'seed');
delete from one.settings where actor = 'seed';
