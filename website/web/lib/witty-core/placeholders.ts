import type { CatalogRow, PlaceholderField } from "./contract";
import { inr } from "./normalise";

/**
 * {{Pn.field}} placeholders: the counselor never types a fee, cutoff, programme or university; code fills them from the
 * catalogue rows chosen by the engine (counselor prompt rule 1). Same field list as Witty.
 */
export type RefRow = { ref: string; row: CatalogRow };

export function bestFee(r: CatalogRow): string | null {
  if (r.fee_yearly) return `${inr(r.fee_yearly)} per year`;
  if (r.fee_semester) return `${inr(r.fee_semester)} per semester`;
  if (r.fee_total) return `${inr(r.fee_total)} total`;
  return null;
}

export function fieldValue(r: CatalogRow, f: PlaceholderField): string | null {
  switch (f) {
    case "program":
      return r.program_name ?? (r.course ? `${r.course}${r.specialization ? ` (${r.specialization})` : ""}` : null);
    case "university":
      return r.university ?? null;
    case "mode":
      return r.mode ?? null;
    case "specialization":
      return r.specialization ?? null;
    case "fee":
      return bestFee(r);
    case "fee_yearly":
      return r.fee_yearly ? `${inr(r.fee_yearly)} per year` : null;
    case "fee_semester":
      return r.fee_semester ? `${inr(r.fee_semester)} per semester` : null;
    case "fee_total":
      return r.fee_total ? `${inr(r.fee_total)} total` : null;
    case "fee_exam":
      return r.fee_exam ? inr(r.fee_exam) : null;
    case "fee_registration":
      return r.fee_registration ? inr(r.fee_registration) : null;
    case "min_pct":
      return r.min_pct_general ? `${r.min_pct_general}%` : null;
    case "brochure":
      return r.brochure_url ?? null;
  }
}

const FIELDS: PlaceholderField[] = ["program", "university", "mode", "specialization", "fee", "fee_yearly", "fee_semester", "fee_total", "fee_exam", "fee_registration", "min_pct", "brochure"];

/** The "has" list the counselor sees for a row: fields with a value. */
export function hasFields(r: CatalogRow): PlaceholderField[] {
  return FIELDS.filter((f) => fieldValue(r, f) !== null);
}

export const PLACEHOLDER = /\{\{\s*(P\d+)\.(\w+)\s*\}\}/g;

/** Placeholders that do not resolve (unknown ref or a field the row does not have). */
export function unresolved(text: string, rows: RefRow[]): string[] {
  const bad: string[] = [];
  for (const m of text.matchAll(PLACEHOLDER)) {
    const row = rows.find((x) => x.ref === m[1])?.row;
    if (!row || !(FIELDS as string[]).includes(m[2]!) || fieldValue(row, m[2] as PlaceholderField) === null) bad.push(m[0]);
  }
  return bad;
}

export function fillPlaceholders(text: string, rows: RefRow[]): string {
  return text.replace(PLACEHOLDER, (all, ref: string, f: string) => {
    const row = rows.find((x) => x.ref === ref)?.row;
    if (!row || !(FIELDS as string[]).includes(f)) return "";
    return fieldValue(row, f as PlaceholderField) ?? "";
  });
}
