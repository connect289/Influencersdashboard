import "server-only";
import * as b2b from "@/lib/b2b";
import { batchDone, chunks, feedEnvelope, intakeBody, singleDone, toBatchItem, type DoneResult, type OutboxItem } from "@/lib/b2b-map";
import { liveMode } from "@/lib/env";
import { googleSa, sendGmail } from "@/lib/gmail";
import { adminClient } from "@/lib/supabase/admin";
import { sendWhatsApp, waConfig, type WaPayload } from "@/lib/whatsapp";

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

    for (const o of items.filter((i) => i.kind === "event")) {
      const r = await b2b.postEvent(o.body);
      results.push(singleDone(o, r.status, r.body));
    }
    for (const o of items.filter((i) => i.kind === "route")) {
      const r = await b2b.routeToPartners(o.lead_id!, String(o.body.reason ?? ""));
      results.push(singleDone(o, r.status, r.body));
    }
    for (const o of items.filter((i) => i.kind === "intake")) {
      const r = await b2b.intake(intakeBody(o.body, o.occurred_at), o.request_id);
      results.push(singleDone(o, r.status, r.body));
    }
    const writes = items.filter((i) => i.kind === "update" || i.kind === "activity");
    if (mode === "urgent") {
      for (const o of writes) {
        const r = o.kind === "update"
          ? await b2b.patchLead(o.lead_id!, o.request_id, (o.body.set as Record<string, unknown>) ?? {}, o.actor)
          : await b2b.postActivity(o.lead_id!, o.request_id, o.body, o.actor);
        results.push(singleDone(o, r.status, r.body));
      }
    } else {
      for (const part of chunks(writes, 200)) {
        const r = await b2b.batch(part.map(toBatchItem));
        results.push(...batchDone(part, r.status, r.body));
      }
    }

    if (results.length) {
      const { error: doneError } = await db.rpc("outbox_done", { p_results: results });
      if (doneError) throw new Error(`outbox_done: ${doneError.message}`);
    }
    out.ok = results.filter((r) => r.ok).length;
    out.failed = results.length - out.ok;
  }

  // Messages to students: WhatsApp and counsellors' emails. Dry run unless live (env and Settings, never test leads).
  const { data: sends, error: takeError } = await db.rpc("send_take", { p_limit: 50 });
  if (takeError) throw new Error(`send_take: ${takeError.message}`);
  const sendResults: Record<string, unknown>[] = [];
  const wa = waConfig();
  const sa = googleSa();
  for (const s of (sends ?? []) as { id: number; channel: "whatsapp" | "email"; to: string; payload: Record<string, unknown>; live: boolean }[]) {
    const live = liveMode() && s.live;
    const r = s.channel === "whatsapp"
      ? await sendWhatsApp(wa, s.to, s.payload as unknown as WaPayload, live)
      : await sendGmail(sa, { from: String(s.payload.from), to: s.to, subject: String(s.payload.subject ?? ""), text: String(s.payload.text ?? ""), html: (s.payload.html as string | null) ?? null }, live);
    sendResults.push({ id: s.id, ok: r.ok, dry_run: r.dry_run ?? false, wamid: "wamid" in r ? r.wamid : undefined, error: r.error });
    if (!r.ok) out.send_failed!++;
    else if (r.dry_run) out.dry_run!++;
    else out.sent!++;
  }
  if (sendResults.length) {
    const { error } = await db.rpc("send_done", { p_results: sendResults });
    if (error) throw new Error(`send_done: ${error.message}`);
  }
  return out;
}

/**
 * Catch-up (every 5 minutes): the hand-off news feed and the lead change feed, from the stored cursors. A missed webhook
 * can then never lose a lead. Entries go through b2c.handoff_receive, which processes each envelope id once.
 */
export async function runReconcile(): Promise<Record<string, number>> {
  const db = adminClient();
  const out: Record<string, number> = { handoffs: 0, changes: 0 };
  if (!b2b.b2bReady()) return out;
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
  return out;
}
