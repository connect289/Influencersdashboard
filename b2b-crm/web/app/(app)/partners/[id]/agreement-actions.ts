"use server";
import { revalidatePath } from "next/cache";
import { assertAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** The Admin confirms (or clears) the signed agreement and data-processing terms: the go-live checklist's first item. */
export async function confirmPartnerAgreement(id: number, note: string): Promise<string | void> {
  await assertAdmin();
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("partner_agreement_confirm", { p_id: id, p_note: note });
  if (error) return error.code === "22023" ? error.message : "Could not record the agreement. Try again.";
  revalidatePath(`/partners/${id}`);
}

export async function clearPartnerAgreement(id: number, reason: string): Promise<string | void> {
  await assertAdmin();
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("partner_agreement_clear", { p_id: id, p_reason: reason });
  if (error) return error.code === "22023" ? error.message : "Could not clear the agreement. Try again.";
  revalidatePath(`/partners/${id}`);
}
