import { createHmac } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetBreakers } from "../http.ts";
import { jwtClaim, RealB2bApi, RealChatwootReader, RealHarness, RealRunnerApi } from "./apps.ts";
import { totp } from "./totp.ts";

type Call = { url: string; method: string; headers: Record<string, string>; body: string | undefined };
let calls: Call[] = [];
let answers: Array<{ status?: number; json: unknown }> = [];

beforeEach(() => {
  resetBreakers();
  calls = [];
  answers = [];
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    calls.push({
      url,
      method: init.method ?? "GET",
      headers: init.headers as Record<string, string>,
      body: init.body as string | undefined,
    });
    const a = answers.shift() ?? { json: {} };
    return new Response(JSON.stringify(a.json), { status: a.status ?? 200 });
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

const jwt = (claims: Record<string, unknown>) => `h.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.s`;

describe("B2B", () => {
  it("posts the intake with the key and the idempotency key", async () => {
    answers.push({
      status: 201,
      json: { ok: true, lead_id: 7, action: "created", is_test: true, routing: { status: "waiting" } },
    });
    const r = await new RealB2bApi("https://crm.example", "eb2b_key", null).intake(
      { lead: { phone: "+910000900001" } },
      "k-1",
    );
    expect(r).toEqual({ status: 201, leadId: 7, isTest: true, action: "created", routing: "waiting" });
    expect(calls[0]?.url).toBe("https://crm.example/v1/leads");
    expect(calls[0]?.headers).toMatchObject({ authorization: "Bearer eb2b_key", "idempotency-key": "k-1" });
  });

  it("signs a partner event over the timestamp and the exact body sent", async () => {
    answers.push({ json: { ok: true } });
    const now = Date.parse("2026-10-23T05:00:00Z");
    await new RealB2bApi("https://crm.example", "k", "partner-secret").partnerEvent(
      "test-partner",
      { event_id: "e1", type: "contacted" },
      now,
    );
    const c = calls[0];
    const ts = String(Math.floor(now / 1000));
    expect(c?.url).toBe("https://crm.example/v1/partners/test-partner/events");
    expect(c?.headers["x-eduwit-timestamp"]).toBe(ts);
    const expected = createHmac("sha256", "partner-secret").update(`${ts}.${c?.body}`).digest("hex");
    expect(c?.headers["x-eduwit-signature"]).toBe(`sha256=${expected}`);
  });

  it("will not post an unsigned partner event", async () => {
    await expect(new RealB2bApi("https://crm.example", "k", null).partnerEvent("p", {}, 0)).rejects.toThrow(/secret/);
    expect(calls).toHaveLength(0);
  });
});

describe("the test runner login", () => {
  const login = { email: "tests@eduwit.in", password: "pw-123456", totpSecret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" };
  const now = () => Date.parse("2026-10-23T05:00:00Z");
  const signIn = (aal: string) => {
    answers.push({
      json: {
        access_token: jwt({ aal: "aal1" }),
        expires_in: 3600,
        user: { factors: [{ id: "f1", factor_type: "totp", status: "verified" }] },
      },
    });
    answers.push({ json: { id: "ch1" } });
    answers.push({ json: { access_token: jwt({ aal }), expires_in: 3600 } });
  };

  it("signs in with the password and the one-time code, then calls the app as aal2, once per session", async () => {
    signIn("aal2");
    answers.push({ json: true }, { json: "admin" });
    const r = new RealRunnerApi("https://db.example", "anon", login, now);
    expect(await r.rpc("b2b", "is_admin", {})).toBe(true);
    expect(await r.rpc("b2c", "my_role", {})).toBe("admin");
    expect(calls.map((c) => c.url)).toEqual([
      "https://db.example/auth/v1/token?grant_type=password",
      "https://db.example/auth/v1/factors/f1/challenge",
      "https://db.example/auth/v1/factors/f1/verify",
      "https://db.example/rest/v1/rpc/is_admin",
      "https://db.example/rest/v1/rpc/my_role",
    ]);
    expect(JSON.parse(calls[2]?.body ?? "{}")).toEqual({ challenge_id: "ch1", code: totp(login.totpSecret, now()) });
    expect(calls[3]?.headers).toMatchObject({ "content-profile": "b2b", "accept-profile": "b2b", apikey: "anon" });
    expect(calls[4]?.headers).toMatchObject({ "content-profile": "b2c" });
  });

  it("refuses a session that is not two-factor", async () => {
    signIn("aal1");
    await expect(
      new RealRunnerApi("https://db.example", "anon", login, now).rpc("b2b", "is_admin", {}),
    ).rejects.toThrow(/aal2/);
    expect(calls).toHaveLength(3);
  });

  it("refuses a login without a verified TOTP factor", async () => {
    answers.push({ json: { access_token: jwt({ aal: "aal1" }), expires_in: 3600, user: { factors: [] } } });
    await expect(
      new RealRunnerApi("https://db.example", "anon", login, now).rpc("b2b", "is_admin", {}),
    ).rejects.toThrow(/TOTP/);
  });

  it("reads a claim and survives a malformed token", () => {
    expect(jwtClaim(jwt({ aal: "aal2" }), "aal")).toBe("aal2");
    expect(jwtClaim("nonsense", "aal")).toBeUndefined();
    expect(jwtClaim("a.%%%.b", "aal")).toBeUndefined();
  });
});

describe("n8n and Chatwoot", () => {
  it("starts the configured scenario under the run tag", async () => {
    answers.push({ json: { ok: true } });
    const h = new RealHarness("https://n8n.example", "key", {
      workflowId: "w1",
      webhookPath: "/webhook/h",
      scenario: "happy_path_mba",
    });
    expect(await h.start("one-5")).toEqual({ accepted: true });
    expect(calls[0]?.url).toBe("https://n8n.example/webhook/h");
    expect(JSON.parse(calls[0]?.body ?? "{}")).toEqual({ run_tag: "one-5", only: ["happy_path_mba"] });
  });

  it("switches the workflow with the API key", async () => {
    answers.push({ json: { active: true } });
    await new RealHarness("https://n8n.example", "key", {
      workflowId: "w1",
      webhookPath: "/w",
      scenario: "s",
    }).setActive(false);
    expect(calls[0]).toMatchObject({ url: "https://n8n.example/api/v1/workflows/w1/deactivate", method: "POST" });
    expect(calls[0]?.headers["X-N8N-API-KEY"]).toBe("key");
  });

  it("counts outgoing Chatwoot messages since a time", async () => {
    answers.push({
      json: {
        payload: [
          { message_type: 0, created_at: 100, content: "hi" },
          { message_type: 1, created_at: 90, content: "old" },
          { message_type: 1, created_at: 110, content: "reply" },
        ],
      },
    });
    expect(await new RealChatwootReader("https://chat.example", "t", "3").outgoingSince(812, 100)).toBe(1);
    expect(calls[0]?.url).toBe("https://chat.example/api/v1/accounts/3/conversations/812/messages");
  });
});
