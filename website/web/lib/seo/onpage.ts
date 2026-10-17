import banned from "@/content/banned-claims.json" with { type: "json" };

/**
 * On-page checker (spec 13.4): runs on the rendered HTML of curated views, university pages and guides. Checks title and
 * description length and uniqueness, one H1, heading order, intro length, FAQs, structured data validity, image alt
 * text, internal links in and out, broken internal links and banned claims, and turns them into a 0–100 score with
 * fix suggestions. Pure (the runner fetches pages and link statuses).
 */
export type Severity = "error" | "warn" | "info";
export interface Issue {
  rule: string;
  severity: Severity;
  message: string;
}
export interface PageFacts {
  path: string;
  title: string;
  description: string;
  h1: string[];
  headings: { level: number; text: string }[];
  firstParagraph: string;
  jsonLd: { ok: boolean; types: string[] }[];
  imagesWithoutAlt: number;
  /** internal links in the page content (main + streamed), the "links out" */
  internalLinks: string[];
  /** every internal link on the page including header and footer, for counting links into other pages */
  siteLinks: string[];
  text: string;
  noindex: boolean;
}

const BANNED = banned.patterns.map((p) => new RegExp(p.source, p.flags));
const decode = (s: string) =>
  s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&nbsp;/g, " ");
const strip = (s: string) => decode(s.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();

/** The intro: the first real paragraph after the H1 (eyebrow labels above it and short meta lines like a university's type
 * and city below it are skipped). */
function intro(body: string): string {
  const paras = [...(body.split(/<\/h1>/i)[1] ?? body).matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].slice(0, 6).map((m) => strip(m[1]!));
  return paras.find((p) => p.length >= 40) ?? paras[0] ?? "";
}

/** Extracts what the checks need from server-rendered HTML (our own pages; no general HTML parser needed). */
export function extractFacts(path: string, html: string): PageFacts {
  const head = html.match(/<head[^>]*>([\s\S]*?)<\/head>/i)?.[1] ?? html;
  // Suspense content streams in hidden segments after the shell (`<div hidden id="S:0">…</div><script>$RC…`); crawlers
  // render it into <main>, so the checker counts it as page content too.
  const streamed = [...html.matchAll(/<div hidden id="S:\d+">([\s\S]*?)<\/div><script>/gi)].map((m) => m[1]).join("\n");
  const body = ((html.match(/<main[^>]*>([\s\S]*?)<\/main>/i)?.[1] ?? html) + streamed).replace(/<script[\s\S]*?<\/script>/gi, "").replace(/<style[\s\S]*?<\/style>/gi, "");
  const meta = (name: string) => decode(head.match(new RegExp(`<meta[^>]+name="${name}"[^>]+content="([^"]*)"`, "i"))?.[1] ?? "");
  const headings = [...body.matchAll(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi)].map((m) => ({ level: Number(m[1]), text: strip(m[2]!) }));
  const jsonLd = [...html.matchAll(/<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => {
    try {
      const j = JSON.parse(m[1]!) as { "@type"?: string | string[] } | { "@type"?: string }[];
      const list = Array.isArray(j) ? j : [j];
      return { ok: list.every((x) => !!x["@type"]), types: list.flatMap((x) => (Array.isArray(x["@type"]) ? x["@type"] : [x["@type"] ?? ""])) };
    } catch {
      return { ok: false, types: [] };
    }
  });
  const imgs = [...body.matchAll(/<img\b[^>]*>/gi)].map((m) => m[0]);
  const hrefs = (s: string) =>
    [...new Set([...s.matchAll(/<a\b[^>]*href="([^"]+)"/gi)].map((m) => decode(m[1]!)).filter((h) => h.startsWith("/") && !h.startsWith("//")).map((l) => l.split("#")[0]!).filter(Boolean))];
  return {
    path,
    title: strip(head.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? ""),
    description: meta("description"),
    h1: headings.filter((h) => h.level === 1).map((h) => h.text),
    headings,
    firstParagraph: intro(body),
    jsonLd,
    imagesWithoutAlt: imgs.filter((t) => !/\balt="/i.test(t)).length,
    internalLinks: hrefs(body),
    siteLinks: hrefs(html),
    text: strip(body),
    noindex: /noindex/i.test(meta("robots")),
  };
}

export interface CheckContext {
  /** titles and descriptions of the other checked pages (uniqueness) */
  otherTitles: string[];
  otherDescriptions: string[];
  /** how many checked pages link to this one */
  inboundLinks: number;
  /** internal links that returned 404 */
  brokenLinks: string[];
  expectFaqs: boolean;
}

const PENALTY: Record<Severity, number> = { error: 15, warn: 6, info: 0 };

export function checkPage(f: PageFacts, c: CheckContext): { score: number; issues: Issue[] } {
  const issues: Issue[] = [];
  const add = (rule: string, severity: Severity, message: string) => issues.push({ rule, severity, message });

  if (f.noindex) add("noindex", "error", "The page is noindex, so it cannot rank. Publish it or remove the override.");
  if (!f.title) add("title_missing", "error", "Add a title.");
  else if (f.title.length < 30 || f.title.length > 65) add("title_length", "warn", `Title is ${f.title.length} characters; aim for 30–65.`);
  if (f.title && c.otherTitles.includes(f.title)) add("title_duplicate", "error", "Another page has the same title.");
  if (!f.description) add("description_missing", "error", "Add a meta description.");
  else if (f.description.length < 70 || f.description.length > 160) add("description_length", "warn", `Description is ${f.description.length} characters; aim for 70–160.`);
  if (f.description && c.otherDescriptions.includes(f.description)) add("description_duplicate", "warn", "Another page has the same description.");
  if (f.h1.length !== 1) add("h1", "error", f.h1.length ? `There are ${f.h1.length} H1 headings; keep one.` : "Add one H1.");
  for (let i = 1; i < f.headings.length; i++) {
    if (f.headings[i]!.level > f.headings[i - 1]!.level + 1) {
      add("heading_order", "warn", `Heading “${f.headings[i]!.text.slice(0, 40)}” skips a level (h${f.headings[i - 1]!.level} → h${f.headings[i]!.level}).`);
      break;
    }
  }
  if (f.firstParagraph.length < 120) add("intro_short", "warn", "The intro is shorter than 120 characters; explain who the page is for and what it compares.");
  if (c.expectFaqs && !f.jsonLd.some((j) => j.types.includes("FAQPage"))) add("faqs_missing", "warn", "Add 3–6 FAQs (they also become FAQPage structured data).");
  if (!f.jsonLd.length) add("schema_missing", "warn", "No structured data found.");
  if (f.jsonLd.some((j) => !j.ok)) add("schema_invalid", "error", "A structured-data block does not parse or lacks @type.");
  if (f.imagesWithoutAlt) add("image_alt", "warn", `${f.imagesWithoutAlt} image(s) without alt text.`);
  if (f.internalLinks.length < 3) add("links_out", "warn", "Fewer than 3 internal links out; link to related views, universities or guides.");
  if (c.inboundLinks === 0) add("links_in", "warn", "No other checked page links here; add it to a hub, footer or related block.");
  if (c.brokenLinks.length) add("broken_links", "error", `Broken internal links: ${c.brokenLinks.slice(0, 5).join(", ")}.`);
  const claim = BANNED.find((re) => re.test(f.text));
  if (claim) add("banned_claim", "error", `Remove the claim matching ${claim}: approvals and outcomes come only from the catalogue.`);

  const score = Math.max(0, 100 - issues.reduce((n, i) => n + PENALTY[i.severity], 0));
  return { score, issues };
}
