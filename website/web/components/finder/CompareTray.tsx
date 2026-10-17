"use client";

import Link from "next/link";
import { GitCompareArrows, X } from "lucide-react";
import { COMPARE_MAX, saved, useSaved } from "@/lib/client/saved-store";

/** Sticky compare tray (spec 6.5): shows the selection and opens /compare with the ids in the URL (shareable). */
export function CompareTray() {
  const ids = useSaved("compare");
  if (!ids.length) return null;
  return (
    <div className="glass-strong fixed inset-x-3 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-[var(--z-dock)] mx-auto flex max-w-xl items-center justify-between gap-3 rounded-full py-2 pr-2 pl-5 md:bottom-4" role="region" aria-label="Compare selection">
      <span className="text-text text-sm">
        <GitCompareArrows className="text-amber-text mr-1.5 inline size-4" aria-hidden />
        {ids.length} of {COMPARE_MAX} selected
      </span>
      <span className="flex items-center gap-1">
        <button type="button" onClick={() => saved.clear("compare")} className="text-muted hover:bg-surface-hover grid size-9 place-items-center rounded-full" aria-label="Clear compare selection">
          <X className="size-4" aria-hidden />
        </button>
        <Link
          href={`/compare?ids=${ids.join(",")}`}
          aria-disabled={ids.length < 2}
          className="bg-primary text-on-primary inline-flex h-10 items-center rounded-full px-5 text-sm font-semibold aria-disabled:opacity-60"
        >
          {ids.length < 2 ? "Pick one more" : "Compare"}
        </Link>
      </span>
    </div>
  );
}
