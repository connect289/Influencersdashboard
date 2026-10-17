import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { scrubString } from "@/lib/security/scrub";
import { toSearchInput, type FinderParams } from "@/lib/search/params";
import type {
  CatalogStats,
  OfferingDetails,
  SearchResult,
  Suggestions,
  UniversityDetails,
  UniversitySummary,
} from "@/lib/search/types";
import { dbConfigured, rpc } from "./db";
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

export async function searchOfferings(
  params: FinderParams,
  extra: { page_size?: number; group_key?: string; include_offerings?: boolean } = {},
): Promise<SearchResult> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return EMPTY_RESULT;
  return rpc<SearchResult>("web_search", { p: toSearchInput(params, extra) });
}

export async function suggest(q: string): Promise<Suggestions> {
  "use cache";
  catalogCache();
  if (!dbConfigured() || !q.trim()) return { programmes: [], groups: [], universities: [] };
  return rpc<Suggestions>("web_suggest", { p_q: q.slice(0, 80), p_limit: 5 });
}

export async function offeringDetails(id: number, qual?: string): Promise<OfferingDetails | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  return rpc<OfferingDetails | null>("web_offering_details", { p_id: id, p_qual: qual ?? null });
}

export async function compareOfferings(ids: number[], qual?: string): Promise<OfferingDetails[]> {
  "use cache";
  catalogCache();
  if (!dbConfigured() || ids.length === 0) return [];
  return rpc<OfferingDetails[]>("web_compare_offerings", { p_ids: ids.slice(0, 4), p_qual: qual ?? null });
}

export async function universities(): Promise<UniversitySummary[]> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return [];
  return rpc<UniversitySummary[]>("web_universities");
}

export async function universityDetails(slug: string): Promise<UniversityDetails | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  return rpc<UniversityDetails | null>("web_university_details", { p_slug: slug });
}

export async function catalogStats(): Promise<CatalogStats | null> {
  "use cache";
  catalogCache();
  if (!dbConfigured()) return null;
  try {
    return await rpc<CatalogStats>("web_catalog_stats");
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
  return rpc<Browse>("web_browse");
}

/** Records a search for the zero-result report and demand insights. Free text is scrubbed of emails and phone numbers. */
export async function logSearch(entry: { q?: string; filters: Record<string, unknown>; results: number; latencyMs: number; source: "finder" | "suggest" | "advisor" | "api" }) {
  if (!dbConfigured()) return;
  try {
    await rpc("web_search_log_add", {
      p: { q: entry.q ? scrubString(entry.q) : null, filters: entry.filters, results: entry.results, latency_ms: entry.latencyMs, source: entry.source },
    });
  } catch (err) {
    log("warn", "search.log_failed", errorFields(err));
  }
}
