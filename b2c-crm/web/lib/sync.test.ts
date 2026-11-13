import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The send loop and the outbox loop of lib/sync.ts with the database, the B2B link and every network call mocked: nothing
// leaves the test.
const state = vi.hoisted(() => ({
  live: false,
  b2b: false,
  outbox: [] as Record<string, unknown>[],
  b2bCalls: [] as string[],
  sends: [] as Record<string, unknown>[],
  rpcs: [] as { fn: string; args: Record<string, unknown> }[],
  signed: [] as string[],
  fetches: [] as { url: string; body: string | null }[],
  rendered: [] as unknown[],
}));

vi.mock("server-only", () => ({}));
vi.mock("@/lib/b2b", () => {
  const answer = (what: string) => async (...args: unknown[]) => {
    state.b2bCalls.push(`${what}:${Array.isArray(args[0]) ? args[0].length : ""}`);
    return { status: 200, body: { ok: true, results: Array.isArray(args[0]) ? args[0].map(() => ({ status: 200, ok: true })) : undefined } };
  };
  return { b2bReady: () => state.b2b, postEvent: answer("event"), routeToPartners: answer("route"), intake: answer("intake"), patchLead: answer("update"), postActivity: answer("activity"), batch: answer("batch") };
});
vi.mock("@/lib/env", async (orig) => ({ ...(await orig<typeof import("./env")>()), liveMode: () => state.live, siteUrl: () => "https://b2c.eduwit.in" }));
vi.mock("@/lib/money-pdf", () => ({
  parseAttachments: (v: unknown) => (Array.isArray(v) ? v : []),
  renderAttachment: async (a: { kind: string; invoice_id?: number }) => {
    state.rendered.push(a);
    return { filename: `INV-${a.invoice_id}.pdf`, content: Buffer.from("%PDF"), contentType: "application/pdf", test: a.invoice_id === 99 };
  },
}));
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      state.rpcs.push({ fn, args });
      if (fn === "send_take") return { data: state.sends, error: null };
      if (fn === "outbox_take") return { data: state.outbox, error: null };
      if (fn === "connection_token") return { data: null, error: null };
      return { data: null, error: null };
    },
    storage: { from: () => ({ createSignedUrl: async (path: string) => { state.signed.push(path); return { data: { signedUrl: `https://x.supabase.co/sign/${path}?token=t` }, error: null }; } }) },
  }),
}));

const { runOutbox, runSends } = await import("./sync");
const { JobBudget } = await import("./job-budget");

const doneResults = () => state.rpcs.find((r) => r.fn === "send_done")?.args.p_results as Record<string, unknown>[];

