import "server-only";
import { createHmac, randomInt } from "node:crypto";
import { cookies } from "next/headers";
import { CONSENT } from "@/content/consent";
import { allowed, CONSENT_COOKIE, parseConsent } from "@/lib/consent";
import { attributionToLead, decodeTouch } from "@/lib/attribution";
import { junkScore } from "@/lib/forms/junk";
import { cleanName, normaliseEmail, normaliseIndianMobile } from "@/lib/forms/validate";
import { rpc } from "./db";
import { email } from "./email";
import { verificationCodeEmail } from "./email/templates";
import { isProduction, sessionSecret } from "./env";
import { errorFields, log } from "./log";
import { hashId, LIMITS, rateLimit } from "./rate-limit";
import { requestContext } from "./request";
import { currentStudent, deviceId, setStudentSession } from "./student-session";
import { verifyTurnstile } from "./turnstile";

/**
 * Email verification for the Witty gate, the application and enquiry forms and student sign-in (spec 7.2, 9.1A, 12).
 * The website issues and checks the 6-digit code (D-005); the database records the attempt, the hashed code, the
 * verification, the consent ledger and the session, and writes the lead through lead_intake only once the email is
 * proven. Abuse controls: honeypot, Turnstile, per-IP / device / email rate limits, disposable-domain and block lists,
 * junk score.
 */
export type Surface = "gate" | "application" | "enquiry" | "signin";

export interface GateContext {
  offering_id?: number;
  group_key?: string;
  university_slug?: string;
  programme_label?: string;
  creator_handle?: string;
}

export interface StartInput {
  surface: Surface;
  context?: GateContext;
  name?: string;
  phone?: string;
  email: string;
  consentVersion?: string;
  marketing?: boolean;
  turnstileToken?: string;
  /** honeypot field: real people never fill it */
  website?: string;
  idempotencyKey: string;
}

export type StartOutcome =
  | { status: "code_sent"; attemptId: string; resendIn: number; maskedEmail: string }
  | { status: "verified"; attemptId: string; reference?: string }
  | { status: "error"; reason: string; message: string };

export type VerifyOutcome =
  | { status: "verified"; attemptId: string; reference?: string; leadId: number | null }
  | { status: "wrong_code"; attemptsLeft: number }
  | { status: "expired" | "too_many_attempts" | "error"; message: string };

/** Adapter for delivering codes (D-005). The Supabase Auth OTP verifier stays disabled until A-AUTH-1 is approved. */
export interface EmailVerifier {
  readonly name: string;
  sendCode(to: string, code: string, purpose: "verify" | "signin", idempotencyKey: string): Promise<void>;
}
export const websiteEmailVerifier: EmailVerifier = {
  name: "website",
  async sendCode(to, code, purpose, idempotencyKey) {
    await email().send(to, verificationCodeEmail(code, purpose, 10), { idempotencyKey });
  },
};
export const supabaseAuthOtpVerifier: EmailVerifier = {
  name: "supabase_auth",
  async sendCode() {
    throw new Error("Supabase Auth OTP verifier is disabled (D-005, A-AUTH-1)");
  },
};
/** Phone OTP adapter (spec 7.2): built, disabled. `require_phone_otp` stays off until a provider exists (S-25). */
export interface PhoneOtpProvider {
  readonly enabled: boolean;
  sendCode(phoneE164: string, code: string): Promise<void>;
}
export const disabledPhoneOtp: PhoneOtpProvider = {
  enabled: false,
  async sendCode() {
    throw new Error("Phone OTP is not configured (S-25)");
  },
};

let verifier: EmailVerifier = websiteEmailVerifier;
/** For tests. */
export function setEmailVerifier(v: EmailVerifier) {
  verifier = v;
}

const MESSAGES: Record<string, string> = {
  invalid_input: "Please check your details and try again.",
  consent: "Please agree to the consent text so a counsellor can help you.",
  turnstile: "We couldn't confirm you're not a robot. Please refresh the page and try again.",
  rate_limited: "Too many attempts. Please wait a few minutes and try again.",
  disposable_email: "Please use your personal or work email — temporary email addresses can't receive our updates.",
  blocked: "We couldn't accept these details. Please contact us on WhatsApp instead.",
  too_many_codes: "You've asked for several codes already. Please wait an hour or contact us on WhatsApp.",
  too_soon: "Please wait a few seconds before asking for another code.",
  send_failed: "We couldn't send the code just now. Please try again in a minute.",
  unavailable: "Something went wrong on our side. Please try again, or contact us on WhatsApp.",
  expired: "That code has expired. Ask for a new one.",
  too_many_attempts: "Too many wrong codes. Ask for a new code.",
};
const err = (reason: string): { status: "error"; reason: string; message: string } => ({
  status: "error",
  reason,
  message: MESSAGES[reason] ?? MESSAGES.unavailable!,
});

