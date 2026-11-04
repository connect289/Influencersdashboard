import { type ReactNode } from "react";
import { buttonClass } from "@/components/ui/button.tsx";

/** A GET form of filters: the URL is the state, so every filtered view can be linked and shared. */
export function Filters({ children, reset }: { children: ReactNode; reset: string }) {
  return (
    <form method="get" className="flex flex-wrap items-end gap-2 rounded-lg border border-border bg-surface p-3">
      {children}
      <button type="submit" className={buttonClass("secondary", "sm")}>
        Apply
      </button>
      <a href={reset} className={buttonClass("ghost", "sm")}>
        Clear
      </a>
    </form>
  );
}

export function FilterSelect({
  name,
  label,
  value,
  options,
}: {
  name: string;
  label: string;
  value?: string;
  options: Array<[string, string]>;
}) {
  return (
    <label className="grid gap-1 text-xs text-fg-muted">
      {label}
      <select
        name={name}
        defaultValue={value ?? ""}
        className="min-h-9 rounded-md border border-border bg-surface px-2 text-sm text-fg max-md:min-h-11"
      >
        {options.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </select>
    </label>
  );
}
