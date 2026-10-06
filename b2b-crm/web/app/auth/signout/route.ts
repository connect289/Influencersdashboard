import { NextResponse, type NextRequest } from "next/server";
import { fetchMe, recordSignIn } from "@/lib/auth";
import { clientIp, SEEN_COOKIE } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** POST only, so another site cannot sign the Admin out with a link or image. */
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const result = await fetchMe(supabase).catch(() => null);
  if (result && "me" in result && result.me.user_id) {
    await recordSignIn({
      email: result.me.email,
      user_id: result.me.user_id,
      method: "sign_out",
      outcome: "signed_out",
      ip: clientIp(request.headers),
      user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null,
    });
  }
  await supabase.auth.signOut({ scope: "local" });
  const res = NextResponse.redirect(new URL("/login?reason=signed_out", request.url), 303);
  res.cookies.delete(SEEN_COOKIE);
  return res;
}
