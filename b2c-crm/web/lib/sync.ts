import "server-only";
import * as b2b from "@/lib/b2b";
import { batchDone, chunks, feedEnvelope, intakeBody, singleDone, toBatchItem, type DoneResult, type OutboxItem } from "@/lib/b2b-map";
import { ConnectorTally, reportConnector } from "@/lib/connector-status";
import { liveMode, siteUrl } from "@/lib/env";
import { marketingEmail } from "@/lib/marketing-email";
import { googleSa, sendGmail, type GmailMessage, type MailAttachment } from "@/lib/gmail";
import { UserGmail } from "@/lib/gmail-user";
import { parseAttachments, renderAttachment } from "@/lib/money-pdf";
import { salesEmail } from "@/lib/sales-email";
import { adminClient } from "@/lib/supabase/admin";
import { MEDIA_BUCKET, sendWhatsApp, waConfig, type WaPayload } from "@/lib/whatsapp";

/** A B2B answer that says the link itself is broken (unreachable, refused credentials, overloaded), not the item. */
const b2bDown = (status: number) => status === 0 || status === 401 || status === 403 || status === 429 || status >= 500;

/** Signed links for files sent on WhatsApp live this long: Meta fetches the file when it sends. */
const MEDIA_LINK_SECONDS = 15 * 60;

type SendItem = { id: number; channel: "whatsapp" | "email"; lead_id: number | null; to: string; payload: Record<string, unknown>; purpose: string | null; live: boolean };
type SendOutcome = { ok: boolean; dry_run?: boolean; wamid?: string; id?: string; error?: string };

/**
 * The B2C → B2B sync (decision K2, K14). mode "urgent" (every minute): events (consent, opt-out, erasure, assignments),
 * partner routing and new students, plus any urgent update. mode "batch" (every 15 minutes): everything else, merged to
 * one update per lead, in calls of up to 200 items. Each answer goes back to b2c.outbox_done, which decides retry,
 * conflict, refusal or success and caches the record B2B returns.
 */
