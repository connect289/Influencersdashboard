"use server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe, SetupError } from "@/lib/auth/guards";
import { maskEmail, OTP_EMAIL_COOKIE } from "@/lib/auth/landing";
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { passwordLinkEmail, staffCodeEmail } from "@/lib/notify/templates";
import { formText } from "@/lib/forms";
import { rateLimit } from "@/lib/rate-limit";
import { requestContext } from "@/lib/request-context";
import {
  breachedPassword,
  DEVICE_COOKIE,
  DEVICE_COOKIE_DAYS,
  PASSWORD_MAX,
  PASSWORD_MIN,
  safeNext,
} from "@/lib/security";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { linkPortalAccount, portalNext } from "@/lib/auth/link";

export type FormState = { error?: string; notice?: string; fieldErrors?: Record<string, string> } | undefined;

const emailSchema = z.email().max(254);

type SignInMethod = "password" | "google" | "email_otp" | "email_code" | "trusted_device" | "magic_link";
type Outcome = "ok" | "failed" | "refused" | "locked";

async function record(
  email: string,
  portal: "staff" | "creator",
  method: SignInMethod,
  outcome: Outcome,
  reason: string | null,
  userId?: string,
) {
  const ctx = await requestContext();
  const { error } = await adminClient().rpc("sign_in_record", {
    p_email: email,
    p_portal: portal,
    p_method: method,
    p_outcome: outcome,
    p_reason: reason ?? undefined,
    p_user: userId,
    p_ip: ctx.ip ?? undefined,
    p_ua: ctx.userAgent ?? undefined,
  });
  if (error) log.warn("sign_in_record.failed", { error: error.message });
}

async function ipKey(): Promise<string> {
  return (await requestContext()).ip ?? "unknown";
}

// ---------------------------------------------------------------------------------------------------------------
// Staff: email + password, then the emailed code
// ---------------------------------------------------------------------------------------------------------------
const staffCredentials = z.object({ email: emailSchema, password: z.string().min(1).max(PASSWORD_MAX) });

export async function staffSignIn(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const parsed = staffCredentials.safeParse({
    email: formText(form, "email").trim().toLowerCase(),
    password: formText(form, "password"),
  });
  if (!parsed.success) return { error: t("auth.errors.invalidCredentialsFormat") };
  const { email, password } = parsed.data;
  const next = safeNext(formText(form, "next"), "/admin");

  const limited = await rateLimit("staff_sign_in", await ipKey());
  if (!limited.ok) return { error: t("auth.errors.tooManyAttempts") };
  const locked = await adminClient().rpc("sign_in_locked", { p_email: email });
  if (locked.data === true) {
    await record(email, "staff", "password", "locked", "locked");
    return { error: t("auth.errors.locked") };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    await record(email, "staff", "password", "failed", error.code ?? "unknown");
    return { error: t("auth.errors.wrongPassword") };
  }
  try {
    const me = await fetchMe(supabase);
    if (me.kind !== "staff" || me.staff?.status !== "active") {
      await record(email, "staff", "password", "refused", `kind:${me.kind ?? "none"}`, data.user.id);
      await supabase.auth.signOut({ scope: "local" });
      return { error: t("auth.errors.notStaff") };
    }
    await supabase.rpc("session_register");
  } catch (e) {
    await supabase.auth.signOut({ scope: "local" });
    return { error: e instanceof SetupError ? t("auth.errors.setup") : t("auth.errors.unavailable") };
  }
  await record(email, "staff", "password", "ok", null, data.user.id);
  redirect(`/verify?next=${encodeURIComponent(next)}`);
}

