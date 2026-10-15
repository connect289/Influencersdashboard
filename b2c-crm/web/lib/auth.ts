import "server-only";
import { cache } from "react";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { ALLOWED_DOMAIN } from "@/lib/env";
import { clientIp, DEVICE_COOKIE } from "@/lib/security";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";

export type Role = "admin" | "marketing" | "counsellor" | "sales_head";

/** b2c.me(): who is signed in and what they may use. The database is the authority; these checks only route. */
export type Me = {
  user_id: string | null;
  email: string | null;
  known: boolean;
  active: boolean;
  role: Role | null;
  full_name: string | null;
  /** This session passed the second step (emailed code or a trusted device). */
  checked: boolean;
  interface: "sales" | "marketing" | "admin" | null;
  /** This session was signed out remotely (b2c.session_revoke): b2c.my_role() is null although the person is active. */
  revoked?: boolean;
};

export type MeResult = { me: Me } | { setupError: "b2c_not_exposed" };

export async function fetchMe(supabase: ServerSupabase): Promise<MeResult> {
  // my_role() is null for a session signed out from another device (E10); asked alongside me() to cost no extra wait.
  const [{ data, error }, role] = await Promise.all([supabase.rpc("me"), supabase.rpc("my_role")]);
  if (error) {
    // PostgREST answers PGRST106 when b2c is not in the Data API's exposed schemas (README step 1).
    if (error.code === "PGRST106") return { setupError: "b2c_not_exposed" };
    throw new Error(`b2c.me() failed: ${error.message}`);
  }
  const me = data as Me;
  if (me.user_id && me.known && me.active && me.role && me.checked && !role.error && role.data === null) me.revoked = true;
  return { me };
}

export const getMe = cache(async (): Promise<MeResult> => fetchMe(await createClient()));

export function isAllowedEmail(email: string | null | undefined): boolean {
  return typeof email === "string" && email.toLowerCase().endsWith("@" + ALLOWED_DOMAIN);
}

/** Where each person lands after signing in. */
export function homeFor(me: Pick<Me, "role">): string {
  return me.role === "admin" || me.role === "marketing" ? "/w" : "/s";
}

export type Area = "sales" | "workspace";
const AREA_ROLES: Record<Area, Role[]> = {
  sales: ["counsellor", "sales_head", "admin"],
  workspace: ["admin", "marketing"],
};

/**
 * Gate for every page in the app: signed out → /login; unknown or inactive → /pending; second step not done on this
 * session → a trusted-device cookie is tried, else /verify; wrong area → the person's own home.
 */
export async function requireUser(area: Area, next = "/"): Promise<Me> {
  const result = await getMe();
  if ("setupError" in result) redirect("/login?error=setup");
  const { me } = result;
  if (!me.user_id) redirect("/login");
  if (me.revoked) redirect("/auth/revoked");
  if (!isAllowedEmail(me.email)) redirect("/auth/refuse");
  if (!me.known || !me.active || !me.role) redirect("/pending");
  if (!me.checked && !(await trustDevice())) redirect(`/verify?next=${encodeURIComponent(next)}`);
  if (!AREA_ROLES[area].includes(me.role)) redirect(homeFor(me));
  return me;
}

/** For server actions: throws instead of redirecting, so a forged call can never proceed. */
export async function assertUser(roles?: Role[]): Promise<Me> {
  const result = await getMe();
  if ("setupError" in result) throw new Error("not allowed");
  const { me } = result;
  if (!me.user_id || !me.active || !me.role || !me.checked || me.revoked) throw new Error("not allowed");
  if (roles && !roles.includes(me.role)) throw new Error("not allowed");
  return me;
}

/** A trusted-device cookie marks this session checked (b2c.device_trust_check records it). */
export async function trustDevice(): Promise<boolean> {
  const token = (await cookies()).get(DEVICE_COOKIE)?.value;
  if (!token || !/^[0-9a-f]{64}$/.test(token)) return false;
  const supabase = await createClient();
  const { data } = await supabase.rpc("device_trust_check", { p_token: token });
  if (data === true) await noteSession(supabase);
  return data === true;
}

/** Records this session's browser and address for "Signed-in devices" (b2c.session_note), after the second step. */
export async function noteSession(supabase?: ServerSupabase): Promise<void> {
  try {
    const h = await headers();
    const db = supabase ?? (await createClient());
    const { error } = await db.rpc("session_note", { p_user_agent: h.get("user-agent")?.slice(0, 300) ?? null, p_ip: clientIp(h) });
    if (error) console.error("session_note failed", error.code);
  } catch (e) {
    console.error("session_note failed", e instanceof Error ? e.message : e); // never block a sign-in on it
  }
}

export const INVITE_EXPIRED = "Your invitation has expired: ask the Admin to send a new one";

/** False when the person was invited more than the invitation period ago and never signed in (b2c.invite_ok, E9). */
export async function inviteOk(email: string | null | undefined): Promise<boolean> {
  if (!email) return true;
  const { data, error } = await adminClient().rpc("invite_ok", { p_email: email });
  if (error) {
    console.error("invite_ok failed", error.code); // an unreadable invitation must not lock everyone out
    return true;
  }
  return data !== false;
}

// ---------- service-role helpers (signed-out flows only) ----------

export type SignInEntry = {
  email: string | null;
  user_id?: string | null;
  method: "google" | "password" | "email_code" | "password_reset" | "password_link" | "sign_out";
  outcome: "success" | "refused_domain" | "refused_unknown" | "failed_password" | "locked" | "code_sent" | "signed_out" | "link_sent" | "mail_not_configured" | "mail_failed" | "password_set"
    | "invite_expired" | "breached_password" | "revoked";
  ip?: string | null;
  user_agent?: string | null;
  detail?: Record<string, unknown>;
};

export async function recordSignIn(entry: SignInEntry): Promise<void> {
  const { error } = await adminClient().rpc("record_sign_in", { p: entry });
  if (error) console.error("record_sign_in failed", error.code); // never block sign-in on the audit write
}

export async function isLocked(email: string): Promise<boolean> {
  const { data, error } = await adminClient().rpc("sign_in_locked", { p_email: email });
  if (error) throw new Error(`lockout check failed (${error.code ?? "unknown"})`); // fail closed
  return data === true;
}

/** A 6-digit code for this user and session (b2c.mfa_issue keeps only its hash; 5 per hour). */
export async function issueCode(userId: string, sessionId: string): Promise<string> {
  const { data, error } = await adminClient().rpc("mfa_issue", { p_user: userId, p_session: sessionId });
  if (error) throw new Error(error.message);
  return String(data);
}
