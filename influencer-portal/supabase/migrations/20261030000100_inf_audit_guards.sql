-- Estate audit, 30 Oct 2026: authorization checks in schema inf (no other schema is touched).
-- 1. Seven content and contract functions treat an unknown side as "not allowed" (null-safe side checks).
-- 2. inf.eligibility_gaps is internal: its client grant is withdrawn (only definer functions call it).
-- 3. inf.creator_profile_update applies inf.avatar_set's own-folder rule to avatar_path.
-- 4. inf.kyc_save keeps the KYC proof in the creator's own folder, where the upload URL puts it.
-- 5. inf.thread_post accepts attachment paths only in the shape the app writes: threads/<thread>/<uuid>-<name>.
-- 6. inf.tiers_list answers staff, creators and the service role, as the RLS policy on inf.tiers does.
-- Idempotent (create or replace, delete of one declared grant, apply_client_grants). Inverse statements: see the
-- rollback block at the end.

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Null-safe side checks
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.change_request_create(p_contract uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v_side text := inf.contract_side(p_contract); v_id uuid; v_section jsonb;
begin
  if not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'negotiation is closed' using errcode = '22023'; end if;
  if p ->> 'kind' = 'clause' then
    select s into v_section from inf.contract_versions v, jsonb_array_elements(v.content -> 'sections') s
     where v.id = c.current_version_id and s ->> 'key' = p ->> 'clause_key';
    if v_section is null then raise exception 'no such clause' using errcode = '22023'; end if;
    if not coalesce((v_section ->> 'negotiable')::boolean, false) or coalesce((v_section ->> 'locked')::boolean, false) then
      raise exception 'this clause is not negotiable' using errcode = '22023';
    end if;
  elsif p ->> 'kind' <> 'compensation' then
    raise exception 'invalid change request' using errcode = '22023';
  end if;
  if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending'
              and kind = p ->> 'kind' and coalesce(clause_key, '') = coalesce(p ->> 'clause_key', '')) then
    raise exception 'a request for this is already pending' using errcode = '22023';
  end if;
  insert into inf.contract_change_requests (contract_id, version_id, kind, clause_key, proposed_body, proposed_terms, note, from_side)
  values (c.id, c.current_version_id, p ->> 'kind', nullif(p ->> 'clause_key', ''), p -> 'proposed_body', p -> 'proposed_terms',
          nullif(trim(p ->> 'note'), ''), v_side)
  returning id into v_id;
  update inf.contracts set status = 'in_negotiation' where id = c.id and status in ('sent', 'ready_to_sign');
  perform inf.contract_notify(c.id, 'eduwit', 'contract.change_requested', 'Change requested on ' || c.number,
                              case when p ->> 'kind' = 'clause' then 'Suggested wording for a clause.' else 'A compensation counter-offer.' end);
  return v_id;
end $$;

