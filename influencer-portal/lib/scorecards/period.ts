// Scorecard periods are calendar months in IST, written "YYYY-MM". Pure.

/** First and last day of a "YYYY-MM" period. */
export function periodRange(period: string): { from: string; to: string } {
  const [y, m] = period.split("-").map(Number) as [number, number];
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { from: `${period}-01`, to: `${period}-${String(last).padStart(2, "0")}` };
}

/** The month before an ISO date's month ("YYYY-MM"), the one the monthly job scores. */
export function previousPeriod(isoDate: string): string {
  const [y, m] = isoDate.split("-").map(Number) as [number, number];
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, "0")}`;
}
