import type { EmailOtpType } from "@supabase/supabase-js";
import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { fetchMe, recordSignIn } from "@/lib/auth";
import { clientIp, safeNext } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

const OTP_TYPES = new Set<EmailOtpType>(["recovery", "magiclink", "email"]);

/** Landing point for Google sign-in and emailed links (password reset). Applies the allowlist before anything else. */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const next = safeNext(params.get("next"));
  const code = params.get("code");
  const tokenHash = params.get("token_hash");
  const type = params.get("type") as EmailOtpType | null;
  const supabase = await createClient();

  let ok = false;
  if (code) ok = !(await supabase.auth.exchangeCodeForSession(code)).error;
  else if (tokenHash && type && OTP_TYPES.has(type)) ok = !(await supabase.auth.verifyOtp({ token_hash: tokenHash, type })).error;
  if (!ok) redirect(params.get("error") ? "/login?error=oauth" : "/login?error=link");

  const recovery = type === "recovery" || next === "/reset";
  const method = recovery ? "password_reset" : "google";
  const ctx = { ip: clientIp(request.headers), user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null };
  const result = await fetchMe(supabase);

  if ("setupError" in result || !result.me.allowlisted) {
    const email = "me" in result ? result.me.email : null;
    const userId = "me" in result ? result.me.user_id : null;
    await supabase.auth.signOut({ scope: "local" });
    await recordSignIn({ email, user_id: userId, method, outcome: "refused_not_allowlisted", ...ctx });
    redirect("/login?error=restricted");
  }

  const { me } = result;
  if (recovery) redirect("/reset");
  if (me.require_totp && me.aal !== "aal2") redirect(`/mfa?next=${encodeURIComponent(next)}`);
  await recordSignIn({ email: me.email, user_id: me.user_id, method, outcome: "success", ...ctx });
  redirect(next);
}
