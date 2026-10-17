import { describe, expect, it } from "vitest";
import { BrevoEmailProvider, MockEmailProvider, ResendEmailProvider } from "./email";
import { escapeHtml, passwordLinkEmail, staffCodeEmail } from "./templates";
import { MetaWhatsAppProvider } from "./whatsapp";
import { ProviderError } from "./types";

function fakeFetch(status: number, body: unknown, seen: { url?: string; init?: RequestInit }) {
  return ((url: string, init?: RequestInit) => {
    seen.url = url;
    seen.init = init;
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  }) as unknown as typeof fetch;
}

const msg = { to: "a@b.test", subject: "S", html: "<p>h</p>", text: "t", idempotencyKey: "k1" };

describe("email providers", () => {
  it("mock records messages", async () => {
    const m = new MockEmailProvider();
    await m.send(msg);
    expect(m.sent).toHaveLength(1);
  });

  it("resend sends the idempotency key and returns the id", async () => {
    const seen: { url?: string; init?: RequestInit } = {};
    const r = await new ResendEmailProvider("Eduwit <c@eduwit.in>", "re_key", fakeFetch(200, { id: "abc" }, seen)).send(
      msg,
    );
    expect(r.id).toBe("abc");
    expect(seen.url).toBe("https://api.resend.com/emails");
    expect((seen.init?.headers as Record<string, string>)["idempotency-key"]).toBe("k1");
  });

  it("brevo parses the sender and maps a 5xx to a retryable error", async () => {
    const seen: { url?: string; init?: RequestInit } = {};
    await new BrevoEmailProvider("Eduwit <c@eduwit.in>", "key", fakeFetch(201, { messageId: "m1" }, seen)).send(msg);
    expect((JSON.parse(seen.init?.body as string) as { sender: unknown }).sender).toEqual({
      name: "Eduwit",
      email: "c@eduwit.in",
    });
    const err = await new BrevoEmailProvider("c@eduwit.in", "key", fakeFetch(503, {}, {}))
      .send(msg)
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ProviderError);
    expect((err as ProviderError).retryable).toBe(true);
  });

  it("a 4xx is not retryable", async () => {
    const err = await new ResendEmailProvider("x", "k", fakeFetch(422, {}, {})).send(msg).catch((e: unknown) => e);
    expect((err as ProviderError).retryable).toBe(false);
  });
});

describe("whatsapp", () => {
  it("sends a template with body parameters", async () => {
    const seen: { url?: string; init?: RequestInit } = {};
    const r = await new MetaWhatsAppProvider(
      "123",
      "tok",
      "v21.0",
      fakeFetch(200, { messages: [{ id: "wamid.1" }] }, seen),
    ).sendTemplate({
      to: "919812345678",
      template: "payout_paid",
      language: "en",
      params: ["₹1,000.00", "UTR123"],
    });
    expect(r.id).toBe("wamid.1");
    expect(seen.url).toBe("https://graph.facebook.com/v21.0/123/messages");
    expect(
      (
        JSON.parse(seen.init?.body as string) as {
          template: { components: { parameters: unknown[] }[] };
        }
      ).template.components[0]?.parameters,
    ).toHaveLength(2);
  });

  it("refuses an invalid number without calling Meta", async () => {
    const seen: { url?: string } = {};
    await expect(
      new MetaWhatsAppProvider("1", "t", "v21.0", fakeFetch(200, {}, seen)).sendTemplate({
        to: "+91 98",
        template: "x",
        language: "en",
        params: [],
      }),
    ).rejects.toThrow(/invalid/);
    expect(seen.url).toBeUndefined();
  });
});

describe("templates", () => {
  it("escapes names and only prints a 6-digit code", () => {
    expect(escapeHtml(`<b>"x"&'y'</b>`)).toBe("&lt;b&gt;&quot;x&quot;&amp;&#39;y&#39;&lt;/b&gt;");
    expect(staffCodeEmail("123456", "<script>").html).not.toContain("<script>");
    expect(staffCodeEmail("12345x", "A").subject).toContain("------");
    expect(passwordLinkEmail("https://x.test/a?b=1&c=2", "A").html).toContain("&amp;c=2");
  });
});
