import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";

/** b2b.me(): who is signed in and whether they may use the app. The database is the authority (b2b.is_admin()). */
export type Me = {
  user_id: string | null;
  email: string | null;
  aal: "aal1" | "aal2";
  allowlisted: boolean;
  role: string | null;
  require_totp: boolean;
  is_admin: boolean;
};

export type MeResult = { me: Me } | { setupError: "b2b_not_exposed" };

export async function fetchMe(supabase: ServerSupabase): Promise<MeResult> {
  const { data, error } = await supabase.schema("b2b").rpc("me");
  if (error) {
    // PostgREST answers PGRST106 when the b2b schema is not in the Data API's exposed schemas.
    if (error.code === "PGRST106") return { setupError: "b2b_not_exposed" };
    throw new Error(`b2b.me() failed: ${error.message}`);
  }
  return { me: data as Me };
}

/** Once per request (React cache): the signed-in user's access, checked on the server. */
export const getMe = cache(async (): Promise<MeResult> => fetchMe(await createClient()));

/**
 * Gate for every page and action inside the app. Signed out → /login; signed in but not on the allowlist → signed out
 * by /auth/refuse; allowlisted without a TOTP-verified session → /mfa.
 */
export async function requireAdmin(): Promise<MeResult> {
  const result = await getMe();
  if ("setupError" in result) return result;
  const { me } = result;
  if (!me.user_id) redirect("/login");
  if (!me.allowlisted) redirect("/auth/refuse");
  if (!me.is_admin) redirect("/mfa");
  return result;
}

/** For server actions: throws instead of rendering, so a forged call can never proceed. */
export async function assertAdmin(): Promise<Me> {
  const result = await getMe();
  if ("setupError" in result || !result.me.is_admin) throw new Error("not allowed");
  return result.me;
}

// ---------- service-role helpers (signed-out flows only) ----------

export type SignInEntry = {
  email: string | null;
  user_id?: string | null;
  method: "google" | "password" | "totp" | "password_reset" | "sign_out" | "session";
  outcome: "success" | "refused_not_allowlisted" | "failed_password" | "failed_totp" | "locked" | "signed_out" | "session_expired";
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
  if (error) throw new Error("lockout check failed"); // fail closed
  return data === true;
}

export async function isAllowlistedEmail(email: string): Promise<boolean> {
  const { data, error } = await adminClient()
    .from("app_users")
    .select("user_id")
    .eq("email", email.toLowerCase())
    .eq("is_active", true)
    .maybeSingle();
  if (error) throw new Error("allowlist check failed");
  return data !== null;
}
