-- B2C CRM b17 (Phase 2): lead scoring, replies, dormancy, the Nurture page's numbers and the timers (B6.3, B6.5, B6.6, B9.0, B9.5).
-- Staging first. Idempotent.
--   score_rules, score_events   fit and engagement points; engagement halves after 14 days without activity; a rise to 60+
--                               after pool entry with engagement re-engages the lead (fit alone never does)
--   replies, reply_rules        every reply to nurture: class, method, confidence; keyword rules first, then Claude (app);
--                               below 0.8 to the Replies inbox; positive re-engages, negative moves to a long gap, STOP opts out
--   wa_inbound() / wa_status()  replaced: pooled replies go through classification; marketing reads score
--   email_event() / email_inbound()   opens, clicks, bounces and replies on marketing email (the app reports them)
--   nurture_overview(), pool_list(), lead_nurture()   what the Nurture page and the lead screen show
--   b2c-nurture (every minute), b2c-nightly (decay and dormancy)

alter table b2c.leads_state add column if not exists fit_points int not null default 0;
alter table b2c.leads_state add column if not exists engagement_points numeric(8, 2) not null default 0;
alter table b2c.leads_state add column if not exists engagement_at timestamptz;
alter table b2c.leads_state add column if not exists score_decayed_at timestamptz;
alter table b2c.leads_state add column if not exists score_band text;

create table if not exists b2c.score_rules (
  key text primary key,
  kind text not null check (kind in ('fit', 'engagement')),
  label text not null,
  points int not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into b2c.score_rules (key, kind, label, points) values
  ('timeline_3m', 'fit', 'Wants to start within 3 months', 15),
  ('budget_50k', 'fit', 'Budget of ₹50,000 a year or more', 10),
  ('qualification_known', 'fit', 'Qualification known', 10),
  ('working_exec', 'fit', 'Working professional for an executive programme', 10),
  ('phone_verified', 'fit', 'Phone verified', 5),
  ('wa_read', 'engagement', 'Read a nurture WhatsApp', 2),
  ('wa_reply', 'engagement', 'Replied on WhatsApp', 15),
  ('email_open', 'engagement', 'Opened a nurture email', 3),
  ('email_click', 'engagement', 'Clicked a link in a nurture email', 8),
  ('email_reply', 'engagement', 'Replied to a nurture email', 15),
  ('brochure_click', 'engagement', 'Opened a brochure link', 8),
  ('witty_resumed', 'engagement', 'Talked to Witty again', 20),
  ('form_filled', 'engagement', 'Filled a form again', 20),
  ('journey', 'engagement', 'Journey step', 0)
on conflict (key) do nothing;

create table if not exists b2c.score_events (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  rule_key text not null,
  points numeric(8, 2) not null,
  score_after int,
  detail jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index if not exists score_events_lead on b2c.score_events (lead_id, at desc);

insert into b2c.settings (key, value) values
  ('scoring', '{"reengage_at": 60, "hot_at": 60, "warm_at": 30, "decay_days": 14}'),
  ('reply_buttons', '{"positive": ["yes, call me", "i''m interested", "share details", "call me"], "negative": ["not now", "not interested", "no thanks"], "consent": ["yes, send updates"]}')
on conflict (key) do nothing;

-- ---------- scoring ----------
create or replace function b2c.score_fit(p_lead bigint) returns int language plpgsql stable security definer set search_path = '' as $f$
declare r jsonb; v int := 0; v_tl text; v_d date; pts jsonb;
begin
  select record into r from b2c.lead_records where lead_id = p_lead;
  if r is null then return 0; end if;
  select jsonb_object_agg(key, points) into pts from b2c.score_rules where kind = 'fit' and active;
  v_tl := lower(coalesce(r -> 'interest' ->> 'enrollment_timeline', ''));
  if v_tl ~ '(immediate|asap|this month|next month|within (1|2|3|one|two|three) month|1 month|2 months|3 months|this intake)' then v := v + coalesce((pts ->> 'timeline_3m')::int, 0);
  else
    begin
      v_d := to_date(regexp_replace(v_tl, '[^a-z0-9 ]', '', 'g'), 'mon yyyy');
      if v_d <= current_date + 92 and v_d >= current_date - 31 then v := v + coalesce((pts ->> 'timeline_3m')::int, 0); end if;
    exception when others then null;
    end;
  end if;
  if coalesce(nullif(regexp_replace(r -> 'interest' ->> 'annual_budget_inr', '[^0-9.]', '', 'g'), '')::numeric, 0) >= 50000 then v := v + coalesce((pts ->> 'budget_50k')::int, 0); end if;
  if coalesce(r -> 'education' ->> 'highest_qualification', '') <> '' then v := v + coalesce((pts ->> 'qualification_known')::int, 0); end if;
  if coalesce(r -> 'interest' ->> 'course', '') ~* 'exec' and coalesce(nullif(regexp_replace(r -> 'education' ->> 'work_experience_years', '[^0-9.]', '', 'g'), '')::numeric, 0) >= 2 then
    v := v + coalesce((pts ->> 'working_exec')::int, 0);
  end if;
  if coalesce((r -> 'student' ->> 'phone_verified')::boolean, false) or r -> 'verification' ->> 'phone_verified_at' is not null then v := v + coalesce((pts ->> 'phone_verified')::int, 0); end if;
  return v;
end $f$;

/* Score = fit + engagement. Pooled leads get the temperature band. The master record is written only when the band
   changes or the score crosses the re-engagement line (B9.5). Returns the new score. */
create or replace function b2c.score_recompute(p_lead bigint) returns int language plpgsql security definer set search_path = '' as $f$
declare s b2c.leads_state; v_fit int := b2c.score_fit(p_lead); v int; v_band text; cfg jsonb := b2c.setting('scoring'); v_line int;
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null then return null; end if;
  v := v_fit + round(s.engagement_points)::int;
  v_line := coalesce((cfg ->> 'reengage_at')::int, 60);
  v_band := case when v >= coalesce((cfg ->> 'hot_at')::int, 60) then 'hot' when v >= coalesce((cfg ->> 'warm_at')::int, 30) then 'warm' else 'cold' end;
  update b2c.leads_state set fit_points = v_fit, score = v, score_band = v_band,
         temperature = case when status = 'pool' then v_band else temperature end
   where lead_id = p_lead;
  if s.status = 'pool' and s.score_band is not null and (s.score_band <> v_band or (coalesce(s.score, 0) < v_line) <> (v < v_line)) then
    perform b2c.queue_update(p_lead, jsonb_strip_nulls(jsonb_build_object('lead_score', v, 'temperature', case when s.status = 'pool' then v_band end)), false);
  end if;
  return v;
end $f$;

/* An engagement event (or a journey's score step). A rise to the line after pool entry re-engages the lead. */
create or replace function b2c.score_add(p_lead bigint, p_rule text, p_points numeric default null, p_detail jsonb default '{}'::jsonb) returns int
language plpgsql security definer set search_path = '' as $f$
declare rl b2c.score_rules; s b2c.leads_state; v_pts numeric; v_new int; v_line int := coalesce((b2c.setting('scoring') ->> 'reengage_at')::int, 60);
begin
  select * into rl from b2c.score_rules where key = p_rule;
  if rl.key is null or (not rl.active and p_points is null) then return null; end if;
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead) then return null; end if;
  perform b2c.score_recompute(p_lead);   -- the baseline (fit may have changed since the last event)
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_pts := coalesce(p_points, rl.points);
  update b2c.leads_state set engagement_points = greatest(0, engagement_points + v_pts), engagement_at = case when v_pts > 0 then now() else engagement_at end
   where lead_id = p_lead;
  v_new := b2c.score_recompute(p_lead);
  insert into b2c.score_events (lead_id, rule_key, points, score_after, detail) values (p_lead, p_rule, v_pts, v_new, coalesce(p_detail, '{}'));
  if s.status = 'pool' and coalesce(s.score, 0) < v_line and v_new >= v_line and v_pts > 0 and rl.kind = 'engagement' and s.pool_entered_at is not null then
    perform b2c.reengage(p_lead, 'score');
  end if;
  return v_new;
end $f$;

/* Nightly, in small batches: engagement halves after 14 days without activity (never re-engages). */
create or replace function b2c.score_decay_tick(p_limit int default 500) returns int language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0; v_days int := coalesce((b2c.setting('scoring') ->> 'decay_days')::int, 14);
begin
  for r in select lead_id from b2c.leads_state
            where engagement_points > 0 and engagement_at < now() - make_interval(days => v_days)
              and (score_decayed_at is null or score_decayed_at < now() - make_interval(days => v_days))
            order by score_decayed_at nulls first limit p_limit loop
    update b2c.leads_state set engagement_points = case when engagement_points / 2 < 0.5 then 0 else engagement_points / 2 end, score_decayed_at = now() where lead_id = r.lead_id;
    insert into b2c.score_events (lead_id, rule_key, points, score_after, detail)
    select r.lead_id, 'decay', 0, b2c.score_recompute(r.lead_id), jsonb_build_object('halved', true);
    n := n + 1;
  end loop;
  return n;
end $f$;

create or replace function b2c.score_rule_save(p_key text, p_points int, p_active boolean) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing');
begin
  if p_points not between -100 and 100 then raise exception 'points between -100 and 100'; end if;
  update b2c.score_rules set points = coalesce(p_points, points), active = coalesce(p_active, active), updated_at = now(), updated_by = me where key = p_key;
  if not found then raise exception 'unknown rule'; end if;
  perform b2c.log('scoring.rule_changed', null, jsonb_build_object('key', p_key, 'points', p_points, 'active', p_active));
end $f$;

-- the master record changes (qualification, budget, timeline): fit is recomputed
create or replace function b2c.lead_records_fit() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if exists (select 1 from b2c.leads_state where lead_id = new.lead_id) then perform b2c.score_recompute(new.lead_id); end if;
  return null;
end $f$;
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'lead_records_fit') then
    create trigger lead_records_fit after insert or update of record on b2c.lead_records for each row execute function b2c.lead_records_fit();
  end if;
  -- a new B2C lead gets its fit score at once (the record usually arrives first)
  if not exists (select 1 from pg_trigger where tgname = 'leads_state_fit') then
    create trigger leads_state_fit after insert on b2c.leads_state for each row execute function b2c.lead_records_fit();
  end if;
