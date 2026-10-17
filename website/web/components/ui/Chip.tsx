"use client";

import { X } from "lucide-react";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

interface ChipProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  selected?: boolean;
  onRemove?: () => void;
  count?: number;
}

/** Selectable chip (starter questions, facet presets) or removable filter chip (applied filters). */
export function Chip({ selected, onRemove, count, className, children, disabled, ...props }: ChipProps) {
  if (onRemove) {
    return (
      <span
        className={cn(
          "border-border-strong bg-surface text-text inline-flex h-8 items-center gap-1 rounded-full border pr-1 pl-3 text-sm",
          className,
        )}
      >
        {children}
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remove filter ${typeof children === "string" ? children : ""}`}
          className="text-muted hover:bg-surface-hover hover:text-text grid size-6 place-items-center rounded-full"
        >
          <X className="size-3.5" aria-hidden />
        </button>
      </span>
    );
  }
  return (
    <button
      type="button"
      aria-pressed={selected}
      disabled={disabled}
      className={cn(
        "inline-flex min-h-9 items-center gap-2 rounded-full border px-3.5 text-sm transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-45",
        selected
          ? "border-primary bg-amber-soft text-text"
          : "border-border bg-surface text-muted hover:border-border-strong hover:text-text",
        className,
      )}
      {...props}
    >
      {children}
      {typeof count === "number" ? (
        <span className="tabular text-subtle text-xs">{count.toLocaleString("en-IN")}</span>
      ) : null}
    </button>
  );
}
