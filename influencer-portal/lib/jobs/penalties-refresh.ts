import "server-only";
import { z } from "zod";
import { compConfig } from "@/lib/compensation/schema";
import { penaltyProposals, type ContentFacts } from "@/lib/content/events";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ deal_id: z.uuid() });
const nullableCount = z.number().nullable();
const factsSchema = z.object({
  deal: z.object({ id: z.uuid(), starts_on: z.string(), ends_on: z.string().nullable() }),
  versions: z.array(z.object({ id: z.uuid(), effective_from: z.string(), config: compConfig })),
  contract_signed_at: z.string().nullable(),
  brief_acknowledged_at: z.string().nullable(),
  deliverables: z.array(
    z.object({
      id: z.uuid(),
      config_ref: z.string().nullable(),
      due_live_at: z.string().nullable(),
      concept_approved_at: z.string().nullable(),
      draft_approved_at: z.string().nullable(),
      live_at: z.string().nullable(),
      cancelled_at: z.string().nullable(),
      disclosure_failed_at: z.string().nullable(),
      metrics: z.array(z.object({ at: z.string(), views: nullableCount, reach: nullableCount })),
    }),
  ),
}) satisfies z.ZodType<ContentFacts & object>;

const contextSchema = z.object({
  eduwit_gst_bps: z.number().int(),
  hold_days: z.number().int(),
  refund_window_days: z.number().int(),
  penalty_cap_bps: z.number().int(),
  confirm_partial_receipts: z.boolean(),
});

/**
 * Recomputes a deal's penalty proposals with the compensation engine after a deliverable goes live, is cancelled or
 * fails its disclosure check. Proposals wait for a person to approve them (inf.penalty_decide); nothing is charged here.
 */
export const penaltiesRefresh: JobHandler = async (job) => {
  const { deal_id } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const [facts, ctx] = await Promise.all([db.rpc("deal_content_facts", { p_deal: deal_id }), db.rpc("comp_context")]);
  if (facts.error) throw new Error(facts.error.message);
  if (ctx.error) throw new Error(ctx.error.message);
  if (facts.data === null) return;
  const f = factsSchema.parse(facts.data);
  if (f.versions.length === 0) return;
  const proposals = penaltyProposals({
    deal: f.deal,
    versions: f.versions,
    facts: f,
    as_of: new Date().toISOString(),
    context: contextSchema.parse(ctx.data),
  });
  const items = proposals.map((p) => ({
    key: p.key,
    rule_id: p.rule_id,
    version_id: p.version_id,
    subject: p.subject,
    amount_paise: p.amount_paise,
    at: p.at,
    reason: p.reason,
    forfeits: p.forfeits,
  }));
  const { error } = await db.rpc("penalty_proposals_sync", { p_deal: deal_id, p_items: items });
  if (error) throw new Error(error.message);
};
