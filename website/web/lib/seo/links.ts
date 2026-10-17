/**
 * Internal linking engine (spec 13.4): suggests links from guides to curated finder views and university pages when a
 * guide mentions them, skipping links it already has. Editors approve each suggestion before it shows. Pure.
 */
export interface LinkTarget {
  path: string;
  /** phrases that identify the target, most specific first (e.g. "online MBA", "MBA") */
  terms: string[];
}
export interface Suggestion {
  from_slug: string;
  to_path: string;
  anchor: string;
  reason: string;
}

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export function suggestLinks(resources: { slug: string; text: string; links: string[] }[], targets: LinkTarget[], maxPerResource = 5): Suggestion[] {
  const out: Suggestion[] = [];
  for (const r of resources) {
    const own = `/resources/${r.slug}`;
    let n = 0;
    for (const t of targets) {
      if (n >= maxPerResource) break;
      if (t.path === own || r.links.includes(t.path)) continue;
      for (const term of t.terms) {
        if (term.length < 3) continue;
        const m = r.text.match(new RegExp(`(?<![\\w-])${esc(term)}(?![\\w-])`, "i"));
        if (m) {
          out.push({ from_slug: r.slug, to_path: t.path, anchor: m[0], reason: `mentions “${term}”` });
          n++;
          break;
        }
      }
    }
  }
  return out;
}
