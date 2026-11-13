-- =====================================================================================================================
-- Rollback of web16 (20261113100000_web16_audit_fixes.sql). Restores the previous definitions (verbatim from the
-- migrations named below, which is what production ran before web16), then removes what web16 added: web_lead_tie,
-- web_code_cap_state, web_code_cap_value, web_code_cap_hit, table web_code_cap_hits (ceiling refusal counters only),
-- web_outbox_mark_sent and column web_outbox.sent_steps, index web_verification_codes_canon_idx, web_email_canonical
-- and the setting code_send_daily_cap. Opt-out requests recorded meanwhile stay in web_deletion_requests. Generated
-- from the migration files; run in a transaction:
--   psql "<url>" -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261113100000_web16_audit_fixes.rollback.sql
-- =====================================================================================================================

-- web_gate_start: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_gate_start(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(p->>'email'));
  v_attempt public.web_gate_attempts;
  v_recent int;
  v_screen jsonb;
begin
  v_screen := public.web_email_screen(v_email, p->>'phone', p->>'ip_hash');
  if not (v_screen->>'ok')::boolean then return v_screen; end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_email and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  -- web14: site-wide hourly ceiling
  if public.web_code_cap_reached() then return jsonb_build_object('ok', false, 'reason', 'site_busy'); end if;

  insert into public.web_gate_attempts as a (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version,
    consent_marketing, attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', v_email, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash',
    (p->>'turnstile_ok')::boolean, coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do update set
    full_name = excluded.full_name, email_norm = excluded.email_norm, phone_e164 = excluded.phone_e164,
    consent_version = excluded.consent_version, consent_marketing = excluded.consent_marketing, context = excluded.context,
    junk_score = excluded.junk_score, junk_reasons = excluded.junk_reasons, submitted_at = now()
  where a.verified_at is null
  returning * into v_attempt;
  if v_attempt.id is null then
    select * into v_attempt from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_attempt.id);
  end if;

  update public.web_verification_codes set consumed_at = now() where attempt_id = v_attempt.id and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (v_attempt.id, 'email', v_email, p->>'code_hash', now() + interval '10 minutes', now() + interval '30 seconds');
  update public.web_gate_attempts set code_sent_at = now() where id = v_attempt.id;
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', v_attempt.id, 'resend_in', 30);
end $$;

