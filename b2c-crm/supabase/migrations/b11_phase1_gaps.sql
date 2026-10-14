-- B2C CRM b11: the rest of Phase 1. Staging first. Idempotent.
--   witty_transcript()   Witty's chat with the student, read-only from public.w2_messages (never written; spec A, B8.3)
--   programme_fit()      programmes for the lead's interest, best match first (B8.3 Programme fit)
--   programme_share()    a programme shared or explained, recorded on the timeline (stage 6 needs one, B5)
--   user_guides          the three guides, editable by the Admin, with what each person has read (B16)
--   push                 web push subscriptions per device; the app pushes new notifications every minute (B16)
--   directory_sync()     also revokes devices and reassigns the open leads of a suspended Workspace account; daily job

-- ---------- Witty's transcript ----------
/* Every Witty message on any of the lead's phones, oldest first (the newest p_limit). Anyone who may see the lead. */
create or replace function b2c.witty_transcript(p_lead bigint, p_limit int default 300) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_phones text[]; v jsonb;
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if to_regclass('public.w2_messages') is null then return '[]'::jsonb; end if;
  select array_agg(distinct x) into v_phones from (
    select c.value_norm as x from b2c.lead_contacts c where c.lead_id = p_lead and c.kind = 'phone' and c.removed_at is null
    union
    select b2c.norm_phone(r.record -> 'student' ->> 'phone') from b2c.lead_records r where r.lead_id = p_lead) p
   where x is not null;
  if v_phones is null then return '[]'::jsonb; end if;
  v_phones := v_phones || array(select '+' || x from unnest(v_phones) x);
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'phone', m.phone, 'direction', m.direction, 'kind', m.kind, 'content', m.content,
                                               'at', m.created_at, 'sent', m.sent) order by m.created_at, m.id), '[]')
    into v
    from (select w.id, w.phone, w.direction, w.kind, w.content, w.created_at, w.sent from public.w2_messages w
           where w.phone = any (v_phones) order by w.created_at desc, w.id desc limit least(greatest(coalesce(p_limit, 300), 1), 1000)) m;
  return v;
end $f$;

-- ---------- Programme fit and sharing ----------
/* The catalogue ranked against the lead's interest: course 4, specialization 3, university 2, mode 1. Level filters. */
create or replace function b2c.programme_fit(p_lead bigint, p_limit int default 12) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare l record; v_level text;
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select lower(nullif(trim(v.course), '')) as course, lower(nullif(trim(v.specialization), '')) as spec, lower(nullif(trim(v.university), '')) as uni,
         lower(nullif(trim(v.study_mode), '')) as mode, lower(nullif(trim(v.programme_level), '')) as level, v.qualification
    into l from b2c.leads_v v where v.lead_id = p_lead;
  v_level := case when l.level in ('pg', 'postgraduate', 'post graduate', 'post-graduate', 'masters', 'master') then 'pg'
                  when l.level in ('ug', 'undergraduate', 'under graduate', 'under-graduate', 'bachelors', 'bachelor') then 'ug'
                  else l.level end;
  return jsonb_build_object(
    'interest', jsonb_build_object('course', l.course, 'specialization', l.spec, 'university', l.uni, 'mode', l.mode, 'level', l.level, 'qualification', l.qualification),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'course', s.course, 'specialization', s.specialization, 'level', s.level,
                 'mode', s.mode, 'university', s.university, 'university_short', s.short_name, 'fee_yearly', s.fee_yearly, 'fee_semester', s.fee_semester,
                 'fee_total', s.fee_total, 'min_qualification', s.min_qualification, 'min_pct', s.min_pct_general, 'eligibility', s.eligibility_text,
                 'brochure_url', s.brochure_url, 'fit', s.fit, 'matched', to_jsonb(array_remove(array[s.m_course, s.m_spec, s.m_uni, s.m_mode], null)))
               order by s.fit desc, coalesce(s.fee_total, s.fee_yearly) nulls last, s.university), '[]')
      from (select s1.* from (select s0.*, case when s0.m_course is not null then 4 else 0 end + case when s0.m_spec is not null then 3 else 0 end
                         + case when s0.m_uni is not null then 2 else 0 end + case when s0.m_mode is not null then 1 else 0 end as fit
              from (select pr.id, coalesce(pr.program_name, pr.course) as name, pr.course, pr.specialization, pr.level, pr.mode, un.name as university, un.short_name,
                           pr.fee_yearly, pr.fee_semester, pr.fee_total, pr.min_qualification, pr.min_pct_general, pr.eligibility_text, pr.brochure_url,
                           case when l.course is not null and (lower(coalesce(pr.course, '')) = l.course
                                                               or position(l.course in lower(coalesce(pr.program_name, pr.course, ''))) > 0) then 'course' end as m_course,
                           case when l.spec is not null and position(l.spec in lower(coalesce(pr.specialization, ''))) > 0 then 'specialization' end as m_spec,
                           case when l.uni is not null and (position(l.uni in lower(coalesce(un.name, ''))) > 0 or lower(coalesce(un.short_name, '')) = l.uni) then 'university' end as m_uni,
                           case when l.mode is not null and lower(coalesce(pr.mode, '')) = l.mode then 'mode' end as m_mode
                      from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
                     where pr.active and (v_level is null or lower(pr.level) = v_level)) s0) s1
             where s1.fit > 0
             order by s1.fit desc, coalesce(s1.fee_total, s1.fee_yearly) nulls last
             limit least(greatest(coalesce(p_limit, 12), 1), 50)) s));
