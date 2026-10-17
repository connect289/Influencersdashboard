import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import banned from "@/content/banned-claims.json" with { type: "json" };
import { suggestLinks, type LinkTarget } from "@/lib/seo/links";
import { checkPage, extractFacts } from "@/lib/seo/onpage";
import type { Block } from "../content";
import { resource, resourcesList } from "../content";
import { rpc } from "../db";
import { env, siteUrl } from "../env";
import { errorFields, log } from "../log";
import { curatedViews, searchOfferings, universities } from "../search";
import { parseFinderParams } from "@/lib/search/params";
import { sitemapEntries } from "../sitemap";
import { getSettings } from "../settings";

/**
 * SEO toolkit jobs (spec 13.4), run from the admin and on a daily schedule (/api/internal/seo-daily).
 */

export async function syncSearchConsole(days = 90): Promise<{ ok: boolean; rows?: number; source?: string; error?: string }> {
  const { gsc } = await import("./gsc");
  const p = gsc();
  if (!p) return { ok: false, error: "Search Console is not connected (S-20)." };
  try {
    const pages = (await Promise.all((["pages", "curated", "universities", "resources"] as const).map((t) => sitemapEntries(t)))).flat().map((e) => new URL(e.loc).pathname);
    const rows = await p.fetchRows(days, pages);
    const r = await rpc<{ rows: number }>("web_seo_import", { p_rows: rows, p_source: p.source });
    return { ok: true, rows: r.rows, source: p.source };
  } catch (err) {
    log("error", "seo.gsc_sync_failed", errorFields(err));
    return { ok: false, error: "Search Console sync failed; see logs." };
  }
}

/** The pages the checker and linking engine look at: curated views, university pages, published guides. */
async function contentPages(): Promise<{ path: string; faqs: boolean }[]> {
  const [views, unis, guides] = await Promise.all([curatedViews(), universities(), resourcesList()]);
  return [
    ...views.map((v) => ({ path: `/programmes/${v.slug}`, faqs: true })),
    ...unis.map((u) => ({ path: `/universities/${u.slug}`, faqs: false })),
    ...guides.map((g) => ({ path: `/resources/${g.slug}`, faqs: false })),
  ];
}

// Crawler user agent so streamed metadata arrives in <head> (D-035).
const UA = "EduwitSEOChecker/1.0 Chrome-Lighthouse";
const HUBS = ["/", "/programmes", "/universities", "/resources"];

export async function runOnPageChecks(limit = 200): Promise<{ checked: number; average: number }> {
  const pages = (await contentPages()).slice(0, limit);
  const fetched = await Promise.all(
    pages.map(async (p) => {
      const res = await fetch(siteUrl(p.path), { headers: { "user-agent": UA }, signal: AbortSignal.timeout(15000) }).catch(() => null);
      return { ...p, status: res?.status ?? 0, facts: res?.ok ? extractFacts(p.path, await res.text()) : null };
    }),
  );
  const ok = fetched.filter((f) => f.facts);
  // Hub pages count as link sources (a university linked from /universities is linked) but are not scored.
  const hubs = await Promise.all(
    HUBS.map(async (h) => {
      const res = await fetch(siteUrl(h), { headers: { "user-agent": UA }, signal: AbortSignal.timeout(15000) }).catch(() => null);
      return res?.ok ? extractFacts(h, await res.text()).siteLinks : [];
    }),
  );
  // Broken internal links: every unique internal link on the checked pages, fetched once (same-site paths only, redirects
  // not followed, so a crafted link can never make the checker fetch another host).
  const links = [...new Set(ok.flatMap((f) => f.facts!.internalLinks))].slice(0, 400);
  const status = new Map<string, number>();
  await Promise.all(
    links.map(async (l) => {
      const r = await fetch(siteUrl(l), { method: "GET", redirect: "manual", headers: { "user-agent": UA }, signal: AbortSignal.timeout(15000) }).catch(() => null);
      status.set(l, r?.status ?? 0);
    }),
  );
  let total = 0;
  for (const f of fetched) {
    if (!f.facts) {
      await rpc("web_seo_check_save", { p_path: f.path, p_score: 0, p_issues: [{ rule: "unreachable", severity: "error", message: `The page returned ${f.status}.` }] });
      continue;
    }
    const others = ok.filter((o) => o.path !== f.path);
    const r = checkPage(f.facts, {
      otherTitles: others.map((o) => o.facts!.title),
      otherDescriptions: others.map((o) => o.facts!.description),
      inboundLinks: others.filter((o) => o.facts!.siteLinks.includes(f.path)).length + hubs.filter((l) => l.includes(f.path)).length,
      brokenLinks: f.facts.internalLinks.filter((l) => status.get(l) === 404),
      expectFaqs: f.faqs,
    });
    total += r.score;
    await rpc("web_seo_check_save", { p_path: f.path, p_score: r.score, p_issues: r.issues });
  }
  return { checked: fetched.length, average: fetched.length ? Math.round(total / fetched.length) : 0 };
}

