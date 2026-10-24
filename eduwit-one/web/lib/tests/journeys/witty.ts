import { z } from "zod";
import { waRouteProblem } from "../apps.ts";
import { Failed, type TestDef, Unsafe } from "../types.ts";
import { apps, need } from "./common.ts";
import type { JourneyIo } from "./io.ts";

// T-WITTY-TURN and T-WITTY-QUALIFY (spec §10). The turn sends a scripted WhatsApp message from the test number (one of
// Witty's trusted test numbers) to Witty's number and follows it through Chatwoot, n8n and the model to a reply. The
// qualify test runs Witty's own harness scenario in n8n under this run's tag and follows a harness phone from HOT to a
// test lead. The harness workflow is switched on only for the run and back off after it, unless it was already on
// (D-072).

const turnSchema = z.object({
  inbox: z.number(),
  conversation_id: z.number().nullable(),
  replies: z.array(
    z.object({
      reply_source: z.string().nullable(),
      sent: z.boolean().nullable(),
      latency_ms: z.number().nullable(),
      verify_errors: z.number(),
    }),
  ),
});

export const tWittyTurn: TestDef<JourneyIo> = {
  id: "T-WITTY-TURN",
  needs: ["test_rows_agreement", "test_whatsapp_number", "chatwoot"],
  guard: async (c) => {
    const a = apps(c);
    if (!a.wa) return "the test WhatsApp sender is not configured";
    if (!a.chatwoot) return "the Chatwoot token is not configured";
    const t = await c.io.seams.fact(c.run.id, "witty.trusted");
    if (t.trusted_test !== true) return "the test number is not a trusted test number in Witty (w2_trusted, is_test)";
    // WhatsApp itself must name the sender the test number and the recipient Witty, so no message reaches a student.
    return waRouteProblem(a.wa, c.identities);
  },
  steps: [
    {
      key: "send",
      title: "Send a scripted message from the test number",
      timeoutS: 30,
      act: async (c) => {
        const since = new Date(c.now() - 5000).toISOString();
        const { id } = await need(apps(c).wa, "the test WhatsApp sender").send(
          `Eduwit One test ${c.run.id}: what is the fee for an online MBA?`,
        );
        return { wa_message_id: id, since };
      },
    },
    {
      key: "inbox",
      title: "A w2_inbox row appears",
      timeoutS: 30,
      until: async (c) => {
        const t = turnSchema.parse(await c.io.seams.fact(c.run.id, "witty.turn", { since: c.artefacts.since }));
        return t.inbox >= 1 ? { done: true, detail: "received" } : { done: false, detail: "not in the inbox yet" };
      },
    },
    {
      key: "reply",
      title: "Witty replies (counselor, rewrite or fixed)",
      timeoutS: 20,
      until: async (c) => {
        const t = turnSchema.parse(await c.io.seams.fact(c.run.id, "witty.turn", { since: c.artefacts.since }));
        const r = t.replies.find((x) => x.sent !== false);
        return r
          ? { done: true, detail: `${r.reply_source ?? "reply"} in ${r.latency_ms ?? "?"} ms` }
          : { done: false, detail: "no reply yet" };
      },
    },
    {
      key: "verified",
      title: "The reply has no verify_errors",
      timeoutS: 5,
      until: async (c) => {
        const t = turnSchema.parse(await c.io.seams.fact(c.run.id, "witty.turn", { since: c.artefacts.since }));
        const r = t.replies.find((x) => x.sent !== false);
        if (!r) throw new Failed("the reply is gone");
        if (r.verify_errors > 0) throw new Failed(`the reply has ${r.verify_errors} verify error(s)`);
        return { done: true, detail: "no verify errors" };
      },
    },
    {
      key: "chatwoot",
      title: "Chatwoot shows the outgoing message",
      timeoutS: 60,
      until: async (c) => {
        // Witty may store the conversation id after the inbox row, so it is read here, not kept from the inbox step.
        const { conversation_id: id } = turnSchema.parse(
          await c.io.seams.fact(c.run.id, "witty.turn", { since: c.artefacts.since }),
        );
        if (id === null) return { done: false, detail: "Witty has not recorded the Chatwoot conversation yet" };
        const since = Math.floor(Date.parse(String(c.artefacts.since)) / 1000);
        const n = await need(apps(c).chatwoot, "the Chatwoot token").outgoingSince(id, since);
        return n >= 1 ? { done: true, detail: `${n} outgoing` } : { done: false, detail: "no outgoing message yet" };
      },
    },
  ],
};

