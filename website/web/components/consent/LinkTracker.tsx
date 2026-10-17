"use client";

import { useEffect } from "react";
import { track } from "@/lib/client/analytics";

/**
 * One delegated listener for "talk to a counsellor" links anywhere on the site (WhatsApp, phone): `counsellor_click`
 * with the page section and channel — no personal data (spec 13.3).
 */
export function LinkTracker() {
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const a = (e.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!a) return;
      const href = a.getAttribute("href") ?? "";
      const channel = /^https:\/\/(wa\.me|api\.whatsapp\.com)\//.test(href) ? "whatsapp" : href.startsWith("tel:") ? "phone" : null;
      if (!channel) return;
      const surface = a.closest("[data-surface]")?.getAttribute("data-surface") ?? (window.location.pathname.split("/")[1] || "home");
      track("counsellor_click", { surface, channel });
    };
    document.addEventListener("click", onClick, { capture: true });
    return () => document.removeEventListener("click", onClick, { capture: true });
  }, []);
  return null;
}
