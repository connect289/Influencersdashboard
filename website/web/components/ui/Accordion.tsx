"use client";

import { Accordion as A } from "radix-ui";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

export function Accordion({
  items,
  className,
  type = "single",
}: {
  items: { id: string; title: React.ReactNode; content: React.ReactNode }[];
  className?: string;
  type?: "single" | "multiple";
}) {
  const Root = A.Root as React.ElementType;
  return (
    <Root
      type={type}
      collapsible={type === "single" ? true : undefined}
      className={cn("divide-border border-border divide-y rounded-[var(--radius-lg)] border", className)}
    >
      {items.map((it) => (
        <A.Item key={it.id} value={it.id}>
          <A.Header>
            <A.Trigger className="group text-text hover:bg-surface-hover flex w-full items-center justify-between gap-4 px-5 py-4 text-left font-medium">
              {it.title}
              <ChevronDown
                className="text-subtle size-5 shrink-0 transition-transform duration-300 group-data-[state=open]:rotate-180"
                aria-hidden
              />
            </A.Trigger>
          </A.Header>
          <A.Content className="accordion-content text-muted overflow-hidden px-5">
            <div className="pb-5">{it.content}</div>
          </A.Content>
        </A.Item>
      ))}
    </Root>
  );
}
