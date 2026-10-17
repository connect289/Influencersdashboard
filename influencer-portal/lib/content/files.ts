import "server-only";
// Storage for content: submission files and metric screenshots in the private inf-deliverables bucket, brief assets
// in inf-briefs. Files go straight from the browser to storage with a one-time signed upload (resumable for large
// videos) and are opened with short-lived signed links, each only after an inf.* check of the caller.
import { safeFileName } from "@/lib/creators/schemas";
import { adminClient } from "@/lib/supabase/admin";

export const DELIVERABLES_BUCKET = "inf-deliverables";
export const BRIEFS_BUCKET = "inf-briefs";
/** How long a file link stays valid (seconds): long enough to watch and comment on a video. */
export const FILE_LINK_SECONDS = 3600;

export function contentPath(folder: string, fileName: string): string {
  return `${folder}/${crypto.randomUUID()}-${safeFileName(fileName).slice(0, 120)}`;
}

export async function signedUpload(bucket: string, path: string): Promise<{ path: string; token: string } | null> {
  const { data, error } = await adminClient().storage.from(bucket).createSignedUploadUrl(path);
  return error ? null : { path: data.path, token: data.token };
}

export async function signedLink(bucket: string, path: string): Promise<string | null> {
  const { data, error } = await adminClient().storage.from(bucket).createSignedUrl(path, FILE_LINK_SECONDS);
  return error ? null : data.signedUrl;
}

/** Links for many files at once (path → URL); paths that fail are left out. */
export async function signedLinks(bucket: string, paths: readonly string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (paths.length === 0) return out;
  const { data } = await adminClient()
    .storage.from(bucket)
    .createSignedUrls([...paths], FILE_LINK_SECONDS);
  for (const r of data ?? []) if (r.path && r.signedUrl && !r.error) out.set(r.path, r.signedUrl);
  return out;
}