const harnessRun = z.object({
  found: z.boolean(),
  summary: z.object({ passed: z.coerce.number().optional(), failed: z.coerce.number().optional() }).nullish(),
});
const qualified = z.object({
  phones: z.number(),
  hot: z.number(),
  outbox_sent: z.number(),
  leads: z.array(z.object({ id: z.number(), is_test: z.boolean(), lead_source: z.string().nullable() })),
});

export const tWittyQualify: TestDef<JourneyIo> = {
  id: "T-WITTY-QUALIFY",
  needs: ["test_rows_agreement", "n8n_api"],
  guard: async (c) => (apps(c).harness ? null : "the n8n API key or the harness settings are not configured"),
  steps: [
    {
      key: "start",
      title: "Switch the harness on and start the scenario",
      timeoutS: 60,
      act: async (c) => {
        const harness = need(apps(c).harness, "the n8n harness");
        const wasActive = await harness.active();
        if (!wasActive) await harness.setActive(true);
        const runTag = `one-${c.run.id}`;
        try {
          const { accepted } = await harness.start(runTag);
          return { run_tag: runTag, harness_switched_on: !wasActive, harness_accepted: accepted };
        } catch (e) {
          // The cleanup only sees what the act returned, so a failed start switches the harness off here (D-072).
          if (!wasActive) await harness.setActive(false).catch(() => undefined);
          throw e;
        }
      },
    },
    {
      key: "finished",
      title: "The harness run is recorded (w2_test_runs)",
      timeoutS: 1200,
      until: async (c) => {
        const r = harnessRun.parse(await c.io.seams.fact(c.run.id, "witty.harness_run"));
        if (!r.found) return { done: false, detail: "the harness is still running" };
        if ((r.summary?.failed ?? 0) > 0) throw new Failed(`the harness reports ${r.summary?.failed} failed check(s)`);
        return { done: true, detail: `${r.summary?.passed ?? 0} passed` };
      },
    },
    {
      key: "hot",
      title: "A harness phone is classified HOT",
      timeoutS: 60,
      until: async (c) => {
        const q = qualified.parse(await c.io.seams.fact(c.run.id, "witty.qualified", { since: c.run.startedAt }));
        if (q.phones === 0) throw new Failed("the harness run names no harness phone");
        return q.hot >= 1 ? { done: true, detail: `${q.hot} HOT` } : { done: false, detail: "none HOT yet" };
      },
    },
    {
      key: "outbox",
      title: "Its w2_outbox row is sent",
      timeoutS: 120,
      until: async (c) => {
        const q = qualified.parse(await c.io.seams.fact(c.run.id, "witty.qualified", { since: c.run.startedAt }));
        return q.outbox_sent >= 1 ? { done: true, detail: "sent" } : { done: false, detail: "not sent yet" };
      },
    },
    {
      key: "lead",
      title: "A student_leads row from the harness, with lead_status and is_test",
      timeoutS: 120,
      until: async (c) => {
        const q = qualified.parse(await c.io.seams.fact(c.run.id, "witty.qualified", { since: c.run.startedAt }));
        if (q.leads.some((l) => !l.is_test)) throw new Unsafe("a harness lead is not marked is_test");
        return q.leads.length >= 1
          ? { done: true, detail: `${q.leads.length} test lead(s)` }
          : { done: false, detail: "no lead yet" };
      },
    },
  ],
  cleanup: async (c) => {
    if (c.artefacts.harness_switched_on === true) await apps(c).harness?.setActive(false);
  },
};
