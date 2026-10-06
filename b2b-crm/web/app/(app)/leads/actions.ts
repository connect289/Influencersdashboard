"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { DELETE_REASONS, parseLeadQuery, type LeadPage } from "@/lib/leads";
import { EDIT_FIELDS, parseEdit } from "@/lib/lead-edit";
import { listLeads } from "@/lib/leads-data";
import { createClient } from "@/lib/supabase/server";

const Ids = z.array(z.number().int().positive()).min(1).max(500);
type Blocked = { id: number; why: string }[];

/** Next page for the table's "Load more". The search string is parsed exactly like the page's own URL. */
export async function loadMoreLeads(search: string, after: { v: string; id: string }): Promise<LeadPage> {
  await assertAdmin();
  const cursor = z.object({ v: z.string().max(100), id: z.string().regex(/^\d{1,18}$/) }).parse(after);
  const query = parseLeadQuery(Object.fromEntries(new URLSearchParams(search.slice(0, 2000))));
  return listLeads(query, cursor);
}

/** Moves leads to the recycle bin. Leads with an enrollment, or with a partner for the wrong reason, come back blocked. */
export async function deleteLeads(ids: number[], reason: string): Promise<{ ok: true; deleted: number[]; blocked: Blocked } | { ok: false; error: string }> {
  await assertAdmin();
  const parsed = z.object({ ids: Ids, reason: z.enum(DELETE_REASONS) }).safeParse({ ids, reason });
  if (!parsed.success) return { ok: false, error: "Choose up to 500 leads and a reason." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_soft_delete", { p_ids: parsed.data.ids, p_reason: parsed.data.reason });
  if (error) return { ok: false, error: "Could not delete. Try again." };
  revalidatePath("/leads");
  const r = data as { deleted: number[]; blocked: Blocked };
  return { ok: true, deleted: r.deleted ?? [], blocked: r.blocked ?? [] };
}

/** Brings leads back from the recycle bin, unless the student has since come back as a newer lead. */
export async function restoreLeads(ids: number[]): Promise<{ ok: true; restored: number[]; blocked: Blocked } | { ok: false; error: string }> {
  await assertAdmin();
  const parsed = Ids.safeParse(ids);
  if (!parsed.success) return { ok: false, error: "Choose up to 500 leads." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_restore", { p_ids: parsed.data });
  if (error) return { ok: false, error: "Could not restore. Try again." };
  revalidatePath("/leads");
  const r = data as { restored: number[]; blocked: Blocked };
  return { ok: true, restored: r.restored ?? [], blocked: r.blocked ?? [] };
}

export type EditState = { errors?: Record<string, string>; error?: string; ok?: number; changed?: number } | undefined;

/**
 * Corrects a lead through b2b.lead_edit (which writes via lead_intake and keeps the field history). The form carries
 * the values it was opened with, so only fields the Admin changed are sent; the database compares again anyway.
 */
export async function editLead(id: number, _prev: EditState, form: FormData): Promise<EditState> {
  await assertAdmin();
  if (!z.number().int().positive().safeParse(id).success) return { error: "Invalid lead." };
  let original: Record<string, string | null> = {};
  try { original = z.record(z.string(), z.string().nullable()).parse(JSON.parse(String(form.get("_original") ?? "{}"))); } catch { return { error: "Reload the lead and try again." }; }
  const values = Object.fromEntries(EDIT_FIELDS.filter((f) => form.has(f)).map((f) => [f, String(form.get(f) ?? "")]));
  const parsed = parseEdit(values, original);
  if (!parsed.ok) return { errors: parsed.errors, error: "Check the highlighted fields." };
  if (Object.keys(parsed.changes).length === 0) return { error: "Nothing changed." };
  const reason = z.string().trim().min(3).max(300).safeParse(form.get("reason") ?? "");
  if (!reason.success) return { errors: { reason: "Say why, for the audit log" }, error: "Check the highlighted fields." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("lead_edit", { p_lead_id: id, p_changes: parsed.changes, p_reason: reason.data });
  if (error) {
    const safe = error.code === "22023" || error.code === "P0002";
    return { error: safe ? error.message.charAt(0).toUpperCase() + error.message.slice(1) + "." : "Could not save. Try again." };
  }
  revalidatePath("/leads");
  return { ok: Date.now(), changed: ((data as { changed: unknown[] }).changed ?? []).length };
}
