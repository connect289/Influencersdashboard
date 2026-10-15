import "server-only";
import { exportColumns, exportFile, type ExportFormat } from "@/lib/lead-export";
import { adminClient } from "@/lib/supabase/admin";

/**
 * The leads side of the every-minute job (b40): files of erased students removed through the storage API, and large
 * exports written to the private bucket for an expiring link. Each part fails on its own.
 */
export async function runLeadJobs(): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const part = async (name: string, fn: () => Promise<unknown>) => {
    try { out[name] = await fn(); } catch (e) { out[`${name}_error`] = e instanceof Error ? e.message : String(e); }
  };
  await part("erased_files", erasedFiles);
  await part("exports", exportsJob);
  return out;
}

export const EXPORT_BUCKET = "b2c-exports";
const PAGE = 500;
const MAX_ROWS = 200_000;

async function erasedFiles(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("erase_files_take", { p_limit: 20 });
  if (error) throw new Error(error.message);
  let n = 0;
  for (const f of (data ?? []) as { id: number; bucket: string; path: string }[]) {
    const rm = await db.storage.from(f.bucket).remove([f.path]);
    await db.rpc("erase_file_done", { p_id: f.id, p_error: rm.error ? rm.error.message : null });
    if (!rm.error) n++;
  }
  return n;
}

let bucketReady = false;
async function ensureBucket() {
  if (bucketReady) return;
  const db = adminClient();
  const { data } = await db.storage.getBucket(EXPORT_BUCKET);
  if (!data) {
    const { error } = await db.storage.createBucket(EXPORT_BUCKET, { public: false });
    if (error && !/already exists/i.test(error.message)) throw new Error(`the ${EXPORT_BUCKET} bucket could not be created: ${error.message}`);
  }
  bucketReady = true;
}

type ExportJob = { id: number; user_id: string; params: { columns?: unknown }; format: ExportFormat };

async function exportsJob(): Promise<number> {
  const db = adminClient();
  const { data, error } = await db.rpc("export_take", { p_limit: 2 });
  if (error) throw new Error(error.message);
  let n = 0;
  for (const x of (data ?? []) as ExportJob[]) {
    let rows: Record<string, unknown>[] = [];
    try {
      for (let offset = 0; offset < MAX_ROWS; offset += PAGE) {
        const page = await db.rpc("export_page", { p_export: x.id, p_offset: offset, p_limit: PAGE });
        if (page.error) throw new Error(page.error.message);
        const got = ((page.data as { rows?: Record<string, unknown>[] } | null)?.rows ?? []);
        rows = rows.concat(got);
        if (got.length < PAGE) break;
      }
      await ensureBucket();
      const file = exportFile(x.format === "xlsx" ? "xlsx" : "csv", exportColumns(x.params?.columns), rows);
      const path = `${x.user_id}/export-${x.id}.${file.ext}`;
      const up = await db.storage.from(EXPORT_BUCKET).upload(path, file.body, { contentType: file.type, upsert: true });
      if (up.error) throw new Error(up.error.message);
      const done = await db.rpc("export_done", { p_export: x.id, p_rows: rows.length, p_path: path, p_error: null });
      if (done.error) throw new Error(done.error.message);
      n++;
    } catch (e) {
      await db.rpc("export_done", { p_export: x.id, p_rows: rows.length, p_path: null, p_error: e instanceof Error ? e.message : String(e) });
    }
  }
  return n;
}
