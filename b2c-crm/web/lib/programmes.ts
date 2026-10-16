/**
 * The Programme page (B8.9): the row b2c.programme_search returns, how the page's address becomes its query, and the
 * grouping and labels the cards show. Pure, unit-tested in programmes.test.ts.
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
  /** Since b44; derived from the rows on an older database. */
  courses?: string[];
  fee: { min: number | null; max: number | null }; duration: { min: number | null; max: number | null };
};

export const SORTS: [string, string][] = [["name", "Name"], ["fee", "Fee: low to high"], ["fee_desc", "Fee: high to low"], ["duration", "Shortest first"], ["popularity", "Most enrolments"]];

/** The page reads the whole catalogue that matches (grouped by university), in calls of FETCH rows, at most MAX_FETCHES of them. */
export const FETCH = 300;
export const MAX_FETCHES = 4;
/** Programmes shown per university before "Show all". */
export const GROUP_PREVIEW = 6;

export type ProgrammeParams = {
  q?: string; university?: string; course?: string; specialization?: string; level?: string; mode?: string; fee_min?: string; fee_max?: string;
  duration?: string; intake?: string; accreditation?: string; emi?: string; eligible?: string; sort?: string; lead?: string;
};

const num = (v: string | undefined) => (v && /^\d+(\.\d+)?$/.test(v) ? Number(v) : null);

/** The page's address as programme_search's argument. A fee bound at the catalogue's own edge is no filter (unpriced programmes stay). */
export function programmeQuery(sp: ProgrammeParams, fee?: { min: number | null; max: number | null }, offset = 0, limit = FETCH): Record<string, unknown> {
  const s = (v: string | undefined) => (v && v.trim() ? v.trim() : null);
  const lo = num(sp.fee_min);
  const hi = num(sp.fee_max);
  const lead = num(sp.lead);
  return {
    q: s(sp.q), university: s(sp.university), course: s(sp.course), specialization: s(sp.specialization), level: s(sp.level), mode: s(sp.mode),
    fee_min: lo !== null && (fee?.min == null || lo > fee.min) ? lo : null,
    fee_max: hi !== null && (fee?.max == null || hi < fee.max) ? hi : null,
    duration_max: num(sp.duration), intake: s(sp.intake), accreditation: s(sp.accreditation),
    emi: sp.emi === "1" ? true : null, eligible: lead && sp.eligible === "1" ? true : null,
    sort: SORTS.some(([k]) => k === sp.sort) ? sp.sort : "name", lead, limit, offset,
  };
}

/** Which filters narrow the catalogue (the count line says "match" when any does). */
export function isFiltered(sp: ProgrammeParams): boolean {
  return (["q", "university", "course", "specialization", "level", "mode", "fee_min", "fee_max", "duration", "intake", "accreditation", "emi", "eligible"] as const)
    .some((k) => sp[k] && sp[k]!.trim() !== "");
}

/** "18 months", "2 years". */
export function duration(months: number | null | undefined): string | null {
  if (!months) return null;
  if (months % 12 === 0) return months === 12 ? "1 year" : `${months / 12} years`;
  return `${months} months`;
}

const LEVELS: Record<string, string> = { UG: "Undergraduate", PG: "Postgraduate", DIPLOMA: "Diploma", CERTIFICATE: "Certificate", PHD: "Doctorate" };

/** The catalogue's level codes as words. */
export function levelLabel(level: string | null | undefined): string | null {
  if (!level) return null;
  const k = level.trim().toUpperCase().replace(/[^A-Z]/g, "");
  if (LEVELS[k]) return LEVELS[k];
  return level.length <= 3 ? level.toUpperCase() : level.charAt(0).toUpperCase() + level.slice(1).toLowerCase();
}

const ACCRED: [RegExp, string][] = [
  [/UGC[\s-]*DEB\s*(approved|recogni[sz]ed|entitled)/i, "UGC-DEB approved"],
  [/NAAC\s*A\+\+/i, "NAAC A++"], [/NAAC\s*A\+/i, "NAAC A+"], [/NAAC\s*(grade\s*)?A\b/i, "NAAC A"],
  [/UGC\s*(entitled|recogni[sz]ed|approved)/i, "UGC recognised"], [/AICTE\s*approved/i, "AICTE approved"], [/NIRF/i, "NIRF ranked"],
];

/** One short approval to show on a card, from the university's accreditation text or its recognitions list. */
export function accreditationLabel(text: string | null | undefined, recognitions?: unknown): string | null {
  const hay = [text ?? "", Array.isArray(recognitions) ? recognitions.filter((x) => typeof x === "string").join(" ") : ""].join(" ");
  for (const [re, label] of ACCRED) if (re.test(hay)) return label;
  if (Array.isArray(recognitions)) {
    const first = recognitions.find((x) => typeof x === "string" && x.trim());
    if (typeof first === "string") return first.trim().slice(0, 40);
  }
  return null;
}

/** The fee a card leads with: the full fee for the whole programme (the catalogue's total; else the yearly fee times the
 * duration; else the yearly fee alone, saying so), and under it the per-semester instalment when the university bills that way. */
export function headlineFee(p: Pick<Programme, "fee_total" | "fee_yearly" | "fee_semester" | "duration_months">): { label: string; value: number | null; semester: number | null } {
  const semester = p.fee_semester ?? null;
  if (p.fee_total) return { label: "Full fee", value: p.fee_total, semester };
  if (p.fee_yearly && p.duration_months) return { label: "Full fee", value: Math.round(p.fee_yearly * p.duration_months / 12), semester };
  if (p.fee_yearly) return { label: "Fee per year", value: p.fee_yearly, semester };
  if (semester) return { label: "Fee per semester", value: semester, semester: null };
  return { label: "Fee", value: null, semester: null };
}

export type UniversityGroup = { university: string; university_id: number | null; university_short: string | null; rows: Programme[] };

/** The rows by university, universities A to Z, each university's rows in the order they came (the chosen sort). */
export function groupByUniversity(rows: Programme[]): UniversityGroup[] {
  const map = new Map<string, UniversityGroup>();
  for (const r of rows) {
    const g = map.get(r.university) ?? { university: r.university, university_id: r.university_id, university_short: r.university_short, rows: [] };
    g.rows.push(r);
    map.set(r.university, g);
  }
  return [...map.values()].sort((a, b) => a.university.localeCompare(b.university));
}

const BASE: Record<string, string> = { first_year: "of the first-year fee", total: "of the total fee", amount_paid: "of the amount paid" };

/** What a university's header says about Eduwit's commission (Admin and Marketing): one rate, several, or none set. */
export function universityCommission(rows: Programme[]): { kind: "rate"; text: string } | { kind: "varies" } | { kind: "none" } {
  const seen = new Set<string>();
  for (const r of rows) {
    const c = r.eduwit_commission;
    if (!c) continue;
    seen.add(c.rate_type === "percent" ? `${c.value}% ${BASE[c.fee_base] ?? ""}`.trim() : c.rate_type === "fixed" ? `₹${Math.round(c.value).toLocaleString("en-IN")} fixed` : "tiered");
  }
  if (seen.size === 0) return { kind: "none" };
  if (seen.size === 1) return { kind: "rate", text: [...seen][0]! };
  return { kind: "varies" };
}

/** The offsets still to read after the first call, given the total it reported. */
export function moreOffsets(total: number): number[] {
  const out: number[] = [];
  for (let o = FETCH; o < total && out.length < MAX_FETCHES - 1; o += FETCH) out.push(o);
  return out;
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
