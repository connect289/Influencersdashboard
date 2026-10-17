import { z } from "zod";

/**
 * Finder state lives in the URL (spec 6.4). These are the URL keys, their parsing, a canonical (normalised) form used as
 * the cache key and for canonical links, and the mapping to the web_search() input.
 */

const SLUG = /^[a-z0-9][a-z0-9_-]{0,60}$/;
const list = (allowed?: readonly string[]) =>
  z
    .string()
    .optional()
    .transform((v) =>
      [...new Set((v ?? "").split(",").map((x) => x.trim().toLowerCase()))]
        .filter((x) => x && SLUG.test(x) && (!allowed || allowed.includes(x)))
        .sort(),
    );
const flag = z
  .string()
  .optional()
  .transform((v) => v === "1" || v === "true");
const money = z
  .string()
  .optional()
  .transform((v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 && n < 1e8 ? Math.round(n) : undefined;
  });

export const MODES = ["online", "odl"] as const;
export const DURATIONS = ["le12", "13-24", "25-36", "gt36"] as const;
export const NAAC = ["a-plus-plus", "a-plus", "a", "b-plus-plus", "b-plus", "b"] as const;
export const MIN_Q = ["12th", "diploma", "bachelor", "master"] as const;
export const QUALS = ["10th", "12th", "diploma", "graduation", "postgraduation"] as const;
export const SORTS = ["relevance", "fee_asc", "fee_desc", "naac", "duration", "popularity"] as const;
export const FORMATS = ["standard", "work-integrated", "apprenticeship", "work-linked"] as const;

export const finderSchema = z.object({
  q: z
    .string()
    .optional()
    .transform((v) => (v ?? "").replace(/\s+/g, " ").trim().slice(0, 120).toLowerCase() || undefined),
  level: list(),
  category: list(),
  programme: list(),
  spec: list(),
  uni: list(),
  mode: list(MODES),
  fee_min: money,
  fee_max: money,
  duration: list(DURATIONS),
  naac: list(NAAC),
  ugc: flag,
  aicte: flag,
  nirf: flag,
  minq: list(MIN_Q),
  workex: z.enum(["required", "not_required"]).optional().catch(undefined),
  entrance: z.enum(["yes", "no"]).optional().catch(undefined),
  state: list(),
  format: list(FORMATS),
  goal: z
    .string()
    .optional()
    .transform((v) => (v && SLUG.test(v) ? v : undefined)),
  qual: z.enum(QUALS).optional().catch(undefined),
  all: flag,
  sort: z.enum(SORTS).optional().catch(undefined),
  view: z.enum(["grouped", "flat"]).optional().catch(undefined),
  page: z
    .string()
    .optional()
    .transform((v) => {
      const n = Number(v);
      return Number.isInteger(n) && n > 1 && n <= 500 ? n : undefined;
    }),
});

export type FinderParams = z.output<typeof finderSchema>;
type Raw = Record<string, string | string[] | undefined> | URLSearchParams;

/** Parses URL search params (Next `searchParams` object or URLSearchParams). Unknown or invalid values are dropped. */
export function parseFinderParams(raw: Raw): FinderParams {
  const flat: Record<string, string> = {};
  const entries = raw instanceof URLSearchParams ? [...raw.entries()] : Object.entries(raw);
  for (const [k, v] of entries) {
    if (v === undefined) continue;
    flat[k] = Array.isArray(v) ? v.join(",") : v;
  }
  return finderSchema.parse(flat);
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
const MODE_SQL: Record<(typeof MODES)[number], string> = { online: "Online", odl: "ODL" };
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
