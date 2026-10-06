/**
 * Programme Repository: the repository fields, header suggestions, value normalisers, a CSV parser and the zip size
 * guard. Pure functions shared by the server actions and the tests. Partner files are untrusted: every value is parsed
 * into a known shape, and anything unparseable becomes a row error the Admin sees.
 */

export const FIELDS = [
  { key: "university", label: "University", required: true },
  { key: "course", label: "Course / degree", required: true },
  { key: "specialization", label: "Specialization", required: false },
  { key: "mode", label: "Mode", required: true },
  { key: "level", label: "Level", required: false },
  { key: "programme_name", label: "Partner's programme name", required: false },
  { key: "programme_code", label: "Partner's programme code", required: false },
  { key: "fee_total", label: "Total fee", required: false },
  { key: "fee_yearly", label: "Yearly fee", required: false },
  { key: "fee_semester", label: "Semester fee", required: false },
  { key: "fee_registration", label: "Registration fee", required: false },
  { key: "fee_exam", label: "Exam fee", required: false },
  { key: "min_qualification", label: "Minimum qualification", required: false },
  { key: "min_pct", label: "Minimum %", required: false },
  { key: "commission", label: "Commission", required: false },
  { key: "valid_from", label: "Valid from", required: false },
  { key: "valid_to", label: "Valid to", required: false },
  { key: "intake", label: "Intake / session", required: false },
  { key: "active", label: "Active", required: false },
  { key: "notes", label: "Notes", required: false },
] as const;

export type FieldKey = (typeof FIELDS)[number]["key"];
/** Repository field → the partner file's column header. */
export type Template = Partial<Record<FieldKey, string>>;
export type Cell = string | number | boolean | Date | null;

export const MAX_ROWS = 5000;
export const MAX_COLS = 80;
export const MAX_FILE_BYTES = 4 * 1024 * 1024;
export const MAX_UNZIPPED_BYTES = 60 * 1024 * 1024;

const key = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

/** Header words partners use for each field, compared without case, spaces or punctuation. */
const SYNONYMS: Record<FieldKey, string[]> = {
  university: ["university", "universityname", "uni", "institute", "institution", "college", "universitycollege"],
  course: ["course", "coursename", "degree", "program", "programme", "programtype", "coursetype", "qualification"],
  specialization: ["specialization", "specialisation", "spec", "stream", "major", "elective", "branch", "track"],
  mode: ["mode", "studymode", "deliverymode", "modeofstudy", "type", "learningmode"],
  level: ["level", "programlevel", "programmelevel", "uglevel", "category"],
  programme_name: ["programname", "programmename", "fullname", "coursefullname", "title", "programtitle"],
  programme_code: ["code", "programcode", "programmecode", "coursecode", "productcode", "sku", "id", "courseid"],
  fee_total: ["fee", "fees", "totalfee", "totalfees", "coursefee", "coursefees", "programfee", "price", "totalprice", "totalcost"],
  fee_yearly: ["yearlyfee", "annualfee", "feeperyear", "peryear", "yearfee"],
  fee_semester: ["semesterfee", "semfee", "persemester", "feepersemester"],
  fee_registration: ["registrationfee", "regfee", "applicationfee", "admissionfee"],
  fee_exam: ["examfee", "examinationfee"],
  min_qualification: ["eligibility", "minqualification", "minimumqualification", "eligibilitycriteria", "qualificationrequired"],
  min_pct: ["minpercentage", "minimumpercentage", "minpct", "percentage", "minmarks", "minimummarks"],
  commission: ["commission", "payout", "commissionpercent", "commissionrate", "brokerage", "cpa", "revenueshare"],
  valid_from: ["validfrom", "startdate", "from", "effectivefrom"],
  valid_to: ["validto", "validtill", "enddate", "to", "expiry", "lastdate"],
  intake: ["intake", "session", "batch", "admissioncycle", "cycle"],
  active: ["active", "status", "isactive", "available", "live"],
  notes: ["notes", "remarks", "comment", "comments"],
};

/** Suggests a column for each field from the headers; a saved template wins where its header still exists. */
export function suggestTemplate(headers: string[], saved: Template = {}): Template {
  const out: Template = {};
  const used = new Set<string>();
  for (const f of FIELDS) {
    const s = saved[f.key];
    if (s && headers.includes(s)) { out[f.key] = s; used.add(s); }
  }
  for (const f of FIELDS) {
    if (out[f.key]) continue;
    const hit = headers.find((h) => !used.has(h) && SYNONYMS[f.key].includes(key(h)))
      ?? headers.find((h) => !used.has(h) && SYNONYMS[f.key].some((w) => w.length > 4 && key(h).includes(w)));
    if (hit) { out[f.key] = hit; used.add(hit); }
  }
  return out;
}

