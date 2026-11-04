import { NextResponse, type NextRequest } from "next/server";
import { sameOriginRequest, SEEN_COOKIE } from "@/lib/security.ts";
import { userClient } from "@/lib/supabase.ts";

/** POST only, from this app's own pages (D-104). The trusted-device cookie stays, as in Spark. */
export async function POST(request: NextRequest) {
  if (!sameOriginRequest(request.headers)) return new Response("forbidden", { status: 403 });
  try {
    const supabase = await userClient();
    await supabase.rpc("auth_sign_out");
    await supabase.auth.signOut({ scope: "local" });
  } catch {
    // Not configured or already signed out: the redirect below is the same.
  }
  const res = NextResponse.redirect(new URL("/login?reason=signed_out", request.url), 303);
  res.cookies.delete(SEEN_COOKIE);
  return res;
}