-- web_gate_resend: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_gate_resend(p_attempt uuid, p_code_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_last public.web_verification_codes; v_recent int;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt;
  if v_a.id is null or v_a.verified_at is not null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select * into v_last from public.web_verification_codes where attempt_id = p_attempt order by created_at desc limit 1;
  if v_last.resend_after > now() then
    return jsonb_build_object('ok', false, 'reason', 'too_soon', 'resend_in', ceil(extract(epoch from v_last.resend_after - now())));
  end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_a.email_norm and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  -- web14: site-wide hourly ceiling
  if public.web_code_cap_reached() then return jsonb_build_object('ok', false, 'reason', 'site_busy'); end if;
  update public.web_verification_codes set consumed_at = now() where attempt_id = p_attempt and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (p_attempt, 'email', v_a.email_norm, p_code_hash, now() + interval '10 minutes', now() + interval '30 seconds');
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', p_attempt, 'resend_in', 30, 'email', v_a.email_norm);
end $$;

-- web_code_cap_reached: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_code_cap_reached()
returns boolean language sql stable security definer set search_path = '' as $$
  with cap as (
    select coalesce((select least(floor((s.value #>> '{}')::numeric), 1000000)::int from public.web_settings s
                      where s.key = 'code_send_hourly_cap' and jsonb_typeof(s.value) = 'number' and (s.value #>> '{}')::numeric >= 0), 200) as n
  )
  select (select count(*) from (select 1 from public.web_verification_codes c
                                 where c.created_at > now() - interval '1 hour' limit (select n from cap)) x) >= (select n from cap)
$$;

-- web_lead_intake: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_lead_intake(p jsonb, p_verified_email text)
returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_phone text := public.crm_norm_phone(p->>'phone');
  v_email text := lower(btrim(coalesce(p_verified_email, '')));
  v_lead public.student_leads;
  v_why text;
  v_p jsonb := p;
begin
  if v_phone is not null and length(v_phone) >= 10 then
    v_lead := public.crm_find_lead(v_phone);
  end if;
  if v_lead.id is not null then
    v_why := case
      when v_email = '' then 'email_not_verified'
      when coalesce(v_lead.email_confirmed, false) and lower(btrim(coalesce(v_lead.email_id, ''))) <> v_email then 'other_confirmed_email'
      when v_lead.enrollment_status is not null then 'enrolled'
      when coalesce(public.w2_crm_owned(v_phone), false) then 'crm_owned'
    end;
  end if;
  if v_why is not null then
    v_p := v_p || jsonb_build_object('source_system', 'web_agent_unverified');
    if v_lead.lead_status is not null and jsonb_typeof(v_p->'lead') = 'object' then
      v_p := jsonb_set(v_p, '{lead}', (v_p->'lead') - 'classification' - 'lead_status');
    end if;
  end if;
  return public.lead_intake(v_p) || jsonb_build_object('web_trust', coalesce(v_why, 'trusted'));
end $$;

-- web_gate_start_trusted: as in 20261017100600_web7_students_leads.sql
create or replace function public.web_gate_start_trusted(p jsonb, p_student uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid; s public.web_students;
begin
  select * into s from public.web_students where id = p_student and deleted_at is null;
  if s.id is null or s.email_norm <> lower(btrim(p->>'email')) then return jsonb_build_object('ok', false, 'reason', 'session_mismatch'); end if;
  insert into public.web_gate_attempts (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version, consent_marketing,
    attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', s.email_norm, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash', (p->>'turnstile_ok')::boolean,
    coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_id);
  end if;
  return public.web_gate_complete(v_id, null, 'session') || jsonb_build_object('attempt_id', v_id);
end $$;

-- web_consent_withdraw: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_consent_withdraw(p_student uuid, p_purposes text[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.web_students; v_res jsonb;
begin
  select * into s from public.web_students where id = p_student;
  if s.id is null then return jsonb_build_object('ok', false); end if;
  update public.web_consents set withdrawn_at = now() where student_id = p_student and withdrawn_at is null and purposes && p_purposes;
  if p_purposes && array['sales', 'partner_share'] and s.phone_e164 is not null then
    v_res := public.web_lead_intake(jsonb_build_object('phone', s.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.opted_out',
      'lead', jsonb_build_object('is_opted_out', true), 'idempotency_key', 'web:optout:' || p_student::text || ':' || extract(epoch from now())::bigint), s.email_norm);
  end if;
  insert into public.web_audit_log (action, entity, entity_id, after) values ('student.consent_withdrawn', 'web_students', p_student::text, to_jsonb(p_purposes));
  return jsonb_build_object('ok', true, 'lead', v_res);
end $$;

-- web_health: as in 20261017101100_web12_catalog_sync.sql
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

-- web_admin_setting: as in 20261031100000_web14_audit_limits.sql
create or replace function public.web_admin_setting(p_key text, p_value jsonb, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.web_admin_role_ok(p_role, case when p_key in ('web_advisor_enabled', 'require_phone_otp', 'push_unverified_gate_leads',
      'push_unverified_after_minutes', 'document_upload_enabled', 'lead_writer', 'web_advisor_models', 'web_advisor_budget',
      'code_send_hourly_cap', 'web_advisor_daily_cap', 'internal_base_url', 'transcript_target') then 'super_admin' else 'content_editor' end) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  -- web_settings_set keeps the history and writes the audit row.
  perform public.web_settings_set(p_key, p_value, p_actor, p_actor_email);
  return jsonb_build_object('ok', true);
end $$;

-- web_search: as in 20261017100300_web4_read_model.sql
create or replace function public.web_search(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb := public.web_resolve_query(p->>'q');
  r_prog text[] := public.web_jarr(v_res->'programme');
  r_spec text[] := public.web_jarr(v_res->'specialisation');
  r_uni text[] := public.web_jarr(v_res->'university');
  r_level text[] := public.web_jarr(v_res->'level');
  r_cat text[] := public.web_jarr(v_res->'category');
  r_mode text[] := public.web_jarr(v_res->'mode');
  a_level text[] := public.web_jarr(p->'level');
  a_cat text[] := public.web_jarr(p->'category');
  a_prog text[] := public.web_jarr(p->'programme');
  a_spec text[] := public.web_jarr(p->'spec');
  a_uni text[] := public.web_jarr(p->'university');
  a_mode text[] := public.web_jarr(p->'mode');
  a_dur text[] := public.web_jarr(p->'duration');
  a_naac text[] := public.web_jarr(p->'naac');
  a_minq text[] := public.web_jarr(p->'min_q');
  a_state text[] := public.web_jarr(p->'state');
  a_format text[] := public.web_jarr(p->'format');
  v_fee_min numeric := nullif(p->>'fee_min', '')::numeric;
  v_fee_max numeric := nullif(p->>'fee_max', '')::numeric;
  v_ugc boolean := coalesce((p->>'ugc_deb')::boolean, false);
  v_aicte boolean := coalesce((p->>'aicte')::boolean, false);
  v_nirf boolean := coalesce((p->>'nirf')::boolean, false);
  v_work text := nullif(p->>'work_exp', '');
  v_entr text := nullif(p->>'entrance', '');
  v_goal text := nullif(p->>'goal', '');
  v_qual text := nullif(p->>'qual', '');
  v_show_inel boolean := coalesce((p->>'show_ineligible')::boolean, false);
  v_sort text := coalesce(nullif(p->>'sort', ''), 'relevance');
  v_view text := coalesce(nullif(p->>'view', ''), 'grouped');
  v_group text := nullif(p->>'group_key', '');
  v_incl boolean := coalesce((p->>'include_offerings')::boolean, false) or v_group is not null;
  v_size int := least(100, greatest(1, coalesce(nullif(p->>'page_size', '')::int, 20)));
  v_page int := greatest(1, coalesce(nullif(p->>'page', '')::int, 1));
  g_prog text[]; g_spec text[];
  v_words text[] := public.web_jarr(v_res->'unmatched');
  v_used text[] := '{}'; v_ignored text[] := '{}'; w text; v_tsq tsquery; v_nomatch boolean := false;
  v_out jsonb;
begin
  if v_goal is not null then
    g_prog := array(select programme_id from public.web_tax_tag_links where tag_kind = 'goal' and tag_id = v_goal and programme_id is not null);
    g_spec := array(select specialisation_id from public.web_tax_tag_links where tag_kind = 'goal' and tag_id = v_goal and specialisation_id is not null);
  end if;
  -- Leftover words: kept only if they match some visible offering (prefix match); otherwise reported as ignored.
  foreach w in array coalesce(v_words, '{}') loop
    if exists (select 1 from public.web_offering_search o where o.visible and o.search_doc @@ to_tsquery('simple', quote_literal(w) || ':*')) then
      v_used := v_used || w;
    else
      v_ignored := v_ignored || w;
    end if;
  end loop;
  if cardinality(v_used) > 0 then
    v_tsq := to_tsquery('simple', array_to_string(array(select quote_literal(x) || ':*' from unnest(v_used) x), ' & '));
  end if;
  -- A query made only of unknown words matches nothing (the zero-results path then offers the closest matches).
  v_nomatch := public.web_norm(p->>'q') is not null and cardinality(v_used) = 0
    and r_prog is null and r_spec is null and r_uni is null and r_level is null and r_cat is null and r_mode is null
    and cardinality(coalesce(v_ignored, '{}')) > 0;

  with b as materialized (
    -- The query (text + resolved entities) narrows everything, facets included; filters are recorded per row as the
    -- list of facets the row fails, so each facet can be counted with every other filter applied (spec 6.3).
    select x.*, array_remove(array[
        case when not (a_level is null or x.level_id = any(a_level)) then 'level' end,
        case when not (a_cat is null or x.category_id = any(a_cat)) then 'category' end,
        case when not (a_prog is null or x.programme_id = any(a_prog)) then 'programme' end,
        case when not (a_spec is null or x.spec_ids && a_spec) then 'spec' end,
        case when not (a_uni is null or x.uni_slug = any(a_uni)) then 'university' end,
        case when not (a_mode is null or x.mode = any(a_mode)) then 'mode' end,
        case when not coalesce((v_fee_min is null or x.fee_total >= v_fee_min) and (v_fee_max is null or x.fee_total <= v_fee_max), false) then 'fee' end,
        case when not coalesce(a_dur is null or x.dur_bucket = any(a_dur), false) then 'duration' end,
        case when not coalesce(a_naac is null or x.naac_grade = any(a_naac), false) then 'naac' end,
        case when v_ugc and x.ugc_deb is null then 'ugc_deb' end,
        case when v_aicte and not x.aicte then 'aicte' end,
        case when v_nirf and not x.nirf_ranked then 'nirf' end,
        case when not coalesce(a_minq is null or x.min_qualification = any(a_minq), false) then 'min_q' end,
        case when not (v_work is null or (v_work = 'required' and x.work_exp) or (v_work = 'not_required' and not x.work_exp)) then 'work_exp' end,
        case when not (v_entr is null or (v_entr = 'yes' and x.entrance_exam is true) or (v_entr = 'no' and x.entrance_exam is false)) then 'entrance' end,
        case when not coalesce(a_state is null or x.uni_state = any(a_state), false) then 'state' end,
        case when not (a_format is null or coalesce(x.format, 'standard') = any(a_format)) then 'format' end,
        case when not (v_goal is null or v_goal = any(x.goal_ids)) then 'goal' end,
        case when v_group is not null and x.group_key <> v_group then 'group' end,
        case when not (v_qual is null or v_show_inel or x.elig <> 'not_eligible') then 'elig' end
      ], null) as fails
    from (
      select o.id, o.group_key, o.programme_id, o.level_id, o.category_id, o.spec_ids, o.university_id, o.uni_slug,
             o.uni_state, o.mode, o.fee_total, o.fee_on_request, o.duration_months, public.web_duration_bucket(o.duration_months) as dur_bucket,
             o.naac_grade, o.naac_rank, o.nirf_rank, o.nirf_ranked, o.ugc_deb, o.aicte, o.min_qualification,
             coalesce(o.work_exp_years, 0) > 0 as work_exp, o.entrance_exam, o.format, o.goal_ids, o.popularity,
             o.level_sort, o.programme_sort,
             public.web_eligibility(v_qual, o.level_id, o.min_qualification) as elig,
             (case when r_prog is not null and o.programme_id = any(r_prog) then 100 else 0 end
              + case when r_spec is not null and o.spec_ids && r_spec then 80 else 0 end
              + case when r_uni is not null and o.university_id::text = any(r_uni) then 50 else 0 end
              + case when v_tsq is not null then ts_rank(o.search_doc, v_tsq) * 20 else 0 end
              + o.popularity + o.naac_rank * 0.1 + o.programme_prior * 0.05)::numeric as score
      from public.web_offering_search o
      where o.visible and not v_nomatch
        and (r_prog is null or o.programme_id = any(r_prog))
        and (r_spec is null or o.spec_ids && r_spec)
        and (r_uni is null or o.university_id::text = any(r_uni))
        and (r_level is null or o.level_id = any(r_level))
        and (r_cat is null or o.category_id = any(r_cat))
        and (r_mode is null or o.mode = any(r_mode))
        and (v_tsq is null or o.search_doc @@ v_tsq)
    ) x
  ),
  ok as materialized (select * from b where cardinality(fails) = 0),
  one as materialized (select * from b where cardinality(fails) = 1),
  -- Facet counts. Rows passing every filter count towards every facet (one pass with grouping sets); rows failing
  -- exactly one filter count only towards that facet.
  counts_ok as (
    select case
             when grouping(level_id) = 0 then 'level' when grouping(category_id) = 0 then 'category'
             when grouping(programme_id) = 0 then 'programme' when grouping(uni_slug) = 0 then 'university'
             when grouping(mode) = 0 then 'mode' when grouping(dur_bucket) = 0 then 'duration'
             when grouping(naac_grade) = 0 then 'naac' when grouping(min_qualification) = 0 then 'min_q'
             when grouping(uni_state) = 0 then 'state' when grouping(fmt) = 0 then 'format'
             when grouping(ugc) = 0 then 'ugc_deb' when grouping(aicte) = 0 then 'aicte' when grouping(nirf_ranked) = 0 then 'nirf'
             when grouping(work_exp) = 0 then 'work_exp' when grouping(entrance_exam) = 0 then 'entrance'
             when grouping(elig) = 0 then 'elig' end as facet,
           coalesce(level_id, category_id, programme_id, uni_slug, mode, dur_bucket, naac_grade, min_qualification, uni_state, fmt,
             case when grouping(ugc) = 0 then ugc::text end, case when grouping(aicte) = 0 then aicte::text end,
             case when grouping(nirf_ranked) = 0 then nirf_ranked::text end, case when grouping(work_exp) = 0 then work_exp::text end,
             case when grouping(entrance_exam) = 0 then entrance_exam::text end, elig) as value,
           count(*) as n
    from (select ok.*, coalesce(ok.format, 'standard') as fmt, ok.ugc_deb is not null as ugc from ok) z
    group by grouping sets ((level_id), (category_id), (programme_id), (uni_slug), (mode), (dur_bucket), (naac_grade),
      (min_qualification), (uni_state), (fmt), (ugc), (aicte), (nirf_ranked), (work_exp), (entrance_exam), (elig))
    union all
    select 'spec', s, count(*) from ok, unnest(ok.spec_ids) s group by 2
    union all
    select 'goal', g, count(*) from ok, unnest(ok.goal_ids) g group by 2
  ),
  counts_one as (
    select one.fails[1] as facet,
      case one.fails[1] when 'level' then one.level_id when 'category' then one.category_id when 'programme' then one.programme_id
        when 'university' then one.uni_slug when 'mode' then one.mode when 'duration' then one.dur_bucket
        when 'naac' then one.naac_grade when 'min_q' then one.min_qualification when 'state' then one.uni_state
        when 'format' then coalesce(one.format, 'standard') when 'ugc_deb' then (one.ugc_deb is not null)::text
        when 'aicte' then one.aicte::text when 'nirf' then one.nirf_ranked::text when 'work_exp' then one.work_exp::text
        when 'entrance' then one.entrance_exam::text when 'elig' then one.elig end as value,
      count(*) as n
    from one where one.fails[1] not in ('spec', 'goal', 'fee', 'group') group by 1, 2
    union all
    select 'spec', s, count(*) from one, unnest(one.spec_ids) s where one.fails[1] = 'spec' group by 2
    union all
    select 'goal', g, count(*) from one, unnest(one.goal_ids) g where one.fails[1] = 'goal' group by 2
  ),
  counts as (select facet, value, sum(n)::int as n from (select * from counts_ok union all select * from counts_one) u
             where value is not null group by 1, 2),
  grp as (
    select ok.group_key as key, min(ok.id) as rep_id, count(*) as offerings, count(distinct ok.university_id) as universities,
      min(ok.fee_total) as fee_min, max(ok.fee_total) as fee_max, min(ok.duration_months) as dur_min, max(ok.duration_months) as dur_max,
      max(ok.naac_rank) as best_naac, max(ok.score) as score, sum(ok.popularity) as pop,
      min(ok.programme_sort) as psort, min(ok.level_sort) as lsort,
      count(*) filter (where ok.elig = 'eligible') as n_eligible, count(*) filter (where ok.elig = 'check') as n_check,
      count(*) filter (where ok.elig = 'not_eligible') as n_not_eligible,
      array_agg(distinct ok.mode) as modes, bool_or(ok.fee_on_request) as some_on_request
    from ok group by ok.group_key
  ),
  grp_page as materialized (
    select grp.*, row_number() over (order by
      case when v_sort = 'fee_asc' then fee_min end asc nulls last,
      case when v_sort = 'fee_desc' then fee_max end desc nulls last,
      case when v_sort = 'naac' then best_naac end desc nulls last,
      case when v_sort = 'duration' then dur_min end asc nulls last,
      case when v_sort = 'popularity' then pop end desc nulls last,
      score desc, pop desc, offerings desc, lsort, psort, key) as ord
    from grp
    order by ord limit case when v_view = 'flat' then 0 else v_size end offset (v_page - 1) * v_size
  ),
  top_u as (
    select t.group_key, jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', m.uni_slug, 'name', m.uni_name, 'short', m.uni_short,
             'logo', m.uni_logo, 'naac_grade', m.naac_grade)) order by t.rk) as unis
    from (
      select d.group_key, d.id, row_number() over (partition by d.group_key order by d.naac_rank desc, d.nirf_rank asc nulls last, d.university_id) as rk
      from (select distinct on (ok.group_key, ok.university_id) ok.group_key, ok.university_id, ok.id, ok.naac_rank, ok.nirf_rank
            from ok where ok.group_key in (select key from grp_page) order by ok.group_key, ok.university_id, ok.fee_total) d) t
    join public.web_offering_search m on m.id = t.id
    where t.rk <= 3 group by t.group_key
  ),
  flat_page as materialized (
    select ok.id, ok.elig, ok.group_key, row_number() over (order by
      case when v_sort = 'fee_asc' then ok.fee_total end asc nulls last,
      case when v_sort = 'fee_desc' then ok.fee_total end desc nulls last,
      case when v_sort = 'naac' then ok.naac_rank end desc nulls last,
      case when v_sort = 'duration' then ok.duration_months end asc nulls last,
      case when v_sort = 'popularity' then ok.popularity end desc nulls last,
      ok.score desc, ok.naac_rank desc, ok.fee_total asc nulls last, ok.id) as ord
    from ok
    where v_view = 'flat' or (v_incl and ok.group_key in (select key from grp_page))
    order by ord limit case when v_view = 'flat' then v_size else 10000 end offset case when v_view = 'flat' then (v_page - 1) * v_size else 0 end
  ),
  cards as (
    select fp.group_key, fp.ord, public.web_offering_card(o, fp.elig) as card
    from flat_page fp join public.web_offering_search o on o.id = fp.id
  ),
  fv as (select * from public.web_facet_values)
  select jsonb_build_object(
    'total', (select count(*) from ok),
    'total_groups', (select count(*) from grp),
    'page', v_page, 'page_size', v_size, 'view', v_view, 'sort', v_sort,
    'items', case when v_view = 'flat' then coalesce((select jsonb_agg(card order by ord) from cards), '[]')
      else coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'key', g.key, 'programme_id', m.programme_id, 'programme_name', m.programme_name, 'programme_full', m.programme_full,
          'level_id', m.level_id, 'level_short', m.level_short, 'level_label', m.level_label, 'category_id', m.category_id,
          'spec_ids', to_jsonb(m.spec_ids), 'spec_name', m.spec_name,
          'offerings', g.offerings, 'universities', g.universities, 'fee_min', g.fee_min, 'fee_max', g.fee_max,
          'duration_min', g.dur_min, 'duration_max', g.dur_max,
          'best_naac', case g.best_naac when 7 then 'A++' when 6 then 'A+' when 5 then 'A' when 4 then 'B++' when 3 then 'B+' when 2 then 'B' when 1 then 'C' end,
          'modes', to_jsonb(g.modes), 'some_fee_on_request', case when g.some_on_request then true end,
          'eligibility', case when v_qual is not null then jsonb_build_object('eligible', g.n_eligible, 'check', g.n_check, 'not_eligible', g.n_not_eligible) end,
          'top_universities', (select tu.unis from top_u tu where tu.group_key = g.key),
          'items', case when v_incl then (select jsonb_agg(c.card order by (c.card->'fee'->>'total')::numeric asc nulls last, c.card->'university'->>'name')
                                          from cards c where c.group_key = g.key) end
        )) order by g.ord) from grp_page g join public.web_offering_search m on m.id = g.rep_id), '[]') end,
    'facets', jsonb_build_object(
      'level', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'level' and c.value = fv.value where fv.facet = 'level'),
      'category', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by k.sort), '[]')
                from fv join public.web_tax_categories k on k.id = fv.value left join counts c on c.facet = 'category' and c.value = fv.value where fv.facet = 'category'),
      'programme', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'full', p2.full_name, 'level', p2.level_id,
                     'count', coalesce(c.n, 0)) order by lv.sort, p2.sort, fv.label), '[]')
                from fv join public.web_tax_programmes p2 on p2.id = fv.value join public.web_tax_levels lv on lv.id = p2.level_id
                left join counts c on c.facet = 'programme' and c.value = fv.value where fv.facet = 'programme'),
      'spec', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0))
                     order by coalesce(c.n, 0) desc, fv.label), '[]')
                from fv left join counts c on c.facet = 'spec' and c.value = fv.value where fv.facet = 'spec'),
      'university', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.label), '[]')
                from fv left join counts c on c.facet = 'university' and c.value = fv.value where fv.facet = 'university'),
      'mode', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'mode' and c.value = fv.value where fv.facet = 'mode'),
      'naac', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'naac' and c.value = fv.value where fv.facet = 'naac'),
      'min_q', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'min_q' and c.value = fv.value where fv.facet = 'min_q'),
      'state', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.label), '[]')
                from fv left join counts c on c.facet = 'state' and c.value = fv.value where fv.facet = 'state'),
      'duration', (select jsonb_agg(jsonb_build_object('value', d.v, 'label', d.l, 'count', coalesce(c.n, 0)) order by d.s)
                from (values ('le12', 'Up to 1 year', 1), ('13-24', '1–2 years', 2), ('25-36', '2–3 years', 3), ('gt36', 'More than 3 years', 4)) d(v, l, s)
                left join counts c on c.facet = 'duration' and c.value = d.v),
      'format', (select jsonb_agg(jsonb_build_object('value', f.id, 'label', f.label, 'count', coalesce(c.n, 0)) order by f.s)
                from (select 'standard' id, 'Standard' label, 0 s union all select id, label, 1 from public.web_tax_formats) f
                left join counts c on c.facet = 'format' and c.value = f.id),
      'goal', (select coalesce(jsonb_agg(jsonb_build_object('value', t.id, 'label', t.label, 'count', coalesce(c.n, 0)) order by t.sort), '[]')
                from public.web_tax_goal_tags t left join counts c on c.facet = 'goal' and c.value = t.id where t.active),
      'fee', coalesce((select jsonb_build_object('min', min(z.fee_total), 'max', max(z.fee_total), 'on_request', count(*) filter (where z.fee_total is null),
                'global_min', gb.lo, 'global_max', gb.hi,
                'histogram', (select jsonb_agg(coalesce(h.n, 0) order by k.i) from generate_series(0, 15) k(i)
                              left join (select least(15, floor((z2.fee_total - gb.lo) / nullif(gb.hi - gb.lo, 0) * 16))::int as i, count(*) n
                                         from (select fee_total from ok union all select fee_total from one where one.fails[1] = 'fee') z2
                                         where z2.fee_total is not null group by 1) h on h.i = k.i))
              from (select fee_total from ok union all select fee_total from one where one.fails[1] = 'fee') z,
                   (select min(fee_total) lo, max(fee_total) hi from public.web_offering_search where visible) gb
              group by gb.lo, gb.hi),
              jsonb_build_object('min', null, 'max', null, 'on_request', 0, 'global_min', (select min(fee_total) from public.web_offering_search where visible),
                'global_max', (select max(fee_total) from public.web_offering_search where visible), 'histogram', '[]'::jsonb)),
      'ugc_deb', coalesce((select n from counts where facet = 'ugc_deb' and value = 'true'), 0),
      'aicte', coalesce((select n from counts where facet = 'aicte' and value = 'true'), 0),
      'nirf', coalesce((select n from counts where facet = 'nirf' and value = 'true'), 0),
      'work_exp', jsonb_build_object('required', coalesce((select n from counts where facet = 'work_exp' and value = 'true'), 0),
                                     'not_required', coalesce((select n from counts where facet = 'work_exp' and value = 'false'), 0)),
      'entrance', jsonb_build_object('yes', coalesce((select n from counts where facet = 'entrance' and value = 'true'), 0),
                                     'no', coalesce((select n from counts where facet = 'entrance' and value = 'false'), 0)),
      'eligibility', case when v_qual is not null then jsonb_build_object(
                'eligible', coalesce((select n from counts where facet = 'elig' and value = 'eligible'), 0),
                'check', coalesce((select n from counts where facet = 'elig' and value = 'check'), 0),
                'not_eligible', coalesce((select n from counts where facet = 'elig' and value = 'not_eligible'), 0)) end
    ),
    'relaxations', (select coalesce(jsonb_agg(jsonb_build_object('filter', r.f, 'count', r.n) order by r.n desc), '[]')
                    from (select one.fails[1] f, count(*) n from one where one.fails[1] <> 'group' group by 1) r
                    where not exists (select 1 from ok)),
    'resolved', v_res - 'unmatched' || jsonb_build_object('used_words', to_jsonb(v_used), 'ignored_words', to_jsonb(v_ignored))
  ) into v_out;

  -- Zero results caused by the text itself: how many results without the query, and the closest matches.
  if (v_out->>'total')::int = 0 and public.web_norm(p->>'q') is not null then
    v_out := v_out || jsonb_build_object(
      'without_query', (public.web_search((p - 'q') || '{"page_size":1}'::jsonb))->'total',
      'closest', coalesce((select jsonb_agg(public.web_offering_card(x, null)) from (
          select o.* from public.web_offering_search o where o.visible
          order by o.search_text operator(public.<->) public.web_norm(p->>'q'), o.naac_rank desc limit 5) x), '[]'));
  end if;
  return v_out;
end $$;

drop function if exists public.web_outbox_mark_sent(bigint, text);
alter table public.web_outbox drop column if exists sent_steps;
drop function if exists public.web_lead_tie(text, text);
drop function if exists public.web_code_cap_hit(text);
drop function if exists public.web_code_cap_state();
drop function if exists public.web_code_cap_value(text, integer);
drop table if exists public.web_code_cap_hits;
drop index if exists public.web_verification_codes_canon_idx;
drop function if exists public.web_email_canonical(text);
delete from public.web_settings where key = 'code_send_daily_cap';
