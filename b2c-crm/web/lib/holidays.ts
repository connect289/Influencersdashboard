/**
 * A pasted holiday list (spec B7.1): one holiday a line, "YYYY-MM-DD, name, national|company" (kind optional, company by
 * default; a header line and blank lines are skipped; DD-MM-YYYY and DD/MM/YYYY are read too). Pure; unit-tested.
 */
export type HolidayRow = { day: string; name: string; kind: "national" | "company" };

function isoDay(s: string): string | null {
  const t = s.trim();
  let y: number, m: number, d: number;
  let x = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t);
  if (x) { y = +x[1]!; m = +x[2]!; d = +x[3]!; }
  else if ((x = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/.exec(t))) { d = +x[1]!; m = +x[2]!; y = +x[3]!; }
  else return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return dt.toISOString().slice(0, 10);
}

/** Splits a CSV line on commas outside double quotes. */
function cells(line: string): string[] {
  const out: string[] = [];
  let cur = "", q = false;
  for (const ch of line) {
    if (ch === '"') q = !q;
    else if (ch === "," && !q) { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out.map((c) => c.trim());
}

export function parseHolidays(text: string): { rows: HolidayRow[]; errors: string[] } {
  const rows: HolidayRow[] = [];
  const errors: string[] = [];
  const seen = new Set<string>();
  text.replace(/\r\n?/g, "\n").split("\n").forEach((raw, i) => {
    const line = raw.trim();
    if (!line) return;
    const [dayText = "", nameText = "", kindText = ""] = cells(line.includes(",") ? line : line.replace(/\t/g, ","));
    const day = isoDay(dayText);
    if (!day) {
      if (i === 0 && /date|day/i.test(dayText)) return; // a header line
      errors.push(`Line ${i + 1}: "${dayText}" is not a date (use YYYY-MM-DD).`);
      return;
    }
    const kind = kindText.toLowerCase();
    if (kind && kind !== "national" && kind !== "company") { errors.push(`Line ${i + 1}: the kind is national or company.`); return; }
    if (seen.has(day)) { errors.push(`Line ${i + 1}: ${day} is listed twice.`); return; }
    seen.add(day);
    rows.push({ day, name: nameText.slice(0, 80) || "Holiday", kind: (kind || "company") as HolidayRow["kind"] });
  });
  return { rows, errors };
}

/** Monday of the week that holds this day ("YYYY-MM-DD"), and the Mondays before and after. */
export function weekOf(day: string): { from: string; prev: string; next: string } {
  const d = new Date(`${day}T00:00:00Z`);
  const dow = (d.getUTCDay() + 6) % 7;
  const from = new Date(d.getTime() - dow * 864e5);
  const iso = (x: Date) => x.toISOString().slice(0, 10);
  return { from: iso(from), prev: iso(new Date(from.getTime() - 7 * 864e5)), next: iso(new Date(from.getTime() + 7 * 864e5)) };
}
