import { describe, expect, it } from "vitest";
import { baseKey, diffLedger, type PostedLine } from "./diff";
import type { LedgerLine } from "./engine";

const line = (key: string, amount: number, confirmed = amount): LedgerLine => ({
  key,
  type: "commission",
  direction: "credit",
  amount_paise: amount,
  confirmed_paise: confirmed,
  rule_id: "r",
  version_id: "v1",
  subject: "s",
  at: "2026-11-01T04:30:00.000Z",
  period: "2026-11",
  due_on: "2026-11-01",
  note: "",
});
const posted = (key: string, amount: number, confirmed = amount, reversed = false): PostedLine => ({
  key,
  type: "commission",
  direction: "credit",
  amount_paise: amount,
  confirmed_paise: confirmed,
  reversed,
});

describe("diffLedger", () => {
  it("posts everything when nothing is posted yet", () => {
    const d = diffLedger([line("a", 100), line("b", 200)], []);
    expect(d.create.map((l) => l.key)).toEqual(["a", "b"]);
    expect(d).toMatchObject({ confirm: [], reverse: [], unchanged: 0 });
  });

  it("leaves identical lines alone", () => {
    expect(diffLedger([line("a", 100)], [posted("a", 100)])).toEqual({
      create: [],
      confirm: [],
      reverse: [],
      unchanged: 1,
    });
  });

  it("raises the confirmed amount without re-posting", () => {
    expect(diffLedger([line("a", 100, 100)], [posted("a", 100, 0)]).confirm).toEqual([
      { key: "a", confirmed_paise: 100 },
    ]);
  });

  it("reverses and re-posts a changed amount, or confirmation going backwards", () => {
    const d = diffLedger([line("a", 150), line("b", 100, 0)], [posted("a", 100), posted("b", 100, 100)]);
    expect(d.reverse).toEqual([
      { key: "a", reason: "changed" },
      { key: "b", reason: "changed" },
    ]);
    expect(d.create.map((l) => [l.key, l.amount_paise])).toEqual([
      ["a~2", 150],
      ["b~2", 100],
    ]);
  });

  it("reverses lines the engine no longer wants", () => {
    expect(diffLedger([], [posted("a", 100), posted("b", 5, 5, true)]).reverse).toEqual([
      { key: "a", reason: "obsolete" },
    ]);
  });

  it("matches re-posted lines by their base key and keeps numbering", () => {
    const history = [posted("a", 100, 100, true), posted("a~2", 150)];
    expect(diffLedger([line("a", 150)], history).unchanged).toBe(1);
    const d = diffLedger([line("a", 175)], history);
    expect(d.reverse).toEqual([{ key: "a~2", reason: "changed" }]);
    expect(d.create.map((l) => l.key)).toEqual(["a~3"]);
    expect(diffLedger([line("a", 175)], [posted("a", 100, 100, true)]).create.map((l) => l.key)).toEqual(["a~2"]);
  });

  it("baseKey strips the re-post suffix", () => {
    expect(baseKey("v1:r:s:accrue~3")).toBe("v1:r:s:accrue");
    expect(baseKey("v1:r:s:accrue")).toBe("v1:r:s:accrue");
  });
});
