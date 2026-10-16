import { NextResponse, type NextRequest } from "next/server";
import { env } from "@/lib/env";
import { safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Email links (password recovery) land here: the one-time token becomes a session, then the next step. */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const tokenHash = params.get("token_hash");
  const type = params.get("type");
  const to = (path: string) => NextResponse.redirect(new URL(path, env().NEXT_PUBLIC_SITE_URL));
  if (!tokenHash || type !== "recovery") return to("/login/staff?reason=link");
  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "recovery" });
  if (error) return to("/login/staff?reason=link");
  await supabase.rpc("session_register");
  return to(safeNext(params.get("next"), "/password/new"));
}
