import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import type { EmailClient } from "../../clients/email.ts";
import type { B2bApi, Harness, RunnerApi, TestApps } from "../apps.ts";
import { advanceRun } from "../runner.ts";
import type { Identities, Run, TestContext, TestDef } from "../types.ts";
import { tAlert } from "./alert.ts";
import { tB2bIntake, tB2bPush } from "./b2b.ts";
import { journeys } from "./index.ts";
import type { JourneyIo } from "./io.ts";
import { tB2cNurture, tHandoff } from "./spark.ts";
import { tWittyQualify, tWittyTurn } from "./witty.ts";

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
  whatsapp_number: "15550001111",
  mailbox: null,
  website_preview_url: null,
  spark_test_user_email: null,
  partner_slug: "test-partner",
  creator_referral_code: null,
  run_phone_prefix: "9100009",
  runner_email: "tests@eduwit.in",
  spark_test_journey_id: "4",
  whatsapp_phone_number_id: "1234",
  witty_number: "919000011111",
};

const T0 = Date.parse("2026-10-23T05:00:00Z");
type Facts = Record<string, (args: Record<string, unknown>) => Record<string, unknown>>;
type World = {
  facts?: Facts;
  acts?: Facts;
  apps?: Partial<TestApps>;
  email?: EmailClient;
  /** Called after each simulated wait with the seconds since the run began. */
  onTick?: (s: number) => void;
};

/** Runs a journey to its end against a simulated world: seams and app doors answer from the world's functions. */
async function drive(def: TestDef<JourneyIo>, w: World, ids: Identities = identities) {
  const clock = { t: T0 };
  const calls: string[] = [];
  const answer = (table: Facts | undefined, kind: string, args: Record<string, unknown>) => {
    const f = table?.[kind];
    if (!f) throw new Error(`the world has no ${kind}`);
    return f(args);
  };
  const io: JourneyIo = {
    seams: {
      fact: async (_run, kind, args = {}) => {
        calls.push(`fact:${kind}`);
        return answer(w.facts, kind, args);
      },
      act: async (_run, kind, args = {}) => {
        calls.push(`act:${kind}`);
        return answer(w.acts, kind, args);
      },
    },
    email: w.email ?? null,
    apps: () => ({ b2b: null, runner: null, harness: null, wa: null, chatwoot: null, ...w.apps }),
  };
  const run: Run = {
    id: 5,
    testId: def.id,
    startedAt: new Date(T0).toISOString(),
    steps: [],
    artefacts: {},
    state: { step: 0, stepStartedAt: new Date(T0).toISOString(), acted: false },
  };
  const finished: Array<{ ok: boolean; error: string | null }> = [];
  const db = {
    testsState: async () => ({ tests: [], identities: ids, runs: [] }),
    runStart: async () => null,
    runSave: async () => undefined,
    runFinish: async (_r: Run, ok: boolean, error: string | null) => {
      finished.push({ ok, error });
    },
  };
  const ctx: TestContext<JourneyIo> = { run, artefacts: run.artefacts, identities: ids, io, now: () => clock.t };
  const guard = await def.guard(ctx);
  if (guard) return { guard, run, calls, finished, result: null };
  const result = await advanceRun(def, run, ctx, 7200, {
    db,
    holder: "h",
    deadline: T0 + 100_000_000,
    pollMs: 5000,
    sleep: async (ms: number) => {
      clock.t += ms;
      w.onTick?.((clock.t - T0) / 1000);
    },
  });
  return { guard: null, run, calls, finished, result };
}

/** A B2B intake that records what it was sent. */
function fakeB2b(leadId = 77) {
  const sent: Array<{ body: Record<string, unknown>; key: string }> = [];
  const events: Array<{ slug: string; event: Record<string, unknown> }> = [];
  const api: B2bApi = {
    intake: async (body, key) => {
      sent.push({ body, key });
      return { status: 201, leadId, isTest: true, action: "created", routing: "waiting" };
    },
    partnerEvent: async (slug, event) => {
      events.push({ slug, event });
      return { status: 200 };
    },
  };
  return { api, sent, events };
}

