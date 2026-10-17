"use client";

import { useState } from "react";
import { ChevronDown, Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { formatCount, formatDuration, formatInrRange } from "@/lib/format";
import { toQueryString, type FinderParams } from "@/lib/search/state";
import type { OfferingCard, ProgrammeGroup, SearchResult } from "@/lib/search/types";
import { cn } from "@/lib/utils";
import { OfferingResult } from "./OfferingResult";
import { UniversityMark } from "./UniversityMark";

function durationRange(min?: number, max?: number) {
  if (!min || !max) return null;
  return min === max ? formatDuration(min) : `${formatDuration(min)} – ${formatDuration(max)}`;
}

/**
 * Programme + specialisation group card (spec 6.2): name and level, number of universities, fee and duration ranges,
 * best NAAC, "Easy EMI available", top three universities; expands to one row per university, loaded on demand with
 * the current filters applied.
 */
export function ResultGroup({ g, params, onOpen }: { g: ProgrammeGroup; params: FinderParams; onOpen: (o: OfferingCard) => void }) {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<OfferingCard[] | null>(g.items ?? null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const domId = `group-${g.key.replace(/[^a-z0-9]/gi, "-")}`;

  async function expand() {
    const next = !open;
    setOpen(next);
    if (!next || items) return;
    setLoading(true);
    setFailed(false);
    try {
      const qs = toQueryString({ ...params, page: undefined, view: undefined });
      const res = await fetch(`/api/search?${qs}${qs ? "&" : ""}group=${encodeURIComponent(g.key)}&page_size=1`);
      const j = (await res.json()) as SearchResult;
      const first = (j.items as ProgrammeGroup[])[0];
      setItems(first?.items ?? []);
    } catch {
      setFailed(true);
    } finally {
      setLoading(false);
    }
  }

  const dur = durationRange(g.duration_min, g.duration_max);
  return (
    <article className="glass overflow-hidden rounded-[var(--radius-xl)]" aria-labelledby={`${domId}-title`}>
      <button type="button" aria-expanded={open} aria-controls={`${domId}-list`} onClick={expand} className="grid w-full grid-cols-[1fr_auto] gap-4 p-5 text-left">
        <div className="min-w-0">
          <p className="eyebrow">{g.level_label}</p>
          <h3 id={`${domId}-title`} className="font-display text-text mt-1 text-xl leading-tight font-semibold sm:text-2xl">
            {g.programme_name}
            <span className="text-muted"> · {g.spec_name}</span>
          </h3>
          <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1.5 text-sm">
            {g.fee_min && g.fee_max ? (
              <>
                <span className="tabular text-text font-semibold">{formatInrRange(g.fee_min, g.fee_max)}</span>
                <span className="text-subtle">total fee</span>
                <Badge tone="amber">Easy EMI available</Badge>
              </>
            ) : (
              <span className="text-muted">Fee on request</span>
            )}
            {dur ? <span className="text-muted">· {dur}</span> : null}
            {g.best_naac ? <Badge tone="verified">Up to NAAC {g.best_naac}</Badge> : null}
          </div>
          <div className="text-muted mt-3 flex flex-wrap items-center gap-2 text-sm">
            <span className="flex -space-x-2">
              {(g.top_universities ?? []).map((u) => (
                <UniversityMark key={u.slug} name={u.name} short={u.short} logo={u.logo} />
              ))}
            </span>
            <span>
              {formatCount(g.universities)} {g.universities === 1 ? "university" : "universities"}
              {g.offerings > g.universities ? ` · ${formatCount(g.offerings)} options` : ""}
            </span>
            {g.eligibility ? (
              <span className="text-subtle">
                · {g.eligibility.eligible} eligible{g.eligibility.check ? `, ${g.eligibility.check} to check` : ""}
              </span>
            ) : null}
          </div>
        </div>
        <span className={cn("border-border text-muted mt-1 grid size-10 place-items-center rounded-full border transition-transform duration-300", open && "rotate-180")}>
          <ChevronDown className="size-5" aria-hidden />
          <span className="sr-only">{open ? "Hide universities" : "Show universities"}</span>
        </span>
      </button>
      <div id={`${domId}-list`} hidden={!open} className="border-border border-t px-2 py-2">
        {loading ? (
          <p className="text-muted flex items-center gap-2 px-3 py-4 text-sm" role="status">
            <Loader2 className="size-4 animate-spin" aria-hidden /> Loading universities…
          </p>
        ) : failed ? (
          <p className="text-danger px-3 py-4 text-sm" role="alert">
            Couldn&apos;t load the universities. Check your connection and try again.
          </p>
        ) : (
          <ul className="grid gap-1">
            {(items ?? []).map((o) => (
              <OfferingResult key={o.id} o={o} onOpen={onOpen} />
            ))}
          </ul>
        )}
      </div>
    </article>
  );
}
