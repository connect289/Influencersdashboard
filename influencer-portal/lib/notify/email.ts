import "server-only";
import nodemailer, { type Transporter } from "nodemailer";
import { env, type ServerEnv } from "@/lib/env";
import { log } from "@/lib/log";
import { ProviderError, type EmailMessage, type EmailProvider, type SendResult } from "./types";
import { listUnsubscribeHeaders } from "./unsubscribe";

/** Extra mail headers for a message, or undefined when it has none. */
function mailHeaders(m: EmailMessage, entityRef: boolean): Record<string, string> | undefined {
  const headers = {
    ...(entityRef && m.idempotencyKey ? { "X-Entity-Ref-ID": m.idempotencyKey } : {}),
    ...listUnsubscribeHeaders(m.listUnsubscribeUrl),
  };
  return Object.keys(headers).length ? headers : undefined;
}

/** Records messages in memory (tests) and logs that a message was sent, never its content. Refused in production. */
export class MockEmailProvider implements EmailProvider {
  readonly name = "mock";
  readonly sent: EmailMessage[] = [];
  send(message: EmailMessage): Promise<SendResult> {
    this.sent.push(message);
    log.info("email.mock_sent", { subject: message.subject });
    return Promise.resolve({ provider: this.name, id: `mock-${this.sent.length}` });
  }
}

export class SmtpEmailProvider implements EmailProvider {
  readonly name = "smtp";
  private readonly transport: Transporter;
  constructor(
    private readonly from: string,
    config: { host: string; port: number; secure: boolean; user?: string; password?: string },
    /** Tests pass a transport that records what would be sent. */
    transport?: Transporter,
  ) {
    this.transport =
      transport ??
      nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.secure,
        auth: config.user ? { user: config.user, pass: config.password ?? "" } : undefined,
        connectionTimeout: 10_000,
        greetingTimeout: 10_000,
        socketTimeout: 20_000,
      });
  }
  async send(m: EmailMessage): Promise<SendResult> {
    try {
      const info = (await this.transport.sendMail({
        from: this.from,
        to: m.to,
        subject: m.subject,
        html: m.html,
        text: m.text,
        headers: mailHeaders(m, true),
        attachments: m.attachments?.map((a) => ({
          filename: a.filename,
          content: a.content,
          contentType: a.contentType,
        })),
      })) as { messageId?: string };
      return { provider: this.name, id: info.messageId ?? null };
    } catch (e) {
      throw new ProviderError(`SMTP send failed: ${(e as Error).message}`, true);
    }
  }
}

/** Server errors and rate limits are worth retrying; other 4xx answers are permanent unless `retryable` says so. */
async function postJson(
  url: string,
  headers: Record<string, string>,
  body: unknown,
  fetchImpl: typeof fetch,
  retryable: (status: number) => boolean = () => false,
): Promise<Record<string, unknown>> {
  const res = await fetchImpl(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  const text = await res.text();
  if (!res.ok)
    throw new ProviderError(
      `HTTP ${res.status}: ${text.slice(0, 300)}`,
      res.status >= 500 || res.status === 429 || retryable(res.status),
    );
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export class ResendEmailProvider implements EmailProvider {
  readonly name = "resend";
  constructor(
    private readonly from: string,
    private readonly apiKey: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}
  async send(m: EmailMessage): Promise<SendResult> {
    const headers = mailHeaders(m, false);
    const r = await postJson(
      "https://api.resend.com/emails",
      {
        authorization: `Bearer ${this.apiKey}`,
        ...(m.idempotencyKey ? { "idempotency-key": m.idempotencyKey } : {}),
      },
      {
        from: this.from,
        to: [m.to],
        subject: m.subject,
        html: m.html,
        text: m.text,
        ...(headers ? { headers } : {}),
        ...(m.attachments?.length
          ? {
              attachments: m.attachments.map((a) => ({
                filename: a.filename,
                content: a.content.toString("base64"),
              })),
            }
          : {}),
      },
      this.fetchImpl,
      // 409: a request with this idempotency key is still in progress (or was sent with other content). The send may
      // well have happened, so it is retried with the same key, which Resend answers without sending twice.
      (status) => status === 409,
    );
    return { provider: this.name, id: typeof r.id === "string" ? r.id : null };
  }
}

export class BrevoEmailProvider implements EmailProvider {
  readonly name = "brevo";
  constructor(
    private readonly from: string,
    private readonly apiKey: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}
  async send(m: EmailMessage): Promise<SendResult> {
    const match = /^(.*)<([^>]+)>\s*$/.exec(this.from);
    const sender = match?.[2] ? { name: (match[1] ?? "").trim() || undefined, email: match[2] } : { email: this.from };
    const headers = mailHeaders(m, false);
    const r = await postJson(
      "https://api.brevo.com/v3/smtp/email",
      { "api-key": this.apiKey },
      {
        sender,
        to: [{ email: m.to }],
        subject: m.subject,
        htmlContent: m.html,
        textContent: m.text,
        ...(headers ? { headers } : {}),
        ...(m.attachments?.length
          ? {
              attachment: m.attachments.map((a) => ({
                name: a.filename,
                content: a.content.toString("base64"),
              })),
            }
          : {}),
      },
      this.fetchImpl,
    );
    return { provider: this.name, id: typeof r.messageId === "string" ? r.messageId : null };
  }
}

export function emailProviderFrom(e: ServerEnv): EmailProvider {
  switch (e.EMAIL_PROVIDER) {
    case "smtp":
      return new SmtpEmailProvider(e.EMAIL_FROM, {
        host: e.SMTP_HOST ?? "",
        port: e.SMTP_PORT,
        secure: e.SMTP_SECURE === "on",
        user: e.SMTP_USER,
        password: e.SMTP_PASSWORD,
      });
    case "resend":
      return new ResendEmailProvider(e.EMAIL_FROM, e.RESEND_API_KEY ?? "");
    case "brevo":
      return new BrevoEmailProvider(e.EMAIL_FROM, e.BREVO_API_KEY ?? "");
    case "mock":
      return new MockEmailProvider();
  }
}

let provider: EmailProvider | null = null;
export function emailProvider(): EmailProvider {
  provider ??= emailProviderFrom(env());
  return provider;
}