export async function sendStaffCode(_: FormState): Promise<FormState> {
  const t = await getTranslations();
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims.sub;
  const sessionId = (claims?.claims as { session_id?: string } | undefined)?.session_id;
  if (!userId || !sessionId) redirect("/login/staff");
  const limited = await rateLimit("code_send", userId);
  if (!limited.ok) return { error: t("auth.errors.tooManyCodes") };

  const me = await fetchMe(supabase);
  if (me.kind !== "staff" || !me.staff) redirect("/no-access");
  if (!me.session?.registered) await supabase.rpc("session_register");
  const issued = await adminClient().rpc("mfa_issue", { p_user: userId, p_session: sessionId });
  const r = issued.data as { ok: boolean; code?: string; error?: string } | null;
  if (issued.error || !r?.ok || !r.code) {
    return { error: r?.error === "too_many_codes" ? t("auth.errors.tooManyCodes") : t("auth.errors.codeNotSent") };
  }
  const to = me.email ?? "";
  try {
    await emailProvider().send({
      ...staffCodeEmail(r.code, me.staff.full_name),
      to,
      idempotencyKey: `code:${sessionId}:${Date.now()}`,
    });
  } catch (e) {
    log.error("staff_code.send_failed", { error: errorMessage(e) });
    await record(to, "staff", "email_code", "failed", "mail_failed", userId);
    return { error: t("auth.errors.mailFailed") };
  }
  return { notice: t("auth.verify.sent", { email: maskEmail(to) }) };
}

export async function verifyStaffCode(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const code = formText(form, "code").replace(/\s/g, "");
  const trust = form.get("trust") === "on";
  const next = safeNext(formText(form, "next"), "/admin");
  if (!/^\d{6}$/.test(code)) return { error: t("auth.errors.codeFormat") };
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims.sub;
  if (!userId) redirect("/login/staff");
  const limited = await rateLimit("code_verify", userId);
  if (!limited.ok) return { error: t("auth.errors.tooManyAttempts") };

  const ctx = await requestContext();
  const { data, error } = await supabase.rpc("mfa_verify", {
    p_code: code,
    p_trust: trust,
    p_label: ctx.userAgent?.slice(0, 120) ?? undefined,
  });
  const r = data as { ok: boolean; error?: string; attempts_left?: number; device_token?: string | null } | null;
  if (error || !r) return { error: t("auth.errors.unavailable") };
  if (!r.ok) {
    await record(claims.claims.email ?? "", "staff", "email_code", "failed", r.error ?? "invalid", userId);
    if (r.error === "expired") return { error: t("auth.errors.codeExpired") };
    if (r.error === "too_many_attempts") return { error: t("auth.errors.codeLocked") };
    return { error: t("auth.errors.codeWrong", { left: r.attempts_left ?? 0 }) };
  }
  await record(claims.claims.email ?? "", "staff", "email_code", "ok", null, userId);
  if (r.device_token) {
    (await cookies()).set(DEVICE_COOKIE, r.device_token, {
      httpOnly: true,
      secure: env().NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: DEVICE_COOKIE_DAYS * 24 * 60 * 60,
    });
  }
  redirect(next);
}

/** "First time, or forgot your password?" Sends a one-time link through the portal's own mail (same answer either way). */
export async function requestPasswordLink(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const email = formText(form, "email").trim().toLowerCase();
  if (!emailSchema.safeParse(email).success) return { error: t("auth.errors.emailFormat") };
  const done = { notice: t("auth.password.linkSent") };
  if (!(await rateLimit("password_link", email)).ok || !(await rateLimit("password_link", await ipKey())).ok)
    return done;

  const db = adminClient();
  const { data: staff } = await db
    .from("staff_profiles")
    .select("user_id, full_name, status")
    .eq("email", email)
    .maybeSingle();
  if (!staff || staff.status !== "active") {
    await record(email, "staff", "magic_link", "refused", "not_staff");
    return done;
  }
  const { data, error } = await db.auth.admin.generateLink({ type: "recovery", email });
  if (error || !data.properties.hashed_token) {
    log.error("password_link.generate_failed", { error: error?.message ?? "no token" });
    return { error: t("auth.errors.unavailable") };
  }
  const link = `${env().NEXT_PUBLIC_SITE_URL}/auth/confirm?token_hash=${encodeURIComponent(data.properties.hashed_token)}&type=recovery&next=/password/new`;
  try {
    await emailProvider().send({ ...passwordLinkEmail(link, staff.full_name), to: email });
  } catch (e) {
    log.error("password_link.send_failed", { error: errorMessage(e) });
    return { error: t("auth.errors.mailFailed") };
  }
  await record(email, "staff", "magic_link", "ok", "password_link_sent", staff.user_id);
  return done;
}