/** The test runner login, answering per function. */
function fakeRunner(answers: Record<string, (args: Record<string, unknown>) => unknown>) {
  const calls: string[] = [];
  const api: RunnerApi = {
    rpc: async (schema, fn, args) => {
      calls.push(`${schema}.${fn}`);
      const f = answers[`${schema}.${fn}`];
      if (!f) throw new Error(`the runner cannot call ${schema}.${fn} here`);
      return f(args);
    },
  };
  return { api, calls };
}

const allocate = { "phone.allocate": () => ({ phone: "910000900005", reset: {} }) };
const testLead = { lead: () => ({ id: 77, is_test: true, lead_status: "new" }) };

describe("the lead tests", () => {
  it("never post a lead on a phone the database did not hand out as a harness phone", async () => {
    const b2b = fakeB2b();
    const d = await drive(tB2bIntake, {
      acts: { "phone.allocate": () => ({ phone: "919812345678" }) },
      apps: { b2b: b2b.api, runner: fakeRunner({}).api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "post: refused" }]);
    expect(b2b.sent).toHaveLength(0);
  });

  it("refuse to start with a run prefix outside 9100009", async () => {
    const d = await drive(
      tB2bIntake,
      { apps: { b2b: fakeB2b().api, runner: fakeRunner({}).api } },
      { ...identities, run_phone_prefix: "9198" },
    );
    expect(d.guard).toMatch(/run_phone_prefix/);
  });

  it("T-B2B-INTAKE: posts a test lead, sees it held and kept out of the command centre", async () => {
    const b2b = fakeB2b();
    const runner = fakeRunner({ "b2b.command_center": () => ({ kpis: { leads_today: 10 } }) });
    const d = await drive(tB2bIntake, {
      acts: allocate,
      facts: {
        ...testLead,
        "b2b.routing": () => ({ allocations: [] }),
        "b2b.real_leads_today": () => ({ leads_today: 10 }),
      },
      apps: { b2b: b2b.api, runner: runner.api },
    });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(d.run.steps.map((s) => s.key)).toEqual(["post", "lead", "held", "no_leak"]);
    const sent = b2b.sent[0];
    expect(sent?.key).toBe("eduwit-one:T-B2B-INTAKE:5");
    expect((sent?.body.lead as Record<string, unknown>).phone).toBe("+910000900005");
    // Only the keys the intake contract accepts (an unknown key is a 400).
    const allowed = ["lead", "source", "channel", "campaign", "utm", "click_ids", "landing_url", "consent"];
    allowed.push("phone_verified", "occurred_at", "route", "b2c_lane");
    expect(Object.keys(sent?.body ?? {}).every((k) => allowed.includes(k))).toBe(true);
    expect(d.run.artefacts).toMatchObject({ lead_id: 77 });
    expect(JSON.stringify(d.run.artefacts)).not.toContain("910000900005");
  });

  it("T-B2B-INTAKE: fails when B2B routes the test lead by itself", async () => {
    const d = await drive(tB2bIntake, {
      acts: allocate,
      facts: {
        ...testLead,
        "b2b.routing": () => ({
          allocations: [
            { id: 1, status: "queued", destination_type: "partner", partner: "x", origin: "auto", reference: null },
          ],
        }),
      },
      apps: { b2b: fakeB2b().api, runner: fakeRunner({}).api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "held: error" }]);
  });

  it("T-B2B-INTAKE: fails when the command centre counts more leads than are real", async () => {
    const d = await drive(tB2bIntake, {
      acts: allocate,
      facts: {
        ...testLead,
        "b2b.routing": () => ({ allocations: [] }),
        "b2b.real_leads_today": () => ({ leads_today: 10 }),
      },
      apps: {
        b2b: fakeB2b().api,
        runner: fakeRunner({ "b2b.command_center": () => ({ kpis: { leads_today: 11 } }) }).api,
      },
    });
    expect(d.finished).toEqual([{ ok: false, error: "no_leak: error" }]);
    expect(d.run.steps.at(-1)?.detail).toMatch(/test leads leak in/);
  });

  it("T-B2B-PUSH: will not start while another partner has a test endpoint", async () => {
    const d = await drive(tB2bPush, {
      facts: { "b2b.sandbox_partners": () => ({ slugs: ["other", "test-partner"] }) },
      apps: { b2b: fakeB2b().api, runner: fakeRunner({}).api },
    });
    expect(d.guard).toMatch(/not the test partner/);
  });

  it("T-B2B-PUSH: routes to the sandbox, sees the push, plays the partner's contacted event back", async () => {
    const b2b = fakeB2b();
    let routed = false;
    const runner = fakeRunner({
      "b2b.route_test_lead": (a) => {
        expect(a).toMatchObject({ p_lead_id: 77, p_target: "partner_sandbox" });
        routed = true;
        return { ok: true };
      },
    });
    const d = await drive(tB2bPush, {
      acts: allocate,
      facts: {
        ...testLead,
        "b2b.sandbox_partners": () => ({ slugs: ["test-partner"] }),
        "b2b.routing": () => ({
          allocations: routed
            ? [
                {
                  id: 9,
                  status: "pushed",
                  destination_type: "partner",
                  partner: "test-partner",
                  origin: "sandbox",
                  reference: "EDW-9",
                },
              ]
            : [],
        }),
        "b2b.push": () => ({ status_code: 200, sandbox: true, outcome: "accepted", to_test_endpoint: true }),
        "b2b.activity": () =>
          b2b.events.length ? { calls: 1, first_contacted_at: "2026-10-23T05:02:00Z" } : { calls: 0 },
      },
      apps: { b2b: b2b.api, runner: runner.api },
    });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(b2b.events[0]).toMatchObject({ slug: "test-partner", event: { type: "contacted", reference: "EDW-9" } });
    expect(b2b.events[0]?.event.event_id).toBe("eduwit-one-5-contacted");
  });

  it("T-B2B-PUSH: stops if the push reached another partner", async () => {
    const d = await drive(tB2bPush, {
      acts: allocate,
      facts: {
        ...testLead,
        "b2b.sandbox_partners": () => ({ slugs: ["test-partner"] }),
        "b2b.routing": () => ({
          allocations: [
            {
              id: 9,
              status: "pushed",
              destination_type: "partner",
              partner: "real-uni",
              origin: "sandbox",
              reference: "EDW-9",
            },
          ],
        }),
      },
      apps: { b2b: fakeB2b().api, runner: fakeRunner({ "b2b.route_test_lead": () => ({}) }).api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "route: refused" }]);
  });
});

