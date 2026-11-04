-- Rollback of 0036: WEB-02 and INF-04 every minute again, and the four heartbeat checks' descriptions as 0006 seeded
-- them before 0036. (The app's probe intervals are the app's; this only puts the catalogue back.)

with before (id, cadence_s, description) as (values
  ('WEB-02', 60, 'GET <hosts.website>/api/health not {ok:true} within 5 s, twice in a row (open_after 2). Run by the app''s health probe, which also writes heartbeat website.'),
  ('INF-04', 60, 'GET <hosts.influencer>/api/health not ok twice in a row. Run by the app''s health probe, which also writes heartbeat influencer.'),
  ('HB-spark', null, 'Spark''s /api/health, written by the app''s health probe; expected every 120 s.'),
  ('HB-b2b-app', null, 'The B2B CRM host''s /api/health, written by the app''s health probe; expected every 120 s.'),
  ('HB-website', null, 'The website''s /api/health, written by the app''s health probe; expected every 60 s.'),
  ('HB-influencer', null, 'The portal host''s /api/health, written by the app''s health probe; expected every 120 s.'))
update one.checks c
   set cadence_s = coalesce(before.cadence_s, c.cadence_s), description = before.description,
       version = c.version + 1, updated_at = now()
  from before
 where c.id = before.id
   and (c.cadence_s, c.description) is distinct from (coalesce(before.cadence_s, c.cadence_s), before.description);
