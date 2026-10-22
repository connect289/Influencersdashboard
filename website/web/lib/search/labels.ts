/**
 * Human labels for finder state: applied-filter chips, relaxation suggestions, page headings. Facet labels come from
 * the search response so they always match the catalogue's canonical names.
 */
import { formatInrCompact } from "@/lib/format";
import { MIN_QUALIFICATION_LABEL, QUALIFICATION_LABEL, type Qualification } from "@/lib/finder/eligibility";
import type { FinderParams } from "./state";
import type { Facets, FacetOption } from "./types";

export const DURATION_LABEL: Record<string, string> = {
  le12: "Up to 1 year",
  "13-24": "1–2 years",
  "25-36": "2–3 years",
  gt36: "More than 3 years",
};
export const NAAC_LABEL: Record<string, string> = {
  "a-plus-plus": "NAAC A++", "a-plus": "NAAC A+", a: "NAAC A", "b-plus-plus": "NAAC B++", "b-plus": "NAAC B+", b: "NAAC B",
};
export const MODE_LABEL: Record<string, string> = { online: "Online", odl: "Distance (ODL)", regular: "On-campus" };
/** Display name of a catalogue study mode ("Online" | "ODL" | "Regular"). */
export function modeDisplay(mode: string | null | undefined): string | null {
  if (!mode) return null;
  return mode === "ODL" ? "Distance (ODL)" : mode === "Regular" ? "On-campus" : mode;
}
export const FORMAT_LABEL: Record<string, string> = {
  standard: "Standard",
  "work-integrated": "Work-integrated learning",
  apprenticeship: "Apprenticeship-embedded",
  "work-linked": "Work-linked",
};
export const UGC_LABEL: Record<string, string> = {
  entitled: "UGC-entitled",
  approved: "UGC-DEB approved",
  recognised: "UGC-DEB recognised",
  stated: "UGC-DEB",
};
export const ATTRIBUTE_LABEL: Record<string, string> = {
  honours: "Honours",
  executive: "Executive",
  pay_after_placement: "Pay after placement",
  internship: "With internship",
  dual_specialisation: "Choose two specialisations",
  professional_certificate: "With professional certificate",
  advanced: "Advanced",
};

const pick = (opts: FacetOption[] | undefined, v: string) => opts?.find((o) => o.value === v)?.label ?? v;

export function feeLabel(min?: number, max?: number): string {
  if (min && max) return `${formatInrCompact(min)} – ${formatInrCompact(max)}`;
  if (max) return `Up to ${formatInrCompact(max)}`;
  if (min) return `From ${formatInrCompact(min)}`;
  return "Any fee";
}

export interface AppliedFilter {
  key: string;
  label: string;
  /** URL state without this filter. */
  without: Partial<FinderParams>;
}

