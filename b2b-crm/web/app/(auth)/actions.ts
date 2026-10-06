"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { fetchMe, isAllowlistedEmail, isLocked, recordSignIn } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { clientIp, passwordProblem, safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export type FormState = { error?: string; notice?: string } | undefined;

const LOCKED = "Too many failed attempts. Sign-in is locked for 15 minutes.";
const RESTRICTED = "This app is restricted. Your account is not allowed to use the Eduwit Partner CRM. The attempt was logged.";

async function requestContext() {
  const h = await headers();
  return { ip: clientIp(h), user_agent: h.get("user-agent")?.slice(0, 500) ?? null };
}

const credentials = z.object({
  email: z.email().max(254),
  password: z.string().min(1).max(128),
});

/** Email + password, first factor. On success the Admin continues to the TOTP step. */
export async function signInWithPassword(_: FormState, form: FormData): Promise<FormState> {
  const parsed = credentials.safeParse({
    email: String(form.get("email") ?? "").trim().toLowerCase(),
    password: String(form.get("password") ?? ""),
  });
  if (!parsed.success) return { error: "Enter a valid email address and your password." };
  const { email, password } = parsed.data;
  const next = safeNext(String(form.get("next") ?? ""));
  const ctx = await requestContext();

  if (await isLocked(email)) {
    await recordSignIn({ email, method: "password", outcome: "locked", ...ctx });
    return { error: LOCKED };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) {
    await recordSignIn({ email, method: "password", outcome: "failed_password", ...ctx, detail: { code: error?.code ?? null } });
    return { error: "Email or password is incorrect." }; // same message whether or not the account exists
  }

  const result = await fetchMe(supabase);
  if ("setupError" in result || !result.me.allowlisted) {
    await supabase.auth.signOut({ scope: "local" });
    await recordSignIn({ email, user_id: data.user.id, method: "password", outcome: "refused_not_allowlisted", ...ctx });
    return { error: RESTRICTED };
  }
  if (result.me.require_totp && result.me.aal !== "aal2") redirect(`/mfa?next=${encodeURIComponent(next)}`);
  await recordSignIn({ email, user_id: data.user.id, method: "password", outcome: "success", ...ctx });
  redirect(next);
}

/** Sends a reset link only to the allowlisted Admin; the answer is the same for every email. */
export async function requestPasswordReset(_: FormState, form: FormData): Promise<FormState> {
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  if (!z.email().max(254).safeParse(email).success) return { error: "Enter a valid email address." };
  if (await isAllowlistedEmail(email)) {
    const supabase = await createClient();
    await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${siteUrl()}/auth/callback?next=/reset` });
  }
  return { notice: "If this email can sign in here, a reset link is on its way. Open it in this browser; it expires in 1 hour." };
}

/** Sets a new password from a recovery session. */
export async function updatePassword(_: FormState, form: FormData): Promise<FormState> {
  const password = String(form.get("password") ?? "");
  const problem = passwordProblem(password, String(form.get("confirm") ?? ""));
  if (problem) return { error: problem };

  const supabase = await createClient();
  const result = await fetchMe(supabase);
  if ("setupError" in result || !result.me.user_id) redirect("/login?error=link");
  if (!result.me.allowlisted) redirect("/auth/refuse");

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    if (error.code === "insufficient_aal" || error.code === "reauthentication_needed") redirect("/mfa?next=/reset");
    if (error.code === "weak_password") return { error: "That password is too weak or has appeared in a data breach. Choose another." };
    if (error.code === "same_password") return { error: "Choose a password different from your current one." };
    return { error: "The password could not be updated. Try again." };
  }
  await recordSignIn({ email: result.me.email, user_id: result.me.user_id, method: "password_reset", outcome: "success", ...(await requestContext()) });
  redirect("/");
}

// ---------- TOTP (second factor) ----------

async function allowlistedSession() {
  const supabase = await createClient();
  const result = await fetchMe(supabase);
  if ("setupError" in result || !result.me.user_id) redirect("/login");
  if (!result.me.allowlisted) redirect("/auth/refuse");
  return { supabase, me: result.me };
}

export type Enrollment = { factorId: string; qr: string; secret: string } | { error: string };

/** Starts authenticator set-up. Stale unverified factors are removed first so a retry always works. */
export async function startTotpEnrollment(): Promise<Enrollment> {
  const { supabase } = await allowlistedSession();
  const { data: factors } = await supabase.auth.mfa.listFactors();
  if (factors?.totp.some((f) => f.status === "verified")) return { error: "An authenticator is already set up. Enter its code instead." };
  for (const f of factors?.all ?? []) {
    if (f.factor_type === "totp" && f.status === "unverified") await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: "Eduwit Partner CRM", issuer: "Eduwit Partner CRM" });
  if (error || !data) return { error: "Could not start set-up. Try again." };
  return { factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
}

const codeSchema = z.string().regex(/^\d{6}$/);

/** Verifies a 6-digit code (set-up or sign-in). Failures count toward the 15-minute lockout. */
export async function verifyTotp(_: FormState, form: FormData): Promise<FormState> {
  const code = String(form.get("code") ?? "").replace(/\s/g, "");
  const next = safeNext(String(form.get("next") ?? ""));
  if (!codeSchema.safeParse(code).success) return { error: "Enter the 6-digit code from your authenticator app." };

  const { supabase, me } = await allowlistedSession();
  const email = me.email ?? "";
  const ctx = await requestContext();
  if (await isLocked(email)) {
    await supabase.auth.signOut({ scope: "local" });
    await recordSignIn({ email, user_id: me.user_id, method: "totp", outcome: "locked", ...ctx });
    redirect("/login?error=locked");
  }

  let factorId = String(form.get("factorId") ?? "");
  if (!factorId) {
    const { data } = await supabase.auth.mfa.listFactors();
    factorId = data?.totp.find((f) => f.status === "verified")?.id ?? "";
  }
  if (!factorId) return { error: "No authenticator is set up yet." };

  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
  if (error) {
    await recordSignIn({ email, user_id: me.user_id, method: "totp", outcome: "failed_totp", ...ctx });
    if (await isLocked(email)) {
      await supabase.auth.signOut({ scope: "local" });
      redirect("/login?error=locked");
    }
    return { error: "That code did not match. Codes change every 30 seconds; try the current one." };
  }
  await recordSignIn({ email, user_id: me.user_id, method: "totp", outcome: "success", ...ctx });
  redirect(next);
}
