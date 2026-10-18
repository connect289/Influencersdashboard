-- Phase 2.6: media kit (spec 7 "auto-generated media kit, a shareable PDF and a web page, from profile data").
-- Two projections of the same profile data:
--   * media_kit(creator): for the creator, staff with creator.read and agencies with "view" (includes the rate card);
--   * media_kit_public(handle): anyone, only when the creator turned on their public page; rates only if the creator
--     chose to show them. Neither ever includes email, phone, KYC or contact hashes.

alter table inf.creators add column media_kit_show_rates boolean not null default false;

create or replace function inf.media_kit_data(p_creator uuid, p_rates boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'creator_id', c.id, 'display_name', c.display_name, 'handle', c.handle, 'bio', c.bio, 'city', c.city, 'state', c.state,
    'languages', to_jsonb(c.languages), 'niches', to_jsonb(c.niches), 'avatar_path', c.avatar_path,
    'public_page_enabled', c.public_page_enabled, 'show_rates', c.media_kit_show_rates,
    'total_followers', coalesce((select sum(p.followers) from inf.creator_platforms p where p.creator_id = c.id), 0),
    'platforms', coalesce((select jsonb_agg(jsonb_build_object('platform', p.platform, 'handle', p.handle, 'url', p.url,
                                                               'followers', p.followers, 'avg_views', p.avg_views,
                                                               'engagement_rate', p.engagement_rate, 'audience', p.audience,
                                                               'stats_updated_at', p.stats_updated_at)
                                            order by p.followers desc nulls last)
                             from inf.creator_platforms p where p.creator_id = c.id), '[]'),
    'rates', case when p_rates then coalesce((select jsonb_agg(jsonb_build_object('platform', r.platform, 'format', r.format,
                                                                                  'suggested_paise', r.suggested_paise)
                                                               order by r.platform, r.format)
                                                from inf.creator_rate_cards r where r.creator_id = c.id), '[]') else '[]'::jsonb end,
    'portfolio', coalesce((select jsonb_agg(jsonb_build_object('url', f.url, 'title', f.title) order by f.position)
                             from (select * from inf.creator_portfolio where creator_id = c.id order by position limit 12) f), '[]'),
    'generated_at', now())
    from inf.creators c where c.id = p_creator;
$$;

create or replace function inf.media_kit(p_creator uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not inf.can_view_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  return inf.media_kit_data(p_creator, true);
end $$;

-- Public: only an approved, active, unblocked creator who enabled their public page.
create or replace function inf.media_kit_public(p_handle text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select inf.media_kit_data(c.id, c.media_kit_show_rates)
    from inf.creators c
   where c.handle = lower(trim(p_handle)) and c.public_page_enabled and c.approved_at is not null
     and c.status = 'active' and not c.is_blocked;
$$;

-- Media-kit preferences and avatar (the creator, or staff with creator.write).
create or replace function inf.media_kit_settings(p_creator uuid, p_public boolean, p_show_rates boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.creators set public_page_enabled = coalesce(p_public, public_page_enabled),
         media_kit_show_rates = coalesce(p_show_rates, media_kit_show_rates)
   where id = p_creator;
end $$;

create or replace function inf.avatar_set(p_creator uuid, p_path text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_path is not null and p_path !~ ('^' || p_creator::text || '/[0-9]{10,16}\.(jpg|png|webp)$') then
    raise exception 'invalid avatar path' using errcode = '22023';
  end if;
  update inf.creators set avatar_path = p_path where id = p_creator;
end $$;

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.media_kit(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.media_kit_public(text)', 'anon', 'execute'),
  ('function', 'inf.media_kit_public(text)', 'authenticated', 'execute'),
  ('function', 'inf.media_kit_settings(uuid, boolean, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.avatar_set(uuid, text)', 'authenticated', 'execute');
call inf.apply_client_grants();
