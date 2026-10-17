"use client";

import { useSyncExternalStore } from "react";
import { CONSENT_COOKIE, parseConsent, serialiseConsent, type ConsentState } from "@/lib/consent";

const listeners = new Set<() => void>();
let snap: ConsentState | null | undefined;

function readCookie(): ConsentState | null {
  const m = document.cookie.match(new RegExp(`(?:^|; )${CONSENT_COOKIE}=([^;]*)`));
  return parseConsent(m?.[1]);
}

export function getConsent(): ConsentState | null {
  if (snap === undefined) snap = typeof document === "undefined" ? null : readCookie();
  return snap;
}

export function setConsent(analytics: boolean, marketing: boolean) {
  const v = serialiseConsent({ analytics, marketing });
  document.cookie = `${CONSENT_COOKIE}=${v}; Path=/; Max-Age=${60 * 60 * 24 * 180}; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}`;
  snap = parseConsent(v);
  listeners.forEach((l) => l());
}

export function useConsent(): { state: ConsentState | null; ready: boolean } {
  const state = useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => getConsent() ?? null,
    () => undefined as unknown as ConsentState | null,
  );
  return { state: state ?? null, ready: state !== undefined };
}

export function onConsentChange(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}
