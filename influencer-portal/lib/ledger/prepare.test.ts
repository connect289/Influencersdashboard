import { describe, expect, it } from "vitest";
import { DEFAULT_TDS_SECTIONS } from "@/lib/compensation/tax";
import { preparePayouts, type CandidateCreator, type CandidateRules } from "./prepare";

const rules: CandidateRules = {
  payouts: {
    kyc_required_for_payout: true,
    hold_until_tax_confirmed: false,
    min_payout_rupees: 0,
    agency_payee: "hold",
  },
  gst: { rate_pct: 18, require_invoice_for_registered: true },
  sections: DEFAULT_TDS_SECTIONS,
  sections_confirmed: false,
};
const entry = (id: number, paise: number, agency = false) => ({
  id,
  type: "milestone" as const,
  direction: "credit" as const,
  remaining_paise: paise,
  tds_component: "milestone" as const,
  agency_payee: agency,
});
const creator = (over: Partial<CandidateCreator>): CandidateCreator => ({
  creator_id: "c1",
  name: "Riya",
  kyc_verified: true,
  has_pan: true,
  charges_gst: false,
  fy_prior: {},
  entries: [entry(1, 10_000_00)],
  ...over,
});

describe("preparePayouts", () => {
  it("builds one payout per creator who can be paid", () => {
    const r = preparePayouts(
      [creator({}), creator({ creator_id: "c2", name: "Arjun", entries: [entry(2, 5_000_00)] })],
      rules,
    );
    expect(r.payouts.map((p) => [p.creator_id, p.net_paise])).toEqual([
      ["c1", 10_000_00],
      ["c2", 5_000_00],
    ]);
    expect(r.skipped).toEqual([]);
  });

  it("skips creators with a reason and the amount left out", () => {
    const r = preparePayouts([creator({ kyc_verified: false })], rules);
    expect(r.payouts).toEqual([]);
    expect(r.skipped).toEqual([{ creator_id: "c1", name: "Riya", reason: "kyc", amount_paise: 10_000_00 }]);
  });

  it("holds agency-payee entries but pays the creator's other entries", () => {
    const r = preparePayouts([creator({ entries: [entry(1, 10_000_00), entry(2, 3_000_00, true)] })], rules);
    expect(r.payouts[0]?.items).toEqual([{ entry_id: 1, amount_paise: 10_000_00 }]);
    expect(r.skipped).toEqual([{ creator_id: "c1", name: "Riya", reason: "agency_payee", amount_paise: 3_000_00 }]);
  });

  it("pays agency-payee entries to the creator when Finance chose that", () => {
    const r = preparePayouts([creator({ entries: [entry(1, 10_000_00), entry(2, 3_000_00, true)] })], {
      ...rules,
      payouts: { ...rules.payouts, agency_payee: "pay_creator" },
    });
    expect(r.payouts[0]?.gross_paise).toBe(13_000_00);
    expect(r.skipped).toEqual([]);
  });

  it("converts the minimum payout and GST rate from settings", () => {
    const below = preparePayouts([creator({})], { ...rules, payouts: { ...rules.payouts, min_payout_rupees: 20_000 } });
    expect(below.skipped[0]?.reason).toBe("below_minimum");
    const gst = preparePayouts([creator({ charges_gst: true })], {
      ...rules,
      gst: { rate_pct: 12, require_invoice_for_registered: false },
    });
    expect(gst.payouts[0]).toMatchObject({ gst_paise: 1_200_00, needs_invoice: false });
  });
});
