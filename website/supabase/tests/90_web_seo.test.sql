-- web10: SEO toolkit — Search Console import and dashboard, keywords with positions and cannibalisation, opportunities,
-- 404 monitor with one-click redirects and chain detection, on-page checks, link suggestions. Runs on the replica too.
begin;
create temp table r (ok boolean, name text) on commit drop;
-- start from no Search Console data (a local database may hold sample rows from e2e runs; rolled back at the end)
delete from public.web_seo_daily;
delete from public.web_seo_keywords;

insert into r select (public.web_seo_import(jsonb_build_array(
  jsonb_build_object('day', current_date - 3, 'query', 'Online MBA fees', 'page', '/programmes/online-mba', 'clicks', 12, 'impressions', 400, 'position', 6.2),
  jsonb_build_object('day', current_date - 3, 'query', 'online mba fees', 'page', '/universities/nmims', 'clicks', 1, 'impressions', 90, 'position', 18),
  jsonb_build_object('day', current_date - 2, 'query', 'online bca for working professionals', 'page', '/', 'clicks', 0, 'impressions', 150, 'position', 22.5),
  jsonb_build_object('day', current_date - 40, 'query', 'online mba fees', 'page', '/programmes/online-mba', 'clicks', 30, 'impressions', 500, 'position', 5),
  jsonb_build_object('day', current_date - 1, 'query', 'is online degree valid for government jobs', 'page', '/', 'clicks', 0, 'impressions', 60, 'position', 30)
), 'sample') ->> 'rows')::int = 5, 'Search Console rows imported (queries normalised)';
insert into r select (public.web_seo_dashboard(28)->'totals'->>'clicks')::int = 13, 'dashboard totals for the period';
insert into r select (public.web_seo_dashboard(28)->'falling'->0->>'page') = '/programmes/online-mba', 'falling page detected against the previous period';
insert into r select jsonb_array_length(public.web_seo_dashboard(28)->'low_ctr') >= 1, 'low-CTR pages listed';

insert into public.web_seo_keywords (keyword, priority, target_path) values ('online mba fees', 1, '/programmes/online-mba');
insert into r select (select (x->>'cannibalised')::boolean and (x->>'target_position')::numeric = 6.2 from jsonb_array_elements(public.web_seo_keywords_report(28)) x where x->>'keyword' = 'online mba fees'), 'keyword position and cannibalisation';

insert into r select exists (select 1 from jsonb_array_elements(public.web_seo_opportunities(90)) x where x->>'query' = 'online bca for working professionals'), 'opportunity: impressions without a landing page';
insert into r select (select (x->>'question')::boolean from jsonb_array_elements(public.web_seo_opportunities(90)) x where x->>'query' like 'is online degree%'), 'question-style queries flagged for guides';
insert into r select not exists (select 1 from jsonb_array_elements(public.web_seo_opportunities(90)) x where x->>'best_page' = '/programmes/online-mba'), 'queries already served by a curated view are not opportunities';

select public.web_404_hit('/old-courses-page', 'https://google.com');
select public.web_404_hit('/old-courses-page', null);
insert into r select (select hits from public.web_404_log where path = '/old-courses-page') = 2, '404 hits counted';
insert into r select (public.web_404_redirect('/old-courses-page', '/programmes', '00000000-0000-0000-0000-0000000000a1', 'ed@eduwit.in', 'content_editor')->>'ok')::boolean, 'one-click redirect from the 404 log';
insert into r select (select resolved_at is not null from public.web_404_log where path = '/old-courses-page')
  and exists (select 1 from public.web_redirects where from_path = '/old-courses-page' and source = '404_monitor'), '404 resolved and redirect recorded';
insert into public.web_redirects (from_path, to_path) values ('/a-chain', '/old-courses-page');
insert into r select jsonb_array_length(public.web_404_report()->'chains') >= 1, 'redirect chains detected';

select public.web_seo_check_save('/programmes/online-mba', 82, '[{"rule":"description_length","severity":"warn"}]');
insert into r select (public.web_seo_checks_list()->0->>'score')::int = 82, 'on-page check stored';

insert into r select public.web_link_suggestions_add('[{"from_slug":"how-to-choose","to_path":"/programmes/online-mba","anchor":"online MBA","reason":"mentions MBA"}]') = 1, 'link suggestion added';
select public.web_link_decide((select id from public.web_link_suggestions where from_slug = 'how-to-choose'), 'approved', 'ed@eduwit.in');
insert into r select (public.web_resource_links('how-to-choose')->0->>'href') = '/programmes/online-mba', 'approved links appear on the guide';
insert into r select (select count(*) from public.web_local_seo_tasks) >= 7, 'local SEO checklist seeded';
-- web11 (L4): 404 rows not seen for 90 days are pruned; recent ones stay.
insert into public.web_404_log (path, last_seen) values ('/stale-404-test', now() - interval '120 days'), ('/fresh-404-test', now());
create temp table pr on commit drop as select public.web_404_prune(90) as n;  -- own statement (snapshot visibility)
insert into r select (select n from pr) >= 1 and not exists (select 1 from public.web_404_log where path = '/stale-404-test')
  and exists (select 1 from public.web_404_log where path = '/fresh-404-test'), '404 log pruned after 90 days';
-- web11 (L2): redirect targets must stay on site or be https.
insert into r select not exists (select 1 from (values ('//evil.com'), ('/\evil.com'), ('/ x')) v(t)
  where t ~ (select substring(pg_get_constraintdef(oid) from $q$'(.*)'::text$q$) from pg_constraint where conname = 'web_redirects_to_path_check')),
  'redirect targets cannot leave the site except over https';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
