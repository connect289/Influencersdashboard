import { z } from "zod";
import { formatDateTime } from "./format";

/** Partner push (spec B7.5, B8.1; Addendum 3 PART 5–6): labels, the credentials form and types shared by the partner and routing screens. */

export const AUTH_TYPES = ["bearer", "header", "basic", "none"] as const;
export const AUTH_LABEL: Record<(typeof AUTH_TYPES)[number], string> = {
  bearer: "Bearer token (Authorization: Bearer …)",
  header: "API key in a header of the partner's choice",
  basic: "HTTP Basic (user:password)",
  none: "No authentication (signed pushes only)",
};

/** push_requests.outcome, plus the allocation outcomes the same screens name (m31i: duplicate_upheld, lost). */
export const PUSH_OUTCOME_LABEL: Record<string, string> = {
  created: "Created",
  duplicate: "Duplicate",
  rejected: "Rejected",
  error: "Error",
  timeout: "No answer",
  failed: "Push failed",
  lost: "Lost",
  duplicate_upheld: "Duplicate upheld: no commission",
};

/** PART 6.1: an allocation the partner marked lost keeps its status for 7 days. */
export const GRACE_OUTCOME_LABEL = "Lost, in grace until";
export const lostGraceText = (until: string | null | undefined): string => (until ? `${GRACE_OUTCOME_LABEL} ${formatDateTime(until)}` : "Lost, in grace");

/**
 * The Result cell of a push. A duplicate answer is only a duplicate with proof (D4: a record id, a created date or the CRM's own
 * duplicate error); without it the allocation was rejected (PART 5.5) and the lead re-routed. claim_proof_ok sits on the allocation,
 * so it is shown only when push_overview carries it on the request row.
 */
export function pushOutcomeText(q: Pick<PushRequest, "outcome" | "claim_proof_ok">): string {
  if (!q.outcome) return "Waiting";
  if (q.outcome === "duplicate" && q.claim_proof_ok === true) return "Duplicate (proof)";
  if (q.outcome === "duplicate" && q.claim_proof_ok === false) return "Rejected: duplicate claim without proof";
  return PUSH_OUTCOME_LABEL[q.outcome] ?? q.outcome;
}

export const EVENT_STATUS_LABEL: Record<string, string> = {
  received: "Received",
  applied: "Applied",
  ignored: "Ignored",
  held_unmapped: "Kept for mapping",
  error: "Error",
};

export const CredentialsSchema = z.object({
  type: z.enum(AUTH_TYPES),
  header: z.string().trim().max(60).regex(/^[A-Za-z0-9-]*$/, "Letters, digits and dashes only"),
  token: z.string().max(4000),
}).superRefine((v, ctx) => {
  if (v.type === "header" && !v.header) ctx.addIssue({ code: "custom", path: ["header"], message: "Give the header name" });
  if (v.type === "basic" && v.token && !v.token.includes(":")) ctx.addIssue({ code: "custom", path: ["token"], message: "Use user:password" });
});

export type PushRequest = {
  id: number; allocation_id: number; reference: string; attempt: number; url: string; sandbox: boolean; status_code: number | null;
  outcome: string | null; error: string | null; sent_at: string; completed_at: string | null;
  /** allocations.claim_proof_ok (m31a0); optional because m31i's push_overview does not add it to the request row yet. */
  claim_proof_ok?: boolean | null;
};
export type PartnerEventRow = { id: number; partner_id: number; event_type: string; reference: string | null; status: string; result: string | null; received_at: string };

// ---------- commission disputes (PART 5.8, PART 6.1 'Late partner activity'; m31i (7), (20), (21)) ----------

export const DISPUTE_KINDS = ["duplicate_after_acceptance", "late_activity_after_lost"] as const;
export type DisputeKind = (typeof DISPUTE_KINDS)[number];
export const isDisputeKind = (k: string): k is DisputeKind => (DISPUTE_KINDS as readonly string[]).includes(k);

