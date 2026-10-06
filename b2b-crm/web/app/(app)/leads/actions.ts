"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { DELETE_REASONS, parseLeadQuery, type LeadPage } from "@/lib/leads";
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
