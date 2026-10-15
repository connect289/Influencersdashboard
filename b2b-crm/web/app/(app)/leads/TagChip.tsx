import { cn } from "@/components/ui/cn";

/** A tag's colour (b2b.tags.color), readable in both themes. */
export const TAG_COLOR: Record<string, string> = {
  slate: "border-border bg-surface-2 text-muted",
  red: "border-danger/30 bg-danger-bg text-danger",
  amber: "border-amber/40 bg-amber/10 text-navy dark:text-amber",
  green: "border-success/30 bg-success-bg text-success",
  blue: "border-info/30 bg-info/10 text-info",
  violet: "border-violet-500/30 bg-violet-500/10 text-violet-700 dark:text-violet-300",
  pink: "border-pink-500/30 bg-pink-500/10 text-pink-700 dark:text-pink-300",
};

export function TagChip({ name, color = "slate", className, children }: { name: string; color?: string; className?: string; children?: React.ReactNode }) {
  return (
    <span className={cn("inline-flex max-w-[160px] items-center gap-1 rounded-md border px-1.5 py-0.5 text-[11px] font-medium leading-4", TAG_COLOR[color] ?? TAG_COLOR.slate, className)}>
      <span className="truncate">{name}</span>{children}
    </span>
  );
}
