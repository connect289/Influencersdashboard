import { type NextRequest } from "next/server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

/** The emailed password link: checks the one-time token, signs the person in for the next step only. */
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const tokenHash = params.get("token_hash");
  if (!tokenHash || params.get("type") !== "recovery") redirect("/password?error=expired");
  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ type: "recovery", token_hash: tokenHash });
  if (error) redirect("/password?error=expired");
  redirect("/password/new");
}
