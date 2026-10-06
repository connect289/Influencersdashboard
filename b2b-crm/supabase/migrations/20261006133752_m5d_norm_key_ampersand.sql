-- M5d: "Analytics & Data Science" and "Analytics and Data Science" compare equal when matching programmes.
create or replace function b2b.norm_key(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select lower(regexp_replace(replace(coalesce(p, ''), '&', 'and'), '[^a-zA-Z0-9]', '', 'g'));
$$;
