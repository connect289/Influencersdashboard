import "server-only";
import { googleSa, mailbox, signedJwt } from "@/lib/gmail";
import { adminClient } from "@/lib/supabase/admin";

/**
 * Replies to marketing email (spec B6.3): the reconcile job reads the marketing mailbox (settings 'marketing_email'
 * from) through the service account (scope gmail.readonly), passes each new reply to b2c.email_inbound (classified like a
 * WhatsApp reply) and each bounce to b2c.email_event. Pure helpers are unit-tested in gmail-inbox.test.ts.
 */

type Part = { mimeType?: string; body?: { data?: string }; parts?: Part[]; headers?: { name: string; value: string }[] };

export function plainText(p: Part): string {
  if (p.mimeType === "text/plain" && p.body?.data) return Buffer.from(p.body.data, "base64url").toString("utf8");
  for (const c of p.parts ?? []) { const t = plainText(c); if (t) return t; }
  if (p.mimeType === "text/html" && p.body?.data) return Buffer.from(p.body.data, "base64url").toString("utf8").replace(/<[^>]+>/g, " ");
  return "";
}

/** The new part of a reply: quoted history ("> …", "On … wrote:") and signatures cut off. */
export function replyOnly(text: string): string {
  const lines = text.replace(/\r\n?/g, "\n").split("\n");
  const out: string[] = [];
  for (const l of lines) {
    if (/^\s*>/.test(l) || /^On .+wrote:\s*$/i.test(l) || /^-{2,}\s*$/.test(l) || /^-+\s*Original Message/i.test(l)) break;
    out.push(l);
  }
  return out.join("\n").trim().slice(0, 4000);
}

export function bounceEmailId(text: string): number | null {
  const m = text.match(/X-B2C-Email-Id:\s*(\d+)/i);
  return m ? Number(m[1]) : null;
}

export async function readMarketingInbox(): Promise<{ replies: number; bounces: number; skipped?: string }> {
  const sa = googleSa();
  const db = adminClient();
  const { data: setting } = await db.from("settings").select("value").eq("key", "marketing_email").maybeSingle();
  const from = (setting?.value as { from?: string } | null)?.from;
  if (!sa || !from) return { replies: 0, bounces: 0, skipped: "Gmail is not configured" };
  const box = mailbox(from);
  const tok = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: signedJwt(sa, box, "https://www.googleapis.com/auth/gmail.readonly") }),
    signal: AbortSignal.timeout(15_000),
  });
  const t = (await tok.json()) as { access_token?: string; error_description?: string };
  if (!t.access_token) return { replies: 0, bounces: 0, skipped: `Google refused the token: ${t.error_description ?? tok.status}` };
  const auth = { authorization: `Bearer ${t.access_token}` };
  const { data: c } = await db.rpc("sync_get", { p_key: "gmail_inbox_after" });
  const after = Number(c ?? 0) || Math.floor(Date.now() / 1000) - 86400;
  const q = new URLSearchParams({ q: `in:inbox after:${after} -from:${box}`, maxResults: "100" });
  const list = (await (await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages?${q}`, { headers: auth, signal: AbortSignal.timeout(15_000) })).json()) as { messages?: { id: string; threadId: string }[] };
  let replies = 0, bounces = 0, newest = after;
  for (const m of list.messages ?? []) {
    const msg = (await (await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${m.id}?format=full`, { headers: auth, signal: AbortSignal.timeout(15_000) })).json()) as
      { id: string; threadId: string; internalDate?: string; payload?: Part };
    newest = Math.max(newest, Math.floor(Number(msg.internalDate ?? 0) / 1000));
    const h = (n: string) => msg.payload?.headers?.find((x) => x.name.toLowerCase() === n)?.value ?? "";
    const body = plainText(msg.payload ?? {});
    if (/mailer-daemon|postmaster/i.test(h("from"))) {
      const id = bounceEmailId(body);
      if (id) { await db.rpc("email_event", { p_email: id, p_kind: "bounce", p_link: null }); bounces++; }
      continue;
    }
    const { error } = await db.rpc("email_inbound", { p_from: h("from"), p_subject: h("subject"), p_text: replyOnly(body), p_gmail_id: msg.id, p_thread: msg.threadId });
    if (!error) replies++;
  }
  await db.rpc("sync_set", { p_key: "gmail_inbox_after", p_value: newest });
  return { replies, bounces };
}
