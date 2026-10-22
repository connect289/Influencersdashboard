/**
 * Finder URL state without runtime dependencies (safe for client bundles): constants, the state type, the canonical
 * query string, filter counting and the mapping to the web_search() input. Parsing/validation lives in ./params (zod,
 * server side).
 */

export const MODES = ["online", "odl", "regular"] as const;
export const DURATIONS = ["le12", "13-24", "25-36", "gt36"] as const;
export const NAAC = ["a-plus-plus", "a-plus", "a", "b-plus-plus", "b-plus", "b"] as const;
export const MIN_Q = ["12th", "diploma", "bachelor", "master"] as const;
export const QUALS = ["10th", "12th", "diploma", "graduation", "postgraduation"] as const;
export const SORTS = ["relevance", "fee_asc", "fee_desc", "naac", "duration", "popularity"] as const;
export const FORMATS = ["standard", "work-integrated", "apprenticeship", "work-linked"] as const;

export interface FinderParams {
  q?: string;
  level: string[];
  category: string[];
  programme: string[];
  spec: string[];
  uni: string[];
  mode: (typeof MODES)[number][];
  fee_min?: number;
  fee_max?: number;
  duration: string[];
  naac: string[];
  ugc: boolean;
  aicte: boolean;
  nirf: boolean;
  minq: string[];
  workex?: "required" | "not_required";
  entrance?: "yes" | "no";
  state: string[];
  format: string[];
  goal?: string;
  qual?: (typeof QUALS)[number];
  all: boolean;
  sort?: (typeof SORTS)[number];
  view?: "grouped" | "flat";
  page?: number;
}

const ORDER: (keyof FinderParams)[] = [
  "q", "level", "category", "programme", "spec", "uni", "mode", "fee_min", "fee_max", "duration", "naac", "ugc", "aicte",
  "nirf", "minq", "workex", "entrance", "state", "format", "goal", "qual", "all", "sort", "view", "page",
];

/** Canonical query string: stable key order, sorted lists, defaults removed. Same state → same string (cache key). */
export function toQueryString(p: Partial<FinderParams>): string {
  const out = new URLSearchParams();
  for (const k of ORDER) {
    const v = p[k];
    if (v === undefined || v === false || v === "" || (Array.isArray(v) && v.length === 0)) continue;
    if (k === "sort" && v === "relevance") continue;
    if (k === "view" && v === "grouped") continue;
    if (k === "page" && v === 1) continue;
    out.set(k, Array.isArray(v) ? [...v].sort().join(",") : v === true ? "1" : String(v));
  }
  return out.toString().replace(/%2C/g, ",");
}

/** Number of user-applied filters (for the "Filters (3)" button and "Clear all"). */
export function activeFilterCount(p: FinderParams): number {
  let n = 0;
  for (const k of ["level", "category", "programme", "spec", "uni", "mode", "duration", "naac", "minq", "state", "format"] as const) {
    n += p[k].length;
  }
  for (const k of ["ugc", "aicte", "nirf"] as const) if (p[k]) n++;
  for (const k of ["workex", "entrance", "goal"] as const) if (p[k]) n++;
  if (p.fee_min || p.fee_max) n++;
  return n;
}

const NAAC_SQL: Record<(typeof NAAC)[number], string> = {
  "a-plus-plus": "A++", "a-plus": "A+", a: "A", "b-plus-plus": "B++", "b-plus": "B+", b: "B",
};
export const naacFromSql = (g: string): string =>
  (Object.entries(NAAC_SQL).find(([, v]) => v === g)?.[0] as string | undefined) ?? g.toLowerCase();
const MODE_SQL: Record<(typeof MODES)[number], string> = { online: "Online", odl: "ODL", regular: "Regular" };
export const modeFromSql = (m: string): string => (m === "ODL" ? "odl" : m.toLowerCase());

/** Maps URL state to the web_search() input. */
export function toSearchInput(p: FinderParams, extra: { page_size?: number; group_key?: string; include_offerings?: boolean } = {}) {
  return {
    q: p.q,
    level: p.level, category: p.category, programme: p.programme, spec: p.spec, university: p.uni,
    mode: p.mode.map((m) => MODE_SQL[m as (typeof MODES)[number]]),
    fee_min: p.fee_min, fee_max: p.fee_max, duration: p.duration,
    naac: p.naac.map((n) => NAAC_SQL[n as (typeof NAAC)[number]]),
    ugc_deb: p.ugc || undefined, aicte: p.aicte || undefined, nirf: p.nirf || undefined,
    min_q: p.minq.map((m) => m.toUpperCase()),
    work_exp: p.workex, entrance: p.entrance, state: p.state, format: p.format, goal: p.goal, qual: p.qual,
    show_ineligible: p.all || undefined, sort: p.sort ?? "relevance", view: p.view ?? "grouped", page: p.page ?? 1,
    ...extra,
  };
}
