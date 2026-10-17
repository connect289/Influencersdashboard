/**
 * Form field rules shared by the application form, the enquiry form and the Witty gate (spec 7.2, 9.1A). Pure and
 * tested; the server re-validates everything (Phase 7).
 */

/** Indian mobile → E.164 (+91XXXXXXXXXX). Accepts spaces, dashes and a +91 / 91 / 0 prefix. Null if invalid. */
export function normaliseIndianMobile(input: string): string | null {
  const digits = input.replace(/[\s\-().]/g, "");
  const m = digits.match(/^(?:\+?91|0)?([6-9]\d{9})$/);
  if (!m) return null;
  // Reject obviously fake numbers (all one digit, simple sequences).
  if (/^(\d)\1{9}$/.test(m[1]!) || m[1] === "9876543210" || m[1] === "6789012345") return null;
  return `+91${m[1]}`;
}

const EMAIL = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
export function normaliseEmail(input: string): string | null {
  const e = input.trim().toLowerCase();
  return e.length <= 254 && EMAIL.test(e) ? e : null;
}

export function cleanName(input: string): string | null {
  const n = input.replace(/\s+/g, " ").trim();
  if (n.length < 2 || n.length > 80) return null;
  if (!/^[\p{L}][\p{L}\p{M} .'-]*$/u.test(n)) return null;
  return n;
}

export type Errors<K extends string> = Partial<Record<K, string>>;

export interface ContactInput {
  name: string;
  phone: string;
  email: string;
  consent: boolean;
}
export function validateContact(c: ContactInput): Errors<keyof ContactInput> {
  const e: Errors<keyof ContactInput> = {};
  if (!cleanName(c.name)) e.name = "Enter your full name (letters only).";
  if (!normaliseIndianMobile(c.phone)) e.phone = "Enter a valid 10-digit Indian mobile number.";
  if (!normaliseEmail(c.email)) e.email = "Enter a valid email address.";
  if (!c.consent) e.consent = "Please agree so a counsellor can help you.";
  return e;
}

export interface AcademicInput {
  qualification: string;
  stream: string;
  scoreType: "percent" | "cgpa";
  score: string;
  currentlyStudying: boolean;
  yearOfPassing: string;
  board: string;
}
export function validateAcademic(a: AcademicInput, nowYear = new Date().getFullYear()): Errors<keyof AcademicInput> {
  const e: Errors<keyof AcademicInput> = {};
  if (!a.qualification) e.qualification = "Choose your highest qualification.";
  if (a.score) {
    const v = Number(a.score);
    const max = a.scoreType === "cgpa" ? 10 : 100;
    if (!Number.isFinite(v) || v <= 0 || v > max) e.score = a.scoreType === "cgpa" ? "Enter a CGPA between 0 and 10." : "Enter a percentage between 0 and 100.";
  }
  if (!a.currentlyStudying && a.yearOfPassing) {
    const y = Number(a.yearOfPassing);
    if (!Number.isInteger(y) || y < 1960 || y > nowYear + 1) e.yearOfPassing = "Enter a valid year.";
  }
  return e;
}

export interface WorkInput {
  working: "yes" | "no" | "";
  years: string;
  role: string;
  industry: string;
  goal: string;
  why: string;
}
export function validateWork(w: WorkInput): Errors<keyof WorkInput> {
  const e: Errors<keyof WorkInput> = {};
  if (!w.working) e.working = "Tell us if you are working.";
  if (w.working === "yes" && w.years !== "") {
    const y = Number(w.years);
    if (!Number.isFinite(y) || y < 0 || y > 50) e.years = "Enter years between 0 and 50.";
  }
  if (w.why.length > 1000) e.why = "Please keep this under 1,000 characters.";
  return e;
}

export interface PreferencesInput {
  intake: string;
  budget: string;
  emi: "yes" | "no" | "";
  universities: string[];
  city: string;
  state: string;
  contactMode: "call" | "whatsapp" | "email" | "";
  bestTime: string;
  questions: string;
}
export function validatePreferences(p: PreferencesInput, needsUniversity: boolean): Errors<keyof PreferencesInput> {
  const e: Errors<keyof PreferencesInput> = {};
  if (needsUniversity && p.universities.length === 0) e.universities = "Pick at least one university, or “Help me choose”.";
  if (!p.contactMode) e.contactMode = "How should a counsellor contact you?";
  if (p.questions.length > 1000) e.questions = "Please keep this under 1,000 characters.";
  return e;
}

/** CGPA → percentage only with an explicit 10-point scale (never guessed for other scales). */
export function scoreToPercent(scoreType: "percent" | "cgpa", score: string): number | null {
  const v = Number(score);
  if (!score || !Number.isFinite(v)) return null;
  return scoreType === "percent" ? v : Math.round(v * 9.5 * 10) / 10;
}