/** The header row: the first of the first 15 rows with at least two text cells and the most known header words. */
export function findHeaderRow(rows: Cell[][]): number {
  let best = 0, bestScore = -1;
  for (let i = 0; i < Math.min(rows.length, 15); i++) {
    const cells = (rows[i] ?? []).filter((c): c is string => typeof c === "string" && c.trim() !== "");
    if (cells.length < 2) continue;
    const score = cells.filter((c) => Object.values(SYNONYMS).some((ws) => ws.includes(key(c)))).length;
    if (score > bestScore) { best = i; bestScore = score; }
  }
  return best;
}

/** Unique, non-empty header names ("Fee", "Fee" → "Fee", "Fee (2)"; empty → "Column C"). */
export function headerNames(row: Cell[]): string[] {
  const seen = new Map<string, number>();
  return row.slice(0, MAX_COLS).map((c, i) => {
    let name = cellText(c).slice(0, 80) || `Column ${columnLetter(i)}`;
    const n = (seen.get(name) ?? 0) + 1;
    seen.set(name, n);
    if (n > 1) name = `${name} (${n})`;
    return name;
  });
}

function columnLetter(i: number): string {
  let s = "";
  for (let n = i + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
  return s;
}

export function cellText(c: Cell | undefined): string {
  if (c === null || c === undefined) return "";
  if (c instanceof Date) return Number.isNaN(c.getTime()) ? "" : c.toISOString().slice(0, 10);
  return String(c).replace(/\s+/g, " ").trim();
}

// ---------- value normalisers ----------

/** "1.5 L" → 150000, "₹1,20,000/-" → 120000, "2.4 Cr" → 24000000, "50k" → 50000. Empty → null. */
export function parseMoney(v: Cell): number | null | "invalid" {
  if (typeof v === "number") return Number.isFinite(v) && v >= 0 ? Math.round(v) : "invalid";
  const s = cellText(v).toLowerCase().replace(/(rs\.?|inr|₹|\/-|,|\s)/g, "");
  if (s === "" || s === "-" || s === "na" || s === "n/a") return null;
  const m = /^(\d+(?:\.\d+)?)(l|lac|lacs|lakh|lakhs|k|thousand|cr|crore|crores)?$/.exec(s);
  if (!m) return "invalid";
  const mult = { l: 1e5, lac: 1e5, lacs: 1e5, lakh: 1e5, lakhs: 1e5, k: 1e3, thousand: 1e3, cr: 1e7, crore: 1e7, crores: 1e7 }[m[2] ?? ""] ?? 1;
  return Math.round(Number(m[1]) * mult);
}

export function parseMode(v: Cell): "Online" | "ODL" | "Regular" | null | "invalid" {
  const s = key(cellText(v));
  if (!s) return null;
  if (["online", "onl", "onlinemode", "elearning", "virtual"].includes(s)) return "Online";
  if (["odl", "distance", "distancelearning", "opendistancelearning", "correspondence", "opendistance"].includes(s)) return "ODL";
  if (["regular", "oncampus", "campus", "fulltime", "offline", "classroom", "regularmode"].includes(s)) return "Regular";
  return "invalid";
}

export function parseLevel(v: Cell): "UG" | "PG" | "DIPLOMA" | "CERTIFICATE" | null | "invalid" {
  const s = key(cellText(v));
  if (!s) return null;
  if (["ug", "undergraduate", "bachelor", "bachelors", "graduation", "graduate"].includes(s)) return "UG";
  if (["pg", "postgraduate", "master", "masters", "postgraduation"].includes(s)) return "PG";
  if (["diploma", "pgdiploma", "advanceddiploma", "pgd"].includes(s)) return s.startsWith("pg") ? "PG" : "DIPLOMA";
  if (["certificate", "certification", "cert"].includes(s)) return "CERTIFICATE";
  return "invalid";
}

/** Level from the course when the file has none: BBA → UG, MBA/PGDM → PG, "Diploma in …" → DIPLOMA. */
export function inferLevel(course: string): "UG" | "PG" | "DIPLOMA" | "CERTIFICATE" | null {
  const s = key(course);
  if (!s) return null;
  if (/^(pgd|pgdm|pgcm|pgdip|postgraduatediploma)/.test(s)) return "PG";
  if (/^(diploma|dca)/.test(s)) return "DIPLOMA";
  if (/^(certificate|cert)/.test(s)) return "CERTIFICATE";
  if (/^(m|master)/.test(s)) return "PG";
  if (/^(b|bachelor)/.test(s)) return "UG";
  return null;
}

/** "55%" / "55" / "55.5" → 55.5; outside 0–100 is invalid. */
export function parsePct(v: Cell): number | null | "invalid" {
  const s = cellText(v).replace(/%/g, "").trim();
  if (!s || s === "-") return null;
  const n = Number(s);
  return Number.isFinite(n) && n >= 0 && n <= 100 ? n : "invalid";
}

export type Commission = { type: "percent"; value: number } | { type: "fixed"; value: number } | { type: "tier"; ref: string };

/** "20%" → percent; "₹35,000" or "35000" → fixed; "Tier 2" → tier reference. Becomes a proposed rate only. */
export function parseCommission(v: Cell): Commission | null | "invalid" {
  const raw = cellText(v);
  if (!raw || raw === "-") return null;
  if (/%/.test(raw)) {
    const n = Number(raw.replace(/[%\s]/g, ""));
    return Number.isFinite(n) && n > 0 && n <= 100 ? { type: "percent", value: n } : "invalid";
  }
  if (/tier|slab/i.test(raw)) return { type: "tier", ref: raw.slice(0, 60) };
  const m = parseMoney(raw);
  if (typeof m === "number" && m > 0) return m <= 100 && !/[₹]|rs|inr/i.test(raw) ? { type: "percent", value: m } : { type: "fixed", value: m };
  return "invalid";
}

/** Excel dates arrive as Date; text as 2026-10-01 or 01/10/2026 (day first, Indian style). */
export function parseDate(v: Cell): string | null | "invalid" {
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? "invalid" : v.toISOString().slice(0, 10);
  const s = cellText(v);
  if (!s) return null;
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s);
  let y: number, mo: number, d: number;
  if (m) [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  else if ((m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(s))) [d, mo, y] = [Number(m[1]), Number(m[2]), Number(m[3])];
  else return "invalid";
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d ? dt.toISOString().slice(0, 10) : "invalid";
}

export function parseActive(v: Cell): boolean | "invalid" {
  if (typeof v === "boolean") return v;
  const s = key(cellText(v));
  if (!s || ["yes", "y", "true", "1", "active", "live", "available", "open"].includes(s)) return true;
  if (["no", "n", "false", "0", "inactive", "closed", "discontinued", "notavailable", "off"].includes(s)) return false;
  return "invalid";
}

const ABBREVIATIONS: Record<string, string> = {
  hr: "Human Resource Management",
  hrm: "Human Resource Management",
  it: "Information Technology",
  ib: "International Business",
  scm: "Supply Chain Management",
  general: "General",
};

/** Specialization text: common abbreviations expanded, "Mgmt" → "Management", empty → "General". */
export function normaliseSpecialization(v: Cell): string {
  const s = cellText(v);
  if (!s || /^(-|na|n\/a|none|nil)$/i.test(s)) return "General";
  const full = ABBREVIATIONS[key(s)];
  return full ?? s.replace(/\bmgmt\b\.?|\bmgt\b\.?/gi, "Management").replace(/\s+/g, " ").trim();
}

export type NormalisedRow = {
  university: string;
  course: string;
  specialization: string;
  mode: string | null;
  level: string | null;
  programme_name: string | null;
  programme_code: string | null;
  fees: Partial<Record<"total" | "yearly" | "semester" | "registration" | "exam", number>>;
  eligibility: { min_qualification?: string; min_pct?: number };
  commission: Commission | null;
  season_from: string | null;
  season_to: string | null;
  intake: string | null;
  active: boolean;
  notes: string | null;
  errors: string[];
};

/** One file row → the shape b2b.programme_version_create stores, with readable errors for the review queue. */
export function normaliseRow(row: Record<string, Cell>, t: Template): NormalisedRow {
  const get = (f: FieldKey): Cell => (t[f] ? (row[t[f]!] ?? null) : null);
  const errors: string[] = [];
  const text = (f: FieldKey, max = 200) => cellText(get(f)).slice(0, max) || null;

  const university = text("university") ?? "";
  const course = text("course") ?? "";
  if (!university) errors.push("University is missing");
  if (!course) errors.push("Course is missing");

  const mode = parseMode(get("mode"));
  if (mode === null) errors.push("Mode is missing");
  if (mode === "invalid") errors.push(`Unknown mode “${cellText(get("mode")).slice(0, 30)}”`);

  let level = parseLevel(get("level"));
  if (level === "invalid") { errors.push(`Unknown level “${cellText(get("level")).slice(0, 30)}”`); level = null; }
  level ??= inferLevel(course);

  const fees: NormalisedRow["fees"] = {};
  for (const [f, k] of [["fee_total", "total"], ["fee_yearly", "yearly"], ["fee_semester", "semester"], ["fee_registration", "registration"], ["fee_exam", "exam"]] as const) {
    const m = parseMoney(get(f));
    if (m === "invalid") errors.push(`${FIELDS.find((x) => x.key === f)!.label} is not an amount`);
    else if (m !== null) fees[k] = m;
  }

  const eligibility: NormalisedRow["eligibility"] = {};
  const q = text("min_qualification", 300);
  if (q) eligibility.min_qualification = q;
  const pct = parsePct(get("min_pct"));
  if (pct === "invalid") errors.push("Minimum % is not a percentage");
  else if (pct !== null) eligibility.min_pct = pct;

  const commission = parseCommission(get("commission"));
  if (commission === "invalid") errors.push("Commission is not a %, an amount or a tier");

  const from = parseDate(get("valid_from")), to = parseDate(get("valid_to"));
  if (from === "invalid") errors.push("Valid from is not a date");
  if (to === "invalid") errors.push("Valid to is not a date");
  if (typeof from === "string" && from !== "invalid" && typeof to === "string" && to !== "invalid" && from > to) errors.push("Valid from is after valid to");

  const active = parseActive(get("active"));
  if (active === "invalid") errors.push("Active is not yes or no");

  return {
    university,
    course,
    specialization: normaliseSpecialization(get("specialization")),
    mode: mode === "invalid" ? null : mode,
    level,
    programme_name: text("programme_name", 300),
    programme_code: text("programme_code", 100),
    fees,
    eligibility,
    commission: commission === "invalid" ? null : commission,
    season_from: from === "invalid" ? null : from,
    season_to: to === "invalid" ? null : to,
    intake: text("intake", 100),
    active: active === "invalid" ? true : active,
    notes: text("notes", 500),
    errors,
  };
}

/** True when the row has no value in any column (spacer rows in partner sheets). */
export const isBlankRow = (row: Cell[]) => row.every((c) => cellText(c) === "");

// ---------- CSV ----------

/** RFC 4180 with the delimiter detected from the first line (comma, semicolon or tab); a BOM is dropped. */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, "");
  const first = src.slice(0, src.search(/\r?\n|$/));
  const counts = [",", ";", "\t"].map((d) => [d, first.split(d).length] as const);
  const delim = counts.sort((a, b) => b[1] - a[1])[0]![0];
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]!;
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') { cell += '"'; i++; } else quoted = false;
      } else cell += ch;
    } else if (ch === '"' && cell === "") quoted = true;
    else if (ch === delim) { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && src[i + 1] === "\n") i++;
      row.push(cell); rows.push(row); row = []; cell = "";
      if (rows.length > MAX_ROWS + 20) break;
    } else cell += ch;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

