import "server-only";
import { cache } from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { DEVICE_COOKIE } from "./security.ts";
import { NotConfigured, userClient, type UserClient } from "./supabase.ts";

// Who is signed in (one.me(), migration 0009). The database is the authority: these checks only route, and every page
// read goes through one.ui_require() as well (D-058).

export const meSchema = z.object({
  user_id: z.string().nullable(),
  email: z.string().nullable(),
  known: z.boolean(),
  active: z.boolean(),
  role: z.enum(["owner", "engineer"]).nullable(),
  checked: z.boolean(),
  alive: z.boolean(),
});
export type Me = z.infer<typeof meSchema>;
export type Role = "owner" | "engineer";

export type MeResult = { me: Me } | { setupError: "not_configured" | "schema_not_exposed" | "unreachable" };

export async function fetchMe(supabase: UserClient): Promise<MeResult> {
  const { data, error } = await supabase.rpc("me");
  if (error) {
    // PGRST106: schema one is not in the Data API's exposed schemas (Setup item supabase_api_schema).
    return { setupError: error.code === "PGRST106" ? "schema_not_exposed" : "unreachable" };
  }
  return { me: meSchema.parse(data) };
}

export const getMe = cache(async (): Promise<MeResult> => {
  try {
    return await fetchMe(await userClient());
  } catch (e) {
    if (e instanceof NotConfigured) return { setupError: "not_configured" };
    throw e;
  }
});

/**
 * The gate of every page: signed out → /login; not on the allow-list → /pending; second step not done on this session
 * → a trusted-device cookie is tried, else /verify. Returns the person.
 */
export async function requireUser(next = "/"): Promise<Me & { role: Role; email: string }> {
  const result = await getMe();
  if ("setupError" in result) redirect(`/login?error=${result.setupError}`);
  const { me } = result;
  if (!me.user_id || !me.alive) redirect("/login");
  if (!me.known || !me.active || !me.role || !me.email) redirect("/pending");
  if (!me.checked && !(await trustDevice())) redirect(`/verify?next=${encodeURIComponent(next)}`);
  return { ...me, role: me.role, email: me.email };
}

/** For server actions: throws instead of redirecting, so a forged call never proceeds. */
export async function assertUser(roles?: Role[]): Promise<Me & { role: Role; email: string }> {
  const result = await getMe();
  if ("setupError" in result) throw new Error("not allowed");
  const { me } = result;
  if (!me.user_id || !me.alive || !me.active || !me.role || !me.email || !me.checked) throw new Error("not allowed");
  if (roles && !roles.includes(me.role)) throw new Error("not allowed");
  return { ...me, role: me.role, email: me.email };
}

/** A trusted-device cookie checks this session (one.auth_device_check records it). */
export async function trustDevice(): Promise<boolean> {
  const token = (await cookies()).get(DEVICE_COOKIE)?.value;
  if (!token || !/^[0-9a-f]{64}$/.test(token)) return false;
  const { data } = await (await userClient()).rpc("auth_device_check", { p_token: token });
  return data === true;
}
