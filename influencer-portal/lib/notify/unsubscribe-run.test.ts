// Following an unsubscribe link (D-198): the shared step and the two routes that call it. A link that is not ours gets
// the same answer as one that worked and costs no database call; a genuine one calls the one database function.
import { beforeEach, describe, expect, it, vi } from "vitest";

interface Hoisted {
  secret: string | undefined;
  rpc: { name: string; args: Record<string, unknown> }[];
  rpcError: null | { message: string };
  rateChecks: { scope: string; subject: string }[];
  rateOk: boolean;
  logged: { event: string; fields: Record<string, unknown> }[];
}
const h = vi.hoisted<Hoisted>(() => ({
  secret: "unit-test-unsubscribe-secret-0123456789abcdef",
  rpc: [],
  rpcError: null,
  rateChecks: [],
  rateOk: true,
  logged: [],
}));

vi.mock("@/lib/env", () => ({ env: () => ({ UNSUBSCRIBE_SECRET: h.secret }) }));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: (scope: string, subject: string) => {
    h.rateChecks.push({ scope, subject });
    return Promise.resolve(h.rateOk ? { ok: true } : { ok: false, retryAfter: 30, unavailable: false });
  },
}));
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({
    rpc: (name: string, args: Record<string, unknown>) => {
      h.rpc.push({ name, args });
      return Promise.resolve(h.rpcError ? { data: null, error: h.rpcError } : { data: 3, error: null });
    },
  }),
}));
vi.mock("@/lib/log", () => {
  const record = (event: string, fields: Record<string, unknown> = {}) => h.logged.push({ event, fields });
  return {
    log: { info: record, warn: record, error: record },
    errorMessage: (e: unknown) => (e instanceof Error ? e.message : String(e)),
  };
});

import { POST as confirm } from "@/app/unsubscribe/[token]/confirm/route";
import { GET as oneClickGet, POST as oneClick } from "@/app/unsubscribe/[token]/one-click/route";
import { signUnsubscribe } from "./unsubscribe";
import { followUnsubscribe, readUnsubscribeToken, tokenForPath } from "./unsubscribe-run";

const SECRET = "unit-test-unsubscribe-secret-0123456789abcdef";
const USER = "0b9f7a52-3c1e-4d6a-9f2b-7e5d4c3b2a10";
const TOKEN = signUnsubscribe(SECRET, { userId: USER, category: "campaigns" });
const FORGED = signUnsubscribe("someone-elses-secret-0123456789abcdef-0123", { userId: USER, category: "campaigns" });
const from = (ip: string) => new Headers({ "x-real-ip": ip });
const ctx = (token: string) => ({ params: Promise.resolve({ token }) });

function post(token: string, body?: BodyInit, headers: Record<string, string> = {}) {
  return new Request(`https://creators.eduwit.in/unsubscribe/${token}/one-click`, {
    method: "POST",
    body,
    headers: { "x-real-ip": "203.0.113.9", ...headers },
  });
}
const FORM = { "content-type": "application/x-www-form-urlencoded" };

beforeEach(() => {
  h.secret = SECRET;
  h.rpc = [];
  h.rpcError = null;
  h.rateChecks = [];
  h.rateOk = true;
  h.logged = [];
});

describe("following an unsubscribe link", () => {
  it("records a genuine link with the one database function, for the account and kind it names", async () => {
    expect(await followUnsubscribe(TOKEN, from("203.0.113.9"))).toBe("done");
    expect(h.rpc).toEqual([{ name: "unsubscribe_email", args: { p_user: USER, p_category: "campaigns" } }]);
    expect(h.rateChecks).toEqual([{ scope: "unsubscribe", subject: "203.0.113.9" }]);
  });

  it("answers the same for a link that is not ours, without touching the database", async () => {
    for (const bad of [FORGED, `${TOKEN}x`, TOKEN.slice(0, -4), "", "link", "../../admin", "a".repeat(4000)]) {
      expect(await followUnsubscribe(bad, from("203.0.113.9")), bad.slice(0, 20)).toBe("done");
    }
    expect(h.rpc).toEqual([]);
    expect(h.rateChecks).toEqual([]);
  });

  it("does nothing when no signing secret is configured", async () => {
    h.secret = undefined;
    expect(readUnsubscribeToken(TOKEN)).toBeNull();
    expect(await followUnsubscribe(TOKEN, from("203.0.113.9"))).toBe("done");
    expect(h.rpc).toEqual([]);
  });

  it("stops at the rate limit before the database function", async () => {
    h.rateOk = false;
    expect(await followUnsubscribe(TOKEN, from("203.0.113.9"))).toBe("limited");
    expect(h.rpc).toEqual([]);
  });

  it("reports a failure when the choice could not be recorded", async () => {
    h.rpcError = { message: "connection reset" };
    expect(await followUnsubscribe(TOKEN, from("203.0.113.9"))).toBe("failed");
  });

  it("logs the kind of email and the count, never the link or the account", async () => {
    await followUnsubscribe(TOKEN, from("203.0.113.9"));
    h.rpcError = { message: "connection reset" };
    await followUnsubscribe(TOKEN, from("203.0.113.9"));
    const lines = JSON.stringify(h.logged);
    expect(h.logged.map((l) => l.event)).toEqual(["unsubscribe.recorded", "unsubscribe.failed"]);
    expect(h.logged[0]?.fields).toEqual({ category: "campaigns", changed: 3 });
    expect(lines).not.toContain(TOKEN);
    expect(lines).not.toContain(USER);
    expect(lines).not.toContain(SECRET);
  });

  it("puts only a link-shaped value back into an address", () => {
    expect(tokenForPath(TOKEN)).toBe(TOKEN);
    for (const bad of [
      "",
      "a/b",
      "../x",
      "a.b",
      "a.b.c.d",
      "a.b.c?r=done",
      "a.b.c#x",
      "a b.c.d",
      "é.b.c",
      `${"a".repeat(99)}.b.c`,
    ])
      expect(tokenForPath(bad), bad).toBe("link");
  });
});

