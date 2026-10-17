import { describe, expect, it } from "vitest";
import {
  ACTIONS,
  availableActions,
  canRequestChanges,
  DEFAULT_TOGGLES,
  DELIVERABLE_STATUSES,
  enabledStages,
  move,
  overdue,
  pendingStage,
  type Action,
  type DeliverableStatus,
  type StageToggles,
} from "./workflow";

const all: StageToggles = { brief: true, concept: true, draft: true, schedule: true, verify: true, metrics: true };
const none: StageToggles = {
  brief: false,
  concept: false,
  draft: false,
  schedule: false,
  verify: false,
  metrics: false,
};

function run(t: StageToggles, actions: Action[], from: DeliverableStatus = "not_started"): DeliverableStatus {
  let s = from;
  for (const a of actions) {
    const r = move(s, a, t);
    if (!r.ok) throw new Error(`${a} from ${s}: ${r.error}`);
    s = r.to;
  }
  return s;
}

describe("move: the full path", () => {
  it("walks every stage in order", () => {
    const path: [Action, DeliverableStatus][] = [
      ["acknowledge_brief", "brief_acknowledged"],
      ["submit_concept", "concept_submitted"],
      ["request_concept_changes", "concept_changes_requested"],
      ["submit_concept", "concept_submitted"],
      ["approve_concept", "concept_approved"],
      ["submit_draft", "draft_submitted"],
      ["request_draft_changes", "draft_changes_requested"],
      ["submit_draft", "draft_submitted"],
      ["approve_draft", "draft_approved"],
      ["schedule", "scheduled"],
      ["schedule", "scheduled"],
      ["go_live", "live"],
      ["go_live", "live"],
      ["verify_live", "live_verified"],
      ["submit_metrics", "metrics_submitted"],
      ["submit_metrics", "metrics_submitted"],
      ["complete", "completed"],
    ];
    let s: DeliverableStatus = "not_started";
    for (const [a, expected] of path) {
      const r = move(s, a, all);
      expect(r, `${a} from ${s}`).toEqual({ ok: true, to: expected });
      if (r.ok) s = r.to;
    }
  });

  it("with every stage off, goes straight from start to live to completed", () => {
    expect(run(none, ["go_live", "complete"])).toBe("completed");
    expect(move("not_started", "acknowledge_brief", none)).toEqual({ ok: false, error: "stage_off" });
    expect(move("not_started", "submit_concept", none)).toEqual({ ok: false, error: "stage_off" });
    expect(move("live", "verify_live", none)).toEqual({ ok: false, error: "stage_off" });
    expect(move("live", "submit_metrics", none)).toEqual({ ok: false, error: "stage_off" });
  });

  it("skips the concept stage", () => {
    const t = { ...DEFAULT_TOGGLES, concept: false };
    expect(run(t, ["acknowledge_brief", "submit_draft", "approve_draft", "go_live", "verify_live"])).toBe(
      "live_verified",
    );
    expect(move("brief_acknowledged", "submit_concept", t).ok).toBe(false);
  });

  it("skips the draft stage: publishing follows the approved concept", () => {
    const t = { ...DEFAULT_TOGGLES, draft: false };
    expect(run(t, ["acknowledge_brief", "submit_concept", "approve_concept", "go_live"])).toBe("live");
    expect(move("concept_approved", "submit_draft", t)).toEqual({ ok: false, error: "stage_off" });
  });

  it("without a brief, work starts from not started", () => {
    const t = { ...DEFAULT_TOGGLES, brief: false };
    expect(run(t, ["submit_concept"])).toBe("concept_submitted");
    expect(move("not_started", "acknowledge_brief", t)).toEqual({ ok: false, error: "stage_off" });
  });

  it("with the brief on, nothing can be submitted before it is acknowledged", () => {
    expect(move("not_started", "submit_concept", DEFAULT_TOGGLES).ok).toBe(false);
    expect(move("not_started", "go_live", DEFAULT_TOGGLES).ok).toBe(false);
  });

  it("scheduling, when on, comes before going live", () => {
    expect(move("draft_approved", "go_live", all).ok).toBe(false);
    expect(move("draft_approved", "go_live", DEFAULT_TOGGLES).ok).toBe(true);
    expect(move("draft_approved", "schedule", DEFAULT_TOGGLES)).toEqual({ ok: false, error: "stage_off" });
  });

  it("metrics off: completes right after verification; verification off: after live", () => {
    expect(run({ ...DEFAULT_TOGGLES, metrics: false }, ["complete"], "live_verified")).toBe("completed");
    expect(move("live", "complete", { ...DEFAULT_TOGGLES, metrics: false }).ok).toBe(false);
    expect(run({ ...DEFAULT_TOGGLES, verify: false }, ["submit_metrics", "complete"], "live")).toBe("completed");
  });

  it("cancel works from any open status and nothing moves after the end", () => {
    for (const s of DELIVERABLE_STATUSES) {
      const r = move(s, "cancel", all);
      if (s === "completed" || s === "cancelled") expect(r.ok, s).toBe(false);
      else expect(r, s).toEqual({ ok: true, to: "cancelled" });
    }
    for (const a of ACTIONS) {
      expect(move("completed", a, all).ok).toBe(false);
      expect(move("cancelled", a, all).ok).toBe(false);
    }
  });

  it("review actions only apply to submitted work", () => {
    expect(move("concept_approved", "approve_concept", all).ok).toBe(false);
    expect(move("draft_approved", "request_draft_changes", all).ok).toBe(false);
    expect(move("live_verified", "verify_live", all).ok).toBe(false);
  });
});

