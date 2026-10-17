import type { Readiness, Scale } from "./contract";

/** Converters the engine applies to extracted values ("code converts them", extractor prompt). Pure. */

const num = (s: string) => Number(s.replace(/,/g, ""));

/** "72", "72%", "7.8" (cgpa10), "3.4" (gpa4) → percent; null when the scale is unknown or the value is out of range. */
export function scoreToPct(raw: string, scale: Scale = "unknown"): number | null {
  const m = raw.match(/\d+(?:\.\d+)?/g);
  if (!m) return null;
  const values = m.map(Number);
  const v = values.length > 1 ? Math.max(...values) : values[0]!; // "58 or 59" → the higher, as written
  let s: Scale = scale;
  if (s === "unknown") s = /%|percent|pct/i.test(raw) || v > 10 ? "percent" : /cgpa/i.test(raw) ? "cgpa10" : "unknown";
  if (s === "percent") return v > 0 && v <= 100 ? Math.round(v * 10) / 10 : null;
  if (s === "cgpa10") return v > 0 && v <= 10 ? Math.round(v * 9.5 * 10) / 10 : null;
  if (s === "gpa4") return v > 0 && v <= 4 ? Math.round(v * 25 * 10) / 10 : null;
  return null;
}

/** "1.5 lakh", "50-60k", "1 se 1.5 lakh", "₹80,000", "2L" → rupees (the upper end of a range). */
export function budgetToInr(raw: string): number | null {
  const t = raw.toLowerCase().replace(/₹|rs\.?|inr/g, " ");
  const unit = /(lakh|lac|lakhs|\bl\b|\d\s*l\b)/.test(t) ? 100000 : /(\d\s*k\b|thousand|hazar|hazaar)/.test(t) ? 1000 : /(crore|cr\b)/.test(t) ? 10000000 : 1;
  const nums = [...t.matchAll(/\d+(?:[.,]\d+)*/g)].map((m) => num(m[0]!.replace(/,(?=\d{3})/g, "")));
  if (!nums.length) return null;
  const v = Math.max(...nums) * unit;
  return v >= 1000 && v <= 100000000 ? Math.round(v) : null;
}

export function experienceYears(raw: string): number | null {
  if (/\b(no|zero|none|fresher|nahi)\b/i.test(raw) && !/\d/.test(raw)) return 0;
  const m = raw.match(/\d+(?:\.\d+)?/);
  if (!m) return null;
  const v = Number(m[0]);
  return v >= 0 && v <= 50 ? v : null;
}

/** Highest completed qualification → rank (10th 1, 12th/diploma 2, bachelor 3, master 4, doctorate 5). */
export function qualificationRank(raw: string | undefined | null): number | null {
  if (!raw) return null;
  const t = raw.toLowerCase().replace(/[.\s]/g, "");
  if (/phd|doctor/.test(t)) return 5;
  if (/matric|ssc|highschool|^10|^x$|class10/.test(t)) return 1;
  if (/mbbs|bds|bams/.test(t)) return 3;
  if (/^(m|pg|post|master)|mba|mca|mcom|msc|mtech|^ma\b|^ma$|^ma[-–]|pgdm|postgrad/.test(t)) return 4;
  if (/^(b|ug|grad|bachelor)|bcom|bsc|bba|bca|btech|be\b|^ba\b|^ba$|^ba[-–]|llb|degree|graduat/.test(t)) return 3;
  if (/diploma|polytechnic/.test(t)) return 2;
  if (/12|xii|inter|hsc|senior ?secondary/.test(t)) return 2;
  if (/10|^x$|ssc|matric|highschool/.test(t)) return 1;
  return null;
}

const REQUIRED_RANK: Record<string, number> = { "12TH": 2, DIPLOMA: 2, BACHELOR: 3, GRADUATION: 3, MASTER: 4, POSTGRADUATION: 4 };
export function requiredRank(minQualification: string | null | undefined): number | null {
  if (!minQualification) return null;
  return REQUIRED_RANK[minQualification.toUpperCase()] ?? null;
}

/** Readiness from the stated timeline (EXPLORING default). */
export function readinessFromTimeline(raw: string | undefined | null): Readiness | null {
  if (!raw) return null;
  const t = raw.toLowerCase();
  if (/(just exploring|not sure|no idea|maybe|pata nahi|soch|dekh rahe|later sometime)/.test(t)) return "EXPLORING";
  if (/(now|asap|immediate|this month|this session|current session|abhi|jaldi|isi (mahine|session)|right away|this week|today)/.test(t)) return "READY_NOW";
  if (/(next|month|months|year|session|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|semester|later|baad)/.test(t)) return "PLANNING";
  return null;
}

export function normaliseMode(raw: string): "Online" | "ODL" | "Regular" | null {
  const t = raw.toLowerCase();
  if (/odl|distance|correspondence/.test(t)) return "ODL";
  if (/online/.test(t)) return "Online";
  if (/regular|campus|offline|full[- ]?time/.test(t)) return "Regular";
  return null;
}

export function normaliseLevel(raw: string): "UG" | "PG" | "DIPLOMA" | "CERTIFICATE" | null {
  const t = raw.toUpperCase();
  if (/CERT/.test(t)) return "CERTIFICATE";
  if (/DIPLOMA|PGD/.test(t)) return t.includes("PG") ? "PG" : "DIPLOMA";
  if (/\bPG\b|POST|MASTER/.test(t)) return "PG";
  if (/\bUG\b|UNDER|BACHELOR/.test(t)) return "UG";
  return null;
}

/** en-IN currency without decimals: 150000 → "₹1,50,000". */
export function inr(n: number): string {
  return `₹${Math.round(n).toLocaleString("en-IN")}`;
}