end $d$;

-- ---------- replies ----------
create table if not exists b2c.reply_rules (
  id bigint generated always as identity primary key,
  class text not null check (class in ('positive', 'question', 'negative', 'opt_out', 'other')),
  pattern text not null,              -- case-insensitive regular expression
  confidence numeric(3, 2) not null default 0.9,
  lang text,
  active boolean not null default true,
  sort int not null default 100,
  unique (class, pattern)
);
insert into b2c.reply_rules (class, pattern, confidence, lang, sort) values
  ('opt_out', '^\s*(stop|unsubscribe|band karo|bandh karo|mat bhejo|no more messages)\s*[.!]*\s*$', 1.0, 'any', 1),
  ('negative', '(already (joined|enrolled|took admission)|enrolled elsewhere|joined (another|other))', 0.95, 'en', 10),
  ('negative', '(not interested|no thanks|no thank you|don''?t (call|message|contact)|not now|no need)', 0.9, 'en', 20),
  ('negative', '(interest nahi|nahi chahiye|mat karo|zarurat nahi|abhi nahi|call mat)', 0.9, 'hinglish', 20),
  ('positive', '(call me|please call|interested|share (the )?details|send (the )?details|tell me more|want to (join|apply|enrol))', 0.9, 'en', 30),
  ('positive', '(call karo|call kar(i|e)ye|details bhejo|batao|haan|ha+n ji|kab call|admission (lena|chahiye)|apply karna)', 0.9, 'hinglish', 30),
  ('positive', '(fees?|emi|scholarship|eligib|admission|last date|deadline)', 0.85, 'any', 40),
  ('question', '(\?\s*$|^(what|how|when|where|which|who|is|are|can|do|does)\b|^(kya|kaise|kab|kahan|kaun|kitna|kitni)\b)', 0.8, 'any', 50)
