/**
 * Related-content links for curated views and university pages (spec 9 internal linking: curated views, university
 * pages and resources link to relevant finder views; spec 13.4 "keeps related-content blocks fresh"). Pure: built from
 * the curated views and catalogue facets on every render, so the block follows new views and universities.
 */
export interface RelatedLink {
  href: string;
  label: string;
}
interface ViewRef {
  slug: string;
  title: string;
  filters: Record<string, unknown>;
}

const programmesOf = (v: ViewRef) => (Array.isArray(v.filters.programme) ? (v.filters.programme as string[]) : []);

/** Curated views for any of the given programmes (a university page links to the views for what it offers). */
export function viewsForProgrammes(views: ViewRef[], programmes: string[], limit = 6): RelatedLink[] {
  const want = new Set(programmes);
  return views
    .filter((v) => programmesOf(v).some((p) => want.has(p)))
    .slice(0, limit)
    .map((v) => ({ href: `/programmes/${v.slug}`, label: v.title }));
}

/** Other curated views, those sharing a programme first. */
export function siblingViews(views: ViewRef[], current: ViewRef, limit = 6): RelatedLink[] {
  const mine = new Set(programmesOf(current));
  const shares = (v: ViewRef) => (programmesOf(v).some((p) => mine.has(p)) ? 0 : 1);
  return views
    .filter((v) => v.slug !== current.slug)
    .map((v, i) => ({ v, i }))
    .sort((a, b) => shares(a.v) - shares(b.v) || a.i - b.i)
    .slice(0, limit)
    .map(({ v }) => ({ href: `/programmes/${v.slug}`, label: v.title }));
}

/** University pages for the universities in a result, most options first. */
export function universityLinks(facet: { value: string; label: string; count: number }[], limit = 8): RelatedLink[] {
  return facet
    .filter((u) => u.count > 0)
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
    .slice(0, limit)
    .map((u) => ({ href: `/universities/${u.value}`, label: u.label }));
}
