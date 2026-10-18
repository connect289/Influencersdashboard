import { z } from "zod";
import { deliverableItem, eligibilitySchema } from "@/lib/campaigns/schemas";

/** What creators may see of a campaign (inf.campaign_public). */
export const campaignPublic = z.object({
  id: z.uuid(),
  name: z.string(),
  objective: z.string(),
  description: z.string().nullable(),
  status: z.string(),
  visibility: z.string(),
  starts_on: z.string().nullable(),
  ends_on: z.string().nullable(),
  apply_by: z.string().nullable(),
  deliverables: z.array(deliverableItem).catch([]),
  compensation_summary: z.string().nullable(),
  eligibility: eligibilitySchema.catch({}),
  slots: z.number().nullable(),
  slots_left: z.number().nullable(),
  gaps: z.array(z.string()),
  application: z.object({ id: z.uuid(), status: z.string() }).nullable(),
  invite: z.object({ id: z.uuid(), status: z.string(), message: z.string().nullable() }).nullable(),
});
export type CampaignPublic = z.infer<typeof campaignPublic>;
