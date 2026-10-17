// Board columns for the staff deliverables view: statuses grouped by who is working on them. The board shows
// where things stand; moves happen through the actions on each deliverable, so the workflow rules always apply.
import type { DeliverableStatus } from "./workflow";

export const BOARD_COLUMNS = [
  "waiting_brief",
  "creating",
  "in_review",
  "ready",
  "live",
  "done",
] as const;
export type BoardColumn = (typeof BOARD_COLUMNS)[number];

const COLUMN: Record<DeliverableStatus, BoardColumn | null> = {
  not_started: "waiting_brief",
  brief_acknowledged: "creating",
  concept_changes_requested: "creating",
  concept_approved: "creating",
  draft_changes_requested: "creating",
  concept_submitted: "in_review",
  draft_submitted: "in_review",
  draft_approved: "ready",
  scheduled: "ready",
  live: "live",
  live_verified: "live",
  metrics_submitted: "live",
  completed: "done",
  cancelled: null,
};

export function boardColumn(
  s: DeliverableStatus,
  awaitingVerification = false,
): BoardColumn | null {
  if (awaitingVerification && s === "live") return "in_review";
  return COLUMN[s];
}
