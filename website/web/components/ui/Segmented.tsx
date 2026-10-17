"use client";

import { ToggleGroup } from "radix-ui";
import { cn } from "@/lib/utils";

/** Single-choice segmented control (e.g. Grouped / All offerings; theme switch in the style guide). */
export function Segmented<T extends string>({
  value,
  onValueChange,
  options,
  label,
  className,
}: {
  value: T;
  onValueChange: (v: T) => void;
  options: { value: T; label: React.ReactNode }[];
  label: string;
  className?: string;
}) {
  return (
    <ToggleGroup.Root
      type="single"
      value={value}
      onValueChange={(v) => v && onValueChange(v as T)}
      aria-label={label}
      className={cn("border-border bg-surface inline-flex rounded-full border p-1", className)}
    >
      {options.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          className="text-muted data-[state=on]:bg-primary data-[state=on]:text-on-primary hover:text-text data-[state=on]:hover:text-on-primary h-8 rounded-full px-3.5 text-sm transition-colors data-[state=on]:shadow-[var(--glow-amber)]"
        >
          {o.label}
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