export function newCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}
/** The code is bound to the attempt; only the HMAC is stored. */
export function codeHash(attemptKey: string, code: string): string {
  return createHmac("sha256", sessionSecret()).update(`web-code:${attemptKey}:${code}`).digest("base64url");
}
export function maskEmail(e: string): string {
  return e.replace(/^(.)(.*)(@.*)$/, (_, a: string, b: string, c: string) => `${a}${"•".repeat(Math.min(6, Math.max(1, b.length)))}${c}`);
}
const REF_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ";
export function newReference(now = new Date()): string {
  let s = "";
  for (let i = 0; i < 5; i++) s += REF_ALPHABET[randomInt(0, REF_ALPHABET.length)];
  return `EDW-${String(now.getFullYear()).slice(-2)}-${s}`;
}

const deviceType = (ua: string) => (/ipad|tablet/i.test(ua) ? "tablet" : /mobi|android|iphone/i.test(ua) ? "mobile" : "desktop");

/** Attribution from the first/last-touch cookies, plus ad-consent state for the Conversions API (D-047). */
async function attribution(ua: string): Promise<Record<string, unknown>> {
  const jar = await cookies();
  const lead = attributionToLead(decodeTouch(jar.get("ew_ft")?.value), decodeTouch(jar.get("ew_lt")?.value));
  const consent = parseConsent(jar.get(CONSENT_COOKIE)?.value);
  const ad = allowed(consent, "marketing");
  const fbp = ad ? jar.get("_fbp")?.value : undefined;
  const fbc = ad ? jar.get("_fbc")?.value : undefined;
  const clicks = { ...((lead.click_ids as Record<string, string> | undefined) ?? {}), ...(fbp ? { fbp } : {}), ...(fbc ? { fbc } : {}) };
  return JSON.parse(
    JSON.stringify({ ...lead, click_ids: Object.keys(clicks).length ? clicks : undefined, device_type: deviceType(ua), ad_consent: ad }),
  ) as Record<string, unknown>;
}

const isTestPhone = (p: string | null) => !!p && /^\+910000\d{6}$/.test(p);

async function openApplicationIfNeeded(surface: Surface, attemptId: string): Promise<string | undefined> {
  if (surface !== "application" && surface !== "enquiry") return undefined;
  for (let i = 0; i < 3; i++) {
    try {
      const r = await rpc<{ ok: boolean; reference?: string }>("web_application_open", {
        p_attempt: attemptId,
        p_kind: surface === "application" ? "application" : "enquiry",
        p_reference: newReference(),
      });
      if (r.ok) return r.reference;
      return undefined;
    } catch (e) {
      // unique reference collision: retry with a new one
      if (i === 2) throw e;
    }
  }
  return undefined;
}

