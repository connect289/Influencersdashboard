/**
 * Attribution capture (spec 9.2): UTM parameters, click ids, referrer, landing page and creator code, persisted
 * first-party (first touch + last touch) and attached to every lead. No personal data; never used to gate access.
 */
export interface Touch {
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_content?: string;
  utm_term?: string;
  gclid?: string;
  gbraid?: string;
  wbraid?: string;
  fbclid?: string;
  /** creator / referral code from ?code= or /c/<handle> pages */
  code?: string;
  /** landing path only (no query string, which may carry personal data) */
  landing?: string;
  /** referrer host only */
  referrer?: string;
  at: string;
}

const KEYS = [
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
  "utm_term",
  "gclid",
  "gbraid",
  "wbraid",
  "fbclid",
] as const;
const SAFE = /^[\w\-.~:+%@ ]{1,200}$/;

/** Extracts a touch from a URL; returns null when the visit carries no attribution signal. */
export function touchFromUrl(url: URL, referrer?: string | null, now = new Date()): Touch | null {
  const t: Touch = { at: now.toISOString() };
  let signal = false;
  for (const k of KEYS) {
    const v = url.searchParams.get(k)?.trim();
    if (v && SAFE.test(v)) {
      t[k] = v.slice(0, 200);
      signal = true;
    }
  }
  const code = (url.searchParams.get("code") ?? url.searchParams.get("ref"))?.trim().toLowerCase();
  if (code && /^[a-z0-9_-]{2,40}$/.test(code)) {
    t.code = code;
    signal = true;
  }
  const creator = /^\/c\/([a-z0-9-]{2,40})(?:\/|$)/i.exec(url.pathname);
  if (creator && !t.code) {
    t.code = creator[1]!.toLowerCase();
    signal = true;
  }
  const refHost = safeHost(referrer);
  if (refHost && refHost !== url.host) {
    t.referrer = refHost;
    signal = true;
  }
  if (!signal) return null;
  t.landing = url.pathname.slice(0, 200);
  return t;
}

function safeHost(ref?: string | null): string | undefined {
  if (!ref) return undefined;
  try {
    return new URL(ref).host.toLowerCase();
  } catch {
    return undefined;
  }
}

/** Paid-click detection used for the B2C sales lane and Meta/Google conversion events. */
export function isPaid(t: Touch | null | undefined): boolean {
  return !!(
    t?.gclid ||
    t?.gbraid ||
    t?.wbraid ||
    t?.fbclid ||
    /^(cpc|ppc|paid|paidsocial|paid_social)$/i.test(t?.utm_medium ?? "")
  );
}

export function encodeTouch(t: Touch): string {
  return Buffer.from(JSON.stringify(t)).toString("base64url");
}

export function decodeTouch(v: string | undefined | null): Touch | null {
  if (!v || v.length > 3000) return null;
  try {
    const o = JSON.parse(Buffer.from(v, "base64url").toString("utf8")) as Touch;
    return typeof o === "object" && o && typeof o.at === "string" ? o : null;
  } catch {
    return null;
  }
}

/** Maps first/last touch onto the lead_intake keys (first-touch fields are write-once in lead_intake). */
export function attributionToLead(first: Touch | null, last: Touch | null): Record<string, unknown> {
  const t = first ?? last;
  if (!t) return {};
  const click: Record<string, string> = {};
  for (const k of ["gclid", "gbraid", "wbraid", "fbclid"] as const) {
    const v = last?.[k] ?? first?.[k];
    if (v) click[k] = v;
  }
  return {
    utm_source: t.utm_source,
    utm_medium: t.utm_medium,
    utm_campaign: t.utm_campaign,
    utm_content: t.utm_content,
    utm_term: t.utm_term,
    click_ids: Object.keys(click).length ? click : undefined,
    landing_url: t.landing,
    referrer_url: t.referrer,
    referred_by_code: last?.code ?? first?.code,
  };
}
