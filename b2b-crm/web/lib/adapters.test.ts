import { describe, expect, it } from "vitest";
import {
  ADAPTER_HOLD_MINUTES, DEDUPE_CONFIRM_HINT, DEDUPE_CONFIRM_LABEL, adapterHoldMinutes, adapterProblems, adapterSavePayload, holdWindowLabel, isCrmAdapter, pollSummary,
  withDedupe, type AdapterSaveForm, type AdapterStatus,
} from "./adapters";
import { DISPUTE_KINDS, DISPUTE_KIND_LABEL, PUSH_OUTCOME_LABEL, disputeDecisionCopy, disputeKindLabel, disputeProofOk, lostGraceText, pushOutcomeText, type Dispute } from "./push";

const spec = (over: Partial<AdapterStatus["spec"]>): AdapterStatus["spec"] => ({
  label: "X", settings: [], secrets: [], oauth: false, poll: true, schema: true, status_field: "S", reference_field: "R", record_field: "id", default_fields: {}, ...over,
});

describe("adapters", () => {
  it("knows the CRM adapters", () => {
    expect(isCrmAdapter("zoho")).toBe(true);
    expect(isCrmAdapter("generic_rest")).toBe(false);
  });
  it("checks a LeadSquared form", () => {
    const s = spec({ settings: ["host"], secrets: ["access_key", "secret_key"] });
    const e = adapterProblems(s, { settings: { host: "example.com" }, secrets: { access_key: "short" }, secretsSet: [], reference_field: "mx Ref", status_field: "", poll_minutes: "1", fixed: [] });
    expect(e).toEqual({ "settings.host": "Looks like api-in21.leadsquared.com.", "secrets.access_key": "8 to 4,000 characters.", "secrets.secret_key": "Required.",
                        reference_field: "Letters, digits and underscores (a path like stage.name for nested fields).", poll_minutes: "2 to 1,440 minutes." });
  });
  it("keeps stored secrets", () => {
    const s = spec({ settings: ["login_url", "client_id"], secrets: ["client_secret"] });
    expect(adapterProblems(s, { settings: { client_id: "abc" }, secrets: {}, secretsSet: ["client_secret"], reference_field: "", status_field: "", poll_minutes: "", fixed: [] })).toEqual({});
  });
  it("checks an in-house CRM form", () => {
    const s = spec({ settings: ["create_url", "auth_type", "auth_name", "wrap_key", "record_id_path", "duplicate_status", "poll_url", "since_param"], secrets: ["token"], schema: false });
    const base = { secrets: {}, secretsSet: [], reference_field: "", status_field: "stage.name", poll_minutes: "", fixed: [] };
    expect(isCrmAdapter("inhouse")).toBe(true);
    expect(adapterProblems(s, { ...base, settings: { create_url: "http://crm.example.com/leads", auth_type: "", record_id_path: "data..id", duplicate_status: "99" } })).toEqual({
      "settings.create_url": "An https address.", "settings.auth_type": "Choose one.", "settings.record_id_path": "Like data or data.lead.id.",
      "settings.duplicate_status": "An HTTP code such as 409.", "secrets.token": "Required." });
    // no key needed when the CRM trusts Eduwit's address
    expect(adapterProblems(s, { ...base, settings: { create_url: "https://crm.example.com/leads", auth_type: "none", poll_url: "https://crm.example.com/changes?since={since}" } })).toEqual({});
  });
  it("summarises a poll", () => {
    expect(pollSummary({ records: 3, applied: 2, unmatched: 1 })).toBe("3 changed · 2 applied · 1 not Eduwit's");
    expect(pollSummary(null)).toBe("—");
  });
});

