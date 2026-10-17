"use client";

import { Tabs as T } from "radix-ui";
import { cn } from "@/lib/utils";

export function Tabs({
  tabs,
  defaultValue,
  className,
}: {
  tabs: { value: string; label: React.ReactNode; content: React.ReactNode }[];
  defaultValue?: string;
  className?: string;
}) {
  return (
    <T.Root defaultValue={defaultValue ?? tabs[0]?.value} className={className}>
      <T.List className="border-border flex gap-1 overflow-x-auto border-b" aria-label="Sections">
        {tabs.map((t) => (
          <T.Trigger
            key={t.value}
            value={t.value}
            className="text-muted hover:text-text data-[state=active]:text-text after:bg-primary relative h-11 shrink-0 px-4 text-sm font-medium transition-colors after:absolute after:inset-x-3 after:-bottom-px after:h-0.5 after:scale-x-0 after:rounded-full after:transition-transform data-[state=active]:after:scale-x-100"
          >
            {t.label}
          </T.Trigger>
        ))}
      </T.List>
      {tabs.map((t) => (
        <T.Content key={t.value} value={t.value} className={cn("pt-5 outline-none")}>
          {t.content}
        </T.Content>
      ))}
    </T.Root>
  );
}
