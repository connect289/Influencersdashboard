"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Abuse controls shown in every verification form (spec 7.2): a honeypot field and Cloudflare Turnstile. Turnstile only
 * loads when a real site key is configured (S-13); otherwise the server mocks the check outside production.
 */
const RAW_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
// Cloudflare test site keys (1x…/2x…/3x…) pair with test secrets the server mocks; no widget is loaded for them.
const SITE_KEY = RAW_KEY && !/^[123]x0{20}A{2}$/.test(RAW_KEY) ? RAW_KEY : undefined;

declare global {
  interface Window {
    turnstile?: {
      render(el: HTMLElement, opts: Record<string, unknown>): string;
      reset(id?: string): void;
      remove(id: string): void;
    };
  }
}

let scriptPromise: Promise<void> | null = null;
function loadScript(): Promise<void> {
  scriptPromise ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error("turnstile"));
    document.head.appendChild(s);
  });
  return scriptPromise;
}

/**
 * `ready()` resolves with the token (waiting up to 5 s for the challenge to finish; undefined when Turnstile is not
 * configured or fails to load, which the server then judges), plus the widget to render and `reset()` after a refusal.
 */
export function useTurnstile(): { ready: () => Promise<string | undefined>; widget: React.ReactNode; reset: () => void } {
  const [, setToken] = useState<string | undefined>(undefined);
  const latest = useRef<string | undefined>(undefined);
  const el = useRef<HTMLDivElement>(null);
  const id = useRef<string | null>(null);
  useEffect(() => {
    if (!SITE_KEY || !el.current) return;
    let cancelled = false;
    loadScript()
      .then(() => {
        if (cancelled || !el.current || !window.turnstile) return;
        id.current = window.turnstile.render(el.current, {
          sitekey: SITE_KEY,
          appearance: "interaction-only",
          callback: (t: string) => {
            latest.current = t;
            setToken(t);
          },
          "expired-callback": () => {
            latest.current = undefined;
            setToken(undefined);
          },
        });
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      if (id.current) window.turnstile?.remove(id.current);
    };
  }, []);
  return {
    ready: async () => {
      if (!SITE_KEY) return undefined;
      for (let i = 0; i < 25 && !latest.current; i++) await new Promise((r) => setTimeout(r, 200));
      return latest.current;
    },
    widget: SITE_KEY ? <div ref={el} className="min-h-0" /> : null,
    reset: () => {
      latest.current = undefined;
      setToken(undefined);
      if (id.current) window.turnstile?.reset(id.current);
    },
  };
}

/** Hidden from people (and assistive tech); bots that fill every field reveal themselves. */
export function Honeypot({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div aria-hidden="true" className="absolute -left-[9999px] h-px w-px overflow-hidden">
      <label>
        Website
        <input type="text" name="website" tabIndex={-1} autoComplete="off" value={value} onChange={(e) => onChange(e.target.value)} />
      </label>
    </div>
  );
}
