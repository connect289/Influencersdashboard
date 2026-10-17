-- Contracts: clause versions and legal review, templates, contract versions hashed by the database, the legal-review
-- gate, negotiation (comments, change requests only on negotiable clauses), signing (service role only, one-time code,
-- attempts), countersign activating the deal, immutability, and who can see what.
begin;
\ir _helpers.psql
select plan(53);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('asha', array['super_admin'], true, true);
select tests.make_staff('fin', array['finance']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
update inf.creators set approved_at = now() where handle in ('riya', 'arjun');

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated, service_role;
create temporary table vals (label text primary key, v text);
grant select, insert, update on vals to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;

-- An agreed deal for Riya (as the deal-from-application path creates it).
insert into ids values ('deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Diwali deal', 'agreed', current_date, 'fixed_only', now();
insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, effective_from, state, decided_at)
select (select id from ids where label = 'deal'), 1, p.comp_config, inf.config_hash(p.comp_config), 'builder', now(), 'accepted', now()
  from inf.deal_presets p where p.key = 'fixed_only';
update inf.deals set current_version_id = (select id from inf.deal_versions where deal_id = (select id from ids where label = 'deal'))
 where id = (select id from ids where label = 'deal');

-- ---------------------------------------------------------------------------------------------------------------
-- Library
-- ---------------------------------------------------------------------------------------------------------------
select is((select count(*)::int from inf.clauses), 20, 'twenty seeded clauses');
select is((select count(*)::int from inf.clause_versions where reviewed_at is null), 20, 'all seeded clauses start unreviewed');
select is((select count(*)::int from inf.contract_templates where is_default), 1, 'one default template');
select ok((select bool_and(body::text like '%DRAFT%') from inf.clause_versions), 'every seed clause carries the draft marker');

select tests.as_person('mona');
select is(jsonb_array_length(inf.clause_library()), 20, 'manager reads the library');
select lives_ok($$ select inf.clause_save(jsonb_build_object('id', (select id from inf.clauses where key = 'conduct'), 'category', 'conduct',
  'title', 'Conduct and reputation', 'body', '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Be kind."}]}]}'::jsonb,
  'negotiable', true)) $$, 'editing a clause creates a version');
select is((select current_version from inf.clauses where key = 'conduct'), 2, 'current version is 2');
select is((select count(*)::int from inf.clause_versions v join inf.clauses c on c.id = v.clause_id where c.key = 'conduct'), 2, 'version 1 is kept');
select throws_ok($$ select inf.clause_mark_reviewed((select id from inf.clauses where key = 'conduct'), 2) $$, '42501', null, 'a manager cannot mark legal review');
select tests.as_person('fin');
select throws_ok($$ select inf.clause_save('{"key":"rogue","category":"other","title":"Rogue","body":{"type":"doc","content":[]}}') $$, '42501', null, 'finance cannot edit clauses');
select tests.as_person('riya');
select is(inf.clause_library(), '[]'::jsonb, 'creators do not read the library');
select tests.reset();
select throws_ok($$ update inf.clause_versions set body = '{"type":"doc","content":[]}' where version = 1 and clause_id = (select id from inf.clauses where key = 'conduct') $$,
                 '42501', null, 'a clause version''s text is immutable');
select tests.as_person('asha');
select lives_ok($$ select inf.clause_mark_reviewed((select id from inf.clauses where key = 'conduct'), 2) $$, 'a Super Admin marks the new version reviewed');

-- ---------------------------------------------------------------------------------------------------------------
-- Contract and versions
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
insert into ids select 'contract', inf.contract_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'),
  'template_id', (select id from inf.contract_templates where is_default)));
select throws_ok($$ select inf.contract_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'), 'template_id', (select id from inf.contract_templates where is_default))) $$,
                 '23505', null, 'one open contract per deal');
select throws_ok($$ select inf.contract_send((select id from ids where label = 'contract')) $$, '22023', null, 'cannot send without content');
insert into vals values ('content', jsonb_build_object('title', 'Creator Agreement', 'header', '[]'::jsonb, 'footer', '[]'::jsonb, 'sections', jsonb_build_array(
  jsonb_build_object('key', 'parties', 'number', 1, 'clause_id', (select id from inf.clauses where key = 'parties'), 'clause_version', 1, 'category', 'parties',
                     'title', 'Parties', 'negotiable', false, 'locked', true, 'amended', false, 'blocks', '[]'::jsonb),
  jsonb_build_object('key', 'conduct', 'number', 2, 'clause_id', (select id from inf.clauses where key = 'conduct'), 'clause_version', 2, 'category', 'conduct',
                     'title', 'Conduct', 'negotiable', true, 'locked', false, 'amended', false, 'blocks', '[]'::jsonb)))::text);
