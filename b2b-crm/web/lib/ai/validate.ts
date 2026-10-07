/**
 * The validator (spec B7.8.2): every number in Claude's narrative must come from a tool result. Numbers are compared
 * as they are usually written: rounded to the narrative's decimals, as a percentage of a stored fraction, or with
 * thousands separators and ₹. The values Claude itself proposes in a change (e.g. "raise exploration to 25%") are
 * proposals, not claims about data, and are allowed.
 */

const NUM_RE = /(?<![\w.])[-−]?(?:₹\s?)?\d{1,3}(?:,\d{2,3})+(?:\.\d+)?%?|(?<![\w.])[-−]?(?:₹\s?)?\d+(?:\.\d+)?%?/g;

export type Claim = { text: string; value: number; decimals: number; percent: boolean };

/** Numbers written in a text, with how they were written. Dates like 2026-10-07 and version tags (v3, #12) are skipped. */
export function extractNumbers(text: string): Claim[] {
  const out: Claim[] = [];
  const cleaned = text
    .replace(/\b\d{4}-\d{2}-\d{2}(?:[T ][\d:.+Z-]*)?/g, " ")   // ISO dates
    .replace(/(?:#|\bv|\bL-)[\w-]+/gi, " ")                       // ids and versions
    .replace(/\b[a-z]+\|[^\s|]+\|[^\s|,.;]+/gi, " ");             // segment keys
  for (const m of cleaned.matchAll(NUM_RE)) {
    const raw = m[0];
    const percent = raw.endsWith("%");
    const digits = raw.replace(/[₹,%\s]/g, "").replace("−", "-");
    const value = Number(digits);
    if (!Number.isFinite(value)) continue;
    const decimals = digits.includes(".") ? digits.split(".")[1]!.length : 0;
    out.push({ text: raw, value, decimals, percent });
  }
  return out;
}

/** Every number in a JSON value (numeric leaves, and numbers written inside strings). */
export function collectNumbers(value: unknown, into: number[] = []): number[] {
  if (typeof value === "number" && Number.isFinite(value)) into.push(value);
  else if (typeof value === "string") {
    if (/^-?\d+(\.\d+)?$/.test(value.trim())) into.push(Number(value));
    else for (const c of extractNumbers(value)) into.push(c.value);
  } else if (Array.isArray(value)) for (const v of value) collectNumbers(v, into);
  else if (value && typeof value === "object") for (const v of Object.values(value)) collectNumbers(v, into);
  return into;
}

const round = (x: number, d: number) => Math.round(x * 10 ** d) / 10 ** d;

/** Whether a written number matches a tool number at the precision it was written (also as % of a fraction). */
export function matches(claim: Claim, source: number): boolean {
  const d = Math.min(claim.decimals, 6);
  const tol = 0.5 * 10 ** -d + 1e-9;
  const candidates = [source, source * 100, Math.abs(source), Math.abs(source) * 100];
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