export const DISPUTE_KIND_LABEL: Record<DisputeKind, string> = {
  duplicate_after_acceptance: "Duplicate claimed after acceptance",
  late_activity_after_lost: "Activity after the lead moved to B2C",
};
/** What happened, for the list row. */
export const DISPUTE_KIND_HINT: Record<DisputeKind, string> = {
  duplicate_after_acceptance: "The partner said it already had this student within 24 hours of accepting the lead. The lead stays with the partner.",
  late_activity_after_lost: "The partner marked the lead lost, the 7-day grace ended and the lead moved to B2C nurture; the partner then reported activity or an enrolment.",
};
export const disputeKindLabel = (kind: string): string => (isDisputeKind(kind) ? DISPUTE_KIND_LABEL[kind] : kind);

/** One row of push_overview.disputes (m31i (21)): open disputes only, `also` is how many later claims joined this dispute. */
export type Dispute = {
  id: number;
  kind: DisputeKind | string;
  lead_id: number;
  lead_name: string | null;
  reference: string;
  partner_name: string;
  /** Duplicate proof (D4): the partner's record id and created date (existing_created_on parsed; existing_created_at is the raw text). */
  existing_record_id: string | null;
  existing_created_at: string | null;
  existing_created_on: string | null;
  /** The partner event that opened a late-activity dispute (null when an enrolment report opened it). */
  partner_event_id: number | null;
  /** Count of further claims appended to this dispute (commission_disputes.also). */
  also: number;
  created_at: string;
};

/** D4: a duplicate claim carries proof when it names the partner's record or its created date. */
export const disputeProofOk = (d: Pick<Dispute, "existing_record_id" | "existing_created_at" | "existing_created_on">): boolean =>
  Boolean(d.existing_record_id || d.existing_created_on || d.existing_created_at);

/** The uphold / reject dialog and toast, per kind (m31i (20): an upheld duplicate earns no commission; an upheld late activity lets the later enrolment earn). */
export function disputeDecisionCopy(kind: string, uphold: boolean): { title: string; body: string; placeholder: string; toast: string } {
  if (kind === "late_activity_after_lost") {
    return uphold
      ? { title: "Uphold the partner's claim?", body: "The partner's later work on this student counts: the enrolment it reports may earn commission. The lead stays in B2C nurture and keeps its partner bar.",
          placeholder: "e.g. the partner's call log shows contact before the lead was lost", toast: "Claim upheld: the later enrolment may earn commission" }
      : { title: "Reject the partner's claim?", body: "The partner's activity after the grace earns nothing on this lead. The lead stays in B2C nurture.",
          placeholder: "e.g. the partner marked it lost and only reacted after our counsellor's follow-up", toast: "Claim rejected: no commission for the late activity" };
  }
  return uphold
    ? { title: "Uphold the duplicate claim?", body: "No commission on this lead: reported enrolments are cancelled and the lead leaves the partner's conversion figures. It stays with the partner.",
        placeholder: "e.g. partner's record predates ours by 3 weeks", toast: "Claim upheld: no commission on this lead" }
    : { title: "Reject the duplicate claim?", body: "The lead stays with the partner and commission applies as normal.",
        placeholder: "e.g. no proof the student enquired before", toast: "Claim rejected: commission applies as normal" };
}

export type PushOverview = {
  by_status: Record<string, number>;
  retrying: { id: number; reference: string; lead_id: number; partner_id: number; partner_name: string; attempts: number; next_push_at: string | null; last_error: string | null }[];
  requests: PushRequest[];
  events: PartnerEventRow[];
  disputes: Dispute[];
  /** Partner allocations lost in the 7-day grace (m31i). Optional: an older push_overview has none. */
  lost_in_grace?: number;
  duplicate_rate_7d: number | null;
};
export type PartnerConnection = {
  adapter_type: string; api_base_url: string | null; test_endpoint: string | null; auth_type: (typeof AUTH_TYPES)[number] | null; auth_header: string | null;
  has_token: boolean; has_inbound_secret: boolean; events_url_path: string; test_accepted: boolean; push: PushOverview;
};
