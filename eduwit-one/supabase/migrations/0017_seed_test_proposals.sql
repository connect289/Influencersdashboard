-- 0017 the builder's proposals for the synthetic tests that cannot run yet (spec §10, D-071). Each blocked test in
-- config/tests.json names what it waits for; each proposal below is that change, which only the owning app can make
-- (Eduwit One alters nothing of the five apps, spec §2). Same rules as 0013: no expiry, a stable source_key, a decided
-- proposal is never reopened. Evidence was measured read-only on production on 23 Oct 2026, and in the website's code
-- on branch claude/inspiring-babbage-8asj1y; no secret or contact field was read.

insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key)
select p.kind, p.app, p.title, p.rationale, p.evidence, p.change, p.risk, 'builder', p.source_key
from jsonb_to_recordset($json$[
  {"source_key": "builder:p5-website-test-enquiry", "kind": "feature", "app": "web", "risk": "medium",
   "title": "Website: a test path for the enquiry form",
   "rationale": "T-WEB-ENQUIRY (P1) is blocked (blocked:website-test-endpoint). The enquiry is a Next.js server action behind Turnstile and a 6-digit code emailed to the student, and it writes the lead through lead_intake only once the email is proven. A server cannot submit it: the action id changes with each build, and the code arrives in a mailbox. Without a test path the form that brings most leads has no end-to-end check.",
   "evidence": {"measured_at": "2026-10-23", "files": ["web/components/forms/EnquiryForm.tsx", "web/lib/server/gate.ts", "web/lib/server/turnstile.ts"], "controls": ["server action", "Turnstile", "email code", "rate limits", "junk score"], "test": "T-WEB-ENQUIRY"},
   "change": {"where": "Website (website/web)", "owner_action": "Add a route (for example POST /api/test/enquiry) that runs the same enquiry pipeline after Turnstile and the email code, only for a phone matching 910000 and six digits, only with a header signed by a secret Eduwit One holds, and marks the lead is_test. Save the secret in Settings → Setup (test_preview_url); Eduwit One then switches the test on.", "touches": ["website API", "security"]}},
  {"source_key": "builder:p5-website-test-advisor", "kind": "feature", "app": "web", "risk": "medium",
   "title": "Website: a test session for the Witty web advisor",
   "rationale": "T-WEB-ADVISOR is blocked (blocked:website-test-endpoint). The web advisor answers only inside a gate session, which needs the same email code as the enquiry. A test session for harness phones would let Eduwit One ask one question and check the answer streams, cites the catalogue and logs a web_advisor_sessions row.",
   "evidence": {"measured_at": "2026-10-23", "files": ["web/components/witty/WittyGate.tsx", "web/lib/server/gate.ts", "web/lib/server/web-advisor/turn.ts"], "test": "T-WEB-ADVISOR"},
   "change": {"where": "Website (website/web)", "owner_action": "Let the signed test route above also open a gate session for a harness phone, marked as a test in web_advisor_sessions, so a turn can be sent and its stream read.", "touches": ["website API", "security"]}},
  {"source_key": "builder:p5-catalogue-test-programme", "kind": "feature", "app": "catalogue", "risk": "medium",
   "title": "Catalogue: a hidden test programme the website test can change",
   "rationale": "T-WEB-CATALOG is blocked (blocked:no-safe-catalogue-write). It should prove that a catalogue change reaches the website, but the catalog_* tables have no test flag, so any change Eduwit One made would be visible to students and to Witty's answers.",
   "evidence": {"measured_at": "2026-10-23", "test_flag_in_catalog": false, "test": "T-WEB-CATALOG"},
   "change": {"where": "Catalogue owner (catalog_* tables) and website", "owner_action": "Add one programme flagged as a test, never listed, searched or cited by Witty, and a function that touches its updated_at; the website shows it only on a preview or test path. Eduwit One then times the change from the function to the page.", "touches": ["catalog_*"]}},
  {"source_key": "builder:p5-witty-referral-code", "kind": "feature", "app": "witty", "risk": "medium",
   "title": "Witty: carry a creator's referral code onto the lead",
   "rationale": "T-INFLUENCER is blocked (blocked:witty-referral-code-not-built). A creator's tracking link gives the student an access code that Witty keeps on the conversation, but no lead carries a referral code: 0 of the leads have student_leads.referral_code, while 14 conversations have an access_code. So a referral cannot be followed from the creator's link to the lead, and the test has nothing to assert.",
   "evidence": {"measured_at": "2026-10-23", "leads_with_referral_code": 0, "conversations_with_access_code": 14, "test": "T-INFLUENCER"},
   "change": {"where": "Witty (n8n workflow and lead_intake payload)", "owner_action": "When a conversation has an access code from a creator's link, send the creator's referral code with the lead to lead_intake, so student_leads.referral_code is set.", "touches": ["n8n", "lead_intake payload", "money"]}},
  {"source_key": "builder:p5-referral-outcomes-exclude-test", "kind": "fix", "app": "b2b", "risk": "high",
   "title": "B2B: leave test leads out of referral outcomes",
   "rationale": "public.b2b_referral_outcomes and b2b.api_referral_outcomes() do not mention is_test, so a test lead with a referral code would be reported as a creator's outcome to whatever credits creators from it. No lead has a referral code today, so nothing has been paid this way; it matters as soon as the Witty proposal above lands or a test sets a code.",
   "evidence": {"measured_at": "2026-10-23", "view": "public.b2b_referral_outcomes", "function": "b2b.api_referral_outcomes(text,text,bigint,integer)", "mentions_is_test": false, "leads_with_referral_code": 0},
   "change": {"where": "B2B CRM (database)", "owner_action": "Exclude leads that are is_test or on a test phone (b2b.is_test_phone) from the view and the API, as the command centre already does.", "touches": ["b2b_referral_outcomes"]}},
  {"source_key": "builder:p5-b2b-delete-sandbox-test-leads", "kind": "fix", "app": "b2b", "risk": "low",
   "title": "B2B: let a test lead routed to the sandbox partner be deleted as a test",
   "rationale": "b2b.leads_soft_delete() allows a lead with a partner only junk, spam or a student request as the reason. A test lead that T-B2B-PUSH routes to the test partner's sandbox is neither, so Eduwit One's purge keeps it and its harness phone (D-071), and those leads build up, one per run.",
   "evidence": {"measured_at": "2026-10-23", "function": "b2b.leads_soft_delete(bigint[],text)", "partner_reasons": ["junk", "spam", "student request"], "test": "T-B2B-PUSH"},
   "change": {"where": "B2B CRM (database)", "owner_action": "Also accept the reason \"test\" when the lead is a test lead and every allocation it has went to a sandbox (origin sandbox). Eduwit One's purge then deletes them like the others.", "touches": ["b2b.leads_soft_delete"]}}
]$json$::jsonb) as p(source_key text, kind text, app text, risk text, title text, rationale text, evidence jsonb, change jsonb)
on conflict (source_key) do nothing;
