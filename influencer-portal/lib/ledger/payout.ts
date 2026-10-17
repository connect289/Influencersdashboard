// One creator's payout from their payable ledger entries (spec 11): eligibility, gross, TDS per section with the FY
// aggregates and catch-up (estimateTax), GST for registered creators, and net. A creator whose payable total is not
// positive is carried forward: debits (clawbacks, penalties, recoveries) wait for future earnings. Pure.
import type { Paise } from "@/lib/compensation/money";
import { estimateTax, type SectionTax, type TdsComponent, type TdsSection } from "@/lib/compensation/tax";
import type { LedgerType } from "./lifecycle";

export interface PayableEntry {
  id: number;
  type: LedgerType;
  direction: "credit" | "debit";
  /** What the payout may take from the entry (unsigned). */
  remaining_paise: Paise;
  tds_component: TdsComponent;
}

export interface PayoutProfile {
  kyc_verified: boolean;
  /** PAN verified (otherwise the higher no-PAN rate applies). */
  has_pan: boolean;
  /** Charges GST: registered, GSTIN verified, not under composition. */
  charges_gst: boolean;
  /** The creator's contract names their agency as payee (D-131: held for Finance to arrange). */
  agency_payee: boolean;
}

export interface PayoutRules {
  kyc_required: boolean;
  min_payout_paise: Paise;
  gst_rate_bps: number;
  require_invoice: boolean;
  /** Hold payouts until every TDS section is marked confirmed by the CA. */
  hold_until_tax_confirmed: boolean;
  sections_confirmed: boolean;
  sections: readonly TdsSection[];
}

export const SKIP_REASONS = ["no_amount", "below_minimum", "kyc", "tax_unconfirmed", "agency_payee"] as const;
export type SkipReason = (typeof SKIP_REASONS)[number];

export interface PayoutItem {
  entry_id: number;
  /** Signed: credits positive, debits negative. */
  amount_paise: Paise;
}

export interface PayoutPlan {
  gross_paise: Paise;
  gst_base_paise: Paise;
  gst_paise: Paise;
  /** Deducted from the payout. */
  tds_paise: Paise;
  /** Borne by Eduwit (194R on barter); reported, never deducted. */
  eduwit_tds_paise: Paise;
  net_paise: Paise;
  sections: SectionTax[];
  needs_invoice: boolean;
  items: PayoutItem[];
}

export type PayoutResult = { ok: true; payout: PayoutPlan } | { ok: false; reason: SkipReason; gross_paise: Paise };

export function signed(e: Pick<PayableEntry, "direction" | "remaining_paise">): Paise {
  return e.direction === "credit" ? e.remaining_paise : -e.remaining_paise;
}

export function buildPayout(input: {
  entries: readonly PayableEntry[];
  profile: PayoutProfile;
  rules: PayoutRules;
  /** The creator's FY so far per section code (from TDS records). */
  fy_prior: Record<string, { base_paise: Paise; taxed: boolean }>;
}): PayoutResult {
  const items = input.entries
    .filter((e) => e.remaining_paise > 0)
    .map((e) => ({ entry_id: e.id, amount_paise: signed(e) }))
    .sort((a, b) => a.entry_id - b.entry_id);
  const gross = items.reduce((t, i) => t + i.amount_paise, 0);
  const skip = (reason: SkipReason): PayoutResult => ({ ok: false, reason, gross_paise: gross });
  if (gross <= 0) return skip("no_amount");
  if (input.rules.kyc_required && !input.profile.kyc_verified) return skip("kyc");
  if (input.rules.hold_until_tax_confirmed && !input.rules.sections_confirmed) return skip("tax_unconfirmed");
  if (input.profile.agency_payee) return skip("agency_payee");

  const byId = new Map(input.entries.map((e) => [e.id, e]));
  const tax = estimateTax({
    lines: items.map((i) => {
      const e = byId.get(i.entry_id) as PayableEntry;
      return {
        type: "adjustment" as const,
        direction: e.direction,
        amount_paise: e.remaining_paise,
        component: e.tds_component,
      };
    }),
    sections: input.rules.sections,
    has_pan: input.profile.has_pan,
    gst: { registered: input.profile.charges_gst, rate_bps: input.rules.gst_rate_bps },
    fy_prior: input.fy_prior,
  });
  if (tax.net_paise < input.rules.min_payout_paise) return skip("below_minimum");
  return {
    ok: true,
    payout: {
      gross_paise: tax.gross_paise,
      gst_base_paise: tax.gst_base_paise,
      gst_paise: tax.gst_paise,
      tds_paise: tax.tds_paise,
      eduwit_tds_paise: tax.eduwit_tds_paise,
      net_paise: tax.net_paise,
      sections: tax.sections,
      needs_invoice: input.profile.charges_gst && input.rules.require_invoice,
      items,
    },
  };
}

/** TDS component a ledger entry is taxed under when it is posted (engine lines by type; others as given). */
export function componentForType(type: LedgerType): TdsComponent {
  switch (type) {
    case "commission":
    case "clawback":
    case "adjustment":
      return "commission";
    case "penalty":
      // A penalty reduces the fees it was charged against.
      return "fixed_fee";
    case "fixed_fee":
    case "milestone":
    case "bonus":
    case "usage_fee":
    case "exclusivity_fee":
    case "reimbursement":
      return type;
    case "reversal":
    case "tds":
    case "gst":
    case "payout":
      throw new Error(`${type} entries take the component of the entry they settle or reverse`);
  }
}
