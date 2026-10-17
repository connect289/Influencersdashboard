-- Rollback for s03 (A-TAX-1): drops the compatibility views and the shared view, then renames the tables back to
-- their web_tax_* names. Data, grants, RLS and indexes travel with the tables, so the website is exactly as before.
drop view if exists public.catalog_tax_offerings_v;
drop view if exists public.web_tax_levels;
drop view if exists public.web_tax_categories;
drop view if exists public.web_tax_programmes;
drop view if exists public.web_tax_specialisations;
drop view if exists public.web_tax_goal_tags;
drop view if exists public.web_tax_career_tags;
drop view if exists public.web_tax_tag_links;
drop view if exists public.web_tax_synonyms;
drop view if exists public.web_tax_formats;
drop view if exists public.web_tax_offering_map;
alter table public.catalog_tax_levels rename to web_tax_levels;
alter table public.catalog_tax_categories rename to web_tax_categories;
alter table public.catalog_tax_programmes rename to web_tax_programmes;
alter table public.catalog_tax_specialisations rename to web_tax_specialisations;
alter table public.catalog_tax_goal_tags rename to web_tax_goal_tags;
alter table public.catalog_tax_career_tags rename to web_tax_career_tags;
alter table public.catalog_tax_tag_links rename to web_tax_tag_links;
alter table public.catalog_tax_synonyms rename to web_tax_synonyms;
alter table public.catalog_tax_formats rename to web_tax_formats;
alter table public.catalog_tax_offering_map rename to web_tax_offering_map;
