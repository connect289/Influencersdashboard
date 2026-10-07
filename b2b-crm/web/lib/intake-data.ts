import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { IntakeOverview } from "@/lib/intake";

/** Intake reads as the signed-in Admin; b2b.intake_overview re-checks b2b.is_admin(). */
export async function intakeOverview(): Promise<IntakeOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("intake_overview");
  if (error) throw new Error(`intake_overview failed (${error.code ?? "unknown"})`);
  return data as IntakeOverview;
}