const sparkFacts = (over: Facts = {}): Facts => ({
  ...testLead,
  "b2b.delivered": () => ({ statuses: ["delivered"] }),
  "b2c.record": () => ({ found: true, held_by_b2c: true, is_test: true }),
  ...over,
});
const handoffRunner = (over: Record<string, (a: Record<string, unknown>) => unknown> = {}) =>
  fakeRunner({
    "b2b.route_test_lead": () => ({
      destination: "in_house",
      allocation_id: 12,
      reference: "EDW-12",
      b2c_lane: "sales",
    }),
    "b2c.call_start": () => ({ call_id: 31, mode: "manual", number: "910000900005" }),
    "b2c.call_log": () => ({ ok: true }),
    "b2c.analytics_run": () => ({ rows: [{ handoffs: 3 }] }),
    ...over,
  });

describe("the Spark tests", () => {
  it("T-HANDOFF: hands off, logs a manual call, sees it written back, and no leak into analytics", async () => {
    const runner = handoffRunner();
    const d = await drive(tHandoff, {
      acts: allocate,
      facts: sparkFacts({
        "b2c.writeback": () => ({ outbox: ["applied"], writes: [{ status: "applied", http_status: 200 }] }),
        "b2c.real_handoffs": () => ({ real: 3, lead_in_facts: true, lead_fact_is_test: true }),
      }),
      apps: { b2b: fakeB2b().api, runner: runner.api },
    });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(runner.calls).toEqual(["b2b.route_test_lead", "b2c.call_start", "b2c.call_log", "b2c.analytics_run"]);
    expect(JSON.stringify(d.run.artefacts)).not.toContain("910000900005");
  });

  it("T-HANDOFF: refuses to log when Spark would place a real call", async () => {
    const runner = handoffRunner({ "b2c.call_start": () => ({ call_id: 31, mode: "bridge" }) });
    const d = await drive(tHandoff, {
      acts: allocate,
      facts: sparkFacts(),
      apps: { b2b: fakeB2b().api, runner: runner.api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "call: refused" }]);
    expect(runner.calls).not.toContain("b2c.call_log");
  });

  it("T-HANDOFF: stops when Spark takes the test lead as real", async () => {
    const d = await drive(tHandoff, {
      acts: allocate,
      facts: sparkFacts({ "b2c.record": () => ({ found: true, held_by_b2c: true, is_test: false }) }),
      apps: { b2b: fakeB2b().api, runner: handoffRunner().api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "held: refused" }]);
  });

  it("T-HANDOFF: fails when analytics count the test lead among real hand-offs", async () => {
    const d = await drive(tHandoff, {
      acts: allocate,
      facts: sparkFacts({
        "b2c.writeback": () => ({ outbox: ["applied"], writes: [{ status: "applied", http_status: 200 }] }),
        "b2c.real_handoffs": () => ({ real: 3, lead_in_facts: true, lead_fact_is_test: true }),
      }),
      apps: {
        b2b: fakeB2b().api,
        runner: handoffRunner({ "b2c.analytics_run": () => ({ rows: [{ handoffs: 4 }] }) }).api,
      },
    });
    expect(d.finished).toEqual([{ ok: false, error: "no_leak: error" }]);
  });

  const journeyFacts = (sends: Record<string, number>) =>
    sparkFacts({
      "b2c.journey": () => ({
        run: { step_idx: 1, status: "running", is_test: true },
        sends: 1,
        sends_to_lead_phone: 1,
        sends_live: 0,
        ...sends,
      }),
    });

  it("T-B2C-NURTURE: runs the test journey and sees one dry-run send to the test phone", async () => {
    const runner = handoffRunner({
      "b2c.journey_test": (a) => {
        expect(a).toEqual({ p_id: 4, p_lead: 77 });
        return 55;
      },
    });
    const d = await drive(tB2cNurture, {
      acts: allocate,
      facts: journeyFacts({}),
      apps: { b2b: fakeB2b().api, runner: runner.api },
    });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(d.run.artefacts).toMatchObject({ journey_run_id: 55 });
  });

  it.each([
    [{ sends_live: 1 }, /went out live/],
    [{ sends: 2 }, /another address/],
  ])("T-B2C-NURTURE: stops on %o", async (sends, why) => {
    const runner = handoffRunner({ "b2c.journey_test": () => 55 });
    const d = await drive(tB2cNurture, {
      acts: allocate,
      facts: journeyFacts(sends),
      apps: { b2b: fakeB2b().api, runner: runner.api },
    });
    expect(d.finished).toEqual([{ ok: false, error: "only_test: refused" }]);
    expect(d.run.steps.at(-1)?.detail).toMatch(why);
  });
});

