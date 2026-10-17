"use client";

import { useEffect, useRef } from "react";
import { cssColor, runShader } from "@/lib/client/gl";
import { ORB_FRAG } from "@/lib/client/shaders/orb";
import { presence } from "@/lib/client/witty-presence";
import { useTier, whenIdle } from "@/lib/client/use-tier";
import { cn } from "@/lib/utils";

/**
 * Witty's visual identity (spec 10.3): breathes at rest, ripples while the student types, pulses with streamed tokens.
 * Low tier / reduced motion: a CSS light-form with a gentle breathe (still for reduced motion). Decorative: the state is
 * announced to screen readers by the chat's live region, not by the orb.
 */
export function WittyOrb({ size = 120, className }: { size?: number; className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const tier = useTier();

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas || tier === "low") return;
    let stop: (() => void) | null = null;
    const cancel = whenIdle(() => {
      const c = {
        u_c1: cssColor(canvas, "--lumen-amber", [1, 0.72, 0.12]),
        u_c2: cssColor(canvas, "--lumen-azure", [0.3, 0.6, 1]),
        u_c3: cssColor(canvas, "--lumen-gold", [1, 0.89, 0.63]),
      };
      stop = runShader({
        canvas,
        fragment: ORB_FRAG,
        resolution: 1,
        fps: tier === "high" ? 60 : 30,
        uniforms: () => {
          const s = presence.get();
          return { ...c, u_energy: s.energy, u_pulse: s.pulse, u_dark: 1 };
        },
      });
      canvas.style.opacity = "1";
    }, 400);
    return () => {
      cancel();
      stop?.();
    };
  }, [tier]);

  return (
    <span
      aria-hidden
      className={cn("relative inline-block size-[var(--orb)] shrink-0", className)}
      style={{ "--orb": `${size}px` } as React.CSSProperties}
    >
      <span className="witty-orb-fallback motion-safe:animate-breathe absolute inset-[12%] rounded-full" />
      <canvas ref={ref} className="absolute inset-0 size-full opacity-0 transition-opacity duration-700" />
    </span>
  );
}
