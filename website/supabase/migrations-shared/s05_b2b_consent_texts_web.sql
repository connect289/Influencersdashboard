-- =====================================================================================================================
-- s05 · Register the website's consent texts in the B2B CRM (APPROVALS_NEEDED A-CONSENT-1, 🔴 blocking for go-live).
-- SHARED DATA (b2b.consent_texts). Dev / replica only until approved. Depends on the lawyer's review of the wording
-- (SETUP_CHECKLIST S-44): the rows are inserted with lawyer_approved_at NULL, so the B2B CRM does not count them until
-- the B2B admin records the approval (date and approver) in the CRM's consent screen, or the owner runs the UPDATE at
-- the bottom with the real date. The bodies are byte-identical to the website's web_consent_texts versions.
-- Rollback: s05_b2b_consent_texts_web.rollback.sql (only while no lead references these versions). Affects: B2B CRM.
-- =====================================================================================================================
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active)
values
  ('web-gate-2026-10-v1', 'website_agent', array['sales', 'partner_share'], $t$I agree that Eduwit Learning Services may use my name, phone number and email to help me choose a programme and with my admission, and may share them with our partner universities and our admission partners (edtech companies). My chat with Witty, Eduwit's AI admissions assistant, is stored to answer me and to improve the service. I can withdraw consent or ask for my data to be deleted at any time.$t$, true, true),
  ('web-form-2026-10-v1', 'web_form', array['sales', 'partner_share'], $t$I agree that Eduwit Learning Services may use the details I have entered to help me with my admission, and may share them with our partner universities and our admission partners (edtech companies). A counsellor may call, WhatsApp or email me about this enquiry. I can withdraw consent or ask for my data to be deleted at any time.$t$, true, true)
on conflict (version) do nothing;

-- After the lawyer's approval (S-44), with the real date and name:
-- update b2b.consent_texts set lawyer_approved_at = '<YYYY-MM-DD>', approved_by = '<lawyer name>',
--   approval_note = 'Website consent texts, approved for partner sharing'
--  where version in ('web-gate-2026-10-v1', 'web-form-2026-10-v1');
