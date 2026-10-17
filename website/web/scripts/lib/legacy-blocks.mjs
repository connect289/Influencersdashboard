// Pure helpers for importing the crawled site (scripts/crawl-legacy-site.mjs output) verbatim. Tested in
// scripts/lib/legacy-blocks.test.ts.

/** Converts crawled blocks ({tag, text}) after the page's H1 into stored content blocks; consecutive <li> → one list. */
export function toContentBlocks(blocks) {
  const out = [];
  let started = false;
  for (const b of blocks) {
    const tag = (b.tag || "").toLowerCase();
    const text = (b.text || "").replace(/\s+/g, " ").trim();
    if (!text) continue;
    if (tag === "h1") {
      started = true;
      continue;
    }
    if (!started) continue;
    if (/^(nav|footer|header)/.test(b.section || "")) continue;
    if (tag === "h2") out.push({ type: "h2", text });
    else if (tag === "h3" || tag === "h4") out.push({ type: "h3", text });
    else if (tag === "li") {
      const last = out[out.length - 1];
      if (last && last.type === "ul") last.items.push(text);
      else out.push({ type: "ul", items: [text] });
    } else out.push({ type: "p", text });
  }
  return out;
}

/** SQL string literal. */
export function lit(v) {
  return v === null || v === undefined ? "null" : `'${String(v).replace(/'/g, "''")}'`;
}

export const LEGAL_SLUGS = ["terms-and-conditions", "privacy-policy", "disclaimer", "refund-policy", "cookie-policy", "data-privacy-opt-out"];
