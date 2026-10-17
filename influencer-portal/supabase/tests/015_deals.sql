-- Deals: config validation (SQL mirror of the zod rules), presets, building, proposing, accepting and declining,
-- immutable versions, amendments, status moves, agencies, deal creation from an accepted offer, TDS table access.
begin;
\ir _helpers.psql
select plan(53);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('rev', array['content_reviewer']);
select tests.make_staff('fin', array['finance']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set approved_at = now() where handle in ('riya', 'arjun');

-- An agency user linked to Riya with the "negotiate" grant, and one linked to Arjun with "view" only.
insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000a001', 'Acme Talent'), ('00000000-0000-0000-0000-00000000a002', 'Zen Mgmt');
do $$
declare v_uid uuid; v_sid uuid;
begin
  v_uid := tests.create_user('ola@acme.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000a001', 'ola@acme.test', 'Ola', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('ola', v_uid, v_sid, null);
  v_uid := tests.create_user('zed@zen.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000a002', 'zed@zen.test', 'Zed', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('zed', v_uid, v_sid, null);
end $$;
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_negotiate_sign)
select '00000000-0000-0000-0000-00000000a001', creator_id, 'active', true, true from tests.people where label = 'riya';
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_negotiate_sign)
select '00000000-0000-0000-0000-00000000a002', creator_id, 'active', true, false from tests.people where label = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
create temporary table cfg (label text primary key, c jsonb);
grant select on cfg to authenticated, service_role;
insert into cfg select 'fixed', comp_config from inf.deal_presets where key = 'fixed_only';
insert into cfg select 'hybrid', comp_config from inf.deal_presets where key = 'fixed_plus_commission';

-- ---------------------------------------------------------------------------------------------------------------
-- Validation (same messages as lib/compensation/schema.ts)
-- ---------------------------------------------------------------------------------------------------------------
select is((select count(*)::int from inf.deal_presets where is_system), 3, 'three system presets generated from TypeScript');
select is(inf.comp_config_errors((select c from cfg where label = 'hybrid')), '{}'::text[], 'a preset is valid');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{fixed,0,milestones,0,share,pct}', '40')),
          array['milestones_not_100'], 'milestone shares must add up to 100%');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{fixed,0,milestones,0,share}', '{"type":"amount","amount_paise":100}')),
          array['milestones_mixed'], 'milestone kinds cannot be mixed');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{commission,1}', (select c -> 'commission' -> 0 from cfg where label = 'hybrid'))),
          array['duplicate_id:commission'], 'ids are unique');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{commission,0,basis,pct}', '10.123')),
          array['two_decimals'], 'percentages have at most two decimals');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{commission,0,slabs}',
          '{"period":"deal","mode":"marginal","tiers":[{"from":2,"pct":1},{"from":2}]}')),
          array['tiers_start_at_1', 'tiers_ascending', 'tier_pct'], 'slab tiers are checked');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{recoupment}', '{"mode":"full","fixed":["nope"]}')),
          array['unknown_fixed:nope'], 'recoupment references real fixed components');
select is(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'fixed'), '{recoupment}', '{"mode":"full","fixed":[]}')),
          array['recoupment_needs_commission'], 'recoupment needs commission');
select ok(cardinality(inf.comp_config_errors((select c from cfg where label = 'hybrid') || '{"extra":1}')) = 1, 'unknown properties are refused');
select ok(cardinality(inf.comp_config_errors(jsonb_set((select c from cfg where label = 'hybrid'), '{commission,0,basis}', '{"type":"flat_per_lead"}'))) = 1,
          'a basis without its amount is refused');
select throws_ok($$ insert into inf.deal_presets (name, comp_config) values ('Broken', '{"schema_version":2}') $$, '23514', null, 'the check constraint guards stored configs');

-- ---------------------------------------------------------------------------------------------------------------
-- Presets
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select is(jsonb_array_length(inf.deal_presets_list()), 3, 'staff list presets');
insert into ids select 'preset', inf.deal_preset_save(jsonb_build_object('name', 'MBA reel pack', 'comp_config', (select c from cfg where label = 'hybrid')));
select throws_ok($$ select inf.deal_preset_save(jsonb_build_object('id', (select id from inf.deal_presets where key = 'fixed_only'), 'name', 'X', 'comp_config', (select c from cfg where label = 'fixed'))) $$,
                 '22023', null, 'system presets cannot be edited');
