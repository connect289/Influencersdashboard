import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { scrubString } from "@/lib/security/scrub";
import { toSearchInput, type FinderParams } from "@/lib/search/params";
import type {
  CatalogStats,
  OfferingCard,
  OfferingDetails,
  SearchResult,
  Suggestions,
  UniversityDetails,
  UniversitySummary,
} from "@/lib/search/types";
import { dbConfigured, rpc, rpcRead } from "./db";
import { errorFields, log } from "./log";

/**
 * SearchAdapter (docs/ARCHITECTURE.md §3): the only way the app reads the catalogue. Every call is one Postgres function
 * over the read model, cached with the `catalog` tag (revalidated when the catalogue poller sees a change) and a short
 * TTL as a safety net. Without a database it degrades to empty results instead of failing the page.
 */

const EMPTY_FACETS: SearchResult["facets"] = {
  level: [], category: [], programme: [], spec: [], university: [], mode: [], naac: [], min_q: [], state: [], duration: [],
  format: [], goal: [], fee: { min: null, max: null, on_request: 0 }, ugc_deb: 0, aicte: 0, nirf: 0,
  work_exp: { required: 0, not_required: 0 }, entrance: { yes: 0, no: 0 },
};
export const EMPTY_RESULT: SearchResult = {
  total: 0, total_groups: 0, page: 1, page_size: 20, view: "grouped", sort: "relevance", items: [], facets: EMPTY_FACETS,
  relaxations: [],
  resolved: { programme: [], specialisation: [], university: [], level: [], category: [], mode: [], corrected: [], used_words: [], ignored_words: [] },
};

function catalogCache() {
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("catalog");
}

// Search, suggestions and offering details depend on request-time filters, so they are cached in the platform's shared
// remote cache (one entry for all server instances) to protect the shared database during ad spikes; locally and in CI
// this falls back to the in-memory cache (D-080).
export async function searchOfferings(
  params: FinderParams,
  extra: { page_size?: number; group_key?: string; include_offerings?: boolean } = {},
): Promise<SearchResult> {
  "use cache: remote";
  catalogCache();
  if (!dbConfigured()) return EMPTY_RESULT;
  return rpcRead<SearchResult>("web_search", { p: toSearchInput(params, extra) });
}

export async function suggest(q: string): Promise<Suggestions> {
  "use cache: remote";
  catalogCache();
  if (!dbConfigured() || !q.trim()) return { programmes: [], groups: [], universities: [] };
  return rpcRead<Suggestions>("web_suggest", { p_q: q.slice(0, 80), p_limit: 5 });
}

export async function offeringDetails(id: number, qual?: string): Promise<OfferingDetails | null> {
  "use cache: remote";
  catalogCache();
  if (!dbConfigured()) return null;
  return rpcRead<OfferingDetails | null>("web_offering_details", { p_id: id, p_qual: qual ?? null });
}

export async function offeringCards(ids: number[], qual?: string): Promise<OfferingCard[]> {
  "use cache: remote";
  catalogCache();
  if (!dbConfigured() || ids.length === 0) return [];
  return rpcRead<OfferingCard[]>("web_offering_cards", { p_ids: ids.slice(0, 100), p_qual: qual ?? null });
}

export async function compareOfferings(ids: number[], qual?: string): Promise<OfferingDetails[]> {
  "use cache";
  catalogCache();
  if (!dbConfigured() || ids.length === 0) return [];
  return rpcRead<OfferingDetails[]>("web_compare_offerings", { p_ids: ids.slice(0, 4), p_qual: qual ?? null });
}

export async function universities(): Promise<UniversitySummary[]> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return [];
  return rpcRead<UniversitySummary[]>("web_universities");
}

export async function universityDetails(slug: string): Promise<UniversityDetails | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  return rpcRead<UniversityDetails | null>("web_university_details", { p_slug: slug });
}

export async function catalogStats(): Promise<CatalogStats | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  try {
    return await rpcRead<CatalogStats>("web_catalog_stats");
  } catch (err) {
    log("error", "catalog.stats_failed", errorFields(err));
    return null;
  }
}

export interface Browse {
  levels: { id: string; label: string; count: number }[];
  categories: { id: string; label: string; count: number }[];
  programmes: { id: string; label: string; full: string; level: string; count: number }[];
  goals: { id: string; label: string; description: string }[];
}

export async function browse(): Promise<Browse | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  return rpcRead<Browse>("web_browse");
}

/** Records a search for the zero-result report and demand insights. Free text is scrubbed of emails and phone numbers. */
/**
 * Search log for the admin (popular and zero-result searches). Entries are buffered per server instance and written in
 * one call every 25 searches or 5 seconds, so a traffic spike does not take a pooled database connection per search
 * (load tests, D-080). An instance that stops loses at most its unwritten buffer — acceptable for analytics.
 */
const logBuffer = globalThis as unknown as { __ewSearchLog?: { rows: Record<string, unknown>[]; since: number } };

export async function logSearch(entry: { q?: string; filters: Record<string, unknown>; results: number; latencyMs: number; source: "finder" | "suggest" | "advisor" | "api" }) {
  if (!dbConfigured()) return;
  const buf = (logBuffer.__ewSearchLog ??= { rows: [], since: Date.now() });
  buf.rows.push({ q: entry.q ? scrubString(entry.q) : null, filters: entry.filters, results: entry.results, latency_ms: entry.latencyMs, source: entry.source });
  if (buf.rows.length < 25 && Date.now() - buf.since < 5000) return;
  const rows = buf.rows.splice(0, buf.rows.length);
  buf.since = Date.now();
  try {
    await rpc("web_search_log_add", { p: rows });
  } catch (err) {
    log("warn", "search.log_failed", { rows: rows.length, ...errorFields(err) });
  }
}

export interface CuratedView {
  slug: string;
  title: string;
  h1: string | null;
  intro: string | null;
  filters: Record<string, unknown>;
  faqs: { q: string; a: string }[];
  seo_description: string | null;
  updated_at: string;
}

export async function curatedView(slug: string): Promise<CuratedView | null> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("content", `curated:${slug}`);
  if (!dbConfigured() || !/^[a-z0-9-]{1,80}$/.test(slug)) return null;
  return rpc<CuratedView | null>("web_curated_view", { p_slug: slug });
}

export async function curatedViews(): Promise<{ slug: string; title: string; filters: Record<string, unknown>; updated_at: string }[]> {
  "use cache";
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("content");
  if (!dbConfigured()) return [];
  return rpc("web_curated_views_list");
}
