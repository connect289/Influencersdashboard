import { describe, expect, it } from "vitest";
import {
  ALWAYS_WRITABLE_FIELDS, CHECK_STEPS, CONTRACT_VERSION, contractVersion, describeActivity, describeChanges, describeProvider, eventLabel, groupFields,
  isWritable, lagText, linkHealth, recordSummary, resyncNote, type LinkOverview, type LinkRecord,
} from "./b2c-link";

const checks = { endpoint: true, secret: true, subscribed: true, ping: true, active: true, key: true, key_used: true, first_delivery: true, first_write: true };
const base: Pick<LinkOverview, "checks" | "settings" | "deliveries" | "endpoint"> = {
  checks, settings: { enabled: true, scope: "held", writable: [] }, deliveries: { by_status: {}, waiting: 0, lag_seconds_avg: 1, lag_seconds_max: 2 },
  endpoint: { id: 1, name: "B2C", url: "https://x", active: true, events: ["b2c.*"], has_secret: true, last_success_at: "2026-10-07T10:00:00Z", last_failure_at: null, last_error: null, subscribed: true },
};

/** A version-3 record as b2b.b2c_record builds it for a duplicate-cascade hand-off (docs/b2c-contract.md §2.1). */
const v3: LinkRecord = {
  id: 949, cycle_no: 1, created_at: "2026-10-01T10:00:00Z", updated_at: "2026-10-07T10:00:00Z", is_test: false, deleted: false, merged_into_id: null,
  held_by_b2c: true, contract_version: 3,
  student: { name: "Asha Verma", phone: "919876543210" },
  interest: { course: "MBA", other_courses: ["BBA", "BCA"] },
  consent: { partner_share_consent_at: "2026-10-01T10:00:00Z", partner_share_given: true, state: "given",
             partner_share_request: { id: 17, status: "answered", channel: "b2c_crm", context: "decision", created_at: "2026-10-02T10:00:00Z", expires_at: "2026-10-04T10:00:00Z", answer: "yes" } },
  qualification: { lead_status: "QUALIFIED", class: "qualified", missing: [] },
  allocation: {
    destination: "in_house", allocation_id: 5501, reference: "EDW-5501", b2c_lane: "sales", reason: "duplicate_cascade", cause: null,
    allocated_at: "2026-10-07T09:00:00Z", status: "handed_off", partner: null,
    partner_barred_at: "2026-10-07T09:00:00Z", partner_bar_reason: "duplicate",
    already_with_providers: [
      { partner_id: 20, partner_name: "Down Edu", first_had_at: "2026-08-28T00:00:00Z", existing_record_id: "LS-77001", claimed_at: "2026-10-07T08:50:00Z" },
      { partner_id: 21, partner_name: "Sync Edu", first_had_at: null, existing_record_id: null, claimed_at: "2026-10-07T08:55:00Z" },
    ],
    hold: { kind: "barred", open: true, allocation_id: 5501, lane: "sales", reason: "duplicate_cascade", owner_assigned: false },
    job: "sell", assignment: "round_robin_now", first_contact_script: "neutral_adviser", nurture_first_message_at: null, b2c_actions: [],
  },
  campaign: { platform: "meta", paid: true },
};

describe("b2c link", () => {
  it("rates the link", () => {
    expect(linkHealth(base).label).toBe("Live");
    expect(linkHealth({ ...base, settings: { ...base.settings, enabled: false } }).label).toBe("Switched off");
    expect(linkHealth({ ...base, checks: { ...checks, active: false } }).label).toBe("Not connected");
    expect(linkHealth({ ...base, deliveries: { ...base.deliveries, by_status: { dead: 1 } } }).tone).toBe("danger");
    expect(linkHealth({ ...base, endpoint: { ...base.endpoint!, last_failure_at: "2026-10-07T11:00:00Z" } }).label).toBe("Failing");
  });
  it("groups fields in order", () => {
    const g = groupFields([
      { field: "name", column: "student_name", group: "student", kind: "text", write: "b2c", max: 120 },
      { field: "stage", column: "stage", group: "pipeline", kind: "stage", write: "b2c", max: null },
      { field: "email", column: "email_id", group: "student", kind: "email", write: "b2c", max: null },
    ]);
    expect(g.map((x) => [x.group, x.fields.length])).toEqual([["student", 2], ["pipeline", 1]]);
  });
  it("describes an activity", () => {
    expect(describeActivity({ kind: "call", outcome: "connected", note: "Wants the weekend batch" })).toBe("call · connected · Wants the weekend batch");
    expect(describeActivity({ kind: "note" })).toBe("note");
    expect(describeActivity({ type: "b2ccrm.partner_consent", outcome: "yes" })).toBe("Consent answer · yes");
    expect(describeActivity({ event_type: "b2ccrm.consent_request_sent", kind: "whatsapp" })).toBe("Consent request sent · whatsapp");
  });
  it("formats lag and changes", () => {
    expect(lagText(2.345)).toBe("2.3 s");
    expect(lagText(125)).toBe("2 min");
    expect(lagText(null)).toBe("—");
    expect(describeChanges({ stage: { from: "nurture", to: "assigned" }, owner_user_id: { from: null, to: null }, a: 1, b: 2, c: 3 }))
      .toBe("stage → assigned, owner_user_id → cleared, a, b +1");
    expect(describeChanges({ other_courses: { from: [], to: ["BBA", "BCA"] }, custom_fields: { from: {}, to: { batch: "weekend" } } }))
      .toBe("other_courses → 2 items, custom_fields → updated");
    expect(describeChanges({ other_courses: { from: ["BBA"], to: [] } })).toBe("other_courses → cleared");
  });
});