on conflict (class, pattern) do nothing;

create table if not exists b2c.replies (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  channel text not null check (channel in ('whatsapp', 'email')),
  wa_message_id bigint,
  email_id bigint,
  text text,
  button text,
  class text check (class in ('positive', 'question', 'negative', 'opt_out', 'other')),
  method text,                        -- button, rule, claude, none
  confidence numeric(3, 2),
  model text,
  status text not null default 'new' check (status in ('new', 'pending_ai', 'inbox', 'done')),
  action text,
  corrected_class text check (corrected_class in ('positive', 'question', 'negative', 'opt_out', 'other')),
  corrected_by uuid,
  corrected_at timestamptz,
  handled_by uuid,
  handled_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists replies_status on b2c.replies (status, created_at);
create index if not exists replies_lead on b2c.replies (lead_id, created_at desc);

create or replace function b2c.notify_marketing(p_kind text, p_title text, p_body text, p_link text, p_lead bigint, p_dedupe text) returns void
language sql security definer set search_path = '' as $f$
  select b2c.notify(u.user_id, p_kind, p_title, p_body, p_link, p_lead, p_dedupe) from b2c.users u where u.is_active and u.role in ('admin', 'marketing')
$f$;

/* Acts on a classified reply (B6.3): positive re-engages (or allocates an unassigned active lead), negative moves to a long
   gap or closes as "enrolled elsewhere", opt-out stops everything; a question, "other" or a low confidence goes to the inbox. */
create or replace function b2c.reply_act(p_reply bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare x b2c.replies; s b2c.leads_state; v_class text; v_out text; v_min numeric := coalesce((b2c.setting('nurture') ->> 'reply_confidence')::numeric, 0.8); v_long bigint;
begin
  select * into x from b2c.replies where id = p_reply for update;
  select * into s from b2c.leads_state where lead_id = x.lead_id;
  v_class := coalesce(x.corrected_class, x.class);
  if v_class = 'opt_out' and coalesce(x.confidence, 0) >= v_min then
    perform b2c.opt_out(x.lead_id, null, case when x.channel = 'whatsapp' then 'stop_word' else 'email_reply' end);
    v_out := 'opted_out';
  elsif v_class = 'positive' and (coalesce(x.confidence, 0) >= v_min or x.corrected_class is not null) then
    if s.status = 'pool' then perform b2c.reengage(x.lead_id, x.channel || '_reply'); v_out := 'reengaged';
    elsif s.status = 'active' and s.owner_id is null then perform b2c.allocate(x.lead_id, 'reply'); v_out := 'allocated';
    else v_out := 'noted'; end if;
  elsif v_class = 'negative' and (coalesce(x.confidence, 0) >= v_min or x.corrected_class is not null) then
    if coalesce(x.text, '') ~* '(already (joined|enrolled|took admission)|enrolled elsewhere|joined (another|other))' then
      perform b2c.journey_exit(x.lead_id, 'negative reply');
      perform b2c.close_lead(x.lead_id, 'closed', 'enrolled_elsewhere');
      v_out := 'closed';
    else
      perform b2c.journey_exit(x.lead_id, 'negative reply');
      select id into v_long from b2c.journeys where key = 'long_term_update' and current_version > 0 and status <> 'archived';
      if v_long is not null and s.status = 'pool' and b2c.may_message(x.lead_id) is null then perform b2c.journey_start(x.lead_id, v_long, 'negative_reply'); end if;
      v_out := 'long_gap';
    end if;
  else
    update b2c.replies set status = 'inbox' where id = x.id;
    perform b2c.notify_marketing('reply', 'A reply needs an answer', left(coalesce(x.text, x.button, ''), 200), '/w/nurture?tab=replies', x.lead_id, 'reply:' || x.id);
    return 'inbox';
  end if;
  update b2c.replies set status = 'done', action = v_out, handled_at = coalesce(handled_at, now()) where id = x.id;
  return v_out;
end $f$;

/* A reply from a pooled or unassigned lead (WhatsApp or email): buttons first, then keyword rules; what the rules cannot
   decide waits for Claude (the app), and goes to the inbox if nobody classifies it within 10 minutes. */
create or replace function b2c.reply_receive(p_lead bigint, p_channel text, p_text text, p_button text default null, p_ref jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_id bigint; v_class text; v_conf numeric; v_method text; v_low text := lower(trim(coalesce(p_button, p_text, ''))); b jsonb := b2c.setting('reply_buttons'); rr record; v_out text;
begin
  if p_button is not null or v_low in (select jsonb_array_elements_text(b -> 'positive') union all select jsonb_array_elements_text(b -> 'negative') union all select jsonb_array_elements_text(b -> 'consent')) then
    if v_low in (select jsonb_array_elements_text(b -> 'consent')) then
      perform b2c.marketing_consent(p_lead, 'whatsapp', true, 'wa_button', 'nurture_consent_repeat');
      perform b2c.marketing_consent(p_lead, 'email', true, 'wa_button', 'nurture_consent_repeat');
      v_class := 'other'; v_conf := 1; v_method := 'button';
    elsif v_low in (select jsonb_array_elements_text(b -> 'positive')) then v_class := 'positive'; v_conf := 1; v_method := 'button';
    elsif v_low in (select jsonb_array_elements_text(b -> 'negative')) then v_class := 'negative'; v_conf := 1; v_method := 'button';
    end if;
  end if;
  if v_class is null then
    for rr in select class, confidence from b2c.reply_rules where active and v_low ~* pattern order by sort, id limit 1 loop
      v_class := rr.class; v_conf := rr.confidence; v_method := 'rule';
    end loop;
  end if;
  insert into b2c.replies (lead_id, channel, wa_message_id, email_id, text, button, class, method, confidence, status)
  values (p_lead, p_channel, (p_ref ->> 'message_id')::bigint, (p_ref ->> 'email_id')::bigint, left(p_text, 4000), p_button, v_class, v_method, v_conf,
          case when v_class is null then 'pending_ai' else 'new' end)
  returning id into v_id;
  if v_class is null then return jsonb_build_object('status', 'classifying', 'reply_id', v_id); end if;
  if v_method = 'button' and v_class = 'other' then
    update b2c.replies set status = 'done', action = 'consent_given', handled_at = now() where id = v_id;
    perform b2c.score_add(p_lead, case when p_channel = 'whatsapp' then 'wa_reply' else 'email_reply' end, null, jsonb_build_object('reply_id', v_id));
    return jsonb_build_object('status', 'consent_given', 'reply_id', v_id);
  end if;
  v_out := b2c.reply_act(v_id);
  -- a reply is engagement, unless it says no
  if v_class not in ('negative', 'opt_out') then
    perform b2c.score_add(p_lead, case when p_channel = 'whatsapp' then 'wa_reply' else 'email_reply' end, null, jsonb_build_object('reply_id', v_id));
  end if;
  return jsonb_build_object('status', v_out, 'reply_id', v_id, 'class', v_class);
end $f$;

/* The app's Claude step (B6.6): only the reply text and the course interest leave the database. */
create or replace function b2c.reply_classify_take(p_limit int default 20) returns jsonb language sql security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'text', left(x.text, 1000), 'course', r.record -> 'interest' ->> 'course') order by x.id), '[]')
    from (select * from b2c.replies where status = 'pending_ai' and coalesce(text, '') <> '' order by id limit p_limit) x
    left join b2c.lead_records r on r.lead_id = x.lead_id