describe("one-click endpoint (RFC 8058)", () => {
  it("accepts the form-encoded body mail providers send and answers 200", async () => {
    const res = await oneClick(post(TOKEN, "List-Unsubscribe=One-Click", FORM), ctx(TOKEN));
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("x-robots-tag")).toContain("noindex");
    expect(res.headers.get("set-cookie")).toBeNull();
    expect(h.rpc).toHaveLength(1);
  });

  it("accepts the same field as multipart form data", async () => {
    const form = new FormData();
    form.set("List-Unsubscribe", "One-Click");
    expect((await oneClick(post(TOKEN, form), ctx(TOKEN))).status).toBe(200);
    expect(h.rpc).toHaveLength(1);
  });

  it("needs no cookie, origin or session", async () => {
    const res = await oneClick(
      post(TOKEN, "List-Unsubscribe=One-Click", { ...FORM, origin: "https://mail.example", cookie: "" }),
      ctx(TOKEN),
    );
    expect(res.status).toBe(200);
  });

  it("refuses a POST without that body, and changes nothing", async () => {
    for (const body of [undefined, "", "List-Unsubscribe=No", "x=1", '{"List-Unsubscribe":"One-Click"}']) {
      const res = await oneClick(post(TOKEN, body, body === undefined ? {} : FORM), ctx(TOKEN));
      expect(res.status, String(body)).toBe(400);
    }
    expect(h.rpc).toEqual([]);
  });

  it("answers a link that is not ours exactly like one that worked", async () => {
    const good = await oneClick(post(TOKEN, "List-Unsubscribe=One-Click", FORM), ctx(TOKEN));
    const bad = await oneClick(post(FORGED, "List-Unsubscribe=One-Click", FORM), ctx(FORGED));
    expect(bad.status).toBe(good.status);
    expect(await bad.text()).toBe(await good.text());
    expect([...bad.headers.entries()]).toEqual([...good.headers.entries()]);
    expect(h.rpc).toHaveLength(1);
  });

  it("says so when it is rate-limited or could not record the choice", async () => {
    h.rateOk = false;
    const limited = await oneClick(post(TOKEN, "List-Unsubscribe=One-Click", FORM), ctx(TOKEN));
    expect([limited.status, limited.headers.get("retry-after")]).toEqual([429, "60"]);
    h.rateOk = true;
    h.rpcError = { message: "timeout" };
    expect((await oneClick(post(TOKEN, "List-Unsubscribe=One-Click", FORM), ctx(TOKEN))).status).toBe(503);
  });

  it("a GET changes nothing and sends a person to the page", async () => {
    const res = await oneClickGet(new Request("https://creators.eduwit.in/x"), ctx(TOKEN));
    expect([res.status, res.headers.get("location")]).toEqual([303, `/unsubscribe/${TOKEN}`]);
    expect(h.rpc).toEqual([]);
  });
});

describe("the page's button", () => {
  it("records the choice and goes back to the page with the result (works as a plain form post)", async () => {
    const res = await confirm(post(TOKEN), ctx(TOKEN));
    expect([res.status, res.headers.get("location")]).toEqual([303, `/unsubscribe/${TOKEN}?r=done`]);
    expect(h.rpc).toEqual([{ name: "unsubscribe_email", args: { p_user: USER, p_category: "campaigns" } }]);
  });

  it("gives a link that is not ours the same result", async () => {
    const res = await confirm(post(FORGED), ctx(FORGED));
    expect([res.status, res.headers.get("location")]).toEqual([303, `/unsubscribe/${FORGED}?r=done`]);
    expect(h.rpc).toEqual([]);
  });

  it("never puts anything but a link-shaped value into the address it sends the browser to", async () => {
    for (const bad of ["//evil.example", "x\r\nSet-Cookie: a=b", "..%2F..%2Fadmin", "a.b.c?next=//evil.example"]) {
      const res = await confirm(post("x"), ctx(bad));
      expect(res.headers.get("location"), bad).toBe("/unsubscribe/link?r=done");
    }
  });

  it("carries a rate limit or a failure back to the page", async () => {
    h.rateOk = false;
    expect((await confirm(post(TOKEN), ctx(TOKEN))).headers.get("location")).toBe(`/unsubscribe/${TOKEN}?r=limited`);
    h.rateOk = true;
    h.rpcError = { message: "timeout" };
    expect((await confirm(post(TOKEN), ctx(TOKEN))).headers.get("location")).toBe(`/unsubscribe/${TOKEN}?r=failed`);
  });
});
