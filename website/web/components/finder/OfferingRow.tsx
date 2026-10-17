"use client";

import { ViewTransition } from "react";
import { GitCompareArrows, Heart } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { formatInr } from "@/lib/format";
import type { SeedOffering } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";

/** One university's offering inside an expanded programme group (spec 6.2). Opens the detail panel. */
export function OfferingRow({
  o,
  onOpen,
  shortlisted,
  onShortlist,
  compared,
  onCompare,
}: {
  o: SeedOffering;
  onOpen: () => void;
  shortlisted?: boolean;
  onShortlist?: () => void;
  compared?: boolean;
  onCompare?: () => void;
}) {
  return (
    <ViewTransition name={`offering-${o.id}`}>
      <li className="group hover:border-border hover:bg-surface-hover grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-2 rounded-[var(--radius-lg)] border border-transparent px-3 py-3 transition-colors sm:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)_auto]">
        <button type="button" onClick={onOpen} className="min-w-0 text-left">
          <span className="text-text block truncate font-semibold">{o.university}</span>
          <span className="text-muted mt-1 flex flex-wrap items-center gap-1.5 text-xs">
            <span>{o.mode}</span>
            {o.durationYears ? <span>· {o.durationYears} years</span> : null}
            {o.naac ? <Badge tone="verified">NAAC {o.naac}</Badge> : null}
            {o.ugcDeb ? <Badge tone="info">UGC-DEB</Badge> : null}
          </span>
        </button>
        <div className="col-span-2 row-start-2 sm:col-span-1 sm:row-start-auto">
          <span className="tabular font-display text-text block text-lg font-semibold">{formatInr(o.feeTotal)}</span>
          <span className="text-muted block text-xs">
            total
            {o.feeSemester
              ? ` · ${formatInr(o.feeSemester)}/sem`
              : o.feeYearly
                ? ` · ${formatInr(o.feeYearly)}/yr`
                : ""}
            {o.emi ? <span className="text-amber-text"> · Easy EMI available</span> : null}
          </span>
        </div>
        <div className="flex gap-1">
          <button
            type="button"
            aria-pressed={shortlisted}
            onClick={onShortlist}
            aria-label={shortlisted ? `Remove ${o.university} from shortlist` : `Shortlist ${o.university}`}
            className={cn(
              "border-border hover:bg-surface-hover grid size-10 place-items-center rounded-full border transition-colors",
              shortlisted ? "text-primary" : "text-muted",
            )}
          >
            <Heart className="size-[18px]" fill={shortlisted ? "currentColor" : "none"} aria-hidden />
          </button>
          <button
            type="button"
            aria-pressed={compared}
            onClick={onCompare}
            aria-label={compared ? `Remove ${o.university} from compare` : `Compare ${o.university}`}
            className={cn(
              "border-border hover:bg-surface-hover grid size-10 place-items-center rounded-full border transition-colors",
              compared ? "border-primary text-primary" : "text-muted",
            )}
          >
            <GitCompareArrows className="size-[18px]" aria-hidden />
          </button>
        </div>
      </li>
    </ViewTransition>
  );
}
