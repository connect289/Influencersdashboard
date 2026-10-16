import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The send loop of lib/sync.ts with the database, the B2B link and every network call mocked: nothing leaves the test.
const state = vi.hoisted(() => ({
  live: false,
  sends: [] as Record<string, unknown>[],
  rpcs: [] as { fn: string; args: Record<string, unknown> }[],
  signed: [] as string[],
  fetches: [] as { url: string; body: string | null }[],
  rendered: [] as unknown[],
}));

vi.mock("server-only", () => ({}));
vi.mock("@/lib/b2b", () => ({ b2bReady: () => false }));
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
      if (fn === "connection_token") return { data: null, error: null };
      return { data: null, error: null };
    },
    storage: { from: () => ({ createSignedUrl: async (path: string) => { state.signed.push(path); return { data: { signedUrl: `https://x.supabase.co/sign/${path}?token=t` }, error: null }; } }) },
  }),
}));

const { runSync } = await import("./sync");

const doneResults = () => state.rpcs.find((r) => r.fn === "send_done")?.args.p_results as Record<string, unknown>[];

beforeEach(() => {
  Object.assign(state, { live: false, sends: [], rpcs: [], signed: [], fetches: [], rendered: [] });
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

describe("runSync sends", () => {
  it("sends nothing anywhere while not live, but still renders attachments", async () => {
    state.sends = [
      { id: 1, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "media", media_kind: "document", path: "leads/7/a.pdf", filename: "a.pdf" } },
      { id: 2, channel: "email", lead_id: null, to: "accounts@uni.example", purpose: "invoice", live: true, payload: { from: "Eduwit <connect@eduwit.in>", subject: "Invoice", text: "Attached", attachments: [{ kind: "invoice_pdf", invoice_id: 5 }] } },
    ];
    const out = await runSync("urgent");
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
    const out = await runSync("urgent");
    expect(out).toMatchObject({ sent: 2, send_failed: 0 });
    const bodies = state.fetches.filter((f) => f.url.endsWith("/123/messages")).map((f) => JSON.parse(f.body!));
    expect(bodies[0]).toMatchObject({ to: "919810000001", type: "template", template: { name: "staff_alert" } });
    expect(bodies[1]).toMatchObject({ type: "image", image: { link: "https://x.supabase.co/sign/leads/7/wa/fees.png?token=t", caption: "Fees" } });
    expect(state.signed).toEqual(["leads/7/wa/fees.png"]);
    expect(state.rpcs.find((r) => r.fn === "connector_report" && r.args.p_key === "whatsapp")?.args.p_ok).toBe(true);
  });

  it("live: refuses a file outside the lead's folder", async () => {
    state.live = true;
    state.sends = [{ id: 5, channel: "whatsapp", lead_id: 7, to: "919000000012", purpose: "sales", live: true, payload: { type: "media", media_kind: "document", path: "leads/8/x.pdf" } }];
    await runSync("urgent");
    expect(doneResults()[0]).toMatchObject({ id: 5, ok: false });
    expect(state.fetches).toEqual([]);
  });

  it("live: a test invoice is never sent; a counsellor without a Gmail connection falls back to delegation", async () => {
    state.live = true;
    state.sends = [
      { id: 6, channel: "email", lead_id: null, to: "accounts@uni.example", purpose: "invoice", live: true, payload: { from: "Eduwit <connect@eduwit.in>", subject: "Invoice", text: "x", attachments: [{ kind: "invoice_pdf", invoice_id: 99 }] } },
      { id: 7, channel: "email", lead_id: 7, to: "asha@example.com", purpose: "sales", live: true, payload: { email_id: 70, from_user: "u-1", from: "priya@eduwit.in", subject: "Fees", text: "See https://amity.edu/mba", html: null } },
    ];
    const out = await runSync("urgent");
    expect(doneResults()[0]).toMatchObject({ id: 6, ok: true, dry_run: true });
    // no service account in the test environment: the fallback path answers "not configured", nothing reaches Google
    expect(doneResults()[1]).toMatchObject({ id: 7, ok: false, error: expect.stringMatching(/not configured/) });
    expect(state.fetches).toEqual([]);
    expect(out.send_failed).toBe(1);
  });
});
