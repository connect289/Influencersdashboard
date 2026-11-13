import { createHmac } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { classifyWaError, mediaAllowed, mediaDownload, mediaInfo, mediaPath, messageBody, parseWebhook, safeFileName, sendWhatsApp, verifyMetaSignature } from "./whatsapp";

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

describe("an ambiguous send is never repeated (b55)", () => {
  const cfg = { phoneNumberId: "123", token: "t", apiVersion: "v21.0" };
  const text = { type: "text" as const, text: "hi" };
  const answer = (status: number, body: unknown) => (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;
  const throws = (e: unknown) => (async () => { throw e; }) as unknown as typeof fetch;

  it("reports a 5xx from Meta as maybe sent (retry: false)", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(503, { error: { message: "Service unavailable", code: 2 } }));
    expect(r).toMatchObject({ ok: false, retry: false, error: expect.stringMatching(/2: Service unavailable.*may have gone out/) });
  });

  it("reports no answer in time as maybe sent", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, throws(new DOMException("The operation timed out.", "TimeoutError")));
    expect(r).toMatchObject({ ok: false, retry: false, error: expect.stringMatching(/^No answer from WhatsApp in time; it may have gone out/) });
  });

  it("reports a connection dropped after the request went out as maybe sent", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, throws(new TypeError("fetch failed", { cause: Object.assign(new Error("socket hang up"), { code: "ECONNRESET" }) })));
    expect(r).toMatchObject({ ok: false, retry: false });
  });

  it("keeps a 4xx Meta does not explain and a failure before the request left as ordinary failures", async () => {
    const bad = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(400, { error: { message: "Generic user error", code: 135000 } }));
    expect(bad).toEqual({ ok: false, error: "135000: Generic user error" });
    const plain = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(400, {}));
    expect(plain).toEqual({ ok: false, error: "HTTP 400" });
    const dns = await sendWhatsApp(cfg, "919000000012", text, true, null, throws(new TypeError("fetch failed", { cause: Object.assign(new Error("getaddrinfo ENOTFOUND"), { code: "ENOTFOUND" }) })));
    expect(dns).toEqual({ ok: false, error: "fetch failed" });
    const noLink = await sendWhatsApp(cfg, "919000000012", { type: "media", media_kind: "image", path: "leads/7/a.png" }, true, null, answer(200, {}));
    expect(noLink).toEqual({ ok: false, error: "a media message needs an https link" });
  });
});

