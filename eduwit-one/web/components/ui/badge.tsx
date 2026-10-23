import { type ReactNode } from "react";
import { IconClock, IconCritical, IconInfo, IconOff, IconOk, IconWarning } from "@/components/icons.tsx";
import { cn } from "@/lib/cn.ts";

export type Tone = "p1" | "p2" | "p3" | "ok" | "off" | "neutral" | "accent";

const tones: Record<Tone, string> = {
  p1: "bg-p1-bg text-p1",
  p2: "bg-p2-bg text-p2",
  p3: "bg-p3-bg text-p3",
  ok: "bg-ok-bg text-ok",
  off: "bg-off-bg text-off",
  neutral: "bg-surface-2 text-fg",
  accent: "bg-accent text-accent-fg",
};

const icons: Record<Tone, ((p: { size?: number }) => ReactNode) | null> = {
  p1: IconCritical,
  p2: IconWarning,
  p3: IconInfo,
  ok: IconOk,
  off: IconOff,
  neutral: null,
  accent: IconClock,
};

/** A label with its tone's icon: colour is never the only signal (spec §12). */
export function Badge({
  tone = "neutral",
  children,
  className,
}: {
  tone?: Tone;
  children: ReactNode;
  className?: string;
}) {
  const Icon = icons[tone];
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap",
        tones[tone],
        className,
      )}
    >
      {Icon ? <Icon size={12} /> : null}
      {children}
    </span>
  );
}

export function SeverityBadge({ severity }: { severity: string }) {
  const tone: Tone = severity === "P1" ? "p1" : severity === "P2" ? "p2" : "p3";
  return <Badge tone={tone}>{severity}</Badge>;
}

const statusTones: Record<string, Tone> = {
  ok: "ok",
  pass: "ok",
  passed: "ok",
  done: "ok",
  sent: "ok",
  approved: "ok",
  applied: "ok",
  validated: "ok",
  verified: "ok",
  recovered: "ok",
  fail: "p1",
  failed: "p1",
  error: "p1",
  rejected: "off",
  source_missing: "p2",
  skipped: "off",
  planned: "p3",
  pending: "p3",
  open: "p3",
  snoozed: "off",
  expired: "off",
  reverted: "off",
  not_configured: "off",
  not_provided: "off",
  unfilled: "off",
  refused: "p2",
  muted: "off",
  suppressed: "off",
};

/** A status word in its tone; unknown words are neutral. Underscores read as spaces. */
export function StatusBadge({ status }: { status: string | null | undefined }) {
  const s = status ?? "unknown";
  return <Badge tone={statusTones[s] ?? "neutral"}>{s.replaceAll("_", " ")}</Badge>;
}
