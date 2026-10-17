/**
 * Content Security Policy builder (D-025). Static public pages: no nonces (they are prerendered and edge-cached);
 * Next's inline RSC payload scripts require 'unsafe-inline' there, so every other directive is strict and hosts are
 * allow-listed. Dynamic sensitive routes (account, admin) get a per-request nonce with 'strict-dynamic'.
 */
export interface CspOptions {
  nonce?: string;
  dev?: boolean;
  supabaseUrl?: string;
}

const ANALYTICS_SCRIPT = ["https://www.googletagmanager.com", "https://connect.facebook.net", "https://www.clarity.ms"];
const ANALYTICS_CONNECT = [
  "https://www.google-analytics.com",
  "https://*.google-analytics.com",
  "https://*.analytics.google.com",
  "https://www.facebook.com",
  "https://*.clarity.ms",
];
const TURNSTILE = "https://challenges.cloudflare.com";

export function buildCsp(o: CspOptions = {}): string {
  const script = o.nonce
    ? [`'self'`, `'nonce-${o.nonce}'`, `'strict-dynamic'`, TURNSTILE, ...ANALYTICS_SCRIPT]
    : [`'self'`, `'unsafe-inline'`, TURNSTILE, ...ANALYTICS_SCRIPT];
  if (o.dev) script.push(`'unsafe-eval'`);
  const connect = [`'self'`, ...ANALYTICS_CONNECT, TURNSTILE];
  if (o.supabaseUrl) connect.push(new URL(o.supabaseUrl).origin);
  if (o.dev) connect.push("ws:", "http://127.0.0.1:54321");
  const d: Record<string, string[]> = {
    "default-src": [`'self'`],
    "script-src": script,
    "style-src": [`'self'`, `'unsafe-inline'`],
    "img-src": [
      `'self'`,
      "data:",
      "blob:",
      "https://www.facebook.com",
      "https://*.google-analytics.com",
      "https://*.googletagmanager.com",
      "https://*.clarity.ms",
    ],
    "font-src": [`'self'`],
    "connect-src": connect,
    "frame-src": [TURNSTILE, "https://www.youtube-nocookie.com"],
    "media-src": [`'self'`],
    "worker-src": [`'self'`, "blob:"],
    "object-src": [`'none'`],
    "base-uri": [`'self'`],
    "form-action": [`'self'`],
    "frame-ancestors": [`'none'`],
    "manifest-src": [`'self'`],
  };
  const policy = Object.entries(d).map(([k, v]) => `${k} ${v.join(" ")}`);
  if (!o.dev) policy.push("upgrade-insecure-requests");
  return policy.join("; ");
}

/** Security headers applied to every response (CSP is added separately). */
export const SECURITY_HEADERS: Record<string, string> = {
  "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
  "Cross-Origin-Opener-Policy": "same-origin",
};
