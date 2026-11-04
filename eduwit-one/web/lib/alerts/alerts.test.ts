import { describe, expect, it } from "vitest";
import { type EmailMessage, MockEmailClient, type SendOptions } from "@/lib/clients/email.ts";
import { FakeDb, tickState } from "@/test/state.ts";
import { compose, type Delivery, deliverySchema } from "./compose.ts";
import { sendPending } from "./sender.ts";

const incident = {
  id: 42,
  check_id: "WITTY-01",
  app: "witty",
  severity: "P1" as const,
  title: "Witty's own health alerts are firing",
  opened_at: "2026-10-23T10:00:00Z",
  occurrences: 3,
  reopened_count: 0,
  subjects: ["outbox_failed"],
  summary: null,
  value: { alerts: [{ alert: "outbox_failed" }] },
  status: "fail",
  error: null,
};
const delivery = (over: Partial<Delivery> = {}): Delivery => ({
  id: 7,
  recipient: "connect@eduwit.in",
  kind: "alert",
  escalation_level: 0,
  attempts: 0,
  idempotency_key: "alert:42:1:0:email:connect@eduwit.in",
  incident,
  digest: null,
  ...over,
});

describe("compose", () => {
  it("puts severity, app, title and the incident number in the subject and a link in the body", () => {
    const m = compose(delivery(), "https://one.eduwit.in");
    expect(m.subject).toBe("[P1] witty: Witty's own health alerts are firing #42");
    expect(m.text).toContain("https://one.eduwit.in/incidents/42");
    expect(m.text).toContain("Affected: outbox_failed");
    expect(m.text).toContain("23 Oct 2026, 3:30 pm");
  });

  it("marks reminders, reopenings and checks that could not run", () => {
    expect(compose(delivery({ kind: "escalation", escalation_level: 2 }), "https://o").subject).toContain(
      "(reminder 2: not acknowledged)",
    );
    expect(compose(delivery({ incident: { ...incident, reopened_count: 1 } }), "https://o").subject).toContain(
      "(failing again)",
    );
    const broken = compose(
      delivery({ incident: { ...incident, status: "source_missing", error: "function missing" } }),
      "https://o",
    );
    expect(broken.text).toContain("The check could not run (source_missing): function missing");
  });

  it("escapes HTML and bounds the value", () => {
    const m = compose(delivery({ incident: { ...incident, title: "<b>x</b>", value: "y".repeat(2000) } }), "https://o");
    expect(m.html).not.toContain("<b>x</b>");
    expect(m.text.length).toBeLessThan(1200);
  });

  it("lists the day's P2 incidents in the digest", () => {
    const m = compose(
      delivery({
        kind: "digest",
        incident: null,
        digest: [
          {
            id: 1,
            check_id: "B2B-09",
            app: "b2b",
            title: "Partner queue",
            opened_at: "2026-10-23T05:00:00Z",
            resolved: false,
          },
          {
            id: 2,
            check_id: "WEB-04",
            app: "web",
            title: "Catalogue review",
            opened_at: "2026-10-23T06:00:00Z",
            resolved: true,
          },
        ],
      }),
      "https://o",
    );
    expect(m.subject).toBe("[Eduwit One] 2 P2 incidents today");
    expect(m.text).toContain("WEB-04 (web): Catalogue review (recovered)");
  });

  it("mails the morning brief as plain text, escaped, with a link to its page", () => {
    const m = compose(
      delivery({
        kind: "brief",
        incident: null,
        brief: {
          id: 9,
          for_date: "2026-10-24",
          body_md: "# Brief\n\n**Quiet day.**\n\n\n- WITTY-02 <b>open</b>",
          model: "claude-sonnet-5-5",
          views: [],
        },
      }),
      "https://o",
    );
    expect(m.subject).toBe("[Eduwit One] Morning brief, 24 Oct 2026");
    expect(m.text).toBe(
      "Brief\n\nQuiet day.\n\n- WITTY-02 <b>open</b>\n\nOpen the brief: https://o/brief/9\nWritten by the AI from the numbers on the brief's page; what is broken is decided by the checks.",
    );
    expect(m.html).toContain("&#60;b&#62;open&#60;/b&#62;");
    expect(m.html).not.toContain("<b>open");
    expect(m.html).toContain('href="https://o/brief/9"');
  });

  it("marks the AI's line as advice, after the deterministic lines (m7)", () => {
    const summary = "Outbox retries are failing since 10:00";
    const m = compose(delivery({ incident: { ...incident, summary } }), "https://o");
    const lines = m.text.split("\n");
    const at = lines.indexOf(`AI summary (advisory): ${summary}`);
    expect(at).toBeGreaterThan(lines.indexOf("Affected: outbox_failed"));
    expect(at).toBeGreaterThan(lines.findIndex((l) => l.startsWith("Opened ")));
    expect(m.html).toContain(`AI summary (advisory): ${summary}`);
    expect(m.text).not.toContain("Summary: ");
  });

  it("reads a saved view with a bad days value as 30 days instead of refusing the brief (m3)", () => {
    const d = deliverySchema.parse({
      ...delivery({ kind: "brief", incident: null }),
      brief: {
        id: 9,
        for_date: "2026-10-26",
        body_md: "All quiet.",
        model: null,
        views: [
          { name: "Funnel", page: "analytics", days: "yes" },
          { name: "Week", page: "marketing", days: 7 },
          { name: "Open", page: "analytics", days: null },
          { name: "Year", page: "analytics", days: 9000 },
        ],
      },
    });
    expect(d.brief?.views.map((v) => v.days)).toEqual([30, 7, 30, 30]);
    expect(compose(d, "https://o").text).toContain(
      "- Funnel: https://o/analytics?days=30\n- Week: https://o/marketing?days=7",
    );
  });

  it("lists the saved views asked for by email, as links", () => {
    const m = compose(
      delivery({
        kind: "brief",
        incident: null,
        brief: {
          id: 9,
          for_date: "2026-10-26",
          body_md: "All quiet.",
          model: null,
          views: [{ name: "Daily funnel", page: "analytics", days: 7 }],
        },
      }),
      "https://o",
    );
    expect(m.text).toContain("Your saved views:\n- Daily funnel: https://o/analytics?days=7");
  });
});

