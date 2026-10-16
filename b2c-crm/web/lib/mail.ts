import "server-only";
import nodemailer, { type Transporter } from "nodemailer";

/**
 * Outgoing system email (sign-in codes, alerts). SMTP through Google Workspace (smtp-relay.gmail.com, or a Workspace
 * mailbox with an app password). Counsellors' own emails to students go through lib/gmail (domain-wide delegation),
 * not through here. Without SMTP settings the message is logged on the server instead (local development).
 */
export type Mail = { to: string; subject: string; text: string; html?: string; replyTo?: string; attachments?: { filename: string; content: Buffer | string; contentType?: string }[] };

let transport: Transporter | null = null;

function smtp(): Transporter | null {
  const host = process.env.SMTP_HOST;
  if (!host) return null;
  transport ??= nodemailer.createTransport({
    host,
    port: Number(process.env.SMTP_PORT ?? 587),
    secure: process.env.SMTP_PORT === "465",
    auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD } : undefined,
  });
  return transport;
}

export async function sendMail(m: Mail): Promise<{ sent: boolean }> {
  const t = smtp();
  if (!t) {
    // Only a local developer sees the content (it can carry a sign-in code); a deployment without SMTP logs nothing secret.
    if (process.env.NODE_ENV === "development") console.info(`[mail:dry-run] to=${m.to} subject=${JSON.stringify(m.subject)}`);
    else console.warn("[mail] SMTP is not configured: message not sent");
    return { sent: false };
  }
  await t.sendMail({ from: process.env.SMTP_FROM ?? "Eduwit Spark <no-reply@eduwit.in>", ...m });
  return { sent: true };
}

export function codeEmail(code: string, name: string | null): Mail & { to: "" } {
  const hi = name ? `Hi ${name.split(" ")[0]},` : "Hi,";
  return {
    to: "",
    subject: `${code} is your Eduwit Spark sign-in code`,
    text: `${hi}\n\nYour sign-in code is ${code}. It expires in 10 minutes.\n\nIf you did not try to sign in, tell the Admin at once.\n\nEduwit Spark`,
  };
}

export function passwordEmail(link: string, name: string | null): Mail & { to: "" } {
  const hi = name ? `Hi ${name.split(" ")[0]},` : "Hi,";
  return {
    to: "",
    subject: "Set your Eduwit Spark password",
    text: `${hi}\n\nOpen this link to set your Eduwit Spark password. It works once, for one hour:\n\n${link}\n\nAfter that you sign in with your email and the new password, and we email you a 6-digit code as usual.\n\nIf you did not ask for this, ignore this email and tell the Admin.\n\nEduwit Spark`,
  };
}

