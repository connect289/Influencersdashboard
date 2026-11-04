// The PII mask for everything a model reads (spec §11: the AI sees masked contact data only). The database already
// sends contact-free data (one.redact, D-046); this is the second layer, applied in the worker to every prompt input
// and every tool result, whatever produced it, and the only layer for what never passes the database's redaction (an
// Ask question, a tool's error text): names under a name key become initials, phones their last 4 digits, emails
// their domain, and message bodies are left out unless the task may quote them (explain on a Witty incident, with
// ai.allow_message_excerpts set). Secrets and identity documents are always left out. Phones are found the way
// one.has_contact finds them (an Indian mobile inside any run of digits, a + number, any run of 10 to 15 digits), after
// other scripts' digits and unusual spaces are normalised; dates, times and ids are left alone. A name inside free
// text cannot be recognised: that is why bodies, notes and excerpts are left out by default.

export type MaskOptions = {
  /** Keep message bodies as short excerpts, themselves masked (explain on a Witty incident only). */
  excerpts?: boolean;
};

const EXCERPT_CHARS = 280;
const STRING_CHARS = 2000;
const ARRAY_ITEMS = 200;
const MAX_DEPTH = 12;

const NAME_KEY =
  /^(name|full_?name|first_?name|last_?name|middle_?name|sur_?name|display_?name|contact_?name|student_?name|guardian_?name|parent_?name|father_?name|mother_?name|counsell?or_?name|sender_?name|recipient_?name|customer_?name|lead_?name|user_?name|profile_?name|push_?name|counsell?or|owner_?name|agent_?name|staff_?name|assignee_?name)s?$/i;
/** A map under one of these keys is keyed by people: its keys become initials. */
const PEOPLE_MAP_KEY =
  /^(by_)?(names|students?|leads?_by_name|guardians?|parents?|contacts?|persons?|people|customers?|applicants?|counsell?ors?|owners?|agents?|users?)(_by_name)?$|^by_(student|lead|guardian|parent|contact|person|customer|applicant|counsell?or|owner|agent|user|name)$/i;
const PHONE_KEY = /(^|_)(phone|mobile|msisdn|whatsapp|wa_?id|contact_?number|phone_?number|alt_?phone)s?(_|$)/i;
const EMAIL_KEY = /(^|_)e?mails?(_|$)|^email/i;
const BODY_KEY =
  /^(text|body|message|messages_?text|message_?text|message_?body|content|reply|reply_?text|transcript|caption|comment|comments|notes?|remarks?|subject|snippet|raw|prompt|answer_?text)$/i;
const DROP_KEY =
  /(^|_)(token|secret|password|passcode|otp|api_?key|authorization|cookie|address|street|pincode|pin_?code|postcode|dob|date_?of_?birth|pan|pan_?number|aadhaa?r|passport|bank_?account|account_?number|ifsc|upi|card_?number|ip|ip_?address|user_?agent)$/i;

const EMAIL = /[A-Z0-9._%+-]+@([A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,})/gi;
// Spans that look like digits but are not contacts: UUIDs, long hex ids, ISO dates and times, d/m/y dates.
const PROTECTED =
  /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{20,}|\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:[+-]\d{2}(?::?\d{2})?|Z)?)?|\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b/gi;
const SEP = "[ .()\\-/_]";
const PHONES = [
  // An Indian mobile anywhere, with an optional +91, 0091, 91 or 0 in front.
  new RegExp(`(?<![0-9])(?:(?:\\+|00)?91${SEP}{0,2}|0)?[6-9](?:${SEP}?[0-9]){9}(?![0-9])`, "g"),
  // A + number of 8 to 15 digits.
  new RegExp(`\\+[ (]?[0-9](?:${SEP}{0,2}[0-9]){7,14}(?![0-9])`, "g"),
  // Any run of 10 to 15 digits (an id that long is masked too: privacy first, as one.redact does).
  new RegExp(`(?<![0-9])[0-9](?:${SEP}?[0-9]){9,14}(?![0-9])`, "g"),
];

/** Other scripts' digits (Devanagari, Bengali, full-width…) as ASCII, and every space-like character as a space. */
export function normaliseDigits(text: string): string {
  return text
    .normalize("NFKC")
    .replace(/[\u00a0\u1680\u2000-\u200b\u202f\u205f\u3000\ufeff]/g, " ")
    .replace(/[\u2010-\u2015\u2212]/g, "-")
    .replace(/\p{Nd}/gu, (d) => {
      if (d >= "0" && d <= "9") return d;
      // Unicode puts each script's digits 0–9 in one run: count back to its zero.
      let cp = d.codePointAt(0) ?? 0;
      let n = 0;
      while (n < 9 && /\p{Nd}/u.test(String.fromCodePoint(cp - 1))) {
        cp--;
        n++;
      }
      return String(n);
    });
}

