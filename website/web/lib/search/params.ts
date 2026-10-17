import { z } from "zod";
import { DURATIONS, FORMATS, MIN_Q, MODES, NAAC, QUALS, SORTS, type FinderParams } from "./state";

export * from "./state";

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

type Raw = Record<string, string | string[] | undefined> | URLSearchParams;

/** Parses URL search params (Next `searchParams` object or URLSearchParams). Unknown or invalid values are dropped. */
export function parseFinderParams(raw: Raw): FinderParams {
  const flat: Record<string, string> = {};
  const entries = raw instanceof URLSearchParams ? [...raw.entries()] : Object.entries(raw);
  for (const [k, v] of entries) {
    if (v === undefined) continue;
    flat[k] = Array.isArray(v) ? v.join(",") : v;
  }
  return finderSchema.parse(flat) as FinderParams; // list() narrows to the allowed values at runtime
}

