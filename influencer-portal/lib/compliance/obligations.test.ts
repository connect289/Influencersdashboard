import { describe, expect, it } from "vitest";
import { obligationsFor, summarise, type DeliverableFacts } from "./obligations";

const NOW = "2026-10-20T12:00:00.000Z";
const d: DeliverableFacts = {
  id: "d1",
  title: "Reel 1",
  deal_id: "deal",
  status: "live_verified",
  due_live: "2026-10-10T18:30:00.000Z",
  live_at: "2026-10-09T10:00:00.000Z",
  cancelled_at: null,
  disclosure_failed_at: null,
  disclosure_ok: true,
  metrics_submitted_at: "2026-10-15T10:00:00.000Z",
  metrics_due_days: 7,
  brief_acknowledged_at: "2026-10-01T10:00:00.000Z",
  first_submission_at: "2026-10-03T10:00:00.000Z",
};
const status = (x: DeliverableFacts) => Object.fromEntries(obligationsFor(x, NOW).map((o) => [o.kind, o.status]));

describe("contract obligations", () => {
  it("all met", () => {
    expect(status(d)).toEqual({
      live_on_time: "met",
      disclosure: "met",
      metrics_reported: "met",
      brief_acknowledged: "met",
    });
  });

  it("late, missing disclosure, late metrics, submitted before acknowledging", () => {
    expect(
      status({
        ...d,
        live_at: "2026-10-12T10:00:00.000Z",
        disclosure_failed_at: "2026-10-12T12:00:00.000Z",
        disclosure_ok: false,
        metrics_submitted_at: "2026-10-20T10:00:00.000Z",
        brief_acknowledged_at: "2026-10-04T10:00:00.000Z",
      }),
    ).toEqual({
      live_on_time: "missed",
      disclosure: "missed",
      metrics_reported: "missed",
      brief_acknowledged: "missed",
    });
  });

  it("open until the date passes, missed after", () => {
    const pending = {
      ...d,
      live_at: null,
      disclosure_ok: null,
      metrics_submitted_at: null,
      due_live: "2026-10-25T18:30:00.000Z",
    };
    expect(status(pending)).toEqual({ live_on_time: "open", brief_acknowledged: "met" });
    expect(status({ ...pending, due_live: "2026-10-18T18:30:00.000Z" }).live_on_time).toBe("missed");
    expect(status({ ...d, metrics_submitted_at: null, live_at: "2026-10-18T10:00:00.000Z" }).metrics_reported).toBe(
      "open",
    );
    expect(status({ ...d, disclosure_ok: null }).disclosure).toBe("open");
  });

  it("cancelled deliverables are waived", () => {
    expect(new Set(Object.values(status({ ...d, cancelled_at: "2026-10-05T00:00:00.000Z", live_at: null })))).toEqual(
      new Set(["waived"]),
    );
  });

  it("summarises met against missed", () => {
    const all = [
      ...obligationsFor(d, NOW),
      ...obligationsFor(
        { ...d, id: "d2", live_at: "2026-10-12T10:00:00.000Z", metrics_submitted_at: null, metrics_due_days: null },
        NOW,
      ),
    ];
    const s = summarise(all);
    expect(s).toMatchObject({ met: 6, missed: 1, open: 0, waived: 0 });
    expect(s.rate).toBeCloseTo(6 / 7);
    expect(s.byKind.live_on_time).toEqual({ met: 1, missed: 1 });
    expect(summarise([]).rate).toBeNull();
  });
});
