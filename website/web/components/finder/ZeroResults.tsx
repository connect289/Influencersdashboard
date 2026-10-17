"use client";

import { SearchX } from "lucide-react";
import { relaxationLabel } from "@/lib/search/labels";
import type { FinderParams } from "@/lib/search/state";
import type { OfferingCard, SearchResult } from "@/lib/search/types";
import { formatCount } from "@/lib/format";
import { AskWitty } from "./AskWitty";
import { OfferingResult } from "./OfferingResult";

/**
 * Zero results never dead-end (spec 6.4): which filter to relax (with the count it gives), the closest matches, and
 * "Ask Witty" with the query pre-filled.
 */
export function ZeroResults({ result, params, onRelax, onOpen, advisorEnabled, whatsapp }: {
  result: SearchResult;
  params: FinderParams;
  onRelax: (next: Partial<FinderParams>) => void;
  onOpen: (o: OfferingCard) => void;
  advisorEnabled: boolean;
  whatsapp: string;
}) {
  const relax = result.relaxations
    .map((r) => ({ ...r, l: relaxationLabel(r.filter, params, result.facets) }))
    .filter((r) => r.l)
    .slice(0, 4);
  const question = [params.q, ...params.programme, ...params.spec].filter(Boolean).join(" ") || undefined;
  return (
    <section className="glass grid gap-6 rounded-[var(--radius-xl)] p-6" aria-labelledby="zero-title">
      <div className="flex items-start gap-4">
        <span className="bg-surface text-muted grid size-11 shrink-0 place-items-center rounded-full">
          <SearchX className="size-5" aria-hidden />
        </span>
        <div>
          <h2 id="zero-title" className="font-display text-text text-xl font-semibold">
            {params.q && result.without_query ? `No programmes match “${params.q}”` : "No programmes match all of these filters"}
          </h2>
          <p className="text-muted mt-1">
            {relax.length ? "Try removing one filter:" : result.without_query ? `There are ${formatCount(result.without_query)} programmes without this search.` : "Try a broader search."}
          </p>
        </div>
      </div>
      {relax.length ? (
        <div className="flex flex-wrap gap-2">
          {relax.map((r) => (
            <button key={r.filter} type="button" onClick={() => onRelax(r.l!.without)} className="border-border bg-surface text-text hover:bg-surface-hover rounded-full border px-4 py-2 text-sm">
              Remove {r.l!.label} <span className="text-subtle">· {formatCount(r.count)} results</span>
            </button>
          ))}
        </div>
      ) : params.q ? (
        <button type="button" onClick={() => onRelax({ q: undefined })} className="border-border bg-surface text-text hover:bg-surface-hover justify-self-start rounded-full border px-4 py-2 text-sm">
          Clear the search text
        </button>
      ) : null}
      {result.closest?.length ? (
        <div>
          <h3 className="eyebrow mb-2">Closest matches</h3>
          <ul className="grid gap-1">
            {result.closest.map((o) => (
              <OfferingResult key={o.id} o={o} onOpen={onOpen} showProgramme />
            ))}
          </ul>
        </div>
      ) : null}
      <div className="border-border flex flex-wrap items-center gap-3 border-t pt-5">
        <p className="text-muted text-sm">Not sure what to look for?</p>
        <AskWitty enabled={advisorEnabled} question={question} whatsapp={whatsapp} />
      </div>
    </section>
  );
}
