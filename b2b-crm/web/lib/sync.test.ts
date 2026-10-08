import { describe, expect, it } from "vitest";
import { formatLag, formatWorkingMinutes, healthState, itemDetail, onTimeRate, parseExportText, type SyncHealth } from "./sync";

const base: SyncHealth = {
  last_event_at: null, events_24h: 0, events_7d: 0, lag_p50_s: null, lag_p95_s: null, errors_7d: 0, held: 0, dead_letters: 0,
  bad_signatures_7d: 0, pushes_7d: 0, push_failures_7d: 0, push_backlog: 0, last_push_at: null, stale_leads: 0, open_items: 0, daily: [],
};
const NOW = Date.parse("2026-10-07T10:00:00Z");

describe("formatting", () => {
  it("formats lag", () => {
    expect(formatLag(null)).toBe("–");
    expect(formatLag(42)).toBe("42 s");
    expect(formatLag(600)).toBe("10 min");
    expect(formatLag(3 * 3600)).toBe("3 h");
    expect(formatLag(12600)).toBe("3.5 h");
  });
  it("formats working minutes", () => {
    expect(formatWorkingMinutes(45)).toBe("45 min");
    expect(formatWorkingMinutes(80)).toBe("1 h 20 min");
    expect(formatWorkingMinutes(120)).toBe("2 h");
  });
  it("computes the on-time rate of decided clocks", () => {
    expect(onTimeRate({ met: 0, met_late: 0, breached: 0 })).toBeNull();
    expect(onTimeRate({ met: 3, met_late: 1, breached: 0 })).toBe(0.75);
  });
});

describe("health", () => {
  it("is neutral before any traffic", () => {
    expect(healthState(base, NOW)).toMatchObject({ tone: "neutral", label: "No traffic yet" });
  });
  it("is healthy with steady events", () => {
    expect(healthState({ ...base, events_7d: 40, pushes_7d: 20, last_event_at: "2026-10-07T09:00:00Z", last_push_at: "2026-10-07T08:00:00Z" }, NOW).tone).toBe("success");
  });
  it("flags failures, held events and silence", () => {
    const h = healthState({ ...base, events_7d: 20, errors_7d: 3, dead_letters: 2, pushes_7d: 5, last_push_at: "2026-10-06T08:00:00Z", last_event_at: "2026-10-01T08:00:00Z" }, NOW);
    expect(h.tone).toBe("danger");
    expect(h.reasons).toEqual(expect.arrayContaining(["2 events failed or held", "15% of events failed this week", "No event from the partner for over 2 days"]));
  });
  it("warns when pushed leads get no event at all", () => {
    expect(healthState({ ...base, pushes_7d: 3, last_push_at: "2026-10-05T08:00:00Z" }, NOW).reasons).toContain("Leads pushed but no event received yet");
  });
});

describe("partner export", () => {
  it("reads CSV with aliased headers and quoted cells", () => {
    const r = parseExportText('Lead ID,Status,Sub Status,Owner\n"LS-1","Attempted","RNR, twice",Priya\nLS-2,Admission,,Ravi\n,,,');
    expect(r).toEqual({ ok: true, ignored: ["owner"], rows: [
      { record_id: "LS-1", stage: "Attempted", sub_stage: "RNR, twice" },
      { record_id: "LS-2", stage: "Admission" },
    ] });
  });
  it("reads semicolon and tab separated files", () => {
    expect(parseExportText("reference;stage\nEDW-5;Open")).toMatchObject({ ok: true, rows: [{ reference: "EDW-5", stage: "Open" }] });
    expect(parseExportText("reference\tstage\nEDW-6\tOpen")).toMatchObject({ ok: true, rows: [{ reference: "EDW-6", stage: "Open" }] });
  });
  it("reads JSON rows", () => {
    expect(parseExportText('[{"Reference":"EDW-1","Lead Stage":"Won"},{"x":1}]')).toMatchObject({ ok: true, rows: [{ reference: "EDW-1", stage: "Won" }] });
  });
  it("refuses files without an identifying column", () => {
    expect(parseExportText("name,stage\nA,B")).toEqual({ ok: false, error: "The first row must name a reference or record_id column." });
    expect(parseExportText("")).toMatchObject({ ok: false });
  });
});

describe("items", () => {
  it("describes a stage mismatch", () => {
    expect(itemDetail({ kind: "status_mismatch", detail: { export_stage: "Attempted", export_maps_to: "contacted", partner_stage: "New" } }))
      .toBe("Export: Attempted (maps to contacted) · last reported: New");
  });
});