// ---------- xlsx guard ----------

/**
 * Sum of uncompressed sizes in a zip's central directory, or null when it is not a readable zip. Read before parsing,
 * so a crafted .xlsx (a zip bomb) is refused instead of filling the server's memory.
 */
export function zipUncompressedSize(buf: Uint8Array): number | null {
  if (buf.length < 22 || buf[0] !== 0x50 || buf[1] !== 0x4b || buf[2] !== 0x03 || buf[3] !== 0x04) return null;
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) return null;
  const entries = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true);
  let total = 0;
  for (let n = 0; n < entries; n++) {
    if (p + 46 > buf.length || view.getUint32(p, true) !== 0x02014b50) return null;
    const size = view.getUint32(p + 24, true);
    if (size === 0xffffffff) return Number.POSITIVE_INFINITY; // zip64: far beyond any partner file
    total += size;
    p += 46 + view.getUint16(p + 28, true) + view.getUint16(p + 30, true) + view.getUint16(p + 32, true);
  }
  return total;
}

// ---------- labels ----------

export const REVIEW_LABEL: Record<string, string> = {
  auto: "Matched",
  approved: "Approved",
  needs_review: "Needs review",
  no_match: "No match",
  ignored: "Ignored",
};
export const REVIEW_TONE: Record<string, "success" | "warning" | "danger" | "neutral" | "info"> = {
  auto: "success",
  approved: "success",
  needs_review: "warning",
  no_match: "danger",
  ignored: "neutral",
};
export const VERSION_LABEL: Record<string, string> = {
  draft: "Draft",
  published: "Live",
  superseded: "Replaced",
  rolled_back: "Rolled back",
  discarded: "Discarded",
};
export const VERSION_TONE: Record<string, "success" | "warning" | "neutral" | "info"> = {
  draft: "warning",
  published: "success",
  superseded: "neutral",
  rolled_back: "neutral",
  discarded: "neutral",
};

export const inr = (n: number | null | undefined) => (n === null || n === undefined ? "—" : `₹${Math.round(n).toLocaleString("en-IN")}`);

export function commissionText(c: Commission | null | undefined): string {
  if (!c) return "—";
  if (c.type === "percent") return `${c.value}%`;
  if (c.type === "fixed") return inr(c.value);
  return c.ref;
}
