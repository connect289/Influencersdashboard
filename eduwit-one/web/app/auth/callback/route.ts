import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { SupabaseOneDb, type SignInEntry } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";
import { clientIp, isAllowedEmail, safeNext } from "@/lib/security.ts";
import { fetchMe } from "@/lib/session.ts";
import { userClient } from "@/lib/supabase.ts";

/** Where Google sign-in lands. The domain is checked first; a person not on the allow-list is signed straight out. */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const code = params.get("code");
  const supabase = await userClient();
  if (!code || (await supabase.auth.exchangeCodeForSession(code)).error) redirect("/login?error=oauth");

  const db = SupabaseOneDb.fromEnv();
  const ctx = { ip: clientIp(request.headers), user_agent: request.headers.get("user-agent")?.slice(0, 300) ?? null };
  const record = async (entry: SignInEntry) => {
    try {
      await db?.authRecord(entry);
    } catch {
      log("warn", "signin.log_failed", { outcome: entry.outcome }); // never block a sign-in on the log
    }
  };
  const result = await fetchMe(supabase);
  if ("setupError" in result) {
    await supabase.auth.signOut({ scope: "local" });
    redirect(`/login?error=${result.setupError}`);
  }
  const { me } = result;
  if (!isAllowedEmail(me.email)) {
    await record({ email: me.email, user_id: me.user_id, method: "google", outcome: "refused_domain", ...ctx });
    await supabase.auth.signOut({ scope: "local" });
    redirect("/login?error=domain");
  }
  if (!me.known || !me.active) {
    await record({ email: me.email, user_id: me.user_id, method: "google", outcome: "refused_unknown", ...ctx });
    await supabase.auth.signOut({ scope: "local" });
    redirect("/pending");
  }
  await record({ email: me.email, user_id: me.user_id, method: "google", outcome: "success", ...ctx });
  redirect(`/verify?next=${encodeURIComponent(safeNext(params.get("next")))}`);
}
