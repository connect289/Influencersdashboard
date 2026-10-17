// Preparing a payout batch (spec 11): every creator with payable entries becomes a payout built by buildPayout(), or a
// skipped line with the reason. Entries from deals whose contract names an agency as payee are held for Finance to
// arrange (or paid to the creator, per Settings → Finance → Payouts). Pure.
import type { TdsSection } from "@/lib/compensation/tax";
import { buildPayout, signed, type PayableEntry, type PayoutPlan, type SkipReason } from "./payout";

export interface CandidateCreator {
  creator_id: string;
  name: string;
  kyc_verified: boolean;
  has_pan: boolean;
  charges_gst: boolean;
  fy_prior: Record<string, { base_paise: number; taxed: boolean }>;
  entries: readonly (PayableEntry & { agency_payee: boolean })[];
}

export interface CandidateRules {
  payouts: {
    kyc_required_for_payout: boolean;
    hold_until_tax_confirmed: boolean;
    min_payout_rupees: number;
    agency_payee: "hold" | "pay_creator";
  };
  gst: { rate_pct: number; require_invoice_for_registered: boolean };
  sections: readonly TdsSection[];
  sections_confirmed: boolean;
}

export interface PreparedPayout extends PayoutPlan {
  creator_id: string;
  name: string;
}

export interface Skipped {
  creator_id: string;
  name: string;
  reason: SkipReason;
  /** Signed total of the entries left out. */
  amount_paise: number;
}

export function preparePayouts(
  creators: readonly CandidateCreator[],
  rules: CandidateRules,
): {
  payouts: PreparedPayout[];
  skipped: Skipped[];
} {
  const payouts: PreparedPayout[] = [];
  const skipped: Skipped[] = [];
  const payRules = {
    kyc_required: rules.payouts.kyc_required_for_payout,
    min_payout_paise: rules.payouts.min_payout_rupees * 100,
    gst_rate_bps: Math.round(rules.gst.rate_pct * 100),
    require_invoice: rules.gst.require_invoice_for_registered,
    hold_until_tax_confirmed: rules.payouts.hold_until_tax_confirmed,
    sections_confirmed: rules.sections_confirmed,
    sections: rules.sections,
  };
  for (const c of creators) {
    const holdAgency = rules.payouts.agency_payee === "hold";
    const agency = holdAgency ? c.entries.filter((e) => e.agency_payee) : [];
    const own = holdAgency ? c.entries.filter((e) => !e.agency_payee) : c.entries;
    if (agency.length)
      skipped.push({
        creator_id: c.creator_id,
        name: c.name,
        reason: "agency_payee",
        amount_paise: agency.reduce((t, e) => t + signed(e), 0),
      });
    if (!own.length) continue;
    const r = buildPayout({
      entries: own,
      profile: { kyc_verified: c.kyc_verified, has_pan: c.has_pan, charges_gst: c.charges_gst, agency_payee: false },
      rules: payRules,
      fy_prior: c.fy_prior,
    });
    if (r.ok) payouts.push({ ...r.payout, creator_id: c.creator_id, name: c.name });
    else skipped.push({ creator_id: c.creator_id, name: c.name, reason: r.reason, amount_paise: r.gross_paise });
  }
  return { payouts, skipped };
}
