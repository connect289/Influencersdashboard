import { NextResponse, type NextRequest } from "next/server";
import { fetchMe, recordSignIn } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { clientIp, SEEN_COOKIE } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * Where requireUser sends a session that was signed out from another device ("Sign out" in Me → Signed-in devices, or
 * the Admin; b2c.session_revoke). It acts only when the database says this session is revoked, so a link to it signs
 * nobody out; then the Supabase session cookie is cleared and the person signs in again.
 */
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const result = await fetchMe(supabase).catch(() => null);
  if (!result || !("me" in result) || !result.me.revoked) return NextResponse.redirect(new URL("/", siteUrl()), 303);
  await recordSignIn({ email: result.me.email, user_id: result.me.user_id, method: "sign_out", outcome: "revoked", ip: clientIp(request.headers),
    user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null });
  await supabase.auth.signOut({ scope: "local" });
  const res = NextResponse.redirect(new URL("/login?reason=revoked", siteUrl()), 303);
  res.cookies.delete(SEEN_COOKIE);
  return res;
}