end $f$;

/* One to three programmes shared (WhatsApp, email) or explained (call, meeting). The app sends the message itself
   through wa_queue_text / email_queue first; this records what was shared, which stage 6 checks. */
create or replace function b2c.programme_share(p_lead bigint, p_programmes bigint[], p_channel text, p_note text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v bigint; v_items jsonb; v_names text;
begin
  if p_channel is null or p_channel not in ('whatsapp', 'email', 'call', 'meeting') then raise exception 'say how the programme was shared'; end if;
  if coalesce(cardinality(p_programmes), 0) = 0 then raise exception 'choose at least one programme'; end if;
  if cardinality(p_programmes) > 3 then raise exception 'share at most 3 programmes at a time'; end if;
  select jsonb_agg(jsonb_build_object('id', pr.id, 'name', coalesce(pr.program_name, pr.course), 'university', un.name) order by array_position(p_programmes, pr.id)),
         string_agg(coalesce(pr.program_name, pr.course) || ' (' || un.name || ')', ', ' order by array_position(p_programmes, pr.id))
    into v_items, v_names
    from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
   where pr.id = any (p_programmes);
  if v_items is null or jsonb_array_length(v_items) <> cardinality(p_programmes) then raise exception 'unknown programme'; end if;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'programme_shared', case when p_channel in ('whatsapp', 'email') then 'out' end,
          case p_channel when 'call' then 'Explained on a call: ' when 'meeting' then 'Explained in a meeting: '
                         when 'whatsapp' then 'Shared on WhatsApp: ' else 'Shared by email: ' end || v_names
            || coalesce(E'\n' || nullif(trim(p_note), ''), ''),
          jsonb_build_object('programmes', v_items, 'channel', p_channel), me)
  returning id into v;
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  return v;
end $f$;

-- ---------- Guides (B16) ----------
create table if not exists b2c.user_guides (
  id bigint generated always as identity primary key,
  role text not null check (role in ('sales', 'marketing', 'admin')),
  slug text not null,
  section text not null,
  title text not null,
  body text not null,                       -- Markdown: paragraphs, "- " lists, **bold**
  screens text[] not null default '{}',     -- where the contextual "?" shows it; "/s/leads/*" matches every lead
  sort int not null default 100,
  version int not null default 1,
  archived_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  unique (role, slug)
);
alter table b2c.user_guides enable row level security;

create table if not exists b2c.guide_progress (
  user_id uuid not null references b2c.users (user_id),
  guide_id bigint not null references b2c.user_guides (id),
  version int not null,
  read_at timestamptz not null default now(),
  primary key (user_id, guide_id)
);
alter table b2c.guide_progress enable row level security;

/* The guides for the person's interface (the Admin may ask for any), with what they have read since the last edit. */
create or replace function b2c.guides(p_role text default null, p_archived boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); v_want text[];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_want := case v_role when 'admin' then case when p_role is null then array['admin', 'sales', 'marketing'] else array[p_role] end
                        when 'marketing' then array['marketing'] else array['sales'] end;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'role', g.role, 'slug', g.slug, 'section', g.section, 'title', g.title, 'body', g.body,
                   'screens', to_jsonb(g.screens), 'sort', g.sort, 'version', g.version, 'updated_at', g.updated_at, 'archived', g.archived_at is not null,
                   'read', p.version is not null and p.version >= g.version, 'read_at', p.read_at)
                 order by array_position(array['admin', 'sales', 'marketing'], g.role), g.sort, g.id), '[]')
            from b2c.user_guides g left join b2c.guide_progress p on p.guide_id = g.id and p.user_id = b2c.uid()
           where g.role = any (v_want) and (g.archived_at is null or (p_archived and v_role = 'admin')));
end $f$;

