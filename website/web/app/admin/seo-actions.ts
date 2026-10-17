"use server";

import { revalidateTag } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/server/admin";
import { isLocalPath } from "@/lib/security/paths";
import { rpc } from "@/lib/server/db";
import type { Brief } from "@/lib/server/seo/toolkit";
import { generateBrief, generateDraft, refreshLinkSuggestions, runOnPageChecks, syncSearchConsole } from "@/lib/server/seo/toolkit";

/** SEO toolkit actions (spec 13.4). Every write goes through the audited admin save path. */
const back = (path: string, msg: string) => redirect(`${path}?msg=${encodeURIComponent(msg)}`);
const slugify = (s: string) =>
  s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 70);
const titleCase = (s: string) => s.replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\b(Mba|Bba|Bca|Mca|Bcom|Mcom|Ma|Ba|Msc|Bsc)\b/g, (m) => m.toUpperCase());

export async function syncGscAction(): Promise<void> {
  await requireAdmin("content_editor");
  const r = await syncSearchConsole(90);
  back("/admin/seo", r.ok ? `Imported ${r.rows} rows (${r.source === "sample" ? "sample data — Search Console not connected" : "Search Console"}).` : (r.error ?? "Failed."));
}

export async function runChecksAction(): Promise<void> {
  await requireAdmin("content_editor");
  const r = await runOnPageChecks();
  back("/admin/seo/checks", `Checked ${r.checked} pages; average score ${r.average}.`);
}

export async function refreshLinksAction(): Promise<void> {
  await requireAdmin("content_editor");
  const n = await refreshLinkSuggestions();
  back("/admin/seo/links", `${n} new suggestion(s).`);
}

export async function decideLinkAction(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const status = String(form.get("status"));
  await rpc("web_link_decide", { p_id: Number(form.get("id")), p_status: status, p_actor_email: s.email });
  revalidateTag("content", { expire: 0 });
  back("/admin/seo/links", status === "approved" ? "Approved: the link now shows on the guide." : "Rejected.");
}

/** Opportunity → draft curated view with the query's filters (reviewed before publishing). */
export async function createViewAction(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const query = String(form.get("query") ?? "").slice(0, 120);
  let filters: Record<string, unknown> = {};
  try {
    const f = JSON.parse(String(form.get("filters") ?? "{}")) as Record<string, unknown>;
    for (const k of ["programme", "spec", "level", "category", "uni", "mode"]) if (Array.isArray(f[k]) && (f[k] as unknown[]).length) filters[k] = f[k];
  } catch {
    filters = {};
  }
  if (!Object.keys(filters).length) back("/admin/seo/opportunities", "That query does not map to finder filters; create a guide instead.");
  const slug = slugify(query);
  const r = await rpc<{ ok: boolean; error?: string }>("web_admin_save", {
    p_entity: "curated_views",
    p_row: { slug, title: titleCase(query), h1: titleCase(query), filters, faqs: [], status: "draft", intro: null },
    p_actor: s.userId,
    p_actor_email: s.email,
    p_role: s.role,
  });
  if (!r.ok) back("/admin/seo/opportunities", r.error ?? "Could not create the view.");
  redirect(`/admin/content/curated_views/edit?key=${encodeURIComponent(JSON.stringify({ slug }))}`);
}

/** Opportunity (question-style query) → guide idea in the content planner. */
export async function createGuideIdeaAction(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const query = String(form.get("query") ?? "").slice(0, 120);
  const title = titleCase(query.endsWith("?") ? query : /^(is|are|can|how|what|which|why|does)\b/i.test(query) ? `${query}?` : query);
  const r = await rpc<{ ok: boolean; error?: string }>("web_admin_save", {
    p_entity: "resources",
    p_row: { slug: slugify(query), title, status: "idea" },
    p_actor: s.userId,
    p_actor_email: s.email,
    p_role: s.role,
  });
  back("/admin/seo/planner", r.ok ? `Added “${title}” to the planner.` : (r.error ?? "Could not add the idea."));
}

export async function briefAction(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const slug = String(form.get("slug"));
  await generateBrief(slug, String(form.get("title")), { id: s.userId, email: s.email, role: s.role });
  back("/admin/seo/planner", "Brief ready — review it in the guide editor.");
}

export async function draftAction(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const slug = String(form.get("slug"));
  const row = await rpc<{ brief: Brief | null; title: string } | null>("web_admin_get", { p_entity: "resources", p_key: { slug } });
  if (!row?.brief) back("/admin/seo/planner", "Create a brief first.");
  const r = await generateDraft(slug, row!.title, row!.brief!, { id: s.userId, email: s.email, role: s.role });
  back("/admin/seo/planner", r.by === "claude" ? "First draft written with Claude — an author must rewrite and a reviewer approve it." : "Draft skeleton created — the author writes it (no AI key configured).");
}

export async function redirect404Action(form: FormData): Promise<void> {
  const s = await requireAdmin("content_editor");
  const to = String(form.get("to") ?? "").trim();
  if (!isLocalPath(to) && !/^https:\/\/[^\s/\\?#]+(?:[/?#]\S*)?$/.test(to)) back("/admin/seo/404", "Enter a site path (/…) or an https URL.");
  const r = await rpc<{ ok: boolean; error?: string }>("web_404_redirect", { p_path: String(form.get("path")), p_to: to, p_actor: s.userId, p_actor_email: s.email, p_role: s.role });
  if (r.ok) revalidateTag("redirects", { expire: 0 });
  back("/admin/seo/404", r.ok ? "Redirect created." : (r.error ?? "Failed."));
}