const blockText = (blocks: Block[]) => blocks.map((b) => ("text" in b ? b.text : b.items.join(" "))).join("\n");

export async function refreshLinkSuggestions(): Promise<number> {
  const [views, unis, guides, tax] = await Promise.all([
    curatedViews(),
    universities(),
    resourcesList(),
    rpc<{ programmes: { id: string; label: string }[] }>("web_admin_taxonomy"),
  ]);
  const programme = new Map(tax.programmes.map((p) => [p.id, p.label]));
  const targets: LinkTarget[] = [
    ...views.map((v) => {
      const ids = Array.isArray(v.filters.programme) ? (v.filters.programme as string[]) : [];
      const label = ids.length === 1 ? programme.get(ids[0]!) : undefined;
      const [short, full] = label ? label.split(" — ") : [];
      return { path: `/programmes/${v.slug}`, terms: [v.title, ...(short ? [`online ${short}`, short] : []), ...(full ? [full] : [])] };
    }),
    ...unis.map((u) => ({ path: `/universities/${u.slug}`, terms: [u.name, ...(u.short && u.short.length >= 3 ? [u.short] : [])] })),
  ];
  const docs = await Promise.all(guides.map((g) => resource(g.slug)));
  const suggestions = suggestLinks(
    docs.filter((d): d is NonNullable<typeof d> => !!d).map((d) => ({ slug: d.slug, text: `${d.title}\n${blockText(d.body)}`, links: [] })),
    targets,
  );
  return rpc<number>("web_link_suggestions_add", { p_rows: suggestions });
}

/** Facts a brief or draft may use: only what the catalogue says (spec 13.4 "grounded only in catalogue facts"). */
async function factsFor(title: string) {
  const f = await rpc<Record<string, string[]>>("web_resolve_to_filters", { p_q: title });
  const raw: Record<string, string> = {};
  for (const k of ["programme", "spec", "level", "mode", "uni"]) if (f[k]?.length) raw[k] = f[k]!.join(",");
  const result = await searchOfferings(parseFinderParams(raw), { page_size: 1 });
  const fee = result.facets.fee as { global_min?: number; global_max?: number } | undefined;
  const universitiesN = result.facets.university.filter((u) => u.count > 0).length;
  const views = (await curatedViews()).filter((v) => JSON.stringify(v.filters).includes(raw.programme?.split(",")[0] ?? "@@"));
  return {
    filters: raw,
    offerings: result.total,
    universities: universitiesN,
    fee_min: fee?.global_min ?? null,
    fee_max: fee?.global_max ?? null,
    links: [...views.map((v) => `/programmes/${v.slug}`), raw.programme ? `/programmes?programme=${raw.programme}` : "/programmes"],
  };
}

export interface Brief {
  intent: string;
  audience: string;
  outline: string[];
  questions: string[];
  internal_links: string[];
  facts: string[];
  rules: string[];
  generated_by: "template" | "claude";
  generated_at: string;
}

