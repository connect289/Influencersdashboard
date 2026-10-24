import { z } from "zod";
import { type TestDef, Unsafe } from "../types.ts";
import { allocations, apps, leadGuard, leadOf, leadStored, need, postTestLead, stepAge } from "./common.ts";
import type { JourneyIo } from "./io.ts";

// T-B2B-INTAKE and T-B2B-PUSH (spec §10). Both post a test lead through B2B's intake API with the intake-only key. The
// first proves B2B keeps it out of routing and out of its own numbers; the second routes it to the test partner's
// sandbox as the test runner and plays the partner's side back with a signed event.

/** B2B routes test leads only by hand; give its minute router this long to prove it left the lead alone. */
const HELD_AFTER_S = 50;

const commandCentre = z.object({ kpis: z.object({ leads_today: z.number() }) });

export const tB2bIntake: TestDef<JourneyIo> = {
  id: "T-B2B-INTAKE",
  needs: ["test_rows_agreement", "test_b2b_intake_key", "test_runner_user"],
  guard: async (c) => leadGuard(c),
  steps: [
    {
      key: "post",
      title: "Post a test lead through the intake API",
      timeoutS: 30,
      act: (c) => postTestLead(c, { route: "auto", partnerShare: true }),
    },
    { key: "lead", title: "The lead is stored with is_test", timeoutS: 60, until: leadStored },
    {
      key: "held",
      title: "B2B routes nothing for it",
      timeoutS: 60,
      until: async (c) => {
        const a = await allocations(c);
        if (a.length > 0) throw new Error(`B2B routed the test lead by itself (${a[0]?.destination_type ?? "?"})`);
        return stepAge(c) >= HELD_AFTER_S
          ? { done: true, detail: `no allocation after ${HELD_AFTER_S} s` }
          : { done: false, detail: "watching the router" };
      },
    },
    {
      key: "no_leak",
      title: "B2B's command centre does not count it",
      timeoutS: 60,
      until: async (c) => {
        const count = async () =>
          Number((await c.io.seams.fact(c.run.id, "b2b.real_leads_today")).leads_today ?? Number.NaN);
        const before = await count();
        const shown = commandCentre.parse(
          await need(apps(c).runner, "the test runner login").rpc("b2b", "command_center", {}),
        ).kpis.leads_today;
        const after = await count();
        if (shown > after) {
          throw new Error(`the command centre shows ${shown} leads today, real leads are ${after}: test leads leak in`);
        }
        return shown >= before
          ? { done: true, detail: `${shown} real leads today, as counted directly` }
          : { done: false, detail: `the command centre shows ${shown}, real leads ${before}` };
      },
    },
  ],
};

export const tB2bPush: TestDef<JourneyIo> = {
  id: "T-B2B-PUSH",
  needs: ["test_rows_agreement", "test_b2b_intake_key", "test_partner", "test_runner_user"],
  guard: async (c) => {
    const base = leadGuard(c);
    if (base) return base;
    const slug = c.identities.partner_slug;
    if (!slug) return "test_identities.partner_slug is not set";
    // A sandbox push goes to whichever open partner has a test endpoint; only run while that can only be ours.
    const { slugs } = z
      .object({ slugs: z.array(z.string()) })
      .parse(await c.io.seams.fact(c.run.id, "b2b.sandbox_partners"));
    if (slugs.length !== 1 || slugs[0] !== slug) {
      return `partners with a test endpoint: ${slugs.length}; a push could reach one that is not the test partner`;
    }
    return null;
  },
  steps: [
    {
      key: "post",
      title: "Post a test lead through the intake API",
      timeoutS: 30,
      act: (c) => postTestLead(c, { route: "auto", partnerShare: true }),
    },
    {
      key: "route",
      title: "Route it to the partner sandbox, as the test runner",
      timeoutS: 30,
      act: async (c) => {
        await need(apps(c).runner, "the test runner login").rpc("b2b", "route_test_lead", {
          p_lead_id: leadOf(c),
          p_target: "partner_sandbox",
          p_reason: `Eduwit One synthetic test ${c.run.testId}`,
        });
        return undefined;
      },
      until: async (c) => {
        const a = (await allocations(c)).find((x) => x.destination_type === "partner");
        if (!a) return { done: false, detail: "no partner allocation yet" };
        if (a.partner !== c.identities.partner_slug) throw new Unsafe("the sandbox push went to another partner");
        if (!a.reference) return { done: false, detail: "allocated, no reference yet" };
        return {
          done: true,
          detail: `allocated (${a.origin ?? "?"})`,
          artefacts: { allocation_id: a.id, reference: a.reference },
        };
      },
    },
    {
      key: "pushed",
      title: "Pushed to the test partner's sandbox endpoint (2xx)",
      timeoutS: 300,
      until: async (c) => {
        const p = await c.io.seams.fact(c.run.id, "b2b.push", { lead_id: leadOf(c) });
        const code = typeof p.status_code === "number" ? p.status_code : null;
        if (code === null) return { done: false, detail: "not pushed yet" };
        if (p.to_test_endpoint !== true || p.sandbox !== true)
          throw new Unsafe("the push did not go to the sandbox endpoint");
        if (code >= 200 && code < 300) return { done: true, detail: `HTTP ${code}` };
        throw new Error(`the sandbox answered HTTP ${code}`);
      },
    },
    {
      key: "event",
      title: "Post a signed contacted event for it",
      timeoutS: 30,
      act: async (c) => {
        const reference = c.artefacts.reference;
        if (typeof reference !== "string") throw new Error("no allocation reference to report on");
        const slug = need(c.identities.partner_slug, "test_identities.partner_slug");
        const r = await need(apps(c).b2b, "the B2B intake key").partnerEvent(
          slug,
          {
            event_id: `eduwit-one-${c.run.id}-contacted`,
            type: "contacted",
            reference,
            occurred_at: new Date(c.now()).toISOString(),
            data: { connected: true, outcome: "interested", duration_sec: 60, direction: "outbound" },
          },
          c.now(),
        );
        return { event_status: r.status };
      },
    },
    {
      key: "activity",
      title: "A partner_activities call and the lead's first contact are recorded",
      timeoutS: 120,
      until: async (c) => {
        const a = await c.io.seams.fact(c.run.id, "b2b.activity", { lead_id: leadOf(c) });
        return Number(a.calls) >= 1 && a.first_contacted_at
          ? { done: true, detail: "call recorded, first contact set" }
          : {
              done: false,
              detail: `calls ${String(a.calls ?? 0)}, first contact ${a.first_contacted_at ? "set" : "not set"}`,
            };
      },
    },
  ],
};
