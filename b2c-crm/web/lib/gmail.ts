import { createSign, randomUUID } from "node:crypto";

/**
 * A counsellor's email to a student, sent from their own @eduwit.in mailbox through the Gmail API with Google Workspace
 * domain-wide delegation (audit §8): a service account signs a JWT for the counsellor (sub) with scope gmail.send.
 * Nothing is sent unless live. Pure helpers are unit-tested in gmail.test.ts.
 */

export type GoogleSa = { email: string; privateKey: string };

export function googleSa(): GoogleSa | null {
  const email = process.env.GOOGLE_SA_EMAIL;
  const key = process.env.GOOGLE_SA_PRIVATE_KEY;
  if (!email || !key) return null;
  return { email, privateKey: key.replace(/\\n/g, "\n") };
}

const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

export function signedJwt(sa: GoogleSa, subject: string, scope: string, now = Math.floor(Date.now() / 1000)): string {
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: sa.email, sub: subject, scope, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const sig = createSign("RSA-SHA256").update(`${head}.${claims}`).sign(sa.privateKey);
  return `${head}.${claims}.${b64url(sig)}`;
}

/** RFC 5322 message, base64url as the Gmail API wants it. Header values are stripped of line breaks (header injection). */
export function rawMessage(m: { from: string; to: string; subject: string; text: string; html?: string | null }): string {
  const clean = (s: string) => s.replace(/[\r\n]+/g, " ").trim();
  const boundary = "b2c-" + randomUUID();
  const subject = `=?UTF-8?B?${Buffer.from(clean(m.subject)).toString("base64")}?=`;
  const head = [`From: ${clean(m.from)}`, `To: ${clean(m.to)}`, `Subject: ${subject}`, "MIME-Version: 1.0"];
  const body = m.html
    ? [`Content-Type: multipart/alternative; boundary="${boundary}"`, "", `--${boundary}`, "Content-Type: text/plain; charset=UTF-8", "", m.text,
       `--${boundary}`, "Content-Type: text/html; charset=UTF-8", "", m.html, `--${boundary}--`]
    : ["Content-Type: text/plain; charset=UTF-8", "", m.text];
  return b64url([...head, ...body].join("\r\n"));
}

export async function sendGmail(sa: GoogleSa | null, m: { from: string; to: string; subject: string; text: string; html?: string | null }, live: boolean): Promise<{ ok: boolean; dry_run?: boolean; id?: string; error?: string }> {
  if (!live) return { ok: true, dry_run: true };
  if (!sa) return { ok: false, error: "Gmail is not configured (GOOGLE_SA_EMAIL, GOOGLE_SA_PRIVATE_KEY)." };
  try {
    const tok = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: signedJwt(sa, m.from, "https://www.googleapis.com/auth/gmail.send") }),
      signal: AbortSignal.timeout(15_000),
    });
    const t = (await tok.json()) as { access_token?: string; error_description?: string };
    if (!t.access_token) return { ok: false, error: `Google refused the token: ${t.error_description ?? tok.status}` };
    const res = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/messages/send", {
      method: "POST",
      headers: { authorization: `Bearer ${t.access_token}`, "content-type": "application/json" },
      body: JSON.stringify({ raw: rawMessage(m) }),
      signal: AbortSignal.timeout(15_000),
    });
    const b = (await res.json()) as { id?: string; error?: { message?: string } };
    return res.ok ? { ok: true, id: b.id } : { ok: false, error: b.error?.message ?? `HTTP ${res.status}` };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}
