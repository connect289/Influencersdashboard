// One colour per status family, reused everywhere (spec 17). Components look statuses up here.
export const STATUS_FAMILIES = [
  "neutral",
  "progress",
  "attention",
  "success",
  "problem",
  "closed",
] as const;
export type StatusFamily = (typeof STATUS_FAMILIES)[number];

const FAMILY_OF: Record<string, StatusFamily> = {
  // neutral
  draft: "neutral",
  not_started: "neutral",
  new: "neutral",
  prospect: "neutral",
  queued: "neutral",
  pending: "attention",
  // in progress
  sent: "progress",
  submitted: "progress",
  in_negotiation: "progress",
  negotiating: "progress",
  qualifying: "progress",
  qualified: "progress",
  allocated: "progress",
  counselling: "progress",
  applied: "progress",
  accrued: "progress",
  invited: "progress",
  onboarding: "progress",
  contacted: "progress",
  running: "progress",
  processing: "progress",
  proposed: "progress",
  brief_acknowledged: "progress",
  concept_submitted: "progress",
  concept_approved: "progress",
  draft_submitted: "progress",
  draft_approved: "progress",
  scheduled: "progress",
  live: "progress",
  metrics_submitted: "progress",
  // waiting / attention
  changes_requested: "attention",
  concept_changes_requested: "attention",
  draft_changes_requested: "attention",
  on_hold: "attention",
  payable: "attention",
  ready_to_sign: "attention",
  under_review: "attention",
  shortlisted: "attention",
  countered: "attention",
  paused: "attention",
  dormant: "attention",
  fraud_suspected: "attention",
  // success
  approved: "success",
  signed: "success",
  signed_by_creator: "success",
  active: "success",
  live_verified: "success",
  enrolled: "success",
  confirmed: "success",
  paid: "success",
  accepted: "success",
  agreed: "success",
  verified: "success",
  credited: "success",
  manually_credited: "success",
  done: "success",
  completed: "success",
  ok: "success",
  // problem
  rejected: "problem",
  declined: "problem",
  overdue: "problem",
  failed: "problem",
  lost: "problem",
  clawed_back: "problem",
  blocked: "problem",
  dead: "problem",
  suspended: "problem",
  junk: "problem",
  terminated: "problem",
  manually_rejected: "problem",
  locked: "problem",
  refused: "problem",
  // closed
  archived: "closed",
  expired: "closed",
  void: "closed",
  superseded: "closed",
  withdrawn: "closed",
  cancelled: "closed",
  duplicate: "closed",
  not_attributed: "closed",
  outside_window: "closed",
  self_referral: "closed",
  reversed: "closed",
};

export function statusFamily(status: string): StatusFamily {
  return FAMILY_OF[status] ?? "neutral";
}

export const FAMILY_CLASSES: Record<StatusFamily, string> = {
  neutral: "bg-surface-2 text-muted",
  progress: "bg-primary-soft text-primary",
  attention: "bg-accent-soft text-accent-ink",
  success: "bg-success-soft text-success",
  problem: "bg-danger-soft text-danger",
  closed: "bg-transparent text-muted ring-1 ring-inset ring-line-strong",
};

/** "in_negotiation" → "In negotiation". UI text should come from messages; this is the fallback. */
export function humanize(value: string): string {
  const s = value.replace(/_/g, " ");
  return s.charAt(0).toUpperCase() + s.slice(1);
}
