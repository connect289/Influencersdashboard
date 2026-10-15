import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { AuditPage, DataProtection, ErasureRow, SystemOverview } from "@/lib/integrations";

/** System reads as the signed-in Admin; b2b.system_overview re-checks b2b.is_admin() and never returns key hashes or secrets. */
export async function systemOverview(): Promise<SystemOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("system_overview");
  if (error) throw new Error(`system_overview failed (${error.code ?? "unknown"})`);
  return data as SystemOverview;
}

/** M33c: the audit log page and the data-protection overview. */
export async function auditLog(p: { actor_type?: string; q?: string; lead_id?: number; partner_id?: number; after?: number; limit?: number }): Promise<AuditPage> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("audit_log", { p });
  if (error) throw new Error(`audit_log failed (${error.code ?? "unknown"})`);
  return data as AuditPage;
}
export async function dataProtection(): Promise<DataProtection> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("data_protection_overview");
  if (error) throw new Error(`data_protection_overview failed (${error.code ?? "unknown"})`);
  return data as DataProtection;
}

export async function openErasureRequests(): Promise<ErasureRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("erasure_requests_open");
  if (error) throw new Error(`erasure_requests_open failed (${error.code ?? "unknown"})`);
  return (data ?? []) as ErasureRow[];
}
