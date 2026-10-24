"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { codeEmail } from "@/lib/auth/code-email.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { RealEmailClient } from "@/lib/clients/email.ts";
import { DbError, SupabaseOneDb } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";
import { clientIp, DEVICE_COOKIE, safeNext } from "@/lib/security.ts";
import { fetchMe } from "@/lib/session.ts";
import { signInSettingsSchema } from "@/lib/state.ts";
import { userClient } from "@/lib/supabase.ts";

export type FormState = { error?: string; notice?: string } | undefined;

const UNAVAILABLE = "Sign-in is not available right now. Try again in a minute.";

/** Sends a fresh 6-digit code to the person's own inbox, bound to this session (one.auth_issue_code). */
export async function sendCode(_: FormState, form: FormData): Promise<FormState> {
  void form;
  const supabase = await userClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  const sessionId = (claims?.claims as { session_id?: string } | undefined)?.session_id;
  if (!userId || !sessionId) redirect("/login");
  const result = await fetchMe(supabase);
  if ("setupError" in result) return { error: UNAVAILABLE };
  const { me } = result;
  if (!me.known || !me.active || !me.email) redirect("/pending");
  const db = SupabaseOneDb.fromEnv();
  if (!db) return { error: UNAVAILABLE };
  const h = await headers();
  const ctx = { ip: clientIp(h), user_agent: h.get("user-agent")?.slice(0, 300) ?? null };

  let code: string;
  try {
    code = await db.authIssueCode(userId, sessionId);
  } catch (e) {
    if (e instanceof DbError && e.code === "54000") {
      await db
        .authRecord({ email: me.email, user_id: userId, method: "email_code", outcome: "too_many_codes", ...ctx })
        .catch(() => undefined);
      return { error: "Five codes were sent in the last hour. Try again later." };
    }
    return { error: UNAVAILABLE };
  }
  try {
    // Only the keys the code email reads (F6): a bad edit elsewhere in one.settings must not stop sign-in.
    const settings = signInSettingsSchema.parse((await db.tickState()).settings);
    const key = credentialsFrom(await vaultSecrets(db)).email;
    if (!key) throw new Error("no email key");
    const minutes = settings.access?.code_minutes ?? 10;
    const m = codeEmail(code, minutes, settings.hosts.one);
    await new RealEmailClient(settings.vendors.resend_api, key).send({
      from: settings.alerts.email_from,
      to: me.email,
      ...m,
      idempotencyKey: `signin:${sessionId}:${Date.now()}`,
    });
  } catch (e) {
    log("error", "signin.code_not_sent", { error: e instanceof Error ? e.message : "error" });
    await db
      .authRecord({ email: me.email, user_id: userId, method: "email_code", outcome: "mail_failed", ...ctx })
      .catch(() => undefined);
    return { error: "The code email could not be sent (Setup item email). Tell the owner." };
  }
  await db
    .authRecord({ email: me.email, user_id: userId, method: "email_code", outcome: "code_sent", ...ctx })
    .catch(() => undefined);
  return { notice: `A code is on its way to ${me.email}.` };
}

/** Checks the code (one.auth_verify_code); on success, optionally trusts this browser, then continues to `next`. */
export async function verifyCode(_: FormState, form: FormData): Promise<FormState> {
  const code = String(form.get("code") ?? "").replace(/\s/g, "");
  const trust = form.get("trust") === "on";
  const next = safeNext(String(form.get("next") ?? "/"));
  if (!/^\d{6}$/.test(code)) return { error: "Enter the 6-digit code from the email." };
  const supabase = await userClient();
  const label = (await headers()).get("user-agent")?.slice(0, 120) ?? null;
  const { data, error } = await supabase.rpc("auth_verify_code", { p_code: code, p_trust: trust, p_label: label });
  if (error) {
    if (error.code === "22023") return { error: `${error.message.charAt(0).toUpperCase()}${error.message.slice(1)}.` };
    return { error: "The code could not be checked. Try again." };
  }
  const r = data as { ok: boolean; left?: number; device_token?: string | null; trusted_days?: number };
  if (!r.ok)
    return {
      error:
        r.left && r.left > 0 ? `That code is not right. ${r.left} tries left.` : "Too many tries: ask for a new code.",
    };
  if (r.device_token) {
    (await cookies()).set(DEVICE_COOKIE, r.device_token, {
      httpOnly: true,
      secure: process.env.NODE_ENV !== "development",
      sameSite: "lax",
      path: "/",
      maxAge: (r.trusted_days ?? 30) * 24 * 60 * 60,
    });
  }
  redirect(next);
}
