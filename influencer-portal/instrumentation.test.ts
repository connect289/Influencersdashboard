import { afterEach, describe, expect, it, vi } from "vitest";
import { onRequestError } from "./instrumentation";

const request = {
  path: "/m/asha?email=s@x.in",
  method: "GET",
  headers: { cookie: "sb=secret", "x-request-id": "req-1" },
};
const context = {
  routerKind: "App Router",
  routePath: "/m/[handle]",
  routeType: "render",
  renderSource: "react-server-components",
  revalidateReason: undefined,
} as const;

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("onRequestError (D-199: the log line, then the count for Eduwit One)", () => {
  it("writes one scrubbed line and prepares no report outside a deployment", async () => {
    vi.useFakeTimers();
    const lines: string[] = [];
    vi.spyOn(console, "error").mockImplementation((l: unknown) => void lines.push(String(l)));
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    await onRequestError(
      Object.assign(new TypeError("no owner for s@x.in, phone 919876543210"), { digest: "1234567" }),
      request,
      context,
    );
    expect(lines).toHaveLength(1);
    expect(lines[0]).toContain("request.error");
    expect(lines[0]).toContain("/m/[handle]");
    expect(lines[0]).not.toMatch(/919876543210|s@x\.in|secret|asha/);
    // Tests run without a production build and without a hosted Supabase address: nothing waits to be sent.
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
