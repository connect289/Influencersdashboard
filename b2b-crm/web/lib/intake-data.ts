import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { ConsentText, IntakeOverview } from "@/lib/intake";

/** Intake reads as the signed-in Admin; b2b.intake_overview re-checks b2b.is_admin(). */
export async function intakeOverview(): Promise<IntakeOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("intake_overview");
  if (error) throw new Error(`intake_overview failed (${error.code ?? "unknown"})`);
  return data as IntakeOverview;
}

/** The registered consent texts (b2b.consent_texts, admin_read RLS), newest first. Written only through b2b.consent_text_save. */
export async function consentTexts(): Promise<ConsentText[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("consent_texts")
    .select("version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at, approved_by, approval_note, created_at")
    .order("created_at", { ascending: false });
  if (error) throw new Error(`consent_texts read failed (${error.code ?? "unknown"})`);
  return (data ?? []) as ConsentText[];
}
