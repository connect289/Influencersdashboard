"use server";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

const uuid = z.uuid();

async function signedIn() {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return { supabase, me };
}

/** Sign out one of my other sessions (remote logout). */
export async function revokeSession(sessionId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(sessionId).success) return fail(t("errors.invalidInput"));
  const ctx = await signedIn();
  if (!ctx) return fail(t("errors.sessionEnded"));
  const { data, error } = await ctx.supabase.rpc("session_revoke", { p_session_id: sessionId });
  if (error) return fail(t("errors.generic"));
  revalidatePath("/admin/account");
  revalidatePath("/creator/account");
  return data ? { ok: true, message: t("account.sessions.revoked") } : fail(t("account.sessions.alreadyEnded"));
}

/** Sign out every other session of mine. */
export async function revokeOtherSessions(): Promise<ActionResult> {
  const t = await getTranslations();
  const ctx = await signedIn();
  if (!ctx) return fail(t("errors.sessionEnded"));
  const { data, error } = await ctx.supabase.rpc("my_sessions");
  if (error) return fail(t("errors.generic"));
  const others = (data as { session_id: string; is_current: boolean; revoked_at: string | null }[]).filter((s) => !s.is_current && !s.revoked_at);
  for (const s of others) await ctx.supabase.rpc("session_revoke", { p_session_id: s.session_id });
  revalidatePath("/admin/account");
  revalidatePath("/creator/account");
  return { ok: true, message: t("account.sessions.revokedAll", { count: others.length }) };
}

export async function revokeDevice(deviceId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(deviceId).success) return fail(t("errors.invalidInput"));
  const ctx = await signedIn();
  if (!ctx) return fail(t("errors.sessionEnded"));
  const { error } = await ctx.supabase.rpc("device_revoke", { p_id: deviceId });
  if (error) return fail(t("errors.generic"));
  revalidatePath("/admin/account");
  return { ok: true, message: t("account.devices.revoked") };
}