insert into ids select 'vm', inf.contract_version_add((select id from ids where label = 'contract'), (select v::jsonb from vals where label = 'content'),
  '<article>missing details</article>', '{}'::jsonb, null, '[]'::jsonb, array['creator.legal_name']);
select throws_ok($$ select inf.contract_send((select id from ids where label = 'contract')) $$, '22023', 'details are missing: creator.legal_name', 'blank required details block sending');
insert into ids select 'v1', inf.contract_version_add((select id from ids where label = 'contract'), (select v::jsonb from vals where label = 'content'),
  '<article><h1>Creator Agreement</h1><p>v1</p></article>', '{}'::jsonb);
select is((select sha256 from inf.contract_versions where id = (select id from ids where label = 'v1')),
          encode(sha256(convert_to('<article><h1>Creator Agreement</h1><p>v1</p></article>', 'UTF8')), 'hex'), 'the database hashes the HTML');
select tests.as_person('riya');
select is(inf.contract_detail((select id from ids where label = 'contract')), null, 'creators do not see drafts');
select tests.as_person('mona');
select throws_ok($$ select inf.contract_send((select id from ids where label = 'contract')) $$, '22023', 'contains 1 clauses not yet legally reviewed', 'the legal-review gate blocks unreviewed clauses');
select tests.reset();
update inf.clause_versions set reviewed_at = now() where clause_id = (select id from inf.clauses where key = 'parties');
select tests.as_person('mona');
select lives_ok($$ select inf.contract_send((select id from ids where label = 'contract')) $$, 'sent once every clause is reviewed');
select is((select status from inf.contracts where id = (select id from ids where label = 'contract')), 'sent', 'status sent');
select ok((select negotiation_deadline > now() from inf.contracts where id = (select id from ids where label = 'contract')), 'negotiation deadline set');

-- ---------------------------------------------------------------------------------------------------------------
-- Negotiation
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('arjun');
select is(inf.contract_detail((select id from ids where label = 'contract')), null, 'another creator cannot open it');
select throws_ok($$ select inf.contract_comment_add((select id from ids where label = 'contract'), 'parties', 'hi') $$, '42501', null, 'nor comment');
select tests.as_person('riya');
select is(inf.contract_detail((select id from ids where label = 'contract')) ->> 'side', 'creator', 'the creator opens it');
select lives_ok($$ select inf.contract_comment_add((select id from ids where label = 'contract'), 'parties', 'Please use my legal name.') $$, 'comment on a clause');
select tests.reset();
select is((select status from inf.contracts where id = (select id from ids where label = 'contract')), 'in_negotiation', 'a creator comment opens negotiation');
select tests.as_person('riya');
select throws_ok($$ select inf.change_request_create((select id from ids where label = 'contract'), '{"kind":"clause","clause_key":"parties","proposed_body":{"type":"doc","content":[]}}') $$,
                 '22023', 'this clause is not negotiable', 'no edits to non-negotiable clauses');
insert into ids select 'req', inf.change_request_create((select id from ids where label = 'contract'),
  '{"kind":"clause","clause_key":"conduct","proposed_body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Be fair."}]}]},"note":"Softer"}');
select throws_ok($$ select inf.change_request_create((select id from ids where label = 'contract'), '{"kind":"clause","clause_key":"conduct","proposed_body":{"type":"doc","content":[]}}') $$,
                 '22023', 'a request for this is already pending', 'one pending request per clause');
insert into ids select 'comp', inf.change_request_create((select id from ids where label = 'contract'),
  '{"kind":"compensation","proposed_terms":{"fixed_fee_paise":2000000},"note":"20k please"}');
select tests.as_person('mona');
select throws_ok($$ select inf.contract_set_ready((select id from ids where label = 'contract')) $$, '22023', null, 'pending requests block "ready to sign"');
select lives_ok($$ select inf.change_request_decide((select id from ids where label = 'req'), 'rejected', 'We keep the standard wording.') $$, 'staff reject a request with a reason');
-- Accept the compensation counter: the deal's terms are replaced by a new accepted version.
insert into ids select 'dv2', inf.deal_version_from_counter((select id from ids where label = 'comp'),
  jsonb_set((select comp_config from inf.deal_presets where key = 'fixed_only'), '{fixed,0,amount_paise}', '2000000'));
select is((select current_version_id from inf.deals where id = (select id from ids where label = 'deal')), (select id from ids where label = 'dv2'), 'deal terms replaced by the counter-offer');
select is((select state from inf.deal_versions where deal_id = (select id from ids where label = 'deal') and version = 1), 'superseded', 'the old terms are superseded');
insert into ids select 'v2', inf.contract_version_add((select id from ids where label = 'contract'), (select v::jsonb from vals where label = 'content'),
  '<article><h1>Creator Agreement</h1><p>v2</p></article>', '{}'::jsonb, 'Fee 20k', jsonb_build_array(jsonb_build_object('id', (select id from ids where label = 'comp'), 'status', 'accepted')));
