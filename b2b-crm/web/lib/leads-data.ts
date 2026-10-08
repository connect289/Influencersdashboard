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

/**
 * One page of b2b.leads_list (m31l). toRpcParams carries every filter of the URL, including the Addendum 3 `destination`
 * flags (barred, qualification_nurture, awaiting_consent, reenquired, lost_grace) and `paid` (meta | google | any), which
 * b2b.lead_filter_sql turns into WHERE clauses; the rows carry the Addendum 3 columns (partner bar, other providers, lane,
 * hold kind, re-enquiry, paid platform, consent state, lost grace).
 */
export async function listLeads(q: LeadQuery, after: Cursor | null = null): Promise<LeadPage> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_list", { p: toRpcParams(q, { after }) });
  if (error) throw new Error(`leads_list failed (${error.code ?? "unknown"})`);
  return data as LeadPage;
}

/**
 * Facet counts for the chips (b2b.leads_facets, m31l). They follow the search, the test switch and the bin, not each
 * other: every option stays visible. `destination` holds the four routing destinations and the five flags; `paid` the
 * Meta / Google / any counts. Missing keys (an older database) read as zero so the bar still renders.
 */
export async function leadFacets(q: LeadQuery): Promise<Facets> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_facets", { p: { q: q.q || undefined, include_test: q.test, bin: q.bin } });
  if (error) throw new Error(`leads_facets failed (${error.code ?? "unknown"})`);
  const f = (data ?? {}) as Partial<Facets> & { paid?: Partial<Facets["paid"]> | null };
  return {
    stage: f.stage ?? {},
    source: f.source ?? {},
    status: f.status ?? {},
    destination: f.destination ?? {},
    paid: { meta: f.paid?.meta ?? 0, google: f.paid?.google ?? 0, any: f.paid?.any ?? 0 },
    bin: f.bin ?? 0,
    tests: f.tests ?? 0,
  };
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