/** "Priya Sharma" → "P.S."; anything that is not a name-like string becomes "?". */
export function initials(value: unknown): string {
  if (typeof value !== "string") return "?";
  const words = value
    .normalize("NFKC")
    .split(/[\s._-]+/)
    .map((w) => w.replace(/[^\p{L}\p{N}]/gu, ""))
    .filter(Boolean);
  if (words.length === 0) return "?";
  return words
    .slice(0, 4)
    .map((w) => `${(Array.from(w)[0] ?? "").toUpperCase()}.`)
    .join("");
}

/** "+91 98765 43210" → "…3210". */
export function lastFour(value: unknown): string {
  const digits = normaliseDigits(String(value ?? "")).replace(/\D/g, "");
  return digits.length >= 4 ? `…${digits.slice(-4)}` : "…";
}

/** "a.b@gmail.com" → "@gmail.com". */
export function emailDomain(value: unknown): string {
  const m = /@([^@\s]+)$/.exec(String(value ?? "").trim());
  return m?.[1] ? `@${m[1].toLowerCase()}` : "@?";
}

function maskPhones(text: string): string {
  return PHONES.reduce((t, re) => t.replace(re, (m) => lastFour(m)), text);
}

/** Masks emails and phone numbers inside free text. Dates, times and ids pass through. */
export function maskText(text: string): string {
  const t = normaliseDigits(text).replace(EMAIL, (_m, domain: string) => `@${domain.toLowerCase()}`);
  let out = "";
  let at = 0;
  for (const m of t.matchAll(PROTECTED)) {
    out += maskPhones(t.slice(at, m.index)) + m[0];
    at = m.index + m[0].length;
  }
  return out + maskPhones(t.slice(at));
}

function maskString(s: string, max: number): string {
  const masked = maskText(s);
  return masked.length > max ? `${masked.slice(0, max)}…` : masked;
}

/** A whole number shaped like a phone: an Indian mobile (with 91 or 0 in front), or 10 to 15 digits. */
function phoneNumber(n: number): boolean {
  if (!Number.isInteger(n)) return false;
  const d = String(Math.abs(n));
  return d.length >= 10 && d.length <= 15;
}

type Ctx = { opts: MaskOptions; depth: number; names: boolean };

function maskValue(value: unknown, key: string | null, ctx: Ctx): unknown {
  let names = ctx.names;
  if (key !== null) {
    if (DROP_KEY.test(key)) return undefined;
    if (BODY_KEY.test(key)) {
      if (!ctx.opts.excerpts || typeof value !== "string") return undefined;
      return maskString(value, EXCERPT_CHARS);
    }
    if (NAME_KEY.test(key)) names = true;
    if (typeof value === "string") {
      if (EMAIL_KEY.test(key) && value.includes("@")) return emailDomain(value);
      if (PHONE_KEY.test(key) && normaliseDigits(value).replace(/\D/g, "").length >= 7) return lastFour(value);
    }
    if (typeof value === "number" && PHONE_KEY.test(key) && String(Math.abs(Math.trunc(value))).length >= 7) {
      return lastFour(value);
    }
  }
  // Under a name key every string is a name, at any depth ({name: {first, last}}, names: […]).
  if (names && typeof value === "string") return initials(value);
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "number") return phoneNumber(value) ? lastFour(value) : value;
  if (typeof value === "string") return maskString(value, STRING_CHARS);
  if (typeof value !== "object") return undefined;
  if (ctx.depth >= MAX_DEPTH) return "[deeper data left out]";
  const next: Ctx = { opts: ctx.opts, depth: ctx.depth + 1, names };
  if (Array.isArray(value)) {
    const out = value.slice(0, ARRAY_ITEMS).map((v) => maskValue(v, null, next));
    if (value.length > ARRAY_ITEMS) out.push(`[${value.length - ARRAY_ITEMS} more left out]`);
    return out.filter((v) => v !== undefined);
  }
  const peopleKeys = key !== null && PEOPLE_MAP_KEY.test(key);
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) {
    const m = maskValue(v, k, next);
    if (m === undefined) continue;
    // A key that is itself a contact (a map keyed by phone or email) is masked like a value; a key in a map of people
    // becomes initials. Two keys that mask alike stay apart.
    let safe = peopleKeys ? initials(k) : maskText(k);
    if (safe in out) {
      let n = 2;
      while (`${safe}#${n}` in out) n++;
      safe = `${safe}#${n}`;
    }
    out[safe] = m;
  }
  return out;
}

/** The masked copy of any JSON-like value; the input is not changed. */
export function maskForAi<T>(value: T, opts: MaskOptions = {}): unknown {
  return maskValue(value, null, { opts, depth: 0, names: false });
}
