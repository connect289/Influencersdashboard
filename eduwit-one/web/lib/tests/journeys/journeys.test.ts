import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { advanceRun } from "../runner.ts";
import type { Identities, Run, TestContext } from "../types.ts";
import { journeys } from "./index.ts";
import type { JourneyIo } from "./io.ts";
import { tAlert } from "./alert.ts";

type Entry = { id: string; needs: string[]; steps: Array<{ key: string; title: string; timeout_s: number }> };
const catalogue = (
  JSON.parse(readFileSync(new URL("../../../../config/tests.json", import.meta.url), "utf8")) as { tests: Entry[] }
).tests;

describe("the journeys match the catalogue", () => {
  for (const j of journeys) {
    it(`${j.id}: same needs and steps as config/tests.json`, () => {
      const entry = catalogue.find((t) => t.id === j.id);
      expect(entry).toBeDefined();
      expect([...j.needs].sort()).toEqual([...(entry?.needs ?? [])].sort());
      expect(j.steps.map((s) => ({ key: s.key, title: s.title, timeout_s: s.timeoutS }))).toEqual(entry?.steps);
    });
  }
});

const identities: Identities = {
  phone_prefix: "910000",
  whatsapp_number: null,
  mailbox: null,
  website_preview_url: null,
  spark_test_user_email: null,
  partner_slug: null,
  creator_referral_code: null,
};

function harness(lastEvent: string) {
  const clock = { t: Date.parse("2026-10-23T05:00:00Z") };
  const delivery = { status: "pending", provider_id: null as string | null, attempts: 0 };
  const acts: string[] = [];
  const io: JourneyIo = {
    seams: {
      fact: async (_run, kind) => {
        expect(kind).toBe("alert.delivery");
        return delivery;
      },
      act: async (_run, kind) => {
        acts.push(kind);
        return kind === "alert.open"
          ? { incident_id: 41, delivery_id: 9, recipient: "resend_test_address" }
          : { closed: true };
      },
    },
    email: {
      send: async () => ({ id: "re-1" }),
      status: async () => ({ lastEvent }),
    },
  };
  const run: Run = {
    id: 5,
    testId: "T-ALERT",
    startedAt: new Date(clock.t).toISOString(),
    steps: [],
    artefacts: {},
    state: { step: 0, stepStartedAt: new Date(clock.t).toISOString(), acted: false },
  };
  const finished: Array<{ ok: boolean; error: string | null }> = [];
  const db = {
    testsState: async () => ({ tests: [], identities, runs: [] }),
    runStart: async () => null,
    runSave: async () => undefined,
    runFinish: async (_r: Run, ok: boolean, error: string | null) => {
      finished.push({ ok, error });
    },
  };
  const ctx: TestContext<JourneyIo> = { run, artefacts: run.artefacts, identities, io, now: () => clock.t };
  const opts = {
    db,
    holder: "h",
    deadline: clock.t + 600_000,
    pollMs: 5000,
    sleep: async (ms: number) => {
      clock.t += ms;
      // The alert sender runs in the same minute: the delivery is sent 20 s after it was queued.
      if (acts.includes("alert.open") && clock.t - Date.parse(run.startedAt) >= 20_000) {
        delivery.status = "sent";
        delivery.provider_id = "re-1";
      }
    },
  };
  return { run, ctx, opts, acts, finished };
}

describe("T-ALERT", () => {
  it("opens, sees the email sent and delivered, then acknowledges and resolves", async () => {
    const h = harness("delivered");
    const r = await advanceRun(tAlert, h.run, h.ctx, 900, h.opts);
    expect(r).toEqual({ status: "finished", ok: true });
    expect(h.acts).toEqual(["alert.open", "alert.close"]);
    expect(h.run.steps.map((s) => s.key)).toEqual(["open", "sent", "delivered", "ack"]);
    expect(h.run.artefacts).toMatchObject({ incident_id: 41, provider_id: "re-1" });
  });

  it("fails at once when Resend reports a bounce", async () => {
    const h = harness("bounced");
    const r = await advanceRun(tAlert, h.run, h.ctx, 900, h.opts);
    expect(r).toEqual({ status: "finished", ok: false });
    expect(h.finished[0]?.error).toBe("delivered: error");
    expect(h.run.steps.at(-1)?.detail).toBe("Resend reports bounced");
  });

  it("will not start without an email client", async () => {
    const h = harness("delivered");
    expect(await tAlert.guard({ ...h.ctx, io: { ...h.ctx.io, email: null } })).toMatch(/not configured/);
  });
});
