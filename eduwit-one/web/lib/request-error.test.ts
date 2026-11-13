import { afterEach, describe, expect, it, vi } from "vitest";
import { onRequestError } from "../instrumentation.ts";
import { logRequestError, MESSAGE_MAX, requestErrorInfo } from "./request-error.ts";

const context = {
  routerKind: "App Router" as const,
  routePath: "/incidents/[id]",
  routeType: "render" as const,
  revalidateReason: undefined,
};
const request = {
  path: "/incidents/42?email=asha@example.com",
  method: "GET",
  headers: { cookie: "sb-access-token=secret" },
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("requestErrorInfo (D-137)", () => {
  it("names the route template, the digest and the error, with contacts masked and nothing from the request", () => {
    const error = Object.assign(new TypeError("lead 9876543210 (asha@example.com) has no owner"), {
      digest: "1234567",
    });
    const info = requestErrorInfo(error, request, context);
    expect(info).toMatchObject({ route: "/incidents/[id]", method: "GET", kind: "render", router: "App Router" });
    expect(info.digest).toBe("1234567");
    expect(info.name).toBe("TypeError");
    expect(info.message).not.toContain("9876543210");
    expect(info.message).not.toContain("asha@");
    const line = JSON.stringify(info);
    expect(line).not.toContain("secret");
    expect(line).not.toContain("?email");
  });

  it("cuts a long message and copes with a thrown string or nothing at all", () => {
    expect(requestErrorInfo(new Error("x".repeat(500)), request, context).message).toHaveLength(MESSAGE_MAX + 1);
    expect(requestErrorInfo("plain failure", request, context)).toMatchObject({
      name: "Error",
      message: "plain failure",
    });
    expect(requestErrorInfo(null, request, context)).toMatchObject({ name: "Error", message: "", digest: null });
  });
});

describe("onRequestError", () => {
  it("writes one app.error line", async () => {
    const lines: string[] = [];
    vi.spyOn(console, "error").mockImplementation((l: unknown) => void lines.push(String(l)));
    await onRequestError(new Error("boom"), request, context);
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0] ?? "{}")).toMatchObject({
      level: "error",
      event: "app.error",
      route: "/incidents/[id]",
      message: "boom",
    });
  });

  it("never throws, even when logging fails", () => {
    vi.spyOn(console, "error").mockImplementation(() => {
      throw new Error("stdout closed");
    });
    expect(() => logRequestError(new Error("boom"), request, context)).not.toThrow();
  });
});
