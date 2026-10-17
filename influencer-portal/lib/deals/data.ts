import "server-only";
import { z } from "zod";
import type { EngineContext } from "@/lib/compensation/engine";
import { compConfig } from "@/lib/compensation/schema";
import { TDS_COMPONENTS, type TdsSection } from "@/lib/compensation/tax";
import { adminClient } from "@/lib/supabase/admin";
import type { ServerSupabase } from "@/lib/supabase/server";
import { DEAL_MODELS, DEAL_STATUSES, VERSION_ORIGINS, VERSION_STATES } from "./schemas";

const version = z.object({
  id: z.uuid(),
  version: z.number().int(),
  comp_config: compConfig,
  origin: z.enum(VERSION_ORIGINS),
  effective_from: z.string(),
  note: z.string().nullable(),
  state: z.enum(VERSION_STATES),
  proposed_at: z.string(),
  decided_at: z.string().nullable(),
  decision_reason: z.string().nullable(),
  is_signed: z.boolean(),
  deal_model: z.enum(DEAL_MODELS),
});
export type DealVersionView = z.infer<typeof version>;

const run = z.object({
  id: z.number(),
  kind: z.string(),
  as_of: z.string(),
  summary: z.record(z.string(), z.unknown()),
  created_at: z.string(),
});

export const dealDetailSchema = z.object({
  id: z.uuid(),
  code: z.string(),
  title: z.string(),
  status: z.enum(DEAL_STATUSES),
  starts_on: z.string(),
  ends_on: z.string().nullable(),
  deal_model: z.enum(DEAL_MODELS),
  creator_id: z.uuid(),
  campaign_id: z.uuid().nullable(),
  agreed_at: z.string().nullable(),
  activated_at: z.string().nullable(),
  closed_at: z.string().nullable(),
  status_reason: z.string().nullable(),
  current_version_id: z.uuid().nullable(),
  creator: z.object({ id: z.uuid(), display_name: z.string(), handle: z.string() }),
  campaign: z
    .object({
      id: z.uuid(),
      name: z.string(),
      starts_on: z.string().nullable(),
      ends_on: z.string().nullable(),
      status: z.string(),
    })
    .nullable(),
  versions: z.array(version),
  can_respond: z.boolean(),
  // Staff only:
  draft_config: compConfig.nullable().optional(),
  internal_notes: z.string().nullable().optional(),
  owner_id: z.uuid().nullable().optional(),
  preset_id: z.uuid().nullable().optional(),
  application_id: z.uuid().nullable().optional(),
  can_write: z.boolean().optional(),
  runs: z.array(run).optional(),
});
export type DealDetail = z.infer<typeof dealDetailSchema>;

export async function loadDeal(supabase: ServerSupabase, id: string): Promise<DealDetail | null> {
  const { data, error } = await supabase.rpc("deal_detail", { p_deal: id });
  if (error) throw new Error(error.message);
  return data === null ? null : dealDetailSchema.parse(data);
}

/** The version in force and any open proposal. */
export function versionsOf(d: DealDetail) {
  return {
    current: d.versions.find((v) => v.id === d.current_version_id) ?? null,
    pending: d.versions.find((v) => v.state === "proposed") ?? null,
    accepted: d.versions
      .filter((v) => v.state === "accepted")
      .sort((a, b) => a.effective_from.localeCompare(b.effective_from)),
  };
}

export const dealRowSchema = z.object({
  id: z.uuid(),
  code: z.string(),
  title: z.string(),
  status: z.enum(DEAL_STATUSES),
  deal_model: z.enum(DEAL_MODELS),
  starts_on: z.string(),
  ends_on: z.string().nullable(),
  creator_id: z.uuid().optional(),
  creator_name: z.string().optional(),
  handle: z.string().optional(),
  campaign_name: z.string().nullable(),
  owner_id: z.uuid().nullable().optional(),
  updated_at: z.string().optional(),
  pending: z.boolean(),
  application_id: z.uuid().nullable().optional(),
});
export type DealRow = z.infer<typeof dealRowSchema>;

export const presetSchema = z.object({
  id: z.uuid(),
  key: z.string().nullable(),
  name: z.string(),
  description: z.string().nullable(),
  comp_config: compConfig,
  is_system: z.boolean(),
  deal_model: z.enum(DEAL_MODELS),
  archived: z.boolean(),
});
export type Preset = z.infer<typeof presetSchema>;

export async function loadPresets(
  supabase: ServerSupabase,
  includeArchived = false,
): Promise<Preset[]> {
  const { data, error } = await supabase.rpc("deal_presets_list", {
    p_include_archived: includeArchived,
  });
  if (error) throw new Error(error.message);
  return z.array(presetSchema).parse(data);
}

const contextSchema = z.object({
  eduwit_gst_bps: z.number().int(),
  hold_days: z.number().int(),
  refund_window_days: z.number().int(),
  penalty_cap_bps: z.number().int(),
  confirm_partial_receipts: z.boolean(),
  gst_rate_bps: z.number().int(),
});
export type CompContext = { engine: EngineContext; gst_rate_bps: number };

export async function loadCompContext(supabase: ServerSupabase): Promise<CompContext> {
  const { data, error } = await supabase.rpc("comp_context");
  if (error) throw new Error(error.message);
  const c = contextSchema.parse(data);
  const { gst_rate_bps, ...engine } = c;
  return { engine, gst_rate_bps };
}

const sectionSchema = z.object({
  code: z.string(),
  label: z.string(),
  rate_bps: z.number().int(),
  no_pan_rate_bps: z.number().int(),
  single_threshold_paise: z.number().int().nullable(),
  fy_threshold_paise: z.number().int().nullable(),
  components: z.array(z.enum(TDS_COMPONENTS)),
  borne_by: z.enum(["creator", "eduwit"]),
  confirmed_by_ca: z.boolean(),
});

export async function loadTdsSections(
  supabase: ServerSupabase,
): Promise<{ sections: TdsSection[]; confirmed: boolean }> {
  const { data, error } = await supabase.rpc("tds_sections_list");
  if (error) throw new Error(error.message);
  const rows = z.array(sectionSchema).parse(data);
  return {
    sections: rows.map(({ confirmed_by_ca: _c, ...s }) => s),
    confirmed: rows.every((r) => r.confirmed_by_ca),
  };
}

/**
 * Eduwit's average commission per enrolment for a campaign (GST-inclusive paise), from the catalogue. Read with the
 * service role so a creator's simulator can use it server-side; callers must never return it to a creator.
 */
export async function commissionEstimate(campaignId: string | null): Promise<number | null> {
  if (!campaignId) return null;
  const { data, error } = await adminClient().rpc("commission_estimate", {
    p_campaign: campaignId,
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function loadMyDeals(supabase: ServerSupabase, creatorId: string): Promise<DealRow[]> {
  const { data, error } = await supabase.rpc("my_deals", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(dealRowSchema).parse(data);
}

/** Active presets as picker options; empty for staff who cannot read deals. */
export async function presetOptions(
  supabase: ServerSupabase,
): Promise<{ id: string; name: string }[]> {
  const { data } = await supabase.rpc("deal_presets_list", { p_include_archived: false });
  return z
    .array(z.object({ id: z.uuid(), name: z.string() }))
    .catch([])
    .parse(data ?? []);
}
