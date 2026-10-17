import { parseFinderParams, toQueryString, type FinderParams } from "./params";

/**
 * Indexing rules for finder URLs (spec 13.1): the only indexable finder pages are the finder home and the curated finder
 * views created in the admin (`/programmes/<slug>`). Every filtered `/programmes?…` URL is `noindex, follow` and
 * canonicalises to the curated view with the same core filters, else to the curated view for its programme, else to
 * the finder home — so arbitrary facet combinations never bloat the index (D-062).
 */
export interface CuratedRef {
  slug: string;
  filters: Record<string, unknown>;
}

const CORE = ["programme", "spec", "level", "category", "uni", "mode"] as const;

function core(p: Partial<FinderParams>): string {
  const pick: Partial<FinderParams> = {};
  for (const k of CORE) if ((p[k] as string[] | undefined)?.length) (pick as Record<string, unknown>)[k] = [...(p[k] as string[])].sort();
  return toQueryString(pick);
}

function curatedParams(filters: Record<string, unknown>): FinderParams {
  const raw: Record<string, string> = {};
  for (const [k, v] of Object.entries(filters)) raw[k] = Array.isArray(v) ? v.join(",") : String(v);
  return parseFinderParams(raw);
}

export function finderIndexability(p: FinderParams, curated: CuratedRef[] = []): { index: boolean; canonical: string } {
  const all = toQueryString(p);
  if (!all) return { index: true, canonical: "/programmes" };
  const key = core(p);
  const views = curated.map((c) => ({ slug: c.slug, params: curatedParams(c.filters) }));
  const exact = key ? views.find((v) => core(v.params) === key) : undefined;
  const byProgramme =
    p.programme.length === 1 ? views.find((v) => v.params.programme.length === 1 && v.params.programme[0] === p.programme[0] && core(v.params) === core({ programme: p.programme })) : undefined;
  const target = exact ?? byProgramme;
  return { index: false, canonical: target ? `/programmes/${target.slug}` : "/programmes" };
}
