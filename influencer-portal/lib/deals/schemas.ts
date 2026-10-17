// Deal inputs shared by the server actions and the builder. The compensation config itself is validated by
// compConfig (lib/compensation/schema.ts) and again in the database (inf.comp_config_valid).
import { z } from "zod";
import { compConfig } from "@/lib/compensation/schema";

export const DEAL_STATUSES = [
  "draft",
  "proposed",
  "negotiating",
  "agreed",
  "active",
  "completed",
  "terminated",
  "expired",
] as const;
export type DealStatus = (typeof DEAL_STATUSES)[number];
export const DEAL_MODELS = ["commission_only", "fixed_only", "hybrid", "barter", "custom"] as const;
export type DealModel = (typeof DEAL_MODELS)[number];
export const VERSION_STATES = ["proposed", "accepted", "declined", "withdrawn", "superseded"] as const;
export type VersionState = (typeof VERSION_STATES)[number];
export const VERSION_ORIGINS = ["builder", "application", "amendment", "renewal", "counter_offer"] as const;

/** Staff status moves allowed from each status (mirrors inf.deal_set_status). */
export const DEAL_MOVES: Record<DealStatus, DealStatus[]> = {
  draft: ["terminated"],
  proposed: ["terminated"],
  negotiating: ["terminated"],
  agreed: ["active", "terminated"],
  active: ["completed", "terminated"],
  completed: [],
  terminated: [],
  expired: [],
};
export const OPEN_STATUSES: readonly DealStatus[] = ["draft", "proposed", "negotiating", "agreed", "active"];

const isoDate = z.iso.date();
const optionalDate = z.union([z.literal(""), isoDate]).default("");

export const dealCreateInput = z
  .object({
    creatorId: z.uuid(),
    campaignId: z.union([z.literal(""), z.uuid()]).default(""),
    title: z.string().trim().min(3).max(120),
    startsOn: isoDate,
    endsOn: optionalDate,
    presetId: z.union([z.literal(""), z.uuid()]).default(""),
    config: compConfig,
    internalNotes: z.string().trim().max(4000).default(""),
  })
  .refine((v) => !v.endsOn || v.endsOn >= v.startsOn, { path: ["endsOn"], message: "end_before_start" });
export type DealCreateInput = z.input<typeof dealCreateInput>;

export const dealUpdateInput = z
  .object({
    dealId: z.uuid(),
    title: z.string().trim().min(3).max(120).optional(),
    startsOn: isoDate.optional(),
    endsOn: optionalDate.optional(),
    config: compConfig.nullable().optional(),
    ownerId: z.union([z.literal(""), z.uuid()]).optional(),
    internalNotes: z.string().trim().max(4000).optional(),
  })
  .refine((v) => !v.endsOn || !v.startsOn || v.endsOn >= v.startsOn, { path: ["endsOn"], message: "end_before_start" });
export type DealUpdateInput = z.input<typeof dealUpdateInput>;

/** An amendment's effective date-time as typed in IST ("YYYY-MM-DDTHH:mm"); empty = now. */
export const proposeInput = z.object({
  dealId: z.uuid(),
  effectiveFrom: z.union([z.literal(""), z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/)]).default(""),
  note: z.string().trim().max(1000).default(""),
});

export const respondInput = z
  .object({ versionId: z.uuid(), accept: z.boolean(), reason: z.string().trim().max(1000).default("") })
  .refine((v) => v.accept || v.reason.length >= 3, { path: ["reason"], message: "reason" });

export const statusInput = z
  .object({ dealId: z.uuid(), status: z.enum(DEAL_STATUSES), reason: z.string().trim().max(1000).default("") })
  .refine((v) => !["active", "terminated"].includes(v.status) || v.reason.length >= 3, {
    path: ["reason"],
    message: "reason",
  });

export const renewInput = z
  .object({ dealId: z.uuid(), startsOn: z.iso.date(), endsOn: z.iso.date().or(z.literal("")) })
  .refine((v) => !v.endsOn || v.endsOn >= v.startsOn, { path: ["endsOn"], message: "dates" });

export const presetInput = z.object({
  id: z.union([z.literal(""), z.uuid()]).default(""),
  name: z.string().trim().min(2).max(80),
  description: z.string().trim().max(500).default(""),
  config: compConfig,
});

/** "YYYY-MM-DDTHH:mm" in IST → ISO instant. */
export function istLocalToIso(local: string): string {
  return new Date(`${local}:00+05:30`).toISOString();
}

/** Database messages → message keys (deals.errors.*). */
export const DEAL_DB_ERRORS: [RegExp, string][] = [
  [/invalid compensation config/i, "config"],
  [/creator cannot take a deal/i, "creator"],
  [/dates are fixed/i, "datesFixed"],
  [/deal is closed/i, "closed"],
  [/cannot take a proposal/i, "cannotPropose"],
  [/nothing to propose/i, "nothingToPropose"],
  [/proposal is already open/i, "proposalOpen"],
  [/terms are unchanged/i, "unchanged"],
  [/must take effect after/i, "effectiveFrom"],
  [/no longer open/i, "proposalClosed"],
  [/reason is required/i, "reason"],
  [/cannot move a/i, "transition"],
  [/only unproposed drafts/i, "deleteDraft"],
  [/system presets/i, "systemPreset"],
  [/preset with this name/i, "presetName"],
  [/only active or ended deals can be renewed/i, "renew"],
  [/end before start/i, "dates"],
];