$f$;

create or replace function b2c.reply_classify_done(p_results jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := 0;
begin
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]')) loop
    update b2c.replies set class = case when x ->> 'class' in ('positive', 'question', 'negative', 'opt_out', 'other') then x ->> 'class' else 'other' end,
           confidence = least(greatest(coalesce((x ->> 'confidence')::numeric, 0), 0), 1), method = 'claude', model = x ->> 'model', status = 'new'
     where id = (x ->> 'id')::bigint and status = 'pending_ai';
    if found then
      perform b2c.reply_act((x ->> 'id')::bigint);
      if coalesce(x ->> 'class', 'other') not in ('negative', 'opt_out') then
        perform b2c.score_add(r.lead_id, case when r.channel = 'whatsapp' then 'wa_reply' else 'email_reply' end, null, jsonb_build_object('reply_id', r.id))
          from b2c.replies r where r.id = (x ->> 'id')::bigint;
      end if;
      n := n + 1;
    end if;
  end loop;
  return n;
end $f$;

/* The Replies inbox (B9.0). */
create or replace function b2c.replies_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('replies');
  return (select coalesce(jsonb_agg(jsonb_build_object('reply', to_jsonb(x), 'lead', jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'course', v.course, 'status', v.status,
                   'owner_name', v.owner_name, 'pool_reason', v.pool_reason, 'journey', v.journey, 'score', v.score),
                   'window_open', b2c.window_open(b2c.wa_phone(x.lead_id))) order by x.created_at desc), '[]')
            from (select * from b2c.replies r where (coalesce(p ->> 'status', 'inbox') = 'all' or r.status = coalesce(p ->> 'status', 'inbox'))
                     and (p ->> 'class' is null or coalesce(r.corrected_class, r.class) = p ->> 'class')
                   order by r.created_at desc limit least(coalesce((p ->> 'limit')::int, 100), 300)) x
            left join b2c.leads_v v on v.lead_id = x.lead_id);
end $f$;

/* Inbox actions: assign (re-engage), negative, opt_out, correct (with a class: kept for accuracy, then acted on), done. */
create or replace function b2c.reply_handle(p_id bigint, p_action text, p_class text default null) returns text language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('replies'); x b2c.replies; s b2c.leads_state; v text;
begin
  select * into x from b2c.replies where id = p_id;
  if x.id is null then raise exception 'unknown reply'; end if;
  select * into s from b2c.leads_state where lead_id = x.lead_id;
  update b2c.replies set handled_by = me, handled_at = now() where id = p_id;
  if p_action = 'correct' then
    if p_class not in ('positive', 'question', 'negative', 'opt_out', 'other') then raise exception 'choose a class'; end if;
    update b2c.replies set corrected_class = p_class, corrected_by = me, corrected_at = now() where id = p_id;
    if p_class in ('positive', 'negative', 'opt_out') then return b2c.reply_act(p_id); end if;
    return 'corrected';
  elsif p_action = 'assign' then
    v := case when s.status = 'pool' then (b2c.reengage(x.lead_id, 'reply_answered') ->> 'outcome')
              when s.status = 'active' and s.owner_id is null then (b2c.allocate(x.lead_id, 'reply') ->> 'outcome') else 'already assigned' end;
  elsif p_action = 'negative' then
    update b2c.replies set corrected_class = coalesce(corrected_class, case when class <> 'negative' then 'negative' end),
           corrected_by = case when class <> 'negative' then me else corrected_by end where id = p_id;
    return b2c.reply_act(p_id);
  elsif p_action = 'opt_out' then
    perform b2c.opt_out(x.lead_id, null, 'replies_inbox'); v := 'opted_out';
  elsif p_action <> 'done' then
    raise exception 'unknown action';
  end if;
  update b2c.replies set status = 'done', action = coalesce(v, p_action) where id = p_id;
  return coalesce(v, p_action);
end $f$;

