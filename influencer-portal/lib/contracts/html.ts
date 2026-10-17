// Contract content → HTML. Every string is escaped; only our own tags are emitted. The HTML of a version is what its
// SHA-256 hash covers ("the exact rendered document", spec 8.4).
import type { Block, Inline } from "./doc";
import type { ContractContent } from "./assemble";

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function inlineHtml(content: readonly Inline[] | undefined): string {
  return (content ?? [])
    .map((i) => {
      if (i.type === "hardBreak") return "<br>";
      let s = escapeHtml(i.text);
      for (const m of i.marks ?? [])
        s =
          m.type === "bold"
            ? `<strong>${s}</strong>`
            : m.type === "italic"
              ? `<em>${s}</em>`
              : `<u>${s}</u>`;
      return s;
    })
    .join("");
}

export function blocksHtml(blocks: readonly Block[]): string {
  return blocks
    .map((b) => {
      switch (b.type) {
        case "paragraph":
          return `<p>${inlineHtml(b.content)}</p>`;
        case "heading":
          return `<h${String(b.attrs.level)}>${inlineHtml(b.content)}</h${String(b.attrs.level)}>`;
        case "bulletList":
        case "orderedList": {
          const tag = b.type === "bulletList" ? "ul" : "ol";
          return `<${tag}>${b.content.map((li) => `<li>${blocksHtml(li.content)}</li>`).join("")}</${tag}>`;
        }
        case "table":
          return `<table><thead><tr>${b.head.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${b.rows
            .map((r) => `<tr>${r.map((c) => `<td>${escapeHtml(c)}</td>`).join("")}</tr>`)
            .join("")}</tbody></table>`;
      }
    })
    .join("");
}

export function contractHtml(c: ContractContent): string {
  const sections = c.sections
    .map(
      (s) =>
        `<section id="clause-${escapeHtml(s.key)}" data-clause="${escapeHtml(s.key)}"><h2>${String(s.number)}. ${escapeHtml(s.title)}</h2>${blocksHtml(s.blocks)}</section>`,
    )
    .join("");
  return `<article><h1>${escapeHtml(c.title)}</h1>${blocksHtml(c.header)}${sections}${blocksHtml(c.footer)}</article>`;
}
