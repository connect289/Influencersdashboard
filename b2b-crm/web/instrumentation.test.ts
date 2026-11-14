import { afterEach, describe, expect, it, vi } from "vitest";
import { onRequestError } from "./instrumentation";

const request = { path: "/leads/42?email=s@x.in", method: "GET", headers: { cookie: "sb=secret" } };
const context = { routerKind: "App Router", routePath: "/leads/[id]", routeType: "render", renderSource: "react-server-components", revalidateReason: undefined } as const;

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("onRequestError (audit M11: the log line, then the count for Eduwit One)", () => {
  it("writes one line without personal data and prepares no report outside a deployment", async () => {
    vi.useFakeTimers();
    const lines: string[] = [];
    vi.spyOn(console, "error").mockImplementation((l: unknown) => void lines.push(String(l)));
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    await onRequestError(Object.assign(new TypeError("phone 919876543210"), { digest: "1234567" }), request, context);
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0] ?? "{}")).toMatchObject({ event: "request_error", name: "TypeError", route: "/leads/[id]", digest: "1234567" });
    expect(lines[0]).not.toMatch(/919876543210|s@x\.in|secret/);
    // Tests run without a production build and without a hosted Supabase address: nothing waits to be sent.
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