select tests.reset();
select is((select status from inf.contract_change_requests where id = (select id from ids where label = 'comp')), 'accepted', 'the request is resolved in the new version');
select tests.as_person('mona');
select lives_ok($$ select inf.contract_set_ready((select id from ids where label = 'contract')) $$, 'ready to sign');
select tests.reset();
select throws_ok($$ update inf.contract_versions set html = 'x' where id = (select id from ids where label = 'v1') $$, '42501', null, 'versions are immutable');

-- ---------------------------------------------------------------------------------------------------------------
-- Signing
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.contract_sign_code_issue((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), 'email') $$,
                 '42501', null, 'signing codes are issued by the service role only');
select tests.act_as_service();
select is(inf.contract_signer_role((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'arjun')), null, 'another creator cannot sign');
select is(inf.contract_signer_role((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'asha')), null, 'the signatory waits for the creator');
insert into vals select 'code', inf.contract_sign_code_issue((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), 'email') ->> 'code';
select is(inf.contract_sign_code_issue((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), 'email') ->> 'error', 'cooldown', 'resend is rate-limited');
select is(inf.contract_sign((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), (select id from ids where label = 'v2'),
          (select sha256 from inf.contract_versions where id = (select id from ids where label = 'v1')), 'Riya Sharma', 1, (select v from vals where label = 'code'), '1.2.3.4', 'UA') ->> 'error',
          'changed', 'signing an outdated hash is refused');
select is(inf.contract_sign((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), (select id from ids where label = 'v2'),
          (select sha256 from inf.contract_versions where id = (select id from ids where label = 'v2')), 'Riya Sharma', 1, '000000', '1.2.3.4', 'UA') ->> 'error',
          'wrong_code', 'a wrong code counts an attempt');
select is(inf.contract_sign((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'riya'), (select id from ids where label = 'v2'),
          (select sha256 from inf.contract_versions where id = (select id from ids where label = 'v2')), 'Riya Sharma', 1, (select v from vals where label = 'code'), '1.2.3.4', 'UA') ->> 'ok',
          'true', 'the creator signs with the code');
select tests.reset();
select is((select status from inf.contracts where id = (select id from ids where label = 'contract')), 'signed_by_creator', 'signed by the creator');
select is((select document_sha256 from inf.signatures where signer_role = 'creator'), (select sha256 from inf.contract_versions where id = (select id from ids where label = 'v2')), 'the signature records the document hash');
select tests.as_person('mona');
select throws_ok($$ select inf.contract_version_add((select id from ids where label = 'contract'), (select v::jsonb from vals where label = 'content'), '<article>changed after signing</article>', '{}'::jsonb) $$,
                 '22023', null, 'no new version after a signature');
select tests.act_as_service();
insert into vals select 'code2', inf.contract_sign_code_issue((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'asha'), 'email') ->> 'code';
select is(inf.contract_sign((select id from ids where label = 'contract'), (select user_id from tests.people where label = 'asha'), (select id from ids where label = 'v2'),
          (select sha256 from inf.contract_versions where id = (select id from ids where label = 'v2')), 'Asha Admin', 1, (select v from vals where label = 'code2'), null, 'UA') ->> 'role',
          'signatory', 'the Authorised Signatory countersigns');
select tests.reset();
select is((select c.status || '/' || d.status from inf.contracts c join inf.deals d on d.id = c.deal_id where c.id = (select id from ids where label = 'contract')),
          'active/active', 'countersigning activates the contract and the deal');
select is((select count(*)::int from inf.jobs where kind = 'contract.finalize'), 1, 'the final PDF is queued');
select throws_ok($$ delete from inf.signatures $$, '42501', null, 'signatures are append-only');
select tests.as_person('mona');
select is((inf.contract_integrity((select id from ids where label = 'contract')) ->> 'ok')::boolean, true, 'integrity check passes');

-- Amendments: the service role (or staff) drafts one against the active contract; a second original is refused.
select tests.act_as_service();
select throws_ok($$ select inf.contract_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'))) $$, '22023',
                 'this deal has an active contract: amend it instead', 'one active contract per deal');
insert into ids select 'amend', inf.contract_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'), 'parent_contract_id', (select id from ids where label = 'contract')));
select tests.reset();
select is((select kind || '/' || (template_id = (select id from inf.contract_templates where is_default))::text from inf.contracts where id = (select id from ids where label = 'amend')),
          'amendment/true', 'an amendment uses the default template when none is given');

select * from finish();
rollback;
