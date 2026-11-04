import { createHash, timingSafeEqual } from "node:crypto";

/**
 * Internal routes (M34f): /v1/ai/tick answers only a caller holding the worker key (the server's AI_WORKER_KEY). The database
 * sends it as "Authorization: Bearer <key>" when it wakes the worker (b2b.ai_wake, m34f); x-internal-key is accepted too.
 */

/** The key a request presents: the Bearer token, else x-internal-key. */
export function presentedKey(headers: Headers): string {
  const m = /^Bearer\s+(\S+)$/i.exec((headers.get("authorization") ?? "").trim());
  return (m?.[1] ?? headers.get("x-internal-key") ?? "").trim();
}

/** Whether the request carries exactly the expected key; compared in constant time (hashes of equal length). */
export function carriesKey(headers: Headers, expected: string | undefined): boolean {
  const given = presentedKey(headers);
  if (!given || !expected) return false;
  return timingSafeEqual(createHash("sha256").update(given).digest(), createHash("sha256").update(expected).digest());
}
