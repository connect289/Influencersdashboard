import "server-only";
// Message attachments live in the private inf-documents bucket under threads/<thread>/<uuid>-<name>. The browser
// uploads with a one-time signed URL after inf.thread_open() confirms the caller may post; downloads go through
// /api/threads/file after inf.thread_file_allowed().
import { safeFileName } from "@/lib/creators/schemas";
import { ATTACHMENTS_BUCKET } from "./schemas";

export const THREADS_BUCKET = ATTACHMENTS_BUCKET;

export function threadFilePath(threadId: string, fileName: string): string {
  return `threads/${threadId}/${crypto.randomUUID()}-${safeFileName(fileName).slice(0, 120)}`;
}
