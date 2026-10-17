import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { dbConfigured, rpc } from "./db";
import { errorFields, log } from "./log";

/** Content managed in the admin (web6_content). Cached with the "content" tag; the admin revalidates it on save. */

export type Block =
  | { type: "h2" | "h3" | "p"; text: string }
  | { type: "ul" | "ol"; items: string[] };

export interface Faq {
  q: string;
  a: string;
}
export interface HomeContent {
  faqs: Faq[];
  testimonials: { name: string; detail?: string; quote: string; rating?: number; photo?: string }[];
  popular: { label: string; href: string }[];
  resources: { slug: string; title: string; summary?: string; published_at?: string }[];
}
export interface LegalPage {
  slug: string;
  title: string;
  body: Block[];
  status: "pending_migration" | "migrated" | "proposed_edit";
  migrated_at: string | null;
  version: number;
  updated_at: string;
}
export interface ResourceSummary {
  slug: string;
  title: string;
  summary?: string;
  published_at?: string;
  tags: string[];
  author?: string;
}
export interface Resource extends Omit<ResourceSummary, "author"> {
  body: Block[];
  updated_at: string;
  seo_title?: string;
  seo_description?: string;
  author: { name: string; role?: string; bio?: string };
  reviewer: { name: string; role?: string };
}

function contentCache() {
  cacheLife({ stale: 60, revalidate: 300, expire: 3600 });
  cacheTag("content");
}

const EMPTY_HOME: HomeContent = { faqs: [], testimonials: [], popular: [], resources: [] };

export async function homeContent(): Promise<HomeContent> {
  "use cache";
  contentCache();
  if (!dbConfigured()) return EMPTY_HOME;
  try {
    return await rpc<HomeContent>("web_home_content");
  } catch (err) {
    log("error", "content.home_failed", errorFields(err));
    return EMPTY_HOME;
  }
}

export async function faqsFor(scope: string): Promise<Faq[]> {
  "use cache";
  contentCache();
  if (!dbConfigured()) return [];
  return rpc<Faq[]>("web_faqs_for", { p_scope: scope });
}

export async function legalPage(slug: string): Promise<LegalPage | null> {
  "use cache";
  contentCache();
  if (!dbConfigured()) return null;
  return rpc<LegalPage | null>("web_legal_page", { p_slug: slug });
}

export async function resourcesList(): Promise<ResourceSummary[]> {
  "use cache";
  contentCache();
  if (!dbConfigured()) return [];
  try {
    return await rpc<ResourceSummary[]>("web_resources_list");
  } catch (err) {
    log("error", "content.resources_failed", errorFields(err));
    return [];
  }
}

/** Editor-approved related links for a guide (internal linking engine, spec 13.4). */
export async function resourceLinks(slug: string): Promise<{ href: string; anchor: string }[]> {
  "use cache";
  contentCache();
  if (!dbConfigured() || !/^[a-z0-9-]{1,100}$/.test(slug)) return [];
  return rpc<{ href: string; anchor: string }[]>("web_resource_links", { p_slug: slug }).catch(() => []);
}

export async function resource(slug: string): Promise<Resource | null> {
  "use cache";
  contentCache();
  if (!dbConfigured() || !/^[a-z0-9-]{1,100}$/.test(slug)) return null;
  return rpc<Resource | null>("web_resource", { p_slug: slug });
}
