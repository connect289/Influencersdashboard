import "server-only";
import { importPKCS8, SignJWT } from "jose";
import { env, isProduction } from "../env";
import { log } from "../log";

/**
 * Google Search Console (spec 13.4, S-20): a service account added as a user on the property reads Search Analytics
 * (date × query × page) daily. Without credentials, development and CI use clearly labelled sample rows built from
 * the site's own pages so the dashboards can be exercised; production shows "connect Search Console" instead.
 */
export interface GscRow {
  day: string;
  query: string;
  page: string;
  clicks: number;
  impressions: number;
  position: number;
}
export interface GscProvider {
  readonly source: "gsc" | "sample";
  fetchRows(days: number, pages: string[]): Promise<GscRow[]>;
}

async function accessToken(email: string, keyPem: string): Promise<string> {
  const key = await importPKCS8(keyPem.replace(/\\n/g, "\n"), "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/webmasters.readonly" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`gsc token ${res.status}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

const gscProvider = (email: string, key: string, site: string): GscProvider => ({
  source: "gsc",
  async fetchRows(days) {
    const token = await accessToken(email, key);
    const end = new Date(Date.now() - 2 * 86400000); // Search Console data lags ~2 days
    const start = new Date(end.getTime() - days * 86400000);
    const iso = (d: Date) => d.toISOString().slice(0, 10);
    const res = await fetch(`https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(site)}/searchAnalytics/query`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ startDate: iso(start), endDate: iso(end), dimensions: ["date", "query", "page"], rowLimit: 25000 }),
      signal: AbortSignal.timeout(30000),
    });
    if (!res.ok) throw new Error(`gsc query ${res.status}`);
    const j = (await res.json()) as { rows?: { keys: [string, string, string]; clicks: number; impressions: number; position: number }[] };
    return (j.rows ?? []).map((r) => ({
      day: r.keys[0],
      query: r.keys[1],
      page: new URL(r.keys[2]).pathname,
      clicks: r.clicks,
      impressions: r.impressions,
      position: Math.round(r.position * 100) / 100,
    }));
  },
});

/** Deterministic sample rows (development and CI only). */
export function sampleRows(days: number, pages: string[], today = new Date()): GscRow[] {
  const queries: [string, string][] = [
    ["online mba", "/programmes/online-mba"],
    ["online mba fees", "/programmes/online-mba"],
    ["online bca", "/programmes/online-bca"],
    ["online mca fees", "/programmes/online-mca"],
    ["online mba for working professionals", "/"],
    ["online bcom", "/programmes"],
    ["is online degree valid for government jobs", "/"],
    ["nmims online mba fees", "/universities/nmims"],
    ["distance mba", "/programmes"],
  ];
  const rows: GscRow[] = [];
  for (let d = 2; d < days + 2; d++) {
    const day = new Date(today.getTime() - d * 86400000).toISOString().slice(0, 10);
    queries.forEach(([q, page], i) => {
      if (page !== "/" && page !== "/programmes" && !pages.includes(page)) return;
      const base = 40 + ((i * 37 + d * 11) % 90);
      const impressions = Math.round(base * (1 + (i % 3) * 0.6));
      const position = 4 + ((i * 7 + d) % 25);
      rows.push({ day, query: q, page, impressions, clicks: Math.round((impressions * Math.max(0.5, 12 - position)) / 100), position });
    });
  }
  return rows;
}

const sampleProvider: GscProvider = { source: "sample", fetchRows: async (days, pages) => sampleRows(days, pages) };

export function gsc(): GscProvider | null {
  const e = env();
  if (e.GSC_SA_EMAIL && e.GSC_SA_PRIVATE_KEY && e.GSC_SITE_URL) return gscProvider(e.GSC_SA_EMAIL, e.GSC_SA_PRIVATE_KEY, e.GSC_SITE_URL);
  if (isProduction()) {
    log("info", "gsc.not_configured");
    return null;
  }
  return sampleProvider;
}
