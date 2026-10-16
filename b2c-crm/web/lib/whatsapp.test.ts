import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { mediaAllowed, mediaDownload, mediaInfo, mediaPath, messageBody, parseWebhook, safeFileName, sendWhatsApp, verifyMetaSignature } from "./whatsapp";

describe("WhatsApp Cloud API", () => {
  it("builds a template message with body parameters", () => {
    expect(messageBody("+91 90000 00012", { type: "template", template: { name: "sales_opener_v1", language: "en", params: ["Asha", "Priya", "MBA"] } })).toEqual({
      messaging_product: "whatsapp", recipient_type: "individual", to: "919000000012", type: "template",
      template: { name: "sales_opener_v1", language: { code: "en" }, components: [{ type: "body", parameters: [{ type: "text", text: "Asha" }, { type: "text", text: "Priya" }, { type: "text", text: "MBA" }] }] },
    });
  });

  it("never calls Meta when the item is not live", async () => {
    expect(await sendWhatsApp(null, "919000000012", { type: "text", text: "hi" }, false)).toEqual({ ok: true, dry_run: true });
  });

  it("refuses to send live without configuration", async () => {
    expect((await sendWhatsApp(null, "919000000012", { type: "text", text: "hi" }, true)).ok).toBe(false);
  });

  it("checks Meta's signature over the raw body", () => {
    const raw = '{"entry":[]}';
    const sig = "sha256=" + createHmac("sha256", "app-secret").update(raw).digest("hex");
    expect(verifyMetaSignature(raw, sig, "app-secret")).toBe(true);
    expect(verifyMetaSignature(raw + " ", sig, "app-secret")).toBe(false);
    expect(verifyMetaSignature(raw, null, "app-secret")).toBe(false);
  });

  it("reads messages, button replies and statuses from a webhook", () => {
    const body = { entry: [{ changes: [{ value: {
      contacts: [{ wa_id: "919000000012", profile: { name: "Asha" } }],
      messages: [
        { from: "919000000012", id: "wamid.A", type: "text", text: { body: "STOP" } },
        { from: "919000000012", id: "wamid.B", type: "button", button: { text: "YES" }, context: { id: "wamid.REQ" } },
      ],
      statuses: [{ id: "wamid.OUT", status: "delivered", timestamp: "1760000000" }],
    } }] }] };
    const { messages, statuses } = parseWebhook(body);
    expect(messages).toHaveLength(2);
    expect(messages[0]).toMatchObject({ from: "919000000012", wamid: "wamid.A", kind: "text", text: "STOP", profile_name: "Asha" });
    expect(messages[1]).toMatchObject({ kind: "button", button: "YES", context_wamid: "wamid.REQ" });
    expect(statuses).toEqual([{ wamid: "wamid.OUT", status: "delivered", at: new Date(1760000000 * 1000).toISOString(), error: null }]);
  });

  it("tolerates an empty or odd webhook", () => {
    expect(parseWebhook(null)).toEqual({ messages: [], statuses: [] });
    expect(parseWebhook({ entry: [{ changes: [{}] }] })).toEqual({ messages: [], statuses: [] });
  });
});

describe("WhatsApp media out (C1)", () => {
  const base = { messaging_product: "whatsapp", recipient_type: "individual", to: "919000000012" };

  it("sends a stored image by its signed link, with the caption", () => {
    expect(messageBody("+91 90000 00012", { type: "media", media_kind: "image", path: "leads/7/fees.png", caption: " Fee table " }, "https://x.supabase.co/storage/v1/object/sign/b2c-documents/leads/7/fees.png?token=t"))
      .toEqual({ ...base, type: "image", image: { link: "https://x.supabase.co/storage/v1/object/sign/b2c-documents/leads/7/fees.png?token=t", caption: "Fee table" } });
  });

  it("sends a brochure link as a document with its file name, and never a filename on an image", () => {
    expect(messageBody("919000000012", { type: "media", media_kind: "document", link: "https://cdn.example.com/mba.pdf", filename: 'MBA "brochure"\r\n.pdf', caption: "Brochure" }))
      .toEqual({ ...base, type: "document", document: { link: "https://cdn.example.com/mba.pdf", caption: "Brochure", filename: "MBA _brochure_.pdf" } });
    const img = messageBody("919000000012", { type: "media", media_kind: "image", link: "https://cdn.example.com/a.jpg", filename: "a.jpg" });
    expect(img).toEqual({ ...base, type: "image", image: { link: "https://cdn.example.com/a.jpg" } });
  });

  it("prefers the signed link over the payload link and refuses a media message without an https link", () => {
    expect((messageBody("919000000012", { type: "media", media_kind: "document", link: "https://a.example/x.pdf" }, "https://signed.example/y") as { document: { link: string } }).document.link).toBe("https://signed.example/y");
    expect(() => messageBody("919000000012", { type: "media", media_kind: "document", path: "leads/7/x.pdf" })).toThrow(/https link/);
    expect(() => messageBody("919000000012", { type: "media", media_kind: "image", link: "http://insecure.example/a.png" })).toThrow(/https link/);
  });

  it("keeps a long caption within Meta's 1024 characters", () => {
    const b = messageBody("919000000012", { type: "media", media_kind: "image", link: "https://a.example/a.png", caption: "x".repeat(2000) }) as { image: { caption: string } };
    expect(b.image.caption).toHaveLength(1024);
  });

  it("sends a staff alert template to a staff phone like any template (no lead, no student checks)", () => {
    expect(messageBody("+91 98100 00001", { type: "template", template: { name: "staff_alert", language: "en", params: ["Follow-up due", "Call Asha", "https://b2c.eduwit.in/s/leads/7"] } }))
      .toMatchObject({ to: "919810000001", type: "template", template: { name: "staff_alert", components: [{ type: "body", parameters: [{ text: "Follow-up due" }, { text: "Call Asha" }, { text: "https://b2c.eduwit.in/s/leads/7" }] }] } });
  });

  it("posts the media body to Meta when live", async () => {
    const calls: { url: string; body: unknown }[] = [];
    const real = globalThis.fetch;
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      calls.push({ url, body: JSON.parse(String(init?.body)) });
      return new Response(JSON.stringify({ messages: [{ id: "wamid.M" }] }), { status: 200 });
    }) as unknown as typeof fetch;
    try {
      const r = await sendWhatsApp({ phoneNumberId: "123", token: "t", apiVersion: "v21.0" }, "919000000012", { type: "media", media_kind: "document", path: "leads/7/a.pdf", filename: "a.pdf" }, true, "https://signed.example/a");
      expect(r).toEqual({ ok: true, wamid: "wamid.M" });
      expect(calls[0]!.url).toBe("https://graph.facebook.com/v21.0/123/messages");
      expect(calls[0]!.body).toMatchObject({ type: "document", document: { link: "https://signed.example/a", filename: "a.pdf" } });
    } finally {
      globalThis.fetch = real;
    }
  });
});

