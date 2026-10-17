"use client";
// Uploads a file for a deliverable straight to the private inf-deliverables bucket with a one-time signed token.
// Files over one chunk use the resumable (TUS) protocol in 6 MB chunks, so a dropped connection resumes where it
// stopped, including after a page reload (the upload's address is kept in this browser for the token's lifetime).
import { deliverableUploadUrl } from "@/lib/actions/content";
import type { UploadType } from "@/lib/content/schemas";
import { publicEnv } from "@/lib/env-public";
import { createClient } from "@/lib/supabase/browser";

/** Supabase's resumable endpoint requires exactly 6 MB chunks (except the last). */
const CHUNK = 6 * 1024 * 1024;
const BUCKET = "inf-deliverables";

export interface Uploaded {
  path: string;
  name: string;
  type: UploadType;
  size: number;
}

export class UploadError extends Error {}

interface Resume {
  path: string;
  token: string;
  location: string;
  at: number;
}

const resumeKey = (folder: string, f: File) =>
  `inf-tus:${folder}:${f.name}:${String(f.size)}:${String(f.lastModified)}`;

function readResume(key: string): Resume | null {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const r = JSON.parse(raw) as Resume;
    // Signed upload tokens last two hours; start again after that.
    return Date.now() - r.at < 110 * 60_000 ? r : null;
  } catch {
    return null;
  }
}

function writeResume(key: string, r: Resume | null) {
  try {
    if (r) localStorage.setItem(key, JSON.stringify(r));
    else localStorage.removeItem(key);
  } catch {
    // Private mode or storage blocked: the upload still works, it just can't resume after a reload.
  }
}

const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

async function tus(
  f: File,
  r: Resume | null,
  sign: () => Promise<{ path: string; token: string }>,
  key: string,
  onProgress: (n: number) => void,
  signal?: AbortSignal,
): Promise<string> {
  const base = `${publicEnv.supabaseUrl}/storage/v1/upload/resumable/sign`;
  const common = (token: string) => ({ "Tus-Resumable": "1.0.0", "x-signature": token, apikey: publicEnv.supabaseKey });
  let state = r;
  let offset = 0;
  if (state) {
    const head = await fetch(state.location, { method: "HEAD", headers: common(state.token), signal }).catch(
      () => null,
    );
    const o = head?.ok ? Number(head.headers.get("upload-offset")) : NaN;
    if (Number.isFinite(o)) offset = o;
    else state = null;
  }
  if (!state) {
    const s = await sign();
    const created = await fetch(base, {
      method: "POST",
      signal,
      headers: {
        ...common(s.token),
        "Upload-Length": String(f.size),
        "Upload-Metadata": `bucketName ${b64(BUCKET)},objectName ${b64(s.path)},contentType ${b64(f.type)}`,
      },
    });
    const location = created.headers.get("location");
    if (!created.ok || !location) throw new UploadError(`create ${String(created.status)}`);
    state = { path: s.path, token: s.token, location, at: Date.now() };
    writeResume(key, state);
  }
  while (offset < f.size) {
    const end = Math.min(offset + CHUNK, f.size);
    let res: Response | null = null;
    // Each chunk retries a few times with a short backoff before giving up (the next attempt resumes from here).
    for (let attempt = 0; attempt < 4 && !res?.ok; attempt++) {
      if (attempt) await new Promise((ok) => setTimeout(ok, 1000 * 2 ** attempt));
      res = await fetch(state.location, {
        method: "PATCH",
        signal,
        headers: {
          ...common(state.token),
          "Upload-Offset": String(offset),
          "Content-Type": "application/offset+octet-stream",
        },
        body: f.slice(offset, end),
      }).catch((e: unknown) => {
        if (signal?.aborted) throw e;
        return null;
      });
    }
    if (!res?.ok) throw new UploadError(`patch ${String(res?.status ?? 0)}`);
    offset = Number(res.headers.get("upload-offset") ?? end);
    onProgress(offset / f.size);
  }
  writeResume(key, null);
  return state.path;
}

export async function uploadDeliverableFile(
  deliverableId: string,
  f: File,
  type: UploadType,
  onProgress: (fraction: number) => void,
  signal?: AbortSignal,
): Promise<Uploaded> {
  const sign = async () => {
    const r = await deliverableUploadUrl({ deliverableId, fileName: f.name, type, size: f.size });
    if (!r.ok || !r.data) throw new UploadError(r.ok ? "sign" : r.error);
    return r.data;
  };
  let path: string;
  if (f.size <= CHUNK) {
    const s = await sign();
    const { error } = await createClient()
      .storage.from(BUCKET)
      .uploadToSignedUrl(s.path, s.token, f, { contentType: f.type });
    if (error) throw new UploadError(error.message);
    path = s.path;
    onProgress(1);
  } else {
    const key = resumeKey(deliverableId, f);
    path = await tus(f, readResume(key), sign, key, onProgress, signal);
  }
  return { path, name: f.name.slice(0, 200), type, size: f.size };
}