beforeEach(() => {
  Object.assign(state, { live: false, b2b: false, outbox: [], b2bCalls: [], sends: [], rpcs: [], signed: [], fetches: [], rendered: [] });
  process.env.WHATSAPP_PHONE_NUMBER_ID = "123";
  process.env.WHATSAPP_TOKEN = "wa-token";
  vi.stubGlobal("fetch", async (url: string, init?: RequestInit) => {
    state.fetches.push({ url: String(url), body: typeof init?.body === "string" ? init.body : null });
    return new Response(JSON.stringify({ messages: [{ id: "wamid.T" }] }), { status: 200 });
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  delete process.env.WHATSAPP_TOKEN;
});

const calls = (fn: string) => state.rpcs.filter((r) => r.fn === fn).map((r) => r.args);
/** A budget whose clock reads `at` for the first `inTime` checks and is past the deadline after that. */
const budgetFor = (inTime: number) => {
  let n = 0;
  return new JobBudget(1_000, () => (n++ < inTime ? 0 : 1_001));
};

describe("runSends records outcomes as it goes and stops at its deadline (b53, b56)", () => {
  const item = (id: number) => ({ id, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "text", text: `m${id}` } });
  it("records outcomes ten at a time, so a run that ends early loses at most one group", async () => {
    state.sends = Array.from({ length: 23 }, (_, i) => item(i + 1));
    const out = await runSends();
    expect(calls("send_done").map((a) => (a.p_results as unknown[]).length)).toEqual([10, 10, 3]);
    expect(out).toMatchObject({ dry_run: 23, released: 0 });
    expect(calls("send_release")).toEqual([]);
  });

  it("starts no send after the deadline and hands the rest back, the attempt not counted", async () => {
    state.sends = [1, 2, 3, 4, 5].map(item);
    const budget = budgetFor(2); // two sends in time, then late
    const out = await runSends(budget);
    expect(calls("send_done").flatMap((a) => (a.p_results as { id: number }[]).map((r) => r.id))).toEqual([1, 2]);
    expect(calls("send_release")).toEqual([{ p_ids: [3, 4, 5] }]);
    expect(out).toMatchObject({ dry_run: 2, released: 3, held: 0 });
    expect(budget.stopped).toEqual(["sends"]);
  });

  it("with no time at all takes the messages, sends none and hands every one back", async () => {
    state.sends = [1, 2].map(item);
    const out = await runSends(budgetFor(0));
    expect(calls("send_done")).toEqual([]);
    expect(calls("send_release")).toEqual([{ p_ids: [1, 2] }]);
    expect(out).toMatchObject({ sent: 0, dry_run: 0, send_failed: 0, released: 2 });
  });
});

describe("runOutbox stops at its deadline (b56)", () => {
  const o = (id: number, kind: string) => ({ id, kind, lead_id: 7, request_id: `r-${id}`, body: { set: { a: 1 }, reason: "x", student: {} }, occurred_at: "2026-11-13T00:00:00Z", actor: null, urgent: true });

  it("does nothing without the B2B link", async () => {
    state.outbox = [o(1, "event")];
    expect(await runOutbox("urgent")).toEqual({ taken: 0, ok: 0, failed: 0, outbox_released: 0 });
    expect(calls("outbox_take")).toEqual([]);
  });

  it("urgent: events, routing, new students, then the writes, one call each, all recorded together", async () => {
    state.b2b = true;
    state.outbox = [o(1, "update"), o(2, "intake"), o(3, "event"), o(4, "route"), o(5, "activity")];
    const out = await runOutbox("urgent");
    expect(state.b2bCalls.map((c) => c.split(":")[0])).toEqual(["event", "route", "intake", "update", "activity"]);
    expect((calls("outbox_done")[0]!.p_results as { id: number }[]).map((r) => r.id)).toEqual([3, 4, 2, 1, 5]);
    expect(calls("job_release")).toEqual([]);
    expect(out).toEqual({ taken: 5, ok: 5, failed: 0, outbox_released: 0 });
  });

  it("starts no call after the deadline: records the answers so far and hands the rest back", async () => {
    state.b2b = true;
    state.outbox = [o(1, "update"), o(2, "intake"), o(3, "event"), o(4, "route")];
    const budget = budgetFor(2);
    const out = await runOutbox("urgent", budget);
    expect(state.b2bCalls.map((c) => c.split(":")[0])).toEqual(["event", "route"]);
    expect((calls("outbox_done")[0]!.p_results as { id: number }[]).map((r) => r.id)).toEqual([3, 4]);
    expect(calls("job_release")).toEqual([{ p_kind: "outbox", p_ids: [2, 1] }]);
    expect(out).toEqual({ taken: 4, ok: 2, failed: 0, outbox_released: 2 });
    expect(budget.stopped).toEqual(["outbox"]);
  });

  it("batch: the writes go 200 a call, and calls not started are handed back whole", async () => {
    state.b2b = true;
    state.outbox = [o(1, "event"), ...Array.from({ length: 450 }, (_, i) => o(i + 10, "update"))];
    const out = await runOutbox("batch", budgetFor(2)); // the event and the first call of 200
    expect(state.b2bCalls).toEqual(["event:", "batch:200"]);
    expect((calls("job_release")[0]!.p_ids as number[]).length).toBe(250);
    expect(out).toMatchObject({ taken: 451, outbox_released: 250 });
  });
});

describe("runSends sends", () => {
  it("sends nothing anywhere while not live, but still renders attachments", async () => {
    state.sends = [
      { id: 1, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "media", media_kind: "document", path: "leads/7/a.pdf", filename: "a.pdf" } },
      { id: 2, channel: "email", lead_id: null, to: "accounts@uni.example", purpose: "invoice", live: true, payload: { from: "Eduwit <connect@eduwit.in>", subject: "Invoice", text: "Attached", attachments: [{ kind: "invoice_pdf", invoice_id: 5 }] } },
    ];
    const out = await runSends();
    expect(out).toMatchObject({ dry_run: 2, sent: 0, send_failed: 0 });
    expect(state.fetches).toEqual([]);
    expect(state.signed).toEqual([]);
    expect(state.rendered).toEqual([{ kind: "invoice_pdf", invoice_id: 5 }]);
    expect(doneResults()).toEqual([expect.objectContaining({ id: 1, ok: true, dry_run: true }), expect.objectContaining({ id: 2, ok: true, dry_run: true })]);
  });

  it("live: a staff alert goes as a template to the staff phone, and a stored file as a signed link", async () => {
    state.live = true;
    state.sends = [
      { id: 3, channel: "whatsapp", lead_id: null, to: "919810000001", purpose: "staff_alert", live: true,
        payload: { type: "template", template: { name: "staff_alert", language: "en", params: ["Follow-up due", "Call Asha", "https://b2c.eduwit.in/s/leads/7"] } } },
      { id: 4, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "media", media_kind: "image", path: "leads/7/wa/fees.png", caption: "Fees" } },
    ];
    const out = await runSends();
    expect(out).toMatchObject({ sent: 2, send_failed: 0 });
    const bodies = state.fetches.filter((f) => f.url.endsWith("/123/messages")).map((f) => JSON.parse(f.body!));
    expect(bodies[0]).toMatchObject({ to: "919810000001", type: "template", template: { name: "staff_alert" } });
    expect(bodies[1]).toMatchObject({ type: "image", image: { link: "https://x.supabase.co/sign/leads/7/wa/fees.png?token=t", caption: "Fees" } });
    expect(state.signed).toEqual(["leads/7/wa/fees.png"]);
    expect(state.rpcs.find((r) => r.fn === "connector_report" && r.args.p_key === "whatsapp")?.args.p_ok).toBe(true);
  });

  const wa = (id: number) => ({ id, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "text", text: `m${id}` } });
  const meta = (status: number, code: number, message: string) => new Response(JSON.stringify({ error: { message, code } }), { status });

  it("live: a send that may have gone out (5xx) is recorded with retry: false; a 4xx Meta does not explain is not", async () => {
    state.live = true;
    state.sends = [1, 2].map(wa);
    let n = 0;
    vi.stubGlobal("fetch", async () => (n++ === 0 ? new Response("{}", { status: 502 }) : meta(400, 131053, "Media upload error")));
    const out = await runSends();
    expect(doneResults()[0]).toMatchObject({ id: 1, ok: false, retry: false, error: expect.stringMatching(/may have gone out/) });
    expect(doneResults()[1]).toMatchObject({ id: 2, ok: false, error: "131053: Media upload error" });
    expect(doneResults()[1]).not.toHaveProperty("retry");
    expect(out.send_failed).toBe(2);
  });

  it("live: a message Meta refuses for good is failed at once with the reason; a rate limit is tried again", async () => {
    state.live = true;
    state.sends = [1, 2, 3].map(wa);
    const answers = [meta(400, 131047, "Re-engagement message"), meta(400, 130429, "Rate limit hit"), meta(404, 132001, "Template name does not exist in the translation")];
    let n = 0;
    vi.stubGlobal("fetch", async () => answers[n++]!);
    const out = await runSends();
    expect(doneResults()[0]).toMatchObject({ id: 1, ok: false, retry: false, error: expect.stringMatching(/more than 24 hours.*not sent again automatically.*131047: Re-engagement message/) });
    expect(doneResults()[1]).toMatchObject({ id: 2, ok: false, error: "130429: Rate limit hit" });
    expect(doneResults()[1]).not.toHaveProperty("retry");
    expect(doneResults()[2]).toMatchObject({ id: 3, ok: false, retry: false, error: expect.stringMatching(/template does not exist/) });
    expect(out).toMatchObject({ send_failed: 3, held: 0, released: 0 });
  });

  it("live: when Meta refuses the connection, the message is tried again, the WhatsApp messages left are handed back and the emails still go", async () => {
    state.live = true;
    state.sends = [wa(1), wa(2), { id: 3, channel: "email", lead_id: null, to: "a@uni.example", purpose: "invoice", live: true, payload: { from: "Eduwit <connect@eduwit.in>", subject: "x", text: "x" } }, wa(4),
      { ...wa(5), live: false }];
    vi.stubGlobal("fetch", async (url: string) => { state.fetches.push({ url: String(url), body: null }); return meta(401, 190, "Error validating access token: Session has expired"); });
    const out = await runSends();
    expect(state.fetches.length).toBe(1); // one call told us; no other message was offered to a connection that refuses
    const done = calls("send_done").flatMap((a) => a.p_results as Record<string, unknown>[]);
    expect(done.map((r) => r.id)).toEqual([1, 3, 5]);
    expect(done[0]).toMatchObject({ ok: false, error: expect.stringMatching(/refused Spark's connection, not this message: the access token has expired/) });
    expect(done[0]).not.toHaveProperty("retry");
    expect(done[2]).toMatchObject({ id: 5, ok: true, dry_run: true }); // a test-mode message calls nobody: recorded as before
    expect(calls("send_release")).toEqual([{ p_ids: [2, 4] }]);
    expect(out).toMatchObject({ send_failed: 2, dry_run: 1, held: 2, released: 2 });
    expect(state.rpcs.find((r) => r.fn === "connector_report" && r.args.p_key === "whatsapp")?.args).toMatchObject({ p_ok: false, p_error: expect.stringMatching(/access token has expired/) });
  });

  it("live: refuses a file outside the lead's folder", async () => {
    state.live = true;
    state.sends = [{ id: 5, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "media", media_kind: "document", path: "leads/8/x.pdf" } }];
    await runSends();
    expect(doneResults()[0]).toMatchObject({ id: 5, ok: false });
    expect(state.fetches).toEqual([]);
  });

  it("live: a test invoice is never sent; a counsellor without a Gmail connection falls back to delegation", async () => {
    state.live = true;
    state.sends = [
      { id: 6, channel: "email", lead_id: null, to: "accounts@uni.example", purpose: "invoice", live: true, payload: { from: "Eduwit <connect@eduwit.in>", subject: "Invoice", text: "x", attachments: [{ kind: "invoice_pdf", invoice_id: 99 }] } },
      { id: 7, channel: "email", lead_id: 7, to: "asha@example.com", purpose: "sales", live: true, payload: { email_id: 70, from_user: "u-1", from: "priya@eduwit.in", subject: "Fees", text: "See https://amity.edu/mba", html: null } },
    ];
    const out = await runSends();
    expect(doneResults()[0]).toMatchObject({ id: 6, ok: true, dry_run: true });
    // no service account in the test environment: the fallback path answers "not configured", nothing reaches Google
    expect(doneResults()[1]).toMatchObject({ id: 7, ok: false, error: expect.stringMatching(/not configured/) });
    expect(state.fetches).toEqual([]);
    expect(out.send_failed).toBe(1);
  });
});