describe("the Witty tests", () => {
  const turn = (replies: unknown[]) => () => ({ inbox: 1, conversation_id: 812, replies });

  it("T-WITTY-TURN: will not send from a number Witty does not trust as a test number", async () => {
    const d = await drive(tWittyTurn, {
      facts: { "witty.trusted": () => ({ trusted_test: false }) },
      apps: { wa: { send: async () => ({ id: "x" }) }, chatwoot: { outgoingSince: async () => 1 } },
    });
    expect(d.guard).toMatch(/not a trusted test number/);
  });

  it("T-WITTY-TURN: sends, sees the inbox row, the reply and Chatwoot's outgoing message", async () => {
    const sent: string[] = [];
    const d = await drive(tWittyTurn, {
      facts: {
        "witty.trusted": () => ({ trusted_test: true }),
        "witty.turn": turn([{ reply_source: "counselor", sent: true, latency_ms: 4200, verify_errors: 0 }]),
      },
      apps: {
        wa: {
          send: async (text) => {
            sent.push(text);
            return { id: "wamid.1" };
          },
        },
        chatwoot: { outgoingSince: async (id) => (id === 812 ? 1 : 0) },
      },
    });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(sent[0]).toMatch(/^Eduwit One test 5:/);
  });

  it("T-WITTY-TURN: fails on a reply with verify errors", async () => {
    const d = await drive(tWittyTurn, {
      facts: {
        "witty.trusted": () => ({ trusted_test: true }),
        "witty.turn": turn([{ reply_source: "counselor", sent: true, latency_ms: 4200, verify_errors: 2 }]),
      },
      apps: { wa: { send: async () => ({ id: "wamid.1" }) }, chatwoot: { outgoingSince: async () => 1 } },
    });
    expect(d.finished).toEqual([{ ok: false, error: "verified: error" }]);
  });

  function fakeHarness(active: boolean) {
    const state = { active, switched: [] as boolean[], tags: [] as string[] };
    const harness: Harness = {
      active: async () => state.active,
      setActive: async (on) => {
        state.active = on;
        state.switched.push(on);
      },
      start: async (tag) => {
        state.tags.push(tag);
        return { accepted: true };
      },
    };
    return { harness, state };
  }
  const qualifyFacts = (failed = 0): Facts => ({
    "witty.harness_run": () => ({ found: true, summary: { passed: 4, failed } }),
    "witty.qualified": () => ({
      phones: 1,
      hot: 1,
      outbox_sent: 1,
      leads: [{ id: 90, is_test: true, lead_source: "witty" }],
    }),
  });

  it("T-WITTY-QUALIFY: switches the harness on for the run and off after it", async () => {
    const h = fakeHarness(false);
    const d = await drive(tWittyQualify, { facts: qualifyFacts(), apps: { harness: h.harness } });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(h.state.tags).toEqual(["one-5"]);
    expect(h.state.switched).toEqual([true, false]);
  });

  it("T-WITTY-QUALIFY: switches it off after a failure too, and leaves alone a harness someone else switched on", async () => {
    const off = fakeHarness(false);
    const failed = await drive(tWittyQualify, { facts: qualifyFacts(1), apps: { harness: off.harness } });
    expect(failed.finished).toEqual([{ ok: false, error: "finished: error" }]);
    expect(off.state.switched).toEqual([true, false]);
    const on = fakeHarness(true);
    await drive(tWittyQualify, { facts: qualifyFacts(), apps: { harness: on.harness } });
    expect(on.state.switched).toEqual([]);
  });

  it("T-WITTY-QUALIFY: stops on a harness lead that is not a test lead", async () => {
    const facts = qualifyFacts();
    facts["witty.qualified"] = () => ({
      phones: 1,
      hot: 1,
      outbox_sent: 1,
      leads: [{ id: 90, is_test: false, lead_source: "witty" }],
    });
    const d = await drive(tWittyQualify, { facts, apps: { harness: fakeHarness(false).harness } });
    expect(d.finished).toEqual([{ ok: false, error: "lead: refused" }]);
  });
});

