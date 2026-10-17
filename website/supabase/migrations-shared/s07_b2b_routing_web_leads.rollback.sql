-- Rollback for s07: website sources require a verified phone again.
select b2b.set_setting(
  'engine',
  coalesce((select value from b2b.settings where key = 'engine'), '{}'::jsonb) || jsonb_build_object('require_verified_phone_sources', '["website_agent","web_agent"]'::jsonb),
  'Rollback of A-B2B-1'
);
