import { describe, expect, it } from "vitest";
import { DEFAULT_TDS_SECTIONS } from "@/lib/compensation/tax";
import {
  buildPayout,
  componentForType,
  signed,
  type PayableEntry,
  type PayoutProfile,
  type PayoutRules,
} from "./payout";

const profile: PayoutProfile = { kyc_verified: true, has_pan: true, charges_gst: false, agency_payee: false };
const rules: PayoutRules = {
  kyc_required: true,
  min_payout_paise: 0,
  gst_rate_bps: 1800,
  require_invoice: true,
  hold_until_tax_confirmed: false,
  sections_confirmed: false,
  sections: DEFAULT_TDS_SECTIONS,
};
const fee = (id: number, paise: number, over: Partial<PayableEntry> = {}): PayableEntry => ({
  id,
  type: "milestone",
  direction: "credit",
  remaining_paise: paise,
  tds_component: "milestone",
  ...over,
});
const commission = (id: number, paise: number): PayableEntry => ({
  id,
  type: "commission",
  direction: "credit",
  remaining_paise: paise,
  tds_component: "commission",
});

describe("buildPayout", () => {
  it("pays below the TDS thresholds without deduction", () => {
    const r = buildPayout({ entries: [fee(1, 30_000_00)], profile, rules, fy_prior: {} });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.payout).toMatchObject({ gross_paise: 30_000_00, tds_paise: 0, gst_paise: 0, net_paise: 30_000_00 });
    expect(r.payout.items).toEqual([{ entry_id: 1, amount_paise: 30_000_00 }]);
  });

  it("deducts 194J at 10% once fees pass ₹50,000 in the FY, with catch-up on earlier fees", () => {
    const r = buildPayout({
      entries: [fee(1, 20_000_00)],
      profile,
      rules,
      fy_prior: { "194J": { base_paise: 40_000_00, taxed: false } },
    });
    if (!r.ok) throw new Error(r.reason);
    const j = r.payout.sections.find((s) => s.code === "194J");
    expect(j).toMatchObject({ base_paise: 20_000_00, taxable_paise: 60_000_00, tds_paise: 6_000_00 });
    expect(r.payout.net_paise).toBe(14_000_00);
  });

  it("uses the no-PAN rate without a verified PAN", () => {
    const r = buildPayout({
      entries: [commission(1, 25_000_00)],
      profile: { ...profile, has_pan: false },
      rules: { ...rules, kyc_required: false },
      fy_prior: {},
    });
    if (!r.ok) throw new Error(r.reason);
    expect(r.payout.tds_paise).toBe(5_000_00);
  });

  it("adds GST for a registered creator and asks for an invoice", () => {
    const r = buildPayout({
      entries: [fee(1, 10_000_00)],
      profile: { ...profile, charges_gst: true },
      rules,
      fy_prior: {},
    });
    if (!r.ok) throw new Error(r.reason);
    expect(r.payout).toMatchObject({
      gst_base_paise: 10_000_00,
      gst_paise: 1_800_00,
      net_paise: 11_800_00,
      needs_invoice: true,
    });
    const noInvoice = buildPayout({
      entries: [fee(1, 10_000_00)],
      profile: { ...profile, charges_gst: true },
      rules: { ...rules, require_invoice: false },
      fy_prior: {},
    });
    expect(noInvoice.ok && noInvoice.payout.needs_invoice).toBe(false);
  });

  it("does not charge GST on reimbursements", () => {
    const r = buildPayout({
      entries: [fee(1, 10_000_00), fee(2, 2_000_00, { type: "reimbursement", tds_component: "reimbursement" })],
      profile: { ...profile, charges_gst: true },
      rules,
      fy_prior: {},
    });
    if (!r.ok) throw new Error(r.reason);
    expect(r.payout.gst_base_paise).toBe(10_000_00);
    expect(r.payout.gst_paise).toBe(1_800_00);
  });

  it("nets debits against credits and carries a negative total forward", () => {
    const penalty = fee(2, 4_000_00, { type: "penalty", direction: "debit", tds_component: "fixed_fee" });
    const r = buildPayout({ entries: [fee(1, 10_000_00), penalty], profile, rules, fy_prior: {} });
    if (!r.ok) throw new Error(r.reason);
    expect(r.payout.gross_paise).toBe(6_000_00);
    expect(r.payout.items).toEqual([
      { entry_id: 1, amount_paise: 10_000_00 },
      { entry_id: 2, amount_paise: -4_000_00 },
    ]);
    const negative = buildPayout({ entries: [fee(1, 1_000_00), { ...penalty, id: 2 }], profile, rules, fy_prior: {} });
    expect(negative).toEqual({ ok: false, reason: "no_amount", gross_paise: -3_000_00 });
  });

  it("skips creators who cannot be paid yet, in a fixed order of reasons", () => {
    const run = (p: Partial<PayoutProfile>, r: Partial<PayoutRules> = {}) =>
      buildPayout({
        entries: [fee(1, 1_000_00)],
        profile: { ...profile, ...p },
        rules: { ...rules, ...r },
        fy_prior: {},
      });
    expect(run({ kyc_verified: false })).toMatchObject({ ok: false, reason: "kyc" });
    expect(run({ kyc_verified: false }, { kyc_required: false }).ok).toBe(true);
    expect(run({}, { hold_until_tax_confirmed: true })).toMatchObject({ ok: false, reason: "tax_unconfirmed" });
    expect(run({}, { hold_until_tax_confirmed: true, sections_confirmed: true }).ok).toBe(true);
    expect(run({ agency_payee: true })).toMatchObject({ ok: false, reason: "agency_payee" });
    expect(run({}, { min_payout_paise: 5_000_00 })).toMatchObject({ ok: false, reason: "below_minimum" });
    expect(buildPayout({ entries: [], profile, rules, fy_prior: {} })).toMatchObject({
      ok: false,
      reason: "no_amount",
    });
  });

  it("ignores entries with nothing left to pay and orders items by entry", () => {
    const r = buildPayout({ entries: [fee(5, 100), fee(3, 0), fee(4, 200)], profile, rules, fy_prior: {} });
    if (!r.ok) throw new Error(r.reason);
    expect(r.payout.items.map((i) => i.entry_id)).toEqual([4, 5]);
  });

  it("signs entries by direction and maps types to TDS components", () => {
    expect(signed({ direction: "debit", remaining_paise: 5 })).toBe(-5);
    expect(componentForType("penalty")).toBe("fixed_fee");
    expect(componentForType("clawback")).toBe("commission");
    expect(componentForType("usage_fee")).toBe("usage_fee");
    expect(() => componentForType("payout")).toThrow();
  });
});
