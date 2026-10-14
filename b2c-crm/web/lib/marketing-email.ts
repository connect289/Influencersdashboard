import { escapeHtml } from "@/lib/compose";
import { encodeLink } from "@/lib/tokens";

/**
 * A marketing email as sent (spec B9.2, B9.6): every link tracked through a signed redirect, an "I'm interested, call me"
 * link (a click re-engages the lead), the unsubscribe footer, the one-click List-Unsubscribe header and an open pixel.
 * Pure; unit-tested in marketing-email.test.ts.
 */
export function marketingEmail(m: { emailId: number; leadId: number; text: string; site: string; key?: string }) {
  const site = m.site.replace(/\/$/, "");
  const click = (url: string, link: "interested" | "brochure" | "other") => `${site}/e/c/${encodeLink({ kind: "click", email: m.emailId, link, url }, m.key)}`;
  const unsub = `${site}/u/${encodeLink({ kind: "unsubscribe", lead: m.leadId, channel: "email" }, m.key)}`;
  const oneClick = `${site}/e/u/${encodeLink({ kind: "unsubscribe", lead: m.leadId, channel: "email" }, m.key)}`;
  const interested = click(`${site}/thanks`, "interested");
  const pixel = `${site}/e/o/${encodeLink({ kind: "open", email: m.emailId }, m.key)}`;

  const paras = m.text.replace(/\r\n?/g, "\n").trim().split(/\n{2,}/).map((p) =>
    escapeHtml(p).replace(/https:\/\/[^\s<]+/g, (u) => {
      const raw = u.replace(/&amp;/g, "&");
      return `<a href="${escapeHtml(click(raw, /brochure|\.pdf($|\?)/i.test(raw) ? "brochure" : "other"))}">${u}</a>`;
    }).replace(/\n/g, "<br>"));
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1f2937">`
    + paras.map((p) => `<p style="margin:0 0 12px">${p}</p>`).join("")
    + `<p style="margin:16px 0"><a href="${escapeHtml(interested)}" style="background:#072E5A;color:#ffffff;padding:10px 16px;border-radius:6px;text-decoration:none;display:inline-block">I'm interested, call me</a></p>`
    + `<p style="margin:24px 0 0;font-size:12px;color:#6b7280">You get this because you asked Eduwit about online programmes. <a href="${escapeHtml(unsub)}" style="color:#6b7280">Unsubscribe</a>.</p>`
    + `<img src="${escapeHtml(pixel)}" width="1" height="1" alt="" style="display:block;border:0">`
    + `</div>`;
  const text = `${m.text.trim()}\n\nI'm interested, call me: ${interested}\n\n--\nYou get this because you asked Eduwit about online programmes. Unsubscribe: ${unsub}`;
  return {
    html, text,
    headers: { "List-Unsubscribe": `<${oneClick}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click", "X-B2C-Email-Id": String(m.emailId) },
  };
}
