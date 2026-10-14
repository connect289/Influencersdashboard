import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { messageBody, parseWebhook, sendWhatsApp, verifyMetaSignature } from "./whatsapp";

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