select throws_ok($$ select inf.deal_preset_save(jsonb_build_object('name', 'mba reel pack', 'comp_config', (select c from cfg where label = 'fixed'))) $$,
                 '23505', null, 'preset names are unique');
select tests.as_person('rev');
select throws_ok($$ select inf.deal_preset_save(jsonb_build_object('name', 'Rogue', 'comp_config', (select c from cfg where label = 'fixed'))) $$, '42501', null, 'content reviewer cannot save presets');
select tests.as_person('riya');
select is(jsonb_array_length(inf.deal_presets_list()), 0, 'creators do not list presets');

-- ---------------------------------------------------------------------------------------------------------------
-- Build, propose, decline, revise, accept
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
insert into ids select 'deal', inf.deal_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'title', 'Always-on MBA deal',
  'starts_on', current_date::text, 'ends_on', (current_date + 90)::text, 'comp_config', (select c from cfg where label = 'fixed'),
  'internal_notes', 'Max 20k'));
select is((select status || '/' || deal_model from inf.deals where id = (select id from ids where label = 'deal')), 'draft/fixed_only', 'draft deal with its model');
select throws_ok($$ select inf.deal_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'title', 'Bad', 'starts_on', current_date::text, 'comp_config', '{"schema_version":1,"fixed":"x"}'::jsonb)) $$,
                 '22023', null, 'invalid config refused');
select tests.as_person('riya');
select throws_ok($$ select inf.deal_create(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'title', 'Mine', 'starts_on', current_date::text, 'comp_config', (select c from cfg where label = 'fixed'))) $$,
                 '42501', null, 'creators cannot create deals');
select is(inf.deal_detail((select id from ids where label = 'deal')) ->> 'status', 'draft', 'creator can open the deal record');
select is(jsonb_array_length(inf.my_deals((select id from ids where label = 'riya'))), 0, 'but drafts are not in My deals');
select is((select count(*)::int from inf.deals), 0, 'deals table returns nothing to creators');

select tests.as_person('mona');
select lives_ok($$ select inf.deal_update((select id from ids where label = 'deal'), jsonb_build_object('comp_config', (select c from cfg where label = 'hybrid'))) $$, 'staff revise the draft');
insert into ids select 'v1', inf.deal_propose((select id from ids where label = 'deal'));
select is((select status || '/' || coalesce(draft_config::text, 'none') from inf.deals where id = (select id from ids where label = 'deal')), 'proposed/none', 'proposed; working copy cleared');
select is((select to_char(effective_from at time zone 'Asia/Kolkata', 'HH24:MI') from inf.deal_versions where id = (select id from ids where label = 'v1')), '00:00', 'first version starts at midnight IST');
select throws_ok($$ select inf.deal_update((select id from ids where label = 'deal'), jsonb_build_object('ends_on', (current_date + 120)::text)) $$, '22023', null, 'dates are fixed while proposed');

select tests.as_person('riya');
select is(inf.deal_detail((select id from ids where label = 'deal')) ? 'internal_notes', false, 'creator never sees internal notes');
select throws_ok($$ select inf.deal_version_respond((select id from ids where label = 'v1'), false, ' ') $$, '22023', null, 'declining needs a reason');
select lives_ok($$ select inf.deal_version_respond((select id from ids where label = 'v1'), false, 'Need 60/40 on milestones') $$, 'creator declines');
select tests.as_person('mona');
select is((select status || '/' || (draft_config is not null)::text from inf.deals where id = (select id from ids where label = 'deal')), 'negotiating/true', 'negotiating, terms back in the working copy');
insert into ids select 'v2', inf.deal_propose((select id from ids where label = 'deal'), null, 'Revised');
select tests.as_person('zed');
select is(inf.deal_detail((select id from ids where label = 'deal')), null, 'an agency with only the view grant cannot open the deal');
select throws_ok($$ select inf.deal_version_respond((select id from ids where label = 'v2'), true) $$, '42501', null, 'nor accept it');
select tests.as_person('ola');
select lives_ok($$ select inf.deal_version_respond((select id from ids where label = 'v2'), true) $$, 'the negotiating agency accepts for the creator');
select tests.reset();
select is((select d.status || '/' || (d.current_version_id = (select id from ids where label = 'v2'))::text || '/' || d.deal_model from inf.deals d where d.id = (select id from ids where label = 'deal')),
          'agreed/true/hybrid', 'agreed on version 2');