/* Marketing answers a reply on WhatsApp inside the 24-hour window (no counsellor owns the lead). */
create or replace function b2c.wa_queue_reply(p_lead bigint, p_text text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('replies'); v_phone text := b2c.wa_phone(p_lead); v bigint;
begin
  if length(coalesce(trim(p_text), '')) = 0 then raise exception 'type a message'; end if;
  if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
  if not b2c.window_open(v_phone) then raise exception 'the 24-hour window is closed: only a template can go now'; end if;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, status, category, purpose, user_id)
  values (v_phone, p_lead, 'out', 'text', left(p_text, 4096), 'queued', 'service', 'replies', me) returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose)
  values ('whatsapp', p_lead, v_phone, v, jsonb_build_object('type', 'text', 'text', left(p_text, 4096)), 'replies');
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id) values (p_lead, 'whatsapp', 'out', left(p_text, 500), jsonb_build_object('message_id', v, 'from', 'replies'), me);
  return v;
end $f$;

-- ---------- WhatsApp in and out, replaced ----------
/* Read receipts on marketing messages score once per message. */
create or replace function b2c.wa_status(p_wamid text, p_status text, p_at timestamptz, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare m b2c.wa_messages;
begin
  select * into m from b2c.wa_messages where wamid = p_wamid for update;
  if m.id is null or p_status not in ('sent', 'delivered', 'read', 'failed') then return; end if;
  if array_position(array['queued', 'dry_run', 'sent', 'delivered', 'read'], m.status) > coalesce(array_position(array['queued', 'dry_run', 'sent', 'delivered', 'read'], p_status), 99) then return; end if;
  update b2c.wa_messages set status = p_status, status_at = p_at, error = coalesce(p_error, error) where id = m.id;
  if p_status = 'read' and m.status <> 'read' and m.purpose in ('journey', 'campaign', 'marketing') and m.lead_id is not null then
    perform b2c.score_add(m.lead_id, 'wa_read', null, jsonb_build_object('message_id', m.id));
  end if;
end $f$;

/* An inbound WhatsApp message on the B2C number (B8.5, B6.3). As in b6, plus: a pooled or unassigned lead's reply is
   classified and acted on (re-engage, long gap, opt-out, inbox). */
create or replace function b2c.wa_inbound(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_phone text := b2c.norm_phone(p ->> 'from'); v_text text := trim(coalesce(p ->> 'text', p ->> 'button', ''));
  v_lead bigint; s b2c.leads_state; v_low text := lower(trim(coalesce(p ->> 'text', p ->> 'button', ''))); q b2c.consent_requests; v_ans text; v_id bigint;
begin
  if p ->> 'wamid' is not null and exists (select 1 from b2c.wa_messages where wamid = p ->> 'wamid') then return jsonb_build_object('status', 'duplicate'); end if;
  select c.lead_id into v_lead from b2c.lead_contacts c join b2c.leads_state s2 on s2.lead_id = c.lead_id
   where c.kind = 'phone' and c.value_norm = v_phone and c.removed_at is null order by s2.status = 'active' desc, s2.updated_at desc limit 1;
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, media, wamid, status, status_at, reply_to)
  values (v_phone, v_lead, 'in', coalesce(p ->> 'kind', 'text'), left(v_text, 4096), p -> 'media', p ->> 'wamid', 'received', now(), p ->> 'context_wamid')
  returning id into v_id;
  insert into b2c.wa_conversations (phone, lead_id, last_inbound_at, unread) values (v_phone, v_lead, now(), 1)
  on conflict (phone) do update set last_inbound_at = now(), unread = b2c.wa_conversations.unread + 1, lead_id = coalesce(b2c.wa_conversations.lead_id, excluded.lead_id), updated_at = now();

  if v_lead is null then
    insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
    values ('intake', null, 'b2c-in-' || v_phone, jsonb_build_object('phone', v_phone, 'lead_source', 'b2c_whatsapp', 'name', p ->> 'profile_name',
            'first_message', left(v_text, 500)), true)
    on conflict (request_id) do nothing;
    perform b2c.notify_admins('new_whatsapp', 'New student on the B2C WhatsApp number', left(v_text, 200), '/w/inbox', null, 'newwa:' || v_phone);
    return jsonb_build_object('status', 'new_lead_requested');
  end if;

  select * into s from b2c.leads_state where lead_id = v_lead;
  insert into b2c.activities (lead_id, kind, direction, body, meta) values (v_lead, 'whatsapp', 'in', left(v_text, 500), jsonb_build_object('message_id', v_id));
  update b2c.leads_state set last_activity_at = now() where lead_id = v_lead;

  if exists (select 1 from jsonb_array_elements_text(coalesce(b2c.setting('opt_out_words') -> 'words', '[]')) w where v_low = w or v_low like w || ' %') then
    perform b2c.opt_out(v_lead, null, 'stop_word', v_text);
    return jsonb_build_object('status', 'opted_out');
  end if;

  select * into q from b2c.consent_requests where lead_id = v_lead and status in ('queued', 'sent') order by created_at desc limit 1;
  if q.request_id is not null then
    v_ans := case when v_low in ('yes', 'y', 'haan', 'ha', 'han', 'yes please', 'ok share') then 'yes'
                  when v_low in ('no', 'n', 'nahi', 'nahin', 'no thanks', 'mat karo') then 'no' end;
    if v_ans is not null then
      update b2c.consent_requests set status = 'answered', answer = v_ans, answer_wamid = p ->> 'wamid', answered_at = now() where request_id = q.request_id;
      perform b2c.queue_event('b2ccrm.partner_consent', v_lead, jsonb_build_object('request_id', q.request_id, 'answer', v_ans, 'answered_at', now(),
                              'channel', 'whatsapp', 'message_id', p ->> 'wamid', 'text_version', coalesce(q.text_version, 'wa_partner_consent:v1')), true);
      return jsonb_build_object('status', 'consent_' || v_ans);
    end if;
  end if;

  if s.owner_id is not null and s.status = 'active' then
    perform b2c.notify(s.owner_id, 'whatsapp', 'WhatsApp from ' || coalesce(b2c.first_name(v_lead), 'a student'), left(v_text, 200), '/s/inbox?lead=' || v_lead, v_lead, null);
    perform b2c.queue_activity(v_lead, 'whatsapp', now(), 'reply', null, left(v_text, 500));
    return jsonb_build_object('status', 'to_counsellor');
  end if;
  -- pooled or unassigned: classified and acted on (B6.3, B6.6)
  perform b2c.queue_activity(v_lead, 'whatsapp', now(), 'reply', null, left(v_text, 500));
  return b2c.reply_receive(v_lead, 'whatsapp', nullif(p ->> 'text', ''), nullif(p ->> 'button', ''), jsonb_build_object('message_id', v_id));
end $f$;

-- ---------- email events (the app reports them) ----------
/* open, click (with the link kind: interested, brochure, other) and bounce on a marketing email. */
create or replace function b2c.email_event(p_email bigint, p_kind text, p_link text default null) returns text language plpgsql security definer set search_path = '' as $f$
declare e b2c.emails;
begin
  select * into e from b2c.emails where id = p_email for update;
  if e.id is null or e.lead_id is null then return 'unknown'; end if;
  if p_kind = 'open' then
    if e.opened_at is null then
      update b2c.emails set opened_at = now() where id = e.id;
      perform b2c.score_add(e.lead_id, 'email_open', null, jsonb_build_object('email_id', e.id));
    end if;
  elsif p_kind = 'click' then
    update b2c.emails set clicked_at = coalesce(clicked_at, now()), opened_at = coalesce(opened_at, now()) where id = e.id;
    if p_link = 'interested' then
      perform b2c.reply_receive(e.lead_id, 'email', null, 'I''m interested', jsonb_build_object('email_id', e.id));
    elsif e.clicked_at is null then
      perform b2c.score_add(e.lead_id, case when p_link = 'brochure' then 'brochure_click' else 'email_click' end, null, jsonb_build_object('email_id', e.id));
    end if;
  elsif p_kind = 'bounce' then
    update b2c.emails set bounced_at = coalesce(bounced_at, now()), status = 'bounced' where id = e.id;
    perform b2c.queue_update(e.lead_id, jsonb_build_object('email_bounced_at', now()), false);
  else
    return 'unknown kind';
  end if;
  return 'ok';
end $f$;

/* A reply to a marketing email (the app reads the marketing mailbox). */
create or replace function b2c.email_inbound(p_from text, p_subject text, p_text text, p_gmail_id text, p_thread text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint; v bigint; s b2c.leads_state; v_addr text := lower(trim(substring(p_from from '[^<\s]+@[^>\s]+')));
begin
  if exists (select 1 from b2c.emails where gmail_message_id = p_gmail_id and direction = 'in') then return jsonb_build_object('status', 'duplicate'); end if;
  select c.lead_id into v_lead from b2c.lead_contacts c join b2c.leads_state s2 on s2.lead_id = c.lead_id
   where c.kind = 'email' and c.value_norm = v_addr and c.removed_at is null order by s2.updated_at desc limit 1;
  if v_lead is null then return jsonb_build_object('status', 'unknown sender'); end if;
  insert into b2c.emails (lead_id, direction, from_address, subject, snippet, gmail_message_id, thread_id, status, purpose)
  values (v_lead, 'in', v_addr, left(p_subject, 300), left(p_text, 200), p_gmail_id, p_thread, 'received', 'reply') returning id into v;
  insert into b2c.activities (lead_id, kind, direction, body, meta) values (v_lead, 'email', 'in', 'Email: ' || left(coalesce(p_subject, ''), 200), jsonb_build_object('email_id', v));
  update b2c.leads_state set last_activity_at = now() where lead_id = v_lead;
  select * into s from b2c.leads_state where lead_id = v_lead;
  if s.owner_id is not null and s.status = 'active' then
    perform b2c.notify(s.owner_id, 'email', 'Email from ' || coalesce(b2c.first_name(v_lead), 'a student'), left(p_subject, 200), '/s/leads/' || v_lead, v_lead, 'email:' || v);
    return jsonb_build_object('status', 'to_counsellor');
  end if;
  return b2c.reply_receive(v_lead, 'email', left(p_text, 4000), null, jsonb_build_object('email_id', v));
end $f$;

-- ---------- dormancy, timers ----------
/* After 12 months in the pool without any response: dormant (no messages, still searchable; B6.5). Never deleted. */
create or replace function b2c.dormancy_tick(p_limit int default 1000) returns int language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0; v_months int := coalesce((b2c.setting('nurture') ->> 'dormant_after_months')::int, 12);
begin
  for r in select s.lead_id from b2c.leads_state s
            where s.status = 'pool' and s.dormant_at is null and s.pool_entered_at < now() - make_interval(months => v_months)
              and coalesce(s.reengaged_at, s.reenquired_at, s.pool_entered_at) < now() - make_interval(months => v_months)
              and not exists (select 1 from b2c.wa_messages m where m.lead_id = s.lead_id and m.direction = 'in' and m.created_at > now() - make_interval(months => v_months))
              and not exists (select 1 from b2c.replies x where x.lead_id = s.lead_id and x.created_at > now() - make_interval(months => v_months))
            limit p_limit loop
    update b2c.leads_state set dormant_at = now(), journey = null where lead_id = r.lead_id;
    perform b2c.journey_exit(r.lead_id, 'dormant');
    insert into b2c.activities (lead_id, kind, body) values (r.lead_id, 'system', 'Dormant: no response for ' || v_months || ' months. No more messages.');
    n := n + 1;
  end loop;
  return n;
end $f$;

create or replace function b2c.nurture_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('journeys', b2c.journey_tick(300)); exception when others then v := v || jsonb_build_object('journeys_error', sqlerrm); end;
  begin v := v || jsonb_build_object('campaigns', b2c.campaign_tick()); exception when others then v := v || jsonb_build_object('campaigns_error', sqlerrm); end;
  -- nobody classified it within 10 minutes (no API key, or Claude failed): a person decides
  update b2c.replies set status = 'inbox', method = coalesce(method, 'none') where status = 'pending_ai' and created_at < now() - interval '10 minutes';
  return v;
end $f$;

create or replace function b2c.nightly_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb := '{}'::jsonb; n int; total int := 0;
begin
  loop
    n := b2c.score_decay_tick(500); total := total + n;
    exit when n < 500 or total >= 20000;
    perform pg_sleep(0.2);   -- small batches, never one mass update next to Witty's writes (B9.5)
  end loop;
  v := jsonb_build_object('decayed', total, 'dormant', b2c.dormancy_tick(1000));
  return v;
end $f$;

do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-nurture') then
    perform cron.schedule('b2c-nurture', '* * * * *', 'select b2c.nurture_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-nightly') then
    perform cron.schedule('b2c-nightly', '30 21 * * *', 'select b2c.nightly_tick()');   -- 03:00 IST
  end if;
end $d$;

-- ---------- what the Nurture page shows ----------
create or replace function b2c.nurture_overview() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'pool', (select count(*) from b2c.leads_state where status = 'pool' and deleted_at is null and dormant_at is null and not is_test),
    'dormant', (select count(*) from b2c.leads_state where dormant_at is not null and deleted_at is null and not is_test),
    'by_reason', (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'age', age, 'n', n) order by reason, age), '[]') from (
                   select coalesce(case when pool_reason = 'counsellor_lost' then 'lost: ' || coalesce(sub_stage, '?')
                                        when pool_reason = 'partner_lost' then 'partner lost' else pool_reason end, '?') reason,
                          case when pool_entered_at > now() - interval '30 days' then '0–30 days' when pool_entered_at > now() - interval '90 days' then '31–90 days'
                               when pool_entered_at > now() - interval '180 days' then '91–180 days' else 'over 180 days' end age, count(*) n
                     from b2c.leads_state where status = 'pool' and deleted_at is null and dormant_at is null and not is_test group by 1, 2) q),
    'flow_14d', (select coalesce(jsonb_agg(jsonb_build_object('day', d::date,
                    'in', (select count(*) from b2c.leads_state s where not s.is_test and s.pool_entered_at >= d and s.pool_entered_at < d + interval '1 day'),
                    'reengaged', (select count(*) from b2c.leads_state s where not s.is_test and s.reengaged_at >= d and s.reengaged_at < d + interval '1 day')) order by d), '[]')
                 from generate_series(d0 - interval '13 days', d0, interval '1 day') d),
    'reengaged_30d', (select count(*) from b2c.leads_state where reengaged_at > now() - interval '30 days' and not is_test),
    'entered_30d', (select count(*) from b2c.leads_state where pool_entered_at > now() - interval '30 days' and not is_test),
    'hours_to_reengage', (select round(extract(epoch from percentile_cont(0.5) within group (order by reengaged_at - pool_entered_at)) / 3600)
                            from b2c.leads_state where reengaged_at > now() - interval '90 days' and pool_entered_at < reengaged_at and not is_test),
    'messages_today', jsonb_build_object(
       'whatsapp', (select count(*) from b2c.wa_messages where purpose in ('journey', 'campaign', 'marketing') and created_at >= d0),
       'email', (select count(*) from b2c.emails where purpose in ('journey', 'campaign', 'marketing') and created_at >= d0)),
    'email_allowance', jsonb_build_object('limit', coalesce((b2c.setting('messaging') ->> 'gmail_daily_allowance')::int, 2000), 'left', b2c.email_allowance_left()),
    'wa_cost_30d', (select coalesce(sum(cost_estimate), 0) from b2c.wa_messages where purpose in ('journey', 'campaign', 'marketing') and status in ('sent', 'delivered', 'read')
                      and created_at > now() - interval '30 days'),
    'replies_today', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(corrected_class, class, 'unclassified') k, count(*) n from b2c.replies where created_at >= d0 group by 1) r),
    'replies_waiting', (select count(*) from b2c.replies where status in ('inbox', 'pending_ai')),
    'suppressed_today', (select coalesce(jsonb_object_agg(k, n), '{}') from (
                           select k, count(distinct lead_id) n from (
                             select l.detail ->> 'blocked' k, l.lead_id from b2c.journey_log l where l.at >= d0 and l.outcome in ('blocked', 'waiting')
                             union all select x.reason, x.lead_id from b2c.campaign_sends x where x.done_at >= d0 and x.status in ('blocked', 'skipped')) a
                           where k is not null group by k) s),
    'wa_quality', b2c.setting('wa_quality'),
    'journeys_running', (select count(*) from b2c.journey_runs where status = 'running' and not is_test));
