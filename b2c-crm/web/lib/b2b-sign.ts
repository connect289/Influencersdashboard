import { createHmac, timingSafeEqual } from "node:crypto";

// Signing for the B2B link (docs/b2c-contract.md §1 and §4): HMAC-SHA256 over "<timestamp>.<raw body>", sent as
// "sha256=<hex>", timestamps within 5 minutes. The same secret signs both directions. Unit-tested in b2b-sign.test.ts.

export const MAX_SKEW_SECONDS = 300;

export function sign(rawBody: string, timestamp: string, secret: string): string {
  return "sha256=" + createHmac("sha256", secret).update(`${timestamp}.${rawBody}`, "utf8").digest("hex");
}

export type VerifyResult = { ok: true } | { ok: false; reason: "missing" | "timestamp" | "signature" };

/** Verifies a request from the B2B CRM over the exact raw bytes it sent, in constant time. */
export function verify(rawBody: string, timestamp: string | null, signature: string | null, secret: string, nowSeconds = Date.now() / 1000): VerifyResult {
  if (!timestamp || !signature) return { ok: false, reason: "missing" };
  if (!/^\d{1,12}$/.test(timestamp) || Math.abs(nowSeconds - Number(timestamp)) > MAX_SKEW_SECONDS) return { ok: false, reason: "timestamp" };
  const expected = Buffer.from(sign(rawBody, timestamp, secret));
  const given = Buffer.from(signature);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return { ok: false, reason: "signature" };
  return { ok: true };
}

/** Headers for a signed B2C → B2B event (POST /v1/events/b2ccrm). */
export function signedHeaders(rawBody: string, secret: string, nowSeconds = Math.floor(Date.now() / 1000)): Record<string, string> {
  const ts = String(nowSeconds);
  return { "content-type": "application/json", "x-eduwit-timestamp": ts, "x-eduwit-signature": sign(rawBody, ts, secret) };
}

/**
 * A GET has no body, so the signed text is the request target instead: "GET <path>?<query>", exactly as requested
 * (GET /v1/events). Signature: "sha256=" + HMAC-SHA256 of "<timestamp>.GET /v1/events?since=120&limit=200".
 */
export function requestTarget(method: string, pathAndQuery: string): string {
  return `${method.toUpperCase()} ${pathAndQuery}`;
}

export function verifyGet(pathAndQuery: string, timestamp: string | null, signature: string | null, secret: string, nowSeconds = Date.now() / 1000): VerifyResult {
  return verify(requestTarget("GET", pathAndQuery), timestamp, signature, secret, nowSeconds);
}

/** Headers for a signed GET (what the B2B CRM sends to GET /v1/events; also used by the tests). */
export function signedGetHeaders(pathAndQuery: string, secret: string, nowSeconds = Math.floor(Date.now() / 1000)): Record<string, string> {
  const ts = String(nowSeconds);
  return { "x-eduwit-timestamp": ts, "x-eduwit-signature": sign(requestTarget("GET", pathAndQuery), ts, secret) };
}
