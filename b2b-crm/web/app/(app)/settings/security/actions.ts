"use server";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { assertAdmin, recordSignIn } from "@/lib/auth";
import { clientIp } from "@/lib/security";
import { createClient } from "@/lib/supabase/server";

/** Signs out every other device; this one stays signed in. */
export async function signOutOtherDevices(): Promise<{ ok: boolean }> {
  const me = await assertAdmin();
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut({ scope: "others" });
  if (error) return { ok: false };
  const h = await headers();
  await recordSignIn({ email: me.email, user_id: me.user_id, method: "sign_out", outcome: "signed_out", ip: clientIp(h), user_agent: h.get("user-agent")?.slice(0, 500) ?? null, detail: { scope: "others" } });
  revalidatePath("/settings/security");
  return { ok: true };
}
