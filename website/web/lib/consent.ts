/**
 * Cookie/analytics consent (spec 13.3, DPDP): necessary (always on), analytics (GA4, Clarity), marketing (Meta Pixel).
 * Stored first-party as a small versioned cookie so the server can honour it (Conversions API) — never inferred.
 */
export const CONSENT_COOKIE = "ew_consent";
export const CONSENT_VERSION = 1;

export interface ConsentState {
  v: number;
  analytics: boolean;
  marketing: boolean;
  /** ISO time of the choice */
  at: string;
}

export function parseConsent(raw: string | undefined | null): ConsentState | null {
  if (!raw) return null;
  try {
    const o = JSON.parse(decodeURIComponent(raw)) as Partial<ConsentState>;
    if (
      o.v !== CONSENT_VERSION ||
      typeof o.analytics !== "boolean" ||
      typeof o.marketing !== "boolean" ||
      typeof o.at !== "string"
    )
      return null;
    return { v: o.v, analytics: o.analytics, marketing: o.marketing, at: o.at };
  } catch {
    return null;
  }
}

export function serialiseConsent(s: Omit<ConsentState, "v" | "at">, now = new Date()): string {
  return encodeURIComponent(
    JSON.stringify({ v: CONSENT_VERSION, analytics: s.analytics, marketing: s.marketing, at: now.toISOString() }),
  );
}

/** No choice yet ⇒ nothing optional runs. */
export function allowed(s: ConsentState | null, category: "analytics" | "marketing"): boolean {
  return !!s && s[category];
}