end $f$;

/* The pool, lead by lead (B6.2). */
create or replace function b2c.pool_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_limit int := least(coalesce((p ->> 'limit')::int, 100), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0); q text := nullif(trim(p ->> 'q'), '');
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select jsonb_build_object('total', count(*) over (), 'rows', coalesce(jsonb_agg(x), '[]')) from (
    select jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'course', v.course, 'reason', v.pool_reason, 'sub_stage', v.sub_stage, 'lost_by', v.lost_by,
             'lost_detail', coalesce(s.partner_lost ->> 'partner_name', u.full_name), 'lost_reason', coalesce(s.partner_lost ->> 'lost_reason', v.sub_stage),
             'missing', s.missing, 'score', v.score, 'trend_7d', (select coalesce(sum(points), 0) from b2c.score_events e where e.lead_id = v.lead_id and e.at > now() - interval '7 days'),
             'marketing_consent', jsonb_build_object('whatsapp', b2c.has_marketing_consent(v.lead_id, 'whatsapp'), 'email', b2c.has_marketing_consent(v.lead_id, 'email')),
             'journey', (select jsonb_build_object('name', j.name, 'step', r.step_idx + 1, 'status', r.status, 'next_at', r.next_at) from b2c.journey_runs r join b2c.journeys j on j.id = r.journey_id
                          where r.lead_id = v.lead_id and r.status in ('running', 'paused') limit 1),
             'first_message_due_at', s.first_message_due_at, 'pool_entered_at', v.pool_entered_at,
             'last_message', (select jsonb_build_object('channel', 'whatsapp', 'status', m.status, 'at', m.created_at) from b2c.wa_messages m
                               where m.lead_id = v.lead_id and m.direction = 'out' and m.purpose in ('journey', 'campaign', 'marketing') order by m.created_at desc limit 1),
             'last_student_at', (select max(m.created_at) from b2c.wa_messages m where m.lead_id = v.lead_id and m.direction = 'in')) x
      from b2c.leads_v v join b2c.leads_state s on s.lead_id = v.lead_id left join b2c.users u on u.user_id = s.lost_by_user
     where v.status = 'pool' and v.deleted_at is null and s.dormant_at is null and v.is_test = coalesce((p ->> 'test')::boolean, false)
       and (p ->> 'reason' is null or v.pool_reason = p ->> 'reason')
       and (q is null or v.name ilike '%' || q || '%' or v.lead_id::text = q or b2c.norm_phone(v.phone) like '%' || regexp_replace(q, '\D', '', 'g') || '%')
     order by v.pool_entered_at desc nulls last
     limit v_limit offset v_offset) t);
