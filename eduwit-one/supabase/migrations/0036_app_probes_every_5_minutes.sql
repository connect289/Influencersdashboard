-- 0036 the apps are probed every 5 minutes (D-133). The app's health probe called the website every minute and the
-- influencer portal, the B2B CRM and Spark every two, and a health call that waits on a slow database runs on the
-- app's side long after the probe gave up (Eduwit One's deadline is 5 s; the app's function ran up to Vercel's 300 s
-- ceiling): on 29 and 31 Oct and 1 Nov 2026 those calls alone cost tens of GB-hours a day, and the Vercel account
-- was paused for exceeding its function time. The owner's rule (3 Nov 2026): every app once in 5 minutes. The probe's
-- intervals move in the app (APP_PROBE_INTERVAL_S, lib/checks/probes/app-health.ts); here the two app-run checks it
-- carries, WEB-02 and INF-04, take the same cadence, and the four heartbeat checks' descriptions say 300 s. Direct
-- updates rather than one.seed_check, so every other field stays as the owner left it. The sources are
-- supabase/checks/web.sql, influencer.sql and heartbeats.sql (0006 is regenerated for a fresh install). Nothing of the
-- five apps is touched; only schema one. Rollback: 0036_app_probes_every_5_minutes.rollback.sql.

with next (id, cadence_s, description) as (values
  ('WEB-02', 300, 'GET <hosts.website>/api/health not {ok:true} within 5 s, twice in a row (open_after 2). Run by the app''s health probe every 5 minutes (D-133), which also writes heartbeat website.'),
  ('INF-04', 300, 'GET <hosts.influencer>/api/health not ok twice in a row. Run by the app''s health probe every 5 minutes (D-133), which also writes heartbeat influencer.'),
  ('HB-spark', null, 'Spark''s /api/health, written by the app''s health probe; expected every 300 s (D-133).'),
  ('HB-b2b-app', null, 'The B2B CRM host''s /api/health, written by the app''s health probe; expected every 300 s (D-133).'),
  ('HB-website', null, 'The website''s /api/health, written by the app''s health probe; expected every 300 s (D-133).'),
  ('HB-influencer', null, 'The portal host''s /api/health, written by the app''s health probe; expected every 300 s (D-133).'))
update one.checks c
   set cadence_s = coalesce(next.cadence_s, c.cadence_s), description = next.description,
       version = c.version + 1, updated_at = now()
  from next
 where c.id = next.id
   and (c.cadence_s, c.description) is distinct from (coalesce(next.cadence_s, c.cadence_s), next.description);
