import "server-only";
import type { ServerSupabase } from "@/lib/supabase/server";

/**
 * After an email-OTP or Google sign-in on the creator/agency login: link the account to its invited creator profile,
 * or else to its agency membership (both matched by verified email in the database). Null = not registered.
 */
export async function linkPortalAccount(
  supabase: ServerSupabase,
): Promise<"creator" | "agency" | null> {
  const creator = await supabase.rpc("creator_account_link");
  if ((creator.data as { ok?: boolean } | null)?.ok === true) return "creator";
  const agency = await supabase.rpc("agency_account_link");
  if ((agency.data as { ok?: boolean } | null)?.ok === true) return "agency";
  return null;
}

/** The creator login defaults `next` to /creator; send agency members to their own portal instead. */
export function portalNext(kind: "creator" | "agency", next: string): string {
  if (kind === "agency") return next.startsWith("/agency") ? next : "/agency";
  return next.startsWith("/agency") ? "/creator" : next;
}
