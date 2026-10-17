// The ledger runner's core (spec 6.3, D-63): gather a deal's facts read-only (inf.ledger_facts), replay them with the
// compensation engine and diff against what is posted (planDeal), then write the outcome (inf.ledger_apply), which
// also posts approved penalties and extra revision fees and syncs penalty proposals. Takes a service-role client so
// the seed can run the same path; the app uses runner.ts. Idempotent.
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { compConfig } from "@/lib/compensation/schema";
import type { Database } from "@/lib/database.types";
import { planDeal, type DealPlan } from "./plan";

export type RunnerClient = SupabaseClient<Database, "inf">;

const iso = z.string();
const nullableIso = iso.nullable();
const count = z.number().nullable();

const factsSchema = z.object({
  deal: z.object({
    id: z.uuid(),
    creator_id: z.uuid(),
    starts_on: z.string(),
    ends_on: z.string().nullable(),
    status: z.string(),
    campaign_ends_on: z.string().nullable(),
  }),
  versions: z.array(z.object({ id: z.uuid(), effective_from: iso, config: compConfig })),
  context: z.object({
    eduwit_gst_bps: z.number().int(),
    hold_days: z.number().int(),
    refund_window_days: z.number().int(),
    penalty_cap_bps: z.number().int(),
    confirm_partial_receipts: z.boolean(),
  }),
  contract_signed_at: nullableIso,
  brief_acknowledged_at: nullableIso,
  deliverables: z.array(
    z.object({
      id: z.uuid(),
      config_ref: z.string().nullable(),
      due_live_at: nullableIso,
      concept_approved_at: nullableIso,
      draft_approved_at: nullableIso,
      live_at: nullableIso,
      cancelled_at: nullableIso,
      disclosure_failed_at: nullableIso,
      metrics: z.array(z.object({ at: iso, views: count, reach: count })),
    }),
  ),
  leads: z.array(
    z.object({
      id: z.uuid(),
      at: iso,
      link_id: z.uuid().nullable(),
      deliverable_ref: z.string().nullable(),
      programme_id: z.number().int().nullable(),
      university_id: z.number().int().nullable(),
      level: z.string().nullable(),
      qualified_at: nullableIso,
      applied_at: nullableIso,
      rejected_at: nullableIso,
      junk: z.boolean(),
    }),
  ),
  enrollments: z.array(
    z.object({
      ref: z.string(),
      lead_id: z.uuid(),
      at: iso,
      programme_id: z.number().int().nullable(),
      university_id: z.number().int().nullable(),
      level: z.string().nullable(),
      fee_paise: z.number().int().nullable(),
      expected_commission_gross_paise: z.number().int().nullable(),
      cancelled_at: nullableIso,
    }),
  ),
  receipts: z.array(
    z.object({ enrollment_ref: z.string(), received_paise: z.number().int(), received_on: iso, full: z.boolean() }),
  ),
  manual: z.array(
    z.object({ id: z.uuid(), kind: z.enum(["manual_release", "breach"]), ref: z.string().nullable(), at: iso }),
  ),
  campaign_ended_at: nullableIso,
  deal_completed_at: nullableIso,
  posted: z.array(
    z.object({
      key: z.string(),
      type: z.enum([
        "fixed_fee",
        "milestone",
        "commission",
        "bonus",
        "usage_fee",
        "exclusivity_fee",
        "reimbursement",
        "clawback",
        "adjustment",
      ]),
      direction: z.enum(["credit", "debit"]),
      amount_paise: z.number().int(),
      confirmed_paise: z.number().int(),
      reversed: z.boolean(),
      paid_paise: z.number().int(),
      in_open_batch: z.boolean(),
    }),
  ),
});
export type LedgerFacts = z.infer<typeof factsSchema>;

/** The facts and the plan for a deal as of `asOf`, without writing anything (null when the deal has no terms). */
export async function planDealWith(
  db: RunnerClient,
  dealId: string,
  asOf: string,
): Promise<{ facts: LedgerFacts; plan: DealPlan } | null> {
  const { data, error } = await db.rpc("ledger_facts", { p_deal: dealId });
  if (error) throw new Error(error.message);
  if (data === null) return null;
  const f = factsSchema.parse(data);
  if (f.versions.length === 0) return null;
  const plan = planDeal({
    deal: {
      id: f.deal.id,
      starts_on: f.deal.starts_on,
      ends_on: f.deal.ends_on,
      campaign_ends_on: f.deal.campaign_ends_on,
    },
    versions: f.versions,
    facts: f,
    posted: f.posted,
    as_of: asOf,
    context: f.context,
  });
  return { facts: f, plan };
}

export interface RunResult {
  created: number;
  confirmed: number;
  reversed: number;
  other: number;
  deferred: number;
}

/** Runs one deal: plan, then apply. Returns null when the deal has no accepted terms yet. */
export async function runDealWith(db: RunnerClient, dealId: string, asOf: string): Promise<RunResult | null> {
  const planned = await planDealWith(db, dealId, asOf);
  if (!planned) return null;
  const { facts, plan } = planned;
  const payload = {
    as_of: asOf,
    create: plan.create.map((c) => ({
      key: c.key,
      type: c.type,
      direction: c.direction,
      amount_paise: c.amount_paise,
      confirmed_paise: c.confirmed_paise,
      rule_id: c.rule_id,
      version_id: c.version_id,
      subject: c.subject,
      period: c.period,
      due_on: c.due_on,
      note: c.note,
      tds_component: c.tds_component,
    })),
    confirm: plan.confirm,
    reverse: plan.reverse,
    deferred: plan.deferred,
    unchanged: plan.unchanged,
    proposals: plan.result.proposals.map((p) => ({
      key: p.key,
      rule_id: p.rule_id,
      version_id: p.version_id,
      subject: p.subject,
      amount_paise: p.amount_paise,
      at: p.at,
      reason: p.reason,
      forfeits: p.forfeits,
    })),
    enrolment_leads: Object.fromEntries(facts.enrollments.map((e) => [e.ref, e.lead_id])),
  };
  const { data, error } = await db.rpc("ledger_apply", {
    p_deal: dealId,
    p: JSON.parse(JSON.stringify(payload)) as never,
  });
  if (error) throw new Error(error.message);
  const r = z
    .object({ created: z.number(), confirmed: z.number(), reversed: z.number(), other: z.number() })
    .parse(data);
  return { ...r, deferred: plan.deferred.length };
}
