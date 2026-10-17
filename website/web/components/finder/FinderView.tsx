"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { Compass, SlidersHorizontal } from "lucide-react";
import { Chip } from "@/components/ui/Chip";
import { Odometer } from "@/components/ui/Odometer";
import { setOfferingParam, useFinderNavigation } from "@/lib/client/use-finder";
import { formatCount } from "@/lib/format";
import { appliedFilters, finderHeading } from "@/lib/search/labels";
import { activeFilterCount, SORTS, type FinderParams } from "@/lib/search/state";
import type { OfferingCard, ProgrammeGroup, SearchResult } from "@/lib/search/types";
import { cn } from "@/lib/utils";
import { AskWitty } from "./AskWitty";
import { CompareTray } from "./CompareTray";
import { FacetPanel } from "./FacetPanel";
import { OfferingResult } from "./OfferingResult";
import { ResultGroup } from "./ResultGroup";
import { SearchBox } from "./SearchBox";
import { ZeroResults } from "./ZeroResults";

const MobileFilters = dynamic(() => import("./MobileFilters"), { ssr: false });
const GuidedFinder = dynamic(() => import("./GuidedFinder").then((m) => m.GuidedFinder), { ssr: false });
const OfferingPanel = dynamic(() => import("./OfferingPanel").then((m) => m.OfferingPanel), { ssr: false });

/** Loads the panel code only when an offering is open (deep link or click). */
function OfferingPanelHost(props: { qual?: string; advisorEnabled: boolean; whatsapp: string }) {
  const sp = useSearchParams();
  const [used, setUsed] = useState(false);
  if (!used && sp.get("offering")) setUsed(true);
  return used ? <OfferingPanel {...props} /> : null;
}

const SORT_LABEL: Record<(typeof SORTS)[number], string> = {
  relevance: "Relevance",
  fee_asc: "Fee: low to high",
  fee_desc: "Fee: high to low",
  naac: "NAAC grade",
  duration: "Duration: shortest",
  popularity: "Popularity",
};

/**
 * The programme finder (spec 6): search, guided finder, facets, grouped results, URL state, sort, zero results,
 * compare and shortlist. Results are rendered by the server from the URL; this component only changes the URL.
 */