export async function runSync(mode: "urgent" | "batch"): Promise<Record<string, number>> {
  const db = adminClient();
  const out: Record<string, number> = { taken: 0, ok: 0, failed: 0, sent: 0, dry_run: 0, send_failed: 0 };

  if (b2b.b2bReady()) {
    const { data, error } = await db.rpc("outbox_take", { p_mode: mode, p_limit: mode === "batch" ? 2000 : 400 });
    if (error) throw new Error(`outbox_take: ${error.message}`);
    const items = (data ?? []) as OutboxItem[];
    out.taken = items.length;
    const results: DoneResult[] = [];
    // connector health: whether the B2B CRM answered at all (a refused or conflicting item is the item's problem)
    let calls = 0, down = 0, downError = "";
    const seen = <T extends b2b.B2bAnswer>(r: T): T => {
      calls++;
      if (b2bDown(r.status)) { down++; downError = `HTTP ${r.status}${r.body.error ? `: ${String(r.body.error)}` : ""}`; }
      return r;
    };

    for (const o of items.filter((i) => i.kind === "event")) {
      const r = seen(await b2b.postEvent(o.body));
      results.push(singleDone(o, r.status, r.body));
    }
    for (const o of items.filter((i) => i.kind === "route")) {
      const r = seen(await b2b.routeToPartners(o.lead_id!, String(o.body.reason ?? "")));
      results.push(singleDone(o, r.status, r.body));
    }
    for (const o of items.filter((i) => i.kind === "intake")) {
      const r = seen(await b2b.intake(intakeBody(o.body, o.occurred_at), o.request_id));
      results.push(singleDone(o, r.status, r.body));
    }
    const writes = items.filter((i) => i.kind === "update" || i.kind === "activity");
    if (mode === "urgent") {
      for (const o of writes) {
        const r = seen(o.kind === "update"
          ? await b2b.patchLead(o.lead_id!, o.request_id, (o.body.set as Record<string, unknown>) ?? {}, o.actor)
          : await b2b.postActivity(o.lead_id!, o.request_id, o.body, o.actor));
        results.push(singleDone(o, r.status, r.body));
      }
    } else {
      for (const part of chunks(writes, 200)) {
        const r = seen(await b2b.batch(part.map(toBatchItem)));
        results.push(...batchDone(part, r.status, r.body));
      }
    }
    if (calls) {
      const detail = { outbox: { mode, calls, failed: down, at: new Date().toISOString() } };
      if (calls > down) await reportConnector("b2b", true, detail);
      if (down) await reportConnector("b2b", false, detail, downError);
    }

    if (results.length) {
      const { error: doneError } = await db.rpc("outbox_done", { p_results: results });
      if (doneError) throw new Error(`outbox_done: ${doneError.message}`);
    }
    out.ok = results.filter((r) => r.ok).length;
    out.failed = results.length - out.ok;
  }

  // Messages: WhatsApp (students inside or outside the window, and staff alerts to a person's own number) and email
  // (counsellors', system and marketing). Dry run unless live (env and Settings, never test leads or test invoices).
  const { data: sends, error: takeError } = await db.rpc("send_take", { p_limit: 50 });
  if (takeError) throw new Error(`send_take: ${takeError.message}`);
  const sendResults: Record<string, unknown>[] = [];
  const ctx: SendContext = { db, wa: waConfig(), sa: googleSa(), userGmail: new UserGmail(db), tally: new ConnectorTally() };
  for (const s of (sends ?? []) as SendItem[]) {
    const live = liveMode() && s.live;
    let r: SendOutcome;
    try {
      r = s.channel === "whatsapp" ? await sendWa(ctx, s, live) : await sendEmail(ctx, s, live);
    } catch (e) {
      r = { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
    sendResults.push({ id: s.id, ok: r.ok, dry_run: r.dry_run ?? false, wamid: r.wamid, error: r.error });
    if (!r.ok) out.send_failed!++;
    else if (r.dry_run) out.dry_run!++;
    else out.sent!++;
  }
  if (sendResults.length) {
    const { error } = await db.rpc("send_done", { p_results: sendResults });
    if (error) throw new Error(`send_done: ${error.message}`);
  }
  await ctx.tally.report();
  return out;
}

type SendContext = { db: ReturnType<typeof adminClient>; wa: ReturnType<typeof waConfig>; sa: ReturnType<typeof googleSa>; userGmail: UserGmail; tally: ConnectorTally };

/**
 * One WhatsApp item. A staff alert (purpose staff_alert, no lead) is an approved template to a staff member's own
 * number: no student checks or quiet hours apply here (b2c.staff_wa_tick chose it). A file stored for the lead goes as
 * a short-lived signed link from the private bucket; a brochure link goes as it is.
 */
async function sendWa(ctx: SendContext, s: SendItem, live: boolean): Promise<SendOutcome> {
  const p = s.payload as unknown as WaPayload;
  let link: string | null = null;
  if (p.type === "media" && live && p.path) {
    if (!s.lead_id || !p.path.startsWith(`leads/${s.lead_id}/`)) return { ok: false, error: "the file is not in this lead's folder" };
    const { data, error } = await ctx.db.storage.from(MEDIA_BUCKET).createSignedUrl(p.path, MEDIA_LINK_SECONDS);
    if (error || !data?.signedUrl) return { ok: false, error: `the file could not be opened: ${error?.message ?? "no link"}` };
    link = data.signedUrl;
  }
  const r = await sendWhatsApp(ctx.wa, s.to, p, live, link);
  if (live && ctx.wa && !r.dry_run) ctx.tally.add("whatsapp", r.ok, r.error, { last_send: { purpose: s.purpose, ok: r.ok } });
  return r;
}

/**
 * One email. Attachments named in the payload (an invoice or a run statement) are rendered now and attached; such
 * emails have no lead. A counsellor's email goes from their own Gmail connection when they have one, else (or if that
 * fails) by domain-wide delegation as before.
 */
async function sendEmail(ctx: SendContext, s: SendItem, live: boolean): Promise<SendOutcome> {
  const p = s.payload;
  const files: MailAttachment[] = [];
  let test = false;
  for (const a of parseAttachments(p.attachments)) {
    const f = await renderAttachment(a, ctx.db);
    files.push({ filename: f.filename, content: f.content, contentType: f.contentType });
    test ||= f.test;
  }
  const m: GmailMessage = { ...emailOf(s), ...(files.length ? { attachments: files } : {}) };
  if (!live || test) return { ok: true, dry_run: true };
  const fromUser = typeof p.from_user === "string" ? p.from_user : null;
  if (fromUser && s.purpose === "sales") {
    const own = await ctx.userGmail.send(fromUser, m);
    if (own?.ok) return own;
  }
  const r = await sendGmail(ctx.sa, m, true);
  if (ctx.sa) ctx.tally.add(p.marketing ? "gmail_marketing" : "gmail_system", r.ok, r.error);
  return r;
}

/**
 * Catch-up (every 5 minutes): the hand-off news feed and the lead change feed, from the stored cursors. A missed webhook
 * can then never lose a lead. Entries go through b2c.handoff_receive, which processes each envelope id once.
 */
export async function runReconcile(): Promise<Record<string, number>> {
  const out: Record<string, number> = { handoffs: 0, changes: 0 };
  if (!b2b.b2bReady()) return out;
  try {
    await reconcileFeeds(out);
  } catch (e) {
    await reportConnector("b2b", false, null, e instanceof Error ? e.message : String(e));
    throw e;
  }
  await reportConnector("b2b", true, { feeds: { handoffs: out.handoffs, changes: out.changes, at: new Date().toISOString() } });
  return out;
}

async function reconcileFeeds(out: Record<string, number>): Promise<void> {
  const db = adminClient();
  const cursor = async (key: string) => {
    const { data } = await db.rpc("sync_get", { p_key: key });
    return typeof data === "number" ? data : data === null || data === undefined ? null : Number(data);
  };

  let after = await cursor("handoffs_after");
  for (let page = 0; page < 10; page++) {
    const r = await b2b.handoffs(after, 200);
    if (r.status !== 200) throw new Error(`handoffs feed: HTTP ${r.status} ${String(r.body.error ?? "")}`);
    const events = (r.body.events as Record<string, unknown>[] | undefined) ?? [];
    for (const env of events) {
      const { error } = await db.rpc("handoff_receive", { p_env: env, p_via: "feed" });
      if (error) throw new Error(`handoff_receive: ${error.message}`);
      out.handoffs!++;
    }
    const next = Number(r.body.next_after ?? after ?? 0);
    if (next !== after) await db.rpc("sync_set", { p_key: "handoffs_after", p_value: next });
    after = next;
    if (events.length === 0) break;
  }

  let feed = (await cursor("feed_after")) ?? 0;
  for (let page = 0; page < 10; page++) {
    const r = await b2b.changes(feed, 200);
    if (r.status !== 200) throw new Error(`change feed: HTTP ${r.status} ${String(r.body.error ?? "")}`);
    const result = (r.body.result ?? r.body) as { leads?: Record<string, unknown>[]; next_after?: number };
    const leads = result.leads ?? [];
    for (const l of leads) {
      const { error } = await db.rpc("handoff_receive", { p_env: feedEnvelope(l as never), p_via: "feed" });
      if (error) throw new Error(`handoff_receive (feed): ${error.message}`);
      out.changes!++;
    }
    const next = Number(result.next_after ?? feed);
    if (next !== feed) await db.rpc("sync_set", { p_key: "feed_after", p_value: next });
    feed = next;
    if (leads.length === 0) break;
  }
  await db.rpc("sync_set", { p_key: "last_reconcile_at", p_value: new Date().toISOString() });
}

/**
 * A queued email as sent: a counsellor's as written with its links tracked (no pixel); a system one (invoice, statement,
 * assignment) as written; a marketing one with tracked links, footer and unsubscribe header.
 */
function emailOf(s: { to: string; lead_id?: number | null; purpose?: string | null; payload: Record<string, unknown> }): GmailMessage {
  const p = s.payload;
  const base = { from: String(p.from), to: s.to, subject: String(p.subject ?? ""), replyTo: (p.reply_to as string | null) ?? null };
  if (!p.marketing && s.purpose === "sales" && Number(p.email_id) > 0 && s.lead_id) {
    try {
      return { ...base, ...salesEmail({ emailId: Number(p.email_id), text: String(p.text ?? ""), html: (p.html as string | null) ?? null, site: siteUrl() }) };
    } catch (e) {
      console.warn("[sync] sales email links not tracked:", e instanceof Error ? e.message : String(e)); // no LINK_SECRET: send as written
    }
  }
  if (!p.marketing) return { ...base, text: String(p.text ?? ""), html: (p.html as string | null) ?? null };
  const m = marketingEmail({ emailId: Number(p.email_id), leadId: Number(p.lead_id), text: String(p.text ?? ""), site: siteUrl() });
  return { ...base, text: m.text, html: m.html, headers: m.headers };
}
