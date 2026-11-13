import { afterEach, describe, expect, it, vi } from "vitest";
import { onRequestError } from "@/instrumentation";
import { scrubText } from "./log";

describe("scrubText", () => {
  it("replaces contact details, account numbers, PAN, GSTIN and tokens", () => {
    expect(scrubText('duplicate key value (email)=(riya.s@example.com) violates "creators_email_key"')).toBe(
      'duplicate key value (email)=([email]) violates "creators_email_key"',
    );
    expect(scrubText("call +91 98765 43210 or 9876543210")).toBe("call [number] or [number]");
    expect(scrubText("account 001234567890 failed")).toBe("account [number] failed");
    expect(scrubText("PAN ABCPS1234K and GSTIN 27ABCPS1234K1Z5")).toBe("PAN [pan] and GSTIN [gstin]");
    expect(scrubText("Authorization: Bearer re_abc.def-123")).toBe("Authorization: Bearer [token]");
    expect(scrubText("jwt eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl here")).toBe("jwt [token] here");
  });

  it("keeps ids, dates and short numbers", () => {
    const id = "12345678-1234-4234-8234-123456789012";
    expect(scrubText(`job ${id} failed on 2026-11-13 after 3 attempts (HTTP 503)`)).toBe(
      `job ${id} failed on 2026-11-13 after 3 attempts (HTTP 503)`,
    );
  });
});

describe("onRequestError", () => {
  afterEach(() => vi.restoreAllMocks());

  it("logs the route pattern and a scrubbed message, never the requested path", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const err = Object.assign(new Error("no creator with email riya@example.com"), { digest: "d1" });
    void onRequestError(
      err,
      { path: "/m/riyalearns?ref=riya@example.com", method: "GET", headers: { "x-request-id": "r1" } },
      {
        routerKind: "App Router",
        routePath: "/m/[handle]",
        routeType: "render",
        renderSource: "react-server-components",
        revalidateReason: undefined,
      },
    );
    const line = String(spy.mock.calls[0]?.[0] ?? "");
    expect(line).not.toContain("riya");
    expect(JSON.parse(line)).toMatchObject({
      event: "request.error",
      message: "no creator with email [email]",
      route: "/m/[handle]",
      digest: "d1",
      request_id: "r1",
    });
  });
});
