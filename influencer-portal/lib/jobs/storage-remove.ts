import "server-only";
import { z } from "zod";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

/** Files the privacy and retention flows may remove: a deleted creator's photo and KYC proofs. */
export const storageFiles = z
  .array(
    z.object({
      bucket: z.enum(["inf-public-avatars", "inf-kyc"]),
      path: z.string().regex(/^[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/),
    }),
  )
  .max(1000);

/** Removes storage objects, grouped by bucket. Idempotent: removing a file that is already gone succeeds. */
export async function removeFiles(files: z.infer<typeof storageFiles>): Promise<void> {
  const byBucket = new Map<string, string[]>();
  for (const f of files) byBucket.set(f.bucket, [...(byBucket.get(f.bucket) ?? []), f.path]);
  for (const [bucket, paths] of byBucket) {
    const { error } = await adminClient().storage.from(bucket).remove(paths);
    if (error) throw new Error(`storage.remove ${bucket}: ${error.message}`);
  }
}

/** storage.remove (queued by inf.retention_run when kept KYC reaches its purge date). */
export const storageRemove: JobHandler = async (job) => {
  const files = storageFiles.parse(job.payload.files);
  await removeFiles(files);
  log.info("storage.remove", { files: files.length });
};