describe("what a refusal from Meta means for the message (b56)", () => {
  const cfg = { phoneNumberId: "123", token: "t", apiVersion: "v21.0" };
  const text = { type: "text" as const, text: "hi" };
  const answer = (status: number, body: unknown) => (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

  // [HTTP status, Meta code, subcode, what Spark does]
  const table: [number, number | null, number | null, "final" | "retry" | "connector"][] = [
    // this message will never be accepted: failed at once
    [400, 100, null, "final"], [400, 130472, null, "final"], [403, 130497, null, "final"], [400, 131008, null, "final"], [400, 131009, null, "final"],
    [400, 131021, null, "final"], [400, 131026, null, "final"], [400, 131030, null, "final"], [400, 131047, null, "final"], [400, 131049, null, "final"],
    [400, 131050, null, "final"], [400, 131051, null, "final"], [400, 132000, null, "final"], [404, 132001, null, "final"], [400, 132005, null, "final"],
    [400, 132007, null, "final"], [400, 132012, null, "final"], [400, 132015, null, "final"], [400, 132016, null, "final"],
    // rate limits pass by themselves: tried again, whatever status they come with
    [429, 4, null, "retry"], [400, 4, null, "retry"], [429, 80007, null, "retry"], [400, 80007, null, "retry"], [429, 130429, null, "retry"], [400, 130429, null, "retry"],
    [429, 131056, null, "retry"], [400, 131056, null, "retry"], [429, null, null, "retry"],
    // not understood, or Meta's own doubt: tried again, as before
    [400, null, null, "retry"], [404, null, null, "retry"], [400, 1, null, "retry"], [400, 131052, null, "retry"], [400, 131053, null, "retry"], [400, 135000, null, "retry"],
    [400, 999999, null, "retry"], [408, null, null, "retry"],
    // the token, a permission, the account or the number: the connector's problem, never the message's
    [401, 190, null, "connector"], [400, 190, null, "connector"], [401, 0, null, "connector"], [403, 10, null, "connector"], [403, 200, null, "connector"],
    [403, 299, null, "connector"], [400, 100, 33, "connector"], [400, 33, null, "connector"], [403, 368, null, "connector"], [403, 131005, null, "connector"],
    [403, 131031, null, "connector"], [400, 131037, null, "connector"], [400, 131042, null, "connector"], [429, 131048, null, "connector"], [400, 131048, null, "connector"],
    [400, 133006, null, "connector"], [400, 133010, null, "connector"], [401, null, null, "connector"], [403, null, null, "connector"], [403, 999999, null, "connector"],
  ];

  it.each(table)("HTTP %i, code %s, subcode %s: %s", (status, code, subcode, kind) => {
    const r = classifyWaError(status, code === null ? null : { code, ...(subcode === null ? {} : { error_subcode: subcode }) });
    expect(r.kind).toBe(kind);
    if (kind === "retry") expect(r.reason).toBeUndefined();
    else expect(r.reason).toMatch(/\S{3}/); // a final or connector answer always says why, in words
  });

  it("codes next to the permission range are not taken for it", () => {
    expect(classifyWaError(400, { code: 199 }).kind).toBe("retry");
    expect(classifyWaError(400, { code: 300 }).kind).toBe("retry");
  });

  it("fails a refused message at once (retry: false) with the reason, Meta's code and its detail", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(400, { error: { message: "(#131047) Re-engagement message", code: 131047,
      error_data: { messaging_product: "whatsapp", details: "Message failed to send because more than 24 hours have passed since the customer last replied to this number." } } }));
    expect(r).toEqual({ ok: false, retry: false, error: "WhatsApp refused it: more than 24 hours have passed since the student last wrote, so only an approved template can be sent. "
      + "It is not sent again automatically. (131047: (#131047) Re-engagement message (Message failed to send because more than 24 hours have passed since the customer last replied to this number.))" });
    const paused = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(400, { error: { message: "Template is paused", code: 132015 } }));
    expect(paused).toMatchObject({ ok: false, retry: false, error: expect.stringMatching(/paused the template.*\(132015: Template is paused\)$/) });
    expect(paused).not.toHaveProperty("connector");
  });

  it("leaves a rate limit to be tried again, exactly as any failure was before", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(429, { error: { message: "Rate limit hit", code: 130429 } }));
    expect(r).toEqual({ ok: false, error: "130429: Rate limit hit" });
  });

  it("marks an expired token as the connector's problem and leaves the message to be tried again", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(401, { error: { message: "Error validating access token: Session has expired", code: 190, error_subcode: 463 } }));
    expect(r).toEqual({ ok: false, connector: true, error: "WhatsApp refused Spark's connection, not this message: the access token has expired or is no longer valid. (190: Error validating access token: Session has expired)" });
    expect(r).not.toHaveProperty("retry");
  });

  it("still treats a 5xx as maybe sent, whatever its code", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(500, { error: { message: "Something went wrong", code: 131000 } }));
    expect(r).toMatchObject({ ok: false, retry: false, error: expect.stringMatching(/may have gone out/) });
    expect(r).not.toHaveProperty("connector");
  });

  it("keeps a long answer from Meta within what the failure column shows", async () => {
    const r = await sendWhatsApp(cfg, "919000000012", text, true, null, answer(400, { error: { message: "x".repeat(900), code: 131026 } }));
    expect(r.error!.length).toBeLessThan(480);
  });
});

describe("webhooks for other numbers (b55)", () => {
  afterEach(() => { vi.unstubAllEnvs(); });
  const change = (id: string, wamid: string) => ({ value: { metadata: { phone_number_id: id, display_phone_number: "91 80000 00000" },
    messages: [{ from: "919000000012", id: wamid, type: "text", text: { body: "hi" } }], statuses: [{ id: `${wamid}.out`, status: "sent", timestamp: "1760000000" }] } });
  const body = { entry: [{ changes: [change("123", "wamid.OURS"), change("999", "wamid.OTHER")] }, { changes: [{ value: { messages: [{ from: "919000000013", id: "wamid.NOMETA", type: "text", text: { body: "x" } }] } }] }] };

  it("reads only changes for Spark's own number", () => {
    const { messages, statuses } = parseWebhook(body, "123");
    expect(messages.map((m) => m.wamid)).toEqual(["wamid.OURS"]);
    expect(statuses.map((s) => s.wamid)).toEqual(["wamid.OURS.out"]);
  });

  it("takes the number from WHATSAPP_PHONE_NUMBER_ID, and reads everything when it is not set", () => {
    vi.stubEnv("WHATSAPP_PHONE_NUMBER_ID", "999");
    expect(parseWebhook(body).messages.map((m) => m.wamid)).toEqual(["wamid.OTHER"]);
    vi.stubEnv("WHATSAPP_PHONE_NUMBER_ID", "");
    expect(parseWebhook(body).messages.map((m) => m.wamid)).toEqual(["wamid.OURS", "wamid.OTHER", "wamid.NOMETA"]);
  });
});
