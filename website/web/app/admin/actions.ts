"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import {
  DEVICE_COOKIE,
  MFA_COOKIE,
  adminCodeHash,
  getAdminSession,
  newCode,
  newDeviceToken,
  signMfa,
} from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { email } from "@/lib/server/email";
import { verificationCodeEmail } from "@/lib/server/email/templates";
import { siteUrl } from "@/lib/server/env";
import { log } from "@/lib/server/log";
import { LIMITS, hashId, rateLimit } from "@/lib/server/rate-limit";
import { requestContext } from "@/lib/server/request";
import { staffAuth } from "@/lib/server/supabase-auth";

export type ActionState = { error?: string; info?: string } | null;

const cookieOpts = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/admin",
};

export async function signInWithPassword(_prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = z
    .object({ email: z.email(), password: z.string().min(8).max(200) })
    .safeParse({ email: form.get("email"), password: form.get("password") });
  if (!parsed.success) return { error: "Enter your work email and password." };
  const { ip } = await requestContext();
  if (!(await rateLimit({ name: "admin_login", limit: 10, windowSeconds: 900 }, `${ip}:${parsed.data.email}`)).ok)
    return { error: "Too many attempts. Try again in 15 minutes." };
  const auth = await staffAuth();
  const { error } = await auth.auth.signInWithPassword(parsed.data);
  if (error) {
    log("warn", "admin.signin_failed", { reason: error.code ?? error.name });
    return { error: "Email or password is incorrect." };
  }
  const s = await getAdminSession();
  if (!s) {
    await auth.auth.signOut();
    return { error: "This account does not have access to the website admin." };
  }
  redirect(s.mfa ? "/admin" : "/admin/verify");
}

export async function signInWithGoogle(): Promise<void> {
  const auth = await staffAuth();
  const { data, error } = await auth.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: siteUrl("/admin/auth/callback") },
  });
  if (error || !data.url) redirect("/admin/login?error=google");
  redirect(data.url);
}

export async function sendAdminCode(): Promise<ActionState> {
  const s = await getAdminSession();
  if (!s) redirect("/admin/login");
  const { ip } = await requestContext();
  if (!(await rateLimit(LIMITS.emailCodeSendPerIp, ip)).ok)
    return { error: "Too many codes requested. Try again later." };
  const code = newCode();
  const res = await rpc<{ ok: boolean; reason?: string }>("web_admin_code_issue", {
    p_user_id: s.userId,
    p_code_hash: adminCodeHash(s.userId, code),
    p_ip_hash: hashId(ip),
  });
  if (!res.ok) return { error: "Too many codes in the last hour. Try again later." };
  try {
    await email().send(s.email, verificationCodeEmail(code, "admin"));
  } catch (err) {
    log("error", "admin.code_email_failed", { message: err instanceof Error ? err.message : String(err) });
    return { error: "We couldn't send the code. Try again in a minute." };
  }
  return { info: `We sent a 6-digit code to ${s.email}.` };
}

export async function verifyAdminCode(_prev: ActionState, form: FormData): Promise<ActionState> {
  const s = await getAdminSession();
  if (!s) redirect("/admin/login");
  const code = String(form.get("code") ?? "").replace(/\D/g, "");
  if (code.length !== 6) return { error: "Enter the 6-digit code." };
  if (!(await rateLimit(LIMITS.emailCodeVerifyPerEmail, s.email)).ok)
    return { error: "Too many attempts. Request a new code later." };
  const res = await rpc<{ ok: boolean; reason?: string; attempts_left?: number }>("web_admin_code_verify", {
    p_user_id: s.userId,
    p_code_hash: adminCodeHash(s.userId, code),
  });
  if (!res.ok) {
    const msg =
      res.reason === "wrong_code"
        ? `That code is not right. ${res.attempts_left ?? 0} attempts left.`
        : res.reason === "too_many_attempts"
          ? "Too many wrong codes. Request a new one."
          : "The code expired. Request a new one.";
    return { error: msg };
  }
  const jar = await cookies();
  jar.set(MFA_COOKIE, signMfa(s.userId, s.sessionId), { ...cookieOpts, maxAge: 12 * 3600 });
  if (form.get("trust") === "on") {
    const { token, hash } = newDeviceToken();
    const { userAgent } = await requestContext();
    await rpc("web_admin_device_add", { p_user_id: s.userId, p_token_hash: hash, p_label: userAgent.slice(0, 120) });
    jar.set(DEVICE_COOKIE, token, { ...cookieOpts, maxAge: 30 * 24 * 3600 });
  }
  redirect("/admin");
}

export async function signOutAdmin(): Promise<void> {
  const auth = await staffAuth();
  await auth.auth.signOut();
  const jar = await cookies();
  jar.delete({ name: MFA_COOKIE, path: "/admin" });
  redirect("/admin/login");
}
