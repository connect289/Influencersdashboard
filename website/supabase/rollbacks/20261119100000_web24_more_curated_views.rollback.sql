-- Rollback of web24: removes the seven landing pages it added.
delete from public.web_curated_views where slug in ('online-bba','online-ma','online-bcom','online-ba','online-mcom','online-pgdm','online-msc');
