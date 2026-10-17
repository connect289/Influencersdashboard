// Notification templates (spec 14 "template editor with variables, preview and test send"): {{variable}}
// placeholders, checked against the event's allowed variables when saved, escaped for HTML when rendered. Plain text
// bodies turn blank-line paragraphs into HTML paragraphs. Pure.
import { allowedVars } from "./catalogue";
import { escapeHtml } from "./templates";

const VAR_RE = /\{\{\s*([a-z_][a-z0-9_]*)\s*\}\}/gi;

/** Variable names used in a template, in order of first use. */
export function templateVars(tpl: string): string[] {
  const out: string[] = [];
  for (const m of tpl.matchAll(VAR_RE)) {
    const name = (m[1] ?? "").toLowerCase();
    if (!out.includes(name)) out.push(name);
  }
  return out;
}

/** Variables a template uses that the event does not provide (empty means the template is valid). */
export function unknownVars(event: string, ...parts: (string | null | undefined)[]): string[] {
  const allowed = allowedVars(event);
  return [...new Set(parts.flatMap((p) => templateVars(p ?? "")))].filter((v) => !allowed.includes(v));
}

export interface Rendered {
  text: string;
  /** Variables the template used that had no value (rendered empty). */
  missing: string[];
}

export function renderText(tpl: string, vars: Readonly<Record<string, string | null | undefined>>): Rendered {
  const missing: string[] = [];
  const text = tpl.replace(VAR_RE, (_, raw: string) => {
    const v = vars[raw.toLowerCase()];
    if (v === undefined || v === null || v === "") {
      if (!missing.includes(raw.toLowerCase())) missing.push(raw.toLowerCase());
      return "";
    }
    return v;
  });
  return { text, missing };
}

/** HTML body: values are escaped, paragraphs split on blank lines, single newlines become line breaks. */
export function renderHtml(tpl: string, vars: Readonly<Record<string, string | null | undefined>>): Rendered {
  const escaped = Object.fromEntries(
    Object.entries(vars).map(([k, v]) => [k, v === null || v === undefined ? v : escapeHtml(v)]),
  );
  const r = renderText(escapeHtml(tpl).replace(/\{\{\s*([a-z_][a-z0-9_]*)\s*\}\}/gi, "{{$1}}"), escaped);
  const html = r.text
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => `<p>${p.replace(/\n/g, "<br>")}</p>`)
    .join("");
  return { text: html, missing: r.missing };
}

/** WhatsApp template parameters: one variable per line of the template body, in order. */
export function whatsappParams(tpl: string, vars: Readonly<Record<string, string | null | undefined>>): string[] {
  return tpl
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => renderText(l, vars).text.slice(0, 1000) || "-");
}
