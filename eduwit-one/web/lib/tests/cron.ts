// The test schedules are 5-field cron expressions in UTC (one.tests.schedule, set from the Tests page). Pure, so the
// runner and its tests share it. Supports "*", "*/n", "a", "a-b", "a-b/n" and comma lists; no names, no "?" or "L".

const FIELDS: ReadonlyArray<{ min: number; max: number }> = [
  { min: 0, max: 59 }, // minute
  { min: 0, max: 23 }, // hour
  { min: 1, max: 31 }, // day of month
  { min: 1, max: 12 }, // month
  { min: 0, max: 7 }, // day of week, 0 or 7 = Sunday
];

export type Cron = { sets: Array<Set<number>>; domStar: boolean; dowStar: boolean };

function parseField(part: string, min: number, max: number, weekday: boolean): Set<number> {
  const out = new Set<number>();
  for (const item of part.split(",")) {
    const m = /^(\*|\d+(?:-\d+)?)(?:\/(\d+))?$/.exec(item);
    if (!m) throw new Error(`cannot read "${item}"`);
    const step = m[2] ? Number(m[2]) : 1;
    let lo = min;
    let hi = max;
    if (m[1] !== "*") {
      const [a, b] = (m[1] ?? "").split("-").map(Number);
      lo = a ?? NaN;
      hi = b ?? (m[2] ? max : lo);
    }
    if (!(step >= 1) || !(lo >= min) || !(hi <= max) || lo > hi) throw new Error(`"${item}" is out of range`);
    for (let v = lo; v <= hi; v += step) out.add(weekday && v === 7 ? 0 : v);
  }
  return out;
}

/** Parses an expression, or throws with what is wrong. */
export function parseCron(expr: string): Cron {
  const parts = expr.trim().split(/\s+/);
  if (parts.length !== 5) throw new Error("a schedule has 5 fields: minute hour day month weekday");
  const sets = parts.map((part, i) => {
    const f = FIELDS[i] ?? { min: 0, max: 0 };
    return parseField(part, f.min, f.max, i === 4);
  });
  return { sets, domStar: parts[2] === "*", dowStar: parts[4] === "*" };
}

/** Whether the minute of `at` (UTC) matches. Day of month and weekday combine as in cron: either, when both are set. */
export function cronMatches(cron: Cron, at: Date): boolean {
  const has = (i: number, v: number) => cron.sets[i]?.has(v) ?? false;
  if (!has(0, at.getUTCMinutes()) || !has(1, at.getUTCHours()) || !has(3, at.getUTCMonth() + 1)) return false;
  const d = has(2, at.getUTCDate());
  const w = has(4, at.getUTCDay());
  if (cron.domStar && cron.dowStar) return true;
  if (cron.domStar) return w;
  if (cron.dowStar) return d;
  return d || w;
}

/** The latest scheduled minute at or before `now`, looking back at most `days` days; null if none. */
export function lastScheduled(cron: Cron, now: Date, days = 8): Date | null {
  const t = new Date(now);
  t.setUTCSeconds(0, 0);
  for (let i = 0; i <= days * 24 * 60; i++) {
    if (cronMatches(cron, t)) return t;
    t.setUTCMinutes(t.getUTCMinutes() - 1);
  }
  return null;
}

/**
 * A test is due when its latest scheduled minute is after its last run started (a run missed while the app was down
 * runs once, not once per missed slot), or when someone pressed "Run now".
 */
export function testDue(schedule: string, lastStartedAt: string | null, now: Date): boolean {
  const slot = lastScheduled(parseCron(schedule), now);
  if (!slot) return false;
  return !lastStartedAt || Date.parse(lastStartedAt) < slot.getTime();
}
