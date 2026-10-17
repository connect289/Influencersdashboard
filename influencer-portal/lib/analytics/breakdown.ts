// A breakdown row with every derived metric (unit economics and lead quality), and its CSV export. Pure.
import { toCsv } from "@/lib/csv";
import { leadQuality, unitEconomics, type Totals } from "./compute";

export interface BreakdownRow {
  key: string | null;
  label: string;
  t: Totals;
  cost_per_lead_paise: number | null;
  cost_per_qualified_paise: number | null;
  cost_per_enrollment_paise: number | null;
  net_roi: number | null;
  roas: number | null;
  qualification_rate: number | null;
  junk_rate: number | null;
  duplicate_rate: number | null;
  enrollment_rate: number | null;
}

export function toBreakdown<T extends Totals & { key: string | null }>(rows: readonly T[], label: (r: T) => string) {
  return rows.map((r): BreakdownRow => {
    const e = unitEconomics(r);
    const q = leadQuality(r);
    return {
      key: r.key,
      label: label(r),
      t: r,
      cost_per_lead_paise: e.cost_per_lead_paise,
      cost_per_qualified_paise: e.cost_per_qualified_paise,
      cost_per_enrollment_paise: e.cost_per_enrollment_paise,
      net_roi: e.net_roi,
      roas: e.roas,
      ...q,
    };
  });
}

/** Sorted for display: most leads first, then most spend; rows without a key (unsplit) last. */
export function sortBreakdown(rows: readonly BreakdownRow[]): BreakdownRow[] {
  return [...rows].sort(
    (a, b) =>
      Number(a.key === null) - Number(b.key === null) || b.t.leads - a.t.leads || b.t.cost_paise - a.t.cost_paise,
  );
}

const rupees = (paise: number | null) => (paise === null ? "" : (paise / 100).toFixed(2));
const rate = (v: number | null) => (v === null ? "" : (v * 100).toFixed(1));
const x = (v: number | null) => (v === null ? "" : v.toFixed(2));

/** CSV of a breakdown: counts, rupees (2 decimals) and percentages (1 decimal), blank when not defined. */
export function breakdownCsv(rows: readonly BreakdownRow[], dimension: string): string {
  return toCsv(
    [
      dimension,
      "Clicks",
      "Leads",
      "Qualified",
      "Enrolled",
      "Junk",
      "Duplicates",
      "Spend (INR)",
      "Revenue (INR)",
      "Cost per lead (INR)",
      "Cost per qualified lead (INR)",
      "Cost per enrolment (INR)",
      "Net ROI (%)",
      "ROAS",
      "Qualification rate (%)",
      "Junk rate (%)",
      "Duplicate rate (%)",
      "Enrolment rate (%)",
    ],
    rows.map((r) => [
      r.label,
      r.t.clicks,
      r.t.leads,
      r.t.qualified,
      r.t.enrolled,
      r.t.junk,
      r.t.duplicates,
      rupees(r.t.cost_paise),
      rupees(r.t.revenue_paise),
      rupees(r.cost_per_lead_paise),
      rupees(r.cost_per_qualified_paise),
      rupees(r.cost_per_enrollment_paise),
      rate(r.net_roi),
      x(r.roas),
      rate(r.qualification_rate),
      rate(r.junk_rate),
      rate(r.duplicate_rate),
      rate(r.enrollment_rate),
    ]),
  );
}
