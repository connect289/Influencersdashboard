import { z } from "zod";
import { Failed, type TestDef, Unsafe } from "../types.ts";
import {
  apps,
  type Ctx,
  deliveredToSpark,
  handToSpark,
  heldBySpark,
  istDay,
  leadGuard,
  leadOf,
  need,
  postTestLead,
} from "./common.ts";
import type { JourneyIo } from "./io.ts";

// T-HANDOFF and T-B2C-NURTURE (spec §10): a test lead handed from B2B to Spark with B2B's own test hand-off, then, as
// the test runner (a Spark admin), a logged call that must come back to B2B, or a test journey whose sends must stay
// dry runs to the lead's own test phone. Spark never dials for a test lead: b2c.telephony_provider gives it the mock
// provider when a real one is set, and a manual call when none is. The call step accepts only those two answers.

const callStart = z.object({ call_id: z.number(), mode: z.string(), provider: z.string().nullish() });
const analytics = z.object({ rows: z.array(z.object({ handoffs: z.coerce.number().nullable().optional() })) });

export const tHandoff: TestDef<JourneyIo> = {
  id: "T-HANDOFF",
  needs: ["test_rows_agreement", "test_b2b_intake_key", "test_runner_user"],
  guard: async (c) => leadGuard(c),
  steps: [
    {
      key: "post",
      title: "Post a test lead through the intake API",
      timeoutS: 30,
      act: (c) => postTestLead(c, { route: "auto", partnerShare: false }),
    },
    { key: "handoff", title: "Hand it to Spark with B2B's test hand-off", timeoutS: 30, act: handToSpark },
    { key: "delivered", title: "integration_outbox delivers it to Spark", timeoutS: 300, until: deliveredToSpark },
    { key: "held", title: "Spark holds it (held_by_b2c, is_test)", timeoutS: 300, until: heldBySpark },
    {
      key: "call",
      title: "Log a call on it in Spark, as the test runner",
      timeoutS: 60,
      act: async (c) => {
        const runner = need(apps(c).runner, "the test runner login");
        const at = new Date(c.now()).toISOString();
        const start = callStart.parse(await runner.rpc("b2c", "call_start", { p_lead: leadOf(c) }));
        // The mock provider ends the call and logs it itself; Spark refuses a log while it is going on.
        if (start.mode === "bridge" && start.provider === "mock") return { call_id: start.call_id, call_at: at };
        if (start.mode !== "manual") throw new Unsafe(`Spark answered a ${start.mode} call for a test lead`);
        await runner.rpc("b2c", "call_log", {
          p_call: start.call_id,
          p_outcome: "connected",
          p_duration_s: 60,
          p_note: `Eduwit One synthetic test ${c.run.testId}, run ${c.run.id}`,
          p_next_due: new Date(c.now() + 86_400_000).toISOString(),
        });
        return { call_id: start.call_id, call_at: at };
      },
    },
    {
      key: "writeback",
      title: "Spark's outbox applies it and B2B records the write (2xx)",
      timeoutS: 1800,
      until: async (c) => {
        const w = z
          .object({
            outbox: z.array(z.string()),
            writes: z.array(z.object({ status: z.string(), http_status: z.number().nullable() })),
          })
          .parse(await c.io.seams.fact(c.run.id, "b2c.writeback", { lead_id: leadOf(c), since: c.artefacts.call_at }));
        if (w.outbox.includes("refused")) throw new Failed("B2B refused Spark's activity");
        const applied = w.writes.find((x) => x.status === "applied");
        return w.outbox.includes("applied") && applied && (applied.http_status ?? 200) < 300
          ? { done: true, detail: "applied in B2B" }
          : { done: false, detail: `outbox ${w.outbox.join(", ") || "empty"}; writes ${w.writes.length}` };
      },
    },
    {
      key: "no_leak",
      title: "Spark's analytics keep it out of real hand-offs",
      timeoutS: 1800,
      until: async (c) => {
        const facts = async () => await c.io.seams.fact(c.run.id, "b2c.real_handoffs", { lead_id: leadOf(c) });
        const before = await facts();
        // Until Spark's fact table has the lead, the check proves nothing.
        if (before.lead_in_facts !== true) return { done: false, detail: "waiting for Spark's analytics refresh" };
        if (before.lead_fact_is_test !== true) throw new Unsafe("Spark's analytics hold the test lead as real");
        const day = istDay(c.now());
        const r = analytics.parse(
          await need(apps(c).runner, "the test runner login").rpc("b2c", "analytics_run", {
            spec: { metrics: ["handoffs"], from: day, to: day, test: false },
          }),
        );
        const shown = r.rows.reduce((n, x) => n + (x.handoffs ?? 0), 0);
        const after = Number((await facts()).real);
        if (shown > after)
          throw new Failed(`analytics show ${shown} hand-offs today, real ones are ${after}: test leads leak in`);
        return shown >= Number(before.real)
          ? { done: true, detail: `${shown} real hand-offs today, as counted directly` }
          : { done: false, detail: `analytics show ${shown}, real ${String(before.real)}` };
      },
    },
  ],
};