describe("WhatsApp media in (C1)", () => {
  it("passes the media id, type, file name and caption to wa_inbound with kind media", () => {
    const { messages } = parseWebhook({ entry: [{ changes: [{ value: { messages: [
      { from: "919000000012", id: "wamid.D", type: "document", document: { id: "MEDIA1", mime_type: "application/pdf", filename: "marksheet.pdf", caption: "my 12th", sha256: "abc" } },
      { from: "919000000012", id: "wamid.I", type: "image", image: { id: "MEDIA2", mime_type: "image/jpeg" } },
      { from: "919000000012", id: "wamid.S", type: "sticker", sticker: { id: "MEDIA3", mime_type: "image/webp" } },
    ] } }] }] });
    expect(messages[0]).toMatchObject({ kind: "media", text: null, media: { type: "document", id: "MEDIA1", mime_type: "application/pdf", filename: "marksheet.pdf", caption: "my 12th", sha256: "abc" } });
    expect(messages[1]).toMatchObject({ kind: "media", media: { type: "image", id: "MEDIA2", mime_type: "image/jpeg", filename: null, caption: null } });
    expect(messages[2]).toMatchObject({ kind: "media", media: { type: "sticker", id: "MEDIA3" } });
  });

  it("stores only the bucket's types under the lead's folder with a safe name", () => {
    expect(mediaAllowed("application/pdf")).toBe(true);
    expect(mediaAllowed("image/jpeg; charset=binary")).toBe(true);
    expect(mediaAllowed("audio/ogg; codecs=opus")).toBe(false);
    expect(mediaAllowed("application/vnd.openxmlformats-officedocument.wordprocessingml.document")).toBe(false);
    expect(safeFileName("../../etc/passwd Marks Sheet.PDF", "application/pdf")).toBe("etc-passwd-Marks-Sheet.pdf");
    expect(safeFileName(null, "image/jpeg", "image")).toBe("image.jpg");
    expect(mediaPath(42, 9001, { filename: "12th marksheet.pdf", mime_type: "application/pdf", type: "document" })).toBe("leads/42/wa/9001-12th-marksheet.pdf");
    expect(mediaPath(42, 9002, { mime_type: "image/png", type: "image" })).toBe("leads/42/wa/9002-image.png");
  });

  it("looks up the download link by media id, then downloads with the token, refusing large files", async () => {
    const cfg = { phoneNumberId: "123", token: "tok", apiVersion: "v21.0" };
    const seen: { url: string; auth: string | null }[] = [];
    const fake = (async (url: string, init?: RequestInit) => {
      seen.push({ url, auth: new Headers(init?.headers).get("authorization") });
      if (url.includes("graph.facebook.com")) return new Response(JSON.stringify({ url: "https://lookaside.fbsbx.com/x", mime_type: "application/pdf", file_size: 5 }));
      return new Response(new Uint8Array([1, 2, 3, 4, 5]), { headers: { "content-type": "application/pdf" } });
    }) as unknown as typeof fetch;
    const info = await mediaInfo(cfg, "MEDIA1", fake);
    expect(info).toEqual({ url: "https://lookaside.fbsbx.com/x", mime_type: "application/pdf", file_size: 5 });
    const f = await mediaDownload(cfg, info.url, 100, fake);
    expect(f.bytes.byteLength).toBe(5);
    expect(seen.map((s) => s.url)).toEqual(["https://graph.facebook.com/v21.0/MEDIA1", "https://lookaside.fbsbx.com/x"]);
    expect(seen.every((s) => s.auth === "Bearer tok")).toBe(true);
    await expect(mediaDownload(cfg, info.url, 4, fake)).rejects.toThrow(/larger/);
    await expect(mediaInfo(cfg, "../me", fake)).rejects.toThrow(/media id/);
  });
});
