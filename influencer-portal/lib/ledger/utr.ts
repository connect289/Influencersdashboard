// Marking payouts paid from the bank's confirmation file (spec 11): a CSV with the payout reference, the UTR and the
// date paid. Every row is checked; nothing is applied when any row is wrong. Pure.
import { CsvError, parseCsv } from "@/lib/csv";

/** UTR: NEFT (16 characters), RTGS (22) or IMPS (12 digits) references are letters and digits. */
export const UTR_RE = /^[A-Z0-9]{12,22}$/;
export const PAYOUT_REF_RE = /^PO-\d{4}-\d{2}-\d{5}$/;

export interface UtrRow {
  payout_ref: string;
  utr: string;
  paid_on: string;
}

export interface UtrError {
  /** 1-based line number in the file (the header is line 1). */
  line: number;
  code: "missing_column" | "bad_ref" | "bad_utr" | "bad_date" | "future_date" | "duplicate" | "file";
}

/** YYYY-MM-DD or DD/MM/YYYY (or DD-MM-YYYY) → YYYY-MM-DD; null when not a real date. */
export function parseBankDate(raw: string): string | null {
  const s = raw.trim();
  let y: number, m: number, d: number;
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  const ind = /^(\d{2})[/-](\d{2})[/-](\d{4})$/.exec(s);
  if (iso) [y, m, d] = [Number(iso[1]), Number(iso[2]), Number(iso[3])];
  else if (ind) [d, m, y] = [Number(ind[1]), Number(ind[2]), Number(ind[3])];
  else return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return dt.toISOString().slice(0, 10);
}

const norm = (h: string) =>
  h
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, "");
const COLUMNS: Record<keyof UtrRow, readonly string[]> = {
  payout_ref: ["payoutref", "reference", "ref", "payoutreference"],
  utr: ["utr", "utrnumber", "bankreference"],
  paid_on: ["paidon", "date", "paiddate", "valuedate"],
};

export function parseUtrFile(text: string, today: string): { rows: UtrRow[]; errors: UtrError[] } {
  let parsed;
  try {
    parsed = parseCsv(text, { maxRows: 5000 });
  } catch (e) {
    if (e instanceof CsvError) return { rows: [], errors: [{ line: 1, code: "file" }] };
    throw e;
  }
  const idx = Object.fromEntries(
    (Object.keys(COLUMNS) as (keyof UtrRow)[]).map((k) => [
      k,
      parsed.headers.findIndex((h) => COLUMNS[k].includes(norm(h))),
    ]),
  ) as Record<keyof UtrRow, number>;
  if (Object.values(idx).some((i) => i < 0)) return { rows: [], errors: [{ line: 1, code: "missing_column" }] };
  const rows: UtrRow[] = [];
  const errors: UtrError[] = [];
  const seen = new Set<string>();
  parsed.rows.forEach((r, i) => {
    const line = i + 2;
    const ref = (r[idx.payout_ref] ?? "").trim().toUpperCase();
    const utr = (r[idx.utr] ?? "").trim().toUpperCase();
    const date = parseBankDate(r[idx.paid_on] ?? "");
    if (!PAYOUT_REF_RE.test(ref)) return errors.push({ line, code: "bad_ref" });
    if (!UTR_RE.test(utr)) return errors.push({ line, code: "bad_utr" });
    if (!date) return errors.push({ line, code: "bad_date" });
    if (date > today) return errors.push({ line, code: "future_date" });
    if (seen.has(ref)) return errors.push({ line, code: "duplicate" });
    seen.add(ref);
    rows.push({ payout_ref: ref, utr, paid_on: date });
  });
  return { rows: errors.length ? [] : rows, errors };
}
