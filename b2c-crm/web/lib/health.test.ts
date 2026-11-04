import { describe, expect, it } from "vitest";
import { combine, configCheck, publicView, reportChecks, storageCheck, type Check } from "./health";

const env = {
  NEXT_PUBLIC_SUPABASE_URL: "https://x.supabase.co",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_x",
  SUPABASE_SERVICE_ROLE_KEY: "service",
  NEXT_PUBLIC_SITE_URL: "https://spark.eduwit.in",
  B2C_INTERNAL_KEY: "k".repeat(40),
  B2B_API_URL: "https://crm.eduwit.in",
  B2B_API_KEY: "b2b",
  B2B_SIGNING_SECRET: "s",
};
const level = (l: Check["level"]) => ({ level: l });
const report = (over: Record<string, unknown> = {}) => ({
  ok: true,
  status: "ok",
  checks: {
    timers: { level: "ok", jobs: 16 },
    app: { level: "ok", pointed: true },
    outbox: level("ok"),
    inbox: level("ok"),
    sending: { level: "ok", stuck_sending: 0 },
    connectors: level("ok"),
    programmes: level("ok"),
    ai: level("ok"),
    jobs: level("ok"),
    ...over,
  },
});
const okStorage = storageCheck(["b2c-documents", "b2c-recordings", "b2c-support"]);

describe("configuration", () => {
  it("is ok with every variable, and names only the missing ones (never a value)", () => {
    expect(configCheck(env)).toMatchObject({ level: "ok", missing: [], invalid: [], b2b_link: true });
    const c = configCheck({ ...env, SUPABASE_SERVICE_ROLE_KEY: undefined, B2C_INTERNAL_KEY: "Zq7-not-long" });
    expect(c.level).toBe("bad");
    expect(c.missing).toEqual(["SUPABASE_SERVICE_ROLE_KEY"]);
    expect(JSON.stringify(c)).not.toContain("Zq7-not-long");
  });

  it("warns without the B2B link, refuses a Gmail token key that is not 32 bytes", () => {
    expect(configCheck({ ...env, B2B_API_KEY: undefined })).toMatchObject({ level: "warn", b2b_link: false, missing: ["B2B_API_KEY"] });
    expect(configCheck({ ...env, GMAIL_TOKEN_KEY: "abc" }).level).toBe("bad");
    expect(configCheck({ ...env, GMAIL_TOKEN_KEY: "a".repeat(64) }).level).toBe("ok");
  });
});

describe("storage and the database report", () => {
  it("storage: no answer is bad, a missing bucket a warning", () => {
    expect(storageCheck(null).level).toBe("bad");
    expect(storageCheck(["b2c-documents"])).toMatchObject({ level: "warn", missing_buckets: ["b2c-recordings", "b2c-support"] });
    expect(okStorage.level).toBe("ok");
  });

  it("no report means the database is down; an unknown part is a warning, not trusted", () => {
    expect(reportChecks(null).database.level).toBe("bad");
    expect(reportChecks({ nope: true }).database.level).toBe("bad");
    const r = reportChecks({ checks: { timers: { level: "fine" } } });
    expect(r.database.level).toBe("ok");
    expect(r.checks.timers).toEqual({ level: "warn", reported: false });
    expect(r.checks.sending).toEqual({ level: "warn", reported: false });
  });
});

describe("the answer", () => {
  it("ok when everything is", () => {
    expect(combine(configCheck(env), okStorage, report())).toMatchObject({ ok: true, status: "ok" });
  });

  it("degraded, still ok, when a queue or a connector needs a look", () => {
    const h = combine(configCheck(env), okStorage, report({ sending: { level: "bad", stuck_sending: 3 }, connectors: level("warn") }));
    expect(h).toMatchObject({ ok: true, status: "degraded" });
  });

  it("down when a core part is bad: configuration, database, storage, timers or the app", () => {
    expect(combine(configCheck({ ...env, B2C_INTERNAL_KEY: undefined }), okStorage, report())).toMatchObject({ ok: false, status: "down" });
    expect(combine(configCheck(env), okStorage, null)).toMatchObject({ ok: false, status: "down" });
    expect(combine(configCheck(env), storageCheck(null), report())).toMatchObject({ ok: false, status: "down" });
    expect(combine(configCheck(env), okStorage, report({ timers: level("bad") }))).toMatchObject({ ok: false, status: "down" });
    expect(combine(configCheck(env), okStorage, report({ app: level("bad") }))).toMatchObject({ ok: false, status: "down" });
  });

  it("shows the public only the levels", () => {
    const v = publicView(combine(configCheck(env), okStorage, report({ sending: { level: "bad", stuck_sending: 3 } })));
    expect(v.checks.sending).toBe("bad");
    expect(Object.keys(v.checks)).toEqual(["config", "database", "storage", "timers", "app", "outbox", "inbox", "sending", "connectors", "programmes", "ai", "jobs"]);
    expect(JSON.stringify(v)).not.toMatch(/stuck_sending|missing|b2b_link/);
  });
});
