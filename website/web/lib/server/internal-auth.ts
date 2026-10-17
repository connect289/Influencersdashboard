import "server-only";
import { timingSafeEqual } from "node:crypto";
import { internalKey } from "./env";

/** Bearer check for machine endpoints (pg_cron → /api/internal/*, oversight → /api/metrics). Constant-time compare. */
export function isInternal(req: Request): boolean {
  const got = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const want = internalKey();
  const a = Buffer.from(got);
  const b = Buffer.from(want);
  return a.length === b.length && timingSafeEqual(a, b);
}
