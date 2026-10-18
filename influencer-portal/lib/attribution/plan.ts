// One lead through the rules: the attribution decisions and, for each, the creator-facing stage. Pure; the sweep,
// re-runs and backfills call it with the facts inf.lead_sync_candidates() returns.
import {
  decide,
  type Decision,
  type EvidenceSource,
  type Existing,
  type LeadFacts,
  type Model,
  type Reason,
  type Rules,
  type TouchKind,
} from "./rules";
import { mapStage, type CreatorStage, type MappingRule, type StageInputs } from "./stages";

export interface ExistingRow extends Existing {
  stage: CreatorStage | null;
  reason: string | null;
  link_id: string | null;
  code: string;
  deal_id: string | null;
  deliverable_id: string | null;
  campaign_id: string | null;
  touch: TouchKind;
  attribution_reason: Reason | null;
  touch_at: string;
  evidence_source: EvidenceSource | "manual";
}

export interface CandidateLead extends LeadFacts {
  id: number;
  is_test: boolean;
  existing: readonly ExistingRow[];
  stage: Omit<StageInputs, "attribution_status">;
  stage_changed_at: string | null;
}

export interface PlannedDecision extends Omit<Decision, "link_id" | "evidence_source"> {
  link_id: string | null;
  evidence_source: EvidenceSource | "manual";
  stage: { stage: CreatorStage; reason: string | null; flags: string[] };
}

export interface PlannedLead {
  id: number;
  created_at: string;
  is_test: boolean;
  occurred_at: string;
  decisions: PlannedDecision[];
  /** Decisions whose stage no rule matched (staff are alerted; the last known stage is kept). */
  unmapped: number;
}

/**
 * The model for a lead: the override of the campaign behind its earliest touch (spec 9.2 "optional overrides per
 * campaign"), otherwise the global one.
 */
export function modelFor(
  lead: Pick<LeadFacts, "touches">,
  global: Model,
  campaignModels: Readonly<Record<string, Model>>,
): Model {
  const first = [...lead.touches].sort((a, b) => a.at.localeCompare(b.at))[0];
  return (first?.campaign_id ? campaignModels[first.campaign_id] : undefined) ?? global;
}

export function planLead(
  lead: CandidateLead,
  rules: Rules,
  stageRules: readonly MappingRule[],
  campaignModels: Readonly<Record<string, Model>> = {},
): PlannedLead {
  const model = modelFor(lead, rules.model, campaignModels);
  const fresh: Omit<PlannedDecision, "stage">[] = decide(lead, { ...rules, model }, lead.existing);
  // Rows with no touch in the current evidence (a manual credit, or evidence that went away) are carried forward as
  // they are, so their stage still follows the CRM.
  const covered = new Set(fresh.map((d) => d.creator_id));
  const carried = lead.existing
    .filter((e) => !covered.has(e.creator_id))
    .map((e): Omit<PlannedDecision, "stage"> => ({
      creator_id: e.creator_id,
      link_id: e.link_id,
      code: e.code,
      deal_id: e.deal_id,
      deliverable_id: e.deliverable_id,
      campaign_id: e.campaign_id,
      touch: e.touch,
      status: e.status,
      reason: e.attribution_reason,
      touch_at: e.touch_at,
      evidence_source: e.evidence_source,
    }));
  let unmapped = 0;
  const decisions = [...fresh, ...carried].map((d): PlannedDecision => {
    const prev = lead.existing.find((e) => e.creator_id === d.creator_id);
    const r = mapStage(
      { ...lead.stage, attribution_status: d.status },
      stageRules,
      prev?.stage ? { stage: prev.stage, reason: prev.reason } : null,
    );
    if (r.unmapped) unmapped++;
    return {
      ...d,
      stage: {
        stage: r.stage,
        reason: r.reason,
        flags: r.unmapped ? [...r.flags, "unmapped"] : [...r.flags],
      },
    };
  });
  return {
    id: lead.id,
    created_at: lead.created_at,
    is_test: lead.is_test,
    occurred_at: lead.stage_changed_at ?? lead.created_at,
    decisions,
    unmapped,
  };
}
