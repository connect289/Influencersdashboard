"use client";

import Link from "next/link";
import { useState } from "react";
import { Cookie } from "lucide-react";
import { setConsent, useConsent } from "@/lib/client/consent-store";

/**
 * Cookie consent (spec 13.3), honouring the Cookie Policy. Equal-weight choices; nothing optional loads before a choice.
 * "Choose" reveals per-category switches inline (no extra library).
 */
export function ConsentBanner() {
  const { state, ready } = useConsent();
  const [choose, setChoose] = useState(false);
  const [analytics, setAnalytics] = useState(true);
  const [marketing, setMarketing] = useState(false);
  // The banner disappears with the button that had focus; hand keyboard focus to the main content instead of losing it.
  const decide = (a: boolean, m: boolean, from: HTMLElement) => {
    const hadFocus = from.closest("[aria-label='Cookie preferences']")?.contains(document.activeElement);
    setConsent(a, m);
    const main = document.getElementById("main");
    if (hadFocus && main) {
      if (!main.hasAttribute("tabindex")) main.setAttribute("tabindex", "-1");
      main.focus({ preventScroll: true });
    }
  };
  // Mounted by the public (site) layout only. The banner is server-rendered so it paints with the page (no late paint,
  // no layout shift); the boot script hides it before first paint when a choice is already stored.
  if (ready && state) return null;
  return (
    <section
      aria-label="Cookie preferences"
      className="consent-banner glass-strong fixed inset-x-3 bottom-20 z-[var(--z-toast)] mx-auto max-w-2xl rounded-[var(--radius-xl)] p-4 sm:p-5 md:bottom-4"
    >
      <div className="flex gap-3">
        <Cookie className="text-amber-text mt-0.5 size-5 shrink-0" aria-hidden />
        <div className="grid gap-3 text-sm">
          <p className="text-text">
            We use necessary cookies to run this site. With your permission we also use analytics (to improve the site)
            and marketing cookies (to measure our ads). See our{" "}
            <Link href="/legal/cookie-policy" className="text-accent font-medium underline underline-offset-4">
              Cookie Policy
            </Link>
            .
          </p>
          {choose ? (
            <fieldset className="grid gap-2">
              <legend className="sr-only">Choose cookie categories</legend>
              <label className="text-muted flex items-center gap-2">
                <input type="checkbox" checked disabled className="size-4" /> Necessary (always on)
              </label>
              <label className="text-text flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={analytics}
                  onChange={(e) => setAnalytics(e.target.checked)}
                  className="size-4 accent-[var(--primary)]"
                />{" "}
                Analytics
              </label>
              <label className="text-text flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={marketing}
                  onChange={(e) => setMarketing(e.target.checked)}
                  className="size-4 accent-[var(--primary)]"
                />{" "}
                Marketing
              </label>
            </fieldset>
          ) : null}
          <div className="flex flex-wrap gap-2">
            {choose ? (
              <button
                type="button"
                onClick={(e) => decide(analytics, marketing, e.currentTarget)}
                className="bg-primary text-on-primary h-10 rounded-full px-4 font-semibold"
              >
                Save choices
              </button>
            ) : (
              <>
                <button
                  type="button"
                  onClick={(e) => decide(true, true, e.currentTarget)}
                  className="bg-primary text-on-primary h-10 rounded-full px-4 font-semibold"
                >
                  Accept all
                </button>
                <button
                  type="button"
                  onClick={(e) => decide(false, false, e.currentTarget)}
                  className="border-border-strong text-text h-10 rounded-full border px-4 font-semibold"
                >
                  Only necessary
                </button>
                <button
                  type="button"
                  onClick={() => setChoose(true)}
                  className="text-accent h-10 rounded-full px-3 font-medium underline-offset-4 hover:underline"
                >
                  Choose
                </button>
              </>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
