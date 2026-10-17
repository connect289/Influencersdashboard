"use client";

import { useSaved } from "@/lib/client/saved-store";
import { cn } from "@/lib/utils";

/** Live count badge for the compare/shortlist selections (localStorage; hidden when zero). */
export function SavedCount({ list, className }: { list: "compare" | "shortlist"; className?: string }) {
  const n = useSaved(list).length;
  if (!n) return null;
  return (
    <span
      className={cn(
        "tabular bg-primary text-on-primary grid min-w-5 place-items-center rounded-full px-1 text-[11px] leading-5 font-bold",
        className,
      )}
    >
      {n}
      <span className="sr-only"> selected</span>
    </span>
  );
}
