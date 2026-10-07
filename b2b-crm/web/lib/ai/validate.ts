/**
 * The validator (spec B7.8.2): every number in Claude's narrative must come from a tool result. Numbers are compared
 * as they are usually written: rounded to the narrative's decimals, as a percentage of a stored fraction, or with
 * thousands separators and ₹. The values Claude itself proposes in a change (e.g. "raise exploration to 25%") are
 * proposals, not claims about data, and are allowed.
 */

const NUM_RE = /(?<![\w.])[-−]?(?:₹\s?)?\d{1,3}(?:,\d{2,3})+(?:\.\d+)?%?|(?<![\w.])[-−]?(?:₹\s?)?\d+(?:\.\d+)?%?/g;

export type Claim = { text: string; value: number; decimals: number; percent: boolean; scale?: number };

// whole month names only (\b), so "decisions", "declined", "marketing", "separate" are not months; "may" only after a day number or before a year
const MON = "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\b\\.?";
const MONY = `(?:${MON}|may\\b)`;
const ORD = "(?:st|nd|rd|th)?";
const YEAR = "(?:,?\\s+\\d{4})?";
/** Dates written in words ("21 October", "1 to 7 October 2026", "Oct 1–7, 2026", "September 2026"): not data claims. */
const DATE_RE = new RegExp(
  `\\b\\d{1,2}${ORD}\\s*(?:-|–|to)\\s*\\d{1,2}${ORD}\\s+${MONY}${YEAR}` +                                   // 1 to 7 October (2026)
  `|\\b\\d{1,2}${ORD}\\s+${MONY}${YEAR}` +                                                                    // 21 October (2026)
  `|\\b(?:${MON})\\s+\\d{1,2}${ORD}(?:\\s*(?:-|–|to)\\s*\\d{1,2}${ORD})?(?:,?\\s+\\d{4})?(?!\\d)` +       // Oct 1–7, 2026
  `|\\b(?:${MON}|may)\\s+\\d{4}\\b`, "gi");                                                                // September 2026

/**
 * Numbers written in a text, with how they were written. Dates (2026-10-07, 21 October, Oct 1–7), version tags (v3, #12)
 * and the 95% of a confidence interval are skipped; a number followed by lakh/L or crore/cr carries its scale.
 */
export function extractNumbers(text: string): Claim[] {
  const out: Claim[] = [];
  const cleaned = text
    .replace(/\b\d{4}-\d{2}-\d{2}(?:[T ][\d:.+Z-]*)?/g, " ")   // ISO dates
    .replace(/(?:#|\bv|\bL-)[\w-]+/gi, " ")                       // ids and versions
    .replace(/\b[a-z]+\|[^\s|]+\|[^\s|,.;]+/gi, " ")             // segment keys
    .replace(DATE_RE, " ")                                         // dates in words
    .replace(/\b95%(?=\s*(?:confidence|interval|CI\b|:))/gi, " ");  // the 95% of a confidence interval
  for (const m of cleaned.matchAll(NUM_RE)) {
    const raw = m[0];
    const percent = raw.endsWith("%");
    const digits = raw.replace(/[₹,%\s]/g, "").replace("−", "-");
    const value = Number(digits);
    if (!Number.isFinite(value)) continue;
    const decimals = digits.includes(".") ? digits.split(".")[1]!.length : 0;
    // "₹4.5 lakh" is 450,000 and "₹1.2 crore" is 12,000,000 (Indian units)
    const tail = cleaned.slice((m.index ?? 0) + raw.length);
    const scale = /^\s*(?:lakh|lac|L)\b/i.test(tail) ? 1e5 : /^\s*(?:crore|cr)\b/i.test(tail) ? 1e7 : 1;
    out.push({ text: raw, value, decimals, percent, scale });
  }
  return out;
}

/** Every number in a JSON value (numeric leaves, and numbers written inside strings). */
export function collectNumbers(value: unknown, into: number[] = []): number[] {
  if (typeof value === "number" && Number.isFinite(value)) into.push(value);
  else if (typeof value === "string") {
    if (/^-?\d+(\.\d+)?$/.test(value.trim())) into.push(Number(value));
    else for (const c of extractNumbers(value)) into.push(c.value * (c.scale ?? 1));
  } else if (Array.isArray(value)) for (const v of value) collectNumbers(v, into);
  else if (value && typeof value === "object") for (const v of Object.values(value)) collectNumbers(v, into);
  return into;
}

const round = (x: number, d: number) => Math.round(x * 10 ** d) / 10 ** d;

/** Whether a written number matches a tool number at the precision it was written (also as % of a fraction). */
export function matches(claim: Claim, source: number): boolean {
  const d = Math.min(claim.decimals, 6);
  const tol = 0.5 * 10 ** -d + 1e-9;
  const candidates = [source, source * 100, Math.abs(source), Math.abs(source) * 100].map((x) => x / (claim.scale ?? 1));
  return candidates.some((s) => Math.abs(round(s, d) - claim.value) <= tol || Math.abs(s - claim.value) <= tol);
}

export type Validation = { ok: boolean; checked: number; unverified: string[] };

/**
 * Checks a narrative against tool outputs. allowed: values Claude proposes (the changes) and fixed facts it was told
 * in the prompt (bounds), which are not data claims.
 */
export function validateNumbers(narrative: string, toolOutputs: unknown[], allowed: unknown[] = []): Validation {
  const sources = collectNumbers(toolOutputs);
  const extra = collectNumbers(allowed);
  const claims = extractNumbers(narrative);
  const unverified: string[] = [];
  for (const c of claims) {
    const ok = sources.some((s) => matches(c, s)) || extra.some((s) => matches(c, s));
    if (!ok) unverified.push(c.text);
  }
  return { ok: unverified.length === 0, checked: claims.length, unverified: [...new Set(unverified)].slice(0, 30) };
}
