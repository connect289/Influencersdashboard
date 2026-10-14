/**
 * Text helpers for messages a counsellor writes (email composer, programme sharing). Pure, unit-tested in compose.test.ts.
 */

export type Vars = { first_name?: string | null; programme?: string | null; university?: string | null; counsellor?: string | null };

/** Fills {{first_name}}, {{programme}}, {{university}} and {{counsellor}}; an unknown or empty placeholder becomes "". */
export function fill(text: string, v: Vars): string {
  return text.replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_, k: string) => {
    const val = (v as Record<string, string | null | undefined>)[k];
    return val ? String(val) : "";
  });
}

/** Placeholders still in the text (the counsellor sees them before sending). */
export function unfilled(text: string): string[] {
  return [...new Set([...text.matchAll(/\{\{\s*([a-z_]+)\s*\}\}/g)].map((m) => m[1]!))];
}

export function firstName(name: string | null | undefined): string | null {
  const f = (name ?? "").trim().split(/\s+/)[0];
  return f ? f[0]!.toUpperCase() + f.slice(1) : null;
}

const ESC: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ESC[c]!);

/** Plain text to safe HTML: paragraphs on blank lines, line breaks kept, https links clickable. Nothing else passes. */
export function textToHtml(text: string): string {
  const paras = text.replace(/\r\n?/g, "\n").trim().split(/\n{2,}/);
  const body = paras
    .map((p) => escapeHtml(p).replace(/https:\/\/[^\s<]+/g, (u) => `<a href="${u}">${u}</a>`).replace(/\n/g, "<br>"))
    .map((p) => `<p style="margin:0 0 12px">${p}</p>`)
    .join("");
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1f2937">${body}</div>`;
}

export type SharedProgramme = { name: string; university: string; fee_total?: number | null; fee_yearly?: number | null; mode?: string | null; brochure_url?: string | null; eligibility?: string | null };

const rupees = (n: number) => "₹" + Math.round(n).toLocaleString("en-IN");

/** The message that shares 1–3 programmes, on WhatsApp or by email. */
export function shareText(ps: SharedProgramme[], name: string | null, counsellor: string | null): string {
  const hi = name ? `Hi ${name},` : "Hi,";
  const lines = ps.map((p, i) => {
    const fee = p.fee_total ? `${rupees(p.fee_total)} in total` : p.fee_yearly ? `${rupees(p.fee_yearly)} a year` : null;
    const bits = [p.mode, fee].filter(Boolean).join(", ");
    return [`${ps.length > 1 ? `${i + 1}. ` : ""}${p.name}, ${p.university}${bits ? ` (${bits})` : ""}`,
            p.eligibility ? `   Eligibility: ${p.eligibility}` : null,
            p.brochure_url && /^https:\/\//.test(p.brochure_url) ? `   Brochure: ${p.brochure_url}` : null].filter(Boolean).join("\n");
  });
  const intro = ps.length > 1 ? "Here are the programmes we discussed, side by side:" : "Here are the details of the programme we discussed:";
  return `${hi}\n\n${intro}\n\n${lines.join("\n\n")}\n\nReply here with any question.${counsellor ? `\n\n${counsellor}, Eduwit` : ""}`;
}
