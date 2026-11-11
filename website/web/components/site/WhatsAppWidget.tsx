"use client";

import { useEffect } from "react";
import { WHATSAPP_WIDGET_ID } from "@/lib/widget-id";

export const WA_WIDGET_SRC = "https://d3mkw6s8thqya7.cloudfront.net/integration-plugin.js";

/**
 * AiSensy WhatsApp chat button (D-091), the owner's snippet as a script element: injected once, after the page has
 * loaded and the browser is idle, so it never delays the page. The widget id comes from Admin → Flags and settings.
 */
export function WhatsAppWidget({ widgetId }: { widgetId: string }) {
  useEffect(() => {
    if (!WHATSAPP_WIDGET_ID.test(widgetId) || document.getElementById("aisensy-wa-widget")) return;
    let cancel = () => {};
    const inject = () => {
      const s = document.createElement("script");
      s.type = "text/javascript";
      s.src = WA_WIDGET_SRC;
      s.id = "aisensy-wa-widget";
      s.setAttribute("widget-id", widgetId);
      s.async = true;
      document.head.appendChild(s);
    };
    const schedule = () => {
      if (typeof window.requestIdleCallback === "function") {
        const id = window.requestIdleCallback(inject, { timeout: 4000 });
        cancel = () => window.cancelIdleCallback(id);
      } else {
        const id = window.setTimeout(inject, 1500);
        cancel = () => window.clearTimeout(id);
      }
    };
    if (document.readyState === "complete") schedule();
    else window.addEventListener("load", schedule, { once: true });
    return () => {
      window.removeEventListener("load", schedule);
      cancel();
    };
  }, [widgetId]);
  return null;
}
