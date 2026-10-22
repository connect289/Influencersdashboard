"use client";

import { GitCompareArrows, Heart } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Badge";
import { track } from "@/lib/client/analytics";
import { saved, useSaved } from "@/lib/client/saved-store";
import { ELIGIBILITY_LABEL } from "@/lib/finder/eligibility";
import { formatDuration, formatInr } from "@/lib/format";
import { ATTRIBUTE_LABEL, FORMAT_LABEL, UGC_LABEL, modeDisplay } from "@/lib/search/labels";
import type { OfferingCard } from "@/lib/search/types";
import { cn } from "@/lib/utils";
import { UniversityMark } from "./UniversityMark";

export function ShortlistCompareButtons({ o }: { o: OfferingCard }) {
  const shortlist = useSaved("shortlist");
  const compare = useSaved("compare");
  const sl = shortlist.includes(o.id);
  const cmp = compare.includes(o.id);
  const name = `${o.programme_name} ${o.spec_name} at ${o.university.name}`;
  return (
    <div className="flex gap-1">
      <button
        type="button"
        aria-pressed={sl}
        aria-label={sl ? `Remove ${name} from shortlist` : `Shortlist ${name}`}
        onClick={() => {
          const r = saved.toggle("shortlist", o.id);
          if (r.added) track("shortlist_add", { offering_id: o.id, count: shortlist.length + 1 });
        }}
        className={cn("border-border hover:bg-surface-hover grid size-10 place-items-center rounded-full border transition-colors", sl ? "text-primary" : "text-muted")}
      >
        <Heart className="size-[18px]" fill={sl ? "currentColor" : "none"} aria-hidden />
      </button>
      <button
        type="button"
        aria-pressed={cmp}
        aria-label={cmp ? `Remove ${name} from compare` : `Compare ${name}`}
        onClick={() => {
          const r = saved.toggle("compare", o.id);
          if (r.full) toast("You can compare up to 4 programmes. Remove one to add another.");
          if (r.added) track("compare_add", { offering_id: o.id, count: compare.length + 1 });
        }}
        className={cn("border-border hover:bg-surface-hover grid size-10 place-items-center rounded-full border transition-colors", cmp ? "border-primary text-primary" : "text-muted")}
      >
        <GitCompareArrows className="size-[18px]" aria-hidden />
      </button>
    </div>
  );
}

export function EligibilityBadge({ e }: { e?: OfferingCard["eligibility"] }) {
  if (!e) return null;
  return <Badge tone={e === "eligible" ? "verified" : e === "check" ? "warning" : "danger"}>{ELIGIBILITY_LABEL[e]}</Badge>;
}

/**
 * One offering (a university's version of a programme): full fee with per-year/semester where available and "Easy EMI
 * available" (D-015), duration, NAAC, approvals, eligibility match, shortlist and compare (spec 6.2). Opens the panel.
 */
export function OfferingResult({ o, onOpen, showProgramme }: { o: OfferingCard; onOpen: (o: OfferingCard) => void; showProgramme?: boolean }) {
  const attrs = Object.entries(o.attributes ?? {}).map(([k, v]) => (k === "medium" ? `${v} medium` : ATTRIBUTE_LABEL[k])).filter(Boolean) as string[];
  return (
    <li className="hover:border-border hover:bg-surface-hover grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-2 rounded-[var(--radius-lg)] border border-transparent px-3 py-3 transition-colors sm:grid-cols-[minmax(0,1.7fr)_minmax(0,1fr)_auto]">
      <a
        href={`?offering=${o.id}`}
        onClick={(e) => {
          if (e.metaKey || e.ctrlKey || e.shiftKey) return;
          e.preventDefault();
          onOpen(o);
        }}
        className="flex min-w-0 items-start gap-3 text-left"
      >
        <UniversityMark name={o.university.name} short={o.university.short} logo={o.university.logo} size={36} className="mt-0.5" />
        <span className="min-w-0">
          <span className="text-text block font-semibold leading-snug">
            {showProgramme ? `${o.programme_name} · ${o.spec_name}` : o.university.name}
          </span>
          {showProgramme ? <span className="text-muted block truncate text-sm">{o.university.name}</span> : null}
          {o.spec_display && o.spec_display !== o.spec_name && !showProgramme ? (
            <span className="text-subtle block truncate text-xs">Listed as “{o.spec_display}”</span>
          ) : null}
          <span className="text-muted mt-1.5 flex flex-wrap items-center gap-1.5 text-xs">
            <span>{modeDisplay(o.mode)}</span>
            {o.duration_months ? <span>· {formatDuration(o.duration_months)}</span> : null}
            {o.naac_grade ? <Badge tone="verified">NAAC {o.naac_grade}</Badge> : null}
            {o.ugc_deb ? <Badge tone="info">{UGC_LABEL[o.ugc_deb]}</Badge> : null}
            {o.format ? <Badge>{FORMAT_LABEL[o.format]}</Badge> : null}
            {attrs.map((a) => (
              <Badge key={a}>{a}</Badge>
            ))}
            <EligibilityBadge e={o.eligibility} />
          </span>
        </span>
      </a>
      <div className="col-span-2 row-start-2 sm:col-span-1 sm:row-start-auto sm:text-right">
        {o.fee.total ? (
          <>
            <span className="tabular font-display text-text block text-lg font-semibold">{formatInr(o.fee.total)}</span>
            <span className="text-muted block text-xs">
              total{o.fee.semester ? ` · ${formatInr(o.fee.semester)}/semester` : o.fee.yearly ? ` · ${formatInr(o.fee.yearly)}/year` : ""}
            </span>
            <span className="text-amber-text block text-xs font-medium">Easy EMI available</span>
          </>
        ) : (
          <span className="text-muted block text-sm">Fee on request</span>
        )}
      </div>
      <ShortlistCompareButtons o={o} />
    </li>
  );
}
