/**
 * Validation of the site-wide ceilings an admin can change (web14: code_send_hourly_cap, web_advisor_daily_cap). The
 * database enforces them and keeps them super-admin only; this only gives the editor a clear message.
 */
export function ceilingError(key: string, value: unknown): string | null {
  if (key === "code_send_hourly_cap") {
    const ok = typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 1_000_000;
    return ok ? null : "Use a whole number of codes per hour (0 stops all sends).";
  }
  if (key === "web_advisor_daily_cap") {
    const v = value as { turns?: unknown; cost_usd?: unknown } | null;
    const num = (x: unknown) => typeof x === "number" && Number.isFinite(x) && x >= 0;
    const ok = !!v && typeof v === "object" && !Array.isArray(v) && num(v.turns) && num(v.cost_usd);
    return ok ? null : 'Use {"turns": 2000, "cost_usd": 25} (numbers of zero or more).';
  }
  return null;
}
