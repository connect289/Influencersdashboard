"use client";

import { useEffect, useRef } from "react";

/**
 * Magnetic hover for primary buttons on desktop pointers only (spec 10.3). Moves the element up to `strength` px toward
 * the pointer; disabled for touch, coarse pointers and reduced motion.
 */
export function useMagnetic<T extends HTMLElement>(strength = 6) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (
      !matchMedia("(hover: hover) and (pointer: fine)").matches ||
      matchMedia("(prefers-reduced-motion: reduce)").matches
    )
      return;
    let raf = 0;
    const move = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width - 0.5) * 2 * strength;
      const y = ((e.clientY - r.top) / r.height - 0.5) * 2 * strength;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => (el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`));
    };
    const leave = () => {
      cancelAnimationFrame(raf);
      el.style.transform = "";
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerleave", leave);
    return () => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerleave", leave);
    };
  }, [strength]);
  return ref;
}

/** Pointer-reactive glow on cards: writes --mx/--my (desktop only). */
export function usePointerGlow<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || !matchMedia("(hover: hover) and (pointer: fine)").matches) return;
    const move = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      el.style.setProperty("--mx", `${e.clientX - r.left}px`);
      el.style.setProperty("--my", `${e.clientY - r.top}px`);
    };
    el.addEventListener("pointermove", move);
    return () => el.removeEventListener("pointermove", move);
  }, []);
  return ref;
}

/** Light haptic tick on supporting phones, only in response to a user action (spec 10.3). */
export function haptic(ms = 8) {
  try {
    if (
      typeof navigator !== "undefined" &&
      "vibrate" in navigator &&
      !matchMedia("(prefers-reduced-motion: reduce)").matches
    )
      navigator.vibrate(ms);
  } catch {
    // unsupported
  }
}
