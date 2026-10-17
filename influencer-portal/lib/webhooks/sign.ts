// Outbound webhooks (spec 18): signed with HMAC-SHA256, retried on a fixed schedule, with a delivery log. The
// signature header is `t=<unix seconds>,v1=<hex hmac of "<t>.<raw body>">`; receivers recompute it with the endpoint
// secret and reject old timestamps. Payloads never carry student contact details. Pure (node:crypto only).
import { createHmac, timingSafeEqual } from "node:crypto";

export const WEBHOOK_EVENTS = [
  "lead.attributed",
  "lead.enrolled",
  "contract.signed",
  "deliverable.live",
  "payout.paid",
  "creator.activated",
] as const;
export type WebhookEvent = (typeof WEBHOOK_EVENTS)[number];

export const SIGNATURE_HEADER = "X-Eduwit-Signature";
/** Seconds after which a receiver should reject a signature. */
export const TOLERANCE_SECONDS = 300;
/** Minutes to wait before attempts 2, 3, … (after the first failure, the second, …). */
export const RETRY_MINUTES = [1, 5, 30, 120, 360, 1440] as const;
export const MAX_ATTEMPTS = RETRY_MINUTES.length + 1;

export function sign(secret: string, timestamp: number, body: string): string {
  return createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");
}

export function signatureHeader(secret: string, timestamp: number, body: string): string {
  return `t=${timestamp},v1=${sign(secret, timestamp, body)}`;
}

/** Receiver-side check (documented for integrators, used in tests). */
export function verify(
  secret: string,
  header: string,
  body: string,
  now: number,
  tolerance = TOLERANCE_SECONDS,
): boolean {
  const m = /^t=(\d+),v1=([0-9a-f]{64})$/.exec(header);
  if (!m) return false;
  const t = Number(m[1]);
  if (Math.abs(now - t) > tolerance) return false;
  const expected = Buffer.from(sign(secret, t, body), "hex");
  const got = Buffer.from(m[2] ?? "", "hex");
  return expected.length === got.length && timingSafeEqual(expected, got);
}

/** When to try again after `attempts` failed attempts, or null to give up. */
export function nextAttemptAt(attempts: number, from: Date): Date | null {
  const minutes = RETRY_MINUTES[attempts - 1];
  return minutes === undefined ? null : new Date(from.getTime() + minutes * 60_000);
}

/** Keys that must never leave the portal in a webhook body (student contact details and secrets). */
const FORBIDDEN_KEY = /(^|_)(phone|email|whatsapp|pan|account|ifsc|secret|token|password)(_|$)/i;

/** Throws if a payload carries a forbidden key anywhere (defence in depth; the database builds payloads). */
export function assertSafePayload(data: unknown, path = "data"): void {
  if (Array.isArray(data)) data.forEach((v, i) => assertSafePayload(v, `${path}[${i}]`));
  else if (data && typeof data === "object")
    for (const [k, v] of Object.entries(data)) {
      if (FORBIDDEN_KEY.test(k)) throw new Error(`webhook payload must not contain ${path}.${k}`);
      assertSafePayload(v, `${path}.${k}`);
    }
}

/** 2xx is delivered; 408, 425, 429 and 5xx are retried; other 4xx are permanent failures. */
export function outcome(status: number | null): "delivered" | "retry" | "failed" {
  if (status === null) return "retry";
  if (status >= 200 && status < 300) return "delivered";
  if (status === 408 || status === 425 || status === 429 || status >= 500) return "retry";
  return "failed";
}
