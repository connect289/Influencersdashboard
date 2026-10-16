import "server-only";
import { ALLOWED_DOMAIN } from "@/lib/env";
import { googleSa, signedJwt, type GoogleSa } from "@/lib/gmail";

/**
 * Google Workspace directory (spec B3.2, Teams sync): the service account, delegated to a Workspace admin
 * (GOOGLE_ADMIN_EMAIL), reads the domain's users with admin.directory.user.readonly. Pure mapping in directory.test.ts.
 */
export type GUser = {
  id?: string; primaryEmail?: string; suspended?: boolean; archived?: boolean; thumbnailPhotoUrl?: string;
  name?: { fullName?: string }; organizations?: { title?: string; primary?: boolean }[];
};
export type DirUser = { id: string | null; email: string; name: string | null; photo_url: string | null; job_title: string | null; suspended: boolean };

export function toDirUser(u: GUser): DirUser | null {
  if (!u.primaryEmail) return null;
  const org = u.organizations?.find((o) => o.primary) ?? u.organizations?.[0];
  return {
    id: u.id ?? null, email: u.primaryEmail.toLowerCase(), name: u.name?.fullName?.trim() || null,
    photo_url: u.thumbnailPhotoUrl && /^https:\/\//.test(u.thumbnailPhotoUrl) ? u.thumbnailPhotoUrl : null,
    job_title: org?.title?.trim() || null, suspended: !!(u.suspended || u.archived),
  };
}

export async function listDirectory(sa: GoogleSa, admin: string, domain: string): Promise<DirUser[]> {
  const tok = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: signedJwt(sa, admin, "https://www.googleapis.com/auth/admin.directory.user.readonly") }),
    signal: AbortSignal.timeout(15_000),
  });
  const t = (await tok.json()) as { access_token?: string; error_description?: string };
  if (!t.access_token) throw new Error(`Google refused the token: ${t.error_description ?? tok.status}`);
  const out: DirUser[] = [];
  let page: string | undefined;
  for (let i = 0; i < 50; i++) {
    const q = new URLSearchParams({ domain, maxResults: "500", projection: "basic", orderBy: "email", ...(page ? { pageToken: page } : {}) });
    const res = await fetch(`https://admin.googleapis.com/admin/directory/v1/users?${q}`, { headers: { authorization: `Bearer ${t.access_token}` }, signal: AbortSignal.timeout(20_000) });
    const b = (await res.json()) as { users?: GUser[]; nextPageToken?: string; error?: { message?: string } };
    if (!res.ok) throw new Error(`Directory: ${b.error?.message ?? res.status}`);
    for (const u of b.users ?? []) { const d = toDirUser(u); if (d) out.push(d); }
    page = b.nextPageToken;
    if (!page) break;
  }
  return out;
}

export function directoryConfig(): { sa: GoogleSa; admin: string; domain: string } | null {
  const sa = googleSa();
  const admin = process.env.GOOGLE_ADMIN_EMAIL;
  if (!sa || !admin) return null;
  return { sa, admin, domain: ALLOWED_DOMAIN };
}
