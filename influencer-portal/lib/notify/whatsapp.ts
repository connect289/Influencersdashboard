import "server-only";
import { env, type ServerEnv } from "@/lib/env";
import { log } from "@/lib/log";
import { ProviderError, type SendResult, type WhatsAppProvider, type WhatsAppTemplateMessage } from "./types";

export class MockWhatsAppProvider implements WhatsAppProvider {
  readonly name = "mock";
  readonly sent: WhatsAppTemplateMessage[] = [];
  sendTemplate(m: WhatsAppTemplateMessage): Promise<SendResult> {
    this.sent.push(m);
    log.info("whatsapp.mock_sent", { template: m.template });
    return Promise.resolve({ provider: this.name, id: `mock-${this.sent.length}` });
  }
}

/** Meta WhatsApp Cloud API, approved template messages only (business-initiated). */
export class MetaWhatsAppProvider implements WhatsAppProvider {
  readonly name = "meta";
  constructor(
    private readonly phoneNumberId: string,
    private readonly token: string,
    private readonly apiVersion: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}
  async sendTemplate(m: WhatsAppTemplateMessage): Promise<SendResult> {
    if (!/^[1-9]\d{9,14}$/.test(m.to)) throw new ProviderError("invalid recipient number", false);
    const res = await this.fetchImpl(`https://graph.facebook.com/${this.apiVersion}/${this.phoneNumberId}/messages`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.token}`, "content-type": "application/json" },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: m.to,
        type: "template",
        template: {
          name: m.template,
          language: { code: m.language },
          components: m.params.length
            ? [{ type: "body", parameters: m.params.map((text) => ({ type: "text", text })) }]
            : [],
        },
      }),
      signal: AbortSignal.timeout(15_000),
    });
    const body = (await res.json().catch(() => ({}))) as {
      messages?: { id?: string }[];
      error?: { message?: string };
    };
    if (!res.ok)
      throw new ProviderError(
        `Meta ${res.status}: ${body.error?.message ?? "error"}`,
        res.status >= 500 || res.status === 429,
      );
    return { provider: this.name, id: body.messages?.[0]?.id ?? null };
  }
}

export function whatsAppProviderFrom(e: ServerEnv): WhatsAppProvider {
  return e.WHATSAPP_PROVIDER === "meta"
    ? new MetaWhatsAppProvider(e.WHATSAPP_PHONE_NUMBER_ID ?? "", e.WHATSAPP_TOKEN ?? "", e.WHATSAPP_API_VERSION)
    : new MockWhatsAppProvider();
}

let provider: WhatsAppProvider | null = null;
export function whatsAppProvider(): WhatsAppProvider {
  provider ??= whatsAppProviderFrom(env());
  return provider;
}
