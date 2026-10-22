/**
 * Compare table rows (spec 6.5): fees, duration, approvals, NAAC, NIRF, eligibility, intakes, EMI, exam requirement,
 * highlights. Rows with no data for any offering are dropped (no "N/A" walls); identical rows can be hidden.
 */
import { formatDuration, formatInr } from "@/lib/format";
import type { OfferingDetails } from "@/lib/search/types";
import { MIN_QUALIFICATION_LABEL } from "./eligibility";
import { ATTRIBUTE_LABEL, FORMAT_LABEL, UGC_LABEL, modeDisplay } from "@/lib/search/labels";

export interface CompareRow {
  key: string;
  label: string;
  section: "Fees" | "Programme" | "University" | "Eligibility";
  values: (string | null)[];
  /** Numeric values for "best" highlighting (lower fee is better, higher NAAC is better). */
  best?: "min" | "max";
  numbers?: (number | null)[];
  identical: boolean;
}

const NAAC_ORDER = ["C", "B", "B+", "B++", "A", "A+", "A++"];

function row(key: string, label: string, section: CompareRow["section"], items: OfferingDetails[], get: (o: OfferingDetails) => string | null | undefined,
  num?: (o: OfferingDetails) => number | null | undefined, best?: "min" | "max"): CompareRow | null {
  const values = items.map((o) => get(o) ?? null);
  if (values.every((v) => v === null)) return null;
  const nonNull = values.filter((v) => v !== null);
  return {
    key, label, section, values, best,
    numbers: num ? items.map((o) => num(o) ?? null) : undefined,
    identical: nonNull.length === values.length && new Set(values).size === 1,
  };
}

export function compareRows(items: OfferingDetails[]): CompareRow[] {
  const rows = [
    row("fee_total", "Total fee", "Fees", items, (o) => (o.fee.total ? formatInr(o.fee.total) : o.fee.on_request ? "Fee on request" : null), (o) => o.fee.total, "min"),
    row("fee_yearly", "Per year", "Fees", items, (o) => (o.fee.yearly ? formatInr(o.fee.yearly) : null), (o) => o.fee.yearly, "min"),
    row("fee_semester", "Per semester", "Fees", items, (o) => (o.fee.semester ? formatInr(o.fee.semester) : null), (o) => o.fee.semester, "min"),
    row("fee_registration", "Registration fee", "Fees", items, (o) => (o.fee_registration ? formatInr(o.fee_registration) : null)),
    row("fee_exam", "Exam fee", "Fees", items, (o) => (o.fee_exam ? formatInr(o.fee_exam) : null)),
    row("emi", "EMI", "Fees", items, () => "Easy EMI available"),
    row("duration", "Duration", "Programme", items, (o) => (o.duration_months ? formatDuration(o.duration_months) : null), (o) => o.duration_months),
    row("mode", "Mode", "Programme", items, (o) => modeDisplay(o.mode)),
    row("format", "Format", "Programme", items, (o) => (o.format ? (FORMAT_LABEL[o.format] ?? o.format) : null)),
    row("highlights", "Highlights", "Programme", items, (o) => {
      const a = Object.entries(o.attributes ?? {}).map(([k, v]) => (k === "medium" ? `${v} medium` : (ATTRIBUTE_LABEL[k] ?? null))).filter(Boolean);
      return a.length ? a.join(", ") : null;
    }),
    row("entrance", "Entrance exam", "Eligibility", items, (o) => (o.entrance_exam === true ? "Required" : o.entrance_exam === false ? "Not required" : null)),
    row("min_q", "Minimum qualification", "Eligibility", items, (o) => (o.min_qualification ? (MIN_QUALIFICATION_LABEL[o.min_qualification] ?? o.min_qualification) : null)),
    row("min_pct", "Minimum marks", "Eligibility", items, (o) => (o.min_pct_general ? `${o.min_pct_general}%${o.min_pct_reserved ? ` (${o.min_pct_reserved}% reserved)` : ""}` : null), (o) => o.min_pct_general, "min"),
    row("work_exp", "Work experience", "Eligibility", items, (o) => (o.work_exp_years ? `${o.work_exp_years}+ years` : null)),
    row("ugc", "UGC-DEB", "University", items, (o) => (o.ugc_deb ? UGC_LABEL[o.ugc_deb] : null)),
    row("aicte", "AICTE", "University", items, (o) => (o.aicte ? "Yes" : null)),
    row("naac", "NAAC", "University", items, (o) => (o.naac_grade ? `NAAC ${o.naac_grade}` : o.naac_accredited ? "NAAC accredited" : null),
      (o) => (o.naac_grade ? NAAC_ORDER.indexOf(o.naac_grade) : null), "max"),
    row("nirf", "NIRF", "University", items, (o) => {
      const n = o.university_facts?.nirf;
      if (!n) return null;
      return `${n.rank ? `#${n.rank}` : n.band}${n.category ? ` (${n.category})` : ""}${n.year ? ` · ${n.year}` : ""}`;
    }, (o) => o.university_facts?.nirf?.rank, "min"),
  ];
  return rows.filter((r): r is CompareRow => r !== null);
}

/** Index of the best value in a row (ties: none highlighted). */
export function bestIndex(r: CompareRow): number | null {
  if (!r.best || !r.numbers) return null;
  const nums = r.numbers.map((n, i) => ({ n, i })).filter((x): x is { n: number; i: number } => x.n !== null);
  if (nums.length < 2) return null;
  const target = r.best === "min" ? Math.min(...nums.map((x) => x.n)) : Math.max(...nums.map((x) => x.n));
  const winners = nums.filter((x) => x.n === target);
  return winners.length === 1 ? winners[0]!.i : null;
}
