import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { findRedirect } = await import("./redirects");
const { resetEnvCache } = await import("./env");

const saved = process.env.SUPABASE_SECRET_KEY;
afterEach(() => {
  if (saved === undefined) delete process.env.SUPABASE_SECRET_KEY;
  else process.env.SUPABASE_SECRET_KEY = saved;
  resetEnvCache();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("runtime redirects", () => {
  it("keep the last good map and back off for a minute when the database is unreachable", async () => {
    process.env.SUPABASE_SECRET_KEY = "test-secret-key-0123456789";
    resetEnvCache();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-30T10:00:00Z"));
    let up = true;
    const fetch = vi.fn(async () => {
      if (!up) throw new Error("timeout");
      return new Response(JSON.stringify({ "/old": { to: "/new", code: 301 } }), { status: 200 });
    });
    vi.stubGlobal("fetch", fetch);

    expect(await findRedirect("/old")).toEqual({ to: "/new", code: 301 });
    expect(fetch).toHaveBeenCalledTimes(1);

    // The map is 61 s old and the database stops answering: one failed load, then no new attempt for a minute.
    up = false;
    vi.setSystemTime(new Date("2026-10-30T10:01:01Z"));
    for (let i = 0; i < 5; i++) expect(await findRedirect("/old")).toEqual({ to: "/new", code: 301 });
    expect(fetch).toHaveBeenCalledTimes(2);

    // A minute later it tries again and picks up the database once it is back.
    up = true;
    vi.setSystemTime(new Date("2026-10-30T10:02:02Z"));
    expect(await findRedirect("/old/")).toEqual({ to: "/new", code: 301 });
    expect(fetch).toHaveBeenCalledTimes(3);
  });
});
