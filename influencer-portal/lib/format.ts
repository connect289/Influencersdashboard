// Display formatting (spec 2.4, 2.5, 17): Indian number format, IST, DD MMM YYYY dates, relative times, Indian FY.
// Money is stored as integer paise; these functions only format it.
export const IST = "Asia/Kolkata";

const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});
const inrWhole = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0,
});
const num = new Intl.NumberFormat("en-IN");

/** ₹1,23,456.00 from paise. Accepts bigint so ledger values never pass through floats before formatting. */
export function formatPaise(paise: bigint | number, opts: { whole?: boolean } = {}): string {
  const p = typeof paise === "bigint" ? paise : BigInt(Math.trunc(paise));
  const negative = p < 0n;
  const abs = negative ? -p : p;
  const rupees = abs / 100n;
  const rest = Number(abs % 100n);
  // Group the rupee part with Indian grouping via Intl on the integer, then append the paise digits exactly.
  const grouped = num.format(rupees);
  const text = opts.whole
    ? `₹${num.format(rest >= 50 ? rupees + 1n : rupees)}`
    : `₹${grouped}.${String(rest).padStart(2, "0")}`;
  return negative ? `-${text}` : text;
}

/** ₹ from a rupee number (catalogue fees come as numeric rupees). */
export function formatRupees(rupees: number, opts: { whole?: boolean } = {}): string {
  return (opts.whole ? inrWhole : inr).format(rupees);
}

export function formatNumber(n: number | bigint): string {
  return num.format(n);
}

/** Compact Indian units: 1.2K, 3.4L (lakh), 1.1Cr (crore). */
export function formatCompact(n: number): string {
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  const fmt = (v: number) => (Math.round(v * 10) / 10).toString().replace(/\.0$/, "");
  if (abs >= 1e7) return `${sign}${fmt(abs / 1e7)}Cr`;
  if (abs >= 1e5) return `${sign}${fmt(abs / 1e5)}L`;
  if (abs >= 1e3) return `${sign}${fmt(abs / 1e3)}K`;
  return `${sign}${abs}`;
}

const dateFmt = new Intl.DateTimeFormat("en-GB", {
  timeZone: IST,
  day: "2-digit",
  month: "short",
  year: "numeric",
});
const timeFmt = new Intl.DateTimeFormat("en-GB", {
  timeZone: IST,
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});

function toDate(value: Date | string | number): Date {
  return value instanceof Date ? value : new Date(value);
}

/** 16 Oct 2026 (IST). */
export function formatDate(value: Date | string | number): string {
  return dateFmt.format(toDate(value));
}

/** 16 Oct 2026, 21:05 IST. */
export function formatDateTime(value: Date | string | number): string {
  const d = toDate(value);
  return `${dateFmt.format(d)}, ${timeFmt.format(d)} IST`;
}

const rtf = new Intl.RelativeTimeFormat("en", { numeric: "auto" });

/** "2 hours ago", "in 3 days". */
export function formatRelative(value: Date | string | number, now: Date = new Date()): string {
  const diff = (toDate(value).getTime() - now.getTime()) / 1000;
  const abs = Math.abs(diff);
  const units: [Intl.RelativeTimeFormatUnit, number][] = [
    ["year", 31536000],
    ["month", 2592000],
    ["week", 604800],
    ["day", 86400],
    ["hour", 3600],
    ["minute", 60],
  ];
  for (const [unit, secs] of units) if (abs >= secs) return rtf.format(Math.round(diff / secs), unit);
  return "just now";
}

/** Calendar parts of an instant in IST. */
export function istParts(value: Date | string | number): {
  year: number;
  month: number;
  day: number;
} {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: IST,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(toDate(value));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  return { year: get("year"), month: get("month"), day: get("day") };
}

/** Indian financial year (1 April – 31 March) of an instant, in IST: "2026-27". */
export function financialYear(value: Date | string | number): string {
  const { year, month } = istParts(value);
  const start = month >= 4 ? year : year - 1;
  return `${start}-${String((start + 1) % 100).padStart(2, "0")}`;
}

/** Quarter of the Indian FY: Q1 = Apr–Jun … Q4 = Jan–Mar. */
export function fyQuarter(value: Date | string | number): "Q1" | "Q2" | "Q3" | "Q4" {
  const { month } = istParts(value);
  if (month >= 4 && month <= 6) return "Q1";
  if (month >= 7 && month <= 9) return "Q2";
  if (month >= 10) return "Q3";
  return "Q4";
}

/** Today's date in IST as YYYY-MM-DD. */
export function istToday(now: Date = new Date()): string {
  return new Date(now.getTime() + 330 * 60_000).toISOString().slice(0, 10);
}
