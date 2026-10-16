import { MAILPIT } from "./env";

interface MailSummary {
  ID: string;
  Created: string;
  Subject: string;
}

/** Waits for the newest email to `to` received after `since`, and returns its text body. */
export async function waitForEmail(
  to: string,
  since: Date,
  timeoutMs = 20_000,
): Promise<{ subject: string; text: string }> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const res = await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${to}"`)}&limit=5`);
    if (res.ok) {
      const body = (await res.json()) as { messages?: MailSummary[] };
      const fresh = (body.messages ?? []).filter((m) => new Date(m.Created).getTime() >= since.getTime() - 1000);
      const latest = fresh[0];
      if (latest) {
        const msg = (await (await fetch(`${MAILPIT}/api/v1/message/${latest.ID}`)).json()) as {
          Text: string;
          Subject: string;
        };
        return { subject: msg.Subject, text: msg.Text };
      }
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`No email to ${to} within ${timeoutMs} ms`);
}

export function sixDigitCode(text: string): string {
  const m = /\b(\d{6})\b/.exec(text);
  if (!m?.[1]) throw new Error("no 6-digit code in the email");
  return m[1];
}
