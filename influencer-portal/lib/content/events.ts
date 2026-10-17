// Content facts → the compensation engine's events (spec 6.3, 10.2). Deliverables, the brief and the contract produce
// the events that fire milestones and penalties. Phase 5 uses them to compute penalty proposals for a person to
// approve (late delivery, missed deliverable, missing disclosure); Phase 7's runner reuses the same mapping to post
// the ledger. Pure.
import {
  computeLedger,
  type DealVersion,
  type EngineContext,
  type PenaltyProposal,
} from "@/lib/compensation/engine";
import type { EngineEvent } from "@/lib/compensation/events";

export interface DeliverableFacts {
  id: string;
  /** The id the deal's compensation rules use for this deliverable (milestone triggers, penalties), if any. */
  config_ref: string | null;
  due_live_at: string | null;
  concept_approved_at: string | null;
  draft_approved_at: string | null;
  live_at: string | null;
  cancelled_at: string | null;
  /** When live verification found the disclosure missing. */
  disclosure_failed_at: string | null;
  /** Latest cumulative views and reach readings with their times. */
  metrics: readonly { at: string; views: number | null; reach: number | null }[];
}

export interface ContentFacts {
  contract_signed_at: string | null;
  brief_acknowledged_at: string | null;
  deliverables: readonly DeliverableFacts[];
}

/** The engine reference for a deliverable: the rule id when the deal names it, else the deliverable's own id. */
export const deliverableRef = (d: Pick<DeliverableFacts, "id" | "config_ref">): string =>
  d.config_ref ?? d.id;

export function contentEvents(f: ContentFacts): EngineEvent[] {
  const out: EngineEvent[] = [];
  if (f.contract_signed_at)
    out.push({ id: "contract_signed", type: "contract_signed", at: f.contract_signed_at });
  if (f.brief_acknowledged_at)
    out.push({ id: "brief_acknowledged", type: "brief_acknowledged", at: f.brief_acknowledged_at });
  for (const d of f.deliverables) {
    const ref = deliverableRef(d);
    const id = (kind: string) => `${d.id}:${kind}`;
    if (d.due_live_at)
      // Known from the start, so it precedes everything else about the deliverable.
      out.push({
        id: id("due"),
        type: "deliverable_due",
        deliverable: ref,
        due_at: d.due_live_at,
        at: "1970-01-01T00:00:00.000Z",
      });
    if (d.concept_approved_at)
      out.push({
        id: id("concept"),
        type: "concept_approved",
        deliverable: ref,
        at: d.concept_approved_at,
      });
    if (d.draft_approved_at)
      out.push({
        id: id("draft"),
        type: "draft_approved",
        deliverable: ref,
        at: d.draft_approved_at,
      });
    if (d.live_at)
      out.push({ id: id("live"), type: "deliverable_live", deliverable: ref, at: d.live_at });
    if (d.cancelled_at)
      out.push({
        id: id("cancelled"),
        type: "deliverable_cancelled",
        deliverable: ref,
        at: d.cancelled_at,
      });
    if (d.disclosure_failed_at)
      out.push({
        id: id("disclosure"),
        type: "disclosure_flag",
        deliverable: ref,
        at: d.disclosure_failed_at,
      });
    for (const [i, m] of d.metrics.entries()) {
      if (m.views !== null)
        out.push({
          id: id(`views${String(i)}`),
          type: "metric",
          deliverable: ref,
          metric: "views",
          value: m.views,
          at: m.at,
        });
      if (m.reach !== null)
        out.push({
          id: id(`reach${String(i)}`),
          type: "metric",
          deliverable: ref,
          metric: "reach",
          value: m.reach,
          at: m.at,
        });
    }
  }
  return out.sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id));
}

/** Penalty proposals for a deal from its content so far (each keyed so re-running never duplicates one). */
export function penaltyProposals(input: {
  deal: { id: string; starts_on: string; ends_on: string | null };
  versions: DealVersion[];
  facts: ContentFacts;
  as_of: string;
  context: EngineContext;
}): PenaltyProposal[] {
  return computeLedger({
    deal: input.deal,
    versions: input.versions,
    events: contentEvents(input.facts),
    as_of: input.as_of,
    context: input.context,
  }).proposals;
}
