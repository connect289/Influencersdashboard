-- M7e: Addendum 1 §3: the B2C CRM's stages join the stage list as "held by B2C", outside the partner funnel rank.
update b2b.settings s
   set value = s.value || (select coalesce(jsonb_agg(jsonb_build_object('key', k, 'rank', null, 'group', 'held_by_b2c') order by o), '[]')
                             from unnest(array['nurture', 'assigned', 'dormant', 'routed_to_partner']) with ordinality as x(k, o)
                            where not exists (select 1 from jsonb_array_elements(s.value) e where e ->> 'key' = x.k))
 where s.key = 'stages';
