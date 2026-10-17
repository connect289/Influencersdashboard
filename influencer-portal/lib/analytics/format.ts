// Formatting dashboard numbers by unit (Indian digit grouping, rupees from paise, IST dates); null is "—". Pure.
import { formatDate, formatNumber, formatPaise } from "@/lib/format";
import type { MetricUnit } from "./metrics";

export const EMPTY = "—";

const pct = (v: number) => {
  const p = v * 100;
  const digits = Math.abs(p) >= 100 || Number.isInteger(Math.round(p * 10) / 10) ? 0 : 1;
  return `${p.toLocaleString("en-IN", { minimumFractionDigits: digits, maximumFractionDigits: digits })}%`;
};

export function formatMetric(unit: MetricUnit, value: number | string | null, opts: { whole?: boolean } = {}): string {
  if (value === null || value === "") return EMPTY;
  switch (unit) {
    case "count":
      return formatNumber(Number(value));
    case "money":
      return formatPaise(Number(value), { whole: opts.whole ?? true });
    case "percent":
      return pct(Number(value));
    case "ratio":
      return `${Number(value).toLocaleString("en-IN", { minimumFractionDigits: 1, maximumFractionDigits: 2 })}×`;
    case "date":
      return formatDate(String(value));
  }
}

/** "+12%", "−5%", or "0%" for a relative change. */
export function formatChange(p: number | null): string | null {
  if (p === null) return null;
  const rounded = Math.round(p * 100);
  if (rounded === 0) return "0%";
  return `${rounded > 0 ? "+" : "−"}${Math.abs(rounded).toLocaleString("en-IN")}%`;
}
