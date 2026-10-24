import { describe, expect, it } from "vitest";
import { fixStatesSchema, incidentFixesSchema } from "./schemas.ts";

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
