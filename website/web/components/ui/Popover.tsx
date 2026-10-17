"use client";

import { Popover as P } from "radix-ui";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

/** Filter pill that opens a popover (Concept B's horizontal filter bar). */
export function FilterPopover({
  label,
  active,
  children,
}: {
  label: React.ReactNode;
  active?: boolean;
  children: React.ReactNode;
}) {
  return (
    <P.Root>
      <P.Trigger
        className={cn(
          "inline-flex h-10 items-center gap-1.5 rounded-full border px-4 text-sm transition-colors",
          active ? "border-primary bg-amber-soft text-text" : "border-border-strong text-muted hover:text-text",
        )}
      >
        {label}
        <ChevronDown className="size-4" aria-hidden />
      </P.Trigger>
      <P.Portal>
        <P.Content
          sideOffset={8}
          align="start"
          className="glass-strong z-[var(--z-overlay)] w-[min(24rem,calc(100vw-2rem))] rounded-[var(--radius-lg)] p-5 outline-none"
        >
          {children}
        </P.Content>
      </P.Portal>
    </P.Root>
  );
}
