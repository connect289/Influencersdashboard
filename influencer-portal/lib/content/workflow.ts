// The deliverable workflow (spec 10.2). Pure: given a deliverable's status, its stage switches and an action, it says
// what happens next. The database applies the same moves (inf.deliverable_next), so this module drives the UI and
// the tests that keep both in step.
//
// Not started → Brief acknowledged → Concept submitted ⇄ Concept changes requested → Concept approved → Draft
// submitted ⇄ Draft changes requested → Draft approved → Scheduled → Live → Live verified → Metrics submitted →
// Completed, plus Cancelled. Stages can be switched off per deliverable; Overdue is computed, never stored.

export const DELIVERABLE_STATUSES = [
  "not_started",
  "brief_acknowledged",
  "concept_submitted",
  "concept_changes_requested",
  "concept_approved",
  "draft_submitted",
  "draft_changes_requested",
  "draft_approved",
  "scheduled",
  "live",
  "live_verified",
  "metrics_submitted",
  "completed",
  "cancelled",
] as const;
export type DeliverableStatus = (typeof DELIVERABLE_STATUSES)[number];

export const STAGES = ["brief", "concept", "draft", "schedule", "verify", "metrics"] as const;
export type Stage = (typeof STAGES)[number];
export type StageToggles = Readonly<Record<Stage, boolean>>;
export const DEFAULT_TOGGLES: StageToggles = {
  brief: true,
  concept: true,
  draft: true,
  schedule: false,
  verify: true,
  metrics: true,
};

export const ACTIONS = [
  "acknowledge_brief",
  "submit_concept",
  "approve_concept",
  "request_concept_changes",
  "submit_draft",
  "approve_draft",
  "request_draft_changes",
  "schedule",
  "go_live",
  "verify_live",
  "submit_metrics",
  "complete",
  "cancel",
] as const;
export type Action = (typeof ACTIONS)[number];
export type Side = "creator" | "eduwit" | "system";

/** Who may take each action: the creator (or their agency with "act on deliverables"), Eduwit staff, the system. */
export const ACTION_SIDE: Readonly<Record<Action, Side>> = {
  acknowledge_brief: "system",
  submit_concept: "creator",
  approve_concept: "eduwit",
  request_concept_changes: "eduwit",
  submit_draft: "creator",
  approve_draft: "eduwit",
  request_draft_changes: "eduwit",
  schedule: "creator",
  go_live: "creator",
  verify_live: "eduwit",
  submit_metrics: "creator",
  complete: "eduwit",
  cancel: "eduwit",
};

const TERMINAL: readonly DeliverableStatus[] = ["completed", "cancelled"];

/** Where work starts once the brief is out of the way. */
function entry(t: StageToggles): DeliverableStatus {
  return t.brief ? "brief_acknowledged" : "not_started";
}

/** The status in which the creator may publish (everything before going live is done). */
function readyToPublish(s: DeliverableStatus, t: StageToggles): boolean {
  if (t.draft) return s === "draft_approved";
  if (t.concept) return s === "concept_approved";
  return s === entry(t);
}

/** The status after which the content is out (live, or verified when verification is on). */
function published(s: DeliverableStatus, t: StageToggles): boolean {
  return t.verify ? s === "live_verified" : s === "live";
}

export type MoveResult = { ok: true; to: DeliverableStatus } | { ok: false; error: "not_allowed" | "stage_off" };

