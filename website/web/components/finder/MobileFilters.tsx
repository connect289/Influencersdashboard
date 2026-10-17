"use client";

import { useEffect, useState } from "react";
import { BottomSheet } from "@/components/ui/BottomSheet";
import { formatCount } from "@/lib/format";
import { toQueryString, type FinderParams } from "@/lib/search/state";
import type { Facets, SearchResult } from "@/lib/search/types";
import { FacetPanel } from "./FacetPanel";

/**
 * Mobile filters (spec 6.3): a bottom sheet where choices are staged, counts update live for the staged state, and a
 * sticky "Show N results" applies them in one navigation.
 */
export default function MobileFilters({ open, onOpenChange, params, facets, total, onApply }: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  params: FinderParams;
  facets: Facets;
  total: number;
  onApply: (p: FinderParams) => void;
}) {
  // Mounted fresh each time the sheet opens, so the staged state starts from the current URL state.
  const [staged, setStaged] = useState(params);
  const stagedQs = toQueryString({ ...staged, page: undefined });
  const [live, setLive] = useState<{ qs: string; facets: Facets; total: number }>({ qs: stagedQs, facets, total });
  const loading = live.qs !== stagedQs;

  useEffect(() => {
    if (!open || live.qs === stagedQs) return;
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      try {
        const res = await fetch(`/api/search?${stagedQs}${stagedQs ? "&" : ""}page_size=1`, { signal: ctrl.signal });
        const j = (await res.json()) as SearchResult;
        setLive({ qs: stagedQs, facets: j.facets, total: j.total });
      } catch {
        // keep the last counts
      }
    }, 150);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [stagedQs, open, live.qs]);

  return (
    <BottomSheet
      open={open}
      onOpenChange={onOpenChange}
      title="Filters"
      footer={
        <div className="flex gap-2">
          <button type="button" className="border-border text-text h-12 rounded-full border px-5 text-sm font-medium" onClick={() => setStaged({ ...params, level: [], category: [], programme: [], spec: [], uni: [], mode: [], duration: [], naac: [], minq: [], state: [], format: [], fee_min: undefined, fee_max: undefined, ugc: false, aicte: false, nirf: false, workex: undefined, entrance: undefined, goal: undefined })}>
            Clear
          </button>
          <button
            type="button"
            className="bg-primary text-on-primary h-12 flex-1 rounded-full text-sm font-semibold disabled:opacity-60"
            disabled={loading}
            onClick={() => {
              onApply(staged);
              onOpenChange(false);
            }}
          >
            <span aria-live="polite">{loading ? "Counting…" : `Show ${formatCount(live.total)} results`}</span>
          </button>
        </div>
      }
    >
      <FacetPanel facets={live.facets} params={staged} total={live.total} onChange={(next) => setStaged((s) => ({ ...s, ...next }))} />
    </BottomSheet>
  );
}
