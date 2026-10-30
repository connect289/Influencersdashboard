import "server-only";
import nodemailer from "nodemailer";
import { env, isDeployed } from "../env";
import { log } from "../log";
import type { Rendered } from "./templates";

/**
 * Transactional email adapter (S-12, D-017): "smtp" (e.g. Google Workspace relay; Mailpit locally), "resend", or
 * "console" (a developer machine only: prints the message so codes can be entered locally).
 */
export interface EmailSender {
  send(to: string, message: Rendered, opts?: { idempotencyKey?: string }): Promise<{ id: string }>;
}

class ConsoleSender implements EmailSender {
  async send(to: string, m: Rendered) {
    // A deployed site (production or preview) has no console mailbox: pretending to send would tell a student "we sent
    // you a code" that never arrives, and printing the message would put the address and the code (it is in the
    // subject) in the hosting logs. Fail instead, so the form says the code could not be sent and the log says why.
    if (isDeployed()) {
      log("error", "email.not_configured", { provider: env().EMAIL_PROVIDER });
      throw new Error("No email provider configured (EMAIL_PROVIDER smtp with EMAIL_SMTP_HOST, or resend with RESEND_API_KEY)");
    }
    const id = `console-${crypto.randomUUID()}`;
    console.info(`[email:console] to=${to} subject="${m.subject}"`);
    log("info", "email.sent", { provider: "console", id });
    return { id };
  }
}

/** Google shows an app password as four groups ("abcd efgh ijkl mnop"); the spaces are display only. */
export function smtpPassword(raw: string | undefined): string {
  const v = raw ?? "";
  return /^[a-z]{4}( [a-z]{4}){3}$/i.test(v) ? v.replace(/ /g, "") : v;
}

class SmtpSender implements EmailSender {
  private t = nodemailer.createTransport({
    host: env().EMAIL_SMTP_HOST,
    port: env().EMAIL_SMTP_PORT,
    secure: env().EMAIL_SMTP_PORT === 465,
    auth: env().EMAIL_SMTP_USER ? { user: env().EMAIL_SMTP_USER!, pass: smtpPassword(env().EMAIL_SMTP_PASSWORD) } : undefined,
    connectionTimeout: 8000,
    greetingTimeout: 8000,
    socketTimeout: 10000,
  });
  async send(to: string, m: Rendered) {
    const info = await this.t.sendMail({ from: env().EMAIL_FROM, to, subject: m.subject, text: m.text, html: m.html });
    log("info", "email.sent", { provider: "smtp", id: info.messageId });
    return { id: info.messageId };
  }
}

class ResendSender implements EmailSender {
  async send(to: string, m: Rendered, opts?: { idempotencyKey?: string }) {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env().RESEND_API_KEY}`,
        "content-type": "application/json",
        ...(opts?.idempotencyKey ? { "idempotency-key": opts.idempotencyKey } : {}),
      },
      body: JSON.stringify({ from: env().EMAIL_FROM, to: [to], subject: m.subject, text: m.text, html: m.html }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) throw new Error(`resend ${res.status}`);
    const j = (await res.json()) as { id: string };
    log("info", "email.sent", { provider: "resend", id: j.id });
    return { id: j.id };
  }
}

/** The provider that actually sends: "console" when none is chosen or the chosen one lacks its settings. */
export function emailProvider(): "smtp" | "resend" | "console" {
  const e = env();
  if (e.EMAIL_PROVIDER === "smtp" && e.EMAIL_SMTP_HOST) return "smtp";
  if (e.EMAIL_PROVIDER === "resend" && e.RESEND_API_KEY) return "resend";
  return "console";
}

let sender: EmailSender | null = null;
export function email(): EmailSender {
  if (sender) return sender;
  const p = emailProvider();
  sender = p === "smtp" ? new SmtpSender() : p === "resend" ? new ResendSender() : new ConsoleSender();
  return sender;
}

/** For tests. */
export function setEmailSender(s: EmailSender | null) {
  sender = s;
}
