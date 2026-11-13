/**
 * Pure parts of /api/health (tested): the verification-code ceilings as the oversight system reads them (D-095).
 */
interface CodesHealth {
  last_hour?: number;
  last_24h?: number;
  hourly_cap?: number;
  daily_cap?: number;
  at_cap?: "hourly" | "daily" | null;
  refused_24h?: { hourly?: number; daily?: number };
  last_refused_at?: string | null;
}

/** ok = no ceiling reached now and no refusal in the last 24 hours (counts only; no addresses). */
export function codesCheck(raw: unknown) {
  const c = (raw && typeof raw === "object" ? raw : {}) as CodesHealth;
  const refusedHourly = Number(c.refused_24h?.hourly ?? 0);
  const refusedDaily = Number(c.refused_24h?.daily ?? 0);
  return {
    ok: !c.at_cap && refusedHourly === 0 && refusedDaily === 0,
    at_cap: c.at_cap ?? null,
    last_hour: c.last_hour ?? null,
    last_24h: c.last_24h ?? null,
    hourly_cap: c.hourly_cap ?? null,
    daily_cap: c.daily_cap ?? null,
    ceiling_refusals_24h: { hourly: refusedHourly, daily: refusedDaily },
    last_refused_at: c.last_refused_at ?? null,
  };
}
