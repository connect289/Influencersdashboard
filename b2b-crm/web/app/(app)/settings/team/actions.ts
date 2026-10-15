"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

const Role = z.enum(["admin", "viewer"]);
const dbMessage = (e: { code?: string; message: string }, fallback: string) => (e.code === "22023" || e.code === "P0002" ? e.message : fallback);

/** M33a: invite someone by email; their first sign-in on that address joins them with this role. */
export async function inviteMember(email: string, role: "admin" | "viewer", note: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ email: z.string().trim().email("Give an email address.").max(200), role: Role, note: z.string().trim().max(300) }).safeParse({ email, role, note });
  if (!p.success) return p.error.issues[0]?.message ?? "Check the fields.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("team_invite", { p_email: p.data.email, p_role: p.data.role, p_note: p.data.note || null });
  if (error) return dbMessage(error, "Could not send the invitation. Try again.");
  revalidatePath("/settings/team");
}

export async function revokeInvite(id: number): Promise<string | void> {
  await assertAdmin();
  if (!z.number().int().positive().safeParse(id).success) return "Invalid invitation.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("team_invite_revoke", { p_id: id });
  if (error) return "Could not revoke the invitation. Try again.";
  revalidatePath("/settings/team");
}

export async function updateMember(userId: string, changes: { role?: "admin" | "viewer"; is_active?: boolean; require_totp?: boolean; note?: string }): Promise<string | void> {
  await assertAdmin();
  const p = z.object({
    userId: z.string().uuid(),
    changes: z.object({ role: Role.optional(), is_active: z.boolean().optional(), require_totp: z.boolean().optional(), note: z.string().trim().max(300).optional() }),
  }).safeParse({ userId, changes });
  if (!p.success) return "Check the fields.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("team_member_update", { p_user_id: p.data.userId, p: p.data.changes });
  if (error) return dbMessage(error, "Could not change this member. Try again.");
  revalidatePath("/settings/team");
}
