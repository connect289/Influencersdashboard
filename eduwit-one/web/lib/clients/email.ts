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
}

export const emailSentFixture = z.object({ id: z.string() });

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
}
