"use client";

import { FUNNEL_STEPS, sanitiseEvent, type EventName, type EventParams } from "@/lib/analytics/events";
import { allowed } from "@/lib/consent";
import { getConsent } from "./consent-store";

type Gtag = (...args: unknown[]) => void;
type Fbq = (...args: unknown[]) => void;
declare global {
  interface Window {
    gtag?: Gtag;
    fbq?: Fbq;
    dataLayer?: unknown[];
  }
}

/** Session-scoped anonymous id for funnel analytics (only with analytics consent; sessionStorage, cleared with the tab). */
function anonId(): string {
  if (!allowed(getConsent(), "analytics")) return "unconsented";
  try {
    let id = sessionStorage.getItem("ew_aid");
    if (!id) {
      id = crypto.randomUUID();
      sessionStorage.setItem("ew_aid", id);
    }
    return id;
  } catch {
    return "unconsented";
  }
}

/**
 * Tracks an allow-listed event: GA4 (analytics consent), Meta Pixel (marketing consent, standard events only), and the
 * site's own funnel counters (always, without identifiers unless analytics consent was given).
 */
export function track(name: EventName, params: EventParams = {}) {
  const clean = sanitiseEvent(name, params);
  const consent = getConsent();
  if (allowed(consent, "analytics")) window.gtag?.("event", name, clean);
  if (allowed(consent, "marketing") && window.fbq) {
    if (name === "lead_created")
      window.fbq("track", "Lead", {}, clean.event_id ? { eventID: String(clean.event_id) } : undefined);
    else if (name === "form_submit")
      window.fbq(
        "trackCustom",
        "SubmitApplication",
        {},
        clean.event_id ? { eventID: String(clean.event_id) } : undefined,
      );
  }
  const f = FUNNEL_STEPS[name];
  if (f) {
    const step = name === "form_step_complete" ? `step_${clean.step ?? "x"}` : f.step;
    const body = JSON.stringify({ funnel: f.funnel, step, anon: anonId(), context: clean });
    try {
      if (!navigator.sendBeacon?.("/api/events", new Blob([body], { type: "application/json" }))) {
        void fetch("/api/events", {
          method: "POST",
          body,
          headers: { "content-type": "application/json" },
          keepalive: true,
        });
      }
    } catch {
      // analytics must never break the page
    }
  }
}
