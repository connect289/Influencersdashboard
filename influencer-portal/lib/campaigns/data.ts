import "server-only";
import type { ApplicationDetail } from "@/components/campaigns/application-view";
import type { CampaignFormValues } from "@/components/campaigns/campaign-form";
import type { ProgrammeCard } from "@/components/campaigns/campaign-details";
import { deliverableItem, eligibilitySchema } from "@/lib/campaigns/schemas";
import type { Database } from "@/lib/database.types";
import type { ServerSupabase } from "@/lib/supabase/server";
import { z } from "zod";

export type CampaignRow = Database["inf"]["Tables"]["campaigns"]["Row"];

export function deliverablesOf(v: unknown) {
  return z.array(deliverableItem).catch([]).parse(v);
}
export function eligibilityOf(v: unknown) {
  return eligibilitySchema.catch({}).parse(v);
}

export async function loadProgrammes(supabase: ServerSupabase, campaignId: string): Promise<ProgrammeCard[]> {
  const { data } = await supabase.rpc("campaign_programmes_view", { p_campaign: campaignId });
  return data ?? [];
}

export function formValuesOf(c: CampaignRow, programmes: ProgrammeCard[]): CampaignFormValues {
  return {
    id: c.id,
    name: c.name,
    objective: c.objective as CampaignFormValues["objective"],
    description: c.description ?? "",
    visibility: c.visibility as CampaignFormValues["visibility"],
    startsOn: c.starts_on ?? "",
    endsOn: c.ends_on ?? "",
    applyBy: c.apply_by ?? "",
    budgetRupees: c.budget_paise === null ? "" : String(c.budget_paise / 100),
    slots: c.slots === null ? "" : String(c.slots),
    eligibility: eligibilityOf(c.eligibility),
    deliverables: deliverablesOf(c.deliverables),
    compensationSummary: c.compensation_summary ?? "",
    internalNotes: c.internal_notes ?? "",
    ownerId: c.owner_id ?? "",
    presetId: c.default_preset_id ?? "",
    contractTemplateId: c.contract_template_id ?? "",
    briefTemplateId: c.brief_template_id ?? "",
    programmes: programmes
      .filter((p) => p.program_name)
      .map((p) => ({
        id: p.id,
        program_name: p.program_name ?? "",
        specialization: p.specialization,
        level: p.level,
        mode: p.mode,
        university: p.university ?? "",
        fee_total: p.fee_total,
      })),
  };
}

export async function loadApplication(
  supabase: ServerSupabase,
  appId: string,
): Promise<{ app: ApplicationDetail | null; error: boolean }> {
  const { data, error } = await supabase.rpc("application_detail", { p_app: appId });
  if (error) return { app: null, error: error.code !== "42501" };
  return { app: data as unknown as ApplicationDetail | null, error: false };
}