// D37 / rulebook PART 5.1: the 0-minute hold is only for a CRM the Admin confirmed to refuse duplicates on create
describe("duplicate-blocking confirmation", () => {
  const form: AdapterSaveForm = {
    env: "live", settings: { host: "api-in21.leadsquared.com" }, secrets: { access_key: "", secret_key: "s3cr3t-key" },
    reference_field: "mx_Eduwit_Reference", status_field: "", poll: true, poll_minutes: "15", fixed: [{ k: "Source", v: "Eduwit" }, { k: "", v: "ignored" }],
  };
  it("keeps dedupe_confirmed in the save payload", () => {
    expect(adapterSavePayload({ ...form, dedupe_confirmed: true })).toEqual({
      env: "live", settings: { host: "api-in21.leadsquared.com" }, secrets: { secret_key: "s3cr3t-key" }, reference_field: "mx_Eduwit_Reference", status_field: null,
      poll: true, poll_minutes: 15, fixed: { Source: "Eduwit" }, dedupe_confirmed: true,
    });
    expect(adapterSavePayload({ ...form, dedupe_confirmed: false })).toMatchObject({ dedupe_confirmed: false });
  });
  it("leaves the key out when the answer is unknown, so partner_adapter_save keeps the stored stamp", () => {
    expect(adapterSavePayload(form)).not.toHaveProperty("dedupe_confirmed");
    expect(adapterSavePayload({ ...form, dedupe_confirmed: null })).not.toHaveProperty("dedupe_confirmed");
    expect(adapterSavePayload({ ...form, poll_minutes: "" })).not.toHaveProperty("poll_minutes");
  });
  it("derives the hold window from the answer", () => {
    expect(ADAPTER_HOLD_MINUTES).toEqual({ confirmed: 0, unconfirmed: 30 });
    expect(adapterHoldMinutes(true)).toBe(0);
    expect(adapterHoldMinutes(false)).toBe(30);
    expect(adapterHoldMinutes(null)).toBe(30);
    expect(holdWindowLabel(true)).toBe("Hold window: 0 min");
    expect(holdWindowLabel(undefined)).toBe("Hold window: 30 min");
    expect(DEDUPE_CONFIRM_LABEL).toBe("This CRM blocks duplicates on create");
    expect(DEDUPE_CONFIRM_HINT).toBe("Tick only if the CRM refuses a duplicate on create; the hold window then drops from 30 to 0 minutes");
  });
  it("attaches the partner's confirmation to a status read that lacks it", () => {
    const s: AdapterStatus = { adapter: "zoho", spec: spec({}), envs: { live: { configured: false, settings: {}, secrets_set: [], state: null }, sandbox: { configured: false, settings: {}, secrets_set: [], state: null } }, polled_events_7d: 0 };
    expect(withDedupe(s, { dedupe_confirmed_at: "2026-10-07T10:00:00Z" })).toMatchObject({ dedupe_confirmed: true, dedupe_confirmed_at: "2026-10-07T10:00:00Z" });
    expect(withDedupe(s, { dedupe_confirmed_at: null })).toMatchObject({ dedupe_confirmed: false, dedupe_confirmed_at: null });
    expect(withDedupe(s, null)).not.toHaveProperty("dedupe_confirmed");
  });
});

// lib/push.ts has no test file of its own in this step; its pure helpers are checked here
describe("push labels (lib/push)", () => {
  const dispute = (over: Partial<Dispute>): Dispute => ({
    id: 1, kind: "duplicate_after_acceptance", lead_id: 7, lead_name: "Riya Shah", reference: "EDW-7", partner_name: "Acme", existing_record_id: null,
    existing_created_at: null, existing_created_on: null, partner_event_id: null, also: 0, created_at: "2026-10-07T10:00:00Z", ...over,
  });
  it("names both dispute kinds", () => {
    expect(DISPUTE_KINDS).toEqual(["duplicate_after_acceptance", "late_activity_after_lost"]);
    expect(DISPUTE_KIND_LABEL).toEqual({ duplicate_after_acceptance: "Duplicate claimed after acceptance", late_activity_after_lost: "Activity after the lead moved to B2C" });
    expect(disputeKindLabel("something_new")).toBe("something_new");
  });
  it("reads the duplicate proof (D4)", () => {
    expect(disputeProofOk(dispute({}))).toBe(false);
    expect(disputeProofOk(dispute({ existing_record_id: "LS-991" }))).toBe(true);
    expect(disputeProofOk(dispute({ existing_created_on: "2026-09-01T00:00:00Z" }))).toBe(true);
    expect(disputeProofOk(dispute({ existing_created_at: "last month" }))).toBe(true);
  });
  it("words the decision per kind (m31i 20)", () => {
    expect(disputeDecisionCopy("duplicate_after_acceptance", true)).toMatchObject({ title: "Uphold the duplicate claim?", toast: "Claim upheld: no commission on this lead" });
    expect(disputeDecisionCopy("duplicate_after_acceptance", true).body).toMatch(/No commission on this lead/);
    expect(disputeDecisionCopy("late_activity_after_lost", true).body).toMatch(/enrolment it reports may earn commission/);
    expect(disputeDecisionCopy("late_activity_after_lost", false).toast).toBe("Claim rejected: no commission for the late activity");
    expect(disputeDecisionCopy("duplicate_after_acceptance", false).body).toBe("The lead stays with the partner and commission applies as normal.");
  });
  it("labels push outcomes, with proof when the row carries it", () => {
    expect(PUSH_OUTCOME_LABEL.duplicate_upheld).toBe("Duplicate upheld: no commission");
    expect(pushOutcomeText({ outcome: null })).toBe("Waiting");
    expect(pushOutcomeText({ outcome: "duplicate" })).toBe("Duplicate");
    expect(pushOutcomeText({ outcome: "duplicate", claim_proof_ok: true })).toBe("Duplicate (proof)");
    expect(pushOutcomeText({ outcome: "duplicate", claim_proof_ok: false })).toBe("Rejected: duplicate claim without proof");
    expect(pushOutcomeText({ outcome: "timeout" })).toBe("No answer");
    expect(pushOutcomeText({ outcome: "odd" })).toBe("odd");
  });
  it("words the lost grace", () => {
    expect(lostGraceText(null)).toBe("Lost, in grace");
    expect(lostGraceText("2026-10-14T06:30:00Z")).toMatch(/^Lost, in grace until 14 Oct, 12:00$/);
  });
});
