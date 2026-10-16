import "server-only";
import { cookies, headers } from "next/headers";
import { notFound, redirect } from "next/navigation";
import { meSchema, toCreatorMe, toStaffMe, type CreatorMe, type Me, type StaffMe } from "@/lib/auth/me";
import type { Permission } from "@/lib/auth/permissions";
import { log } from "@/lib/log";
import { DEVICE_COOKIE, safeNext } from "@/lib/security";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";

/** Thrown when the Data API does not expose schema `inf` yet (PGRST106): a deployment setup step, not a user error. */
export class SetupError extends Error {
  constructor() {
    super("The portal cannot reach its data yet: add `inf` to the Supabase Data API's exposed schemas.");
  }
}

export class ForbiddenError extends Error {
  constructor(message = "You don't have access to do that.") {
    super(message);
  }
}

async function currentPath(): Promise<string> {
  return safeNext((await headers()).get("x-inf-path"), "/");
}

export async function fetchMe(supabase: ServerSupabase): Promise<Me> {
  const { data, error } = await supabase.rpc("me");
  if (error) {
    if (error.code === "PGRST106" || /schema must be one of/i.test(error.message)) throw new SetupError();
    throw new Error(`me() failed: ${error.message}`);
  }
  return meSchema.parse(data);
}

async function signedInClient(loginPath: string): Promise<ServerSupabase> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims.sub) redirect(`${loginPath}?next=${encodeURIComponent(await currentPath())}`);
  return supabase;
}

async function signOutWith(supabase: ServerSupabase, to: string): Promise<never> {
  await supabase.auth.signOut({ scope: "local" });
  redirect(to);
}

/**
 * Gate for every staff page. Registers the session, requires the emailed code (or a trusted device) and an active
 * staff profile, and returns 404 when the role lacks `permission` (screens a role can't use are hidden, not disabled).
 */
export async function requireStaff(permission?: Permission): Promise<{ supabase: ServerSupabase; me: StaffMe }> {
  const supabase = await signedInClient("/login/staff");
  let me = await fetchMe(supabase);
  if (me.kind !== "staff") redirect("/no-access");
  if (!me.session?.registered) {
    await supabase.rpc("session_register");
    me = await fetchMe(supabase);
  }
  if (me.session?.revoked) return signOutWith(supabase, "/login/staff?reason=revoked");
  if (!me.session?.verified) {
    const token = (await cookies()).get(DEVICE_COOKIE)?.value;
    const trusted = token ? (await supabase.rpc("device_trust_check", { p_token: token })).data === true : false;
    if (!trusted) redirect(`/verify?next=${encodeURIComponent(await currentPath())}`);
    me = await fetchMe(supabase);
  }
  const staff = toStaffMe(me);
  if (!staff) return signOutWith(supabase, "/no-access");
  if (permission && !staff.permissions.has(permission)) notFound();
  void supabase
    .rpc("session_touch")
    .then(({ error }) => error && log.warn("session_touch.failed", { error: error.message }));
  return { supabase, me: staff };
}

/** Gate for every creator page. Links the account on first sign-in and registers the session. */
export async function requireCreator(): Promise<{ supabase: ServerSupabase; me: CreatorMe }> {
  const supabase = await signedInClient("/login");
  let me = await fetchMe(supabase);
  if (me.kind === "staff") redirect("/admin");
  if (me.kind !== "creator") {
    const link = await supabase.rpc("creator_account_link");
    if ((link.data as { ok?: boolean } | null)?.ok !== true) return signOutWith(supabase, "/no-access?portal=creator");
    me = await fetchMe(supabase);
  }
  if (!me.session?.registered) {
    await supabase.rpc("session_register");
    me = await fetchMe(supabase);
  }
  if (me.session?.revoked) return signOutWith(supabase, "/login?reason=revoked");
  const creator = toCreatorMe(me);
  if (!creator || !me.session?.verified) return signOutWith(supabase, "/no-access?portal=creator");
  void supabase
    .rpc("session_touch")
    .then(({ error }) => error && log.warn("session_touch.failed", { error: error.message }));
  return { supabase, me: creator };
}

/** Throwing variant for server actions and route handlers (no redirects). */
export async function assertStaff(permission?: Permission): Promise<{ supabase: ServerSupabase; me: StaffMe }> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  const staff = toStaffMe(me);
  if (!staff || !me.session?.verified || me.session.revoked)
    throw new ForbiddenError("Your session has ended. Sign in again.");
  if (permission && !staff.permissions.has(permission)) throw new ForbiddenError();
  return { supabase, me: staff };
}

export async function assertCreator(): Promise<{ supabase: ServerSupabase; me: CreatorMe }> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  const creator = toCreatorMe(me);
  if (!creator || !me.session?.verified || me.session.revoked)
    throw new ForbiddenError("Your session has ended. Sign in again.");
  return { supabase, me: creator };
}
