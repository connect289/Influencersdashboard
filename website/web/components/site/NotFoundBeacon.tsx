"use client";

import { useEffect } from "react";

/** Reports a 404 (path and referring host only) to the admin 404 monitor (spec 13.4). */
export function NotFoundBeacon() {
  useEffect(() => {
    const ref = document.referrer ? new URL(document.referrer).host : "";
    const body = JSON.stringify({ path: window.location.pathname, referrer: ref });
    try {
      if (!navigator.sendBeacon?.("/api/events/404", new Blob([body], { type: "application/json" })))
        void fetch("/api/events/404", { method: "POST", body, headers: { "content-type": "application/json" }, keepalive: true });
    } catch {
      // never break the page
    }
  }, []);
  return null;
}
