/**
 * Content planner "Refresh due" (spec 13.4): published guides past their refresh date, older than N months, or losing
 * rankings (Search Console clicks down 30% or more on the previous period, from at least 5). Pure; returns the reason.
 */
export const REFRESH_MONTHS = 9;

export interface GuideRow {
  slug: string;
  status: string;
  published_at: string | null;
  refresh_due_at: string | null;
}
export interface PageTrend {
  page: string;
  clicks: number;
  prev: number;
}

export function refreshReasons(rows: GuideRow[], falling: PageTrend[], now: number, months = REFRESH_MONTHS): Map<string, string> {
  const losing = new Map(falling.filter((f) => f.prev >= 5 && f.clicks <= f.prev * 0.7).map((f) => [f.page, f]));
  const out = new Map<string, string>();
  for (const r of rows) {
    if (r.status !== "published") continue;
    const drop = losing.get(`/resources/${r.slug}`);
    if (r.refresh_due_at && Date.parse(r.refresh_due_at) < now) out.set(r.slug, "past its refresh date");
    else if (drop) out.set(r.slug, `losing clicks (${drop.prev} → ${drop.clicks})`);
    else if (r.published_at && now - Date.parse(r.published_at) > months * 30 * 86400000) out.set(r.slug, `older than ${months} months`);
  }
  return out;
}
