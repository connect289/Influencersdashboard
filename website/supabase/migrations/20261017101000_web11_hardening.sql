-- =====================================================================================================================
-- web11 · Phase 12 hardening (docs/SECURITY_REVIEW.md). Website objects only; no shared object is touched.
--   M2  callback requests: one per student, day and slot; at most 3 a day (each one reaches the shared lead).
--   L2  redirects: targets must be a same-site path or an https URL (no //host, no backslashes, no whitespace).
--   L4  404 log: rows not seen for 90 days are pruned by the daily SEO job.
--   L11 fee lines: allow-list by shape instead of a denylist.
--   L13 first admin sign-in links only a confirmed auth email.
-- =====================================================================================================================

-- M2
delete from public.web_callback_requests a using public.web_callback_requests b
 where a.student_id = b.student_id and a.slot_date = b.slot_date and a.slot = b.slot and a.id > b.id;
create unique index if not exists web_callback_requests_slot_uidx on public.web_callback_requests (student_id, slot_date, slot);

create or replace function public.web_callback_request(p_student uuid, p_session uuid, p_date date, p_slot text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st public.web_students; v_id bigint; v_res jsonb; v_label text;
begin
  select * into st from public.web_students where id = p_student and deleted_at is null;
  if st.id is null or st.phone_e164 is null then return jsonb_build_object('ok', false, 'reason', 'no_phone'); end if;
  if p_date < (now() at time zone 'Asia/Kolkata')::date or p_date > (now() at time zone 'Asia/Kolkata')::date + 14 then
    return jsonb_build_object('ok', false, 'reason', 'bad_date');
  end if;
  v_label := 'Callback ' || to_char(p_date, 'Dy DD Mon') || ', ' || case p_slot when 'morning' then 'morning (9am–12pm)' when 'afternoon' then 'afternoon (12–4pm)' else 'evening (4–8pm)' end;
  -- The same slot again: already booked, nothing new reaches the lead. At most 3 requests a day per student.
  select id into v_id from public.web_callback_requests where student_id = p_student and slot_date = p_date and slot = p_slot;
  if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'duplicate', true); end if;
  if (select count(*) from public.web_callback_requests where student_id = p_student and created_at > now() - interval '1 day') >= 3 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;
  insert into public.web_callback_requests (student_id, session_id, lead_id, slot_date, slot)
  values (p_student, p_session, st.lead_id, p_date, p_slot)
  on conflict (student_id, slot_date, slot) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'label', v_label, 'duplicate', true); end if;
  v_label := 'Callback ' || to_char(p_date, 'Dy DD Mon') || ', ' || case p_slot when 'morning' then 'morning (9am–12pm)' when 'afternoon' then 'afternoon (12–4pm)' else 'evening (4–8pm)' end;
  v_res := public.lead_intake(jsonb_build_object('phone', st.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.updated',
    'idempotency_key', 'web:callback:' || v_id, 'lead', jsonb_build_object('preferred_call_time', v_label, 'last_intent', 'asks_human')));
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'lead', v_res);
end $$;

-- L2
alter table public.web_redirects drop constraint if exists web_redirects_to_path_check;
alter table public.web_redirects add constraint web_redirects_to_path_check
  check (to_path ~ '^(/([^/\\[:space:]][^\\[:space:]]*)?|https://[^/\\[:space:]?#]+([/?#][^\\[:space:]]*)?)$');

-- L4
create or replace function public.web_404_prune(p_days integer default 90)
returns integer language sql volatile security definer set search_path = '' as $$
  with d as (delete from public.web_404_log where last_seen < now() - make_interval(days => greatest(p_days, 7)) returning 1)
  select count(*)::integer from d
$$;
revoke all on function public.web_404_prune(integer) from public, anon, authenticated;
grant execute on function public.web_404_prune(integer) to service_role;

-- L11
create or replace function public.web_offering_details(p_id bigint, p_qual text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.web_offering_search; c public.catalog_programs; v_fees jsonb; v_facts jsonb; v_moved boolean := false;
begin
  select * into o from public.web_offering_search where id = p_id;
  if o.id is not null and not o.visible then
    select s.* into o from public.web_offering_search s
     where s.visible and s.university_id = o.university_id and s.group_key = o.group_key and s.mode is not distinct from o.mode
     order by s.verified_at desc, s.id desc limit 1;
    v_moved := o.id is not null;
  end if;
  if o.id is null or not o.visible then return null; end if;
  select * into c from public.catalog_programs where id = o.id;
  -- Fee lines students pay; never internal keys (EMI, import notes) or prices of other things.
  select coalesce(jsonb_agg(jsonb_build_object('label', k, 'amount', v) order by k), '[]') into v_fees
  from jsonb_each(coalesce(c.fee_other, '{}')) e(k, v)
  where jsonb_typeof(v) = 'number' and k not in ('Emi', 'as_imported')
    -- allow-list by shape (keys are free text from the catalogue sheet): student-payable lines only; anything that looks
    -- commercial is never shown, even if someone adds it to the sheet
    and k ~* '(fee|semester|\msem\M|year|payment|spilt|split|deposit|charges|tuition|tution)'
    and k !~* '(commission|payout|margin|partner|incentive|discount|net price|cost price|brokerage|referral)';
  select public.web_university_facts(u.accreditation_text, u.recognitions) || coalesce(p.facts_override, '{}') into v_facts
  from public.catalog_universities u left join public.web_university_profiles p on p.catalog_university_id = u.id
  where u.id = o.university_id;
  return public.web_offering_card(o, public.web_eligibility(p_qual, o.level_id, o.min_qualification)) || jsonb_strip_nulls(jsonb_build_object(
    'moved_from', case when v_moved then p_id end,
    'programme_full', o.programme_full, 'level_label', o.level_label, 'category_id', o.category_id,
    'category_label', o.category_label, 'program_name', c.program_name,
    'fee_exam', o.fee_exam, 'fee_registration', o.fee_registration, 'emi_amount', o.emi_amount,
    'fee_lines', case when jsonb_array_length(v_fees) > 0 then v_fees end,
    'duration_source', o.duration_source, 'min_pct_reserved', o.min_pct_reserved,
    'eligibility_text', nullif(btrim(c.eligibility_text), ''), 'brochure_url', o.brochure_url,
    'university_facts', v_facts,
    'alternatives', (select jsonb_agg(public.web_offering_card(a, public.web_eligibility(p_qual, a.level_id, a.min_qualification))
                       order by a.fee_total asc nulls last, a.naac_rank desc)
                     from public.web_offering_search a where a.visible and a.group_key = o.group_key and a.id <> o.id)
  ));
end $$;

-- L13
create or replace function public.web_admin_resolve(p_user_id uuid, p_email text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v public.web_admin_users;
begin
  select * into v from public.web_admin_users where user_id = p_user_id;
  if v.email is null then
    -- First sign-in links the allow-listed email to the auth user only if Supabase Auth has confirmed that address
    -- (the auth record's own email, not just the token claim).
    update public.web_admin_users a set user_id = p_user_id
     where a.email = lower(p_email) and a.user_id is null
       and exists (select 1 from auth.users u where u.id = p_user_id and lower(u.email) = a.email and u.email_confirmed_at is not null)
    returning * into v;
  end if;
  if v.email is null or not v.active then return null; end if;
  return jsonb_build_object('email', v.email, 'role', v.role, 'display_name', v.display_name);
end $$;