describe("contract version 3", () => {
  it("summarises a version-3 record", () => {
    const s = recordSummary(v3);
    expect(s.version).toBe(3);
    expect(s.bar).toEqual({ reason: "duplicate", label: "Duplicate at partners", since: "2026-10-07T09:00:00Z" });
    expect(s.providers.map((p) => p.partner_name)).toEqual(["Down Edu", "Sync Edu"]);
    expect(s.hold).toEqual({ kind: "barred", label: "Partner-barred, with B2C", open: true, lane: "sales", reason: "duplicate_cascade" });
    expect(s.handling).toEqual({
      reason: "Duplicate at partners (partner-barred)", job: "Sell", assignment: "Assign a counsellor now (round robin)",
      script: "Neutral adviser (“Eduwit can help you compare options”)", nurture_first_message_at: null,
    });
    expect(s.actions).toEqual([]);
    expect(s.qualification).toEqual({ class: "qualified", label: "Qualified", missing: [] });
    expect(s.consent.given).toBe(true);
    expect(s.consent.label).toBe("Partner-sharing consent given");
    expect(s.consent.request?.id).toBe(17);
    expect(s.consent.requestText).toBe("Answered · via B2C number · asked at the routing decision · answer YES");
    expect(s.other_courses).toEqual(["BBA", "BCA"]);
  });
  it("summarises a nurture hand-off with the welcome request and missing details", () => {
    const s = recordSummary({
      ...v3, consent: { partner_share_given: false, state: "requested", partner_share_request: { id: 18, status: "sent", channel: "witty", context: "nurture", created_at: "2026-10-07T10:00:00Z", expires_at: "2026-10-09T10:00:00Z", answer: null } },
      qualification: { class: "unqualified", missing: ["no_email", "witty_unconfirmed"] },
      allocation: { ...v3.allocation, reason: "not_qualified", b2c_lane: "nurture", partner_barred_at: null, partner_bar_reason: null, already_with_providers: [],
                    hold: { kind: "qualification_nurture", open: true, allocation_id: 5502, lane: "nurture", reason: "not_qualified", owner_assigned: false },
                    job: "qualify", assignment: "unassigned", first_contact_script: "standard", b2c_actions: ["welcome_explore_programmes"] },
    });
    expect(s.bar).toBeNull();
    expect(s.providers).toEqual([]);
    expect(s.hold?.label).toBe("B2C nurture: qualifying");
    expect(s.handling?.job).toBe("Qualify");
    expect(s.handling?.assignment).toBe("Unassigned");
    expect(s.actions.map((a) => a.code)).toEqual(["welcome_explore_programmes"]);
    expect(s.actions[0]!.label).toMatch(/explore-programmes WhatsApp/);
    expect(s.qualification.label).toBe("Not yet qualified");
    expect(s.qualification.missing.map((m) => m.label)).toEqual(["email", "Witty has not confirmed the details (no HOT / WARM / COLD)"]);
    expect(s.consent.given).toBe(false);
    expect(s.consent.label).toBe("Consent requested, waiting for the answer");
    expect(s.consent.requestText).toBe("Sent · via Witty · asked at the nurture recheck");
  });
  it("reads a partner-lost hand-off's first nurture message date and a lost bar", () => {
    const s = recordSummary({
      ...v3, consent: { partner_share_given: true, state: "given", partner_share_request: null },
      allocation: { ...v3.allocation, reason: "partner_lost", b2c_lane: "nurture", partner_bar_reason: "lost", partner_barred_at: "2026-10-14T09:00:00Z", already_with_providers: [],
                    hold: { kind: "barred", open: true, allocation_id: 5503, lane: "nurture", reason: "partner_lost", owner_assigned: false },
                    job: "nurture", assignment: "unassigned_until_interest", first_contact_script: "standard", nurture_first_message_at: "2026-10-28T09:00:00Z" },
    });
    expect(s.bar?.label).toBe("A partner marked it lost");
    expect(s.handling?.assignment).toBe("Unassigned until the student shows interest");
    expect(s.handling?.nurture_first_message_at).toBe("2026-10-28T09:00:00Z");
    expect(s.consent.requestText).toBeNull();
  });
  it("tolerates a version-2 record and a lead B2C does not hold", () => {
    const s = recordSummary({ id: 1, cycle_no: 1, created_at: "2026-10-01T00:00:00Z", updated_at: null, is_test: false, deleted: false, merged_into_id: null, held_by_b2c: false,
                              allocation: { destination: "partner", reason: "rule" } });
    expect(s.version).toBe(2);
    expect(s.bar).toBeNull();
    expect(s.providers).toEqual([]);
    expect(s.hold).toBeNull();
    expect(s.handling).toBeNull();
    expect(s.qualification).toEqual({ class: null, label: null, missing: [] });
    expect(s.consent).toEqual({ given: false, state: "none", label: "No partner-sharing consent", request: null, requestText: null });
    expect(s.other_courses).toEqual([]);
    // handling is only for the lead B2C holds: the hand-off words stay empty for a partner-held lead even with stale allocation keys
    expect(recordSummary({ ...v3, held_by_b2c: false }).handling).toBeNull();
  });
  it("names a provider with or without the date the partner first had the student", () => {
    expect(describeProvider(v3.allocation!.already_with_providers![0]!)).toBe("Down Edu · first had the student on 2026-08-28 · their record LS-77001");
    expect(describeProvider(v3.allocation!.already_with_providers![1]!)).toBe("Sync Edu · date not given");
    expect(describeProvider({ partner_id: 9, partner_name: "", first_had_at: null, existing_record_id: null, claimed_at: null }, () => "x")).toBe("partner #9 · date not given");
  });
  it("knows the contract version, the always-writable field and the new events", () => {
    expect(CONTRACT_VERSION).toBe(3);
    expect(contractVersion({})).toBe(3);
    expect(contractVersion({ contract_version: 4 })).toBe(4);
    expect(ALWAYS_WRITABLE_FIELDS).toContain("other_courses");
    expect(isWritable({ writable: ["stage"] }, "other_courses")).toBe(true);
    expect(isWritable({ writable: ["stage"] }, "stage")).toBe(true);
    expect(isWritable({ writable: ["stage"] }, "phone")).toBe(false);
    for (const t of ["b2c.lead_requalified", "b2c.lead_reengaged", "b2c.consent_requested", "b2c.consent_closed", "b2c.lead_reenquired", "b2ccrm.partner_consent", "b2ccrm.consent_request_sent"]) {
      expect(eventLabel(t)).not.toBe(t);
    }
    expect(eventLabel("b2c.lead_upserted")).toBe("Lead sent");
    expect(eventLabel("something.else")).toBe("something.else");
    expect(CHECK_STEPS.map((s) => s.key)).toContain("golive_events");
  });
  it("asks for the version-3 resend until one is on record", () => {
    const sync = { in_scope: 120, held_now: 40, changes_24h: 3, last_change_at: null, last_seq: 9, tick: null };
    const out = (origin: string | null) => ({ dir: "out" as const, at: "2026-10-08T00:00:00Z", lead_id: 1, name: null, type: "upserted" as const, version: 2, origin, delivery: null });
    expect(resyncNote({ log: [out(null)], sync }, "batched")).toEqual({ batched: true });
    expect(resyncNote({ log: [out("b2c:abc")], sync }, "realtime")).toEqual({ batched: false });
    expect(resyncNote({ log: [out(null), out("resync")], sync }, "batched")).toBeNull();
    expect(resyncNote({ log: [], sync: { ...sync, in_scope: 0, held_now: 0 } }, "batched")).toBeNull();
    // once b2c_link_overview reports the last resend, it decides
    expect(resyncNote({ log: [out("resync")], sync, last_resync_at: null }, "batched")).toEqual({ batched: true });
    expect(resyncNote({ log: [], sync, last_resync_at: "2026-10-08T01:00:00Z" }, "realtime")).toBeNull();
  });
});
