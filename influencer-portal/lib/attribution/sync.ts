import "server-only";
// The lead sweep (STAGE_MAPPING.md §4): gather facts from the shared tables (inf.lead_sync_candidates, read-only),
// run the pure rules (planLead), write the outcome (inf.lead_sync_apply), then evaluate fraud signals for the creators
// involved. Used by the every-minute sweep, staff re-runs and backfills. Idempotent.
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { creatorSignals, isOffHours, leadSignals, type FraudSettings } from "./fraud";
import { planLead, type CandidateLead } from "./plan";
import { ATTRIBUTION_STATUSES, type Rules } from "./rules";
import { CREATOR_STAGES, STAGE_FIELDS, type MappingRule } from "./stages";

const iso = z.string();
const status = z.enum(ATTRIBUTION_STATUSES);
const stageName = z.enum(CREATOR_STAGES);
const touchSchema = z.object({
  code: z.string(),
  link_id: z.string(),
  creator_id: z.string(),
  deal_id: z.string().nullable(),
  deliverable_id: z.string().nullable(),
  campaign_id: z.string().nullable(),
  at: iso,
  source: z.enum(["click", "referral_code", "touchpoint", "access_code"]),
});
const leadSchema = z.object({
  id: z.number().int(),
  created_at: iso,
  reopened_at: iso.nullable(),
  is_test: z.boolean(),
  touches: z.array(touchSchema),
  self_referral_creators: z.array(z.string()),
  existing: z.array(
    z.object({
      creator_id: z.string(),
      status,
      stage: stageName.nullable(),
      reason: z.string().nullable(),
      link_id: z.string().nullable(),
      code: z.string(),
      deal_id: z.string().nullable(),
      deliverable_id: z.string().nullable(),
      campaign_id: z.string().nullable(),
      touch: z.enum(["first", "last", "assisted", "none"]),
      attribution_reason: z
        .enum(["existing_lead", "another_creator", "outside_window", "self_referral"])
        .nullable(),
      touch_at: iso,
      evidence_source: z.enum(["click", "referral_code", "touchpoint", "access_code", "manual"]),
    }),
  ),
  stage: z.record(z.enum(STAGE_FIELDS), z.union([z.string(), z.boolean(), z.null()])),
  stage_changed_at: iso.nullable(),
}) satisfies z.ZodType<CandidateLead>;

const rulesSchema = z.object({
  window_days: z.number().int(),
  model: z.enum(["first_touch", "last_touch", "first_touch_with_assisted"]),
  duplicate_grace_minutes: z.number().int(),
  reenquiry_credit_after_days: z.number().int().nullable(),
}) satisfies z.ZodType<Rules>;

const conditionSchema = z.object({
  field: z.enum(STAGE_FIELDS),
  in: z.array(z.string()).optional(),
  present: z.boolean().optional(),
  empty: z.boolean().optional(),
  is_true: z.boolean().optional(),
});
const stageRuleSchema = z.object({
  priority: z.number().int(),
  conditions: z.array(conditionSchema),
  creator_stage: stageName.nullable(),
  reason_category: z.string().nullable(),
  flag: z.enum(["cancelled", "under_review"]).nullable(),
}) satisfies z.ZodType<MappingRule>;

const candidatesSchema = z.object({
  leads: z.array(leadSchema),
  scanned: z.number().int(),
  last_id: z.number().int().nullable(),
  watermark: z.string().nullable(),
  rules: rulesSchema,
  stage_rules: z.array(stageRuleSchema),
});

export type SyncMode =
  | { since: string }
  | { lead_ids: number[] }
  | { from: string; to: string; after: number };
export interface SyncResult {
  scanned: number;
  leads: number;
  decisions: number;
  unmapped: number;
  flags: number;
  last_id: number | null;
}

export const BATCH = 500;

