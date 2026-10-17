"use client";

import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";
import { usePointerGlow } from "@/lib/client/use-magnetic";

/** Floating translucent surface with a pointer-reactive glow (desktop) and luminous hairline. */
export function Card({
  className,
  glow = true,
  children,
  ...props
}: HTMLAttributes<HTMLDivElement> & { glow?: boolean }) {
  const ref = usePointerGlow<HTMLDivElement>();
  return (
    <div
      ref={glow ? ref : undefined}
      className={cn("glass hairline-lumen rounded-[var(--radius-xl)]", glow && "pointer-glow", className)}
      {...props}
    >
      {children}
    </div>
  );
}
