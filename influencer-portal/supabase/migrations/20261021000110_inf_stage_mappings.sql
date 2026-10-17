-- generated: stage-mappings sha256=84093f1a9c166ca3999f10d0001620f421fae0cd27eb3862e54258a9e8eecd5e
-- DO NOT EDIT. Produced by `npm run gen:sql` from lib/auth/permissions.ts, lib/settings/registry.ts,
-- lib/compensation/schema.ts, lib/compensation/presets.ts and lib/contracts/library.ts.
insert into inf.stage_mappings (priority, conditions, creator_stage, reason_category, flag)
select * from (values
  (10, '[{"field":"attribution_status","in":["duplicate"]}]'::jsonb, 'duplicate', 'already enquired before your link', null),
  (11, '[{"field":"attribution_status","in":["outside_window"]}]'::jsonb, 'not_attributed', 'outside the attribution window', null),
  (12, '[{"field":"attribution_status","in":["self_referral"]}]'::jsonb, 'not_attributed', 'self-referral', null),
  (13, '[{"field":"attribution_status","in":["fraud_suspected"]}]'::jsonb, null, null, 'under_review'),
  (14, '[{"field":"attribution_status","in":["manually_rejected"]}]'::jsonb, 'not_attributed', 'rejected after review', null),
  (20, '[{"field":"enrollment_status","in":["refunded","cancelled"]}]'::jsonb, 'enrolled', 'enrollment cancelled', 'cancelled'),
  (21, '[{"field":"stage","in":["enrolled","verified","commission_booked","paid"]}]'::jsonb, 'enrolled', null, null),
  (22, '[{"field":"enrollment_status","in":["reported","verified"]}]'::jsonb, 'enrolled', null, null),
  (23, '[{"field":"b2c_stage","in":["enrolled"]}]'::jsonb, 'enrolled', null, null),
  (30, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["duplicate"]}]'::jsonb, 'duplicate', 'duplicate enquiry', null),
  (31, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["junk or test"]}]'::jsonb, 'junk', 'invalid or test', null),
  (32, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["wrong number"]}]'::jsonb, 'junk', 'wrong number', null),
  (33, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["not reachable"]}]'::jsonb, 'lost', 'not reachable', null),
  (34, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["not interested"]}]'::jsonb, 'lost', 'not interested', null),
  (35, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["not eligible"]}]'::jsonb, 'lost', 'not eligible', null),
  (36, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["over budget"]}]'::jsonb, 'lost', 'budget', null),
  (37, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["chose another provider","enrolled elsewhere"]}]'::jsonb, 'lost', 'chose another option', null),
  (38, '[{"field":"stage","in":["lost"]},{"field":"lost_reason","in":["cannot be served"]}]'::jsonb, 'lost', 'programme not available', null),
  (39, '[{"field":"stage","in":["lost"]}]'::jsonb, 'lost', 'other', null),
  (40, '[{"field":"b2c_stage","in":["lost"]}]'::jsonb, 'lost', 'other', null),
  (50, '[{"field":"stage","in":["applied"]}]'::jsonb, 'applied', null, null),
  (51, '[{"field":"b2c_stage","in":["applied"]}]'::jsonb, 'applied', null, null),
  (52, '[{"field":"applied_at","present":true}]'::jsonb, 'applied', null, null),
  (60, '[{"field":"stage","in":["contacted","counselled"]}]'::jsonb, 'counselling', null, null),
  (61, '[{"field":"b2c_stage","in":["contacted","counselled"]}]'::jsonb, 'counselling', null, null),
  (70, '[{"field":"stage","in":["allocated","sent_to_partner","duplicate_at_partner","routed_to_partner","assigned"]}]'::jsonb, 'allocated', null, null),
  (71, '[{"field":"stage","in":["nurture","dormant"]}]'::jsonb, 'allocated', null, null),
  (72, '[{"field":"b2c_stage","in":["assigned"]}]'::jsonb, 'allocated', null, null),
  (80, '[{"field":"stage","in":["qualifying"]},{"field":"is_sales_ready","is_true":true}]'::jsonb, 'qualified', null, null),
  (81, '[{"field":"stage","in":["qualifying"]}]'::jsonb, 'qualifying', null, null),
  (90, '[{"field":"stage","in":["new"]}]'::jsonb, 'new', null, null),
  (91, '[{"field":"stage","empty":true}]'::jsonb, 'new', null, null)
) as v(priority, conditions, creator_stage, reason_category, flag)
where not exists (select 1 from inf.stage_mappings);
