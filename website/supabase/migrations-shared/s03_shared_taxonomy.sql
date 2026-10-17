-- s03_shared_taxonomy — PROPOSAL (A-TAX-1). Dev/replica only; never applied to production without the owner's approval.
-- Promotes the website's taxonomy to a shared layer that Witty and the CRMs can read: the web_tax_* tables become
-- catalog_tax_* and the old names stay as simple (auto-updatable) views, so the website keeps working unchanged and
-- can switch to the new names later. Nothing existing in the shared schema is altered.
-- Verified by scripts/db/check-shared-proposals.sh (applies inside a transaction on the replica, then rolls back).

alter table public.web_tax_levels rename to catalog_tax_levels;
alter table public.web_tax_categories rename to catalog_tax_categories;
alter table public.web_tax_programmes rename to catalog_tax_programmes;
alter table public.web_tax_specialisations rename to catalog_tax_specialisations;
alter table public.web_tax_goal_tags rename to catalog_tax_goal_tags;
alter table public.web_tax_career_tags rename to catalog_tax_career_tags;
alter table public.web_tax_tag_links rename to catalog_tax_tag_links;
alter table public.web_tax_synonyms rename to catalog_tax_synonyms;
alter table public.web_tax_formats rename to catalog_tax_formats;
alter table public.web_tax_offering_map rename to catalog_tax_offering_map;

create view public.web_tax_levels with (security_invoker = true) as select * from public.catalog_tax_levels;
create view public.web_tax_categories with (security_invoker = true) as select * from public.catalog_tax_categories;
create view public.web_tax_programmes with (security_invoker = true) as select * from public.catalog_tax_programmes;
create view public.web_tax_specialisations with (security_invoker = true) as select * from public.catalog_tax_specialisations;
create view public.web_tax_goal_tags with (security_invoker = true) as select * from public.catalog_tax_goal_tags;
create view public.web_tax_career_tags with (security_invoker = true) as select * from public.catalog_tax_career_tags;
create view public.web_tax_tag_links with (security_invoker = true) as select * from public.catalog_tax_tag_links;
create view public.web_tax_synonyms with (security_invoker = true) as select * from public.catalog_tax_synonyms;
create view public.web_tax_formats with (security_invoker = true) as select * from public.catalog_tax_formats;
create view public.web_tax_offering_map with (security_invoker = true) as select * from public.catalog_tax_offering_map;

do $$
declare t text;
begin
  foreach t in array array['web_tax_levels','web_tax_categories','web_tax_programmes','web_tax_specialisations','web_tax_goal_tags',
    'web_tax_career_tags','web_tax_tag_links','web_tax_synonyms','web_tax_formats','web_tax_offering_map'] loop
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- Read-only convenience view for Witty and the CRMs: catalogue row → canonical names.
create view public.catalog_tax_offerings_v with (security_invoker = true) as
select m.catalog_program_id, m.programme_id, p.short_name as programme, p.level_id, m.specialisation_ids,
       (select string_agg(s.name, ' + ' order by array_position(m.specialisation_ids, s.id))
          from public.catalog_tax_specialisations s where s.id = any(m.specialisation_ids)) as specialisation,
       m.format, m.attributes
from public.catalog_tax_offering_map m
left join public.catalog_tax_programmes p on p.id = m.programme_id;
revoke all on public.catalog_tax_offerings_v from anon, authenticated, public;
grant select on public.catalog_tax_offerings_v to service_role;
