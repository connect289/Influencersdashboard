-- Smoke test for s01 (runs after the proposal is applied, inside the dry-run transaction).
do $$
declare r jsonb; l public.student_leads;
begin
  r := public.lead_intake(jsonb_build_object('phone', '+919812300001', 'source_system', 'web_agent', 'event_type', 'lead.verified',
       'idempotency_key', 'dryrun:s01:1', 'lead', jsonb_build_object('full_name', 'Dry Run', 'email_verified_at', '2026-10-17T10:00:00Z',
       'final_program_id', 42, 'programs_shown', jsonb_build_array(1, 2), 'consent_partner_share_declined_at', '2026-10-17T10:00:00Z',
       'junk_risk_score', 3)));
  select * into l from public.student_leads where id = (r->>'lead_id')::bigint;
  if l.email_verified_at is null then raise exception 's01: email_verified_at not stored for web_agent'; end if;
  if (l.custom_fields->>'final_program_id')::int is distinct from 42 or (l.custom_fields->>'junk_risk_score')::int is distinct from 3 then
    raise exception 's01: agent fields not kept in custom_fields: %', l.custom_fields;
  end if;
  -- write-once: a later value does not replace the first
  perform public.lead_intake(jsonb_build_object('phone', '+919812300001', 'source_system', 'web_agent', 'idempotency_key', 'dryrun:s01:2',
       'lead', jsonb_build_object('email_verified_at', '2030-01-01T00:00:00Z', 'consent_partner_share_declined_at', '2030-01-01T00:00:00Z')));
  select * into l from public.student_leads where id = (r->>'lead_id')::bigint;
  if l.email_verified_at > '2027-01-01' or (l.custom_fields->>'consent_partner_share_declined_at') > '2027' then raise exception 's01: not write-once'; end if;
  -- other sources cannot set it
  r := public.lead_intake(jsonb_build_object('phone', '+919812300002', 'source_system', 'meta', 'idempotency_key', 'dryrun:s01:3',
       'lead', jsonb_build_object('email_verified_at', '2026-10-17T10:00:00Z', 'final_program_id', 7)));
  select * into l from public.student_leads where id = (r->>'lead_id')::bigint;
  if l.email_verified_at is not null or l.custom_fields ? 'final_program_id' then raise exception 's01: a non-agent source set agent fields'; end if;
  raise notice 's01 smoke: PASS';
end $$;
