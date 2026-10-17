import { AlertTriangle, Inbox, SearchX } from "lucide-react";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Nothing here yet (first use). */
export function EmptyState({
  title,
  description,
  action,
  icon,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 rounded-[var(--radius-card)] border border-dashed border-line-strong px-6 py-10 text-center">
      <div className="text-faint [&_svg]:size-8" aria-hidden>
        {icon ?? <Inbox />}
      </div>
      <p className="font-medium">{title}</p>
      {description ? <p className="max-w-md text-sm text-muted">{description}</p> : null}
      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}

/** Filters matched nothing. */
export function NoResults({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return <EmptyState title={title} description={description} action={action} icon={<SearchX />} />;
}

/** Something failed to load. Never shows raw error text that could carry data. */
export function ErrorState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div
      role="alert"
      className="flex flex-col items-center gap-2 rounded-[var(--radius-card)] bg-danger-soft px-6 py-8 text-center"
    >
      <AlertTriangle className="size-7 text-danger" aria-hidden />
      <p className="font-medium text-danger">{title}</p>
      {description ? <p className="max-w-md text-sm text-ink">{description}</p> : null}
      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-lg bg-surface-2", className)} aria-hidden />;
}

/** Loading placeholder for a list or table. */
export function ListSkeleton({ rows = 6, label }: { rows?: number; label: string }) {
  return (
    <div role="status" aria-label={label} className="flex flex-col gap-2">
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton key={i} className="h-12 w-full" />
      ))}
      <span className="sr-only">{label}</span>
    </div>
  );
}

export function Banner({
  tone = "info",
  children,
}: {
  tone?: "info" | "warning" | "danger" | "success";
  children: ReactNode;
}) {
  const tones = {
    info: "bg-primary-soft text-primary",
    warning: "bg-accent-soft text-accent-ink",
    danger: "bg-danger-soft text-danger",
    success: "bg-success-soft text-success",
  } as const;
  return (
    <div
      role={tone === "danger" ? "alert" : "status"}
      className={cn("rounded-xl px-3 py-2 text-sm", tones[tone])}
    >
      {children}
    </div>
  );
}