/** The next status for an action, or why it isn't possible. */
export function move(from: DeliverableStatus, action: Action, t: StageToggles): MoveResult {
  const deny = (error: "not_allowed" | "stage_off" = "not_allowed"): MoveResult => ({
    ok: false,
    error,
  });
  const to = (s: DeliverableStatus): MoveResult => ({ ok: true, to: s });
  if (TERMINAL.includes(from)) return deny();
  switch (action) {
    case "acknowledge_brief":
      if (!t.brief) return deny("stage_off");
      return from === "not_started" ? to("brief_acknowledged") : deny();
    case "submit_concept":
      if (!t.concept) return deny("stage_off");
      return from === entry(t) || from === "concept_changes_requested" ? to("concept_submitted") : deny();
    case "approve_concept":
      return t.concept && from === "concept_submitted"
        ? to("concept_approved")
        : deny(t.concept ? "not_allowed" : "stage_off");
    case "request_concept_changes":
      return t.concept && from === "concept_submitted"
        ? to("concept_changes_requested")
        : deny(t.concept ? "not_allowed" : "stage_off");
    case "submit_draft": {
      if (!t.draft) return deny("stage_off");
      const start = t.concept ? from === "concept_approved" : from === entry(t);
      return start || from === "draft_changes_requested" ? to("draft_submitted") : deny();
    }
    case "approve_draft":
      return t.draft && from === "draft_submitted" ? to("draft_approved") : deny(t.draft ? "not_allowed" : "stage_off");
    case "request_draft_changes":
      return t.draft && from === "draft_submitted"
        ? to("draft_changes_requested")
        : deny(t.draft ? "not_allowed" : "stage_off");
    case "schedule":
      if (!t.schedule) return deny("stage_off");
      return readyToPublish(from, t) || from === "scheduled" ? to("scheduled") : deny();
    case "go_live":
      // Going live again (a corrected link) is allowed until the post is verified.
      if (from === "live") return to("live");
      return (t.schedule ? from === "scheduled" : readyToPublish(from, t)) ? to("live") : deny();
    case "verify_live":
      if (!t.verify) return deny("stage_off");
      return from === "live" ? to("live_verified") : deny();
    case "submit_metrics":
      if (!t.metrics) return deny("stage_off");
      return published(from, t) || from === "metrics_submitted" ? to("metrics_submitted") : deny();
    case "complete":
      return (t.metrics ? from === "metrics_submitted" : published(from, t)) ? to("completed") : deny();
    case "cancel":
      return to("cancelled");
  }
}

/** Actions a side can take now (for buttons). */
export function availableActions(from: DeliverableStatus, t: StageToggles, side: Side): Action[] {
  return ACTIONS.filter((a) => ACTION_SIDE[a] === side && move(from, a, t).ok);
}

/** The stages switched on, in order (for progress displays). */
export function enabledStages(t: StageToggles): Stage[] {
  return STAGES.filter((s) => t[s]);
}

export const DUE_STAGES = ["concept", "draft", "live", "metrics"] as const;
export type DueStage = (typeof DUE_STAGES)[number];
export type DueDates = Partial<Record<DueStage, string>>;

/** What the creator owes next, if anything (submitted work awaiting review is Eduwit's turn, never overdue). */
export function pendingStage(s: DeliverableStatus, t: StageToggles): DueStage | null {
  if (TERMINAL.includes(s) || (s === "not_started" && t.brief)) return null;
  if (s === "concept_submitted" || s === "draft_submitted") return null;
  if (t.concept && (s === entry(t) || s === "concept_changes_requested")) return "concept";
  if (t.draft && (s === "draft_changes_requested" || (t.concept ? s === "concept_approved" : s === entry(t))))
    return "draft";
  if (readyToPublish(s, t) || s === "scheduled") return "live";
  if (s === "live" && t.verify) return null; // waiting for Eduwit to verify
  if (t.metrics && published(s, t)) return "metrics";
  return null;
}

export interface Overdue {
  stage: DueStage;
  due_at: string;
  days_late: number;
}

const DAY_MS = 86_400_000;

/** The overdue flag (spec 10.2: computed): the pending stage's due date has passed. */
export function overdue(s: DeliverableStatus, t: StageToggles, due: DueDates, now: Date): Overdue | null {
  const stage = pendingStage(s, t);
  if (!stage) return null;
  const at = due[stage];
  if (!at) return null;
  const late = now.getTime() - Date.parse(at);
  return late > 0 ? { stage, due_at: at, days_late: Math.ceil(late / DAY_MS) } : null;
}

/**
 * Whether a reviewer may ask for another round of changes: `used` rounds so far against the contract's limit plus
 * extra rounds an admin approved (spec 10.2 "revision limit … further revisions need admin approval").
 */
export function canRequestChanges(used: number, limit: number, extraApproved: number): boolean {
  return used < limit + extraApproved;
}

/** The submission kind each creator action records. */
export const SUBMISSION_KIND: Partial<Record<Action, "concept" | "draft" | "final">> = {
  submit_concept: "concept",
  submit_draft: "draft",
};
