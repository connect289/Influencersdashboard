import { describe, expect, it } from "vitest";
import { delta, flowByDestination, slaShare } from "./overview";

describe("command center helpers", () => {
  it("compares with the same hours yesterday", () => {
    expect(delta(0, 0)).toBeNull();
    expect(delta(5, 0)).toEqual({ text: "+5 vs 0", tone: "up" });
    expect(delta(6, 4)).toEqual({ text: "+50% vs yesterday", tone: "up" });
    expect(delta(2, 4)).toEqual({ text: "-50% vs yesterday", tone: "down" });
    expect(delta(4, 4)?.tone).toBe("flat");
  });
  it("gives SLA compliance only once a deadline has passed", () => {
    expect(slaShare(0, 0)).toBeNull();
    expect(slaShare(3, 4)).toBe(0.75);
  });
  it("groups the flow by destination, largest first", () => {
    const rows = flowByDestination([
      { source: "witty", destination: "Acme", n: 3 },
      { source: "meta", destination: "B2C sales", n: 5 },
      { source: "meta", destination: "Acme", n: 4 },
    ]);
    expect(rows.map((r) => [r.destination, r.n])).toEqual([["Acme", 7], ["B2C sales", 5]]);
    expect(rows[0]?.sources.map((s) => s.source)).toEqual(["meta", "witty"]);
  });
});
