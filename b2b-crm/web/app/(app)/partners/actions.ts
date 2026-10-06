"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { parsePartnerForm, STATUSES, type FieldErrors } from "@/lib/partners";
import { createClient } from "@/lib/supabase/server";

export type SaveState = { errors?: FieldErrors; error?: string; saved?: number } | undefined;

/**
 * Messages raised by the b2b.partner_* functions (errcode 22023, 23505, P0002) are written for the Admin and safe to
 * show. Anything else is reported generically.
 */
function dbMessage(error: { code?: string; message: string }): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  if (error.code === "23505") return "That slug is already used by another partner.";
  return "Could not save. Try again.";
}

export async function savePartner(_prev: SaveState, form: FormData): Promise<SaveState> {
  await assertAdmin();
  const parsed = parsePartnerForm(form);
  if (!parsed.ok) return { errors: parsed.errors, error: "Check the highlighted fields." };

  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("partner_save", { p: parsed.data });
  if (error) {
    if (error.code === "23505") return { errors: { slug: "Already used by another partner" }, error: dbMessage(error) };
    return { error: dbMessage(error) };
  }
  const id = (data as { id: number }).id;
  revalidatePath("/partners");
  revalidatePath(`/partners/${id}`);
  if (parsed.data.id === null) redirect(`/partners/${id}?created=1`);
  return { saved: Date.now() };
}

export async function setPartnerStatus(id: number, status: string, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ id: z.number().int().positive(), status: z.enum(STATUSES), reason: z.string().max(500) }).safeParse({ id, status, reason });
  if (!p.success) return "Invalid request.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("partner_set_status", { p_id: p.data.id, p_status: p.data.status, p_reason: p.data.reason || null });
  if (error) return dbMessage(error);
  revalidatePath("/partners");
  revalidatePath(`/partners/${id}`);
}

export async function setPartnerLive(id: number, live: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ id: z.number().int().positive(), live: z.boolean(), reason: z.string().trim().min(1).max(500) }).safeParse({ id, live, reason });
  if (!p.success) return "A reason is required.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("partner_set_live", { p_id: p.data.id, p_live: p.data.live, p_reason: p.data.reason });
  if (error) return dbMessage(error);
  revalidatePath("/", "layout"); // the shell's live indicator
}
