import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { safeNext } from "@/lib/security.ts";
import { NotConfigured, userClient } from "@/lib/supabase.ts";

// Starts Google sign-in on the server (PKCE: the verifier goes in a cookie), so the browser never needs a Supabase
// key. POST only, from the sign-in page's form. hd narrows Google's account picker to the company domain; the
// callback checks the domain again on the server.
export async function POST(request: NextRequest) {
  const form = await request.formData();
  const next = safeNext(String(form.get("next") ?? "/"));
  let target: string | null = null;
  try {
    const supabase = await userClient();
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${request.nextUrl.origin}/auth/callback?next=${encodeURIComponent(next)}`,
        queryParams: { prompt: "select_account", hd: "eduwit.in" },
        skipBrowserRedirect: true,
      },
    });
    if (!error && data.url) target = data.url;
  } catch (e) {
    if (!(e instanceof NotConfigured)) throw e;
    redirect("/login?error=not_configured");
  }
  redirect(target ?? "/login?error=oauth");
}
