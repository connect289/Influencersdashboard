-- =====================================================================================================================
-- web12 · Catalogue sync: the website's programme list follows the shared catalogue (the same rows Witty and the CRMs
-- read) whatever changes it — Witty's loader, the CRMs, a person in the Supabase table editor (D-081).
--   1. The change detector hashes the CONTENT of every catalogue programme, university and synonym row. Before, it
--      trusted updated_at / catalog_version, which only the official loader maintains, so a direct edit (e.g. a fee fixed
--      in the table editor) was never picked up. Cost: ~10 ms at 715 rows, ~75 ms at 10,000, once a minute.
--   2. University names: profiles that still carry an unedited copy of the catalogue name follow catalogue renames;
--      names an editor changed on purpose (e.g. "NMIMS") stay.
--   3. A new catalogue row the website cannot map yet (brand-new course) stays hidden (spec 5.3) but is never silent:
--      super admins get one email per new batch, and health/admin show the count.
-- Website objects only; no shared object is touched.
-- =====================================================================================================================

create or replace function public.web_catalog_fingerprint()
returns text language sql stable security definer set search_path = '' as $$
  select md5(concat_ws('|',
    (select md5(coalesce(string_agg(md5(c::text), '' order by c.id), '')) from public.catalog_programs c),
    (select md5(coalesce(string_agg(md5(u::text), '' order by u.id), '')) from public.catalog_universities u),
    (select md5(coalesce(string_agg(md5(s::text), '' order by s::text), '')) from public.catalog_synonyms s),
    (select value::text from public.w2_meta where key = 'catalog_version'),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_offering_map),
    (select coalesce(max(updated_at)::text, '') from public.web_university_profiles),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_programmes),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_specialisations)))
$$;

alter table public.web_university_profiles add column if not exists catalogue_name_seen text;
update public.web_university_profiles p set catalogue_name_seen = u.name
  from public.catalog_universities u where u.id = p.catalog_university_id and p.catalogue_name_seen is null;

create or replace function public.web_university_names_sync()
returns integer language sql volatile security definer set search_path = '' as $$
  with ch as (
    update public.web_university_profiles p
       set display_name = case when p.display_name is not distinct from p.catalogue_name_seen then u.name else p.display_name end,
           catalogue_name_seen = u.name
      from public.catalog_universities u
     where u.id = p.catalog_university_id and p.catalogue_name_seen is distinct from u.name
    returning 1)
  select count(*)::integer from ch
$$;

alter table public.web_catalog_state add column if not exists unmapped_alerted bigint[] not null default '{}';

create or replace function public.web_catalog_unmapped_alert()
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare v_now bigint[]; v_old bigint[]; v_new bigint[]; v_to text[];
begin
  select coalesce(array_agg(o.id order by o.id), '{}') into v_now from public.web_offering_search o where o.hidden_reason = 'unmapped';
  select unmapped_alerted into v_old from public.web_catalog_state where id = 1;
  v_new := array(select x from unnest(v_now) x except select y from unnest(coalesce(v_old, '{}')) y order by 1);
  update public.web_catalog_state set unmapped_alerted = v_now where id = 1;
  if cardinality(v_new) = 0 then return 0; end if;
  select array_agg(email order by email) into v_to from public.web_admin_users where role = 'super_admin' and active;
  if v_to is null then return cardinality(v_new); end if;
  perform public.web_outbox_enqueue('catalog_alert', 'catalog_alert:' || md5(array_to_string(v_new, ',')),
    jsonb_build_object('to', to_jsonb(v_to), 'count', cardinality(v_new), 'total_unmapped', cardinality(v_now),
      'examples', (select coalesce(jsonb_agg(jsonb_build_object('programme', c.program_name, 'course', c.course, 'university', u.name)), '[]')
                     from (select * from unnest(v_new) id limit 10) n
                     join public.catalog_programs c on c.id = n.id join public.catalog_universities u on u.id = c.university_id)));
  return cardinality(v_new);
end $$;

create or replace function public.web_refresh_read_model()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_map jsonb; t0 timestamptz := clock_timestamp(); v_populated boolean;
begin
  v_map := public.web_tax_automap(false);
  perform public.web_university_names_sync();
  select relispopulated into v_populated from pg_class where oid = 'public.web_offering_search'::regclass;
  if v_populated then
    refresh materialized view concurrently public.web_offering_search;
    refresh materialized view concurrently public.web_facet_values;
  else
    refresh materialized view public.web_offering_search;
    refresh materialized view public.web_facet_values;
  end if;
  insert into public.web_catalog_state (id, fingerprint, refreshed_at, last_checked_at, last_result)
  values (1, public.web_catalog_fingerprint(), now(), now(), v_map)
  on conflict (id) do update set fingerprint = excluded.fingerprint, refreshed_at = now(), last_checked_at = now(),
    last_result = excluded.last_result;
  perform public.web_outbox_enqueue('revalidate', 'revalidate:catalog:' || public.web_catalog_fingerprint(),
    jsonb_build_object('tags', jsonb_build_array('catalog')));
  perform public.web_catalog_unmapped_alert();
  return v_map || jsonb_build_object('refresh_ms', round(extract(epoch from clock_timestamp() - t0) * 1000),
    'visible', (select count(*) from public.web_offering_search where visible));
end $$;

create or replace function public.web_health()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'db', true,
    'at', now(),
    'catalogue_rows', (select count(*) from public.catalog_programs where active),
    'outbox_pending', (select count(*) from public.web_outbox where status in ('pending', 'processing')),
    'outbox_dead', (select count(*) from public.web_outbox where status = 'dead'),
    'outbox_oldest_pending_seconds', (select coalesce(extract(epoch from now() - min(created_at))::int, 0) from public.web_outbox where status = 'pending'),
    -- catalogue sync (web12): when the poll last ran and last rebuilt the website's copy, and what is waiting for a mapping
    'catalog_checked_seconds_ago', (select extract(epoch from now() - last_checked_at)::int from public.web_catalog_state where id = 1),
    'catalog_refreshed_at', (select refreshed_at from public.web_catalog_state where id = 1),
    'catalog_unmapped', (select count(*) from public.web_offering_search where hidden_reason = 'unmapped')
  );
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_catalog_fingerprint()', 'public.web_university_names_sync()', 'public.web_catalog_unmapped_alert()',
                           'public.web_refresh_read_model()', 'public.web_health()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
