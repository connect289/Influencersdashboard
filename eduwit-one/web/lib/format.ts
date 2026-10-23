// Display formats (spec: store UTC, show IST, Indian number grouping). Pure, so pages and emails share them.

const IST = "Asia/Kolkata";
const dateTime = new Intl.DateTimeFormat("en-IN", { timeZone: IST, dateStyle: "medium", timeStyle: "short" });
const dateOnly = new Intl.DateTimeFormat("en-IN", { timeZone: IST, dateStyle: "medium" });
const timeOnly = new Intl.DateTimeFormat("en-IN", { timeZone: IST, timeStyle: "short" });
const number = new Intl.NumberFormat("en-IN");
const rupees = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 });
const dollars = new Intl.NumberFormat("en-IN", { style: "currency", currency: "USD", maximumFractionDigits: 4 });

function parse(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** "23 Oct 2026, 3:30 pm" in IST, or an em dash. */
export function ist(iso: string | null | undefined): string {
  const d = parse(iso);
  return d ? dateTime.format(d) : "—";
}

export function istDate(iso: string | null | undefined): string {
  const d = parse(iso);
  return d ? dateOnly.format(d) : "—";
}

export function istTime(iso: string | null | undefined): string {
  const d = parse(iso);
  return d ? timeOnly.format(d) : "—";
}

/** "just now", "4 min ago", "3 h ago", "2 d ago"; "in 5 min" for a future time. */
export function ago(iso: string | null | undefined, now: number = Date.now()): string {
  const d = parse(iso);
  if (!d) return "never";
  const s = Math.round((now - d.getTime()) / 1000);
  const future = s < 0;
  const a = Math.abs(s);
  const text =
    a < 45
      ? null
      : a < 3600
        ? `${Math.round(a / 60)} min`
        : a < 86400
          ? `${Math.round(a / 3600)} h`
          : `${Math.round(a / 86400)} d`;
  if (!text) return "just now";
  return future ? `in ${text}` : `${text} ago`;
}

/** Seconds as "45 s", "12 min", "3 h 5 min". */
export function duration(seconds: number | null | undefined): string {
  if (seconds == null || !Number.isFinite(seconds)) return "—";
  const s = Math.max(0, Math.round(seconds));
  if (s < 60) return `${s} s`;
  if (s < 3600) return `${Math.round(s / 60)} min`;
  const h = Math.floor(s / 3600);
  const m = Math.round((s % 3600) / 60);
  return m ? `${h} h ${m} min` : `${h} h`;
}

export function num(n: number | null | undefined): string {
  return n == null || !Number.isFinite(n) ? "—" : number.format(n);
}

export function inr(n: number | null | undefined): string {
  return n == null || !Number.isFinite(n) ? "—" : rupees.format(n);
}

export function usd(n: number | null | undefined): string {
  return n == null || !Number.isFinite(n) ? "—" : dollars.format(n);
}

export function ms(n: number | null | undefined): string {
  if (n == null || !Number.isFinite(n)) return "—";
  return n < 1000 ? `${Math.round(n)} ms` : `${(n / 1000).toFixed(1)} s`;
}

/** A JSON value for display, bounded so one large evidence blob cannot flood a page. */
export function json(value: unknown, max = 4000): string {
  let text: string;
  try {
    text = JSON.stringify(value, null, 2) ?? "null";
  } catch {
    text = String(value);
  }
  return text.length > max ? `${text.slice(0, max)}\n… (${num(text.length - max)} more characters)` : text;
}
