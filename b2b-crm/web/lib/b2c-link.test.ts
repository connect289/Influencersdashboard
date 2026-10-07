import { describe, expect, it } from "vitest";
import { describeActivity, describeChanges, groupFields, lagText, linkHealth, type LinkOverview } from "./b2c-link";

const checks = { endpoint: true, secret: true, subscribed: true, ping: true, active: true, key: true, key_used: true, first_delivery: true, first_write: true };
const base: Pick<LinkOverview, "checks" | "settings" | "deliveries" | "endpoint"> = {
  checks, settings: { enabled: true, scope: "held", writable: [] }, deliveries: { by_status: {}, waiting: 0, lag_seconds_avg: 1, lag_seconds_max: 2 },
  endpoint: { id: 1, name: "B2C", url: "https://x", active: true, events: ["b2c.*"], has_secret: true, last_success_at: "2026-10-07T10:00:00Z", last_failure_at: null, last_error: null, subscribed: true },
};

describe("b2c link", () => {
  it("rates the link", () => {
    expect(linkHealth(base).label).toBe("Live");
    expect(linkHealth({ ...base, settings: { ...base.settings, enabled: false } }).label).toBe("Switched off");
    expect(linkHealth({ ...base, checks: { ...checks, active: false } }).label).toBe("Not connected");
    expect(linkHealth({ ...base, deliveries: { ...base.deliveries, by_status: { dead: 1 } } }).tone).toBe("danger");
    expect(linkHealth({ ...base, endpoint: { ...base.endpoint!, last_failure_at: "2026-10-07T11:00:00Z" } }).label).toBe("Failing");
  });
  it("groups fields in order", () => {
    const g = groupFields([
      { field: "name", column: "student_name", group: "student", kind: "text", write: "b2c", max: 120 },
      { field: "stage", column: "stage", group: "pipeline", kind: "stage", write: "b2c", max: null },
      { field: "email", column: "email_id", group: "student", kind: "email", write: "b2c", max: null },
    ]);
    expect(g.map((x) => [x.group, x.fields.length])).toEqual([["student", 2], ["pipeline", 1]]);
  });
  it("describes an activity", () => {
    expect(describeActivity({ kind: "call", outcome: "connected", note: "Wants the weekend batch" })).toBe("call · connected · Wants the weekend batch");
    expect(describeActivity({ kind: "note" })).toBe("note");
  });
  it("formats lag and changes", () => {
    expect(lagText(2.345)).toBe("2.3 s");
    expect(lagText(125)).toBe("2 min");
    expect(lagText(null)).toBe("—");
    expect(describeChanges({ stage: { from: "nurture", to: "assigned" }, owner_user_id: { from: null, to: null }, a: 1, b: 2, c: 3 }))
      .toBe("stage → assigned, owner_user_id → cleared, a, b +1");
  });
});