const RULES = [
  "Use only the catalogue facts listed here; write \"a counsellor can confirm\" for anything else.",
  "No claims of guaranteed jobs, placements or admission; approvals only per university from the catalogue.",
  "A named author and a named reviewer must sign off before publishing.",
];

export interface Actor {
  id: string;
  email: string;
  role: string;
}

export async function generateBrief(slug: string, title: string, actor: Actor): Promise<Brief> {
  const f = await factsFor(title);
  const facts = [
    `${f.offerings} matching options from ${f.universities} universities in the catalogue`,
    ...(f.fee_min && f.fee_max ? [`full fees range from ₹${f.fee_min.toLocaleString("en-IN")} to ₹${f.fee_max.toLocaleString("en-IN")}`] : []),
  ];
  const question = /^(is|are|can|how|what|which|why|does)\b/i.test(title);
  const brief: Brief = {
    intent: question ? "Informational: answer the question directly, then help the reader compare options." : "Commercial investigation: help the reader compare and shortlist.",
    audience: "Indian students and working professionals considering an online or distance degree.",
    outline: question
      ? ["Short answer (2–3 sentences)", "What it depends on", "How to check a specific programme", "Options to compare", "FAQs"]
      : ["Who this is for", "What to compare: fees, duration, approvals, eligibility", "How the options differ", "How to apply with a counsellor", "FAQs"],
    questions: [`What does ${title.toLowerCase()} cost?`, "Who is eligible?", "Is it recognised for jobs and higher studies?", "How long does it take?"],
    internal_links: f.links,
    facts,
    rules: RULES,
    generated_by: "template",
    generated_at: new Date().toISOString(),
  };
  await rpc("web_admin_save", {
    p_entity: "resources",
    p_row: { slug, brief, status: "brief" },
    p_actor: actor.id,
    p_actor_email: actor.email,
    p_role: actor.role,
  });
  return brief;
}

/** First draft (Claude-assisted when a key is set; otherwise a structured skeleton). Never published automatically. */
export async function generateDraft(slug: string, title: string, brief: Brief, actor: Actor): Promise<{ blocks: Block[]; by: "claude" | "template" }> {
  let blocks: Block[] | null = null;
  let by: "claude" | "template" = "template";
  const key = env().ANTHROPIC_API_KEY;
  if (key) {
    try {
      const settings = await getSettings();
      const client = new Anthropic({ apiKey: key, baseURL: env().WEB_ANTHROPIC_BASE_URL, maxRetries: 1 });
      const r = await client.messages.create({
        model: settings.web_advisor_models.counselor,
        max_tokens: 2000,
        system:
          "You draft guides for eduwit.in. Return only JSON: an array of blocks {type: h2|h3|p, text} or {type: ul|ol, items}. Use ONLY the facts given; never invent numbers, approvals, rankings, salaries or placements. Where something needs checking, write [Counsellor to confirm]. Plain, friendly English for Indian students.",
        messages: [{ role: "user", content: JSON.stringify({ title, brief }) }],
      });
      const text = r.content.map((c) => (c.type === "text" ? c.text : "")).join("");
      const parsed = JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, "")) as Block[];
      const claims = banned.patterns.map((p) => new RegExp(p.source, p.flags));
      if (Array.isArray(parsed) && !claims.some((re) => re.test(JSON.stringify(parsed)))) {
        blocks = parsed;
        by = "claude";
      }
    } catch (err) {
      log("warn", "seo.draft_claude_failed", errorFields(err));
    }
  }
  blocks ??= brief.outline.flatMap((h): Block[] => [
    { type: "h2", text: h },
    { type: "p", text: `[Author to write. Facts you may use: ${brief.facts.join("; ") || "none yet"}. Link to: ${brief.internal_links.join(", ")}.]` },
  ]);
  await rpc("web_admin_save", {
    p_entity: "resources",
    p_row: { slug, body: blocks, status: "draft", draft_source: by === "claude" ? "claude_assisted" : "human" },
    p_actor: actor.id,
    p_actor_email: actor.email,
    p_role: actor.role,
  });
  return { blocks, by };
}
