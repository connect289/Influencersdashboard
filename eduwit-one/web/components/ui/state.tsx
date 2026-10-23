import { type ReactNode } from "react";
import { IconCritical, IconInfo, IconWarning } from "@/components/icons.tsx";
import { cn } from "@/lib/cn.ts";

// Every screen has an empty, a loading and an error state (spec standard 6).

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="px-4 py-8 text-center">
      <p className="font-medium">{title}</p>
      {children ? <div className="mt-1 text-sm text-fg-muted">{children}</div> : null}
    </div>
  );
}

/** A load that failed: says what could not be read and what to do, never the raw error or a secret. */
export function ErrorState({ title = "This could not be loaded", detail }: { title?: string; detail?: ReactNode }) {
  return (
    <div role="alert" className="flex gap-3 rounded-lg border border-p1 bg-p1-bg px-4 py-3 text-p1">
      <IconCritical size={20} className="mt-0.5 shrink-0" />
      <div>
        <p className="font-medium">{title}</p>
        {detail ? <div className="mt-0.5 text-sm">{detail}</div> : null}
      </div>
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-md bg-surface-2", className)} aria-hidden="true" />;
}

export function LoadingPage({ label = "Loading" }: { label?: string }) {
  return (
    <div className="grid gap-4" role="status" aria-live="polite">
      <span className="sr-only">{label}…</span>
      <Skeleton className="h-8 w-56" />
      <div className="grid gap-4 md:grid-cols-3">
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
        <Skeleton className="h-28" />
      </div>
      <Skeleton className="h-64" />
    </div>
  );
}

const bannerTone = {
  p1: { cls: "border-p1 bg-p1-bg text-p1", Icon: IconCritical },
  p2: { cls: "border-p2 bg-p2-bg text-p2", Icon: IconWarning },
  p3: { cls: "border-p3 bg-p3-bg text-p3", Icon: IconInfo },
};

export function Banner({ tone, children }: { tone: keyof typeof bannerTone; children: ReactNode }) {
  const { cls, Icon } = bannerTone[tone];
  return (
    <div
      role={tone === "p1" ? "alert" : "status"}
      className={cn("flex items-start gap-2 rounded-md border px-3 py-2 text-sm", cls)}
    >
      <Icon size={16} className="mt-0.5 shrink-0" />
      <div className="min-w-0">{children}</div>
    </div>
  );
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-xl font-semibold md:text-2xl">{title}</h1>
        {description ? <p className="mt-1 max-w-3xl text-sm text-fg-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

/** JSON evidence, bounded and scrollable. */
export function Code({ children, className }: { children: string; className?: string }) {
  return (
    <pre
      className={cn("max-h-96 overflow-auto rounded-md bg-surface-2 p-3 font-mono text-xs leading-relaxed", className)}
    >
      {children}
    </pre>
  );
}
