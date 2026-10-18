// Date ranges for every dashboard (spec 12): presets for today, the last 7, 30 or 90 days, this month, last month and
// this financial year, or a custom range. Dates are IST calendar days, inclusive at both ends. The comparison period
// is the same number of days immediately before the range. Pure.
import { z } from "zod";

export const RANGE_PRESETS = ["today", "7d", "30d", "90d", "this_month", "last_month", "this_fy", "custom"] as const;
export type RangePreset = (typeof RANGE_PRESETS)[number];
export const DEFAULT_PRESET: RangePreset = "30d";
/** The longest custom range (about three years), so one request stays cheap. */
export const MAX_RANGE_DAYS = 1_100;

export type Bucket = "day" | "week" | "month";

export interface DateRange {
  preset: RangePreset;
  /** First IST day (YYYY-MM-DD), inclusive. */
  from: string;
  /** Last IST day (YYYY-MM-DD), inclusive. */
  to: string;
  days: number;
  previous: { from: string; to: string };
  bucket: Bucket;
  compare: boolean;
}

const isoDate = z.iso.date();
const DAY = 86_400_000;

export const addDays = (d: string, n: number): string =>
  new Date(Date.parse(`${d}T00:00:00Z`) + n * DAY).toISOString().slice(0, 10);
export const daysBetween = (from: string, to: string): number =>
  Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY) + 1;

/** First day of the Indian financial year (1 April) that `d` falls in. */
export function fyStart(d: string): string {
  const [y, m] = d.split("-").map(Number) as [number, number];
  return `${m >= 4 ? y : y - 1}-04-01`;
}

/** Day buckets up to two months, weeks up to a year, months beyond. */
export function bucketFor(days: number): Bucket {
  if (days <= 62) return "day";
  if (days <= 366) return "week";
  return "month";
}

function span(preset: Exclude<RangePreset, "custom">, today: string): { from: string; to: string } {
  switch (preset) {
    case "today":
      return { from: today, to: today };
    case "7d":
      return { from: addDays(today, -6), to: today };
    case "30d":
      return { from: addDays(today, -29), to: today };
    case "90d":
      return { from: addDays(today, -89), to: today };
    case "this_month":
      return { from: `${today.slice(0, 7)}-01`, to: today };
    case "last_month": {
      const first = `${today.slice(0, 7)}-01`;
      const last = addDays(first, -1);
      return { from: `${last.slice(0, 7)}-01`, to: last };
    }
    case "this_fy":
      return { from: fyStart(today), to: today };
  }
}

export function makeRange(preset: RangePreset, today: string, custom?: { from?: string; to?: string }, compare = true) {
  let from: string;
  let to: string;
  if (preset === "custom") {
    const f = isoDate.safeParse(custom?.from);
    const t = isoDate.safeParse(custom?.to);
    if (!f.success || !t.success) return makeRange(DEFAULT_PRESET, today, undefined, compare);
    to = t.data > today ? today : t.data;
    from = f.data > to ? to : f.data;
    if (daysBetween(from, to) > MAX_RANGE_DAYS) from = addDays(to, -(MAX_RANGE_DAYS - 1));
  } else ({ from, to } = span(preset, today));
  const days = daysBetween(from, to);
  const range: DateRange = {
    preset,
    from,
    to,
    days,
    previous: { from: addDays(from, -days), to: addDays(from, -1) },
    bucket: bucketFor(days),
    compare,
  };
  return range;
}

/** Reads `range`, `from`, `to` and `compare` from the URL; anything unknown falls back to the default. */
export function parseRange(search: Record<string, string | undefined>, today: string): DateRange {
  const preset = (RANGE_PRESETS as readonly string[]).includes(search.range ?? "")
    ? (search.range as RangePreset)
    : DEFAULT_PRESET;
  return makeRange(preset, today, { from: search.from, to: search.to }, search.compare !== "0");
}

/** URL parameters for a range (the default preset with comparison on writes nothing). */
export function rangeParams(r: Pick<DateRange, "preset" | "from" | "to" | "compare">): Record<string, string> {
  const out: Record<string, string> = {};
  if (r.preset !== DEFAULT_PRESET) out.range = r.preset;
  if (r.preset === "custom") Object.assign(out, { from: r.from, to: r.to });
  if (!r.compare) out.compare = "0";
  return out;
}

/** The start of the bucket a day falls in: the day, its Monday, or the 1st of its month. */
export function bucketStart(d: string, bucket: Bucket): string {
  if (bucket === "day") return d;
  if (bucket === "month") return `${d.slice(0, 7)}-01`;
  const dow = new Date(`${d}T00:00:00Z`).getUTCDay();
  return addDays(d, -((dow + 6) % 7));
}

/** Every bucket start from `from` to `to`, so a series has no gaps. */
export function bucketStarts(from: string, to: string, bucket: Bucket): string[] {
  const out: string[] = [];
  let cur = bucketStart(from, bucket);
  while (cur <= to) {
    out.push(cur);
    cur =
      bucket === "day"
        ? addDays(cur, 1)
        : bucket === "week"
          ? addDays(cur, 7)
          : (() => {
              const [y, m] = cur.split("-").map(Number) as [number, number];
              return new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10);
            })();
  }
  return out;
}

/** Fills a sparse series (bucket start → value) with zeros for every bucket in the range. */
export function fillSeries(
  points: readonly { at: string; value: number }[],
  from: string,
  to: string,
  bucket: Bucket,
): { at: string; value: number }[] {
  const by = new Map<string, number>();
  for (const p of points) {
    const k = bucketStart(p.at.slice(0, 10), bucket);
    by.set(k, (by.get(k) ?? 0) + p.value);
  }
  return bucketStarts(from, to, bucket).map((at) => ({ at, value: by.get(at) ?? 0 }));
}