export async function startVerification(input: StartInput): Promise<StartOutcome> {
  const { ip, userAgent, requestId } = await requestContext();
  const ipHash = hashId(ip);
  const surface = input.surface;
  const emailNorm = normaliseEmail(input.email ?? "");
  const phone = surface === "signin" ? null : normaliseIndianMobile(input.phone ?? "");
  const name = surface === "signin" ? null : cleanName(input.name ?? "");
  if (!emailNorm || (surface !== "signin" && (!phone || !name))) return err("invalid_input");
  if (!/^[\w-]{8,80}$/.test(input.idempotencyKey ?? "")) return err("invalid_input");
  const expectedConsent = surface === "gate" ? CONSENT.gate.version : surface === "signin" ? undefined : CONSENT.form.version;
  if (expectedConsent && input.consentVersion !== expectedConsent) return err("consent");

  // Honeypot: look like success, do nothing (bots learn nothing).
  if (input.website) {
    log("info", "gate.honeypot", { surface, requestId });
    return { status: "code_sent", attemptId: crypto.randomUUID(), resendIn: 30, maskedEmail: maskEmail(emailNorm) };
  }

  const device = await deviceId();
  for (const [limit, id] of [
    [LIMITS.emailCodeSendPerIp, ip],
    [LIMITS.emailCodeSendPerDevice, device],
    [LIMITS.emailCodeSendPerEmail, emailNorm],
  ] as const) {
    if (!(await rateLimit(limit, id)).ok) {
      log("info", "gate.rate_limited", { surface, limit: limit.name, requestId });
      return err("rate_limited");
    }
  }

  const turnstile = await verifyTurnstile(input.turnstileToken, ip);
  if (!turnstile.ok) return err("turnstile");

  const context = Object.fromEntries(Object.entries(input.context ?? {}).filter(([, v]) => v !== undefined && v !== ""));
  const junk = name && phone ? junkScore({ name, phone, email: emailNorm }) : { score: 0, reasons: [] };
  const payload = {
    idempotency_key: `${surface}:${input.idempotencyKey}`,
    surface,
    context,
    name,
    email: emailNorm,
    phone,
    consent_version: expectedConsent ?? null,
    marketing: !!input.marketing,
    attribution: await attribution(userAgent),
    junk_score: junk.score,
    junk_reasons: junk.reasons,
    ip_hash: ipHash,
    device_hash: hashId(device),
    turnstile_ok: turnstile.mocked ? null : turnstile.ok,
    is_test: !isProduction() || isTestPhone(phone),
  };

  try {
    // Signed-in student with the same email: no code needed (spec 9.1A).
    const student = surface === "signin" ? null : await currentStudent();
    if (student && student.email === emailNorm) {
      const r = await rpc<{ ok: boolean; reason?: string; status?: string; attempt_id: string; session_id?: string }>(
        "web_gate_start_trusted",
        { p: payload, p_student: student.studentId },
      );
      if (r.ok) {
        if (r.session_id) await setStudentSession(r.session_id);
        const reference = await openApplicationIfNeeded(surface, r.attempt_id);
        log("info", "gate.trusted", { surface, requestId });
        return { status: "verified", attemptId: r.attempt_id, reference };
      }
    }

    const code = newCode();
    const r = await rpc<{ ok: boolean; reason?: string; status?: string; attempt_id?: string }>("web_gate_start", {
      p: { ...payload, code_hash: codeHash(payload.idempotency_key, code) },
    });
    if (!r.ok) {
      log("info", "gate.refused", { surface, reason: r.reason, requestId });
      return err(r.reason ?? "unavailable");
    }
    if (r.status === "already_verified") return { status: "verified", attemptId: r.attempt_id! };
    try {
      await verifier.sendCode(emailNorm, code, surface === "signin" ? "signin" : "verify", `code:${r.attempt_id}:${code}`);
    } catch (e) {
      log("error", "gate.send_failed", { surface, requestId, ...errorFields(e) });
      return err("send_failed");
    }
    log("info", "gate.code_sent", { surface, junk: junk.score, requestId });
    return { status: "code_sent", attemptId: r.attempt_id!, resendIn: 30, maskedEmail: maskEmail(emailNorm) };
  } catch (e) {
    log("error", "gate.start_failed", { surface, requestId, ...errorFields(e) });
    return err("unavailable");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** The attempt's idempotency key (what the code hash is bound to) and surface. */
async function attemptInfo(attemptId: string): Promise<{ key: string; surface: Surface; email: string } | null> {
  const r = await rpc<{ key: string; surface: Surface; email: string } | null>("web_gate_attempt_info", { p_attempt: attemptId });
  return r ?? null;
}

export async function resendCode(attemptId: string): Promise<StartOutcome> {
  if (!UUID.test(attemptId)) return err("expired");
  const { ip, requestId } = await requestContext();
  if (!(await rateLimit(LIMITS.emailCodeSendPerIp, ip)).ok) return err("rate_limited");
  try {
    const info = await attemptInfo(attemptId);
    if (!info) return err("expired");
    const code = newCode();
    const r = await rpc<{ ok: boolean; reason?: string; resend_in?: number; email?: string }>("web_gate_resend", {
      p_attempt: attemptId,
      p_code_hash: codeHash(info.key, code),
    });
    if (!r.ok) return r.reason === "too_soon" ? { ...err("too_soon") } : err(r.reason ?? "unavailable");
    await verifier.sendCode(info.email, code, info.surface === "signin" ? "signin" : "verify", `code:${attemptId}:${code}`);
    log("info", "gate.code_resent", { surface: info.surface, requestId });
    return { status: "code_sent", attemptId, resendIn: r.resend_in ?? 30, maskedEmail: maskEmail(info.email) };
  } catch (e) {
    log("error", "gate.resend_failed", { requestId, ...errorFields(e) });
    return err("send_failed");
  }
}

export async function verifyCode(attemptId: string, code: string): Promise<VerifyOutcome> {
  if (!UUID.test(attemptId) || !/^\d{6}$/.test(code)) return { status: "wrong_code", attemptsLeft: 4 };
  const { ip, userAgent, requestId } = await requestContext();
  if (!(await rateLimit(LIMITS.emailCodeVerifyPerIp, ip)).ok) return { status: "error", message: MESSAGES.rate_limited! };
  try {
    const info = await attemptInfo(attemptId);
    if (!info) return { status: "expired", message: MESSAGES.expired! };
    const r = await rpc<{ ok: boolean; reason?: string; status?: string; attempts_left?: number; session_id?: string; lead_id?: number | null }>(
      "web_gate_verify",
      { p_attempt: attemptId, p_code_hash: codeHash(info.key, code), p_ua_hash: hashId(userAgent) },
    );
    if (!r.ok) {
      if (r.reason === "wrong_code") return { status: "wrong_code", attemptsLeft: r.attempts_left ?? 0 };
      if (r.reason === "too_many_attempts") return { status: "too_many_attempts", message: MESSAGES.too_many_attempts! };
      return { status: "expired", message: MESSAGES.expired! };
    }
    if (r.session_id) await setStudentSession(r.session_id);
    const reference = await openApplicationIfNeeded(info.surface, attemptId);
    log("info", "gate.verified", { surface: info.surface, requestId, lead: r.lead_id ? "yes" : "no" });
    return { status: "verified", attemptId, reference, leadId: r.lead_id ?? null };
  } catch (e) {
    log("error", "gate.verify_failed", { requestId, ...errorFields(e) });
    return { status: "error", message: MESSAGES.unavailable! };
  }
}
