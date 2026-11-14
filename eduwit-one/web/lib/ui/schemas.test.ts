import { describe, expect, it } from "vitest";
import { appErrorsSchema, fixStatesSchema, incidentFixesSchema } from "./schemas.ts";

describe("fixStatesSchema (one.ui_fix_states, 0020)", () => {
  it("reads each fix's proof state and leaves runs without an incident out of awaiting_verdict", () => {
    const parsed = fixStatesSchema.parse([
      {
        fix_id: "FIX-INBOX-RETRY",
        proven: false,
        proven_at: null,
        paused: true,
        paused_at: "2026-10-24T05:00:00Z",
        paused_reason: "two runs did not hold within 7 days",
        did_not_hold_7d: 2,
        awaiting_verdict: [12, null, 13],
      },
      {
        fix_id: "FIX-N8N-RETRY",
        proven: true,
        proven_at: "2026-10-20T05:00:00Z",
        paused: false,
        paused_at: null,
        paused_reason: null,
        did_not_hold_7d: 0,
        awaiting_verdict: [],
        later_column: "passes through",
      },
    ]);
    expect(parsed[0]).toMatchObject({ fix_id: "FIX-INBOX-RETRY", paused: true, awaiting_verdict: [12, 13] });
    expect(parsed[1]).toMatchObject({ proven: true, awaiting_verdict: [] });
    expect(fixStatesSchema.parse([])).toEqual([]);
    expect(fixStatesSchema.safeParse([{ fix_id: "FIX-X" }]).success).toBe(false);
    expect(fixStatesSchema.safeParse([{ fix_id: "FIX-X", proven: "yes" }]).success).toBe(false);
  });
});

describe("incidentFixesSchema (one.ui_incident's fixes, 0020)", () => {
  it("reads the fixes tried on the incident's check, and is empty when the answer has none", () => {
    expect(incidentFixesSchema.parse(undefined)).toEqual([]);
    expect(
      incidentFixesSchema.parse([
        { id: "FIX-INBOX-RETRY", mode: "act", title: "Retry the inbox", enabled: true, paused: true, stopped: false },
        { id: "FIX-N8N-RETRY", mode: "app", title: "Retry n8n", enabled: false },
      ]),
    ).toEqual([
      { id: "FIX-INBOX-RETRY", mode: "act", title: "Retry the inbox", enabled: true, paused: true, stopped: false },
      { id: "FIX-N8N-RETRY", mode: "app", title: "Retry n8n", enabled: false, paused: false, stopped: false },
    ]);
    expect(incidentFixesSchema.safeParse([{ id: "FIX-X", mode: "magic", title: "x", enabled: true }]).success).toBe(
      false,
    );
  });
});

describe("appErrorsSchema (one.ui_app_errors, 0041)", () => {
  it("reads an app's counts, with and without samples, and refuses an answer without them", () => {
    const empty = { app: "witty", hours: 24, total: 0, pairs: 0, last_seen: null, last_15m: 0, limit_15m: 20, top: [] };
    expect(appErrorsSchema.parse(empty).top).toEqual([]);
    const some = appErrorsSchema.parse({
      ...empty,
      app: "b2b",
      total: 7,
      pairs: 2,
      last_seen: "2026-11-13T10:00:00Z",
      last_15m: 3,
      top: [
        {
          route: "/leads/[id]",
          error: "TypeError",
          n: 5,
          last_seen: "2026-11-13T10:00:00Z",
          message: "lead [phone] has no owner",
          digest: "1234567",
          kind: "render",
        },
        { route: "(overflow)", error: "(overflow)", n: 2, last_seen: null, message: null, digest: null, kind: null },
      ],
    });
    expect(some.top.map((t) => t.n)).toEqual([5, 2]);
    expect(appErrorsSchema.safeParse({ ...empty, top: undefined }).success).toBe(false);
    expect(appErrorsSchema.safeParse({ ...empty, total: "7" }).success).toBe(false);
  });
});
