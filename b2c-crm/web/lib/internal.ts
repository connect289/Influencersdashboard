import { timingSafeEqual } from "node:crypto";

/** The pg_cron jobs call /api/internal/* with x-internal-key (Vault secret b2c_internal_key = env B2C_INTERNAL_KEY). */
export function internalKeyOk(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected || expected.length < 32) return false;
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
