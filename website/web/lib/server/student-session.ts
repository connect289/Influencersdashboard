import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { cache } from "react";
import { rpc } from "./db";
import { isDeployed, sessionSecret } from "./env";

/**
 * Student sessions (spec 7.2 "verified users stay signed in", spec 12). The cookie carries only the session id, signed;
 * the web_student_sessions row allows revocation and expiry (90 days). Supabase Auth is reserved for staff (D-005).
 */
export const STUDENT_COOKIE = "ew_sid";
export const DEVICE_COOKIE = "ew_did";
const MAX_AGE = 60 * 60 * 24 * 90;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const sign = (data: string) => createHmac("sha256", sessionSecret()).update(`student:${data}`).digest("base64url");

export function signSessionId(sid: string): string {
  return `${sid}.${sign(sid)}`;
}

export function readSessionId(value: string | undefined): string | null {
  if (!value) return null;
  const [sid, sig] = value.split(".");
  if (!sid || !sig || !UUID.test(sid)) return null;
  const want = Buffer.from(sign(sid));
  const got = Buffer.from(sig);
  return want.length === got.length && timingSafeEqual(want, got) ? sid : null;
}

export interface Student {
  studentId: string;
  sessionId: string;
  email: string;
  name: string | null;
  phone: string | null;
  leadId: number | null;
}

/** The signed-in student for this request, or null. Cached per request. */
export const currentStudent = cache(async (): Promise<Student | null> => {
  const jar = await cookies();
  const sid = readSessionId(jar.get(STUDENT_COOKIE)?.value);
  if (!sid) return null;
  const r = await rpc<{ student_id: string; email: string; name: string | null; phone: string | null; lead_id: number | null } | null>(
    "web_session_check",
    { p_sid: sid },
  ).catch(() => null);
  if (!r) return null;
  return { studentId: r.student_id, sessionId: sid, email: r.email, name: r.name, phone: r.phone, leadId: r.lead_id };
});

const cookieOpts = { httpOnly: true, secure: true, sameSite: "lax" as const, path: "/" };
/** Secure on every deployed site (production and preview are HTTPS-only); plain http only on a developer machine. */
const secure = () => isDeployed();

/** Server actions / route handlers only. */
export async function setStudentSession(sid: string) {
  (await cookies()).set(STUDENT_COOKIE, signSessionId(sid), { ...cookieOpts, secure: secure(), maxAge: MAX_AGE });
}

export async function clearStudentSession() {
  const jar = await cookies();
  const sid = readSessionId(jar.get(STUDENT_COOKIE)?.value);
  if (sid) await rpc("web_session_revoke", { p_sid: sid }).catch(() => undefined);
  jar.delete(STUDENT_COOKIE);
}

/** A random, first-party device id used only for per-device rate limits (stored hashed). */
export async function deviceId(): Promise<string> {
  const jar = await cookies();
  const existing = jar.get(DEVICE_COOKIE)?.value;
  if (existing && /^[\w-]{16,64}$/.test(existing)) return existing;
  const id = crypto.randomUUID();
  jar.set(DEVICE_COOKIE, id, { ...cookieOpts, secure: secure(), maxAge: 60 * 60 * 24 * 365 });
  return id;
}
