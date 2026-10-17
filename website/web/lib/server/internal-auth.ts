import "server-only";
import { timingSafeEqual } from "node:crypto";
import { cronSecret, internalKey } from "./env";

function same(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

/**
 * Bearer check for machine endpoints (pg_cron → /api/internal/*, Vercel Cron, oversight → /api/metrics).
 * Accepts the website's internal key or Vercel's CRON_SECRET. Constant-time compare.
 */
export function isInternal(req: Request): boolean {
  const got = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!got) return false;
  const cron = cronSecret();
  return same(got, internalKey()) || (!!cron && same(got, cron));
}
