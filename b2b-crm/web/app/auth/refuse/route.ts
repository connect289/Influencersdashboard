import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { fetchMe, recordSignIn } from "@/lib/auth";
import { clientIp } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Signs out an account that authenticated but is not on the allowlist. Does nothing for the Admin. */
export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const result = await fetchMe(supabase).catch(() => null);
  if (result && "me" in result && result.me.allowlisted) redirect("/");
  if (result && "me" in result && result.me.user_id) {
    await recordSignIn({
      email: result.me.email,
      user_id: result.me.user_id,
      method: "session",
      outcome: "refused_not_allowlisted",
      ip: clientIp(request.headers),
      user_agent: request.headers.get("user-agent")?.slice(0, 500) ?? null,
    });
  }
  await supabase.auth.signOut({ scope: "local" });
  redirect("/login?error=restricted");
}
