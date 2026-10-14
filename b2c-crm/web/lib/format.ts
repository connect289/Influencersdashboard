// Display helpers. Everything is shown in India time (IST), whatever the device's zone. Unit-tested in format.test.ts.

const TZ = "Asia/Kolkata";

export function inr(n: number | string | null | undefined): string {
  if (n === null || n === undefined || n === "") return "—";
  const v = Number(n);
  if (!Number.isFinite(v)) return "—";
  return "₹" + v.toLocaleString("en-IN", { maximumFractionDigits: 0 });
}

function parts(d: Date) {
  const f = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false });
  const o: Record<string, string> = {};
  for (const p of f.formatToParts(d)) o[p.type] = p.value;
  return { y: o.year!, m: o.month!, d: o.day!, h: o.hour === "24" ? "00" : o.hour!, min: o.minute! };
}

/** "YYYY-MM-DD" of the IST day. */
export function istDay(d: Date): string {
  const p = parts(d);
  return `${p.y}-${p.m}-${p.d}`;
}

export function time(iso: string | null | undefined): string {
  if (!iso) return "—";
  const p = parts(new Date(iso));
  return `${p.h}:${p.min}`;
}

export function date(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Intl.DateTimeFormat("en-IN", { timeZone: TZ, day: "numeric", month: "short", year: "numeric" }).format(new Date(iso));
}

/** "Today 14:30", "Tomorrow 10:00", "Yesterday 09:12", "Thu 15 Oct 18:00". */
export function when(iso: string | null | undefined, now = new Date()): string {
  if (!iso) return "—";
  const d = new Date(iso);
  const day = istDay(d);
  const today = istDay(now);
  const tomorrow = istDay(new Date(now.getTime() + 864e5));
  const yesterday = istDay(new Date(now.getTime() - 864e5));
  const t = time(iso);
  if (day === today) return `Today ${t}`;
  if (day === tomorrow) return `Tomorrow ${t}`;
  if (day === yesterday) return `Yesterday ${t}`;
  const label = new Intl.DateTimeFormat("en-IN", { timeZone: TZ, weekday: "short", day: "numeric", month: "short" }).format(d);
  return `${label} ${t}`;
}

/** "in 25 min", "3 h ago". */
export function relative(iso: string | null | undefined, now = new Date()): string {
  if (!iso) return "—";
  const s = Math.round((new Date(iso).getTime() - now.getTime()) / 1000);
  const a = Math.abs(s);
  const v = a < 60 ? `${a} s` : a < 3600 ? `${Math.round(a / 60)} min` : a < 86400 ? `${Math.round(a / 3600)} h` : `${Math.round(a / 86400)} d`;
  return s >= 0 ? `in ${v}` : `${v} ago`;
}

/** Value for <input type="datetime-local"> in IST, e.g. "2026-10-15T10:30". */
export function toLocalInput(d: Date): string {
  const p = parts(d);
  return `${p.y}-${p.m}-${p.d}T${p.h}:${p.min}`;
}

/** An IST "YYYY-MM-DDTHH:mm" from a form, as an ISO instant. India has no daylight saving: always +05:30. */
export function fromLocalInput(v: string | null | undefined): string | null {
  if (!v || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(v)) return null;
  const d = new Date(`${v}:00+05:30`);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** Quick follow-up choices (spec B8.3): in 3 hours, this evening 18:00, tomorrow 10:00. */
export function quickTimes(now = new Date()): { label: string; iso: string }[] {
  const at = (dayOffset: number, hh: number) => fromLocalInput(`${istDay(new Date(now.getTime() + dayOffset * 864e5))}T${String(hh).padStart(2, "0")}:00`)!;
  const out = [{ label: "In 3 hours", iso: new Date(now.getTime() + 3 * 3600e3).toISOString() }];
  const evening = at(0, 18);
  if (new Date(evening).getTime() > now.getTime() + 30 * 60e3) out.push({ label: "Today 18:00", iso: evening });
  out.push({ label: "Tomorrow 10:00", iso: at(1, 10) });
  out.push({ label: "In 2 days", iso: at(2, 10) });
  return out;
}

export function maskPhone(p: string | null | undefined): string {
  if (!p) return "—";
  const d = p.replace(/\D/g, "");
  if (d.length < 6) return p;
  const local = d.length > 10 ? d.slice(-10) : d;
  const cc = d.length > 10 ? "+" + d.slice(0, d.length - 10) + " " : "";
  return `${cc}${local.slice(0, 5)} ${local.slice(5)}`;
}

export function initials(name: string | null | undefined): string {
  const parts = (name ?? "?").trim().split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "?") + (parts[1]?.[0] ?? "")).toUpperCase();
}

export function plural(n: number, one: string, many = one + "s"): string {
  return `${n} ${n === 1 ? one : many}`;
}
