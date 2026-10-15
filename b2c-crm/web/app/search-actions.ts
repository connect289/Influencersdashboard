"use server";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";
import { maskPhone } from "@/lib/format";
import type { LeadRow } from "@/lib/types";

export type LeadHit = { lead_id: number; name: string | null; phone: string | null; course: string | null; stage: string | null; owner_name: string | null };

/** The search box behind ⌘K: the same lead search as the Leads page (name, any phone, email, application ID), eight hits. */
export async function searchLeads(q: string): Promise<ActionResult<LeadHit[]>> {
  await assertUser();
  const text = String(q ?? "").trim().slice(0, 80);
  if (text.length < 2) return { ok: true, data: [] };
  return act(async () => {
    const r = await rpc<{ rows: LeadRow[] }>("lead_list", { p: { search: text, limit: 8, sort: { field: "last_activity_at", dir: "desc" } } });
    return r.rows.map((l) => ({ lead_id: l.lead_id, name: l.name, phone: maskPhone(l.phone), course: l.course, stage: l.stage, owner_name: l.owner_name }));
  });
}
