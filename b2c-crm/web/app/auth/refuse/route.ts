import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { fetchMe, isAllowedEmail, recordSignIn } from "@/lib/auth";
import { clientIp } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Signs out a session whose account is outside eduwit.in. Does nothing for a company account. */
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const result = await fetchMe(supabase).catch(() => null);
  if (result && "me" in result && isAllowedEmail(result.me.email)) redirect("/");
  if (result && "me" in result && result.me.user_id) {
    await recordSignIn({
      email: result.me.email,
      user_id: result.me.user_id,
      method: "google",
      outcome: "refused_domain",
      ip: clientIp(request.headers),
      user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null,
    });
  }
  await supabase.auth.signOut({ scope: "local" });
  redirect("/login?error=domain");
}
