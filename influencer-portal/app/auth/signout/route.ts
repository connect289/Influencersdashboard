import { NextResponse, type NextRequest } from "next/server";
import { env } from "@/lib/env";
import { formText } from "@/lib/forms";
import { DEVICE_COOKIE, safeNext, SEEN_COOKIE } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Signs out this browser: ends the portal session in the database, then the Supabase session. POST only, same origin. */
export async function POST(request: NextRequest) {
  const site = new URL(env().NEXT_PUBLIC_SITE_URL);
  const origin = request.headers.get("origin");
  // Browsers always send Origin on a POST; a request without one is not from the sign-out form.
  if (origin !== site.origin) return new NextResponse("Forbidden", { status: 403 });
  const form = await request.formData().catch(() => null);
  const target = safeNext(formText(form, "to") || null, "/login");
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const sessionId = (data?.claims as { session_id?: string } | undefined)?.session_id;
  if (sessionId) await supabase.rpc("session_revoke", { p_session_id: sessionId });
  await supabase.auth.signOut({ scope: "local" });
  const res = NextResponse.redirect(new URL(target, site), { status: 303 });
  res.cookies.delete(SEEN_COOKIE);
  if (form?.get("forget_device") === "on") res.cookies.delete(DEVICE_COOKIE);
  return res;
}
