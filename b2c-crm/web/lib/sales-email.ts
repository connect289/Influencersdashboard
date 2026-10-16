import { escapeHtml, textToHtml } from "@/lib/compose";
import { encodeLink } from "@/lib/tokens";

/**
 * A counsellor's one-to-one email as sent (spec B8.6, C4): every https link in the HTML part goes through the signed
 * click redirect (/e/c/<token>, the mechanism marketing email uses), so a click is recorded on the email and scored. No
 * open pixel and no footer: it is personal mail. The plain-text part keeps the real links. Pure; sales-email.test.ts.
 */
export function trackLinks(html: string, emailId: number, site: string, key?: string): string {
  const base = site.replace(/\/+$/, "");
  return html.replace(/href=(["'])(https:\/\/[^"']+)\1/gi, (whole, q: string, href: string) => {
    const url = href.replace(/&amp;/g, "&").replace(/&#39;/g, "'").replace(/&quot;/g, '"');
    if (url.startsWith(base + "/e/") || url.startsWith(base + "/u/")) return whole; // already a tracked or unsubscribe link
    const kind = /brochure|\.pdf($|[?#])/i.test(url) ? "brochure" : "other";
    return `href=${q}${escapeHtml(`${base}/e/c/${encodeLink({ kind: "click", email: emailId, link: kind, url }, key)}`)}${q}`;
  });
}

export function salesEmail(m: { emailId: number; text: string; html: string | null; site: string; key?: string }): { text: string; html: string } {
  const html = m.html && m.html.trim() ? m.html : textToHtml(m.text);
  return { text: m.text, html: trackLinks(html, m.emailId, m.site, m.key) };
}
