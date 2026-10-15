import "server-only";
import { reportConnector } from "@/lib/connector-status";
import { adminClient } from "@/lib/supabase/admin";
import { baseMime, MEDIA_BUCKET, MEDIA_MAX_BYTES, mediaAllowed, mediaDownload, mediaInfo, mediaPath, waConfig, type InboundMedia } from "@/lib/whatsapp";

/**
 * Files students send on WhatsApp (spec B8.5, B8.8, C1), part of the every-minute job: b2c.wa_media_take hands out up
 * to ten inbound messages with a media id; each is looked up on the Graph API, downloaded with the token and kept in the
 * private bucket at leads/<lead_id>/wa/<message_id>-<name>, then b2c.wa_media_stored records the path (counsellors open
 * it by signed link and attach it to the application checklist). The bucket takes PDFs and images up to 4 MB; any other
 * file (voice notes, videos, Word files) is not downloaded and keeps an error the inbox shows. Without the WhatsApp
 * configuration nothing is taken, so no attempt is spent.
 */
export async function runWaMediaJobs(limit = 10): Promise<{ stored: number; failed: number; skipped?: string }> {
  const cfg = waConfig();
  if (!cfg) return { stored: 0, failed: 0, skipped: "WhatsApp is not configured" };
  const db = adminClient();
  const { data, error } = await db.rpc("wa_media_take", { p_limit: limit });
  if (error) throw new Error(`wa_media_take: ${error.message}`);
  let stored = 0, failed = 0, graphOk = 0, graphFailed = 0, lastError = "";
  for (const m of (data ?? []) as { id: number; lead_id: number; media: Partial<InboundMedia> & Record<string, unknown> }[]) {
    let path: string | null = null, err: string | null = null;
    try {
      if (!m.media?.id) throw new Error("no media id");
      if (m.media.mime_type && !mediaAllowed(m.media.mime_type)) throw new Error(`not stored: ${baseMime(m.media.mime_type)} files are not kept (PDF and images only)`);
      let info, file;
      try {
        info = await mediaInfo(cfg, String(m.media.id));
        if (!mediaAllowed(info.mime_type ?? m.media.mime_type)) throw new Error(`not stored: ${baseMime(info.mime_type) || "unknown"} files are not kept (PDF and images only)`);
        if (info.file_size && info.file_size > MEDIA_MAX_BYTES) throw new Error("not stored: larger than 4 MB");
        file = await mediaDownload(cfg, info.url);
        graphOk++;
      } catch (e) {
        if (!/^not stored/.test((e as Error).message)) { graphFailed++; lastError = (e as Error).message; }
        throw e;
      }
      const mime = baseMime(info.mime_type ?? m.media.mime_type);
      path = mediaPath(m.lead_id, m.id, { filename: m.media.filename ?? null, mime_type: mime, type: m.media.type ?? null });
      const up = await db.storage.from(MEDIA_BUCKET).upload(path, file.bytes, { contentType: mime, upsert: true });
      if (up.error) throw new Error(`storage: ${up.error.message}`);
    } catch (e) {
      err = e instanceof Error ? e.message : String(e);
      path = null;
    }
    const { error: doneError } = await db.rpc("wa_media_stored", { p_message: m.id, p_path: path, p_error: err });
    if (doneError) throw new Error(`wa_media_stored: ${doneError.message}`);
    if (err) failed++;
    else stored++;
  }
  if (graphOk) await reportConnector("whatsapp", true, { media: { fetched: graphOk, at: new Date().toISOString() } });
  if (graphFailed) await reportConnector("whatsapp", false, null, `media download: ${lastError}`);
  return { stored, failed };
}