create or replace function b2c.guide_read(p_id bigint) returns void language plpgsql security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2c.guide_progress (user_id, guide_id, version)
  select b2c.uid(), g.id, g.version from b2c.user_guides g where g.id = p_id
  on conflict (user_id, guide_id) do update set version = excluded.version, read_at = now();
end $f$;

/* The Admin edits a guide in the app. A changed title or body is a new version: it shows as unread again. */
create or replace function b2c.guide_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint := nullif(p ->> 'id', '')::bigint; v_title text := nullif(trim(p ->> 'title'), '');
        v_body text := nullif(trim(p ->> 'body'), ''); v_screens text[];
begin
  if v_title is null or length(v_title) > 120 then raise exception 'give the article a title (at most 120 characters)'; end if;
  if v_body is null or length(v_body) > 20000 then raise exception 'write the article (at most 20,000 characters)'; end if;
  v_screens := coalesce(array(select trim(x) from jsonb_array_elements_text(coalesce(p -> 'screens', '[]')) x where trim(x) ~ '^/[a-z0-9/_*-]*$'), '{}');
  if v is null then
    if coalesce(p ->> 'role', '') not in ('sales', 'marketing', 'admin') then raise exception 'choose the guide: sales, marketing or admin'; end if;
    insert into b2c.user_guides (role, slug, section, title, body, screens, sort, updated_by)
    values (p ->> 'role', coalesce(nullif(p ->> 'slug', ''), trim(both '-' from regexp_replace(lower(v_title), '[^a-z0-9]+', '-', 'g')) || '-' || to_char(now(), 'YYMMDDHH24MISS')),
            coalesce(nullif(trim(p ->> 'section'), ''), 'General'), v_title, v_body, v_screens, coalesce((p ->> 'sort')::int, 100), me)
    returning id into v;
  else
    update b2c.user_guides g set
      version = g.version + case when g.title is distinct from v_title or g.body is distinct from v_body then 1 else 0 end,
      title = v_title, body = v_body, section = coalesce(nullif(trim(p ->> 'section'), ''), g.section),
      screens = case when p ? 'screens' then v_screens else g.screens end, sort = coalesce((p ->> 'sort')::int, g.sort),
      archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(g.archived_at, now()) end else g.archived_at end,
      updated_at = now(), updated_by = me
     where g.id = v;
    if not found then raise exception 'unknown article'; end if;
  end if;
  perform b2c.log('guide.saved', null, jsonb_build_object('id', v, 'title', v_title));
  return v;
end $f$;

/* Who has read what (the Admin's view on the Guide page). */
create or replace function b2c.guide_readers() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', coalesce(u.full_name, u.email), 'role', u.role,
                   'total', t.total, 'read', (select count(*) from b2c.guide_progress p join b2c.user_guides g on g.id = p.guide_id
                                               where p.user_id = u.user_id and g.archived_at is null and g.role = t.grole and p.version >= g.version))
                 order by u.full_name), '[]')
            from b2c.users u
            cross join lateral (select case u.role when 'admin' then 'admin' when 'marketing' then 'marketing' else 'sales' end as grole) r
            cross join lateral (select r.grole, count(*) as total from b2c.user_guides g where g.archived_at is null and g.role = r.grole) t
           where u.is_active);
end $f$;

-- ---------- Web push (B16: reminders and alerts on the counsellor's phone) ----------
/* This device's push subscription on (or off). Up to 5 devices per person, newest first. Only the browsers' push
   services are accepted as endpoints, so the server never posts anywhere else. */
create or replace function b2c.push_subscribe(p_sub jsonb, p_on boolean default true) returns int
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v jsonb; v_end text := p_sub ->> 'endpoint';
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_end is null or length(v_end) > 1000
     or v_end !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.notify\.windows\.com|web\.push\.apple\.com)/' then
    raise exception 'not a browser push subscription';
  end if;
  if p_on and (coalesce(p_sub -> 'keys' ->> 'p256dh', '') = '' or coalesce(p_sub -> 'keys' ->> 'auth', '') = '') then
    raise exception 'not a browser push subscription';
  end if;
  select coalesce(jsonb_agg(x order by n), '[]') into v
    from b2c.users u, jsonb_array_elements(case when jsonb_typeof(u.push_subscription) = 'array' then u.push_subscription else '[]'::jsonb end) with ordinality e(x, n)
   where u.user_id = me and x ->> 'endpoint' <> v_end;
  if p_on then
    v := jsonb_build_array(jsonb_build_object('endpoint', v_end, 'keys', jsonb_build_object('p256dh', p_sub -> 'keys' ->> 'p256dh', 'auth', p_sub -> 'keys' ->> 'auth'),
                                              'at', now())) || coalesce(v, '[]');
  end if;
  select coalesce(jsonb_agg(x order by n), '[]') into v from jsonb_array_elements(coalesce(v, '[]')) with ordinality e(x, n) where n <= 5;
  update b2c.users set push_subscription = v, updated_at = now() where user_id = me;
  return jsonb_array_length(v);