const newPassword = z
  .object({ password: z.string().min(PASSWORD_MIN).max(PASSWORD_MAX), confirm: z.string() })
  .refine((v) => v.password === v.confirm, { path: ["confirm"], message: "mismatch" });

export async function setNewPassword(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const parsed = newPassword.safeParse({ password: formText(form, "password"), confirm: formText(form, "confirm") });
  if (!parsed.success) {
    const mismatch = parsed.error.issues.some((i) => i.path[0] === "confirm");
    return { error: mismatch ? t("auth.password.mismatch") : t("auth.password.tooShort", { min: PASSWORD_MIN }) };
  }
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) redirect("/login/staff?reason=link");
  const breach = await breachedPassword(parsed.data.password);
  if (breach.breached) return { error: t("auth.password.breached") };
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { error: t("auth.password.notSaved") };
  redirect("/verify?next=/admin");
}

// ---------------------------------------------------------------------------------------------------------------
// Creators: email OTP (no password), or Google
// ---------------------------------------------------------------------------------------------------------------
export async function creatorSendOtp(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const email = formText(form, "email").trim().toLowerCase();
  if (!emailSchema.safeParse(email).success) return { error: t("auth.errors.emailFormat") };
  if (
    !(await rateLimit("creator_otp_send_ip", await ipKey())).ok ||
    !(await rateLimit("creator_otp_send_email", email)).ok
  ) {
    return { error: t("auth.errors.tooManyCodes") };
  }
  const supabase = await createClient();
  // shouldCreateUser: false. Only invited creators (whose auth account the portal created) receive a code. The
  // response is the same for unknown emails, so the form can't be used to discover who is registered.
  const { error } = await supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } });
  if (error && !/signups not allowed|user not found/i.test(error.message)) {
    log.warn("creator_otp.send_failed", { error_code: error.code ?? null, status: error.status ?? null });
    if (error.status === 429) return { error: t("auth.errors.tooManyCodes") };
  }
  await record(email, "creator", "email_otp", error ? "refused" : "ok", error ? "otp_not_sent" : "otp_sent");
  (await cookies()).set(OTP_EMAIL_COOKIE, email, {
    httpOnly: true,
    secure: env().NODE_ENV === "production",
    sameSite: "lax",
    path: "/login",
    maxAge: 15 * 60,
  });
  const next = safeNext(formText(form, "next"), "/creator");
  redirect(`/login/code?next=${encodeURIComponent(next)}`);
}

export async function creatorVerifyOtp(_: FormState, form: FormData): Promise<FormState> {
  const t = await getTranslations();
  const token = formText(form, "code").replace(/\s/g, "");
  const next = safeNext(formText(form, "next"), "/creator");
  const email = (await cookies()).get(OTP_EMAIL_COOKIE)?.value ?? "";
  if (!emailSchema.safeParse(email).success) redirect("/login?reason=expired");
  if (!/^\d{6,8}$/.test(token)) return { error: t("auth.errors.codeFormat") };
  if (!(await rateLimit("creator_otp_verify", email)).ok) return { error: t("auth.errors.tooManyAttempts") };

  const supabase = await createClient();
  const { data, error } = await supabase.auth.verifyOtp({ email, token, type: "email" });
  if (error || !data.user) {
    await record(email, "creator", "email_otp", "failed", error?.code ?? "invalid");
    return { error: t("auth.errors.otpWrong") };
  }
  const kind = await linkPortalAccount(supabase);
  if (!kind) {
    await record(email, "creator", "email_otp", "refused", "not_registered", data.user.id);
    await supabase.auth.signOut({ scope: "local" });
    redirect("/no-access?portal=creator");
  }
  await supabase.rpc("session_register");
  await record(email, "creator", "email_otp", "ok", kind === "agency" ? "agency" : null, data.user.id);
  (await cookies()).delete({ name: OTP_EMAIL_COOKIE, path: "/login" });
  redirect(portalNext(kind, next));
}
