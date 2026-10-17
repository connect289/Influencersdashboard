#!/usr/bin/env python3
"""Regenerates supabase/migrations-shared/s01_lead_intake_email_verified{,.rollback}.sql from production's current
public.lead_intake body (read-only). Use when production's lead_intake changed after 17 Oct 2026 (RUNBOOK §8).

  psql "<production url>" -X -A -t -c "select pg_get_functiondef('public.lead_intake(jsonb)'::regprocedure)" > /tmp/lead_intake.sql
  python3 -I scripts/db/make-s01.py /tmp/lead_intake.sql

Fails loudly if the anchor lines the s01 change hooks into are no longer in the body (then edit by hand and re-review)."""
import pathlib, sys

body = pathlib.Path(sys.argv[1]).read_text().strip()
if not body.endswith(";"):
    body += "\n;"
root = pathlib.Path(__file__).resolve().parents[2] / "supabase" / "migrations-shared"
cur = (root / "s01_lead_intake_email_verified.sql").read_text()
header = cur[: cur.index("CREATE OR REPLACE FUNCTION public.lead_intake")]

A = "    'consent_sales_at','consent_marketing_at','consent_partner_share_at','consent_text_version','first_agent_channel'];\nbegin\n"
B = "    execute format('update student_leads set %s, updated_by = %L where id = %s', v_set, v_sys, v_id);\n  end if;\n"
for anchor in (A, B):
    if anchor not in body:
        sys.exit(f"anchor not found in production body — edit s01 by hand:\n{anchor}")
new = body.replace(A, A.replace("begin\n", """  v_extra   jsonb;   -- s01: A-LEAD-2 / A-LEAD-3
begin
  -- s01 · A-LEAD-1: the website records the email verification on the lead (write-once, web_agent only).
  if v_sys = 'web_agent' then
    v_allowed := v_allowed || 'email_verified_at'::text;
    v_first   := v_first || 'email_verified_at'::text;
  end if;
"""), 1)
new = new.replace(B, B + """  -- s01 · A-LEAD-2 / A-LEAD-3: fields Witty and the website send that have no column of their own are kept in
  -- custom_fields (trusted agent sources only). The partner-share refusal timestamp is write-once like the consents.
  if v_sys in ('witty', 'web_agent') then
    select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_extra
      from jsonb_each(v_lead)
     where key = any(array['final_program_id','final_program_name','programs_shown','consent_partner_share_declined_at','junk_risk_score'])
       and jsonb_typeof(value) <> 'null';
    if v_extra <> '{}'::jsonb then
      update student_leads
         set custom_fields = custom_fields || (v_extra - 'consent_partner_share_declined_at')
                             || jsonb_strip_nulls(jsonb_build_object('consent_partner_share_declined_at',
                                  coalesce(custom_fields->'consent_partner_share_declined_at', v_extra->'consent_partner_share_declined_at')))
       where id = v_id;
    end if;
  end if;
""", 1)
(root / "s01_lead_intake_email_verified.sql").write_text(header + new + "\n")
(root / "s01_lead_intake_email_verified.rollback.sql").write_text(
    "-- Rollback for s01: restores public.lead_intake exactly as read from production. Grants are\n-- unchanged by s01, so CREATE OR REPLACE keeps them.\n" + body + "\n")
print("s01 regenerated; run scripts/db/check-shared-proposals.sh and get it re-reviewed")
