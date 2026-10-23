import { describe, expect, it } from "vitest";
import { mockClients } from "@/lib/clients/index.ts";
import { MockN8nClient } from "@/lib/clients/n8n.ts";
import type { Clients } from "@/lib/clients/types.ts";
import { FakeDb, tickState } from "@/test/state.ts";
import { runTick } from "./runner.ts";
import type { Probe } from "./types.ts";

const run = (db: FakeDb, clients: Clients = mockClients(), extra: Partial<Parameters<typeof runTick>[0]> = {}) =>
  runTick({ db, clients: () => clients, requestId: "test", ...extra });

const heartbeat = (db: FakeDb, component: string) => db.reports[0]?.heartbeats.find((h) => h.component === component);
const result = (db: FakeDb, id: string) => db.reports[0]?.results.find((r) => r.check_id === id);

describe("one tick against the recorded fixtures", () => {
  it("writes one:app, the app health heartbeats and their checks in one report", async () => {
    const db = new FakeDb(tickState());
    const summary = await run(db);
    expect(db.reports).toHaveLength(1);
    expect(heartbeat(db, "one:app")?.ok).toBe(true);
    for (const c of ["website", "influencer", "b2b-app", "spark"]) expect(heartbeat(db, c)?.ok, c).toBe(true);
    expect(result(db, "WEB-02")?.status).toBe("ok");
    expect(result(db, "INF-04")?.status).toBe("ok");
    expect(summary.probes["app-health"]?.status).toBe("ran");
  });

  it("reports the website's Vercel deployment ready and Eduwit One's project as missing", async () => {
    const db = new FakeDb(tickState());
    await run(db);
    expect(heartbeat(db, "vercel:website")?.ok).toBe(true);
    expect(result(db, "WEB-07")?.status).toBe("ok");
    expect(heartbeat(db, "vercel:one")).toMatchObject({ ok: false, error: "deployment missing" });
  });

  it("gives WITTY-03 its Chatwoot reading and checks escalated conversations' labels", async () => {
    const db = new FakeDb(tickState());
    db.escalations = [{ conversation_id: 77, account_id: 1, escalated_at: new Date().toISOString() }];
    await run(db);
    expect(heartbeat(db, "chatwoot")?.detail).toMatchObject({ incoming_recent: expect.any(Number), window_h: 3 });
    expect(result(db, "WITTY-05")).toMatchObject({ status: "fail", value: { missing_label: [77], subjects: ["77"] } });
  });

  it("does not run disabled checks or probe a component read moments ago", async () => {
    const fresh = new Date(Date.now() - 30_000).toISOString();
    const db = new FakeDb(
      tickState({
        heartbeats: [{ component: "website", last_ok_at: fresh, last_error_at: null, expected_interval_s: 60 }],
        checks: [{ id: "WEB-02", enabled: true, disabled_reason: null, cadence_s: 60, last_ran_at: fresh }],
      }),
    );
    await run(db);
    expect(heartbeat(db, "website")).toBeUndefined();
    expect(result(db, "WEB-02")).toBeUndefined();
    expect(result(db, "WITTY-02")).toBeUndefined();
  });
});

describe("missing configuration and failures", () => {
  it("writes nothing for a client that is not configured, so a mock never fakes a heartbeat", async () => {
    const db = new FakeDb(tickState());
    const clients = {
      ...mockClients(),
      vercel: { mode: "not_configured" as const, client: null },
      n8n: { mode: "not_configured" as const, client: null },
    };
    const summary = await run(db, clients);
    expect(heartbeat(db, "vercel:website")).toBeUndefined();
    expect(summary.probes.vercel?.status).toBe("not_configured");
    expect(summary.probes.n8n?.status).toBe("not_configured");
  });

  it("marks a website that stops answering as a failed heartbeat, which HB-website turns into an incident at 3 × 60 s", async () => {
    const db = new FakeDb(tickState());
    const clients = mockClients();
    clients.appHealth = { mode: "mock", client: { health: async () => ({ ok: false, status: 503, ms: 40 }) } };
    await run(db, clients);
    expect(heartbeat(db, "website")).toMatchObject({ ok: false, error: "health 503", expected_interval_s: 60 });
    expect(result(db, "WEB-02")?.status).toBe("fail");
  });

  it("stops a hung probe at its deadline and still writes the rest", async () => {
    const db = new FakeDb(tickState());
    const hung: Probe = { name: "hung", run: () => new Promise(() => undefined) };
    const summary = await run(db, mockClients(), { probes: [hung], probeDeadlineMs: 50 });
    expect(summary.probes.hung).toMatchObject({ status: "error", error: "deadline" });
    expect(heartbeat(db, "one:app")?.ok).toBe(true);
  });

  it("judges WITTY-02 from the workflow's flag, its latest start and recent errors", async () => {
    const now = new Date();
    const ago = (m: number) => new Date(now.getTime() - m * 60_000).toISOString();
    const state = tickState();
    state.checks = state.checks.map((c) => (c.id === "WITTY-02" ? { ...c, enabled: true, disabled_reason: null } : c));
    const n8n = new MockN8nClient({
      workflows: { default: { id: "x", name: "Witty", active: true } },
      executions: {
        default: {
          data: [
            { id: "9", status: "success", startedAt: ago(1), stoppedAt: ago(1) },
            { id: "8", status: "error", startedAt: ago(10), stoppedAt: ago(10) },
          ],
        },
      },
    });
    const db = new FakeDb(state);
    await run(db, { ...mockClients(), n8n: { mode: "mock", client: n8n } }, { now });
    expect(result(db, "WITTY-02")).toMatchObject({ status: "fail", value: { active: true, failed_15m: ["8"] } });
    expect(heartbeat(db, `n8n:${state.settings.n8n.witty_workflow_id}`)?.ok).toBe(true);
  });
});
