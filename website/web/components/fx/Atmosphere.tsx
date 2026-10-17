"use client";

import { useEffect, useRef } from "react";
import { cssColor, runShader } from "@/lib/client/gl";
import { AURORA_FRAG } from "@/lib/client/shaders/aurora";
import { PRISM_FRAG } from "@/lib/client/shaders/prism";
import { presence } from "@/lib/client/witty-presence";
import { useTier, whenIdle } from "@/lib/client/use-tier";
import { cn } from "@/lib/utils";

/**
 * Hero atmosphere (spec 10.2 "living aurora", 10.4 guardrails). The CSS poster gradient is always painted first (and is
 * all that low-tier devices get); the shader fades in after first paint, at reduced resolution, capped fps, paused
 * off-screen. It reacts to pointer, scroll and Witty's activity. Never the LCP element: it is aria-hidden decoration.
 */
export function Atmosphere({ variant = "aurora", className }: { variant?: "aurora" | "prism"; className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const tier = useTier();

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas || tier === "low") return;
    let stop: (() => void) | null = null;
    const pointer: [number, number] = [0.7, 0.6];
    const target: [number, number] = [0.7, 0.6];
    let scroll = 0;
    let colours = readColours(canvas);

    const onMove = (e: PointerEvent) => {
      const r = canvas.getBoundingClientRect();
      target[0] = (e.clientX - r.left) / r.width;
      target[1] = 1 - (e.clientY - r.top) / r.height;
    };
    const onScroll = () => {
      scroll = Math.min(1, window.scrollY / Math.max(1, window.innerHeight));
    };
    const mo = new MutationObserver(() => {
      colours = readColours(canvas);
    });
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    const themed = canvas.closest("[data-theme]");
    if (themed && themed !== document.documentElement)
      mo.observe(themed, { attributes: true, attributeFilter: ["data-theme"] });

    const cancelIdle = whenIdle(() => {
      stop = runShader({
        canvas,
        fragment: variant === "prism" ? PRISM_FRAG : AURORA_FRAG,
        resolution: tier === "high" ? 0.75 : 0.5,
        fps: tier === "high" ? 60 : 30,
        uniforms: () => {
          pointer[0] += (target[0] - pointer[0]) * 0.04;
          pointer[1] += (target[1] - pointer[1]) * 0.04;
          return { ...colours, u_pointer: [pointer[0], pointer[1]], u_scroll: scroll, u_energy: presence.get().energy };
        },
      });
      canvas.style.opacity = "1";
    });
    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      cancelIdle();
      stop?.();
      mo.disconnect();
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("scroll", onScroll);
    };
  }, [tier, variant]);

  return (
    <div aria-hidden className={cn("pointer-events-none absolute inset-0 overflow-hidden", className)}>
      <div className={cn("absolute inset-0", variant === "prism" ? "atmosphere-poster-prism" : "atmosphere-poster")} />
      <canvas ref={ref} className="absolute inset-0 size-full opacity-0 transition-opacity duration-[1200ms]" />
    </div>
  );
}

function readColours(el: Element) {
  const dark = (el.closest("[data-theme]")?.getAttribute("data-theme") ?? "dark") !== "light";
  return {
    u_c1: cssColor(el, "--aurora-1", [1, 0.72, 0.12]),
    u_c2: cssColor(el, "--aurora-2", [0.16, 0.44, 0.86]),
    u_c3: cssColor(el, "--aurora-3", [0.04, 0.25, 0.47]),
    u_base: cssColor(el, "--aurora-base", [0.01, 0.035, 0.075]),
    u_dark: dark ? 1 : 0,
  };
}
