import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { fetchMe, homeFor, inviteOk, isAllowedEmail, recordSignIn } from "@/lib/auth";
import { clientIp, safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Landing point for Google sign-in. Checks the domain before anything else, then sends the person to the code step. */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const code = params.get("code");
  const supabase = await createClient();
  if (!code || (await supabase.auth.exchangeCodeForSession(code)).error) redirect("/login?error=oauth");

  const ctx = { ip: clientIp(request.headers), user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null };
  const result = await fetchMe(supabase);
  if ("setupError" in result) {
    await supabase.auth.signOut({ scope: "local" });
    redirect("/login?error=setup");
  }
  const { me } = result;
  if (!isAllowedEmail(me.email)) {
    await recordSignIn({ email: me.email, user_id: me.user_id, method: "google", outcome: "refused_domain", ...ctx });
    await supabase.auth.signOut({ scope: "local" });
    redirect("/login?error=domain");
  }
  if (me.known && !(await inviteOk(me.email))) {
    await recordSignIn({ email: me.email, user_id: me.user_id, method: "google", outcome: "invite_expired", ...ctx });
    await supabase.auth.signOut({ scope: "local" });
    redirect("/login?error=invite");
  }
  await recordSignIn({ email: me.email, user_id: me.user_id, method: "google", outcome: me.known ? "success" : "refused_unknown", ...ctx });
  if (!me.known || !me.active) redirect("/pending");
  const next = safeNext(params.get("next"));
  redirect(`/verify?next=${encodeURIComponent(next === "/" ? homeFor(me) : next)}`);
}
