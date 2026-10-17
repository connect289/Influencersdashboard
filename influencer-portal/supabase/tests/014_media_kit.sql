-- Media kit: public only when enabled and approved; never contact details; rates only when the creator opts in;
-- internal kit for the creator, staff and agencies with "view".
begin;
\ir _helpers.psql
select plan(13);

select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_staff('fin', array['finance']);
select tests.make_staff('view', array['viewer']);
update inf.creators set approved_at = now(), bio = 'MBA prep', phone_e164 = '+919811112222' where handle = 'riya';
insert into inf.creator_platforms (creator_id, platform, url, handle, followers) select creator_id, 'instagram', 'https://instagram.com/riya', 'riya', 50000 from tests.people where label = 'riya';
insert into inf.creator_rate_cards (creator_id, platform, format, suggested_paise) select creator_id, 'instagram', 'reel', 1500000 from tests.people where label = 'riya';
create temporary table ids as select label, creator_id from tests.people where creator_id is not null;
grant select on ids to authenticated, anon;

select tests.act_as_anon();
select is(inf.media_kit_public('riya'), null, 'no public kit until the creator enables it');

select tests.as_person('riya');
select lives_ok($$ select inf.media_kit_settings((select creator_id from ids where label = 'riya'), true, false) $$, 'creator enables the public page');
select throws_ok($$ select inf.media_kit_settings((select creator_id from ids where label = 'arjun'), true, true) $$, '42501', null, 'not for another creator');
select is((inf.media_kit((select creator_id from ids where label = 'riya')) -> 'rates' -> 0 ->> 'suggested_paise')::bigint, 1500000::bigint, 'internal kit includes rates');

select tests.act_as_anon();
select is(inf.media_kit_public('Riya') ->> 'total_followers', '50000', 'public kit by handle (case-insensitive)');
select is(inf.media_kit_public('riya') -> 'rates', '[]'::jsonb, 'no rates unless the creator opts in');
select ok(inf.media_kit_public('riya')::text !~ '9811112222|creator\.test', 'no phone or email in the public kit');
select throws_ok($$ select inf.media_kit((select creator_id from ids where label = 'riya')) $$, '42501', null, 'anon cannot read the internal kit');
select is(inf.media_kit_public('arjun'), null, 'unapproved creators have no public kit');

select tests.as_person('riya');
select inf.media_kit_settings((select creator_id from ids where label = 'riya'), null, true);
select throws_ok($$ select inf.avatar_set((select creator_id from ids where label = 'riya'), '../../etc/x.png') $$, '22023', null, 'avatar paths are confined to the creator''s folder');
select tests.act_as_anon();
select is(jsonb_array_length(inf.media_kit_public('riya') -> 'rates'), 1, 'rates appear once opted in');

select tests.as_person('fin');
select ok(inf.media_kit((select creator_id from ids where label = 'riya')) is not null, 'finance (creator.read) can open the internal kit');
select tests.as_person('view');
select throws_ok($$ select inf.media_kit((select creator_id from ids where label = 'riya')) $$, '42501', null, 'viewer cannot');

select * from finish();
rollback;
