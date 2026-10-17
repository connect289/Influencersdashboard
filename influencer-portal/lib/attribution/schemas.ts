// Inputs for the link and attribution actions, shared by forms and server actions.
import { z } from "zod";
import { PLATFORMS } from "@/lib/creators/schemas";
import { DESTINATIONS } from "./links";

const uuid = z.uuid();

export const linkInput = z
  .object({
    creatorId: uuid,
    dealId: uuid.nullable().default(null),
    deliverableId: uuid.nullable().default(null),
    programmeId: z.number().int().positive().nullable().default(null),
    destination: z.enum(DESTINATIONS),
    customUrl: z.string().trim().max(1000).default(""),
    platform: z.enum(PLATFORMS).nullable().default(null),
    label: z.string().trim().max(120).default(""),
  })
  .refine((v) => v.destination !== "custom_url" || /^https:\/\/[^\s/]+\.[^\s]+$/i.test(v.customUrl), {
    path: ["customUrl"],
    message: "https",
  });
export type LinkInput = z.input<typeof linkInput>;

export const overrideInput = z.object({
  studentLeadId: z.number().int().positive(),
  creatorId: uuid,
  status: z.enum(["manually_credited", "manually_rejected"]),
  linkId: uuid.nullable().default(null),
  reason: z.string().trim().min(3).max(1000),
});
export type OverrideInput = z.input<typeof overrideInput>;

export const fraudDecisionInput = z.object({
  flagId: uuid,
  confirm: z.boolean(),
  note: z.string().trim().min(3).max(1000),
});

export const backfillInput = z
  .object({ from: z.iso.date(), to: z.iso.date() })
  .refine((v) => v.to >= v.from, { path: ["to"] });

/** A campaign's own attribution model and WhatsApp message (empty = the global setting). */
export const campaignAttributionInput = z.object({
  campaignId: uuid,
  model: z.enum(["", "first_touch", "last_touch", "first_touch_with_assisted"]).default(""),
  message: z
    .string()
    .trim()
    .max(500)
    .default("")
    .refine((m) => m === "" || (m.length >= 10 && m.includes("{code}")), { message: "code" }),
});
export type CampaignAttributionInput = z.input<typeof campaignAttributionInput>;

export const stageRuleInput = z.object({
  id: uuid.nullable().default(null),
  priority: z.number().int().min(1).max(9999),
  conditions: z
    .array(
      z.object({
        field: z.enum([
          "attribution_status",
          "stage",
          "lost_reason",
          "enrollment_status",
          "applied_at",
          "is_sales_ready",
          "b2c_stage",
          "b2c_closed_reason",
        ]),
        in: z.array(z.string().trim().min(1).max(60)).max(20).optional(),
        present: z.boolean().optional(),
        empty: z.boolean().optional(),
        is_true: z.boolean().optional(),
      }),
    )
    .min(1)
    .max(6),
  creatorStage: z
    .enum([
      "new",
      "qualifying",
      "qualified",
      "allocated",
      "counselling",
      "applied",
      "enrolled",
      "lost",
      "duplicate",
      "junk",
      "not_attributed",
    ])
    .nullable(),
  reasonCategory: z.string().trim().max(80).default(""),
  flag: z.enum(["cancelled", "under_review"]).nullable().default(null),
  active: z.boolean().default(true),
});
export type StageRuleInput = z.input<typeof stageRuleInput>;

/** Database messages → leads.errors.* keys (first match wins). */
export const ATTRIBUTION_DB_ERRORS: readonly [RegExp, string][] = [
  [/this code is taken/, "codeTaken"],
  [/custom addresses are set by Eduwit/, "customUrlStaff"],
  [/links need an agreed deal/, "needsDeal"],
  [/programme not in this campaign/, "programme"],
  [/invalid (deal|deliverable|programme)/, "invalidTarget"],
  [/a reason is required/, "reasonRequired"],
  [/no attribution to reject/, "nothingToReject"],
  [/no such lead/, "noLead"],
  [/already been decided/, "alreadyDecided"],
  [/range of up to 400 days/, "range"],
  [/another rule has this priority/, "priorityTaken"],
];
