// Compliance checks on scripts and captions (spec 10.2, 16). Pure: the banned-claims scan, the disclosure check and
// the ASCI checklist. A blocking match or a missing disclosure blocks approval unless a reviewer overrides it with a
// reason (inf.compliance_override).
import type { Platform } from "@/lib/creators/schemas";

export interface BannedClaim {
  id: string;
  pattern: string;
  kind: "phrase" | "regex";
  /** block: approval is blocked until fixed or overridden; warn: shown to the reviewer only. */
  severity: "block" | "warn";
  note: string | null;
}

export interface ClaimMatch {
  claim_id: string;
  severity: "block" | "warn";
  text: string;
  index: number;
  note: string | null;
}

/** Longest text scanned (a caption or script); longer input is scanned up to this length. */
export const MAX_SCAN_CHARS = 20_000;

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Whether a staff-entered pattern is safe to run: bounded length, no backreferences or lookbehind, and no nested
 * quantifiers (the usual catastrophic-backtracking shapes such as `(a+)+` or `(.*)*`).
 */
export function safePattern(pattern: string): boolean {
  if (pattern.length === 0 || pattern.length > 200) return false;
  if (/\\[1-9]|\(\?<[=!]|\\k</.test(pattern)) return false;
  if (/\((?:[^()\\]|\\.)*[+*}](?:[^()\\]|\\.)*\)\s*[+*{]/.test(pattern)) return false;
  try {
    new RegExp(pattern, "iu");
    return true;
  } catch {
    return false;
  }
}

function compile(c: BannedClaim): RegExp | null {
  if (c.kind === "regex") return safePattern(c.pattern) ? new RegExp(c.pattern, "giu") : null;
  const words = c.pattern.trim().split(/\s+/).filter(Boolean).map(escape);
  if (words.length === 0) return null;
  // Whole words, any spacing between them; letters and digits on either side don't count as a boundary.
  return new RegExp(`(?<![\\p{L}\\p{N}])${words.join("\\s+")}(?![\\p{L}\\p{N}])`, "giu");
}

/** Every banned-claim match in a text, in order. */
export function scanClaims(text: string, claims: readonly BannedClaim[]): ClaimMatch[] {
  const input = text.slice(0, MAX_SCAN_CHARS);
  const out: ClaimMatch[] = [];
  for (const c of claims) {
    const re = compile(c);
    if (!re) continue;
    for (const m of input.matchAll(re)) {
      if (m[0] === "") continue;
      out.push({ claim_id: c.id, severity: c.severity, text: m[0], index: m.index, note: c.note });
    }
  }
  return out.sort((a, b) => a.index - b.index);
}

export interface DisclosureSettings {
  disclosure_terms: readonly string[];
  disclosure_required_platforms: readonly Platform[];
}

export interface DisclosureResult {
  required: boolean;
  present: boolean;
  found: string | null;
}

/** Whether one disclosure term appears: hashtags as whole tags (#ad, not #adidas), phrases as whole words. */
function hasTerm(text: string, term: string): boolean {
  const t = term.trim();
  if (!t) return false;
  const body = t.split(/\s+/).map(escape).join("\\s+");
  const before = t.startsWith("#") ? "(?<![\\p{L}\\p{N}_#])" : "(?<![\\p{L}\\p{N}])";
  return new RegExp(`${before}${body}(?![\\p{L}\\p{N}_])`, "iu").test(text);
}

/** The disclosure rule (spec 10.2): one of the configured terms must be present on platforms that require it. */
export function checkDisclosure(text: string, platform: Platform, s: DisclosureSettings): DisclosureResult {
  const required = s.disclosure_required_platforms.includes(platform);
  const input = text.slice(0, MAX_SCAN_CHARS);
  const found = s.disclosure_terms.find((term) => hasTerm(input, term)) ?? null;
  return { required, present: found !== null, found };
}

export interface ScanResult {
  claims: ClaimMatch[];
  disclosure: DisclosureResult | null;
  /** True when nothing blocks approval (no blocking claim; disclosure present where required and checked). */
  passed: boolean;
}

/**
 * The automatic scan of a submission. Scripts and concepts are scanned for claims only; drafts and finals (what will
 * be posted) are also checked for the disclosure.
 */
export function scanSubmission(
  text: string,
  kind: "concept" | "draft" | "final",
  platform: Platform,
  claims: readonly BannedClaim[],
  s: DisclosureSettings,
): ScanResult {
  const found = scanClaims(text, claims);
  const disclosure = kind === "concept" ? null : checkDisclosure(text, platform, s);
  const blocked =
    found.some((m) => m.severity === "block") || (disclosure !== null && disclosure.required && !disclosure.present);
  return { claims: found, disclosure, passed: !blocked };
}

/** The ASCI influencer disclosure checklist (spec 16), ticked by the reviewer before approval. */
export const ASCI_CHECKLIST = [
  "disclosure_upfront",
  "disclosure_clear",
  "disclosure_language",
  "disclosure_in_video",
  "approved_claims_only",
  "genuine_experience",
  "no_misleading_results",
] as const;
export type AsciItem = (typeof ASCI_CHECKLIST)[number];

/** Every checklist item ticked. */
export function checklistComplete(answers: Readonly<Partial<Record<AsciItem, boolean>>>): boolean {
  return ASCI_CHECKLIST.every((k) => answers[k] === true);
}