describe("sendPending", () => {
  it("sends each claimed delivery once, with its idempotency key, and records the verdict", async () => {
    const db = new FakeDb(tickState());
    db.deliveries = [delivery(), delivery({ id: 8, recipient: "second@eduwit.in" })];
    const email = new MockEmailClient({ id: "prov-1" });
    const s = await sendPending({
      db,
      email: { mode: "mock", client: email },
      from: "Eduwit One <one@eduwit.in>",
      oneHost: "https://o",
    });
    expect(s).toMatchObject({ claimed: 2, sent: 2, failed: 0 });
    expect(email.sent.map((m) => [m.to, m.idempotencyKey])).toEqual([
      ["connect@eduwit.in", "alert:42:1:0:email:connect@eduwit.in"],
      ["second@eduwit.in", "alert:42:1:0:email:connect@eduwit.in"],
    ]);
    expect(db.finished).toEqual([
      { id: 7, ok: true, error: null, providerId: "prov-1" },
      { id: 8, ok: true, error: null, providerId: "prov-1" },
    ]);
  });

  it("records a failed send without its message text, and claims nothing without an email key", async () => {
    const db = new FakeDb(tickState());
    db.deliveries = [delivery()];
    const failing = {
      send: async () => {
        throw new Error("connect ECONNREFUSED with secret");
      },
      status: async () => ({ lastEvent: null }),
    };
    const s = await sendPending({ db, email: { mode: "real", client: failing }, from: "x", oneHost: "https://o" });
    expect(s.failed).toBe(1);
    expect(db.finished[0]).toMatchObject({ ok: false, error: "email error" });
    const db2 = new FakeDb(tickState());
    db2.deliveries = [delivery()];
    const none = await sendPending({
      db: db2,
      email: { mode: "not_configured", client: null },
      from: "x",
      oneHost: "https://o",
    });
    expect(none.claimed).toBe(0);
    expect(db2.deliveries).toHaveLength(1);
  });
});

describe("sendPending within the tick's deadline (F8)", () => {
  it("claims and sends nothing once the deadline has passed, and says so", async () => {
    const db = new FakeDb(tickState());
    db.deliveries = [delivery()];
    const email = new MockEmailClient({ id: "prov-1" });
    const s = await sendPending({
      db,
      email: { mode: "mock", client: email },
      from: "x",
      oneHost: "https://o",
      deadline: 1_000,
      now: () => 1_000,
    });
    expect(s).toMatchObject({ claimed: 0, sent: 0, failed: 0, released: 0 });
    expect(s.errors).toEqual(["out of time: nothing claimed, the next tick sends"]);
    expect(email.sent).toHaveLength(0);
    expect(db.deliveries).toHaveLength(1);
  });

  it("sends without retries and hands back what it claimed once the deadline passes mid-way", async () => {
    const db = new FakeDb(tickState());
    db.deliveries = [delivery(), delivery({ id: 8 })];
    const options: Array<SendOptions | undefined> = [];
    let clock = 0;
    const client = {
      send: async (_m: EmailMessage, o?: SendOptions) => {
        options.push(o);
        clock = 5_000;
        return { id: "prov-2" };
      },
      status: async () => ({ lastEvent: null }),
    };
    const s = await sendPending({
      db,
      email: { mode: "real", client },
      from: "x",
      oneHost: "https://o",
      deadline: 4_000,
      now: () => clock,
    });
    expect(s).toMatchObject({ claimed: 2, sent: 1, failed: 0, released: 1 });
    expect(options).toEqual([{ retries: 0 }]);
    expect(db.finished).toEqual([
      { id: 7, ok: true, error: null, providerId: "prov-2" },
      { id: 8, ok: false, error: "out of time in this tick", providerId: null },
    ]);
    expect(s.errors).toEqual(["out of time: 1 released for the next tick"]);
  });
});
