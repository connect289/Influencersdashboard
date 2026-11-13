import { describe, expect, it } from "vitest";
import { requestErrorLine } from "./request-error";

const ctx = { routerKind: "App Router", routePath: "/leads/[id]", routeType: "render", renderSource: "react-server-components" } as const;

describe("requestErrorLine (M34i onRequestError)", () => {
  it("keeps the error's name, digest and code and the route pattern", () => {
    const e = Object.assign(new TypeError("boom"), { digest: "1234567890", code: "PGRST116" });
    expect(requestErrorLine(e, { path: "/leads/42?q=x", method: "GET" }, ctx)).toEqual({
      event: "request_error", name: "TypeError", digest: "1234567890", code: "PGRST116", method: "GET", route: "/leads/[id]",
      route_type: "render", router: "App Router", render_source: "react-server-components",
    });
  });
  it("never carries the message, the query string or free-text codes", () => {
    const e = Object.assign(new Error('duplicate key: phone 919876543210, email s@x.in'), { code: "Key (email)=(s@x.in) exists" });
    const line = JSON.stringify(requestErrorLine(e, { path: "/leads/42?email=s@x.in", method: "POST" }, { ...ctx, routePath: "" }));
    expect(line).not.toMatch(/919876543210|s@x\.in|duplicate key/);
    expect(JSON.parse(line)).toMatchObject({ code: null, route: "/leads/[id]", method: "POST" });
  });
  it("copes with thrown values that are not errors", () => {
    expect(requestErrorLine("a string with a phone 919876543210", { path: "/", method: "get" }, ctx)).toMatchObject({
      name: "Error", digest: null, code: null, method: "?",
    });
    expect(requestErrorLine(null, { path: "/", method: "GET" }, ctx).name).toBe("Error");
  });
});