export async function syncBatch(
  mode: SyncMode,
  source: "sweep" | "backfill" | "override",
): Promise<SyncResult> {
  const db = adminClient();
  const { data, error } = await db.rpc("lead_sync_candidates", { p: { ...mode, limit: BATCH } });
  if (error) throw new Error(error.message);
  const c = candidatesSchema.parse(data);
  const planned = c.leads.map((l) => planLead(l, c.rules, c.stage_rules));
  const payload = {
    source,
    watermark: "since" in mode ? c.watermark : null,
    leads: planned.map((p) => ({ ...p, decisions: p.decisions.map((d) => ({ ...d })) })),
  };
  const applied = await db.rpc("lead_sync_apply", {
    p: JSON.parse(JSON.stringify(payload)) as never,
  });
  if (applied.error) throw new Error(applied.error.message);
  const creators = [
    ...new Set(
      planned.flatMap((p) =>
        p.decisions.filter((d) => d.status === "credited").map((d) => d.creator_id),
      ),
    ),
  ];
  const flags = creators.length ? await evaluateFraud(creators) : 0;
  return {
    scanned: c.scanned,
    leads: planned.length,
    decisions: planned.reduce((n, p) => n + p.decisions.length, 0),
    unmapped: planned.reduce((n, p) => n + p.unmapped, 0),
    flags,
    last_id: c.last_id,
  };
}

const fraudSchema = z.object({
  settings: z.object({
    velocity_leads_per_hour: z.number(),
    same_device_max_leads: z.number(),
    no_witty_reply_hours: z.number(),
    off_hours_start: z.string(),
    off_hours_end: z.string(),
    off_hours_burst: z.number(),
    junk_rate_pct: z.number(),
    min_sample: z.number(),
  }) satisfies z.ZodType<FraudSettings>,
  creators: z.array(
    z.object({
      creator_id: z.string(),
      leads_last_hour: z.number(),
      recent: z.array(iso),
      closed_30d: z.number(),
      junk_30d: z.number(),
      leads: z.array(
        z.object({
          attribution_id: z.string(),
          age_hours: z.number(),
          student_replied: z.boolean().nullable(),
          same_device_leads: z.number(),
        }),
      ),
    }),
  ),
});

/** Computes fraud signals for creators and opens flags (never rejects anything by itself). */
export async function evaluateFraud(creatorIds: string[]): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("fraud_facts", { p_creators: creatorIds });
  if (error) throw new Error(error.message);
  const f = fraudSchema.parse(data);
  const s = f.settings;
  const flags = f.creators.flatMap((c) => [
    ...creatorSignals(
      {
        leads_last_hour: c.leads_last_hour,
        off_hours_leads_24h: c.recent.filter((at) =>
          isOffHours(at, s.off_hours_start, s.off_hours_end),
        ).length,
        closed_30d: c.closed_30d,
        junk_30d: c.junk_30d,
      },
      s,
    ).map((x) => ({
      creator_id: c.creator_id,
      attribution_id: null,
      signal: x.signal,
      detail: x.detail,
    })),
    ...c.leads.flatMap((l) =>
      leadSignals(l, s).map((x) => ({
        creator_id: c.creator_id,
        attribution_id: l.attribution_id,
        signal: x.signal,
        detail: x.detail,
      })),
    ),
  ]);
  if (!flags.length) return 0;
  const r = await db.rpc("fraud_apply", { p: { flags } });
  if (r.error) throw new Error(r.error.message);
  return r.data;
}

/** The every-minute sweep: batches from the watermark until nothing is left or the time is up. */
export async function sweep(deadline: number): Promise<SyncResult[]> {
  const db = adminClient();
  const out: SyncResult[] = [];
  while (Date.now() < deadline) {
    const since = await db.rpc("lead_sync_since");
    if (since.error) throw new Error(since.error.message);
    const r = await syncBatch({ since: since.data }, "sweep");
    out.push(r);
    if (r.scanned < BATCH) break;
  }
  return out;
}
