import { z } from "zod";
import { fetchJson } from "../http.ts";

// Alert email through Resend (D-013): the website's verified domain, Eduwit One's own key. The idempotency key of the
// delivery row goes to Resend too, so a retried send after a lost answer cannot send twice.

export type EmailMessage = {
  from: string;
  to: string;
  subject: string;
  text: string;
  html: string;
  idempotencyKey: string;
};

export interface EmailClient {
  send(message: EmailMessage): Promise<{ id: string }>;
  /** Resend's last event for a sent email (delivered, bounced, delivery_delayed...): T-ALERT's "delivered" step. */
  status(id: string): Promise<{ lastEvent: string | null }>;
}

export const emailSentFixture = z.object({ id: z.string() });
const emailStatusSchema = z.object({ last_event: z.string().nullable().optional() });

export class RealEmailClient implements EmailClient {
  private readonly apiBase: string;
  private readonly key: string;

  constructor(apiBase: string, key: string) {
    this.apiBase = apiBase;
    this.key = key;
  }

  async send(m: EmailMessage) {
    const { json } = await fetchJson(
      "email",
      `${this.apiBase}/emails`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${this.key}`, "Idempotency-Key": m.idempotencyKey },
        body: { from: m.from, to: [m.to], subject: m.subject, text: m.text, html: m.html },
      },
      { timeoutMs: 8000, retries: 1, breakerFailures: 3, breakerCooldownMs: 120_000 },
    );
    return emailSentFixture.parse(json);
  }

  async status(id: string) {
    if (!/^[A-Za-z0-9-]{8,64}$/.test(id)) throw new Error("not a Resend email id");
    const { json } = await fetchJson(
      "email",
      `${this.apiBase}/emails/${id}`,
      { method: "GET", headers: { authorization: `Bearer ${this.key}` } },
      { timeoutMs: 8000, retries: 1, breakerFailures: 3, breakerCooldownMs: 120_000 },
    );
    return { lastEvent: emailStatusSchema.parse(json).last_event ?? null };
  }
}

/** Keeps what it was asked to send; answers with the fixture's id. */
export class MockEmailClient implements EmailClient {
  readonly sent: EmailMessage[] = [];
  private readonly reply: z.infer<typeof emailSentFixture>;

  constructor(reply: z.infer<typeof emailSentFixture>) {
    this.reply = reply;
  }

  async send(m: EmailMessage) {
    this.sent.push(m);
    return this.reply;
  }

  async status() {
    return { lastEvent: "delivered" };
  }
}
