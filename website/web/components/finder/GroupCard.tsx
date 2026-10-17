"use client";

import { ViewTransition, useState } from "react";
import { ChevronDown, Sparkles } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { formatInrRange } from "@/lib/format";
import type { SeedGroup, SeedOffering } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";
import { OfferingRow } from "./OfferingRow";

/**
 * Programme + specialisation group (spec 6.2): name and level, number of universities, fee range, best NAAC, EMI badge,
 * top three university marks; expands to one row per university.
 */
export function GroupCard({
  g,
  onOpen,
  variant = "a",
  shortlist,
  compare,
  onShortlist,
  onCompare,
}: {
  g: SeedGroup;
  onOpen: (o: SeedOffering) => void;
  variant?: "a" | "b";
  shortlist: Set<number>;
  compare: Set<number>;
  onShortlist: (id: number) => void;
  onCompare: (id: number) => void;
}) {
  const [open, setOpen] = useState(false);
  const id = `group-${g.key.replace(/[^a-z0-9]/gi, "-")}`;
  return (
    <ViewTransition name={id}>
      <Card className={cn("overflow-hidden", variant === "b" && "rounded-[var(--radius-lg)]")}>
        <button
          type="button"
          aria-expanded={open}
          aria-controls={`${id}-list`}
          onClick={() => setOpen((v) => !v)}
          className="grid w-full grid-cols-[1fr_auto] gap-4 p-5 text-left"
        >
          <div className="min-w-0">
            <p className="eyebrow">
              {g.level === "PG" ? "Postgraduate" : g.level === "UG" ? "Undergraduate" : g.level}
            </p>
            <h3 className="font-display text-text mt-1 text-xl leading-tight font-semibold sm:text-2xl">
              {g.programme}
              <span className="text-muted"> · {g.specialisation}</span>
            </h3>
            <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
              <span className="tabular text-text font-semibold">{formatInrRange(g.feeMin, g.feeMax)}</span>
              <span className="text-subtle">total fee</span>
              {g.offerings.some((o) => o.emi) ? <Badge tone="amber">Easy EMI available</Badge> : null}
              {g.bestNaac ? <Badge tone="verified">Up to NAAC {g.bestNaac}</Badge> : null}
            </div>
            <div className="text-muted mt-3 flex items-center gap-2 text-sm">
              <span className="flex -space-x-2" aria-hidden>
                {g.universities.slice(0, 3).map((u) => (
                  <span
                    key={u}
                    className="bg-navy-700 grid size-8 place-items-center rounded-full border-2 border-[var(--surface-solid)] text-[10px] font-bold text-white"
                  >
                    {u.slice(0, 3).toUpperCase()}
                  </span>
                ))}
              </span>
              <span>
                {g.universities.length} {g.universities.length === 1 ? "university" : "universities"}
              </span>
            </div>
          </div>
          <span
            className={cn(
              "border-border text-muted mt-1 grid size-10 place-items-center rounded-full border transition-transform duration-300",
              open && "rotate-180",
            )}
          >
            <ChevronDown className="size-5" aria-hidden />
          </span>
        </button>
        {open ? (
          <ul id={`${id}-list`} className="border-border grid gap-1 border-t px-2 py-2">
            {g.offerings.map((o) => (
              <OfferingRow
                key={o.id}
                o={o}
                onOpen={() => onOpen(o)}
                shortlisted={shortlist.has(o.id)}
                compared={compare.has(o.id)}
                onShortlist={() => onShortlist(o.id)}
                onCompare={() => onCompare(o.id)}
              />
            ))}
            <li className="text-muted flex items-center gap-2 px-3 py-2 text-sm">
              <Sparkles className="text-amber-text size-4" aria-hidden /> Not sure which one?{" "}
              <span className="text-text font-medium">Ask Witty</span>
            </li>
          </ul>
        ) : null}
      </Card>
    </ViewTransition>
  );
}
