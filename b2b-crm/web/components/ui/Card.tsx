import { cn } from "./cn";

export function Card({ className, ...rest }: React.HTMLAttributes<HTMLElement>) {
  return <section className={cn("rounded-[var(--radius-card)] border border-border bg-surface", className)} {...rest} />;
}

export function CardHeader({ title, description, action }: { title: string; description?: string; action?: React.ReactNode }) {
  return (
    <header className="flex items-start justify-between gap-4 border-b border-border px-5 py-4">
      <div className="min-w-0">
        <h2 className="text-sm font-semibold text-fg">{title}</h2>
        {description && <p className="mt-0.5 text-[13px] text-muted">{description}</p>}
      </div>
      {action}
    </header>
  );
}

export function Badge({ tone = "neutral", children, className }: {
  tone?: "neutral" | "success" | "warning" | "danger" | "info" | "brand";
  children: React.ReactNode;
  className?: string;
}) {
  const tones = {
    neutral: "bg-surface-2 text-muted border-border",
    success: "bg-success-bg text-success border-success/20",
    warning: "bg-warning-bg text-warning border-warning/20",
    danger: "bg-danger-bg text-danger border-danger/20",
    info: "bg-info-bg text-info border-info/20",
    brand: "bg-amber/15 text-navy dark:text-amber border-amber/30",
  };
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[11px] font-medium leading-4", tones[tone], className)}>
      {children}
    </span>
  );
}

export function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex h-5 min-w-5 items-center justify-center rounded border border-border bg-surface-2 px-1 font-mono text-[11px] text-muted">
      {children}
    </kbd>
  );
}

export function EmptyState({ icon: Icon, title, children, action }: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  children?: React.ReactNode;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-12 text-center">
      <div className="mb-3 grid size-11 place-items-center rounded-xl border border-border bg-surface-2">
        <Icon className="size-5 text-muted" />
      </div>
      <h3 className="text-sm font-semibold text-fg">{title}</h3>
      {children && <div className="mt-1 max-w-md text-[13px] leading-5 text-muted">{children}</div>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: React.ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight text-fg">{title}</h1>
        {description && <p className="mt-1 max-w-2xl text-sm text-muted">{description}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
