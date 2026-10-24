// The PII mask for everything a model reads (spec §11: the AI sees masked contact data only). The database already
// sends contact-free data (one.redact, D-046); this is the second layer, applied in the worker to every prompt input
// and every tool result, whatever produced it: names become initials, phones their last 4 digits, emails their
// domain, and message bodies are left out unless the task may quote them (explain on a Witty incident, with
// ai.allow_message_excerpts set). Secrets and identity documents are always left out.

export type MaskOptions = {
  /** Keep message bodies as short excerpts, themselves masked (explain on a Witty incident only). */
  excerpts?: boolean;
};

const EXCERPT_CHARS = 280;
const STRING_CHARS = 2000;
const ARRAY_ITEMS = 200;
const MAX_DEPTH = 12;

const NAME_KEY =
  /^(name|full_?name|first_?name|last_?name|middle_?name|sur_?name|display_?name|contact_?name|student_?name|guardian_?name|parent_?name|father_?name|mother_?name|counsell?or_?name|sender_?name|recipient_?name|customer_?name|lead_?name|user_?name|profile_?name|push_?name|counsell?or|owner_?name|agent_?name|staff_?name|assignee_?name)$/i;
const PHONE_KEY = /(^|_)(phone|mobile|msisdn|whatsapp|wa_?id|contact_?number|phone_?number|alt_?phone)(_|$)/i;
const EMAIL_KEY = /(^|_)e?mail(_|$)|^email/i;
const BODY_KEY =
  /^(text|body|message|messages_?text|message_?text|message_?body|content|reply|reply_?text|transcript|caption|comment|comments|notes?|remarks?|subject|snippet|raw|prompt|answer_?text)$/i;
const DROP_KEY =
  /(^|_)(token|secret|password|passcode|otp|api_?key|authorization|cookie|address|street|pincode|pin_?code|postcode|dob|date_?of_?birth|pan|pan_?number|aadhaa?r|passport|bank_?account|account_?number|ifsc|upi|card_?number|ip|ip_?address|user_?agent)$/i;

const EMAIL = /[A-Z0-9._%+-]+@([A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,})/gi;
// Digit runs with the separators people write in phone numbers. Whether a run is a phone is decided by its digits
// (phoneDigits), so dates and times ("2026-10-24", "09:15") pass through.
const DIGIT_RUN = /\+?\d[\d \-().]{5,}\d/g;

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

/** The digits of a phone number, or null when the run is not shaped like one (an Indian mobile, or + and 11–15 digits). */
export function phoneDigits(run: string): string | null {
  const digits = run.replace(/\D/g, "");
  const plus = run.trimStart().startsWith("+");
  let core = digits;
  if (core.length === 12 && core.startsWith("91")) core = core.slice(2);
  else if (core.length === 11 && core.startsWith("0")) core = core.slice(1);
  if (core.length === 10 && /^[6-9]/.test(core)) return digits;
  if (plus && digits.length >= 11 && digits.length <= 15) return digits;
  return null;
}

/** "+91 98765 43210" → "…3210". */
export function lastFour(value: unknown): string {
  const digits = String(value ?? "").replace(/\D/g, "");
  return digits.length >= 4 ? `…${digits.slice(-4)}` : "…";
}

/** "a.b@gmail.com" → "@gmail.com". */
export function emailDomain(value: unknown): string {
  const m = /@([^@\s]+)$/.exec(String(value ?? "").trim());
  return m?.[1] ? `@${m[1].toLowerCase()}` : "@?";
}

/** Masks emails and phone numbers inside free text. */
export function maskText(text: string): string {
  return text
    .replace(EMAIL, (_m, domain: string) => `@${domain.toLowerCase()}`)
    .replace(DIGIT_RUN, (run) => (phoneDigits(run) ? lastFour(run) : run));
}

function maskString(s: string, max: number): string {
  const masked = maskText(s);
  return masked.length > max ? `${masked.slice(0, max)}…` : masked;
}

function maskNumber(n: number): number | string {
  return Number.isInteger(n) && phoneDigits(String(Math.abs(n))) ? lastFour(n) : n;
}

function maskValue(value: unknown, key: string | null, opts: MaskOptions, depth: number): unknown {
  if (key !== null) {
    if (DROP_KEY.test(key)) return undefined;
    if (BODY_KEY.test(key)) {
      if (!opts.excerpts || typeof value !== "string") return undefined;
      return maskString(value, EXCERPT_CHARS);
    }
    if (typeof value === "string") {
      if (NAME_KEY.test(key)) return initials(value);
      if (EMAIL_KEY.test(key) && value.includes("@")) return emailDomain(value);
      if (PHONE_KEY.test(key) && value.replace(/\D/g, "").length >= 7) return lastFour(value);
    }
    if (typeof value === "number" && PHONE_KEY.test(key) && String(Math.abs(Math.trunc(value))).length >= 7) {
      return lastFour(value);
    }
  }
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "number") return maskNumber(value);
  if (typeof value === "string") return maskString(value, STRING_CHARS);
  if (typeof value !== "object") return undefined;
  if (depth >= MAX_DEPTH) return "[deeper data left out]";
  if (Array.isArray(value)) {
    const out = value.slice(0, ARRAY_ITEMS).map((v) => maskValue(v, null, opts, depth + 1));
    if (value.length > ARRAY_ITEMS) out.push(`[${value.length - ARRAY_ITEMS} more left out]`);
    return out.filter((v) => v !== undefined);
  }
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) {
    // A key that is itself an email or a phone number (a map keyed by contact) is masked like a value.
    const safeKey = maskText(k);
    const m = maskValue(v, k, opts, depth + 1);
    if (m !== undefined) out[safeKey] = m;
  }
  return out;
}

/** The masked copy of any JSON-like value; the input is not changed. */
export function maskForAi<T>(value: T, opts: MaskOptions = {}): unknown {
  return maskValue(value, null, opts, 0);
}