end $f$;

/* Service role, every minute: unread notifications of the last 30 minutes not yet pushed, with the person's devices. */
create or replace function b2c.push_take(p_limit int default 200) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with c as (select n.id from b2c.notifications n join b2c.users u on u.user_id = n.user_id
              where n.pushed_at is null and n.read_at is null and n.created_at > now() - interval '30 minutes' and u.is_active
                and jsonb_typeof(u.push_subscription) = 'array' and jsonb_array_length(u.push_subscription) > 0
              order by n.id limit p_limit for update of n skip locked),
  x as (update b2c.notifications n set pushed_at = now() from c where n.id = c.id
        returning n.id, n.user_id, n.kind, n.title, n.body, n.link)
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'user_id', x.user_id, 'kind', x.kind, 'title', x.title, 'body', x.body, 'link', x.link,
                                               'subscriptions', u.push_subscription) order by x.id), '[]')
    into v from x join b2c.users u on u.user_id = x.user_id;
  return v;
end $f$;

/* Service role: the push service says this device is gone (404 or 410). */
create or replace function b2c.push_gone(p_user uuid, p_endpoint text) returns void language sql security definer set search_path = '' as $f$
  update b2c.users u set push_subscription = (select coalesce(jsonb_agg(x order by n), '[]') from jsonb_array_elements(u.push_subscription) with ordinality e(x, n)
                                               where x ->> 'endpoint' <> p_endpoint)
   where u.user_id = p_user and jsonb_typeof(u.push_subscription) = 'array'
$f$;

-- ---------- Workspace directory sync ----------
/* Service role, daily: name, photo and title stay current. A suspended Workspace account is deactivated like the Admin
   would (trusted devices revoked, open leads reassigned by the rules); the last active Admin is never deactivated here. */
create or replace function b2c.directory_sync(p_users jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := 0; d int := 0; v_user uuid; r record; moved int := 0; m int;
begin
  for x in select * from jsonb_array_elements(coalesce(p_users, '[]')) loop
    update b2c.users set full_name = coalesce(nullif(x ->> 'name', ''), full_name), photo_url = coalesce(nullif(x ->> 'photo_url', ''), photo_url),
           job_title = coalesce(nullif(x ->> 'job_title', ''), job_title), workspace_user_id = coalesce(x ->> 'id', workspace_user_id), synced_at = now()
     where email = lower(x ->> 'email')
    returning user_id into v_user;
    if v_user is null then continue; end if;
    n := n + 1;
    if coalesce((x ->> 'suspended')::boolean, false)
       and exists (select 1 from b2c.users where user_id = v_user and is_active)
       and not ((select role from b2c.users where user_id = v_user) = 'admin'
                and (select count(*) from b2c.users where role = 'admin' and is_active) <= 1) then
      update b2c.users set is_active = false, deactivated_at = now(), on_call = false, updated_at = now() where user_id = v_user;
      update b2c.trusted_devices set revoked_at = now() where user_id = v_user and revoked_at is null;
      m := 0;
      for r in select lead_id from b2c.leads_state where owner_id = v_user and status = 'active' loop
        perform b2c.allocate(r.lead_id, 'deactivated', v_user); m := m + 1;
      end loop;
      perform b2c.log('team.user_deactivated', null, jsonb_build_object('user_id', v_user, 'reason', 'suspended in Google Workspace', 'reassigned', m), 'system');
      d := d + 1; moved := moved + m;
    end if;
    v_user := null;
  end loop;
  perform b2c.sync_set('directory_at', to_jsonb(now()));
  return jsonb_build_object('updated', n, 'deactivated', d, 'reassigned', moved);
end $f$;

do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-directory') then
    perform cron.schedule('b2c-directory', '40 20 * * *', $$select b2c.job_call('/api/internal/directory')$$);   -- 02:10 IST
  end if;
end $d$;

-- ---------- grants ----------
grant execute on function b2c.witty_transcript(bigint, int), b2c.programme_fit(bigint, int), b2c.programme_share(bigint, bigint[], text, text),
  b2c.guides(text, boolean), b2c.guide_read(bigint), b2c.guide_save(jsonb), b2c.guide_readers(), b2c.push_subscribe(jsonb, boolean) to authenticated;
revoke execute on function b2c.push_take(int), b2c.push_gone(uuid, text), b2c.directory_sync(jsonb) from public, authenticated;
grant execute on function b2c.push_take(int), b2c.push_gone(uuid, text), b2c.directory_sync(jsonb) to service_role;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
