import { cn } from "@/lib/utils";
import { FAMILY_CLASSES, humanize, statusFamily, type StatusFamily } from "@/lib/design/status";

export function Badge({
  family = "neutral",
  children,
  className,
}: {
  family?: StatusFamily;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
        FAMILY_CLASSES[family],
        className,
      )}
    >
      {children}
    </span>
  );
}

/** A status pill coloured by its family. `label` should come from messages; humanize() is the fallback. */
export function StatusBadge({ status, label }: { status: string; label?: string }) {
  return <Badge family={statusFamily(status)}>{label ?? humanize(status)}</Badge>;
}
