import { describe, expect, it } from "vitest";
import { requestErrorLine } from "./request-error";

describe("request error log line (D-095)", () => {
  it("is structured JSON without personal data", () => {
    const err = Object.assign(new Error("lead 9876543211 for asha@example.com failed"), { digest: "123abc" });
    const line = requestErrorLine(
      err,
      {
        path: "/account/asha@example.com?email=asha@example.com&phone=9876543211",
        method: "POST",
        headers: { "x-request-id": "req-1", cookie: "s=secret" },
      },
      { routePath: "/account", routeType: "action", routerKind: "App Router", renderSource: "react-server-components" },
      new Date("2026-11-13T00:00:00Z"),
    );
    const j = JSON.parse(line) as Record<string, unknown>;
    expect(j).toMatchObject({
      level: "error",
      event: "request.error",
      error: "Error",
      digest: "123abc",
      method: "POST",
      requestId: "req-1",
      route: "/account",
      kind: "action",
    });
    expect(line).not.toContain("asha");
    expect(line).not.toContain("9876543211");
    expect(line).not.toContain("secret");
    expect(j.path).toBe("/account/[email]");
  });
  it("drops a request id that is not an id and bounds the message", () => {
    const j = JSON.parse(
      requestErrorLine("x".repeat(2000), { path: "/", method: "GET", headers: { "x-request-id": "<script>" } }, {}),
    ) as Record<string, unknown>;
    expect(j.requestId).toBeUndefined();
    expect(String(j.message).length).toBeLessThanOrEqual(500);
    expect(j.error).toBe("string");
  });
});
