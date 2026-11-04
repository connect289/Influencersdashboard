import { describe, expect, it } from "vitest";
import { internalToken } from "./security.ts";

// The key is set before auth.ts is loaded: bootEnv() reads the environment once.
const key = "k".repeat(40);
process.env.ONE_INTERNAL_KEY = key;

describe("internalAuthorized (the /api/internal/* door)", () => {
  it("takes the static bearer or a fresh token for the request's own path", async () => {
    const { internalAuthorized } = await import("./auth.ts");
    const url = "https://one.eduwit.in/api/internal/tick";
    const post = (headers: Record<string, string>) => new Request(url, { method: "POST", headers });
    const ts = Math.floor(Date.now() / 1000);
    expect(await internalAuthorized(post({ authorization: `Bearer ${key}` }))).toBe(true);
    expect(await internalAuthorized(post({ "x-one-token": await internalToken(key, "/api/internal/tick", ts) }))).toBe(
      true,
    );
    expect(
      await internalAuthorized(post({ "x-one-token": await internalToken(key, "/api/internal/heartbeat", ts) })),
    ).toBe(false);
    expect(await internalAuthorized(post({ authorization: "Bearer nope" }))).toBe(false);
    expect(await internalAuthorized(post({}))).toBe(false);
  });
});