end $f$;

/* The lead's nurture history (lead screen; B9.0 lead-level control). */
create or replace function b2c.lead_nurture(p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'score', (select jsonb_build_object('score', s.score, 'fit', s.fit_points, 'engagement', s.engagement_points, 'band', s.score_band, 'dormant_at', s.dormant_at)
                from b2c.leads_state s where s.lead_id = p_lead),
    'consent', jsonb_build_object('whatsapp', b2c.has_marketing_consent(p_lead, 'whatsapp'), 'email', b2c.has_marketing_consent(p_lead, 'email'),
                                  'history', (select coalesce(jsonb_agg(to_jsonb(c) order by c.at desc), '[]') from b2c.consents c where c.lead_id = p_lead)),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'journey', j.name, 'key', j.key, 'status', r.status, 'step', r.step_idx + 1, 'next_at', r.next_at,
                      'entered_at', r.entered_at, 'exited_at', r.exited_at, 'exit_reason', r.exit_reason,
                      'log', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'step', l.step_idx + 1, 'type', l.step_type, 'outcome', l.outcome, 'detail', l.detail) order by l.at), '[]')
                                from b2c.journey_log l where l.run_id = r.id)) order by r.entered_at desc), '[]')
               from b2c.journey_runs r join b2c.journeys j on j.id = r.journey_id where r.lead_id = p_lead),
    'replies', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]') from b2c.replies x where x.lead_id = p_lead),
    'score_events', (select coalesce(jsonb_agg(to_jsonb(e) order by e.at desc), '[]') from (select * from b2c.score_events e where e.lead_id = p_lead order by e.at desc limit 50) e));
