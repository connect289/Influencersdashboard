import "server-only";
import { siteUrl } from "@/lib/env";
import { googleSa, mailbox, sendGmail, signedJwt } from "@/lib/gmail";
import { plainText, replyOnly } from "@/lib/gmail-inbox";
import { sendMail } from "@/lib/mail";
import { adminClient } from "@/lib/supabase/admin";
import { statusFromReply, supportEmail, ticketFromSubject, type MailRow } from "@/lib/support";
import { supportToken } from "@/lib/support-token";

/**
 * Support tickets ↔ the developer (b31). Out: every message from the CRM side is emailed to the developer with its
 * screenshots, from the support mailbox when one is set (so answers come back to it), else by SMTP. In: answers in the
 * support mailbox carrying [SUP-…] in the subject, from a developer address, are added to the ticket with any
 * "Status:" line applied. The signed link in each email works too, without a mailbox.
 */
export async function sendSupportMail(limit = 10): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("support_mail_take", { p_limit: limit });
  if (error) throw new Error(error.message);
  const sa = googleSa();
  let n = 0;
  for (const r of (data ?? []) as MailRow[]) {
    try {
      const files = [];
      for (const a of r.attachments ?? []) {
        const f = await db.storage.from("b2c-support").download(a.path);
        if (f.data) files.push({ filename: a.name, content: Buffer.from(await f.data.arrayBuffer()), contentType: a.type });
      }
      const m = supportEmail(r, siteUrl(), supportToken(r.ticket_id));
      const to = (r.developer_emails ?? []).join(", ");
      if (r.mailbox && sa) {
        const res = await sendGmail(sa, { from: `Eduwit CRM support <${mailbox(r.mailbox)}>`, to, replyTo: mailbox(r.mailbox), subject: m.subject, text: m.text, attachments: files }, true);
        if (!res.ok) throw new Error(res.error ?? "Gmail refused the message");
      } else {
        const res = await sendMail({ to, subject: m.subject, text: m.text, replyTo: r.mailbox ?? undefined, attachments: files });
        if (!res.sent) throw new Error("email is not configured (SMTP, or the support mailbox with Google)");
      }
      await db.rpc("support_mail_done", { p_message: r.message_id, p_error: null });
      n++;
    } catch (e) {
      await db.rpc("support_mail_done", { p_message: r.message_id, p_error: e instanceof Error ? e.message : String(e) });
    }
  }
  return n;
}

type Part = Parameters<typeof plainText>[0];

export async function readSupportInbox(): Promise<{ answers: number; auto_closed?: number; skipped?: string }> {
  const db = adminClient();
  await db.rpc("support_tick");   // "fixed" tickets close by themselves after the set days
  const sa = googleSa();
  const { data: s } = await db.from("settings").select("value").eq("key", "support").maybeSingle();
  const cfg = (s?.value ?? {}) as { mailbox?: string | null; developer_emails?: string[] };
  if (!sa || !cfg.mailbox) return { answers: 0, skipped: "no support mailbox" };
  const box = mailbox(cfg.mailbox);
  const devs = new Set((cfg.developer_emails ?? []).map((e) => mailbox(e)));
  const tok = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, signal: AbortSignal.timeout(15_000),
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: signedJwt(sa, box, "https://www.googleapis.com/auth/gmail.readonly") }),
  });
  const t = (await tok.json()) as { access_token?: string; error_description?: string };
  if (!t.access_token) return { answers: 0, skipped: `Google refused the token: ${t.error_description ?? tok.status}` };
  const auth = { authorization: `Bearer ${t.access_token}` };
  const { data: c } = await db.rpc("sync_get", { p_key: "support_inbox_after" });
  const after = Number(c ?? 0) || Math.floor(Date.now() / 1000) - 86400;
  const q = new URLSearchParams({ q: `subject:SUP after:${after} -from:${box}`, maxResults: "50" });
  const list = (await (await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages?${q}`, { headers: auth, signal: AbortSignal.timeout(15_000) })).json()) as { messages?: { id: string }[] };
  let answers = 0, newest = after;
  for (const m of list.messages ?? []) {
    const msg = (await (await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${m.id}?format=full`, { headers: auth, signal: AbortSignal.timeout(15_000) })).json()) as
      { id: string; internalDate?: string; payload?: Part & { headers?: { name: string; value: string }[] } };
    newest = Math.max(newest, Math.floor(Number(msg.internalDate ?? 0) / 1000));
    const h = (n: string) => msg.payload?.headers?.find((x) => x.name.toLowerCase() === n)?.value ?? "";
    const ticket = ticketFromSubject(h("subject"));
    const from = mailbox(h("from"));
    if (!ticket || !devs.has(from)) continue;
    const { status, body } = statusFromReply(replyOnly(plainText(msg.payload ?? {})));
    if (!body && !status) continue;
    const { error } = await db.rpc("support_developer_reply", { p: { ticket_id: ticket, body, status, from_email: from, source: "email", external_id: msg.id } });
    if (!error) answers++;
  }
  await db.rpc("sync_set", { p_key: "support_inbox_after", p_value: newest });
  return { answers };
}
