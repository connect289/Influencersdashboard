import { z } from "zod";
import type { TestApps } from "../apps.ts";
import { type Artefacts, type TestContext, Unsafe } from "../types.ts";
import type { JourneyIo } from "./io.ts";

// What the B2B and Spark journeys share: the test lead each starts from, and small readers for seam answers.

export type Ctx = TestContext<JourneyIo>;

/** The app doors for this run's identities. */
export const apps = (c: Ctx): TestApps => c.io.apps(c.identities);

/** A door the journey needs, or the error that fails its step. */
export function need<T>(v: T | null, what: string): T {
  if (v === null) throw new Error(`${what} is not configured`);
  return v;
}

/** Seconds since the current step began. */
export const stepAge = (c: Ctx): number => (c.now() - Date.parse(c.run.state.stepStartedAt)) / 1000;

export function leadOf(c: Ctx): number {
  const id = c.artefacts.lead_id;
  if (typeof id !== "number") throw new Error("no test lead recorded by the post step");
  return id;
}

/** The guard every lead-creating test shares: the doors it needs, and a prefix that can only give harness phones. */
export function leadGuard(c: Ctx, more: Array<keyof TestApps> = []): string | null {
  const a = apps(c);
  for (const k of ["b2b", "runner", ...more] as const) {
    if (!a[k])
      return `${k === "b2b" ? "the B2B intake key" : k === "runner" ? "the test runner login" : k} is not configured`;
  }
  if (!/^9100009\d{0,4}$/.test(c.identities.run_phone_prefix))
    return "test_identities.run_phone_prefix is not in 9100009";
  return null;
}

/**
 * Posts this run's test lead through B2B's intake API: a phone the database hands out (one.test_act phone.allocate,
 * 9100009 and five digits, so w2_is_test makes the lead is_test), a name and course that say what it is, and an
 * idempotency key per run, so a retried post never makes a second lead.
 */
export async function postTestLead(
  c: Ctx,
  opts: { route: "auto" | "hold"; partnerShare: boolean },
): Promise<Artefacts> {
  const b2b = need(apps(c).b2b, "the B2B intake key");
  const { phone } = await c.io.seams.act(c.run.id, "phone.allocate");
  if (typeof phone !== "string" || !/^9100009\d{5}$/.test(phone)) {
    throw new Unsafe("the database did not hand out a harness phone");
  }
  const at = new Date(c.now()).toISOString();
  const r = await b2b.intake(
    {
      lead: {
        full_name: "Eduwit One Test",
        phone: `+${phone}`,
        city: "Delhi",
        course: "Online MBA",
        notes: `Eduwit One synthetic test ${c.run.testId}, run ${c.run.id}`,
      },
      source: "eduwit_one_test",
      channel: "api",
      campaign: "eduwit_one_tests",
      consent: {
        sales_at: at,
        partner_share_at: opts.partnerShare ? at : null,
        marketing_at: null,
        text_version: "eduwit-one-test-v1",
      },
      phone_verified: false,
      occurred_at: at,
      route: opts.route,
    },
    `eduwit-one:${c.run.testId}:${c.run.id}`,
  );
  if (!r.isTest) throw new Unsafe("B2B did not take the lead as a test lead");
  return { lead_id: r.leadId, intake_action: r.action, intake_routing: r.routing };
}

/** The lead step every lead test shares: the seam answers only for this run's test leads. */
export async function leadStored(c: Ctx) {
  const l = await c.io.seams.fact(c.run.id, "lead", { lead_id: leadOf(c) });
  if (l.is_test !== true) throw new Unsafe("the lead is not marked is_test");
  return { done: true, detail: `lead stored (${String(l.lead_status ?? "no status")})` };
}

const allocationsSchema = z.object({
  allocations: z.array(
    z.object({
      id: z.number(),
      status: z.string().nullable(),
      destination_type: z.string().nullable(),
      partner: z.string().nullable(),
      origin: z.string().nullable(),
      reference: z.string().nullable(),
    }),
  ),
});

export async function allocations(c: Ctx) {
  return allocationsSchema.parse(await c.io.seams.fact(c.run.id, "b2b.routing", { lead_id: leadOf(c) })).allocations;
}

/** B2B's test hand-off to Spark, as the test runner (b2b.route_test_lead, B2B admin with two-factor). */
export async function handToSpark(c: Ctx): Promise<Artefacts> {
  const r = z.object({ destination: z.string(), allocation_id: z.number() }).parse(
    await need(apps(c).runner, "the test runner login").rpc("b2b", "route_test_lead", {
      p_lead_id: leadOf(c),
      p_target: "b2c_test",
      p_reason: `Eduwit One synthetic test ${c.run.testId}`,
    }),
  );
  if (r.destination !== "in_house") throw new Error(`the test hand-off went to ${r.destination}`);
  return { allocation_id: r.allocation_id };
}

/** B2B's outbox delivered the lead to Spark. */
export async function deliveredToSpark(c: Ctx) {
  const statuses = z
    .object({ statuses: z.array(z.string()) })
    .parse(await c.io.seams.fact(c.run.id, "b2b.delivered", { lead_id: leadOf(c) })).statuses;
  if (statuses.includes("delivered")) return { done: true, detail: "delivered" };
  if (statuses.includes("dead")) throw new Error("the outbox gave up on it (dead)");
  return { done: false, detail: statuses.length ? `outbox ${statuses.join(", ")}` : "not in the outbox yet" };
}

/** Spark holds the lead as a test lead. */
export async function heldBySpark(c: Ctx) {
  const r = await c.io.seams.fact(c.run.id, "b2c.record", { lead_id: leadOf(c) });
  if (r.found !== true) return { done: false, detail: "not in Spark yet" };
  if (r.is_test !== true) throw new Unsafe("Spark took the test lead as a real lead");
  return r.held_by_b2c === true
    ? { done: true, detail: "held by Spark" }
    : { done: false, detail: "in Spark, not held" };
}

/** Today in India (YYYY-MM-DD), the day Spark's analytics count in. */
export function istDay(ms: number): string {
  return new Date(ms + 5.5 * 3600_000).toISOString().slice(0, 10);
}
