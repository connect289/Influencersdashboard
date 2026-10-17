// Campaign, eligibility, offer-terms and application rules shared by forms and server actions. The database
// enforces status transitions, eligibility, slots and who may act; these schemas shape and validate the input.
import { z } from "zod";
import { CONTENT_FORMATS, PLATFORMS } from "@/lib/creators/schemas";

export const OBJECTIVES = ["leads", "enrolments", "awareness", "content"] as const;
export const CAMPAIGN_STATUSES = [
  "draft",
  "open",
  "invite_only",
  "active",
  "paused",
  "completed",
  "archived",
] as const;
export type CampaignStatus = (typeof CAMPAIGN_STATUSES)[number];
export const VISIBILITIES = ["open", "invite_only", "both"] as const;
export const DEAL_TYPES = ["fixed", "commission", "hybrid", "barter"] as const;
export type DealType = (typeof DEAL_TYPES)[number];
export const APPLICATION_STATUSES = [
  "submitted",
  "shortlisted",
  "countered",
  "accepted",
  "rejected",
  "withdrawn",
] as const;
export const ELIGIBILITY_GAPS = [
  "not_approved",
  "platform",
  "followers",
  "niche",
  "language",
  "geography",
  "unknown",
] as const;

/** Allowed status moves (mirrors inf.campaign_set_status). */
export const STATUS_MOVES: Record<CampaignStatus, CampaignStatus[]> = {
  draft: ["open", "invite_only", "archived"],
  open: ["active", "invite_only", "paused", "completed"],
  invite_only: ["open", "active", "paused", "completed"],
  active: ["paused", "completed"],
  paused: ["open", "invite_only", "active", "completed"],
  completed: ["archived"],
  archived: [],
};

export const deliverableItem = z.object({
  platform: z.enum(PLATFORMS),
  format: z.enum(CONTENT_FORMATS),
  count: z.number().int().min(1).max(50),
});
export type DeliverableItem = z.infer<typeof deliverableItem>;

const words = z.array(z.string().trim().min(1).max(40)).max(20);
export const eligibilitySchema = z.object({
  min_followers: z.number().int().min(0).max(1_000_000_000).optional(),
  platforms: z.array(z.enum(PLATFORMS)).max(8).optional(),
  niches: words.optional(),
  languages: words.optional(),
  states: words.optional(),
});
export type Eligibility = z.infer<typeof eligibilitySchema>;

const isoDate = z.union([z.literal(""), z.iso.date()]);

export const campaignInput = z
  .object({
    id: z.uuid().optional(),
    name: z.string().trim().min(3).max(120),
    objective: z.enum(OBJECTIVES),
    description: z.string().trim().max(8000).default(""),
    visibility: z.enum(VISIBILITIES).default("open"),
    startsOn: isoDate.default(""),
    endsOn: isoDate.default(""),
    applyBy: isoDate.default(""),
    /** Rupees as typed; stored as integer paise. */
    budgetRupees: z.number().min(0).max(1_000_000_000).nullable().default(null),
    slots: z.number().int().min(1).max(10_000).nullable().default(null),
    eligibility: eligibilitySchema.default({}),
    deliverables: z.array(deliverableItem).max(20).default([]),
    compensationSummary: z.string().trim().max(1000).default(""),
    internalNotes: z.string().trim().max(4000).default(""),
    ownerId: z.union([z.literal(""), z.uuid()]).default(""),
    presetId: z.union([z.literal(""), z.uuid()]).default(""),
    contractTemplateId: z.union([z.literal(""), z.uuid()]).default(""),
    briefTemplateId: z.union([z.literal(""), z.uuid()]).default(""),
    programmeIds: z.array(z.number().int().positive()).max(30).default([]),
  })
  .refine((v) => !v.startsOn || !v.endsOn || v.endsOn >= v.startsOn, {
    path: ["endsOn"],
    message: "end_before_start",
  })
  .refine((v) => !v.applyBy || !v.endsOn || v.applyBy <= v.endsOn, {
    path: ["applyBy"],
    message: "apply_after_end",
  });
export type CampaignInput = z.input<typeof campaignInput>;

/** Offer terms (an application's proposed or counter-offered deal). Commission specifics come from the deal preset. */
export const offerTerms = z
  .object({
    deal_type: z.enum(DEAL_TYPES),
    fixed_fee_paise: z.number().int().min(0).max(100_000_000_00).optional(),
    includes_commission: z.boolean().optional(),
    deliverables: z.array(deliverableItem).max(20).default([]),
    usage_rights: z.string().trim().max(300).optional(),
    exclusivity_days: z.number().int().min(0).max(365).optional(),
    notes: z.string().trim().max(1000).optional(),
    counter: z.boolean().optional(),
  })
  .refine((t) => !["fixed", "hybrid"].includes(t.deal_type) || (t.fixed_fee_paise ?? 0) > 0, {
    path: ["fixed_fee_paise"],
    message: "fee_required",
  });
export type OfferTerms = z.infer<typeof offerTerms>;

export function rupeesToPaise(rupees: number): number {
  return Math.round(rupees * 100);
}

export const applyInput = z.object({
  campaignId: z.uuid(),
  creatorId: z.uuid(),
  pitch: z.string().trim().max(4000).default(""),
  samples: z
    .array(
      z
        .string()
        .trim()
        .refine((v) => /^https:\/\/\S{4,}$/.test(v), "sample"),
    )
    .max(10)
    .default([]),
  terms: offerTerms,
});
export type ApplyInput = z.input<typeof applyInput>;
