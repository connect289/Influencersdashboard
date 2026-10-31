import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
let daily: Record<string, unknown> = { ok: true };
const rpc = vi.fn(async (fn: string): Promise<unknown> => {
  if (fn === "web_advisor_daily_check") return daily;
  throw new Error(`unexpected rpc ${fn}`);
});
vi.mock("../db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));

const { breakerOpen, dailyCapReached } = await import("./breaker");
const { kv } = await import("../kv");

afterEach(async () => {
  await kv().del("wa:breaker:open");
  vi.restoreAllMocks();
});

describe("site-wide daily Witty ceiling (web14)", () => {
  it("below the ceiling: the turn runs and the breaker stays closed", async () => {
    daily = { ok: true, turns: 10, cost_usd: 0.4, max_turns: 2000, max_cost_usd: 25, reset_seconds: 3600 };
    expect(await dailyCapReached()).toBe(false);
    expect(await breakerOpen()).toBe(false);
  });

  it("at the ceiling: the turn is refused, the breaker opens and the alert is logged", async () => {
    const errors: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void errors.push(a.map(String).join(" ")));
    daily = { ok: false, turns: 2000, cost_usd: 9.5, max_turns: 2000, max_cost_usd: 25, reset_seconds: 3600 };
    expect(await dailyCapReached()).toBe(true);
    expect(await breakerOpen()).toBe(true);
    expect(errors.some((l) => l.includes("web_advisor.daily_cap_reached"))).toBe(true);
  });

  it("a failed check does not block the turn", async () => {
    rpc.mockRejectedValueOnce(new Error("db down"));
    expect(await dailyCapReached()).toBe(false);
  });
});
