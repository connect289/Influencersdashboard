import { NextResponse } from "next/server";
import { staffAuth } from "@/lib/server/supabase-auth";
import { siteUrl } from "@/lib/server/env";

/** Google OAuth return: exchange the code for a staff session, then continue to the second factor. */
export async function GET(req: Request) {
  const code = new URL(req.url).searchParams.get("code");
  if (!code) return NextResponse.redirect(siteUrl("/admin/login?error=google"));
  const auth = await staffAuth();
  const { error } = await auth.auth.exchangeCodeForSession(code);
  return NextResponse.redirect(siteUrl(error ? "/admin/login?error=google" : "/admin/verify"));
}
