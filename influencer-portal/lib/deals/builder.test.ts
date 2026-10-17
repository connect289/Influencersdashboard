import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig, TRIGGER_TYPES } from "@/lib/compensation/schema";
import {
  allIds,
  builderIssues,
  defaultMilestones,
  defaultTrigger,
  newBonus,
  newFee,
  newFixed,
  newFloor,
  newMilestone,
  newNonCash,
  newPenalty,
  newRule,
  nextId,
  PENALTY_TYPES,
} from "./builder";

const empty = compConfig.parse({ schema_version: 1 });

describe("builder helpers", () => {
  it("nextId takes the first free number", () => {
    expect(nextId("fee", new Set())).toBe("fee1");
    expect(nextId("fee", new Set(["fee1", "fee3"]))).toBe("fee2");
  });

  it("collects every id including milestones", () => {
    expect([...allIds(SYSTEM_PRESETS.fixed_plus_commission.config)].sort()).toEqual([
      "commission",
      "fee",
      "fee.live",
      "fee.signing",
    ]);
  });

  it("factories produce a valid config together", () => {
    let c = empty;
    c = { ...c, fixed: [newFixed(c, "Content fee", "When live")] };
    c = { ...c, commission: [newRule(c, "Per enrolment")] };
    c = { ...c, floors: [newFloor(c, "Minimum")] };
    c = { ...c, bonuses: [newBonus(c, "Five enrolments")] };
    c = {
      ...c,
      penalties: PENALTY_TYPES.reduce<typeof c.penalties>(
        (acc, t) => [...acc, newPenalty({ ...c, penalties: acc }, t, t)],
        [],
      ),
    };
    c = { ...c, fees: [newFee(c, "Usage")] };
    c = { ...c, non_cash: [newNonCash(c, "Course seat")] };
    expect(builderIssues(c)).toEqual([]);
    expect(new Set(allIds(c)).size).toBe(allIds(c).size);
  });

  it("default triggers are valid for every type", () => {
    for (const t of TRIGGER_TYPES) {
      const c = {
        ...empty,
        fixed: [
          {
            ...newFixed(empty, "F", "M"),
            milestones: defaultMilestones("M").map((m) => ({ ...m, trigger: defaultTrigger(t) })),
          },
        ],
      };
      expect(builderIssues(c), t).toEqual([]);
    }
  });

  it("a new milestone follows the component's share kind and makes the total wrong until edited", () => {
    const f = newFixed(empty, "F", "M");
    const m = newMilestone(f, "Second");
    expect(m.share).toEqual({ type: "pct", pct: 0 });
    expect(m.id).toBe("m2");
    const issues = builderIssues({
      ...empty,
      fixed: [
        {
          ...f,
          milestones: [
            ...f.milestones.map((x) => ({ ...x, share: { type: "pct" as const, pct: 60 } })),
            m,
          ],
        },
      ],
    });
    expect(issues).toEqual([
      {
        section: "fixed",
        code: "milestones_not_100",
        detail: undefined,
        path: ["fixed", 0, "milestones"],
      },
    ]);
  });

  it("reports field problems with their path and known codes with their detail", () => {
    const f = newFixed(empty, "", "M");
    const issues = builderIssues({
      ...empty,
      fixed: [f],
      recoupment: { mode: "full", fixed: ["x"] },
    });
    expect(issues.map((i) => [i.section, i.code, i.detail])).toEqual(
      expect.arrayContaining([
        ["fixed", null, undefined],
        ["recoupment", "unknown_fixed", "x"],
      ]),
    );
  });
});
