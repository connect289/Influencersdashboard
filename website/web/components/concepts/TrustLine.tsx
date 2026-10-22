"use client";

import { ShieldCheck } from "lucide-react";
import { Odometer } from "@/components/ui/Odometer";
import { cn } from "@/lib/utils";

/**
 * Live trust layer (spec 8.1, 10.3): counts up from catalogue numbers. Only claims the data supports (D-014): the
 * "UGC-DEB entitled" share is shown only when every listed university states it.
 */
export function TrustLine({
  universities,
  programmes,
  allDeb,
  className,
}: {
  universities: number;
  programmes: number;
  allDeb: boolean;
  className?: string;
}) {
  return (
    <p
      className={cn(
        "border-border bg-surface text-muted inline-flex flex-wrap items-center justify-center gap-x-2 gap-y-0.5 rounded-[var(--radius-lg)] border px-3.5 py-1.5 text-xs backdrop-blur sm:rounded-full sm:px-4 sm:text-sm",
        className,
      )}
    >
      <ShieldCheck className="text-success size-4" aria-hidden />
      <span>
        <Odometer value={universities} className="text-text font-semibold" /> partner universities
      </span>
      <span aria-hidden>·</span>
      <span>
        <Odometer value={programmes} className="text-text font-semibold" /> programmes
      </span>
      <span aria-hidden className="hidden sm:inline">
        ·
      </span>
      <span className="hidden sm:inline">{allDeb ? "100% UGC-DEB entitled" : "approvals from university records"}</span>
    </p>
  );
}
