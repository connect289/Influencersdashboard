"use client";

import { useEffect } from "react";
import { allowed } from "@/lib/consent";
import { getConsent, onConsentChange } from "@/lib/client/consent-store";

/**
 * Loads GA4, Meta Pixel and Microsoft Clarity only after the matching consent, and only when their ids are configured
 * (spec 13.3). Scripts are injected once; withdrawing consent stops further loading and is honoured on next page load.
 */
export function AnalyticsLoader({ ga4, pixel, clarity }: { ga4?: string; pixel?: string; clarity?: string }) {
  useEffect(() => {
    const loaded = new Set<string>();
    const inject = (id: string, src: string, onload?: () => void) => {
      if (loaded.has(id) || document.getElementById(id)) return;
      loaded.add(id);
      const s = document.createElement("script");
      s.id = id;
      s.async = true;
      s.src = src;
      if (onload) s.onload = onload;
      document.head.appendChild(s);
    };
    const apply = () => {
      const c = getConsent();
      if (ga4 && allowed(c, "analytics") && /^G-[A-Z0-9]{4,12}$/.test(ga4)) {
        window.dataLayer = window.dataLayer ?? [];
        window.gtag = function gtag() {
          // eslint-disable-next-line prefer-rest-params
          window.dataLayer!.push(arguments);
        };
        window.gtag("js", new Date());
        window.gtag("config", ga4, { anonymize_ip: true, send_page_view: true });
        inject("ew-ga4", `https://www.googletagmanager.com/gtag/js?id=${ga4}`);
      }
      if (pixel && allowed(c, "marketing") && /^\d{6,20}$/.test(pixel) && !window.fbq) {
        const q: unknown[] = [];
        const fbq = function fbq(...args: unknown[]) {
          q.push(args);
        } as ((...a: unknown[]) => void) & { queue?: unknown[]; loaded?: boolean; version?: string; push?: unknown };
        fbq.queue = q;
        fbq.loaded = true;
        fbq.version = "2.0";
        window.fbq = fbq;
        window.fbq("init", pixel);
        window.fbq("track", "PageView");
        inject("ew-pixel", "https://connect.facebook.net/en_US/fbevents.js");
      }
      if (clarity && allowed(c, "analytics") && /^[a-z0-9]{6,20}$/i.test(clarity)) {
        inject("ew-clarity", `https://www.clarity.ms/tag/${clarity}`);
      }
    };
    apply();
    return onConsentChange(apply);
  }, [ga4, pixel, clarity]);
  return null;
}
