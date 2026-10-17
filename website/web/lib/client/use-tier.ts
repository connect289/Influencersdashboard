"use client";

import { useSyncExternalStore } from "react";

export type Tier = "low" | "mid" | "high";

function subscribeAttr(attr: string) {
  return (cb: () => void) => {
    const mo = new MutationObserver(cb);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: [attr] });
    return () => mo.disconnect();
  };
}
const subscribeTier = subscribeAttr("data-tier");

/** Reads the capability tier the boot script wrote to <html data-tier> (spec 10.4). Server snapshot: "low". */
export function useTier(): Tier {
  return useSyncExternalStore(
    subscribeTier,
    () => {
      const t = document.documentElement.getAttribute("data-tier");
      return t === "high" || t === "mid" ? t : "low";
    },
    () => "low",
  );
}

/** Defers work until the browser is idle after first paint (falls back to a timeout). */
export function whenIdle(cb: () => void, timeout = 1200): () => void {
  if (typeof window === "undefined") return () => {};
  const w = window as Window & {
    requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number;
    cancelIdleCallback?: (id: number) => void;
  };
  if (w.requestIdleCallback) {
    const id = w.requestIdleCallback(cb, { timeout });
    return () => w.cancelIdleCallback?.(id);
  }
  const id = window.setTimeout(cb, 300);
  return () => window.clearTimeout(id);
}