-- Versions are immutable.
select throws_ok($$ update inf.deal_versions set comp_config = (select c from cfg where label = 'fixed'), config_hash = 'x' where id = (select id from ids where label = 'v2') $$,
                 '42501', null, 'a version''s terms cannot change');
select throws_ok($$ update inf.deal_versions set state = 'withdrawn' where id = (select id from ids where label = 'v2') $$, '42501', null, 'nor its decision');
select throws_ok($$ delete from inf.deal_versions where id = (select id from ids where label = 'v1') $$, '42501', null, 'versions cannot be deleted');

-- ---------------------------------------------------------------------------------------------------------------
-- Amendments and status
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.deal_propose((select id from ids where label = 'deal')) $$, '22023', null, 'nothing to amend without a working copy');
select inf.deal_update((select id from ids where label = 'deal'), jsonb_build_object('comp_config', (select c from cfg where label = 'hybrid')));
select throws_ok($$ select inf.deal_propose((select id from ids where label = 'deal'), now() + interval '1 day') $$, '22023', null, 'unchanged terms are not an amendment');
select inf.deal_update((select id from ids where label = 'deal'), jsonb_build_object('comp_config',
  jsonb_set((select c from cfg where label = 'hybrid'), '{fixed,0,amount_paise}', '2000000')));
select throws_ok($$ select inf.deal_propose((select id from ids where label = 'deal'), now() - interval '400 days') $$, '22023', null, 'an amendment takes effect after the current terms');
insert into ids select 'v3', inf.deal_propose((select id from ids where label = 'deal'), now() + interval '1 day', 'Fee raised');
select is((select origin from inf.deal_versions where id = (select id from ids where label = 'v3')), 'amendment', 'recorded as an amendment');
select tests.as_person('riya');
select lives_ok($$ select inf.deal_version_respond((select id from ids where label = 'v3'), true) $$, 'creator accepts the amendment');
select is(jsonb_array_length(inf.my_deals((select id from ids where label = 'riya'))), 1, 'the deal is in My deals');
select tests.as_person('mona');
select throws_ok($$ select inf.deal_set_status((select id from ids where label = 'deal'), 'active') $$, '22023', null, 'manual activation needs a reason');
select lives_ok($$ select inf.deal_set_status((select id from ids where label = 'deal'), 'active', 'Signed on paper') $$, 'activated with a reason');
select throws_ok($$ select inf.deal_set_status((select id from ids where label = 'deal'), 'draft') $$, '22023', null, 'invalid moves refused');

-- ---------------------------------------------------------------------------------------------------------------
-- From an accepted campaign offer
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
insert into ids select 'camp', inf.campaign_save('{"name":"Diwali push","objective":"leads"}');
select tests.reset();
insert into inf.campaign_applications (id, campaign_id, creator_id, status, accepted_terms, decided_at, submitted_by)
values ('00000000-0000-0000-0000-0000000aa001', (select id from ids where label = 'camp'), (select id from ids where label = 'arjun'), 'accepted',
        '{"deal_type":"fixed","fixed_fee_paise":1000000}', now(), (select user_id from tests.people where label = 'arjun'));
select tests.as_person('mona');
select throws_ok($$ select inf.deal_from_application('00000000-0000-0000-0000-0000000aa001', (select c from cfg where label = 'fixed')) $$, '42501', null, 'only the service role creates deals from applications');
select tests.act_as_service();
insert into ids select 'appdeal', inf.deal_from_application('00000000-0000-0000-0000-0000000aa001', (select c from cfg where label = 'fixed'));
select is(inf.deal_from_application('00000000-0000-0000-0000-0000000aa001', (select c from cfg where label = 'fixed')), (select id from ids where label = 'appdeal'), 'idempotent per application');
select tests.reset();
select is((select d.status || '/' || v.state || '/' || v.origin from inf.deals d join inf.deal_versions v on v.id = d.current_version_id where d.id = (select id from ids where label = 'appdeal')),
          'agreed/accepted/application', 'created agreed, with the accepted version');

-- TDS table
select tests.as_person('riya');
select is(jsonb_array_length(inf.tds_sections_list()), 3, 'creators can read the TDS rates (public law)');
select is(inf.commission_estimate((select id from ids where label = 'camp')), null, 'but never Eduwit''s commission');
select tests.as_person('mona');
select throws_ok($$ select inf.tds_section_save('{"code":"194C","label":"Contract","rate_bps":100,"no_pan_rate_bps":2000,"components":["fixed_fee"]}') $$, '42501', null, 'only Finance edits TDS sections');

select * from finish();
rollback;
