import "server-only";
import { env } from "@/lib/env";
import { safeEqual } from "@/lib/security";

/** True when the request carries the internal key (x-internal-key or Bearer). Constant-time comparison. */
export function hasInternalKey(headers: Headers): boolean {
  const given =
    headers.get("x-internal-key") ?? headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  return given.length > 0 && safeEqual(given, env().INF_INTERNAL_API_KEY);
}
