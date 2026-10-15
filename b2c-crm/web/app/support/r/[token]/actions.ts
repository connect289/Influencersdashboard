"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { readSupportToken } from "@/lib/support-token";

/** The developer's answer from the signed page: the token is the only credential, and names one ticket. */
export async function developerAnswer(token: string, f: FormData): Promise<{ ok: boolean; error?: string }> {
  const ticket = readSupportToken(token);
  if (!ticket) return { ok: false, error: "This link is not valid." };
  const status = z.enum(["", "in_progress", "waiting", "fixed", "closed", "open"]).safeParse(String(f.get("status") ?? ""));
  if (!status.success) return { ok: false, error: "Unknown status." };
  const body = String(f.get("body") ?? "").slice(0, 8000);
  const { error } = await adminClient().rpc("support_developer_reply", { p: { ticket_id: ticket, body, status: status.data || null, source: "link" } });
  if (error) return { ok: false, error: error.message };
  revalidatePath(`/support/r/${token}`);
  return { ok: true };
}