const journeySchema = z.object({
  run: z.object({ step_idx: z.number(), status: z.string(), is_test: z.boolean().nullable() }).nullable(),
  sends: z.number(),
  sends_to_lead_phone: z.number(),
  sends_live: z.number(),
});

/** The test's own journey run and the sends since it was enrolled (Spark's other journeys may enrol the lead too). */
const journeyArgs = (c: Ctx) => ({
  lead_id: leadOf(c),
  journey_run_id: c.artefacts.journey_run_id,
  since: c.artefacts.enrolled_at,
});

export const tB2cNurture: TestDef<JourneyIo> = {
  id: "T-B2C-NURTURE",
  needs: ["test_rows_agreement", "test_b2b_intake_key", "test_runner_user", "test_spark_journey"],
  guard: async (c) =>
    leadGuard(c) ?? (c.identities.spark_test_journey_id ? null : "test_identities.spark_test_journey_id is not set"),
  steps: [
    {
      key: "post",
      title: "Post a test lead through the intake API",
      timeoutS: 30,
      act: (c) => postTestLead(c, { route: "auto", partnerShare: false }),
    },
    { key: "handoff", title: "Hand it to Spark with B2B's test hand-off", timeoutS: 30, act: handToSpark },
    { key: "held", title: "Spark holds it", timeoutS: 600, until: heldBySpark },
    {
      key: "enrol",
      title: "Run the test journey for it, as the test runner",
      timeoutS: 30,
      act: async (c) => {
        const journey = Number(need(c.identities.spark_test_journey_id, "test_identities.spark_test_journey_id"));
        const run = z.coerce.number().parse(
          await need(apps(c).runner, "the test runner login").rpc("b2c", "journey_test", {
            p_id: journey,
            p_lead: leadOf(c),
          }),
        );
        return { journey_run_id: run, enrolled_at: new Date(c.now()).toISOString() };
      },
    },
    {
      key: "advanced",
      title: "The journey run advances a step",
      timeoutS: 900,
      until: async (c) => {
        const j = journeySchema.parse(await c.io.seams.fact(c.run.id, "b2c.journey", journeyArgs(c)));
        if (!j.run) return { done: false, detail: "no journey run yet" };
        if (j.run.is_test === false) throw new Unsafe("the journey run is not a test run");
        if (j.run.status === "exited") throw new Failed("the journey run exited");
        return j.run.step_idx >= 1 || j.run.status === "done"
          ? { done: true, detail: `step ${j.run.step_idx}, ${j.run.status}` }
          : { done: false, detail: `step ${j.run.step_idx}, ${j.run.status}` };
      },
    },
    {
      key: "queued",
      title: "A send to its test phone is queued (a dry run)",
      timeoutS: 900,
      until: async (c) => {
        const j = journeySchema.parse(await c.io.seams.fact(c.run.id, "b2c.journey", journeyArgs(c)));
        return j.sends_to_lead_phone >= 1
          ? { done: true, detail: `${j.sends_to_lead_phone} queued to the test phone` }
          : { done: false, detail: `${j.sends} sends queued` };
      },
    },
    {
      key: "only_test",
      title: "Nothing is queued for any other address",
      timeoutS: 30,
      until: async (c) => {
        const j = journeySchema.parse(await c.io.seams.fact(c.run.id, "b2c.journey", journeyArgs(c)));
        if (j.sends_live > 0) throw new Unsafe(`${j.sends_live} send(s) went out live for a test lead`);
        if (j.sends > j.sends_to_lead_phone)
          throw new Unsafe(`${j.sends - j.sends_to_lead_phone} send(s) queued for another address`);
        return { done: true, detail: "dry runs to the test phone only" };
      },
    },
  ],
};
