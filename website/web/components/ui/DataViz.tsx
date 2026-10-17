import { cn } from "@/lib/utils";

/** Horizontal fee bar: fills to the offering's fee relative to a range (spec 10.1 "data as delight"). */
export function FeeBar({
  value,
  min,
  max,
  className,
  label,
}: {
  value: number;
  min: number;
  max: number;
  className?: string;
  label: string;
}) {
  const pct = max > min ? Math.round(((value - min) / (max - min)) * 100) : 50;
  return (
    <div className={cn("grid gap-1", className)}>
      <div className="bg-border relative h-2 overflow-hidden rounded-full" role="img" aria-label={label}>
        <span
          className="fee-bar-fill absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-amber-400 to-amber-600"
          style={{ width: `${Math.max(4, pct)}%` }}
        />
      </div>
    </div>
  );
}

/** Segmented meter for ordinal values such as NAAC grades (B … A++). */
export function GradeMeter({
  grade,
  scale = ["B", "B+", "B++", "A", "A+", "A++"],
  className,
}: {
  grade: string | null;
  scale?: string[];
  className?: string;
}) {
  const idx = grade ? scale.indexOf(grade) : -1;
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <div className="flex gap-0.5" role="img" aria-label={grade ? `NAAC grade ${grade}` : "NAAC grade not stated"}>
        {scale.map((g, i) => (
          <span
            key={g}
            className={cn(
              "h-2 w-3 rounded-[2px]",
              i <= idx ? "bg-success shadow-[0_0_6px_-1px_var(--success)]" : "bg-border-strong",
            )}
          />
        ))}
      </div>
      <span className="text-text text-sm font-semibold">{grade ?? "—"}</span>
    </div>
  );
}

/** Luminous progress track for multi-step forms (spec 10.3). */
export function ProgressTrack({
  step,
  total,
  labels,
  label = "Progress",
}: {
  step: number;
  total: number;
  labels?: string[];
  label?: string;
}) {
  return (
    <div className="grid gap-2">
      <div
        className="bg-border relative h-1.5 overflow-hidden rounded-full"
        role="progressbar"
        aria-label={label}
        aria-valuemin={1}
        aria-valuemax={total}
        aria-valuenow={step}
        aria-valuetext={
          labels?.[step - 1] ? `Step ${step} of ${total}: ${labels[step - 1]}` : `Step ${step} of ${total}`
        }
      >
        <span
          className="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-amber-500 via-amber-300 to-amber-500 shadow-[0_0_14px_var(--primary)] transition-[width] duration-500 ease-[var(--ease-out-expo)]"
          style={{ width: `${(step / total) * 100}%` }}
        />
      </div>
      {labels ? (
        <ol className="text-subtle hidden justify-between text-xs sm:flex">
          {labels.map((l, i) => (
            <li key={l} className={cn(i + 1 === step && "text-text font-semibold", i + 1 < step && "text-muted")}>
              {l}
            </li>
          ))}
        </ol>
      ) : null}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div aria-hidden className={cn("skeleton h-4", className)} />;
}

export function EmptyState({
  icon,
  title,
  children,
  action,
}: {
  icon?: React.ReactNode;
  title: string;
  children?: React.ReactNode;
  action?: React.ReactNode;
}) {
  return (
    <div className="border-border-strong grid justify-items-center gap-3 rounded-[var(--radius-xl)] border border-dashed px-6 py-10 text-center">
      {icon ? (
        <div className="bg-amber-soft text-amber-text grid size-12 place-items-center rounded-full">{icon}</div>
      ) : null}
      <h3 className="text-lg font-semibold">{title}</h3>
      {children ? <div className="text-muted max-w-md">{children}</div> : null}
      {action}
    </div>
  );
}