describe("T-ALERT", () => {
  function world(lastEvent: string) {
    const delivery = { status: "pending", provider_id: null as string | null, attempts: 0 };
    const acts: string[] = [];
    return {
      acts,
      w: {
        facts: { "alert.delivery": () => delivery },
        acts: {
          "alert.open": () => {
            acts.push("alert.open");
            return { incident_id: 41, delivery_id: 9, recipient: "resend_test_address" };
          },
          "alert.close": () => {
            acts.push("alert.close");
            return { closed: true };
          },
        },
        // The alert sender runs in the same minute: the delivery is sent 20 s after it was queued.
        onTick: (s: number) => {
          if (acts.includes("alert.open") && s >= 20) {
            delivery.status = "sent";
            delivery.provider_id = "re-1";
          }
        },
      },
      email: { send: async () => ({ id: "re-1" }), status: async () => ({ lastEvent }) } satisfies EmailClient,
    };
  }

  it("opens, sees the email sent and delivered, then acknowledges and resolves", async () => {
    const x = world("delivered");
    const d = await drive(tAlert, { ...x.w, email: x.email });
    expect(d.result).toEqual({ status: "finished", ok: true });
    expect(x.acts).toEqual(["alert.open", "alert.close"]);
    expect(d.run.steps.map((s) => s.key)).toEqual(["open", "sent", "delivered", "ack"]);
    expect(d.run.artefacts).toMatchObject({ incident_id: 41, provider_id: "re-1" });
  });

  it("fails at once when Resend reports a bounce", async () => {
    const x = world("bounced");
    const d = await drive(tAlert, { ...x.w, email: x.email });
    expect(d.finished[0]?.error).toBe("delivered: error");
    expect(d.run.steps.at(-1)?.detail).toBe("Resend reports bounced");
  });

  it("will not start without an email client", async () => {
    const d = await drive(tAlert, {});
    expect(d.guard).toMatch(/not configured/);
  });
});
