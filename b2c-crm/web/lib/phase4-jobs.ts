import "server-only";
import { CalendarClient, eventBody, type CalendarRow } from "@/lib/calendar";
import { siteUrl } from "@/lib/env";
import { googleSa } from "@/lib/gmail";
import { adminClient } from "@/lib/supabase/admin";
import { exotelConfig, fetchRecording } from "@/lib/telephony";

/**
 * The Phase 4 side of the every-minute job: call recordings (fetched from the provider into the private bucket, removed
 * after the retention period) and follow-ups pushed to Google Calendar. Each part fails on its own.
 */
export async function runPhase4Jobs(): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const part = async (name: string, fn: () => Promise<unknown>) => {
    try { out[name] = await fn(); } catch (e) { out[`${name}_error`] = e instanceof Error ? e.message : String(e); }
  };
  await part("recordings", recordings);
  await part("recordings_expired", expired);
  await part("calendar", calendar);
  return out;
}

async function recordings(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("recordings_take", { p_limit: 5 });
  if (error) throw new Error(error.message);
  const cfg = exotelConfig();
  let n = 0;
  for (const r of (data ?? []) as { id: number; lead_id: number; provider: string; recording_url: string }[]) {
    try {
      const f = await fetchRecording(r.provider, r.recording_url, cfg);
      const path = `calls/${r.lead_id}/${r.id}.${f.ext}`;
      const up = await db.storage.from("b2c-recordings").upload(path, f.bytes, { contentType: f.contentType, upsert: true });
      if (up.error) throw new Error(up.error.message);
      await db.rpc("recording_saved", { p_call: r.id, p_path: path, p_error: null });
      n++;
    } catch (e) {
      await db.rpc("recording_saved", { p_call: r.id, p_path: null, p_error: e instanceof Error ? e.message : String(e) });
    }
  }
  return n;
}

async function expired(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("recordings_expired", { p_limit: 50 });
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as { id: number; path: string }[];
  if (!rows.length) return 0;
  const rm = await db.storage.from("b2c-recordings").remove(rows.map((r) => r.path));
  if (rm.error) throw new Error(rm.error.message);
  for (const r of rows) await db.rpc("recording_removed", { p_call: r.id });
  return rows.length;
}

async function calendar(): Promise<number | string> {
  const sa = googleSa();
  if (!sa) return "Google service account not set";
  const db = adminClient();
  const { data, error } = await db.rpc("calendar_take", { p_limit: 25 });
  if (error) throw new Error(error.message);
  const client = new CalendarClient(sa);
  let n = 0;
  for (const r of (data ?? []) as CalendarRow[]) {
    try {
      if (r.old_event_id && r.old_email) await client.remove(r.old_email, r.old_event_id);
      if (r.want === "remove") {
        if (r.event_id && r.email) await client.remove(r.email, r.event_id);
        await db.rpc("calendar_done", { p_task: r.task_id, p_event_id: null, p_etag: null, p_error: null });
      } else {
        if (!r.email) throw new Error("the follow-up has no owner");
        const e = await client.upsert(r.email, r.event_id, eventBody(r, siteUrl()));
        await db.rpc("calendar_done", { p_task: r.task_id, p_event_id: e.id, p_etag: e.etag, p_error: null });
      }
      n++;
    } catch (e) {
      await db.rpc("calendar_done", { p_task: r.task_id, p_event_id: null, p_etag: null, p_error: e instanceof Error ? e.message : String(e) });
    }
  }
  return n;
}
