import "server-only";
import { createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { rpc } from "./db";
import { sessionSecret } from "./env";
import { staffAuth } from "./supabase-auth";

export type AdminRole = "viewer" | "content_editor" | "super_admin";
const RANK: Record<AdminRole, number> = { viewer: 1, content_editor: 2, super_admin: 3 };
export const MFA_COOKIE = "ew_admin_mfa";
export const DEVICE_COOKIE = "ew_admin_td";

export interface AdminSession {
  userId: string;
  email: string;
  role: AdminRole;
  displayName: string | null;
  sessionId: string;
  mfa: boolean;
}

const hmac = (data: string) => createHmac("sha256", sessionSecret()).update(data).digest("base64url");

/** Code hash binds the code to the user, so a code leaked for one account is useless for another. */
export function adminCodeHash(userId: string, code: string): string {
  return hmac(`admin-code:${userId}:${code}`);
}
export function newCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}
export function newDeviceToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: hmac(`device:${token}`) };
}
export function deviceHash(token: string): string {
  return hmac(`device:${token}`);
}

/** Second-factor proof: signed, bound to the user and the Supabase session id, valid 12 hours. */
export function signMfa(userId: string, sessionId: string, now = Date.now()): string {
  const body = Buffer.from(JSON.stringify({ u: userId, s: sessionId, e: now + 12 * 3600_000 })).toString("base64url");
  return `${body}.${hmac(`mfa:${body}`)}`;
}
export function verifyMfa(value: string | undefined, userId: string, sessionId: string, now = Date.now()): boolean {
  if (!value) return false;
  const [body, sig] = value.split(".");
  if (!body || !sig) return false;
  const want = Buffer.from(hmac(`mfa:${body}`));
  const got = Buffer.from(sig);
  if (want.length !== got.length || !timingSafeEqual(want, got)) return false;
  try {
    const p = JSON.parse(Buffer.from(body, "base64url").toString()) as { u: string; s: string; e: number };
    return p.u === userId && p.s === sessionId && p.e > now;
  } catch {
    return false;
  }
}

/** Current staff session (null when signed out or not on the allow-list). `mfa` tells whether the code step is done. */
export async function getAdminSession(): Promise<AdminSession | null> {
  const auth = await staffAuth();
  const { data } = await auth.auth.getClaims();
  const claims = data?.claims as { sub?: string; email?: string; session_id?: string } | undefined;
  if (!claims?.sub || !claims.email) return null;
  const admin = await rpc<{ email: string; role: AdminRole; display_name: string | null } | null>("web_admin_resolve", {
    p_user_id: claims.sub,
    p_email: claims.email,
  });
  if (!admin) return null;
  const jar = await cookies();
  const sessionId = claims.session_id ?? "";
  let mfa = verifyMfa(jar.get(MFA_COOKIE)?.value, claims.sub, sessionId);
  if (!mfa) {
    const dev = jar.get(DEVICE_COOKIE)?.value;
    if (dev)
      mfa = await rpc<boolean>("web_admin_device_check", { p_user_id: claims.sub, p_token_hash: deviceHash(dev) });
  }
  return { userId: claims.sub, email: admin.email, role: admin.role, displayName: admin.display_name, sessionId, mfa };
}

/** Page/server-action guard: signed in, allow-listed, second factor done, and at least `min` role. */
export async function requireAdmin(min: AdminRole = "viewer"): Promise<AdminSession> {
  const s = await getAdminSession();
  if (!s) redirect("/admin/login");
  if (!s.mfa) redirect("/admin/verify");
  if (RANK[s.role] < RANK[min]) redirect("/admin?denied=1");
  return s;
}

export function hasRole(s: Pick<AdminSession, "role">, min: AdminRole): boolean {
  return RANK[s.role] >= RANK[min];
}
