import { describe, expect, it } from "vitest";
import type { EngineContext } from "@/lib/compensation/engine";
import { compConfig } from "@/lib/compensation/schema";
import { contentEvents, deliverableRef, penaltyProposals, type DeliverableFacts } from "./events";

const context: EngineContext = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};
const config = compConfig.parse({
  schema_version: 1,
  fixed: [
    {
      id: "fee",
      label: "Content fee",
      amount_paise: 20_000_00,
      basis: "lump_sum",
      milestones: [
        {
          id: "live",
          label: "On live",
          share: { type: "pct", pct: 100 },
          trigger: { type: "on_deliverable_live", deliverable: "reel1" },
        },
      ],
    },
  ],
  penalties: [
    {
      id: "late",
      type: "late_delivery",
      label: "Late delivery",
      grace_days: 1,
      per_day: { type: "amount", amount_paise: 500_00 },
    },
    {
      id: "missed",
      type: "missed_deliverable",
      label: "Missed deliverable",
      action: { type: "fixed", amount_paise: 1_000_00 },
    },
    { id: "disc", type: "disclosure", label: "Missing disclosure", amount_paise: 700_00 },
  ],
});
const versions = [{ id: "v1", effective_from: "2026-11-01T00:00:00.000Z", config }];
const deal = { id: "d1", starts_on: "2026-11-01", ends_on: null };
const base: DeliverableFacts = {
  id: "11111111-1111-4111-8111-111111111111",
  config_ref: "reel1",
  due_live_at: "2026-11-10T18:29:59.000Z",
  concept_approved_at: null,
  draft_approved_at: null,
  live_at: null,
  cancelled_at: null,
  disclosure_failed_at: null,
  metrics: [],
};
const facts = (d: Partial<DeliverableFacts>[]) => ({
  contract_signed_at: "2026-11-01T06:00:00.000Z",
  brief_acknowledged_at: "2026-11-02T06:00:00.000Z",
  deliverables: d.map((x, i) => ({ ...base, id: `${base.id.slice(0, -1)}${String(i)}`, ...x })),
});

describe("contentEvents", () => {
  it("orders events, due dates first, with stable ids", () => {
    const ev = contentEvents(
      facts([
        {
          live_at: "2026-11-12T10:00:00.000Z",
          metrics: [{ at: "2026-11-13T10:00:00.000Z", views: 5000, reach: null }],
        },
      ]),
    );
    expect(ev.map((e) => e.type)).toEqual([
      "deliverable_due",
      "contract_signed",
      "brief_acknowledged",
      "deliverable_live",
      "metric",
    ]);
    expect(new Set(ev.map((e) => e.id)).size).toBe(ev.length);
  });
  it("uses the deal's rule id when there is one", () => {
    expect(deliverableRef({ id: "abc", config_ref: null })).toBe("abc");
    expect(deliverableRef({ id: "abc", config_ref: "reel1" })).toBe("reel1");
  });
});

describe("penaltyProposals", () => {
  it("proposes late delivery after the grace days", () => {
    const p = penaltyProposals({
      deal,
      versions,
      context,
      as_of: "2026-12-01T00:00:00.000Z",
      facts: facts([{ live_at: "2026-11-13T10:00:00.000Z" }]),
    });
    // Due 10 Nov 23:59 IST, live 13 Nov 15:30 IST: 2.6 days late − 1 grace day → 2 days × ₹500.
    expect(p.map((x) => [x.rule_id, x.amount_paise])).toEqual([["late", 1_000_00]]);
    expect(p[0]?.key).toBe("v1:late:reel1:penalty");
  });
  it("nothing when on time, or not yet live", () => {
    expect(
      penaltyProposals({
        deal,
        versions,
        context,
        as_of: "2026-12-01T00:00:00.000Z",
        facts: facts([{ live_at: "2026-11-10T10:00:00.000Z" }]),
      }),
    ).toEqual([]);
    expect(
      penaltyProposals({ deal, versions, context, as_of: "2026-12-01T00:00:00.000Z", facts: facts([{}]) }),
    ).toEqual([]);
  });
  it("proposes the missed-deliverable and disclosure penalties", () => {
    const p = penaltyProposals({
      deal,
      versions,
      context,
      as_of: "2026-12-01T00:00:00.000Z",
      facts: facts([
        { cancelled_at: "2026-11-20T10:00:00.000Z" },
        { config_ref: "reel2", live_at: "2026-11-09T10:00:00.000Z", disclosure_failed_at: "2026-11-09T12:00:00.000Z" },
      ]),
    });
    expect(p.map((x) => [x.rule_id, x.subject, x.amount_paise]).sort()).toEqual([
      ["disc", "reel2", 700_00],
      ["missed", "reel1", 1_000_00],
    ]);
    expect(p.find((x) => x.rule_id === "missed")?.forfeits).toEqual(["fee.live"]);
  });
  it("is deterministic", () => {
    const input = {
      deal,
      versions,
      context,
      as_of: "2026-12-01T00:00:00.000Z",
      facts: facts([{ live_at: "2026-11-15T10:00:00.000Z" }]),
    };
    expect(penaltyProposals(input)).toEqual(penaltyProposals(input));
  });
});
