import "server-only";
import { cookies } from "next/headers";
import { fetchMe } from "@/lib/auth/guards";
import { homeFor } from "@/lib/auth/me";
import { createClient } from "@/lib/supabase/server";

export const OTP_EMAIL_COOKIE = "inf_otp_email";

export function maskEmail(email: string): string {
  const [local = "", domain = ""] = email.split("@");
  return `${local.slice(0, 2)}${"•".repeat(Math.max(local.length - 2, 1))}@${domain}`;
}

/** Masked form of the email the creator asked a code for (from the short-lived httpOnly cookie). */
export async function otpEmailHint(): Promise<string | null> {
  const email = (await cookies()).get(OTP_EMAIL_COOKIE)?.value;
  return email ? maskEmail(email) : null;
}

/** Where "/" sends a signed-in person. */
export async function landingPath(): Promise<string> {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims.sub) return "/login";
  try {
    return homeFor(await fetchMe(supabase));
  } catch {
    return "/login";
  }
}
