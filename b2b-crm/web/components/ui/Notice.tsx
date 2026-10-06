import { CircleAlert, CircleCheck, Info } from "lucide-react";
import { cn } from "./cn";

const tones = {
  error: { cls: "bg-danger-bg text-danger border-danger/25", Icon: CircleAlert },
  success: { cls: "bg-success-bg text-success border-success/25", Icon: CircleCheck },
  info: { cls: "bg-info-bg text-info border-info/25", Icon: Info },
  warning: { cls: "bg-warning-bg text-warning border-warning/25", Icon: CircleAlert },
} as const;

/** Inline message. Errors are announced to screen readers immediately. */
export function Notice({ tone = "info", children, className }: { tone?: keyof typeof tones; children: React.ReactNode; className?: string }) {
  const { cls, Icon } = tones[tone];
  return (
    <div role={tone === "error" ? "alert" : "status"} className={cn("flex gap-2.5 rounded-lg border px-3 py-2.5 text-[13px] leading-5 animate-fade-in", cls, className)}>
      <Icon className="mt-0.5 size-4 shrink-0" aria-hidden />
      <div className="min-w-0">{children}</div>
    </div>
  );
}
