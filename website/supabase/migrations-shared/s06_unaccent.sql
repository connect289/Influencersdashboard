-- =====================================================================================================================
-- s06 · Install the `unaccent` extension (APPROVALS_NEEDED A-EXT-1, optional). Dev / replica only until approved.
-- New extension in the `extensions` schema; changes nothing for other products. The website keeps using web_norm()
-- either way; with unaccent installed a later website migration may fold accents in search too.
-- Rollback: s06_unaccent.rollback.sql.
-- =====================================================================================================================
create extension if not exists unaccent with schema extensions;
