import type { Metadata } from "next";
import { Suspense } from "react";
import { FinderView } from "@/components/finder/FinderView";
import { Skeleton } from "@/components/ui/DataViz";
import { finderHeading } from "@/lib/search/labels";
import { parseFinderParams } from "@/lib/search/params";
import { mergeParsed, parseQuery } from "@/lib/search/parse";
import { finderIndexability } from "@/lib/search/seo";
import { getSettings } from "@/lib/server/settings";
import { curatedViews, searchOfferings } from "@/lib/server/search";

/** Programme groups per "page"; small enough that a mid-range phone hydrates the first screen quickly. */
const PAGE_SIZE = 12;

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

// The title, description and robots rules depend on the search state, so a navigation into the finder waits for its
// metadata; the static shell and skeleton still prerender (Next docs: generateMetadata with Cache Components).
export const instant = false;

async function load(searchParams: Props["searchParams"]) {
  const sp = await searchParams;
  const raw = parseFinderParams(sp);
  const params = raw.q ? mergeParsed(raw, parseQuery(raw.q)) : raw;
  // "Show more" keeps earlier pages on screen: page N renders the first N pages in one request (back/forward restore).
  const page = params.page ?? 1;
  const result = await searchOfferings({ ...params, page: undefined }, { page_size: Math.min(96, PAGE_SIZE * page) });
  return { raw, params, result, guided: sp.guided === "1" };
}

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const [{ params, result }, sp, views] = await Promise.all([load(searchParams), searchParams, curatedViews()]);
  const heading = finderHeading(params, result.facets);
  const { index: filtersIndexable, canonical } = finderIndexability(params, views);
  // Offering / programme-group panel deep links are not standalone pages (spec 13.1): noindex, canonical to the view.
  const index = filtersIndexable && !sp.offering && !sp.group;
  const title = heading === "Find your programme" ? "Find online and distance programmes" : `${heading} — compare ${result.total_groups > 1 ? "programmes" : "universities"}`;
  return {
    title,
    description:
      result.total > 0
        ? `Compare ${result.total} ${heading === "Find your programme" ? "online and distance" : heading} options from ${result.facets.university.filter((u) => u.count > 0).length} universities: full fees, duration, approvals and eligibility.`
        : "Search online and distance programmes by full fee, duration, approvals and eligibility.",
    alternates: { canonical },
    robots: index ? undefined : { index: false, follow: true },
  };
}

async function Finder({ searchParams }: Props) {
  const [{ params, result, guided }, settings] = await Promise.all([load(searchParams), getSettings()]);
  return <FinderView params={params} result={result} initialGuided={guided} advisorEnabled={settings.web_advisor_enabled} whatsapp={settings.counsellor_whatsapp} />;
}

function FinderSkeleton() {
  return (
    <div className="grid gap-6" aria-busy="true" aria-label="Loading programmes">
      <div className="grid gap-3">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-10 w-72 max-w-full" />
        <Skeleton className="h-14 w-full rounded-full" />
      </div>
      <div className="grid gap-8 lg:grid-cols-[17.5rem_minmax(0,1fr)]">
        <div className="hidden gap-3 lg:grid">
          {Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="h-24" />)}
        </div>
        <div className="grid content-start gap-4">
          {Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-40 rounded-[var(--radius-xl)]" />)}
        </div>
      </div>
    </div>
  );
}

/** /programmes — the programme finder (spec 6). Static shell; results stream in from the URL state. */
export default function ProgrammesPage({ searchParams }: Props) {
  return (
    <main id="main" className="container-site pt-8 pb-28 lg:pb-16">
      <Suspense fallback={<FinderSkeleton />}>
        <Finder searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