create or replace function inf.change_request_withdraw(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r inf.contract_change_requests;
begin
  select * into r from inf.contract_change_requests where id = p_request;
  if r.id is null or not coalesce(inf.contract_side(r.contract_id) in ('creator', 'agency'), false) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update inf.contract_change_requests set status = 'withdrawn' where id = p_request and status = 'pending';
end $$;

create or replace function inf.brief_acknowledge(p_brief uuid, p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare b inf.briefs; v_side text; v_first boolean; r record;
begin
  select * into b from inf.briefs where id = p_brief for update;
  v_side := inf.content_side(b.deal_id);
  if b.id is null or not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if b.current_version_id is distinct from p_version then raise exception 'a newer version of the brief exists' using errcode = '22023'; end if;
  v_first := not exists (select 1 from inf.brief_acknowledgements where brief_id = b.id);
  insert into inf.brief_acknowledgements (brief_id, version_id, side) values (b.id, p_version, v_side)
  on conflict (version_id) do nothing;
  if not found then return; end if;
  for r in select * from inf.deliverables where deal_id = b.deal_id and status = 'not_started'
             and coalesce((stages ->> 'brief')::boolean, true) loop
    perform inf.deliverable_apply(r.id, 'acknowledge_brief', 'system', null);
  end loop;
  if v_first then
    perform inf.emit_event('brief.acknowledged', 'brief', b.id::text, jsonb_build_object('deal_id', b.deal_id, 'version_id', p_version),
                           'brief_acknowledged:' || b.id);
  end if;
  perform inf.content_notify(b.deal_id, 'eduwit', 'brief.acknowledged', 'Brief acknowledged', 'The creator has read and acknowledged the brief.',
                             '/creator/briefs/' || b.id, '/admin/briefs/' || b.id, p_version::text);
end $$;

create or replace function inf.deliverable_schedule(p_id uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text;
begin
  select * into x from inf.deliverables where id = p_id;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_at is null or p_at < now() - interval '1 day' then raise exception 'choose a future date' using errcode = '22023'; end if;
  perform inf.deliverable_apply(p_id, 'schedule', v_side, null);
  update inf.deliverables set scheduled_for = p_at where id = p_id;
end $$;

create or replace function inf.submission_add(p_deliverable uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; v_kind text := p ->> 'kind'; v_id uuid; v_file jsonb;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_kind not in ('concept', 'draft') then raise exception 'invalid submission' using errcode = '22023'; end if;
  if coalesce(trim(p ->> 'body'), '') = '' and coalesce(jsonb_array_length(p -> 'files'), 0) = 0 and coalesce(p ->> 'link_url', '') = '' then
    raise exception 'add text, a file or a link' using errcode = '22023';
  end if;
  for v_file in select * from jsonb_array_elements(coalesce(p -> 'files', '[]'::jsonb)) loop
    if coalesce(v_file ->> 'path', '') !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then
      raise exception 'invalid file' using errcode = '22023';
    end if;
  end loop;
  perform inf.deliverable_apply(x.id, 'submit_' || v_kind, v_side, null);
  insert into inf.deliverable_submissions (deliverable_id, kind, version, body, files, link_url, creator_note, author_side)
  values (x.id, v_kind, coalesce((select max(version) from inf.deliverable_submissions where deliverable_id = x.id and kind = v_kind), 0) + 1,
          nullif(trim(p ->> 'body'), ''), coalesce(p -> 'files', '[]'), nullif(trim(p ->> 'link_url'), ''), nullif(trim(p ->> 'note'), ''), v_side)
  returning id into v_id;
  perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.submitted', initcap(v_kind) || ' to review: ' || x.title,
                             'A new submission is waiting for review.', '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
  return v_id;
end $$;

create or replace function inf.post_submit(p_deliverable uuid, p_url text, p_posted_on date, p_oembed jsonb default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; v_id uuid;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_posted_on is null or p_posted_on > (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'the posting date can''t be in the future' using errcode = '22023';
  end if;
  perform inf.deliverable_apply(x.id, 'go_live', v_side, null);
  update inf.published_posts set verification_status = 'replaced' where deliverable_id = x.id and verification_status = 'pending';
  insert into inf.published_posts (deliverable_id, live_url, posted_on, oembed) values (x.id, trim(p_url), p_posted_on, p_oembed)
  returning id into v_id;
  perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.live', 'Live post to verify: ' || x.title, trim(p_url),
                             '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
  return v_id;
end $$;

create or replace function inf.metrics_submit(p_deliverable uuid, p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; pp inf.published_posts; v_id bigint; v_path text;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or not coalesce(v_side in ('creator', 'agency'), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pp from inf.published_posts where deliverable_id = x.id and verification_status <> 'replaced' order by created_at desc limit 1;
  if pp.id is null then raise exception 'submit the live link first' using errcode = '22023'; end if;
  foreach v_path in array coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}') loop
    if v_path !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then raise exception 'invalid file' using errcode = '22023'; end if;
  end loop;
  insert into inf.post_metric_snapshots (deliverable_id, published_post_id, checkpoint, views, reach, likes, comments, shares, saves, clicks,
                                         watch_time_s, source, screenshot_paths)
  values (x.id, pp.id, coalesce(nullif(p ->> 'checkpoint', ''), 'adhoc'), nullif(p ->> 'views', '')::bigint, nullif(p ->> 'reach', '')::bigint,
          nullif(p ->> 'likes', '')::bigint, nullif(p ->> 'comments', '')::bigint, nullif(p ->> 'shares', '')::bigint,
          nullif(p ->> 'saves', '')::bigint, nullif(p ->> 'clicks', '')::bigint, nullif(p ->> 'watch_time_s', '')::bigint,
          case when jsonb_array_length(coalesce(p -> 'screenshots', '[]')) > 0 then 'screenshot' else 'manual' end,
          coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}'))
  returning id into v_id;
  if inf.deliverable_next(x.status, 'submit_metrics', x.stages) is not null then
    perform inf.deliverable_apply(x.id, 'submit_metrics', v_side, null);
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. The avatar path rule of inf.avatar_set also in inf.creator_profile_update
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creator_profile_update(p_creator uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_phone text;
begin
  if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'phone_e164' then
    v_phone := nullif(trim(p ->> 'phone_e164'), '');
    if v_phone is not null and v_phone !~ '^\+[1-9]\d{7,14}$' then raise exception 'invalid phone number' using errcode = '22023'; end if;
  end if;
  if nullif(p ->> 'avatar_path', '') is not null and (p ->> 'avatar_path') !~ ('^' || p_creator::text || '/[0-9]{10,16}\.(jpg|png|webp)$') then
    raise exception 'invalid avatar path' using errcode = '22023';
  end if;
  update inf.creators set
    display_name = coalesce(nullif(trim(p ->> 'display_name'), ''), display_name),
    legal_name = case when p ? 'legal_name' then nullif(trim(p ->> 'legal_name'), '') else legal_name end,
    bio = case when p ? 'bio' then nullif(trim(p ->> 'bio'), '') else bio end,
    city = case when p ? 'city' then nullif(trim(p ->> 'city'), '') else city end,
    state = case when p ? 'state' then nullif(trim(p ->> 'state'), '') else state end,
    phone_e164 = case when p ? 'phone_e164' then v_phone else phone_e164 end,
    languages = case when p ? 'languages' then coalesce((select array_agg(distinct left(trim(x), 40)) from jsonb_array_elements_text(p -> 'languages') x where trim(x) <> ''), '{}') else languages end,
    niches = case when p ? 'niches' then coalesce((select array_agg(distinct left(lower(trim(x)), 40)) from jsonb_array_elements_text(p -> 'niches') x where trim(x) <> ''), '{}') else niches end,
    avatar_path = case when p ? 'avatar_path' then nullif(p ->> 'avatar_path', '') else avatar_path end,
    public_page_enabled = coalesce((p ->> 'public_page_enabled')::boolean, public_page_enabled),
    leaderboard_opt_in = coalesce((p ->> 'leaderboard_opt_in')::boolean, leaderboard_opt_in),
    last_activity_at = now()
  where id = p_creator;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. KYC proof only from the creator's own folder
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.kyc_save(p_creator uuid, p_pan text, p_name_on_pan text, p_gst_status text, p_gstin text,
                                        p_bank_account text, p_ifsc text, p_account_holder text, p_proof_path text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_cur     inf.creator_kyc;
  v_pan     text := upper(nullif(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'), ''));
  v_acct    text := nullif(regexp_replace(coalesce(p_bank_account, ''), '\s', '', 'g'), '');
  v_ifsc    text := upper(nullif(trim(coalesce(p_ifsc, '')), ''));
  v_gstin   text := upper(nullif(trim(coalesce(p_gstin, '')), ''));
  v_status  text := coalesce(nullif(p_gst_status, ''), 'unregistered');
  v_changed boolean;
  v_complete boolean;
  v_pan_eff text;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write') or inf.has_perm('kyc.verify')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_pan is not null and not inf.valid_pan(v_pan) then return jsonb_build_object('ok', false, 'error', 'invalid_pan'); end if;
  if v_acct is not null and v_acct !~ '^\d{9,18}$' then return jsonb_build_object('ok', false, 'error', 'invalid_account'); end if;
  if v_ifsc is not null and not inf.valid_ifsc(v_ifsc) then return jsonb_build_object('ok', false, 'error', 'invalid_ifsc'); end if;
  if v_status not in ('unregistered', 'registered', 'composition') then return jsonb_build_object('ok', false, 'error', 'invalid_gst_status'); end if;
  if v_status <> 'unregistered' and (v_gstin is null or not inf.valid_gstin(v_gstin)) then return jsonb_build_object('ok', false, 'error', 'invalid_gstin'); end if;
  if v_status = 'unregistered' then v_gstin := null; end if;
  -- The proof must be in this creator's own folder of inf-kyc (<creator>/<file>), where the upload URL puts it.
  if nullif(p_proof_path, '') is not null and split_part(p_proof_path, '/', 1) <> p_creator::text then
    return jsonb_build_object('ok', false, 'error', 'invalid_proof');
  end if;

  select * into v_cur from inf.creator_kyc where creator_id = p_creator for update;
  v_pan_eff := coalesce(v_pan, case when v_cur.pan_enc is not null then inf.pii_decrypt(v_cur.pan_enc) end);
  -- GSTIN characters 3–12 are the PAN.
  if v_gstin is not null and v_pan_eff is not null and substr(v_gstin, 3, 10) <> v_pan_eff then
    return jsonb_build_object('ok', false, 'error', 'gstin_pan_mismatch');
  end if;
  v_changed := v_cur.creator_id is not null and (v_pan is not null or v_acct is not null
                 or v_ifsc is distinct from v_cur.ifsc or v_gstin is distinct from v_cur.gstin);

  insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, gst_status, gstin, bank_account_enc, bank_last4, ifsc, account_holder, proof_path)
  values (p_creator, inf.pii_encrypt(v_pan), right(v_pan, 4), nullif(trim(p_name_on_pan), ''), v_status, v_gstin,
          inf.pii_encrypt(v_acct), right(v_acct, 4), v_ifsc, nullif(trim(p_account_holder), ''), nullif(p_proof_path, ''))
  on conflict (creator_id) do update set
    pan_enc = coalesce(excluded.pan_enc, inf.creator_kyc.pan_enc),
    pan_last4 = coalesce(excluded.pan_last4, inf.creator_kyc.pan_last4),
    name_on_pan = coalesce(excluded.name_on_pan, inf.creator_kyc.name_on_pan),
    gst_status = excluded.gst_status,
    gstin = excluded.gstin,
    gstin_verified = case when excluded.gstin is distinct from inf.creator_kyc.gstin then false else inf.creator_kyc.gstin_verified end,
    bank_account_enc = coalesce(excluded.bank_account_enc, inf.creator_kyc.bank_account_enc),
    bank_last4 = coalesce(excluded.bank_last4, inf.creator_kyc.bank_last4),
    ifsc = coalesce(excluded.ifsc, inf.creator_kyc.ifsc),
    account_holder = coalesce(excluded.account_holder, inf.creator_kyc.account_holder),
    proof_path = coalesce(excluded.proof_path, inf.creator_kyc.proof_path);

  select (pan_enc is not null and name_on_pan is not null and bank_account_enc is not null and ifsc is not null and account_holder is not null)
    into v_complete from inf.creator_kyc where creator_id = p_creator;
  update inf.creator_kyc set
    status = case when not v_complete then 'pending'
                  when status = 'verified' and not v_changed then 'verified'
                  else 'submitted' end,
    submitted_at = case when v_complete and (status <> 'verified' or v_changed) then now() else submitted_at end,
    verified_at = case when v_changed then null else verified_at end,
    verified_by = case when v_changed then null else verified_by end,
    rejection_reason = case when v_complete then null else rejection_reason end
  where creator_id = p_creator;
  update inf.creators set last_activity_at = now() where id = p_creator;
  return jsonb_build_object('ok', true, 'status', (select status from inf.creator_kyc where creator_id = p_creator), 'complete', v_complete);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 5. Message attachments: exactly threads/<this thread>/<uuid>-<name>
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.thread_post(p_type text, p_entity uuid, p_body text, p_attachments jsonb default '[]', p_creator uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  v_thread uuid;
  v_msg uuid;
  v_side text;
  v_creator uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_plain text;
  v_user uuid;
  v_sender text;
  a jsonb;
  v_mentions uuid[] := '{}';
begin
  r := inf.thread_resolve(p_type, p_entity, p_creator);
  if r is null or not coalesce((r ->> 'can_post')::boolean, false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(v_body) = 0 and coalesce(jsonb_array_length(p_attachments), 0) = 0 then
    raise exception 'a message is required' using errcode = '22023';
  end if;
  if char_length(v_body) > 4000 then raise exception 'message too long' using errcode = '22023'; end if;
  if coalesce(jsonb_array_length(p_attachments), 0) > 5 then raise exception 'at most 5 attachments' using errcode = '22023'; end if;
  v_side := r ->> 'side';
  v_creator := (r ->> 'creator_id')::uuid;
  insert into inf.threads (entity_type, entity_id, creator_id, staff_only)
  values (p_type, p_entity, v_creator, (r ->> 'staff_only')::boolean)
  on conflict (entity_type, entity_id, coalesce(creator_id, '00000000-0000-0000-0000-000000000000'::uuid)) do nothing;
  select id into v_thread from inf.threads
   where entity_type = p_type and entity_id = p_entity and creator_id is not distinct from v_creator;
  insert into inf.messages (thread_id, author_side, body) values (v_thread, v_side, coalesce(nullif(v_body, ''), '📎'))
  returning id into v_msg;
  for a in select * from jsonb_array_elements(coalesce(p_attachments, '[]')) loop
    if coalesce(a ->> 'path', '') !~ ('^threads/' || v_thread::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then
      raise exception 'invalid file' using errcode = '22023';
    end if;
    insert into inf.message_attachments (message_id, path, name, mime, size_bytes)
    values (v_msg, a ->> 'path', left(a ->> 'name', 200), a ->> 'mime', (a ->> 'size_bytes')::int);
  end loop;
  update inf.threads set last_message_at = now() where id = v_thread;
  insert into inf.thread_reads (thread_id, user_id, last_read_at) values (v_thread, auth.uid(), now())
  on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;

  v_plain := regexp_replace(v_body, '@\[([^\]]+)\]\(user:[0-9a-f-]{36}\)', '@\1', 'g');
  v_sender := case v_side when 'eduwit' then 'Eduwit'
                          when 'agency' then coalesce((select ag.name from inf.agency_members am join inf.agencies ag on ag.id = am.agency_id
                                                       where am.user_id = auth.uid() limit 1), 'Agency')
                          else (select c.display_name from inf.creators c where c.id = v_creator) end;
  -- Mentions (staff posting about staff only).
  if v_side = 'eduwit' then
    select coalesce(array_agg(distinct m[1]::uuid), '{}') into v_mentions
      from regexp_matches(v_body, '@\[[^\]]+\]\(user:([0-9a-f-]{36})\)', 'g') m
     where exists (select 1 from inf.staff_profiles sp where sp.user_id = m[1]::uuid and sp.status = 'active');
    insert into inf.message_mentions (message_id, user_id) select v_msg, u from unnest(v_mentions) u on conflict do nothing;
    perform inf.notify(u, 'thread.mention', 'You were mentioned: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
                       jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                       'thread_mention:' || v_msg || ':' || u)
      from unnest(v_mentions) u where u <> auth.uid();
  end if;
  -- The other side.
  if v_side = 'eduwit' then
    if not (r ->> 'staff_only')::boolean then
      select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = v_creator;
      if v_user is not null then
        perform inf.notify(v_user, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'creator_link',
                           jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                           'thread_message:' || v_msg || ':' || v_user);
      end if;
      perform inf.notify(am.user_id, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300),
                         coalesce(r ->> 'agency_link', '/agency'),
                         jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                         'thread_message:' || v_msg || ':' || am.user_id)
        from inf.agency_creator_links l join inf.agency_members am on am.agency_id = l.agency_id
       where l.creator_id = v_creator and l.status = 'active' and am.user_id is not null and am.status = 'active'
         and r ->> 'agency_grant' is not null
         and case r ->> 'agency_grant' when 'view' then l.can_view when 'deliverables' then l.can_act_deliverables
                                       when 'negotiate' then l.can_negotiate_sign when 'earnings' then l.can_view_earnings else false end;
    end if;
  else
    perform inf.notify(f, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
                       jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
                       'thread_message:' || v_msg || ':' || f)
      from inf.thread_staff_followers(v_thread, (r ->> 'owner_id')::uuid) f;
  end if;
  return jsonb_build_object('thread_id', v_thread, 'message_id', v_msg);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 6. Tiers for staff, creators and the service role only (as the RLS policy on inf.tiers)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.tiers_list() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'rank', t.rank, 'rules', t.entry_rules,
                                               'benefits', t.benefits, 'active', t.active,
                                               'creators', case when inf.has_perm('creator.read')
                                                                then (select count(*) from inf.creators c where c.tier_id = t.id) end)
                            order by t.rank), '[]')
    from inf.tiers t
   where (t.active or inf.has_perm('tier.manage'))
     and (coalesce(auth.role(), '') = 'service_role' or inf.is_staff() or inf.current_creator_id() is not null)
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. eligibility_gaps is internal: no client grant
-- ---------------------------------------------------------------------------------------------------------------
delete from inf.client_grants
 where object_type = 'function' and object_name = 'inf.eligibility_gaps(uuid, uuid)' and grantee = 'authenticated';

call inf.apply_client_grants();

-- rollback: (inverse statements; run in one transaction)
-- insert into inf.client_grants (object_type, object_name, grantee, privilege)
--   select 'function', 'inf.eligibility_gaps(uuid, uuid)', 'authenticated', 'execute'
--    where not exists (select 1 from inf.client_grants where object_name = 'inf.eligibility_gaps(uuid, uuid)' and grantee = 'authenticated');
-- The previous definitions, verbatim:
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.change_request_create(p_contract uuid, p jsonb) returns uuid
-- language plpgsql security definer set search_path = '' as $$
-- declare c inf.contracts; v_side text := inf.contract_side(p_contract); v_id uuid; v_section jsonb;
-- begin
--   if v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into c from inf.contracts where id = p_contract for update;
--   if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'negotiation is closed' using errcode = '22023'; end if;
--   if p ->> 'kind' = 'clause' then
--     select s into v_section from inf.contract_versions v, jsonb_array_elements(v.content -> 'sections') s
--      where v.id = c.current_version_id and s ->> 'key' = p ->> 'clause_key';
--     if v_section is null then raise exception 'no such clause' using errcode = '22023'; end if;
--     if not coalesce((v_section ->> 'negotiable')::boolean, false) or coalesce((v_section ->> 'locked')::boolean, false) then
--       raise exception 'this clause is not negotiable' using errcode = '22023';
--     end if;
--   elsif p ->> 'kind' <> 'compensation' then
--     raise exception 'invalid change request' using errcode = '22023';
--   end if;
--   if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending'
--               and kind = p ->> 'kind' and coalesce(clause_key, '') = coalesce(p ->> 'clause_key', '')) then
--     raise exception 'a request for this is already pending' using errcode = '22023';
--   end if;
--   insert into inf.contract_change_requests (contract_id, version_id, kind, clause_key, proposed_body, proposed_terms, note, from_side)
--   values (c.id, c.current_version_id, p ->> 'kind', nullif(p ->> 'clause_key', ''), p -> 'proposed_body', p -> 'proposed_terms',
--           nullif(trim(p ->> 'note'), ''), v_side)
--   returning id into v_id;
--   update inf.contracts set status = 'in_negotiation' where id = c.id and status in ('sent', 'ready_to_sign');
--   perform inf.contract_notify(c.id, 'eduwit', 'contract.change_requested', 'Change requested on ' || c.number,
--                               case when p ->> 'kind' = 'clause' then 'Suggested wording for a clause.' else 'A compensation counter-offer.' end);
--   return v_id;
-- end $$;
--
-- -- from 20261019000100_inf_contracts.sql
-- create or replace function inf.change_request_withdraw(p_request uuid) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare r inf.contract_change_requests;
-- begin
--   select * into r from inf.contract_change_requests where id = p_request;
--   if r.id is null or inf.contract_side(r.contract_id) not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   update inf.contract_change_requests set status = 'withdrawn' where id = p_request and status = 'pending';
-- end $$;
--
-- -- from 20261020000100_inf_content.sql
-- create or replace function inf.brief_acknowledge(p_brief uuid, p_version uuid) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare b inf.briefs; v_side text; v_first boolean; r record;
-- begin
--   select * into b from inf.briefs where id = p_brief for update;
--   v_side := inf.content_side(b.deal_id);
--   if b.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   if b.current_version_id is distinct from p_version then raise exception 'a newer version of the brief exists' using errcode = '22023'; end if;
--   v_first := not exists (select 1 from inf.brief_acknowledgements where brief_id = b.id);
--   insert into inf.brief_acknowledgements (brief_id, version_id, side) values (b.id, p_version, v_side)
--   on conflict (version_id) do nothing;
--   if not found then return; end if;
--   for r in select * from inf.deliverables where deal_id = b.deal_id and status = 'not_started'
--              and coalesce((stages ->> 'brief')::boolean, true) loop
--     perform inf.deliverable_apply(r.id, 'acknowledge_brief', 'system', null);
--   end loop;
--   if v_first then
--     perform inf.emit_event('brief.acknowledged', 'brief', b.id::text, jsonb_build_object('deal_id', b.deal_id, 'version_id', p_version),
--                            'brief_acknowledged:' || b.id);
--   end if;
--   perform inf.content_notify(b.deal_id, 'eduwit', 'brief.acknowledged', 'Brief acknowledged', 'The creator has read and acknowledged the brief.',
--                              '/creator/briefs/' || b.id, '/admin/briefs/' || b.id, p_version::text);
-- end $$;
--
-- -- from 20261020000100_inf_content.sql
-- create or replace function inf.deliverable_schedule(p_id uuid, p_at timestamptz) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare x inf.deliverables; v_side text;
-- begin
--   select * into x from inf.deliverables where id = p_id;
--   v_side := inf.content_side(x.deal_id);
--   if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   if p_at is null or p_at < now() - interval '1 day' then raise exception 'choose a future date' using errcode = '22023'; end if;
--   perform inf.deliverable_apply(p_id, 'schedule', v_side, null);
--   update inf.deliverables set scheduled_for = p_at where id = p_id;
-- end $$;
--
-- -- from 20261020000100_inf_content.sql
-- create or replace function inf.submission_add(p_deliverable uuid, p jsonb) returns uuid
-- language plpgsql security definer set search_path = '' as $$
-- declare x inf.deliverables; v_side text; v_kind text := p ->> 'kind'; v_id uuid; v_file jsonb;
-- begin
--   select * into x from inf.deliverables where id = p_deliverable for update;
--   v_side := inf.content_side(x.deal_id);
--   if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   if v_kind not in ('concept', 'draft') then raise exception 'invalid submission' using errcode = '22023'; end if;
--   if coalesce(trim(p ->> 'body'), '') = '' and coalesce(jsonb_array_length(p -> 'files'), 0) = 0 and coalesce(p ->> 'link_url', '') = '' then
--     raise exception 'add text, a file or a link' using errcode = '22023';
--   end if;
--   for v_file in select * from jsonb_array_elements(coalesce(p -> 'files', '[]'::jsonb)) loop
--     if coalesce(v_file ->> 'path', '') !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then
--       raise exception 'invalid file' using errcode = '22023';
--     end if;
--   end loop;
--   perform inf.deliverable_apply(x.id, 'submit_' || v_kind, v_side, null);
--   insert into inf.deliverable_submissions (deliverable_id, kind, version, body, files, link_url, creator_note, author_side)
--   values (x.id, v_kind, coalesce((select max(version) from inf.deliverable_submissions where deliverable_id = x.id and kind = v_kind), 0) + 1,
--           nullif(trim(p ->> 'body'), ''), coalesce(p -> 'files', '[]'), nullif(trim(p ->> 'link_url'), ''), nullif(trim(p ->> 'note'), ''), v_side)
--   returning id into v_id;
--   perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.submitted', initcap(v_kind) || ' to review: ' || x.title,
--                              'A new submission is waiting for review.', '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
--   return v_id;
-- end $$;
--
-- -- from 20261020000100_inf_content.sql
-- create or replace function inf.post_submit(p_deliverable uuid, p_url text, p_posted_on date, p_oembed jsonb default null) returns uuid
-- language plpgsql security definer set search_path = '' as $$
-- declare x inf.deliverables; v_side text; v_id uuid;
-- begin
--   select * into x from inf.deliverables where id = p_deliverable for update;
--   v_side := inf.content_side(x.deal_id);
--   if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   if p_posted_on is null or p_posted_on > (now() at time zone 'Asia/Kolkata')::date then
--     raise exception 'the posting date can''t be in the future' using errcode = '22023';
--   end if;
--   perform inf.deliverable_apply(x.id, 'go_live', v_side, null);
--   update inf.published_posts set verification_status = 'replaced' where deliverable_id = x.id and verification_status = 'pending';
--   insert into inf.published_posts (deliverable_id, live_url, posted_on, oembed) values (x.id, trim(p_url), p_posted_on, p_oembed)
--   returning id into v_id;
--   perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.live', 'Live post to verify: ' || x.title, trim(p_url),
--                              '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
--   return v_id;
-- end $$;
--
-- -- from 20261020000100_inf_content.sql
-- create or replace function inf.metrics_submit(p_deliverable uuid, p jsonb) returns bigint
-- language plpgsql security definer set search_path = '' as $$
-- declare x inf.deliverables; v_side text; pp inf.published_posts; v_id bigint; v_path text;
-- begin
--   select * into x from inf.deliverables where id = p_deliverable for update;
--   v_side := inf.content_side(x.deal_id);
--   if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
--   select * into pp from inf.published_posts where deliverable_id = x.id and verification_status <> 'replaced' order by created_at desc limit 1;
--   if pp.id is null then raise exception 'submit the live link first' using errcode = '22023'; end if;
--   foreach v_path in array coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}') loop
--     if v_path !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then raise exception 'invalid file' using errcode = '22023'; end if;
--   end loop;
--   insert into inf.post_metric_snapshots (deliverable_id, published_post_id, checkpoint, views, reach, likes, comments, shares, saves, clicks,
--                                          watch_time_s, source, screenshot_paths)
--   values (x.id, pp.id, coalesce(nullif(p ->> 'checkpoint', ''), 'adhoc'), nullif(p ->> 'views', '')::bigint, nullif(p ->> 'reach', '')::bigint,
--           nullif(p ->> 'likes', '')::bigint, nullif(p ->> 'comments', '')::bigint, nullif(p ->> 'shares', '')::bigint,
--           nullif(p ->> 'saves', '')::bigint, nullif(p ->> 'clicks', '')::bigint, nullif(p ->> 'watch_time_s', '')::bigint,
--           case when jsonb_array_length(coalesce(p -> 'screenshots', '[]')) > 0 then 'screenshot' else 'manual' end,
--           coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}'))
--   returning id into v_id;
--   if inf.deliverable_next(x.status, 'submit_metrics', x.stages) is not null then
--     perform inf.deliverable_apply(x.id, 'submit_metrics', v_side, null);
--   end if;
--   return v_id;
-- end $$;
--
-- -- from 20261018000100_inf_creator_profile_kyc.sql
-- create or replace function inf.creator_profile_update(p_creator uuid, p jsonb) returns void
-- language plpgsql security definer set search_path = '' as $$
-- declare v_phone text;
-- begin
--   if not inf.can_edit_creator(p_creator) then raise exception 'not allowed' using errcode = '42501'; end if;
--   if p ? 'phone_e164' then
--     v_phone := nullif(trim(p ->> 'phone_e164'), '');
--     if v_phone is not null and v_phone !~ '^\+[1-9]\d{7,14}$' then raise exception 'invalid phone number' using errcode = '22023'; end if;
--   end if;
--   update inf.creators set
--     display_name = coalesce(nullif(trim(p ->> 'display_name'), ''), display_name),
--     legal_name = case when p ? 'legal_name' then nullif(trim(p ->> 'legal_name'), '') else legal_name end,
--     bio = case when p ? 'bio' then nullif(trim(p ->> 'bio'), '') else bio end,
--     city = case when p ? 'city' then nullif(trim(p ->> 'city'), '') else city end,
--     state = case when p ? 'state' then nullif(trim(p ->> 'state'), '') else state end,
--     phone_e164 = case when p ? 'phone_e164' then v_phone else phone_e164 end,
--     languages = case when p ? 'languages' then coalesce((select array_agg(distinct left(trim(x), 40)) from jsonb_array_elements_text(p -> 'languages') x where trim(x) <> ''), '{}') else languages end,
--     niches = case when p ? 'niches' then coalesce((select array_agg(distinct left(lower(trim(x)), 40)) from jsonb_array_elements_text(p -> 'niches') x where trim(x) <> ''), '{}') else niches end,
--     avatar_path = case when p ? 'avatar_path' then nullif(p ->> 'avatar_path', '') else avatar_path end,
--     public_page_enabled = coalesce((p ->> 'public_page_enabled')::boolean, public_page_enabled),
--     leaderboard_opt_in = coalesce((p ->> 'leaderboard_opt_in')::boolean, leaderboard_opt_in),
--     last_activity_at = now()
--   where id = p_creator;
-- end $$;
--
-- -- from 20261018000100_inf_creator_profile_kyc.sql
-- create or replace function inf.kyc_save(p_creator uuid, p_pan text, p_name_on_pan text, p_gst_status text, p_gstin text,
--                                         p_bank_account text, p_ifsc text, p_account_holder text, p_proof_path text default null)
-- returns jsonb language plpgsql security definer set search_path = '' as $$
-- declare
--   v_cur     inf.creator_kyc;
--   v_pan     text := upper(nullif(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'), ''));
--   v_acct    text := nullif(regexp_replace(coalesce(p_bank_account, ''), '\s', '', 'g'), '');
--   v_ifsc    text := upper(nullif(trim(coalesce(p_ifsc, '')), ''));
--   v_gstin   text := upper(nullif(trim(coalesce(p_gstin, '')), ''));
--   v_status  text := coalesce(nullif(p_gst_status, ''), 'unregistered');
--   v_changed boolean;
--   v_complete boolean;
--   v_pan_eff text;
-- begin
--   if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.has_perm('creator.write') or inf.has_perm('kyc.verify')) then
--     raise exception 'not allowed' using errcode = '42501';
--   end if;
--   if v_pan is not null and not inf.valid_pan(v_pan) then return jsonb_build_object('ok', false, 'error', 'invalid_pan'); end if;
--   if v_acct is not null and v_acct !~ '^\d{9,18}$' then return jsonb_build_object('ok', false, 'error', 'invalid_account'); end if;
--   if v_ifsc is not null and not inf.valid_ifsc(v_ifsc) then return jsonb_build_object('ok', false, 'error', 'invalid_ifsc'); end if;
--   if v_status not in ('unregistered', 'registered', 'composition') then return jsonb_build_object('ok', false, 'error', 'invalid_gst_status'); end if;
--   if v_status <> 'unregistered' and (v_gstin is null or not inf.valid_gstin(v_gstin)) then return jsonb_build_object('ok', false, 'error', 'invalid_gstin'); end if;
--   if v_status = 'unregistered' then v_gstin := null; end if;
--
--   select * into v_cur from inf.creator_kyc where creator_id = p_creator for update;
--   v_pan_eff := coalesce(v_pan, case when v_cur.pan_enc is not null then inf.pii_decrypt(v_cur.pan_enc) end);
--   -- GSTIN characters 3–12 are the PAN.
--   if v_gstin is not null and v_pan_eff is not null and substr(v_gstin, 3, 10) <> v_pan_eff then
--     return jsonb_build_object('ok', false, 'error', 'gstin_pan_mismatch');
--   end if;
--   v_changed := v_cur.creator_id is not null and (v_pan is not null or v_acct is not null
--                  or v_ifsc is distinct from v_cur.ifsc or v_gstin is distinct from v_cur.gstin);
--
--   insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, gst_status, gstin, bank_account_enc, bank_last4, ifsc, account_holder, proof_path)
--   values (p_creator, inf.pii_encrypt(v_pan), right(v_pan, 4), nullif(trim(p_name_on_pan), ''), v_status, v_gstin,
--           inf.pii_encrypt(v_acct), right(v_acct, 4), v_ifsc, nullif(trim(p_account_holder), ''), nullif(p_proof_path, ''))
--   on conflict (creator_id) do update set
--     pan_enc = coalesce(excluded.pan_enc, inf.creator_kyc.pan_enc),
--     pan_last4 = coalesce(excluded.pan_last4, inf.creator_kyc.pan_last4),
--     name_on_pan = coalesce(excluded.name_on_pan, inf.creator_kyc.name_on_pan),
--     gst_status = excluded.gst_status,
--     gstin = excluded.gstin,
--     gstin_verified = case when excluded.gstin is distinct from inf.creator_kyc.gstin then false else inf.creator_kyc.gstin_verified end,
--     bank_account_enc = coalesce(excluded.bank_account_enc, inf.creator_kyc.bank_account_enc),
--     bank_last4 = coalesce(excluded.bank_last4, inf.creator_kyc.bank_last4),
--     ifsc = coalesce(excluded.ifsc, inf.creator_kyc.ifsc),
--     account_holder = coalesce(excluded.account_holder, inf.creator_kyc.account_holder),
--     proof_path = coalesce(excluded.proof_path, inf.creator_kyc.proof_path);
--
--   select (pan_enc is not null and name_on_pan is not null and bank_account_enc is not null and ifsc is not null and account_holder is not null)
--     into v_complete from inf.creator_kyc where creator_id = p_creator;
--   update inf.creator_kyc set
--     status = case when not v_complete then 'pending'
--                   when status = 'verified' and not v_changed then 'verified'
--                   else 'submitted' end,
--     submitted_at = case when v_complete and (status <> 'verified' or v_changed) then now() else submitted_at end,
--     verified_at = case when v_changed then null else verified_at end,
--     verified_by = case when v_changed then null else verified_by end,
--     rejection_reason = case when v_complete then null else rejection_reason end
--   where creator_id = p_creator;
--   update inf.creators set last_activity_at = now() where id = p_creator;
--   return jsonb_build_object('ok', true, 'status', (select status from inf.creator_kyc where creator_id = p_creator), 'complete', v_complete);
-- end $$;
--
-- -- from 20261024000100_inf_communication.sql
-- create or replace function inf.thread_post(p_type text, p_entity uuid, p_body text, p_attachments jsonb default '[]', p_creator uuid default null)
-- returns jsonb language plpgsql security definer set search_path = '' as $$
-- declare
--   r jsonb;
--   v_thread uuid;
--   v_msg uuid;
--   v_side text;
--   v_creator uuid;
--   v_body text := trim(coalesce(p_body, ''));
--   v_plain text;
--   v_user uuid;
--   v_sender text;
--   a jsonb;
--   v_mentions uuid[] := '{}';
-- begin
--   r := inf.thread_resolve(p_type, p_entity, p_creator);
--   if r is null or not coalesce((r ->> 'can_post')::boolean, false) then raise exception 'not allowed' using errcode = '42501'; end if;
--   if char_length(v_body) = 0 and coalesce(jsonb_array_length(p_attachments), 0) = 0 then
--     raise exception 'a message is required' using errcode = '22023';
--   end if;
--   if char_length(v_body) > 4000 then raise exception 'message too long' using errcode = '22023'; end if;
--   if coalesce(jsonb_array_length(p_attachments), 0) > 5 then raise exception 'at most 5 attachments' using errcode = '22023'; end if;
--   v_side := r ->> 'side';
--   v_creator := (r ->> 'creator_id')::uuid;
--   insert into inf.threads (entity_type, entity_id, creator_id, staff_only)
--   values (p_type, p_entity, v_creator, (r ->> 'staff_only')::boolean)
--   on conflict (entity_type, entity_id, coalesce(creator_id, '00000000-0000-0000-0000-000000000000'::uuid)) do nothing;
--   select id into v_thread from inf.threads
--    where entity_type = p_type and entity_id = p_entity and creator_id is not distinct from v_creator;
--   insert into inf.messages (thread_id, author_side, body) values (v_thread, v_side, coalesce(nullif(v_body, ''), '📎'))
--   returning id into v_msg;
--   for a in select * from jsonb_array_elements(coalesce(p_attachments, '[]')) loop
--     if (a ->> 'path') not like 'threads/' || v_thread || '/%' then raise exception 'invalid file' using errcode = '22023'; end if;
--     insert into inf.message_attachments (message_id, path, name, mime, size_bytes)
--     values (v_msg, a ->> 'path', left(a ->> 'name', 200), a ->> 'mime', (a ->> 'size_bytes')::int);
--   end loop;
--   update inf.threads set last_message_at = now() where id = v_thread;
--   insert into inf.thread_reads (thread_id, user_id, last_read_at) values (v_thread, auth.uid(), now())
--   on conflict (thread_id, user_id) do update set last_read_at = excluded.last_read_at;
--
--   v_plain := regexp_replace(v_body, '@\[([^\]]+)\]\(user:[0-9a-f-]{36}\)', '@\1', 'g');
--   v_sender := case v_side when 'eduwit' then 'Eduwit'
--                           when 'agency' then coalesce((select ag.name from inf.agency_members am join inf.agencies ag on ag.id = am.agency_id
--                                                        where am.user_id = auth.uid() limit 1), 'Agency')
--                           else (select c.display_name from inf.creators c where c.id = v_creator) end;
--   -- Mentions (staff posting about staff only).
--   if v_side = 'eduwit' then
--     select coalesce(array_agg(distinct m[1]::uuid), '{}') into v_mentions
--       from regexp_matches(v_body, '@\[[^\]]+\]\(user:([0-9a-f-]{36})\)', 'g') m
--      where exists (select 1 from inf.staff_profiles sp where sp.user_id = m[1]::uuid and sp.status = 'active');
--     insert into inf.message_mentions (message_id, user_id) select v_msg, u from unnest(v_mentions) u on conflict do nothing;
--     perform inf.notify(u, 'thread.mention', 'You were mentioned: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
--                        jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
--                        'thread_mention:' || v_msg || ':' || u)
--       from unnest(v_mentions) u where u <> auth.uid();
--   end if;
--   -- The other side.
--   if v_side = 'eduwit' then
--     if not (r ->> 'staff_only')::boolean then
--       select ca.user_id into v_user from inf.creator_accounts ca where ca.creator_id = v_creator;
--       if v_user is not null then
--         perform inf.notify(v_user, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'creator_link',
--                            jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
--                            'thread_message:' || v_msg || ':' || v_user);
--       end if;
--       perform inf.notify(am.user_id, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300),
--                          coalesce(r ->> 'agency_link', '/agency'),
--                          jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
--                          'thread_message:' || v_msg || ':' || am.user_id)
--         from inf.agency_creator_links l join inf.agency_members am on am.agency_id = l.agency_id
--        where l.creator_id = v_creator and l.status = 'active' and am.user_id is not null and am.status = 'active'
--          and r ->> 'agency_grant' is not null
--          and case r ->> 'agency_grant' when 'view' then l.can_view when 'deliverables' then l.can_act_deliverables
--                                        when 'negotiate' then l.can_negotiate_sign when 'earnings' then l.can_view_earnings else false end;
--     end if;
--   else
--     perform inf.notify(f, 'thread.message', 'New message: ' || (r ->> 'subject'), left(v_plain, 300), r ->> 'admin_link',
--                        jsonb_build_object('thread_id', v_thread, 'subject', r ->> 'subject', 'sender', v_sender), false,
--                        'thread_message:' || v_msg || ':' || f)
--       from inf.thread_staff_followers(v_thread, (r ->> 'owner_id')::uuid) f;
--   end if;
--   return jsonb_build_object('thread_id', v_thread, 'message_id', v_msg);
-- end $$;
--
-- -- from 20261025000100_inf_insight_privacy.sql
-- create or replace function inf.tiers_list() returns jsonb
-- language sql stable security definer set search_path = '' as $$
--   select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'rank', t.rank, 'rules', t.entry_rules,
--                                                'benefits', t.benefits, 'active', t.active,
--                                                'creators', case when inf.has_perm('creator.read')
--                                                                 then (select count(*) from inf.creators c where c.tier_id = t.id) end)
--                             order by t.rank), '[]')
--     from inf.tiers t
--    where (t.active or inf.has_perm('tier.manage'))
--      and (coalesce(auth.role(), '') = 'service_role' or auth.uid() is not null)
-- $$;
-- call inf.apply_client_grants();
