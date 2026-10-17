import { NextResponse, type NextRequest } from "next/server";
import { fetchMe, SetupError } from "@/lib/auth/guards";
import { linkPortalAccount, portalNext } from "@/lib/auth/link";
import { env } from "@/lib/env";
import { log } from "@/lib/log";
import { clientIp, safeNext } from "@/lib/security";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

/**
 * Landing point for Google sign-in (both portals). Exchanges the code, then checks the account against the portal:
 * staff go on to the emailed code, creators are linked by verified email. Anyone else is signed out and refused.
 */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const portal = params.get("portal") === "staff" ? "staff" : "creator";
  const login = portal === "staff" ? "/login/staff" : "/login";
  const to = (path: string) => NextResponse.redirect(new URL(path, env().NEXT_PUBLIC_SITE_URL));
  const code = params.get("code");
  const supabase = await createClient();
  if (!code || (await supabase.auth.exchangeCodeForSession(code)).error) return to(`${login}?error=oauth`);

  const record = async (email: string, outcome: "ok" | "refused", reason: string | null, userId?: string) => {
    await adminClient().rpc("sign_in_record", {
      p_email: email,
      p_portal: portal,
      p_method: "google",
      p_outcome: outcome,
      p_reason: reason ?? undefined,
      p_user: userId,
      p_ip: clientIp(request.headers) ?? undefined,
      p_ua: request.headers.get("user-agent")?.slice(0, 500) ?? undefined,
    });
  };

  try {
    let me = await fetchMe(supabase);
    const email = me.email ?? "";
    const hd = env().STAFF_GOOGLE_HD;
    if (portal === "staff") {
      if (me.kind !== "staff" || (hd && !email.toLowerCase().endsWith(`@${hd.toLowerCase()}`))) {
        await record(email, "refused", me.kind !== "staff" ? "not_staff" : "domain", me.user_id);
        await supabase.auth.signOut({ scope: "local" });
        return to("/no-access");
      }
      await supabase.rpc("session_register");
      await record(email, "ok", null, me.user_id);
      return to(`/verify?next=${encodeURIComponent(safeNext(params.get("next"), "/admin"))}`);
    }
    if (me.kind === "staff") {
      await supabase.auth.signOut({ scope: "local" });
      return to("/login/staff");
    }
    let kind: "creator" | "agency" | null = me.kind === "creator" || me.kind === "agency" ? me.kind : null;
    if (!kind) {
      kind = await linkPortalAccount(supabase);
      if (!kind) {
        await record(email, "refused", "not_registered", me.user_id);
        await supabase.auth.signOut({ scope: "local" });
        return to("/no-access?portal=creator");
      }
      me = await fetchMe(supabase);
    }
    await supabase.rpc("session_register");
    await record(email, "ok", kind === "agency" ? "agency" : null, me.user_id);
    return to(portalNext(kind, safeNext(params.get("next"), "/creator")));
  } catch (e) {
    log.error("oauth_callback.failed", { error: e instanceof Error ? e.message : String(e) });
    await supabase.auth.signOut({ scope: "local" });
    return to(`${login}?error=${e instanceof SetupError ? "setup" : "oauth"}`);
  }
}