export function FinderView({
  params,
  result,
  advisorEnabled,
  whatsapp,
  basePath = "/programmes",
  intro,
}: {
  params: FinderParams;
  result: SearchResult;
  advisorEnabled: boolean;
  whatsapp: string;
  basePath?: string;
  intro?: React.ReactNode;
}) {
  const { go, href, pending, optimistic } = useFinderNavigation(params, basePath);
  const [sheet, setSheet] = useState(false);
  const [guided, setGuided] = useState(false);
  const chips = appliedFilters(params, result.facets);
  const nFilters = activeFilterCount(params);
  const open = (o: OfferingCard) => setOfferingParam(o.id, "push");
  const grouped = result.view !== "flat";
  const shown = grouped ? (result.items as ProgrammeGroup[]).length : (result.items as OfferingCard[]).length;
  const totalUnits = grouped ? result.total_groups : result.total;
  const page = params.page ?? 1;
  const corrected = result.resolved.corrected.filter((c) => c.from !== c.to);

  return (
    <div className="grid gap-6">
      <header className="grid gap-4">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="eyebrow">Programme finder</p>
            <h1 className="font-display text-text mt-1 text-3xl leading-tight font-semibold sm:text-4xl">
              {finderHeading(params, result.facets)}
            </h1>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setGuided((v) => !v)}
              aria-expanded={guided}
              className="border-border bg-surface text-text hover:bg-surface-hover inline-flex h-11 items-center gap-2 rounded-full border px-4 text-sm font-medium"
            >
              <Compass className="text-amber-text size-4" aria-hidden />
              <span className="sm:hidden">Guide me</span>
              <span className="hidden sm:inline">Not sure? Answer 3 questions</span>
            </button>
            <AskWitty enabled={advisorEnabled} whatsapp={whatsapp} question={params.q}>
              {advisorEnabled ? undefined : (
                <>
                  <span className="sm:hidden">Ask a counsellor</span>
                  <span className="hidden sm:inline">Ask a counsellor on WhatsApp</span>
                </>
              )}
            </AskWitty>
          </div>
        </div>
        {intro}
        <SearchBox key={params.q ?? ""} initialQuery={params.q ?? ""} basePath={basePath} />
        {guided ? (
          <GuidedFinder
            params={optimistic}
            facets={result.facets}
            total={result.total}
            onChange={(n) => go(n)}
            onClose={() => setGuided(false)}
          />
        ) : null}
        {nFilters === 0 && !params.q ? (
          <nav aria-label="Browse by category" className="flex flex-wrap gap-2">
            {result.facets.category.map((c) => (
              <Link
                key={c.value}
                href={href({ category: [c.value] })}
                scroll={false}
                className="border-border bg-surface text-muted hover:text-text hover:border-border-strong rounded-full border px-3.5 py-1.5 text-sm"
              >
                {c.label} <span className="tabular text-subtle text-xs">{formatCount(c.count)}</span>
              </Link>
            ))}
          </nav>
        ) : null}
      </header>

      <div className="grid gap-8 lg:grid-cols-[17.5rem_minmax(0,1fr)]">
        <aside className="hidden lg:block" aria-label="Filters">
          <div className="sticky top-24 max-h-[calc(100dvh-7rem)] overflow-y-auto overscroll-contain pr-2">
            {/* Separate Suspense boundaries let React hydrate the rail, toolbar and results in separate tasks. */}
            <Suspense>
              <FacetPanel facets={result.facets} params={optimistic} total={result.total} onChange={(n) => go(n)} />
            </Suspense>
          </div>
        </aside>

        <section className="grid min-w-0 content-start gap-4" aria-labelledby="results-heading">
          <h2 id="results-heading" className="sr-only">
            Results
          </h2>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p
              className="text-muted text-sm"
              aria-live="polite"
              aria-atomic="true"
              data-testid="result-count"
              data-total={result.total}
            >
              <Odometer value={result.total} className="text-text font-semibold" /> offerings
              {grouped ? (
                <>
                  {" "}
                  in <Odometer value={result.total_groups} className="text-text font-semibold" /> programmes
                </>
              ) : null}
            </p>
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                className="border-border bg-surface text-text inline-flex h-10 items-center gap-2 rounded-full border px-4 text-sm lg:hidden"
                onClick={() => setSheet(true)}
              >
                <SlidersHorizontal className="size-4" aria-hidden /> Filters{nFilters ? ` (${nFilters})` : ""}
              </button>
              <label className="text-muted flex items-center gap-2 text-sm">
                <span className="sr-only sm:not-sr-only">Sort</span>
                <select
                  value={optimistic.sort ?? "relevance"}
                  onChange={(e) => go({ sort: e.target.value as FinderParams["sort"] })}
                  className="border-border bg-surface text-text h-10 rounded-full border px-3 text-sm"
                >
                  {SORTS.map((s) => (
                    <option key={s} value={s}>
                      {SORT_LABEL[s]}
                    </option>
                  ))}
                </select>
              </label>
              <div
                className="border-border bg-surface inline-flex rounded-full border p-1"
                role="group"
                aria-label="Results view"
              >
                {(["grouped", "flat"] as const).map((v) => {
                  const on = (optimistic.view === "flat" ? "flat" : "grouped") === v;
                  return (
                    <button
                      key={v}
                      type="button"
                      aria-pressed={on}
                      onClick={() => go({ view: v === "flat" ? "flat" : undefined })}
                      className={cn(
                        "h-8 rounded-full px-3.5 text-sm transition-colors",
                        on ? "bg-primary text-on-primary" : "text-muted hover:text-text",
                      )}
                    >
                      {v === "grouped" ? "By programme" : "All offerings"}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>

          {chips.length ? (
            <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Applied filters">
              {chips.map((c) => (
                <Chip key={c.key} onRemove={() => go(c.without)}>
                  {c.label}
                </Chip>
              ))}
              {chips.length > 1 ? (
                <Link href={basePath} scroll={false} className="text-accent text-sm font-medium hover:underline">
                  Clear all
                </Link>
              ) : null}
            </div>
          ) : null}

          {corrected.length ? (
            <p className="text-muted text-sm">
              Showing results for <span className="text-text font-medium">{corrected.map((c) => c.to).join(", ")}</span>{" "}
              (you typed {corrected.map((c) => `“${c.from}”`).join(", ")}).
            </p>
          ) : null}
          {result.resolved.ignored_words.length && result.total > 0 ? (
            <p className="text-subtle text-sm">We didn&apos;t recognise: {result.resolved.ignored_words.join(", ")}.</p>
          ) : null}

          <div
            className={cn("grid gap-4 transition-opacity duration-200", pending && "pointer-events-none opacity-55")}
            aria-busy={pending}
          >
            <Suspense>
              {result.total === 0 ? (
                <ZeroResults
                  result={result}
                  params={params}
                  onRelax={(n) => go(n)}
                  onOpen={open}
                  advisorEnabled={advisorEnabled}
                  whatsapp={whatsapp}
                />
              ) : grouped ? (
                (result.items as ProgrammeGroup[]).map((g) => (
                  <ResultGroup key={g.key} g={g} params={params} onOpen={open} />
                ))
              ) : (
                <ul className="glass grid gap-1 rounded-[var(--radius-xl)] p-2">
                  {(result.items as OfferingCard[]).map((o) => (
                    <OfferingResult key={o.id} o={o} onOpen={open} showProgramme />
                  ))}
                </ul>
              )}
            </Suspense>
          </div>

          {shown < totalUnits ? (
            <div className="grid justify-items-center gap-2 pt-2">
              <p className="text-subtle text-sm">
                Showing {formatCount(shown)} of {formatCount(totalUnits)} {grouped ? "programmes" : "offerings"}
              </p>
              <Link
                href={href({ page: page + 1 }, true)}
                scroll={false}
                replace
                className="border-border bg-surface text-text hover:bg-surface-hover inline-flex h-11 items-center rounded-full border px-6 text-sm font-semibold"
              >
                Show more
              </Link>
            </div>
          ) : null}
        </section>
      </div>

      <CompareTray />
      <OfferingPanelHost qual={params.qual} advisorEnabled={advisorEnabled} whatsapp={whatsapp} />
      {sheet ? (
        <MobileFilters
          open={sheet}
          onOpenChange={setSheet}
          params={params}
          facets={result.facets}
          total={result.total}
          onApply={(p) => go(p)}
        />
      ) : null}
    </div>
  );
}
