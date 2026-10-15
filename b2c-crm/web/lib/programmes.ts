/**
 * The Programme page (B8.9): the row b2c.programme_search returns and how the page's address becomes its query.
 * Pure, unit-tested in programmes.test.ts.
 */

export type Programme = {
  id: number; name: string; course: string | null; specialization: string | null; level: string | null; mode: string | null;
  university: string; university_id: number | null; university_short: string | null; duration_months: number | null;
  fee_yearly: number | null; fee_semester: number | null; fee_total: number | null; fee_exam: number | null; fee_registration: number | null;
  emi_monthly: number | null; scholarship: string | null; intakes: string[] | null; deadline: string | null; accreditation: string | null;
  recognitions: unknown; min_qualification: string | null; min_pct: number | null; eligibility: string | null; brochure_url: string | null;
  enrollments: number; eligible: boolean | null; within_budget: boolean | null;
  /** Admin and Marketing only: the database leaves these out for everyone else. */
  partners?: { partner_id: number; name: string; commission: unknown }[];
  eduwit_commission?: { rate_type: string; value: number; fee_base: string; amount: number | null } | null;
  /** Programme fit only. */
  fit?: number; matched?: string[];
};

export type Facets = {
  universities: string[]; specializations: string[]; levels: string[]; modes: string[]; intakes: string[];
  fee: { min: number | null; max: number | null }; duration: { min: number | null; max: number | null };
};

export const SORTS: [string, string][] = [["name", "Name"], ["fee", "Fee: low to high"], ["fee_desc", "Fee: high to low"], ["duration", "Shortest first"], ["popularity", "Most enrolments"]];

export const PAGE_SIZE = 24;

export type ProgrammeParams = {
  q?: string; university?: string; specialization?: string; level?: string; mode?: string; fee_min?: string; fee_max?: string;
  duration?: string; intake?: string; accreditation?: string; emi?: string; eligible?: string; sort?: string; page?: string; lead?: string;
};

const num = (v: string | undefined) => (v && /^\d+(\.\d+)?$/.test(v) ? Number(v) : null);

/** The page's address as programme_search's argument. A fee bound at the catalogue's own edge is no filter (unpriced programmes stay). */
export function programmeQuery(sp: ProgrammeParams, fee?: { min: number | null; max: number | null }): Record<string, unknown> {
  const s = (v: string | undefined) => (v && v.trim() ? v.trim() : null);
  const lo = num(sp.fee_min);
  const hi = num(sp.fee_max);
  const lead = num(sp.lead);
  const page = Math.max(0, num(sp.page) ?? 0);
  return {
    q: s(sp.q), university: s(sp.university), specialization: s(sp.specialization), level: s(sp.level), mode: s(sp.mode),
    fee_min: lo !== null && (fee?.min == null || lo > fee.min) ? lo : null,
    fee_max: hi !== null && (fee?.max == null || hi < fee.max) ? hi : null,
    duration_max: num(sp.duration), intake: s(sp.intake), accreditation: s(sp.accreditation),
    emi: sp.emi === "1" ? true : null, eligible: lead && sp.eligible === "1" ? true : null,
    sort: SORTS.some(([k]) => k === sp.sort) ? sp.sort : "name", lead, limit: PAGE_SIZE, offset: page * PAGE_SIZE,
  };
}

/** "18 months", "2 years". */
export function duration(months: number | null | undefined): string | null {
  if (!months) return null;
  if (months % 12 === 0) return months === 12 ? "1 year" : `${months / 12} years`;
  return `${months} months`;
}

/** A partner's commission as stored (a number, a percent, or {type, value}). */
export function commissionText(c: unknown): string {
  if (c === null || c === undefined || c === "") return "—";
  if (typeof c === "number") return c <= 100 ? `${c}%` : `₹${Math.round(c).toLocaleString("en-IN")}`;
  if (typeof c === "string") return c;
  const o = c as { type?: string; rate_type?: string; value?: number; percent?: number; amount?: number };
  if (o.percent !== undefined) return `${o.percent}%`;
  if ((o.type ?? o.rate_type) === "percent" && o.value !== undefined) return `${o.value}%`;
  const v = o.amount ?? o.value;
  return v !== undefined ? `₹${Math.round(Number(v)).toLocaleString("en-IN")}` : "—";
}
