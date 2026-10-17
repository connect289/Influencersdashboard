/** Indian-style money and number formatting used everywhere fees appear (tabular figures in the UI). */

const inr = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 });
const num = new Intl.NumberFormat("en-IN");

/** ₹1,00,000 */
export function formatInr(n: number): string {
  return inr.format(Math.round(n));
}

/** Compact Indian units: ₹85K, ₹1.2 lakh, ₹1.25 crore (used in ranges, chips and the fee slider). */
export function formatInrCompact(n: number): string {
  const v = Math.round(n);
  if (v >= 1_00_00_000) return `₹${trim(v / 1_00_00_000)} crore`;
  if (v >= 1_00_000) return `₹${trim(v / 1_00_000)} lakh`;
  if (v >= 1_000) return `₹${trim(v / 1_000)}K`;
  return `₹${v}`;
}

function trim(x: number): string {
  return (Math.round(x * 100) / 100).toString();
}

/** "₹85K – ₹1.2 lakh" (or a single value when equal). */
export function formatInrRange(min: number, max: number): string {
  return min === max ? formatInrCompact(min) : `${formatInrCompact(min)} – ${formatInrCompact(max)}`;
}

export function formatCount(n: number): string {
  return num.format(n);
}

/** "2 years", "18 months", "1 year 6 months". */
export function formatDuration(months: number): string {
  if (months % 12 === 0) {
    const y = months / 12;
    return `${y} ${y === 1 ? "year" : "years"}`;
  }
  if (months < 12) return `${months} months`;
  const y = Math.floor(months / 12);
  const m = months % 12;
  return `${y} ${y === 1 ? "year" : "years"} ${m} months`;
}

/** "30 Sep 2026" for "Data last verified". */
export function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });
}
