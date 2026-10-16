-- B2C CRM b44: the Programme page's filter choices also list the course families (MBA, BBA, BCA…). Staging first. Idempotent.
create or replace function b2c.programme_facets() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'universities', (select coalesce(jsonb_agg(distinct university), '[]') from b2c.programme_cache where active),
    'courses', (select coalesce(jsonb_agg(distinct course), '[]') from b2c.programme_cache where active and course is not null),
    'specializations', (select coalesce(jsonb_agg(distinct specialization), '[]') from b2c.programme_cache where active and specialization is not null),
    'levels', (select coalesce(jsonb_agg(distinct level), '[]') from b2c.programme_cache where active and level is not null),
    'modes', (select coalesce(jsonb_agg(distinct mode), '[]') from b2c.programme_cache where active and mode is not null),
    'intakes', (select coalesce(jsonb_agg(distinct i), '[]') from b2c.programme_cache, unnest(intakes) i where active),
    'fee', (select jsonb_build_object('min', min(coalesce(fee_total, fee_yearly)), 'max', max(coalesce(fee_total, fee_yearly))) from b2c.programme_cache where active),
    'duration', (select jsonb_build_object('min', min(duration_months), 'max', max(duration_months)) from b2c.programme_cache where active));
end $f$;
grant execute on function b2c.programme_facets() to authenticated;
revoke execute on all functions in schema b2c from public, anon;
