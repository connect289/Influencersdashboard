import { toQueryString, type FinderParams } from "./params";

/**
 * Indexing rules for finder URLs (spec 13): only deliberate, high-demand combinations are indexable — one programme
 * (optionally with one specialisation), or one level, category or university, with no other filters. Everything else
 * is `noindex, follow` and canonicalises to its nearest indexable view.
 */
export function finderIndexability(p: FinderParams): { index: boolean; canonicalQuery: string } {
  const others =
    p.q || p.mode.length || p.duration.length || p.naac.length || p.minq.length || p.state.length || p.format.length ||
    p.fee_min || p.fee_max || p.ugc || p.aicte || p.nirf || p.workex || p.entrance || p.goal || p.qual || p.all ||
    (p.sort && p.sort !== "relevance") || p.view === "flat" || (p.page && p.page > 1);
  const single = (a: string[]) => a.length === 1;
  const dims = [p.programme.length > 0, p.spec.length > 0, p.level.length > 0, p.category.length > 0, p.uni.length > 0].filter(Boolean).length;
  const programmeView = single(p.programme) && p.spec.length <= 1 && !p.level.length && !p.category.length && !p.uni.length;
  const simpleView = dims === 1 && (single(p.level) || single(p.category) || single(p.uni));
  const index = !others && (dims === 0 || programmeView || simpleView);
  const base = { programme: p.programme.slice(0, 1), spec: single(p.programme) ? p.spec.slice(0, 1) : [] } as Partial<FinderParams>;
  const canonicalQuery = index ? toQueryString(p) : toQueryString(p.programme.length ? base : {});
  return { index, canonicalQuery };
}
