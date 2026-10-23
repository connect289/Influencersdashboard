import "server-only";
import { timingSafeEqual } from "node:crypto";
import { bootEnv } from "./env.ts";

/**
 * The internal routes' bearer check (spec §13): the database's job calls carry one_internal_key from Vault; the app
 * holds the same value as ONE_INTERNAL_KEY. Constant-time compare; no key configured means every call is refused.
 */
export function internalAuthorized(request: Request): boolean {
  const key = bootEnv().ONE_INTERNAL_KEY;
  const header = request.headers.get("authorization") ?? "";
  if (!key || !header.startsWith("Bearer ")) return false;
  const given = Buffer.from(header.slice(7));
  const want = Buffer.from(key);
  return given.length === want.length && timingSafeEqual(given, want);
}