/** Applied filters as removable chips, in a stable order. */
export function appliedFilters(p: FinderParams, f?: Facets): AppliedFilter[] {
  const out: AppliedFilter[] = [];
  const lists: [keyof FinderParams, (v: string) => string][] = [
    ["level", (v) => pick(f?.level, v)],
    ["category", (v) => pick(f?.category, v)],
    ["programme", (v) => pick(f?.programme, v)],
    ["spec", (v) => pick(f?.spec, v)],
    ["uni", (v) => pick(f?.university, v)],
    ["mode", (v) => MODE_LABEL[v] ?? v],
    ["duration", (v) => DURATION_LABEL[v] ?? v],
    ["naac", (v) => NAAC_LABEL[v] ?? v],
    ["minq", (v) => `Requires ${(MIN_QUALIFICATION_LABEL[v.toUpperCase()] ?? v).toLowerCase()}`],
    ["state", (v) => v],
    ["format", (v) => FORMAT_LABEL[v] ?? v],
  ];
  for (const [k, label] of lists) {
    const vals = p[k] as string[];
    for (const v of vals) out.push({ key: `${k}:${v}`, label: label(v), without: { [k]: vals.filter((x) => x !== v) } });
  }
  if (p.fee_min || p.fee_max) out.push({ key: "fee", label: feeLabel(p.fee_min, p.fee_max), without: { fee_min: undefined, fee_max: undefined } });
  if (p.ugc) out.push({ key: "ugc", label: "UGC-DEB stated", without: { ugc: false } });
  if (p.aicte) out.push({ key: "aicte", label: "AICTE", without: { aicte: false } });
  if (p.nirf) out.push({ key: "nirf", label: "NIRF ranked", without: { nirf: false } });
  if (p.workex) out.push({ key: "workex", label: p.workex === "required" ? "Work experience required" : "No work experience needed", without: { workex: undefined } });
  if (p.entrance) out.push({ key: "entrance", label: p.entrance === "yes" ? "Entrance exam" : "No entrance exam", without: { entrance: undefined } });
  if (p.goal) out.push({ key: "goal", label: pick(f?.goal, p.goal), without: { goal: undefined } });
  if (p.qual) out.push({ key: "qual", label: `I've completed ${QUALIFICATION_LABEL[p.qual as Qualification].toLowerCase()}`, without: { qual: undefined, all: false } });
  if (p.q) out.push({ key: "q", label: `“${p.q}”`, without: { q: undefined } });
  return out;
}

/** Label for a relaxation suggestion ("Remove NAAC A++ → 12 results"). */
export function relaxationLabel(filter: string, p: FinderParams, f?: Facets): { label: string; without: Partial<FinderParams> } | null {
  const map: Record<string, keyof FinderParams> = {
    level: "level", category: "category", programme: "programme", spec: "spec", university: "uni", mode: "mode",
    duration: "duration", naac: "naac", min_q: "minq", state: "state", format: "format",
  };
  const k = map[filter];
  if (k) {
    const chips = appliedFilters(p, f).filter((a) => a.key.startsWith(`${k}:`));
    if (!chips.length) return null;
    return { label: chips.map((c) => c.label).join(" or "), without: { [k]: [] } };
  }
  const single: Record<string, [string, Partial<FinderParams>]> = {
    fee: [feeLabel(p.fee_min, p.fee_max), { fee_min: undefined, fee_max: undefined }],
    ugc_deb: ["UGC-DEB stated", { ugc: false }],
    aicte: ["AICTE", { aicte: false }],
    nirf: ["NIRF ranked", { nirf: false }],
    work_exp: ["the work-experience filter", { workex: undefined }],
    entrance: ["the entrance-exam filter", { entrance: undefined }],
    goal: [pick(f?.goal, p.goal ?? ""), { goal: undefined }],
    elig: ["“hide not eligible”", { all: true }],
  };
  const s = single[filter];
  return s ? { label: s[0], without: s[1] } : null;
}

/** Page heading for the current state, e.g. "Online MBA · Marketing", "Postgraduate programmes", "All programmes". */
export function finderHeading(p: FinderParams, f?: Facets): string {
  const mode = p.mode.length === 1 ? `${MODE_LABEL[p.mode[0]!]} ` : "";
  if (p.programme.length === 1) {
    const prog = pick(f?.programme, p.programme[0]!);
    const spec = p.spec.length === 1 ? ` in ${pick(f?.spec, p.spec[0]!)}` : "";
    const uni = p.uni.length === 1 ? ` at ${pick(f?.university, p.uni[0]!)}` : "";
    return `${mode}${prog}${spec}${uni}`.trim();
  }
  if (p.spec.length === 1) return `${mode}programmes in ${pick(f?.spec, p.spec[0]!)}`.replace(/^./, (c) => c.toUpperCase());
  if (p.uni.length === 1) return `Programmes at ${pick(f?.university, p.uni[0]!)}`;
  if (p.level.length === 1) return `${mode}${pick(f?.level, p.level[0]!)} programmes`.trim();
  if (p.category.length === 1) return `${mode}${pick(f?.category, p.category[0]!)} programmes`.trim();
  return mode ? `${mode}programmes` : "Find your programme";
}
