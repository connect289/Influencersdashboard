// TDS and GST estimate for a set of ledger lines (spec 11). Pure. The section table is configuration (Finance edits
// it; defaults are marked "confirm with CA", D-19); this module only applies it.
//
// Rules applied, per section:
//   * the base is the net of the lines whose component maps to the section (never negative), excluding GST;
//   * TDS applies when the base exceeds the per-transaction threshold, or when the creator's FY aggregate (prior +
//     this base) exceeds the FY threshold; on the transaction that first crosses the FY threshold, TDS is also
//     deducted on the earlier untaxed amounts of the FY ("catch-up"), as the Income-tax Act requires;
//   * the rate is the section rate, or the no-PAN rate (206AA) when the creator has no verified PAN;
//   * sections borne by Eduwit (194R on barter) are reported but never deducted from the payout.
import type { EntryType, LedgerLine } from "./engine";
import { pctOf, sum, type Paise } from "./money";

export const TDS_COMPONENTS = [
  "commission",
  "fixed_fee",
  "milestone",
  "bonus",
  "usage_fee",
  "exclusivity_fee",
  "reimbursement",
  "non_cash",
] as const;
export type TdsComponent = (typeof TDS_COMPONENTS)[number];

export interface TdsSection {
  code: string;
  label: string;
  rate_bps: number;
  no_pan_rate_bps: number;
  single_threshold_paise: Paise | null;
  fy_threshold_paise: Paise | null;
  components: TdsComponent[];
  /** "eduwit": Eduwit pays the tax itself (194R on barter); nothing is deducted from the creator. */
  borne_by: "creator" | "eduwit";
}

/** Approved defaults (PHASE0_FINDINGS Q9, D-19), editable by Finance and marked "confirm with CA". */
export const DEFAULT_TDS_SECTIONS: TdsSection[] = [
  {
    code: "194H",
    label: "Commission or brokerage",
    rate_bps: 200,
    no_pan_rate_bps: 2000,
    single_threshold_paise: null,
    fy_threshold_paise: 20_000_00,
    components: ["commission"],
    borne_by: "creator",
  },
  {
    code: "194J",
    label: "Fees for professional services",
    rate_bps: 1000,
    no_pan_rate_bps: 2000,
    single_threshold_paise: null,
    fy_threshold_paise: 50_000_00,
    components: ["fixed_fee", "milestone", "bonus", "usage_fee", "exclusivity_fee"],
    borne_by: "creator",
  },
  {
    code: "194R",
    label: "Benefit or perquisite (barter)",
    rate_bps: 1000,
    no_pan_rate_bps: 2000,
    single_threshold_paise: null,
    fy_threshold_paise: 20_000_00,
    components: ["non_cash"],
    borne_by: "eduwit",
  },
];

/** The income component a line belongs to. Engine clawbacks and adjustments (recoupment, floors) are commission. */
export function componentOf(line: Pick<LedgerLine, "type">): TdsComponent {
  const t: EntryType = line.type;
  return t === "clawback" || t === "adjustment" ? "commission" : t;
}

export interface TaxInput {
  lines: readonly Pick<LedgerLine, "type" | "direction" | "amount_paise">[];
  /** Barter value in this computation (194R base). */
  non_cash_paise?: Paise;
  sections: readonly TdsSection[];
  has_pan: boolean;
  gst: { registered: boolean; rate_bps: number };
  /** The creator's FY so far, per section code: amounts already paid and whether TDS was deducted on them. */
  fy_prior?: Record<string, { base_paise: Paise; taxed: boolean }>;
}

export interface SectionTax {
  code: string;
  label: string;
  base_paise: Paise;
  /** The amount TDS is charged on (base, plus the FY catch-up when the threshold is first crossed). */
  taxable_paise: Paise;
  rate_bps: number;
  tds_paise: Paise;
  borne_by: "creator" | "eduwit";
}

export interface TaxEstimate {
  gross_paise: Paise;
  sections: SectionTax[];
  /** Deducted from the payout. */
  tds_paise: Paise;
  /** Paid by Eduwit on the creator's behalf (194R). */
  eduwit_tds_paise: Paise;
  /** Untaxed amount (no section maps the component). */
  unmapped_paise: Paise;
  gst_paise: Paise;
  net_paise: Paise;
}

export function estimateTax(input: TaxInput): TaxEstimate {
  const byComponent = new Map<TdsComponent, Paise>();
  for (const l of input.lines) {
    const c = componentOf(l);
    byComponent.set(
      c,
      (byComponent.get(c) ?? 0) + (l.direction === "credit" ? l.amount_paise : -l.amount_paise),
    );
  }
  if (input.non_cash_paise) byComponent.set("non_cash", input.non_cash_paise);
  const gross = sum([...byComponent.entries()].filter(([c]) => c !== "non_cash").map(([, v]) => v));

  const mapped = new Set<TdsComponent>();
  const sections: SectionTax[] = [];
  for (const s of input.sections) {
    const base = Math.max(
      sum(s.components.filter((c) => !mapped.has(c)).map((c) => byComponent.get(c) ?? 0)),
      0,
    );
    for (const c of s.components) mapped.add(c);
    if (base === 0) continue;
    const prior = input.fy_prior?.[s.code] ?? { base_paise: 0, taxed: false };
    const overSingle = s.single_threshold_paise !== null && base > s.single_threshold_paise;
    const overFy = s.fy_threshold_paise === null || prior.base_paise + base > s.fy_threshold_paise;
    const applies = overSingle || overFy;
    const catchUp =
      applies && overFy && !prior.taxed && s.fy_threshold_paise !== null ? prior.base_paise : 0;
    const taxable = applies ? base + catchUp : 0;
    const rate = input.has_pan ? s.rate_bps : s.no_pan_rate_bps;
    sections.push({
      code: s.code,
      label: s.label,
      base_paise: base,
      taxable_paise: taxable,
      rate_bps: rate,
      tds_paise: pctOf(taxable, rate),
      borne_by: s.borne_by,
    });
  }
  const unmapped = sum(
    [...byComponent.entries()]
      .filter(([c]) => c !== "non_cash" && !mapped.has(c))
      .map(([, v]) => Math.max(v, 0)),
  );
  const tds = sum(sections.filter((s) => s.borne_by === "creator").map((s) => s.tds_paise));
  const eduwitTds = sum(sections.filter((s) => s.borne_by === "eduwit").map((s) => s.tds_paise));
  // GST is charged by a registered creator on their services; reimbursements of actual costs are not a supply.
  const gstBase = Math.max(gross - Math.max(byComponent.get("reimbursement") ?? 0, 0), 0);
  const gst = input.gst.registered ? pctOf(gstBase, input.gst.rate_bps) : 0;
  return {
    gross_paise: gross,
    sections,
    tds_paise: tds,
    eduwit_tds_paise: eduwitTds,
    unmapped_paise: unmapped,
    gst_paise: gst,
    net_paise: gross + gst - tds,
  };
}