end $f$;

/* A one-off marketing message to one pooled lead from the Nurture page. */
create or replace function b2c.nurture_send(p_lead bigint, p_channel text, p_template bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return case p_channel when 'whatsapp' then b2c.queue_marketing_wa(p_lead, p_template, 'marketing', '{}'::jsonb, false)
                        else b2c.queue_marketing_email(p_lead, p_template, 'marketing', '{}'::jsonb, false) end;
end $f$;

/* Hand a pooled lead to a counsellor now (B9.0). */
create or replace function b2c.nurture_handover(p_lead bigint, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('journey_membership');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'say why'; end if;
  return b2c.reengage(p_lead, 'handed over: ' || left(p_reason, 100));
end $f$;

-- ---------- grants ----------
alter table b2c.score_rules enable row level security;
alter table b2c.score_events enable row level security;
alter table b2c.reply_rules enable row level security;
alter table b2c.replies enable row level security;
grant select on b2c.score_rules, b2c.reply_rules, b2c.score_events, b2c.replies to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'score_rules' and policyname = 'staff read') then
    create policy "staff read" on b2c.score_rules for select to authenticated using ((select b2c.is_staff()));
    create policy "marketing read" on b2c.reply_rules for select to authenticated using ((select b2c.can('marketing')));
    create policy "who may see" on b2c.score_events for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.replies for select to authenticated using ((select b2c.can_see(lead_id)));
  end if;
end $p$;
grant execute on function b2c.score_rule_save(text, int, boolean), b2c.replies_list(jsonb), b2c.reply_handle(bigint, text, text), b2c.wa_queue_reply(bigint, text),
  b2c.nurture_overview(), b2c.pool_list(jsonb), b2c.lead_nurture(bigint), b2c.nurture_send(bigint, text, bigint), b2c.nurture_handover(bigint, text) to authenticated;
revoke execute on function b2c.score_fit(bigint), b2c.score_recompute(bigint), b2c.score_add(bigint, text, numeric, jsonb), b2c.score_decay_tick(int), b2c.reply_act(bigint),
  b2c.reply_receive(bigint, text, text, text, jsonb), b2c.reply_classify_take(int), b2c.reply_classify_done(jsonb), b2c.email_event(bigint, text, text),
  b2c.email_inbound(text, text, text, text, text), b2c.dormancy_tick(int), b2c.nurture_tick(), b2c.nightly_tick(), b2c.notify_marketing(text, text, text, text, bigint, text),
  b2c.lead_records_fit() from public, authenticated;
grant execute on function b2c.reply_classify_take(int), b2c.reply_classify_done(jsonb), b2c.email_event(bigint, text, text), b2c.email_inbound(text, text, text, text, text),
  b2c.wa_template_status(text, text, text, text, text) to service_role;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
