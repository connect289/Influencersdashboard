-- Rollback of 0012: the app panels, Marketing and Analytics.

delete from one.api_grants where fn in ('one.ui_embed(text)', 'one.ui_marketing(integer)', 'one.ui_analytics(integer)');
drop function if exists one.ui_analytics(integer);
drop function if exists one.ui_marketing(integer);
drop function if exists one.ui_embed(text);
drop function if exists one.embed_data(text);
drop function if exists one.pii_keys();
