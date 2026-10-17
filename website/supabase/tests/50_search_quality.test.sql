-- Search quality suite (spec 6.4, Phase 4): real-world queries against the real catalogue (seeded locally). Each case
-- states what a correct answer looks like: resolution, the top result, minimum result counts, or "no dead end".
-- Skipped on databases without the catalogue (the production-schema replica has no catalogue rows).
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table cases (q text, expect jsonb, name text) on commit drop;

insert into cases values
  -- exact programme / specialisation
  ('mba', '{"programme": ["mba"], "min_total": 200}', 'programme abbreviation'),
  ('Master of Business Administration', '{"programme": ["mba"]}', 'programme full name'),
  ('m.b.a', '{"programme": ["mba"]}', 'dotted abbreviation'),
  ('mba in marketing', '{"programme": ["mba"], "spec": ["marketing"], "top_group": "mba:marketing"}', 'programme + specialisation'),
  ('mba hr', '{"programme": ["mba"], "spec": ["human-resource-management"], "top_group": "mba:human-resource-management"}', 'HR abbreviation'),
  ('mba human resources', '{"spec": ["human-resource-management"]}', 'HR long form'),
  ('mba finance', '{"top_group": "mba:finance"}', 'finance group first'),
  ('bca data science', '{"programme": ["bca"], "spec": ["data-science"]}', 'BCA specialisation'),
  ('mca ai', '{"programme": ["mca"], "spec": ["ai-ml"]}', 'AI abbreviation'),
  ('ma english', '{"programme": ["ma"], "spec": ["english"], "top_group": "ma:english"}', 'MA subject'),
  ('digital marketing', '{"spec": ["digital-marketing"], "min_total": 10}', 'specialisation alone'),
  ('supply chain', '{"spec": ["supply-chain-management"]}', 'partial specialisation name'),
  ('pgdm', '{"programme": ["pgdm"]}', 'PGDM'),
  ('bba mba', '{"programme": ["bba-mba"]}', 'integrated degree'),
  -- spacing, Hinglish, typos
  ('b com', '{"programme": ["bcom"]}', 'spaced B.Com'),
  ('bcom', '{"programme": ["bcom"]}', 'compact B.Com'),
  ('mba online karna hai', '{"programme": ["mba"], "mode": ["Online"]}', 'Hinglish'),
  ('mujhe bca karna hai', '{"programme": ["bca"]}', 'Hinglish prefix'),
  ('markting', '{"spec": ["marketing"], "corrected": true}', 'typo: markting'),
  ('data sciense', '{"spec": ["data-science"], "corrected": true}', 'typo: two-word phrase'),
  ('finanace', '{"spec": ["finance"], "corrected": true}', 'typo: finanace'),
  ('amitty', '{"university_any": true, "corrected": true}', 'typo: university'),
  -- universities
  ('amity mba', '{"programme": ["mba"], "university_any": true}', 'university + programme'),
  ('nmims', '{"university_any": true, "min_total": 1}', 'university short name'),
  ('lovely professional university', '{"university_any": true}', 'university full name'),
  ('manipal', '{"university_count": 2}', 'ambiguous name matches both Manipal universities'),
  -- levels / modes / categories
  ('pg diploma', '{"level": ["pg_diploma"]}', 'level phrase'),
  ('distance mba', '{"programme": ["mba"], "mode": ["ODL"]}', 'distance = ODL'),
  ('commerce', '{"category": ["commerce"]}', 'category'),
  -- no dead ends
  ('qwzxv', '{"zero_with_closest": true}', 'gibberish → closest matches'),
  ('mba wizardry', '{"programme": ["mba"], "ignored": ["wizardry"], "min_total": 200}', 'unknown word ignored, not fatal');

do $$
declare c record; res jsonb; ok boolean; g text;
begin
  if (select count(*) from public.web_offering_search where visible) < 100 then
    insert into r values (true, 'skipped: no catalogue in this database');
    return;
  end if;
  for c in select * from cases loop
    res := public.web_search(jsonb_build_object('q', c.q));
    ok := true;
    if c.expect ? 'programme' then ok := ok and (res->'resolved'->'programme') @> (c.expect->'programme'); end if;
    if c.expect ? 'spec' then ok := ok and (res->'resolved'->'specialisation') @> (c.expect->'spec'); end if;
    if c.expect ? 'mode' then ok := ok and (res->'resolved'->'mode') @> (c.expect->'mode'); end if;
    if c.expect ? 'level' then ok := ok and (res->'resolved'->'level') @> (c.expect->'level'); end if;
    if c.expect ? 'category' then ok := ok and (res->'resolved'->'category') @> (c.expect->'category'); end if;
    if c.expect ? 'university_any' then ok := ok and jsonb_array_length(res->'resolved'->'university') > 0; end if;
    if c.expect ? 'university_count' then ok := ok and jsonb_array_length(res->'resolved'->'university') = (c.expect->>'university_count')::int; end if;
    if c.expect ? 'corrected' then ok := ok and jsonb_array_length(res->'resolved'->'corrected') > 0; end if;
    if c.expect ? 'ignored' then ok := ok and (res->'resolved'->'ignored_words') @> (c.expect->'ignored'); end if;
    if c.expect ? 'min_total' then ok := ok and (res->>'total')::int >= (c.expect->>'min_total')::int; end if;
    if c.expect ? 'top_group' then
      g := res->'items'->0->>'key';
      ok := ok and g = c.expect->>'top_group';
    end if;
    if c.expect ? 'zero_with_closest' then ok := ok and (res->>'total')::int = 0 and jsonb_array_length(res->'closest') > 0; end if;
    if not (c.expect ? 'zero_with_closest') then ok := ok and (res->>'total')::int > 0; end if;
    insert into r values (ok, format('%s: “%s”', c.name, c.q) || case when not ok then ' → ' || left((res->'resolved')::text, 200) || ' top=' || coalesce(res->'items'->0->>'key', '-') else '' end);
  end loop;
end $$;

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
