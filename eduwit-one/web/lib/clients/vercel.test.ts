import { afterEach, describe, expect, it, vi } from "vitest";
import { RealVercelClient } from "./vercel.ts";

// The probe judges the newest production deployment that finished building: a canceled one (a docs-only push skipped by
// the ignored-build step, D-111, or one superseded) or one still building is passed over; an ERROR is still a failure.
const deployments = (states: string[]) => ({
  deployments: states.map((s, i) => ({
    uid: `dpl_${i}`,
    readyState: s,
    created: 1_800_000_000_000 - i * 60_000,
    url: null,
  })),
});

function client(states: string[]) {
  vi.stubGlobal(
    "fetch",
    vi.fn(
      async () =>
        new Response(JSON.stringify(deployments(states)), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    ),
  );
  return new RealVercelClient("https://api.vercel.example", "test-token");
}

afterEach(() => vi.unstubAllGlobals());

describe("latestProduction", () => {
  it("passes over canceled deployments to the newest built one", async () => {
    const d = await client(["CANCELED", "CANCELED", "READY", "ERROR"]).latestProduction("eduwit-one", "eduwit");
    expect(d).toMatchObject({ uid: "dpl_2", state: "READY" });
  });
  it("keeps a failed build as the answer", async () => {
    const d = await client(["CANCELED", "ERROR", "READY"]).latestProduction("eduwit-one", "eduwit");
    expect(d).toMatchObject({ uid: "dpl_1", state: "ERROR" });
  });
  it("passes over a build still in progress", async () => {
    const d = await client(["BUILDING", "CANCELED", "READY"]).latestProduction("eduwit-one", "eduwit");
    expect(d).toMatchObject({ uid: "dpl_2", state: "READY" });
  });
  it("returns the newest when every listed deployment was canceled", async () => {
    const d = await client(["CANCELED", "CANCELED"]).latestProduction("eduwit-one", "eduwit");
    expect(d).toMatchObject({ uid: "dpl_0", state: "CANCELED" });
  });
});
