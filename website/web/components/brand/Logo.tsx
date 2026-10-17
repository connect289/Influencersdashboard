import { cn } from "@/lib/utils";

type Variant = "lockup" | "mark" | "wordmark" | "full";

const SRC: Record<Variant, { light: string; dark: string; w: number; h: number }> = {
  lockup: { light: "/brand/eduwit-lockup.svg", dark: "/brand/eduwit-lockup-dark.svg", w: 980, h: 260 },
  mark: { light: "/brand/eduwit-mark.svg", dark: "/brand/eduwit-mark-dark.svg", w: 500, h: 610 },
  wordmark: { light: "/brand/eduwit-wordmark.svg", dark: "/brand/eduwit-wordmark-dark.svg", w: 720, h: 260 },
  full: { light: "/brand/eduwit-logo.svg", dark: "/brand/eduwit-logo-dark.svg", w: 720, h: 860 },
};

/**
 * The Eduwit logo, unchanged from the owner's file (SVG trace — S-40). Two cached <img> files, one per theme, toggled by
 * the theme attribute so the navy half stays legible on dark surfaces. Height drives size; width follows the ratio.
 */
export function Logo({
  variant = "lockup",
  height = 32,
  className,
  priority,
}: {
  variant?: Variant;
  height?: number;
  className?: string;
  priority?: boolean;
}) {
  const s = SRC[variant];
  const width = Math.round((s.w / s.h) * height);
  const common = { width, height, decoding: "async" as const, fetchPriority: priority ? ("high" as const) : undefined };
  return (
    <span className={cn("inline-flex shrink-0", className)} style={{ width, height }}>
      {/* eslint-disable-next-line @next/next/no-img-element -- SVG brand asset, already optimal */}
      <img src={s.light} alt="Eduwit" {...common} className="only-light" />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={s.dark} width={width} height={height} decoding="async" alt="" aria-hidden className="only-dark" />
    </span>
  );
}
