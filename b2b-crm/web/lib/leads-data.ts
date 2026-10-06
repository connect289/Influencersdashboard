import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { EditHistory } from "@/lib/lead-edit";
import { toRpcParams, type Cursor, type Facets, type LeadPage, type LeadQuery } from "@/lib/leads";

/**
 * Lead reads, as the signed-in Admin. Every b2b.leads_* function re-checks b2b.is_admin() and builds its WHERE clause
 * from literals (format %L), so nothing here is trusted for access or escaping.
 */

export type LeadDetail = {
  lead: Record<string, unknown> & { id: number; is_test: boolean; deleted_at: string | null; destination_type: string | null };
  touchpoints: { at: string; system: string | null; event: string | null; source: string | null; campaign: string | null }[];
  messages: { at: string; direction: "in" | "out"; kind: string | null; content: string | null }[];
  events: { at: string; type: string; actor: string; payload: Record<string, unknown> }[];
  deletions: { at: string; action: "delete" | "restore"; reason: string | null }[];
  has_enrollment: boolean;
};

export async function listLeads(q: LeadQuery, after: Cursor | null = null): Promise<LeadPage> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_list", { p: toRpcParams(q, { after }) });
  if (error) throw new Error(`leads_list failed (${error.code ?? "unknown"})`);
  return data as LeadPage;
}

export async function leadFacets(q: LeadQuery): Promise<Facets> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_facets", { p: { q: q.q || undefined, include_test: q.test, bin: q.bin } });
  if (error) throw new Error(`leads_facets failed (${error.code ?? "unknown"})`);
  return data as Facets;
}

export async function leadDetail(id: number): Promise<LeadDetail | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("lead_detail", { p_id: id });
  if (error) throw new Error(`lead_detail failed (${error.code ?? "unknown"})`);
  return (data as LeadDetail | null) ?? null;
}

export async function leadEditHistory(id: number): Promise<EditHistory> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("lead_edit_history", { p_lead_id: id });
  if (error) throw new Error(`lead_edit_history failed (${error.code ?? "unknown"})`);
  return (data ?? []) as EditHistory;
}
