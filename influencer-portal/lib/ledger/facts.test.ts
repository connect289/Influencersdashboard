import { describe, expect, it } from "vitest";
import { dealEvents, type DealFacts } from "./facts";

const empty: DealFacts = {
  contract_signed_at: null,
  brief_acknowledged_at: null,
  deliverables: [],
  leads: [],
  enrollments: [],
  receipts: [],
  manual: [],
  campaign_ended_at: null,
  deal_completed_at: null,
};
const lead = {
  id: "a1",
  at: "2026-11-02T10:00:00.000Z",
  link_id: "l1",
  deliverable_ref: "reel1",
  programme_id: 7,
  university_id: 3,
  level: "PG",
  qualified_at: "2026-11-03T10:00:00.000Z",
  applied_at: null,
  rejected_at: null,
  junk: false,
};
const enrol = {
  ref: "b2b:9",
  lead_id: "a1",
  at: "2026-11-20T00:00:00.000Z",
  programme_id: null,
  university_id: null,
  level: null,
  fee_paise: 15_000_000,
  expected_commission_gross_paise: 1_180_000,
  cancelled_at: null,
};

describe("deal facts → engine events", () => {
  it("is empty for an empty deal", () => expect(dealEvents(empty)).toEqual([]));

  it("turns a credited lead and its stages into lead events with scope fields", () => {
    const ev = dealEvents({ ...empty, leads: [lead] });
    expect(ev.map((e) => e.type)).toEqual(["lead", "lead_qualified"]);
    expect(ev[0]).toMatchObject({
      lead: "a1",
      link: "l1",
      deliverable: "reel1",
      programme_id: 7,
      level: "PG",
      junk: false,
    });
  });

  it("leaves out scope fields that are unknown", () => {
    const ev = dealEvents({ ...empty, leads: [{ ...lead, link_id: null, deliverable_ref: null, programme_id: null }] });
    expect(ev[0]).not.toHaveProperty("link");
    expect(ev[0]).not.toHaveProperty("deliverable");
    expect(ev[0]).not.toHaveProperty("programme_id");
  });

  it("counts enrolments only for this deal's credited leads, inheriting the lead's scope", () => {
    const ev = dealEvents({
      ...empty,
      leads: [lead],
      enrollments: [enrol, { ...enrol, ref: "b2c:4", lead_id: "other" }],
    });
    const enrolled = ev.filter((e) => e.type === "enrolled");
    expect(enrolled).toHaveLength(1);
    expect(enrolled[0]).toMatchObject({
      enrollment: "b2b:9",
      programme_id: 7,
      university_id: 3,
      link: "l1",
      deliverable: "reel1",
      fee_paise: 15_000_000,
      expected_commission_gross_paise: 1_180_000,
    });
  });

  it("adds cancellations and receipts, never before the enrolment", () => {
    const ev = dealEvents({
      ...empty,
      leads: [lead],
      enrollments: [{ ...enrol, cancelled_at: "2026-12-05T00:00:00.000Z" }],
      receipts: [
        { enrollment_ref: "b2b:9", received_paise: 1_180_000, received_on: "2026-11-01T00:00:00.000Z", full: true },
        { enrollment_ref: "b2b:404", received_paise: 500, received_on: "2026-11-25T00:00:00.000Z", full: true },
        { enrollment_ref: "b2b:9", received_paise: 0, received_on: "2026-11-26T00:00:00.000Z", full: false },
      ],
    });
    const receipt = ev.filter((e) => e.type === "commission_received");
    expect(receipt).toHaveLength(1);
    expect(receipt[0]).toMatchObject({ at: enrol.at, gross_paise: 1_180_000, full: true });
    expect(ev.some((e) => e.type === "enrollment_cancelled")).toBe(true);
  });

  it("includes manual releases, breaches and the deal closing, ordered by time then id", () => {
    const ev = dealEvents({
      ...empty,
      contract_signed_at: "2026-11-01T00:00:00.000Z",
      manual: [
        { id: "m2", kind: "breach", ref: null, at: "2026-11-05T00:00:00.000Z" },
        { id: "m1", kind: "manual_release", ref: "fee.live", at: "2026-11-05T00:00:00.000Z" },
        { id: "m3", kind: "manual_release", ref: null, at: "2026-11-06T00:00:00.000Z" },
      ],
      campaign_ended_at: "2026-12-31T18:30:00.000Z",
      deal_completed_at: "2027-01-02T00:00:00.000Z",
    });
    expect(ev.map((e) => e.id)).toEqual([
      "contract_signed",
      "manual:m1",
      "manual:m2",
      "campaign_ended",
      "deal_completed",
    ]);
  });

  it("is deterministic whatever the input order", () => {
    const a = dealEvents({ ...empty, leads: [lead, { ...lead, id: "a2" }] });
    const b = dealEvents({ ...empty, leads: [{ ...lead, id: "a2" }, lead] });
    expect(a).toEqual(b);
  });
});
