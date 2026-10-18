// A deal's facts → the compensation engine's events (spec 6.3). Content events come from Phase 5 (contract, brief,
// deliverables, metrics); this adds the deal's credited leads and their stages, enrolments of those leads, Eduwit's
// commission receipts, manual releases and breaches recorded by staff, and the campaign and deal closing. The runner
// gathers the facts read-only (inf.ledger_facts) and replays them with the engine. Pure.
import type { EngineEvent } from "@/lib/compensation/events";
import { contentEvents, deliverableRef, type ContentFacts } from "@/lib/content/events";

export interface LeadFacts {
  /** Attribution id (stable per lead and creator). */
  id: string;
  /** When the lead was created in the CRM. */
  at: string;
  link_id: string | null;
  /** The deliverable the lead came through: its engine reference (config_ref or id). */
  deliverable_ref: string | null;
  programme_id: number | null;
  university_id: number | null;
  level: string | null;
  /** First time the creator-facing stage reached qualified, applied, or a rejection (junk, duplicate, not attributed). */
  qualified_at: string | null;
  applied_at: string | null;
  rejected_at: string | null;
  junk: boolean;
}

export interface EnrollmentFacts {
  /** `b2b:<id>` or `b2c:<id>` (INTEGRATION_CONTRACTS §3). */
  ref: string;
  /** Attribution id of the credited lead. */
  lead_id: string;
  at: string;
  programme_id: number | null;
  university_id: number | null;
  level: string | null;
  fee_paise: number | null;
  /** Eduwit's expected commission, GST-inclusive. */
  expected_commission_gross_paise: number | null;
  cancelled_at: string | null;
}

export interface ReceiptFacts {
  enrollment_ref: string;
  /** Effective cumulative amount received (GST-inclusive). */
  received_paise: number;
  received_on: string;
  /** Received in full (final receipt). */
  full: boolean;
}

export interface ManualEvent {
  id: string;
  kind: "manual_release" | "breach";
  /** For releases: "<component id>.<milestone id>". */
  ref: string | null;
  at: string;
}

export interface DealFacts extends ContentFacts {
  leads: readonly LeadFacts[];
  enrollments: readonly EnrollmentFacts[];
  receipts: readonly ReceiptFacts[];
  manual: readonly ManualEvent[];
  campaign_ended_at: string | null;
  deal_completed_at: string | null;
}

const opt = <K extends string, V>(key: K, v: V | null | undefined): Partial<Record<K, V>> =>
  v === null || v === undefined ? {} : ({ [key]: v } as Record<K, V>);

/** Every engine event for a deal, ordered by time (ties by id, so a replay is deterministic). */
export function dealEvents(f: DealFacts): EngineEvent[] {
  const out: EngineEvent[] = [...contentEvents(f)];
  for (const l of f.leads) {
    out.push({
      id: `lead:${l.id}`,
      type: "lead",
      at: l.at,
      lead: l.id,
      junk: l.junk,
      duplicate: false,
      ...opt("link", l.link_id),
      ...opt("deliverable", l.deliverable_ref),
      ...opt("programme_id", l.programme_id),
      ...opt("university_id", l.university_id),
      ...opt("level", l.level),
    });
    if (l.qualified_at)
      out.push({ id: `lead:${l.id}:qualified`, type: "lead_qualified", at: l.qualified_at, lead: l.id });
    if (l.applied_at) out.push({ id: `lead:${l.id}:applied`, type: "lead_applied", at: l.applied_at, lead: l.id });
    if (l.rejected_at) out.push({ id: `lead:${l.id}:rejected`, type: "lead_rejected", at: l.rejected_at, lead: l.id });
  }
  const leads = new Map(f.leads.map((l) => [l.id, l]));
  for (const e of f.enrollments) {
    const lead = leads.get(e.lead_id);
    // Only enrolments of this deal's credited leads count.
    if (!lead) continue;
    out.push({
      id: `enrolment:${e.ref}`,
      type: "enrolled",
      at: e.at,
      lead: e.lead_id,
      enrollment: e.ref,
      ...opt("programme_id", e.programme_id ?? lead.programme_id),
      ...opt("university_id", e.university_id ?? lead.university_id),
      ...opt("level", e.level ?? lead.level),
      ...opt("link", lead.link_id),
      ...opt("deliverable", lead.deliverable_ref),
      ...opt("fee_paise", e.fee_paise),
      ...opt("expected_commission_gross_paise", e.expected_commission_gross_paise),
    });
    if (e.cancelled_at)
      out.push({
        id: `enrolment:${e.ref}:cancelled`,
        type: "enrollment_cancelled",
        at: e.cancelled_at,
        enrollment: e.ref,
      });
  }
  const enrolled = new Map(f.enrollments.filter((e) => leads.has(e.lead_id)).map((e) => [e.ref, e]));
  for (const r of f.receipts) {
    const e = enrolled.get(r.enrollment_ref);
    if (!e || r.received_paise <= 0) continue;
    // A receipt cannot precede its enrolment in the replay.
    const at = r.received_on > e.at ? r.received_on : e.at;
    out.push({
      id: `receipt:${r.enrollment_ref}`,
      type: "commission_received",
      at,
      enrollment: r.enrollment_ref,
      gross_paise: r.received_paise,
      full: r.full,
    });
  }
  for (const m of f.manual) {
    if (m.kind === "manual_release" && m.ref)
      out.push({ id: `manual:${m.id}`, type: "manual_release", at: m.at, milestone: m.ref });
    else if (m.kind === "breach") out.push({ id: `manual:${m.id}`, type: "breach", at: m.at });
  }
  if (f.campaign_ended_at) out.push({ id: "campaign_ended", type: "campaign_ended", at: f.campaign_ended_at });
  if (f.deal_completed_at) out.push({ id: "deal_completed", type: "deal_completed", at: f.deal_completed_at });
  return out.sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id));
}

export { deliverableRef };
