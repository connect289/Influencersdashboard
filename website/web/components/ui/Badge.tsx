import { cva, type VariantProps } from "class-variance-authority";
import { BadgeCheck } from "lucide-react";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const badge = cva(
  "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold leading-5 [&_svg]:size-3.5",
  {
    variants: {
      tone: {
        neutral: "border-border bg-surface text-muted",
        verified:
          "verified-shimmer border-[color-mix(in_oklab,var(--success)_35%,transparent)] bg-success-soft text-success",
        amber: "border-[color-mix(in_oklab,var(--primary)_40%,transparent)] bg-amber-soft text-amber-text",
        info: "border-[color-mix(in_oklab,var(--accent)_35%,transparent)] bg-accent-soft text-accent",
        warning: "border-[color-mix(in_oklab,var(--warning)_40%,transparent)] bg-warning-soft text-warning",
        danger: "border-[color-mix(in_oklab,var(--danger)_40%,transparent)] bg-danger-soft text-danger",
      },
    },
    defaultVariants: { tone: "neutral" },
  },
);

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badge> {}

/** Small status label. `verified` adds the approval shimmer (spec 10.3 "live trust layer"). */
export function Badge({ className, tone, children, ...props }: BadgeProps) {
  return (
    <span className={cn(badge({ tone }), className)} {...props}>
      {tone === "verified" ? <BadgeCheck aria-hidden /> : null}
      {children}
    </span>
  );
}
