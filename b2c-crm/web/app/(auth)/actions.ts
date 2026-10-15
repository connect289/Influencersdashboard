"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { fetchMe, homeFor, isAllowedEmail, isLocked, issueCode, recordSignIn } from "@/lib/auth";
import { codeEmail, passwordEmail, sendMail } from "@/lib/mail";
import { siteUrl } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";
import { clientIp, DEVICE_COOKIE, passwordProblem, safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export type FormState = { error?: string; notice?: string } | undefined;

const LOCKED = "Too many failed attempts. Sign-in is locked for 15 minutes.";
const SETUP = "Your sign-in worked, but the app cannot reach its data yet. In Supabase, add b2c under Project Settings → Data API → Exposed schemas, save, and sign in again.";
const DOMAIN = "Only @eduwit.in accounts can sign in. The attempt was logged.";

async function requestContext() {
  const h = await headers();
  return { ip: clientIp(h), user_agent: h.get("user-agent")?.slice(0, 500) ?? null };
}

const credentials = z.object({ email: z.email().max(254), password: z.string().min(1).max(128) });

/** Email + password, the first step. The second step (a code to the company inbox) follows unless this device is trusted. */
export async function signInWithPassword(_: FormState, form: FormData): Promise<FormState> {
  const parsed = credentials.safeParse({
    email: String(form.get("email") ?? "").trim().toLowerCase(),
    password: String(form.get("password") ?? ""),
  });
  if (!parsed.success) return { error: "Enter a valid email address and your password." };
  const { email, password } = parsed.data;
  const next = safeNext(String(form.get("next") ?? ""));
  const ctx = await requestContext();
  if (!isAllowedEmail(email)) {
    await recordSignIn({ email, method: "password", outcome: "refused_domain", ...ctx });
    return { error: DOMAIN };
  }

  let locked: boolean;
  try {
    locked = await isLocked(email);
  } catch (e) {
    return { error: String(e).includes("PGRST106") ? SETUP : "Sign-in is unavailable right now. Try again in a minute." };
  }
  if (locked) {
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
  if ("setupError" in result) {
    await supabase.auth.signOut({ scope: "local" });
    return { error: SETUP };
  }
  await recordSignIn({ email, user_id: data.user.id, method: "password", outcome: "success", ...ctx });
  if (!result.me.known || !result.me.active) redirect("/pending");
  redirect(`/verify?next=${encodeURIComponent(next === "/" ? homeFor(result.me) : next)}`);
}

/** Sends a fresh 6-digit code to the person's company inbox, bound to this session. */
export async function sendCode(_: FormState, form: FormData): Promise<FormState> {
  void form;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  const sessionId = (claims?.claims as { session_id?: string } | undefined)?.session_id;
  if (!userId || !sessionId) redirect("/login");
  const result = await fetchMe(supabase);
  if ("setupError" in result) return { error: SETUP };
  const { me } = result;
  if (!me.known || !me.active || !me.email) redirect("/pending");
  let code: string;
  try {
    code = await issueCode(userId, sessionId);
  } catch (e) {
    return { error: String((e as Error).message).includes("too many") ? "Too many codes this hour. Try again later." : "The code could not be sent. Try again." };
  }
  const mail = codeEmail(code, me.full_name);
  const sent = await sendMail({ ...mail, to: me.email }).catch((e: unknown) => {
    console.error("[mail] sign-in code not sent:", (e as Error).message);
    return null;
  });
  if (!sent) {
    await recordSignIn({ email: me.email, user_id: userId, method: "email_code", outcome: "mail_failed", ...(await requestContext()) });
    return { error: "The code email could not be sent (the email settings need checking). Tell the Admin." };
  }
  await recordSignIn({ email: me.email, user_id: userId, method: "email_code", outcome: "code_sent", ...(await requestContext()) });
  return { notice: `A code is on its way to ${me.email}. It expires in 10 minutes.` };
}

/** Checks the code (b2c.mfa_verify); on success marks the session checked and, if asked, trusts this browser for 30 days. */
export async function verifyCode(_: FormState, form: FormData): Promise<FormState> {
  const code = String(form.get("code") ?? "").replace(/\s/g, "");
  const trust = form.get("trust") === "on";
  const next = safeNext(String(form.get("next") ?? ""));
  if (!/^\d{6}$/.test(code)) return { error: "Enter the 6-digit code from the email." };
  const supabase = await createClient();
  const label = (await headers()).get("user-agent")?.slice(0, 120) ?? null;
  const { data, error } = await supabase.rpc("mfa_verify", { p_code: code, p_trust: trust, p_label: label });
  if (error) return { error: error.message.replace(/^.*?: /, "") || "The code could not be checked." };
  const r = data as { ok: boolean; left?: number; device_token?: string | null };
  if (!r.ok) return { error: r.left && r.left > 0 ? `That code is not right. ${r.left} tries left.` : "Too many attempts: ask for a new code." };
  if (r.device_token) {
    (await cookies()).set(DEVICE_COOKIE, r.device_token, {
      httpOnly: true,
      secure: process.env.NODE_ENV !== "development",
      sameSite: "lax",
      path: "/",
      maxAge: 30 * 24 * 60 * 60,
    });
  }
  redirect(next);
}

/**
 * "First time, or forgot your password?": emails a one-time link (1 hour) to an active staff member, through the app's
 * own mail, never Supabase's mailer. The answer is the same whether or not the account exists; at most 3 links an hour.
 */
export async function requestPasswordLink(_: FormState, form: FormData): Promise<FormState> {
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  if (!z.email().max(254).safeParse(email).success) return { error: "Enter your @eduwit.in email address." };
  if (!isAllowedEmail(email)) return { error: DOMAIN };
  const done = { notice: `If ${email} has an Eduwit Spark account, a link to set the password is on its way. It works once, for one hour.` };
  const ctx = await requestContext();
  const db = adminClient();
  const recent = await db.schema("b2c").from("sign_in_log").select("id", { count: "exact", head: true })
    .eq("email", email).eq("method", "password_link").gt("at", new Date(Date.now() - 3600e3).toISOString());
  if ((recent.count ?? 0) >= 3) return done;
  const { data: person } = await db.schema("b2c").from("users").select("user_id, full_name, is_active").eq("email", email).maybeSingle();
  if (!person?.is_active) {
    await recordSignIn({ email, method: "password_link", outcome: "refused_unknown", ...ctx });
    return done;
  }
  const { data, error } = await db.auth.admin.generateLink({ type: "recovery", email });
  if (error || !data.properties?.hashed_token) return { error: "The link could not be made. Try again in a minute." };
  const link = `${siteUrl()}/auth/confirm?token_hash=${encodeURIComponent(data.properties.hashed_token)}&type=recovery`;
  const sent = await sendMail({ ...passwordEmail(link, person.full_name), to: email }).catch((e: unknown) => {
    console.error("[mail] password link not sent:", (e as Error).message);
    return null;
  });
  await recordSignIn({ email, user_id: person.user_id, method: "password_link", outcome: !sent ? "mail_failed" : sent.sent ? "link_sent" : "mail_not_configured", ...ctx });
  if (!sent) return { error: "The email could not be sent (the email settings need checking). Tell the Admin." };
  return sent.sent ? done : { error: "Email is not set up yet (SMTP). Ask the Admin." };
}

/** Sets the password after the emailed link (the app's one password rule, lib/security); the 6-digit code step still follows. */
export async function setPassword(_: FormState, form: FormData): Promise<FormState> {
  const password = String(form.get("password") ?? "");
  const problem = passwordProblem(password, String(form.get("again") ?? ""));
  if (problem) return { error: problem };
  const parsed = { data: { password } };
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims?.sub) redirect("/password?error=expired");
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { error: /same|different/i.test(error.message) ? "Choose a password you have not used here before." : /weak|short/i.test(error.message) ? "That password is too weak: make it longer." : "The password could not be saved. Try again." };
  const result = await fetchMe(supabase);
  if ("setupError" in result) return { error: SETUP };
  await recordSignIn({ email: result.me.email ?? null, user_id: claims.claims.sub, method: "password_link", outcome: "password_set", ...(await requestContext()) });
  redirect(`/verify?next=${encodeURIComponent(homeFor(result.me))}`);
}