describe("availableActions", () => {
  it("splits actions by side", () => {
    expect(availableActions("brief_acknowledged", DEFAULT_TOGGLES, "creator")).toEqual(["submit_concept"]);
    expect(availableActions("concept_submitted", DEFAULT_TOGGLES, "eduwit")).toEqual([
      "approve_concept",
      "request_concept_changes",
      "cancel",
    ]);
    expect(availableActions("concept_submitted", DEFAULT_TOGGLES, "creator")).toEqual([]);
    expect(availableActions("not_started", DEFAULT_TOGGLES, "system")).toEqual(["acknowledge_brief"]);
    expect(availableActions("live", DEFAULT_TOGGLES, "creator")).toEqual(["go_live"]);
    expect(availableActions("live", DEFAULT_TOGGLES, "eduwit")).toEqual(["verify_live", "cancel"]);
  });
  it("lists enabled stages", () => {
    expect(enabledStages(DEFAULT_TOGGLES)).toEqual(["brief", "concept", "draft", "verify", "metrics"]);
    expect(enabledStages(none)).toEqual([]);
  });
});

describe("pending stage and overdue", () => {
  const due = {
    concept: "2026-11-01T18:29:59.000Z",
    draft: "2026-11-08T18:29:59.000Z",
    live: "2026-11-15T18:29:59.000Z",
    metrics: "2026-11-22T18:29:59.000Z",
  };
  it("knows what the creator owes next", () => {
    const cases: [DeliverableStatus, string | null][] = [
      ["not_started", null],
      ["brief_acknowledged", "concept"],
      ["concept_submitted", null],
      ["concept_changes_requested", "concept"],
      ["concept_approved", "draft"],
      ["draft_submitted", null],
      ["draft_changes_requested", "draft"],
      ["draft_approved", "live"],
      ["scheduled", "live"],
      ["live", null],
      ["live_verified", "metrics"],
      ["metrics_submitted", null],
      ["completed", null],
      ["cancelled", null],
    ];
    for (const [s, stage] of cases) expect(pendingStage(s, DEFAULT_TOGGLES), s).toBe(stage);
    expect(pendingStage("live", { ...DEFAULT_TOGGLES, verify: false })).toBe("metrics");
    expect(pendingStage("not_started", { ...DEFAULT_TOGGLES, brief: false })).toBe("concept");
    expect(pendingStage("not_started", none)).toBe("live");
    expect(pendingStage("live", none)).toBeNull();
  });
  it("flags overdue from the pending stage's due date", () => {
    expect(overdue("brief_acknowledged", DEFAULT_TOGGLES, due, new Date("2026-11-01T18:00:00Z"))).toBeNull();
    expect(overdue("brief_acknowledged", DEFAULT_TOGGLES, due, new Date("2026-11-02T00:00:00Z"))).toEqual({
      stage: "concept",
      due_at: due.concept,
      days_late: 1,
    });
    expect(overdue("draft_approved", DEFAULT_TOGGLES, due, new Date("2026-11-20T00:00:00Z"))?.days_late).toBe(5);
    // Waiting for review is never overdue for the creator.
    expect(overdue("draft_submitted", DEFAULT_TOGGLES, due, new Date("2027-01-01T00:00:00Z"))).toBeNull();
    // No due date for the stage: not overdue.
    expect(overdue("brief_acknowledged", DEFAULT_TOGGLES, {}, new Date("2027-01-01T00:00:00Z"))).toBeNull();
  });
});

describe("revision limit", () => {
  it("allows rounds up to the limit plus approved extras", () => {
    expect(canRequestChanges(0, 2, 0)).toBe(true);
    expect(canRequestChanges(1, 2, 0)).toBe(true);
    expect(canRequestChanges(2, 2, 0)).toBe(false);
    expect(canRequestChanges(2, 2, 1)).toBe(true);
    expect(canRequestChanges(0, 0, 0)).toBe(false);
  });
});
